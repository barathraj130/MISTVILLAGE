"""
Stage 13 — cut the classified city into binary streaming tiles for Godot (docs/CBE_MAP_PIPELINE.md §13).

Reads build/cbe/cache/roads.gpkg + osm.gpkg (buildings), the SRTM tile and the designed-building manifest
(godot/assets/buildings/manifest.json); writes godot/assets/city/:

    index.json          tile size, origin, class list, variant list, tiles (counts), bounds, flags
    chunks/CBE_c_r.bin  one 256 m tile (little-endian), read by scripts/city/city_streamer.gd:
        b"CBE5"  i32 cx  i32 cz  i32 hn  f32[hn*hn] ground heights (8 m grid, row = z)
        i32 nroads   per road:  u8 class  u8 flags(1 oneway, 2 bridge)  u16 npts  f32 width  f32 a0  f32 len
                                f32 clear0  f32 clear1  f32[3*npts] x,y,z
                     (a0 = metres along the whole OSM way where this piece starts, len = the way's length, so
                     dashes run on across tiles; clear0/1 = how far the junction surface reaches into the way at
                     its start/end (0 = no junction there): the paint stops and a zebra is drawn just outside it)
        i32 nblds    per building:
                     u8 floors  u8 flags(1 shop, 2 generated-height, 4 generated infill — not in OSM)  u8 r  u8 g  u8 b  u8 rnd  u16 nverts
                     f32 base  i32 variant(-1 = none)  f32[7] ox oy oz  fx fz  sx sz   f32[2*nverts] x,z
        i32 nwalks   per footpath strip:  u8 flags(1 painted kerb, 2 streetlights, 4 road on the right)  u8 class
                     u16 npts  f32 width  f32[3*npts] x,y,z (centre of the footpath, its top surface)
        i32 njunc    per junction surface: u16 nverts  f32[3*nverts] x,y,z (a triangle list; the crossing with
                     filleted corners, laid over the road ends that meet there)
        i32 nprops   per prop: u8 type(1 traffic signal, 2 bus shelter, 3 speed breaker)  f32 x y z  f32 yaw  f32 size
        i32 nyards   per record: u8 kind  u16 nverts  f32[3*nverts] x,y,z
                     kind 1 paver forecourt, 2 concrete yard, 6 footpath corner at a junction (triangle lists);
                     101 / 102 / 106 the outline of the record before it (an edge skirt down into the ground);
                     3 compound wall 1.5 m, 5 mill wall 2.4 m (polylines along the top of the footing);
                     4 tree (one point: where it stands)

Everything heavy happens here, once: roads densified to ≤ 6 m following smoothed ground; ground lowered
under roads; building footprints cut back from the (generous) road + footpath corridors so nothing stands in
the street; storeys from tags or rules (flagged); and, for near-rectangular footprints by a street, the
designed building that fits — its kind, size, facing (towards the street) and scale (0.6–1.6).
"""
import gzip
import json
import math
import os
import struct
import sys
import time
import zlib

import geopandas as gpd
import numpy as np
import shapely
import shapely.ops
from pyproj import Transformer
from shapely.geometry import Point
from shapely.strtree import STRtree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import build_dir, load, path  # noqa: E402

TILE = 256.0
HSTEP = 8.0
HN = int(TILE / HSTEP) + 1
FOOTPATH = 1.8                     # kept clear beside every road for the footpath
KERB = 0.2
WALK = 1.8                         # footpath width beside the kerb (fits inside the cleared corridor)
MEDIAN = 1.0                       # kerbed median strip on the inner side of a divided road's carriageway
NO_WALK = {"footway", "track"}
LIFT = {"trunk": 0.07, "primary": 0.06, "secondary": 0.05, "tertiary": 0.04, "unclassified": 0.03, "residential": 0.025,
        "living_street": 0.02, "service": 0.015, "track": 0.01, "footway": 0.035}   # = city_streamer.gd RANK


