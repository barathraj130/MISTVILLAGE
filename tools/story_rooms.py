"""
The story's interiors, designed for close-up cutscenes (docs/STORY_BIBLE.md): each one the inside of its own
building in Coimbatore, with real materials (procedural textures generated here into godot/assets/interiors/tex,
plus the project's CC0 timber / plaster / rug and the CC0 Poly Haven monobloc chair), proper furniture and the
everyday things that make the place:
    home        Karthik's rented house in Ganapathy: a front hall (red-oxide floor, blue dado, Amma's sewing
                machine, the family photos, calendar, clock, the wall shrine), the kitchen (granite platform, gas
                stove and cylinder, vessel rack) and Karthik's room (cot, the phone on charge, shirts, the cap)
    dev_office  Raghavan Developers, 1st floor in Gandhipuram: reception under the company board, sofa, staff
                desks with computers, Karthik's small desk, Raghavan's glass cabin (executive desk, nameplate, the
                Mist Village photo, the layout plan, trophy cabinet, AC, blinds)
    coopbank    Kovai Nagar Cooperative Bank: counters behind glass, counter numbers, token display, row seating,
                slip desk, notice board, cash counting machine, strong-room door, ATM
    mess        Hotel Anna Mess: steel tables and benches, hand-wash row, cash counter, parotta griddle at the
                kitchen hatch, menu board, banana leaves, cold-drinks fridge
    police      Nagar Police Station: front desk with the signing register, visitors' bench, inspector's table,
                the lock-up, wireless set, notice board
Empties for the game: Entry / Exit, Mark_<who> (a person's spot, facing the empty's +Y), Cam_<shot> / Look_<shot>
(planned cameras), Light_tube_* / Light_window_* / Light_lamp_* (where the room's light comes from).
Blender -Y is the room's front (the door), so in Godot the door faces +Z.

    Blender -b --factory-startup --python tools/story_rooms.py -- [names...] [--preview previews/rooms] [--no-export]
"""
import math
import random
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OUT = os.path.join(ROOT, "godot", "assets", "interiors")
TEX = os.path.join(OUT, "tex")
GTEX = os.path.join(ROOT, "godot", "assets", "models", "textures")
DTEX = os.path.join(ROOT, "godot", "assets", "drive", "tex")
CHAIR = os.path.join(ROOT, "mapdata", "polyhaven", "plastic_monobloc_chair_01", "plastic_monobloc_chair_01.gltf")
SKETCHFAB = os.path.join(ROOT, "mapdata", "sketchfab", "props")    # CC-BY models, credited in docs/DATA_SOURCES.md
H = 3.0                       # ceiling height (houses); offices and the bank set their own


# ============================================================================ procedural textures
def _noise(n, octaves=5, seed=1):
    """Fractal value noise in [0, 1], n × n, tiling."""
    rng = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        cells = 4 * 2 ** o
        g = rng.random((cells, cells))
        idx = np.arange(n) * cells / n
        i0 = np.floor(idx).astype(int) % cells
        i1 = (i0 + 1) % cells
        f = idx - np.floor(idx)
        f = f * f * (3 - 2 * f)
        row = g[i0][:, i0] * (1 - f)[None, :] + g[i0][:, i1] * f[None, :]
        row2 = g[i1][:, i0] * (1 - f)[None, :] + g[i1][:, i1] * f[None, :]
        layer = row * (1 - f)[:, None] + row2 * f[:, None]
        out += amp * layer
        tot += amp
        amp *= 0.5
    return out / tot


def _save(name, rgb):
    """rgb: n × n × 3 in [0, 1] → a PNG in godot/assets/interiors/tex and a Blender image."""
    os.makedirs(TEX, exist_ok=True)
    n = rgb.shape[0]
    img = bpy.data.images.new(name, n, n, alpha=False)
    px = np.ones((n, n, 4))
    px[:, :, :3] = np.clip(rgb[::-1], 0, 1)
    img.pixels.foreach_set(px.astype(np.float32).ravel())
    path = os.path.join(TEX, name + ".png")
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    return img


def _tint(base, n, var=0.1, seed=1, octaves=5):
    v = _noise(n, octaves, seed)
    return np.clip(np.array(base)[None, None, :] * (1 - var + 2 * var * v)[:, :, None], 0, 1)


def _ell(yy, xx, cy, cx, ry, rx):
    return ((yy - cy) / ry) ** 2 + ((xx - cx) / rx) ** 2 < 1.0


def _portrait(n, people, sepia, seed, faded=False):
    """A studio photograph: a plain backdrop, each person head and shoulders (hair, eyes, brows, a moustache on
    the men, a bindi and flowers on the women), then sepia or faded colour, a vignette and grain."""
    yy, xx = np.mgrid[0:n, 0:n] / n
    img = np.ones((n, n, 3)) * np.array([0.62, 0.66, 0.7])[None, None, :]
    img *= (0.85 + 0.25 * (1 - yy))[:, :, None]                                   # the backdrop's light
    rng = np.random.default_rng(seed)
    for cx, hy, sc, kind, cloth in people:
        r = 0.11 * sc
        skin = np.array([0.62, 0.44, 0.32]) * float(rng.uniform(0.9, 1.1))
        img[_ell(yy, xx, hy + 0.36 * sc, cx, 0.2 * sc, 0.25 * sc) & (yy > hy + 0.18 * sc)] = cloth      # shoulders
        img[(np.abs(xx - cx) < 0.045 * sc) & (yy > hy + 0.08 * sc) & (yy < hy + 0.2 * sc)] = skin * 0.9     # neck
        if kind in ("man", "boy") and cloth[0] > 0.8:                             # a collar
            img[_ell(yy, xx, hy + 0.19 * sc, cx, 0.03 * sc, 0.08 * sc)] = np.array(cloth) * 0.85
        head = _ell(yy, xx, hy, cx, r * 1.18, r)
        img[head] = skin
        hair = np.array([0.05, 0.04, 0.04])
        if kind in ("woman", "girl"):
            img[_ell(yy, xx, hy - 0.02 * sc, cx, r * 1.12, r * 1.08) & ~_ell(yy, xx, hy + 0.04 * sc, cx, r * 1.05, r * 0.86)] = hair
            img[_ell(yy, xx, hy - 0.06 * sc, cx + 0.105 * sc, 0.02 * sc, 0.012 * sc)] = (0.98, 0.95, 0.85)   # jasmine
            img[_ell(yy, xx, hy - 0.035 * sc, cx, 0.007 * sc, 0.007 * sc)] = (0.7, 0.05, 0.05)              # the bindi
        else:
            img[_ell(yy, xx, hy - 0.06 * sc, cx, r * 0.75, r * 1.04) & (yy < hy - 0.035 * sc)] = hair
        for s in (-1, 1):
            img[_ell(yy, xx, hy - 0.005 * sc, cx + s * 0.038 * sc, 0.009 * sc, 0.014 * sc)] = (0.95, 0.93, 0.9)
            img[_ell(yy, xx, hy - 0.005 * sc, cx + s * 0.038 * sc, 0.008 * sc, 0.007 * sc)] = (0.08, 0.05, 0.04)
            img[(np.abs(yy - (hy - 0.03 * sc)) < 0.005 * sc) & (np.abs(xx - cx - s * 0.04 * sc) < 0.02 * sc)] = hair  # brows
        img[_ell(yy, xx, hy + 0.035 * sc, cx, 0.01 * sc, 0.016 * sc)] = skin * 0.8                                  # the nose
        if kind == "man":
            img[_ell(yy, xx, hy + 0.06 * sc, cx, 0.009 * sc, 0.035 * sc)] = hair                                    # moustache
        img[_ell(yy, xx, hy + 0.085 * sc, cx, 0.006 * sc, 0.022 * sc)] = skin * 0.6                                 # the mouth
    if sepia:
        lum = (img @ np.array([0.3, 0.55, 0.15]))[:, :, None]
        img = lum * np.array([1.05, 0.88, 0.66])[None, None, :]
    if faded:
        img = img * 0.8 + 0.15
    d = np.hypot(yy - 0.5, xx - 0.5)
    img *= (1.0 - 0.6 * np.clip(d - 0.3, 0, 1))[:, :, None]                       # vignette
    img *= (0.95 + 0.1 * rng.random((n, n)))[:, :, None]                           # grain
    return np.clip(img, 0, 1)


def _god(n):
    """A framed god's picture as in every house and shop: a red ground, a gold halo, a blue figure with a crown and
    a vel, flowers below."""
    yy, xx = np.mgrid[0:n, 0:n] / n
    img = np.ones((n, n, 3)) * np.array([0.7, 0.12, 0.08])[None, None, :]
    img *= (0.8 + 0.3 * (1 - np.hypot(yy - 0.4, xx - 0.5)))[:, :, None]
    halo = np.hypot(yy - 0.3, xx - 0.5)
    img[halo < 0.2] = (0.98, 0.78, 0.25)
    img[(halo > 0.2) & (halo < 0.215)] = (1.0, 0.92, 0.5)
    img[_ell(yy, xx, 0.33, 0.5, 0.09, 0.075)] = (0.25, 0.45, 0.8)                 # the face
    img[_ell(yy, xx, 0.22, 0.5, 0.06, 0.07) & (yy < 0.25)] = (0.95, 0.7, 0.15)    # the crown
    img[_ell(yy, xx, 0.66, 0.5, 0.26, 0.2)] = (0.25, 0.45, 0.8)                   # the body
    img[_ell(yy, xx, 0.62, 0.5, 0.2, 0.12)] = (0.95, 0.6, 0.1)                    # the silk
    img[(np.abs(xx - 0.72) < 0.008) & (yy > 0.25) & (yy < 0.9)] = (0.85, 0.7, 0.3)   # the vel
    img[_ell(yy, xx, 0.24, 0.72, 0.05, 0.022)] = (0.9, 0.8, 0.4)
    for k in range(9):                                                            # flowers along the foot
        img[_ell(yy, xx, 0.92, 0.1 + k * 0.1, 0.03, 0.03)] = ((0.98, 0.95, 0.85) if k % 2 else (0.95, 0.55, 0.1))
    return img


