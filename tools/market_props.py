"""
A street vegetable market's things, for the story's market scene (STORY_BIBLE.md Act 3: Ganapathy market), each its
own glb in godot/assets/city_props (market_*.glb), with its textures painted here (godot/assets/city_props/tex,
market_*.png: wood grain, worn and patched tarpaulin, woven palm, rusted iron, jute, coconut husk):

  market_vegcart     a wooden push cart on two rusted spoked wheels, its sloped board overflowing by kind
                     (tomatoes, small onions, potatoes, green chillies, beans, carrots with their tops, cabbages,
                     cauliflowers, drumsticks, bottle gourds, ginger and garlic), a faded patched blue tarpaulin
                     sagging over bamboo poles and roped to them, a brass hand-scale hanging, a tin of weights
  market_groundstall a worn tarpaulin on the ground, two tiers of woven palm baskets (keerai and curry-leaf
                     bundles, brinjals, ladies' fingers, lemons, bitter gourds, coconuts), two open jute sacks of
                     onions and potatoes, a steel bowl of change, the seller's low stool, a faded umbrella over it
  market_banana      a bamboo frame hung with banana bunches, yellow and green, a heap of coconuts and a bunch of
                     plantain leaves beneath, an old cloth roof tied over it
  market_crates      plastic crates stacked three high, red and blue, the open ones heaped with tomatoes, onions
                     and potatoes, a sack leaning on them

Real produce from Poly Haven's CC0 scans (third_party/polyhaven/<id>, the 1k glTF from
https://api.polyhaven.com/files/<id>, not in git): yellow_onion, food_ginger_01, lemon, food_lime_01, sweet_potato,
bananas; each cut down to a few hundred triangles. Plants the same way: island_tree_02 (the tree by the Pudhur
hut, its trunk and branches decimated, its leaf cards thinned and grown), shrub_02, shrub_04, grass_medium_01,
weed_plant_02. The rest is painted here.

    Blender -b --factory-startup --python tools/market_props.py -- [--preview previews/market]
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "godot", "assets", "city_props")
TEX = os.path.join(OUT, "tex")
R = random.Random(7)
NP = np.random.default_rng(7)


# ---- textures ----
def _smooth_noise(n, cells, seed):
    g = np.random.default_rng(seed).random((cells + 1, cells + 1))
    t = np.linspace(0, cells, n, endpoint=False)
    i = t.astype(int)
    f = t - i
    f = f * f * (3 - 2 * f)
    a = g[i][:, i] * (1 - f)[None, :] + g[i][:, i + 1] * f[None, :]
    b = g[i + 1][:, i] * (1 - f)[None, :] + g[i + 1][:, i + 1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def _fbm(n, seed, base=4, octaves=4):
    out = np.zeros((n, n))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * _smooth_noise(n, base * 2 ** o, seed + o)
        tot += amp
        amp *= 0.5
    return out / tot


def _save(name, rgb):
    os.makedirs(TEX, exist_ok=True)
    n = rgb.shape[0]
    img = bpy.data.images.new("market_" + name, n, n)
    rgba = np.ones((n, n, 4))
    rgba[:, :, :3] = np.clip(rgb, 0, 1)
    img.pixels = rgba[::-1].ravel()
    path = os.path.join(TEX, "market_%s.png" % name)
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    return path


def _save_rgba(name, rgba):
    os.makedirs(TEX, exist_ok=True)
    n = rgba.shape[0]
    img = bpy.data.images.new("market_" + name, n, n, alpha=True)
    img.pixels = np.clip(rgba, 0, 1)[::-1].ravel()
    path = os.path.join(TEX, "market_%s.png" % name)
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    return path


def make_textures():
    n = 512
    T = {}
    y, x = np.mgrid[0:n, 0:n] / n
    # wood: long grain along x, knots, sun-greyed
    grain = np.sin((y * 90 + _fbm(n, 1, 3) * 10) * math.pi) * 0.5 + 0.5
    wood = np.array([0.3, 0.19, 0.11]) * (0.7 + 0.4 * grain[:, :, None]) * (0.8 + 0.35 * _fbm(n, 2, 6)[:, :, None])
    wood = wood * (1 - 0.35 * (_fbm(n, 5, 20) > 0.7)[:, :, None])              # dark grime in the grain
    paint = _fbm(n, 6, 7)                                                       # old green paint, mostly flaked off
    flake = (paint > 0.6) & (_fbm(n, 7, 30) > 0.45)
    wood[flake] = np.array([0.22, 0.42, 0.34]) * (0.8 + 0.3 * _fbm(n, 8, 12)[flake][:, None])
    T["wood"] = _save("wood", wood)
    # rusted iron
    rust = _fbm(n, 3, 5)
    iron = np.where((rust > 0.55)[:, :, None], np.array([0.45, 0.22, 0.1]), np.array([0.14, 0.13, 0.13]))
    T["iron"] = _save("iron", iron * (0.8 + 0.4 * _fbm(n, 4, 12)[:, :, None]))
    # tarpaulins: faded, stained, creased, a sewn patch of another colour
    def tarp(base, patch, seed):
        t = np.array(base) * (0.8 + 0.35 * _fbm(n, seed, 3)[:, :, None])
        t = t * (1 - 0.25 * (_fbm(n, seed + 10, 8) > 0.68)[:, :, None])           # stains
        t = t + 0.18 * (_fbm(n, seed + 20, 2)[:, :, None] - 0.4).clip(0, 1)       # sun-faded
        crease = np.abs(np.sin((x * 9 + y * 2 + _fbm(n, seed + 30, 4)) * math.pi))
        t = t * (0.9 + 0.1 * crease[:, :, None])
        for (x0, y0, w, h) in ((0.12, 0.18, 0.22, 0.16), (0.62, 0.6, 0.18, 0.22)):
            m = (x > x0) & (x < x0 + w) & (y > y0) & (y < y0 + h)
            t[m] = np.array(patch) * (0.85 + 0.2 * _fbm(n, seed + 40, 6)[m][:, None])
            edge = m & ((np.abs(x - x0) < 0.006) | (np.abs(x - x0 - w) < 0.006) | (np.abs(y - y0) < 0.006) | (np.abs(y - y0 - h) < 0.006))
            t[edge] = 0.85
        return t
    T["tarp_blue"] = _save("tarp_blue", tarp((0.12, 0.3, 0.62), (0.78, 0.42, 0.1), 50))
    T["tarp_orange"] = _save("tarp_orange", tarp((0.82, 0.42, 0.12), (0.1, 0.28, 0.6), 60))
    T["umbrella"] = _save("umbrella", tarp((0.7, 0.15, 0.12), (0.85, 0.75, 0.3), 70))
    T["cloth"] = _save("cloth", tarp((0.6, 0.55, 0.42), (0.35, 0.45, 0.25), 80))
    # woven palm leaf: strips over and under
    wx = x * 64 + _fbm(n, 91, 3) * 1.6                                         # strips, a little uneven
    wy = y * 64 + _fbm(n, 92, 3) * 1.6
    over = (np.floor(wx) + np.floor(wy)) % 2
    shade = NP.uniform(0.75, 1.1, 70)
    strip = np.where(over > 0, shade[np.floor(wx).astype(int) % 70], shade[np.floor(wy).astype(int) % 70])
    palm = np.where(over[:, :, None] > 0, np.array([0.68, 0.55, 0.32]), np.array([0.56, 0.43, 0.24])) * strip[:, :, None]
    palm = palm * (0.85 + 0.25 * _fbm(n, 90, 10)[:, :, None])
    palm[(np.abs(wx % 1 - 0.5) > 0.44) | (np.abs(wy % 1 - 0.5) > 0.44)] *= 0.55
    T["palm"] = _save("palm", palm)
    # jute sacking: a coarse weave
    w = (np.sin(x * 2 * math.pi * 80) * np.sin(y * 2 * math.pi * 80)) * 0.5 + 0.5
    T["jute"] = _save("jute", np.array([0.55, 0.43, 0.28]) * (0.75 + 0.3 * w[:, :, None]) * (0.85 + 0.25 * _fbm(n, 100, 8)[:, :, None]))
    # coconut husk: brown fibre streaks
    husk = np.sin((x * 40 + _fbm(n, 110, 6) * 6) * math.pi) * 0.5 + 0.5
    grime = np.array([0.66, 0.63, 0.55]) * (0.82 + 0.25 * _fbm(n, 120, 3)[:, :, None])
    grime = grime * (1 - 0.35 * np.clip((y - 0.55) * 2.2, 0, 1)[:, :, None] * _fbm(n, 121, 8)[:, :, None])   # oily up from the floor
    hand = (_fbm(n, 122, 14) > 0.72) & (y > 0.35) & (y < 0.6)                    # handprints by the bench
    grime[hand] *= 0.55
    T["grime"] = _save("grime", grime)
    # the site: stained plaster, a faded peeling hoarding, red earth with weeds and the tyre tracks of two cars
    pl = np.array([0.84, 0.8, 0.7]) * (0.85 + 0.2 * _fbm(n, 130, 4)[:, :, None])
    streak = np.clip(np.sin(x * 2 * math.pi * 9 + _fbm(n, 131, 3) * 4) * 0.5 + 0.5, 0, 1) * np.clip(y * 1.3, 0, 1)
    pl = pl * (1 - 0.3 * (streak ** 6)[:, :, None]) * (1 - 0.25 * (_fbm(n, 132, 10) > 0.7)[:, :, None])
    chip = _fbm(n, 133, 18) > 0.78
    pl[chip] = np.array([0.55, 0.45, 0.38])
    T["plaster_stained"] = _save("plaster_stained", pl)
    ho = np.array([0.2, 0.46, 0.3]) * (0.75 + 0.35 * _fbm(n, 140, 3)[:, :, None])
    ho = ho + 0.25 * np.clip(_fbm(n, 141, 2) - 0.45, 0, 1)[:, :, None]            # sun-faded towards one corner
    peel = (_fbm(n, 142, 6) > 0.66) & (y > 0.5)
    ho[peel] = np.array([0.85, 0.83, 0.78]) * (0.9 + 0.1 * _fbm(n, 143, 20)[peel][:, None])
    T["hoarding"] = _save("hoarding", ho)
    ea = np.array([0.52, 0.37, 0.27]) * (0.8 + 0.3 * _fbm(n, 150, 5)[:, :, None])       # dusty, sun-bleached
    path = np.abs(x - (0.5 + 0.25 * y + 0.04 * np.sin(y * 9))) < 0.03 + 0.01 * _fbm(n, 153, 6)   # a footpath worn to the hut
    ea[path] = ea[path] * 1.25 + 0.04
    weeds = (_fbm(n, 151, 24) > 0.68)
    ea[weeds] = np.array([0.32, 0.4, 0.18]) * (0.8 + 0.3 * _fbm(n, 152, 30)[weeds][:, None])
    for (c0, c1, k0) in ((0.42, 0.47, 0.0), (0.53, 0.58, 0.3)):               # two cars' tracks, curving in at the gate
        bend = 0.08 * np.sin(y * 3.0 + k0)
        for off in (0.0, 0.035):
            band = (np.abs(x - (c0 + bend + off)) < 0.008) & (y < 0.75)
            ea[band] *= 0.55
    T["earth_site"] = _save("earth_site", ea)
    tape = np.ones((n, n, 3)) * np.array([0.95, 0.8, 0.1])
    tape[(np.floor((x + y) * 24) % 2) == 0] = 0.08
    T["tape"] = _save("tape", tape * (0.7 + 0.35 * _fbm(n, 160, 4)[:, :, None]))
    pb = np.zeros((n, n, 3))
    blade = np.sin(x * 2 * math.pi * 70 + _fbm(n, 170, 4) * 6) * 0.5 + 0.5
    tip = np.clip(1 - y * 1.1, 0, 1)                                        # lighter at the tips, darker at the water
    pb[:] = np.array([0.22, 0.48, 0.14])
    pb = pb * (0.6 + 0.5 * blade[:, :, None]) * (0.65 + 0.5 * tip[:, :, None]) * (0.85 + 0.25 * _fbm(n, 171, 8)[:, :, None])
    pb = pb + np.array([0.12, 0.08, 0.0]) * (_fbm(n, 172, 3) > 0.6)[:, :, None] * tip[:, :, None]   # yellowing patches
    T["paddy"] = _save("paddy", pb)
    lu = np.ones((n, n, 3)) * np.array([0.15, 0.3, 0.55])
    lu[(np.floor(x * 16) % 4) == 0] = np.array([0.1, 0.45, 0.3])
    lu[(np.floor(y * 16) % 4) == 0] = np.array([0.1, 0.45, 0.3])
    lu[((np.floor(x * 16) % 4) == 0) & ((np.floor(y * 16) % 4) == 0)] = np.array([0.85, 0.82, 0.7])
    T["lungi"] = _save("lungi", lu * (0.85 + 0.2 * _fbm(n, 180, 6)[:, :, None]))
    rw = (np.sin(x * 2 * math.pi * 40) * np.sin(y * 2 * math.pi * 40)) * 0.5 + 0.5
    T["rope_weave"] = _save("rope_weave", np.array([0.75, 0.65, 0.45]) * (0.7 + 0.35 * rw[:, :, None]))
    bk = np.array([0.36, 0.3, 0.25]) * (0.6 + 0.5 * (np.sin((x * 30 + _fbm(n, 190, 4) * 5) * math.pi) * 0.5 + 0.5))[:, :, None]
    bk = bk * (0.8 + 0.3 * _fbm(n, 191, 12)[:, :, None]) * (1 - 0.4 * (_fbm(n, 192, 6) > 0.72)[:, :, None])   # fissures, knots
    T["bark_neem"] = _save("bark_neem", bk)
    ring = np.sin(y * 2 * math.pi * 30 + _fbm(n, 193, 3) * 2) * 0.5 + 0.5
    T["bark_palm"] = _save("bark_palm", np.array([0.5, 0.45, 0.38]) * (0.65 + 0.4 * (ring ** 3)[:, :, None]) * (0.85 + 0.2 * _fbm(n, 194, 8)[:, :, None]))
    # a coconut frond: the rib down the middle, leaflets slanting out to both sides, cut out (alpha)
    fr = np.zeros((n, n, 4))
    rib = np.abs(x - 0.5) < 0.012
    leaflets = np.zeros((n, n), bool)
    for k in range(48):
        yy0 = 0.03 + k * 0.02
        for side in (-1, 1):
            u = (x - 0.5) * side
            along = yy0 + u * 0.45
            leaflets |= (u > 0) & (u < 0.48 * (1 - 0.6 * yy0)) & (np.abs(y - along) < 0.006 + 0.004 * (1 - u * 2))
    col = np.array([0.32, 0.45, 0.2]) * (0.75 + 0.35 * _fbm(n, 195, 6)[:, :, None])
    fr[..., :3] = np.where(rib[:, :, None], np.array([0.6, 0.6, 0.35]), col)
    fr[..., 3] = (rib | leaflets).astype(float)
    T["frond"] = _save_rgba("frond", fr)
    T["husk"] = _save("husk", np.array([0.42, 0.27, 0.13]) * (0.7 + 0.45 * husk[:, :, None]))
    # skins, on a UV sphere's map (the top rows are the top of the fruit)
    m = 256
    yy, xx = np.mgrid[0:m, 0:m] / m
    def skin(name, base, top=None, top_k=0.18, streak=0.0, speck=0.0, vein=0.0, seed=0):
        for i, f in enumerate((0.85, 1.0, 1.12)):
            t = np.array(base) * f * (0.88 + 0.2 * _fbm(m, seed + i, 4)[:, :, None])
            if top is not None:                                               # the stalk end ripens last
                k = np.clip(1 - yy / top_k, 0, 1)[:, :, None]
                t = t * (1 - k) + np.array(top) * k
            if streak:
                t = t * (1 - streak + streak * (np.sin(xx * 2 * math.pi * 14 + _fbm(m, seed + 9, 3) * 3) * 0.5 + 0.5))[:, :, None]
            if speck:
                sp = NP.random((m, m)) > 1 - speck
                t[sp] = t[sp] * 0.6 + 0.4
            if vein:
                v = np.abs(np.sin((xx * 3 + yy * 10) * math.pi)) < vein
                t[v] = t[v] * 1.25
            T["%s_%d" % (name, i)] = _save("%s_%d" % (name, i), t)
    skin("tomato", (0.72, 0.09, 0.05), (0.85, 0.45, 0.1), 0.12, 0.0, 0.004, seed=200)
    skin("brinjal", (0.25, 0.05, 0.28), None, 0, 0.25, 0.0, seed=210)
    skin("chilli", (0.12, 0.44, 0.09), None, 0, 0.3, 0.0, seed=220)
    skin("beans", (0.3, 0.55, 0.18), None, 0, 0.35, 0.002, seed=230)
    skin("okra", (0.35, 0.58, 0.2), None, 0, 0.5, 0.003, seed=240)
    skin("potato", (0.6, 0.47, 0.3), None, 0, 0.0, 0.02, seed=250)
    skin("leaf", (0.15, 0.42, 0.12), None, 0, 0.0, 0.0, 0.04, seed=260)
    skin("greens", (0.1, 0.36, 0.09), None, 0, 0.0, 0.0, 0.05, seed=270)
    skin("cabbage", (0.6, 0.76, 0.45), None, 0, 0.0, 0.0, 0.03, seed=280)
    skin("carrot", (0.88, 0.4, 0.07), None, 0, 0.2, 0.0, seed=290)
    skin("gourd", (0.55, 0.7, 0.4), None, 0, 0.12, 0.004, seed=300)
    # the shop's QR code card: a white card, a black-and-white square pattern (no bank, no app: a made-up code)
    q = np.ones((m, m, 3))
    cells = 29
    grid = NP.random((cells, cells)) > 0.5
    for (r0, c0) in ((0, 0), (0, cells - 7), (cells - 7, 0)):               # the three finder squares
        grid[r0:r0 + 7, c0:c0 + 7] = True
        grid[r0 + 1:r0 + 6, c0 + 1:c0 + 6] = False
        grid[r0 + 2:r0 + 5, c0 + 2:c0 + 5] = True
    pad = 40
    cs = (m - 2 * pad) / cells
    for r in range(cells):
        for c in range(cells):
            if grid[r, c]:
                q[int(pad + r * cs):int(pad + (r + 1) * cs), int(pad + c * cs):int(pad + (c + 1) * cs)] = 0.05
    q[:24] = np.array([0.95, 0.5, 0.1])
    T["qr"] = _save("qr", q)
    # the fair: showroom paint with a bloom of dust low down and scuffs, rubber, artificial turf, the forecourt's pavers,
    # gazebo canvas with its seams and creases
    for key, col in (("paint_red", (0.62, 0.06, 0.04)), ("paint_blue", (0.08, 0.22, 0.55)), ("paint_orange", (0.85, 0.32, 0.05)),
                     ("paint_green", (0.1, 0.42, 0.14)), ("paint_grey", (0.16, 0.16, 0.17))):
        pt = np.array(col) * (0.92 + 0.12 * _fbm(n, 200, 3)[:, :, None])
        dust = np.clip((y - 0.55) * 2.2, 0, 1) * _fbm(n, 201, 10)                  # dust thrown up on the lower half
        pt = pt * (1 - 0.35 * dust[:, :, None]) + np.array([0.55, 0.45, 0.35]) * 0.35 * dust[:, :, None]
        scuff = (_fbm(n, 202, 40) > 0.74) & (_fbm(n, 203, 6) > 0.55)
        pt[scuff] = pt[scuff] * 0.75 + 0.08
        T[key] = _save(key, pt)
    ru = np.array([0.055, 0.053, 0.05]) * (0.8 + 0.4 * _fbm(n, 210, 16)[:, :, None])
    ru = ru + np.array([0.3, 0.24, 0.18]) * 0.25 * (_fbm(n, 211, 5) > 0.62)[:, :, None]   # red dust in the lugs
    T["rubber"] = _save("rubber", ru)
    tu = np.array([0.16, 0.42, 0.12]) * (0.7 + 0.5 * NP.random((n, n))[:, :, None]) * (0.85 + 0.25 * _fbm(n, 220, 5)[:, :, None])
    worn = np.abs(x - 0.5 - 0.05 * np.sin(y * 6)) < 0.12 * _fbm(n, 221, 3)          # trodden flat down the middle
    tu[worn] = tu[worn] * 0.8 + np.array([0.12, 0.18, 0.08])
    T["turf"] = _save("turf", tu)
    pv = np.array([0.6, 0.57, 0.52]) * (0.8 + 0.25 * _fbm(n, 230, 6)[:, :, None])
    bx, by = (x * 8) % 1, (y * 16) % 1
    off = (np.floor(y * 16) % 2) * 0.5
    bx = (x * 8 + off) % 1
    joint = (bx < 0.04) | (by < 0.08)
    pv[joint] = np.array([0.32, 0.3, 0.27])
    tone = _smooth_noise(n, 64, 231)
    pv[~joint] *= (0.9 + 0.2 * tone[~joint])[:, None]
    pv *= (1 - 0.3 * (_fbm(n, 232, 8) > 0.72))[:, :, None]                          # oil and tyre marks
    T["pavers"] = _save("pavers", pv)
    for key, col in (("canvas_white", (0.92, 0.92, 0.9)), ("canvas_orange", (0.9, 0.42, 0.1)), ("canvas_green", (0.12, 0.45, 0.2))):
        cv = np.array(col) * (0.88 + 0.12 * _fbm(n, 240, 4)[:, :, None])
        crease = np.abs(np.sin((x * 5 + _fbm(n, 241, 3) * 2) * math.pi)) ** 12
        cv *= (1 - 0.12 * crease)[:, :, None]
        seam = (np.abs(x - 0.5) < 0.004) | (np.abs(y - 0.5) < 0.004)
        cv[seam] *= 0.8
        cv *= (1 - 0.15 * np.clip(1 - y * 5, 0, 1) * _fbm(n, 242, 8))[:, :, None]   # grubby along one edge
        T[key] = _save(key, cv)
    # the booths' posters and the TV's picture: a paddy field under the sky, drip lines in a field, seed packets, solar panels
    def sky_field(seed, field_col):
        im = np.zeros((n, n, 3))
        sky = np.array([0.45, 0.65, 0.92]) * (1 - 0.4 * y[:, :, None]) + np.array([0.95, 0.95, 0.9]) * 0.4 * y[:, :, None]
        im[:] = sky
        hor = 0.45 + 0.03 * np.sin(x * 20) * _fbm(n, seed, 4)
        trees = (y > hor - 0.05 - 0.05 * (_fbm(n, seed + 1, 14) > 0.5)) & (y < hor)
        im[trees] = np.array([0.12, 0.25, 0.1])
        g = y >= hor
        rows = np.sin((x - 0.5) / np.maximum(y - 0.3, 0.05) * 60) * 0.5 + 0.5
        im[g] = (np.array(field_col) * (0.7 + 0.4 * rows[:, :, None]))[g]
        return im, g, rows
    pf, g, rows = sky_field(250, (0.3, 0.6, 0.15))
    T["poster_field"] = _save("poster_field", pf)
    pd, g, rows = sky_field(252, (0.45, 0.3, 0.2))
    pipe = g & (np.abs(np.sin((x - 0.5) / np.maximum(y - 0.3, 0.05) * 30)) < 0.06)
    pd[pipe] = 0.05
    sprout = g & (_fbm(n, 253, 60) > 0.66) & ~pipe
    pd[sprout] = np.array([0.2, 0.55, 0.15])
    T["poster_drip"] = _save("poster_drip", pd)
    ps = np.ones((n, n, 3)) * 0.95
    cols = np.array([(0.9, 0.7, 0.1), (0.2, 0.6, 0.25), (0.85, 0.3, 0.15), (0.3, 0.45, 0.8), (0.6, 0.2, 0.5), (0.95, 0.5, 0.1)])
    cx, cy = (x * 4).astype(int), (y * 3).astype(int)
    inside = ((x * 4) % 1 > 0.08) & ((x * 4) % 1 < 0.92) & ((y * 3) % 1 > 0.08) & ((y * 3) % 1 < 0.92)
    ps[inside] = cols[(cx + cy * 4)[inside] % 6]
    leafy = inside & ((((x * 4) % 1 - 0.5) ** 2 + (((y * 3) % 1) - 0.45) ** 2) < 0.06)
    ps[leafy] = np.array([0.15, 0.5, 0.12]) * (0.8 + 0.4 * _fbm(n, 254, 20)[leafy][:, None])
    T["poster_seeds"] = _save("poster_seeds", ps)
    so, g, rows = sky_field(256, (0.35, 0.55, 0.2))
    panel = (y > 0.2) & (y < 0.75) & (x > 0.15) & (x < 0.85) & (y > 0.2 + 0.3 * (x - 0.15))
    so[panel] = np.array([0.08, 0.15, 0.35])
    cell = panel & ((((x * 20) % 1) < 0.06) | (((y * 20) % 1) < 0.06))
    so[cell] = 0.75
    T["poster_solar"] = _save("poster_solar", so)
    tv, g, rows = sky_field(258, (0.32, 0.6, 0.16))
    trac = ((x - 0.55) ** 2 / 0.02 + (y - 0.62) ** 2 / 0.004 < 1) | ((x > 0.5) & (x < 0.66) & (y > 0.52) & (y < 0.62))
    tv[trac] = np.array([0.75, 0.08, 0.05])
    for wx, wy, wr in ((0.48, 0.66, 0.05), (0.64, 0.68, 0.03)):
        tv[(x - wx) ** 2 + (y - wy) ** 2 < wr ** 2] = 0.05
    T["tv_screen"] = _save("tv_screen", tv)
    te = np.array([0.66, 0.32, 0.2]) * (0.8 + 0.3 * _fbm(n, 260, 6)[:, :, None])
    tj = ((x * 16) % 1 < 0.05) | ((y * 4) % 1 < 0.06)
    te[tj] = np.array([0.75, 0.72, 0.66])
    te *= (1 - 0.2 * np.clip((y - 0.6) * 2.5, 0, 1) * _fbm(n, 261, 10))[:, :, None]   # rain streaks low down
    T["hall_terra"] = _save("hall_terra", te)
    # the shops: a rolling shutter's ribs, greyed and streaked; the boards' pictures (a phone, a plate of sweets, a
    # green cross, a key); an umbrella's sun-faded cloth
    sh = np.array([0.5, 0.51, 0.52]) * (0.75 + 0.25 * (np.sin(y * math.pi * 60) * 0.5 + 0.5))[:, :, None]
    sh *= (0.85 + 0.2 * _fbm(n, 270, 5))[:, :, None]
    sh *= (1 - 0.25 * np.clip((y - 0.6) * 3, 0, 1) * (_fbm(n, 271, 9) > 0.55))[:, :, None]
    T["shutter"] = _save("shutter", sh)
    for key, bg in (("pic_phone", (0.95, 0.95, 0.97)), ("pic_sweets", (0.98, 0.92, 0.75)), ("pic_cross", (0.96, 0.98, 0.96)), ("pic_key", (0.9, 0.93, 0.98))):
        im = np.ones((n, n, 3)) * np.array(bg)
        cx, cy = x - 0.5, y - 0.5
        if key == "pic_phone":
            body = (np.abs(cx) < 0.2) & (np.abs(cy) < 0.38)
            im[body] = 0.08
            scr = (np.abs(cx) < 0.17) & (np.abs(cy) < 0.32)
            im[scr] = (np.array([0.2, 0.45, 0.95]) * (1 - y[:, :, None] * 0.6) + np.array([0.9, 0.3, 0.6]) * y[:, :, None] * 0.6)[scr]
        elif key == "pic_sweets":
            plate = cx ** 2 + (cy * 1.6) ** 2 < 0.16
            im[plate] = np.array([0.85, 0.85, 0.8])
            for k, (px, py, col) in enumerate(((-0.15, -0.05, (0.95, 0.75, 0.2)), (0.1, -0.08, (0.9, 0.5, 0.15)), (-0.02, 0.08, (0.95, 0.9, 0.7)),
                                                (0.18, 0.06, (0.6, 0.35, 0.15)), (-0.2, 0.08, (0.95, 0.6, 0.6)))):
                im[(cx - px) ** 2 + (cy - py) ** 2 < 0.007] = np.array(col)
        elif key == "pic_cross":
            cr = ((np.abs(cx) < 0.1) & (np.abs(cy) < 0.32)) | ((np.abs(cy) < 0.1) & (np.abs(cx) < 0.32))
            im[cr] = np.array([0.1, 0.65, 0.3])
        else:
            bow = (cx + 0.18) ** 2 + cy ** 2 < 0.03
            hole = (cx + 0.18) ** 2 + cy ** 2 < 0.008
            blade = (cx > -0.05) & (cx < 0.35) & (np.abs(cy) < 0.04)
            teeth = (cx > 0.12) & (cx < 0.35) & (cy > 0.0) & (cy < 0.09) & (np.sin(cx * 90) > 0)
            im[bow | blade | teeth] = np.array([0.78, 0.62, 0.25])
            im[hole] = np.array(bg)
        T[key] = _save(key, im)
    for key, col in (("umb_red", (0.72, 0.16, 0.12)), ("umb_blue", (0.12, 0.32, 0.72)), ("umb_black", (0.07, 0.07, 0.08))):
        um = np.array(col) * (0.85 + 0.2 * _fbm(n, 280, 3)[:, :, None])
        um = um + 0.15 * np.clip(_fbm(n, 281, 2)[:, :, None] - 0.4, 0, 1)           # sun-faded
        um *= (1 - 0.15 * (_fbm(n, 282, 10) > 0.7))[:, :, None]                   # stains
        T[key] = _save(key, um)
    return T


# ---- materials ----
def mat(name, colour, rough=0.6, metal=0.0, alpha=1.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*colour, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if alpha < 1.0:                                                           # (glass: the jars show what's in them)
        b.inputs["Alpha"].default_value = alpha
        m.surface_render_method = 'BLENDED'
    return m


def tmat(name, path, rough=0.8, metal=0.0, cutout=False):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    im = nt.nodes.new("ShaderNodeTexImage")
    im.image = bpy.data.images.load(path, check_existing=True)
    nt.links.new(im.outputs["Color"], b.inputs["Base Color"])
    if cutout:                                                                # (leaves: the shape in the picture)
        nt.links.new(im.outputs["Alpha"], b.inputs["Alpha"])
        m.surface_render_method = 'DITHERED'
        m.use_backface_culling = False
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def variants(name, colour, spread=0.12, k=4, rough=0.45):
    """A few shades of one thing, so a heap isn't one colour."""
    out = []
    for i in range(k):
        f = 1.0 + spread * (i - (k - 1) / 2) / ((k - 1) / 2)
        hue = (0.0, 0.03 * (i % 2), 0.0)
        out.append(mat("%s_%d" % (name, i), tuple(min(1.0, max(0.0, c * f + h)) for c, h in zip(colour, hue)), rough))
    return out


