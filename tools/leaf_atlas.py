"""
Painted leaf atlases and bark for the trees and bushes (tools/vegetation.py) — our own drawings, done with numpy:
each atlas is 2 x 2 cells of 512 px, every cell one leaf spray on a transparent background, drawn upward from the
bottom centre (the twig end). Written to art/leaves/*.png, used by the Blender trees and by the game.

  neem      pinnate leaves: 9-15 curved, saw-edged leaflets on a thin stalk          (cells 0-3)
  rain      bipinnate: a few side stalks, each with rows of small oblong leaflets    (cells 0-3)
  gulmohar  fine fern-like bipinnate fronds (0-2) and a cluster of scarlet flowers   (cell 3)
  bush      hibiscus leaves (0-1), croton leaves green-yellow-red (2), ixora cluster (3)
  bark      1024 x 1024 tileable bark: vertical fissures, plates, lichen spots

    Blender -b --factory-startup --python tools/leaf_atlas.py
"""
import math
import os
import random

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "art", "leaves")
CELL = 512


class Canvas:
    def __init__(self, n=2):
        self.size = CELL * n
        self.rgba = np.zeros((self.size, self.size, 4), np.float32)

    def cell_origin(self, k):
        return (k % 2) * CELL, (k // 2) * CELL           # x, y (y up, as Blender images are stored)

    def blade(self, cx, cy, ang, length, width, col, serr=0.0, tip=0.85, base=0.6, vein=0.18, curl=0.0, rng=None):
        """One leaf blade from (cx, cy) along `ang`: a lens shape, optional saw edge, a lighter midrib,
        darker towards the edge, a soft light-to-dark gradient along it."""
        ca, sa = math.cos(ang), math.sin(ang)
        r = int(length + width) + 2
        x0, x1 = max(int(cx - r), 0), min(int(cx + r), self.size - 1)
        y0, y1 = max(int(cy - r), 0), min(int(cy + r), self.size - 1)
        if x1 <= x0 or y1 <= y0:
            return
        ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1].astype(np.float32)
        dx, dy = xs - cx, ys - cy
        u = (dx * ca + dy * sa) / length                      # 0 at the base, 1 at the tip
        v = (-dx * sa + dy * ca) / width
        v = v - curl * u * u * 1.5                            # a falcate (sickle) curve
        uu = np.clip(u, 0, 1)
        half = np.power(np.sin(np.pi * np.clip(uu, 0, 1) ** base), tip)
        if serr > 0:
            half = half * (1.0 - serr * (0.5 + 0.5 * np.sin(uu * length * 0.9)))
        inside = (u > 0) & (u < 1) & (np.abs(v) < half)
        if not inside.any():
            return
        edge = np.clip(np.abs(v) / np.maximum(half, 1e-3), 0, 1)
        shade = 1.0 - 0.35 * edge ** 2 - 0.12 * uu
        rib = np.exp(-(v / 0.06) ** 2) * vein
        side = np.where(v > 0, 1.0, 0.86)                     # the two halves catch light differently
        c = np.array(col, np.float32)
        out = c[None, None, :] * (shade * side)[..., None] + rib[..., None] * np.array((0.18, 0.2, 0.08))
        sl = self.rgba[y0:y1 + 1, x0:x1 + 1]
        sl[inside, :3] = out[inside]
        sl[inside, 3] = 1.0

    def stalk(self, pts, w, col):
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            n = int(max(abs(bx - ax), abs(by - ay))) + 1
            for i in range(n + 1):
                f = i / n
                x, y = ax + (bx - ax) * f, ay + (by - ay) * f
                r = int(math.ceil(w))
                xa, ya = int(x), int(y)
                sl = self.rgba[max(ya - r, 0):ya + r + 1, max(xa - r, 0):xa + r + 1]
                sl[..., :3] = col
                sl[..., 3] = 1.0

    def save(self, name):
        img = bpy.data.images.new(name, self.size, self.size, alpha=True)
        px = self.rgba.copy()
        # bleed colour into the transparent pixels (no dark fringe when mip-mapped)
        a = px[..., 3] > 0.5
        mean = px[a, :3].mean(axis=0) if a.any() else np.zeros(3)
        px[~a, :3] = mean
        img.pixels.foreach_set(px.ravel())
        os.makedirs(OUT, exist_ok=True)
        img.filepath_raw = os.path.join(OUT, name + ".png")
        img.file_format = 'PNG'
        img.save()
        print("ATLAS", img.filepath_raw, flush=True)


