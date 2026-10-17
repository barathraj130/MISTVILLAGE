"""
Water bodies for the city tiles (design: tools/ponds.py, previews/ponds/): the real OSM tanks, ponds and lakes, their
water level, the ground carved under them, and godot/assets/city/water.bin for scripts/city/city_water.gd.

Styles
    0 kuttai    village pond / tank: mud banks, reeds, lotus, hyacinth, egrets
    1 walkway   a restored city lake (Ukkadam, Valankulam, Kurichi): stone-pitched bund, paved walkway with railings
                and lamps on top
    2 temple    a theppakulam: granite steps down on all four sides, a mandapam in the middle

Levels: the water stands a little below the lower shore (15th percentile of the ground round the outline), so the
shore is dry all round; a walkway bund is raised to `bund`, a temple tank's rim (`bund`) is the ground round it.

water.bin (little-endian):
    b"CWAT"  i32 n
    per body:  u8 style  f32 level  f32 bund  f32 cx cz angle sx sz (the outline's smallest rotated rectangle)
               u16 npts  f32[2n] x,z (outer ring, game frame)  f32[n] ground 6 m out from each point (the bank)
               u16 len  utf-8 name
"""
import math
import struct

import numpy as np
import shapely
import shapely.geometry.polygon
from shapely.geometry import Polygon

KINDS = {"pond", "lake", "reservoir", "water", "intermittent", "intermittent,_rock_pool"}
WALKWAY = {"Ukkadam Lake", "Valaan Kulam", "Kurichi Kulam"}
BUND = 2.4                     # walkway bund above the water
SLOPE = 5.0                    # stone pitching from the water up to the walkway
WALK = 9.0                     # the walkway band behind it
STEPS = 3.6                    # temple tank: rim above the water (12 steps of 0.3 m)


def style_of(name, poly):
    if name in WALKWAY:
        return 1
    rect = poly.minimum_rotated_rectangle
    fill = poly.area / max(rect.area, 1e-6)
    if "temple" in (name or "").lower() or (300 < poly.area < 8000 and fill > 0.88):
        return 2
    return 0


def load(wa, game, height):
    """wa: the OSM water layer (GeoDataFrame, metric CRS); game: UTM → game frame; height(x, z): DEM ground."""
    bodies = []
    for kind, name, g in zip(wa["kind"], wa["name"], wa.geometry):
        if kind not in KINDS or g is None:
            continue
        name = name if isinstance(name, str) else ""
        parts = g.geoms if g.geom_type == "MultiPolygon" else [g] if g.geom_type == "Polygon" else []
        for p in parts:
            if p.area < 200:
                continue
            p = game(Polygon(p.exterior)).simplify(1.5, preserve_topology=True).buffer(0)
            if p.geom_type == "MultiPolygon":
                p = max(p.geoms, key=lambda q: q.area)
            if p.is_empty or not p.is_valid or p.area < 200:
                continue
            p = shapely.geometry.polygon.orient(Polygon(p.exterior), 1.0)
            ring = p.exterior
            n = max(8, int(ring.length / 4))
            pts = np.array([ring.interpolate(i / n, normalized=True).coords[0] for i in range(n)])
            gnd = np.asarray(height(pts[:, 0], pts[:, 1]), dtype=float)
            st = style_of(name, p)
            if st == 2:
                bund = float(np.median(gnd))
                level = bund - STEPS
            else:
                # the satellite heights over open water are the water surface itself (noisy): their median inside
                # the outline, a little lowered, and never above the lower part of the shore
                minx, minz, maxx, maxz = p.bounds
                step = max(6.0, math.sqrt(p.area) / 25.0)
                gx, gz = np.meshgrid(np.arange(minx, maxx, step), np.arange(minz, maxz, step))
                inn = shapely.contains_xy(p, gx.ravel(), gz.ravel())
                if inn.sum() >= 4:
                    surf = float(np.median(height(gx.ravel()[inn], gz.ravel()[inn])))
                else:
                    surf = float(np.median(gnd))
                level = min(surf - 0.4, float(np.percentile(gnd, 25)) - 0.2)
                bund = level + BUND if st == 1 else level
            # the bank 6 m out from every outline point (where the game's shore strip meets the ground)
            co = np.asarray(p.exterior.coords)[:-1]
            nb = len(co)
            outn = np.zeros((nb, 2))
            for i in range(nb):
                t = co[(i + 1) % nb] - co[i - 1]
                nrm = np.array([t[1], -t[0]]) / max(np.hypot(*t), 1e-6)
                if p.contains(shapely.Point(*(co[i] + nrm * 0.5))):
                    nrm = -nrm
                outn[i] = nrm
            q = co + outn * 6.0
            nat = np.asarray(height(q[:, 0], q[:, 1]), dtype=float)
            bank = np.clip(nat, level + 0.66, level + 0.4 + 0.35 * 6.0) if st == 0 else np.full(nb, bund)
            rect = p.minimum_rotated_rectangle
            rc = np.asarray(rect.exterior.coords)[:4]
            e1, e2 = rc[1] - rc[0], rc[2] - rc[1]
            c = rc.mean(axis=0)
            bodies.append({"poly": p, "style": st, "level": level, "bund": bund, "name": name, "bank": bank.astype(np.float32),
                           "rect": (float(c[0]), float(c[1]), math.atan2(e1[1], e1[0]),
                                    float(np.hypot(*e1)), float(np.hypot(*e2)))})
    return bodies