M = {}


T_ALL = {}


def mats(T):
    T_ALL.update(T)
    M.update({
        "wood": tmat("mk_wood", T["wood"], 0.85), "iron": tmat("mk_iron", T["iron"], 0.6, 0.4),
        "tarp_blue": tmat("mk_tarp_blue", T["tarp_blue"], 0.6), "tarp_orange": tmat("mk_tarp_orange", T["tarp_orange"], 0.65),
        "umbrella": tmat("mk_umbrella", T["umbrella"], 0.7), "cloth": tmat("mk_cloth", T["cloth"], 0.85),
        "palm": tmat("mk_palm", T["palm"], 0.9), "jute": tmat("mk_jute", T["jute"], 0.95), "husk": tmat("mk_husk", T["husk"], 0.9),
        "bamboo": mat("mk_bamboo", (0.66, 0.55, 0.32), 0.7), "rope": mat("mk_rope", (0.7, 0.62, 0.45), 0.9),
        "brass": mat("mk_brass", (0.72, 0.55, 0.24), 0.35, 0.8), "steel": mat("mk_steel", (0.75, 0.76, 0.78), 0.3, 0.8),
        "string": mat("mk_string", (0.85, 0.82, 0.7), 0.9), "stem": mat("mk_stem", (0.2, 0.35, 0.12), 0.7),
        "tomato": variants("mk_tomato", (0.75, 0.1, 0.05), 0.18), "onion": variants("mk_onion", (0.6, 0.24, 0.32), 0.2),
        "potato": variants("mk_potato", (0.62, 0.48, 0.3), 0.15, rough=0.85), "chilli": variants("mk_chilli", (0.14, 0.48, 0.1), 0.2),
        "beans": variants("mk_beans", (0.32, 0.58, 0.2), 0.2), "carrot": variants("mk_carrot", (0.9, 0.4, 0.07), 0.12),
        "leaf": variants("mk_leaf", (0.18, 0.45, 0.14), 0.25, rough=0.6), "cabbage": variants("mk_cabbage", (0.6, 0.76, 0.45), 0.12),
        "cauli": variants("mk_cauli", (0.93, 0.9, 0.8), 0.06, rough=0.8), "gourd": variants("mk_gourd", (0.55, 0.7, 0.4), 0.15),
        "bitter": variants("mk_bitter", (0.2, 0.42, 0.12), 0.2), "ginger": variants("mk_ginger", (0.72, 0.58, 0.38), 0.1, rough=0.85),
        "garlic": variants("mk_garlic", (0.92, 0.88, 0.82), 0.05, rough=0.7), "drumstick": variants("mk_drumstick", (0.32, 0.46, 0.2), 0.15),
        "greens": variants("mk_greens", (0.12, 0.38, 0.1), 0.25, rough=0.6), "curry": variants("mk_curry", (0.08, 0.3, 0.08), 0.2),
        "lemon": variants("mk_lemon", (0.92, 0.82, 0.22), 0.1), "brinjal": variants("mk_brinjal", (0.3, 0.08, 0.32), 0.25, rough=0.25),
        "okra": variants("mk_okra", (0.38, 0.6, 0.22), 0.15), "banana_y": variants("mk_banana_y", (0.93, 0.78, 0.18), 0.1),
        "banana_g": variants("mk_banana_g", (0.42, 0.6, 0.16), 0.12), "plantain": variants("mk_plantain", (0.25, 0.5, 0.15), 0.15),
        "crate_red": mat("mk_crate_red", (0.72, 0.1, 0.08), 0.45), "crate_blue": mat("mk_crate_blue", (0.1, 0.25, 0.6), 0.45),
        "crate_in": mat("mk_crate_in", (0.06, 0.06, 0.06), 0.8),
        "qr": tmat("mk_qr", T["qr"], 0.6), "phone": mat("mk_phone", (0.03, 0.03, 0.035), 0.25, 0.3),
        "plastic_red": mat("mk_plastic_red", (0.7, 0.08, 0.07), 0.4), "plastic_white": mat("mk_plastic_white", (0.88, 0.88, 0.85), 0.4),
        "bucket": mat("mk_bucket", (0.1, 0.35, 0.7), 0.35), "water": mat("mk_water", (0.08, 0.14, 0.16), 0.05),
        "wet": mat("mk_wet", (0.2, 0.15, 0.1), 0.08), "bag_pink": mat("mk_bag_pink", (0.9, 0.55, 0.65), 0.35),
        "bag_white": mat("mk_bag_white", (0.92, 0.92, 0.9), 0.35), "peel": mat("mk_peel", (0.7, 0.5, 0.2), 0.7),
        "dead_leaf": mat("mk_dead_leaf", (0.42, 0.4, 0.15), 0.8)})
    for kind, rough in (("tomato", 0.3), ("brinjal", 0.18), ("chilli", 0.35), ("beans", 0.5), ("okra", 0.55), ("potato", 0.85),
                        ("leaf", 0.6), ("greens", 0.6), ("cabbage", 0.6), ("carrot", 0.55), ("gourd", 0.45)):
        M[kind] = [tmat("mk_%s_t%d" % (kind, i), T["%s_%d" % (kind, i)], rough) for i in range(3)]


# ---- shapes ----
def _put(ob, m, coll, smooth=True):
    ob.data.materials.append(R.choice(m) if isinstance(m, list) else m)
    if smooth:
        for p in ob.data.polygons:
            p.use_smooth = True
    for c in ob.users_collection:
        c.objects.unlink(ob)
    coll.objects.link(ob)
    return ob


def box(coll, loc, size, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    ob = bpy.context.object
    ob.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return _put(ob, m, coll, False)


def cyl(coll, loc, r, h, m, rot=(0, 0, 0), verts=12, r2=None, smooth=True):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, rotation=rot, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, location=loc, rotation=rot, vertices=verts)
    return _put(bpy.context.object, m, coll, smooth)


def blob(coll, loc, r, m, scale=(1, 1, 1), rot=(0, 0, 0), seg=10, lumpy=0.0):
    """A smooth round thing: a UV sphere, scaled, a little lumpy if asked (potatoes, ginger)."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=seg, ring_count=max(5, seg // 2 + 1), location=loc, rotation=rot)
    ob = bpy.context.object
    ob.scale = scale
    if lumpy > 0:
        for v in ob.data.vertices:
            v.co *= 1.0 + R.uniform(-lumpy, lumpy)
    bpy.ops.object.transform_apply(scale=True)
    return _put(ob, m, coll)


def line(coll, a, b, r, m, verts=6):
    a, b = Vector(a), Vector(b)
    d = b - a
    ob = cyl(coll, (a + b) / 2, r, d.length, m, verts=verts)
    ob.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    return ob


def sheet(coll, cx, cy, z, w, d, m, sag=0.12, wave=0.03, tilt=0.0, nx=14, ny=10):
    """A tarpaulin or a cloth roof: a grid sagging between its corners, rippled, a little lower at the front."""
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=nx, y_subdivisions=ny, size=1, location=(cx, cy, z))
    ob = bpy.context.object
    ob.scale = (w, d, 1)
    bpy.ops.object.transform_apply(scale=True)
    for v in ob.data.vertices:
        u, t = v.co.x / w * 2, v.co.y / d * 2
        v.co.z -= sag * (1 - u * u) * (1 - t * t) + tilt * t
        v.co.z += wave * math.sin(u * 7 + t * 3) * (1 - abs(t))
    _put(ob, m, coll)
    mod = ob.modifiers.new("Solid", 'SOLIDIFY')
    mod.thickness = 0.008
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="Solid")
    return ob


# ---- scans (third_party/polyhaven, CC0): real onions, ginger, lemons, limes, sweet potatoes, bananas ----
SCAN_DIR = os.path.join(HERE, "..", "third_party", "polyhaven")
SCANS = {}


def load_scan(key, ident, size, tris=260):
    """A Poly Haven scan, joined, cut down to `tris` triangles (its textures kept), its largest side `size` metres,
    sitting on its base at the origin; kept out of the props (a template that heaps copy)."""
    path = os.path.join(SCAN_DIR, ident, "%s_1k.gltf" % ident)
    if not os.path.exists(path):
        print("MARKET no scan", ident)
        return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in set(bpy.data.objects) - before if o.type == 'MESH']
    for o in set(bpy.data.objects) - before:
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in new:
        o.select_set(True)
    bpy.context.view_layer.objects.active = new[0]
    if len(new) > 1:
        bpy.ops.object.join()
    ob = bpy.context.object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    n = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if n > tris:
        d = ob.modifiers.new("Less", 'DECIMATE')
        d.ratio = tris / n
        bpy.ops.object.modifier_apply(modifier="Less")
    lo = Vector([min(v.co[i] for v in ob.data.vertices) for i in range(3)])
    hi = Vector([max(v.co[i] for v in ob.data.vertices) for i in range(3)])
    ext = hi - lo
    if ext.z > max(ext.x, ext.y) * 1.2:                                      # scanned standing up: lay it down
        for v in ob.data.vertices:
            v.co = Vector((v.co.z, v.co.y, -v.co.x))
        lo = Vector([min(v.co[i] for v in ob.data.vertices) for i in range(3)])
        hi = Vector([max(v.co[i] for v in ob.data.vertices) for i in range(3)])
    k = size / max(hi - lo)
    for v in ob.data.vertices:
        v.co = (v.co - Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))) * k
    for c in ob.users_collection:
        c.objects.unlink(ob)
    SCANS[key] = ob
    print("MARKET scan %s: %d tris" % (ident, sum(len(p.vertices) - 2 for p in ob.data.polygons)))


PLANTS = {}


def load_plant(key, ident, keep_leaves=1.0, grow=1.0, size=None, trunk_tris=3000, max_part=0):
    """A Poly Haven plant (CC0), made light enough for the game: its trunk and branches decimated, its leaf cards
    thinned to `keep_leaves` of them and each kept card grown by `grow` so the crown stays full; each part a
    template the props copy. size: its height in metres."""
    path = os.path.join(SCAN_DIR, ident, "%s_1k.gltf" % ident)
    if not os.path.exists(path):
        print("MARKET no plant", ident)
        return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    parts = [o for o in set(bpy.data.objects) - before if o.type == 'MESH']
    for o in set(bpy.data.objects) - before:
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    split = []
    for o in parts:                                                          # one material to a part: trunk, branches, leaves
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        if len(o.data.materials) > 1:
            before2 = set(bpy.data.objects)
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.separate(type='MATERIAL')
            bpy.ops.object.mode_set(mode='OBJECT')
            split += [o] + [x for x in set(bpy.data.objects) - before2 if x.type == 'MESH']
        else:
            split.append(o)
    parts = split
    out = []
    for o in parts:
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        leafy = {i for i, m in enumerate(o.data.materials) if m and ("leaf" in m.name.lower() or "leaves" in m.name.lower()
                 or ident.startswith(("shrub", "grass", "weed")))}
        doomed = []
        for f in bm.faces:
            if f.material_index in leafy and keep_leaves < 1.0:
                if R.random() > keep_leaves:
                    doomed.append(f)
                elif grow != 1.0:
                    cen = f.calc_center_median()
                    for v in f.verts:
                        v.co = cen + (v.co - cen) * grow
        bmesh.ops.delete(bm, geom=doomed, context='FACES')
        bm.to_mesh(o.data)
        bm.free()
        solid = [i for i in range(len(o.data.materials)) if i not in leafy]
        n = len(o.data.polygons)
        if solid and n > trunk_tris and len(solid) == len(o.data.materials):
            d = o.modifiers.new("Less", 'DECIMATE')
            d.ratio = trunk_tris / n
            bpy.ops.object.modifier_apply(modifier="Less")
        for c in o.users_collection:
            c.objects.unlink(o)
        out.append(o)
    if size:
        hgt = max(max(v.co.z for v in o.data.vertices) for o in out) - min(min(v.co.z for v in o.data.vertices) for o in out)
        for o in out:
            for v in o.data.vertices:
                v.co *= size / hgt
    if max_part:                                                             # (only the light clumps: grass by the hundred)
        out = [o for o in out if len(o.data.polygons) <= max_part] or out[:1]
    PLANTS[key] = out
    print("MARKET plant %s: %s" % (ident, [len(o.data.polygons) for o in out]))


def plant(c, key, p, scale=1.0, yaw=None, part=None):
    """Copies of a plant's parts (all of them, or one) at p."""
    obs = []
    for i, t in enumerate(PLANTS.get(key, [])):
        if part is not None and i != part % len(PLANTS[key]):
            continue
        ob = t.copy()
        c.objects.link(ob)
        ob.location = p
        ob.rotation_euler = (0, 0, R.uniform(0, 6.3) if yaw is None else yaw)
        ob.scale = (scale, scale, scale)
        obs.append(ob)
    return obs


def palm_frond(c, base, a, length, droop, m):
    """A coconut frond: a strip along its rib, arching up and out and drooping, the leaflets in its picture."""
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=12, y_subdivisions=2, size=1, location=(0, 0, 0))
    ob = bpy.context.object
    for v in ob.data.vertices:                                               # x along the frond (0..1), y across it
        t = v.co.x + 0.5
        w = v.co.y * 1.1 * (1.0 - 0.55 * t)
        r = t * length
        z = droop[0] * t * length - droop[1] * (t * length) ** 2 / length
        v.co.x, v.co.y, v.co.z = r, w, z
    ob.location = base
    ob.rotation_euler = (0, 0, a)
    bpy.ops.object.transform_apply(location=True, rotation=True)
    return _put(ob, m, c, False)


def scan(c, key, p, scale=1.0):
    t = SCANS[key]
    ob = t.copy()
    c.objects.link(ob)
    ob.location = p
    ob.rotation_euler = (R.uniform(-0.4, 0.4), R.uniform(-0.4, 0.4), R.uniform(0, 6.3))
    ob.scale = (scale, scale, scale)
    return ob


# ---- produce ----
def tomato(c, p, r=0.035):
    blob(c, p, r, M["tomato"], (1, 1, 0.82), seg=10)
    cyl(c, (p[0], p[1], p[2] + r * 0.8), r * 0.3, 0.006, M["stem"], verts=5, smooth=False)


def onion(c, p, r=0.028):
    if "onion" in SCANS:
        scan(c, "onion", (p[0], p[1], p[2] - r), r / 0.028)
        return
    blob(c, p, r, M["onion"], (1, 1, 0.9), seg=8)
    cyl(c, (p[0], p[1], p[2] + r * 0.95), r * 0.22, r * 0.3, M["onion"], verts=6, r2=0.003)


def potato(c, p, r=0.04):
    blob(c, p, r, M["potato"], (1.3, 1, 0.85), (0, 0, R.uniform(0, 3)), seg=8, lumpy=0.12)


def garlic(c, p, r=0.022):
    blob(c, p, r, M["garlic"], (1, 1, 0.85), seg=8, lumpy=0.06)


def ginger(c, p, r=0.03):
    if "ginger" in SCANS:
        scan(c, "ginger", (p[0], p[1], p[2] - r), r / 0.03)
        return
    for k in range(3):
        blob(c, (p[0] + 0.03 * k, p[1] + R.uniform(-0.01, 0.01), p[2]), r, M["ginger"], (1.5, 0.8, 0.6), (0, 0, R.uniform(0, 3)), seg=7, lumpy=0.15)


def lemon(c, p, r=0.026):
    key = "lemon" if R.random() < 0.5 else "lime"
    if key in SCANS:
        scan(c, key, (p[0], p[1], p[2] - r), r / 0.026)
        return
    blob(c, p, r, M["lemon"], (1.2, 1, 1), (0, 0, R.uniform(0, 3)), seg=8)


def sweet_potato(c, p, r=0.045):
    if "sweet_potato" in SCANS:
        scan(c, "sweet_potato", (p[0], p[1], p[2] - r * 0.6), r / 0.045)
        return
    potato(c, p, r)


def brinjal(c, p, r=0.035):
    a = R.uniform(0, 3)
    blob(c, p, r, M["brinjal"], (1.6, 1, 1), (0, 0, a), seg=10)
    cyl(c, (p[0] + math.cos(a) * r * 1.5, p[1] + math.sin(a) * r * 1.5, p[2]), r * 0.5, r * 0.6, M["stem"],
        rot=(0, math.pi / 2, a), verts=6, r2=r * 0.15)