def make_textures():
    T = {}
    n = 1024
    # polished red oxide: deep red, cloudy, the mop's arcs as faint lighter sweeps
    ro = _tint((0.42, 0.11, 0.07), n, 0.12, 2)
    y, x = np.mgrid[0:n, 0:n] / n
    sweep = 0.5 + 0.5 * np.sin((x * 3 + np.sin(y * 9) * 0.3) * 2 * np.pi * 3)
    T["red_oxide"] = _save("red_oxide", ro * (0.92 + 0.12 * sweep[:, :, None] * _noise(n, 3, 5)[:, :, None]))
    # cream vitrified tiles, 2 × 2 per texture (60 cm), grout lines, each tile its own faint shade and veins
    t = _tint((0.86, 0.82, 0.74), n, 0.05, 3)
    vein = _noise(n, 6, 4)
    t *= (0.97 + 0.05 * np.abs(np.sin(vein * 25)))[:, :, None]
    for i in range(2):
        for j in range(2):
            t[i * n // 2:(i + 1) * n // 2, j * n // 2:(j + 1) * n // 2] *= 0.96 + 0.06 * ((i * 7 + j * 3) % 5) / 5
    g = 6
    for k in range(3):
        p = min(k * n // 2, n - 1)
        t[max(p - g, 0):p + g, :] = (0.55, 0.52, 0.48)
        t[:, max(p - g, 0):p + g] = (0.55, 0.52, 0.48)
    T["tile_cream"] = _save("tile_cream", t)
    # black granite (kitchen platform, counters): near-black with white, grey and gold specks
    rng = np.random.default_rng(7)
    gr = _tint((0.06, 0.06, 0.065), n, 0.25, 8, 3)
    for c, k in (((0.6, 0.6, 0.62), 2200), ((0.3, 0.3, 0.32), 5000), ((0.5, 0.42, 0.25), 900)):
        ys, xs = rng.integers(0, n, k), rng.integers(0, n, k)
        gr[ys, xs] = c
        gr[np.clip(ys + 1, 0, n - 1), xs] = c
    T["granite_black"] = _save("granite_black", gr)
    # bathroom: blue glazed wall tiles (10 cm), small grey anti-skid floor tiles
    bt = _tint((0.55, 0.72, 0.85), n, 0.04, 31, 3)
    for k in range(0, n, n // 6):
        bt[k:k + 4, :] = (0.85, 0.88, 0.9)
        bt[:, k:k + 4] = (0.85, 0.88, 0.9)
    T["bath_tiles"] = _save("bath_tiles", bt)
    bf = _tint((0.55, 0.56, 0.56), n, 0.08, 32, 4)
    for k in range(0, n, n // 8):
        bf[k:k + 4, :] = (0.35, 0.36, 0.36)
        bf[:, k:k + 4] = (0.35, 0.36, 0.36)
    T["bath_floor"] = _save("bath_floor", bf)
    # the bank's floor: grey-white speckled granite slabs, 1 per texture with a thin joint
    bg = _tint((0.74, 0.73, 0.71), n, 0.06, 9, 4)
    ys, xs = rng.integers(0, n, 20000), rng.integers(0, n, 20000)
    bg[ys, xs] = (0.25, 0.25, 0.27)
    bg[:4, :] = bg[:, :4] = (0.45, 0.44, 0.42)
    T["granite_grey"] = _save("granite_grey", bg)
    # walls: blue distemper (houses), its oil-paint dado, office off-white, police khaki-cream, mess green
    T["distemper_blue"] = _save("distemper_blue", _tint((0.62, 0.74, 0.84), n, 0.06, 11, 4))
    T["dado_blue"] = _save("dado_blue", _tint((0.22, 0.4, 0.58), 512, 0.04, 12, 3))
    T["wall_offwhite"] = _save("wall_offwhite", _tint((0.88, 0.86, 0.8), n, 0.04, 13, 4))
    T["wall_cream_police"] = _save("wall_cream_police", _tint((0.85, 0.78, 0.6), n, 0.07, 14, 4))
    T["wall_green_mess"] = _save("wall_green_mess", _tint((0.55, 0.72, 0.58), n, 0.07, 15, 4))
    T["dado_brown"] = _save("dado_brown", _tint((0.38, 0.22, 0.12), 512, 0.05, 16, 3))
    # a printed check bedsheet
    m = 512
    yy, xx = np.mgrid[0:m, 0:m]
    chk = ((yy // 32 + xx // 32) % 2)[:, :, None]
    T["bedsheet"] = _save("bedsheet", np.where(chk, np.array([0.7, 0.25, 0.22]), np.array([0.92, 0.85, 0.6])) *
                          (0.92 + 0.08 * _noise(m, 3, 17))[:, :, None])
    # the land layout plan: cream paper, roads, rows of numbered plots (lines only)
    lp = np.ones((n, n, 3)) * np.array([0.93, 0.9, 0.8])
    for k in range(1, 8):
        p = k * n // 8
        lp[p - 2:p + 2, 40:n - 40] = (0.35, 0.3, 0.25)
        lp[40:n - 40, p - 2:p + 2] = (0.35, 0.3, 0.25)
    lp[n // 2 - 18:n // 2 + 18, 40:n - 40] = (0.8, 0.78, 0.7)              # the main road
    lp[40:n - 40, n // 2 - 14:n // 2 + 14] = (0.8, 0.78, 0.7)
    lp[n // 8:n // 4, 5 * n // 8:3 * n // 4] = (0.55, 0.75, 0.5)             # the park
    T["layout_plan"] = _save("layout_plan", lp)
    # a Tamil calendar's picture (a temple gopuram in reds and golds, as blocks) above a white date grid
    cal = np.ones((m, m, 3)) * 0.95
    cal[:m // 2] = np.array([0.85, 0.35, 0.1]) * (0.7 + 0.5 * _noise(m, 4, 18)[:m // 2, :, None])
    for k in range(6):
        w = 60 - k * 8
        cal[60 + k * 35:95 + k * 35, m // 2 - w:m // 2 + w] = (0.9, 0.7, 0.2)
    for k in range(1, 6):
        cal[m // 2 + k * 40:m // 2 + k * 40 + 3, 30:m - 30] = 0.6
    T["calendar"] = _save("calendar", cal)
    # photographs: Appa's garlanded portrait, the family, the children, an old leader (police), the god's picture
    T["photo_appa"] = _save("photo_appa", _portrait(m, [(0.5, 0.36, 1.25, "man", (0.92, 0.92, 0.9))], True, 31))
    T["photo_family"] = _save("photo_family", _portrait(m, [(0.24, 0.36, 0.8, "man", (0.9, 0.9, 0.88)),
                                                         (0.44, 0.38, 0.75, "woman", (0.6, 0.1, 0.15)),
                                                         (0.64, 0.5, 0.6, "boy", (0.3, 0.45, 0.75)),
                                                         (0.8, 0.54, 0.55, "girl", (0.85, 0.5, 0.6))], True, 32, faded=True))
    T["photo_kids"] = _save("photo_kids", _portrait(m, [(0.34, 0.38, 0.85, "boy", (0.25, 0.42, 0.7)),
                                                     (0.66, 0.42, 0.78, "girl", (0.2, 0.55, 0.55))], False, 33))
    T["photo_sepia"] = _save("photo_sepia", _portrait(m, [(0.5, 0.38, 1.2, "man", (0.95, 0.95, 0.93))], True, 34))
    T["photo_god"] = _save("photo_god", _god(m))
    # a printed cotton curtain: cream with maroon five-petal flowers and green leaves
    cu = _tint((0.93, 0.86, 0.72), m, 0.05, 41, 3)
    yy, xx = np.mgrid[0:m, 0:m] / m
    for gy in range(4):
        for gx in range(4):
            cy, cx = (gy + 0.5) / 4, (gx + 0.5 + 0.5 * (gy % 2)) / 4 % 1.0
            for k in range(5):
                a = k * 2 * math.pi / 5
                cu[_ell(yy, xx, cy + 0.04 * math.sin(a), cx + 0.04 * math.cos(a), 0.03, 0.03)] = (0.6, 0.1, 0.12)
            cu[_ell(yy, xx, cy, cx, 0.018, 0.018)] = (0.95, 0.75, 0.2)
            cu[_ell(yy, xx, cy + 0.07, cx + 0.06, 0.02, 0.045)] = (0.25, 0.45, 0.22)
    T["curtain_print"] = _save("curtain_print", cu)
    yy, xx = np.mgrid[0:m, 0:m] / m
    T["photo_hills"] = _save("photo_hills", np.where((yy > 0.45 + 0.1 * np.sin(xx * 9))[:, :, None],
                                                     np.array([0.22, 0.45, 0.25]), np.array([0.7, 0.8, 0.9])) *
                             (0.85 + 0.2 * _noise(m, 4, 20))[:, :, None])
    # the mess's menu board: green with white writing-like strokes
    mb = _tint((0.08, 0.28, 0.16), m, 0.08, 21, 3)
    mb[16:22, 16:m - 16] = mb[m - 22:m - 16, 16:m - 16] = 0.85                  # a chalk border; the lines are real text
    T["menu_board"] = _save("menu_board", mb)
    # a notice board of circulars
    nb = _tint((0.55, 0.4, 0.25), m, 0.1, 22, 3)
    for k in range(7):
        x0, y0 = 30 + (k % 4) * 115, 30 + (k // 4) * 230
        nb[y0:y0 + 190, x0:x0 + 95] = (0.95, 0.94, 0.9)
        for r in range(8):
            nb[y0 + 20 + r * 20:y0 + 24 + r * 20, x0 + 10:x0 + 85] = 0.4
    T["notice"] = _save("notice", nb)
    # blue fabric (office partitions)
    T["fabric_blue"] = _save("fabric_blue", _tint((0.18, 0.28, 0.45), 512, 0.12, 23, 6))
    return T


# ============================================================================ materials
M = {}
FIT = ("photo_", "calendar", "notice", "menu_board", "layout_plan", "area_map")   # pictures: the image fits the face


def mat(key, colour=(0.8, 0.8, 0.8), rough=0.6, metal=0.0, tex=None, normal=None, emit=None, strength=1.0,
        alpha=1.0, scale=1.0):
    """A material; tex: a Blender image or a path (repeating every `scale` metres via the box UVs)."""
    if key in M:
        return M[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*colour, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if tex is not None:
        it = nt.nodes.new("ShaderNodeTexImage")
        it.image = tex if not isinstance(tex, str) else bpy.data.images.load(tex, check_existing=True)
        nt.links.new(it.outputs["Color"], b.inputs["Base Color"])
    if normal is not None and os.path.exists(normal):
        nm = nt.nodes.new("ShaderNodeTexImage")
        nm.image = bpy.data.images.load(normal, check_existing=True)
        nm.image.colorspace_settings.name = 'Non-Color'
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nm.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], b.inputs["Normal"])
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = 'BLENDED'
        else:
            m.blend_method = 'BLEND'
    m["uv_scale"] = scale
    m["fit"] = key.startswith(FIT)
    M[key] = m
    return m


# ============================================================================ geometry
def _link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _uv_box(bm, scale, fit=False):
    """World-size box mapping: each face takes its UVs from the two axes it spans, `scale` metres per repeat.
    fit: a picture (photo, calendar, board): the image spans the face once, the right way round for the viewer."""
    uv = bm.loops.layers.uv.verify()
    lo = [min(v.co[i] for v in bm.verts) for i in range(3)]
    hi = [max(v.co[i] for v in bm.verts) for i in range(3)]
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [(1, 2), (0, 2), (0, 1)][ax]
        for lp in f.loops:
            co = lp.vert.co
            if fit:
                u = (co[a] - lo[a]) / max(hi[a] - lo[a], 1e-6)
                v = (co[b] - lo[b]) / max(hi[b] - lo[b], 1e-6)
                if (ax == 1 and n[1] > 0) or (ax == 0 and n[0] < 0):          # seen from behind the axis: mirror
                    u = 1.0 - u
                lp[uv].uv = (u, v)
            else:
                lp[uv].uv = (co[a] / scale, co[b] / scale)


def box(c, size, m, bev=0.0, rot=(0, 0, 0)):
    """An axis box centred at c (metres), with world-scaled UVs; bev rounds its edges."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bev > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bev, segments=2, affect='EDGES')
    rm = Matrix.Rotation(rot[2], 4, 'Z') @ Matrix.Rotation(rot[1], 4, 'Y') @ Matrix.Rotation(rot[0], 4, 'X')
    bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ rm, verts=bm.verts)
    bm.normal_update()
    _uv_box(bm, m.get("uv_scale", 1.0) if m else 1.0, bool(m.get("fit", False)) if m else False)
    me = bpy.data.meshes.new("Box")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m)
    return _link(bpy.data.objects.new("Box", me))


def cyl(c, r, h, m, verts=24, rot=(0, 0, 0), r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=r, radius2=r if r2 is None else r2, depth=h)
    rm = Matrix.Rotation(rot[2], 4, 'Z') @ Matrix.Rotation(rot[1], 4, 'Y') @ Matrix.Rotation(rot[0], 4, 'X')
    bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ rm, verts=bm.verts)
    _uv_box(bm, m.get("uv_scale", 1.0) if m else 1.0)
    me = bpy.data.meshes.new("Cyl")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(m)
    return _link(bpy.data.objects.new("Cyl", me))


def dome(c, r, h, m, sx=1.0, sy=1.0, segs=16):
    """A mound: the top half of a sphere r across (stretched by sx, sy), h high, its base at c (rice, an idli)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=8, radius=1.0)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-4], context='VERTS')
    bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ Matrix.Diagonal((r * sx, r * sy, h, 1.0)), verts=bm.verts)
    _uv_box(bm, 1.0)
    me = bpy.data.meshes.new("Dome")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(m)
    return _link(bpy.data.objects.new("Dome", me))


FOODS = ("idli", "meals", "parotta", "dosa", "curd_rice")


def food(kind, x, y, z, toward=-1.0):
    """One dish on a banana leaf whose middle is x, y and top z, the eater on the far side from `toward` (-1: he
    faces -Y, the cups go along the leaf's far edge). Kinds as the game's menus name them (tasks.gd FOOD_ITEMS). Its
    parts are named Food_<kind>: the export keeps each dish one object of its own, the game shows the one ordered."""
    before = set(bpy.data.objects)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    f = toward

    def cup(dx, dy, key, col):                                     # a steel katori with a curry in it
        cyl((x + dx, y + dy * f, z + 0.018), 0.025, 0.036, steel, 20, r2=0.034)      # wider at the rim
        cyl((x + dx, y + dy * f, z + 0.036), 0.031, 0.003, mat(key, col, 0.3), 20)    # filled to the brim
    rice = mat("food_rice", (0.96, 0.95, 0.9), 0.75)
    golden = mat("food_golden", (0.85, 0.6, 0.28), 0.6)
    if kind == "idli":
        for dx, dy in ((-0.07, -0.02), (0.0, -0.03), (0.07, -0.02), (-0.035, 0.05)):
            dome((x + dx, y + dy * f, z), 0.036, 0.02, mat("food_idli", (0.95, 0.94, 0.88), 0.7))
        cyl((x + 0.06, y + 0.05 * f, z + 0.008), 0.035, 0.016, mat("food_vada", (0.6, 0.35, 0.12), 0.55), 20)
        cyl((x + 0.06, y + 0.05 * f, z + 0.009), 0.01, 0.018, mat("leaf_green", (0.2, 0.5, 0.18), 0.6), 12)   # its hole
        cup(-0.13, 0.1, "food_sambar", (0.8, 0.42, 0.1))
        cup(-0.05, 0.11, "food_chutney", (0.93, 0.92, 0.8))
    elif kind == "meals":
        dome((x, y, z), 0.07, 0.04, rice, sx=1.25)                 # the rice in the middle
        for k, (key, col) in enumerate((("food_sambar", (0.8, 0.42, 0.1)), ("food_rasam", (0.6, 0.2, 0.08)),
                                        ("food_kootu", (0.85, 0.72, 0.3)), ("food_curd", (0.97, 0.97, 0.95)))):
            cup(-0.14 + k * 0.08, 0.11, key, col)
        dome((x + 0.13, y - 0.02 * f, z), 0.035, 0.012, mat("food_poriyal", (0.42, 0.62, 0.22), 0.7), sx=1.3)
        cyl((x - 0.14, y - 0.03 * f, z + 0.003), 0.05, 0.003, mat("food_appalam", (0.95, 0.85, 0.55), 0.6), 24)
        dome((x + 0.15, y + 0.06 * f, z), 0.015, 0.01, mat("food_pickle", (0.7, 0.18, 0.08), 0.5))
    elif kind == "parotta":
        for k, (dx, dy) in enumerate(((-0.04, 0.0), (0.03, -0.02))):    # two, one leaning on the other
            cyl((x + dx, y + dy * f, z + 0.008 + k * 0.012), 0.085, 0.014, golden, 32, rot=(0.0, 0.12 * k, 0.0))
        cyl((x + 0.12, y + 0.08 * f, z + 0.025), 0.038, 0.05, steel, 24, r2=0.05)         # the salna bowl
        cyl((x + 0.12, y + 0.08 * f, z + 0.05), 0.047, 0.003, mat("food_salna", (0.55, 0.25, 0.08), 0.3), 24)
        dome((x + 0.13, y - 0.05 * f, z), 0.025, 0.018, mat("food_egg", (0.97, 0.95, 0.88), 0.5), sx=1.3)
        cyl((x + 0.13, y - 0.05 * f, z + 0.017), 0.013, 0.003, mat("food_yolk", (0.98, 0.7, 0.1), 0.4), 16)
    elif kind == "dosa":
        cyl((x, y, z + 0.028), 0.03, 0.38, golden, 24, rot=(0.0, math.pi / 2, 0.0), r2=0.012)    # the rolled dosa
        dome((x - 0.2, y, z), 0.028, 0.026, mat("food_masala", (0.9, 0.7, 0.2), 0.7))   # the potato at its open end
        cup(-0.08, 0.1, "food_chutney", (0.93, 0.92, 0.8))
        cup(0.0, 0.1, "food_sambar", (0.8, 0.42, 0.1))
        cup(0.08, 0.1, "food_red_chutney", (0.78, 0.25, 0.12))
    elif kind == "curd_rice":
        dome((x, y, z), 0.075, 0.045, mat("food_curd_rice", (0.97, 0.97, 0.94), 0.6), sx=1.2)
        rng = random.Random(7)                                     # mustard seeds and curry leaves on the mound
        for k in range(16):
            a, d = rng.uniform(0, math.tau), 0.065 * math.sqrt(rng.random())
            dx, dy = d * math.cos(a) * 1.2, d * math.sin(a)
            top = z + 0.045 * math.sqrt(max(1.0 - (dx / 0.09) ** 2 - (dy / 0.075) ** 2, 0.0)) - 0.001
            if k < 4:
                dome((x + dx, y + dy, top), 0.011, 0.002, mat("food_curry_leaf", (0.12, 0.35, 0.1), 0.5), sx=0.45)
            else:
                dome((x + dx, y + dy, top), 0.0035, 0.003, mat("food_seed", (0.1, 0.07, 0.05), 0.5))
        dome((x + 0.12, y + 0.06 * f, z), 0.018, 0.01, mat("food_pickle", (0.7, 0.18, 0.08), 0.5))
        cyl((x - 0.13, y - 0.02 * f, z + 0.003), 0.05, 0.003, mat("food_appalam", (0.95, 0.85, 0.55), 0.6), 24)
    for o in set(bpy.data.objects) - before:
        o.name = "Food_%s_part" % kind


def empty(name, loc, yaw=0.0):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    e.rotation_euler = (0, 0, yaw)
    return _link(e)


def mark(name, x, y, yaw):
    empty("Mark_" + name, (x, y, 0), yaw)


def shot(name, cam, look):
    empty("Cam_" + name, cam)
    empty("Look_" + name, look)


def light(kind, loc, k):
    empty("Light_%s_%d" % (kind, k), loc)


def chair_poly(x, y, yaw, colour=None):
    """The CC0 Poly Haven monobloc chair, if it's on disk, else a simple one."""
    if os.path.exists(CHAIR):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=CHAIR)
        new = [o for o in bpy.data.objects if o not in before]
        for o in new:
            if o.parent is None:
                o.location = (x, y, 0)
                o.rotation_euler = (0, 0, yaw)
            if colour and o.type == 'MESH':
                for ms in o.material_slots:
                    if ms.material:
                        mc = ms.material.copy()
                        b = mc.node_tree.nodes.get("Principled BSDF")
                        for ln in list(b.inputs["Base Color"].links):
                            mc.node_tree.links.remove(ln)
                        b.inputs["Base Color"].default_value = (*colour, 1)
                        ms.material = mc
        return
    box((x, y, 0.44), (0.44, 0.42, 0.04), mat("plastic_red", (0.7, 0.1, 0.08), 0.4), 0.01)



SF = {}                                                                  # one import per prop (and per room)


def _sketchfab_mesh(path, drop, keep, decimate, recolour, paint=()):
    """Import a Sketchfab glb once: its meshes (less `drop`, or only `keep`) baked into one mesh, thinned, its
    textures no bigger than 512 px (they're small things in the room). The objects go; the mesh stays for sketchfab() to copy."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH' and not any(d in o.name for d in drop)
              and (keep is None or any(k in o.name for k in keep))]
    for o in meshes:                                                     # bake the model's own transforms in first
        o.data = o.data.copy()
        o.data.transform(o.matrix_world)
    for o in new:
        if o not in meshes:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
        tris = sum(len(f.vertices) - 2 for f in o.data.polygons)
        if tris > decimate:
            md = o.modifiers.new("thin", 'DECIMATE')
            md.ratio = decimate / tris
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=md.name)
        for ms in o.material_slots:
            for part, colour in (recolour or {}).items():
                if ms.material and part in ms.material.name:
                    b = ms.material.node_tree.nodes.get("Principled BSDF")
                    b.inputs["Base Color"].default_value = (*colour[:3], 1)
                    if len(colour) > 3:
                        b.inputs["Metallic"].default_value = colour[3]
            for part, x0, y0, x1, y1, dx in paint:
                if ms.material and part == ms.material.name:
                    _paint_over(ms.material, x0, y0, x1, y1, dx)
            if ms.material and ms.material.use_nodes:
                for n in ms.material.node_tree.nodes:
                    im = getattr(n, "image", None)
                    if im is not None and max(im.size) > 512:
                        im.scale(*(max(1, v * 512 // max(im.size)) for v in im.size))
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    me = ob.data
    bpy.data.objects.remove(ob, do_unlink=True)
    return me

def _paint_over(m, x0, y0, x1, y1, dx):
    """Cover a patch of a material's textures (colour, shine, bumps) with the texture dx pixels to its right (once per
    image)."""
    for n in m.node_tree.nodes:
        im = getattr(n, "image", None)
        if im is None or im.get("painted_%d_%d" % (x0, y0)):
            continue
        w, h = im.size
        px = np.empty(w * h * 4, dtype=np.float32)
        im.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)
        r0, r1 = h - y1, h - y0                                          # Blender rows start at the bottom
        px[r0:r1, x0:x1] = px[r0:r1, x0 + dx:x1 + dx]
        im.pixels.foreach_set(px.ravel())
        im.update()
        im["painted_%d_%d" % (x0, y0)] = True


def sketchfab(name, loc, size, yaw=0.0, drop=(), keep=None, by="height", decimate=1200, recolour=None, paint=()):
    """A Sketchfab prop (mapdata/sketchfab/props/<name>.glb) joined into one mesh, its feet at loc, scaled so its
    height (by="height") or widest side (by="width") is `size` metres. drop / keep: mesh-name parts to leave out or
    to keep only (a model's table, its backdrop). Meshes over `decimate` triangles are thinned. recolour: {material
    name part: colour} for models that came without textures. paint: (material name part, x0, y0, x1, y1, dx) patches
of its textures (pixels, from the top left) covered with the paint dx pixels to the right: a brand name or
logo out (the game has no real brands). Returns None (and the caller builds its own) if the
    file isn't on this machine."""
    path = os.path.join(SKETCHFAB, name + ".glb")
    if not os.path.exists(path):
        return None
    key = (name, tuple(drop), tuple(keep or ()), tuple(sorted((recolour or {}).items())), tuple(paint))
    if key not in SF:
        SF[key] = _sketchfab_mesh(path, drop, keep, decimate, recolour, paint)
    ob = _link(bpy.data.objects.new("Prop_" + name, SF[key].copy()))     # copies share the materials and images
    vs = [v.co for v in ob.data.vertices]
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    k = size / ((hi - lo).z if by == "height" else max((hi - lo).x, (hi - lo).y))
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    ob.data.transform(Matrix.Translation(loc) @ Matrix.Rotation(yaw, 4, 'Z') @ Matrix.Scale(k, 4) @ Matrix.Translation(-centre))
    return ob


# ---- furniture pieces ----
def shell(w, d, h, floor, wall, ceiling, dado=None, dado_h=1.0, door_w=1.0, door_x=0.0, windows=()):
    """Floor, ceiling, four walls (a doorway in the front one at door_x), a painted dado band, skirting, and
    window openings: windows = [(wall 'L'|'R'|'B', centre along it, width, sill, height)] with bars and a
    bright sky beyond; a sill of 0 makes it a doorway into a room beyond (no bars, no sky: a door frame)."""
    t = 0.12
    box((0, 0, -0.05), (w, d, 0.1), floor)
    box((0, 0, h + 0.05), (w, d, 0.1), ceiling)
    walls = {"B": ((0, d / 2 + t / 2), (w + 2 * t, t), "x"), "L": ((-w / 2 - t / 2, 0), (t, d), "y"),
             "R": ((w / 2 + t / 2, 0), (t, d), "y")}
    for side, (pos, sz, along) in walls.items():
        cuts = sorted([wd for wd in windows if wd[0] == side], key=lambda wd: wd[1])
        length = sz[0] if along == "x" else sz[1]
        a = -length / 2
        segs = []
        for _, c, ww, sill, wh in cuts:
            segs.append((a, c - ww / 2))
            a = c + ww / 2
            for z0, z1 in ((0, sill), (sill + wh, h)):                     # under and over the window
                if z1 - z0 < 0.01:
                    continue
                cc = Vector((pos[0], pos[1], (z0 + z1) / 2))
                if along == "x":
                    cc.x = c
                    box(cc, (ww, t, z1 - z0), wall)
                else:
                    cc.y = c
                    box(cc, (t, ww, z1 - z0), wall)
        segs.append((a, length / 2))
        for s0, s1 in segs:
            if s1 - s0 < 0.01:
                continue
            mid = (s0 + s1) / 2
            if along == "x":
                box((mid, pos[1], h / 2), (s1 - s0, t, h), wall)
            else:
                box((pos[0], mid, h / 2), (t, s1 - s0, h), wall)
    # the front wall with its doorway
    left = (door_x - door_w / 2) - (-w / 2)
    right = w / 2 - (door_x + door_w / 2)
    box((-w / 2 + left / 2, -d / 2 - t / 2, h / 2), (left, t, h), wall)
    box((w / 2 - right / 2, -d / 2 - t / 2, h / 2), (right, t, h), wall)
    box((door_x, -d / 2 - t / 2, (h + 2.2) / 2), (door_w, t, h - 2.2), wall)
    wood = mat("door_frame", (0.35, 0.2, 0.1), 0.5, tex=os.path.join(GTEX, "warm_natural_timber_base.jpg"), scale=1.0)
    box((door_x, -d / 2 - 0.03, 2.24), (door_w + 0.14, 0.18, 0.08), wood, 0.005)
    for s in (-1, 1):
        box((door_x + s * (door_w / 2 + 0.035), -d / 2 - 0.03, 1.1), (0.07, 0.18, 2.2), wood, 0.005)
    sky = mat("daylight", (1, 1, 1), 0.5, emit=(1.0, 0.98, 0.92), strength=2.2)
    box((door_x, -d / 2 - 0.6, 1.1), (door_w, 0.02, 2.2), sky)
    # the dado band and skirting inside
    if dado:
        for side, (pos, sz, along) in walls.items():
            if along == "x":
                box((0, pos[1] - t / 2 - 0.006, dado_h / 2), (w, 0.012, dado_h), dado)
                continue
            a = -d / 2                                                     # (broken at doorways)
            for _, c, ww, sill, wh in sorted([wd for wd in windows if wd[0] == side and wd[3] <= 0.01], key=lambda wd: wd[1]):
                if c - ww / 2 - a > 0.01:
                    box((pos[0] + (t / 2 + 0.006) * (1 if pos[0] < 0 else -1), (a + c - ww / 2) / 2, dado_h / 2), (0.012, c - ww / 2 - a, dado_h), dado)
                a = c + ww / 2
            box((pos[0] + (t / 2 + 0.006) * (1 if pos[0] < 0 else -1), (a + d / 2) / 2, dado_h / 2), (0.012, d / 2 - a, dado_h), dado)
    # windows: frame, iron bars, open shutters, sky
    bars = mat("window_bars", (0.1, 0.12, 0.1), 0.4, 0.6)
    shutter = mat("shutter_green", (0.15, 0.4, 0.28), 0.5)
    for side, c, ww, sill, wh in windows:
        pos, sz, along = walls[side]
        inward = Vector((0, -1, 0)) if side == "B" else (Vector((1, 0, 0)) if side == "L" else Vector((-1, 0, 0)))
        centre = Vector((c if along == "x" else pos[0], c if along == "y" else pos[1], sill + wh / 2))
        span = Vector((1, 0, 0)) if along == "x" else Vector((0, 1, 0))
        if sill <= 0.01:                                               # a doorway: just its wooden frame
            top_sz = (ww + 0.14, 0.18, 0.08) if along == "x" else (0.18, ww + 0.14, 0.08)
            box(centre + Vector((0, 0, wh / 2 + 0.04)), top_sz, wood, 0.005)
            for s in (-1, 1):
                box(centre + span * s * (ww / 2 + 0.035), (0.07, 0.18, wh) if along == "x" else (0.18, 0.07, wh), wood, 0.005)
            continue
        for k in range(int(ww / 0.12)):
            p = centre + span * (-ww / 2 + 0.06 + k * 0.12)
            box(p, (0.016, 0.016, wh) if True else None, bars)
        frame_sz = (ww + 0.1, 0.1, 0.06) if along == "x" else (0.1, ww + 0.1, 0.06)
        box(centre + Vector((0, 0, wh / 2)), frame_sz, wood)
        box(centre - Vector((0, 0, wh / 2)), frame_sz, wood)
        box(centre - inward * 0.5, (ww, 0.02, wh) if along == "x" else (0.02, ww, wh), sky)
        for s in (-1, 1):                                              # shutters open against the wall outside
            box(centre - inward * 0.08 + span * s * (ww / 2 + ww / 4), (ww / 2, 0.03, wh) if along == "x" else (0.03, ww / 2, wh), shutter)
        light("window", tuple(centre - inward * 0.2), len([o for o in bpy.data.objects if o.name.startswith("Light_window")]))
    empty("Entry", (door_x, -d / 2 + 0.9, 0), 0.0)
    empty("Exit", (door_x, -d / 2 + 0.35, 0), math.pi)


def curtain(x, y0, y1, z0, z1, m, folds=7):
    """A cotton curtain hanging from a rod: gathered into soft pleats (deep at the top where it's bunched on the
    rod, opening out lower down), the hem swinging a little; both sides of the cloth."""
    cols, rows = folds * 8, 12
    bm = bmesh.new()
    grid = []
    for r in range(rows + 1):
        t = r / rows                                         # 0 at the hem, 1 at the rod
        z = z0 + (z1 - z0) * t
        row = []
        for c in range(cols + 1):
            u = c / cols
            depth = 0.045 * (0.7 + 0.3 * t)                  # the pleats' depth
            off = depth * math.sin(u * folds * 2 * math.pi) + 0.012 * math.sin(u * 23.0 + t * 3.0) * (1 - t)
            row.append(bm.verts.new((x + off, y0 + (y1 - y0) * u, z)))
        grid.append(row)
    for r in range(rows):
        for c in range(cols):
            bm.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.004)
    bm.normal_update()
    _uv_box(bm, m.get("uv_scale", 1.0))
    me = bpy.data.meshes.new("Curtain")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(m)
    _link(bpy.data.objects.new("Curtain", me))
    for k in range(folds + 1):                               # the rings on the rod
        cyl((x, y0 + (y1 - y0) * k / folds, z1 + 0.05), 0.02, 0.01, mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55), 10,
            rot=(math.pi / 2, 0, 0))


def tube_light(x, y, z, along_x=True, k=0):
    tube = mat("tube_glow", (1, 1, 1), 0.3, emit=(0.95, 0.97, 1.0), strength=5.0)
    fit = mat("tube_fitting", (0.9, 0.9, 0.88), 0.4)
    box((x, y, z), (1.22, 0.07, 0.07) if along_x else (0.07, 1.22, 0.07), fit, 0.01)
    box((x, y, z - 0.035), (1.18, 0.04, 0.03) if along_x else (0.04, 1.18, 0.03), tube)
    light("tube", (x, y, z - 0.15), k)


def ceiling_fan(x, y, h):
    fan = sketchfab("ceiling_fan_lp", (x, y, h - 0.62), 1.2, by="width", decimate=4000)
    if fan is not None:
        cyl((x, y, h - 0.2), 0.012, 0.4, mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55), 8)   # the down-rod
        return
    white = mat("fan_white", (0.9, 0.9, 0.88), 0.4)
    cyl((x, y, h - 0.25), 0.015, 0.5, mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55), 8)
    cyl((x, y, h - 0.55), 0.11, 0.1, white, 20)
    for k in range(3):
        a = k * 2 * math.pi / 3
        box((x + math.cos(a) * 0.45, y + math.sin(a) * 0.45, h - 0.55), (0.75, 0.12, 0.012), white, 0.004, rot=(0.06, 0, a))


def table(x, y, w, d, h, top, legs, bev=0.01):
    box((x, y, h - 0.02), (w, d, 0.04), top, bev)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((x + sx * (w / 2 - 0.05), y + sy * (d / 2 - 0.05), (h - 0.04) / 2), (0.045, 0.045, h - 0.04), legs)


def office_chair(x, y, yaw):
    black = mat("chair_black", (0.04, 0.04, 0.045), 0.5)
    chrome = mat("chrome", (0.82, 0.82, 0.84), 0.2, 0.6)
    cyl((x, y, 0.25), 0.02, 0.42, chrome, 10)
    for k in range(5):
        a = yaw + k * 2 * math.pi / 5
        box((x + math.cos(a) * 0.17, y + math.sin(a) * 0.17, 0.05), (0.34, 0.04, 0.03), black, 0.01, rot=(0, 0, a))
    box((x, y, 0.47), (0.5, 0.48, 0.08), black, 0.03)
    bx, by = x - math.sin(yaw) * -0.23, y + math.cos(yaw) * -0.23
    box((bx, by, 0.82), (0.46, 0.06, 0.6) if abs(math.cos(yaw)) > 0.5 else (0.06, 0.46, 0.6), black, 0.03)


def frame(x, y, z, w, h, picture, face_y=-1, facing="-y"):
    """A framed picture on a wall, facing into the room ("-y": on a back wall; "+x": on the left wall)."""
    wood = mat("frame_wood", (0.25, 0.14, 0.07), 0.45)
    if facing == "+x":
        box((x, y, z), (0.03, w + 0.06, h + 0.06), wood, 0.005)
        box((x + 0.017, y, z), (0.004, w, h), picture)
        return
    box((x, y, z), (w + 0.06, 0.03, h + 0.06), wood, 0.005)
    box((x, y + face_y * 0.017, z), (w, 0.004, h), picture)


def almirah(x, y, yaw=0.0, mirror=True):
    steel = mat("almirah_grey", (0.42, 0.45, 0.43), 0.35, 0.6)
    box((x, y, 0.95), (0.92, 0.52, 1.9), steel, 0.01, rot=(0, 0, yaw))
    front = Vector((0, -0.27, 0))
    front.rotate(Matrix.Rotation(yaw, 3, 'Z'))
    box(Vector((x, y, 0.95)) + front, (0.01 if abs(math.sin(yaw)) > 0.5 else 0.88, 0.01 if abs(math.sin(yaw)) <= 0.5 else 0.88, 1.84),
        mat("almirah_line", (0.2, 0.22, 0.2), 0.4, 0.6))
    if mirror:
        box(Vector((x, y, 1.25)) + front * 1.03, (0.3, 0.008, 0.9) if abs(math.sin(yaw)) <= 0.5 else (0.008, 0.3, 0.9),
            mat("mirror", (0.85, 0.88, 0.9), 0.02, 1.0))


# ============================================================================ the rooms
def bathroom(T, wall_x, door_y):
    """The bathroom off the hall (beyond its left wall at wall_x, the doorway at door_y): a bucket bath room as in
    any Coimbatore house: blue glazed tiles to shoulder height, a grey floor tiled to a drain, the tap low on the
    wall with a bucket and mug under it, a low plastic stool, a shelf with soap and the toothbrush cup, a small
    mirror, a high ventilator window, a bulb."""
    w, d, h = 1.7, 1.7, H
    x0 = wall_x - 0.06 - w / 2                                           # its centre
    y0 = door_y
    tile = mat("bath_tiles", (1, 1, 1), 0.15, tex=T["bath_tiles"], scale=0.6)
    floor_t = mat("bath_floor", (1, 1, 1), 0.3, tex=T["bath_floor"], scale=0.6)
    paint = mat("bath_paint", (0.86, 0.9, 0.9), 0.85)
    box((x0, y0, -0.05), (w + 0.24, d + 0.24, 0.1), floor_t)
    box((x0, y0, h + 0.05), (w + 0.24, d + 0.24, 0.1), paint)
    t = 0.12
    box((x0 - w / 2 - t / 2, y0, h / 2), (t, d + 2 * t, h), paint)               # the far wall
    for s in (-1, 1):
        box((x0, y0 + s * (d / 2 + t / 2), h / 2), (w, t, h), paint)
    for s in (-1, 1):                                                    # the tiles, to shoulder height
        box((x0, y0 + s * (d / 2 - 0.006), 0.8), (w, 0.012, 1.6), tile)
    box((x0 - w / 2 + 0.006, y0, 0.8), (0.012, d, 1.6), tile)
    box((x0 - w / 2 + 0.3, y0 - d / 2 + 0.3, 0.003), (0.12, 0.12, 0.006), mat("drain", (0.3, 0.3, 0.32), 0.3, 0.8))
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    tap_x = x0 - w / 2 + 0.06
    cyl((tap_x + 0.06, y0, 0.62), 0.016, 0.12, steel, 12, rot=(0, math.pi / 2, 0))     # the tap
    cyl((tap_x + 0.11, y0, 0.58), 0.012, 0.08, steel, 12)
    cyl((tap_x + 0.03, y0, 0.66), 0.025, 0.04, steel, 12, rot=(0, math.pi / 2, 0))
    if sketchfab("plastic_bucket", (tap_x + 0.3, y0, 0.0), 0.4, yaw=0.6) is None:
        cyl((tap_x + 0.28, y0, 0.2), 0.17, 0.4, mat("bucket_blue", (0.12, 0.35, 0.75), 0.35), 32, r2=0.21)
    cyl((tap_x + 0.3, y0, 0.33), 0.19, 0.01, mat("water", (0.35, 0.6, 0.8), 0.05), 32)
    mug = mat("mug_orange", (0.95, 0.4, 0.15), 0.35)
    cyl((tap_x + 0.55, y0 + 0.28, 0.06), 0.06, 0.12, mug, 20)
    stool = mat("plastic_red", (0.7, 0.1, 0.08), 0.4)
    box((x0 + 0.1, y0 - 0.35, 0.22), (0.32, 0.32, 0.04), stool, 0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((x0 + 0.1 + sx * 0.13, y0 - 0.35 + sy * 0.13, 0.1), (0.03, 0.03, 0.2), stool)
    shelf_y = y0 + d / 2 - 0.1
    box((x0 - 0.2, shelf_y, 1.25), (0.5, 0.16, 0.02), mat("shelf_white", (0.95, 0.95, 0.93), 0.3), 0.004)
    box((x0 - 0.35, shelf_y, 1.28), (0.09, 0.05, 0.03), mat("soap", (0.95, 0.62, 0.48), 0.4), 0.01)
    ceramic = {"ceramic": (0.93, 0.93, 0.9), "metal": (0.74, 0.75, 0.77, 0.8)}
    if sketchfab("basic_bathroom_accessories", (x0 - 0.12, shelf_y, 1.26), 0.1, keep=("toothbrushHolder",), recolour=ceramic) is None:
        cyl((x0 - 0.12, shelf_y, 1.31), 0.03, 0.1, mat("cup_green", (0.3, 0.65, 0.4), 0.3), 16)
    sketchfab("basic_bathroom_accessories", (x0 - 0.02, shelf_y, 1.26), 0.15, keep=("soapDispenser",), recolour=ceramic)
    for k in range(2):                                                   # toothbrushes in the cup
        cyl((x0 - 0.13 + k * 0.02, shelf_y, 1.4), 0.004, 0.16, mat("brush_%d" % k, ((0.2, 0.5, 0.9), (0.9, 0.3, 0.3))[k], 0.3), 8, rot=(0.1 * (k - 0.5), 0, 0))
    box((x0 - 0.2, shelf_y + 0.04, 1.6), (0.36, 0.01, 0.45), mat("mirror", (0.85, 0.88, 0.9), 0.02, 1.0))
    box((x0 - 0.2, y0 - d / 2 - 0.0, 2.45), (0.5, 0.02, 0.3), mat("daylight", (1, 1, 1), 0.5, emit=(1.0, 0.98, 0.92), strength=2.2))   # the ventilator
    for k in range(4):
        box((x0 - 0.38 + k * 0.12, y0 - d / 2 + 0.01, 2.45), (0.02, 0.02, 0.3), mat("window_bars", (0.1, 0.12, 0.1), 0.4, 0.6))
    cyl((x0, y0, h - 0.08), 0.04, 0.08, mat("bulb", (1, 1, 0.9), 0.3, emit=(1.0, 0.95, 0.85), strength=6), 16)
    light("tube", (x0, y0, h - 0.3), 9)
    # (the door: a plank door standing open into the bathroom)
    box((wall_x - 0.06 - 0.02, y0 + 0.4 + 0.33, 1.05), (0.04, 0.68, 2.05), mat("door_teak", (1, 1, 1), 0.5,
        tex=os.path.join(GTEX, "dark_timber_deck_base.jpg"), scale=1.0), 0.005, rot=(0, 0, 0.0))
    shot("bathroom", (wall_x + 0.9, y0 - 0.1, 1.6), (x0 - 0.3, y0, 0.7))


def home(T):
    W, D = 7.6, 6.0
    floor = mat("red_oxide", (1, 1, 1), 0.18, tex=T["red_oxide"], scale=2.0)
    wall = mat("distemper_blue", (1, 1, 1), 0.92, tex=T["distemper_blue"], normal=os.path.join(DTEX, "plaster_normal.jpg"), scale=2.5)
    dado = mat("dado_blue", (1, 1, 1), 0.3, tex=T["dado_blue"], scale=1.0)
    ceil = mat("ceiling_white", (0.93, 0.93, 0.9), 0.95)
    shell(W, D, H, floor, wall, ceil, dado, 1.0, door_w=1.0, door_x=-1.2,
          windows=[("L", 1.75, 0.9, 0.9, 1.2), ("R", 1.6, 0.9, 0.9, 1.2), ("B", 2.6, 0.7, 1.1, 0.9),
                   ("L", -0.45, 0.8, 0.0, 2.1)])                           # the bathroom's doorway off the hall
    bathroom(T, -W / 2 - 0.12, -0.45)
    # partitions: the hall (left), Karthik's room (right back), the kitchen (left back)
    part = wall
    box((1.4, 1.2, H / 2), (0.1, 3.6, H), part)                     # hall | Karthik's room, a doorway at y=-0.4
    box((1.4, -2.6, H / 2), (0.1, 0.8, H), part)
    box((1.4, -1.3, H - 0.4), (0.1, 1.8, 0.8), part)
    box((-2.4, 2.05, H / 2), (0.1, 1.9, H), part)                   # the kitchen corner, back left, its doorway
    box((-2.4, 0.7, H - 0.4), (0.1, 0.8, 0.8), part)                # at y 0.3..1.1 under a lintel
    box((-3.2, 0.25, H / 2), (1.6, 0.1, H), part)
    curtain(-2.4, 0.3, 1.1, 0.12, 2.25, mat("curtain_print", (1, 1, 1), 0.9, tex=T["curtain_print"], scale=0.45))
    cyl((-2.4, 0.7, 2.3), 0.012, 0.8, mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55), 8, rot=(math.pi / 2, 0, 0))
    wood = mat("timber", (1, 1, 1), 0.55, tex=os.path.join(GTEX, "warm_natural_timber_base.jpg"),
               normal=os.path.join(GTEX, "warm_natural_timber_normal.png"), scale=1.2)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    # Amma's sewing machine on its iron stand, by the window
    black = mat("machine_black", (0.03, 0.03, 0.035), 0.3, 0.2)
    box((-3.3, -1.4, 0.74), (0.5, 0.95, 0.04), wood, 0.01)
    box((-3.3, -1.4, 0.35), (0.42, 0.06, 0.7), black)
    box((-3.3, -1.75, 0.08), (0.35, 0.25, 0.03), black)             # the treadle
    box((-3.25, -1.45, 0.86), (0.18, 0.4, 0.14), black, 0.03)
    box((-3.25, -1.62, 1.0), (0.14, 0.08, 0.16), black, 0.03)
    cyl((-3.25, -1.2, 0.86), 0.06, 0.03, steel, 16, rot=(0, math.pi / 2, 0))
    box((-3.35, -1.2, 0.78), (0.4, 0.4, 0.04), mat("cloth_pink", (0.85, 0.42, 0.55), 0.9), 0.01)
    chair_poly(-2.75, -1.4, -math.pi / 2, (0.7, 0.12, 0.1))
    # the hall: plastic chairs, a TV on its cabinet, the steel almirah, a mat rolled in the corner
    for x, y, yaw in ((-0.4, 0.9, math.pi), (0.4, 0.9, math.pi), (-0.2, -0.6, 0.0)):
        chair_poly(x, y, yaw, (0.72, 0.12, 0.1))
    box((0.0, 2.65, 0.32), (1.1, 0.42, 0.64), wood, 0.01)
    box((0.0, 2.7, 0.92), (0.82, 0.08, 0.5), mat("tv_black", (0.02, 0.02, 0.025), 0.15), 0.01)
    almirah(1.08, -2.45, -math.pi / 2)
    cyl((-0.4, 2.7, 0.08), 0.08, 0.9, mat("mat_reed", (0.75, 0.62, 0.38), 0.9), 16, rot=(0, math.pi / 2, 0))
    # the back wall: the family photos (Appa garlanded), the calendar, the clock, a switchboard by the door
    frame(-1.4, D / 2 - 0.02, 1.95, 0.42, 0.52, mat("photo_appa", (1, 1, 1), 0.7, tex=T["photo_appa"]))
    garland = mat("garland", (0.95, 0.55, 0.1), 0.9)
    for k in range(9):
        a = math.pi * k / 8
        cyl((-1.4 + 0.26 * math.cos(a), D / 2 - 0.05, 1.68 - 0.06 * math.sin(a)), 0.03, 0.06, garland, 8, rot=(math.pi / 2, 0, 0))
    frame(-0.65, D / 2 - 0.02, 1.9, 0.62, 0.45, mat("photo_family", (1, 1, 1), 0.7, tex=T["photo_family"]))
    frame(0.0, D / 2 - 0.02, 1.9, 0.32, 0.42, mat("photo_kids", (1, 1, 1), 0.6, tex=T["photo_kids"]))
    box((0.8, D / 2 - 0.02, 1.7), (0.42, 0.01, 0.62), mat("calendar", (1, 1, 1), 0.8, tex=T["calendar"]))
    # the shrine in the left wall: a niche, a small framed picture, a brass lamp lit
    brass = mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0)
    box((-W / 2 + 0.06, 1.3, 1.5), (0.12, 0.6, 0.06), wood, 0.005)
    frame(-W / 2 + 0.03, 1.3, 1.8, 0.25, 0.3, mat("photo_god", (1, 1, 1), 0.5, tex=T["photo_god"]), facing="+x")
    cyl((-W / 2 + 0.15, 1.15, 1.6), 0.05, 0.12, brass, 16)
    cyl((-W / 2 + 0.15, 1.15, 1.69), 0.01, 0.025, mat("flame", (1, 0.6, 0.2), 0.5, emit=(1, 0.55, 0.15), strength=10), 8)
    light("lamp", (-W / 2 + 0.3, 1.15, 1.7), 0)
    cyl((-W / 2 + 0.3, 2.0, 0.22), 0.16, 0.36, brass, 20, r2=0.1)   # the brass water pot
    # the kitchen: granite platform, the stove, the red cylinder below, a vessel rack, the mixie
    gran = mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"], scale=1.0)
    box((-3.1, 2.6, 0.82), (1.3, 0.6, 0.05), gran, 0.005)
    box((-3.1, 2.6, 0.4), (1.3, 0.55, 0.8), mat("cement_kitchen", (0.55, 0.53, 0.5), 0.9))
    box((-3.3, 2.6, 0.9), (0.62, 0.38, 0.08), steel, 0.01)
    for s in (-1, 1):
        cyl((-3.3 + s * 0.15, 2.6, 0.95), 0.07, 0.02, black, 16)
    unbrand = (("Cylinder_1", 245, 65, 412, 325, 185), ("Cylinder_1", 240, 595, 412, 825, 185))   # its maker's name and logo
    if sketchfab("indane_gas_cylinder_-_low_poly", (-2.66, 2.06, 0.0), 0.68, yaw=2.4, paint=unbrand) is None:
        cyl((-3.3, 2.55, 0.3), 0.15, 0.55, mat("cylinder_red", (0.7, 0.08, 0.06), 0.35), 20)
    cyl((-2.75, 2.2, 0.75), 0.006, 0.3, mat("hose_black", (0.05, 0.05, 0.05), 0.6), 8, rot=(0.9, 0, 0.5))   # the hose up to the stove
    box((-3.1, 2.84, 1.55), (1.2, 0.25, 0.03), wood)
    for k in range(5):
        cyl((-3.6 + k * 0.25, 2.84, 1.68), 0.09, 0.22, steel, 16)
    box((-2.65, 2.6, 0.99), (0.16, 0.16, 0.28), mat("mixie_white", (0.92, 0.92, 0.9), 0.35), 0.03)
    # Karthik's room: the cot and its sheet, the table with the phone on charge, shirts on hooks, the cap
    sheet = mat("bedsheet", (1, 1, 1), 0.85, tex=T["bedsheet"], scale=0.8)
    box((2.75, 2.2, 0.22), (1.95, 0.95, 0.44), wood, 0.01)
    box((2.75, 2.2, 0.52), (1.9, 0.9, 0.14), sheet, 0.04)
    box((3.45, 2.2, 0.64), (0.4, 0.62, 0.1), mat("pillow", (0.93, 0.93, 0.9), 0.85), 0.04)
    table(2.6, 0.0, 0.7, 0.45, 0.74, wood, wood)
    box((2.5, 0.0, 0.75), (0.075, 0.15, 0.01), mat("phone_black", (0.02, 0.02, 0.025), 0.15), 0.003)
    box((2.75, 0.18, 0.76), (0.04, 0.03, 0.03), mat("charger_white", (0.93, 0.93, 0.9), 0.4))
    shirts = (mat("shirt_blue", (0.3, 0.5, 0.8), 0.85), mat("shirt_white", (0.92, 0.92, 0.9), 0.85), mat("shirt_check", (0.6, 0.25, 0.2), 0.85))
    for k, sm in enumerate(shirts):
        box((W / 2 - 0.08, -0.9 + k * 0.45, 1.45), (0.05, 0.42, 0.62), sm, 0.02)
    cyl((W / 2 - 0.1, -1.5, 1.85), 0.11, 0.08, mat("cap_black", (0.06, 0.06, 0.08), 0.8), 20, rot=(0, math.pi / 2, 0))
    box((W / 2 - 0.03, 0.5, 1.6), (0.02, 0.35, 0.5), mat("mirror", (0.85, 0.88, 0.9), 0.02, 1.0))
    # lights, fans
    tube_light(-0.6, 0.0, H - 0.05, True, 0)
    tube_light(2.6, 1.0, H - 0.05, False, 1)
    tube_light(-3.1, 2.0, H - 0.05, True, 2)
    ceiling_fan(-0.6, 0.6, H)
    ceiling_fan(2.6, 1.2, H)
    mark("amma", -1.5, 0.5, math.pi)
    chair_poly(-1.5, 0.53, math.pi, (0.72, 0.12, 0.1))                    # Amma's chair by the curtain, facing the door as she does
    mark("divya", -0.5, -0.6, 0.74)
    mark("karthik", -1.1, -1.5, 0.0)
    mark("karthik_room", 2.3, 0.5, math.pi)
    mark("door", -1.2, -2.6, math.pi)
    # the places Karthik walks to in the morning (story "home" visits)
    mark("bathroom", -4.75, -0.45, -math.pi / 2)                          # inside, at the tap and bucket
    mark("wardrobe", 3.15, -0.45, -math.pi / 2)                           # his shirts on the hooks
    mark("kitchen", -1.95, 0.75, math.pi / 2)                             # at the kitchen doorway, Amma inside
    mark("amma_kitchen", -3.0, 1.4, -math.pi / 2)
    mark("amma_dinner", -1.45, 2.12, math.pi)                            # at dinner: on her chair by the dining corner
    chair_poly(-1.45, 2.15, math.pi, (0.72, 0.12, 0.1))
    mark("door_shelf", -0.5, -2.35, math.pi)                              # the shelf by the door: wallet, phone, keys
    box((-0.5, -D / 2 + 0.11, 1.05), (0.5, 0.18, 0.025), mat("timber", (1, 1, 1), 0.55), 0.004)
    box((-0.62, -D / 2 + 0.11, 1.075), (0.11, 0.08, 0.02), mat("wallet_brown", (0.35, 0.2, 0.1), 0.6), 0.004)
    box((-0.45, -D / 2 + 0.11, 1.07), (0.075, 0.15, 0.01), mat("phone_black", (0.02, 0.02, 0.025), 0.15), 0.003)
    for k in range(2):                                                   # the keys on hooks below
        cyl((-0.3 + k * 0.08, -D / 2 + 0.04, 0.95), 0.006, 0.03, mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0), 8, rot=(math.pi / 2, 0, 0))
        box((-0.3 + k * 0.08, -D / 2 + 0.06, 0.9), (0.02, 0.004, 0.06), mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55))
    shot("wide", (0.45, -2.55, 2.2), (-1.6, 1.2, 1.0))
    shot("amma", (-1.0, -0.75, 1.32), (-1.5, 0.5, 1.12))                 # (she sits on the chair at her mark)
    shot("divya", (-1.0, 0.15, 1.5), (-0.5, -0.6, 1.4))
    shot("karthik", (-1.25, 0.0, 1.6), (-1.1, -1.5, 1.5))
    shot("photos", (-0.7, 1.4, 1.65), (-0.7, D / 2, 1.9))
    shot("room", (1.9, -1.8, 1.9), (2.8, 1.0, 0.8))
    shot("kitchen", (-2.65, 0.45, 1.8), (-3.3, 2.6, 1.0))
    shot("breakfast", (-0.7, 0.4, 1.3), (-1.6, 1.5, 0.2))


