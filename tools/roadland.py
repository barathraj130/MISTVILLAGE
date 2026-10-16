"""
Land and roads of real Coimbatore in Blender, built from the city tiles (tools/citygen/chunk.py) at the quality we
want the game to reach — the design reference for the Godot city.

    Blender -b --python tools/roadland.py -- --tiles -1,-1:0,0 --out previews/roadland [--blend art/roadland.blend]
                                             [--nobuildings] [--samples 96]

What is built (all in metres, the game frame turned into Blender's: x east, y north, z up):
  land        the real ground heights (8 m grid) refined to 2 m with a little relief, and a ground shader that mixes
              red soil, dry grass and green patches by large-scale noise, darker in hollows
  roads       every road piece as a ribbon with a 2 % crown, worn asphalt (photo texture + wheel tracks + patches),
              its paint as real geometry: centre dashes, lane dashes, edge lines, double centre lines on big roads,
              stop lines and zebras before the big junctions — the same rules as the game
  junctions   the filleted junction surfaces
  kerbs       a 20 cm kerb with a rounded top on the road side of every footpath, black-and-white on main roads,
              black-and-yellow on medians and separators; the footpath in pavers with a skirt into the ground
  medians     raised kerbed medians on two-way main roads with shrubs; separators between parallel roads
  roadside    paved forecourts and concrete yards, plastered compound walls with coping, streetlights, trees
              (coconut and neem from tools/trees_tn.py), traffic signals
  buildings   the designed buildings placed as in the game (optional)
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "citygen"))
from lib.tiles import read_tile  # noqa: E402

TEX = os.path.join(ROOT, "godot", "assets", "drive", "tex")
TEX_R = os.path.join(ROOT, "godot", "assets", "models", "textures")
CITY = os.path.join(ROOT, "godot", "assets", "city")
BUILD = os.path.join(ROOT, "godot", "assets", "buildings")
LIFT = 0.09                     # road surface above its centreline points (= the game)
CROWN = 0.05                    # crown height at the centre of a 7 m road
MARK = {"motorway": 3, "trunk": 3, "primary": 2, "secondary": 2, "tertiary": 1, "unclassified": 1, "residential": 1}
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))     # game (x, y up, z south) → Blender


# ----------------------------------------------------------------------------- materials
_mats = {}


def _img(path, colour=True):
    im = bpy.data.images.load(path, check_existing=True)
    if not colour:
        im.colorspace_settings.name = "Non-Color"
    return im


def tex_mat(name, base, tile, rough=0.85, tint=None, uv=False, bump=0.6):
    """Photo-textured material: UV (roads, footpaths) or world box projection (everything else)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    co = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1 / tile, 1 / tile, 1 / tile)
    nt.links.new(co.outputs["UV" if uv else "Object"], mp.inputs["Vector"])

    def tex(suffix, colour):
        path = os.path.join(TEX, base + suffix) if os.path.exists(os.path.join(TEX, base + suffix)) else None
        if path is None:
            return None
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = _img(path, colour)
        if not uv:
            t.projection = 'BOX'
            t.projection_blend = 0.3
        nt.links.new(mp.outputs[0], t.inputs["Vector"])
        return t
    c = tex("_color.jpg", True)
    if c:
        out = c.outputs["Color"]
        if tint:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(out, mix.inputs[6])
            mix.inputs[7].default_value = (*tint, 1)
            out = mix.outputs[2]
        nt.links.new(out, p.inputs["Base Color"])
    n = tex("_normal.jpg", False)
    if n:
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = bump
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    r = tex("_rough.jpg", False)
    if r:
        nt.links.new(r.outputs["Color"], p.inputs["Roughness"])
    else:
        p.inputs["Roughness"].default_value = rough
    return m