def coconut(c, p, r=0.08):
    blob(c, p, r, M["husk"], (1, 0.9, 0.88), (0, 0, R.uniform(0, 3)), seg=10)


def cabbage(c, p, r=0.08):
    blob(c, p, r, M["cabbage"], (1, 1, 0.92), seg=12)
    for k in range(3):                                                       # its loose outer leaves
        a = k * 2.1 + R.uniform(0, 0.5)
        blob(c, (p[0] + math.cos(a) * r * 0.55, p[1] + math.sin(a) * r * 0.55, p[2] - r * 0.25), r * 0.75,
             M["leaf"], (1, 0.3, 0.8), (0.4, 0, a), seg=8)


def cauli(c, p, r=0.075):
    for k in range(7):
        a = k * 0.9
        blob(c, (p[0] + math.cos(a) * r * 0.35, p[1] + math.sin(a) * r * 0.35, p[2] + 0.01 * (k % 2)), r * 0.5, M["cauli"], (1, 1, 0.8), seg=7)
    for k in range(4):
        a = k * 1.6
        blob(c, (p[0] + math.cos(a) * r * 0.8, p[1] + math.sin(a) * r * 0.8, p[2] - r * 0.3), r * 0.6, M["leaf"], (1, 0.25, 0.9), (0.6, 0, a), seg=7)


def stick(c, p, length, r, m, a, droop=0.0):
    """Beans, chillies, ladies' fingers, drumsticks: thin, tapering, curved a little."""
    ob = cyl(c, p, r, length, m, rot=(math.pi / 2 + droop, 0, a), verts=6, r2=r * 0.4)
    return ob


def carrot(c, p, a):
    cyl(c, p, 0.018, 0.16, M["carrot"], rot=(math.pi / 2, 0, a), verts=8, r2=0.003)
    for k in range(3):                                                       # its feathery top
        cyl(c, (p[0] - math.sin(a) * 0.1, p[1] + math.cos(a) * 0.1, p[2] + 0.01), 0.008, 0.1, M["leaf"],
            rot=(math.pi / 2 + 0.3 * (k - 1), 0, a + 0.3 * (k - 1)), verts=4, r2=0.001)


def gourd(c, p, a):
    blob(c, p, 0.06, M["gourd"], (3.2, 1, 1), (0, 0, a), seg=12)


def bitter(c, p, a):
    blob(c, p, 0.03, M["bitter"], (2.6, 1, 1), (0, 0, a), seg=8, lumpy=0.12)


def bundle(c, p, m, leaves=9, size=0.14):
    """Keerai, curry leaves: a fan of leaves on stems, tied with a string."""
    a0 = R.uniform(0, 6.3)
    for k in range(leaves):
        a = a0 + R.uniform(-0.5, 0.5)
        tilt = R.uniform(0.3, 0.9)
        blob(c, (p[0] + math.cos(a) * size * 0.6, p[1] + math.sin(a) * size * 0.6, p[2] + size * 0.25 * tilt), size * 0.45,
             m, (1.0, 0.45, 0.08), (0, -tilt, a), seg=8)
    cyl(c, (p[0] - math.cos(a0) * 0.04, p[1] - math.sin(a0) * 0.04, p[2] + 0.01), 0.022, 0.1, M["stem"], rot=(math.pi / 2, 0, a0 + math.pi / 2), verts=6)
    cyl(c, (p[0] - math.cos(a0) * 0.04, p[1] - math.sin(a0) * 0.04, p[2] + 0.01), 0.025, 0.012, M["string"], rot=(math.pi / 2, 0, a0 + math.pi / 2), verts=8, smooth=False)


SPILL = []                                                                    # where things that roll off land


def heap(c, fn, cx, cy, z, w, d, r, n, mound=0.42):
    """A heap that overflows its board: a mound, higher in the middle, and a few rolled off it onto the ground."""
    for _ in range(int(n * 0.06) if SPILL else 0):
        gx, gy, gz, sp = SPILL[0]
        fn(c, (gx + R.uniform(-sp, sp), gy + R.uniform(-sp * 0.5, sp * 0.5), gz + r), r)
    for _ in range(n):
        x = R.uniform(-w / 2, w / 2)
        y = R.uniform(-d / 2, d / 2)
        hgt = max(0.0, 1.0 - (x / (w / 2)) ** 2) * max(0.0, 1.0 - (y / (d / 2)) ** 2)
        fn(c, (cx + x, cy + y, z + r + hgt * w * mound * R.uniform(0.7, 1.0)), r * R.uniform(0.85, 1.15))


