"""
People for the Coimbatore streets: MPFB2 bodies (CC0 skins, hair, brows, eyes) in everyday South Indian dress —
shirt and trousers, shirt and white veshti, checked lungi, saree with pleats and pallu, school uniform — posed
standing or mid-stride, baked (pose applied, joined, reduced to ~9k triangles) and exported for the game.

    Blender -b --python tools/humans/street_people.py -- --preview out.jpg        (needs MPFB: no --factory-startup)
    Blender -b --python tools/humans/street_people.py -- --export godot/assets/people
"""
import importlib
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def mp(path, key):
    for m in sys.modules:
        if m.endswith(path):
            return getattr(importlib.import_module(m), key)
    raise SystemExit("MPFB is not enabled")


HS = mp("mpfb.services.humanservice", "HumanService")
HOP = mp("mpfb.entities.objectproperties", "HumanObjectProperties")
TS = mp("mpfb.services.targetservice", "TargetService")
AS = mp("mpfb.services.assetservice", "AssetService")


def asset(name, sub):
    try:
        return AS.find_asset_absolute_path(name, asset_subdir=sub)
    except Exception:
        return None


def age(years):
    return years / 24.0 * 0.5 if years <= 25 else 0.5 + (years - 25) / 65.0 * 0.5


# name, gender, years, weight, muscle, height, skin, hair, brows, outfit, pose, colours
PEOPLE = [
    ("man_shirt_walk", 1.0, 32, 0.5, 0.55, 0.55, "young_african_male", "short02", "mindfront_eyebrows_03", "trousers", "walk", [(0.55, 0.7, 0.85)]),
    ("man_shirt_stand", 1.0, 41, 0.6, 0.5, 0.5, "middleage_african_male", "short04", "eyebrow004", "trousers", "stand", [(0.85, 0.85, 0.82)]),
    ("man_veshti", 1.0, 58, 0.55, 0.4, 0.5, "old_african_male", "short01", "eyebrow004", "veshti", "stand", [(0.95, 0.95, 0.92)]),
    ("man_lungi", 1.0, 36, 0.5, 0.6, 0.52, "young_african_male", "short02", "mindfront_eyebrows_03", "lungi", "stand", [(0.15, 0.3, 0.55)]),
    ("woman_saree_red", 0.0, 34, 0.55, 0.4, 0.42, "cutoff3d_indian_female_enhanced", "braid01", "mindfront_eyebrows_08", "saree", "stand", [(0.7, 0.06, 0.12)]),
    ("woman_saree_green", 0.0, 45, 0.65, 0.4, 0.4, "cutoff3d_indian_female_enhanced", "bob02", "mindfront_eyebrows_08", "saree", "stand", [(0.1, 0.45, 0.25)]),
    ("woman_saree_blue", 0.0, 27, 0.48, 0.42, 0.45, "cutoff3d_indian_female_enhanced", "ponytail01", "mindfront_eyebrows_10", "saree", "stand", [(0.12, 0.2, 0.6)]),
    ("schoolboy", 1.0, 12, 0.45, 0.45, 0.42, "young_african_male", "short02", "mindfront_eyebrows_03", "school", "walk", [(0.95, 0.95, 0.95)]),
]

STRIDE = {"walk": 1.0, "stand": 0.0}


def cloth(name, colour, rough=0.9, pattern=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*colour, 1)
    p.inputs["Roughness"].default_value = rough
    if pattern == "check":                     # lungi checks
        co = nt.nodes.new("ShaderNodeTexCoord")
        ck = nt.nodes.new("ShaderNodeTexChecker")
        ck.inputs["Scale"].default_value = 18.0
        ck.inputs["Color1"].default_value = (*colour, 1)
        ck.inputs["Color2"].default_value = (colour[0] * 0.4 + 0.5, colour[1] * 0.4 + 0.45, colour[2] * 0.4 + 0.4, 1)
        nt.links.new(co.outputs["Object"], ck.inputs["Vector"])
        nt.links.new(ck.outputs["Color"], p.inputs["Base Color"])
    return m


def tint(obj, rgb, amount=1.0):
    for slot in obj.material_slots:
        m = slot.material
        if not m or not m.use_nodes:
            continue
        nt = m.node_tree
        for n in list(nt.nodes):
            if n.type == 'TEX_IMAGE' and n.image and n.image.colorspace_settings.name == "sRGB":
                outs = [l for l in nt.links if l.from_node == n and l.from_socket.name == "Color"]
                if not outs:
                    continue
                mix = nt.nodes.new("ShaderNodeMix")
                mix.data_type = "RGBA"
                mix.blend_type = "MULTIPLY"
                mix.inputs["Factor"].default_value = amount
                mix.inputs[7].default_value = (*rgb, 1)
                nt.links.new(n.outputs["Color"], mix.inputs[6])
                for l in outs:
                    to = l.to_socket
                    nt.links.remove(l)
                    nt.links.new(mix.outputs[2], to)


