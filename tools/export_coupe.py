"""Build the sports coupe with tools/coupe.py (the user's generator) and export just the car
to godot/assets/vehicles/coupe.glb: modifiers applied (wheel arches cut, subdivided), wheels
kept as separate Wheel_FL/FR/RL/RR nodes so the game can spin and steer them.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python tools/export_coupe.py
"""
import os
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "godot", "assets", "vehicles", "coupe.glb")

exec(compile(open(os.path.join(HERE, "coupe.py")).read(), "coupe.py", "exec"))

# keep only the car: body, canopy, wheels (+ their parts), lamps
keep_roots = {"Body", "Canopy", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR", "Headlight", "Headlight.001", "TailBar"}
car = set()
for o in bpy.data.objects:
    root = o
    while root.parent:
        root = root.parent
    if root.name in keep_roots:
        car.add(o)
bpy.ops.object.select_all(action='DESELECT')
for o in car:
    o.select_set(True)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_apply=True,
                          export_yup=True, export_materials='EXPORT')
print("EXPORTED", OUT, sorted(o.name for o in car if o.parent is None))