def lay(c, fn, cx, cy, z, w, d, n, layers=3):
    for k in range(n):
        fn(c, (cx + R.uniform(-w / 2, w / 2), cy + R.uniform(-d / 2, d / 2), z + 0.012 * (k * layers // n)), R.uniform(-0.6, 0.6))


def basket(c, x, y, z, r=0.28):
    cyl(c, (x, y, z + 0.045), r, 0.09, M["palm"], verts=20, r2=r * 1.15, smooth=False)
    cyl(c, (x, y, z + 0.092), r * 1.16, 0.012, M["palm"], verts=20, smooth=False)


def sack(c, x, y, z, fn, r=0.3, h=0.55, n=40, rr=0.035):
    cyl(c, (x, y, z + h / 2), r, h, M["jute"], verts=16, r2=r * 1.05, smooth=False)
    bpy.ops.mesh.primitive_torus_add(major_radius=r * 1.07, minor_radius=0.05, location=(x, y, z + h), major_segments=16, minor_segments=6)
    _put(bpy.context.object, M["jute"], c)                                   # the rolled-down top
    heap(c, fn, x, y, z + h - 0.06, r * 1.6, r * 1.6, rr, n, 0.35)


def scatter(c, cx, cy, z, w, d, leaves=14, peels=10, wet=2):
    """What a market leaves on the ground: loose leaves, onion peels, a wet patch where the greens were sprinkled."""
    for _ in range(leaves):
        blob(c, (cx + R.uniform(-w / 2, w / 2), cy + R.uniform(-d / 2, d / 2), z + 0.004), R.uniform(0.03, 0.06),
             M["dead_leaf"] if R.random() < 0.5 else M["leaf"], (1, 0.5, 0.05), (0, 0, R.uniform(0, 6.3)), seg=6)
    for _ in range(peels):
        blob(c, (cx + R.uniform(-w / 2, w / 2), cy + R.uniform(-d / 2, d / 2), z + 0.003), R.uniform(0.012, 0.025),
             M["peel"] if R.random() < 0.5 else M["onion"], (1, 0.7, 0.05), (0, 0, R.uniform(0, 6.3)), seg=5)
    for _ in range(wet):
        cyl(c, (cx + R.uniform(-w / 2, w / 2), cy + R.uniform(-d / 2, d / 2), z + 0.002), R.uniform(0.2, 0.4), 0.002,
            M["wet"], verts=16, smooth=False).scale = (1.0, R.uniform(0.5, 0.9), 1.0)


def chair(c, x, y, yaw, m):
    """A plastic chair, the seller's."""
    ca, sa = math.cos(yaw), math.sin(yaw)
    rot = lambda dx, dy: (x + dx * ca - dy * sa, y + dx * sa + dy * ca)
    box(c, (*rot(0, 0), 0.43), (0.44, 0.42, 0.04), m, rot=(0, 0, yaw))
    box(c, (*rot(0, 0.21), 0.68), (0.42, 0.04, 0.42), m, rot=(-0.15, 0, yaw))
    for dx in (-0.19, 0.19):
        for dy in (-0.18, 0.18):
            cyl(c, (*rot(dx, dy), 0.21), 0.018, 0.43, m, verts=8)


def bucket(c, x, y):
    cyl(c, (x, y, 0.15), 0.15, 0.3, M["bucket"], verts=20, r2=0.13, smooth=False)
    cyl(c, (x, y, 0.27), 0.135, 0.01, M["water"], verts=20, smooth=False)
    cyl(c, (x + 0.06, y, 0.3), 0.04, 0.07, M["steel"], verts=12)            # the mug in it, for sprinkling the greens


def bags(c, x, y, z):
    """A bunch of thin carry bags hung on a nail."""
    for k in range(6):
        blob(c, (x + 0.02 * (k % 3), y + 0.01 * k, z - 0.12 - 0.01 * k), 0.1, M["bag_pink"] if k % 2 else M["bag_white"],
             (0.8, 0.12, 1.3), (0, 0, 0.2 * k), seg=8)


def phone_qr(c, x, y, z, yaw=0.0):
    box(c, (x, y, z + 0.006), (0.075, 0.155, 0.009), M["phone"], rot=(0, 0, yaw))
    box(c, (x + 0.16, y, z + 0.11), (0.12, 0.005, 0.17), M["qr"], rot=(0, 0, yaw))   # the card, clipped upright
    box(c, (x + 0.16, y + 0.004, z + 0.02), (0.13, 0.01, 0.03), M["iron"], rot=(0, 0, yaw))


def new_coll(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    return c


# ---- the things ----
def vegcart():
    c = new_coll("market_vegcart")
    L, W, H = 2.2, 1.1, 0.85
    box(c, (0, 0, H), (L, W, 0.05), M["wood"], rot=(0.07, 0, 0))            # the board, tilted to the buyer
    for y in (-W / 2, W / 2):
        box(c, (0, y, H + 0.07), (L, 0.04, 0.12), M["wood"])
    for x in (-L / 2, L / 2):
        box(c, (x, 0, H + 0.07), (0.04, W, 0.12), M["wood"])
    for k in range(-2, 3):                                                   # the dividers between the kinds
        box(c, (k * 0.42, 0, H + 0.05), (0.02, W - 0.05, 0.06), M["wood"])
    for side in (-1, 1):                                                     # two spoked wheels, rusted rims
        wy = side * (W / 2 + 0.07)
        cyl(c, (0.3, wy, 0.42), 0.42, 0.04, M["iron"], rot=(math.pi / 2, 0, 0), verts=28, smooth=False)
        cyl(c, (0.3, wy, 0.42), 0.37, 0.05, M["wood"], rot=(math.pi / 2, 0, 0), verts=28, smooth=False)
        cyl(c, (0.3, wy, 0.42), 0.07, 0.08, M["iron"], rot=(math.pi / 2, 0, 0), verts=12, smooth=False)
        for k in range(10):
            a = k * math.pi / 10
            box(c, (0.3, wy, 0.42), (0.72 * math.cos(a) + 0.03, 0.03, 0.72 * math.sin(a) + 0.03), M["wood"])
    cyl(c, (0.3, 0, 0.42), 0.025, W + 0.24, M["iron"], rot=(math.pi / 2, 0, 0), smooth=False)
    for y in (-0.3, 0.3):                                                    # the handles, the stand leg
        box(c, (-L / 2 - 0.55, y, H - 0.06), (1.1, 0.05, 0.05), M["wood"])
    box(c, (-L / 2 + 0.12, 0, H / 2), (0.06, 0.06, H), M["wood"])
    z = H + 0.04
    SPILL[:] = [(0.0, -W / 2 - 0.35, 0.0, 0.9)]                              # (what rolls off lands in front of it)
    cw, cd = 0.4, W / 2 - 0.06                                               # each bay: 0.4 wide, half the board deep
    bays = [(-0.84, -1, tomato, 0.035, 120), (-0.84, 1, onion, 0.028, 150), (-0.42, -1, potato, 0.03, 110),
            (-0.42, 1, garlic, 0.017, 120), (0.42, 1, ginger, 0.03, 14)]
    for bx, side, fn, r, n in bays:
        heap(c, fn, bx, side * cd / 2, z, cw - 0.04, cd - 0.04, r, n)
    lay(c, lambda c2, p, a: stick(c2, p, 0.09, 0.006, M["chilli"], a), 0.0, -cd / 2, z, cw - 0.05, cd - 0.05, 110)
    lay(c, lambda c2, p, a: stick(c2, p, 0.15, 0.007, M["beans"], a), 0.0, cd / 2, z, cw - 0.05, cd - 0.05, 90)
    lay(c, lambda c2, p, a: carrot(c2, p, a + math.pi / 2), 0.42, -cd / 2, z, cw - 0.1, cd - 0.08, 18)
    for k in range(3):
        cabbage(c, (0.84 - 0.06, -cd / 2 - 0.12 + k * 0.13, z + 0.08), 0.075)
    cauli(c, (0.98, -cd / 2 + 0.05, z + 0.07))
    for k in range(3):
        gourd(c, (0.9, cd / 2 - 0.08 + k * 0.1, z + 0.06 + 0.02 * (k % 2)), 0.1)
    for k in range(12):                                                      # drumsticks, tied, laid across the end
        stick(c, (L / 2 - 0.08, -0.32 + k * 0.012, z + 0.1 + (k % 3) * 0.012), 0.6, 0.008, M["drumstick"], math.pi / 2)
    # the faded blue tarpaulin, sagging over four bamboo poles, roped to them
    corners = [(-L / 2 - 0.05, -W / 2 - 0.05), (L / 2 + 0.05, -W / 2 - 0.05), (-L / 2 - 0.05, W / 2 + 0.05), (L / 2 + 0.05, W / 2 + 0.05)]
    for x, y in corners:
        cyl(c, (x, y, H + 0.72), 0.022, 1.45, M["bamboo"], verts=8)
    top = H + 1.42
    sheet(c, 0, 0, top, L + 0.6, W + 0.7, M["tarp_blue"], 0.16, 0.035, 0.12)
    for x, y in corners:
        line(c, (x, y, top - 0.02), (x * 1.18, y * 1.35, top - 0.12), 0.006, M["rope"])
    line(c, (-0.25, -W / 2 + 0.05, top - 0.15), (-0.25, -W / 2 + 0.05, H + 1.2), 0.003, M["string"])
    box(c, (-0.25, -W / 2 + 0.05, H + 1.2), (0.34, 0.015, 0.015), M["brass"])
    for dx in (-0.16, 0.16):                                                 # the hand-scale's two pans
        cyl(c, (-0.25 + dx, -W / 2 + 0.05, H + 0.85), 0.085, 0.025, M["brass"], verts=18, r2=0.06)
        for k in range(3):
            a = k * 2.1
            line(c, (-0.25 + dx, -W / 2 + 0.05, H + 1.2), (-0.25 + dx + 0.07 * math.cos(a), -W / 2 + 0.05 + 0.07 * math.sin(a), H + 0.87), 0.0015, M["string"], 4)
    for k in range(5):
        cyl(c, (-L / 2 + 0.25 + k * 0.05, W / 2 - 0.12, z + 0.02), 0.014 + k * 0.004, 0.03, M["iron"], verts=8)   # the weights
    SPILL.clear()
    phone_qr(c, -L / 2 + 0.25, W / 2 - 0.32, z + 0.1)                        # his phone and the shop's QR card
    bags(c, L / 2 + 0.05, -W / 2 - 0.05, H + 1.2)                            # carry bags on the front pole
    bucket(c, -0.5, W / 2 + 0.35)
    chair(c, -L / 2 - 0.3, W / 2 + 0.55, 0.4, M["plastic_red"])
    scatter(c, 0.0, -W / 2 - 0.4, 0.0, L + 0.8, 0.8, 16, 12, 2)
    return c


def groundstall():
    c = new_coll("market_groundstall")
    sheet(c, 0, 0, 0.012, 2.6, 2.0, M["tarp_orange"], -0.0, 0.006, 0.0, 10, 8)
    # the back tier: a plank on two bricks, baskets on it
    box(c, (0, 0.6, 0.12), (2.3, 0.4, 0.04), M["wood"])
    for x in (-0.9, 0.9):
        box(c, (x, 0.6, 0.05), (0.22, 0.12, 0.1), mat("mk_brick", (0.55, 0.22, 0.12), 0.9))
    SPILL[:] = [(0.0, -0.75, 0.012, 1.1)]
    back = [(-0.75, coconut, 0.08, 9), (0.0, lemon, 0.026, 70), (0.75, sweet_potato, 0.045, 22)]
    for x, fn, r, n in back:
        basket(c, x, 0.6, 0.14, 0.26)
        if r:
            heap(c, fn, x, 0.6, 0.24, 0.4, 0.4, r, n, 0.35)
        else:
            lay(c, fn, x, 0.6, 0.24, 0.34, 0.34, n)
    front = [(-0.85, "greens"), (-0.2, brinjal), (0.45, "okra"), (1.05, "curry")]
    for x, what in front:
        basket(c, x, -0.25, 0.012, 0.28)
        z = 0.11
        if what == "greens":
            for k in range(6):
                bundle(c, (x + R.uniform(-0.14, 0.14), -0.25 + R.uniform(-0.14, 0.14), z + 0.02 * k), M["greens"], 9, 0.16)
        elif what == "curry":
            for k in range(7):
                bundle(c, (x + R.uniform(-0.15, 0.15), -0.25 + R.uniform(-0.15, 0.15), z + 0.015 * k), M["curry"], 12, 0.11)
        elif what == "okra":
            lay(c, lambda c2, p, a: stick(c2, p, 0.11, 0.01, M["okra"], a), x, -0.25, z, 0.36, 0.36, 70)
        else:
            heap(c, what, x, -0.25, z, 0.4, 0.4, 0.035, 28, 0.3)
    SPILL.clear()
    for k in range(10):
        bitter(c, (1.1 + R.uniform(-0.1, 0.1), 0.05 + R.uniform(-0.1, 0.1), 0.03 + 0.01 * k), R.uniform(0, 3))   # bitter gourds, on the tarp
    sack(c, -1.55, 0.35, 0.0, onion, 0.28, 0.5, 70, 0.028)                     # two open sacks at the side
    sack(c, -1.5, -0.4, 0.0, potato, 0.3, 0.45, 40, 0.04)
    cyl(c, (1.0, 0.15, 0.03), 0.09, 0.05, M["steel"], verts=16, r2=0.07)       # the bowl of change
    phone_qr(c, 1.2, 0.72, 0.14)
    bucket(c, -0.9, -1.25)
    scatter(c, 0.0, -0.3, 0.012, 2.5, 1.8, 18, 14, 2)
    scatter(c, 0.0, -1.5, 0.0, 3.0, 0.8, 10, 8, 1)
    box(c, (1.55, -0.3, 0.14), (0.34, 0.26, 0.04), M["wood"])                  # her stool
    for dx in (-0.13, 0.13):
        box(c, (1.55 + dx, -0.3, 0.06), (0.04, 0.24, 0.12), M["wood"])
    # a faded umbrella over it, on a bamboo pole lashed to a brick
    cyl(c, (1.55, 0.7, 1.05), 0.022, 2.1, M["bamboo"], verts=8)
    bpy.ops.mesh.primitive_cone_add(radius1=1.35, radius2=0.04, depth=0.45, vertices=16, location=(1.55, 0.7, 2.0))
    um = bpy.context.object
    for v in um.data.vertices:                                               # it sags between its ribs
        a = math.atan2(v.co.y, v.co.x)
        rad = math.hypot(v.co.x, v.co.y)
        v.co.z -= 0.05 * (rad / 1.35) * (0.5 + 0.5 * math.cos(a * 8))
    _put(um, M["umbrella"], c, False)
    for k in range(8):
        a = k * math.pi / 4
        line(c, (1.55, 0.7, 2.2), (1.55 + 1.3 * math.cos(a), 0.7 + 1.3 * math.sin(a), 1.76), 0.006, M["iron"], 4)
    return c


def banana():
    c = new_coll("market_banana")
    for x in (-0.9, 0.9):
        for y in (-0.35, 0.35):
            cyl(c, (x, y, 1.15), 0.03, 2.3, M["bamboo"], verts=8)
    for y in (-0.35, 0.35):
        line(c, (-0.95, y, 2.2), (0.95, y, 2.2), 0.025, M["bamboo"], 8)
    sheet(c, 0, 0, 2.32, 2.3, 1.2, M["cloth"], 0.12, 0.03, 0.05)
    for x, y in ((-0.9, -0.35), (0.9, -0.35), (-0.9, 0.35), (0.9, 0.35)):
        line(c, (x, y, 2.28), (x * 1.15, y * 1.6, 2.05), 0.006, M["rope"])
    for k in range(6):                                                       # the bunches, hanging from the front bar
        x = -0.75 + k * 0.3
        kind = M["banana_y"] if k % 3 != 1 else M["banana_g"]
        if False:                                                            # (the scanned hands lie on the plank below)
            line(c, (x, -0.35, 2.18), (x, -0.35, 1.92), 0.004, M["string"])
            cyl(c, (x, -0.35, 1.68), 0.022, 0.5, M["stem"], verts=8)
            for tier in range(4):
                for j in range(4):
                    a = j * math.pi / 2 + tier * 0.7
                    ob = scan(c, "bananas", (x + 0.09 * math.cos(a), -0.35 + 0.09 * math.sin(a), 1.62 + tier * 0.09))
                    ob.rotation_euler = (0.3 * math.sin(a), -0.3 * math.cos(a), a)
            continue
        line(c, (x, -0.35, 2.18), (x, -0.35, 1.92), 0.004, M["string"])
        cyl(c, (x, -0.35, 1.68), 0.022, 0.5, M["stem"], verts=8)
        for tier in range(6):
            for j in range(8):
                a = j * 2 * math.pi / 8 + tier * 0.4
                zz = 1.86 - tier * 0.075
                p = (x + 0.065 * math.cos(a), -0.35 + 0.065 * math.sin(a), zz)
                ob = cyl(c, p, 0.018, 0.15, kind, rot=(0, 0, 0), verts=7, r2=0.009)
                ob.rotation_euler = (0.95 * math.sin(a) + 0.2, -0.95 * math.cos(a), 0)
    heap(c, coconut, -0.45, 0.15, 0.0, 0.8, 0.5, 0.08, 18, 0.3)
    box(c, (0.4, -0.05, 0.3), (1.1, 0.5, 0.04), M["wood"])                   # a plank on crates, ripe hands laid on it
    for dx in (-0.1, 0.9):
        box(c, (dx, -0.05, 0.14), (0.3, 0.45, 0.28), M["crate_blue"])
    if "bananas" in SCANS:
        for k in range(9):
            ob = scan(c, "bananas", (0.0 + (k % 5) * 0.2, -0.15 + (k // 5) * 0.2, 0.32 + 0.03 * (k // 5)))
            ob.rotation_euler = (0, 0, R.uniform(-0.3, 0.3) + (0 if k % 2 else math.pi))
    scatter(c, 0, 0, 0.0, 2.0, 1.2, 8, 6, 1)
    for k in range(5):                                                       # plantain leaves, folded in a pile
        blob(c, (0.75, 0.25, 0.03 + 0.012 * k), 0.4, M["plantain"], (1.0, 0.35, 0.03), (0, 0, 0.3 * k), seg=10)
    return c


def crates():
    c = new_coll("market_crates")
    fills = {(0, 2): tomato, (1, 1): onion}
    for col in range(2):
        for row in range(3 - col):
            m = M["crate_red"] if (row + col) % 2 == 0 else M["crate_blue"]
            x, z = col * 0.64, row * 0.32
            box(c, (x, 0, z + 0.16), (0.6, 0.42, 0.3), m)
            box(c, (x, 0, z + 0.3), (0.52, 0.34, 0.02), M["crate_in"])
            for k in range(3):                                               # the slots in its sides
                box(c, (x - 0.15 + k * 0.15, -0.212, z + 0.18), (0.08, 0.01, 0.16), M["crate_in"])
            if (col, row) in fills:
                heap(c, fills[(col, row)], x, 0, z + 0.3, 0.5, 0.34, 0.035 if col == 0 else 0.028, 70 if col == 0 else 90, 0.35)
    box(c, (1.25, 0, 0.16), (0.6, 0.42, 0.3), M["crate_blue"])
    heap(c, potato, 1.25, 0, 0.3, 0.5, 0.34, 0.04, 40, 0.35)
    sack(c, 1.25, 0.6, 0.0, onion, 0.25, 0.5, 50, 0.028)
    return c


FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def text(c, s, loc, size, m, rot=(math.pi / 2, 0, 0)):
    cu = bpy.data.curves.new("Text", 'FONT')
    cu.body = s
    cu.size = size
    cu.extrude = 0.003
    cu.align_x, cu.align_y = 'CENTER', 'CENTER'
    if os.path.exists(FONT):
        cu.font = bpy.data.fonts.load(FONT, check_existing=True)
    ob = bpy.data.objects.new("Text", cu)
    c.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = rot
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.ops.object.convert(target='MESH')
    ob.data.materials.clear()
    ob.data.materials.append(m)
    return ob


def teakadai():
    """Sekar's tea stall at the Pudhur Vayal turn (Murugan Tea Stall): a timber counter under a tin roof on poles, its
    board painted yellow; on the counter the big steel tea kettle and the milk vessel on their stove, steel tumblers
    and glasses upside down on a tray, glass jars of biscuits, murukku and buns, a bunch of bananas hanging from the
    roof bar, a calendar picture on the post; a long bench in front with the day's newspaper on it, a water drum."""
    c = new_coll("market_teakadai")
    W, D, H = 2.6, 1.0, 1.0
    box(c, (0, 0, H / 2), (W, D, H), M["wood"])                              # the counter
    box(c, (0, 0, H + 0.02), (W + 0.06, D + 0.06, 0.04), mat("mk_counter_top", (0.2, 0.2, 0.22), 0.4, 0.3))
    for x in (-W / 2 - 0.1, W / 2 + 0.1):                                    # the roof posts (behind and in front)
        for y in (-D / 2 - 0.35, D / 2 + 0.4):
            box(c, (x, y, 1.25), (0.08, 0.08, 2.5), M["wood"])
    sheet(c, 0, 0.0, 2.55, W + 0.7, D + 1.4, M["iron"], 0.04, 0.012, 0.18)  # the tin roof, rusted, sloping forward
    yellow = mat("mk_board_yellow", (0.92, 0.75, 0.12), 0.6)
    blue = mat("mk_letters_blue", (0.08, 0.15, 0.5), 0.5)
    red = mat("mk_letters_red", (0.65, 0.07, 0.05), 0.5)
    box(c, (0, -D / 2 - 0.4, 2.25), (W + 0.4, 0.04, 0.42), yellow)            # the board
    text(c, "MURUGAN TEA STALL", (0, -D / 2 - 0.43, 2.3), 0.2, blue)
    text(c, "TEA  ·  COFFEE  ·  SNACKS", (0, -D / 2 - 0.43, 2.11), 0.08, red)
    # the stove: the kettle and the milk vessel, steaming
    box(c, (0.7, 0.15, H + 0.12), (0.5, 0.36, 0.2), M["iron"])
    cyl(c, (0.58, 0.15, H + 0.42), 0.13, 0.38, M["steel"], verts=20)           # the tea kettle (the big samovar)
    cyl(c, (0.58, 0.15, H + 0.64), 0.07, 0.06, M["steel"], verts=16, r2=0.03)
    cyl(c, (0.58, 0.02, H + 0.36), 0.015, 0.12, M["steel"], rot=(0.9, 0, 0), verts=8)   # its tap
    cyl(c, (0.85, 0.15, H + 0.32), 0.12, 0.18, mat("mk_aluminium", (0.68, 0.68, 0.66), 0.35, 0.8), verts=20)   # the milk pan
    cyl(c, (0.85, 0.15, H + 0.405), 0.105, 0.01, mat("mk_milk", (0.95, 0.93, 0.86), 0.3), verts=20)
    # glasses and tumblers on a tray
    box(c, (0.05, -0.15, H + 0.045), (0.5, 0.32, 0.01), M["steel"])
    for i in range(4):
        for j in range(3):
            cyl(c, (-0.13 + i * 0.12, -0.25 + j * 0.1, H + 0.1), 0.03, 0.1, mat("mk_glass", (0.75, 0.82, 0.8), 0.05, 0.0, 0.35), verts=10, r2=0.034)
    for k in range(5):
        cyl(c, (0.36, -0.3, H + 0.08 + 0.035 * k), 0.036, 0.06, M["steel"], verts=12, r2=0.032)   # tumblers, stacked
    # the glass jars of snacks, in a row at the front edge
    jar = mat("mk_jar_glass", (0.85, 0.9, 0.88), 0.05, 0.0, 0.22)
    lid = mat("mk_jar_lid", (0.75, 0.12, 0.1), 0.4)
    fills = [mat("mk_biscuit", (0.8, 0.6, 0.3), 0.7), mat("mk_murukku", (0.75, 0.5, 0.2), 0.8), mat("mk_bun", (0.85, 0.65, 0.4), 0.7),
             mat("mk_rusk", (0.7, 0.45, 0.2), 0.8), mat("mk_peanut", (0.8, 0.6, 0.35), 0.8)]
    for k in range(5):
        x = -1.05 + k * 0.24
        cyl(c, (x, -D / 2 + 0.15, H + 0.16), 0.09, 0.24, jar, verts=16)
        cyl(c, (x, -D / 2 + 0.15, H + 0.12), 0.085, 0.16, fills[k], verts=16)
        cyl(c, (x, -D / 2 + 0.15, H + 0.3), 0.07, 0.04, lid, verts=16)
    # bananas hanging from the front roof bar, a calendar on the post
    line(c, (-W / 2 - 0.1, -D / 2 - 0.35, 2.05), (W / 2 + 0.1, -D / 2 - 0.35, 2.05), 0.025, M["wood"], 8)
    for k in range(2):
        x = -0.9 + k * 0.25
        line(c, (x, -D / 2 - 0.35, 2.04), (x, -D / 2 - 0.35, 1.85), 0.004, M["string"])
        for tier in range(4):
            for j in range(7):
                a = j * 2 * math.pi / 7 + tier * 0.4
                ob = cyl(c, (x + 0.06 * math.cos(a), -D / 2 - 0.35 + 0.06 * math.sin(a), 1.78 - tier * 0.07), 0.016, 0.13,
                         M["banana_y"], verts=6, r2=0.008)
                ob.rotation_euler = (0.95 * math.sin(a) + 0.2, -0.95 * math.cos(a), 0)
    box(c, (W / 2 + 0.06, -D / 2 - 0.35, 1.5), (0.01, 0.3, 0.42), mat("mk_calendar", (0.9, 0.45, 0.15), 0.7))
    # the bench in front, the newspaper on it; a water drum at the side
    box(c, (0, -D / 2 - 1.1, 0.42), (2.2, 0.35, 0.05), M["wood"])
    for x in (-0.9, 0.0, 0.9):
        box(c, (x, -D / 2 - 1.1, 0.2), (0.06, 0.3, 0.4), M["wood"])
    box(c, (0.4, -D / 2 - 1.1, 0.455), (0.4, 0.3, 0.012), mat("mk_newspaper", (0.85, 0.83, 0.78), 0.9), rot=(0, 0, 0.15))
    cyl(c, (-W / 2 - 0.45, 0.2, 0.42), 0.28, 0.84, M["bucket"], verts=20)
    scatter(c, 0, -D / 2 - 1.0, 0.0, 3.0, 1.2, 6, 8, 1)
    return c


def workshop_closed():
    """Bala Motors at night: the same workshop, its rolling shutter pulled down and padlocked, the board unlit, a
    single bulb over it still on."""
    c = workshop()
    c.name = "bala_workshop_closed"
    W, D, H = 6.0, 4.0, 3.2
    shutter = mat("mk_shutter", (0.34, 0.35, 0.36), 0.7, 0.15)
    for k in range(int((H - 0.55) / 0.08)):                                  # the shutter's slats
        box(c, (0, -D / 2 + 0.02, 0.04 + k * 0.08), (W - 0.2, 0.03, 0.075), shutter)
    box(c, (0, -D / 2 - 0.01, 0.06), (W - 0.2, 0.05, 0.1), M["iron"])          # its bottom bar, the padlock
    box(c, (0.4, -D / 2 - 0.06, 0.12), (0.06, 0.03, 0.08), M["brass"])
    blob(c, (0, -D / 2 - 0.25, H - 0.6), 0.05, mat("mk_bulb", (1.0, 0.92, 0.7), 0.2), seg=8)
    paint = mat("mk_paint_red", (0.72, 0.08, 0.06), 0.6)                     # painted on the shutter
    text(c, "BALA MOTORS", (0, -D / 2 - 0.005, 1.55), 0.32, paint)
    text(c, "9 AM - 9 PM", (0, -D / 2 - 0.005, 1.15), 0.2, paint)
    text(c, "Ph: 94433 *****", (0, -D / 2 - 0.005, 0.85), 0.14, paint)
    return c                                                                 # (its light: the story's lamp, story.gd)


def workshop():
    """Bala Motors, Ganapathy (Act 5): an open-fronted workshop under a corrugated roof. The back wall: a pegboard of
    spanners and screwdrivers, the board BALA MOTORS (two-wheeler and car service, key programming), a calendar;
    the workbench with a vice, a toolbox, a rag, the job-card book, and the key programmer (a small grey box with a
    lead and a chip key in it: E11); stacked tyres, an oil drum, oil cans, a compressor, a trolley jack, a stool."""
    c = new_coll("bala_workshop")
    W, D, H = 6.0, 4.0, 3.2
    concrete = mat("mk_concrete", (0.55, 0.54, 0.5), 0.9)
    oil = mat("mk_oil_floor", (0.22, 0.21, 0.2), 0.25)
    box(c, (0, 0, 0.02), (W, D, 0.04), concrete)                             # the floor, oil-stained
    for k in range(5):
        cyl(c, (R.uniform(-2, 2), R.uniform(-1.2, 1.2), 0.042), R.uniform(0.25, 0.6), 0.002, oil, verts=16, smooth=False).scale = (1, R.uniform(0.5, 1), 1)
    wall = tmat("mk_wall_workshop", T_ALL["grime"], 0.9)
    box(c, (0, D / 2, H / 2), (W, 0.15, H), wall)                            # the back wall and the sides
    for x in (-W / 2, W / 2):
        box(c, (x, 0, H / 2), (0.15, D, H), wall)
    sheet(c, 0, 0, H + 0.1, W + 0.6, D + 0.8, M["iron"], 0.03, 0.01, 0.2)     # the corrugated roof, rusted
    for k in range(14):                                                      # (its ridges)
        box(c, (-W / 2 - 0.2 + k * 0.48, 0, H + 0.09), (0.04, D + 0.8, 0.03), M["iron"], rot=(0.05, 0, 0))
    # the board over the opening
    red = mat("mk_board_red", (0.7, 0.08, 0.06), 0.55)
    white = mat("mk_letters_white", (0.95, 0.95, 0.93), 0.5)
    yellow = mat("mk_letters_yellow", (0.98, 0.82, 0.2), 0.5)
    box(c, (0, -D / 2 - 0.1, H - 0.25), (W, 0.05, 0.55), red)
    text(c, "BALA MOTORS", (0, -D / 2 - 0.13, H - 0.17), 0.28, white)
    text(c, "TWO WHEELER & CAR SERVICE  ·  KEY PROGRAMMING", (0, -D / 2 - 0.13, H - 0.4), 0.09, yellow)
    # the pegboard of tools on the back wall
    peg = mat("mk_pegboard", (0.55, 0.45, 0.3), 0.85)
    steel = M["steel"]
    box(c, (-1.2, D / 2 - 0.09, 1.7), (2.2, 0.02, 1.0), peg)
    for k in range(12):                                                      # spanners, small to big
        x = -2.15 + k * 0.17
        ln = 0.12 + k * 0.012
        box(c, (x, D / 2 - 0.11, 1.95 - ln / 2), (0.022, 0.01, ln), steel)
        cyl(c, (x, D / 2 - 0.11, 1.96), 0.022, 0.01, steel, rot=(math.pi / 2, 0, 0), verts=8)
    for k in range(8):                                                       # screwdrivers
        x = -2.1 + k * 0.12
        box(c, (x, D / 2 - 0.11, 1.42), (0.01, 0.01, 0.14), steel)
        box(c, (x, D / 2 - 0.12, 1.53), (0.025, 0.025, 0.09), mat("mk_handle_%d" % (k % 3), ((0.8, 0.1, 0.05), (0.1, 0.3, 0.7), (0.9, 0.7, 0.1))[k % 3], 0.4))
    box(c, (0.4, D / 2 - 0.08, 0.9 + 0.95), (0.4, 0.01, 0.55), mat("mk_calendar_ws", (0.9, 0.4, 0.15), 0.7))   # the calendar
    # the workbench: a vice, a toolbox, a rag, the job-card book, the key programmer
    box(c, (-1.2, D / 2 - 0.45, 0.88), (2.4, 0.7, 0.06), M["wood"])
    for x in (-2.3, -0.1):
        for y in (D / 2 - 0.75, D / 2 - 0.15):
            box(c, (x, y, 0.43), (0.06, 0.06, 0.86), M["iron"])
    box(c, (-0.3, D / 2 - 0.5, 0.98), (0.14, 0.2, 0.14), M["iron"])          # the vice
    cyl(c, (-0.3, D / 2 - 0.62, 1.0), 0.012, 0.24, steel, rot=(0, math.pi / 2, 0), verts=8)
    box(c, (-2.0, D / 2 - 0.45, 1.0), (0.5, 0.25, 0.2), red)                 # the toolbox
    blob(c, (-1.55, D / 2 - 0.6, 0.93), 0.1, mat("mk_rag", (0.55, 0.45, 0.35), 0.95), (1.4, 1, 0.3), seg=8)
    box(c, (-1.15, D / 2 - 0.55, 0.925), (0.22, 0.3, 0.025), mat("mk_jobbook", (0.15, 0.3, 0.55), 0.7))    # the job-card book
    box(c, (-1.15, D / 2 - 0.55, 0.94), (0.2, 0.28, 0.005), mat("mk_jobpage", (0.95, 0.93, 0.85), 0.8))
    box(c, (-0.75, D / 2 - 0.4, 0.97), (0.24, 0.16, 0.1), mat("mk_programmer", (0.4, 0.42, 0.45), 0.4))   # the key programmer
    box(c, (-0.75, D / 2 - 0.48, 1.0), (0.12, 0.005, 0.05), mat("mk_screen", (0.1, 0.35, 0.25), 0.2))
    line(c, (-0.65, D / 2 - 0.4, 0.95), (-0.45, D / 2 - 0.65, 0.92), 0.006, mat("mk_cable", (0.05, 0.05, 0.05), 0.5))
    box(c, (-0.42, D / 2 - 0.66, 0.925), (0.06, 0.03, 0.015), mat("mk_key", (0.08, 0.08, 0.09), 0.4))      # a chip key
    # the PIN's clues (the story's keypad step): a yellow sticky note on the programmer; on the wall, young Bala on his
    # first bike in a frame, its number plate readable up close
    box(c, (-0.75, D / 2 - 0.4, 1.023), (0.075, 0.075, 0.003), mat("mk_sticky", (0.98, 0.88, 0.25), 0.7), rot=(0, 0, 0.2))
    fx, fy, fz = 1.4, D / 2 - 0.09, 1.65
    box(c, (fx, fy, fz), (0.46, 0.025, 0.36), mat("mk_frame_wood", (0.25, 0.14, 0.07), 0.5))
    box(c, (fx, fy - 0.014, fz), (0.4, 0.005, 0.3), mat("mk_photo_wall", (0.78, 0.74, 0.62), 0.7))       # the school wall
    box(c, (fx, fy - 0.016, fz - 0.11), (0.4, 0.004, 0.08), mat("mk_photo_road", (0.42, 0.4, 0.38), 0.8))
    bike = mat("mk_photo_bike", (0.75, 0.1, 0.08), 0.5)
    for dx in (-0.08, 0.08):                                                  # the bike, side on: wheels, tank, seat
        cyl(c, (fx + dx, fy - 0.02, fz - 0.07), 0.04, 0.004, M["phone"], rot=(math.pi / 2, 0, 0), verts=14)
    box(c, (fx, fy - 0.02, fz - 0.03), (0.13, 0.004, 0.035), bike)
    box(c, (fx - 0.04, fy - 0.02, fz - 0.01), (0.07, 0.004, 0.015), M["phone"])
    box(c, (fx - 0.03, fy - 0.021, fz + 0.04), (0.04, 0.004, 0.08), mat("mk_photo_shirt", (0.92, 0.92, 0.95), 0.6))   # Bala
    blob(c, (fx - 0.03, fy - 0.021, fz + 0.1), 0.02, mat("mk_photo_skin", (0.45, 0.3, 0.2), 0.6), (1, 0.2, 1.1), seg=8)
    box(c, (fx + 0.1, fy - 0.022, fz - 0.06), (0.06, 0.003, 0.022), M["plastic_white"])                # the plate
    text(c, "TN 37 K 2719", (fx + 0.1, fy - 0.025, fz - 0.06), 0.0085, M["phone"])
    # tyres stacked, an oil drum and cans, a compressor, a trolley jack, a stool
    rubber = mat("mk_tyre", (0.05, 0.05, 0.05), 0.85)
    for k in range(5):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.3, minor_radius=0.1, location=(2.3, D / 2 - 0.5, 0.1 + k * 0.2),
                                         major_segments=20, minor_segments=8)
        _put(bpy.context.object, rubber, c)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.3, minor_radius=0.1, location=(2.7, 0.6, 0.38), rotation=(math.pi / 2, 0, 0.3),
                                     major_segments=20, minor_segments=8)
    _put(bpy.context.object, rubber, c)
    cyl(c, (1.5, D / 2 - 0.4, 0.45), 0.3, 0.9, mat("mk_drum_blue", (0.1, 0.25, 0.55), 0.5), verts=20)
    for k in range(4):
        box(c, (1.0 + k * 0.16, D / 2 - 0.3, 0.12), (0.12, 0.08, 0.22), mat("mk_can_%d" % (k % 2), ((0.75, 0.65, 0.1), (0.15, 0.35, 0.15))[k % 2], 0.4))
    cyl(c, (-2.5, 0.3, 0.35), 0.22, 0.6, red, rot=(0, math.pi / 2, 0), verts=16)   # the compressor tank
    box(c, (-2.5, 0.3, 0.75), (0.3, 0.25, 0.2), M["iron"])
    box(c, (0.6, -0.3, 0.12), (0.9, 0.3, 0.12), red)                         # the trolley jack
    line(c, (0.15, -0.3, 0.15), (-0.45, -0.3, 0.85), 0.02, M["iron"])
    box(c, (-1.0, D / 2 - 1.2, 0.3), (0.3, 0.3, 0.04), M["wood"])            # his stool
    for dx in (-0.12, 0.12):
        for dy in (-0.12, 0.12):
            cyl(c, (-1.0 + dx, D / 2 - 1.2 + dy, 0.15), 0.015, 0.3, M["iron"], verts=6)
    # shelves of parts on the left wall, a hanging tube and a chain, an air hose coiled, a tube light
    for k in range(3):
        box(c, (-W / 2 + 0.3, 0.2, 0.7 + k * 0.6), (0.45, 2.0, 0.03), M["wood"])
        for j in range(6):
            box(c, (-W / 2 + 0.3, -0.6 + j * 0.32, 0.8 + k * 0.6), (0.3, 0.25, 0.18),
                mat("mk_partbox_%d" % ((j + k) % 4), ((0.75, 0.6, 0.35), (0.2, 0.35, 0.6), (0.8, 0.75, 0.7), (0.6, 0.15, 0.1))[(j + k) % 4], 0.7))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.32, minor_radius=0.03, location=(1.0, D / 2 - 0.1, 2.2), rotation=(math.pi / 2, 0, 0))
    _put(bpy.context.object, rubber, c)                                      # an inner tube on a nail
    for k in range(14):
        cyl(c, (1.6, D / 2 - 0.15, 2.4 - k * 0.04), 0.012, 0.035, M["iron"], rot=(0, (k % 2) * math.pi / 2, 0), verts=6)   # a chain
    for k in range(4):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.25 - k * 0.02, minor_radius=0.012, location=(-2.5, 0.3, 1.05 + k * 0.02))
        _put(bpy.context.object, mat("mk_hose", (0.7, 0.15, 0.08), 0.5), c)
    box(c, (0, 0, H - 0.08), (1.2, 0.08, 0.05), mat("mk_tube_light", (1, 1, 0.95), 0.2))
    box(c, (2.2, D / 2 - 0.08, 2.1), (0.5, 0.01, 0.7), mat("mk_poster", (0.85, 0.75, 0.55), 0.8))   # an old poster, torn
    scatter(c, 0, -1.0, 0.04, 4.0, 1.5, 0, 6, 0)
    return c


def pudhur_site():
    """Pudhur Vayal, off the Thondamuthur road (STORY_BIBLE.md: the farmers' land, the Green Valley site, where
    Raghavan died): the site's gate between two plastered pillars, a steel gate half open, a watchman's tin hut; a
    big faded hoarding, GREEN VALLEY, a Raghavan Developers project, its plot layout; a barbed-wire fence on stone
    posts along the road, survey stones in the cleared red earth; beyond the fence the farmers' paddy, green in rows,
    a banana plot, a thatched field shed with a cart wheel against it, a well."""
    c = new_coll("pudhur_site")
    earth = tmat("mk_red_earth", T_ALL["earth_site"], 0.95)
    box(c, (0, 6.0, 0.02), (24.0, 14.0, 0.04), earth)                         # the cleared site
    plaster = tmat("mk_pillar", T_ALL["plaster_stained"], 0.9)
    for x in (-2.6, 2.6):                                                    # the gate's pillars and the gate
        box(c, (x, 0, 1.2), (0.6, 0.6, 2.4), plaster)
        box(c, (x, 0, 2.45), (0.7, 0.7, 0.1), plaster)
    gate = M["iron"]                                                         # (rusted)
    box(c, (-1.25, 0.05, 1.0), (2.2, 0.05, 0.06), gate)
    box(c, (-1.25, 0.05, 1.9), (2.2, 0.05, 0.06), gate)
    for k in range(9):
        box(c, (-2.25 + k * 0.25, 0.05, 1.05), (0.03, 0.03, 1.7), gate)
    ca, sa = math.cos(1.0), math.sin(1.0)                                     # the other half, swung open
    hx, hy = 2.3, 0.05
    for z in (1.0, 1.9):
        box(c, (hx - 1.1 * ca, hy + 1.1 * sa, z), (2.2, 0.05, 0.06), gate, rot=(0, 0, -1.0))
    for k in range(9):
        box(c, (hx - (0.1 + k * 0.25) * ca, hy + (0.1 + k * 0.25) * sa, 1.05), (0.03, 0.03, 1.7), gate)
    # the watchman's hut
    tin = M["iron"]
    box(c, (4.8, 1.8, 1.1), (1.6, 1.6, 2.2), tin)
    box(c, (4.8, 1.8, 2.25), (1.9, 1.9, 0.06), tin, rot=(0.05, 0, 0))
    box(c, (4.0, 1.8, 0.95), (0.02, 0.7, 1.8), mat("mk_hut_door", (0.3, 0.2, 0.12), 0.8))
    chair(c, 3.6, 1.1, -0.4, M["plastic_red"])
    # the hoarding, faded: GREEN VALLEY
    for x in (-6.5, -2.5):
        box(c, (x, 3.0, 1.8), (0.15, 0.15, 3.6), M["iron"])
    board = tmat("mk_hoarding", T_ALL["hoarding"], 0.85)
    box(c, (-4.5, 3.0, 3.4), (5.0, 0.08, 2.4), board)
    white = mat("mk_letters_white2", (0.95, 0.95, 0.92), 0.6)
    gold = mat("mk_letters_gold2", (0.95, 0.8, 0.35), 0.5)
    text(c, "GREEN VALLEY", (-4.5, 2.95, 4.15), 0.55, white)
    text(c, "DTCP APPROVED PLOTS  ·  A RAGHAVAN DEVELOPERS PROJECT", (-4.5, 2.95, 3.6), 0.15, gold)
    plan = mat("mk_plan", (0.92, 0.9, 0.8), 0.8)
    box(c, (-4.5, 2.95, 2.75), (3.6, 0.01, 0.9), plan)
    for k in range(6):
        box(c, (-6.0 + k * 0.6, 2.94, 2.75), (0.02, 0.01, 0.85), mat("mk_plan_line", (0.4, 0.35, 0.3), 0.8))
    box(c, (-4.5, 2.94, 2.75), (3.5, 0.01, 0.02), mat("mk_plan_line", (0.4, 0.35, 0.3), 0.8))
    # the barbed-wire fence on stone posts along the road
    stone = mat("mk_stone_post", (0.6, 0.58, 0.55), 0.95)
    for k in range(-5, 6):
        if abs(k) < 2:
            continue
        x = k * 2.0
        box(c, (x, 0.0, 0.7), (0.15, 0.15, 1.4), stone)
    for z in (0.5, 0.85, 1.2):
        for side in (-1, 1):
            line(c, (side * 3.0, 0.0, z), (side * 10.0, 0.0, z), 0.006, M["iron"], 4)
    for k in range(8):                                                       # survey stones on the cleared plots
        box(c, (R.uniform(-9, 9), R.uniform(3.0, 11.0), 0.12), (0.12, 0.12, 0.24), mat("mk_survey", (0.9, 0.88, 0.85), 0.8))
    # the farmers' paddy, beyond, in rows; a banana plot; a field shed; a well
    paddy = [mat("mk_paddy_%d" % k, (0.25 + 0.05 * k, 0.55 + 0.04 * k, 0.15), 0.8) for k in range(3)]
    pmat = tmat("mk_paddy_rows", T_ALL["paddy"], 0.7)
    for r in range(22):                                                      # paddy in rows, a carpet of blades
        for x0 in (-11.0, 3.0):
            bpy.ops.mesh.primitive_grid_add(x_subdivisions=24, y_subdivisions=2, size=1, location=(x0 + 4.0, 13.3 + r * 0.3, 0.3))
            ob = bpy.context.object
            ob.scale = (8.0, 0.22, 1)
            ob.rotation_euler = (math.pi / 2 - 0.12, 0, 0)
            bpy.ops.object.transform_apply(scale=True, rotation=True)
            for v in ob.data.vertices:                                       # a ragged top, swaying
                if v.co.z > 0.0:
                    v.co.z += R.uniform(-0.08, 0.12)
                    v.co.y += R.uniform(-0.06, 0.06)
                v.co.z *= R.uniform(2.6, 2.9)
            _put(ob, pmat, c)
            for k in range(10):                                              # (a few blades standing out)
                cyl(c, (x0 + R.uniform(0.1, 7.9), 13.3 + r * 0.3, 0.45), 0.03, 0.6, R.choice(paddy), rot=(R.uniform(-0.3, 0.3), R.uniform(-0.3, 0.3), 0), verts=4, r2=0.004)
    for x0 in (-7.0, 7.0):
        box(c, (x0, 16.5, 0.03), (8.2, 6.8, 0.01), mat("mk_paddy_water", (0.22, 0.28, 0.24), 0.04, 0.3))   # glinting
    box(c, (-4.0, 16.5, 0.08), (0.5, 7.0, 0.16), earth)                       # a bund between the fields
    leaf = M["plantain"]
    for k in range(10):
        x, y = 9.5 + (k % 3) * 1.6, 9.0 + (k // 3) * 1.7
        cyl(c, (x, y, 1.0), 0.09, 2.0, mat("mk_banana_trunk", (0.45, 0.5, 0.25), 0.8), verts=8)
        for j in range(6):
            a = j * 1.05 + k
            ob = blob(c, (x + 0.6 * math.cos(a), y + 0.6 * math.sin(a), 2.0), 0.8, leaf, (1.0, 0.25, 0.04), (0, -0.5, a), seg=8)
    thatch = mat("mk_thatch", (0.6, 0.5, 0.3), 0.95)
    for x in (-10.0, -7.6):
        for y in (8.0, 10.0):
            cyl(c, (x, y, 1.0), 0.07, 2.0, M["bamboo"], verts=6)
    bpy.ops.mesh.primitive_cone_add(radius1=2.2, radius2=0.1, depth=1.2, vertices=4, location=(-8.8, 9.0, 2.5), rotation=(0, 0, math.pi / 4))
    _put(bpy.context.object, thatch, c, False)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.6, minor_radius=0.06, location=(-7.3, 8.4, 0.62), rotation=(math.pi / 2, 0, 0.3))
    _put(bpy.context.object, M["wood"], c)                                    # a cart wheel against the shed
    cyl(c, (-6.0, 12.0, 0.4), 1.0, 0.8, stone, verts=20, smooth=False)       # the well
    cyl(c, (-6.0, 12.0, 0.79), 0.85, 0.02, M["water"], verts=20, smooth=False)
    # coconut palms along the bunds
    trunk = tmat("mk_palm_trunk", T_ALL["bark_palm"], 0.9)
    fmat = tmat("mk_frond", T_ALL["frond"], 0.7, 0.0, True)
    frond = [mat("mk_frond_%d" % k, (0.2 + 0.05 * k, 0.42 + 0.04 * k, 0.12), 0.75) for k in range(3)]
    for k, (x, y) in enumerate(((-12.0, 12.6), (-8.0, 20.0), (1.5, 12.5), (12.0, 13.0), (-2.0, 21.0), (8.0, 20.5))):
        lean = R.uniform(-0.12, 0.12)
        hgt = R.uniform(7.0, 9.5)
        cyl(c, (x + lean * hgt / 2, y, hgt / 2), 0.17, hgt, trunk, rot=(0, lean, 0), verts=8, r2=0.12)
        tx, tz = x + lean * hgt, hgt
        for j in range(20):                                                  # fronds arching out and drooping
            a = j * 0.314 + k + R.uniform(-0.1, 0.1)
            palm_frond(c, (tx, y, tz - 0.2), a, R.uniform(3.0, 3.8), (R.uniform(0.2, 0.9), R.uniform(1.2, 2.0)), fmat)
        for j in range(9):                                                   # the bunch of nuts under the crown
            a = j * 0.7
            blob(c, (tx + 0.28 * math.cos(a), y + 0.28 * math.sin(a), tz - 0.35 - 0.12 * (j % 3)), 0.14, M["husk"], seg=8)
    # weeds and grass along the fence and at the pillars' feet
    grass = [mat("mk_grass_%d" % k, (0.3 + 0.06 * k, 0.45, 0.15), 0.85) for k in range(3)]
    for k in range(80):
        x = R.uniform(-10.5, 10.5)
        if abs(x) < 2.9 and R.random() < 0.8:
            continue
        p = (x, R.uniform(-0.5, 0.7), 0.0)
        if "grass" in PLANTS:
            plant(c, "grass" if k % 4 else "weed", p, R.uniform(1.6, 2.6), part=k)
        else:
            cyl(c, (p[0], p[1], 0.15), 0.05, R.uniform(0.2, 0.45), R.choice(grass), verts=4, r2=0.005)
    # what the police left: faded tape on the gate, torn and hanging; a pole, its camera bracket empty
    tape = tmat("mk_police_tape", T_ALL["tape"], 0.6)
    line(c, (-2.6, -0.32, 1.5), (2.6, -0.32, 1.35), 0.012, tape, 4)
    line(c, (-2.6, -0.32, 1.1), (-0.4, -0.32, 0.55), 0.012, tape, 4)             # (its end cut, fallen)
    line(c, (2.6, -0.32, 1.0), (4.0, -0.32, 0.9), 0.012, tape, 4)
    cyl(c, (-3.6, -0.6, 3.0), 0.08, 6.0, mat("mk_pole_concrete", (0.65, 0.64, 0.6), 0.9), verts=8)
    box(c, (-3.6, -0.85, 4.6), (0.06, 0.5, 0.06), M["iron"])
    box(c, (-3.6, -1.08, 4.5), (0.12, 0.04, 0.16), M["iron"])                  # the bracket, nothing on it
    # a big neem over the hut, bushes along the fence
    bark = tmat("mk_neem_bark", T_ALL["bark_neem"], 0.95)
    neem = [mat("mk_neem_%d" % k, (0.2 + 0.03 * k, 0.32 + 0.04 * k, 0.16), 0.8) for k in range(3)]
    if "neem" in PLANTS:                                                     # (a real tree, made light)
        plant(c, "neem", (6.4, 3.8, 0.0), 1.0, 0.6)
    else:
        cyl(c, (6.2, 3.6, 1.6), 0.28, 3.2, bark, verts=10, r2=0.2)
        for k in range(26):
            a = R.uniform(0, 6.3)
            rr = R.uniform(0.0, 2.8)
            blob(c, (6.2 + rr * math.cos(a), 3.6 + rr * math.sin(a), R.uniform(3.6, 5.6)), R.uniform(0.7, 1.2), R.choice(neem), (1, 1, 0.75), seg=8, lumpy=0.12)
    for k in range(12):                                                      # bushes along the fence
        x = R.choice((-1, 1)) * R.uniform(3.6, 10.5)
        if "bush" in PLANTS:
            plant(c, "bush" if k % 3 else "bush2", (x, 0.7 + R.uniform(-0.1, 0.4), 0.0), R.uniform(0.5, 0.8), part=k)
        else:
            blob(c, (x, 0.6, 0.35), 0.45, R.choice(neem), (1, 1, 0.8), seg=7, lumpy=0.15)
    # the farmers' life: a goat tied to a post, a bicycle at the hut, washing on a line, a cot, a pot on three stones
    goat = mat("mk_goat", (0.5, 0.36, 0.25), 0.9)
    goat_w = mat("mk_goat_w", (0.88, 0.85, 0.8), 0.9)
    horn = mat("mk_horn", (0.35, 0.3, 0.25), 0.6)
    gx, gy = 7.6, 5.5
    box(c, (gx + 1.1, gy, 0.5), (0.08, 0.08, 1.0), M["wood"])
    blob(c, (gx, gy, 0.6), 0.26, goat, (1.7, 0.85, 0.9), seg=12)              # the body
    blob(c, (gx - 0.42, gy, 0.82), 0.1, goat, (0.9, 0.9, 1.1), (0, -0.4, 0), seg=10)   # the neck
    blob(c, (gx - 0.58, gy, 0.95), 0.1, goat_w, (1.5, 0.85, 0.85), (0, 0.5, 0), seg=10)  # the head, the white face
    for side in (-1, 1):
        blob(c, (gx - 0.52, gy + side * 0.1, 0.98), 0.07, goat, (1.0, 0.25, 0.45), (0, 0.4, side * 0.6), seg=6)   # the ears
        cyl(c, (gx - 0.5, gy + side * 0.04, 1.08), 0.015, 0.14, horn, rot=(0, -0.8, 0), verts=5, r2=0.003)
    cyl(c, (gx - 0.7, gy, 0.86), 0.015, 0.07, goat_w, verts=5, r2=0.004)       # its beard
    for dx in (-0.3, 0.3):
        for dy in (-0.12, 0.12):
            cyl(c, (gx + dx, gy + dy, 0.2), 0.025, 0.42, goat, verts=6)
            cyl(c, (gx + dx, gy + dy, 0.015), 0.03, 0.03, horn, verts=6)
    cyl(c, (gx + 0.44, gy, 0.75), 0.03, 0.12, goat, rot=(0, -0.7, 0), verts=5, r2=0.01)   # the tail, up
    line(c, (gx + 1.1, gy, 0.8), (gx - 0.4, gy, 0.82), 0.004, M["rope"])
    box(c, (4.0, 1.8, 0.95), (0.03, 0.75, 1.85), M["iron"])                    # the hut's tin door
    for k in range(6):
        box(c, (3.98, 1.45 + k * 0.14, 0.95), (0.02, 0.02, 1.8), M["iron"])
    rope_top = tmat("mk_rope_weave", T_ALL["rope_weave"], 0.9)                # a rope cot outside the hut
    box(c, (5.0, -0.2, 0.42), (1.9, 0.9, 0.04), rope_top)
    for dx in (-0.9, 0.9):
        box(c, (5.0 + dx, -0.2, 0.42), (0.07, 0.95, 0.07), M["wood"])
        for dy in (-0.42, 0.42):
            cyl(c, (5.0 + dx, -0.2 + dy, 0.2), 0.035, 0.42, M["wood"], verts=6)
    wheel = mat("mk_bike_tyre", (0.05, 0.05, 0.05), 0.8)
    frame = mat("mk_bike_frame", (0.1, 0.1, 0.12), 0.4, 0.5)
    bx, by = 4.0, 2.7
    for dx in (-0.55, 0.55):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.33, minor_radius=0.02, location=(bx + dx, by, 0.34), rotation=(math.pi / 2, 0, 0))
        _put(bpy.context.object, wheel, c)
    for a, b in (((-0.55, 0.34), (0.0, 0.34)), ((0.0, 0.34), (0.35, 0.8)), ((-0.55, 0.34), (-0.15, 0.8)), ((-0.15, 0.8), (0.35, 0.8)),
                 ((0.55, 0.34), (0.4, 0.95)), ((-0.15, 0.8), (-0.2, 0.92))):
        line(c, (bx + a[0], by, a[1]), (bx + b[0], by, b[1]), 0.015, frame, 6)
    for x in (-12.0, -8.5):
        cyl(c, (x, 6.5, 0.9), 0.04, 1.8, M["bamboo"], verts=6)
    line(c, (-12.0, 6.5, 1.75), (-8.5, 6.5, 1.75), 0.004, M["rope"])
    lungi = tmat("mk_lungi", T_ALL["lungi"], 0.9)
    for k, col in enumerate(((0.75, 0.15, 0.2), (0.95, 0.92, 0.85), None, (0.85, 0.6, 0.15))):
        m = lungi if col is None else mat("mk_washing_%d" % k, col, 0.9)
        box(c, (-11.4 + k * 0.85, 6.5, 1.3), (0.7, 0.01, 0.9 if col is None else 0.75), m)   # a saree's end, a dhoti, a lungi, a shirt
    for k in range(3):
        a = k * 2.1
        box(c, (-7.0 + 0.18 * math.cos(a), 9.8 + 0.18 * math.sin(a), 0.08), (0.15, 0.12, 0.16), mat("mk_stone_hearth", (0.45, 0.43, 0.4), 0.95))
    cyl(c, (-7.0, 9.8, 0.3), 0.22, 0.3, mat("mk_pot_black", (0.08, 0.07, 0.07), 0.6), verts=16, r2=0.16)
    cyl(c, (-7.0, 9.8, 0.01), 0.35, 0.01, mat("mk_ash", (0.3, 0.29, 0.28), 0.95), verts=16, smooth=False)
    scatter(c, 0, 1.5, 0.04, 8.0, 3.0, 10, 4, 0)
    return c


def group(c, build, x, y, yaw=0.0, z=0.0):
    """Build a thing round the origin (front +x), then set it down at (x, y) turned by yaw."""
    t = new_coll("tmp_%d" % R.randrange(10 ** 9))
    build(t)
    bpy.ops.object.select_all(action='DESELECT')
    for o in t.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = t.objects[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob = join(t, "part")
    ob.location = (x, y, z)
    ob.rotation_euler = (0, 0, yaw)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True)
    t.objects.unlink(ob)
    c.objects.link(ob)
    bpy.data.collections.remove(t)
    return ob


def tile(ob, ux, uy):
    """Repeat an object's texture ux by uy times across it."""
    for d in ob.data.uv_layers.active.data:
        d.uv = (d.uv[0] * ux, d.uv[1] * uy)
    return ob


def rbox(coll, loc, size, m, rot=(0, 0, 0), bevel=0.05, seg=3):
    """A box with rounded edges: pressed sheet metal."""
    ob = box(coll, loc, size, m, rot)
    mod = ob.modifiers.new("Bevel", 'BEVEL')
    mod.width = bevel
    mod.segments = seg
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="Bevel")
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def tyre(c, loc, r, w, rub, rim, hub, lugs=22, front=False):
    """A tractor tyre on its rim, the wheel's axis along y: the rear's deep chevron lugs, the front's ribs."""
    x, y, z = loc
    th = r * 0.24                                                            # the casing: a fat ring, its sidewalls bulging
    bpy.ops.mesh.primitive_torus_add(major_radius=r - th - 0.03, minor_radius=th, location=(x, y, z), rotation=(math.pi / 2, 0, 0),
                                     major_segments=36, minor_segments=12)
    ob = bpy.context.object
    ob.scale = (1, 1, (w / 2) / th)
    bpy.ops.object.transform_apply(scale=True)
    _put(ob, rub, c)
    if front:
        for k in (-1, 0, 1):
            bpy.ops.mesh.primitive_torus_add(major_radius=r - 0.035, minor_radius=0.03, location=(x, y + k * w * 0.28, z),
                                             rotation=(math.pi / 2, 0, 0), major_segments=28, minor_segments=6)
            _put(bpy.context.object, rub, c)
    else:
        for k in range(lugs):                                                # two lugs a pitch, angled into a V
            a = k * 2 * math.pi / lugs
            for side in (-1, 1):
                box(c, (x + (r - 0.03) * math.cos(a), y + side * w * 0.24, z + (r - 0.03) * math.sin(a)), (0.06, w * 0.5, 0.07), rub,
                    rot=(side * 0.45, -a, 0))
    # the dished rim in the body's colour, the black centre and its studs
    cyl(c, (x, y, z), r * 0.62, w * 0.82, rim, rot=(math.pi / 2, 0, 0), verts=28)
    for side in (-1, 1):
        cyl(c, (x, y + side * w * 0.42, z), r * 0.3, 0.02, hub, rot=(math.pi / 2, 0, 0), verts=16)
        cyl(c, (x, y + side * (w * 0.42 + 0.05), z), r * 0.12, 0.1, hub, rot=(math.pi / 2, 0, 0), verts=12)
        for k in range(8):
            a = k * math.pi / 4
            cyl(c, (x + r * 0.22 * math.cos(a), y + side * (w * 0.42 + 0.02), z + r * 0.22 * math.sin(a)), 0.016, 0.04, M["steel"],
                rot=(math.pi / 2, 0, 0), verts=6)


def tractor_build(paint, stripe, canopy=False):
    """A 45-horsepower farm tractor as Indian showrooms have them (front +x, 3.6 m long): deep-lugged rear wheels on rims in
    the body's colour, little ribbed front ones, the dark engine and front axle, a bonnet sloping to its grille and
    headlamps, a decal stripe, the tall exhaust and the air cleaner's pipe, the dash and steering wheel, curved rear
    fenders with their lamps, a sprung seat, the levers, the three-point linkage and the tow hook. (A maker of the story's own.)"""
    def build(c):
        body = tmat("mk_" + paint, T_ALL[paint], 0.3, 0.15)
        dark = tmat("mk_paint_grey", T_ALL["paint_grey"], 0.45, 0.4)
        rub = tmat("mk_rubber", T_ALL["rubber"], 0.9)
        black = mat("mk_black_plastic", (0.03, 0.03, 0.03), 0.5)
        chrome = mat("mk_chrome", (0.8, 0.8, 0.82), 0.15, 1.0)
        for side in (-1, 1):
            tyre(c, (-0.75, side * 0.82, 0.78), 0.78, 0.4, rub, body, dark)
            tyre(c, (1.25, side * 0.72, 0.4), 0.4, 0.2, rub, body, dark, front=True)
        # the transmission and rear axle trumpets, the engine and sump, the front axle beam
        rbox(c, (-0.6, 0, 0.82), (0.95, 0.7, 0.7), dark, bevel=0.08)
        cyl(c, (-0.75, 0, 0.78), 0.14, 1.3, dark, rot=(math.pi / 2, 0, 0), verts=14, r2=None)
        rbox(c, (0.5, 0, 0.85), (1.4, 0.5, 0.55), dark, bevel=0.06)
        rbox(c, (0.6, 0, 0.55), (1.0, 0.42, 0.18), dark, bevel=0.04)
        for k in range(4):                                                   # the fuel pump's pipes along the block
            line(c, (0.1 + k * 0.22, 0.27, 0.9), (0.1 + k * 0.22, 0.27, 1.05), 0.012, chrome)
        box(c, (1.25, 0, 0.4), (0.14, 1.3, 0.12), dark)
        cyl(c, (1.25, 0, 0.47), 0.05, 0.2, dark, verts=10)                   # the front pivot
        # the bonnet: a rounded shell sloping down to the grille, its side louvres, the stripe
        bon = rbox(c, (0.75, 0, 1.24), (1.55, 0.62, 0.42), body, rot=(0, 0.06, 0), bevel=0.12, seg=4)
        for v in bon.data.vertices:                                          # taper the nose
            if v.co.x > 0.3:
                f = (v.co.x - 0.3) / 0.48
                v.co.y *= 1.0 - 0.12 * f
                v.co.z -= 0.06 * f
        for side in (-1, 1):
            box(c, (0.85, side * 0.315, 1.24), (1.0, 0.01, 0.05), stripe, rot=(0, 0.06, 0))
            box(c, (0.85, side * 0.315, 1.17), (1.0, 0.01, 0.02), mat("mk_stripe_dark", (0.08, 0.08, 0.08), 0.4), rot=(0, 0.06, 0))
            for k in range(5):
                box(c, (1.15 + k * 0.06, side * 0.31, 1.05), (0.025, 0.012, 0.16), black)
        # the grille, its mesh, the headlamps in their housing
        rbox(c, (1.54, 0, 1.08), (0.1, 0.56, 0.52), body, bevel=0.03)
        box(c, (1.6, 0, 1.0), (0.02, 0.44, 0.3), black)
        for k in range(6):
            box(c, (1.615, 0, 0.88 + k * 0.05), (0.01, 0.44, 0.012), chrome)
        for side in (-1, 1):
            cyl(c, (1.6, side * 0.17, 1.22), 0.07, 0.04, chrome, rot=(0, math.pi / 2, 0), verts=16)
            cyl(c, (1.625, side * 0.17, 1.22), 0.058, 0.01, mat("mk_lamp_glass", (0.92, 0.94, 0.95), 0.05, 0.2), rot=(0, math.pi / 2, 0), verts=16)
        # the front weights on their bracket, the maker's badge on the grille, the model on the bonnet's sides
        box(c, (1.72, 0, 0.62), (0.12, 0.7, 0.1), dark)
        for k in range(6):
            rbox(c, (1.82, -0.3 + k * 0.12, 0.62), (0.14, 0.1, 0.36), dark, bevel=0.02)
        text(c, "KAVERI", (1.66, 0, 1.36), 0.07, chrome, rot=(math.pi / 2, 0, math.pi / 2))
        for side in (-1, 1):
            text(c, "45 DI", (0.95, side * 0.33, 1.1), 0.08, M["plastic_white"], rot=(math.pi / 2, 0, 0 if side < 0 else math.pi))
            text(c, "KAVERI", (0.55, side * 0.33, 1.32), 0.08, M["plastic_white"], rot=(math.pi / 2, 0, 0 if side < 0 else math.pi))
        rbox(c, (-0.45, 0.95, 1.5), (0.35, 0.16, 0.16), dark, bevel=0.02)          # the tool box on the left fender
        for side in (-1, 1):                                                   # the side steps
            box(c, (-0.15, side * 0.56, 0.55), (0.3, 0.16, 0.025), mat("mk_footplate", (0.25, 0.25, 0.26), 0.6, 0.6))
            line(c, (-0.15, side * 0.5, 0.56), (-0.15, side * 0.48, 0.95), 0.015, dark)
        # the exhaust stack with its curved cap and heat shield, the air cleaner beside it
        cyl(c, (0.55, 0.22, 1.85), 0.045, 1.25, M["phone"], verts=12)
        cyl(c, (0.55, 0.22, 2.48), 0.05, 0.08, M["phone"], rot=(0, 0.9, 0), verts=12)
        cyl(c, (0.55, 0.27, 1.75), 0.06, 0.45, mat("mk_shield", (0.25, 0.25, 0.26), 0.4, 0.7), verts=12)
        cyl(c, (0.5, -0.2, 1.62), 0.07, 0.7, black, verts=12)
        cyl(c, (0.5, -0.2, 2.0), 0.1, 0.12, black, verts=14)
        # the dash and steering, the seat, the levers, the fuel tank, the steps
        rbox(c, (-0.05, 0, 1.32), (0.22, 0.5, 0.42), body, rot=(0, -0.2, 0), bevel=0.05)
        box(c, (-0.13, 0, 1.45), (0.02, 0.3, 0.12), black)
        line(c, (-0.05, 0, 1.45), (-0.3, 0, 1.78), 0.025, black)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.2, minor_radius=0.017, location=(-0.32, 0, 1.8), rotation=(0, -0.6, 0),
                                         major_segments=24, minor_segments=6)
        _put(bpy.context.object, black, c)
        rbox(c, (0.2, 0, 1.5), (0.45, 0.5, 0.1), body, bevel=0.04)           # the fuel tank's cowl
        rbox(c, (-1.0, 0, 1.38), (0.42, 0.45, 0.1), black, bevel=0.04)
        rbox(c, (-1.2, 0, 1.6), (0.08, 0.42, 0.38), black, rot=(0, 0.2, 0), bevel=0.03)
        cyl(c, (-1.0, 0, 1.22), 0.04, 0.24, dark, verts=8)
        for dx, dy, h in ((-0.6, 0.2, 0.5), (-0.7, -0.18, 0.45), (-0.85, 0.26, 0.35)):
            line(c, (dx, dy, 1.15), (dx + 0.05, dy, 1.15 + h), 0.012, black)
            blob(c, (dx + 0.05, dy, 1.17 + h), 0.03, mat("mk_knob_red", (0.7, 0.08, 0.05), 0.3), seg=8)
        box(c, (-0.3, 0, 1.0), (0.9, 1.05, 0.03), mat("mk_footplate", (0.25, 0.25, 0.26), 0.6, 0.6))
        for side in (-1, 1):
            box(c, (-0.25, side * 0.5, 0.65), (0.25, 0.14, 0.02), dark)
        # the rear fenders, curved over the wheels, with a lamp and a reflector each, and the flat platforms
        for side in (-1, 1):
            for k in range(9):
                a = math.pi * (0.3 + 0.62 * k / 8)
                ax, az = -0.75 + 0.9 * math.cos(a), 0.78 + 0.9 * math.sin(a)
                rbox(c, (ax, side * 0.82, az), (0.33, 0.48, 0.03), body, rot=(0, -a + math.pi / 2, 0), bevel=0.012, seg=2)
            box(c, (-0.75, side * 0.6, 1.4), (0.9, 0.06, 0.6), body)
            rbox(c, (-0.3, side * 1.02, 1.55), (0.12, 0.08, 0.08), chrome, bevel=0.02)
            box(c, (-0.24, side * 1.02, 1.55), (0.01, 0.06, 0.06), mat("mk_lamp_amber", (0.95, 0.55, 0.1), 0.2))
            box(c, (-1.6, side * 0.82, 1.2), (0.01, 0.08, 0.05), mat("mk_reflector", (0.8, 0.05, 0.03), 0.2))
        # the three-point linkage and the tow hook
        for side in (-1, 1):
            line(c, (-1.0, side * 0.25, 0.6), (-1.55, side * 0.35, 0.45), 0.03, dark)
        line(c, (-1.1, 0, 1.05), (-1.55, 0, 0.95), 0.03, dark)
        box(c, (-1.25, 0, 0.42), (0.4, 0.12, 0.06), dark)
        if canopy:                                                           # a sun canopy on its roll frame
            for side in (-1, 1):
                line(c, (-1.3, side * 0.62, 1.4), (-1.3, side * 0.62, 2.55), 0.03, black)
                line(c, (-0.35, side * 0.62, 1.4), (-0.35, side * 0.62, 2.55), 0.03, black)
            rbox(c, (-0.8, 0, 2.6), (1.3, 1.35, 0.06), tmat("mk_canvas_green", T_ALL["canvas_green"], 0.85), bevel=0.02)
    return build


