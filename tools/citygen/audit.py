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

LIFT = {k: 0.03 for k in ("motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential",
                           "living_street", "service", "track", "footway")}       # = chunk.py LIFT (one height)


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
                       "junc", "junc_low", "paving_on_road", "medians_on_road"], 0)
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
        drive = [(ln, r, cls) for ln, r, cls in lines if cls not in ("footway", "track")]
        dcarr = [ln.buffer(r["w"] * 0.5, cap_style="flat") for ln, r, cls in drive]
        dtree = STRtree(dcarr) if dcarr else None

        def near_carr(geom):
            return [] if dtree is None else list(dtree.query(geom, predicate="intersects"))

        def surface(h, P):
            ln, r, cls = drive[h] if isinstance(h, (int, np.integer)) else h
            cum = np.concatenate([[0.0], np.cumsum(np.hypot(np.diff(r["p"][:, 0]), np.diff(r["p"][:, 2])))])
            return float(np.interp(ln.project(P), cum, r["p"][:, 1])) + LIFT.get(cls, 0.02) + 0.06
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
            # kerb: footpath top at least 10 cm above every carriageway beside it (streets without a footpath have a
            # flush edge strip instead: street types 4-7)
            if (w["fl"] >> 4) & 7 >= 4 and not w["fl"] & 8:
                continue
            mid = p[len(p) // 2]
            P = Point(mid[0], mid[2])
            hs = [surface(h, P) for h in near_carr(P.buffer(w["w"] * 0.5 + 0.6))]
            if hs and mid[1] - max(hs) < 0.1:
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
        for kind, v in t["yards"]:
            if kind in (1, 2, 6) and len(v) >= 3 and tree is not None:
                for i in range(0, len(v) - 2, 3):
                    tri = Polygon(v[i:i + 3, [0, 2]])
                    if tri.area > 0.05 and any(tri.intersection(carr[h]).area > 0.3 for h in tree.query(tri, predicate="intersects")):
                        c["paving_on_road"] += 1
                        break
        for w in t["walks"]:
            if w["w"] < 1.5 and len(w["p"]) >= 2 and tree is not None:
                strip = LineString(w["p"][:, [0, 2]]).buffer(w["w"] * 0.5, cap_style="flat")
                if any(strip.intersection(carr[h]).area > 0.3 for h in tree.query(strip, predicate="intersects")):
                    c["medians_on_road"] += 1
        jpolys = []
        for v in t["junc"]:
            c["junc"] += 1
            tri = [Polygon(v[i:i + 3, [0, 2]]) for i in range(0, len(v) - 2, 3)]
            jp = shapely.union_all([q.buffer(0) for q in tri if q.area > 0])
            jpolys.append(jp)
            # every vertex above every ribbon whose carriageway it lies on
            if any(v[i, 1] < max(hs) - 0.005 for i in range(0, len(v), 3)
                   for hs in [[surface(h, Point(v[i, 0], v[i, 2])) for h in near_carr(Point(v[i, 0], v[i, 2]))]] if hs):
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
