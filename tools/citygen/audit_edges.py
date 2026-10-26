"""
Check where every street meets its edge, the way the game builds it (city_streamer.gd _walks / _street_edge), over
every tile in godot/assets/city, and print counts with the worst places:

  gap        bare ground between the road's edge and its footpath or edge strip (the footpath set back from the road)
  buried     a footpath or a street-edge strip (colony concrete, old-town drain, gravel shoulder) under the ground
             beside it, so the earth shows over it
  kerb_slit  a raised footpath's kerb face ending above the road surface (a slit of nothing under the kerb)
  step       a street-edge strip standing more than 0.3 m over the road (a wall at the road's edge)
  tall       a strip or footpath standing over 1.2 m above the land behind it (its back and end faces run down to the
             ground in the game; listed to see where roads stand on banks)

    .venv/bin/python tools/citygen/audit_edges.py [--sample N] [--worst N]
"""
import json
import math
import os
import sys

import numpy as np
from shapely.geometry import LineString, Point
from shapely.strtree import STRtree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import path  # noqa: E402
from lib.tiles import read_tile  # noqa: E402

KERB = 0.2                     # = chunk.py / city_streamer.gd KERB
LIFT = 0.09                    # road surface above its centreline points (city_streamer.gd RANK + 0.06)
EDGE_DN = 0.04                 # street-edge strips below the footpath line (city_streamer.gd _street_edge dn)
KERB_UP, KERB_DROP = 0.02, 1.0  # kerb top over the footpath, its face's drop (city_streamer.gd _walks)
FACE = 1.2
NO_WALK = ("footway", "track")


def ground(t, step, x, z):
    """The ground mesh's height at x, z: the same two triangles per cell as city_streamer.gd _ground."""
    H, n = t["H"], t["hn"]
    fx, fz = (x - t["cx"] * 256.0) / step, (z - t["cz"] * 256.0) / step
    j, i = min(max(int(fx), 0), n - 2), min(max(int(fz), 0), n - 2)
    u, v = fx - j, fz - i
    if u + v <= 1.0:
        return H[i, j] + (H[i, j + 1] - H[i, j]) * u + (H[i + 1, j] - H[i, j]) * v
    return H[i + 1, j + 1] + (H[i + 1, j] - H[i + 1, j + 1]) * (1 - u) + (H[i, j + 1] - H[i + 1, j + 1]) * (1 - v)


def road_y(p, line, x, z):
    """The road centreline's height at the point nearest x, z."""
    s = line.project(Point(x, z))
    acc = 0.0
    for k in range(len(p) - 1):
        L = math.hypot(p[k + 1, 0] - p[k, 0], p[k + 1, 2] - p[k, 2])
        if acc + L >= s or k == len(p) - 2:
            f = 0.0 if L < 1e-6 else min(max((s - acc) / L, 0.0), 1.0)
            return p[k, 1] + (p[k + 1, 1] - p[k, 1]) * f
        acc += L
    return p[0, 1]