def dev_office(T):
    W, D, h = 9.0, 7.0, 3.1
    floor = mat("tile_cream", (1, 1, 1), 0.12, tex=T["tile_cream"], scale=1.2)
    wall = mat("wall_offwhite", (1, 1, 1), 0.9, tex=T["wall_offwhite"], normal=os.path.join(DTEX, "plaster_normal.jpg"), scale=2.5)
    ceil = mat("false_ceiling", (0.95, 0.95, 0.93), 0.9)
    shell(W, D, h, floor, wall, ceil, None, door_w=1.2, door_x=1.8, windows=[("R", 0.8, 1.6, 0.9, 1.5), ("B", -2.6, 1.4, 1.0, 1.3)])
    wood = mat("timber_dark", (1, 1, 1), 0.45, tex=os.path.join(GTEX, "dark_timber_deck_base.jpg"), scale=1.5)
    gran = mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"], scale=1.0)
    glass = mat("glass", (0.6, 0.72, 0.75), 0.05, alpha=0.12)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    # reception under the company board, by the door
    box((2.2, -1.9, 0.55), (1.8, 0.55, 1.1), wood, 0.02)
    box((2.2, -1.9, 1.12), (1.9, 0.62, 0.04), gran, 0.005)
    office_chair(2.2, -1.3, math.pi)
    sofa = mat("leather_brown", (0.28, 0.14, 0.08), 0.4)
    box((3.6, -3.0, 0.22), (1.8, 0.75, 0.44), sofa, 0.06)
    box((3.6, -3.32, 0.62), (1.8, 0.16, 0.5), sofa, 0.06)
    for s in (-1, 1):
        box((3.6 + s * 0.85, -3.0, 0.45), (0.14, 0.75, 0.5), sofa, 0.06)
    cyl((W / 2 - 0.4, 3.0, 0.3), 0.22, 0.6, mat("pot_clay", (0.55, 0.3, 0.18), 0.85), 20)
    for k in range(7):                                           # an areca palm's fronds
        a = k * 0.9
        box((W / 2 - 0.4 + 0.25 * math.cos(a), 3.0 + 0.25 * math.sin(a), 1.2), (0.6, 0.05, 0.02),
            mat("palm_leaf", (0.2, 0.45, 0.18), 0.7), rot=(0.6, 0, a))
    box((W / 2 - 0.35, 2.2, 0.6), (0.32, 0.32, 1.2), mat("dispenser", (0.92, 0.92, 0.9), 0.4), 0.03)
    # the staff: two desks with partitions and computers, Suresh's desk, Karthik's small desk by the door
    fabric = mat("fabric_blue", (1, 1, 1), 0.9, tex=T["fabric_blue"], scale=0.6)
    screen = mat("screen", (0.05, 0.1, 0.15), 0.1, emit=(0.25, 0.45, 0.7), strength=1.5)
    for k, (x, y) in enumerate(((1.0, 0.8), (2.6, 0.8))):
        table(x, y, 1.4, 0.75, 0.75, mat("desk_top", (0.75, 0.68, 0.55), 0.5), steel)
        box((x, y + 0.4, 1.0), (1.45, 0.05, 1.0), fabric, 0.01)
        box((x, y + 0.2, 1.02), (0.55, 0.04, 0.33), mat("monitor", (0.04, 0.04, 0.045), 0.3), 0.01)
        box((x, y + 0.18, 1.02), (0.5, 0.005, 0.28), screen)
        box((x, y - 0.1, 0.77), (0.45, 0.15, 0.02), mat("keyboard", (0.08, 0.08, 0.09), 0.4))
        office_chair(x, y - 0.6, 0.0)
    table(1.6, -2.4, 1.0, 0.6, 0.75, mat("desk_top", (0.75, 0.68, 0.55), 0.5), steel)   # Karthik's desk
    box((1.45, -2.45, 0.76), (0.075, 0.15, 0.01), mat("phone_black", (0.02, 0.02, 0.025), 0.15), 0.003)
    box((1.75, -2.3, 0.77), (0.04, 0.03, 0.03), mat("charger_white", (0.93, 0.93, 0.9), 0.4))
    cyl((1.25, -2.3, 0.82), 0.035, 0.12, steel, 16)
    office_chair(1.6, -1.9, math.pi)
    # Raghavan's cabin, back left behind glass with a frosted band, a wooden door
    box((-0.7, -0.2, h / 2), (0.06, 0.06, h), steel)
    box((-2.6, -0.2, h / 2), (3.8, 0.02, h), glass)
    box((-2.6, -0.21, 1.35), (3.8, 0.01, 0.12), mat("frosted", (0.95, 0.96, 0.97), 0.6, alpha=0.55))
    box((-0.7, 1.65, h / 2), (0.02, 3.7, h), glass)
    exec_wood = mat("exec_wood", (1, 1, 1), 0.35, tex=os.path.join(GTEX, "dark_timber_deck_base.jpg"), scale=1.0)
    box((-2.9, 2.2, 0.38), (1.9, 0.9, 0.76), exec_wood, 0.015)
    box((-2.9, 2.2, 0.775), (1.95, 0.95, 0.015), glass)
    box((-2.0, 1.6, 0.38), (0.5, 0.5, 0.76), exec_wood, 0.015)   # the L return
    office_chair(-2.9, 2.95, math.pi)
    for x in (-3.4, -2.4):
        office_chair(x, 1.25, 0.0)
    box((-3.5, 1.95, 0.88), (0.22, 0.03, 0.17), mat("frame_wood", (0.25, 0.14, 0.07), 0.45), 0.004)
    box((-3.5, 1.935, 0.88), (0.19, 0.005, 0.14), mat("photo_hills", (1, 1, 1), 0.6, tex=T["photo_hills"]))
    box((-2.9, 1.8, 0.82), (0.32, 0.06, 0.07), mat("nameplate", (0.75, 0.6, 0.3), 0.3, 0.8), 0.01)
    for k, c in enumerate(((0.15, 0.5, 0.25), (0.6, 0.15, 0.1), (0.8, 0.7, 0.45))):     # Green Valley on top
        box((-2.3, 2.3, 0.8 + k * 0.035), (0.34, 0.25, 0.03), mat("file_%d" % k, c, 0.8))
    box((-2.1, 2.05, 0.83), (0.2, 0.16, 0.08), mat("desk_phone", (0.1, 0.1, 0.11), 0.4), 0.02)
    frame(-2.9, D / 2 - 0.02, 1.85, 1.5, 0.95, mat("layout_plan", (1, 1, 1), 0.85, tex=T["layout_plan"]))
    box((-4.2, 2.9, 0.95), (0.6, 0.45, 1.9), exec_wood, 0.01)       # the trophy cabinet
    for k in range(3):
        cyl((-4.2, 2.75, 1.25 + k * 0.4), 0.05, 0.22, mat("trophy", (0.85, 0.7, 0.3), 0.25, 1.0), 12)
    box((-2.9, D / 2 - 0.12, h - 0.4), (1.0, 0.22, 0.3), mat("ac_white", (0.95, 0.95, 0.94), 0.35), 0.03)
    blinds = mat("blinds", (0.85, 0.82, 0.75), 0.7)
    for k in range(10):                                          # vertical blinds over the cabin window
        box((-3.25 + k * 0.14, D / 2 - 0.15, 1.65), (0.1, 0.01, 1.4), blinds, rot=(0, 0, 0.5))
    almirah(-4.3, -2.8, -math.pi / 2, False)
    box((0.0, D / 2 - 0.03, 1.6), (1.0, 0.03, 0.75), mat("notice", (1, 1, 1), 0.8, tex=T["notice"]))
    for k, (x, y) in enumerate(((-2.8, 1.6), (1.8, 0.6), (2.6, -2.2))):
        box((x, y, h - 0.02), (0.6, 0.6, 0.02), mat("panel_light", (1, 1, 1), 0.3, emit=(1.0, 0.98, 0.95), strength=4.0))
        light("tube", (x, y, h - 0.2), k)
    mark("raghavan_desk", -2.9, 2.85, math.pi)
    mark("visitor_l", -3.4, 0.85, 0.0)
    mark("visitor_r", -2.4, 0.85, 0.0)
    mark("suresh", -1.6, 1.9, math.pi / 2)
    mark("karthik_desk", 1.6, -1.75, math.pi)
    mark("suresh_desk", 2.6, 0.2, 0.0)
    mark("reception", 2.2, -1.3, math.pi)
    mark("door", 1.8, -3.0, 0.0)
    shot("cabin", (0.3, -1.0, 1.9), (-2.9, 2.2, 1.0))
    shot("raghavan", (-2.6, 1.0, 1.35), (-2.9, 2.85, 1.25))
    shot("karthik", (-2.7, 2.6, 1.45), (-3.4, 0.85, 1.2))
    shot("suresh", (-2.2, 1.0, 1.5), (-1.6, 1.9, 1.5))
    shot("desk", (0.6, -3.0, 1.6), (1.6, -2.2, 0.9))
    shot("hall", (4.0, -3.2, 2.2), (-1.0, 1.2, 1.0))


