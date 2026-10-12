"""
Street trees for the Coimbatore city: coconut palms (curved ringed trunk, a crown of arching fronds with real
leaflets, a coconut cluster) and neem trees (forked trunk, branches, a soft smooth-shaded canopy of many leaf
clumps with colour variation). Our own designs, no downloads. Each exports a near mesh and a light far version.

    Blender -b --factory-startup --python tools/trees_tn.py -- --preview out.jpg
    Blender -b --factory-startup --python tools/trees_tn.py -- --export godot/assets/models
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fleet as F  # noqa: E402


def mats():
    return {
        "bark_palm": F.make_mat("Palm Bark", (0.32, 0.27, 0.2), rough=0.9),
        "ring": F.make_mat("Palm Ring", (0.22, 0.18, 0.13), rough=0.9),
        "frond": F.make_mat("Palm Frond", (0.16, 0.3, 0.07), rough=0.6),
        "frond_dry": F.make_mat("Palm Frond Dry", (0.4, 0.33, 0.14), rough=0.8),
        "nut": F.make_mat("Coconut", (0.25, 0.3, 0.08), rough=0.5),
        "bark": F.make_mat("Neem Bark", (0.12, 0.09, 0.07), rough=0.95),
        "leaf_a": F.make_mat("Neem Leaves", (0.035, 0.1, 0.02), rough=0.75),
        "leaf_b": F.make_mat("Neem Leaves Light", (0.07, 0.16, 0.03), rough=0.75),
    }


def tube(name, pts, radii, mat, segs=10):
    """A tube along pts with a radius per point (trunks, branches, frond midribs)."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        a = d.orthogonal().normalized()
        b = d.cross(a).normalized()
        rings.append([bm.verts.new(p + (a * math.cos(t) + b * math.sin(t)) * radii[i])
                      for t in (2 * math.pi * k / segs for k in range(segs))])
    for r1, r2 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r1[k], r1[(k + 1) % segs], r2[(k + 1) % segs], r2[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = F.link(bpy.data.objects.new(name, me))
    o.data.materials.append(mat)
    F.smooth(o)
    return o


def frond(name, base, direction, length, droop, M, rng, dry=False):
    """An arching frond: a midrib curving down, leaflets in two rows hanging off it (thin double strips)."""
    up = Vector((0, 0, 1))
    d = Vector(direction).normalized()
    side = d.cross(up).normalized()
    n = 14
    pts = []
    for i in range(n + 1):
        t = i / n
        p = base + d * (length * t) + up * (length * (0.35 * t - droop * t * t))
        pts.append(p)
    tube(name + "Rib", pts, [0.035 * (1 - 0.8 * i / n) + 0.006 for i in range(n + 1)], M["frond_dry" if dry else "frond"], 5)
    bm = bmesh.new()
    for i in range(2, n):
        t = i / n
        p = pts[i]
        tang = (pts[i + 1] - pts[i - 1]).normalized()
        ll = length * 0.42 * math.sin(math.pi * min(1.0, t * 1.1)) + 0.15
        for s in (-1, 1):
            for j in range(3):                                  # three leaflets per station each side
                q = p + tang * (j * length / n / 3)
                tip = q + (side * s * 0.8 + tang * 0.45 + Vector((0, 0, -0.55 - 0.3 * t))).normalized() * ll * rng.uniform(0.85, 1.05)
                w = 0.035
                v = [bm.verts.new(q - tang * w), bm.verts.new(q + tang * w), bm.verts.new(tip + tang * 0.005), bm.verts.new(tip - tang * 0.005)]
                bm.faces.new(v)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = F.link(bpy.data.objects.new(name, me))
    o.data.materials.append(M["frond_dry" if dry else "frond"])
    s = o.modifiers.new("Solid", 'SOLIDIFY')
    s.thickness = 0.006
    return o


def palm(seed, M):
    rng = random.Random(seed)
    h = rng.uniform(9.0, 13.0)
    lean = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized() * rng.uniform(0.6, 1.6)
    pts, radii = [], []
    n = 24
    for i in range(n + 1):
        t = i / n
        pts.append(Vector((0, 0, h * t)) + lean * (t * t) + Vector((0, 0, 0)))
        radii.append(0.2 - 0.07 * t + (0.08 if i == 0 else 0.0))
    tube("Trunk", pts, radii, M["bark_palm"], 12)
    for k in range(int(h / 0.22)):                                # leaf-scar rings up the trunk
        t = k * 0.22 / h
        c = Vector((0, 0, h * t)) + lean * (t * t)
        r = 0.2 - 0.07 * t
        F.lathe("Ring", [(r + 0.012, -0.02), (r + 0.016, 0.0), (r + 0.012, 0.02)], M["ring"], 12).location = c
    for o in bpy.data.objects:
        if o.name.startswith("Ring"):
            o.rotation_euler = (math.pi / 2, 0, 0)
    top = pts[-1]
    nf = rng.randint(16, 20)
    for k in range(nf):
        a = 2 * math.pi * k / nf + rng.uniform(-0.15, 0.15)
        tier = k % 3
        elev = [0.55, 0.15, -0.35][tier]
        d = Vector((math.cos(a), math.sin(a), elev))
        frond("Frond%d" % k, top + Vector((0, 0, 0.1)), d, rng.uniform(3.6, 4.6), [0.55, 0.75, 0.9][tier], M, rng,
              dry=(tier == 2 and rng.random() < 0.35))
    for k in range(rng.randint(6, 12)):                            # coconut cluster under the crown
        a = rng.uniform(0, 2 * math.pi)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=7, radius=0.13,
                                             location=top + Vector((math.cos(a) * 0.28, math.sin(a) * 0.28, -0.35 - rng.random() * 0.2)))
        c = bpy.context.active_object
        c.scale = (1, 1, 1.15)
        c.data.materials.append(M["nut"])
        F.smooth(c)


