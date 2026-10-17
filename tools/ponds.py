"""
Coimbatore water bodies — a design reference in Blender (our own designs) before anything goes into the game.

  lake     a city kulam after the Smart City work (Valankulam / Ukkadam / Kurichi): the real Valaan Kulam outline
           (OSM), a stone-pitched bund, a paved walkway on top with railings, lamps and benches, water hyacinth
           drifting at the edges, reeds and cattails, rain trees and neem on the bank
  temple   a theppakulam: a square granite tank, stepped down on all four sides, a pillared neerazhi mandapam in
           the middle, a compound wall with a gate
  kuttai   a village pond (the real Kaliyaperumal Kuttai outline): muddy banks with buffalo tracks, reeds, lotus
           pads and flowers, hyacinth, palmyra palms and a neem on the bund

    Blender -b --factory-startup --python tools/ponds.py -- --out previews/ponds [--samples 64] [--only lake]
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import vegetation as VG  # noqa: E402

SHAPES = os.path.join(HERE, "..", "art", "ponds", "shapes.json")


# ----------------------------------------------------------------------------- materials
_M = {}


DULL = ("Lake Bed", "Bank Soil", "Pond Bed", "Pond Bank", "Field Soil", "Temple Soil", "Stone Pitching", "Granite",
        "Pavers", "Kaavi Wall", "Hazy Hills")


def node_mat(name, build):
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    if name in DULL or name.startswith("House"):
        # soil, stone and plaster hardly reflect: without this a low sun glares white off them
        m.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.12
    build(m.node_tree, m.node_tree.nodes["Principled BSDF"])
    _M[name] = m
    return m


def _noise(nt, scale, detail=6.0, coord="Object", stretch=None):
    co = nt.nodes.new("ShaderNodeTexCoord")
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    if stretch:
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = stretch
        nt.links.new(co.outputs[coord], mp.inputs["Vector"])
        nt.links.new(mp.outputs[0], n.inputs["Vector"])
    else:
        nt.links.new(co.outputs[coord], n.inputs["Vector"])
    return n


def _ramp(nt, src, c0, c1, p0=0.3, p1=0.7):
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].position = p0
    r.color_ramp.elements[1].position = p1
    r.color_ramp.elements[0].color = (*c0, 1)
    r.color_ramp.elements[1].color = (*c1, 1)
    nt.links.new(src, r.inputs["Fac"])
    return r


def water_mat(tint=(0.035, 0.06, 0.035)):
    """Tank water: dark green-brown, glassy, small wind ripples (bump) — reflects the sky."""
    def b(nt, p):
        p.inputs["Base Color"].default_value = (*tint, 1)
        p.inputs["Roughness"].default_value = 0.04
        p.inputs["IOR"].default_value = 1.33
        n = _noise(nt, 0.9, 4.0, stretch=(1.0, 2.5, 1.0))
        n2 = _noise(nt, 6.0, 3.0)
        add = nt.nodes.new("ShaderNodeMath")
        nt.links.new(n.outputs["Fac"], add.inputs[0])
        nt.links.new(n2.outputs["Fac"], add.inputs[1])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.12
        bump.inputs["Distance"].default_value = 0.05
        nt.links.new(add.outputs[0], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
    return node_mat("Water %s" % str(tint), b)


def _wet_band(nt, col, top=0.8):
    """Darken and green a colour below `top` m above the water: the wet band, algae at the waterline."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    n = _noise(nt, 1.5, 4.0)
    jit = nt.nodes.new("ShaderNodeMath")
    jit.operation = "MULTIPLY_ADD"
    nt.links.new(n.outputs["Fac"], jit.inputs[0])
    jit.inputs[1].default_value = 0.4
    nt.links.new(sep.outputs["Z"], jit.inputs[2])
    f = nt.nodes.new("ShaderNodeMapRange")
    nt.links.new(jit.outputs[0], f.inputs["Value"])
    f.inputs["From Min"].default_value = top
    f.inputs["From Max"].default_value = 0.2
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = 'MULTIPLY'
    nt.links.new(f.outputs[0], mix.inputs["Factor"])
    nt.links.new(col, mix.inputs[6])
    mix.inputs[7].default_value = (0.32, 0.4, 0.22, 1)
    return mix.outputs[2]