def plain(name, colour, rough=0.6, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*colour, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit:
        for nm in ("Emission Color", "Emission"):
            if nm in p.inputs:
                p.inputs[nm].default_value = (*emit, 1)
        p.inputs["Emission Strength"].default_value = strength
    return m


def asphalt_mat():
    """Worn city asphalt: the photo texture at 4 m, darker polished wheel tracks in each lane (from the UV: u is
    metres across from the left edge), large patchy colour variation and dust at the edges."""
    m = tex_mat("Asphalt", "asphalt", 4.0, uv=True, tint=(0.11, 0.11, 0.12), bump=0.6)
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    base = p.inputs["Base Color"].links[0].from_socket
    co = nt.nodes.new("ShaderNodeTexCoord")
    # large-scale variation (resurfaced stretches, sun-bleached areas)
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 0.02
    nz.inputs["Detail"].default_value = 3.0
    nt.links.new(co.outputs["Object"], nz.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeMapRange")
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Value"])
    ramp.inputs["To Min"].default_value = 0.82
    ramp.inputs["To Max"].default_value = 1.12
    # wheel tracks: u in metres across; tracks 0.8 m either side of each 3.5 m lane centre
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(co.outputs["UV"], sep.inputs[0])
    lane = nt.nodes.new("ShaderNodeMath")
    lane.operation = "PINGPONG"
    nt.links.new(sep.outputs["X"], lane.inputs[0])
    lane.inputs[1].default_value = 1.75
    trk = nt.nodes.new("ShaderNodeMapRange")
    nt.links.new(lane.outputs[0], trk.inputs["Value"])
    trk.inputs["From Min"].default_value = 0.7
    trk.inputs["From Max"].default_value = 1.15
    trk.inputs["To Min"].default_value = 1.0
    trk.inputs["To Max"].default_value = 0.86
    trk.clamp = True
    trk2 = nt.nodes.new("ShaderNodeMath")
    trk2.operation = "MAXIMUM"
    nt.links.new(trk.outputs[0], trk2.inputs[0])
    big = nt.nodes.new("ShaderNodeMath")
    big.operation = "GREATER_THAN"
    nt.links.new(lane.outputs[0], big.inputs[0])
    big.inputs[1].default_value = 1.15
    nt.links.new(big.outputs[0], trk2.inputs[1])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(ramp.outputs[0], mul.inputs[0])
    nt.links.new(trk2.outputs[0], mul.inputs[1])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(base, mix.inputs[6])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    for k in ("X", "Y", "Z"):
        nt.links.new(mul.outputs[0], comb.inputs[k])
    nt.links.new(comb.outputs[0], mix.inputs[7])
    nt.links.new(mix.outputs[2], p.inputs["Base Color"])
    # no sheen: asphalt is rough and barely reflects; drop the roughness map link if any
    for lk in list(p.inputs["Roughness"].links):
        nt.links.remove(lk)
    p.inputs["Roughness"].default_value = 0.88
    if "Specular IOR Level" in p.inputs:
        p.inputs["Specular IOR Level"].default_value = 0.3
    return m


def ground_mat():
    """Open ground: red soil, dry grass and green grass in large patches."""
    m = bpy.data.materials.new("Ground")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    co = nt.nodes.new("ShaderNodeTexCoord")
    layers = []
    for name, tile in (("dry_grass", 5.0), ("grass", 4.0), ("red_soil", 4.0)):
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (1 / tile,) * 3
        nt.links.new(co.outputs["Object"], mp.inputs["Vector"])
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = _img(os.path.join(TEX, name + "_color.jpg"))
        t.projection = 'BOX'
        t.projection_blend = 0.3
        nt.links.new(mp.outputs[0], t.inputs["Vector"])
        layers.append(t)
    def noise(scale, seed_off):
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.noise_dimensions = '4D'
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = 4.0
        n.inputs["W"].default_value = seed_off
        nt.links.new(co.outputs["Object"], n.inputs["Vector"])
        r = nt.nodes.new("ShaderNodeMapRange")
        nt.links.new(n.outputs["Fac"], r.inputs["Value"])
        r.inputs["From Min"].default_value = 0.5
        r.inputs["From Max"].default_value = 0.62
        return r.outputs[0]
    m1 = nt.nodes.new("ShaderNodeMix")
    m1.data_type = "RGBA"
    nt.links.new(noise(0.025, 1.0), m1.inputs["Factor"])
    nt.links.new(layers[0].outputs["Color"], m1.inputs[6])
    nt.links.new(layers[1].outputs["Color"], m1.inputs[7])
    m2 = nt.nodes.new("ShaderNodeMix")
    m2.data_type = "RGBA"
    nt.links.new(noise(0.04, 7.0), m2.inputs["Factor"])
    nt.links.new(m1.outputs[2], m2.inputs[6])
    nt.links.new(layers[2].outputs["Color"], m2.inputs[7])
    nt.links.new(m2.outputs[2], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.95
    bm = nt.nodes.new("ShaderNodeBump")
    bn = nt.nodes.new("ShaderNodeTexNoise")
    bn.inputs["Scale"].default_value = 3.0
    nt.links.new(co.outputs["Object"], bn.inputs["Vector"])
    nt.links.new(bn.outputs["Fac"], bm.inputs["Height"])
    bm.inputs["Strength"].default_value = 0.25
    nt.links.new(bm.outputs["Normal"], p.inputs["Normal"])
    return m


def materials():
    if _mats:
        return _mats
    paver = bpy.data.materials.new("Pavers")
    paver.use_nodes = True
    nt = paver.node_tree
    pp = nt.nodes["Principled BSDF"]
    co = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (0.5, 0.5, 0.5)
    nt.links.new(co.outputs["UV"], mp.inputs["Vector"])
    for f, inp, colour in (("parking_pavers_base.jpg", "Base Color", True), ("parking_pavers_rough.jpg", "Roughness", False)):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = _img(os.path.join(TEX_R, f), colour)
        nt.links.new(mp.outputs[0], t.inputs["Vector"])
        nt.links.new(t.outputs["Color"], pp.inputs[inp])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = _img(os.path.join(TEX_R, "parking_pavers_normal.png"), False)
    nt.links.new(mp.outputs[0], tn.inputs["Vector"])
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], pp.inputs["Normal"])
    _mats.update({
        "asphalt": asphalt_mat(),
        "ground": ground_mat(),
        "pavers": paver,
        "concrete": tex_mat("Concrete", "concrete", 3.0, tint=(0.85, 0.83, 0.8)),
        "kerb": tex_mat("Kerb", "concrete", 1.5, tint=(0.75, 0.74, 0.72)),
        "paint": plain("Road Paint", (0.82, 0.82, 0.78), 0.55),
        "paint_y": plain("Yellow Paint", (0.85, 0.62, 0.05), 0.55),
        "black": plain("Kerb Black", (0.03, 0.03, 0.03), 0.6),
        "kerb_w": plain("Kerb White", (0.8, 0.8, 0.77), 0.6),
        "soil": tex_mat("Median Soil", "red_soil", 2.0),
        "plaster": tex_mat("Wall Plaster", "plaster", 2.0),
        "coping": plain("Coping", (0.55, 0.54, 0.52), 0.8),
        "steel": plain("Galvanised", (0.5, 0.51, 0.52), 0.4, 0.8),
        "lamp": plain("Lamp", (0.95, 0.92, 0.85), 0.3, emit=(1.0, 0.92, 0.78), strength=1.0),
        "shrub": plain("Shrub", (0.05, 0.14, 0.03), 0.8),
        "sig_red": plain("Signal Red", (0.6, 0.02, 0.01), 0.3, emit=(1, 0.05, 0.02), strength=4),
        "sig_body": plain("Signal Body", (0.02, 0.02, 0.02), 0.5),
        "sig_yellow": plain("Signal Yellow", (0.8, 0.6, 0.03), 0.5),
        "wire": plain("Wire", (0.01, 0.01, 0.01), 0.5),
        "gravel": tex_mat("Gravel", "gravel", 1.5, tint=(0.8, 0.65, 0.55)),
        "drain_water": plain("Drain Water", (0.03, 0.035, 0.025), 0.15),
        "drain_wall": tex_mat("Drain Wall", "concrete", 1.0, tint=(0.55, 0.53, 0.5)),
    })
    import streetlife as SL
    _mats["dust"] = SL.decal_mat("Kerb Dust", (0.42, 0.24, 0.13), 0.95, 0.9, 0.38, 0.85)
    _mats["oil"] = SL.decal_mat("Oil Stain", (0.015, 0.015, 0.015), 0.35, 1.6, 0.48, 0.55)
    _mats["patch"] = SL.decal_mat("Patch Repair", (0.035, 0.035, 0.038), 0.9, 0.4, 0.2, 0.9)
    _mats["crack"] = plain("Crack", (0.01, 0.01, 0.01), 0.9)
    return _mats


# ----------------------------------------------------------------------------- mesh helpers (game frame)
class Builder:
    """Collects quads/triangles in the game frame with UVs, per material; one object per material at the end."""

    def __init__(self, name):
        self.name = name
        self.parts = {}

    def _p(self, mat):
        if mat not in self.parts:
            self.parts[mat] = ([], [], [])          # verts, faces, uvs (per face corner)
        return self.parts[mat]

    def quad(self, mat, a, b, c, d, uv=((0, 0), (1, 0), (1, 1), (0, 1))):
        vs, fs, uvs = self._p(mat)
        i = len(vs)
        vs.extend([a, b, c, d])
        fs.append((i, i + 1, i + 2, i + 3))
        uvs.extend(uv)

    def tri(self, mat, a, b, c, uv=((0, 0), (1, 0), (0, 1))):
        vs, fs, uvs = self._p(mat)
        i = len(vs)
        vs.extend([a, b, c])
        fs.append((i, i + 1, i + 2))
        uvs.extend(uv)

    def finish(self, parent):
        objs = []
        for mat, (vs, fs, uvs) in self.parts.items():
            if not fs:
                continue
            me = bpy.data.meshes.new(self.name + "_" + mat)
            me.from_pydata([tuple(v) for v in vs], [], fs)
            uvl = me.uv_layers.new()
            k = 0
            for poly in me.polygons:
                for li in poly.loop_indices:
                    uvl.data[li].uv = uvs[k]
                    k += 1
            me.validate()
            for poly in me.polygons:
                poly.use_smooth = True
            ob = bpy.data.objects.new(self.name + "_" + mat, me)
            bpy.context.scene.collection.objects.link(ob)
            ob.data.materials.append(materials()[mat])
            ob.parent = parent
            objs.append(ob)
        return objs


def V(x, y, z):
    return Vector((float(x), float(y), float(z)))


def flat(v):
    return Vector((v.x, 0.0, v.z))


def left_of(d):
    """the driver's left of a direction in the game frame (x east, z south)"""
    return Vector((d.z, 0.0, -d.x)).normalized()


# ----------------------------------------------------------------------------- the scene parts
def land(tiles, b, refine=4):
    """Ground from each tile's height grid, refined with bilinear interpolation plus a little relief."""
    rng = np.random.default_rng(3)
    for t in tiles:
        H, hn = t["H"], t["hn"]
        n = (hn - 1) * refine + 1
        step = 8.0 / refine
        x0, z0 = t["cx"] * 256.0, t["cz"] * 256.0
        gi = np.linspace(0, hn - 1, n)
        I, J = np.meshgrid(gi, gi, indexing="ij")
        i0 = np.clip(I.astype(int), 0, hn - 2)
        j0 = np.clip(J.astype(int), 0, hn - 2)
        fi, fj = I - i0, J - j0
        Y = (H[i0, j0] * (1 - fi) * (1 - fj) + H[i0 + 1, j0] * fi * (1 - fj) + H[i0, j0 + 1] * (1 - fi) * fj
             + H[i0 + 1, j0 + 1] * fi * fj)
        Y = Y + rng.normal(0, 0.04, Y.shape)
        for i in range(n - 1):
            for j in range(n - 1):
                a = V(x0 + j * step, Y[i, j], z0 + i * step)
                bb = V(x0 + (j + 1) * step, Y[i, j + 1], z0 + i * step)
                c = V(x0 + (j + 1) * step, Y[i + 1, j + 1], z0 + (i + 1) * step)
                d = V(x0 + j * step, Y[i + 1, j], z0 + (i + 1) * step)
                b.quad("ground", a, d, c, bb)


def has_median(r, classes):
    cls = classes[r["cid"]]
    return not (r["fl"] & 1) and (cls in ("trunk", "motorway", "primary") or r["w"] >= 11.0)


def mark_under(tiles, classes):
    """A road piece mostly inside a wider carriageway (each direction mapped separately, slip lanes, service lanes
    mapped inside the main road) leaves the painting to the wider road, as in the game."""
    allr = [r for t in tiles for r in t["roads"] if len(r["p"]) >= 2 and classes[r["cid"]] not in ("footway", "track")]
    segs = []
    for j, o in enumerate(allr):
        q = o["p"][:, [0, 2]]
        segs.append((j, q[:-1], q[1:], o["w"]))
    for i, r in enumerate(allr):
        pts = r["p"][:, [0, 2]]
        inside = 0
        for k in range(len(pts)):
            for j, a, bq, w in segs:
                if j == i or w < r["w"] or (w == r["w"] and j > i):
                    continue
                ab = bq - a
                t = np.clip(((pts[k] - a) * ab).sum(1) / np.maximum((ab * ab).sum(1), 1e-9), 0, 1)
                d = np.hypot(*(a + ab * t[:, None] - pts[k]).T).min()
                if d < w * 0.5 - 0.3:
                    inside += 1
                    break
        r["under"] = inside >= math.ceil(len(pts) * 0.4)


def roads(tiles, classes, b):
    """Road ribbons with a crown, and their paint as geometry."""
    mark_under(tiles, classes)
    for t in tiles:
        for r in t["roads"]:
            cls = classes[r["cid"]]
            p = r["p"]
            if len(p) < 2 or cls in ("footway", "track"):
                continue
            pts = [V(q[0], q[1] + LIFT, q[2]) for q in p]
            half = r["w"] * 0.5
            n = len(pts)
            lefts = []
            for i in range(n):
                d = flat(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)])
                lefts.append(left_of(d) if d.length > 1e-4 else Vector((1, 0, 0)))
            along = [r["a0"]]
            for i in range(1, n):
                along.append(along[-1] + (pts[i] - pts[i - 1]).length)
            crown = CROWN * min(1.0, half / 3.5)
            # five strips across: edge, quarter, centre (crowned), quarter, edge
            offs = [-half, -half * 0.5, 0.0, half * 0.5, half]
            hs = [0.0, crown * 0.75, crown, crown * 0.75, 0.0]
            for i in range(n - 1):
                for k in range(4):
                    a = pts[i] + lefts[i] * offs[k] + Vector((0, hs[k], 0))
                    bb = pts[i] + lefts[i] * offs[k + 1] + Vector((0, hs[k + 1], 0))
                    c = pts[i + 1] + lefts[i + 1] * offs[k + 1] + Vector((0, hs[k + 1], 0))
                    d = pts[i + 1] + lefts[i + 1] * offs[k] + Vector((0, hs[k], 0))
                    u0, u1 = (offs[k] + half), (offs[k + 1] + half)
                    b.quad("asphalt", a, d, c, bb, uv=((u0, along[i]), (u0, along[i + 1]), (u1, along[i + 1]), (u1, along[i])))
            paint(r, cls, pts, lefts, along, half, crown, b, has_median(r, classes))


