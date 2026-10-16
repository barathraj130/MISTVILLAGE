"""
Natural trees and bushes for the Coimbatore streets, made of real branches and thousands of individual leaves
(alpha-shaped leaf cards, slightly translucent, every leaf its own shade), not blobs. Our own procedural designs.

  neem       a straight trunk forking into a rounded crown of fine leaves
  raintree   a short trunk splitting low into long spreading limbs, a wide flat umbrella canopy
  gulmohar   a spreading crown with red-orange flower clusters among feathery leaves
  palm       coconut palm (tools/trees_tn.py)
  bush       a leafy mound (croton / hibiscus): mixed greens, some yellow-red croton leaves or red flowers
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


def leaf_mat(name, colour_a, colour_b, trans=0.25):
    """Leaf cards: an ellipse cut out of the card by alpha, colour varied per leaf (vertex colour), lit through."""
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.blend_method = 'HASHED' if hasattr(m, "blend_method") else None
    nt = m.node_tree
    out = nt.nodes["Material Output"]
    p = nt.nodes["Principled BSDF"]
    uv = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(uv.outputs["UV"], sep.inputs[0])
    # ellipse: ((u - .5) / .5)^2 + ((v - .5) / .5)^2 < 1, a little pointed at the tip
    def sq(socket, centre, half):
        a = nt.nodes.new("ShaderNodeMath")
        a.operation = "SUBTRACT"
        nt.links.new(socket, a.inputs[0])
        a.inputs[1].default_value = centre
        b = nt.nodes.new("ShaderNodeMath")
        b.operation = "DIVIDE"
        nt.links.new(a.outputs[0], b.inputs[0])
        b.inputs[1].default_value = half
        c = nt.nodes.new("ShaderNodeMath")
        c.operation = "POWER"
        nt.links.new(b.outputs[0], c.inputs[0])
        c.inputs[1].default_value = 2.0
        return c.outputs[0]
    s = nt.nodes.new("ShaderNodeMath")
    s.operation = "ADD"
    nt.links.new(sq(sep.outputs["X"], 0.5, 0.5), s.inputs[0])
    nt.links.new(sq(sep.outputs["Y"], 0.5, 0.5), s.inputs[1])
    alpha = nt.nodes.new("ShaderNodeMath")
    alpha.operation = "LESS_THAN"
    nt.links.new(s.outputs[0], alpha.inputs[0])
    alpha.inputs[1].default_value = 1.0
    nt.links.new(alpha.outputs[0], p.inputs["Alpha"])
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs[6].default_value = (*colour_a, 1)
    mix.inputs[7].default_value = (*colour_b, 1)
    sv = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(vc.outputs["Color"], sv.inputs[0])
    nt.links.new(sv.outputs[0], mix.inputs["Factor"])
    # a vertex colour with green > 0.5 means "use the vertex colour itself" (flowers, croton leaves)
    pick = nt.nodes.new("ShaderNodeMix")
    pick.data_type = "RGBA"
    gt = nt.nodes.new("ShaderNodeMath")
    gt.operation = "GREATER_THAN"
    nt.links.new(sv.outputs[2], gt.inputs[0])
    gt.inputs[1].default_value = 0.5
    nt.links.new(gt.outputs[0], pick.inputs["Factor"])
    nt.links.new(mix.outputs[2], pick.inputs[6])
    nt.links.new(vc.outputs["Color"], pick.inputs[7])
    nt.links.new(pick.outputs[2], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.55
    for nm in ("Subsurface Weight", "Transmission Weight"):
        if nm in p.inputs and nm.startswith("Subsurface"):
            p.inputs[nm].default_value = 0.0
    # light through the leaves
    tr = nt.nodes.new("ShaderNodeBsdfTranslucent")
    nt.links.new(pick.outputs[2], tr.inputs["Color"])
    ms = nt.nodes.new("ShaderNodeMixShader")
    ms.inputs[0].default_value = trans
    nt.links.new(p.outputs[0], ms.inputs[1])
    nt.links.new(tr.outputs[0], ms.inputs[2])
    # alpha must apply to both: mix with transparent by alpha
    tp = nt.nodes.new("ShaderNodeBsdfTransparent")
    ma = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(alpha.outputs[0], ma.inputs[0])
    nt.links.new(tp.outputs[0], ma.inputs[1])
    nt.links.new(ms.outputs[0], ma.inputs[2])
    nt.links.new(ma.outputs[0], out.inputs["Surface"])
    _M[name] = m
    return m


def bark_mat():
    if "bark" in _M:
        return _M["bark"]
    m = bpy.data.materials.new("Bark")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    co = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (6.0, 6.0, 1.2)
    nt.links.new(co.outputs["Object"], mp.inputs["Vector"])
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = 4.0
    n.inputs["Detail"].default_value = 8.0
    nt.links.new(mp.outputs[0], n.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.06, 0.045, 0.035, 1)
    ramp.color_ramp.elements[1].color = (0.22, 0.18, 0.14, 1)
    nt.links.new(n.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], p.inputs["Base Color"])
    bm = nt.nodes.new("ShaderNodeBump")
    nt.links.new(n.outputs["Fac"], bm.inputs["Height"])
    bm.inputs["Strength"].default_value = 0.6
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
        self.mat = self.bm.faces.layers.int.new("mat")

    def tube(self, pts, radii, segs=8, mat=0):
        rings = []
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            a = d.orthogonal().normalized()
            b = d.cross(a).normalized()
            rings.append([self.bm.verts.new(p + (a * math.cos(t) + b * math.sin(t)) * radii[i])
                          for t in (2 * math.pi * k / segs for k in range(segs))])
        for r1, r2 in zip(rings, rings[1:]):
            for k in range(segs):
                f = self.bm.faces.new((r1[k], r1[(k + 1) % segs], r2[(k + 1) % segs], r2[k]))
                f.smooth = True
                f.material_index = mat
                for lp in f.loops:
                    lp[self.col] = (0.5, 0.5, 0.5, 1)

    def leaf(self, at, normal, size, aspect, colour, mat=1, rng=None):
        """A leaf card centred at `at`, facing roughly `normal`, rotated randomly about it."""
        n = normal.normalized()
        t = n.orthogonal().normalized()
        if rng:
            t = Matrix.Rotation(rng.uniform(0, math.tau), 3, n) @ t
        s = n.cross(t).normalized()
        w, h = size * aspect * 0.5, size * 0.5
        vs = [self.bm.verts.new(at + s * sx * w + t * ty * h) for sx, ty in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        f = self.bm.faces.new(vs)
        f.material_index = mat
        for lp, uv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            lp[self.uv].uv = uv
            lp[self.col] = colour

    def finish(self, name, mats):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        for m in mats:
            ob.data.materials.append(m)
        return ob


def _branches(m, rng, base, direction, length, radius, depth, spread, tips, droop=0.0, splits=(2, 3)):
    """Recursive branching: a curved limb, children fanning out from its end; leaf points at the twig tips."""
    pts, radii = [], []
    d = direction.normalized()
    p = base.copy()
    n = 5
    for i in range(n + 1):
        f = i / n
        pts.append(p.copy())
        radii.append(radius * (1 - 0.6 * f) if depth > 0 else radius * (1 - 0.85 * f))
        bend = Vector((rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), rng.uniform(-0.06, 0.08) - droop))
        d = (d + bend * 0.3).normalized()
        p = p + d * (length / n)
    m.tube(pts, radii, segs=8 if depth > 1 else 5)
    end = pts[-1]
    if depth == 0:
        tips.append((end, d))
        return
    for k in range(rng.randint(*splits)):
        ax = d.orthogonal().normalized()
        ax = Matrix.Rotation(rng.uniform(0, math.tau), 3, d) @ ax
        nd = Matrix.Rotation(rng.uniform(spread * 0.5, spread), 3, ax) @ d
        start = pts[rng.randint(n // 2, n)]
        _branches(m, rng, start, nd, length * rng.uniform(0.55, 0.72), radius * 0.55, depth - 1, spread, tips, droop, splits)


def _crown(m, rng, tips, per_tip, radius, size, aspect, flower_rate=0.0, flower_col=(0.9, 0.18, 0.05, 1), flat=0.0,
           mat=1):
    """Leaves round every twig tip: a cloud of cards facing outward-up, sizes and shades varying."""
    centre = sum((t[0] for t in tips), Vector()) / max(len(tips), 1)
    for tip, d in tips:
        for _k in range(per_tip):
            off = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1) * (1 - flat))).normalized() * radius * rng.random() ** 0.5
            at = tip + off
            outward = (at - centre).normalized() + Vector((0, 0, 0.8))
            normal = (outward + Vector((rng.gauss(0, 0.5), rng.gauss(0, 0.5), rng.gauss(0, 0.5)))).normalized()
            if rng.random() < flower_rate:
                m.leaf(at, normal, size * 0.8, 1.0, flower_col, mat, rng)
            else:
                shade = rng.random()
                m.leaf(at, normal, size * rng.uniform(0.75, 1.25), aspect, (shade, 0.0, 0.0, 1), mat, rng)


def neem(seed=1):
    rng = random.Random(seed)
    m = Mesh()
    tips = []
    h = rng.uniform(3.2, 4.2)
    m.tube([Vector((0, 0, -0.3)), Vector((0.05, 0.02, h * 0.5)), Vector((0.1, 0.05, h))], [0.3, 0.24, 0.18], 10)
    for k in range(rng.randint(4, 6)):
        a = k / 5 * math.tau + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a) * 0.7, math.sin(a) * 0.7, 1.0))
        _branches(m, rng, Vector((0.1, 0.05, h - rng.uniform(0, 0.6))), d, rng.uniform(2.0, 2.6), 0.13, 4, 0.7, tips)
    _crown(m, rng, tips, 95, 0.8, 0.2, 0.4)
    return m.finish("neem_%d" % seed, [bark_mat(), leaf_mat("Neem Leaf", (0.03, 0.09, 0.015), (0.11, 0.2, 0.035))])


def raintree(seed=1):
    rng = random.Random(seed)
    m = Mesh()
    tips = []
    h = rng.uniform(2.2, 3.0)
    m.tube([Vector((0, 0, -0.3)), Vector((0, 0, h * 0.6)), Vector((0.1, 0, h))], [0.55, 0.45, 0.38], 12)
    for k in range(rng.randint(5, 7)):
        a = k / 6 * math.tau + rng.uniform(-0.25, 0.25)
        d = Vector((math.cos(a), math.sin(a), rng.uniform(0.55, 0.8)))
        _branches(m, rng, Vector((0.1, 0, h)), d, rng.uniform(3.4, 4.4), 0.24, 4, 0.55, tips, droop=0.03, splits=(2, 3))
    _crown(m, rng, tips, 85, 1.1, 0.2, 0.6, flat=0.6)
    return m.finish("raintree_%d" % seed, [bark_mat(), leaf_mat("Rain Tree Leaf", (0.04, 0.12, 0.02), (0.14, 0.26, 0.05))])


def gulmohar(seed=1):
    rng = random.Random(seed)
    m = Mesh()
    tips = []
    h = rng.uniform(2.6, 3.2)
    m.tube([Vector((0, 0, -0.3)), Vector((0.08, 0, h * 0.55)), Vector((0.05, 0.05, h))], [0.32, 0.25, 0.2], 10)
    for k in range(rng.randint(4, 6)):
        a = k / 5 * math.tau + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), rng.uniform(0.6, 0.9)))
        _branches(m, rng, Vector((0.05, 0.05, h)), d, rng.uniform(2.6, 3.2), 0.16, 4, 0.62, tips, droop=0.03)
    _crown(m, rng, tips, 80, 0.85, 0.19, 0.5, flower_rate=0.3, flower_col=(0.85, 0.12, 0.02, 1), flat=0.35)
    return m.finish("gulmohar_%d" % seed, [bark_mat(), leaf_mat("Gulmohar Leaf", (0.06, 0.15, 0.02), (0.16, 0.3, 0.05))])


def bush(seed=1):
    rng = random.Random(seed)
    m = Mesh()
    tips = []
    r = rng.uniform(0.5, 0.9)
    for k in range(rng.randint(5, 8)):
        a = rng.uniform(0, math.tau)
        d = Vector((math.cos(a) * 0.6, math.sin(a) * 0.6, 1.0))
        _branches(m, rng, Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), -0.05)), d, r * 0.8, 0.025, 1, 0.8, tips)
    croton = rng.random() < 0.4
    flower = (0.85, 0.08, 0.1, 1) if not croton else (0.85, 0.65, 0.05, 1)
    _crown(m, rng, tips, 70, r * 0.55, 0.11, 0.5, flower_rate=0.12 if not croton else 0.3, flower_col=flower)
    return m.finish("bush_%d" % seed, [bark_mat(), leaf_mat("Bush Leaf", (0.03, 0.1, 0.02), (0.12, 0.24, 0.04))])


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
        shade = (rng.random(), 0, 0, 1)
        vs = [m.bm.verts.new(pts[0] - side), m.bm.verts.new(pts[0] + side), m.bm.verts.new(pts[1] + side * 0.6),
              m.bm.verts.new(pts[1] - side * 0.6), m.bm.verts.new(pts[2])]
        for face in ((vs[0], vs[1], vs[2], vs[3]), (vs[3], vs[2], vs[4])):
            f = m.bm.faces.new(face)
            f.material_index = 0
            for lp in f.loops:
                lp[m.col] = shade
                lp[m.uv].uv = (0.5, 0.5)
    return m.finish("grass_%d" % seed, [leaf_mat("Grass Blade", (0.18, 0.2, 0.06), (0.32, 0.3, 0.1), trans=0.35)])


def palm(seed=1):
    import trees_tn
    before = set(bpy.data.objects)
    trees_tn.build("palm", seed)
    return [o for o in bpy.data.objects if o not in before]


KINDS = {"neem": neem, "raintree": raintree, "gulmohar": gulmohar, "bush": bush, "grass": grass_tuft}


def preview(out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
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
    for k in range(6):
        o = bush(k + 1)
        o.location = (-6 + k * 2.8, -4, 0)
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


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--preview" in args:
        preview(os.path.abspath(args[args.index("--preview") + 1]))