def neem(seed, M):
    rng = random.Random(seed)
    h = rng.uniform(4.0, 5.5)
    trunk = [Vector((0, 0, 0)), Vector((0.05, 0, h * 0.4)), Vector((0.1, 0.05, h * 0.75)), Vector((0.08, 0.1, h))]
    tube("Trunk", trunk, [0.32, 0.24, 0.2, 0.16], M["bark"], 12)
    tips = []
    for k in range(rng.randint(5, 7)):                            # main branches fanning up and out
        a = 2 * math.pi * k / 6 + rng.uniform(-0.3, 0.3)
        start = trunk[-1] - Vector((0, 0, rng.uniform(0, h * 0.25)))
        out = Vector((math.cos(a), math.sin(a), 0)) * rng.uniform(2.2, 3.6)
        mid = start + out * 0.5 + Vector((0, 0, rng.uniform(1.0, 1.8)))
        end = start + out + Vector((0, 0, rng.uniform(1.6, 2.8)))
        tube("Branch", [start, mid, end], [0.14, 0.09, 0.04], M["bark"], 8)
        tips += [mid, end]
    crown_c = Vector((0.1, 0.1, h + 2.2))
    t = bpy.data.textures.get("clump") or bpy.data.textures.new("clump", 'VORONOI')
    t.noise_scale = 0.18
    for k in range(260):                                          # a canopy of many small leaf clumps
        if k < len(tips) * 6:
            c = tips[k % len(tips)] + Vector((rng.uniform(-1.1, 1.1), rng.uniform(-1.1, 1.1), rng.uniform(-0.3, 0.9)))
        else:
            u = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 0.5))).normalized()
            c = crown_c + Vector((u.x * 3.8, u.y * 3.8, u.z * 1.9)) * rng.uniform(0.45, 1.0)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=rng.uniform(0.35, 0.62), location=c)
        o = bpy.context.active_object
        o.scale = (1.0, 1.0, 0.65)
        o.rotation_euler = (rng.uniform(0, 3), rng.uniform(0, 3), rng.uniform(0, 3))
        dm = o.modifiers.new("Leafy", 'DISPLACE')
        dm.texture = t
        dm.strength = 0.28
        o.data.materials.append(M["leaf_a" if rng.random() < 0.7 else "leaf_b"])
        F.smooth(o)


KINDS = {"palm": palm, "neem": neem}


def build(kind, seed, at=(0, 0, 0)):
    M = mats()
    before = set(bpy.data.objects)
    KINDS[kind](seed, M)
    root = F.link(bpy.data.objects.new("%s_%d" % (kind, seed), None))
    for o in bpy.data.objects:
        if o not in before and o is not root and o.parent is None:
            o.parent = root
    root.location = at
    return root


def preview(out):
    F.reset()
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
    sc.view_settings.exposure = -0.5
    sc.world = bpy.data.worlds.new("Sky")
    sc.world.use_nodes = True
    sky = sc.world.node_tree.nodes.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_elevation = math.radians(38)
    sky.sun_rotation = math.radians(-125)
    sc.world.node_tree.links.new(sky.outputs[0], sc.world.node_tree.nodes["Background"].inputs[0])
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.12
    F.box("Ground", (0, 0, -0.05), (60, 40, 0.1), F.make_mat("Soil", (0.32, 0.2, 0.12), rough=0.95), bev=0)
    F.box("Road", (0, -7, -0.02), (60, 7, 0.06), F.make_mat("Asphalt", (0.06, 0.06, 0.065), rough=0.85), bev=0)
    build("palm", 1, (-6, 2, 0))
    build("palm", 2, (-1, 4, 0))
    build("neem", 3, (6, 3, 0))
    build("palm", 4, (12, 6, 0))
    build("neem", 5, (-14, 7, 0))
    cam = F.link(bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")))
    cam.data.lens = 24
    cam.location = (2, -16, 2.0)
    cam.rotation_euler = (Vector((0, 4, 6.5)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out)


def export(out_dir):
    for kind, seeds in (("palm", (1, 2, 4)), ("neem", (3, 5))):
        for seed in seeds:
            for far in (False, True):
                F.reset()
                build(kind, seed)
                for o in list(bpy.data.objects):
                    if o.type == 'MESH':
                        bpy.context.view_layer.objects.active = o
                        for m in list(o.modifiers):
                            bpy.ops.object.modifier_apply(modifier=m.name)
                meshes = [o for o in bpy.data.objects if o.type == 'MESH']
                bpy.ops.object.select_all(action='DESELECT')
                for o in meshes:
                    o.select_set(True)
                bpy.context.view_layer.objects.active = meshes[0]
                bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
                bpy.ops.object.join()
                ob = bpy.context.view_layer.objects.active
                if far:
                    d = ob.modifiers.new("Dec", 'DECIMATE')
                    d.ratio = min(1.0, 900 / max(1, len(ob.data.polygons)))
                    bpy.ops.object.modifier_apply(modifier="Dec")
                name = "city_%s_%d%s" % (kind, seed, "_far" if far else "")
                bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, name + ".glb"), export_format='GLB',
                                          use_selection=True, export_apply=True, export_yup=True)
                print("TREE", name, len(ob.data.polygons), flush=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--preview" in args:
        preview(os.path.abspath(args[args.index("--preview") + 1]))
    if "--export" in args:
        export(os.path.abspath(args[args.index("--export") + 1]))
