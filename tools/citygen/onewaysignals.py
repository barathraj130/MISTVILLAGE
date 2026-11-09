"""
Traffic signals on one-way roads: chunk.py puts a signal on each approach to an OSM-tagged signal point, one each way
along the road. On a one-way road (the two halves of every divided main road are one-ways in OSM) one of the two
faces the traffic leaving the junction: nobody drives towards it, and it stands on the left of the wrong way, which
is the right-hand kerb of the real traffic. That one is taken out; the approach's own signal, on its left kerb, stays.
Written into the tiles' prop lists in place, after clearprops.py (run by chunk.py; running it again changes nothing).

    .venv/bin/python tools/citygen/onewaysignals.py [--dry-run]
"""
import json
import math
import os
import struct
import sys

import numpy as np
from shapely.geometry import LineString, Point

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import path  # noqa: E402
from resignal import PS, parse  # noqa: E402

SIGNAL = 1
REACH = 4.0                    # past the road's half width: a kerb signal belongs to the road it stands beside


def main():
    dry = "--dry-run" in sys.argv
    out = path("godot", "assets", "city")
    chunks = os.path.join(out, "chunks")
    index = json.load(open(os.path.join(out, "index.json")))
    roads_of = {}

    def roads(cx, cz):
        if (cx, cz) not in roads_of:
            fn = os.path.join(chunks, "CBE_%d_%d.bin" % (cx, cz))
            rs = []
            if os.path.exists(fn):
                for cid, fl, w, c0, c1, pts in parse(bytearray(open(fn, "rb").read()))[0]:
                    if len(pts) >= 2 and not (fl & 2):
                        rs.append((LineString(pts[:, [0, 2]]), w, bool(fl & 1)))
            roads_of[(cx, cz)] = rs
        return roads_of[(cx, cz)]

    removed = kept = 0
    for key in sorted(index["tiles"]):
        cx, cz = map(int, key.split(","))
        fn = os.path.join(chunks, "CBE_%d_%d.bin" % (cx, cz))
        if not os.path.exists(fn):
            continue
        buf = bytearray(open(fn, "rb").read())
        _, props, at, end = parse(buf)
        if not any(p[0] == SIGNAL for p in props):
            continue
        near = [r for dx in (-1, 0, 1) for dz in (-1, 0, 1) for r in roads(cx + dx, cz + dz)]
        keep = []
        for p in props:
            kind, x, y, z, yaw, size = p
            if kind != SIGNAL or not near:
                keep.append(p)
                continue
            pt = Point(x, z)
            ln, w, oneway = min(near, key=lambda r: r[0].distance(pt))
            if not oneway or ln.distance(pt) > w * 0.5 + REACH:
                keep.append(p)
                kept += 1
                continue
            s = ln.project(pt)
            a = ln.interpolate(max(s - 1.0, 0.0))
            b = ln.interpolate(min(s + 1.0, ln.length))
            tx, tz = b.x - a.x, b.y - a.y                         # the one-way's direction (its points run that way)
            tl = math.hypot(tx, tz) or 1.0
            served = np.array([-math.sin(yaw), -math.cos(yaw)])     # the lights face the oncoming driver: traffic -f
            if served[0] * tx / tl + served[1] * tz / tl < -0.5:
                removed += 1                                       # faces the traffic leaving: nobody comes this way
                continue
            keep.append(p)
            kept += 1
        if len(keep) == len(props) or dry:
            continue
        body = bytearray(struct.pack("<i", len(keep)))
        for r in keep:
            body += PS.pack(*r)
        buf = buf[:at] + body + buf[end:]
        with open(fn + ".tmp", "wb") as f:
            f.write(bytes(buf))
        os.replace(fn + ".tmp", fn)
    print("SIGNALS %d on one-ways facing the wrong way %s, %d kept" % (removed, "found (dry run)" if dry else "taken out", kept),
          flush=True)


if __name__ == "__main__":
    main()