def _green(rng, base, var=0.18):
    k = rng.uniform(1 - var, 1 + var)
    return tuple(min(c * k * rng.uniform(0.93, 1.07), 1) for c in base)


def pinnate(cv, k, rng, n_pairs, leaf_len, leaf_w, base_col, serr, curl, stalk_col, bend=0.25, droop=0.0, alt=0.0):
    """A pinnate leaf: a gently curved stalk up the cell, leaflet pairs along it, one at the tip."""
    ox, oy = cv.cell_origin(k)
    x, y = ox + CELL / 2 + rng.uniform(-20, 20), oy + 18
    L = CELL * 0.88
    ang = math.pi / 2 + rng.uniform(-0.12, 0.12)
    pts = []
    steps = 24
    for i in range(steps + 1):
        pts.append((x, y))
        ang -= bend / steps * (1 if k % 2 else -1)
        x += math.cos(ang) * L / steps
        y += math.sin(ang) * L / steps
    cv.stalk(pts, 2.2, stalk_col)
    for j in range(n_pairs):
        f = 0.12 + 0.82 * j / max(n_pairs - 1, 1)
        i = int(f * steps)
        (ax, ay), (bx, by) = pts[i], pts[min(i + 1, steps)]
        d = math.atan2(by - ay, bx - ax)
        size = leaf_len * (0.75 + 0.35 * math.sin(math.pi * min(f * 1.1, 1)))
        for s in (-1, 1):
            off = alt * s * L / steps
            a2 = d + s * (math.radians(55) + rng.uniform(-0.12, 0.12)) - s * droop
            cv.blade(ax + math.cos(d) * off, ay + math.sin(d) * off, a2, size, leaf_w * size / leaf_len,
                     _green(rng, base_col), serr=serr, curl=curl * s)
    ex, ey = pts[-1]
    d = math.atan2(pts[-1][1] - pts[-2][1], pts[-1][0] - pts[-2][0])
    cv.blade(ex - math.cos(d) * 6, ey - math.sin(d) * 6, d, leaf_len * 0.9, leaf_w * 0.9, _green(rng, base_col), serr=serr)


def bipinnate(cv, k, rng, n_pinnae, pinna_len, n_leaflets, leaflet_len, leaflet_w, base_col, stalk_col, tip=0.6):
    """A twice-divided frond: side stalks (pinnae) off a main stalk, each with rows of small leaflets."""
    ox, oy = cv.cell_origin(k)
    x, y = ox + CELL / 2 + rng.uniform(-15, 15), oy + 16
    L = CELL * 0.86
    ang = math.pi / 2 + rng.uniform(-0.15, 0.15)
    pts = []
    steps = 20
    for i in range(steps + 1):
        pts.append((x, y))
        ang += rng.uniform(-0.03, 0.03)
        x += math.cos(ang) * L / steps
        y += math.sin(ang) * L / steps
    cv.stalk(pts, 1.8, stalk_col)
    for j in range(n_pinnae):
        f = 0.15 + 0.8 * j / max(n_pinnae - 1, 1)
        i = int(f * steps)
        (ax, ay), (bx, by) = pts[i], pts[min(i + 1, steps)]
        d = math.atan2(by - ay, bx - ax)
        plen = pinna_len * (1.0 - 0.45 * f) * rng.uniform(0.9, 1.1)
        for s in (-1, 1):
            a2 = d + s * math.radians(rng.uniform(48, 62))
            q = [(ax + math.cos(a2) * plen * t / 8, ay + math.sin(a2) * plen * t / 8) for t in range(9)]
            cv.stalk(q, 1.0, stalk_col)
            for m in range(n_leaflets):
                g = 0.1 + 0.88 * m / max(n_leaflets - 1, 1)
                px_, py_ = ax + math.cos(a2) * plen * g, ay + math.sin(a2) * plen * g
                ll = leaflet_len * (1.0 - 0.35 * g)
                for s2 in (-1, 1):
                    cv.blade(px_, py_, a2 + s2 * math.radians(rng.uniform(60, 80)), ll, leaflet_w * ll / leaflet_len,
                             _green(rng, base_col, 0.12), tip=tip, base=0.8, vein=0.08)