def _stripe(b, mat, pts, lefts, along, off, width, crown_at, a_from, a_to, lift=0.012):
    """A painted line `width` wide at lateral offset `off`, from along a_from to a_to."""
    n = len(pts)
    for i in range(n - 1):
        s0, s1 = max(along[i], a_from), min(along[i + 1], a_to)
        if s1 <= s0:
            continue
        f0 = (s0 - along[i]) / max(along[i + 1] - along[i], 1e-6)
        f1 = (s1 - along[i]) / max(along[i + 1] - along[i], 1e-6)
        c0 = pts[i].lerp(pts[i + 1], f0)
        c1 = pts[i].lerp(pts[i + 1], f1)
        l0 = lefts[i].lerp(lefts[i + 1], f0).normalized()
        l1 = lefts[i].lerp(lefts[i + 1], f1).normalized()
        up = Vector((0, crown_at + lift, 0))
        a = c0 + l0 * (off - width / 2) + up
        bb = c0 + l0 * (off + width / 2) + up
        c = c1 + l1 * (off + width / 2) + up
        d = c1 + l1 * (off - width / 2) + up
        b.quad(mat, a, d, c, bb)


def paint(r, cls, pts, lefts, along, half, crown, b, median):
    if r.get("under"):
        return
    code = MARK.get(cls, 0)
    if code > 0 and half >= 6.0:
        code = 3
    if code == 0:
        return
    oneway = bool(r["fl"] & 1)
    L = r["len"]
    c0 = r["c0"] + 4.3 if r["c0"] > 0 else 9.0
    c1 = r["c1"] + 4.3 if r["c1"] > 0 else 9.0
    a_start, a_end = max(along[0], c0), min(along[-1], L - c1)

    def dashes(off, w):
        a = math.ceil(a_start / 7.5) * 7.5
        while a < a_end:
            _stripe(b, "paint", pts, lefts, along, off, w, crown * (1 - abs(off) / max(half, 0.1)), a, min(a + 3.0, a_end))
            a += 7.5

    def solid(off, w, mat="paint"):
        _stripe(b, mat, pts, lefts, along, off, w, crown * (1 - abs(off) / max(half, 0.1)), a_start, a_end)
    if median:
        for s in (1, -1):
            solid(s * 0.85, 0.12)
    elif code in (1, 2) and not oneway:
        dashes(0.0, 0.12)
    elif code == 3 and not oneway:
        solid(0.13, 0.1)
        solid(-0.13, 0.1)
    if code == 3:
        for s in (1, -1):
            dashes(s * 3.5, 0.12)
    if oneway and half > 3.6:
        dashes(0.0, 0.12)
    if code >= 2:
        for s in (1, -1):
            solid(s * (half - 0.4), 0.15)
    # stop line and zebra just outside a big junction
    for c, at_start in ((r["c0"], True), (r["c1"], False)):
        if c < 8.0 or code < 2 or L < 30:
            continue
        base = c if at_start else L - c
        sgn = 1 if at_start else -1
        zs, ze = sorted((base + sgn * 0.6, base + sgn * 3.6))
        if ze < along[0] or zs > along[-1]:
            continue
        o = -half + 0.6
        while o < half - 0.6:
            _stripe(b, "paint", pts, lefts, along, o + 0.25, 0.5, crown * 0.5, max(zs, along[0]), min(ze, along[-1]))
            o += 1.1
        sl = base + sgn * 4.2
        if along[0] < sl < along[-1]:
            _stripe(b, "paint", pts, lefts, along, 0.0, 2 * half - 1.0, crown * 0.5, sl - 0.15, sl + 0.15)