def coopbank(T):
    W, D, h = 11.0, 8.0, 3.4
    floor = mat("granite_grey", (1, 1, 1), 0.15, tex=T["granite_grey"], scale=1.2)
    wall = mat("wall_offwhite", (1, 1, 1), 0.9, tex=T["wall_offwhite"], scale=2.5)
    ceil = mat("ceiling_white", (0.93, 0.93, 0.9), 0.95)
    shell(W, D, h, floor, wall, ceil, mat("dado_brown", (1, 1, 1), 0.4, tex=T["dado_brown"]), 1.1,
          door_w=1.6, door_x=0.0, windows=[("L", -1.0, 1.4, 1.1, 1.4), ("R", -1.0, 1.4, 1.1, 1.4)])
    wood = mat("counter_wood", (1, 1, 1), 0.45, tex=os.path.join(GTEX, "warm_natural_timber_base.jpg"), scale=1.0)
    gran = mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"], scale=1.0)
    glass = mat("glass", (0.6, 0.72, 0.75), 0.05, alpha=0.12)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    # the counters: wood with granite tops, glass up to the ceiling, speaking holes, lit counter numbers
    y = 1.4
    box((0, y, 0.55), (9.0, 0.6, 1.1), wood, 0.01)
    box((0, y, 1.12), (9.1, 0.68, 0.04), gran, 0.005)
    box((0, y + 0.1, 2.3), (9.0, 0.015, 2.3), glass)
    lit = mat("counter_no", (0.05, 0.05, 0.05), 0.3, emit=(1.0, 0.25, 0.1), strength=3.0)
    for k in range(4):
        x = -3.4 + k * 2.25
        box((x, y + 0.11, 1.55), (0.3, 0.02, 0.3), mat("speak_ring", (0.6, 0.6, 0.62), 0.3, 1.0))
        box((x, y - 0.05, 1.18), (0.16, 0.1, 0.08), mat("pen_holder", (0.1, 0.1, 0.1), 0.4))
        office_chair(x, y + 0.9, math.pi)
    box((-1.15, y - 0.1, 1.22), (0.32, 0.28, 0.16), mat("cash_machine", (0.85, 0.85, 0.82), 0.4), 0.02)
    box((3.2, D / 2 - 0.05, 2.25), (1.0, 0.06, 0.32), mat("token", (0.03, 0.03, 0.03), 0.4), 0.01)   # the token display
    text("A-27", (3.2, D / 2 - 0.085, 2.25), 0.2, mat("token_digits", (1, 0.2, 0.1), 0.4, emit=(1.0, 0.15, 0.05), strength=5), "-y", FONT_COND)
    # behind the counters: desks, ledgers, almirahs, the strong-room door
    for x in (-3.0, 0.0, 3.0):
        table(x, 2.9, 1.3, 0.7, 0.75, wood, steel)
        box((x - 0.2, 2.9, 0.82), (0.32, 0.24, 0.12), mat("ledger", (0.45, 0.12, 0.1), 0.7), 0.005)
    box((4.4, D / 2 - 0.08, 1.1), (1.1, 0.15, 2.1), mat("strongroom", (0.35, 0.38, 0.36), 0.3, 0.8), 0.02)
    cyl((4.4, D / 2 - 0.18, 1.1), 0.18, 0.06, steel, 24, rot=(math.pi / 2, 0, 0))
    almirah(-4.6, 3.3, math.pi, False)
    # the public side: steel row seating, the slip-writing desk, notice board, the ATM by the door
    for row in (-1.2, -2.4):
        box((-1.0, row, 0.45), (3.0, 0.45, 0.04), steel, 0.01)
        box((-1.0, row - 0.2, 0.75), (3.0, 0.04, 0.55), steel, 0.01)
        for s in (-1.3, 0.0, 1.3):
            box((-1.0 + s, row, 0.22), (0.05, 0.4, 0.44), steel)
    box((3.4, -1.6, 0.55), (1.2, 0.6, 1.1), wood, 0.01)
    box((3.4, -1.6, 1.12), (1.25, 0.65, 0.04), gran)
    box((-W / 2 + 0.03, 0.2, 1.7), (0.03, 1.2, 0.9), mat("notice", (1, 1, 1), 0.8, tex=T["notice"]))
    box((-4.6, -3.4, 0.95), (0.8, 0.6, 1.9), mat("atm", (0.3, 0.32, 0.35), 0.4, 0.6), 0.02)
    box((-4.6, -3.71, 1.3), (0.4, 0.02, 0.3), mat("screen", (0.05, 0.1, 0.15), 0.1, emit=(0.25, 0.45, 0.7), strength=1.5))
    for k, (x, yy) in enumerate(((-3.0, 0.0), (2.0, 0.0), (0.0, 2.6))):
        tube_light(x, yy, h - 0.05, True, k)
    ceiling_fan(-2.0, -1.8, h)
    ceiling_fan(2.0, -1.8, h)
    mark("clerk", -1.15, y + 0.75, math.pi)
    mark("karthik", -1.15, y - 0.75, 0.0)
    mark("door", 0.0, -3.4, 0.0)
    shot("counter", (0.3, -1.0, 1.65), (-1.15, y + 0.75, 1.45))
    shot("karthik", (-1.6, y + 0.4, 1.55), (-1.15, y - 0.75, 1.45))
    shot("wide", (4.6, -3.4, 2.3), (-1.0, 1.4, 1.1))