def harvester_build(c):
    """A combine harvester on show (front +x): the green body on its big drive wheels, the glazed cab up top, the wide
    header with its cutter bar and the reel, the grain tank, the unloading auger folded back along it, the ladder."""
    body = tmat("mk_paint_green", T_ALL["paint_green"], 0.35, 0.15)
    dark = tmat("mk_paint_grey", T_ALL["paint_grey"], 0.45, 0.4)
    rub = tmat("mk_rubber", T_ALL["rubber"], 0.9)
    yellow = mat("mk_paint_yellow", (0.9, 0.7, 0.08), 0.35)
    glass = mat("mk_cab_glass", (0.12, 0.18, 0.2), 0.05, 0.3, 0.55)
    for side in (-1, 1):
        tyre(c, (0.8, side * 1.15, 0.8), 0.8, 0.5, rub, yellow, dark)
        tyre(c, (-2.0, side * 1.0, 0.5), 0.5, 0.3, rub, yellow, dark, front=True)
    rbox(c, (-0.5, 0, 1.75), (3.8, 1.9, 1.7), body, bevel=0.1)
    rbox(c, (-0.6, 0, 2.9), (1.8, 1.7, 0.6), body, bevel=0.08)                # the grain tank
    rbox(c, (1.2, 0, 3.15), (1.1, 1.2, 1.1), body, bevel=0.06)                 # the cab
    for dy in (-0.61, 0.61):
        box(c, (1.2, dy, 3.2), (0.9, 0.01, 0.75), glass)
    box(c, (1.76, 0, 3.2), (0.01, 1.0, 0.8), glass)
    box(c, (1.2, 0, 3.75), (1.25, 1.35, 0.06), mat("mk_cab_roof", (0.92, 0.92, 0.9), 0.4))
    rbox(c, (2.3, 0, 1.35), (1.2, 1.2, 0.5), body, rot=(0, -0.45, 0), bevel=0.05)   # the feeder throat
    rbox(c, (3.1, 0, 0.55), (0.9, 4.2, 0.45), yellow, bevel=0.04)             # the header
    for k in range(26):                                                       # its guards along the cutter bar
        box(c, (3.6, -2.0 + k * 0.16, 0.36), (0.18, 0.025, 0.02), M["steel"])
    for side in (-1, 1):
        rbox(c, (3.1, side * 2.12, 0.75), (1.0, 0.06, 0.8), yellow, bevel=0.02)
        line(c, (2.7, side * 2.05, 1.0), (3.3, side * 2.05, 1.35), 0.03, dark)
    cyl(c, (3.3, 0, 1.35), 0.05, 4.0, dark, rot=(math.pi / 2, 0, 0), verts=8)  # the reel and its bats
    for k in range(6):
        a = k * math.pi / 3
        box(c, (3.3 + 0.45 * math.cos(a), 0, 1.35 + 0.45 * math.sin(a)), (0.04, 3.9, 0.12), mat("mk_reel", (0.9, 0.85, 0.75), 0.6), rot=(0, -a, 0))
    line(c, (-1.4, 0.95, 3.0), (1.4, 0.95, 2.6), 0.13, body)                  # the unloading auger, folded
    for k in range(7):
        box(c, (0.4, -0.97, 0.7 + k * 0.25), (0.35, 0.03, 0.03), dark)
    for lx in (0.25, 0.55):                                                   # the ladder's rails
        line(c, (lx, -0.97, 0.6), (lx, -0.97, 2.4), 0.02, dark)