def junctions(tiles, b):
    for t in tiles:
        for v in t["junc"]:
            for i in range(0, len(v) - 2, 3):
                a, bb, c = (V(*v[i]), V(*v[i + 1]), V(*v[i + 2]))
                if (bb - a).cross(c - a).y < 0:
                    bb, c = c, bb
                b.tri("asphalt", a, c, bb, uv=((a.x, a.z), (c.x, c.z), (bb.x, bb.z)))


def footpaths(tiles, b, lamps):
    """Paver footpaths with a skirt, a rounded-top kerb on the road side; separators/medians planted."""
    rng = random.Random(5)
    for t in tiles:
        for wk in t["walks"]:
            p = wk["p"]
            if len(p) < 2:
                continue
            pts = [V(*q) for q in p]
            n = len(pts)
            hw = wk["w"] * 0.5
            road_right = bool(wk["fl"] & 4)
            sep = bool(wk["fl"] & 8)
            main = bool(wk["fl"] & 1)
            typ = wk.get("type", "arterial")
            if typ in ("colony", "oldtown", "industrial", "periurban"):
                street_edge(b, pts, n, hw, road_right, typ)
                continue
            rws = []
            for i in range(n):
                d = flat(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
                rw = Vector((d.z, 0, -d.x)) if road_right else Vector((-d.z, 0, d.x))
                rws.append(rw)
            along = 0.0
            next_lamp = 16.0
            for i in range(n - 1):
                a, c = pts[i], pts[i + 1]
                seg = (c - a).length
                ai, ci = a + rws[i] * hw, c + rws[i + 1] * hw
                ao, co_ = a - rws[i] * hw, c - rws[i + 1] * hw
                top_mat = "soil" if sep else "pavers"
                b.quad(top_mat, ai, ci, co_, ao, uv=((hw, along), (hw, along + seg), (-hw, along + seg), (-hw, along)))
                dn = Vector((0, -0.6, 0))
                b.quad("kerb", ao, co_, co_ + dn, ao + dn)
                # kerb: 0.2 m, a little higher than the path, a rounded nose to the road
                kmat = "kerb"
                if main or sep:
                    stripe = int(along / (1.0 if sep else 1.2)) % 2
                    kmat = ("black" if stripe == 0 else ("paint_y" if sep else "kerb_w"))
                up = Vector((0, 0.02, 0))
                k0, k1 = ai + rws[i] * 0.12 + up, ci + rws[i + 1] * 0.12 + up
                b.quad(kmat, ai + up, ci + up, k1, k0)
                n0, n1 = ai + rws[i] * 0.2 - Vector((0, 0.04, 0)), ci + rws[i + 1] * 0.2 - Vector((0, 0.04, 0))
                b.quad(kmat, k0, k1, n1, n0)
                b.quad(kmat, n0, n1, n1 - Vector((0, 0.35, 0)), n0 - Vector((0, 0.35, 0)))
                if sep and int(along / 3.0) != int((along + seg) / 3.0):
                    shrub(b, (a + c) * 0.5, rng)
                if (wk["fl"] & 2) and not sep:
                    while next_lamp <= along + seg:
                        q = a.lerp(c, (next_lamp - along) / max(seg, 1e-6)) + rws[i] * (hw - 0.35)
                        lamps.append((q, rws[i]))
                        next_lamp += 32.0
                along += seg


def street_edge(b, pts, n, hw, road_right, typ):
    """Streets without a footpath (docs/COIMBATORE_STREETS.md): colony — a 0.5 m concrete edge strip at road level
    (the slab drain follows, placed by streetlife); old town — an open drain channel right at the road edge;
    industrial / outskirts — a gravel and red-soil shoulder."""
    rws = []
    for i in range(n):
        d = flat(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        rws.append(Vector((d.z, 0, -d.x)) if road_right else Vector((-d.z, 0, d.x)))
    along = 0.0
    for i in range(n - 1):
        a, c = pts[i], pts[i + 1]
        seg = (c - a).length
        dn = Vector((0, -0.15, 0))                       # the strip data sits on footpath height; streets are flush
        e0, e1 = a + rws[i] * (hw + 0.2) + dn, c + rws[i + 1] * (hw + 0.2) + dn      # road edge
        if typ == "colony":
            w = 0.5
            b.quad("concrete", e0, e1, e1 - rws[i + 1] * w, e0 - rws[i] * w, uv=((0, along), (0, along + seg), (w, along + seg), (w, along)))
        elif typ == "oldtown":
            w, depth = 0.45, 0.35
            low = Vector((0, -depth, 0))
            o0, o1 = e0 - rws[i] * w, e1 - rws[i + 1] * w
            b.quad("drain_water", e0 + low, e1 + low, o1 + low, o0 + low)
            b.quad("drain_wall", e0, e1, e1 + low, e0 + low)
            b.quad("drain_wall", o1, o0, o0 + low, o1 + low)
            # slab bridges to the doors every ~5 m
            if int(along / 5.0) != int((along + seg) / 5.0):
                mid = a.lerp(c, 0.5)
                rwm = (rws[i] + rws[i + 1]).normalized()
                dd = flat(c - a).normalized()
                q0 = mid + rwm * (hw + 0.2) + dn + Vector((0, 0.02, 0))
                b.quad("concrete", q0 - dd * 0.5, q0 + dd * 0.5, q0 + dd * 0.5 - rwm * (w + 0.1), q0 - dd * 0.5 - rwm * (w + 0.1))
        else:
            w = 1.6 if typ == "industrial" else 1.2
            b.quad("gravel", e0, e1, e1 - rws[i + 1] * w + Vector((0, -0.03, 0)), e0 - rws[i] * w + Vector((0, -0.03, 0)),
                   uv=((0, along), (0, along + seg), (w, along + seg), (w, along)))
        along += seg


SHRUBS = []


def shrub(b, at, rng):
    SHRUBS.append((at, rng.uniform(0.3, 0.45)))


def yards(tiles, b, trees):
    for t in tiles:
        for kind, v in t["yards"]:
            if kind in (1, 2, 6):
                mat = "concrete" if kind == 2 else "pavers"
                for i in range(0, len(v) - 2, 3):
                    a, bb, c = V(*v[i]), V(*v[i + 1]), V(*v[i + 2])
                    if (bb - a).cross(c - a).y < 0:
                        bb, c = c, bb
                    b.tri(mat, a, c, bb, uv=((a.x, a.z), (c.x, c.z), (bb.x, bb.z)))
            elif kind > 100:
                for i in range(len(v) - 1):
                    a, c = V(*v[i]), V(*v[i + 1])
                    b.quad("kerb", a, c, c + Vector((0, -0.6, 0)), a + Vector((0, -0.6, 0)))
                    b.quad("kerb", c, a, a + Vector((0, -0.6, 0)), c + Vector((0, -0.6, 0)))
            elif kind in (3, 5):
                h = 1.5 if kind == 3 else 2.4
                for i in range(len(v) - 1):
                    a, c = V(*v[i]), V(*v[i + 1])
                    d = flat(c - a)
                    if d.length < 0.05:
                        continue
                    s = Vector((d.z, 0, -d.x)).normalized() * 0.12
                    lo, hi = Vector((0, -0.4, 0)), Vector((0, h, 0))
                    for side in (s, -s):
                        b.quad("plaster", a + side + lo, c + side + lo, c + side + hi, a + side + hi)
                    cs, ch = s * 1.6, Vector((0, h + 0.07, 0))
                    b.quad("coping", a + cs + ch, c + cs + ch, c - cs + ch, a - cs + ch)
            elif kind == 4:
                trees.append(V(*v[0]))


# ----------------------------------------------------------------------------- objects placed whole
def instance_of(coll, matrix):
    e = bpy.data.objects.new("Inst_" + coll.name, None)
    e.instance_type = 'COLLECTION'
    e.instance_collection = coll
    e.matrix_world = matrix
    bpy.context.scene.collection.objects.link(e)
    return e


def lamp_collection():
    coll = bpy.data.collections.new("Streetlight")
    M = materials()
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.08, depth=8.0, location=(0, 0, 4.0))
    pole = bpy.context.active_object
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.9, 7.9))
    arm = bpy.context.active_object
    arm.scale = (0.08, 1.8, 0.08)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -1.75, 7.82))
    head = bpy.context.active_object
    head.scale = (0.32, 0.65, 0.12)
    for o, m in ((pole, "steel"), (arm, "steel"), (head, "lamp")):
        o.data.materials.append(M[m])
        bpy.context.scene.collection.objects.unlink(o)
        coll.objects.link(o)
    return coll