def main():
    out = path("godot", "assets", "city")
    index = json.load(open(os.path.join(out, "index.json")))
    classes, step = index["classes"], float(index["hstep"])
    keys = sorted(index["tiles"])
    if "--sample" in sys.argv:
        keys = keys[::max(1, len(keys) // int(sys.argv[sys.argv.index("--sample") + 1]))]
    nworst = int(sys.argv[sys.argv.index("--worst") + 1]) if "--worst" in sys.argv else 8
    c = dict.fromkeys(["tiles", "edge_samples", "gap", "gap_1m", "buried", "kerb_slit", "step", "tall"], 0)
    worst = {k: [] for k in ("gap", "buried", "kerb_slit", "step", "tall")}
    cache = {}
    for key in keys:
        cx, cz = map(int, key.split(","))
        fn = os.path.join(out, "chunks", "CBE_%d_%d.bin" % (cx, cz))
        if not os.path.exists(fn):
            continue
        t = read_tile(fn)
        c["tiles"] += 1
        roads = []                                          # this tile's roads and its neighbours' (edges near a border)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                nf = os.path.join(out, "chunks", "CBE_%d_%d.bin" % (cx + dx, cz + dz))
                if not os.path.exists(nf):
                    continue
                if nf not in cache:
                    if len(cache) > 64:
                        cache.clear()
                    cache[nf] = read_tile(nf)["roads"]
                roads += [(LineString(r["p"][:, [0, 2]]), r) for r in cache[nf] if len(r["p"]) >= 2
                          and (classes[r["cid"]] if r["cid"] < len(classes) else "residential") not in NO_WALK]
        if not roads:
            continue
        tree = STRtree([q[0] for q in roads])
        x0, z0 = cx * 256.0, cz * 256.0
        for wk in t["walks"]:
            fl, hw, p = wk["fl"], wk["w"] * 0.5, wk["p"]
            if fl & 8 or len(p) < 2:
                continue                                    # medians and separators have roads on both sides
            styp = (fl >> 4) & 7
            right = (fl & 4) != 0
            for k in range(len(p) - 1):
                a, b = p[k], p[k + 1]
                L = math.hypot(b[0] - a[0], b[2] - a[2])
                if L < 0.5:
                    continue
                tx, tz = (b[0] - a[0]) / L, (b[2] - a[2]) / L
                rx, rz = (tz, -tx) if right else (-tz, tx)          # towards the road (= _walks rw)
                m = (a + b) * 0.5
                if not (x0 <= m[0] < x0 + 256 and z0 <= m[2] < z0 + 256):
                    continue
                c["edge_samples"] += 1
                ex, ez = m[0] + rx * (hw + KERB), m[2] + rz * (hw + KERB)      # where the road edge should be
                E = Point(ex, ez)                                    # the nearest road *edge* (a wide road beside a
                hs = [int(q) for q in tree.query(E.buffer(12.0))] or [int(np.atleast_1d(tree.query_nearest(E))[0])]
                h = min(hs, key=lambda q: roads[q][0].distance(E) - roads[q][1]["w"] * 0.5)    # narrow one counts)
                line, r = roads[h]
                d = line.distance(E) - r["w"] * 0.5
                ry = road_y(r["p"], line, ex, ez) + LIFT
                where = "%.0f,%.0f" % (m[0], m[2])
                if d > 0.3:
                    c["gap"] += 1
                    c["gap_1m"] += d > 1.0
                    worst["gap"].append((d, where))
                if styp >= 4:
                    top = m[1] - EDGE_DN
                    w2 = {4: 1.25, 5: 1.05}.get(styp, 1.6 if styp == 6 else 1.2)
                    for s in (0.05, w2):                        # its road edge, its back edge
                        g = ground(t, step, ex - rx * s, ez - rz * s)
                        if g > top + 0.02:
                            c["buried"] += 1
                            worst["buried"].append((g - top, where))
                            break
                    gb = ground(t, step, ex - rx * w2, ez - rz * w2)
                    if top - gb > FACE:
                        c["tall"] += 1
                        worst["tall"].append((top - gb, where))
                    if top - ry > 0.3:
                        c["step"] += 1
                        worst["step"].append((top - ry, where))
                else:
                    g = ground(t, step, m[0] - rx * hw * 0.9, m[2] - rz * hw * 0.9)      # its back edge
                    if g > m[1] + 0.02:
                        c["buried"] += 1
                        worst["buried"].append((g - m[1], where))
                    gb = ground(t, step, m[0] - rx * hw, m[2] - rz * hw)
                    if m[1] - gb > FACE:
                        c["tall"] += 1
                        worst["tall"].append((m[1] - gb, where))
                    bottom = m[1] + KERB_UP - KERB_DROP
                    if bottom > ry:
                        c["kerb_slit"] += 1
                        worst["kerb_slit"].append((bottom - ry, where))
    print("tiles %d, edge samples %d" % (c["tiles"], c["edge_samples"]))
    for k in ("gap", "buried", "kerb_slit", "step", "tall"):
        n = c[k]
        extra = " (%d over 1 m)" % c["gap_1m"] if k == "gap" else ""
        print("%-10s %6d  %.2f%%%s" % (k, n, 100.0 * n / max(c["edge_samples"], 1), extra))
        for v, w in sorted(worst[k], reverse=True)[:nworst]:
            print("             %.2f m at %s" % (v, w))


if __name__ == "__main__":
    main()
