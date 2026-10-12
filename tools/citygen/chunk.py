"""
Stage 13 — cut the classified city into streaming tiles for Godot (docs/CBE_MAP_PIPELINE.md §13).

Reads build/cbe/cache/roads.gpkg (UTM 43N) and the SRTM tile, writes godot/assets/city/:

    index.json          tile size, origin, the list of tiles (with road counts) and the city bounds
    chunks/CBE_c_r.json one 256 m tile: its ground heights (33 × 33 points, 8 m apart) and every road piece
                        whose segments lie in it: class, width, oneway, bridge, layer, src and points [x, y, z, …]

Game frame: x = E − E0, z = −(N − N0) (metres, origin Gandhipuram), y = SRTM elevation in metres.
Roads are densified to ≤ 6 m so they follow the ground; their heights are smoothed along the road. A road
crossing a tile edge is split there, sharing the edge point, so the pieces join without a gap.
SRTM tile N11E076 ends at 11.0° N: the few southern kilometres below it are clamped to its edge row until the
N10E076 tile is added (flagged in index.json).
"""
import gzip
import json
import math
import os
import sys
import time

import geopandas as gpd
import numpy as np
from pyproj import Transformer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import build_dir, load, path  # noqa: E402

TILE = 256.0
HSTEP = 8.0
HN = int(TILE / HSTEP) + 1


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


def run(cfg):
    t0 = time.time()
    out = path("godot", "assets", "city")
    os.makedirs(os.path.join(out, "chunks"), exist_ok=True)
    roads = gpd.read_file(os.path.join(build_dir(cfg), "cache", "roads.gpkg"))
    to_utm = Transformer.from_crs("EPSG:4326", cfg["crs"], always_xy=True)
    to_ll = Transformer.from_crs(cfg["crs"], "EPSG:4326", always_xy=True)
    e0, n0 = to_utm.transform(cfg["origin"]["lon"], cfg["origin"]["lat"])
    dem = Dem()

    def height(x, z):
        lon, lat = to_ll.transform(np.asarray(x) + e0, -np.asarray(z) + n0)
        return dem.sample(lat, lon)

    tiles = {}

    def tile(key):
        if key not in tiles:
            tiles[key] = {"roads": []}
        return tiles[key]

    n_pieces = 0
    for row in roads.itertuples():
        g = row.geometry
        lines = list(g.geoms) if g.geom_type == "MultiLineString" else [g]
        for line in lines:
            c = np.asarray(line.coords)
            # game frame, densified to ≤ 6 m
            xs = c[:, 0] - e0
            zs = -(c[:, 1] - n0)
            px, pz = [xs[0]], [zs[0]]
            for i in range(1, len(xs)):
                d = math.hypot(xs[i] - xs[i - 1], zs[i] - zs[i - 1])
                k = max(1, int(math.ceil(d / 6.0)))
                for j in range(1, k + 1):
                    px.append(xs[i - 1] + (xs[i] - xs[i - 1]) * j / k)
                    pz.append(zs[i - 1] + (zs[i] - zs[i - 1]) * j / k)
            px = np.array(px)
            pz = np.array(pz)
            py = height(px, pz)
            if len(py) >= 5:                                    # smooth bumps along the road
                kern = np.ones(5) / 5.0
                sm = np.convolve(np.pad(py, 2, mode="edge"), kern, mode="valid")
                py = sm
            bridge = bool(getattr(row, "bridge_b", False))
            layer = int(getattr(row, "layer_n", 0) or 0)
            attrs = {"c": row.cls, "w": round(float(row.width_m), 1), "o": bool(row.oneway_b), "b": bridge,
                     "l": layer, "n": (row.name if isinstance(getattr(row, "name", None), str) else "")[:40], "src": row.src}
            # split into per-tile runs (segment → tile of its midpoint), sharing edge points
            keys = [(int(math.floor((px[i] + px[i + 1]) * 0.5 / TILE)), int(math.floor((pz[i] + pz[i + 1]) * 0.5 / TILE)))
                    for i in range(len(px) - 1)]
            start = 0
            for i in range(1, len(keys) + 1):
                if i == len(keys) or keys[i] != keys[start]:
                    sl = slice(start, i + 1)
                    pts = np.column_stack([px[sl], py[sl], pz[sl]]).round(2).ravel().tolist()
                    piece = dict(attrs)
                    piece["p"] = pts
                    tile(keys[start])["roads"].append(piece)
                    n_pieces += 1
                    start = i
    # ground heights per tile
    for (cx, cz), t in tiles.items():
        gx = cx * TILE + np.arange(HN) * HSTEP
        gz = cz * TILE + np.arange(HN) * HSTEP
        X, Z = np.meshgrid(gx, gz)
        H = height(X.ravel(), Z.ravel()).reshape(HN, HN)
        # keep the ground just under every road in this tile (and a margin beside it), so it never pokes through
        for piece in t["roads"]:
            p = np.asarray(piece["p"]).reshape(-1, 3)
            reach = piece["w"] * 0.5 + 3.0
            for x, y, z in p:
                i0 = int(max(0, math.floor((z - cz * TILE - reach) / HSTEP)))
                i1 = int(min(HN - 1, math.ceil((z - cz * TILE + reach) / HSTEP)))
                j0 = int(max(0, math.floor((x - cx * TILE - reach) / HSTEP)))
                j1 = int(min(HN - 1, math.ceil((x - cx * TILE + reach) / HSTEP)))
                if i1 < i0 or j1 < j0:
                    continue
                sub = H[i0:i1 + 1, j0:j1 + 1]
                np.minimum(sub, y - 0.3, out=sub)
        t["h"] = np.round(H.ravel(), 1).tolist()
    index = {"tile": TILE, "hstep": HSTEP, "hn": HN, "origin": cfg["origin"], "crs": cfg["crs"],
             "tiles": {}, "bounds": None, "dem_clamped_south": dem.clamped > 0}
    xs_all = []
    for (cx, cz), t in tiles.items():
        name = "CBE_%d_%d" % (cx, cz)
        with open(os.path.join(out, "chunks", name + ".json"), "w") as f:
            json.dump({"id": name, "cx": cx, "cz": cz, "h": t["h"], "roads": t["roads"]}, f, separators=(",", ":"))
        index["tiles"]["%d,%d" % (cx, cz)] = {"roads": len(t["roads"])}
        xs_all.append((cx, cz))
    a = np.array(xs_all)
    index["bounds"] = [int(a[:, 0].min()), int(a[:, 1].min()), int(a[:, 0].max()), int(a[:, 1].max())]
    with open(os.path.join(out, "index.json"), "w") as f:
        json.dump(index, f, separators=(",", ":"))
    size = sum(os.path.getsize(os.path.join(out, "chunks", n)) for n in os.listdir(os.path.join(out, "chunks")))
    print("CHUNK %d tiles, %d road pieces, %.1f MB, %ds (south DEM clamped: %s)" % (
        len(tiles), n_pieces, size / 1e6, time.time() - t0, index["dem_clamped_south"]))


if __name__ == "__main__":
    run(load("city.yaml"))