class Dem:
    def __init__(self):
        with gzip.open(path("mapdata", "N11E076.hgt.gz")) as f:
            raw = f.read()
        self.n = int(math.sqrt(len(raw) // 2))
        d = np.frombuffer(raw, dtype=">i2").reshape(self.n, self.n).astype(np.float32)
        d[d < -1000] = np.nan
        self.d = np.where(np.isnan(d), np.nanmean(d), d)
        self.clamped = 0

    def sample(self, lat, lon):
        lat = np.asarray(lat, dtype=np.float64)
        lon = np.asarray(lon, dtype=np.float64)
        fy = (12.0 - lat) * (self.n - 1)
        fx = (lon - 76.0) * (self.n - 1)
        self.clamped += int((fy > self.n - 1.001).sum())
        fy = np.clip(fy, 0, self.n - 1.001)
        fx = np.clip(fx, 0, self.n - 1.001)
        x0 = fx.astype(int)
        y0 = fy.astype(int)
        tx = fx - x0
        ty = fy - y0
        a = self.d[y0, x0]
        b = self.d[y0, x0 + 1]
        c = self.d[y0 + 1, x0]
        e = self.d[y0 + 1, x0 + 1]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + e * tx) * ty


# ----------------------------------------------------------------------------- designed buildings
class Kit:
    def __init__(self):
        mp = path("godot", "assets", "buildings", "manifest.json")
        self.m = json.load(open(mp)) if os.path.exists(mp) else {}
        self.names = sorted(self.m)
        self.by_kind = {}
        for n in self.names:
            self.by_kind.setdefault(self.m[n]["kind"], []).append(n)

    def extent(self, n):
        """centre (x, z) and size (x across the front, z deep) in Godot space"""
        mn, mx = self.m[n]["min"], self.m[n]["max"]
        return ((mn[0] + mx[0]) * 0.5, -(mn[1] + mx[1]) * 0.5), (mx[0] - mn[0], mx[1] - mn[1])

    def pick(self, kind, floors, w, d, seed=0):
        """a design of this kind that fits: one of the three closest, chosen by seed, so rows don't repeat"""
        scored = []
        for n in self.by_kind.get(kind, []):
            _, (bw, bd) = self.extent(n)
            scored.append((abs(math.log(w / bw)) + abs(math.log(d / bd)) + abs(self.m[n]["floors"] - floors) * 0.6, n))
        if not scored:
            return None
        scored.sort()
        top = [n for s, n in scored[:3] if s < scored[0][0] + 0.8]
        return top[seed % len(top)]


def run(cfg, roads_cfg):
    t0 = time.time()
    out = path("godot", "assets", "city")
    # write into chunks.tmp and swap at the end: the game never sees a half-written city
    tmp = os.path.join(out, "chunks.tmp")
    os.makedirs(tmp, exist_ok=True)
    for f in os.listdir(tmp):
        os.remove(os.path.join(tmp, f))
    bdir = build_dir(cfg)
    classes = list(roads_cfg["classes"].keys())
    roads = gpd.read_file(os.path.join(bdir, "cache", "roads.gpkg"))
    to_utm = Transformer.from_crs("EPSG:4326", cfg["crs"], always_xy=True)
    to_ll = Transformer.from_crs(cfg["crs"], "EPSG:4326", always_xy=True)
    e0, n0 = to_utm.transform(cfg["origin"]["lon"], cfg["origin"]["lat"])
    dem = Dem()
    kit = Kit()

    def height(x, z):
        lon, lat = to_ll.transform(np.asarray(x) + e0, -np.asarray(z) + n0)
        return dem.sample(lat, lon)

    def game(geom):
        """UTM geometry → game frame (x = E − E0, z = −(N − N0))"""
        return shapely.transform(geom, lambda c: np.column_stack([c[:, 0] - e0, -(c[:, 1] - n0)]))

    tiles = {}

    def tile(key):
        if key not in tiles:
            tiles[key] = {"roads": [], "blds": [], "walks": [], "junc": [], "props": [], "yards": []}
        return tiles[key]

    # ---- roads ---------------------------------------------------------------------------------------
    road_geoms, road_w, road_cls = [], [], []
    road_lines = []                                  # (2D line, 3D line with height as z, width, class)
    road_oneway = []                                 # per road_lines entry: one carriageway of a divided road
    n_pieces = 0
    for row in roads.itertuples():
        g = game(row.geometry)
        road_geoms.append(g)
        road_w.append(float(row.width_m))
        road_cls.append(row.cls)
        lines = list(g.geoms) if g.geom_type == "MultiLineString" else [g]
        for line in lines:
            c = np.asarray(line.coords)
            px, pz = [c[0, 0]], [c[0, 1]]
            for i in range(1, len(c)):
                d = math.hypot(c[i, 0] - c[i - 1, 0], c[i, 1] - c[i - 1, 1])
                k = max(1, int(math.ceil(d / 6.0)))
                for j in range(1, k + 1):
                    px.append(c[i - 1, 0] + (c[i, 0] - c[i - 1, 0]) * j / k)
                    pz.append(c[i - 1, 1] + (c[i, 1] - c[i - 1, 1]) * j / k)
            px, pz = np.array(px), np.array(pz)
            py = height(px, pz)
            if len(py) >= 5:
                py = np.convolve(np.pad(py, 2, mode="edge"), np.ones(5) / 5.0, mode="valid")
            seg = np.hypot(np.diff(px), np.diff(pz))
            cum = np.concatenate([[0.0], np.cumsum(seg)])
            total = float(cum[-1])
            wi = -1
            if len(px) >= 2 and total > 1.0:
                wi = len(road_lines)
                road_oneway.append(bool(row.oneway_b))
                road_lines.append((shapely.LineString(np.column_stack([px, pz])),
                                   shapely.LineString(np.column_stack([px, pz, py])), float(row.width_m), row.cls))
            flags = (1 if row.oneway_b else 0) | (2 if row.bridge_b else 0)
            cid = classes.index(row.cls) if row.cls in classes else 0
            keys = [(int(math.floor((px[i] + px[i + 1]) * 0.5 / TILE)), int(math.floor((pz[i] + pz[i + 1]) * 0.5 / TILE)))
                    for i in range(len(px) - 1)]
            start = 0
            for i in range(1, len(keys) + 1):
                if i == len(keys) or keys[i] != keys[start]:
                    sl = slice(start, i + 1)
                    pts = np.column_stack([px[sl], py[sl], pz[sl]]).astype(np.float32)
                    tile(keys[start])["roads"].append([cid, flags, float(row.width_m), pts, float(cum[start]), total, wi])
                    n_pieces += 1
                    start = i
    print("  roads → %d pieces (%ds)" % (n_pieces, time.time() - t0), flush=True)

    # ---- buildings -----------------------------------------------------------------------------------
    corridors = shapely.buffer(np.array(road_geoms, dtype=object),
                               np.array(road_w) * 0.5 + FOOTPATH + 0.3, cap_style="flat")
    ctree = STRtree(corridors)
    line_tree = STRtree(np.array(road_geoms, dtype=object))
    main = {"trunk", "primary", "secondary"}
    b = gpd.read_file(os.path.join(bdir, "cache", "osm.gpkg"), layer="buildings").to_crs(cfg["crs"])
    c = cfg["boundary"]["circle"]
    area_circle = gpd.GeoSeries([Point(c["lon"], c["lat"])], crs="EPSG:4326").to_crs(cfg["crs"]).iloc[0].buffer(float(c["radius_m"]))
    b = b[b.intersects(area_circle)]
    print("  %d buildings to place (%ds)" % (len(b), time.time() - t0), flush=True)
    grid = {}                                   # 32 m cell → placed building rectangles (overlap checks)
    placed = []                                 # for yards and walls: (rect, kind, C, nx, nz, hx, hz, tile key)

    def cells(poly):
        x0, z0, x1, z1 = poly.bounds
        for i in range(int(math.floor(x0 / 32)), int(math.floor(x1 / 32)) + 1):
            for j in range(int(math.floor(z0 / 32)), int(math.floor(z1 / 32)) + 1):
                yield (i, j)

    def near_rects(poly):
        seen, ids = [], set()
        for c in cells(poly):
            for q in grid.get(c, ()):
                if id(q) not in ids:
                    ids.add(id(q))
                    seen.append(q)
        return seen

    def rect(C, nx, nz, hx, hz):
        return shapely.Polygon([C - nx * hx - nz * hz, C + nx * hx - nz * hz, C + nx * hx + nz * hz, C - nx * hx + nz * hz])
    n_moved = n_shrunk = 0
    n_in, n_cut, n_drop, n_kit = len(b), 0, 0, 0
    cols = [(0.86, 0.82, 0.74), (0.93, 0.9, 0.84), (0.82, 0.74, 0.62), (0.78, 0.8, 0.76), (0.88, 0.78, 0.7), (0.72, 0.78, 0.82)]
    for bi, row in enumerate(b.itertuples()):
        if bi % 20000 == 0 and bi:
            print("  ... %d buildings (%ds)" % (bi, time.time() - t0), flush=True)
        g = game(row.geometry)
        if not g.is_valid:
            g = g.buffer(0)
        if g.geom_type == "MultiPolygon":
            g = max(g.geoms, key=lambda q: q.area)
        a0 = g.area
        if g.geom_type != "Polygon" or a0 < 12.0 or a0 > 30000.0:
            n_drop += 1
            continue
        hits = ctree.query(g, predicate="intersects")
        if len(hits):
            g2 = g.difference(shapely.union_all(corridors[hits]))
            if g2.is_empty or g2.area < 0.55 * a0:
                n_drop += 1
                continue
            if g2.geom_type == "MultiPolygon":
                g2 = max(g2.geoms, key=lambda q: q.area)
            g2 = g2.simplify(0.15)
            if g2.geom_type != "Polygon" or g2.area < 12.0:
                n_drop += 1
                continue
            g = g2
            n_cut += 1
        ext = np.asarray(g.exterior.coords)[:-1]
        if len(ext) < 3 or len(ext) > 4000:
            continue
        seed = zlib.crc32(row.src.encode())
        shop = bool(isinstance(row.shop, str) and row.shop) or bool(isinstance(row.amenity, str) and row.amenity)
        near = line_tree.query(g.centroid, predicate="dwithin", distance=30.0)
        on_main = any(road_cls[i] in main for i in near)
        try:
            floors = int(float(row.levels))
            gen_h = False
        except (TypeError, ValueError):
            lo, hi = (2, 4) if (shop or on_main) else (1, 3)
            floors = lo + seed % (hi - lo + 1)
            gen_h = True
        floors = max(1, min(floors, 12))
        base = float(height(ext[:, 0], ext[:, 1]).min()) - 0.3
        rnd = (seed >> 8) % 1000 / 1000.0
        col = cols[seed % len(cols)]
        # every footprint gets a designed building, faced towards its nearest street: shop rows on the main
        # roads, Tamil Nadu houses (now and then a corner shop) on every other street, mills on big plots
        variant, kd = -1, [0.0] * 7
        if kit.names:
            rr = g.minimum_rotated_rectangle
            rc = np.asarray(rr.exterior.coords)[:4] if rr.geom_type == "Polygon" else None
            if rc is not None and len(rc) == 4:
                e1, e2 = rc[1] - rc[0], rc[2] - rc[1]
                l1, l2 = np.linalg.norm(e1), np.linalg.norm(e2)
                fill = math.sqrt(min(1.0, g.area / max(rr.area, 1e-6)))        # L- and odd shapes: shrink to fit
                if min(l1, l2) > 0.5:
                    C = np.asarray(g.representative_point().coords[0]) if fill < 0.8 else rc.mean(axis=0)
                    ni = line_tree.nearest(Point(C))
                    sp = shapely.ops.nearest_points(road_geoms[ni], Point(C))[0]
                    ds = np.array([sp.x - C[0], sp.y - C[1]])
                    ds /= max(np.linalg.norm(ds), 1e-6)
                    u, v = e1 / l1, e2 / l2
                    cands = [(u, l1, l2), (-u, l1, l2), (v, l2, l1), (-v, l2, l1)]
                    face, depth, front = max(cands, key=lambda q: float(np.dot(q[0], ds)))
                    front, depth = front * fill, depth * fill
                    main_front = on_main and float(np.linalg.norm(np.array([sp.x, sp.y]) - C)) < 30.0
                    big = max(front, depth) > 40.0 or front * depth > 1300.0
                    r = seed % 100
                    if big and not main_front:
                        # big plots: some mills and godowns, more shopping complexes and flats
                        kind = "mill_shed" if r < 30 else ("apartment" if floors >= 3 and r < 65 else "commercial")
                    elif main_front or shop:
                        kind = "commercial" if front >= 12.5 else "shop_house"
                    elif floors >= 4 and front * depth > 220:
                        kind = "hotel" if r < 8 and front * depth > 280 else "apartment"
                    elif r < 8:
                        kind = "shop_house"                                    # corner shops in the lanes
                    elif r < 18:
                        kind = "city_house"
                    elif r < 24 and floors <= 1 and front * depth > 110:
                        kind = "bungalow"
                    else:
                        kind = "tn_house"
                    name = kit.pick(kind, floors, front, depth, seed >> 3) or kit.pick("city_house", floors, front, depth)
                    if name:
                        (ecx, ecz), (bw, bd) = kit.extent(name)
                        sx = min(max(front / bw, 0.55), 1.8)
                        sz = min(max(depth / bd, 0.55), 1.8)
                        nz = np.array([face[0], face[1]])
                        nx = np.array([nz[1], -nz[0]])
                        # never on a street or footpath, never inside a neighbour: step back, then shrink
                        for attempt in range(7):
                            R = rect(C, nx, nz, bw * sx / 2, bd * sz / 2)
                            on_road = any(R.intersection(corridors[h]).area > 0.3 for h in ctree.query(R, predicate="intersects"))
                            on_bld = any(R.intersection(q).area > 0.12 * min(R.area, q.area) for q in near_rects(R) if R.intersects(q))
                            if not on_road and not on_bld:
                                break
                            if on_road and attempt < 3:
                                C = C - nz * 1.2
                                n_moved += 1
                            else:
                                sx, sz = max(sx * 0.85, 0.35), max(sz * 0.85, 0.35)
                                n_shrunk += 1
                        R = rect(C, nx, nz, bw * sx / 2, bd * sz / 2)
                        for cc in cells(R):
                            grid.setdefault(cc, []).append(R)
                        # origin = C − basis·(ecx, 0, ecz); basis columns nx·sx, up, nz·sz
                        ox = C[0] - (nx[0] * sx * ecx + nz[0] * sz * ecz)
                        oz = C[1] - (nx[1] * sx * ecx + nz[1] * sz * ecz)
                        variant = kit.names.index(name)
                        kd = [ox, base + 0.3, oz, nz[0], nz[1], sx, sz]
                        n_kit += 1
                        placed.append((R, kind, C, nx, nz, bw * sx / 2, bd * sz / 2))
        cxz = ext.mean(axis=0)
        key = (int(math.floor(cxz[0] / TILE)), int(math.floor(cxz[1] / TILE)))
        tile(key)["blds"].append((floors, (1 if shop else 0) | (2 if gen_h else 0), col, base, variant, kd,
                                  ext.astype(np.float32), rnd))
    print("  buildings: %d in area, %d trimmed back from roads, %d dropped, %d designed, %d steps back, %d shrinks (%ds)" % (
        n_in, n_cut, n_drop, n_kit, n_moved, n_shrunk, time.time() - t0), flush=True)

    # ---- infill: OSM misses many real buildings, so empty frontage in built-up streets gets designed ones -----
    # (only where real buildings stand nearby, never on water, parks, fields or rail land; flagged generated: 2 | 4)
    OPEN = {"grass", "farmland", "meadow", "forest", "park", "cemetery", "recreation_ground", "railway", "orchard",
            "scrub", "wetland", "village_green", "military", "quarry", "garden", "pitch", "golf_course", "nature_reserve"}
    lu = gpd.read_file(os.path.join(bdir, "cache", "osm.gpkg"), layer="landuse").to_crs(cfg["crs"])
    wa = gpd.read_file(os.path.join(bdir, "cache", "osm.gpkg"), layer="water").to_crs(cfg["crs"])
    opens = [game(g) for k, g in zip(lu["kind"], lu.geometry) if k in OPEN and g is not None and g.geom_type in ("Polygon", "MultiPolygon")]
    opens += [game(g) for g in wa.geometry if g is not None and g.geom_type in ("Polygon", "MultiPolygon")]
    otree = STRtree(opens) if opens else None
    real = STRtree([q[0] for q in placed]) if placed else None
    n_fill = 0
    for ri, (l2, l3, w, cls) in enumerate(road_lines):
        if cls in NO_WALK or cls in ("service", "motorway") or l2.length < 20.0 or real is None:
            continue
        if len(real.query(l2.buffer(120.0), predicate="intersects")) < 4:
            continue                                                   # countryside: leave it open
        mainr = cls in main
        L = l2.length
        for side in (1.0, -1.0):
            t = 5.0
            while t < L - 5.0:
                h = zlib.crc32(b"%d_%d_%d" % (ri, int(side), int(t)))
                front = 7.0 + (h % 60) / 10.0
                depth = 9.0 + ((h >> 8) % 60) / 10.0
                a = np.asarray(l2.interpolate(t).coords[0])
                b2 = np.asarray(l2.interpolate(min(L, t + 1.0)).coords[0])
                d = (b2 - a) / max(np.linalg.norm(b2 - a), 1e-6)
                nrm = np.array([-d[1], d[0]]) * side
                C = a + d * (front / 2) + nrm * (w * 0.5 + KERB + WALK + 0.8 + depth / 2)
                nz = -nrm
                nx = np.array([nz[1], -nz[0]])
                R = rect(C, nx, nz, front / 2 + 0.6, depth / 2 + 0.6)       # with a little space round it
                bad = any(R.intersects(corridors[q]) for q in ctree.query(R, predicate="intersects"))
                bad = bad or any(R.intersects(q) for q in near_rects(R))
                bad = bad or (otree is not None and len(otree.query(R, predicate="intersects")) > 0)
                if bad or len(real.query(Point(C), predicate="dwithin", distance=150.0)) < 3:
                    t += 4.0
                    continue
                floors = (2 + h % 3) if mainr else (1 + (h >> 4) % 3)
                r = h % 100
                if mainr:
                    kind = "commercial" if front >= 12.5 or r < 30 else ("apartment" if r < 45 else ("city_house" if r < 60 else "shop_house"))
                else:
                    kind = "shop_house" if r < 8 else ("city_house" if r < 22 else "tn_house")
                name = kit.pick(kind, floors, front, depth, h >> 5)
                if not name:
                    t += 4.0
                    continue
                (ecx, ecz), (bw, bd) = kit.extent(name)
                sx = min(max(front / bw, 0.55), 1.8)
                sz = min(max(depth / bd, 0.55), 1.8)
                R = rect(C, nx, nz, bw * sx / 2, bd * sz / 2)
                if any(R.intersects(corridors[q]) for q in ctree.query(R, predicate="intersects")) or \
                        any(R.intersects(q) for q in near_rects(R)):
                    t += 4.0
                    continue
                ext = np.asarray(R.exterior.coords)[:-1]
                base = float(height(ext[:, 0], ext[:, 1]).min()) - 0.3
                ox = C[0] - (nx[0] * sx * ecx + nz[0] * sz * ecz)
                oz = C[1] - (nx[1] * sx * ecx + nz[1] * sz * ecz)
                kd = [ox, base + 0.3, oz, nz[0], nz[1], sx, sz]
                for cc in cells(R):
                    grid.setdefault(cc, []).append(R)
                placed.append((R, kind, C, nx, nz, bw * sx / 2, bd * sz / 2))
                key = (int(math.floor(C[0] / TILE)), int(math.floor(C[1] / TILE)))
                tile(key)["blds"].append((floors, 2 | 4, cols[h % len(cols)], base, kit.names.index(name), kd,
                                          ext.astype(np.float32), (h % 1000) / 1000.0))
                n_fill += 1
                t += bw * sx + 1.5
    print("  infill → %d generated buildings on empty frontage (%ds)" % (n_fill, time.time() - t0), flush=True)

    # ---- footpaths: a kerbed strip each side of every street, stopping at the kerb of any road it meets ----
    lines2 = np.array([q[0] for q in road_lines], dtype=object)
    carriage = shapely.buffer(lines2, np.array([q[2] for q in road_lines]) * 0.5 + KERB + WALK * 0.5 + 0.05, cap_style="flat")
    walkzone = shapely.buffer(lines2, np.array([q[2] for q in road_lines]) * 0.5 + KERB + WALK, cap_style="flat")
    wtree = STRtree(walkzone)

    def surface(ri, x, z):
        """top of the road ribbon at (x, z) on road ri (city_streamer.gd lifts each class a little)"""
        l2, l3, w, cls = road_lines[ri]
        return l3.interpolate(l2.project(Point(x, z))).z + LIFT.get(cls, 0.02) + 0.06
    ctree2 = STRtree(carriage)
    n_walk = 0
    for ri, (l2, l3, w, cls) in enumerate(road_lines):
        if cls in NO_WALK:
            continue
        mainr = cls in main
        for s in (1.0, -1.0):
            # one carriageway of a divided road: footpath on the driver's left (the kerb side, s < 0),
            # a narrow kerbed median strip on its right
            median = road_oneway[ri] and s > 0
            ww = MEDIAN if median else WALK
            off = shapely.offset_curve(l2, s * (w * 0.5 + KERB + ww * 0.5), join_style="mitre", mitre_limit=2.0)
            if off.is_empty:
                continue
            hits = [h for h in ctree2.query(off, predicate="intersects") if h != ri]
            if hits:
                off = off.difference(shapely.union_all(carriage[hits]))
            parts = list(off.geoms) if hasattr(off, "geoms") else [off]
            for part in parts:
                if part.geom_type != "LineString" or part.length < 3.0:
                    continue
                part = shapely.segmentize(part, 6.0)
                c = np.asarray(part.coords)
                ry = np.array([surface(ri, x, z) for x, z in c])
                gy = height(c[:, 0], c[:, 1])
                y = np.clip(np.maximum(ry + 0.15, gy + 0.05), ry + 0.15, ry + 0.55) + 0.004 * (ri % 5)
                pts = np.column_stack([c[:, 0], y, c[:, 1]]).astype(np.float32)
                # offset_curve keeps the line's direction: a left (+) offset has the road on its right
                fl = (1 if mainr else 0) | (2 if mainr or cls == "tertiary" else 0) | (4 if s > 0 else 0)
                cid = classes.index(cls) if cls in classes else 0
                keys = [(int(math.floor((pts[i, 0] + pts[i + 1, 0]) * 0.5 / TILE)), int(math.floor((pts[i, 2] + pts[i + 1, 2]) * 0.5 / TILE)))
                        for i in range(len(pts) - 1)]
                st = 0
                for i in range(1, len(keys) + 1):
                    if i == len(keys) or keys[i] != keys[st]:
                        tile(keys[st])["walks"].append((fl, cid, ww, pts[st:i + 1]))
                        n_walk += 1
                        st = i
    print("  footpaths → %d strips (%ds)" % (n_walk, time.time() - t0), flush=True)

    def put_poly(kind, poly, yfun):
        """a paved area as a triangle list (kind) and its outline (kind + 100) for the edge skirt"""
        try:
            tris = shapely.constrained_delaunay_triangles(poly)
        except Exception:
            return
        verts = []
        for tri in tris.geoms:
            for x, z in list(tri.exterior.coords)[:3]:
                verts.append((x, yfun(x, z), z))
        if not verts:
            return
        v = np.asarray(verts, dtype=np.float32)
        ring = np.asarray([(x, yfun(x, z), z) for x, z in poly.exterior.coords], dtype=np.float32)
        cxz = v[:, [0, 2]].mean(axis=0)
        key = (int(math.floor(cxz[0] / TILE)), int(math.floor(cxz[1] / TILE)))
        tile(key)["yards"].append((kind, v))
        tile(key)["yards"].append((kind + 100, ring))

    # ---- junctions: where two or more streets share a node --------------------------------------------
    from collections import defaultdict
    deg, ways = defaultdict(int), defaultdict(set)
    for ri, (l2, l3, w, cls) in enumerate(road_lines):
        if cls in NO_WALK:
            continue
        c = np.asarray(l2.coords)
        for i, (x, z) in enumerate(c):
            k = (round(x, 2), round(z, 2))
            deg[k] += 1 if i in (0, len(c) - 1) else 2
            ways[k].add(ri)
    clear = defaultdict(lambda: [0.0, 0.0])
    patches = []
    pads = []
    for k, ws in ways.items():
        if len(ws) < 2 or deg[k] < 3:
            continue
        J = Point(k)
        ws = list(ws)
        polys = []
        for ri in ws:
            l2, l3, w, cls = road_lines[ri]
            other = max(road_lines[o][2] for o in ws if o != ri) * 0.5
            arm = max(3.0, other + 2.5)
            t = l2.project(J)
            L = l2.length
            if t < 0.5:
                clear[ri][0] = max(clear[ri][0], arm)
            elif t > L - 0.5:
                clear[ri][1] = max(clear[ri][1], arm)
            sub = shapely.ops.substring(l2, max(0.0, t - arm), min(L, t + arm))
            if sub.length > 0.1:
                polys.append(sub.buffer(w * 0.5, cap_style="flat"))
        if polys:
            u = shapely.union_all(polys).buffer(2.5, join_style="round").buffer(-2.5, join_style="round")
            patches.append((u, ws))
            # the footpath round each corner: the band beside the kerbs, near the crossing, off the carriageways
            band, inner = [], []
            for ri in ws:
                l2, l3, w, cls = road_lines[ri]
                t = l2.project(J)
                sub = shapely.ops.substring(l2, max(0.0, t - 14.0), min(l2.length, t + 14.0))
                if sub.length > 0.1:
                    band.append(sub.buffer(w * 0.5 + KERB + WALK, cap_style="flat"))
                    inner.append(sub.buffer(w * 0.5 + KERB, cap_style="flat"))
            reach = max(road_lines[ri][2] for ri in ws) * 0.5 + KERB + WALK + 1.5
            pad = shapely.union_all(band).difference(shapely.union_all(inner)).difference(u).intersection(J.buffer(reach))
            pads.append((pad, ws))
    merged = shapely.union_all([p for p, _ in patches]) if patches else None
    n_junc = 0
    if merged is not None:
        lines_tree = STRtree(lines2)
        for comp in (merged.geoms if hasattr(merged, "geoms") else [merged]):
            if comp.geom_type != "Polygon" or comp.area < 4.0:
                continue
            comp = comp.simplify(0.08)
            tris = shapely.constrained_delaunay_triangles(comp)
            verts = []
            for tri in tris.geoms:
                for x, z in list(tri.exterior.coords)[:3]:
                    hits = [h for h in lines_tree.query(Point(x, z), predicate="dwithin", distance=12.0)
                            if road_lines[h][3] not in NO_WALK]
                    if not hits:
                        hits = [int(lines_tree.nearest(Point(x, z)))]
                    hits.sort(key=lambda h: road_lines[h][0].distance(Point(x, z)))
                    y = max(surface(h, x, z) for h in hits[:3]) + 0.015       # over every ribbon meeting here
                    verts.append((x, y, z))
            if not verts:
                continue
            v = np.asarray(verts, dtype=np.float32)
            cxz = v[:, [0, 2]].mean(axis=0)
            key = (int(math.floor(cxz[0] / TILE)), int(math.floor(cxz[1] / TILE)))
            tile(key)["junc"].append(v)
            n_junc += 1
    n_pad = 0
    for pad, ws in pads:
        for comp in (pad.geoms if hasattr(pad, "geoms") else [pad]):
            if comp.geom_type != "Polygon" or comp.area < 0.5:
                continue
            comp = comp.simplify(0.05)
            ref = ws[0]
            put_poly(6, comp, lambda x, z: max(surface(h, x, z) for h in ws) + 0.165)
            n_pad += 1
    print("  junctions → %d surfaces, %d footpath corners (%ds)" % (n_junc, n_pad, time.time() - t0), flush=True)

    # ---- props: traffic signals and bus shelters from OSM, speed breakers on the longer side streets ----
    pois = gpd.read_file(os.path.join(bdir, "cache", "osm.gpkg"), layer="pois").to_crs(cfg["crs"])
    lines_tree = STRtree(lines2)
    n_props = 0

    def drive_left(d):                     # the driver's left in the game frame (x east, z south)
        return np.array([d[1], -d[0]])

    def put_prop(kind, x, y, z, yaw, size):
        key = (int(math.floor(x / TILE)), int(math.floor(z / TILE)))
        tile(key)["props"].append((kind, x, y, z, yaw, size))

    for row in pois.itertuples():
        hw = row.highway if isinstance(row.highway, str) else ""
        if hw not in ("traffic_signals", "bus_stop"):
            continue
        g = game(row.geometry)
        P = Point(g.x, g.y)
        if hw == "traffic_signals":
            near = [h for h in lines_tree.query(P, predicate="dwithin", distance=3.0) if road_lines[h][3] not in NO_WALK]
            if not near:
                continue
            reach = max(road_lines[h][2] for h in near) * 0.5 + 2.5
            for h in near:
                l2, l3, w, cls = road_lines[h]
                t = l2.project(P)
                for sgn in (-1.0, 1.0):                         # one signal for each approach
                    ta = t + sgn * (reach + 1.5)
                    if ta < 0 or ta > l2.length:
                        continue
                    a = np.asarray(l2.interpolate(ta).coords[0])
                    b = np.asarray(l2.interpolate(min(l2.length, max(0.0, ta - sgn * 1.0))).coords[0])
                    d = (a - b) / max(np.linalg.norm(a - b), 1e-6)      # direction of the traffic coming in
                    if sgn < 0:
                        d = -d
                    d = -d if sgn > 0 else d
                    # traffic heads towards P: from the far side of the approach towards the junction
                    to_j = np.asarray(P.coords[0]) - a
                    d = to_j / max(np.linalg.norm(to_j), 1e-6)
                    q = a + drive_left(d) * (w * 0.5 + 0.6)
                    if any(h2 != h and carriage[h2].contains(Point(q[0], q[1])) for h2 in ctree2.query(Point(q[0], q[1]))):
                        continue
                    y = surface(h, a[0], a[1]) + 0.15
                    f = -d                                              # the lights face the oncoming driver
                    put_prop(1, q[0], y, q[1], math.atan2(f[0], f[1]), w)
                    n_props += 1
        else:
            h = int(lines_tree.nearest(P))
            l2, l3, w, cls = road_lines[h]
            if cls in NO_WALK or l2.distance(P) > 25.0:
                continue
            t = l2.project(P)
            c = np.asarray(l2.interpolate(t).coords[0])
            c2 = np.asarray(l2.interpolate(min(l2.length, t + 1.0)).coords[0])
            d = (c2 - c) / max(np.linalg.norm(c2 - c), 1e-6)
            side = np.array([P.x, P.y]) - c
            n = drive_left(d)
            sgn = 1.0 if float(np.dot(side, n)) >= 0 else -1.0
            q = c + n * sgn * (w * 0.5 + KERB + WALK * 0.5)
            if any(h2 != h and carriage[h2].contains(Point(q[0], q[1])) for h2 in ctree2.query(Point(q[0], q[1]))):
                continue
            y = surface(h, c[0], c[1]) + 0.15
            f = -n * sgn                                                # open side faces the road
            put_prop(2, q[0], y, q[1], math.atan2(f[0], f[1]), 4.0)
            n_props += 1
    jkeys = [Point(k) for k, ws in ways.items() if len(ws) >= 2 and deg[k] >= 3]
    jtree = STRtree(jkeys)
    for ri, (l2, l3, w, cls) in enumerate(road_lines):
        if cls in ("residential", "unclassified", "tertiary") and l2.length > 110.0 and ri % 3 == 0:
            t = l2.length * (0.35 + 0.3 * ((ri * 7919) % 100) / 100.0)
            c0, c1 = clear[ri] if ri in clear else (0.0, 0.0)
            if t < c0 + 18.0 or t > l2.length - c1 - 18.0:
                continue
            if len(jtree.query(l2.interpolate(t), predicate="dwithin", distance=18.0)):
                continue
            c = np.asarray(l2.interpolate(t).coords[0])
            c2 = np.asarray(l2.interpolate(min(l2.length, t + 1.0)).coords[0])
            d = (c2 - c) / max(np.linalg.norm(c2 - c), 1e-6)
            y = l3.interpolate(t).z + LIFT.get(cls, 0.02) + 0.06
            put_prop(3, c[0], y, c[1], math.atan2(d[0], d[1]), w)
            n_props += 1
    print("  props → %d (signals, bus shelters, speed breakers) (%ds)" % (n_props, time.time() - t0), flush=True)

    # ---- yards: paving in front of every building, compound walls round houses and mills, trees ----------
    n_yard = n_wall = n_tree = 0
    ytrees = []
    HOUSES = {"tn_house", "city_house", "bungalow", "hill_cottage"}
    gy = lambda x, z: float(height(np.array([x]), np.array([z]))[0])   # noqa: E731
    for (R, kind, C, nx, nz, hx, hz) in placed:
        F = C + nz * hz
        hits = wtree.query(Point(F), predicate="dwithin", distance=30.0)
        if not len(hits):
            continue
        h = min(hits, key=lambda q: road_lines[q][0].distance(Point(F)))
        gap = road_lines[h][0].distance(Point(F)) - (road_lines[h][2] * 0.5 + KERB + WALK)
        house = kind in HOUSES or kind == "mill_shed"
        side = (3.0 if kind == "mill_shed" else 1.0) if house else 0.0
        if 0.4 < gap < 25.0:
            yard = rect(C + nz * (hz + gap / 2 + 0.3), nx, nz, hx + side, gap / 2 + 0.3)
            for q in wtree.query(yard, predicate="intersects"):
                yard = yard.difference(walkzone[q])
            for q in near_rects(yard):
                if q is not R and yard.intersects(q):
                    yard = yard.difference(q)
            if not yard.is_empty:
                part = max(yard.geoms, key=lambda q: q.area) if hasattr(yard, "geoms") else yard
                if part.geom_type == "Polygon" and part.area > 2.0:
                    ytrees.append(part)
                    put_poly(2 if house else 1, part.simplify(0.05), lambda x, z: gy(x, z) + 0.06)
                    n_yard += 1
        if house and gap > 1.0:
            b_ = 3.0 if kind == "mill_shed" else 1.5
            gate = 6.0 if kind == "mill_shed" else 3.2
            fd = hz + gap - 0.15
            FL = C - nx * (hx + side) + nz * fd
            FR = C + nx * (hx + side) + nz * fd
            BL = C - nx * (hx + side) - nz * (hz + b_)
            BR = C + nx * (hx + side) - nz * (hz + b_)
            GL = C - nx * gate / 2 + nz * fd
            GR = C + nx * gate / 2 + nz * fd
            wall = shapely.LineString([GL, FL, BL, BR, FR, GR])
            for q in wtree.query(wall, predicate="intersects"):
                wall = wall.difference(walkzone[q])
            for q in near_rects(wall.buffer(0.5)):
                if q is not R and wall.intersects(q.buffer(0.3)):
                    wall = wall.difference(q.buffer(0.3))
            for part in (wall.geoms if hasattr(wall, "geoms") else [wall]):
                if part.geom_type == "LineString" and part.length > 1.0:
                    c = np.asarray(part.coords)
                    v = np.asarray([(x, gy(x, z), z) for x, z in c], dtype=np.float32)
                    key = (int(math.floor(c[:, 0].mean() / TILE)), int(math.floor(c[:, 1].mean() / TILE)))
                    tile(key)["yards"].append((5 if kind == "mill_shed" else 3, v))
                    n_wall += 1
    ytree = STRtree(ytrees) if ytrees else None
    rng = np.random.default_rng(11)
    for (cx, cz), t in list(tiles.items()):
        for i in range(26):
            for j in range(26):
                x = cx * TILE + (i + 0.15 + 0.7 * rng.random()) * 9.85
                z = cz * TILE + (j + 0.15 + 0.7 * rng.random()) * 9.85
                if rng.random() > 0.3:
                    continue
                P = Point(x, z)
                if len(wtree.query(P, predicate="dwithin", distance=1.2)):
                    continue
                if any(q.distance(P) < 2.0 for q in grid.get((int(math.floor(x / 32)), int(math.floor(z / 32))), ())):
                    continue
                if ytree is not None and len(ytree.query(P, predicate="dwithin", distance=0.8)):
                    continue
                t["yards"].append((4, np.asarray([(x, gy(x, z), z)], dtype=np.float32)))
                n_tree += 1
    print("  yards → %d paved, %d wall runs, %d trees (%ds)" % (n_yard, n_wall, n_tree, time.time() - t0), flush=True)

    # ---- ground, then write -------------------------------------------------------------------------
    for (cx, cz), t in tiles.items():
        gx = cx * TILE + np.arange(HN) * HSTEP
        gz = cz * TILE + np.arange(HN) * HSTEP
        X, Z = np.meshgrid(gx, gz)
        H = height(X.ravel(), Z.ravel()).reshape(HN, HN).astype(np.float32)
        for cid, fl, w, pts, a0, ln, wi in t["roads"]:
            reach = w * 0.5 + 3.0
            for x, y, z in pts:
                i0 = int(max(0, math.floor((z - cz * TILE - reach) / HSTEP)))
                i1 = int(min(HN - 1, math.ceil((z - cz * TILE + reach) / HSTEP)))
                j0 = int(max(0, math.floor((x - cx * TILE - reach) / HSTEP)))
                j1 = int(min(HN - 1, math.ceil((x - cx * TILE + reach) / HSTEP)))
                if i1 >= i0 and j1 >= j0:
                    sub = H[i0:i1 + 1, j0:j1 + 1]
                    np.minimum(sub, y - 0.3, out=sub)
        buf = bytearray(b"CBE5")
        buf += struct.pack("<iii", cx, cz, HN)
        buf += H.astype("<f4").tobytes()
        buf += struct.pack("<i", len(t["roads"]))
        for cid, fl, w, pts, a0, ln, wi in t["roads"]:
            c0, c1 = clear[wi] if wi >= 0 and wi in clear else (0.0, 0.0)
            buf += struct.pack("<BBHfffff", cid, fl, len(pts), w, a0, ln, c0, c1)
            buf += pts.astype("<f4").tobytes()
        buf += struct.pack("<i", len(t["blds"]))
        for floors, fl, col, base, variant, kd, ext, rnd in t["blds"]:
            buf += struct.pack("<BBBBBBHfi", floors, fl, int(col[0] * 255), int(col[1] * 255), int(col[2] * 255),
                               int(rnd * 255), len(ext), base, variant)
            buf += struct.pack("<7f", *kd)
            buf += ext.astype("<f4").tobytes()
        buf += struct.pack("<i", len(t["walks"]))
        for fl, cid, w, pts in t["walks"]:
            buf += struct.pack("<BBHf", fl, cid, len(pts), w)
            buf += pts.astype("<f4").tobytes()
        buf += struct.pack("<i", len(t["junc"]))
        for v in t["junc"]:
            buf += struct.pack("<H", len(v))
            buf += v.astype("<f4").tobytes()
        buf += struct.pack("<i", len(t["props"]))
        for kind, x, y, z, yaw, size in t["props"]:
            buf += struct.pack("<B5f", kind, x, y, z, yaw, size)
        buf += struct.pack("<i", len(t["yards"]))
        for kind, v in t["yards"]:
            buf += struct.pack("<BH", kind, len(v))
            buf += v.astype("<f4").tobytes()
        name = "CBE_%d_%d" % (cx, cz)
        with open(os.path.join(tmp, name + ".bin"), "wb") as f:
            f.write(bytes(buf))
        t["n"] = (len(t["roads"]), len(t["blds"]))
    keys = np.array(list(tiles.keys()))
    index = {"tile": TILE, "hstep": HSTEP, "hn": HN, "origin": cfg["origin"], "crs": cfg["crs"], "format": "CBE5",
             "classes": classes, "variants": kit.names,
             "tiles": {"%d,%d" % k: list(t["n"]) for k, t in tiles.items()},
             "bounds": [int(keys[:, 0].min()), int(keys[:, 1].min()), int(keys[:, 0].max()), int(keys[:, 1].max())],
             "dem_clamped_south": dem.clamped > 0}
    import shutil
    old = os.path.join(out, "chunks.old")
    if os.path.exists(old):
        shutil.rmtree(old)
    if os.path.exists(os.path.join(out, "chunks")):
        os.replace(os.path.join(out, "chunks"), old)
    os.replace(tmp, os.path.join(out, "chunks"))
    with open(os.path.join(out, "index.json"), "w") as f:
        json.dump(index, f, separators=(",", ":"))
    shutil.rmtree(old, ignore_errors=True)
    size = sum(os.path.getsize(os.path.join(out, "chunks", n)) for n in os.listdir(os.path.join(out, "chunks")))
    print("CHUNK %d tiles, %d road pieces, %d buildings (%d designed), %.1f MB, %ds" % (
        len(tiles), n_pieces, sum(len(t["blds"]) for t in tiles.values()), n_kit, size / 1e6, time.time() - t0))


if __name__ == "__main__":
    run(load("city.yaml"), load("roads.yaml"))
