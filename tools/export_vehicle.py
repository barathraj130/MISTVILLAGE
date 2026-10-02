"""Run one or more of the user's Blender vehicle scripts in order and export only the vehicle
(meshes + wheel empties, modifiers applied; no cutters, floor, lights or cameras) to a GLB.

    Blender -b --factory-startup --python tools/export_vehicle.py -- <out.glb> <script.py> [script2.py ...]

    e.g. ... -- godot/assets/vehicles/luxury_suv.glb tools/luxury_suv.py tools/suv_interior.py
"""
import os
import sys
import bpy

args = sys.argv[sys.argv.index("--") + 1:]
out, scripts = os.path.abspath(args[0]), args[1:]
for s in scripts:
    exec(compile(open(s).read(), s, "exec"), {"__name__": "__main__"})

SKIP = ("ArchCutter", "INT_CabinCutter", "Plane", "Target", "INT_CamTarget")
# parts the game drives itself stay separate; everything else is merged into a few meshes so a
# car is a handful of draw calls instead of 160 (modifiers are applied first)
KEEP = ("Greenhouse", "Canopy", "Glass", "Headlight", "FogDRL", "TailCorner", "TailStrip", "TailBar",
        "INT_SteeringRim", "INT_SteeringHub", "INT_SteeringSpoke", "INT_SteeringBadge", "INT_Cluster",
        "INT_CenterScreen")
for o in list(bpy.data.objects):
    if o.type == 'MESH' and not o.name.startswith(SKIP):
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except RuntimeError:
                o.modifiers.remove(m)
groups = {}
for o in bpy.data.objects:
    if o.type != 'MESH' or o.parent is not None or o.name.startswith(SKIP) or o.name.startswith(KEEP):
        continue
    groups.setdefault("Interior" if o.name.startswith("INT_") else "Body", []).append(o)
for name, objs in groups.items():
    if len(objs) < 2:
        continue
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    bpy.context.view_layer.objects.active.name = name
for root in [o for o in bpy.data.objects if o.type == 'EMPTY' and o.name.startswith("Wheel_")]:
    kids = [c for c in root.children if c.type == 'MESH']
    if len(kids) > 1:
        bpy.ops.object.select_all(action='DESELECT')
        for k in kids:
            k.select_set(True)
        bpy.context.view_layer.objects.active = kids[0]
        bpy.ops.object.join()
bpy.ops.object.select_all(action='DESELECT')
picked = []
for o in bpy.data.objects:
    if o.type not in ('MESH', 'EMPTY') or o.name.startswith(SKIP):
        continue
    o.hide_set(False)
    o.select_set(True)
    picked.append(o.name)
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_apply=True,
                          export_yup=True, export_materials='EXPORT')
print("EXPORTED", out, len(picked), "objects")
