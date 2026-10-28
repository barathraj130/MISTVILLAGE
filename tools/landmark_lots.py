"""
Where a landmark stands in the city: its map position (lat, lon) in game metres, the building footprints there in
the city tiles (the plain blocks a designed landmark replaces), the ground height, and the nearest main roads with
their direction (which way its front should face).

    .venv/bin/python tools/landmark_lots.py LAT LON [RADIUS]
"""
import json
import math
import os
import sys

import numpy as np
from pyproj import Transformer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "citygen"))
from lib.common import load, path  # noqa: E402
from lib.tiles import read_tile  # noqa: E402


def to_xz(lat, lon):
    cfg = load("city.yaml")
    to_utm = Transformer.from_crs("EPSG:4326", cfg["crs"], always_xy=True)
    e0, n0 = to_utm.transform(cfg["origin"]["lon"], cfg["origin"]["lat"])
    e, n = to_utm.transform(lon, lat)
    return e - e0, -(n - n0)


def area(xz):
    return 0.5 * abs(np.dot(xz[:, 0], np.roll(xz[:, 1], 1)) - np.dot(xz[:, 1], np.roll(xz[:, 0], 1)))


def main():
    lat, lon = float(sys.argv[1]), float(sys.argv[2])
    r = float(sys.argv[3]) if len(sys.argv) > 3 else 120.0
    x0, z0 = to_xz(lat, lon)
    out = path("godot", "assets", "city")
    classes = json.load(open(os.path.join(out, "index.json")))["classes"]
    print("AT x %.1f z %.1f" % (x0, z0))
    blds, roads = [], []
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            fn = os.path.join(out, "chunks", "CBE_%d_%d.bin" % (x0 // 256 + dx, z0 // 256 + dz))
            if not os.path.exists(fn):
                continue
            t = read_tile(fn)
            for b in t["blds"]:
                c = b["xz"].mean(0)
                d = math.hypot(c[0] - x0, c[1] - z0)
                if d < r:
                    blds.append((d, b, c))
            for rd in t["roads"]:
                cl = classes[rd["cid"]] if rd["cid"] < len(classes) else "?"
                if cl not in ("trunk", "primary", "secondary", "tertiary"):
                    continue
                p = rd["p"]
                dd = np.hypot(p[:, 0] - x0, p[:, 2] - z0)
                i = int(dd.argmin())
                if dd[i] < r * 1.5:
                    j = min(i + 1, len(p) - 1)
                    k = max(j - 1, 0)
                    v = p[j, [0, 2]] - p[k, [0, 2]]
                    roads.append((dd[i], cl, rd["w"], p[i, [0, 2]].round(1).tolist(), (v / (np.linalg.norm(v) or 1)).round(3).tolist()))
    for d, b, c in sorted(blds, key=lambda q: -area(q[1]["xz"]))[:12]:
        print("BLD d %5.1f area %6.0f floors %d base %.2f centre %s xz %s" % (d, area(b["xz"]), b["floors"], b["base"],
              c.round(2).tolist(), b["xz"].round(1).tolist()))
    for q in sorted(roads)[:6]:
        print("ROAD d %5.1f %s w %.1f at %s dir %s" % q)


if __name__ == "__main__":
    main()
