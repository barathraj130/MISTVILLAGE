"""
Turn film-quality Poly Haven models (CC0) into light, game-ready GLBs for the drive.

    /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/make_game_props.py

Reads   mapdata/polyhaven/<asset>/<asset>.gltf  (1k textures, from api.polyhaven.com)
Writes  godot/assets/drive/props/<name>.glb             origin at the base centre, +Y up in Godot

Each entry picks some of the asset's objects, joins them, moves the origin to the bottom centre,
decimates to a triangle budget (textures and UVs are kept) and exports a GLB.
"""
import bpy, os
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "mapdata", "polyhaven")
OUT = os.path.join(ROOT, "godot", "assets", "drive", "props")
os.makedirs(OUT, exist_ok=True)

# name: (asset, object-name filter (prefix, or None for all), triangle budget)
JOBS = {
    "power_pole": ("modular_electricity_poles", "preset_02_", 3500),
    "road_barrier": ("concrete_road_barrier", None, 700),
    "street_lamp_head": ("street_lamp_02", None, 1800),
    "shutter": ("rollershutter_door", "rollershutter_door", 1200),
    "shutter_graffiti": ("rollershutter_door", "rollershutter_door_graffiti", 1200),
    "monobloc_chair": ("plastic_monobloc_chair_01", None, 3400),
    "utility_box": ("utility_box_01", None, 1000),
    "fern": ("fern_02", None, 6300),
}
for k in "abcd":
    JOBS["shrub_" + k] = ("shrub_02", "shrub_02_" + k, 3600)
for i in range(1, 7):
    JOBS["mossy_rock_%d" % i] = ("rock_moss_set_01", "rock_moss_set_01_rock%02d" % i, 900)


def tri_count(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


for name, (asset, filt, budget) in JOBS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, asset, asset + ".gltf"))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if filt:
        objs = [o for o in objs if o.name == filt or (filt.endswith("_") and o.name.startswith(filt))]
    if not objs:
        print("SKIP", name, "no objects match", filt)
        continue
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and o not in objs:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    # origin at the bottom centre
    pts = [Vector(c) for c in o.bound_box]
    base = Vector(((min(p.x for p in pts) + max(p.x for p in pts)) / 2,
                   (min(p.y for p in pts) + max(p.y for p in pts)) / 2, min(p.z for p in pts)))
    o.data.transform(__import__("mathutils").Matrix.Translation(-base))
    before = tri_count(o)
    for _ in range(5):                      # some meshes stop early; repeat until on budget
        if tri_count(o) <= budget * 1.15:
            break
        d = o.modifiers.new("decimate", "DECIMATE")
        d.ratio = budget / tri_count(o)
        d.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=d.name)
    for e in list(bpy.context.scene.objects):
        if e.type == "EMPTY":
            bpy.data.objects.remove(e, do_unlink=True)
    o.name = name
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=False,
                              export_apply=True, export_yup=True, export_image_format="JPEG", export_jpeg_quality=85)
    dims = o.dimensions
    print(f"PROP {name:18s} {before:7d} → {tri_count(o):6d} tris  size {dims.x:.2f} x {dims.y:.2f} x {dims.z:.2f} m")
