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
