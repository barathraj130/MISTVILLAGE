"""
Export the pond things for the game (godot/assets/ponds/): the same models as the Blender design (tools/ponds.py)
— reed clumps, water hyacinth and lotus patches, egrets, palmyra, Prosopis scrub, the carved theppakulam — and
the textures the game's materials use (granite, the carved lotus panel's normal map).

    Blender -b --factory-startup --python tools/export_ponds.py
"""
import math
import os
import random
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import export_life as EL  # noqa: E402
import ponds as P  # noqa: E402
import vegetation as VG  # noqa: E402

OUT = os.path.join(HERE, "..", "godot", "assets", "ponds")


def fresh():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    P._M.clear()
    VG._M.clear()
    P._KIT.clear()


def save_png(name, rgba):
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = 'PNG'
    img.save()
    print("TEX", name, flush=True)


def textures():
    n = 512
    y, x = np.mgrid[0:n, 0:n] / n
    rng = np.random.default_rng(3)

    def vnoise(f):
        lat = rng.random((f, f))
        xi, yi = (x * f).astype(int), (y * f).astype(int)
        tx, ty = x * f - xi, y * f - yi
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a, b = lat[yi % f, xi % f], lat[yi % f, (xi + 1) % f]
        c, d = lat[(yi + 1) % f, xi % f], lat[(yi + 1) % f, (xi + 1) % f]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
    g = vnoise(64) * 0.5 + vnoise(128) * 0.3 + vnoise(16) * 0.2
    speck = (vnoise(256) > 0.72) * 0.25
    v = np.clip(0.55 + (g - 0.5) * 1.1 - speck, 0, 1)
    col = np.stack([0.33 * v + 0.05, 0.31 * v + 0.05, 0.29 * v + 0.045, np.ones_like(v)], -1)
    save_png("granite", col)
    # the lotus medallion panel (1.2 m x 0.9 m tile): a height field → a tangent-space normal map
    W, Hh = 600, 450
    yy, xx = np.mgrid[0:Hh, 0:W]
    u, vv = (xx / W - 0.5) * 1.2, (yy / Hh - 0.5) * 0.9
    r = np.hypot(u, vv)
    ang = np.arctan2(vv, u)
    petal = r < 0.27 + 0.05 * np.cos(8 * ang)
    ring = np.abs(r - 0.37) < 0.02
    boss = r < 0.07
    hgt = (petal.astype(float) + ring + boss) * 1.0
    from numpy import gradient
    gy_, gx_ = gradient(hgt)
    k = 3.0
    nx, ny, nz = -gx_ * k, -gy_ * k, np.ones_like(hgt)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nm = np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5, np.ones_like(hgt)], -1)
    save_png("lotus_panel_normal", nm)
    ao = np.stack([0.75 + 0.25 * (hgt > 0)] * 3 + [np.ones_like(hgt)], -1)
    save_png("lotus_panel_ao", ao)


def export(ob, name):
    EL.export_objects([ob], os.path.join(OUT, name + ".glb"))
    print("POND", name, sum(len(p.vertices) - 2 for p in ob.data.polygons), flush=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    fresh()
    textures()
    things = [("reeds_%d" % s, lambda s=s: P.reed_clump(s)) for s in (1, 2, 3)]
    things += [("hyacinth_%d" % s, lambda s=s: P.hyacinth_patch(s, 2.5, 2.6, 7)) for s in (1, 2)]
    things += [("lotus_%d" % s, lambda s=s: P.lotus_patch(s, 3.0, 1.8)) for s in (1, 2)]
    things += [("egret_stand", lambda: P.egret(1, 0)), ("egret_feed", lambda: P.egret(2, 1)), ("palmyra", lambda: P.palmyra(1))]
    things += [("prosopis_%d" % s, lambda s=s: P.prosopis(s)) for s in (1, 2)]
    for name, fn in things:
        fresh()
        export(fn(), name)
    # the theppakulam (steps, parapet, gate, mandapam, lamp pillar), centred, rim at z = 3.6, water at 0
    fresh()
    P.temple()
    tank = bpy.data.objects["Theppakulam"]
    for o in list(bpy.data.objects):
        if o is not tank:
            bpy.data.objects.remove(o, do_unlink=True)
    export(tank, "theppakulam")


if __name__ == "__main__":
    main()