def plain_clothes(obj, colour, outfit):
    """No printed logos: the shirt or top in a plain cloth colour; trousers (jeans) dark grey or school navy."""
    cl = cloth("Top %s" % outfit, colour, 0.85)
    legs = cloth("Pants %s" % outfit, (0.05, 0.08, 0.2) if outfit == "school" else (0.12, 0.12, 0.13), 0.8)
    me = obj.data
    me.materials.clear()
    me.materials.append(cl)
    me.materials.append(legs)
    for p in me.polygons:
        z = sum((me.vertices[i].co.z for i in p.vertices)) / len(p.vertices)
        p.material_index = 1 if z < 0.93 else 0
    obj["outfit"] = outfit


def cut_below(obj, z_cut):
    """Remove the part of a garment under the wraps (jeans or shorts under a veshti, lungi or saree)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    kill = [v for v in bm.verts if v.co.z < z_cut]
    bmesh.ops.delete(bm, geom=kill, context='VERTS')
    bm.to_mesh(obj.data)
    bm.free()


def rotate_bone(arm, name, axis, angle):
    """Turn a pose bone about a world axis through its head (the children follow)."""
    pb = arm.pose.bones.get(name)
    if pb is None:
        return
    m = arm.matrix_world @ pb.matrix
    t = m.translation.copy()
    R = Matrix.Rotation(angle, 4, axis)
    new = Matrix.Translation(t) @ R @ Matrix.Translation(-t) @ m
    pb.matrix = arm.matrix_world.inverted() @ new
    bpy.context.view_layer.update()


def pose(arm, kind, rng, arm_angle=52):
    """Arms down from MakeHuman's A-pose; a stride for walkers (left leg forward, opposite arm swings)."""
    s = STRIDE[kind]
    rotate_bone(arm, "upperarm01.L", 'Y', math.radians(arm_angle))
    rotate_bone(arm, "upperarm01.R", 'Y', math.radians(-arm_angle))
    if s:
        a = math.radians(18)
        rotate_bone(arm, "upperleg01.L", 'X', a)                 # forward is -Y: rotating about +X lifts it forward
        rotate_bone(arm, "upperleg01.R", 'X', -a * 0.8)
        rotate_bone(arm, "lowerleg01.R", 'X', math.radians(-15))
        rotate_bone(arm, "upperarm01.R", 'X', math.radians(18))
        rotate_bone(arm, "upperarm01.L", 'X', math.radians(-16))
    if not s:                                                    # stand with the feet closer together
        rotate_bone(arm, "upperleg01.L", 'Y', math.radians(7))       # feet in under the hips
        rotate_bone(arm, "upperleg01.R", 'Y', math.radians(-7))
    rotate_bone(arm, "neck01", 'Z', rng.uniform(-0.15, 0.15))


BODY = {}


def fit_profile(heights, flare=0.0, ease=0.03):
    """Rings that clear the baked body: at each height, the body's half width and half depth plus ease, the hem
    flaring out; returns [(rx, z, ry/rx)] for lathe()."""
    vs = BODY.get("verts")
    out = []
    zs = sorted(heights, reverse=True)
    for k, z in enumerate(zs):
        band = [v for v in vs if abs(v[2] - z) < 0.05] if vs is not None else []
        rx = max([abs(v[0]) for v in band] + [0.15]) + ease
        ry = max([abs(v[1] - BODY.get("cy", 0.0)) for v in band] + [0.11]) + ease
        f = k / max(len(zs) - 1, 1)
        rx += flare * f * f
        ry += flare * 0.6 * f * f
        out.append((rx, z, ry / rx))
    return out