def mess(T):
    W, D, h = 9.0, 7.0, 3.2
    floor = mat("tile_cream", (1, 1, 1), 0.2, tex=T["tile_cream"], scale=1.2)
    wall = mat("wall_green_mess", (1, 1, 1), 0.9, tex=T["wall_green_mess"], scale=2.5)
    shell(W, D, h, floor, wall, mat("ceiling_white", (0.93, 0.93, 0.9), 0.95),
          mat("dado_tiles", (0.92, 0.92, 0.9), 0.25), 1.2, door_w=2.0, door_x=0.0)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    top = mat("steel_top", (0.8, 0.81, 0.82), 0.25, 0.55)
    for x in (-2.6, 0.0, 2.6):
        for yy in (-1.6, 0.6):
            table(x, yy, 1.6, 0.7, 0.75, top, steel)
            for s in (-1, 1):
                box((x, yy + s * 0.6, 0.45), (1.6, 0.3, 0.04), steel, 0.005)
                for e in (-0.7, 0.7):
                    box((x + e, yy + s * 0.6, 0.22), (0.04, 0.26, 0.44), steel)
            for k in range(3):
                cyl((x - 0.5 + k * 0.5, yy, 0.82), 0.04, 0.12, steel, 16)
    box((-W / 2 + 0.35, -1.0, 0.85), (0.5, 2.4, 0.12), mat("basin_white", (0.93, 0.93, 0.92), 0.25), 0.02)
    for k in range(4):
        cyl((-W / 2 + 0.1, -2.0 + k * 0.65, 1.1), 0.015, 0.2, steel, 8, rot=(0, math.pi / 2, 0))
    box((3.3, -2.6, 0.55), (1.4, 0.7, 1.1), mat("counter_wood", (0.35, 0.2, 0.1), 0.45), 0.01)   # the cash counter
    box((3.3, -2.6, 1.12), (1.45, 0.75, 0.04), mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"]))
    box((3.0, -2.6, 1.2), (0.35, 0.25, 0.12), mat("cash_box", (0.5, 0.1, 0.08), 0.5), 0.01)
    trim = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    for zz in (0.78, 1.82):                                        # the kitchen hatch: a steel-trimmed opening
        box((0.0, D / 2 - 0.08, zz), (2.6, 0.16, 0.05), trim)
    for xx in (-1.3, 1.3):
        box((xx, D / 2 - 0.08, 1.3), (0.05, 0.16, 1.1), trim)
    for k in range(4):                                             # vessels on the kitchen shelf beyond
        cyl((-0.9 + k * 0.6, D / 2 - 0.05, 1.55), 0.12, 0.18, mat("pot_alu", (0.6, 0.6, 0.62), 0.4, 0.6), 16)
    cyl((0.0, D / 2 - 0.3, 1.0), 0.45, 0.04, mat("tawa", (0.08, 0.08, 0.08), 0.5, 0.6), 32)
    box((-2.8, D / 2 - 0.03, 2.0), (1.5, 0.03, 1.0), mat("menu_board", (1, 1, 1), 0.7, tex=T["menu_board"]))
    box((2.8, D / 2 - 0.35, 0.95), (0.75, 0.6, 1.9), mat("fridge_red", (0.75, 0.1, 0.08), 0.35), 0.03)
    box((2.8, D / 2 - 0.66, 1.0), (0.6, 0.02, 1.5), mat("glass", (0.6, 0.72, 0.75), 0.05, alpha=0.12))
    table(-1.6, D / 2 - 0.5, 0.7, 0.5, 0.65, steel, steel)                # the leaf stand
    box((-1.6, D / 2 - 0.5, 0.72), (0.6, 0.4, 0.12), mat("banana_leaf", (0.2, 0.5, 0.18), 0.6), 0.01)
    for k, (x, yy) in enumerate(((-2.0, -0.5), (2.0, -0.5), (0.0, 2.2))):
        tube_light(x, yy, h - 0.05, True, k)
    for x in (-2.6, 0.0, 2.6):
        ceiling_fan(x, -0.5, h)
    mark("cook", 3.3, -2.0, math.pi)
    mark("karthik", 3.3, -3.25, 0.0)
    mark("karthik_eat", -0.1, -1.03, math.pi)                             # eating out: on the bench, the leaf at his right hand
    mark("door", 0.0, -3.0, 0.0)
    shot("eat", (0.55, -2.75, 1.45), (-0.15, -1.0, 0.95))                 # (the kitchen hatch and menu board behind him)
    shot("counter", (1.8, -3.2, 1.6), (3.3, -2.0, 1.45))
    shot("wide", (-4.0, -3.0, 2.3), (1.0, 1.0, 1.0))
    shot("table", (0.9, -2.7, 1.5), (0.0, -1.6, 0.75))


def police(T):
    W, D, h = 10.0, 8.0, 3.4
    floor = mat("red_oxide", (1, 1, 1), 0.25, tex=T["red_oxide"], scale=2.0)
    wall = mat("wall_cream_police", (1, 1, 1), 0.92, tex=T["wall_cream_police"], scale=2.5)
    shell(W, D, h, floor, wall, mat("ceiling_white", (0.93, 0.93, 0.9), 0.95),
          mat("dado_brown", (1, 1, 1), 0.4, tex=T["dado_brown"]), 1.1, door_w=1.6, door_x=-1.5,
          windows=[("L", 0.0, 1.2, 1.0, 1.4), ("B", -2.5, 1.2, 1.2, 1.2)])
    wood = mat("timber", (1, 1, 1), 0.55, tex=os.path.join(GTEX, "warm_natural_timber_base.jpg"), scale=1.2)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    # the front desk with the signing register (Karthik signs here every evening)
    box((-1.0, -0.6, 0.5), (2.0, 0.75, 1.0), wood, 0.01)
    box((-1.0, -0.6, 1.02), (2.05, 0.8, 0.04), wood, 0.005)
    box((-1.2, -0.75, 1.06), (0.45, 0.32, 0.03), mat("register", (0.15, 0.25, 0.45), 0.6), 0.004)
    box((-1.2, -0.75, 1.08), (0.43, 0.3, 0.004), mat("register_page", (0.95, 0.94, 0.9), 0.8))
    cyl((-0.9, -0.75, 1.07), 0.006, 0.14, mat("pen_blue", (0.1, 0.2, 0.6), 0.3), 8, rot=(0, math.pi / 2, 0.3))
    chair_poly(-1.0, 0.0, math.pi, (0.12, 0.25, 0.55))
    # visitors' bench along the left wall
    box((-W / 2 + 0.4, -1.5, 0.45), (0.45, 2.4, 0.05), wood, 0.01)
    for s in (-1.0, 0.0, 1.0):
        box((-W / 2 + 0.4, -1.5 + s, 0.22), (0.4, 0.05, 0.44), wood)
    # the inspector's table at the back with files, a desk bell, a cap on the table
    table(2.0, 2.4, 1.6, 0.85, 0.78, mat("green_baize", (0.12, 0.3, 0.15), 0.9), wood)
    office_chair(2.0, 3.1, math.pi)
    for x in (1.6, 2.4):
        chair_poly(x, 1.6, 0.0, (0.3, 0.3, 0.32))
    box((2.4, 2.5, 0.84), (0.4, 0.3, 0.1), mat("file_stack", (0.8, 0.7, 0.45), 0.8))
    cyl((1.5, 2.3, 0.82), 0.04, 0.04, steel, 16)
    # the lock-up at the back right: bars and a door
    bars = mat("cell_bars", (0.15, 0.15, 0.17), 0.4, 0.7)
    for k in range(18):
        box((3.2 + k * 0.1, 0.6, h / 2), (0.025, 0.025, h), bars)
    box((4.0, 0.6, h - 0.1), (1.8, 0.06, 0.08), bars)
    box((4.0, 0.6, 1.0), (1.8, 0.04, 0.05), bars)
    # the wireless set, almirahs, the notice board (wanted / missing)
    box((-3.8, D / 2 - 0.35, 0.95), (0.9, 0.5, 0.06), wood)
    box((-3.8, D / 2 - 0.35, 1.08), (0.4, 0.3, 0.2), mat("wireless", (0.2, 0.25, 0.2), 0.5, 0.3), 0.01)
    cyl((-3.6, D / 2 - 0.35, 1.45), 0.008, 0.6, steel, 6)
    almirah(-4.5, 2.0, -math.pi / 2, False)
    almirah(-4.5, 3.0, -math.pi / 2, False)
    box((0.0, D / 2 - 0.03, 1.7), (1.4, 0.03, 0.9), mat("notice", (1, 1, 1), 0.8, tex=T["notice"]))
    for k, (x, yy) in enumerate(((-1.0, -0.4), (2.0, 2.0), (-3.5, 2.0))):
        tube_light(x, yy, h - 0.05, True, k)
    ceiling_fan(-1.0, 0.6, h)
    ceiling_fan(2.0, 1.4, h)
    mark("constable", -1.0, 0.05, math.pi)
    mark("karthik", -1.0, -1.35, 0.0)
    mark("inspector", 2.0, 3.0, math.pi)
    mark("door", -1.5, -3.4, 0.0)
    shot("desk", (0.3, -1.8, 1.6), (-1.0, 0.05, 1.4))
    shot("register", (-1.0, -1.1, 1.6), (-1.2, -0.75, 1.06))
    shot("karthik", (-1.5, 0.2, 1.55), (-1.0, -1.35, 1.45))
    shot("wide", (3.8, -3.4, 2.4), (-1.0, 0.8, 1.1))


# ============================================================================ the detail pass: what makes each place
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_COND = "/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf"
FACING = {"-y": 0.0, "+y": math.pi, "+x": math.pi / 2, "-x": -math.pi / 2}


def text(s, loc, size, m, facing="-y", font=FONT_BOLD, depth=0.004):
    """Lettering (signs, boards, nameplates) as real geometry, facing into the room."""
    cu = bpy.data.curves.new("Text", 'FONT')
    cu.body = s
    cu.size = size
    cu.extrude = depth
    cu.resolution_u = 3                                   # letters stay light on polygons
    cu.align_x, cu.align_y = 'CENTER', 'CENTER'
    if os.path.exists(font):
        cu.font = bpy.data.fonts.load(font, check_existing=True)
    ob = _link(bpy.data.objects.new("Text", cu))
    ob.location = loc
    ob.rotation_euler = (math.pi / 2, 0, FACING[facing])
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.ops.object.convert(target='MESH')
    ob.data.materials.clear()
    ob.data.materials.append(m)
    return ob


def sign(s, loc, w, h, board, ink, facing="-y", size=None, font=FONT_BOLD):
    """A board with lettering on it."""
    n = Vector((0, -1, 0))
    n.rotate(Matrix.Rotation(FACING[facing], 3, 'Z'))
    thick = (w, 0.03, h) if facing in ("-y", "+y") else (0.03, w, h)
    box(loc, thick, board, 0.006)
    text(s, Vector(loc) + n * 0.017, size or h * 0.55, ink, facing, font)


def door_leaf(hinge_x, y, width, wood, swing=-1):
    """A panelled wooden door standing open against the front wall inside (swing -1: to the left of the hinge)."""
    cx = hinge_x + swing * width / 2
    box((cx, y + 0.03, 1.05), (width, 0.04, 2.08), wood, 0.006)
    panel = mat("door_panel", (0.3, 0.17, 0.08), 0.45)
    for z in (0.55, 1.5):
        box((cx, y + 0.055, z), (width - 0.2, 0.012, 0.75), panel, 0.004)
    brass = mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0)
    box((hinge_x + swing * (width - 0.08), y + 0.07, 1.0), (0.03, 0.03, 0.14), brass)
    box((hinge_x + swing * (width - 0.08), y + 0.07, 1.9), (0.1, 0.02, 0.02), brass)        # the tower bolt


