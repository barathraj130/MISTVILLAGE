"""
South Indian test cast built with MPFB2 (MakeHuman) — bodies, faces, skin, eyes, brows, lashes, hair, moustaches —
rendered for review next to nothing else. Uses the CC0 asset packs when installed (tools/humans/install_packs.py);
without them it falls back to a simple skin material of our own so the body and face shapes can still be judged.

    Blender -b --python tools/humans/make_cast.py -- <out.jpg>      (needs MPFB enabled: no --factory-startup)

MakeHuman macro notes: age 0..1 → 1 year at 0, 25 at 0.5, 90 at 1 (linear in each half).
Ethnicity mix (african / asian / caucasian, summing to 1) sets face and body proportions; South Indian faces sit
roughly between the african and caucasian targets with a little asian.
"""
import importlib
import math
import os
import sys

import bpy
from mathutils import Vector


def mp(path, key):
    for m in sys.modules:
        if m.endswith(path):
            return getattr(importlib.import_module(m), key)
    raise SystemExit("MPFB is not enabled")


HumanService = mp("mpfb.services.humanservice", "HumanService")
HOP = mp("mpfb.entities.objectproperties", "HumanObjectProperties")
TargetService = mp("mpfb.services.targetservice", "TargetService")
AssetService = mp("mpfb.services.assetservice", "AssetService")


def age(years):
    return years / 24.0 * 0.5 if years <= 25 else 0.5 + (years - 25) / 65.0 * 0.5


CAST = [
    # name, gender (0 f / 1 m), years, weight, muscle, height, (african, asian, caucasian), skin rgb, hair, extras
    ("protagonist", 1.0, 27, 0.48, 0.58, 0.58, (0.42, 0.12, 0.46), (0.20, 0.105, 0.06), "short02", ["moustache"]),
    ("mother", 0.0, 46, 0.66, 0.4, 0.38, (0.45, 0.15, 0.40), (0.19, 0.10, 0.058), "braid01", []),
    ("elder", 1.0, 68, 0.42, 0.38, 0.5, (0.5, 0.1, 0.40), (0.14, 0.075, 0.045), "short01", ["moustache"]),
    ("schoolgirl", 0.0, 12, 0.45, 0.45, 0.45, (0.42, 0.18, 0.40), (0.23, 0.125, 0.072), "ponytail01", []),
]


def own_skin(rgb):
    m = bpy.data.materials.new("SkinPreview")
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = 0.48
    for n in ("Subsurface Weight", "Subsurface"):
        if n in p.inputs:
            p.inputs[n].default_value = 0.12
    if "Subsurface Radius" in p.inputs:
        p.inputs["Subsurface Radius"].default_value = (1.0, 0.35, 0.2)
    return m


def asset(name, subdir):
    try:
        return AssetService.find_asset_absolute_path(name, asset_subdir=subdir)
    except Exception:
        return None


def build(spec, x):
    name, g, yrs, w, mu, hgt, eth, rgb, hair, extras = spec
    h = HumanService.create_human()
    h.name = name
    for k, v in (("gender", g), ("age", age(yrs)), ("weight", w), ("muscle", mu), ("height", hgt),
                 ("african", eth[0]), ("asian", eth[1]), ("caucasian", eth[2])):
        HOP.set_value(k, v, entity_reference=h)
    TargetService.reapply_macro_details(h)
    have_packs = asset("eyebrow001.mhclo", "eyebrows") is not None
    if have_packs:
        tone = "young" if yrs < 35 else ("middleage" if yrs < 60 else "old")
        sex = "male" if g > 0.5 else "female"
        skin = asset("%s_african_%s.mhmat" % (tone, sex), "skins") or asset("young_african_male.mhmat", "skins")
        if skin:
            HumanService.set_character_skin(skin, h, skin_type="ENHANCED_SSS")
        for sub, fname, typ in (("eyes", "low-poly.mhclo", "Eyes"), ("eyebrows", "eyebrow001.mhclo", "Eyebrows"),
                                ("eyelashes", "eyelashes01.mhclo", "Eyelashes"), ("teeth", "teeth_base.mhclo", "Teeth"),
                                ("tongue", "tongue01.mhclo", "Tongue"), ("hair", hair + ".mhclo", "Hair")):
            p = asset(fname, sub)
            if p:
                HumanService.add_mhclo_asset(p, h, asset_type=typ)
    else:
        h.data.materials.clear()
        h.data.materials.append(own_skin(rgb))
    h.location = (x, 0, 0)
    return h


def main():
    out = os.path.abspath(sys.argv[-1])
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    sc = bpy.context.scene
    xs = []
    for k, spec in enumerate(CAST):
        build(spec, k * 0.9)
        xs.append(k * 0.9)
    bpy.ops.mesh.primitive_plane_add(size=40)
    g = bpy.context.active_object
    gm = bpy.data.materials.new("Ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.31, 0.29, 1)
    g.data.materials.append(gm)
    for nm, rot, e, col in (("Key", (55, 0, -35), 3.2, (1.0, 0.93, 0.85)), ("Fill", (70, 0, 140), 0.8, (0.8, 0.88, 1.0))):
        L = bpy.data.objects.new(nm, bpy.data.lights.new(nm, 'SUN'))
        L.data.energy = e
        L.data.color = col
        L.data.angle = math.radians(3)
        L.rotation_euler = tuple(math.radians(a) for a in rot)
        sc.collection.objects.link(L)
    sc.world = bpy.data.worlds.new("Sky")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.62, 0.72, 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    mid = sum(xs) / len(xs)
    cam.location = (mid, -4.4, 1.2)
    cam.data.lens = 42
    cam.rotation_euler = (Vector((mid, 0, 0.88)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 64
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
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.view_settings.view_transform = 'AgX'
    sc.render.image_settings.file_format = 'JPEG'
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    # faces: one close-up per person
    for k, spec in enumerate(CAST):
        h = bpy.data.objects[spec[0]]
        top = max((h.matrix_world @ Vector(c)).z for c in h.bound_box)
        fz = top - 0.11 * (top / 1.7)
        cam.location = (xs[k], -0.62 * (top / 1.7), fz)
        cam.data.lens = 70
        cam.rotation_euler = (Vector((xs[k], 0, fz - 0.01)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.resolution_x, sc.render.resolution_y = 800, 900
        sc.render.filepath = out.replace(".jpg", "_%s.jpg" % spec[0])
        bpy.ops.render.render(write_still=True)
    print("CAST rendered", out)


main()
