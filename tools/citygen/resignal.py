"""
Traffic signals at the big junctions OpenStreetMap has not tagged: where main roads (trunk, primary, secondary)
meet from at least two directions with three or more arms, and no signal stands within 45 m, every arm gets a
signal on its left kerb (India drives on the left), just back from the junction surface — written into the
tiles' prop lists in place (no city rebuild). Running it again adds nothing new: the added signals count as
existing ones.

    .venv/bin/python tools/citygen/resignal.py
"""
import json
import math
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import path  # noqa: E402

MAJOR = {"motorway", "trunk", "primary", "secondary"}
RS = struct.Struct("<BBHfffff")
PS = struct.Struct("<B5f")


def parse(buf):
    """Offsets of a tile's sections and its roads and props."""
    hn, = struct.unpack_from("<i", buf, 12)
    o = 16 + 4 * hn * hn
    n, = struct.unpack_from("<i", buf, o)
    o += 4
    roads = []
    for _ in range(n):
        cid, fl, npts, w, a0, ln, c0, c1 = RS.unpack_from(buf, o)
        o += RS.size
        pts = np.frombuffer(bytes(buf[o:o + 12 * npts]), "<f4").reshape(npts, 3).astype(float)
        o += 12 * npts
        roads.append((cid, fl, w, c0, c1, pts))
    n, = struct.unpack_from("<i", buf, o)                       # buildings
    o += 4
    for _ in range(n):
        h = struct.unpack_from("<BBBBBBHfi", buf, o)
        o += struct.calcsize("<BBBBBBHfi") + 28 + 8 * h[6]
    n, = struct.unpack_from("<i", buf, o)                       # footpaths
    o += 4
    for _ in range(n):
        fl, cid, npts, w = struct.unpack_from("<BBHf", buf, o)
        o += struct.calcsize("<BBHf") + 12 * npts
    n, = struct.unpack_from("<i", buf, o)                       # junction surfaces
    o += 4
    for _ in range(n):
        v, = struct.unpack_from("<H", buf, o)
        o += 2 + 12 * v
    props_at = o
    n, = struct.unpack_from("<i", buf, o)
    o += 4
    props = [PS.unpack_from(buf, o + PS.size * i) for i in range(n)]
    o += PS.size * n
    return roads, props, props_at, o


def back_along(pts, dist):
    """The point `dist` metres along the polyline from its first point."""
    left = dist
    for a, b in zip(pts, pts[1:]):
        L = float(np.hypot(b[0] - a[0], b[2] - a[2]))
        if L >= left and L > 1e-6:
            return a + (b - a) * (left / L)
        left -= L
    return pts[-1]


