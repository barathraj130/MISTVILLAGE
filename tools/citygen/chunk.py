"""
Stage 13 — cut the classified city into binary streaming tiles for Godot (docs/CBE_MAP_PIPELINE.md §13).

Reads build/cbe/cache/roads.gpkg + osm.gpkg (buildings), the SRTM tile and the designed-building manifest
(godot/assets/buildings/manifest.json); writes godot/assets/city/:

    index.json          tile size, origin, class list, variant list, tiles (counts), bounds, flags
    chunks/CBE_c_r.bin  one 256 m tile (little-endian), read by scripts/city/city_streamer.gd:
        b"CBE2"  i32 cx  i32 cz  i32 hn  f32[hn*hn] ground heights (8 m grid, row = z)
        i32 nroads   per road:  u8 class  u8 flags(1 oneway, 2 bridge)  u16 npts  f32 width  f32[3*npts] x,y,z
        i32 nblds    per building:
                     u8 floors  u8 flags(1 shop, 2 generated-height)  u8 r  u8 g  u8 b  u8 rnd  u16 nverts
                     f32 base  i32 variant(-1 = none)  f32[7] ox oy oz  fx fz  sx sz   f32[2*nverts] x,z

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

    def pick(self, kind, floors, w, d):
        best, bs = None, 1e9
        for n in self.by_kind.get(kind, []):
            _, (bw, bd) = self.extent(n)
            s = abs(math.log(w / bw)) + abs(math.log(d / bd)) + abs(self.m[n]["floors"] - floors) * 0.6
            if s < bs:
                best, bs = n, s
        return best


def run(cfg, roads_cfg):
    t0 = time.time()
    out = path("godot", "assets", "city")
    os.makedirs(os.path.join(out, "chunks"), exist_ok=True)
    for f in os.listdir(os.path.join(out, "chunks")):
        os.remove(os.path.join(out, "chunks", f))
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
            tiles[key] = {"roads": [], "blds": []}
        return tiles[key]

    # ---- roads ---------------------------------------------------------------------------------------
    road_geoms, road_w, road_cls = [], [], []
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
            flags = (1 if row.oneway_b else 0) | (2 if row.bridge_b else 0)
            cid = classes.index(row.cls) if row.cls in classes else 0
            keys = [(int(math.floor((px[i] + px[i + 1]) * 0.5 / TILE)), int(math.floor((pz[i] + pz[i + 1]) * 0.5 / TILE)))
                    for i in range(len(px) - 1)]
            start = 0
            for i in range(1, len(keys) + 1):
                if i == len(keys) or keys[i] != keys[start]:
                    sl = slice(start, i + 1)
                    pts = np.column_stack([px[sl], py[sl], pz[sl]]).astype(np.float32)
                    tile(keys[start])["roads"].append((cid, flags, float(row.width_m), pts))
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
        # a designed building where the footprint is a house-sized rectangle by a street
        variant, kd = -1, [0.0] * 7
        if kit.names:
            rr = g.minimum_rotated_rectangle
            if rr.geom_type == "Polygon" and g.area / max(rr.area, 1e-6) >= 0.72:
                rc = np.asarray(rr.exterior.coords)[:4]
                e1, e2 = rc[1] - rc[0], rc[2] - rc[1]
                l1, l2 = np.linalg.norm(e1), np.linalg.norm(e2)
                if min(l1, l2) >= 4.5 and max(l1, l2) <= 36.0:
                    C = rc.mean(axis=0)
                    ni = line_tree.nearest(Point(C))
                    sp = shapely.ops.nearest_points(road_geoms[ni], Point(C))[0]
                    ds = np.array([sp.x - C[0], sp.y - C[1]])
                    if np.linalg.norm(ds) <= 45.0:
                        ds /= max(np.linalg.norm(ds), 1e-6)
                        u, v = e1 / l1, e2 / l2
                        cands = [(u, l1, l2), (-u, l1, l2), (v, l2, l1), (-v, l2, l1)]
                        face, depth, front = max(cands, key=lambda q: float(np.dot(q[0], ds)))
                        if floors >= 4:
                            kind = "hotel" if front * depth > 280 and seed % 7 == 0 else "apartment"
                        elif shop:
                            kind = "shop_house"
                        elif floors <= 1:
                            kind = "bungalow"
                        else:
                            kind = "shop_house" if on_main else "city_house"
                        name = kit.pick(kind, floors, front, depth)
                        if name:
                            (ecx, ecz), (bw, bd) = kit.extent(name)
                            sx, sz = front / bw, depth / bd
                            if 0.6 <= sx <= 1.6 and 0.6 <= sz <= 1.6:
                                nz = np.array([face[0], face[1]])
                                nx = np.array([nz[1], -nz[0]])
                                # origin = C − basis·(ecx, 0, ecz); basis columns nx·sx, up, nz·sz
                                ox = C[0] - (nx[0] * sx * ecx + nz[0] * sz * ecz)
                                oz = C[1] - (nx[1] * sx * ecx + nz[1] * sz * ecz)
                                variant = kit.names.index(name)
                                kd = [ox, base + 0.3, oz, nz[0], nz[1], sx, sz]
                                n_kit += 1
        cxz = ext.mean(axis=0)
        key = (int(math.floor(cxz[0] / TILE)), int(math.floor(cxz[1] / TILE)))
        tile(key)["blds"].append((floors, (1 if shop else 0) | (2 if gen_h else 0), col, base, variant, kd,
                                  ext.astype(np.float32), rnd))
    print("  buildings: %d in area, %d trimmed back from roads, %d dropped, %d designed (%ds)" % (
        n_in, n_cut, n_drop, n_kit, time.time() - t0), flush=True)

    # ---- ground, then write -------------------------------------------------------------------------
    for (cx, cz), t in tiles.items():
        gx = cx * TILE + np.arange(HN) * HSTEP
        gz = cz * TILE + np.arange(HN) * HSTEP
        X, Z = np.meshgrid(gx, gz)
        H = height(X.ravel(), Z.ravel()).reshape(HN, HN).astype(np.float32)
        for cid, fl, w, pts in t["roads"]:
            reach = w * 0.5 + 3.0
            for x, y, z in pts:
                i0 = int(max(0, math.floor((z - cz * TILE - reach) / HSTEP)))
                i1 = int(min(HN - 1, math.ceil((z - cz * TILE + reach) / HSTEP)))
                j0 = int(max(0, math.floor((x - cx * TILE - reach) / HSTEP)))
                j1 = int(min(HN - 1, math.ceil((x - cx * TILE + reach) / HSTEP)))
                if i1 >= i0 and j1 >= j0:
                    sub = H[i0:i1 + 1, j0:j1 + 1]
                    np.minimum(sub, y - 0.3, out=sub)
        buf = bytearray(b"CBE2")
        buf += struct.pack("<iii", cx, cz, HN)
        buf += H.astype("<f4").tobytes()
        buf += struct.pack("<i", len(t["roads"]))
        for cid, fl, w, pts in t["roads"]:
            buf += struct.pack("<BBHf", cid, fl, len(pts), w)
            buf += pts.astype("<f4").tobytes()
        buf += struct.pack("<i", len(t["blds"]))
        for floors, fl, col, base, variant, kd, ext, rnd in t["blds"]:
            buf += struct.pack("<BBBBBBHfi", floors, fl, int(col[0] * 255), int(col[1] * 255), int(col[2] * 255),
                               int(rnd * 255), len(ext), base, variant)
            buf += struct.pack("<7f", *kd)
            buf += ext.astype("<f4").tobytes()
        name = "CBE_%d_%d" % (cx, cz)
        with open(os.path.join(out, "chunks", name + ".bin"), "wb") as f:
            f.write(bytes(buf))
        t["n"] = (len(t["roads"]), len(t["blds"]))
    keys = np.array(list(tiles.keys()))
    index = {"tile": TILE, "hstep": HSTEP, "hn": HN, "origin": cfg["origin"], "crs": cfg["crs"], "format": "CBE2",
             "classes": classes, "variants": kit.names,
             "tiles": {"%d,%d" % k: list(t["n"]) for k, t in tiles.items()},
             "bounds": [int(keys[:, 0].min()), int(keys[:, 1].min()), int(keys[:, 0].max()), int(keys[:, 1].max())],
             "dem_clamped_south": dem.clamped > 0}
    with open(os.path.join(out, "index.json"), "w") as f:
        json.dump(index, f, separators=(",", ":"))
    size = sum(os.path.getsize(os.path.join(out, "chunks", n)) for n in os.listdir(os.path.join(out, "chunks")))
    print("CHUNK %d tiles, %d road pieces, %d buildings (%d designed), %.1f MB, %ds" % (
        len(tiles), n_pieces, sum(len(t["blds"]) for t in tiles.values()), n_kit, size / 1e6, time.time() - t0))


if __name__ == "__main__":
    run(load("city.yaml"), load("roads.yaml"))
