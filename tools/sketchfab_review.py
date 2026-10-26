"""
Line up downloaded Sketchfab models (.glb) side by side for a design check.

    Blender -b --factory-startup --python tools/sketchfab_review.py -- <out.jpg> <height_m|0> a.glb [b.glb ...]

Each model is scaled so its height is <height_m> (0 keeps its own size), stood on the floor,
labelled with its file name, and the native size is printed so we can see the units it came in.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out, height = os.path.abspath(args[0]), float(args[1])
glbs = [os.path.abspath(a) for a in args[2:]]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def bounds(objs):
    """World bounds of the posed (evaluated) meshes that render."""
    dg = bpy.context.evaluated_depsgraph_get()
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in objs:
        if o.type != "MESH" or o.hide_render or not o.visible_get():
            continue
        e = o.evaluated_get(dg)
        me = e.to_mesh()
        mw = e.matrix_world
        for v in me.vertices:
            w = mw @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
        e.to_mesh_clear()
    return lo, hi


cols = max(1, math.ceil(math.sqrt(len(glbs) * 1.8)))
cell = 1.0
gap = 1.15 if height > 0 else 1.45  # people stand in rows seen from the front
for k, path in enumerate(glbs):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.animation_data:
            o.animation_data.action = None
        if o.type == "ARMATURE":
            o.data.pose_position = "REST"
    bpy.context.view_layer.update()
    roots = [o for o in new if o.parent is None]
    lo, hi = bounds(new)
    size = hi - lo
    name = os.path.basename(path)[:-4]
    print(f"MODEL {name}: size {size.x:.2f} x {size.y:.2f} x {size.z:.2f}")
    # every model fills its cell; people (height > 0) by height so they compare
    s = (cell * 0.9 / size.z) if height > 0 else cell * 0.85 / max(size)
    piv = bpy.data.objects.new("pivot_" + name, None)
    sc.collection.objects.link(piv)
    for r in roots:
        r.parent = piv
        r.matrix_parent_inverse.identity()
    cx, cy = (k % cols) * cell * 1.15, -(k // cols) * cell * gap
    piv.scale = (s,) * 3
    piv.location = (cx - (lo.x + hi.x) / 2 * s, cy - (lo.y + hi.y) / 2 * s, -lo.z * s + (k // cols) * (cell * 1.05 if height > 0 else 0))
    bpy.ops.object.text_add(location=(cx, cy - 0.45, 0.002))
    t = bpy.context.object
    t.data.body = f"{name[:24]}\n{size.x:.2f}x{size.y:.2f}x{size.z:.2f}"
    t.data.align_x = "CENTER"
    t.data.size = 0.06
    t.data.extrude = 0.004
    tm = bpy.data.materials.new("label")
    tm.diffuse_color = (0.05, 0.05, 0.05, 1)
    t.data.materials.append(tm)

rows = math.ceil(len(glbs) / cols)
w, h = (cols - 1) * 1.15, (rows - 1) * gap
bpy.ops.mesh.primitive_plane_add(size=1, location=(w / 2, -h / 2, 0))
fl = bpy.context.object
fl.scale = (w + 6, h + 6, 1)
m = bpy.data.materials.new("floor")
m.diffuse_color = (0.62, 0.62, 0.6, 1)
fl.data.materials.append(m)

cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
cam.data.type = "ORTHO"
cam.data.ortho_scale = max(w + 1.4, (h + 2.0) * 16 / 9 * 0.75)
tilt = 84 if height > 0 else 68
cam.rotation_euler = (math.radians(tilt), 0, 0)
up = (rows * cell * 1.05 / 2) if height > 0 else 0.5
cam.location = (w / 2, -h / 2 - 12 * math.sin(math.radians(tilt)) - 0.6, 12 * math.cos(math.radians(tilt)) + up)
if height > 0:
    cam.data.ortho_scale = max(w + 1.4, rows * 1.15 * 16 / 9)
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 2.2
sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
sc.collection.objects.link(sun)
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.8, 0.88, 1)
sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
sc.camera = cam
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
sc.view_settings.view_transform = "Standard"
sc.render.image_settings.file_format = "JPEG"
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("WROTE", out)
