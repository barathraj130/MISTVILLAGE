"""
Traffic signals and bus shelters off the carriageway: one that stands on a road (a signal set out from its own road
onto the crossing road at a junction, a shelter mapped on a bus bay's centreline) moves out to the kerb of the road
it stands on, on its side, 0.6 m past the edge (or up to 12 m along that road at a tight corner); if no such place is
clear of every road it is left out. Written into the tiles'
prop lists in place, after resignal.py (run by chunk.py; running it again changes nothing). Traffic police booths
(kind 4) stand in the junction on purpose and are left alone.

    .venv/bin/python tools/citygen/clearprops.py
"""
import json
import math
import os
import struct
import sys

import numpy as np
from shapely.geometry import LineString, Point
from shapely.strtree import STRtree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import path  # noqa: E402
from resignal import PS, parse  # noqa: E402

MOVE = (1, 2)                  # traffic signal, bus shelter
NO_CARRIAGE = ("footway", "track")


def main():
    out = path("godot", "assets", "city")
    chunks = os.path.join(out, "chunks")
    index = json.load(open(os.path.join(out, "index.json")))
    classes = index["classes"]
    roads_of = {}

    def roads(cx, cz):
        if (cx, cz) not in roads_of:
            fn = os.path.join(chunks, "CBE_%d_%d.bin" % (cx, cz))
            rs = []
            if os.path.exists(fn):
                for cid, fl, w, c0, c1, pts in parse(bytearray(open(fn, "rb").read()))[0]:
                    if len(pts) >= 2 and (classes[cid] if cid < len(classes) else "residential") not in NO_CARRIAGE:
                        rs.append((LineString(pts[:, [0, 2]]), w))
            roads_of[(cx, cz)] = rs
        return roads_of[(cx, cz)]

    moved = dropped = 0
    for key in sorted(index["tiles"]):
        cx, cz = map(int, key.split(","))
        fn = os.path.join(chunks, "CBE_%d_%d.bin" % (cx, cz))
        if not os.path.exists(fn):
            continue
        buf = bytearray(open(fn, "rb").read())
        _, props, at, end = parse(buf)
        if not any(p[0] in MOVE for p in props):
            continue
        near = [r for dx in (-1, 0, 1) for dz in (-1, 0, 1) for r in roads(cx + dx, cz + dz)]
        if not near:
            continue
        tree = STRtree([ln.buffer(w * 0.5 + 0.3, cap_style="flat") for ln, w in near])

        def on_road(x, z):
            return [int(h) for h in tree.query(Point(x, z), predicate="intersects")]

        keep, changed = [], False
        for p in props:
            kind, x, y, z, yaw, size = p
            hits = on_road(x, z) if kind in MOVE else []
            if not hits:
                keep.append(p)
                continue
            changed = True
            for _ in range(3):                                   # out past the edge of the road it's on, on its side
                ln, w = near[min(hits, key=lambda h: near[h][0].distance(Point(x, z)))]
                q = ln.interpolate(ln.project(Point(x, z)))
                dx, dz = x - q.x, z - q.y
                d = math.hypot(dx, dz)
                if d < 1e-3:                                      # on the centreline: its left side (India: the kerb)
                    a = ln.interpolate(max(ln.project(q) - 1.0, 0.0))
                    b = ln.interpolate(min(ln.project(q) + 1.0, ln.length))
                    tx, tz = b.x - a.x, b.y - a.y
                    tl = math.hypot(tx, tz) or 1.0
                    dx, dz, d = tz / tl, -tx / tl, 1.0
                x, z = q.x + dx / d * (w * 0.5 + 0.6), q.y + dz / d * (w * 0.5 + 0.6)
                hits = on_road(x, z)
                if not hits:
                    break
            if hits:                                             # a tight corner: try a few metres along its road
                ln, w = near[min(hits, key=lambda h: near[h][0].distance(Point(x, z)))]
                s0 = ln.project(Point(x, z))
                q0 = ln.interpolate(s0)
                for ds in (3.0, -3.0, 6.0, -6.0, 9.0, -9.0, 12.0, -12.0):
                    sa = min(max(s0 + ds, 0.0), ln.length)
                    a = ln.interpolate(max(sa - 0.5, 0.0))
                    b = ln.interpolate(min(sa + 0.5, ln.length))
                    tx, tz = b.x - a.x, b.y - a.y
                    tl = math.hypot(tx, tz) or 1.0
                    nx, nz = tz / tl, -tx / tl                    # one side; the prop keeps the side it was on
                    c = ln.interpolate(sa)
                    if (x - q0.x) * nx + (z - q0.y) * nz < 0:
                        nx, nz = -nx, -nz
                    xx, zz = c.x + nx * (w * 0.5 + 0.6), c.y + nz * (w * 0.5 + 0.6)
                    if not on_road(xx, zz):
                        x, z, hits = xx, zz, []
                        break
            if hits:
                dropped += 1
                continue
            moved += 1
            keep.append((kind, float(x), y, float(z), yaw, size))
        if not changed:
            continue
        body = bytearray(struct.pack("<i", len(keep)))
        for r in keep:
            body += PS.pack(*r)
        buf = buf[:at] + body + buf[end:]
        with open(fn + ".tmp", "wb") as f:
            f.write(bytes(buf))
        os.replace(fn + ".tmp", fn)
    print("PROPS %d signals / shelters moved off the road, %d left out (no clear kerb)" % (moved, dropped), flush=True)


if __name__ == "__main__":
    main()
