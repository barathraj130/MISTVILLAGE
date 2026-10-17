"""
Natural trees and bushes for the Coimbatore streets: real branching limbs on a flared, textured trunk, and leaf
sprays painted per species (tools/leaf_atlas.py — compound neem leaves, fern-like rain-tree and gulmohar fronds,
gulmohar flowers, hibiscus, croton, ixora) on folded cards; leaves deep in the crown are darker. Our own designs.

  neem       a straight trunk forking into a rounded crown of fine leaves
  raintree   a short trunk splitting low into long spreading limbs, a wide flat umbrella canopy
  gulmohar   a spreading crown with red-orange flower clusters among feathery leaves
  palm       coconut palm (tools/trees_tn.py)
  bush       a leafy mound: hibiscus, croton (green-yellow-red) or ixora with red flower heads
  grass      a tuft of curved blades, for scattering over open ground

    Blender -b --python tools/vegetation.py -- --preview out.jpg
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

_M = {}
DETAIL = 1.0          # < 1: the far version for the game (fewer, larger leaf sprays, no twigs)


ATLAS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "leaves")


def _image(name):
    path = os.path.abspath(os.path.join(ATLAS, name + ".png"))
    for im in bpy.data.images:
        if im.filepath == path:
            return im
    return bpy.data.images.load(path)


def leaf_mat(name, atlas, trans=0.3):
    """Leaf sprays: a painted atlas (tools/leaf_atlas.py), cut out by its alpha; the vertex colour darkens the
    leaves inside the crown (r = light, 0 deep inside .. 1 on the sunny outside) and shifts some towards
    yellow-green (g); lit through from behind."""
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    if hasattr(m, "blend_method"):
        m.blend_method = 'CLIP'
    nt = m.node_tree
    out = nt.nodes["Material Output"]
    p = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = _image(atlas)
    tex.interpolation = 'Cubic'
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    sv = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(vc.outputs["Color"], sv.inputs[0])
    light = nt.nodes.new("ShaderNodeMapRange")
    nt.links.new(sv.outputs[0], light.inputs["Value"])
    light.inputs["To Min"].default_value = 0.5
    light.inputs["To Max"].default_value = 1.35
    warm = nt.nodes.new("ShaderNodeMix")
    warm.data_type = "RGBA"
    warm.inputs[6].default_value = (1, 1, 1, 1)
    warm.inputs[7].default_value = (1.2, 1.08, 0.6, 1)
    gk = nt.nodes.new("ShaderNodeMath")
    gk.operation = "MULTIPLY"
    nt.links.new(sv.outputs[1], gk.inputs[0])
    gk.inputs[1].default_value = 0.45
    nt.links.new(gk.outputs[0], warm.inputs["Factor"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = 'MULTIPLY'
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(tex.outputs["Color"], mul.inputs[6])
    nt.links.new(warm.outputs[2], mul.inputs[7])
    col = nt.nodes.new("ShaderNodeVectorMath")
    col.operation = "SCALE"
    nt.links.new(mul.outputs[2], col.inputs[0])
    nt.links.new(light.outputs[0], col.inputs["Scale"])
    nt.links.new(col.outputs[0], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.5
    tr = nt.nodes.new("ShaderNodeBsdfTranslucent")
    nt.links.new(col.outputs[0], tr.inputs["Color"])
    ms = nt.nodes.new("ShaderNodeMixShader")
    ms.inputs[0].default_value = trans
    nt.links.new(p.outputs[0], ms.inputs[1])
    nt.links.new(tr.outputs[0], ms.inputs[2])
    tp = nt.nodes.new("ShaderNodeBsdfTransparent")
    ma = nt.nodes.new("ShaderNodeMixShader")
    cut = nt.nodes.new("ShaderNodeMath")
    cut.operation = "GREATER_THAN"
    nt.links.new(tex.outputs["Alpha"], cut.inputs[0])
    cut.inputs[1].default_value = 0.5
    nt.links.new(cut.outputs[0], ma.inputs[0])
    nt.links.new(tp.outputs[0], ma.inputs[1])
    nt.links.new(ms.outputs[0], ma.inputs[2])
    nt.links.new(ma.outputs[0], out.inputs["Surface"])
    _M[name] = m
    return m


def bark_mat():
    """Bark from the painted bark texture (fissures run along the trunk), bumped by its own brightness."""
    if "bark" in _M:
        return _M["bark"]
    m = bpy.data.materials.new("Bark")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = _image("bark")
    nt.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    bm = nt.nodes.new("ShaderNodeBump")
    nt.links.new(tex.outputs["Color"], bm.inputs["Height"])
    bm.inputs["Strength"].default_value = 0.8
    nt.links.new(bm.outputs["Normal"], p.inputs["Normal"])
    p.inputs["Roughness"].default_value = 0.95
    _M["bark"] = m
    return m


# ----------------------------------------------------------------------------- geometry
class Mesh:
    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def tube(self, pts, radii, segs=8, mat=0):
        """A limb: rings round the points, bark UVs (u round the limb, v along it, 1 unit = 0.8 m)."""
        rings = []
        along = [0.0]
        for a, b in zip(pts, pts[1:]):
            along.append(along[-1] + (b - a).length)
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            a = d.orthogonal().normalized()
            b = d.cross(a).normalized()
            rings.append([self.bm.verts.new(p + (a * math.cos(t) + b * math.sin(t)) * radii[i])
                          for t in (2 * math.pi * k / segs for k in range(segs))])
        wrap = max(1, round(2 * math.pi * radii[0] / 0.8 * 2))     # bark texture repeats round thick trunks
        for i, (r1, r2) in enumerate(zip(rings, rings[1:])):
            for k in range(segs):
                f = self.bm.faces.new((r1[k], r1[(k + 1) % segs], r2[(k + 1) % segs], r2[k]))
                f.smooth = True
                f.material_index = mat
                u0, u1 = k / segs * wrap, (k + 1) / segs * wrap
                v0, v1 = along[i] / 0.8, along[i + 1] / 0.8
                for lp, uv in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
                    lp[self.uv].uv = uv
                    lp[self.col] = (0.5, 0.0, 0.0, 1)

    def spray(self, base, along, normal, size, cell, light, warm, mat=1, fold=0.18, curl=0.12):
        """A leaf spray card from the twig at `base` out along `along`: two quads folded along its stalk
        (a shallow V), the tip dipping back, UVs on one cell of the 2 x 2 atlas."""
        t = along.normalized()
        n = (normal - t * normal.dot(t)).normalized()
        s = t.cross(n).normalized()
        u0, v0 = (cell % 2) * 0.5, (cell // 2) * 0.5
        grid = []
        for j, ty in enumerate((0.0, 1.0)):
            row = []
            for i, sx in enumerate((-1.0, 0.0, 1.0)):
                lift = fold * size * (1 - abs(sx)) - curl * size * ty * ty * (1 - 0.6 * abs(sx))
                p = base + t * ty * size + s * sx * size * 0.5 + n * lift
                row.append((self.bm.verts.new(p), (u0 + 0.25 + 0.245 * sx, v0 + 0.01 + 0.48 * ty)))
            grid.append(row)
        c = (light, warm, 0.0, 1.0)
        for j in range(1):
            for i in range(2):
                q = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
                f = self.bm.faces.new([v for v, _ in q])
                f.material_index = mat
                f.smooth = True
                for lp, (_, uv) in zip(f.loops, q):
                    lp[self.uv].uv = uv
                    lp[self.col] = c

    def finish(self, name, mats):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        for m in mats:
            ob.data.materials.append(m)
        return ob


def _trunk(m, rng, h, r, lean=0.08, segs=12):
    """A trunk with a flared, buttressed foot and a few kinks; returns the top point."""
    pts, radii = [], []
    lx, ly = rng.uniform(-1, 1) * lean, rng.uniform(-1, 1) * lean
    n = 8
    for i in range(n + 1):
        f = i / n
        z = -0.3 + (h + 0.3) * f
        k = 1.0 + 0.7 * math.exp(-max(z, 0) / 0.35) if z < 0.9 else 1.0
        pts.append(Vector((lx * z + rng.uniform(-0.03, 0.03), ly * z + rng.uniform(-0.03, 0.03), z)))
        radii.append(r * k * (1 - 0.3 * f))
    m.tube(pts, radii, segs if DETAIL >= 1.0 else 6)
    return pts[-1]


def _branches(m, rng, base, direction, length, radius, depth, spread, tips, droop=0.0, splits=(2, 3), nodes=None, node_depth=9):
    """Recursive branching: a curved limb, children fanning out from its upper half; twig tips (and, for bushes,
    points all along the stems) get the leaves."""
    pts, radii = [], []
    d = direction.normalized()
    p = base.copy()
    n = 5
    for i in range(n + 1):
        f = i / n
        pts.append(p.copy())
        radii.append(radius * (1 - 0.6 * f) if depth > 0 else radius * (1 - 0.85 * f))
        bend = Vector((rng.uniform(-0.14, 0.14), rng.uniform(-0.14, 0.14), rng.uniform(-0.06, 0.08) - droop))
        d = (d + bend * 0.3).normalized()
        p = p + d * (length / n)
        if nodes is not None and i > 1 and depth <= node_depth:
            nodes.append((p.copy(), d.copy()))
    if depth == 0:                                   # twigs: three sides, three rings
        pts, radii = pts[::2] + ([pts[-1]] if n % 2 else []), radii[::2] + ([radii[-1]] if n % 2 else [])
    if DETAIL >= 1.0:
        m.tube(pts, radii, segs=8 if depth > 2 else (5 if depth >= 1 else 3))
    elif depth >= 3:
        m.tube(pts[::2] + [pts[-1]], radii[::2] + [radii[-1]], segs=4)
    end = pts[-1]
    if depth == 0:
        tips.append((end, d))
        return
    for k in range(rng.randint(*splits)):
        ax = d.orthogonal().normalized()
        ax = Matrix.Rotation(rng.uniform(0, math.tau), 3, d) @ ax
        nd = Matrix.Rotation(rng.uniform(spread * 0.5, spread), 3, ax) @ d
        start = pts[rng.randint(n // 2, n)]
        _branches(m, rng, start, nd, length * rng.uniform(0.55, 0.72), radius * 0.55, depth - 1, spread, tips, droop,
                  splits, nodes, node_depth)


def _crown(m, rng, tips, per_tip, size, cells=(0, 1, 2, 3), flower_cell=None, flower_rate=0.0, droop=0.25, lit=0.15):
    """Leaf sprays fanning out of every twig tip. Light: the leaves on the crown's sunny outer shell are bright,
    the ones deep inside dark (r), a few yellow-green (g)."""
    if not tips:
        return
    pts = [t[0] for t in tips]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre = (lo + hi) / 2
    half = Vector((max(hi.x - lo.x, 0.5), max(hi.y - lo.y, 0.5), max(hi.z - lo.z, 0.5))) / 2 + Vector((size, size, size))
    if DETAIL < 1.0:
        size = size / DETAIL ** 0.5
    for tip, d in tips:
        for _k in range(max(1, round(per_tip * DETAIL)) if DETAIL < 1.0 else per_tip):
            out = (tip - centre)
            out = Vector((out.x / half.x, out.y / half.y, out.z / half.z))
            r = min(out.length, 1.2)
            spread = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 0.7)))
            along = (d * 0.6 + out.normalized() * 0.6 + spread * 0.55 + Vector((0, 0, -droop))).normalized()
            normal = (Vector((0, 0, 1)) + out.normalized() * 0.6 + spread * 0.3).normalized()
            if abs(normal.dot(along)) > 0.95:
                normal = along.orthogonal()
            top = 0.25 * max(0.0, (tip.z - centre.z) / half.z)
            light = max(0.0, min(1.0, lit + (1 - lit) * r ** 1.6 + top + rng.uniform(-0.12, 0.12)))
            warm = rng.random() ** 3
            sz = size * rng.uniform(0.8, 1.2)
            base = tip + spread * size * 0.12
            if flower_cell is not None and rng.random() < flower_rate * (0.4 + r):
                m.spray(base, (along + Vector((0, 0, 0.8))).normalized(), normal, sz * 0.8, flower_cell, light, 0.0)
            else:
                m.spray(base, along, normal, sz, rng.choice(cells), light, warm)


def neem(seed=1):
    rng = random.Random(seed)
    m = Mesh()
    tips = []
    nodes = []
    h = rng.uniform(3.0, 3.8)
    top = _trunk(m, rng, h, 0.24)
    for k in range(rng.randint(4, 6)):
        a = k / 5 * math.tau + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a) * 0.75, math.sin(a) * 0.75, 1.0))
        _branches(m, rng, top - Vector((0, 0, rng.uniform(0, 0.7))), d, rng.uniform(2.0, 2.6), 0.12, 4, 0.7, tips,
                  nodes=nodes, node_depth=1)
    _crown(m, rng, tips + nodes[::2], 6, 0.75, cells=(0, 1, 2, 3), droop=0.35, lit=0.3)
    return m.finish("neem_%d" % seed, [bark_mat(), leaf_mat("Neem Leaf", "neem")])


def raintree(seed=1):
    rng = random.Random(seed)
    m = Mesh()
    tips = []
    nodes = []
    h = rng.uniform(2.2, 2.8)
    top = _trunk(m, rng, h, 0.42, lean=0.12, segs=14)
    for k in range(rng.randint(5, 7)):
        a = k / 6 * math.tau + rng.uniform(-0.25, 0.25)
        d = Vector((math.cos(a), math.sin(a), rng.uniform(0.5, 0.75)))
        _branches(m, rng, top, d, rng.uniform(3.4, 4.4), 0.22, 4, 0.55, tips, droop=0.03, splits=(2, 3),
                  nodes=nodes, node_depth=1)
    _crown(m, rng, tips + nodes[::2], 5, 1.0, droop=0.15, lit=0.3)
    return m.finish("raintree_%d" % seed, [bark_mat(), leaf_mat("Rain Tree Leaf", "rain")])


def gulmohar(seed=1):
    rng = random.Random(seed)
    m = Mesh()
    tips = []
    nodes = []
    h = rng.uniform(2.5, 3.1)
    top = _trunk(m, rng, h, 0.26, lean=0.1)
    for k in range(rng.randint(4, 6)):
        a = k / 5 * math.tau + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), rng.uniform(0.55, 0.85)))
        _branches(m, rng, top, d, rng.uniform(2.6, 3.2), 0.15, 4, 0.62, tips, droop=0.03, nodes=nodes, node_depth=1)
    _crown(m, rng, tips + nodes[::2], 6, 0.85, cells=(0, 1, 2), flower_cell=3, flower_rate=0.35, droop=0.2, lit=0.3)
    return m.finish("gulmohar_%d" % seed, [bark_mat(), leaf_mat("Gulmohar Leaf", "gulmohar")])


def bush(seed=1):
    """seed 1, 4: hibiscus with a few red ixora heads; 2, 5: croton; 3, 6: ixora hedge plant."""
    rng = random.Random(seed)
    m = Mesh()
    tips = []
    nodes = []
    r = rng.uniform(0.55, 0.9)
    for k in range(rng.randint(6, 9)):
        a = rng.uniform(0, math.tau)
        d = Vector((math.cos(a) * 0.55, math.sin(a) * 0.55, 1.0))
        _branches(m, rng, Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), -0.05)), d, r * 0.85, 0.022, 1, 0.8,
                  tips, nodes=nodes)
    kind = (seed - 1) % 3
    leaves = tips + nodes[::2]
    cells, fl, rate = {0: ((0, 1), 3, 0.08), 1: ((2,), None, 0.0), 2: ((0, 1), 3, 0.3)}[kind]
    _crown(m, rng, leaves, 4 if kind != 1 else 3, 0.36 if kind != 1 else 0.42, cells=cells, flower_cell=fl,
           flower_rate=rate, droop=0.1, lit=0.5)
    return m.finish("bush_%d" % seed, [bark_mat(), leaf_mat("Bush Leaf", "bush")])


def grass_tuft(seed=1):
    rng = random.Random(seed)
    m = Mesh()
    for k in range(26):
        a = rng.uniform(0, math.tau)
        lean = rng.uniform(0.1, 0.5)
        hgt = rng.uniform(0.12, 0.3)
        base = Vector((math.cos(a) * 0.04, math.sin(a) * 0.04, 0))
        d = Vector((math.cos(a) * lean, math.sin(a) * lean, 1.0)).normalized()
        side = Vector((-math.sin(a), math.cos(a), 0)) * 0.006
        pts = [base + d * hgt * f + Vector((0, 0, -0.5 * lean * hgt * f * f)) for f in (0, 0.5, 1)]
        shade = (rng.uniform(0.3, 1.0), rng.random() ** 2, 0, 1)
        vs = [m.bm.verts.new(pts[0] - side), m.bm.verts.new(pts[0] + side), m.bm.verts.new(pts[1] + side * 0.6),
              m.bm.verts.new(pts[1] - side * 0.6), m.bm.verts.new(pts[2])]
        for face in ((vs[0], vs[1], vs[2], vs[3]), (vs[3], vs[2], vs[4])):
            f = m.bm.faces.new(face)
            f.material_index = 0
            for lp in f.loops:
                lp[m.col] = shade
                lp[m.uv].uv = (0.5, 0.5)
    return m.finish("grass_%d" % seed, [grass_mat()])


def grass_mat():
    if "grass" in _M:
        return _M["grass"]
    m = bpy.data.materials.new("Grass Blade")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    sv = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(vc.outputs["Color"], sv.inputs[0])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs[6].default_value = (0.1, 0.13, 0.04, 1)
    mix.inputs[7].default_value = (0.3, 0.3, 0.1, 1)
    nt.links.new(sv.outputs[0], mix.inputs["Factor"])
    nt.links.new(mix.outputs[2], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.6
    _M["grass"] = m
    return m


def palm(seed=1):
    import trees_tn
    before = set(bpy.data.objects)
    trees_tn.build("palm", seed)
    return [o for o in bpy.data.objects if o not in before]


KINDS = {"neem": neem, "raintree": raintree, "gulmohar": gulmohar, "bush": bush, "grass": grass_tuft}


def preview(out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _M.clear()
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 96
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
    sc.view_settings.exposure = -0.8
    sc.world = bpy.data.worlds.new("Sky")
    sc.world.use_nodes = True
    sky = sc.world.node_tree.nodes.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_elevation = math.radians(40)
    sky.sun_rotation = math.radians(-60)
    sc.world.node_tree.links.new(sky.outputs[0], sc.world.node_tree.nodes["Background"].inputs[0])
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.12
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(-130))
    sc.collection.objects.link(sun)
    bpy.ops.mesh.primitive_plane_add(size=80)
    g = bpy.context.active_object
    gm = bpy.data.materials.new("Soil")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.2, 0.13, 0.08, 1)
    g.data.materials.append(gm)
    for fn, loc in ((raintree, (-9, 6, 0)), (neem, (2, 3, 0)), (gulmohar, (10, 7, 0))):
        o = fn(3)
        o.location = loc
        print("TRIS", o.name, sum(len(p.vertices) - 2 for p in o.data.polygons), flush=True)
    for k in range(6):
        o = bush(k + 1)
        o.location = (-6 + k * 2.8, -4, 0)
        print("TRIS", o.name, sum(len(p.vertices) - 2 for p in o.data.polygons), flush=True)
    pal = palm(4)
    for o in pal:
        if o.parent is None:
            o.location = (17, 10, 0)
    import random as _r
    rr = _r.Random(2)
    gt = grass_tuft(1)
    gt.location = (0, -100, 0)
    for k in range(700):
        inst = bpy.data.objects.new("tuft", gt.data)
        sc.collection.objects.link(inst)
        inst.location = (rr.uniform(-20, 20), rr.uniform(-8, 2), 0)
        inst.rotation_euler = (0, 0, rr.uniform(0, 6.28))
        inst.scale = (1.4, 1.4, rr.uniform(0.8, 1.6))
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.location = (0, -22, 3.2)
    cam.data.lens = 26
    cam.rotation_euler = (Vector((1, 4, 3.6)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out, flush=True)
    # close: under the neem and the bushes, as a walker sees them
    cam.location = (-3.5, -9.5, 1.6)
    cam.data.lens = 30
    cam.rotation_euler = (Vector((1.0, 1.0, 2.6)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = out.replace(".jpg", "_close.jpg")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", sc.render.filepath, flush=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--preview" in args:
        preview(os.path.abspath(args[args.index("--preview") + 1]))