def stone_pitch_mat():
    """Hand-laid stone pitching on the bund: grey-brown rubble in grout (Voronoi cells), lichen and silt stains."""
    def b(nt, p):
        co = nt.nodes.new("ShaderNodeTexCoord")
        v = nt.nodes.new("ShaderNodeTexVoronoi")
        v.feature = 'DISTANCE_TO_EDGE'
        v.inputs["Scale"].default_value = 2.4
        nt.links.new(co.outputs["Object"], v.inputs["Vector"])
        grout = _ramp(nt, v.outputs["Distance"], (0.09, 0.085, 0.08), (0.36, 0.33, 0.3), 0.02, 0.08)
        n = _noise(nt, 0.6, 5.0)
        stain = _ramp(nt, n.outputs["Fac"], (0.55, 0.6, 0.5), (1.0, 1.0, 1.0), 0.35, 0.65)
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = 'MULTIPLY'
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(grout.outputs["Color"], mul.inputs[6])
        nt.links.new(stain.outputs["Color"], mul.inputs[7])
        wet = _wet_band(nt, mul.outputs[2], 0.9)
        nt.links.new(wet, p.inputs["Base Color"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.7
        nt.links.new(v.outputs["Distance"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
        p.inputs["Roughness"].default_value = 0.9
    return node_mat("Stone Pitching", b)


def granite_mat():
    def b(nt, p):
        n = _noise(nt, 18.0, 8.0)
        r = _ramp(nt, n.outputs["Fac"], (0.07, 0.066, 0.062), (0.2, 0.19, 0.175), 0.35, 0.7)
        n2 = _noise(nt, 0.4, 4.0)
        dirt = _ramp(nt, n2.outputs["Fac"], (0.5, 0.48, 0.42), (1, 1, 1), 0.3, 0.7)
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = 'MULTIPLY'
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(r.outputs["Color"], mul.inputs[6])
        nt.links.new(dirt.outputs["Color"], mul.inputs[7])
        nt.links.new(_wet_band(nt, mul.outputs[2], 1.0), p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = 0.75
    return node_mat("Granite", b)


def ground_mat(name, dry, green, mud=None):
    """Bank ground: dry red-brown Coimbatore soil and patchy grass, wet dark mud near the water (by height)."""
    def b(nt, p):
        n = _noise(nt, 0.35, 6.0)
        r = _ramp(nt, n.outputs["Fac"], tuple(c * 0.62 for c in dry), tuple(c * 0.7 for c in green), 0.42, 0.62)
        col = r.outputs["Color"]
        # clods and pebbles
        cl = _noise(nt, 9.0, 4.0)
        clr = _ramp(nt, cl.outputs["Fac"], (0.7, 0.68, 0.66), (1.15, 1.12, 1.08), 0.35, 0.75)
        m0 = nt.nodes.new("ShaderNodeMix")
        m0.data_type = "RGBA"
        m0.blend_type = 'MULTIPLY'
        m0.inputs["Factor"].default_value = 1.0
        nt.links.new(col, m0.inputs[6])
        nt.links.new(clr.outputs["Color"], m0.inputs[7])
        col = m0.outputs[2]
        if mud:
            # dried mud cracking into plates where the water has drawn back
            co = nt.nodes.new("ShaderNodeTexCoord")
            vo = nt.nodes.new("ShaderNodeTexVoronoi")
            vo.feature = 'DISTANCE_TO_EDGE'
            vo.inputs["Scale"].default_value = 3.5
            nt.links.new(co.outputs["Object"], vo.inputs["Vector"])
            crack = _ramp(nt, vo.outputs["Distance"], (0.25, 0.22, 0.2), (1, 1, 1), 0.0, 0.04)
            m1 = nt.nodes.new("ShaderNodeMix")
            m1.data_type = "RGBA"
            m1.blend_type = 'MULTIPLY'
            m1.inputs["Factor"].default_value = 1.0
            nt.links.new(col, m1.inputs[6])
            nt.links.new(crack.outputs["Color"], m1.inputs[7])
            col = m1.outputs[2]
            geo = nt.nodes.new("ShaderNodeNewGeometry")
            sep = nt.nodes.new("ShaderNodeSeparateXYZ")
            nt.links.new(geo.outputs["Position"], sep.inputs[0])
            wet = nt.nodes.new("ShaderNodeMapRange")
            nt.links.new(sep.outputs["Z"], wet.inputs["Value"])
            wet.inputs["From Min"].default_value = 0.05
            wet.inputs["From Max"].default_value = 0.6
            wet.inputs["To Min"].default_value = 1.0
            wet.inputs["To Max"].default_value = 0.0
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            nt.links.new(wet.outputs[0], mix.inputs["Factor"])
            nt.links.new(col, mix.inputs[6])
            mix.inputs[7].default_value = (*mud, 1)
            col = mix.outputs[2]
            rough = nt.nodes.new("ShaderNodeMapRange")
            nt.links.new(wet.outputs[0], rough.inputs["Value"])
            rough.inputs["To Min"].default_value = 1.0
            rough.inputs["To Max"].default_value = 0.62
            nt.links.new(rough.outputs[0], p.inputs["Roughness"])
        else:
            p.inputs["Roughness"].default_value = 0.95
        nt.links.new(col, p.inputs["Base Color"])
        fine = _noise(nt, 12.0, 8.0)
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.3
        nt.links.new(fine.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
    return node_mat(name, b)


def paver_mat():
    def b(nt, p):
        co = nt.nodes.new("ShaderNodeTexCoord")
        br = nt.nodes.new("ShaderNodeTexBrick")
        br.inputs["Scale"].default_value = 3.0
        br.inputs["Color1"].default_value = (0.45, 0.4, 0.36, 1)
        br.inputs["Color2"].default_value = (0.36, 0.3, 0.27, 1)
        br.inputs["Mortar"].default_value = (0.2, 0.19, 0.18, 1)
        br.inputs["Mortar Size"].default_value = 0.01
        nt.links.new(co.outputs["Object"], br.inputs["Vector"])
        nt.links.new(br.outputs["Color"], p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = 0.85
    return node_mat("Pavers", b)


def flat_mat(name, col, rough=0.6, metal=0.0):
    def b(nt, p):
        p.inputs["Base Color"].default_value = (*col, 1)
        p.inputs["Roughness"].default_value = rough
        p.inputs["Metallic"].default_value = metal
    return node_mat(name, b)


def leafy_mat(name, col, trans=0.3, rough=0.5):
    """Two-sided leaves lit through from behind (reeds, hyacinth, lotus pads)."""
    def b(nt, p):
        geo = nt.nodes.new("ShaderNodeVertexColor")
        geo.layer_name = "Col"
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = 'MULTIPLY'
        mul.inputs["Factor"].default_value = 1.0
        mul.inputs[6].default_value = (*col, 1)
        nt.links.new(geo.outputs["Color"], mul.inputs[7])
        nt.links.new(mul.outputs[2], p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = rough
        tr = nt.nodes.new("ShaderNodeBsdfTranslucent")
        nt.links.new(mul.outputs[2], tr.inputs["Color"])
        ms = nt.nodes.new("ShaderNodeMixShader")
        ms.inputs[0].default_value = trans
        out = nt.nodes["Material Output"]
        nt.links.new(p.outputs[0], ms.inputs[1])
        nt.links.new(tr.outputs[0], ms.inputs[2])
        nt.links.new(ms.outputs[0], out.inputs["Surface"])
    return node_mat(name, b)


# ----------------------------------------------------------------------------- geometry helpers
def obj_from_bm(bm, name, mats, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        for f in me.polygons:
            f.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        me.materials.append(m)
    return ob


def box(bm, centre, size, rot=0.0, mat=0):
    c, s = math.cos(rot), math.sin(rot)
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    vs = []
    for z in (-hz, hz):
        for x, y in ((-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)):
            vs.append(bm.verts.new((centre[0] + x * c - y * s, centre[1] + x * s + y * c, centre[2] + z)))
    for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        bm.faces.new([vs[i] for i in f]).material_index = mat


def cyl(bm, a, b, r, segs=8, mat=0):
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    u = d.orthogonal().normalized()
    v = d.cross(u)
    ra = [bm.verts.new(a + (u * math.cos(t) + v * math.sin(t)) * r) for t in (k * math.tau / segs for k in range(segs))]
    rb = [bm.verts.new(b + (u * math.cos(t) + v * math.sin(t)) * r) for t in (k * math.tau / segs for k in range(segs))]
    for k in range(segs):
        f = bm.faces.new((ra[k], ra[(k + 1) % segs], rb[(k + 1) % segs], rb[k]))
        f.material_index = mat
        f.smooth = True
    bm.faces.new(list(reversed(ra))).material_index = mat
    bm.faces.new(rb).material_index = mat


def sdf(poly, pts):
    """Signed distance from points to a polygon outline (negative inside)."""
    P = np.asarray(poly, float)
    A, B = P, np.roll(P, -1, axis=0)
    X = pts[:, None, :]
    AB = (B - A)[None]
    t = np.clip(((X - A[None]) * AB).sum(-1) / np.maximum((AB * AB).sum(-1), 1e-9), 0, 1)
    proj = A[None] + t[..., None] * AB
    d = np.sqrt(((X - proj) ** 2).sum(-1)).min(axis=1)
    x, y = pts[:, 0][:, None], pts[:, 1][:, None]
    ya, yb = A[None, :, 1], B[None, :, 1]
    xa, xb = A[None, :, 0], B[None, :, 0]
    cross = ((ya > y) != (yb > y)) & (x < (xb - xa) * (y - ya) / (yb - ya + 1e-12) + xa)
    inside = cross.sum(axis=1) % 2 == 1
    return np.where(inside, -d, d)


def offset(poly, dist):
    """The outline moved outward by `dist` (vertex normals; fine for gentle outlines)."""
    P = [Vector((x, y, 0)) for x, y in poly]
    n = len(P)
    area = sum(P[i].x * P[(i + 1) % n].y - P[(i + 1) % n].x * P[i].y for i in range(n))
    sgn = 1 if area > 0 else -1
    out = []
    for i in range(n):
        a, b, c = P[i - 1], P[i], P[(i + 1) % n]
        n1 = Vector(((b - a).y, -(b - a).x, 0)).normalized() * sgn
        n2 = Vector(((c - b).y, -(c - b).x, 0)).normalized() * sgn
        m = (n1 + n2)
        m = m.normalized() / max(m.normalized().dot(n1), 0.5) if m.length > 1e-6 else n1
        out.append(b + m * dist)
    return out


def resample(loop, step):
    pts = []
    n = len(loop)
    for i in range(n):
        a, b = loop[i], loop[(i + 1) % n]
        L = (b - a).length
        k = max(1, int(L / step))
        for j in range(k):
            pts.append(a + (b - a) * (j / k))
    return pts


def heights(poly, G, bank_h, slope_w, bed):
    """Ground height (and signed distance to the water's edge) at points G (n x 2)."""
    d = sdf(poly, G)
    h = np.where(d > 0, bank_h * np.clip(d / slope_w, 0, 1) ** 0.8, np.maximum(-bed, d * 0.35)) - 0.25
    wob = np.sin(G[:, 0] * 0.05 + 1.3) * np.cos(G[:, 1] * 0.043) * 0.25 + np.sin(G[:, 0] * 0.31) * np.sin(G[:, 1] * 0.27) * 0.06
    wob = np.where(d > slope_w + 14.0, wob * 0.12, np.where(d > slope_w, wob, wob * 0.3))
    return h + wob, d


def terrain(poly, res, margin, bank_h, slope_w, bed, rng, name, mats, zones):
    """Ground around and under a pond: the bed below water (z = 0 is the water level), the bank rising to
    `bank_h` over `slope_w` metres, flat land beyond with gentle noise. `zones(d)` → material index per face."""
    P = np.asarray(poly)
    lo, hi = P.min(axis=0) - margin, P.max(axis=0) + margin
    nx, ny = int((hi[0] - lo[0]) / res) + 1, int((hi[1] - lo[1]) / res) + 1
    xs, ys = np.linspace(lo[0], hi[0], nx), np.linspace(lo[1], hi[1], ny)
    G = np.stack(np.meshgrid(xs, ys), -1).reshape(-1, 2)
    h, d = heights(poly, G, bank_h, slope_w, bed)
    bm = bmesh.new()
    vs = [bm.verts.new((G[i, 0], G[i, 1], h[i])) for i in range(len(G))]
    for j in range(ny - 1):
        for i in range(nx - 1):
            k = j * nx + i
            q = (vs[k], vs[k + 1], vs[k + nx + 1], vs[k + nx])
            fc = bm.faces.new(q)
            fc.smooth = True
            fc.material_index = zones((d[k] + d[k + 1] + d[k + nx] + d[k + nx + 1]) / 4)
    return obj_from_bm(bm, name, mats, smooth=True), (lo, hi)


def water_body(poly, lo, hi, res, absorb, density=0.9, scum=0.35, depth=4.0):
    """The water as a closed body (so light is absorbed with depth: clear at the edge, murky in the middle);
    vertex colour r = nearness to the shore (green scum and floating dust collect there)."""
    nx, ny = int((hi[0] - lo[0]) / res) + 1, int((hi[1] - lo[1]) / res) + 1
    xs, ys = np.linspace(lo[0], hi[0], nx), np.linspace(lo[1], hi[1], ny)
    G = np.stack(np.meshgrid(xs, ys), -1).reshape(-1, 2)
    d = sdf(poly, G)
    shore = np.clip(1.0 + d / 14.0, 0, 1)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    top = [bm.verts.new((G[i, 0], G[i, 1], 0.0)) for i in range(len(G))]
    bot = [bm.verts.new((G[i, 0], G[i, 1], -depth)) for i in range(len(G))]
    for j in range(ny - 1):
        for i in range(nx - 1):
            k = j * nx + i
            ids = (k, k + 1, k + nx + 1, k + nx)
            f = bm.faces.new([top[t] for t in ids])
            for lp, t in zip(f.loops, ids):
                lp[col] = (shore[t], 0, 0, 1)
            bm.faces.new([bot[t] for t in reversed(ids)])
    edges = [[j * nx for j in range(ny)], [j * nx + nx - 1 for j in range(ny)], list(range(nx)), [(ny - 1) * nx + i for i in range(nx)]]
    for e, flip in zip(edges, (True, False, False, True)):
        for a, b in zip(e, e[1:]):
            q = (top[a], top[b], bot[b], bot[a])
            bm.faces.new(q if not flip else tuple(reversed(q)))
    bm.normal_update()
    return obj_from_bm(bm, "Water", [water_body_mat(absorb, density, scum)])


def water_body_mat(absorb, density, scum):
    def b(nt, p):
        p.inputs["Base Color"].default_value = (0.8, 0.85, 0.8, 1)
        p.inputs["Roughness"].default_value = 0.02
        p.inputs["IOR"].default_value = 1.33
        p.inputs["Transmission Weight"].default_value = 1.0
        n = _noise(nt, 0.9, 4.0, stretch=(1.0, 2.5, 1.0))
        n2 = _noise(nt, 7.0, 3.0)
        add = nt.nodes.new("ShaderNodeMath")
        nt.links.new(n.outputs["Fac"], add.inputs[0])
        nt.links.new(n2.outputs["Fac"], add.inputs[1])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.1
        bump.inputs["Distance"].default_value = 0.04
        nt.links.new(add.outputs[0], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
        out = nt.nodes["Material Output"]
        # scum near the shore: patchy (noise) where the vertex colour says shore
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(vc.outputs["Color"], sep.inputs[0])
        patch = _noise(nt, 0.12, 6.0)
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        nt.links.new(sep.outputs[0], mul.inputs[0])
        nt.links.new(patch.outputs["Fac"], mul.inputs[1])
        fac = nt.nodes.new("ShaderNodeMapRange")
        nt.links.new(mul.outputs[0], fac.inputs["Value"])
        fac.inputs["From Min"].default_value = scum
        fac.inputs["From Max"].default_value = scum + 0.12
        sc = nt.nodes.new("ShaderNodeBsdfPrincipled")
        fine = _noise(nt, 3.0, 8.0)
        sc_col = _ramp(nt, fine.outputs["Fac"], (0.035, 0.06, 0.015), (0.11, 0.16, 0.04), 0.35, 0.7)
        nt.links.new(sc_col.outputs["Color"], sc.inputs["Base Color"])
        sc.inputs["Roughness"].default_value = 0.7
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(fac.outputs[0], mix.inputs[0])
        nt.links.new(p.outputs[0], mix.inputs[1])
        nt.links.new(sc.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
        vol = nt.nodes.new("ShaderNodeVolumeAbsorption")
        vol.inputs["Color"].default_value = (*absorb, 1)
        vol.inputs["Density"].default_value = density
        nt.links.new(vol.outputs[0], out.inputs["Volume"])
    return node_mat("Water body %s" % str(absorb), b)


def water_plane(lo, hi, mat, z=0.0):
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z)) for x, y in ((lo[0], lo[1]), (hi[0], lo[1]), (hi[0], hi[1]), (lo[0], hi[1]))]
    bm.faces.new(vs)
    return obj_from_bm(bm, "Water", [mat])


def instance(src, loc, rot=0.0, scale=1.0, name="inst"):
    ob = bpy.data.objects.new(name, src.data)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (0, 0, rot)
    ob.scale = (scale, scale, scale)
    return ob


def hide(ob):
    ob.location = (0, 0, -500)
    return ob


# ----------------------------------------------------------------------------- plants of the water's edge
def reed_clump(seed, cattail=True):
    """Cattails / reeds: 30-50 long ribbon blades leaning out, a few brown cattail spikes on stalks."""
    rng = random.Random(seed)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    for k in range(rng.randint(30, 50)):
        a = rng.uniform(0, math.tau)
        r0 = rng.uniform(0, 0.35)
        base = Vector((math.cos(a) * r0, math.sin(a) * r0, -0.1))
        hgt = rng.uniform(1.0, 2.0)
        lean = rng.uniform(0.05, 0.35)
        d = Vector((math.cos(a) * lean, math.sin(a) * lean, 1)).normalized()
        side = Vector((-math.sin(a), math.cos(a), 0)) * rng.uniform(0.008, 0.016)
        pts = [base + d * hgt * t + Vector((math.cos(a), math.sin(a), 0)) * (lean * hgt * t * t * 0.6) for t in (0, 0.35, 0.7, 1.0)]
        shade = rng.uniform(0.55, 1.1)
        dry = rng.random() < 0.18
        c = (shade * (1.6 if dry else 1), shade * (1.25 if dry else 1), shade * (0.6 if dry else 1), 1)
        ring = [(bm.verts.new(p - side * (1 - i / 3)), bm.verts.new(p + side * (1 - i / 3))) for i, p in enumerate(pts)]
        for i in range(3):
            f = bm.faces.new((ring[i][0], ring[i][1], ring[i + 1][1], ring[i + 1][0]))
            for lp in f.loops:
                lp[col] = c
    if cattail:
        for k in range(rng.randint(3, 8)):
            a = rng.uniform(0, math.tau)
            r0 = rng.uniform(0, 0.3)
            base = Vector((math.cos(a) * r0, math.sin(a) * r0, -0.1))
            top = base + Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), rng.uniform(1.4, 2.1)))
            n0 = len(bm.faces)
            cyl(bm, base, top, 0.006, 4, 0)
            cyl(bm, top - Vector((0, 0, 0.32)), top - Vector((0, 0, 0.05)), 0.022, 6, 1)
            for f in list(bm.faces)[n0:]:
                for lp in f.loops:
                    lp[col] = (1, 1, 1, 1)
    return obj_from_bm(bm, "reeds_%d" % seed, [leafy_mat("Reed", (0.16, 0.24, 0.07)), flat_mat("Cattail", (0.18, 0.09, 0.04), 0.9)])


def hyacinth_patch(seed, radius=3.0, density=6.0, K=14):
    """Water hyacinth (aagaya thamarai): floating rosettes of glossy round leaves on swollen stalks, lilac
    flower spikes here and there, packed into a drifting mat."""
    rng = random.Random(seed)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    n = int(math.pi * radius * radius * density)
    for k in range(n):
        r = radius * math.sqrt(rng.random())
        a = rng.uniform(0, math.tau)
        c0 = Vector((math.cos(a) * r * rng.uniform(0.8, 1.2), math.sin(a) * r, 0.0))
        for j in range(rng.randint(4, 7)):
            la = rng.uniform(0, math.tau)
            tilt = rng.uniform(0.5, 1.1)
            size = rng.uniform(0.07, 0.12)
            out = Vector((math.cos(la), math.sin(la), 0))
            cen = c0 + out * size * 0.9 + Vector((0, 0, 0.06 + size * math.sin(tilt) * 0.6))
            nrm = (out * math.cos(tilt) + Vector((0, 0, 1)) * math.sin(tilt)).normalized()
            u = nrm.cross(Vector((0, 0, 1))).normalized() if abs(nrm.z) < 0.99 else Vector((1, 0, 0))
            v = nrm.cross(u)
            ring = [bm.verts.new(cen + (u * math.cos(t) + v * math.sin(t) * 1.15) * size * (0.92 if i == 0 else 1.0)
                                 + nrm * size * 0.18) for i, t in enumerate(j2 * math.tau / K for j2 in range(K))]
            mid_r = [bm.verts.new(cen + (u * math.cos(t) + v * math.sin(t) * 1.15) * size * 0.55 + nrm * size * 0.04)
                     for t in (j2 * math.tau / K for j2 in range(K))]
            mid = bm.verts.new(cen - nrm * size * 0.05)
            shade = rng.uniform(0.6, 1.15)
            cc = (shade, shade * rng.uniform(0.95, 1.08), shade * 0.9, 1)
            for i in range(K):
                i2 = (i + 1) % K
                for q in ((mid, mid_r[i], mid_r[i2]), (mid_r[i], ring[i], ring[i2], mid_r[i2])):
                    f = bm.faces.new(q)
                    f.smooth = True
                    for lp in f.loops:
                        lp[col] = cc
            # the swollen, spongy stalk below the leaf
            n0 = len(bm.faces)
            cyl(bm, c0 + Vector((0, 0, 0.02)), cen - nrm * size * 0.3, 0.018, 6, 0)
            for f in list(bm.faces)[n0:]:
                for lp in f.loops:
                    lp[col] = (0.9, 1.0, 0.8, 1)
        if rng.random() < 0.12:
            top = c0 + Vector((0, 0, rng.uniform(0.25, 0.4)))
            n0 = len(bm.faces)
            cyl(bm, c0 + Vector((0, 0, 0.05)), top, 0.008, 4, 0)
            for j in range(6):
                p = top - Vector((0, 0, j * 0.03)) + Vector((rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), 0))
                box(bm, p, (0.045, 0.045, 0.03), rng.uniform(0, 3), 1)
            for f in list(bm.faces)[n0:]:
                for lp in f.loops:
                    lp[col] = (1, 1, 1, 1)
    return obj_from_bm(bm, "hyacinth_%d" % seed, [leafy_mat("Hyacinth", (0.1, 0.26, 0.05), 0.2, 0.22),
                                                   flat_mat("Hyacinth Flower", (0.5, 0.35, 0.75), 0.5)])


def lotus_patch(seed, radius=4.0, density=2.2):
    """Lotus pads flat on the water (a notch to the centre), a few raised pads and pink flowers on stalks."""
    rng = random.Random(seed)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    for k in range(int(math.pi * radius * radius * density)):
        r = radius * math.sqrt(rng.random())
        a = rng.uniform(0, math.tau)
        c0 = Vector((math.cos(a) * r, math.sin(a) * r, 0.012))
        size = rng.uniform(0.18, 0.4)
        raised = rng.random() < 0.15
        if raised:
            c0.z = rng.uniform(0.3, 0.7)
        notch = rng.uniform(0, math.tau)
        mid = bm.verts.new(c0)
        ring = []
        for i in range(14):
            t = notch + 0.25 + i / 13 * (math.tau - 0.5)
            ring.append(bm.verts.new(c0 + Vector((math.cos(t) * size, math.sin(t) * size, (0.04 * size if raised else 0.0)))))
        shade = rng.uniform(0.65, 1.1)
        for i in range(13):
            f = bm.faces.new((mid, ring[i], ring[i + 1]))
            for lp in f.loops:
                lp[col] = (shade, shade * rng.uniform(0.95, 1.05), shade, 1)
        if rng.random() < 0.07:
            top = c0 + Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), rng.uniform(0.5, 0.9)))
            n0 = len(bm.faces)
            cyl(bm, Vector((c0.x, c0.y, 0)), top, 0.008, 4, 0)
            for j in range(10):
                pa = j / 10 * math.tau
                tip = top + Vector((math.cos(pa) * 0.09, math.sin(pa) * 0.09, 0.12 if j % 2 else 0.09))
                left = top + Vector((math.cos(pa - 0.3) * 0.04, math.sin(pa - 0.3) * 0.04, 0.02))
                right = top + Vector((math.cos(pa + 0.3) * 0.04, math.sin(pa + 0.3) * 0.04, 0.02))
                f = bm.faces.new((bm.verts.new(top), bm.verts.new(left), bm.verts.new(tip), bm.verts.new(right)))
                f.material_index = 1
            for f in list(bm.faces)[n0:]:
                for lp in f.loops:
                    lp[col] = (1, 1, 1, 1)
    return obj_from_bm(bm, "lotus_%d" % seed, [leafy_mat("Lotus Pad", (0.06, 0.16, 0.035), 0.1, 0.75),
                                                flat_mat("Lotus Flower", (0.9, 0.42, 0.55), 0.4)])


def palmyra(seed):
    """Palmyra (panai): a tall straight dark trunk ringed with leaf scars, a ball of stiff fan leaves on top."""
    rng = random.Random(seed)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    h = rng.uniform(11, 15)
    lean = Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), 0))
    prev = None
    for i in range(12):
        f0, f1 = i / 12, (i + 1) / 12
        a = Vector((0, 0, h * f0)) + lean * f0 * f0
        b = Vector((0, 0, h * f1)) + lean * f1 * f1
        n0 = len(bm.faces)
        cyl(bm, a, b, 0.32 - 0.06 * f0 + (0.06 if i == 0 else 0), 10, 0)
        for fc in list(bm.faces)[n0:]:
            for lp in fc.loops:
                lp[col] = (1, 1, 1, 1)
    top = Vector((0, 0, h)) + lean
    for k in range(rng.randint(22, 30)):
        az = rng.uniform(0, math.tau)
        el = rng.uniform(-0.6, 1.2)
        d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
        stalk_end = top + d * rng.uniform(1.0, 1.6)
        n0 = len(bm.faces)
        cyl(bm, top, stalk_end, 0.035, 4, 0)
        # the fan: radial segments from the stalk end, a pleated half-disc
        u = d.cross(Vector((0, 0, 1))).normalized() if abs(d.z) < 0.99 else Vector((1, 0, 0))
        w = u.cross(d).normalized()
        R = rng.uniform(1.1, 1.5)
        dry = rng.random() < 0.2 or el < -0.3
        shade = rng.uniform(0.7, 1.1)
        c = (shade * (2.2 if dry else 1), shade * (1.5 if dry else 1), shade * (0.7 if dry else 1), 1)
        centre = bm.verts.new(stalk_end)
        prev_v = None
        for j in range(17):
            t = -1.25 + 2.5 * j / 16
            pleat = 0.08 * (1 if j % 2 else -1)
            pdir = (d * math.cos(t) + u * math.sin(t)).normalized()
            v = bm.verts.new(stalk_end + pdir * R + w * (pleat * R - 0.25 * R * abs(t)))
            if prev_v:
                fc = bm.faces.new((centre, prev_v, v))
                fc.material_index = 1
            prev_v = v
        for fc in list(bm.faces)[n0:]:
            for lp in fc.loops:
                lp[col] = c if fc.material_index == 1 else (1, 1, 1, 1)
    return obj_from_bm(bm, "palmyra_%d" % seed, [flat_mat("Palmyra Trunk", (0.09, 0.075, 0.065), 0.9),
                                                  leafy_mat("Palmyra Leaf", (0.2, 0.3, 0.12), 0.2)])


