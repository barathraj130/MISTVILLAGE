"""
Render a vehicle's cabin from the driver's seat (and from the back seat) with its body around it.

    Blender -b --factory-startup --python tools/cabin_preview.py -- <out.jpg> <exterior.glb> <interior.glb>
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out, ext, inn = (os.path.abspath(a) for a in args[:3])
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
before = set(bpy.data.materials)
bpy.ops.import_scene.gltf(filepath=ext)
outer = [m for m in bpy.data.materials if m not in before]
bpy.ops.import_scene.gltf(filepath=inn)
# like the game: the body shell is one-sided, so from inside you see out wherever there's no trim
for m in outer:
    if not m.use_nodes or m.name.startswith("Glass"):
        continue
    nt = m.node_tree
    outp = nt.nodes.get("Material Output")
    src = outp.inputs["Surface"].links[0].from_socket if outp and outp.inputs["Surface"].links else None
    if src is None:
        continue
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(geo.outputs["Backfacing"], mix.inputs[0])
    nt.links.new(src, mix.inputs[1])
    nt.links.new(tr.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], outp.inputs["Surface"])
# see out through the glass (a light tint, like the game's)
for m in bpy.data.materials:
    if m.name.startswith("Glass") and m.use_nodes:
        nt = m.node_tree
        outp = nt.nodes.get("Material Output")
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        tr.inputs[0].default_value = (0.75, 0.8, 0.8, 1)
        nt.links.new(tr.outputs[0], outp.inputs["Surface"])
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, 0))
g = bpy.context.active_object
gm = bpy.data.materials.new("Ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.25, 0.27, 0.22, 1)
g.data.materials.append(gm)
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
sun.data.energy = 3.0
sun.data.angle = math.radians(2)
sun.rotation_euler = (math.radians(50), 0, math.radians(140))
sc.collection.objects.link(sun)
sc.world = bpy.data.worlds.new("Sky")
sc.world.use_nodes = True
wn = sc.world.node_tree
sky = wn.nodes.new("ShaderNodeTexSky")
sky.sky_type = 'MULTIPLE_SCATTERING'
sky.sun_elevation = math.radians(40)
sky.sun_disc = False
wn.links.new(sky.outputs[0], wn.nodes["Background"].inputs[0])
wn.nodes["Background"].inputs[1].default_value = 0.35
eye = bpy.data.objects.get("Eye")
e = eye.matrix_world.translation.copy() if eye else Vector((-0.6, -0.37, 1.15))
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.lens = 17
cam.location = e
cam.rotation_euler = (Vector((e.x + 1.0, e.y + 0.12, e.z - 0.22)) - e).to_track_quat('-Z', 'Y').to_euler()
sc.render.engine = 'CYCLES'
sc.cycles.samples = 48
sc.cycles.transparent_max_bounces = 16
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
sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
sc.view_settings.view_transform = 'AgX'
sc.view_settings.exposure = -0.6
sc.render.image_settings.file_format = 'JPEG'
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("PREVIEW", out)
# from the middle of the back seat, looking forward over the front seats
r = Vector((e.x - 0.95, 0.0, e.z - 0.02))
cam.location = r
cam.data.lens = 16
cam.rotation_euler = (Vector((r.x + 1.0, 0, r.z - 0.18)) - r).to_track_quat('-Z', 'Y').to_euler()
sc.render.filepath = out.replace(".jpg", "_rear.jpg")
bpy.ops.render.render(write_still=True)
print("PREVIEW", sc.render.filepath)