def rotavator_build(c):
    """A rotavator on its stand, as the implement makers show them in orange: the hood, the side plates, the gearbox up
    top, the hitch frame, and under the hood the rows of L-blades."""
    o = tmat("mk_paint_orange", T_ALL["paint_orange"], 0.35, 0.2)
    dark = tmat("mk_paint_grey", T_ALL["paint_grey"], 0.45, 0.4)
    cyl(c, (0, 0, 0.45), 0.38, 1.9, o, rot=(math.pi / 2, 0, 0), verts=20)     # the hood, as a drum, open below
    for side in (-1, 1):
        rbox(c, (0, side * 0.97, 0.45), (0.9, 0.04, 0.8), o, bevel=0.02)
    rbox(c, (0.05, 0, 0.98), (0.4, 0.35, 0.35), dark, bevel=0.04)            # the gearbox
    for side in (-1, 1):
        line(c, (0.1, side * 0.4, 0.8), (0.7, side * 0.4, 1.3), 0.04, o)
    line(c, (0.1, 0, 1.15), (0.6, 0, 1.6), 0.04, o)
    box(c, (-0.4, 0, 0.35), (0.02, 1.85, 0.4), o)                             # the trailing board
    for k in range(9):
        for j in range(4):
            a = j * math.pi / 2 + k
            box(c, (0.25 * math.cos(a), -0.85 + k * 0.21, 0.1 + 0.05 * math.sin(a)), (0.03, 0.06, 0.14), M["steel"], rot=(0, a, 0))
    for side in (-1, 1):
        box(c, (0, side * 0.7, 0.04), (0.6, 0.08, 0.08), dark)                # the stand


def drone_build(c):
    """A crop-spraying drone on its table: six folding arms, the rotors, the tank slung under it, the spray boom, the legs."""
    w = mat("mk_drone_white", (0.9, 0.9, 0.9), 0.35)
    k_ = mat("mk_drone_black", (0.05, 0.05, 0.05), 0.4)
    rbox(c, (0, 0, 0.35), (0.5, 0.5, 0.18), w, bevel=0.06)
    cyl(c, (0, 0, 0.18), 0.17, 0.25, mat("mk_drone_tank", (0.9, 0.92, 0.95), 0.2, 0.0, 0.8), verts=16)
    for k in range(6):
        a = k * math.pi / 3
        line(c, (0.2 * math.cos(a), 0.2 * math.sin(a), 0.36), (0.75 * math.cos(a), 0.75 * math.sin(a), 0.38), 0.02, k_)
        cyl(c, (0.75 * math.cos(a), 0.75 * math.sin(a), 0.42), 0.04, 0.07, k_, verts=10)
        box(c, (0.75 * math.cos(a), 0.75 * math.sin(a), 0.47), (0.55, 0.05, 0.008), k_, rot=(0, 0, a + 0.6))
    for side in (-1, 1):
        line(c, (0.15, side * 0.2, 0.3), (0.2, side * 0.35, 0.0), 0.012, k_)
        line(c, (-0.15, side * 0.2, 0.3), (-0.2, side * 0.35, 0.0), 0.012, k_)
        line(c, (-0.3, side * 0.35, 0.01), (0.3, side * 0.35, 0.01), 0.012, k_)
    line(c, (0, -0.55, 0.12), (0, 0.55, 0.12), 0.01, k_)


def coco_palm(c, x, y, hgt):
    trunk = tmat("mk_palm_trunk", T_ALL["bark_palm"], 0.9)
    fmat = tmat("mk_frond", T_ALL["frond"], 0.7, 0.0, True)
    lean = R.uniform(-0.1, 0.1)
    cyl(c, (x + lean * hgt / 2, y, hgt / 2), 0.17, hgt, trunk, rot=(0, lean, 0), verts=8, r2=0.12)
    tx = x + lean * hgt
    for j in range(18):
        a = j * 0.35 + R.uniform(-0.1, 0.1)
        palm_frond(c, (tx, y, hgt - 0.2), a, R.uniform(3.0, 3.6), (R.uniform(0.2, 0.9), R.uniform(1.2, 2.0)), fmat)
    for j in range(7):
        a = j * 0.9
        blob(c, (tx + 0.26 * math.cos(a), y + 0.26 * math.sin(a), hgt - 0.35 - 0.1 * (j % 3)), 0.14, M["husk"], seg=8)


def gazebo(c, x, y, title, canvas, size=3.0):
    """A pop-up gazebo: four aluminium legs, the peaked canvas roof, the valance with the exhibitor's name printed round it."""
    roof = tmat("mk_" + canvas, T_ALL[canvas], 0.85)
    for dx in (-1, 1):
        for dy in (-1, 1):
            cyl(c, (x + dx * size / 2, y + dy * size / 2, 1.2), 0.025, 2.4, M["steel"], verts=8)
    bpy.ops.mesh.primitive_cone_add(radius1=size * 0.72, radius2=0.08, depth=0.8, vertices=4, location=(x, y, 2.8), rotation=(0, 0, math.pi / 4))
    _put(bpy.context.object, roof, c, False)
    for k, (dx, dy, rz) in enumerate(((0, -1, 0), (0, 1, math.pi), (-1, 0, -math.pi / 2), (1, 0, math.pi / 2))):
        box(c, (x + dx * size / 2, y + dy * size / 2, 2.3), (size if dx == 0 else 0.01, 0.01 if dx == 0 else size, 0.25), roof)
        if dy == -1:
            text(c, title, (x, y - size / 2 - 0.012, 2.3), 0.15, M["plastic_white"] if canvas != "canvas_white" else mat("mk_letters_dark", (0.08, 0.1, 0.15), 0.5))


def booth_inside(c, x, y, w, d, poster, colour):
    """What's in a booth: the poster on the back wall, a TV on its stand, shelves of the products, a desk with a laptop,
    the brochure rack, a potted areca palm, a chair."""
    pm = tmat("mk_" + poster, T_ALL[poster], 0.5)
    box(c, (x + w * 0.15, y + d - 0.03, 1.45), (1.6, 0.01, 1.1), pm)
    box(c, (x - w * 0.3, y + d - 0.3, 0.6), (0.4, 0.3, 1.2), M["phone"])                   # the TV's stand
    box(c, (x - w * 0.3, y + d - 0.3, 1.55), (1.1, 0.05, 0.65), M["phone"])
    box(c, (x - w * 0.3, y + d - 0.33, 1.55), (1.02, 0.01, 0.58), tmat("mk_tv_screen", T_ALL["tv_screen"], 0.2))
    shelf = mat("mk_shelf", (0.85, 0.85, 0.84), 0.5)
    sx = x + w / 2 - 0.4
    for k in range(4):
        box(c, (sx, y + d / 2, 0.3 + k * 0.45), (0.5, 1.4, 0.03), shelf)
        for j in range(6):
            kind = (j + k) % 3
            pz = 0.32 + k * 0.45
            if kind == 0:                                                      # boxed parts, bottles, sacks of seed
                box(c, (sx, y + d / 2 - 0.55 + j * 0.22, pz + 0.12), (0.3, 0.16, 0.24), mat("mk_prod_box_%d" % (j % 3), tuple(min(1, v * (0.9 + 0.2 * (j % 3))) for v in colour), 0.5))
            elif kind == 1:
                cyl(c, (sx, y + d / 2 - 0.55 + j * 0.22, pz + 0.13), 0.06, 0.26, mat("mk_bottle_%d" % (j % 2), ((0.9, 0.9, 0.92), (0.2, 0.5, 0.2))[j % 2], 0.3), verts=10)
            else:
                rbox(c, (sx, y + d / 2 - 0.55 + j * 0.22, pz + 0.1), (0.28, 0.18, 0.2), M["jute"], bevel=0.04, seg=2)
    for side in (-1, 1):
        box(c, (sx, y + d / 2 + side * 0.72, 0.8), (0.5, 0.02, 1.6), shelf)
    table(c, x + 0.2, y + d - 1.1, 1.2, 0.6)
    box(c, (x + 0.2, y + d - 1.05, 0.81), (0.34, 0.24, 0.015), M["phone"])                 # the laptop, open
    box(c, (x + 0.2, y + d - 0.93, 0.93), (0.34, 0.015, 0.22), M["phone"], rot=(0.25, 0, 0))
    chair(c, x + 0.2, y + d - 0.55, math.pi, M["plastic_white"])
    cyl(c, (x - w / 2 + 0.35, y + 0.4, 0.2), 0.18, 0.4, mat("mk_planter", (0.75, 0.45, 0.3), 0.7), verts=12, r2=0.14)
    fm = tmat("mk_frond", T_ALL["frond"], 0.7, 0.0, True)
    for j in range(7):
        palm_frond(c, (x - w / 2 + 0.35, y + 0.4, 0.4), j * 0.9, 0.9, (1.2, 0.9), fm)


def booth(c, x, y, w, d, name, sub, colour, poster=None):
    """A shell-scheme booth, as the fair builds them: white panels in aluminium frames, the fascia with the exhibitor's
    name, a lightbox, a counter, a carpet, spotlights on the fascia."""
    panel = mat("mk_booth_panel", (0.94, 0.94, 0.93), 0.5)
    alu = mat("mk_alu", (0.78, 0.79, 0.8), 0.3, 0.9)
    box(c, (x, y + d / 2, 0.012), (w, d, 0.02), mat("mk_booth_carpet_%d" % int(colour[2] * 100), tuple(v * 0.5 for v in colour), 0.95))
    box(c, (x, y + d, 1.25), (w, 0.04, 2.5), panel)
    for side in (-1, 1):
        box(c, (x + side * w / 2, y + d / 2, 1.25), (0.04, d, 2.5), panel)
        cyl(c, (x + side * w / 2, y, 1.25), 0.025, 2.5, alu, verts=8)
    box(c, (x, y - 0.02, 2.65), (w + 0.05, 0.05, 0.4), mat("mk_fascia_%d" % int(colour[0] * 100 + colour[1] * 10), colour, 0.4))
    text(c, name, (x, y - 0.05, 2.68), 0.2, M["plastic_white"])
    text(c, sub, (x, y - 0.05, 2.5), 0.08, M["plastic_white"])
    for k in range(3):
        cyl(c, (x - w / 3 + k * w / 3, y + 0.1, 2.85), 0.035, 0.12, alu, rot=(0.9, 0, 0), verts=8)
    box(c, (x - w / 4, y + d - 0.04, 1.6), (1.0, 0.04, 1.4), mat("mk_lightbox", (0.95, 0.95, 0.9), 0.3))
    box(c, (x - w / 4, y + d - 0.065, 1.6), (0.9, 0.01, 1.25), mat("mk_lightbox_print_%d" % int(colour[1] * 100), tuple(min(1, v * 1.4) for v in colour), 0.4))
    rbox(c, (x + w / 4, y + 0.6, 0.5), (1.1, 0.5, 1.0), panel, bevel=0.03)   # the counter
    box(c, (x + w / 4, y + 0.34, 0.6), (1.0, 0.01, 0.3), mat("mk_fascia_%d" % int(colour[0] * 100 + colour[1] * 10), colour, 0.4))
    for k in range(4):                                                     # the brochures fanned on the counter
        box(c, (x + w / 4 - 0.3 + k * 0.2, y + 0.6, 1.01), (0.15, 0.21, 0.01),
            mat("mk_brochure_%d" % (k % 3), ((0.85, 0.2, 0.1), (0.1, 0.5, 0.25), (0.15, 0.35, 0.75))[k % 3], 0.5), rot=(0, 0, 0.15 * k))
    if poster:
        booth_inside(c, x, y, w, d, poster, colour)


def standee(c, x, y, top, line1, line2, colour):
    """A roll-up banner on its foot."""
    box(c, (x, y, 0.04), (0.85, 0.25, 0.08), M["steel"])
    box(c, (x, y, 1.05), (0.8, 0.01, 2.0), mat("mk_standee_%d" % int(colour[0] * 100 + colour[2] * 10), colour, 0.5))
    text(c, top, (x, y - 0.01, 1.8), 0.11, M["plastic_white"])
    text(c, line1, (x, y - 0.01, 1.3), 0.075, M["plastic_white"])
    text(c, line2, (x, y - 0.01, 1.15), 0.075, mat("mk_letters_yellow3", (0.98, 0.85, 0.2), 0.5))


def codissia_hall(c, x0, y0):
    """The hall behind, as CODISSIA's halls look: two storeys, white pillars between glazed doors in grey frames, a
    band of terracotta tiles, the first floor's ribbon of windows under a deep sunshade, the long blue fascia with
    the complex's name and the hall's own badge over it, steps up from the forecourt, a canopy over the way in."""
    white = mat("mk_hall_white", (0.9, 0.89, 0.86), 0.6)
    terra = tmat("mk_hall_terra", T_ALL["hall_terra"], 0.8)
    glass = mat("mk_hall_glass", (0.16, 0.22, 0.26), 0.05, 0.6)
    frame = mat("mk_hall_frame", (0.4, 0.42, 0.44), 0.4, 0.6)
    blue = mat("mk_hall_blue", (0.1, 0.42, 0.62), 0.4)
    box(c, (x0, y0 + 4.0, 4.6), (34.0, 8.0, 9.2), white)                    # the block
    tile(box(c, (x0, y0 - 0.02, 4.5), (34.0, 0.06, 1.6), terra), 12, 1)      # the terracotta band between the floors
    for k in range(11):                                                    # the ground floor: pillars, doors, frames
        px = x0 - 15.0 + k * 3.0
        box(c, (px, y0 - 0.25, 1.9), (0.55, 0.5, 3.8), white)
        if k < 10:
            gx = px + 1.5
            box(c, (gx, y0 - 0.03, 1.75), (2.4, 0.02, 3.3), glass)
            for fx in (-1.2, 0.0, 1.2):
                box(c, (gx + fx, y0 - 0.05, 1.75), (0.06, 0.03, 3.3), frame)
            box(c, (gx, y0 - 0.05, 2.5), (2.4, 0.03, 0.06), frame)
    box(c, (x0, y0 - 0.06, 6.4), (34.0, 0.02, 1.4), glass)                  # the first floor's windows and their mullions
    for k in range(23):
        box(c, (x0 - 16.5 + k * 1.5, y0 - 0.08, 6.4), (0.06, 0.03, 1.4), frame)
    box(c, (x0, y0 - 0.6, 7.25), (34.0, 1.2, 0.12), white)                  # the sunshade over them
    box(c, (x0, y0 - 0.2, 8.6), (22.0, 0.3, 1.5), blue)                     # the fascia
    text(c, "CODISSIA TRADE FAIR COMPLEX", (x0, y0 - 0.37, 8.6), 0.95, M["plastic_white"])
    box(c, (x0, y0 - 0.2, 9.75), (2.6, 0.25, 0.7), white)
    text(c, "HALL - B", (x0, y0 - 0.34, 9.75), 0.36, blue)
    box(c, (x0, y0 + 4.0, 9.35), (34.4, 8.4, 0.3), white)                    # the parapet
    for k in range(3):                                                     # the steps up from the forecourt
        box(c, (x0, y0 - 1.5 + k * 0.4, 0.08 + k * 0.15), (24.0, 0.4, 0.16 + k * 0.3), mat("mk_steps", (0.62, 0.6, 0.56), 0.8))
    for side in (-1, 1):                                                   # the canopy over the way in, on two columns
        cyl(c, (x0 + side * 3.0, y0 - 3.2, 1.9), 0.18, 3.8, white, verts=16)
    rbox(c, (x0, y0 - 2.0, 3.9), (7.0, 3.4, 0.25), white, bevel=0.05)