def grass_field(poly, bank_h, slope_w, bed, rng, d0, d1, count, name="grass", spread=None):
    """Dry-season grass on the banks: tufts of straw-coloured and green blades between d0 and d1 m from the
    water's edge (one mesh)."""
    P = np.asarray(poly)
    lo, hi = P.min(axis=0) - d1, P.max(axis=0) + d1
    pts = []
    tries = 0
    while len(pts) < count and tries < count * 40:
        tries += 1
        q = np.array([[rng.uniform(lo[0], hi[0]), rng.uniform(lo[1], hi[1])] for _ in range(4000)])
        dd = sdf(poly, q)
        ok = q[(dd > d0) & (dd < d1)]
        pts.extend(ok.tolist())
    pts = np.array(pts[:count])
    if not len(pts):
        return None
    h, _ = heights(poly, pts, bank_h, slope_w, bed)
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    for (x, y), z in zip(pts, h):
        dry = rng.random()
        for k in range(rng.randint(6, 12)):
            a = rng.uniform(0, math.tau)
            lean = rng.uniform(0.1, 0.6)
            hgt = rng.uniform(0.15, 0.55)
            base = Vector((x + math.cos(a) * 0.05, y + math.sin(a) * 0.05, z - 0.03))
            dvec = Vector((math.cos(a) * lean, math.sin(a) * lean, 1)).normalized()
            side = Vector((-math.sin(a), math.cos(a), 0)) * 0.007
            tip = base + dvec * hgt + Vector((math.cos(a), math.sin(a), 0)) * lean * hgt * 0.4
            midp = base + dvec * hgt * 0.5
            straw = (0.5, 0.42, 0.2) if dry > 0.35 else (0.16, 0.24, 0.07)
            sh = rng.uniform(0.7, 1.15)
            c = (straw[0] * sh, straw[1] * sh, straw[2] * sh, 1)
            vs = [bm.verts.new(base - side), bm.verts.new(base + side), bm.verts.new(midp + side * 0.6),
                  bm.verts.new(midp - side * 0.6), bm.verts.new(tip)]
            for face in ((vs[0], vs[1], vs[2], vs[3]), (vs[3], vs[2], vs[4])):
                f = bm.faces.new(face)
                for lp in f.loops:
                    lp[col] = c
    return obj_from_bm(bm, name, [leafy_mat("Field Grass", (1.0, 1.0, 1.0), 0.25, 0.7)])


