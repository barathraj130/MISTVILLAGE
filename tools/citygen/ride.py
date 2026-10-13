"""
Ride quality of the city roads: how a car at 50 km/h would feel the road surface.

  jolt     vertical acceleration from the road's changing gradient, |d²y/ds²|·v², worst over every 6 m step
  steps    height differences where two road pieces meet (same point, different heights)

    .venv/bin/python tools/citygen/ride.py [--sample N]
"""
import json
import os
import sys
from collections import defaultdict

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import path  # noqa: E402
from lib.tiles import read_tile  # noqa: E402

V = 50 / 3.6


def main():
    out = path("godot", "assets", "city")
    index = json.load(open(os.path.join(out, "index.json")))
    keys = sorted(index["tiles"])
    if "--sample" in sys.argv:
        keys = keys[::max(1, len(keys) // int(sys.argv[sys.argv.index("--sample") + 1]))]
    jolts, ends = [], defaultdict(list)
    for k in keys:
        cx, cz = map(int, k.split(","))
        fn = os.path.join(out, "chunks", "CBE_%d_%d.bin" % (cx, cz))
        if not os.path.exists(fn):
            continue
        t = read_tile(fn)
        for r in t["roads"]:
            p = r["p"].astype(np.float64)
            if r["fl"] & 2 or len(p) < 3:              # bridges are raised separately in the game
                continue
            s = np.concatenate([[0], np.cumsum(np.hypot(np.diff(p[:, 0]), np.diff(p[:, 2])))])
            y = p[:, 1]
            g = np.diff(y) / np.maximum(np.diff(s), 0.5)
            dg = np.abs(np.diff(g)) / np.maximum((s[2:] - s[:-2]) * 0.5, 0.5)
            jolts.extend((dg * V * V).tolist())
            for q in (p[0], p[-1]):
                ends[(round(q[0], 1), round(q[2], 1))].append(q[1])
    j = np.array(jolts)
    steps = np.array([max(v) - min(v) for v in ends.values() if len(v) > 1])
    res = {"tiles": len(keys), "points": int(j.size),
           "jolt_median": round(float(np.median(j)), 2), "jolt_p95": round(float(np.percentile(j, 95)), 2),
           "jolt_p99": round(float(np.percentile(j, 99)), 2), "jolt_over_2ms2_pct": round(float((j > 2.0).mean() * 100), 2),
           "joins": int(steps.size), "step_over_2cm_pct": round(float((steps > 0.02).mean() * 100), 2) if steps.size else 0,
           "step_max_cm": round(float(steps.max() * 100), 1) if steps.size else 0}
    print(json.dumps(res))


if __name__ == "__main__":
    main()
