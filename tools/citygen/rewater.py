"""
Re-shape the ground round the water without rebuilding the city: for every tile near a water body the ground is
sampled again from the DEM, lowered under the tile's own roads exactly as chunk.py does, carved for the water
(water.py) and written back over the tile's height block; water.bin is rewritten. Same result as a full chunk.py
run for the ground, in about a minute.

    .venv/bin/python tools/citygen/rewater.py
"""
import math
import os
import struct
import sys
import time

import geopandas as gpd
import numpy as np
import shapely
from pyproj import Transformer
from shapely.strtree import STRtree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import build_dir, load, path  # noqa: E402
import chunk as C  # noqa: E402
import water as WATER  # noqa: E402


def main():
    t0 = time.time()
    cfg = load("city.yaml")
    bdir = build_dir(cfg)
    out = path("godot", "assets", "city")
    to_utm = Transformer.from_crs("EPSG:4326", cfg["crs"], always_xy=True)
    to_ll = Transformer.from_crs(cfg["crs"], "EPSG:4326", always_xy=True)
    e0, n0 = to_utm.transform(cfg["origin"]["lon"], cfg["origin"]["lat"])
    dem = C.Dem()

    def height(x, z):
        lon, lat = to_ll.transform(np.asarray(x) + e0, -np.asarray(z) + n0)
        return dem.sample(lat, lon)

    def game(g):
        return shapely.transform(g, lambda c: np.column_stack([c[:, 0] - e0, -(c[:, 1] - n0)]))

    wa = gpd.read_file(os.path.join(bdir, "cache", "osm.gpkg"), layer="water").to_crs(cfg["crs"])
    bodies = WATER.load(wa, game, height)
    btree = STRtree([b["poly"] for b in bodies])
    print("water → %d bodies (%ds)" % (len(bodies), time.time() - t0), flush=True)
    TILE, HN, HSTEP = C.TILE, C.HN, C.HSTEP
    keys = set()
    for b in bodies:
        x0, z0, x1, z1 = b["poly"].buffer(WATER.reach(b) + 20).bounds
        for cx in range(int(math.floor(x0 / TILE)), int(math.floor(x1 / TILE)) + 1):
            for cz in range(int(math.floor(z0 / TILE)), int(math.floor(z1 / TILE)) + 1):
                keys.add((cx, cz))
    done = 0
    for cx, cz in sorted(keys):
        fn = os.path.join(out, "chunks", "CBE_%d_%d.bin" % (cx, cz))
        if not os.path.exists(fn):
            continue
        buf = bytearray(open(fn, "rb").read())
        hn, = struct.unpack_from("<i", buf, 12)
        assert hn == HN
        o = 16 + 4 * HN * HN
        nroads, = struct.unpack_from("<i", buf, o)
        o += 4
        roads = []
        for _ in range(nroads):
            cid, fl, npts, w, a0, ln, c0, c1 = struct.unpack_from("<BBHfffff", buf, o)
            o += struct.calcsize("<BBHfffff")
            pts = np.frombuffer(bytes(buf[o:o + 12 * npts]), "<f4").reshape(npts, 3)
            o += 12 * npts
            roads.append((w, pts))
        gx = cx * TILE + np.arange(HN) * HSTEP
        gz = cz * TILE + np.arange(HN) * HSTEP
        X, Z = np.meshgrid(gx, gz)
        H = height(X.ravel(), Z.ravel()).reshape(HN, HN).astype(np.float32)
        tb = shapely.box(cx * TILE - 40, cz * TILE - 40, (cx + 1) * TILE + 40, (cz + 1) * TILE + 40)
        near = [bodies[q] for q in btree.query(tb) if bodies[q]["poly"].distance(tb) < WATER.reach(bodies[q])]
        wet = WATER.carve(H, X, Z, near) if near else None
        for w, pts in roads:                                       # = chunk.py: ground under roads, causeways
            reach = w * 0.5 + 3.0
            for x, y, z in pts:
                i0 = int(max(0, math.floor((z - cz * TILE - reach) / HSTEP)))
                i1 = int(min(HN - 1, math.ceil((z - cz * TILE + reach) / HSTEP)))
                j0 = int(max(0, math.floor((x - cx * TILE - reach) / HSTEP)))
                j1 = int(min(HN - 1, math.ceil((x - cx * TILE + reach) / HSTEP)))
                if i1 >= i0 and j1 >= j0:
                    sub = H[i0:i1 + 1, j0:j1 + 1]
                    np.minimum(sub, y - 0.3, out=sub)
                    if wet is not None:
                        sub[wet[i0:i1 + 1, j0:j1 + 1]] = y - 0.3
        buf[16:16 + 4 * HN * HN] = H.astype("<f4").tobytes()
        with open(fn + ".tmp", "wb") as f:
            f.write(bytes(buf))
        os.replace(fn + ".tmp", fn)
        done += 1
    size = WATER.write(os.path.join(out, "water.bin"), bodies)
    print("REWATER %d tiles re-shaped, water.bin %.1f KB, %ds" % (done, size / 1024, time.time() - t0), flush=True)


if __name__ == "__main__":
    main()