def prosopis(seed):
    """Seemai karuvelam (Prosopis juliflora), the thorny scrub on every tank bund around Coimbatore: many
    crooked dark stems from the ground, a loose drooping crown of tiny feathery leaves."""
    rng = random.Random(seed)
    m = VG.Mesh()
    tips = []
    for k in range(rng.randint(4, 7)):
        a = rng.uniform(0, math.tau)
        d = Vector((math.cos(a) * 0.9, math.sin(a) * 0.9, 1.0))
        VG._branches(m, rng, Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), -0.1)), d, rng.uniform(1.4, 2.2),
                     0.06, 3, 0.8, tips, droop=0.06)
    VG._crown(m, rng, tips, 4, 0.55, droop=0.45, lit=0.25)
    return m.finish("prosopis_%d" % seed, [VG.bark_mat(), VG.leaf_mat("Prosopis Leaf", "rain")])


def egret(seed, pose=0):
    """A cattle / little egret: white body, S-curved neck, yellow-black bill, black legs (about 0.6 m tall)."""
    rng = random.Random(seed)
    bm = bmesh.new()
    body_c = Vector((0, 0, 0.42))
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.1,
                              matrix=__import__("mathutils").Matrix.Translation(body_c) @
                              __import__("mathutils").Matrix.Diagonal((1.7, 0.9, 0.95, 1.0)))
    for f in bm.faces:
        f.smooth = True
    head_lift = 0.0 if pose == 0 else -0.22                         # 1: bent down, feeding
    neck = [body_c + Vector((0.13, 0, 0.04)), body_c + Vector((0.12, 0, 0.14 + head_lift * 0.3)),
            body_c + Vector((0.17, 0, 0.22 + head_lift * 0.7)), body_c + Vector((0.2, 0, 0.27 + head_lift))]
    for a, b in zip(neck, neck[1:]):
        cyl(bm, a, b, 0.022, 6)
    head = neck[-1]
    bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=0.035,
                              matrix=__import__("mathutils").Matrix.Translation(head))
    tail = body_c + Vector((-0.2, 0, -0.02))
    cyl(bm, body_c + Vector((-0.1, 0, 0)), tail, 0.04, 6)
    n0 = len(bm.faces)
    bill_end = head + Vector((0.11, 0, -0.02 + (-0.06 if pose else 0)))
    cyl(bm, head + Vector((0.02, 0, 0)), bill_end, 0.008, 4, 1)
    for side in (-1, 1):
        hip = body_c + Vector((-0.02, side * 0.04, -0.06))
        knee = hip + Vector((-0.02, 0, -0.17))
        cyl(bm, hip, knee, 0.007, 4, 2)
        cyl(bm, knee, knee + Vector((0.01, 0, -0.2)), 0.006, 4, 2)
    return obj_from_bm(bm, "egret_%d" % seed, [flat_mat("Egret White", (0.82, 0.82, 0.78), 0.55),
                                                flat_mat("Egret Bill", (0.8, 0.6, 0.08), 0.4),
                                                flat_mat("Egret Leg", (0.03, 0.03, 0.03), 0.5)])


def flock(poly, rng, n, birds):
    """Egrets wading in the shallows (0.5-4 m in from the edge, where the water is ankle-deep)."""
    loop = resample(offset(poly, -rng.uniform(1.0, 2.5)), 3.0)
    for k in range(n):
        p = rng.choice(loop)
        o = instance(rng.choice(birds), (p.x + rng.uniform(-1, 1), p.y + rng.uniform(-1, 1), -0.15),
                     rng.uniform(0, math.tau), rng.uniform(0.9, 1.1))


def _vnoise(x, y, seed):
    """Smooth value noise on a unit lattice (numpy)."""
    xi, yi = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
    tx, ty = x - xi, y - yi
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)

    def h(a, b):
        v = (a * 374761393 + b * 668265263 + seed * 2147483647) & 0xFFFFFFFF
        v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
        return (v & 0xFFFF) / 65535.0
    return (h(xi, yi) * (1 - tx) + h(xi + 1, yi) * tx) * (1 - ty) + (h(xi, yi + 1) * (1 - tx) + h(xi + 1, yi + 1) * tx) * ty