def tree_collections():
    import trees_tn
    out = []
    for kind, seed in (("palm", 1), ("palm", 2), ("neem", 3)):
        coll = bpy.data.collections.new("Tree_%s_%d" % (kind, seed))
        before = set(bpy.data.objects)
        trees_tn.build(kind, seed)
        for o in set(bpy.data.objects) - before:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            coll.objects.link(o)
        out.append(coll)
    return out


def building_collections(index):
    """Import each designed building variant once into its own collection."""
    out = {}
    for vi, name in enumerate(index["variants"]):
        path = os.path.join(BUILD, name + ".glb")
        if not os.path.exists(path):
            continue
        coll = bpy.data.collections.new("Bld_" + name)
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        for o in set(bpy.data.objects) - before:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            coll.objects.link(o)
        out[vi] = coll
    return out


KIT_TEX = {1: ("R", "dark_nilgiri_stone_base.jpg", 2.5), 2: ("R", "stone_retaining_wall_base.jpg", 2.5),
           3: ("R", "weathered_stone_coping_base.jpg", 1.5), 4: ("R", "warm_mineral_plaster_base.jpg", 3.0),
           5: ("D", "plaster_color.jpg", 2.5), 6: ("R", "warm_natural_timber_base.jpg", 1.2),
           7: ("R", "dark_timber_deck_base.jpg", 1.2), 8: ("R", "charcoal_standing_seam_roof_base.jpg", 2.0),
           9: ("D", "tin_roof_color.jpg", 2.0), 10: ("D", "concrete_color.jpg", 3.0), 11: ("R", "natural_stone_paving_base.jpg", 2.5),
           12: ("R", "parking_pavers_base.jpg", 2.0), 13: ("R", "flagstone_path_base.jpg", 2.0)}