def conduit(points, r=0.012):
    """Surface wiring in white PVC conduit along the walls (every Indian room has it)."""
    pvc = mat("conduit", (0.9, 0.9, 0.88), 0.4)
    for a, b in zip(points, points[1:]):
        a, b = Vector(a), Vector(b)
        d = b - a
        size = (abs(d.x) + 2 * r, abs(d.y) + 2 * r, abs(d.z) + 2 * r)
        box((a + b) / 2, size, pvc)


def switchboard(x, y, z, facing="-y", w=0.3):
    sb = mat("switchboard", (0.92, 0.92, 0.9), 0.4)
    sw = mat("switch_key", (0.98, 0.98, 0.97), 0.3)
    n = Vector((0, -1, 0))
    n.rotate(Matrix.Rotation(FACING[facing], 3, 'Z'))
    t = Vector((1, 0, 0))
    t.rotate(Matrix.Rotation(FACING[facing], 3, 'Z'))
    c = Vector((x, y, z))
    box(c, (w, 0.03, 0.15) if facing in ("-y", "+y") else (0.03, w, 0.15), sb, 0.004)
    for k in range(int(w / 0.06)):
        box(c + n * 0.018 + t * (-w / 2 + 0.04 + k * 0.055), (0.025, 0.01, 0.04) if facing in ("-y", "+y") else (0.01, 0.025, 0.04), sw)
    conduit([c + n * 0.0 + Vector((0, 0, 0.075)), c + Vector((0, 0, 3.4 - z - 0.2))])


def wall_clock(x, y, z, facing="-y"):
    n = Vector((0, -1, 0))
    n.rotate(Matrix.Rotation(FACING[facing], 3, 'Z'))
    rx = (math.pi / 2, 0, FACING[facing])
    cyl((x, y, z), 0.17, 0.05, mat("clock_rim", (0.15, 0.1, 0.08), 0.4), 32, rot=rx)
    cyl(Vector((x, y, z)) + n * 0.027, 0.15, 0.005, mat("clock_face", (0.95, 0.95, 0.9), 0.4), 32, rot=rx)
    hand = mat("clock_hand", (0.05, 0.05, 0.05), 0.4)
    c = Vector((x, y, z)) + n * 0.032
    t = Vector((1, 0, 0))
    t.rotate(Matrix.Rotation(FACING[facing], 3, 'Z'))
    box(c + Vector((0, 0, 0.05)), (0.012, 0.004, 0.1) if facing in ("-y", "+y") else (0.004, 0.012, 0.1), hand)
    box(c + t * 0.04, (0.08, 0.004, 0.01) if facing in ("-y", "+y") else (0.004, 0.08, 0.01), hand)


def box_files(x0, x1, y, z0, rows, facing_y=-1):
    """An open steel rack full of coloured box files and bundles, along x at wall y."""
    steel = mat("rack_grey", (0.5, 0.52, 0.5), 0.4, 0.5)
    cols = [(0.6, 0.12, 0.1), (0.12, 0.25, 0.55), (0.15, 0.45, 0.2), (0.85, 0.7, 0.2), (0.4, 0.25, 0.15), (0.9, 0.88, 0.8)]
    rng = np.random.default_rng(int(x0 * 100) % 97)
    for r in range(rows + 1):
        box(((x0 + x1) / 2, y, z0 + r * 0.42), (x1 - x0, 0.38, 0.02), steel)
    for s in (x0, x1):
        box((s, y, z0 + rows * 0.21), (0.03, 0.38, rows * 0.42 + 0.04), steel)
    for r in range(rows):
        x = x0 + 0.04
        while x < x1 - 0.1:
            w = float(rng.uniform(0.06, 0.09))
            hgt = float(rng.uniform(0.28, 0.36))
            c = cols[int(rng.integers(0, len(cols)))]
            box((x + w / 2, y + facing_y * 0.02, z0 + r * 0.42 + 0.01 + hgt / 2), (w - 0.006, 0.3, hgt),
                mat("file_%.2f_%.2f_%.2f" % c, c, 0.8))
            x += w
            if rng.random() < 0.12:
                x += 0.08


