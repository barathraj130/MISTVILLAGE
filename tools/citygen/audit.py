"""
Check every street in the city tiles (godot/assets/city) for the faults a driver would notice, and print counts:

  roads      road surface below the ground beside it; steep steps between neighbouring points
  kerbs      footpath strips that run onto another road's carriageway; footpath barely above the road (no kerb)
  buildings  designed buildings standing on a carriageway; buildings overlapping each other
  props      signals / shelters / lamps on a carriageway; speed breakers inside a junction
  junctions  junction surfaces that sit below the road ribbons they should cover

    .venv/bin/python tools/citygen/audit.py [--sample N]
"""
import json
import math
import os
import sys

import numpy as np
import shapely
from shapely.geometry import LineString, Point, Polygon
from shapely.strtree import STRtree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import path  # noqa: E402
from lib.tiles import read_tile  # noqa: E402

LIFT = {"motorway": 0.07, "trunk": 0.07, "primary": 0.06, "secondary": 0.05, "tertiary": 0.04, "unclassified": 0.03,
        "residential": 0.025, "living_street": 0.02, "service": 0.015, "track": 0.01, "footway": 0.035}


def kit_rect(kd, ext):
    """footprint rectangle of a placed designed building (game x, z)"""
    ox, oy, oz, fx, fz, sx, sz = kd
    (ecx, ecz), (bw, bd) = ext
    nz = np.array([fx, fz])
    nx = np.array([fz, -fx])
    c = np.array([ox, oz]) + nx * sx * ecx + nz * sz * ecz
    hx, hz = bw * sx / 2, bd * sz / 2
    pts = [c + nx * a * hx + nz * b * hz for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    return Polygon(pts)


def main():
    out = path("godot", "assets", "city")
    index = json.load(open(os.path.join(out, "index.json")))
    classes = index["classes"]
    man = json.load(open(path("godot", "assets", "buildings", "manifest.json")))
    ext = {}
    for i, n in enumerate(index["variants"]):
        mn, mx = man[n]["min"], man[n]["max"]
        ext[i] = (((mn[0] + mx[0]) * 0.5, -(mn[1] + mx[1]) * 0.5), (mx[0] - mn[0], mx[1] - mn[1]))
    keys = sorted(index["tiles"])
    if "--sample" in sys.argv:
        step = max(1, len(keys) // int(sys.argv[sys.argv.index("--sample") + 1]))
        keys = keys[::step]
    c = dict.fromkeys(["tiles", "road_pts", "road_below_ground", "road_steps", "walks", "walk_on_road", "walk_low_kerb",
                       "kits", "kit_on_road", "kit_overlap", "props", "prop_on_road", "breaker_in_junction",
                       "junc", "junc_low"], 0)
    for k in keys:
        cx, cz = map(int, k.split(","))
        fn = os.path.join(out, "chunks", "CBE_%d_%d.bin" % (cx, cz))
        if not os.path.exists(fn):
            continue
        t = read_tile(fn)
        c["tiles"] += 1
        H, hn = t["H"], t["hn"]
        carr, lines = [], []
        for r in t["roads"]:
            p = r["p"]
            cls = classes[r["cid"]] if r["cid"] < len(classes) else "residential"
            if len(p) >= 2:
                ln = LineString(p[:, [0, 2]])
                lines.append((ln, r, cls))
                if cls not in ("footway", "track"):
                    carr.append(ln.buffer(r["w"] * 0.5 - 0.15, cap_style="flat"))
            for i, (x, y, z) in enumerate(p):
                c["road_pts"] += 1
                j = int((x - cx * 256) / 8)
                q = int((z - cz * 256) / 8)
                if 0 <= j < hn and 0 <= q < hn and H[q, j] > y + 0.02:
                    c["road_below_ground"] += 1
                if i and abs(y - p[i - 1][1]) > 1.2:
                    c["road_steps"] += 1
        tree = STRtree(carr) if carr else None
        ltree = STRtree([l for l, _, _ in lines]) if lines else None
        for w in t["walks"]:
            p = w["p"]
            if len(p) < 2:
                continue
            c["walks"] += 1
            strip = LineString(p[:, [0, 2]]).buffer(w["w"] * 0.5, cap_style="flat")
            if tree is not None:
                hit = [h for h in tree.query(strip, predicate="intersects") if strip.intersection(carr[h]).area > 0.3]
                if hit:
                    c["walk_on_road"] += 1
            if ltree is not None:
                mid = p[len(p) // 2]
                h = int(ltree.nearest(Point(mid[0], mid[2])))
                ln, r, cls = lines[h]
                ry = float(r["p"][min(range(len(r["p"])), key=lambda i: (r["p"][i][0] - mid[0]) ** 2 + (r["p"][i][2] - mid[2]) ** 2)][1])
                if mid[1] - (ry + LIFT.get(cls, 0.02) + 0.06) < 0.1:
                    c["walk_low_kerb"] += 1
        rects = []
        for b in t["blds"]:
            if b["variant"] < 0:
                continue
            c["kits"] += 1
            rc = kit_rect(b["kd"], ext[b["variant"]])
            rects.append(rc)
            if tree is not None and any(rc.intersection(carr[h]).area > 0.5 for h in tree.query(rc, predicate="intersects")):
                c["kit_on_road"] += 1
        if rects:
            rt = STRtree(rects)
            for i, rc in enumerate(rects):
                for h in rt.query(rc, predicate="intersects"):
                    if h > i and rc.intersection(rects[h]).area > 0.15 * min(rc.area, rects[h].area):
                        c["kit_overlap"] += 1
        jpolys = []
        for v in t["junc"]:
            c["junc"] += 1
            tri = [Polygon(v[i:i + 3, [0, 2]]) for i in range(0, len(v) - 2, 3)]
            jp = shapely.union_all([q.buffer(0) for q in tri if q.area > 0])
            jpolys.append(jp)
            if ltree is not None:
                cc = v.mean(axis=0)
                h = int(ltree.nearest(Point(cc[0], cc[2])))
                ln, r, cls = lines[h]
                ry = float(r["p"][min(range(len(r["p"])), key=lambda i: (r["p"][i][0] - cc[0]) ** 2 + (r["p"][i][2] - cc[2]) ** 2)][1])
                if cc[1] < ry + LIFT.get(cls, 0.02) + 0.06:
                    c["junc_low"] += 1
        jtree = STRtree(jpolys) if jpolys else None
        for kind, x, y, z, yaw, size in t["props"]:
            c["props"] += 1
            P = Point(x, z)
            if kind == 3:
                if jtree is not None and len(jtree.query(P.buffer(6.0), predicate="intersects")):
                    c["breaker_in_junction"] += 1
            elif tree is not None and len(tree.query(P.buffer(0.2), predicate="intersects")):
                c["prop_on_road"] += 1
    print(json.dumps(c, indent=1))


if __name__ == "__main__":
    main()
