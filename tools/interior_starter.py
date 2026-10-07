"""
Starter .blend files for interior designers, and the export back to the game.

    # make art/interiors/<kind>_start.blend for every vehicle (or the ones listed)
    Blender -b --factory-startup --python tools/interior_starter.py -- start [hatchback sedan ...]

    # turn a designer's finished .blend into the game file godot/assets/vehicles/interior_<kind>.glb
    Blender -b --python tools/interior_starter.py -- export <kind> path/to/designed.blend

Each starter has three collections:
    REFERENCE exterior (locked)   the body the cabin must fit; never exported
    CABIN (design here)           the current game cabin to edit or replace, plus the markers
                                  Eye, SteeringPivot (wheel parts parented to it), Cluster
    PREVIEW                       a camera at Eye with the game's cockpit field of view, and a sun
"""
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VEH = os.path.join(ROOT, "godot", "assets", "vehicles")
OUT = os.path.join(ROOT, "art", "interiors")
SHELL = {"hatchback": "fleet_hatchback", "sedan": "fleet_sedan", "taxi": "fleet_sedan", "coupe": "coupe",
         "auto": "fleet_auto", "bus": "fleet_bus", "lorry": "fleet_lorry"}
NOTE = """THE MIST VILLAGE - vehicle interior: {kind}

Design inside the collection "CABIN (design here)". Do not move or export the REFERENCE.
Axes: +X = front, +Y = car's left, +Z = up, metres. Driver on the RIGHT (-Y).
Keep these empties (exact names):
  Eye            driver's eyes (camera "Driver view" looks from here)
  SteeringPivot  wheel centre; parent steering-wheel parts to it; its local Z = column toward the driver
  Cluster        centre of the instrument cluster (the game draws live gauges here)
Close the cabin: door cards, pillars, headliner, floor (the body is see-through from inside).
About 40k triangles, textures 2K or less, bake procedural textures, no logos.
Save the .blend and send it back - that's all.
Full guide: docs/VEHICLE_INTERIORS_GUIDE.md
"""


def coll(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(c)
    return c


def import_into(path, c):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for uc in list(o.users_collection):
            uc.objects.unlink(o)
        c.objects.link(o)
    return new


def start(kind):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'
    ref = coll("REFERENCE exterior (locked)")
    cab = coll("CABIN (design here)")
    prev = coll("PREVIEW")
    shell = os.path.join(VEH, SHELL[kind] + ".glb")
    for o in import_into(shell, ref):
        o.hide_select = True
        if o.type == 'MESH':
            for m in o.data.materials:
                if m:
                    m.use_backface_culling = True       # like the game: see out through the body from inside
        if o.type == 'MESH':
            o.display_type = 'WIRE' if "Glass" in o.name else 'SOLID'
    ref.hide_select = True
    cabin = os.path.join(VEH, "interior_%s.glb" % kind)
    if os.path.exists(cabin):
        import_into(cabin, cab)
    names = {o.name for o in cab.objects}
    for m in ("Eye", "SteeringPivot", "Cluster"):
        if m not in names:
            e = bpy.data.objects.new(m, None)
            e.empty_display_type = 'ARROWS'
            e.empty_display_size = 0.15
            e.location = {"Eye": (-0.3, -0.37, 1.2), "SteeringPivot": (0.25, -0.37, 0.9), "Cluster": (0.45, -0.37, 0.95)}[m]
            cab.objects.link(e)
    for o in cab.objects:
        if o.type == 'EMPTY':
            o.empty_display_size = 0.15
            o.show_name = True
    bpy.context.view_layer.update()                    # world positions of the imported markers
    eye = bpy.data.objects.get("Eye")
    cam = bpy.data.objects.new("Driver view", bpy.data.cameras.new("Driver view"))
    prev.objects.link(cam)
    cam.data.sensor_fit = 'VERTICAL'
    cam.data.angle = math.radians(74)                 # the game's cockpit field of view
    cam.data.clip_start = 0.05
    cam.location = eye.matrix_world.translation.copy()         # at the eyes, looking ahead and a little down
    cam.rotation_euler = Vector((1.0, 0.0, -0.18)).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(140))
    prev.objects.link(sun)
    t = bpy.data.texts.new("READ ME")
    t.write(NOTE.format(kind=kind))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "%s_start.blend" % kind)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
    print("STARTER", path)


def export(kind, blend):
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(blend))
    cab = bpy.data.collections.get("CABIN (design here)")
    if cab is None:
        raise SystemExit("no 'CABIN (design here)' collection in %s" % blend)
    missing = [m for m in ("Eye", "SteeringPivot", "Cluster") if m not in {o.name for o in cab.all_objects}]
    if missing:
        raise SystemExit("missing markers: %s" % ", ".join(missing))
    bpy.ops.object.select_all(action='DESELECT')
    for o in cab.all_objects:
        o.hide_set(False)
        o.select_set(True)
    out = os.path.join(VEH, "interior_%s.glb" % kind)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_apply=True, export_yup=True)
    tris = sum(len(p.vertices) - 2 for o in cab.all_objects if o.type == 'MESH' for p in o.data.polygons)
    print("EXPORTED", out, "tris", tris, "(budget ~40k for a car)")


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if args and args[0] == "export":
        export(args[1], args[2])
    else:
        for k in (args[1:] if len(args) > 1 else list(SHELL.keys())):
            start(k)