def flower_cluster(cv, k, rng, petal_col, n=7, leaves=None):
    """A cluster of open flowers (five spoon-shaped petals each) with a few leaves behind, on a short stalk."""
    ox, oy = cv.cell_origin(k)
    cx, cy = ox + CELL / 2, oy + CELL * 0.55
    cv.stalk([(cx, oy + 16), (cx, cy)], 2.4, (0.16, 0.2, 0.07))
    if leaves:
        for j in range(5):
            a = math.pi / 2 + rng.uniform(-1.3, 1.3)
            cv.blade(cx, cy - 40, a, CELL * 0.3, CELL * 0.07, _green(rng, leaves), serr=0.0)
    for j in range(n):
        r = CELL * 0.22 * math.sqrt(rng.random())
        a = rng.uniform(0, math.tau)
        fx, fy = cx + math.cos(a) * r, cy + math.sin(a) * r
        rot = rng.uniform(0, math.tau)
        size = CELL * rng.uniform(0.07, 0.1)
        col = tuple(c * rng.uniform(0.85, 1.1) for c in petal_col)
        for p in range(5):
            pa = rot + p * math.tau / 5
            cv.blade(fx, fy, pa, size, size * 0.55, col, tip=0.5, base=0.5, vein=0.0)
        cv.blade(fx, fy, rot, size * 0.3, size * 0.3, (0.95, 0.8, 0.2), tip=0.5, base=0.5, vein=0.0)


def neem_atlas():
    rng = random.Random(11)
    cv = Canvas()
    for k in range(4):
        pinnate(cv, k, rng, rng.randint(5, 7), CELL * 0.2, CELL * 0.05, (0.13, 0.3, 0.05), serr=0.09, curl=0.25,
                stalk_col=(0.2, 0.26, 0.08), bend=0.35, alt=0.4)
    cv.save("neem")


def rain_atlas():
    rng = random.Random(12)
    cv = Canvas()
    for k in range(4):
        bipinnate(cv, k, rng, 3, CELL * 0.36, 6, CELL * 0.07, CELL * 0.035, (0.12, 0.28, 0.06), (0.18, 0.22, 0.08))
    cv.save("rain")


def gulmohar_atlas():
    rng = random.Random(13)
    cv = Canvas()
    for k in range(3):
        bipinnate(cv, k, rng, 7, CELL * 0.3, 11, CELL * 0.03, CELL * 0.014, (0.16, 0.34, 0.05), (0.2, 0.25, 0.08), tip=0.8)
    flower_cluster(cv, 3, rng, (0.85, 0.12, 0.03), n=9)
    cv.save("gulmohar")