def main():
    out = path("godot", "assets", "city")
    index = json.load(open(os.path.join(out, "index.json")))
    classes = index["classes"]
    chunks = os.path.join(out, "chunks")
    ends = []                       # [x, z, y, dx, dz (travel towards the junction), w, clear, approach pts]
    signals = []
    for fn in os.listdir(chunks):
        if not fn.endswith(".bin"):
            continue
        roads, props, _, _ = parse(open(os.path.join(chunks, fn), "rb").read())
        signals += [(p[1], p[3]) for p in props if p[0] == 1]
        for cid, fl, w, c0, c1, pts in roads:
            if classes[cid] not in MAJOR or len(pts) < 2 or (fl & 2):
                continue
            oneway = bool(fl & 1)
            for at_start, clear in ((True, c0), (False, c1)):
                if clear <= 0.0:
                    continue
                if oneway and at_start:                         # one-way: traffic leaves the junction here
                    continue
                seq = pts if at_start else pts[::-1]            # from the junction outward
                d = seq[0] - seq[1]
                dn = math.hypot(d[0], d[2])
                if dn < 1e-6:
                    continue
                ends.append((seq[0][0], seq[0][2], seq[0][1], d[0] / dn, d[2] / dn, w, clear, seq, oneway))
    print("major road ends at junctions: %d, existing signals: %d" % (len(ends), len(signals)), flush=True)
    S = np.array(signals) if signals else np.zeros((0, 2))
    E = np.array([[e[0], e[1]] for e in ends])
    used = np.zeros(len(ends), bool)
    new = {}
    n_j = 0
    for i in range(len(ends)):
        if used[i]:
            continue
        near = np.where(np.hypot(E[:, 0] - E[i, 0], E[:, 1] - E[i, 1]) < 25.0)[0]
        used[near] = True
        if len(near) < 3:
            continue
        dirs = [math.atan2(ends[k][4], ends[k][3]) for k in near]
        spread = max(abs((a - b + math.pi) % (2 * math.pi) - math.pi) for a in dirs for b in dirs)
        if spread < math.radians(40):
            continue
        cx, cz = E[near, 0].mean(), E[near, 1].mean()
        if len(S) and np.hypot(S[:, 0] - cx, S[:, 1] - cz).min() < 45.0:
            continue
        n_j += 1
        for k in near:
            x, z, y, dx, dz, w, clear, seq, oneway = ends[k]
            a = back_along(seq, clear + 1.5)                       # just back from the junction surface
            d = np.array([dx, dz])                                  # travel towards the junction
            left = np.array([d[1], -d[0]])                          # = chunk.py drive_left
            off = (w * 0.5 + 0.6) if oneway else (w * 0.5 + 0.6)
            q = np.array([a[0], a[2]]) + left * off
            f = -d                                                  # the lights face the oncoming driver
            yaw = math.atan2(f[0], f[1])
            key = (int(math.floor(q[0] / 256.0)), int(math.floor(q[1] / 256.0)))
            new.setdefault(key, []).append((1, float(q[0]), float(a[1]) + 0.15, float(q[1]), yaw, float(w)))
    added = 0
    for (cx, cz), recs in new.items():
        fn = os.path.join(chunks, "CBE_%d_%d.bin" % (cx, cz))
        if not os.path.exists(fn):
            continue
        buf = bytearray(open(fn, "rb").read())
        _, props, at, end = parse(buf)
        body = bytearray(struct.pack("<i", len(props) + len(recs)))
        body += buf[at + 4:end]
        for r in recs:
            body += PS.pack(*r)
        buf = buf[:at] + body + buf[end:]
        with open(fn + ".tmp", "wb") as f:
            f.write(bytes(buf))
        os.replace(fn + ".tmp", fn)
        added += len(recs)
    print("RESIGNAL %d junctions signalled, %d signal heads added" % (n_j, added), flush=True)
    booths()


def booths():
    """A traffic police umbrella booth (prop 4) at a corner of every junction with four or more signal heads:
    on the footpath behind one approach's pole, towards the junction."""
    chunks = os.path.join(path("godot", "assets", "city"), "chunks")
    sigs, have = [], []
    for fn in os.listdir(chunks):
        if fn.endswith(".bin"):
            _, props, _, _ = parse(open(os.path.join(chunks, fn), "rb").read())
            sigs += [p for p in props if p[0] == 1]
            have += [(p[1], p[3]) for p in props if p[0] == 4]
    P = np.array([[p[1], p[3]] for p in sigs])
    H = np.array(have) if have else np.zeros((0, 2))
    used = np.zeros(len(sigs), bool)
    new = {}
    for i in range(len(sigs)):
        if used[i]:
            continue
        near = np.where(np.hypot(P[:, 0] - P[i, 0], P[:, 1] - P[i, 1]) < 35.0)[0]
        used[near] = True
        if len(near) < 4:
            continue
        cx, cz = P[near, 0].mean(), P[near, 1].mean()
        if len(H) and np.hypot(H[:, 0] - cx, H[:, 1] - cz).min() < 45.0:
            continue
        _, x, y, z, yaw, w = sigs[near[0]]
        f = np.array([math.sin(yaw), math.cos(yaw)])            # the lights face this way; traffic comes -f
        d = -f
        left = np.array([d[1], -d[0]])
        q = np.array([x, z]) + left * 2.2 + d * 3.5
        key = (int(math.floor(q[0] / 256.0)), int(math.floor(q[1] / 256.0)))
        new.setdefault(key, []).append((4, float(q[0]), float(y), float(q[1]), float(yaw), 1.0))
    added = 0
    for (cx, cz), recs in new.items():
        fn = os.path.join(chunks, "CBE_%d_%d.bin" % (cx, cz))
        if not os.path.exists(fn):
            continue
        buf = bytearray(open(fn, "rb").read())
        _, props, at, end = parse(buf)
        body = bytearray(struct.pack("<i", len(props) + len(recs))) + buf[at + 4:end]
        for r in recs:
            body += PS.pack(*r)
        buf = buf[:at] + body + buf[end:]
        with open(fn + ".tmp", "wb") as f:
            f.write(bytes(buf))
        os.replace(fn + ".tmp", fn)
        added += len(recs)
    print("BOOTHS %d traffic police booths added" % added, flush=True)


if __name__ == "__main__":
    main()