def bundles(x, y, z, n, m_paper, m_tie):
    """Case bundles: paper stacks tied with red cloth tape."""
    for k in range(n):
        zz = z + k * 0.09
        box((x, y, zz + 0.04), (0.34, 0.24, 0.08), m_paper, 0.01)
        box((x, y, zz + 0.04), (0.02, 0.25, 0.085), m_tie)


def steel_chair(x, y, yaw, seat):
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    f = Vector((0, -1, 0))
    f.rotate(Matrix.Rotation(yaw, 3, 'Z'))
    s = Vector((1, 0, 0))
    s.rotate(Matrix.Rotation(yaw, 3, 'Z'))
    c = Vector((x, y, 0))
    box(c + Vector((0, 0, 0.45)), (0.44, 0.44, 0.04), seat, 0.01, rot=(0, 0, yaw))
    box(c - f * 0.21 + Vector((0, 0, 0.75)), (0.42, 0.04, 0.35), seat, 0.01, rot=(0, 0, yaw))
    for a in (-1, 1):
        for b in (-1, 1):
            box(c + s * a * 0.19 + f * b * 0.19 + Vector((0, 0, 0.22)), (0.025, 0.025, 0.44), steel)
        box(c + s * a * 0.19 - f * 0.2 + Vector((0, 0, 0.6)), (0.022, 0.022, 0.3), steel)


def monitor(x, y, z, yaw):
    """A desktop monitor on its stand, the screen lit, facing yaw (0: faces -Y)."""
    body = mat("monitor", (0.04, 0.04, 0.045), 0.3)
    scr = mat("screen", (0.05, 0.1, 0.15), 0.1, emit=(0.25, 0.45, 0.7), strength=1.5)
    f = Vector((0, -1, 0))
    f.rotate(Matrix.Rotation(yaw, 3, 'Z'))
    c = Vector((x, y, z))
    box(c + Vector((0, 0, 0.01)), (0.2, 0.16, 0.02), body, 0.005, rot=(0, 0, yaw))
    box(c + Vector((0, 0, 0.12)), (0.04, 0.03, 0.2), body, rot=(0, 0, yaw))
    box(c + Vector((0, 0, 0.3)) + f * 0.02, (0.5, 0.03, 0.31), body, 0.008, rot=(0, 0, yaw))
    box(c + Vector((0, 0, 0.31)) + f * 0.037, (0.46, 0.004, 0.27), scr, rot=(0, 0, yaw))


def plant(x, y, h=1.1):
    cyl((x, y, 0.2), 0.18, 0.4, mat("pot_clay", (0.55, 0.3, 0.18), 0.85), 20, r2=0.14)
    leaf = mat("palm_leaf", (0.2, 0.45, 0.18), 0.7)
    for k in range(9):
        a = k * 2.4
        tilt = 0.5 + 0.08 * (k % 3)
        box((x + 0.18 * math.cos(a), y + 0.18 * math.sin(a), 0.4 + h * 0.55 + 0.05 * (k % 2)), (0.55, 0.07, 0.015), leaf,
            rot=(tilt, 0, a + math.pi / 2))


def serial_lights(x0, x1, y, z, sag=0.12):
    """A string of small coloured bulbs, as around a god's photo."""
    cols = [(1, 0.2, 0.2), (0.2, 1, 0.3), (0.3, 0.5, 1), (1, 0.8, 0.2)]
    n = int((x1 - x0) / 0.06)
    for k in range(n + 1):
        t = k / n
        c = cols[k % 4]
        cyl((x0 + (x1 - x0) * t, y, z - sag * 4 * t * (1 - t)), 0.012, 0.02,
            mat("bulb_%d" % (k % 4), c, 0.3, emit=c, strength=6), 8)


def stanchion_row(x0, x1, y):
    steel = mat("chrome", (0.82, 0.82, 0.84), 0.2, 0.6)
    belt = mat("belt_red", (0.6, 0.08, 0.06), 0.6)
    n = max(1, int((x1 - x0) / 1.2))
    for k in range(n + 1):
        x = x0 + (x1 - x0) * k / n
        cyl((x, y, 0.015), 0.16, 0.03, steel, 20)
        cyl((x, y, 0.48), 0.025, 0.96, steel, 12)
        if k < n:
            box(((x + x0 + (x1 - x0) * (k + 1) / n) / 2, y, 0.9), ((x1 - x0) / n, 0.008, 0.05), belt)


def ceiling_grid(W, D, h, step=0.6):
    """The T-bar grid of an office false ceiling."""
    bar = mat("ceiling_grid", (0.82, 0.82, 0.8), 0.5)
    for k in range(int(W / step) + 1):
        box((-W / 2 + k * step, 0, h - 0.008), (0.022, D, 0.016), bar)
    for k in range(int(D / step) + 1):
        box((0, -D / 2 + k * step, h - 0.008), (W, 0.022, 0.016), bar)


def cornice(W, D, h, m):
    for s in (-1, 1):
        box((0, s * (D / 2 - 0.03), h - 0.05), (W, 0.06, 0.1), m)
        box((s * (W / 2 - 0.03), 0, h - 0.05), (0.06, D, 0.1), m)


def skirting(W, D, m, door_x=None, door_w=1.0):
    for s in (-1, 1):
        box((s * (W / 2 - 0.01), 0, 0.05), (0.02, D, 0.1), m)
    box((0, D / 2 - 0.01, 0.05), (W, 0.02, 0.1), m)
    if door_x is None:
        return
    left = door_x - door_w / 2 + W / 2
    right = W / 2 - door_x - door_w / 2
    box((-W / 2 + left / 2, -D / 2 + 0.01, 0.05), (left, 0.02, 0.1), m)
    box((W / 2 - right / 2, -D / 2 + 0.01, 0.05), (right, 0.02, 0.1), m)