def lathe(name, profile, mat, segs=40, pleats=0.0):
    """A cloth tube: (radius, z) rings around the body's vertical axis; optional pleats as a ripple."""
    bm = bmesh.new()
    rings = []
    cy = BODY.get("cy", 0.0)
    for r, z, *rest in profile:
        ring = []
        for i in range(segs):
            a = i / segs * math.tau
            rr = r * (1.0 + pleats * max(0.0, math.cos(a + math.pi / 2)) * (0.5 + 0.5 * math.sin(i * 2.7)) * 0.06)
            ry = rr * (rest[0] if rest else 0.82)            # bodies are deeper than wide: an oval
            ring.append(bm.verts.new((math.cos(a) * rr, cy + math.sin(a) * ry, z)))
        rings.append(ring)
    for r1, r2 in zip(rings, rings[1:]):
        for i in range(segs):
            bm.faces.new((r1[i], r1[(i + 1) % segs], r2[(i + 1) % segs], r2[i]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def wrap(kind, colour, stride):
    """Lower-body garments as cloth tubes over the legs (fitted to a standing MakeHuman adult)."""
    parts = []
    if kind == "veshti":
        m = cloth("Veshti", (0.95, 0.95, 0.9), 0.85)
        prof = fit_profile([1.0, 0.9, 0.75, 0.6, 0.45, 0.3, 0.18, 0.07], flare=0.03)
        parts.append(lathe("Veshti", prof, m))
        b = cloth("Veshti Border", (0.85, 0.65, 0.15), 0.6)          # gold border at the hem
        rx, z, k = prof[-1]
        parts.append(lathe("Border", [(rx + 0.003, 0.11, k), (rx + 0.003, 0.07, k)], b))
    elif kind == "lungi":
        m = cloth("Lungi", colour, 0.85, "check")
        parts.append(lathe("Lungi", fit_profile([1.0, 0.9, 0.75, 0.6, 0.45, 0.32, 0.22], flare=0.02), m))
    elif kind == "saree":
        m = cloth("Saree", colour, 0.6)
        prof = fit_profile([1.04, 0.95, 0.82, 0.68, 0.52, 0.36, 0.2, 0.04], flare=0.05, ease=0.035)
        parts.append(lathe("Saree", prof, m, segs=56, pleats=1.0))
        gold = cloth("Zari", (0.85, 0.62, 0.12), 0.4)
        rx, z, k = prof[-1]
        parts.append(lathe("Zari", [(rx + 0.003, 0.12, k), (rx + 0.003, 0.05, k)], gold, segs=56))
        # pallu: a band from the waist at the right, across the chest, over the left shoulder, hanging down the back;
        # the band's width lies on the body's surface (perpendicular to its run and to the outward normal)
        pts = [(-0.13, -0.1, 1.02, 0.12), (-0.06, -0.125, 1.14, 0.15), (0.02, -0.13, 1.26, 0.16), (0.09, -0.1, 1.37, 0.13),
               (0.14, -0.03, 1.43, 0.1), (0.15, 0.06, 1.42, 0.11), (0.14, 0.1, 1.25, 0.15), (0.13, 0.11, 0.95, 0.18)]
        bm = bmesh.new()
        prev = None
        for i, (x, y, z, wd) in enumerate(pts):
            pv = Vector((x, y, z))
            run = (Vector(pts[min(i + 1, len(pts) - 1)][:3]) - Vector(pts[max(i - 1, 0)][:3])).normalized()
            out = Vector((x, y * 1.2, 0.0)).normalized() if abs(x) + abs(y) > 0.01 else Vector((0, -1, 0))
            if z > 1.4:
                out = (out + Vector((0, 0, 1.2))).normalized()
            side = run.cross(out).normalized() * (wd * 0.5)
            pv = pv + out * 0.012
            a1, b1 = bm.verts.new(pv - side), bm.verts.new(pv + side)
            if prev:
                bm.faces.new((prev[0], prev[1], b1, a1))
            prev = (a1, b1)
        me = bpy.data.meshes.new("Pallu")
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new("Pallu", me)
        bpy.context.scene.collection.objects.link(o)
        o.data.materials.append(m)
        for pl in o.data.polygons:
            pl.use_smooth = True
        sol = o.modifiers.new("Thick", 'SOLIDIFY')
        sol.thickness = 0.01
        parts.append(o)
        bl = cloth("Blouse", (colour[0] * 0.6 + 0.3, colour[1] * 0.4 + 0.25, colour[2] * 0.5 + 0.1), 0.7)
        _ = bl
    return parts


def build(spec, x=0.0, rng=None):
    name, g, yrs, w, mu, hgt, skin, hair, brows, outfit, kind, colours = spec
    rng = rng or random.Random(hash(name) & 0xffff)
    h = HS.create_human()
    h.name = name
    for k, v in (("gender", g), ("age", age(yrs)), ("weight", w), ("muscle", mu), ("height", hgt),
                 ("african", 0.45), ("asian", 0.13), ("caucasian", 0.42)):
        HOP.set_value(k, v, entity_reference=h)
    TS.reapply_macro_details(h)
    arm = HS.add_builtin_rig(h, "default")
    sk = asset(skin + ".mhmat", "skins")
    if sk:
        HS.set_character_skin(sk, h, skin_type="MAKESKIN")
    objs = [h]
    for sub, fname, typ in (("eyes", "low-poly.mhclo", "Eyes"), ("eyebrows", brows + ".mhclo", "Eyebrows"),
                            ("hair", hair + ".mhclo", "Hair")):
        p = asset(fname, sub)
        if p:
            o = HS.add_mhclo_asset(p, h, asset_type=typ, subdiv_levels=0, material_type="MAKESKIN")
            if typ == "Hair":
                tint(o, (0.05, 0.04, 0.035) if yrs < 55 else (0.45, 0.44, 0.42), 0.9)
            objs.append(o)
    top = {"trousers": "male_casualsuit03", "veshti": "male_casualsuit03", "lungi": "male_casualsuit06",
           "saree": "female_casualsuit02", "school": "male_casualsuit03"}[outfit]
    p = asset(top + ".mhclo", "clothes")
    if p:
        c = HS.add_mhclo_asset(p, h, asset_type="Clothes", subdiv_levels=0, material_type="MAKESKIN")
        shirt = {"trousers": colours[0], "veshti": (0.92, 0.92, 0.88), "lungi": (0.55, 0.62, 0.7),
                 "saree": (colours[0][0] * 0.6 + 0.25, colours[0][1] * 0.6 + 0.2, colours[0][2] * 0.6 + 0.15),
                 "school": (0.95, 0.95, 0.95)}[outfit]
        plain_clothes(c, shirt, outfit)
        objs.append(c)
    shoes = asset("shoes0%d.mhclo" % (1 + rng.randrange(3)), "clothes")
    if shoes and outfit in ("trousers", "school"):
        objs.append(HS.add_mhclo_asset(shoes, h, asset_type="Clothes", subdiv_levels=0, material_type="MAKESKIN"))
    pose(arm, kind, rng, 30 if outfit == "saree" else 52)
    # bake the pose into the meshes
    for o in objs:
        bpy.context.view_layer.objects.active = o
        if o.data.shape_keys:                                  # the body's targets: freeze the current shape
            bpy.ops.object.select_all(action='DESELECT')
            o.select_set(True)
            bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
        for m in list(o.modifiers):
            if m.type in ('ARMATURE', 'SUBSURF', 'MASK'):
                if m.type == 'SUBSURF':
                    m.levels = 0
                try:
                    bpy.ops.object.modifier_apply(modifier=m.name)
                except RuntimeError:
                    o.modifiers.remove(m)
    for o in objs:
        o.parent = None
        if o.get("outfit") in ("veshti", "lungi", "saree"):
            cut_below(o, 1.0 if o["outfit"] == "saree" else 0.95)
    bpy.data.objects.remove(arm, do_unlink=True)
    names = {g.index: g.name for g in h.vertex_groups}
    keep = ("upperleg", "lowerleg", "pelvis", "foot", "spine04", "spine05", "root")
    bv = []
    for v in h.data.vertices:
        if not v.groups:
            continue
        top = max(v.groups, key=lambda g: g.weight)
        if names.get(top.group, "").startswith(keep):       # legs and hips only, never the hands hanging beside them
            bv.append(tuple(h.matrix_world @ v.co))
    BODY["verts"] = [v for v in bv if v[2] < 1.08]
    BODY["cy"] = sum(v[1] for v in BODY["verts"]) / max(len(BODY["verts"]), 1)
    objs += wrap(outfit, colours[0], STRIDE[kind])
    for o in objs:
        o.location.x += x
    return objs


def bake(objs, name, target=9000):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except RuntimeError:
                o.modifiers.remove(m)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > target:
        d = ob.modifiers.new("Dec", 'DECIMATE')
        d.ratio = target / tris
        bpy.ops.object.modifier_apply(modifier="Dec")
    return ob


def preview(out):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    sc = bpy.context.scene
    for k, spec in enumerate(PEOPLE):
        build(spec, k * 0.8)
    bpy.ops.mesh.primitive_plane_add(size=40)
    g = bpy.context.active_object
    gm = bpy.data.materials.new("Ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.28, 0.25, 1)
    g.data.materials.append(gm)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    sc.world = bpy.data.worlds.new("Sky")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.62, 0.72, 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    mid = (len(PEOPLE) - 1) * 0.4
    cam.location = (mid, -6.2, 1.25)
    cam.data.lens = 38
    cam.rotation_euler = (Vector((mid, 0, 0.9)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    try:
        pr = bpy.context.preferences.addons["cycles"].preferences
        pr.compute_device_type = 'METAL'
        pr.get_devices()
        for d in pr.devices:
            d.use = True
        sc.cycles.device = 'GPU'
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = 1920, 820
    sc.view_settings.view_transform = 'AgX'
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out, flush=True)


def export(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for spec in PEOPLE:
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        objs = build(spec, 0.0)
        ob = bake(objs, spec[0])
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, "street_%s.glb" % spec[0]), export_format='GLB',
                                  use_selection=True, export_apply=True, export_yup=True)
        print("PERSON", spec[0], sum(len(p.vertices) - 2 for p in ob.data.polygons), flush=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--preview" in args:
        preview(os.path.abspath(args[args.index("--preview") + 1]))
    if "--export" in args:
        export(os.path.abspath(args[args.index("--export") + 1]))
