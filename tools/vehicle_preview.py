"""
Render exported vehicles (.glb) on a road in daylight for review.

    Blender -b --factory-startup --python tools/vehicle_preview.py -- <out.jpg> a.glb [b.glb ...]

Vehicles stand side by side along X (nose +X), 3/4 front view.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out, glbs = os.path.abspath(args[0]), [os.path.abspath(a) for a in args[1:]]
HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "..", "godot", "assets", "drive", "tex")
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def tex_mat(name, stem, tile, tint=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    co = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1 / tile,) * 3
    nt.links.new(co.outputs["Object"], mp.inputs["Vector"])
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(os.path.join(TEX, stem + "_color.jpg"))
    nt.links.new(mp.outputs[0], t.inputs["Vector"])
    if tint:
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type, mix.blend_type = "RGBA", "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(t.outputs["Color"], mix.inputs[6])
        mix.inputs[7].default_value = (*tint, 1)
        nt.links.new(mix.outputs[2], p.inputs["Base Color"])
    else:
        nt.links.new(t.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.85
    return m


bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
road = bpy.context.active_object
road.scale = (80, 14, 1)
road.data.materials.append(tex_mat("Asphalt", "asphalt", 4.0, (0.38, 0.38, 0.4)))
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 40, -0.02))
g = bpy.context.active_object
g.scale = (300, 60, 1)
g.data.materials.append(tex_mat("Grass", "grass", 5.0, (0.8, 0.85, 0.7)))

x = 0.0
for path in glbs:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    xs = [(o.matrix_world @ Vector(c)).x for o in new if o.type == 'MESH' for c in o.bound_box]
    length = (max(xs) - min(xs)) if xs else 4.0
    root = bpy.data.objects.new("V", None)
    sc.collection.objects.link(root)
    for o in new:
        if o.parent is None:
            o.parent = root
    root.location = (x + length / 2, 0, 0)
    x += length + 1.6
mid = x / 2

sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
sun.data.energy = 3.2
sun.data.color = (1.0, 0.9, 0.78)
sun.data.angle = math.radians(1.0)
sun.rotation_euler = (math.radians(55), 0, math.radians(35))
sc.collection.objects.link(sun)
sc.world = bpy.data.worlds.new("Sky")
sc.world.use_nodes = True
wn = sc.world.node_tree
sky = wn.nodes.new("ShaderNodeTexSky")
sky.sky_type = 'MULTIPLE_SCATTERING'
sky.sun_elevation = math.radians(35)
sky.sun_disc = False
wn.links.new(sky.outputs[0], wn.nodes["Background"].inputs[0])
wn.nodes["Background"].inputs[1].default_value = 0.25

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
sc.collection.objects.link(cam)
sc.camera = cam
dist = max(x * 0.75, 7.0)
cam.location = (mid + dist * 0.55, -dist * 0.9, 1.6 + dist * 0.12)
cam.data.lens = 40
cam.rotation_euler = (Vector((mid, 0, 0.7)) - cam.location).to_track_quat('-Z', 'Y').to_euler()

sc.render.engine = 'CYCLES'
sc.cycles.samples = 64
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
sc.render.resolution_x, sc.render.resolution_y = 1600, 800
sc.view_settings.view_transform = 'AgX'
sc.view_settings.exposure = -0.3
sc.render.image_settings.file_format = 'JPEG'
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("PREVIEW", out)