def hills(cx, cy, rng, west=(-1.0, 0.0)):
    """The Western Ghats round Coimbatore: ridged mountains 4-12 km out, high to the west (Velliangiri,
    Bolampatti side), lower broken hills elsewhere. Forest canopy on the slopes, bare rock on the steep faces,
    dry grass at the foot, and haze that thickens with distance (aerial perspective)."""
    NA, NR = 900, 48
    a = np.linspace(0, math.tau, NA, endpoint=False)
    rr = 3800 + (np.linspace(0, 1, NR) ** 1.6) * 9000
    A, Rr = np.meshgrid(a, rr)
    X, Y = np.cos(A) * Rr, np.sin(A) * Rr
    wdir = max(0.0, 1.0)
    w = np.clip(np.cos(A - math.atan2(west[1], west[0])), 0, 1) ** 1.3
    big = 160 + 1050 * w
    ridged = np.zeros_like(X)
    amp, f = 1.0, 1 / 1800.0
    for o in range(6):
        n = _vnoise(X * f + 31.7, Y * f - 12.1, 7 + o)
        ridged += amp * (1 - np.abs(n * 2 - 1)) ** 1.25
        amp *= 0.5
        f *= 2.1
    ridged /= 1.97
    rise = np.clip((Rr - 3800) / 2600, 0, 1) ** 1.5
    Z = big * rise * (0.25 + 0.95 * ridged) - 20
    bm = bmesh.new()
    vs = [[bm.verts.new((cx + X[r, k], cy + Y[r, k], Z[r, k])) for k in range(NA)] for r in range(NR)]
    for r in range(NR - 1):
        for k in range(NA):
            k2 = (k + 1) % NA
            bm.faces.new((vs[r][k], vs[r][k2], vs[r + 1][k2], vs[r + 1][k])).smooth = True

    def b(nt, p):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Position"], sep.inputs[0])
        nsep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Normal"], nsep.inputs[0])
        canopy = _noise(nt, 0.02, 8.0)                                  # tree crowns ~ 25-50 m patches
        forest = _ramp(nt, canopy.outputs["Fac"], (0.02, 0.045, 0.015), (0.07, 0.12, 0.035), 0.35, 0.7)
        rock_f = nt.nodes.new("ShaderNodeMapRange")
        nt.links.new(nsep.outputs["Z"], rock_f.inputs["Value"])
        rock_f.inputs["From Min"].default_value = 0.8
        rock_f.inputs["From Max"].default_value = 0.68
        rn = _noise(nt, 0.01, 6.0)
        rock = _ramp(nt, rn.outputs["Fac"], (0.12, 0.11, 0.1), (0.26, 0.24, 0.21), 0.3, 0.7)
        m1 = nt.nodes.new("ShaderNodeMix")
        m1.data_type = "RGBA"
        nt.links.new(rock_f.outputs[0], m1.inputs["Factor"])
        nt.links.new(forest.outputs["Color"], m1.inputs[6])
        nt.links.new(rock.outputs["Color"], m1.inputs[7])
        low = nt.nodes.new("ShaderNodeMapRange")
        nt.links.new(sep.outputs["Z"], low.inputs["Value"])
        low.inputs["From Min"].default_value = 140
        low.inputs["From Max"].default_value = 40
        gn = _noise(nt, 0.004, 4.0)
        gmul = nt.nodes.new("ShaderNodeMath")
        gmul.operation = "MULTIPLY"
        nt.links.new(low.outputs[0], gmul.inputs[0])
        nt.links.new(gn.outputs["Fac"], gmul.inputs[1])
        g2 = nt.nodes.new("ShaderNodeMath")
        g2.operation = "MULTIPLY"
        nt.links.new(gmul.outputs[0], g2.inputs[0])
        g2.inputs[1].default_value = 1.6
        m2 = nt.nodes.new("ShaderNodeMix")
        m2.data_type = "RGBA"
        nt.links.new(g2.outputs[0], m2.inputs["Factor"])
        nt.links.new(m1.outputs[2], m2.inputs[6])
        m2.inputs[7].default_value = (0.24, 0.19, 0.09, 1)
        nt.links.new(m2.outputs[2], p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = 1.0
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.6
        nt.links.new(canopy.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
        # haze: lit air between the eye and the slope
        camd = nt.nodes.new("ShaderNodeCameraData")
        hz = nt.nodes.new("ShaderNodeMath")
        hz.operation = "MULTIPLY"
        nt.links.new(camd.outputs["View Distance"], hz.inputs[0])
        hz.inputs[1].default_value = -1 / 9500.0
        ex = nt.nodes.new("ShaderNodeMath")
        ex.operation = "EXPONENT"
        nt.links.new(hz.outputs[0], ex.inputs[0])
        inv = nt.nodes.new("ShaderNodeMath")
        inv.operation = "SUBTRACT"
        inv.inputs[0].default_value = 0.9
        nt.links.new(ex.outputs[0], inv.inputs[1])
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = (0.5, 0.57, 0.65, 1)
        em.inputs["Strength"].default_value = 1.0
        mx = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(inv.outputs[0], mx.inputs[0])
        nt.links.new(p.outputs[0], mx.inputs[1])
        nt.links.new(em.outputs[0], mx.inputs[2])
        nt.links.new(mx.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    obj_from_bm(bm, "Hills", [node_mat("Forest Hills", b)])


HOUSE_COLS = [(0.75, 0.72, 0.62), (0.62, 0.72, 0.68), (0.78, 0.62, 0.5), (0.7, 0.68, 0.75), (0.8, 0.76, 0.55),
              (0.58, 0.6, 0.62), (0.85, 0.82, 0.78), (0.6, 0.45, 0.4)]


def house_mat(i, col):
    """Plastered walls with rows of windows (dark glass behind grilles, a sunshade line over each), floor bands
    and rain streaks; the window grid runs along the wall (x + y) and up (z)."""
    def b(nt, p):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Position"], sep.inputs[0])
        add = nt.nodes.new("ShaderNodeMath")
        nt.links.new(sep.outputs["X"], add.inputs[0])
        nt.links.new(sep.outputs["Y"], add.inputs[1])
        comb = nt.nodes.new("ShaderNodeCombineXYZ")
        nt.links.new(add.outputs[0], comb.inputs[0])
        nt.links.new(sep.outputs["Z"], comb.inputs[1])
        br = nt.nodes.new("ShaderNodeTexBrick")
        br.offset = 0.0
        br.inputs["Scale"].default_value = 1.0
        br.inputs["Brick Width"].default_value = 2.6
        br.inputs["Row Height"].default_value = 3.1
        br.inputs["Mortar Size"].default_value = 0.85
        br.inputs["Mortar Smooth"].default_value = 0.0
        br.inputs["Color1"].default_value = (0.04, 0.045, 0.05, 1)
        br.inputs["Color2"].default_value = (0.09, 0.08, 0.07, 1)
        br.inputs["Mortar"].default_value = (*col, 1)
        nt.links.new(comb.outputs[0], br.inputs["Vector"])
        n = _noise(nt, 0.5, 5.0, stretch=(1.0, 1.0, 0.15))
        streak = _ramp(nt, n.outputs["Fac"], (0.62, 0.6, 0.56), (1, 1, 1), 0.3, 0.6)
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = 'MULTIPLY'
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(br.outputs["Color"], mul.inputs[6])
        nt.links.new(streak.outputs["Color"], mul.inputs[7])
        nt.links.new(mul.outputs[2], p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = 0.85
    return node_mat("House %d" % i, b)


def houses(poly, rng, d0, d1, n, base_z, name="Houses"):
    """The city round a lake: flat-roofed plastered houses 1-4 floors, black water tanks on the roofs, some
    half-built with columns sticking up — packed between d0 and d1 m from the water."""
    P = np.asarray(poly)
    lo, hi = P.min(axis=0) - d1, P.max(axis=0) + d1
    q = np.array([[rng.uniform(lo[0], hi[0]), rng.uniform(lo[1], hi[1])] for _ in range(n * 30)])
    dd = sdf(poly, q)
    q = q[(dd > d0) & (dd < d1)][:n]
    bm = bmesh.new()
    nmat = len(HOUSE_COLS)
    for x, y in q:
        w, dep = rng.uniform(7, 12), rng.uniform(8, 14)
        fl = rng.choice((1, 2, 2, 2, 3, 3, 4))
        h = fl * 3.1
        rot = rng.uniform(0, math.tau)
        box(bm, (x, y, base_z + h / 2), (w, dep, h), rot, rng.randrange(nmat))
        box(bm, (x, y, base_z + h + 0.45), (w, dep, 0.9), rot, nmat)          # parapet band (darker)
        c, s_ = math.cos(rot), math.sin(rot)
        tx, ty = rng.uniform(-w / 3, w / 3), rng.uniform(-dep / 3, dep / 3)
        if rng.random() < 0.85:
            cyl(bm, (x + tx * c - ty * s_, y + tx * s_ + ty * c, base_z + h + 0.9),
                (x + tx * c - ty * s_, y + tx * s_ + ty * c, base_z + h + 2.1), 0.6, 10, nmat + 1)
        if rng.random() < 0.25:
            for k in range(4):
                cx_, cy_ = (w / 2 - 0.3) * (1 if k % 2 else -1), (dep / 2 - 0.3) * (1 if k // 2 else -1)
                box(bm, (x + cx_ * c - cy_ * s_, y + cx_ * s_ + cy_ * c, base_z + h + 1.2), (0.3, 0.3, 1.8), rot, nmat + 2)
    mats = [house_mat(i, c) for i, c in enumerate(HOUSE_COLS)]
    mats += [flat_mat("Parapet", (0.42, 0.4, 0.37), 0.9), flat_mat("Sintex Tank", (0.02, 0.02, 0.02), 0.45),
             flat_mat("Bare Concrete", (0.45, 0.44, 0.42), 0.95)]
    return obj_from_bm(bm, name, mats)


_KIT = {}
KIT_SPECS = [("tn_house", 7, 9, 1, 21), ("tn_house", 9, 12, 2, 22), ("tn_house", 12, 14, 3, 23), ("tn_house", 9, 12, 3, 24),
             ("tn_house", 7, 9, 2, 25), ("tn_house", 12, 14, 2, 26), ("commercial", 16, 14, 3, 27), ("commercial", 24, 16, 2, 28)]


def kit_sources(specs=KIT_SPECS):
    """The game's own Kovai buildings (tools/buildings_tn.py: pastel RCC houses with sit-outs, grills, stair
    rooms and tanks; shop rows with signboards), built once each and hidden; instances share their meshes."""
    import buildings as B
    import buildings_tn  # noqa: F401  (registers the Kovai kinds and materials)
    out = []
    for kind, w, d, fl, seed in specs:
        key = (kind, w, d, fl, seed)
        if key not in _KIT or _KIT[key].name not in bpy.data.objects:
            ob, info = B.build(kind, w, d, fl, seed)
            ob.location = (0, 0, -900)
            _KIT[key] = ob
            _KIT[key + ("info",)] = info
        info = _KIT[key + ("info",)]
        out.append((_KIT[key], w + 2 * info.get("side", 2.5), d + info.get("setback", 4.0), kind))
    return out


def kovai_buildings(poly, rng, d0, rows, row_gap, base_z, specs=KIT_SPECS, shop_rows=(0,), density=1.0):
    """Rows of real buildings round the water, fronts (local -y) turned to face it, plot fronts on the row line;
    shop rows on the first (lakeside road) row. Overlaps in tight bends are skipped."""
    src = kit_sources(specs)
    houses_ = [x for x in src if x[3] == "tn_house"]
    shops = [x for x in src if x[3] == "commercial"] or houses_
    placed = []
    grid = {}
    count = 0
    for r in range(rows):
        dist = d0 + r * row_gap
        loop = offset(poly, dist)
        loop = resample(loop, 1.0)
        n = len(loop)
        i = 0
        along_skip = 0.0
        while i < n:
            pool = shops if (r in shop_rows and rng.random() < 0.6) else houses_
            ob, wid, dep, kind = rng.choice(pool)
            p = loop[i]
            q = loop[(i + 3) % n]
            t = (q - p).normalized()
            outward = Vector((t.y, -t.x, 0))
            # outward must point away from the water
            test = np.array([[p.x + outward.x * 3, p.y + outward.y * 3]])
            if sdf(poly, test)[0] < dist:
                outward = -outward
            c = p + outward * (dep / 2) + t * (wid / 2)
            key = (int(c.x // 20), int(c.y // 20))
            clash = any((c - o).length < (wid + w2) * 0.48 for kx in (-1, 0, 1) for ky in (-1, 0, 1)
                        for o, w2 in grid.get((key[0] + kx, key[1] + ky), []))
            if not clash and rng.random() < density:
                rot = math.atan2(-outward.x, outward.y)
                inst = instance(ob, (c.x, c.y, base_z), rot)
                grid.setdefault(key, []).append((c, wid))
                count += 1
            i += max(1, int(wid + rng.uniform(0.0, 2.5)))
    print("BUILDINGS", count, flush=True)
    return count


def road_ring(poly, d0, d1, z, name="Lake road"):
    """An asphalt road round the water between two offsets, with kerbs and a skirt down to the ground."""
    bm = bmesh.new()
    a, b2 = offset(poly, d0), offset(poly, d1)
    va = [bm.verts.new((p.x, p.y, z)) for p in a]
    vb = [bm.verts.new((p.x, p.y, z)) for p in b2]
    sa = [bm.verts.new((p.x, p.y, z - 0.8)) for p in a]
    sb = [bm.verts.new((p.x, p.y, z - 0.8)) for p in b2]
    n = len(va)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((va[i], va[j], vb[j], vb[i]))
        bm.faces.new((sa[i], sa[j], va[j], va[i]))
        bm.faces.new((vb[i], vb[j], sb[j], sb[i]))
    for loop, m in ((a, 1), (b2, 1)):
        for i in range(len(loop)):
            p, q = loop[i], loop[(i + 1) % len(loop)]
            L = (q - p).length
            if L > 0.01:
                box(bm, ((p.x + q.x) / 2, (p.y + q.y) / 2, z + 0.06), (L + 0.1, 0.2, 0.3), math.atan2(q.y - p.y, q.x - p.x), m)
    def asph(nt, p):
        n = _noise(nt, 2.0, 8.0)
        r = _ramp(nt, n.outputs["Fac"], (0.035, 0.035, 0.037), (0.08, 0.08, 0.082), 0.3, 0.75)
        nt.links.new(r.outputs["Color"], p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = 0.85
    return obj_from_bm(bm, name, [node_mat("Asphalt", asph), granite_mat()])


def carved_mat():
    """Carved granite panels: a lotus medallion in every 1.2 x 0.9 m panel (eight petals round a boss, a
    beaded ring), cut in relief — bump only, so it costs no geometry."""
    def b(nt, p):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Position"], sep.inputs[0])
        add = nt.nodes.new("ShaderNodeMath")
        nt.links.new(sep.outputs["X"], add.inputs[0])
        nt.links.new(sep.outputs["Y"], add.inputs[1])

        def wrap(src, period):
            m = nt.nodes.new("ShaderNodeMath")
            m.operation = "WRAP"
            nt.links.new(src, m.inputs[0])
            m.inputs[1].default_value = period
            m.inputs[2].default_value = 0.0
            c = nt.nodes.new("ShaderNodeMath")
            c.operation = "SUBTRACT"
            nt.links.new(m.outputs[0], c.inputs[0])
            c.inputs[1].default_value = period / 2
            return c.outputs[0]
        u = wrap(add.outputs[0], 1.2)
        v = wrap(sep.outputs["Z"], 0.9)
        comb = nt.nodes.new("ShaderNodeCombineXYZ")
        nt.links.new(u, comb.inputs[0])
        nt.links.new(v, comb.inputs[1])
        ln = nt.nodes.new("ShaderNodeVectorMath")
        ln.operation = "LENGTH"
        nt.links.new(comb.outputs[0], ln.inputs[0])
        at = nt.nodes.new("ShaderNodeMath")
        at.operation = "ARCTAN2"
        nt.links.new(v, at.inputs[0])
        nt.links.new(u, at.inputs[1])
        k8 = nt.nodes.new("ShaderNodeMath")
        k8.operation = "MULTIPLY"
        nt.links.new(at.outputs[0], k8.inputs[0])
        k8.inputs[1].default_value = 8.0
        cs = nt.nodes.new("ShaderNodeMath")
        cs.operation = "COSINE"
        nt.links.new(k8.outputs[0], cs.inputs[0])
        petal_r = nt.nodes.new("ShaderNodeMath")                  # petal edge radius 0.22..0.32
        petal_r.operation = "MULTIPLY_ADD"
        nt.links.new(cs.outputs[0], petal_r.inputs[0])
        petal_r.inputs[1].default_value = 0.05
        petal_r.inputs[2].default_value = 0.27
        inside = nt.nodes.new("ShaderNodeMath")
        inside.operation = "LESS_THAN"
        nt.links.new(ln.outputs["Value"], inside.inputs[0])
        nt.links.new(petal_r.outputs[0], inside.inputs[1])
        ring = nt.nodes.new("ShaderNodeMath")                     # beaded ring at r = 0.36
        ring.operation = "COMPARE"
        nt.links.new(ln.outputs["Value"], ring.inputs[0])
        ring.inputs[1].default_value = 0.37
        ring.inputs[2].default_value = 0.02
        boss = nt.nodes.new("ShaderNodeMath")
        boss.operation = "LESS_THAN"
        nt.links.new(ln.outputs["Value"], boss.inputs[0])
        boss.inputs[1].default_value = 0.07
        h1 = nt.nodes.new("ShaderNodeMath")
        nt.links.new(inside.outputs[0], h1.inputs[0])
        nt.links.new(ring.outputs[0], h1.inputs[1])
        h2 = nt.nodes.new("ShaderNodeMath")
        nt.links.new(h1.outputs[0], h2.inputs[0])
        nt.links.new(boss.outputs[0], h2.inputs[1])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 1.0
        bump.inputs["Distance"].default_value = 0.05
        nt.links.new(h2.outputs[0], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
        n = _noise(nt, 18.0, 8.0)
        r = _ramp(nt, n.outputs["Fac"], (0.07, 0.066, 0.062), (0.2, 0.19, 0.175), 0.35, 0.7)
        # dirt collects in the cuts
        cut = nt.nodes.new("ShaderNodeMapRange")
        nt.links.new(h2.outputs[0], cut.inputs["Value"])
        cut.inputs["To Min"].default_value = 0.45
        cut.inputs["To Max"].default_value = 1.0
        mul = nt.nodes.new("ShaderNodeVectorMath")
        mul.operation = "SCALE"
        nt.links.new(r.outputs["Color"], mul.inputs[0])
        nt.links.new(cut.outputs[0], mul.inputs["Scale"])
        nt.links.new(_wet_band(nt, mul.outputs[0], 1.0), p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = 0.8
    return node_mat("Carved Granite", b)


def step_mat():
    """Tank steps: long granite slabs, a joint every 1.4-1.8 m along each step, edges worn paler, dark
    water-stained low down."""
    def b(nt, p):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Position"], sep.inputs[0])
        add = nt.nodes.new("ShaderNodeMath")
        nt.links.new(sep.outputs["X"], add.inputs[0])
        nt.links.new(sep.outputs["Y"], add.inputs[1])
        jn = _noise(nt, 0.7, 2.0)
        jit = nt.nodes.new("ShaderNodeMath")
        jit.operation = "MULTIPLY_ADD"
        nt.links.new(jn.outputs["Fac"], jit.inputs[0])
        jit.inputs[1].default_value = 0.6
        nt.links.new(add.outputs[0], jit.inputs[2])
        fr = nt.nodes.new("ShaderNodeMath")
        fr.operation = "WRAP"
        nt.links.new(jit.outputs[0], fr.inputs[0])
        fr.inputs[1].default_value = 1.6
        fr.inputs[2].default_value = 0.0
        joint = nt.nodes.new("ShaderNodeMath")
        joint.operation = "LESS_THAN"
        nt.links.new(fr.outputs[0], joint.inputs[0])
        joint.inputs[1].default_value = 0.012
        n = _noise(nt, 14.0, 8.0)
        r = _ramp(nt, n.outputs["Fac"], (0.08, 0.075, 0.07), (0.22, 0.205, 0.19), 0.35, 0.7)
        dark = nt.nodes.new("ShaderNodeMix")
        dark.data_type = "RGBA"
        nt.links.new(joint.outputs[0], dark.inputs["Factor"])
        nt.links.new(r.outputs["Color"], dark.inputs[6])
        dark.inputs[7].default_value = (0.02, 0.02, 0.02, 1)
        st = _noise(nt, 0.25, 4.0, stretch=(1.0, 1.0, 6.0))
        stain = _ramp(nt, st.outputs["Fac"], (0.55, 0.55, 0.5), (1, 1, 1), 0.35, 0.6)
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = 'MULTIPLY'
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(dark.outputs[2], mul.inputs[6])
        nt.links.new(stain.outputs["Color"], mul.inputs[7])
        nt.links.new(_wet_band(nt, mul.outputs[2], 1.1), p.inputs["Base Color"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.4
        nt.links.new(joint.outputs[0], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
        p.inputs["Roughness"].default_value = 0.8
    return node_mat("Step Granite", b)


def pillar(bm, x, y, z0, h, mat=0):
    """A Dravidian mandapam pillar: square base block, octagonal shaft, a square band (sadurам) midway,
    octagon again, a cushion capital and a stepped pothigai bracket reaching out four ways."""
    box(bm, (x, y, z0 + 0.3), (0.64, 0.64, 0.6), 0.0, mat)
    box(bm, (x, y, z0 + 0.64), (0.56, 0.56, 0.08), 0.0, mat)
    a = z0 + 0.68
    seg = (h - 1.5) / 2
    cyl(bm, (x, y, a), (x, y, a + seg), 0.24, 8, mat)
    box(bm, (x, y, a + seg + 0.2), (0.5, 0.5, 0.4), 0.0, 2)
    cyl(bm, (x, y, a + seg + 0.4), (x, y, a + 2 * seg + 0.4), 0.24, 8, mat)
    top = a + 2 * seg + 0.4
    cyl(bm, (x, y, top), (x, y, top + 0.14), 0.33, 12, mat)
    box(bm, (x, y, top + 0.22), (0.6, 0.6, 0.12), 0.0, mat)
    for k, (L, zz) in enumerate(((0.9, 0.36), (1.25, 0.48))):
        box(bm, (x, y, top + zz), (L, 0.32, 0.12), 0.0, mat)
        box(bm, (x, y, top + zz), (0.32, L, 0.12), 0.0, mat)
    return top + 0.54


def mandapam(bm, z_bed, cx=0.0, cy=0.0):
    """The neerazhi mandapam: a moulded plinth (upanam, jagati, a rounded kumudam, pattikai, carved panels),
    12 pillars, beams, a roof slab with a curved kapotam cornice, a two-tier vimana with corner shrines and
    kudu niches, a domed sikharam and a kalasam."""
    box(bm, (cx, cy, (z_bed + 0.15) / 2), (9.8, 9.8, 0.15 - z_bed), 0.0, 0)                       # upanam (into the water)
    box(bm, (cx, cy, 0.3), (9.4, 9.4, 0.3), 0.0, 0)                                                  # jagati
    for sx, sy, L, ang in ((0, 4.55, 9.1, 0), (0, -4.55, 9.1, 0), (4.55, 0, 9.1, 1), (-4.55, 0, 9.1, 1)):
        a = (cx + sx - (L / 2 if not ang else 0), cy + sy - (L / 2 if ang else 0), 0.6)
        b2 = (cx + sx + (L / 2 if not ang else 0), cy + sy + (L / 2 if ang else 0), 0.6)
        cyl(bm, a, b2, 0.16, 10, 0)                                                                 # kumudam
    box(bm, (cx, cy, 0.62), (9.0, 9.0, 0.3), 0.0, 0)
    box(bm, (cx, cy, 0.86), (9.3, 9.3, 0.18), 0.0, 0)                                                # pattikai
    box(bm, (cx, cy, 1.0), (9.0, 9.0, 0.1), 0.0, 3)                                                  # floor
    tops = []
    for i in range(4):
        for j in range(4):
            if 0 < i < 3 and 0 < j < 3:
                continue
            tops.append(pillar(bm, cx - 3.6 + i * 2.4, cy - 3.6 + j * 2.4, 1.05, 3.0))
    zt = max(tops)
    for k in range(4):                                                                               # uthiram beams
        o = -3.6 + k * 2.4
        box(bm, (cx + o, cy, zt + 0.12), (0.34, 7.9, 0.28), 0.0, 0)
        box(bm, (cx, cy + o, zt + 0.12), (7.9, 0.34, 0.28), 0.0, 0)
    roof = zt + 0.26
    box(bm, (cx, cy, roof + 0.12), (9.0, 9.0, 0.24), 0.0, 0)
    for sx, sy, L, ang in ((0, 4.6, 9.4, 0), (0, -4.6, 9.4, 0), (4.6, 0, 9.4, 1), (-4.6, 0, 9.4, 1)):
        a = (cx + sx - (L / 2 if not ang else 0), cy + sy - (L / 2 if ang else 0), roof + 0.2)
        b2 = (cx + sx + (L / 2 if not ang else 0), cy + sy + (L / 2 if ang else 0), roof + 0.2)
        cyl(bm, a, b2, 0.3, 12, 0)                                                                   # kapotam
    z = roof + 0.5
    for tier, w in enumerate((6.4, 4.6)):
        h = 1.3 - tier * 0.2
        box(bm, (cx, cy, z + h / 2), (w, w, h), 0.0, 2)
        for sx in (-1, 1):
            for sy in (-1, 1):                                                                       # karnakoota corner shrines
                px, py = cx + sx * (w / 2 - 0.45), cy + sy * (w / 2 - 0.45)
                box(bm, (px, py, z + h + 0.3), (0.8, 0.8, 0.6), 0.0, 0)
                cyl(bm, (px, py, z + h + 0.6), (px, py, z + h + 0.95), 0.34, 10, 0)
        for k in range(4):                                                                            # kudu niches
            for side in range(4):
                c_, s_ = [(1, 0), (0, 1), (-1, 0), (0, -1)][side]
                o = -w / 2 + (k + 0.5) * w / 4
                px = cx + c_ * (w / 2 + 0.02) + (-s_) * o
                py = cy + s_ * (w / 2 + 0.02) + c_ * o
                box(bm, (px, py, z + h * 0.5), (0.36 if s_ else 0.06, 0.06 if s_ else 0.36, h * 0.5), 0.0, 1)
        box(bm, (cx, cy, z + h + 0.07), (w + 0.3, w + 0.3, 0.14), 0.0, 0)
        z += h + 0.14
    cyl(bm, (cx, cy, z), (cx, cy, z + 0.6), 1.2, 16, 0)                                              # griva
    dome_z = z + 0.6
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=1.0,
                              matrix=__import__("mathutils").Matrix.Translation((cx, cy, dome_z)) @
                              __import__("mathutils").Matrix.Diagonal((1.55, 1.55, 1.05, 1.0)))
    cyl(bm, (cx, cy, dome_z + 1.0), (cx, cy, dome_z + 1.9), 0.18, 10, 4)                              # kalasam
    bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=0.26,
                              matrix=__import__("mathutils").Matrix.Translation((cx, cy, dome_z + 1.35)))


def deepa_sthambam(bm, x, y, z0, mat=0):
    """The lamp pillar before a temple: a stepped square base, a tall octagonal shaft with banded rings, lamp
    arms near the top, a small pavilion cap."""
    for k, w in enumerate((1.8, 1.4, 1.0)):
        box(bm, (x, y, z0 + 0.2 + k * 0.4), (w, w, 0.4), 0.0, mat)
    cyl(bm, (x, y, z0 + 1.2), (x, y, z0 + 8.5), 0.22, 8, mat)
    for k in range(5):
        cyl(bm, (x, y, z0 + 2.0 + k * 1.4), (x, y, z0 + 2.12 + k * 1.4), 0.3, 8, mat)
    for k in range(4):
        a = k * math.pi / 2
        cyl(bm, (x, y, z0 + 7.6), (x + math.cos(a) * 0.9, y + math.sin(a) * 0.9, z0 + 7.9), 0.05, 6, mat)
    box(bm, (x, y, z0 + 8.7), (0.8, 0.8, 0.4), 0.0, mat)
    cyl(bm, (x, y, z0 + 8.9), (x, y, z0 + 9.3), 0.32, 8, mat)


def kaavi_mat():
    """Temple compound wall: vertical red-ochre (kaavi) and white lime stripes, weathered."""
    def b(nt, p):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Position"], sep.inputs[0])
        add = nt.nodes.new("ShaderNodeMath")
        nt.links.new(sep.outputs["X"], add.inputs[0])
        nt.links.new(sep.outputs["Y"], add.inputs[1])
        sn = nt.nodes.new("ShaderNodeMath")
        sn.operation = "SINE"
        mulx = nt.nodes.new("ShaderNodeMath")
        mulx.operation = "MULTIPLY"
        nt.links.new(add.outputs[0], mulx.inputs[0])
        mulx.inputs[1].default_value = math.pi / 0.5
        nt.links.new(mulx.outputs[0], sn.inputs[0])
        r = _ramp(nt, sn.outputs[0], (0.85, 0.82, 0.74), (0.5, 0.09, 0.04), 0.48, 0.52)
        n = _noise(nt, 1.2, 6.0)
        dirt = _ramp(nt, n.outputs["Fac"], (0.6, 0.55, 0.48), (1, 1, 1), 0.3, 0.7)
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = 'MULTIPLY'
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(r.outputs["Color"], mul.inputs[6])
        nt.links.new(dirt.outputs["Color"], mul.inputs[7])
        nt.links.new(mul.outputs[2], p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = 0.9
    return node_mat("Kaavi Wall", b)


def gopuram(bm, cx, cy, base_z, w=14.0, d=8.0, tiers=6, mat_stone=0, mat_paint=1, mat_gold=2, mat_dark=3):
    """A temple gateway tower: a granite base with a dark doorway, then tiers narrowing upward, each with a
    cornice and a row of little shrine niches, painted; a barrel-vaulted crown with five gilded kalasams."""
    box(bm, (cx, cy, base_z + 2.5), (w, d, 5.0), 0.0, mat_stone)
    box(bm, (cx, cy - d / 2 - 0.01, base_z + 2.0), (2.6, 0.2, 4.0), 0.0, mat_dark)
    z = base_z + 5.0
    tw, td = w, d
    for t in range(tiers):
        th = 3.0 - t * 0.2
        tier_mat = (mat_paint, 7, 8)[t % 3]
        box(bm, (cx, cy, z + th / 2), (tw, td, th), 0.0, tier_mat)
        box(bm, (cx, cy, z + th + 0.12), (tw + 0.5, td + 0.5, 0.24), 0.0, mat_paint)
        nn = max(2, int(tw / 1.6))
        for k in range(nn):
            x = cx - tw / 2 + (k + 0.5) * tw / nn
            for sgn in (-1, 1):
                box(bm, (x, cy + sgn * (td / 2 + 0.15), z + th * 0.55), (0.7, 0.3, th * 0.6), 0.0, 4 + (k + t) % 3)
                box(bm, (x, cy + sgn * (td / 2 + 0.32), z + th * 0.55), (0.35, 0.05, th * 0.35), 0.0, mat_dark)
        z += th + 0.24
        tw *= 0.86
        td *= 0.8
    # barrel-vault crown
    seg = 10
    r = td / 2 + 0.4
    for k in range(seg):
        a0, a1 = math.pi * k / seg, math.pi * (k + 1) / seg
        vs = []
        for x in (cx - tw / 2 - 0.4, cx + tw / 2 + 0.4):
            for a in (a0, a1):
                vs.append(bm.verts.new((x, cy + math.cos(a) * r, z + math.sin(a) * r * 1.3)))
        bm.faces.new((vs[0], vs[1], vs[3], vs[2])).material_index = mat_paint
    for k in range(5):
        x = cx - tw / 2 + (k + 0.5) * tw / 5
        cyl(bm, (x, cy, z + r * 1.3 - 0.1), (x, cy, z + r * 1.3 + 0.9), 0.18, 8, mat_gold)
    return z + r * 1.3 + 0.9


def scatter_edge(poly, src_list, every, offset_m, rng, jitter=1.5, prob=1.0, rot=True, scale=(0.8, 1.2), z=0.0):
    loop = resample(offset(poly, offset_m), every)
    obs = []
    for p in loop:
        if rng.random() > prob:
            continue
        src = rng.choice(src_list)
        loc = (p.x + rng.uniform(-jitter, jitter), p.y + rng.uniform(-jitter, jitter), z)
        obs.append(instance(src, loc, rng.uniform(0, math.tau) if rot else 0.0, rng.uniform(*scale)))
    return obs


def ground_z(ob, x, y):
    """Height of the terrain under (x, y), by ray cast from above."""
    dg = bpy.context.evaluated_depsgraph_get()
    hit, loc, *_ = bpy.context.scene.ray_cast(dg, Vector((x, y, 200)), Vector((0, 0, -1)))
    return loc.z if hit else 0.0


# ----------------------------------------------------------------------------- the three designs
def lake(rng):
    """Valaan Kulam (the real outline): a bund with stone pitching, a walkway with railings, lamps, benches."""
    poly = json.load(open(SHAPES))["Valaan Kulam"]
    SLOPE, BANK = 5.0, 2.6
    WALK0, WALK1 = SLOPE + 0.4, SLOPE + 4.4                      # the walkway on top of the bund

    def zones(d):
        if d < 0.15:
            return 0
        if d < SLOPE:
            return 1
        return 3
    ground, (lo, hi) = terrain(poly, 2.0, 340, BANK, SLOPE, 2.5, rng, "Lake ground",
                               [ground_mat("Lake Bed", (0.12, 0.09, 0.06), (0.1, 0.1, 0.05), (0.05, 0.04, 0.03)),
                                stone_pitch_mat(), paver_mat(),
                                ground_mat("Bank Soil", (0.2, 0.11, 0.06), (0.11, 0.14, 0.045))], zones)
    water_body(poly, lo, hi, 6.0, (0.45, 0.55, 0.3), 0.8, 0.32, 3.0)
    # the walkway: pavers between two offset outlines, a granite kerb on each side
    bm = bmesh.new()
    o2 = offset(poly, WALK1)
    inner_l = offset(poly, WALK0)
    zt = BANK + 0.12
    vi = [bm.verts.new((p.x, p.y, zt)) for p in inner_l]
    vo = [bm.verts.new((p.x, p.y, zt)) for p in o2]
    for i in range(len(vi)):
        j = (i + 1) % len(vi)
        bm.faces.new((vi[i], vi[j], vo[j], vo[i]))
    for loop in (inner_l, o2):
        for i in range(len(loop)):
            a, b = loop[i], loop[(i + 1) % len(loop)]
            L = (b - a).length
            if L < 0.01:
                continue
            box(bm, ((a.x + b.x) / 2, (a.y + b.y) / 2, zt + 0.05), (L + 0.2, 0.25, 0.35), math.atan2(b.y - a.y, b.x - a.x), 1)
    obj_from_bm(bm, "Walkway", [paver_mat(), granite_mat()])
    # railings: posts every 2 m on the water side of the walkway, two rails; kerb on the land side
    bm = bmesh.new()
    rail = resample(offset(poly, WALK0 + 0.2), 2.0)
    for i, p in enumerate(rail):
        q = rail[(i + 1) % len(rail)]
        if (q - p).length > 6:
            continue
        z = BANK + 0.12
        box(bm, (p.x, p.y, z + 0.5), (0.08, 0.08, 1.0), math.atan2(q.y - p.y, q.x - p.x))
        for zz in (0.45, 0.95):
            cyl(bm, (p.x, p.y, z + zz), (q.x, q.y, z + zz), 0.025, 6)
    obj_from_bm(bm, "Railing", [flat_mat("Railing Paint", (0.15, 0.32, 0.4), 0.4, 0.3)])
    bm = bmesh.new()
    lamps = resample(offset(poly, WALK1 - 0.3), 24.0)
    for p in lamps:
        z = BANK + 0.12
        cyl(bm, (p.x, p.y, z), (p.x, p.y, z + 4.2), 0.06, 8)
        box(bm, (p.x, p.y, z + 4.3), (0.35, 0.35, 0.18))
    obj_from_bm(bm, "Lamps", [flat_mat("Lamp Grey", (0.3, 0.31, 0.33), 0.4, 0.6)])
    bm = bmesh.new()
    for p in resample(offset(poly, WALK1 - 0.8), 37.0):
        z = BANK + 0.12
        box(bm, (p.x, p.y, z + 0.42), (1.6, 0.42, 0.06))
        box(bm, (p.x, p.y, z + 0.2), (0.2, 0.38, 0.4))
    obj_from_bm(bm, "Benches", [granite_mat()])
    # plants
    reeds = [hide(reed_clump(s)) for s in (1, 2, 3)]
    hyac = [hide(hyacinth_patch(s, rng.uniform(2.5, 5.0))) for s in (1, 2, 3)]
    for o in scatter_edge(poly, reeds, 3.5, -1.0, rng, 1.2, prob=0.55):
        o.location.z = -0.1
    for o in scatter_edge(poly, hyac, 22.0, -rng.uniform(4, 9), rng, 3.0, prob=0.7, scale=(0.8, 1.6)):
        o.location.z = 0.0
    trees = [hide(VG.raintree(2)), hide(VG.neem(3)), hide(VG.neem(4))]
    for o in scatter_edge(poly, trees, 16.0, WALK1 + 4.5, rng, 2.5, prob=0.85, scale=(0.9, 1.3)):
        o.location.z = BANK - 0.3
    scrub = [hide(prosopis(s)) for s in (1, 2, 3)]
    for o in scatter_edge(poly, scrub, 9.0, WALK1 + 12.0, rng, 4.0, prob=0.6, scale=(0.8, 1.3)):
        o.location.z = BANK - 0.3
    grass_field(poly, BANK, SLOPE, 2.5, rng, WALK1 + 0.6, WALK1 + 30.0, 9000, "Bank grass")
    grass_field(poly, BANK, SLOPE, 2.5, rng, 0.3, 1.6, 2500, "Edge weeds")
    birds = [hide(egret(1, 0)), hide(egret(2, 1))]
    flock(poly, rng, 26, birds)
    road_ring(poly, WALK1 + 17.0, WALK1 + 25.0, BANK - 0.17)
    kovai_buildings(poly, rng, WALK1 + 27.0, 6, 30.0, BANK - 0.17)
    c = np.asarray(poly).mean(axis=0)
    hills(c[0], c[1], rng)
    return poly, BANK, WALK0, WALK1


def temple():
    """A theppakulam: 44 m square, 12 granite steps down to the water on all sides (and on below it), a pillared
    mandapam with a stepped vimana in the middle, a parapet with a gate, black water stains at the waterline."""
    S, STEPS, RISE, TREAD = 44.0, 16, 0.3, 0.75
    top = 12 * RISE                                                  # water at z = 0, the rim at `top`
    BOT = top - STEPS * RISE - 0.2
    bm = bmesh.new()

    def ring(half, inner, z0, z1, mat=0):
        h = z1 - z0
        zc = (z0 + z1) / 2
        w = half - inner
        box(bm, (0, half - w / 2, zc), (2 * half, w, h), 0.0, mat)
        box(bm, (0, -(half - w / 2), zc), (2 * half, w, h), 0.0, mat)
        box(bm, (half - w / 2, 0, zc), (w, 2 * inner, h), 0.0, mat)
        box(bm, (-(half - w / 2), 0, zc), (w, 2 * inner, h), 0.0, mat)
    for i in range(STEPS):
        half = S / 2 - i * TREAD
        z = top - i * RISE
        ring(half, half - TREAD, BOT, z, 3)
        e = half - TREAD + 0.03                                         # a rounded nosing on every step
        for (ax, ay), (bx, by) in (((-e, -e), (e, -e)), ((e, -e), (e, e)), ((e, e), (-e, e)), ((-e, e), (-e, -e))):
            cyl(bm, (ax, ay, z - 0.05), (bx, by, z - 0.05), 0.05, 6, 3)
    box(bm, (0, 0, BOT - 0.1), (S, S, 0.2))
    # rim: a 3 m granite apron, a parapet 0.9 m with a gate gap on the south
    R = S / 2 + 3.0
    ring(R, S / 2, top - 0.3, top)
    for side in range(4):
        L = 2 * R
        if side == 3:
            for k in (-1, 1):
                box(bm, (k * (L / 4 + 1.5), -R + 0.2, top + 0.45), (L / 2 - 3, 0.4, 0.9), 0.0, 2)
                box(bm, (k * (L / 4 + 1.5), -R + 0.2, top + 0.95), (L / 2 - 2.8, 0.55, 0.12), 0.0, 0)
            for k in (-1, 1):
                pillar(bm, k * 1.6, -R + 0.2, top, 3.2)
            box(bm, (0, -R + 0.2, top + 3.9), (4.4, 0.9, 0.4))
        else:
            c, s_ = [(1, 0), (0, 1), (-1, 0)][side]
            box(bm, (c * (R - 0.2), s_ * (R - 0.2), top + 0.45), (0.4 if c else L, L if c else 0.4, 0.9), 0.0, 2)
            box(bm, (c * (R - 0.2), s_ * (R - 0.2), top + 0.95), (0.55 if c else L + 0.2, L + 0.2 if c else 0.55, 0.12), 0.0, 0)
    mandapam(bm, BOT)
    deepa_sthambam(bm, -6.0, -R - 4.0, top - 0.05)
    obj_from_bm(bm, "Theppakulam", [granite_mat(), flat_mat("Niche Shadow", (0.03, 0.028, 0.025), 0.9), carved_mat(),
                                     step_mat(), flat_mat("Kalasam", (0.75, 0.55, 0.15), 0.3, 0.9)])
    sq = [(-S / 2, -S / 2), (S / 2, -S / 2), (S / 2, S / 2), (-S / 2, S / 2)]
    water_body(sq, (-S / 2 + 0.01, -S / 2 + 0.01), (S / 2 - 0.01, S / 2 - 0.01), 2.0, (0.35, 0.6, 0.3), 1.4, 0.55, 4.6)
    # the temple compound: a kaavi-striped wall 12 m out, a gopuram on the north side
    bm = bmesh.new()
    W = R + 12.0
    for side in range(4):
        c, s_ = [(1, 0), (0, 1), (-1, 0), (0, -1)][side]
        if side == 1:
            for k in (-1, 1):
                box(bm, (k * (W / 2 + 4.5), W, top + 1.1), (W - 9, 0.5, 2.2))
        else:
            box(bm, (c * W, s_ * W, top + 1.1), (0.5 if c else 2 * W, 2 * W if c else 0.5, 2.2))
    obj_from_bm(bm, "Kaavi wall", [kaavi_mat()])
    bm = bmesh.new()
    gopuram(bm, 0.0, W, top)
    obj_from_bm(bm, "Gopuram", [granite_mat(), flat_mat("Gopuram Paint", (0.72, 0.66, 0.55), 0.85),
                                 flat_mat("Kalasam", (0.75, 0.55, 0.15), 0.3, 0.9), flat_mat("Niche", (0.08, 0.06, 0.05), 0.9),
                                 flat_mat("Figure Blue", (0.25, 0.4, 0.6), 0.8), flat_mat("Figure Pink", (0.75, 0.42, 0.42), 0.8),
                                 flat_mat("Figure Green", (0.3, 0.52, 0.34), 0.8), flat_mat("Tier Blue", (0.55, 0.65, 0.72), 0.85),
                                 flat_mat("Tier Pink", (0.78, 0.6, 0.58), 0.85)])
    rect = [(-W - 6, -W - 6), (W + 6, -W - 6), (W + 6, W + 6), (-W - 6, W + 6)]
    road_ring(rect, 0.5, 8.5, top - 0.02, "Car street")
    kovai_buildings(rect, random.Random(9), 10.0, 4, 30.0, top - 0.02, shop_rows=(0,))
    hills(0, 0, random.Random(2))
    lp = lotus_patch(7, 3.0, 1.4)
    lp.location = (-11, 9, 0)
    bm = bmesh.new()
    for c, size in (((0, R + 100), (400, 200)), ((0, -R - 100), (400, 200)), ((R + 100, 0), (200, 2 * R)), ((-R - 100, 0), (200, 2 * R))):
        box(bm, (c[0], c[1], top - 0.55), (size[0], size[1], 1.0))
    obj_from_bm(bm, "Temple ground", [ground_mat("Temple Soil", (0.22, 0.13, 0.07), (0.13, 0.14, 0.05))])
    rng = random.Random(4)
    trees = [hide(VG.neem(5)), hide(VG.raintree(3))]
    for k in range(10):
        a = k / 10 * math.tau + rng.uniform(-0.2, 0.2)
        r = rng.uniform(34, 46)
        instance(rng.choice(trees), (math.cos(a) * r, math.sin(a) * r, top - 0.05), rng.uniform(0, 6.28), rng.uniform(1.0, 1.3))
    pal = palmyra(3)
    pal.location = (32, 28, top - 0.05)
    return top


def kuttai(rng):
    """Kaliyaperumal Kuttai (the real outline): mud banks, reeds, lotus, hyacinth, palmyra palms, a neem."""
    poly = json.load(open(SHAPES))["Kaliyaperumal Kuttai"]
    SLOPE, BANK = 9.0, 1.6

    def zones(d):
        if d < 0.2:
            return 0
        if d < SLOPE * 0.7:
            return 1
        return 2
    ground, (lo, hi) = terrain(poly, 2.5, 180, BANK, SLOPE, 1.5, rng, "Kuttai ground",
                               [ground_mat("Pond Bed", (0.1, 0.08, 0.05), (0.08, 0.08, 0.04), (0.05, 0.04, 0.03)),
                                ground_mat("Pond Bank", (0.17, 0.1, 0.055), (0.1, 0.13, 0.045), (0.06, 0.045, 0.03)),
                                ground_mat("Field Soil", (0.21, 0.12, 0.06), (0.12, 0.15, 0.05))], zones)
    water_body(poly, lo, hi, 4.0, (0.55, 0.5, 0.3), 1.1, 0.28, 2.0)
    reeds = [hide(reed_clump(s)) for s in (4, 5, 6)]
    for o in scatter_edge(poly, reeds, 2.5, -0.8, rng, 1.5, prob=0.7):
        o.location.z = -0.1
    lotus = [hide(lotus_patch(s, rng.uniform(4, 7))) for s in (1, 2)]
    for o in scatter_edge(poly, lotus, 30.0, -rng.uniform(8, 14), rng, 4.0, prob=0.8, scale=(1.0, 1.6)):
        o.location.z = 0.0
    hyac = [hide(hyacinth_patch(s + 10, rng.uniform(3, 6))) for s in (1, 2)]
    for o in scatter_edge(poly, hyac, 40.0, -rng.uniform(5, 10), rng, 3.0, prob=0.7, scale=(1.0, 1.8)):
        o.location.z = 0.0
    palms = [hide(palmyra(s)) for s in (1, 2)]
    for o in scatter_edge(poly, palms, 14.0, SLOPE + 2.0, rng, 3.0, prob=0.6, scale=(0.9, 1.15)):
        o.location.z = BANK - 0.35
    trees = [hide(VG.neem(6)), hide(VG.bush(1)), hide(VG.bush(2))]
    for o in scatter_edge(poly, trees, 9.0, SLOPE + 6.0, rng, 3.0, prob=0.4, scale=(0.9, 1.3)):
        o.location.z = BANK - 0.35
    scrub = [hide(prosopis(s)) for s in (4, 5, 6)]
    for o in scatter_edge(poly, scrub, 4.0, SLOPE + 3.0, rng, 3.5, prob=0.75, scale=(0.8, 1.4)):
        o.location.z = BANK - 0.35
    grass_field(poly, BANK, SLOPE, 1.5, rng, 0.6, SLOPE + 40.0, 14000, "Bank grass")
    birds = [hide(egret(3, 0)), hide(egret(4, 1))]
    flock(poly, rng, 18, birds)
    kovai_buildings(poly, rng, SLOPE + 80.0, 2, 40.0, BANK - 0.3,
                    specs=[s_ for s_ in KIT_SPECS if s_[0] == "tn_house"], shop_rows=(), density=0.25)
    c = np.asarray(poly).mean(axis=0)
    hills(c[0], c[1], rng)
    return poly, BANK, SLOPE


# ----------------------------------------------------------------------------- render
def setup(samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _M.clear()
    VG._M.clear()
    _KIT.clear()
    import buildings as B
    B._M.clear()
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = 'GPU'
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.exposure = -0.6
    sc.render.image_settings.file_format = 'JPEG'
    sc.render.image_settings.quality = 90
    sc.world = bpy.data.worlds.new("Sky")
    sc.world.use_nodes = True
    sky = sc.world.node_tree.nodes.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_elevation = math.radians(38)
    sky.sun_rotation = math.radians(-60)
    for k, v in (("aerosol_density", 3.0), ("dust_density", 3.0), ("air_density", 1.3)):
        if hasattr(sky, k):
            setattr(sky, k, v)
    sc.world.node_tree.links.new(sky.outputs[0], sc.world.node_tree.nodes["Background"].inputs[0])
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.12
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(1.0)
    sun.rotation_euler = (math.radians(52), 0, math.radians(-150))
    sc.collection.objects.link(sun)
    return sc


def shoot(sc, out, loc, target, lens=24):
    cam = bpy.data.objects.get("Cam")
    if cam is None:
        cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
    cam.location = loc
    cam.data.lens = lens
    cam.data.clip_end = 20000
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("RENDER", out, flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = os.path.abspath(args[args.index("--out") + 1]) if "--out" in args else os.path.join(HERE, "..", "previews", "ponds")
    samples = int(args[args.index("--samples") + 1]) if "--samples" in args else 64
    only = args[args.index("--only") + 1] if "--only" in args else None
    os.makedirs(out, exist_ok=True)
    if only in (None, "lake"):
        sc = setup(samples)
        poly, bank, w0, w1 = lake(random.Random(3))
        walk = resample(offset(poly, (w0 + w1) / 2), 5.0)
        # on the walkway, looking along it and across the water
        p, q = walk[len(walk) // 3], walk[len(walk) // 3 + 4]
        inward = (Vector(sum((Vector((x, y, 0)) for x, y in poly), Vector())) / len(poly) - p).normalized()
        shoot(sc, os.path.join(out, "lake_walkway.jpg"), (p.x, p.y, bank + 0.12 + 1.65),
              (q.x + inward.x * 25, q.y + inward.y * 25, bank - 1.2), 22)
        wat = resample(offset(poly, -22.0), 5.0)
        r = wat[len(wat) // 3 + 2]
        near = min(walk, key=lambda w: (w - r).length)
        shoot(sc, os.path.join(out, "lake_bund.jpg"), (r.x, r.y, 1.4), (near.x, near.y, bank - 0.8), 26)
    if only in (None, "temple"):
        sc = setup(samples)
        top = temple()
        shoot(sc, os.path.join(out, "temple_tank.jpg"), (-21.0, -23.5, top + 1.7), (1.0, 2.0, 1.0), 22)
        # down on the steps by the water: slab joints, nosings, the carved parapet behind, the mandapam ahead
        shoot(sc, os.path.join(out, "temple_steps.jpg"), (-7.0, -16.0, top - 7 * 0.3 + 1.6), (1.5, 0.0, 3.2), 26)
        shoot(sc, os.path.join(out, "temple_parapet.jpg"), (4.0, -18.0, top - 2 * 0.3 + 1.5), (-2.0, -25.0, top + 0.6), 30)
    if only in (None, "kuttai"):
        sc = setup(samples)
        poly, bank, slope = kuttai(random.Random(5))
        edge = resample(offset(poly, slope * 0.5), 5.0)
        p = edge[len(edge) // 2]
        cen = Vector(sum((Vector((x, y, 0)) for x, y in poly), Vector())) / len(poly)
        inward = (cen - p).normalized()
        shoot(sc, os.path.join(out, "village_kuttai.jpg"), (p.x, p.y, bank * 0.5 + 1.6),
              (p.x + inward.x * 60, p.y + inward.y * 60, 0.5), 24)


if __name__ == "__main__":
    main()