def reach(b):
    return SLOPE + WALK + 14.0 if b["style"] == 1 else (6.0 if b["style"] == 2 else 10.0)


def carve(H, X, Z, bodies):
    """Lower the ground under the water and shape the shore, in place. H, X, Z: the tile's grid (HN x HN).
    Returns the mask of grid points under water (for causeway roads)."""
    wet = np.zeros(H.shape, dtype=bool)
    xs, zs = X.ravel(), Z.ravel()
    for b in bodies:
        p = b["poly"]
        inside = shapely.contains_xy(p, xs, zs).reshape(H.shape)
        d = shapely.distance(p.exterior, shapely.points(xs, zs)).reshape(H.shape)
        d = np.where(inside, -d, d)
        L, B = b["level"], b["bund"]
        if b["style"] == 2:
            # the whole stepped tank (its rectangle) goes down, a 3 m apron round it stays at the rim
            cx, cz, ang, sx, sz = b["rect"]
            ca, sa = math.cos(ang), math.sin(ang)
            lu = (xs - cx) * ca + (zs - cz) * sa
            lv = -(xs - cx) * sa + (zs - cz) * ca
            ex = np.maximum(np.abs(lu) - sx / 2, np.abs(lv) - sz / 2).reshape(H.shape)
            H[:] = np.where(ex < 0.0, np.minimum(H, L - 1.5), H)
            H[:] = np.where((ex >= 0.0) & (ex < 5.0), B - 0.05, H)
            continue                                   # no causeways through a temple tank
        else:
            if b["style"] == 1:
                depth = np.clip(1.5 + 0.2 * (-d), 1.5, 3.0)
            else:
                depth = np.clip(0.5 + 0.2 * (-d), 0.5, 2.2)
            H[:] = np.where(inside, np.minimum(H, L - depth), H)
            if b["style"] == 1:
                top = B - 0.05
                # under the stone pitching (drawn by the game) the ground stays low — 1.5 m under the water — so
                # that, between the 8 m grid points, it never rises through the stone slope
                bank = np.where(d < SLOPE + 1.0, L - 1.5, top)
                f = np.clip((d - SLOPE - WALK) / 14.0, 0, 1)
                bank = bank * (1 - f) + H * f
                H[:] = np.where((~inside) & (d < SLOPE + WALK + 14.0), bank, H)
            else:
                # a gentle bank: dry above the water, never steeper than 1 in 3 for 20 m (no cliffs at the edge)
                H[:] = np.where((~inside) & (d < 20.0), np.minimum(H, L + 0.4 + 0.35 * d), H)
                H[:] = np.where((~inside) & (d < 8.0), np.maximum(H, L + 0.12 + 0.09 * d), H)
        wet |= inside
    return wet


def tile_keys(bodies, tile):
    """Every tile a water body or its shore reaches (they all need ground, even with nothing else in them)."""
    keys = set()
    for b in bodies:
        x0, z0, x1, z1 = b["poly"].buffer(reach(b) + 20).bounds
        for cx in range(int(math.floor(x0 / tile)), int(math.floor(x1 / tile)) + 1):
            for cz in range(int(math.floor(z0 / tile)), int(math.floor(z1 / tile)) + 1):
                keys.add((cx, cz))
    return keys


def write(path, bodies):
    buf = bytearray(b"CWAT")
    buf += struct.pack("<i", len(bodies))
    for b in bodies:
        c = np.asarray(b["poly"].exterior.coords)[:-1]
        nm = b["name"].encode("utf-8")[:200]
        buf += struct.pack("<Bff5fH", b["style"], b["level"], b["bund"], *b["rect"], len(c))
        buf += c.astype("<f4").tobytes()
        buf += b["bank"].astype("<f4").tobytes()
        buf += struct.pack("<H", len(nm)) + nm
    with open(path, "wb") as f:
        f.write(bytes(buf))
    return len(buf)
