"""Reader for the binary city tiles written by tools/citygen/chunk.py (format in its docstring)."""
import struct

import numpy as np


def read_tile(path):
    f = open(path, "rb").read()
    magic = f[:4].decode()
    o = 4
    cx, cz, hn = struct.unpack_from("<iii", f, o)
    o += 12
    H = np.frombuffer(f, "<f4", hn * hn, o).reshape(hn, hn)
    o += hn * hn * 4
    t = {"magic": magic, "cx": cx, "cz": cz, "hn": hn, "H": H, "roads": [], "blds": [], "walks": [], "junc": [], "props": [],
         "yards": []}
    n, = struct.unpack_from("<i", f, o)
    o += 4
    for _ in range(n):
        cid, fl, np_, w, a0, ln, c0, c1 = struct.unpack_from("<BBHfffff", f, o)
        o += 24
        p = np.frombuffer(f, "<f4", 3 * np_, o).reshape(np_, 3)
        o += 12 * np_
        t["roads"].append({"cid": cid, "fl": fl, "w": w, "a0": a0, "len": ln, "c0": c0, "c1": c1, "p": p})
    n, = struct.unpack_from("<i", f, o)
    o += 4
    for _ in range(n):
        floors, fl, r, g, b, rnd, nv, base, variant = struct.unpack_from("<BBBBBBHfi", f, o)
        o += 16
        kd = struct.unpack_from("<7f", f, o)
        o += 28
        xz = np.frombuffer(f, "<f4", 2 * nv, o).reshape(nv, 2)
        o += 8 * nv
        t["blds"].append({"floors": floors, "fl": fl, "base": base, "variant": variant, "kd": kd, "xz": xz})
    n, = struct.unpack_from("<i", f, o)
    o += 4
    for _ in range(n):
        fl, cid, np_, w = struct.unpack_from("<BBHf", f, o)
        o += 8
        p = np.frombuffer(f, "<f4", 3 * np_, o).reshape(np_, 3)
        o += 12 * np_
        t["walks"].append({"fl": fl, "cid": cid, "w": w, "p": p})
    n, = struct.unpack_from("<i", f, o)
    o += 4
    for _ in range(n):
        nv, = struct.unpack_from("<H", f, o)
        o += 2
        t["junc"].append(np.frombuffer(f, "<f4", 3 * nv, o).reshape(nv, 3))
        o += 12 * nv
    n, = struct.unpack_from("<i", f, o)
    o += 4
    for _ in range(n):
        kind, x, y, z, yaw, size = struct.unpack_from("<B5f", f, o)
        o += 21
        t["props"].append((kind, x, y, z, yaw, size))
    if o < len(f):                                   # CBE5: yards (paving, walls, trees)
        n, = struct.unpack_from("<i", f, o)
        o += 4
        for _ in range(n):
            kind, nv = struct.unpack_from("<BH", f, o)
            o += 3
            t["yards"].append((kind, np.frombuffer(f, "<f4", 3 * nv, o).reshape(nv, 3)))
            o += 12 * nv
    return t