def bush_atlas():
    rng = random.Random(14)
    cv = Canvas()
    for k in range(2):                                   # hibiscus: broad ovate, saw-edged, alternate on a twig
        ox, oy = cv.cell_origin(k)
        cx = ox + CELL / 2
        cv.stalk([(cx, oy + 14), (cx + 10, oy + CELL * 0.85)], 2.2, (0.18, 0.2, 0.08))
        for j in range(6):
            f = 0.15 + 0.13 * j
            s = 1 if j % 2 else -1
            cv.blade(cx + 10 * f, oy + CELL * f, math.pi / 2 + s * rng.uniform(0.6, 0.9), CELL * 0.3, CELL * 0.12,
                     _green(rng, (0.1, 0.26, 0.05)), serr=0.07, tip=0.7, base=0.45)
        cv.blade(cx + 10, oy + CELL * 0.82, math.pi / 2, CELL * 0.17, CELL * 0.07, _green(rng, (0.14, 0.3, 0.06)), serr=0.07)
    ox, oy = cv.cell_origin(2)                          # croton: long leaves, green with yellow and red
    cx, cy = ox + CELL / 2, oy + 30
    for j in range(7):
        a = math.pi / 2 + (j - 3) * 0.28 + rng.uniform(-0.08, 0.08)
        col = rng.choice([(0.55, 0.45, 0.04), (0.6, 0.16, 0.04), (0.12, 0.25, 0.05), (0.4, 0.34, 0.06)])
        cv.blade(cx, cy, a, CELL * rng.uniform(0.6, 0.8), CELL * 0.07, col, tip=0.8, base=0.5, vein=0.5)
    flower_cluster(cv, 3, rng, (0.9, 0.2, 0.08), n=14, leaves=(0.1, 0.24, 0.05))   # ixora (red-orange heads)
    cv.save("bush")


def bark():
    rng = np.random.default_rng(5)
    n = 1024
    # tileable value noise from random lattices (wrapped), stretched along the trunk (y)
    def noise(fx, fy, oct_=4):
        acc = np.zeros((n, n), np.float32)
        amp = 1.0
        for o in range(oct_):
            gx, gy = fx * 2 ** o, fy * 2 ** o
            lat = rng.random((gy, gx)).astype(np.float32)
            ys = np.linspace(0, gy, n, endpoint=False)
            xs = np.linspace(0, gx, n, endpoint=False)
            yi, xi = ys.astype(int), xs.astype(int)
            ty, tx = (ys - yi)[:, None], (xs - xi)[None, :]
            ty, tx = ty * ty * (3 - 2 * ty), tx * tx * (3 - 2 * tx)
            a = lat[yi % gy][:, xi % gx]
            b = lat[yi % gy][:, (xi + 1) % gx]
            c = lat[(yi + 1) % gy][:, xi % gx]
            d = lat[(yi + 1) % gy][:, (xi + 1) % gx]
            acc += amp * ((a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty)
            amp *= 0.5
        return acc / (2 - 2 ** (1 - oct_))
    fiss = noise(24, 4)                       # long vertical fissures
    plates = noise(10, 6)
    fine = noise(64, 64, 3)
    ridge = 1.0 - np.abs(fiss * 2 - 1)
    h = np.clip(ridge ** 2.2 * 0.75 + plates * 0.2 + fine * 0.15, 0, 1)
    base = np.array((0.24, 0.19, 0.15), np.float32)
    dark = np.array((0.06, 0.045, 0.035), np.float32)
    col = dark[None, None, :] + (base - dark)[None, None, :] * h[..., None]
    lich = noise(14, 14, 3)
    m = np.clip((lich - 0.68) * 6, 0, 1)[..., None] * 0.5
    col = col * (1 - m) + np.array((0.33, 0.33, 0.27), np.float32)[None, None, :] * m
    rgba = np.concatenate([col, np.ones((n, n, 1), np.float32)], axis=2)
    img = bpy.data.images.new("bark", n, n, alpha=False)
    img.pixels.foreach_set(rgba.ravel())
    os.makedirs(OUT, exist_ok=True)
    img.filepath_raw = os.path.join(OUT, "bark.png")
    img.file_format = 'PNG'
    img.save()
    print("ATLAS", img.filepath_raw, flush=True)


def main():
    neem_atlas()
    rain_atlas()
    gulmohar_atlas()
    bush_atlas()
    bark()


if __name__ == "__main__":
    main()