def agri_fair():
    """The Kovai Agri Expo (a fair of the story's own) on the CODISSIA trade fair complex's forecourt, as the farm fairs
    there look: the paved forecourt with coconut palms, the hall's white roof behind, an aisle of green turf down the
    middle; a red tractor on show (Day 18: 'Look at the tractor') and a blue one with a canopy, a combine harvester,
    orange rotavators on their stands, a spraying drone on a table; shell-scheme booths with their fascias and lightboxes,
    pop-up gazebos with their names round the valance, roll-up standees, flags, white plastic chairs, a water can."""
    c = new_coll("agri_fair")
    pav = tmat("mk_pavers", T_ALL["pavers"], 0.85)
    turf = tmat("mk_turf", T_ALL["turf"], 0.95)
    white = M["plastic_white"]
    yellow = mat("mk_letters_yellow3", (0.98, 0.85, 0.2), 0.5)
    tile(box(c, (0, 8.0, -0.02), (30.0, 30.0, 0.04), pav), 15, 15)
    tile(box(c, (0, 8.0, 0.005), (3.2, 30.0, 0.01), turf), 1.5, 14)
    codissia_hall(c, 0.0, 21.0)
    # the expo's arch over the aisle
    arch = mat("mk_banner_green", (0.1, 0.45, 0.2), 0.6)
    for x in (-2.3, 2.3):
        rbox(c, (x, -1.0, 2.1), (0.4, 0.4, 4.2), arch, bevel=0.06)
    rbox(c, (0, -1.0, 4.4), (5.6, 0.4, 1.0), arch, bevel=0.06)
    text(c, "KOVAI AGRI EXPO 2026", (0, -1.22, 4.55), 0.36, yellow)
    text(c, "Farm machinery  ·  Irrigation  ·  Seeds  ·  Dairy", (0, -1.22, 4.15), 0.13, white)
    # the tractors on show, the harvester, the rotavators, the drone
    group(c, tractor_build("paint_red", mat("mk_stripe_yellow", (0.95, 0.75, 0.1), 0.4)), -3.6, 2.6, -0.75)
    group(c, tractor_build("paint_blue", mat("mk_stripe_white", (0.95, 0.95, 0.95), 0.4), canopy=True), -4.6, 7.4, 0.2)
    group(c, harvester_build, 6.2, 10.5, math.pi - 0.15)
    for k in range(3):
        group(c, rotavator_build, 4.0 + k * 0.4, 2.2 + k * 1.6, math.pi / 2 + 0.1)
    # the booths down the right and the left, further in
    booth(c, 7.2, 4.2, 4.0, 3.0, "BHAVANI DRIP", "Drip & sprinkler systems  ·  Subsidy desk", (0.1, 0.4, 0.7), "poster_drip")
    booth(c, -7.4, 11.5, 4.0, 3.0, "SIRUVANI SEEDS", "Hybrid paddy · maize · vegetables", (0.12, 0.45, 0.2), "poster_seeds")
    booth(c, -2.8, 15.5, 4.0, 3.0, "KONGU SOLAR PUMPS", "PM-KUSUM approved", (0.85, 0.5, 0.05), "poster_solar")
    booth(c, 3.4, 15.5, 4.0, 3.0, "NOYYAL AGRO", "Rotavators · ploughs · harrows", (0.8, 0.3, 0.05), "poster_field")
    gazebo(c, -8.2, 3.0, "KAVERI TRACTORS", "canvas_orange")
    gazebo(c, 8.8, 0.2, "VAANAM AGRI DRONES", "canvas_white")
    table(c, 8.8, 0.2, 1.6, 0.8)
    group(c, drone_build, 8.8, 0.2, 0.3, 0.8)
    standee(c, -1.8, 0.6, "KAVERI 45", "45 HP · 2WD · Rs 7.2 L", "EASY EMI · Loan in 1 day", (0.62, 0.06, 0.04))
    standee(c, -2.5, 6.0, "KAVERI 39 DI", "39 HP · Canopy · Rs 6.4 L", "Exchange offer", (0.08, 0.22, 0.55))
    standee(c, 5.3, 6.0, "DRIP SUBSIDY", "upto 100% for small farmers", "Ask at the desk", (0.1, 0.4, 0.7))
    standee(c, 9.8, -0.6, "SPRAY 1 ACRE", "in 7 minutes", "Demo every hour", (0.15, 0.15, 0.18))
    # flags along the aisle, white chairs at the booths, a water can
    for k in range(3):
        for side in (-1, 1):
            fx, fy = side * 2.1, 3.0 + k * 5.0
            cyl(c, (fx, fy, 2.25), 0.03, 4.5, M["steel"], verts=8)
            fl = box(c, (fx + side * 0.45, fy, 4.05), (0.9, 0.01, 0.6), mat("mk_flag_%d" % (k % 3), ((0.1, 0.45, 0.2), (0.98, 0.8, 0.15), (0.1, 0.25, 0.6))[k % 3], 0.7))
            for v in fl.data.vertices:                                       # a ripple in the cloth
                v.co.y += 0.06 * math.sin(v.co.x * 9 + k)
    for k in range(6):
        chair(c, 6.0 + (k % 3) * 0.55, 5.0 + (k // 3) * 0.6, math.pi + R.uniform(-0.3, 0.3), white)
    for k in range(4):
        chair(c, -7.8 + k * 0.6, 2.0, R.uniform(-0.3, 0.3), white if k % 2 else M["plastic_red"])
    cyl(c, (-2.2, 9.5, 0.25), 0.15, 0.5, mat("mk_water_can", (0.3, 0.55, 0.8), 0.2, 0.0, 0.8), verts=16)
    for x, y, h in ((-13.0, 1.0, 8.5), (-12.0, 9.0, 9.5), (12.5, 3.0, 8.0), (13.0, 13.0, 9.0), (-9.0, 19.0, 9.0), (9.5, 19.0, 8.5)):
        coco_palm(c, x, y, h)
    fair_life(c)
    return c


def fair_life(c):
    """The fair's life round its edges: the registration desk under its canopy, the queue's stanchions, a sugarcane juice
    cart, a balloon seller's bunch, the food court's tent, wet-and-dry bins in pairs, flex banners on the fence."""
    white = M["plastic_white"]
    # registration, by the arch
    gazebo(c, -4.8, -3.2, "REGISTRATION · FREE ENTRY", "canvas_white", 2.6)
    table(c, -4.8, -3.0, 2.0, 0.7)
    for k in range(3):
        box(c, (-5.4 + k * 0.6, -3.0, 0.81), (0.21, 0.3, 0.01), mat("mk_form", (0.96, 0.96, 0.94), 0.8))
    for k in range(6):                                                     # the queue's posts and their ropes
        px = -6.6 + k * 0.6
        cyl(c, (px, -4.4, 0.45), 0.025, 0.9, M["steel"], verts=8)
        cyl(c, (px, -4.4, 0.02), 0.15, 0.04, M["steel"], verts=12)
        if k:
            line(c, (px - 0.6, -4.4, 0.85), (px, -4.4, 0.85), 0.015, mat("mk_rope_red", (0.6, 0.06, 0.06), 0.8))
    # the sugarcane juice cart
    jx, jy = 10.6, -3.6
    box(c, (jx, jy, 0.75), (1.6, 0.9, 0.08), M["wood"])
    for dx in (-0.6, 0.6):
        cyl(c, (jx + dx, jy, 0.35), 0.33, 0.06, M["iron"], rot=(math.pi / 2, 0, 0), verts=16)
    rbox(c, (jx - 0.3, jy, 1.05), (0.5, 0.5, 0.55), mat("mk_crusher", (0.15, 0.4, 0.2), 0.4, 0.3), bevel=0.04)
    cyl(c, (jx - 0.3, jy - 0.3, 1.1), 0.25, 0.05, M["steel"], rot=(math.pi / 2, 0, 0), verts=16)
    for k in range(14):                                                    # the canes stacked against it
        line(c, (jx + 0.2 + k * 0.03, jy + 0.4, 0.8), (jx + 0.4 + k * 0.03, jy + 0.35, 2.4), 0.02, mat("mk_cane", (0.45, 0.42, 0.18), 0.6))
    for k in range(4):
        cyl(c, (jx + 0.4 + k * 0.1, jy - 0.3, 0.87), 0.035, 0.12, mat("mk_glass_juice", (0.6, 0.75, 0.3), 0.1, 0.0, 0.7), verts=8)
    cyl(c, (jx, jy, 1.6), 0.025, 1.7, M["steel"], verts=6)
    bpy.ops.mesh.primitive_cone_add(radius1=1.2, radius2=0.03, depth=0.4, vertices=12, location=(jx, jy, 2.5))
    _put(bpy.context.object, M["umbrella"], c, False)
    box(c, (jx, jy - 0.47, 0.6), (1.4, 0.01, 0.25), mat("mk_juice_board", (0.95, 0.85, 0.2), 0.5))
    text(c, "KARUMBU JUICE  Rs 30", (jx, jy - 0.48, 0.6), 0.1, mat("mk_letters_red", (0.75, 0.1, 0.08), 0.5))
    # the balloon seller's bunch
    bx, by = 3.6, -3.8
    cyl(c, (bx, by, 1.0), 0.02, 2.0, M["bamboo"], verts=6)
    for k in range(16):
        a, h = k * 2.4, 2.1 + (k % 4) * 0.18
        px, py = bx + 0.3 * math.cos(a), by + 0.3 * math.sin(a)
        line(c, (bx, by, 1.9), (px, py, h - 0.15), 0.003, M["string"])
        blob(c, (px, py, h), 0.14, mat("mk_balloon_%d" % (k % 5), ((0.9, 0.1, 0.1), (0.95, 0.8, 0.1), (0.1, 0.4, 0.9), (0.2, 0.7, 0.3), (0.9, 0.3, 0.6))[k % 5], 0.25),
             scale=(1, 1, 1.2), seg=10)
    # the food court's tent at the back
    gazebo(c, 10.4, 16.0, "FOOD COURT · TIFFIN · MEALS · TEA", "canvas_green", 4.0)
    for k in range(3):
        table(c, 9.2 + k * 1.2, 16.0, 1.0, 0.7)
        for side in (-1, 1):
            chair(c, 9.2 + k * 1.2, 16.0 + side * 0.6, math.pi if side > 0 else 0.0, white)
    # the bins, a pair at each corner of the aisle
    for bx2, by2 in ((-2.9, -0.4), (3.2, -0.4), (-2.9, 13.4), (2.9, 13.4)):
        for j, (col, word) in enumerate((((0.1, 0.5, 0.2), "WET"), ((0.1, 0.3, 0.7), "DRY"))):
            cyl(c, (bx2 + j * 0.45 - 0.22, by2, 0.4), 0.2, 0.8, mat("mk_bin_%s" % word, col, 0.4), verts=14, r2=0.18)
    # the fence down the left with the flex banners tied on it
    for k in range(12):
        fy = -4.0 + k * 2.2
        cyl(c, (-14.6, fy, 0.9), 0.03, 1.8, M["iron"], verts=6)
    box(c, (-14.6, 8.1, 1.7), (0.03, 24.2, 0.04), M["iron"])
    box(c, (-14.6, 8.1, 0.2), (0.03, 24.2, 0.04), M["iron"])
    for k, (word, col) in enumerate((("TRACTOR LOANS IN 24 HRS", (0.75, 0.1, 0.08)), ("ORGANIC MANURE · VERMICOMPOST", (0.12, 0.45, 0.2)),
                                     ("COCONUT CLIMBER · Rs 4,500", (0.85, 0.5, 0.05)), ("DAIRY FEED · CATTLE MATS", (0.1, 0.3, 0.7)))):
        fy = -2.0 + k * 5.5
        box(c, (-14.56, fy, 1.0), (0.01, 4.0, 1.1), mat("mk_flex_%d" % k, col, 0.6))
        text(c, word, (-14.54, fy, 1.0), 0.17, M["plastic_white"], rot=(math.pi / 2, 0, math.pi / 2))


def table(c, x, y, w=1.8, d=0.7):
    box(c, (x, y, 0.78), (w, d, 0.04), M["wood"])
    box(c, (x, y, 0.4), (w - 0.05, d - 0.05, 0.76), mat("mk_tablecloth", (0.92, 0.92, 0.95), 0.9))


def panel(c, loc, w, h, m):
    """A flat picture facing -y (the street), its texture whole on it: a board's picture, a poster."""
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc, rotation=(math.pi / 2, 0, 0))
    ob = bpy.context.object
    ob.scale = (w, h, 1)
    bpy.ops.object.transform_apply(scale=True)
    return _put(ob, m, c, False)


def glow(name, colour, strength=3.0):
    """A thing that gives light: a tubelight, a lit sign."""
    m = mat(name, colour, 0.5)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Emission Color"].default_value = (*colour, 1.0)
    b.inputs["Emission Strength"].default_value = strength
    return m


def street_umbrella(c, x, y, cloth, stripe=None, h=2.25, r=1.4, tilt=0.12):
    """A big pavement umbrella as the vendors use them: a pole a little off true, the canopy in eight panels on its
    ribs, sagging between them, a scalloped valance; its cloth sun-faded and stained (and every other panel white,
    if "stripe")."""
    cyl(c, (x, y, h / 2), 0.028, h, M["steel"], rot=(tilt * 0.3, -tilt, 0), verts=8)
    top = Vector((x - tilt * h * 0.5, y + tilt * h * 0.15, h + 0.02))
    cm = tmat("mk_" + cloth, T_ALL[cloth], 0.85)
    sm = mat("mk_umb_white", (0.9, 0.88, 0.82), 0.85) if stripe else cm
    for k in range(8):
        a0, a1 = k * math.pi / 4, (k + 1) * math.pi / 4
        bm = bmesh.new()
        verts = [bm.verts.new(top + Vector((0, 0, 0.42)))]
        for j in range(7):                                                    # the panel's edge, sagging between ribs
            a = a0 + (a1 - a0) * j / 6
            sag = 0.08 * math.sin(math.pi * j / 6)
            verts.append(bm.verts.new(top + Vector((r * (1 - sag) * math.cos(a), r * (1 - sag) * math.sin(a), 0.0))))
        for j in range(1, 7):
            bm.faces.new((verts[0], verts[j], verts[j + 1]))
        me = bpy.data.meshes.new("umb")
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new("umb", me)
        c.objects.link(ob)
        ob.data.materials.append(sm if (stripe and k % 2) else cm)
        mod = ob.modifiers.new("Solid", 'SOLIDIFY')
        mod.thickness = 0.012
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.ops.object.modifier_apply(modifier="Solid")
        for j in range(5):                                                    # the scalloped valance under its edge
            a = a0 + (a1 - a0) * (j + 0.5) / 5
            box(c, top + Vector((r * 0.99 * math.cos(a), r * 0.99 * math.sin(a), -0.08)), (0.2, 0.01, 0.16), sm if (stripe and k % 2) else cm,
                rot=(0, 0, a + math.pi / 2))
        line(c, top + Vector((0, 0, 0.42)), top + Vector((r * math.cos(a0), r * math.sin(a0), 0.0)), 0.006, M["steel"])   # its rib


def townhall_pavement():
    """Town Hall's pavement (Day 14, the key-cutter search), as these footpaths are: a compound wall with torn posters
    and a painted 'stick no bills', a neem's shade, an electric pole and its tangle of wires, a bin, a parked
    bicycle; and three big umbrellas, only one of which cuts keys:
      the cobbler (black umbrella): his wooden box with its drawers, the iron last, a tarp of chappals and shoes in
        rows, polish tins and brushes, a tin of nails;
      the phone-cover boy (blue and white): a folding table under covers in their packets hanging on strings,
        screen guards fanned out, earphones and chargers on hooks, his board 'COVERS Rs 99';
      the key-cutter (faded red and white): his low box with a vice and a hand-cranked cutter, two boards of key
        blanks on nails, a row of padlocks, a glass-topped box of keys, a tin of filings, his stool, and a painted
        tin board KEYS · LOCK REPAIR with his number."""
    c = new_coll("townhall_pavement")
    pav = tmat("mk_pavers", T_ALL["pavers"], 0.85)
    tile(box(c, (0, 0.6, 0.06), (28.0, 3.4, 0.12), pav), 12, 2)
    box(c, (0, -1.1, 0.07), (28.0, 0.2, 0.14), mat("mk_kerb", (0.62, 0.6, 0.55), 0.8))
    for k in range(14):                                                       # the kerb's paint, black and yellow
        box(c, (-13.5 + k * 2.0, -1.21, 0.08), (1.0, 0.01, 0.12), mat("mk_kerb_yellow", (0.9, 0.75, 0.15), 0.7))
    wall = tmat("mk_plaster_stained", T_ALL["plaster_stained"], 0.9)
    tile(box(c, (0, 2.4, 1.2), (28.0, 0.25, 2.4), wall), 7, 1)
    box(c, (0, 2.4, 2.45), (28.2, 0.35, 0.1), mat("mk_coping", (0.7, 0.68, 0.62), 0.8))
    for k in range(7):                                                        # posters pasted over posters, torn
        for j in range(2):
            box(c, (-12 + k * 3.9 + j * 0.5, 2.26 - j * 0.005, 1.35 + j * 0.15), (0.75, 0.01, 1.0),
                mat("mk_poster_%d" % ((k + j) % 4), ((0.85, 0.75, 0.2), (0.75, 0.2, 0.15), (0.2, 0.4, 0.7), (0.9, 0.9, 0.85))[(k + j) % 4], 0.8))
    text(c, "STICK NO BILLS", (4.0, 2.26, 2.05), 0.16, mat("mk_letters_black", (0.05, 0.05, 0.05), 0.6))
    if "neem" in PLANTS:                                                      # a neem's shade over the cobbler
        plant(c, "neem", (-9.5, 3.4, 0.0), 0.75)
    cyl(c, (11.5, -0.7, 4.5), 0.13, 9.0, mat("mk_pole", (0.55, 0.54, 0.5), 0.8), verts=10, r2=0.09)   # the electric pole
    box(c, (11.5, -0.7, 8.6), (1.8, 0.12, 0.12), mat("mk_pole", (0.55, 0.54, 0.5), 0.8))
    for k in range(5):                                                        # its wires, sagging away both ways
        for side in (-1, 1):
            z = 8.65 + (k % 2) * 0.1
            line(c, (11.5 - 0.8 + k * 0.4, -0.7, z), (11.5 - 0.8 + k * 0.4 + side * 14, -0.7 + side * 0.5, z - 0.9), 0.008, M["phone"])
    box(c, (11.5, -0.55, 1.6), (0.3, 0.15, 0.4), mat("mk_meter", (0.5, 0.52, 0.5), 0.6, 0.3))
    cyl(c, (-3.6, 1.9, 0.45), 0.25, 0.8, mat("mk_bin_green", (0.1, 0.5, 0.2), 0.4), verts=14, r2=0.22)   # a bin
    for dx in (-0.45, 0.45):                                                  # a bicycle against the wall
        bpy.ops.mesh.primitive_torus_add(major_radius=0.33, minor_radius=0.015, location=(-14.0 + 3.5 + dx, 2.05, 0.45), rotation=(math.pi / 2, 0, 0))
        _put(bpy.context.object, M["phone"], c)
    line(c, (-10.95, 2.05, 0.45), (-10.3, 2.05, 0.85), 0.018, mat("mk_cycle", (0.1, 0.12, 0.35), 0.5, 0.5))
    line(c, (-10.3, 2.05, 0.85), (-10.05, 2.05, 0.45), 0.018, mat("mk_cycle", (0.1, 0.12, 0.35), 0.5, 0.5))
    line(c, (-10.95, 2.05, 0.45), (-10.55, 2.05, 0.95), 0.018, mat("mk_cycle", (0.1, 0.12, 0.35), 0.5, 0.5))
    # the cobbler
    street_umbrella(c, -7.0, 0.9, "umb_black")
    box(c, (-7.0, 1.4, 0.32), (0.9, 0.5, 0.4), M["wood"])
    for j in range(3):
        box(c, (-7.3 + j * 0.3, 1.14, 0.3), (0.24, 0.01, 0.12), mat("mk_drawer", (0.35, 0.22, 0.12), 0.7))
    box(c, (-7.0, 0.4, 0.125), (1.8, 1.3, 0.008), tmat("mk_tarp_blue", T_ALL["tarp_blue"], 0.6))
    cyl(c, (-6.7, 0.9, 0.3), 0.03, 0.35, M["iron"], verts=8)
    box(c, (-6.7, 0.9, 0.5), (0.24, 0.08, 0.07), M["iron"])
    for row in range(2):
        for k in range(6):
            col = ((0.4, 0.25, 0.12), (0.08, 0.08, 0.08), (0.6, 0.2, 0.15), (0.75, 0.6, 0.4))[(k + row) % 4]
            box(c, (-7.75 + k * 0.28, 0.0 + row * 0.35, 0.145), (0.1, 0.27, 0.03), mat("mk_chappal_%d" % ((k + row) % 4), col, 0.6), rot=(0, 0, 0.1 * (k % 3)))
            if row == 1 and k % 2:
                box(c, (-7.75 + k * 0.28, 0.35, 0.2), (0.1, 0.24, 0.1), mat("mk_shoe_%d" % k, col, 0.4))
    for k in range(4):
        cyl(c, (-6.55 + k * 0.1, 1.45, 0.54), 0.04, 0.03, mat("mk_polish", (0.1, 0.1, 0.12), 0.3, 0.4), verts=10)
    box(c, (-7.3, 1.45, 0.56), (0.18, 0.06, 0.05), mat("mk_brush", (0.35, 0.2, 0.1), 0.8))
    # the phone-cover boy
    street_umbrella(c, 0.0, 0.9, "umb_blue", stripe=True)
    box(c, (0.0, 1.0, 0.85), (1.7, 0.65, 0.04), mat("mk_table_white", (0.9, 0.9, 0.88), 0.5))
    for dx in (-0.8, 0.8):
        line(c, (dx, 0.75, 0.12), (dx, 1.25, 0.83), 0.015, M["steel"])
        line(c, (dx, 1.25, 0.12), (dx, 0.75, 0.83), 0.015, M["steel"])
    for j in range(4):                                                        # covers in packets on strings
        z = 1.95 - j * 0.28
        line(c, (-0.85, 1.35, z + 0.12), (0.85, 1.35, z + 0.12), 0.004, M["string"])
        for k in range(10):
            box(c, (-0.78 + k * 0.17, 1.35, z), (0.1, 0.012, 0.2), mat("mk_cover_%d" % ((k + j) % 6),
                ((0.9, 0.2, 0.4), (0.1, 0.1, 0.1), (0.2, 0.6, 0.9), (0.95, 0.8, 0.2), (0.6, 0.3, 0.8), (0.3, 0.8, 0.4))[(k + j) % 6], 0.25))
    for dx in (-0.85, 0.85):
        cyl(c, (dx, 1.35, 1.1), 0.015, 2.0, M["steel"], verts=6)
    for k in range(12):
        box(c, (-0.65 + k * 0.11, 0.85, 0.875), (0.08, 0.15, 0.008), mat("mk_guard", (0.85, 0.9, 0.95), 0.1, 0.0, 0.6), rot=(0, 0, 0.05 * (k - 6)))
    for k in range(5):                                                        # earphones, chargers on hooks
        line(c, (0.5 + k * 0.07, 1.1, 1.2), (0.5 + k * 0.07, 1.1, 0.95), 0.006, M["plastic_white"] if k % 2 else M["phone"])
    box(c, (0.0, 0.67, 0.68), (1.1, 0.01, 0.32), mat("mk_board_yellow", (0.98, 0.85, 0.2), 0.6))
    text(c, "COVERS  Rs 99", (0.0, 0.66, 0.72), 0.12, mat("mk_letters_red", (0.75, 0.1, 0.08), 0.5))
    text(c, "Screen guard fitting", (0.0, 0.66, 0.6), 0.06, M["phone"])
    # the key-cutter
    street_umbrella(c, 7.0, 0.9, "umb_red", stripe=True)
    box(c, (7.0, 1.15, 0.36), (1.1, 0.6, 0.48), M["wood"])
    box(c, (7.0, 1.15, 0.61), (1.0, 0.5, 0.02), mat("mk_glasstop", (0.7, 0.8, 0.85), 0.05, 0.0, 0.45))   # its glass top
    brass = mat("mk_brass_key", (0.78, 0.62, 0.25), 0.35, 0.8)
    for k in range(30):                                                       # keys under the glass
        box(c, (6.6 + (k % 10) * 0.08, 1.0 + (k // 10) * 0.12, 0.59), (0.02, 0.06, 0.006), brass if k % 3 else M["steel"], rot=(0, 0, 0.3 * (k % 4)))
    box(c, (6.7, 1.0, 0.68), (0.12, 0.16, 0.12), M["iron"])                   # the vice
    box(c, (7.3, 1.2, 0.71), (0.3, 0.2, 0.18), mat("mk_cutter_grey", (0.45, 0.47, 0.5), 0.4, 0.5))
    cyl(c, (7.3, 1.08, 0.75), 0.08, 0.02, M["steel"], rot=(math.pi / 2, 0, 0), verts=16)
    line(c, (7.46, 1.2, 0.8), (7.56, 1.2, 1.0), 0.012, M["iron"])
    blob(c, (7.56, 1.2, 1.02), 0.025, M["plastic_red"], seg=8)
    for bx in (6.45, 7.55):                                                   # two boards of blanks on nails
        box(c, (bx, 2.05, 1.15), (1.0, 0.04, 1.1), mat("mk_keyboard", (0.2, 0.3, 0.45), 0.7), rot=(0.1, 0, 0))
        for k in range(70):
            box(c, (bx - 0.43 + (k % 10) * 0.095, 2.0 - 0.01 * (k // 10), 0.72 + (k // 10) * 0.12), (0.022, 0.006, 0.07),
                brass if (k + int(bx)) % 3 else M["steel"], rot=(0.1, 0, 0))
    for k in range(14):                                                       # padlocks hanging along the top
        px = 6.05 + k * 0.14
        box(c, (px, 1.98, 1.83), (0.08, 0.03, 0.07), brass if k % 3 else M["steel"])
        bpy.ops.mesh.primitive_torus_add(major_radius=0.025, minor_radius=0.006, location=(px, 1.98, 1.89), rotation=(math.pi / 2, 0, 0))
        _put(bpy.context.object, M["steel"], c)
    cyl(c, (6.55, 1.5, 0.66), 0.07, 0.06, mat("mk_tin", (0.6, 0.6, 0.55), 0.4, 0.6), verts=12)
    cyl(c, (7.7, 0.35, 0.2), 0.16, 0.38, M["plastic_red"], verts=14)
    tin = mat("mk_tin_board", (0.92, 0.9, 0.82), 0.6, 0.3)
    box(c, (7.0, 0.38, 0.5), (0.9, 0.02, 0.45), tin)
    text(c, "KEYS", (7.0, 0.365, 0.6), 0.14, mat("mk_letters_red", (0.75, 0.1, 0.08), 0.5))
    text(c, "LOCK REPAIR · DUPLICATE KEY", (7.0, 0.365, 0.44), 0.045, M["phone"])
    text(c, "94433 2•••8", (7.0, 0.365, 0.35), 0.05, M["phone"])
    return c


def shopfront(c, x, w, name, sub, col, pic, goods, D=1.5):
    """One shop of a row, D metres deep (shallow, as the small shops are, and so clear of the city's houses behind):
    its walls, the concrete sunshade over the front, the rolling shutter up, the board with its picture and name, a
    tubelight inside, a glass counter across the front, shelves of what it sells on the back wall."""
    wallc = mat("mk_shop_wall", (0.86, 0.84, 0.78), 0.8)
    for dx in (-w / 2, w / 2):
        box(c, (x + dx, D / 2, 1.75), (0.25, D, 3.5), wallc)
    box(c, (x, D, 1.75), (w, 0.2, 3.5), wallc)
    box(c, (x, D / 2, 0.17), (w, D, 0.06), mat("mk_shop_floor", (0.82, 0.8, 0.76), 0.25))   # the tiled floor
    box(c, (x, -0.15, 0.12), (w, 0.6, 0.24), mat("mk_step", (0.55, 0.53, 0.5), 0.8))       # the step
    box(c, (x, -0.35, 3.3), (w + 0.25, 1.1, 0.1), mat("mk_chajja", (0.75, 0.73, 0.68), 0.85))   # the sunshade
    box(c, (x, 0.05, 3.05), (w - 0.3, 0.35, 0.35), tmat("mk_shutter", T_ALL["shutter"], 0.5, 0.5))   # the shutter, up
    box(c, (x, -0.15, 3.8), (w, 0.12, 0.8), mat("mk_shopboard_%s" % pic, col, 0.4))
    panel(c, (x - w / 2 + 0.55, -0.225, 3.8), 0.7, 0.7, tmat("mk_" + pic, T_ALL[pic], 0.4))
    text(c, name, (x + 0.35, -0.22, 3.92), 0.24, M["plastic_white"])
    text(c, sub, (x + 0.35, -0.22, 3.62), 0.1, M["plastic_white"])
    box(c, (x, D / 2, 3.2), (1.2, 0.05, 0.04), glow("mk_tubelight", (1.0, 1.0, 0.95), 4.0))   # the tubelight
    box(c, (x - 0.5, 0.42, 0.65), (w - 1.8, 0.4, 0.9), mat("mk_counter_base", (0.9, 0.9, 0.88), 0.4))   # (a gap to step in)
    box(c, (x - 0.5, 0.42, 1.12), (w - 1.8, 0.4, 0.03), mat("mk_counter_glass", (0.7, 0.85, 0.9), 0.05, 0.0, 0.4))
    for j in range(4):
        box(c, (x, D - 0.22, 0.9 + j * 0.5), (w - 0.5, 0.3, 0.03), mat("mk_shelf", (0.85, 0.85, 0.84), 0.5))
        for i in range(int((w - 0.7) / 0.32)):
            gc = goods[(i + j) % len(goods)]
            box(c, (x - w / 2 + 0.45 + i * 0.32, D - 0.22, 1.03 + j * 0.5), (0.22, 0.2, 0.22 if j % 2 else 0.18), mat("mk_goods_%d_%d_%d" % tuple(int(v * 99) for v in gc), gc, 0.45))


def rsp_shoprow():
    """R.S. Puram by the flyover (Day 14, the key shop search), as these rows are: a two-storey block with grilled
    windows, a sintex tank on the roof and a tuition centre's board upstairs, over four shops: AMMAN MOBILES,
    KOVAI SWEETS & BAKERY (a glass cabinet of sweets on the step), SAI MEDICALS (a lit green cross), and by the
    flyover's pier VINAYAGA KEY WORKS (car keys, remotes, locks: a board of blanks hung outside like the street
    cutters, an electronic key machine and a laptop with its programmer on the counter). Meter boxes and wires, a
    plastic chair, a crate of empty bottles. (The shops' names are the story's own.)"""
    c = new_coll("rsp_shoprow")
    pav = tmat("mk_pavers", T_ALL["pavers"], 0.85)
    tile(box(c, (0, -0.95, 0.06), (18.0, 1.3, 0.12), pav), 8, 1)                # (a narrow footpath: the row stands close to the road)
    box(c, (0, -1.65, 0.08), (18.0, 0.2, 0.16), mat("mk_kerb", (0.62, 0.6, 0.55), 0.8))
    shops = (("AMMAN MOBILES", "Recharge · Accessories · Service", (0.82, 0.1, 0.1), "pic_phone",
              ((0.1, 0.1, 0.12), (0.9, 0.9, 0.92), (0.2, 0.5, 0.9), (0.9, 0.3, 0.4))),
             ("KOVAI SWEETS & BAKERY", "Sweets · Savouries · Cakes", (0.92, 0.55, 0.08), "pic_sweets",
              ((0.95, 0.75, 0.2), (0.9, 0.5, 0.15), (0.95, 0.9, 0.7), (0.6, 0.35, 0.15))),
             ("SAI MEDICALS", "24 hrs · Free home delivery", (0.08, 0.5, 0.28), "pic_cross",
              ((0.95, 0.95, 0.95), (0.3, 0.6, 0.9), (0.9, 0.4, 0.3), (0.95, 0.85, 0.3))),
             ("VINAYAGA KEY WORKS", "Car keys · Remotes · Locks", (0.1, 0.24, 0.58), "pic_key",
              ((0.78, 0.62, 0.25), (0.75, 0.76, 0.78), (0.1, 0.1, 0.12))))
    for k, (name, sub, col, pic, goods) in enumerate(shops):
        shopfront(c, -6.0 + k * 4.0, 4.0, name, sub, col, pic, goods)
    # the floors above: a slab, the walls with grilled windows, a tuition centre's board, the roof's water tank
    upper = mat("mk_upper_wall", (0.78, 0.72, 0.6), 0.85)
    box(c, (0, 0.8, 3.6), (16.4, 1.8, 0.2), mat("mk_slab", (0.72, 0.7, 0.66), 0.85))
    box(c, (0, 0.8, 5.4), (16.4, 1.6, 3.4), upper)
    box(c, (0, 0.8, 7.2), (16.6, 1.8, 0.2), mat("mk_slab", (0.72, 0.7, 0.66), 0.85))
    grill = mat("mk_grill", (0.15, 0.25, 0.22), 0.5, 0.5)
    for k in range(6):
        wx = -6.5 + k * 2.6
        box(c, (wx, -0.02, 5.3), (1.2, 0.02, 1.3), mat("mk_window_glass", (0.25, 0.32, 0.36), 0.1, 0.4))
        for j in range(5):
            box(c, (wx - 0.5 + j * 0.25, -0.05, 5.3), (0.02, 0.02, 1.3), grill)
        box(c, (wx, -0.25, 6.05), (1.5, 0.5, 0.06), mat("mk_chajja", (0.75, 0.73, 0.68), 0.85))
    box(c, (-3.2, -0.08, 4.35), (4.0, 0.06, 0.8), mat("mk_tuition", (0.95, 0.9, 0.3), 0.5))
    text(c, "BRIGHT TUITION CENTRE · 1st floor", (-3.2, -0.12, 4.35), 0.16, mat("mk_letters_blue", (0.1, 0.22, 0.5), 0.4))
    cyl(c, (5.5, 0.8, 8.0), 0.65, 1.4, mat("mk_sintex", (0.12, 0.12, 0.12), 0.6), verts=20)   # the black water tank
    for k in range(3):                                                         # meter boxes and their wires
        box(c, (-7.9, -0.02, 2.2 + k * 0.45), (0.35, 0.15, 0.35), mat("mk_meter", (0.5, 0.52, 0.5), 0.6, 0.3))
        line(c, (-7.9, -0.1, 2.4 + k * 0.45), (-7.9 - 0.3, -0.2, 3.2), 0.01, M["phone"])
    # out on the step: the sweet shop's glass cabinet, a chair, a crate of bottles; the key works' board outside
    box(c, (-2.0, -0.6, 0.75), (1.4, 0.55, 1.1), mat("mk_cabinet_glass", (0.75, 0.85, 0.9), 0.05, 0.0, 0.35))
    for j in range(3):
        for i in range(6):
            box(c, (-2.55 + i * 0.22, -0.6, 0.4 + j * 0.32), (0.18, 0.4, 0.06),
                mat("mk_sweet_%d" % ((i + j) % 4), ((0.95, 0.75, 0.2), (0.9, 0.5, 0.15), (0.95, 0.9, 0.7), (0.6, 0.35, 0.15))[(i + j) % 4], 0.5))
    chair(c, 3.0, -0.7, 0.4, M["plastic_white"])
    box(c, (-5.0, -0.6, 0.27), (0.45, 0.32, 0.3), M["crate_red"])
    brass = mat("mk_brass_key", (0.78, 0.62, 0.25), 0.35, 0.8)
    box(c, (7.6, -0.25, 1.5), (0.8, 0.04, 1.1), mat("mk_keyboard", (0.2, 0.3, 0.45), 0.7))
    for k in range(48):
        box(c, (7.28 + (k % 8) * 0.09, -0.29, 1.08 + (k // 8) * 0.15), (0.022, 0.006, 0.07), brass if k % 3 else M["steel"])
    kx = 6.0                                                                   # inside: the machine, the laptop, remotes
    box(c, (kx - 0.1, 0.45, 1.32), (0.45, 0.32, 0.38), mat("mk_keymachine", (0.85, 0.85, 0.82), 0.3, 0.3))
    box(c, (kx - 0.1, 0.28, 1.38), (0.3, 0.01, 0.15), glow("mk_screen_lit", (0.3, 0.8, 0.5), 1.5))
    box(c, (kx - 1.0, 0.45, 1.15), (0.34, 0.24, 0.015), M["phone"])
    box(c, (kx - 1.0, 0.57, 1.27), (0.34, 0.015, 0.22), glow("mk_laptop_lit", (0.5, 0.65, 0.95), 1.2), rot=(0.25, 0, 0))
    box(c, (kx - 0.55, 0.4, 1.17), (0.16, 0.1, 0.05), mat("mk_programmer", (0.4, 0.42, 0.45), 0.4))
    for k in range(5):
        box(c, (kx - 1.6 + k * 0.12, 0.35, 1.15), (0.05, 0.1, 0.02), M["phone"])
    glowc = glow("mk_cross_lit", (0.1, 0.9, 0.3), 3.0)                         # the pharmacy's lit cross
    box(c, (3.6, -0.3, 2.7), (0.08, 0.5, 0.15), glowc)
    box(c, (3.6, -0.3, 2.7), (0.08, 0.15, 0.5), glowc)
    # the flyover beside the row: a pier, its cap, the deck going over the road
    concrete = tmat("mk_plaster_stained", T_ALL["plaster_stained"], 0.9)
    box(c, (10.8, 0.5, 4.5), (1.6, 1.6, 9.0), concrete)
    box(c, (10.8, -3.0, 9.4), (2.4, 10.0, 0.8), concrete)
    box(c, (10.8, -3.0, 10.3), (12.0, 16.0, 1.0), concrete)
    for k in range(3):                                                         # posters on the pier
        box(c, (10.8 - 0.81, 0.5, 1.6 + k * 0.9), (0.01, 0.9, 0.7), mat("mk_poster_%d" % (k % 4), ((0.85, 0.75, 0.2), (0.75, 0.2, 0.15), (0.2, 0.4, 0.7), (0.9, 0.9, 0.85))[k % 4], 0.8))
    return c


def cash_bag():
    """The bag Suresh puts on his car's bonnet at the trap (Day 16): a black zip bag, half open, bundles of
    five-hundred-rupee notes inside under their paper bands. (It stands on the ground at its origin; the story lifts it.)"""
    c = new_coll("cash_bag")
    blk = mat("mk_bag_black", (0.05, 0.05, 0.06), 0.55)
    rbox(c, (0, 0, 0.13), (0.46, 0.26, 0.26), blk, bevel=0.05)
    box(c, (0, 0, 0.265), (0.4, 0.03, 0.01), mat("mk_zip", (0.6, 0.6, 0.6), 0.3, 0.8))
    for side in (-1, 1):                                                       # its handles
        bpy.ops.mesh.primitive_torus_add(major_radius=0.1, minor_radius=0.012, location=(0, side * 0.08, 0.28), rotation=(math.pi / 2, 0, 0))
        _put(bpy.context.object, blk, c)
    note = mat("mk_note500", (0.62, 0.64, 0.6), 0.7)
    band = mat("mk_band", (0.92, 0.9, 0.85), 0.7)
    for k in range(6):                                                         # bundles peeking out of the open zip
        x = -0.15 + (k % 3) * 0.15
        y = -0.03 + (k // 3) * 0.06
        box(c, (x, y, 0.27 + 0.01 * (k % 2)), (0.14, 0.06, 0.05), note, rot=(0.2 * (k % 2), 0, 0.1 * (k - 3)))
        box(c, (x, y, 0.27 + 0.01 * (k % 2)), (0.02, 0.062, 0.052), band, rot=(0.2 * (k % 2), 0, 0.1 * (k - 3)))
    return c


BUILD = {"market_vegcart": vegcart, "market_groundstall": groundstall, "market_banana": banana, "market_crates": crates,
         "market_teakadai": teakadai, "bala_workshop": workshop, "bala_workshop_closed": workshop_closed,
         "pudhur_site": pudhur_site, "agri_fair": agri_fair, "townhall_pavement": townhall_pavement, "rsp_shoprow": rsp_shoprow,
         "cash_bag": cash_bag}


def join(coll, name):
    obs = [o for o in coll.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = bpy.context.object
    ob.name = name
    return ob


def export(coll):
    ob = join(coll, coll.name)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    path = os.path.join(OUT, coll.name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB', export_apply=True)
    print("MARKET %s %.1f KB, %d polys" % (coll.name, os.path.getsize(path) / 1024, len(ob.data.polygons)))
    return ob


def preview(out_dir, obs):
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    sc.view_settings.view_transform = 'Standard'          # (the colours as they are, as Godot shows them)
    at = {"market_vegcart": -4.6, "market_groundstall": -1.2, "market_banana": 1.9, "market_crates": 4.4, "market_teakadai": 9.0,
          "bala_workshop": 16.0, "bala_workshop_closed": 16.0, "pudhur_site": 40.0, "agri_fair": 70.0,
          "townhall_pavement": 110.0, "rsp_shoprow": 140.0, "cash_bag": 170.0}
    for ob in obs:
        ob.location = (at[ob.name], 0, 0)
    built = [ob.name for ob in obs]
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    bpy.context.object.data.materials.append(mat("ground_dust", (0.5, 0.42, 0.33), 0.95))
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.2
    sun.rotation_euler = (0.85, 0.15, 0.7)
    sc.collection.objects.link(sun)
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.72, 0.85, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.4
    sc.world = world
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    for name, loc, look in (("market_props", (0, -12.5, 4.6), (0, 0, 0.8)), ("market_cart_close", (-4.6, -2.3, 2.0), (-4.6, 0, 0.9)),
                            ("market_ground_close", (-1.2, -2.6, 1.6), (-1.2, 0.1, 0.2)),
                            ("market_teakadai", (10.2, -5.6, 2.1), (9.0, 0.0, 1.35)),
                            ("bala_workshop", (17.2, -8.5, 2.2), (16.0, 0.5, 1.6)),
                            ("bala_workshop_in", (16.6, -3.0, 1.7), (15.6, 1.5, 1.1)),
                            ("pudhur_site", (43.0, -11.0, 3.0), (39.0, 5.0, 1.5)),
                            ("pudhur_site_wide", (52.0, -14.0, 7.0), (38.0, 9.0, 2.5)),
                            ("agri_fair", (70.0, -13.0, 3.4), (70.5, 6.0, 1.6)),
                            ("agri_fair_tractor", (63.0, -2.2, 1.6), (66.4, 2.6, 1.0)),
                            ("townhall_pavement", (104.0, -14.0, 3.2), (109.0, 1.0, 1.0)),
                            ("townhall_pavement_keys", (115.5, -2.2, 1.5), (117.0, 1.3, 0.8)),
                            ("rsp_shoprow", (137.0, -17.0, 3.0), (142.0, 1.5, 3.0))):
        if not any(name.startswith(b) or (name.startswith("market_") and b.startswith("market_")) for b in built):
            continue
        if name.startswith(("townhall", "rsp")) and not bpy.data.objects.get("ground_street"):
            bpy.ops.mesh.primitive_plane_add(size=80, location=(125.0, 0, -0.005))   # (the road in front of them)
            bpy.context.object.name = "ground_street"
            bpy.context.object.data.materials.append(mat("mk_asphalt_prev", (0.2, 0.2, 0.21), 0.9))
        if name.startswith("agri") and not bpy.data.objects.get("bike_borrowed"):
            vdir = os.path.join(HERE, "..", "godot", "assets", "vehicles")
            for k, (fn, bx, by) in enumerate((("bike_scooter_0", 59.5, 5.0), ("bike_motorcycle_1", 59.5, 5.9), ("bike_scooter_2", 59.5, 6.8),
                                              ("bike_motorcycle_3", 59.5, 7.7), ("bike_scooter_1", 59.5, 8.6))):
                before = set(bpy.data.objects)
                bpy.ops.import_scene.gltf(filepath=os.path.join(vdir, fn + ".glb"))
                for o in set(bpy.data.objects) - before:
                    if o.parent is None:
                        o.location = (bx, by, 0)
                        o.rotation_euler = (0, 0, 0.2)
                        o.name = "bike_borrowed" if k == 0 else o.name
        if name.startswith("agri"):                                          # a soft warm morning: low sun, soft shadows, sky fill
            sun.data.energy, sun.data.color, sun.data.angle = 3.6, (1.0, 0.92, 0.8), math.radians(6)
            sun.rotation_euler = (0.95, 0.2, 2.6)
            world.node_tree.nodes["Background"].inputs[1].default_value = 0.55
            world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.68, 0.85, 1)
            if hasattr(sc.eevee, "use_gtao"):
                sc.eevee.use_gtao = True
            cam.data.lens = 32
        cam.location = loc
        d = Vector(look) - Vector(loc)
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(out_dir, name + ".jpg")
        sc.render.image_settings.file_format = 'JPEG'
        bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats(make_textures())
    for key, ident, size, tris in (("onion", "yellow_onion", 0.06, 220), ("ginger", "food_ginger_01", 0.1, 260),
                                   ("lemon", "lemon", 0.055, 160), ("lime", "food_lime_01", 0.05, 160),
                                   ("sweet_potato", "sweet_potato", 0.15, 220), ("bananas", "bananas", 0.24, 500)):
        load_scan(key, ident, size, tris)
    load_plant("neem", "island_tree_02", 0.06, 2.6, 8.5, 4000)
    load_plant("bush", "shrub_02", 0.3, 1.5)
    load_plant("bush2", "shrub_04", 0.4, 1.3)
    load_plant("grass", "grass_medium_01", max_part=1500)
    load_plant("weed", "weed_plant_02", 0.5, 1.2)
    only = args[args.index("--only") + 1].split(",") if "--only" in args else list(BUILD)   # (just these: --only a,b)
    obs = [export(fn()) for name, fn in BUILD.items() if name in only]
    if "--preview" in args:
        preview(os.path.abspath(args[args.index("--preview") + 1]), obs)


main()
