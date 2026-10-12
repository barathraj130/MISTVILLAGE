"""
Two-wheelers for the Coimbatore streets, in the fleet's lofted style (tools/fleet.py): a step-through scooter and
a commuter motorcycle at real sizes, no badges or names. +X is the nose, +Y the rider's left, Z up; standing on
the side stand (leaning a little to the left), as they are parked outside every house and shop.

    Blender -b --factory-startup --python tools/twowheeler.py -- --preview <out.jpg>
    Blender -b --factory-startup --python tools/twowheeler.py -- --export godot/assets/vehicles
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fleet as F  # noqa: E402

LEAN = math.radians(7.0)            # parked on the side stand


def front_wheel(name, x, R, M):
    return F.wheel(name, (x, 0.05, R), R, 0.09, M, True, spokes=5)


def scooter(M, paint):
    R = 0.25
    body = F.loft("Body", [(-0.88, 0.1, 0.42, 0.6, 0), (-0.8, 0.17, 0.33, 0.74, 0), (-0.55, 0.21, 0.3, 0.8, 0),
                           (-0.28, 0.2, 0.3, 0.76, 0), (-0.12, 0.15, 0.3, 0.62, 0)], paint, n_top=3.5, n_bot=5.0)
    F.box("Floor", (0.1, 0, 0.31), (0.5, 0.32, 0.05), M["black"], bev=0.02)
    F.box("FloorMat", (0.1, 0, 0.338), (0.46, 0.28, 0.008), M["under"], bev=0.002)
    # leg shield / front apron rising to the handlebar, the panel the scooter is known by
    F.loft("Apron", [(0.3, 0.18, 0.28, 0.5, 0), (0.42, 0.25, 0.3, 0.88, 0), (0.48, 0.24, 0.5, 1.02, 0),
                     (0.52, 0.16, 0.7, 1.06, 0)], paint, n_top=3.0, n_bot=3.0, segs=24)
    F.loft("Mudguard", [(0.45, 0.07, 0.42, 0.56, 0), (0.62, 0.09, 0.5, 0.58, 0), (0.8, 0.08, 0.4, 0.52, 0)], paint,
           n_top=2.5, n_bot=8.0, segs=16)
    # handlebar cowl with the headlamp, the grips, levers and mirrors
    F.loft("Cowl", [(0.38, 0.12, 1.02, 1.12, 0), (0.48, 0.34, 1.0, 1.14, 0), (0.6, 0.2, 1.0, 1.12, 0)], paint,
           n_top=3.0, n_bot=4.0, segs=24)
    F.box("Headlight", (0.6, 0, 1.06), (0.04, 0.18, 0.07), M["head"], bev=0.02)
    for s in (1, -1):
        F.cyl("Grip", (0.45, s * 0.4, 1.06), 0.02, 0.12, M["black"], rot=(math.pi / 2, 0, 0), verts=12)
        F.beam("Lever", (0.48, s * 0.3, 1.08), (0.43, s * 0.42, 1.07), 0.012, 0.01, M["chrome"])
        F.beam("MirrorStem", (0.45, s * 0.28, 1.1), (0.4, s * 0.33, 1.32), 0.012, 0.012, M["chrome"])
        F.box("Mirror", (0.4, s * 0.35, 1.34), (0.03, 0.12, 0.08), M["black"], bev=0.015)
        F.box("Indicator", (0.58, s * 0.24, 1.04), (0.03, 0.05, 0.03), M["amber"], bev=0.01)
        F.box("IndicatorR", (-0.86, s * 0.14, 0.62), (0.03, 0.04, 0.03), M["amber"], bev=0.01)
    F.beam("Bar", (0.45, 0.42, 1.06), (0.45, -0.42, 1.06), 0.022, 0.022, M["chrome"])
    F.box("Speedo", (0.47, 0, 1.15), (0.08, 0.16, 0.02), M["lens"], bev=0.01, rot=(0, math.radians(-30), 0))
    # fork down to the front wheel
    for s in (1, -1):
        F.beam("Fork", (0.5, s * 0.07, 0.95), (0.66, s * 0.07, R), 0.035, 0.035, M["chrome"])
    # the seat, a grab rail, the tail lamp and plate
    F.loft("Seat", [(-0.8, 0.12, 0.76, 0.84, 0), (-0.6, 0.17, 0.78, 0.88, 0), (-0.3, 0.17, 0.77, 0.87, 0),
                    (-0.12, 0.14, 0.74, 0.82, 0)], M["seat"], n_top=3.0, n_bot=6.0, segs=24)
    F.beam("Rail", (-0.86, 0.14, 0.78), (-0.6, 0.18, 0.77), 0.025, 0.02, M["black"])
    F.beam("Rail", (-0.86, -0.14, 0.78), (-0.6, -0.18, 0.77), 0.025, 0.02, M["black"])
    F.box("TailBar", (-0.89, 0, 0.63), (0.02, 0.16, 0.05), M["tail"], bev=0.01)
    F.box("Plate", (-0.88, 0, 0.5), (0.01, 0.2, 0.1), M["plate"], bev=0.002)
    # engine and silencer on the right, rear wheel, side stand on the left
    F.box("Engine", (-0.48, -0.08, 0.32), (0.4, 0.16, 0.18), M["under"], bev=0.04)
    F.cyl("Silencer", (-0.62, -0.2, 0.36), 0.05, 0.36, M["steel"], rot=(0, math.pi / 2, 0), verts=14)
    F.beam("Stand", (-0.1, 0.12, 0.3), (-0.18, 0.28, 0.0), 0.025, 0.025, M["black"])
    front_wheel("Wheel_F", 0.66, R, M)
    F.wheel("Wheel_R", (-0.62, 0.05, R), R, 0.1, M, True, spokes=5)
    return body


def motorcycle(M, paint):
    R = 0.3
    F.loft("Tank", [(0.0, 0.12, 0.78, 0.92, 0), (0.18, 0.18, 0.74, 1.0, 0), (0.38, 0.17, 0.78, 1.02, 0),
                    (0.5, 0.1, 0.84, 0.98, 0)], paint, n_top=3.0, n_bot=4.0, segs=24)
    F.loft("SidePanel", [(-0.36, 0.13, 0.58, 0.78, 0), (-0.12, 0.15, 0.56, 0.8, 0), (0.0, 0.12, 0.6, 0.8, 0)], paint,
           n_top=4.0, n_bot=4.0, segs=20)
    F.loft("Seat", [(-0.62, 0.1, 0.8, 0.88, 0), (-0.4, 0.15, 0.8, 0.92, 0), (-0.05, 0.15, 0.82, 0.95, 0),
                    (0.05, 0.12, 0.84, 0.94, 0)], M["seat"], n_top=3.0, n_bot=6.0, segs=24)
    F.loft("Tail", [(-0.85, 0.06, 0.74, 0.8, 0), (-0.7, 0.1, 0.72, 0.84, 0), (-0.55, 0.12, 0.7, 0.82, 0)], paint,
           n_top=3.0, n_bot=4.0, segs=16)
    F.box("TailBar", (-0.86, 0, 0.75), (0.02, 0.1, 0.04), M["tail"], bev=0.01)
    F.box("Plate", (-0.84, 0, 0.6), (0.01, 0.2, 0.11), M["plate"], bev=0.002, rot=(0, math.radians(15), 0))
    F.loft("RearGuard", [(-0.86, 0.06, 0.55, 0.62, 0), (-0.6, 0.07, 0.62, 0.66, 0)], M["black"], n_top=2.0, n_bot=6.0, segs=12)
    # engine: crankcase, cylinder with fins, the frame tubes round it
    F.box("Crankcase", (0.1, 0, 0.38), (0.34, 0.22, 0.24), M["steel"], bev=0.04)
    F.box("Cylinder", (0.28, 0, 0.56), (0.14, 0.14, 0.22), M["under"], bev=0.02, rot=(0, math.radians(-25), 0))
    for k in range(5):
        F.box("Fin", (0.29 + k * 0.012, 0, 0.48 + k * 0.035), (0.2, 0.2, 0.012), M["steel"], bev=0, rot=(0, math.radians(-25), 0))
    F.beam("Frame", (0.52, 0, 0.98), (0.3, 0, 0.32), 0.05, 0.05, M["black"])
    F.beam("Frame", (0.52, 0, 0.98), (-0.2, 0, 0.78), 0.05, 0.05, M["black"])
    F.beam("Frame", (-0.2, 0, 0.78), (-0.15, 0, 0.32), 0.05, 0.05, M["black"])
    F.beam("Exhaust", (0.36, -0.08, 0.5), (0.1, -0.16, 0.26), 0.04, 0.04, M["chrome"])
    F.cyl("Silencer", (-0.42, -0.17, 0.32), 0.05, 0.6, M["chrome"], rot=(0, math.pi / 2 - 0.12, 0), verts=14)
    F.box("ChainGuard", (-0.32, 0.1, 0.33), (0.62, 0.03, 0.08), M["black"], bev=0.01)
    # swingarm and shocks
    for s in (1, -1):
        F.beam("Swingarm", (-0.12, s * 0.09, 0.34), (-0.66, s * 0.09, R), 0.04, 0.04, M["black"])
        F.beam("Shock", (-0.58, s * 0.11, 0.33), (-0.52, s * 0.11, 0.76), 0.035, 0.035, M["chrome"])
    # front: telescopic forks, round headlamp in its bezel, handlebar, mirrors
    for s in (1, -1):
        F.beam("Fork", (0.58, s * 0.09, 1.0), (0.78, s * 0.09, R), 0.035, 0.035, M["chrome"])
        F.cyl("Grip", (0.48, s * 0.36, 1.1), 0.02, 0.12, M["black"], rot=(math.pi / 2, 0, 0), verts=12)
        F.beam("MirrorStem", (0.52, s * 0.24, 1.1), (0.48, s * 0.3, 1.32), 0.012, 0.012, M["chrome"])
        F.box("Mirror", (0.48, s * 0.31, 1.34), (0.03, 0.1, 0.07), M["black"], bev=0.015)
        F.box("Indicator", (0.66, s * 0.16, 0.92), (0.04, 0.04, 0.03), M["amber"], bev=0.01)
        F.box("IndicatorR", (-0.84, s * 0.12, 0.7), (0.04, 0.04, 0.03), M["amber"], bev=0.01)
    F.beam("Handlebar", (0.52, 0.36, 1.1), (0.52, -0.36, 1.1), 0.025, 0.025, M["chrome"])
    F.lathe("Bezel", [(0.1, -0.04), (0.11, 0.0), (0.1, 0.04), (0.0, 0.045)], M["chrome"], 24).rotation_euler = (0, 0, -math.pi / 2)
    bpy.context.active_object.location = (0.68, 0, 0.95)
    F.lathe("Headlight", [(0.09, 0.045), (0.06, 0.06), (0.0, 0.065)], M["head"], 24).rotation_euler = (0, 0, -math.pi / 2)
    for o in bpy.data.objects:
        if o.name.startswith(("Bezel", "Headlight")) and o.location.length < 0.01:
            o.location = (0.68, 0, 0.95)
    F.box("Speedo", (0.56, 0, 1.08), (0.06, 0.12, 0.08), M["black"], bev=0.02)
    F.loft("Mudguard", [(0.62, 0.06, 0.52, 0.6, 0), (0.8, 0.07, 0.58, 0.64, 0), (0.98, 0.06, 0.46, 0.54, 0)], paint,
           n_top=2.5, n_bot=8.0, segs=16)
    F.beam("Stand", (0.0, 0.12, 0.3), (-0.08, 0.3, 0.0), 0.025, 0.025, M["black"])
    F.wheel("Wheel_F", (0.8, 0.05, R), R, 0.09, M, True, spokes=6)
    F.wheel("Wheel_R", (-0.66, 0.05, R), R, 0.11, M, True, spokes=6)


KINDS = {"scooter": (scooter, [(0.75, 0.75, 0.73), (0.55, 0.06, 0.06), (0.05, 0.1, 0.3), (0.02, 0.02, 0.02)]),
         "motorcycle": (motorcycle, [(0.03, 0.03, 0.03), (0.45, 0.04, 0.04), (0.08, 0.15, 0.4), (0.5, 0.5, 0.52)])}


def build(kind, colour_i=0, at=(0, 0, 0), rz=0.0):
    """One parked two-wheeler, grouped under an empty that leans it on its stand."""
    fn, colours = KINDS[kind]
    M = F.mats(colours[colour_i % len(colours)])
    paint = M["paint"].copy()                           # each bike its own colour ("Paint…" for the game to tint)
    paint.name = "Paint_%s_%d" % (kind, colour_i)
    before = set(bpy.data.objects)
    fn(M, paint)
    root = F.link(bpy.data.objects.new(kind, None))
    for o in bpy.data.objects:
        if o not in before and o is not root and o.parent is None:
            o.parent = root
    root.rotation_euler = (LEAN, 0, rz)
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
    sc.world = bpy.data.worlds.new("Sky")
    sc.world.use_nodes = True
    sky = sc.world.node_tree.nodes.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_elevation = math.radians(35)
    sky.sun_rotation = math.radians(-120)
    sc.world.node_tree.links.new(sky.outputs[0], sc.world.node_tree.nodes["Background"].inputs[0])
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.12
    sc.view_settings.exposure = -0.6
    ground = F.box("Ground", (0, 0, -0.05), (12, 8, 0.1), F.make_mat("Pavers", (0.2, 0.19, 0.17), rough=0.85), bev=0)
    F.box("Wall", (-1.5, 3.2, 0.75), (10, 0.25, 1.5), F.make_mat("WallPaint", (0.75, 0.45, 0.45), rough=0.9), bev=0)
    _ = ground
    build("scooter", 0, (-0.2, 0.9, 0), math.radians(-20))
    build("motorcycle", 1, (0.2, -0.9, 0), math.radians(-20))
    build("scooter", 2, (-2.6, 1.0, 0), math.radians(-20))
    build("motorcycle", 2, (-2.4, -0.9, 0), math.radians(-20))
    cam = F.link(bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")))
    cam.data.lens = 40
    cam.location = (3.4, -3.6, 1.5)
    cam.rotation_euler = (Vector((-0.9, 0.0, 0.55)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--preview" in args:
        preview(os.path.abspath(args[args.index("--preview") + 1]))
    if "--export" in args:
        out = os.path.abspath(args[args.index("--export") + 1])
        for kind in KINDS:
            for ci in range(4):                      # four paint colours each, one joined mesh, leaning on its stand
                F.reset()
                root = build(kind, ci)
                bpy.context.view_layer.update()
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
                bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
                bpy.ops.object.join()
                ob = bpy.context.view_layer.objects.active
                d = ob.modifiers.new("Dec", 'DECIMATE')            # a parked bike seen from the street: ~4,000 tris
                d.ratio = min(1.0, 4000 / max(1, len(ob.data.polygons)))
                bpy.ops.object.modifier_apply(modifier="Dec")
                name = "bike_%s_%d" % (kind, ci)
                bpy.context.view_layer.objects.active.name = name
                bpy.ops.export_scene.gltf(filepath=os.path.join(out, name + ".glb"), export_format='GLB',
                                          use_selection=True, export_apply=True, export_yup=True)
                print("BIKE", name, sum(len(p.vertices) - 2 for p in bpy.context.view_layer.objects.active.data.polygons), flush=True)
