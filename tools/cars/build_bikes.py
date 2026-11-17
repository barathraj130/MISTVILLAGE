"""The two-wheelers you can ride (docs/VEHICLE_AUDIT_2026-11-17.md, Stage 5): the detailed commuter motorcycle and
step-through scooter of the rider scenes (tools/bikes_real.py: round-tube frame, engine with fins, exhaust, chain,
coil-spring shocks, forks, switchgear, levers, lamps), exported for the game as the drivable "bike" and "scooter"
(they were boxes built in code). Karthik's own scooter stays tools/story_scooter.py's.

    blender -b --factory-startup --python tools/cars/build_bikes.py -- [--export] [--preview dir]

Nose along +X, wheels Wheel_F / Wheel_R, the bar's parts named as jeep.gd's BAR_PARTS (they turn with the steering).
"""
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import bikes_real as BR  # noqa: E402
import carkit as K  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "godot", "assets", "vehicles")
BIKES = {"motorcycle": ("bike_ride.glb", (0.42, 0.015, 0.02)),     # a deep red commuter
         "scooter": ("scooter_ride.glb", (0.6, 0.6, 0.62))}        # a pearl white scooter


def export(root, path):
    bpy.ops.object.select_all(action='DESELECT')
    stack = [root]
    while stack:
        o = stack.pop()
        o.select_set(True)
        stack.extend(o.children)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_image_format='JPEG')
    print("BIKE exported %s (%.1f MB)" % (path, os.path.getsize(path) / 1e6), flush=True)


PLATES = {"motorcycle": ("TN 38 BX 2741", 12.0), "scooter": ("TN 66 F 9083", 10.0)}


def plates(root, kind):
    """The blank plate the rider scenes have, given a made-up registration (white, black letters)."""
    import math
    M = {"PlateWhite": K._mat("PlateWhite", (0.88, 0.88, 0.86), rough=0.4), "PlateText": K._mat("PlateText", (0.02, 0.02, 0.02), rough=0.5)}
    old = [o for o in bpy.data.objects if o.name.startswith("Plate") and not o.name.startswith("PlateBracket")]
    for o in old:
        bpy.context.view_layer.update()
        at = o.matrix_world.translation.copy()
        w, h = o.dimensions.y, o.dimensions.z
        tilt = math.radians(PLATES[kind][1])
        pl, tx = K.plate(M, "Plate", PLATES[kind][0], at, Vector((-1, 0, 0)), w=w, h=h)
        for ob in (pl, tx):
            ob.rotation_euler.y += tilt if ob is pl else 0.0
            ob.parent = root
        tx.location = at + Vector((-math.cos(tilt), 0, math.sin(tilt))) * 0.008
        tx.rotation_euler = (math.pi / 2, -tilt, -math.pi / 2)
        bpy.data.objects.remove(o)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for kind, (fname, paint) in BIKES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        root = bpy.data.objects.new("Bike", None)
        bpy.context.collection.objects.link(root)
        _, fit = BR.build(kind, root, paint)
        plates(root, kind)
        tris = 0
        dg = bpy.context.evaluated_depsgraph_get()
        for o in bpy.data.objects:
            if o.type in ('MESH', 'CURVE'):
                ev = o.evaluated_get(dg)
                me = ev.to_mesh()
                tris += sum(len(p.vertices) - 2 for p in me.polygons)
                ev.to_mesh_clear()
        print("BIKE %s: %d objects, ~%d triangles, fit %s" % (kind, len(bpy.data.objects), tris, fit), flush=True)
        if "--export" in args:
            export(root, os.path.abspath(os.path.join(OUT, fname)))
        if "--preview" in args:
            d = args[args.index("--preview") + 1]
            os.makedirs(d, exist_ok=True)
            K.previews(os.path.join(d, kind), target=Vector((0, 0, 0.6)), dist=3.2,
                       views={"front34": (35, 12), "side": (90, 4), "rear34": (150, 12), "front": (0, 6)})


main()
