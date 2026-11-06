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
bananas; each cut down to a few hundred triangles. The rest is painted here.

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


def tmat(name, path, rough=0.8, metal=0.0):
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


BUILD = {"market_vegcart": vegcart, "market_groundstall": groundstall, "market_banana": banana, "market_crates": crates,
         "market_teakadai": teakadai, "bala_workshop": workshop, "bala_workshop_closed": workshop_closed}


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
    for ob, x in zip(obs, (-4.6, -1.2, 1.9, 4.4, 9.0, 16.0)):
        ob.location = (x, 0, 0)
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
                            ("bala_workshop_in", (16.6, -3.0, 1.7), (15.6, 1.5, 1.1))):
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
    obs = [export(fn()) for fn in BUILD.values()]
    if "--preview" in args:
        preview(os.path.abspath(args[args.index("--preview") + 1]), obs)


main()