def kit_material():
    """The designed buildings' look, as in the game's building_kit shader: the vertex colour carries RGB = tint and
    A = layer / 255; each layer is a texture (box-projected in metres), 0 = plain colour, 14 = metal, 100 a lit room,
    101 a lamp. Painted walls and concrete get the rain streaks, the darker foot and faded patches."""
    m = bpy.data.materials.new("KitTextured")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    vc = nt.nodes.new("ShaderNodeVertexColor")
    va = nt.nodes.new("ShaderNodeAttribute")
    va.attribute_name = "Col"
    va.attribute_type = 'GEOMETRY'
    layer = nt.nodes.new("ShaderNodeMath")
    layer.operation = "MULTIPLY"
    nt.links.new(vc.outputs["Alpha"], layer.inputs[0])
    layer.inputs[1].default_value = 255.0
    lr = nt.nodes.new("ShaderNodeMath")
    lr.operation = "ROUND"
    nt.links.new(layer.outputs[0], lr.inputs[0])
    co = nt.nodes.new("ShaderNodeTexCoord")
    colour = vc.outputs["Color"]                                  # layer 0: plain tint
    for li, (src, fn, tile) in KIT_TEX.items():
        path = os.path.join(TEX_R if src == "R" else TEX, fn)
        if not os.path.exists(path):
            continue
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (1 / tile,) * 3
        nt.links.new(co.outputs["Object"], mp.inputs["Vector"])
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = _img(path)
        t.projection = 'BOX'
        t.projection_blend = 0.25
        nt.links.new(mp.outputs[0], t.inputs["Vector"])
        tint = nt.nodes.new("ShaderNodeMix")
        tint.data_type = "RGBA"
        tint.blend_type = "MULTIPLY"
        tint.inputs["Factor"].default_value = 1.0
        nt.links.new(t.outputs["Color"], tint.inputs[6])
        nt.links.new(vc.outputs["Color"], tint.inputs[7])
        eq = nt.nodes.new("ShaderNodeMath")
        eq.operation = "COMPARE"
        nt.links.new(lr.outputs[0], eq.inputs[0])
        eq.inputs[1].default_value = li
        eq.inputs[2].default_value = 0.25
        sel = nt.nodes.new("ShaderNodeMix")
        sel.data_type = "RGBA"
        nt.links.new(eq.outputs[0], sel.inputs["Factor"])
        nt.links.new(colour, sel.inputs[6])
        nt.links.new(tint.outputs[2], sel.inputs[7])
        colour = sel.outputs[2]
    # weathering: vertical streaks, a darker foot (object z = height in the building), faded patches
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(co.outputs["Object"], sep.inputs[0])
    mp2 = nt.nodes.new("ShaderNodeMapping")
    mp2.inputs["Scale"].default_value = (7.0, 7.0, 0.35)
    nt.links.new(co.outputs["Object"], mp2.inputs["Vector"])
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 1.0
    nz.inputs["Detail"].default_value = 5.0
    nt.links.new(mp2.outputs[0], nz.inputs["Vector"])
    streak = nt.nodes.new("ShaderNodeMapRange")
    nt.links.new(nz.outputs["Fac"], streak.inputs["Value"])
    streak.inputs["From Min"].default_value = 0.5
    streak.inputs["From Max"].default_value = 0.8
    streak.inputs["To Min"].default_value = 1.0
    streak.inputs["To Max"].default_value = 0.78
    foot = nt.nodes.new("ShaderNodeMapRange")
    nt.links.new(sep.outputs["Z"], foot.inputs["Value"])
    foot.inputs["From Min"].default_value = 0.0
    foot.inputs["From Max"].default_value = 1.1
    foot.inputs["To Min"].default_value = 0.65
    foot.inputs["To Max"].default_value = 1.0
    w = nt.nodes.new("ShaderNodeMath")
    w.operation = "MULTIPLY"
    nt.links.new(streak.outputs[0], w.inputs[0])
    nt.links.new(foot.outputs[0], w.inputs[1])
    painted = nt.nodes.new("ShaderNodeMath")                     # only plaster (4, 5) and concrete (10)
    painted.operation = "COMPARE"
    nt.links.new(lr.outputs[0], painted.inputs[0])
    painted.inputs[1].default_value = 7.0
    painted.inputs[2].default_value = 3.1
    wsel = nt.nodes.new("ShaderNodeMix")
    wsel.data_type = "FLOAT"
    nt.links.new(painted.outputs[0], wsel.inputs["Factor"])
    wsel.inputs[2].default_value = 1.0
    nt.links.new(w.outputs[0], wsel.inputs[3])
    weath = nt.nodes.new("ShaderNodeMix")
    weath.data_type = "RGBA"
    weath.blend_type = "MULTIPLY"
    weath.inputs["Factor"].default_value = 1.0
    nt.links.new(colour, weath.inputs[6])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    for k in ("X", "Y", "Z"):
        nt.links.new(wsel.outputs[0], comb.inputs[k])
    nt.links.new(comb.outputs[0], weath.inputs[7])
    nt.links.new(weath.outputs[2], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.82
    # lit rooms and lamps glow softly by day
    glow = nt.nodes.new("ShaderNodeMath")
    glow.operation = "GREATER_THAN"
    nt.links.new(lr.outputs[0], glow.inputs[0])
    glow.inputs[1].default_value = 99.5
    for nm in ("Emission Color", "Emission"):
        if nm in p.inputs:
            nt.links.new(vc.outputs["Color"], p.inputs[nm])
    em = nt.nodes.new("ShaderNodeMath")
    em.operation = "MULTIPLY"
    nt.links.new(glow.outputs[0], em.inputs[0])
    em.inputs[1].default_value = 0.6
    nt.links.new(em.outputs[0], p.inputs["Emission Strength"])
    return m


def kit_materials():
    """Swap the imported Kit material for the textured one, and give the glass a dark reflective look."""
    tex = kit_material()
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        for slot in ob.material_slots:
            if slot.material and slot.material.name.startswith("KitGlass"):
                g = slot.material
                g.use_nodes = True
                p = g.node_tree.nodes.get("Principled BSDF")
                if p:
                    p.inputs["Base Color"].default_value = (0.04, 0.06, 0.07, 1)
                    p.inputs["Roughness"].default_value = 0.05
                    p.inputs["Metallic"].default_value = 0.5
            elif slot.material and slot.material.name.startswith("Kit"):
                slot.material = tex


# ----------------------------------------------------------------------------- scene, cameras
def setup_render(samples):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = 'GPU'
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
    sc.view_settings.view_transform = 'AgX'
    try:
        sc.view_settings.look = 'AgX - Medium High Contrast'
    except TypeError:
        pass
    sc.view_settings.exposure = -0.85
    sc.render.image_settings.file_format = 'JPEG'
    sc.render.image_settings.quality = 92
    sc.world = bpy.data.worlds.new("Sky")
    sc.world.use_nodes = True
    sky = sc.world.node_tree.nodes.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_elevation = math.radians(38)
    sky.sun_rotation = math.radians(-50)
    sc.world.node_tree.links.new(sky.outputs[0], sc.world.node_tree.nodes["Background"].inputs[0])
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.14
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.data.angle = math.radians(1.0)
    sun.data.color = (1.0, 0.93, 0.82)
    sun.rotation_euler = (math.radians(52), 0, math.radians(-140))
    sc.collection.objects.link(sun)
    sc.view_settings.view_transform = 'AgX'


def to_blender(v):
    return Vector((v.x, -v.z, v.y))


def shoot(name, loc_g, target_g, lens, out):
    sc = bpy.context.scene
    cam = bpy.data.objects.new("Cam_" + name, bpy.data.cameras.new("Cam_" + name))
    sc.collection.objects.link(cam)
    loc, tgt = to_blender(loc_g), to_blender(target_g)
    cam.location = loc
    cam.data.lens = lens
    cam.data.clip_end = 3000
    cam.rotation_euler = (tgt - loc).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sc.render.filepath = os.path.join(out, "roadland_%s.jpg" % name)
    bpy.ops.render.render(write_still=True)
    print("SHOT", name, flush=True)


def pick_views(tiles, classes):
    """Street level on the biggest road near the middle, an aerial over its busiest junction, a footpath view."""
    best, bw = None, -1
    cx = np.mean([t["cx"] for t in tiles]) * 256 + 128
    cz = np.mean([t["cz"] for t in tiles]) * 256 + 128
    for t in tiles:
        for r in t["roads"]:
            if len(r["p"]) < 4 or r["fl"] & 2:
                continue
            mid = r["p"][len(r["p"]) // 2]
            score = r["w"] * 10 - math.hypot(mid[0] - cx, mid[2] - cz) * 0.05 + len(r["p"]) * 0.2
            if score > bw:
                best, bw = r, score
    p = best["p"]
    i = len(p) // 2
    a, c = V(*p[i - 1]), V(*p[i + 1])
    d = flat(c - a).normalized()
    left = left_of(d)
    half = best["w"] * 0.5
    eye = a - d * 25 + left * (half * 0.15) + Vector((0, 1.6, 0))
    street = (eye, eye + d * 60 + Vector((0, -1.0, 0)))
    walk = (a - d * 10 + left * (half + 1.3) + Vector((0, 1.75, 0)), a + d * 30 + left * (half * 0.2) + Vector((0, 0.6, 0)))
    jbest, jn = None, -1
    for t in tiles:
        for v in t["junc"]:
            if len(v) > jn:
                jbest, jn = v, len(v)
    jc = Vector(np.asarray(jbest).mean(axis=0).tolist())
    aerial = (jc + Vector((-55, 60, 70)), jc)
    high = (Vector((cx - 250, jc.y + 260, cz + 250)), Vector((cx, jc.y, cz)))
    return {"street": (*street, 26), "footpath": (*walk, 24), "junction": (*aerial, 30), "overview": (*high, 28)}


def type_views(tiles):
    """One street-level view per street type found: from the middle of the longest strip of that type, looking
    along the street from the near edge of the carriageway."""
    best = {}
    for t in tiles:
        for wk in t["walks"]:
            typ = wk.get("type")
            if typ in (None, "median") or len(wk["p"]) < 4:
                continue
            L = float(np.hypot(*np.diff(wk["p"][:, [0, 2]], axis=0).T).sum())
            if L > best.get(typ, (0, None))[0]:
                best[typ] = (L, wk)
    out = {}
    for typ, (L, wk) in best.items():
        p = wk["p"]
        i = len(p) // 3
        a, c = V(*p[i]), V(*p[i + 1])
        d = flat(c - a).normalized()
        rw = Vector((d.z, 0, -d.x)) if (wk["fl"] & 4) else Vector((-d.z, 0, d.x))
        hw = wk["w"] * 0.5
        eye = a + rw * (hw + 3.2) + Vector((0, 1.5, 0))                 # in the carriageway, clear of parked vehicles
        out["type_" + typ] = (eye, eye + d * 40 - rw * 3.0 + Vector((0, -1.2, 0)), 24)
    return out


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    rng = args[args.index("--tiles") + 1] if "--tiles" in args else "-1,-1:0,0"
    out = os.path.abspath(args[args.index("--out") + 1]) if "--out" in args else os.path.join(ROOT, "previews", "roadland")
    samples = int(args[args.index("--samples") + 1]) if "--samples" in args else 96
    os.makedirs(out, exist_ok=True)
    (a0, b0), (a1, b1) = [tuple(map(int, s.split(","))) for s in rng.split(":")]
    import json
    index = json.load(open(os.path.join(CITY, "index.json")))
    classes = index["classes"]
    tiles = []
    for cz in range(b0, b1 + 1):
        for cx in range(a0, a1 + 1):
            fn = os.path.join(CITY, "chunks", "CBE_%d_%d.bin" % (cx, cz))
            if os.path.exists(fn):
                tiles.append(read_tile(fn))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_render(samples)
    world = bpy.data.objects.new("World", None)                   # game frame → Blender
    world.matrix_world = C
    bpy.context.scene.collection.objects.link(world)
    b = Builder("City")
    lamps, trees = [], []
    import streetlife as SL
    SL.classify(tiles, classes, json.load(open(os.path.join(BUILD, "manifest.json"))), index["variants"])
    land(tiles, b)
    roads(tiles, classes, b)
    junctions(tiles, b)
    footpaths(tiles, b, lamps)
    yards(tiles, b, trees)
    SL.place(tiles, classes, instance_of, to_blender, b)
    trees.extend(SL.TREE_SPOTS)
    objs = b.finish(world)
    print("MESH", sum(len(o.data.polygons) for o in objs), "faces", flush=True)
    lc = lamp_collection()
    for q, rw in lamps:
        rot = Matrix.Rotation(math.atan2(rw.x, rw.z), 4, 'Y')            # arm reaches over the road (game frame)
        g = Matrix.Translation(q) @ rot @ Matrix.Rotation(-math.pi / 2, 4, 'X')
        instance_of(lc, C @ g)
    import vegetation as VG

    def as_coll(name, obs):
        coll = bpy.data.collections.new(name)
        for o in (obs if isinstance(obs, list) else [obs]):
            for c in list(o.users_collection):
                c.objects.unlink(o)
            coll.objects.link(o)
        return coll
    bushes = [as_coll("Bush%d" % k, VG.bush(k + 1)) for k in range(5)]
    for k, (at, r) in enumerate(SHRUBS):
        instance_of(bushes[k % len(bushes)], Matrix.Translation(to_blender(at)) @ Matrix.Scale(r * 1.4, 4))
    big = [as_coll("Neem1", VG.neem(1)), as_coll("Neem2", VG.neem(2)), as_coll("Rain1", VG.raintree(1)),
           as_coll("Gul1", VG.gulmohar(1)), as_coll("Palm1", VG.palm(1)), as_coll("Palm2", VG.palm(2))]
    grass = as_coll("Tuft", VG.grass_tuft(1))
    rr = random.Random(9)
    for k, q in enumerate(trees):
        roll = rr.random()
        m = Matrix.Translation(to_blender(q)) @ Matrix.Rotation(rr.random() * 6.28, 4, 'Z')
        if roll < 0.35:
            instance_of(big[rr.randrange(len(big))], m @ Matrix.Scale(rr.uniform(0.8, 1.15), 4))
        elif roll < 0.7:
            instance_of(bushes[rr.randrange(len(bushes))], m @ Matrix.Scale(rr.uniform(0.8, 1.4), 4))
            for _g in range(6):
                off = Vector((rr.uniform(-2, 2), rr.uniform(-2, 2), 0))
                instance_of(grass, Matrix.Translation(to_blender(q) + off) @ Matrix.Rotation(rr.random() * 6.28, 4, 'Z')
                            @ Matrix.Scale(rr.uniform(1.0, 1.8), 4))
        else:
            for _g in range(10):
                off = Vector((rr.uniform(-3, 3), rr.uniform(-3, 3), 0))
                instance_of(grass, Matrix.Translation(to_blender(q) + off) @ Matrix.Rotation(rr.random() * 6.28, 4, 'Z')
                            @ Matrix.Scale(rr.uniform(1.0, 1.8), 4))
    if "--nobuildings" not in args:
        bcs = building_collections(index)
        kit_materials()
        n = 0
        for t in tiles:
            for bd in t["blds"]:
                if bd["variant"] in bcs:
                    ox, oy, oz, fx, fz, sx, sz = bd["kd"]
                    nz = Vector((fx, 0, fz))
                    nx = Vector((fz, 0, -fx))
                    T = Matrix(((nx.x * sx, 0, nz.x * sz, ox), (0, 1, 0, oy), (nx.z * sx, 0, nz.z * sz, oz), (0, 0, 0, 1)))
                    instance_of(bcs[bd["variant"]], C @ T @ C.inverted())
                    n += 1
        print("BUILDINGS", n, flush=True)
    views = pick_views(tiles, classes)
    if "--typeviews" in args:
        views = type_views(tiles)
    for name, (loc, tgt, lens) in views.items():
        shoot(name, loc, tgt, lens, out)
    if "--blend" in args:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args[args.index("--blend") + 1]), compress=True)


if __name__ == "__main__":
    main()