def home_detail(T):
    W, D = 7.6, 6.0
    wood = mat("timber", (1, 1, 1), 0.55)
    teak = mat("door_teak", (1, 1, 1), 0.5, tex=os.path.join(GTEX, "dark_timber_deck_base.jpg"), scale=1.0)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    brass = mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0)
    door_leaf(-1.7, -D / 2, 0.95, teak, -1)
    skirting(W, D, mat("skirting_red", (0.32, 0.08, 0.05), 0.3), -1.2, 1.0)
    cornice(W, D, H, mat("cornice_white", (0.95, 0.95, 0.93), 0.9))
    # a handloom rug in the hall, slippers just inside the door, an umbrella on a nail
    box((-0.6, 0.0, 0.006), (1.8, 1.2, 0.012), mat("rug", (1, 1, 1), 0.95, tex=os.path.join(GTEX, "handloom_rug_base.jpg"), scale=1.2))
    rubber = (mat("slipper_blue", (0.15, 0.25, 0.6), 0.7), mat("slipper_red", (0.6, 0.12, 0.1), 0.7))
    for k, (x, y, a) in enumerate(((-2.0, -2.75, 0.2), (-2.12, -2.72, 0.1), (-2.4, -2.78, -0.3), (-2.52, -2.74, -0.2))):
        box((x, y, 0.012), (0.1, 0.26, 0.024), rubber[k // 2], 0.01, rot=(0, 0, a))
    cyl((-2.95, -D / 2 + 0.08, 1.15), 0.035, 0.8, mat("umbrella", (0.05, 0.05, 0.06), 0.6), 12, r2=0.01)
    # a wall shelf on the front wall: brass vessels, books, a radio
    box((-3.2, -D / 2 + 0.14, 1.8), (1.0, 0.25, 0.03), teak, 0.005)
    for k in range(3):
        cyl((-3.55 + k * 0.18, -D / 2 + 0.14, 1.88), 0.06 - k * 0.01, 0.13, brass, 16, r2=0.035)
    for k, c in enumerate(((0.5, 0.1, 0.1), (0.1, 0.3, 0.5), (0.7, 0.6, 0.3), (0.2, 0.4, 0.2))):
        box((-3.0 + k * 0.045, -D / 2 + 0.14, 1.93), (0.04, 0.18, 0.24 - k * 0.02), mat("book_%d" % k, c, 0.8))
    box((-2.85 + 0.25, -D / 2 + 0.14, 1.89), (0.26, 0.1, 0.15), mat("radio", (0.35, 0.2, 0.12), 0.4), 0.02)
    # wiring: the switchboards, conduit to the ceiling and along to the fans and tubes
    switchboard(-1.85, -D / 2 + 0.02, 1.3, "-y")
    switchboard(W / 2 - 0.02, -0.3, 1.3, "+x", 0.24)
    conduit([(-1.85, -D / 2 + 0.02, H - 0.15), (-0.6, -D / 2 + 0.02, H - 0.15), (-0.6, -D / 2 + 0.02, H - 0.02)])
    wall_clock(0.55, D / 2 - 0.02, 2.45)
    # a steel trunk under the cot, a school bag on a hook, a water bottle on the table, books, the mosquito coil
    box((2.6, 2.2, 0.15), (0.75, 0.45, 0.28), mat("trunk_green", (0.15, 0.3, 0.2), 0.4, 0.5), 0.01)
    box((3.75, -1.05, 1.3), (0.12, 0.32, 0.42), mat("bag_navy", (0.1, 0.12, 0.25), 0.8), 0.04)
    cyl((2.85, -0.1, 0.87), 0.035, 0.24, mat("bottle_blue", (0.3, 0.5, 0.8), 0.1, alpha=0.6), 16)
    for k in range(3):
        box((2.4, 0.12, 0.76 + k * 0.025), (0.2, 0.27, 0.022), mat("book_%d" % k, (0.5, 0.1, 0.1), 0.8))
    # the dining corner: a steel water pot and tumblers on a low stool by the kitchen doorway
    box((-1.9, 1.7, 0.2), (0.4, 0.4, 0.4), wood, 0.01)
    cyl((-1.9, 1.7, 0.53), 0.13, 0.26, steel, 20, r2=0.08)
    for k in range(2):
        cyl((-1.78 + k * 0.08, 1.58, 0.44), 0.03, 0.08, steel, 12, r2=0.035)
    sketchfab("idli_south_indian_food", (-1.35, 1.2, 0.012), 0.48, yaw=-0.3, drop=("Material.026",), by="width")
    sketchfab("tea_glass__chai_glass_indian_style", (-2.02, 1.82, 0.4), 0.1, drop=("Object_11",))
    # a calendar text, a small family sign
    text("2026", (0.8, D / 2 - 0.035, 1.47), 0.06, mat("ink_red", (0.7, 0.05, 0.05), 0.6), "-y")


def office_detail(T):
    W, D, h = 9.0, 7.0, 3.1
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    navy = mat("board_navy", (0.08, 0.12, 0.3), 0.4)
    gold = mat("letters_gold", (0.95, 0.78, 0.35), 0.3, 0.8)
    white = mat("letters_white", (0.97, 0.97, 0.97), 0.4)
    ceiling_grid(W, D, h)
    skirting(W, D, mat("skirting_grey", (0.45, 0.43, 0.4), 0.3), 1.8, 1.2)
    # the company board over reception (replacing the plain bar) and the nameplate
    sign("RAGHAVAN DEVELOPERS", (W / 2 - 0.05, -1.8, 2.25), 2.2, 0.42, navy, gold, "+x", 0.17)
    text("Plots  -  Villas  -  Since 1994", (W / 2 - 0.08, -1.8, 1.95), 0.07, white, "+x")
    text("R. RAGHAVAN", (-2.9, 1.765, 0.82), 0.035, mat("ink_black", (0.05, 0.05, 0.05), 0.4), "-y", depth=0.002)
    text("GREEN VALLEY  -  LAYOUT PLAN", (-2.9, D / 2 - 0.045, 2.42), 0.06, mat("ink_black", (0.05, 0.05, 0.05), 0.4), "-y")
    text("MD", (-1.0, -0.22, 2.1), 0.12, mat("frosted_ink", (0.3, 0.3, 0.35), 0.4), "-y")
    # a Ganesha on the reception counter, a printer, the file racks, a wall clock, visitors' chairs
    cyl((2.75, -1.9, 1.2), 0.05, 0.12, mat("ganesha", (0.85, 0.55, 0.3), 0.4, 0.5), 16, r2=0.035)
    cyl((2.75, -1.9, 1.28), 0.035, 0.06, mat("ganesha", (0.85, 0.55, 0.3), 0.4, 0.5), 12)
    table(0.3, -3.15, 0.8, 0.5, 0.75, mat("desk_top", (0.75, 0.68, 0.55), 0.5), steel)
    box((0.3, -3.15, 0.88), (0.45, 0.38, 0.22), mat("printer", (0.85, 0.85, 0.83), 0.4), 0.02)
    box((0.3, -3.12, 1.0), (0.32, 0.25, 0.02), mat("paper", (0.97, 0.97, 0.95), 0.8))
    box_files(-3.9, -1.0, -D / 2 + 0.22, 0.05, 4, 1)
    wall_clock(1.5, D / 2 - 0.02, 2.4)
    switchboard(1.05, -D / 2 + 0.02, 1.25, "-y")
    # the glass door handle of the cabin, the staff desks' clutter
    box((-0.95, -0.24, 1.05), (0.02, 0.04, 0.5), mat("chrome", (0.82, 0.82, 0.84), 0.2, 0.6))
    for x in (1.0, 2.6):
        box((x + 0.5, 0.9, 0.79), (0.24, 0.32, 0.06), mat("file_0", (0.15, 0.5, 0.25), 0.8))
        cyl((x - 0.55, 0.95, 0.82), 0.04, 0.12, mat("mug_white", (0.93, 0.93, 0.9), 0.3), 16)
    plant(-4.2, -0.6, 1.0)


def bank_detail(T):
    W, D, h = 11.0, 8.0, 3.4
    green = mat("bank_green", (0.05, 0.32, 0.18), 0.4)
    white = mat("letters_white", (0.97, 0.97, 0.97), 0.4)
    yellow = mat("letters_yellow", (1.0, 0.85, 0.2), 0.4)
    ink = mat("ink_black", (0.05, 0.05, 0.05), 0.4)
    y = 1.4
    sign("KOVAI NAGAR CO-OPERATIVE BANK", (0, D / 2 - 0.04, 3.0), 5.2, 0.45, green, yellow, "-y", 0.2)
    for k, lab in enumerate(("1  CASH", "2  CASH", "3  LOANS", "4  ENQUIRY")):
        x = -3.4 + k * 2.25
        sign(lab, (x, y + 0.06, 2.4), 1.0, 0.22, green, white, "-y", 0.12)
        monitor(x + 0.3, y + 0.25, 1.14, math.pi)                          # the clerk's screen faces the clerk
        box((x - 0.35, y + 0.3, 1.16), (0.3, 0.2, 0.06), mat("passbook_printer", (0.82, 0.82, 0.8), 0.4), 0.01)
    stanchion_row(-2.4, 0.1, y - 1.1)                                     # the cash queue
    # notices, a clock, CCTV, a pamphlet stand, a water can, a plant
    wall_clock(-3.2, D / 2 - 0.02, 2.55)
    cyl((4.6, -3.0, h - 0.06), 0.08, 0.08, mat("cctv", (0.15, 0.15, 0.16), 0.2), 16)
    cyl((-4.5, 3.0, h - 0.06), 0.08, 0.08, mat("cctv", (0.15, 0.15, 0.16), 0.2), 16)
    box((2.55, -2.2, 0.7), (0.4, 0.3, 1.4), mat("pamphlet_stand", (0.6, 0.6, 0.62), 0.3, 0.6), 0.01)
    for k in range(3):
        box((2.55, -2.36, 0.8 + k * 0.3), (0.3, 0.02, 0.22), mat("pamphlet_%d" % k, ((0.2, 0.5, 0.3), (0.9, 0.8, 0.3), (0.3, 0.4, 0.8))[k], 0.6))
    box((-W / 2 + 0.03, -2.4, 1.7), (0.02, 0.6, 0.85), mat("poster_loan", (0.9, 0.6, 0.15), 0.6))
    text("GOLD LOAN 7.5%", (-W / 2 + 0.05, -2.4, 1.9), 0.08, ink, "+x")
    text("CROP LOAN", (-W / 2 + 0.05, -2.4, 1.6), 0.08, ink, "+x")
    plant(4.8, -3.4, 1.2)
    cyl((-W / 2 + 0.4, -0.9, 0.55), 0.14, 0.5, mat("water_can", (0.3, 0.5, 0.85), 0.2, alpha=0.7), 20)
    box((-W / 2 + 0.4, -0.9, 0.15), (0.35, 0.35, 0.3), mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55))
    # behind the counter: ledgers, file racks, a computer at each desk
    box_files(-4.4, -2.0, D / 2 - 0.25, 0.05, 4, -1)
    for x in (-3.0, 0.0, 3.0):
        monitor(x + 0.3, 3.05, 0.76, math.pi)
        bundles(x - 0.45, 2.85, 0.76, 3, mat("paper", (0.97, 0.97, 0.95), 0.8), mat("tie_red", (0.7, 0.08, 0.06), 0.8))
    skirting(W, D, mat("skirting_grey", (0.45, 0.43, 0.4), 0.3), 0.0, 1.6)
    cornice(W, D, h, mat("cornice_white", (0.95, 0.95, 0.93), 0.9))
    switchboard(1.2, -D / 2 + 0.02, 1.3, "-y", 0.36)


def mess_detail(T):
    W, D, h = 9.0, 7.0, 3.2
    red = mat("sign_red", (0.7, 0.08, 0.06), 0.4)
    yellow = mat("letters_yellow", (1.0, 0.85, 0.2), 0.4)
    chalk = mat("chalk", (0.95, 0.95, 0.92), 0.8)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    sign("HOTEL ANNA MESS", (0.0, D / 2 - 0.04, 2.55), 3.0, 0.5, red, yellow, "-y", 0.26)
    menu = ["MENU", "Idli (2) ..... 20", "Dosa ......... 40", "Parotta ...... 15", "Meals ........ 90",
            "Pongal ....... 35", "Tea / Coffee . 12"]
    for k, line in enumerate(menu):
        text(line, (-2.8, D / 2 - 0.05, 2.36 - k * 0.13), 0.15 if k else 0.19, chalk, "-y", FONT_COND)
    # the god's photo over the cash counter, garlanded, with serial lights
    box((W / 2 - 0.03, -2.6, 2.1), (0.03, 0.56, 0.66), mat("frame_wood", (0.25, 0.14, 0.07), 0.45), 0.005)
    box((W / 2 - 0.05, -2.6, 2.1), (0.005, 0.5, 0.6), mat("photo_god", (1, 1, 1), 0.5, tex=T["photo_god"]))
    for k in range(9):
        a = math.pi * k / 8
        cyl((W / 2 - 0.07, -2.6 + 0.3 * math.cos(a), 1.78 - 0.08 * math.sin(a)), 0.03, 0.06,
            mat("garland", (0.95, 0.55, 0.1), 0.9), 8)
    for k in range(13):
        t = k / 12
        c = [(1, 0.2, 0.2), (0.2, 1, 0.3), (0.3, 0.5, 1), (1, 0.8, 0.2)][k % 4]
        cyl((W / 2 - 0.06, -2.95 + 0.7 * t, 2.48 - 0.1 * 4 * t * (1 - t)), 0.012, 0.02, mat("bulb_%d" % (k % 4), c, 0.3, emit=c, strength=6), 8)
    # on the counter: the sweets case, a bell; the tea urn; jugs on every table; the leaf stack; a wash-area mirror
    glass = mat("glass", (0.6, 0.72, 0.75), 0.05, alpha=0.12)
    box((3.55, -2.6, 1.32), (0.6, 0.4, 0.36), glass)
    for k in range(6):
        box((3.35 + (k % 3) * 0.2, -2.68 + (k // 3) * 0.16, 1.18), (0.1, 0.1, 0.06), mat("sweet_%d" % (k % 3), ((0.95, 0.75, 0.2), (0.9, 0.5, 0.15), (0.95, 0.9, 0.8))[k % 3], 0.6))
    cyl((2.4, -2.9, 0.75), 0.22, 0.7, steel, 24)
    cyl((2.4, -2.9, 1.13), 0.15, 0.06, steel, 24)
    box((2.4, -3.13, 0.55), (0.04, 0.08, 0.04), mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0))
    for x in (-2.6, 0.0, 2.6):
        for yy in (-1.6, 0.6):
            cyl((x + 0.6, yy, 0.86), 0.06, 0.18, steel, 16, r2=0.05)
            if (x, yy) == (0.0, -1.6):                     # Karthik's place: a big leaf, whichever dish he orders
                box((x - 0.2, yy + 0.15, 0.772), (0.52, 0.34, 0.004), mat("banana_leaf", (0.2, 0.5, 0.18), 0.6))
                for kind in FOODS:
                    food(kind, x - 0.2, yy + 0.15, 0.774)
                sketchfab("tea_glass__chai_glass_indian_style", (x + 0.35, yy + 0.15, 0.77), 0.1, drop=("Object_11",))
            elif (x, yy) == (-2.6, 0.6):
                sketchfab("idli_south_indian_food", (x - 0.2, yy - 0.15, 0.77), 0.46, drop=("Material.026",), by="width")
                sketchfab("tea_glass__chai_glass_indian_style", (x + 0.35, yy - 0.15, 0.77), 0.1, drop=("Object_11",))
            else:
                box((x - 0.2, yy - 0.2, 0.77), (0.4, 0.3, 0.004), mat("banana_leaf", (0.2, 0.5, 0.18), 0.6))
    box((-W / 2 + 0.03, -1.0, 1.65), (0.02, 1.6, 0.6), mat("mirror", (0.85, 0.88, 0.9), 0.02, 1.0))
    # the kitchen beyond the hatch: a warm glow, a steaming pot
    box((0.0, D / 2 - 0.012, 1.3), (2.6, 0.01, 1.04), mat("kitchen_glow", (0.4, 0.25, 0.1), 0.8, emit=(1.0, 0.55, 0.25), strength=1.2))
    cyl((-0.6, D / 2 - 0.25, 1.0), 0.2, 0.3, mat("pot_alu", (0.6, 0.6, 0.62), 0.4, 0.6), 20)
    light("lamp", (0.0, D / 2 - 0.4, 1.6), 1)
    switchboard(-3.2, -D / 2 + 0.02, 1.3, "-y")
    cornice(W, D, h, mat("cornice_white", (0.95, 0.95, 0.93), 0.9))
    wall_clock(-W / 2 + 0.02, 1.8, 2.5, "+x")


def police_detail(T):
    W, D, h = 10.0, 8.0, 3.4
    blue = mat("police_blue", (0.08, 0.15, 0.4), 0.4)
    red = mat("police_red", (0.6, 0.08, 0.06), 0.4)
    white = mat("letters_white", (0.97, 0.97, 0.97), 0.4)
    ink = mat("ink_black", (0.05, 0.05, 0.05), 0.4)
    khaki = mat("khaki", (0.6, 0.5, 0.3), 0.8)
    paper = mat("paper_old", (0.9, 0.86, 0.72), 0.85)
    tie = mat("tie_red", (0.7, 0.08, 0.06), 0.8)
    wood = mat("timber", (1, 1, 1), 0.55)
    sign("NAGAR POLICE STATION", (-2.4 + 0.0, D / 2 - 0.04, 2.85), 3.4, 0.42, blue, white, "-y", 0.2)
    text("Tamil Nadu Police  -  Coimbatore City", (-2.4, D / 2 - 0.07, 2.52), 0.08, ink, "-y")
    sign("STATION HOUSE OFFICER", (2.0, 2.0, 0.97), 0.55, 0.09, red, white, "-y", 0.045)
    sign("ENQUIRY", (-1.0, -0.98, 1.3), 0.5, 0.14, blue, white, "-y", 0.08)
    # the area map behind the inspector, leaders' photos, the duty roster
    box((2.0, D / 2 - 0.03, 1.95), (1.4, 0.02, 1.0), mat("area_map", (1, 1, 1), 0.8, tex=T["layout_plan"]))
    text("STATION LIMITS", (2.0, D / 2 - 0.045, 2.55), 0.07, ink, "-y")
    for k in range(3):
        frame(-4.2 + k * 0.5, D / 2 - 0.02, 2.0, 0.32, 0.4, mat("photo_sepia", (1, 1, 1), 0.7, tex=T["photo_sepia"]))
    box((W / 2 - 0.03, -2.0, 1.7), (0.02, 1.0, 0.7), mat("roster", (0.95, 0.95, 0.92), 0.8))
    text("DUTY ROSTER", (W / 2 - 0.045, -2.0, 1.98), 0.06, ink, "-x")
    for r in range(6):
        box((W / 2 - 0.045, -2.0, 1.85 - r * 0.08), (0.004, 0.85, 0.006), ink)
    # case bundles on racks along the front wall, the lathis, caps and the wireless log
    for k, x in enumerate((1.6, 2.6, 3.6)):
        box((x, -D / 2 + 0.25, 0.9), (0.9, 0.4, 0.03), wood)
        box((x, -D / 2 + 0.25, 1.5), (0.9, 0.4, 0.03), wood)
        bundles(x - 0.2, -D / 2 + 0.25, 0.915, 3 + k % 2, paper, tie)
        bundles(x + 0.22, -D / 2 + 0.25, 1.515, 2 + k % 3, paper, tie)
    for k in range(3):
        cyl((-W / 2 + 0.12 + k * 0.05, 3.6, 0.6), 0.015, 1.2, mat("lathi", (0.55, 0.35, 0.15), 0.6), 8, rot=(0.08, 0, 0))
    cyl((2.5, 2.2, 0.85), 0.12, 0.08, khaki, 20, r2=0.13)
    box((2.5, 2.08, 0.82), (0.2, 0.08, 0.02), mat("cap_peak", (0.08, 0.06, 0.04), 0.3))
    box((-3.65, D / 2 - 0.35, 1.0), (0.25, 0.18, 0.02), paper)
    # the lock-up's door and a bench inside
    bars = mat("cell_bars", (0.15, 0.15, 0.17), 0.4, 0.7)
    box((3.5, 0.6, 1.05), (0.06, 0.08, 2.1), bars)
    box((3.8, 0.58, 1.1), (0.08, 0.06, 0.12), mat("padlock", (0.7, 0.6, 0.3), 0.3, 0.9))
    box((4.4, 2.6, 0.4), (1.0, 0.45, 0.06), mat("cement_bench", (0.6, 0.58, 0.55), 0.9))
    box((4.4, 2.6, 0.2), (0.9, 0.4, 0.4), mat("cement_bench", (0.6, 0.58, 0.55), 0.9))
    wall_clock(0.9, D / 2 - 0.02, 2.5)
    switchboard(-2.5, -D / 2 + 0.02, 1.3, "-y")
    skirting(W, D, mat("skirting_red", (0.32, 0.08, 0.05), 0.3), -1.5, 1.6)
    cornice(W, D, h, mat("cornice_white", (0.95, 0.95, 0.93), 0.9))
    door_leaf(-2.3, -D / 2, 0.8, mat("door_teak", (1, 1, 1), 0.5, tex=os.path.join(GTEX, "dark_timber_deck_base.jpg"), scale=1.0), -1)


DETAIL = {"home": home_detail, "dev_office": office_detail, "coopbank": bank_detail, "mess": mess_detail,
          "police": police_detail}


ROOMS = {"home": home, "dev_office": dev_office, "coopbank": coopbank, "mess": mess, "police": police}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M.clear()
    SF.clear()


def export(name):
    """The room as one mesh ("Room"), but each dish (Food_<kind> parts) one object of its own the game can show."""
    groups = {}
    for o in bpy.data.objects:
        if o.type == 'MESH':
            groups.setdefault(o.name.split("_part")[0] if o.name.startswith("Food_") else "Room", []).append(o)
    for gname, obs in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in obs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        if len(obs) > 1:
            bpy.ops.object.join()
        bpy.context.view_layer.objects.active.name = gname
    bpy.ops.object.select_all(action='SELECT')
    path = os.path.join(OUT, "room_%s.glb" % name)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_image_format='JPEG')
    print("ROOM", name, "%.1f MB" % (os.path.getsize(path) / 1e6), flush=True)


def preview(name, out_dir, shots=()):
    """A look inside from the room's wide shot, lit by its lights (Eevee)."""
    sc = bpy.context.scene
    engines = [e.identifier for e in sc.render.bl_rna.properties["engine"].enum_items]
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    sc.render.image_settings.file_format = 'JPEG'
    for e in [o for o in bpy.data.objects if o.name.startswith("Light_")]:
        kind = e.name.split("_")[1]
        ld = bpy.data.lights.new(e.name, 'POINT')
        ld.energy = {"tube": 250, "window": 400, "lamp": 25}.get(kind, 150)
        ld.shadow_soft_size = 0.5
        ld.color = {"tube": (0.95, 0.97, 1.0), "window": (1.0, 0.95, 0.85), "lamp": (1.0, 0.6, 0.25)}.get(kind, (1, 1, 1))
        lo = bpy.data.objects.new(e.name + "_L", ld)
        lo.location = e.location
        sc.collection.objects.link(lo)
    cam_e = next((o for o in bpy.data.objects if o.name.startswith("Cam_wide") or o.name.startswith("Cam_cabin")), None)
    look_e = bpy.data.objects.get(cam_e.name.replace("Cam_", "Look_")) if cam_e else None
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.data.lens = 22
    cam.location = cam_e.location if cam_e else (0, -3, 2)
    tgt = look_e.location if look_e else Vector((0, 0, 1))
    cam.rotation_euler = (Vector(tgt) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    sc.world = w
    os.makedirs(out_dir, exist_ok=True)
    sc.render.filepath = os.path.join(out_dir, "room_%s.jpg" % name)
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", sc.render.filepath, flush=True)
    be = bpy.data.objects.get("Cam_bathroom")                            # (the home: its bathroom too)
    if be is not None:
        cam.location = be.location
        cam.rotation_euler = (bpy.data.objects["Look_bathroom"].location - be.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(out_dir, "room_%s_bathroom.jpg" % name)
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", sc.render.filepath, flush=True)
    for s in shots:                                                      # --shots kitchen,meal: more of the room
        ce, le = bpy.data.objects.get("Cam_" + s), bpy.data.objects.get("Look_" + s)
        if ce is None or le is None:
            continue
        cam.location = ce.location
        cam.rotation_euler = (le.location - ce.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(out_dir, "room_%s_%s.jpg" % (name, s))
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", sc.render.filepath, flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    prev = args[args.index("--preview") + 1] if "--preview" in args else None
    shots = args[args.index("--shots") + 1].split(",") if "--shots" in args else ()
    names = [a for a in args if a in ROOMS] or list(ROOMS)
    for name in names:
        reset()
        T = make_textures()
        ROOMS[name](T)
        DETAIL[name](T)
        if prev:                                          # the preview first: the export joins everything
            import copy  # noqa: F401
            preview(name, os.path.abspath(prev), shots)
            for o in [o for o in bpy.data.objects if o.type == 'LIGHT' or o.name == "Cam"]:
                bpy.data.objects.remove(o, do_unlink=True)
        if "--no-export" not in args:                     # (--no-export: look first, the game keeps its rooms)
            export(name)


if __name__ == "__main__":
    main()
