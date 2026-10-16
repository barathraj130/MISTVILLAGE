"""
Export the street-life props and the natural trees and bushes for the game (godot/assets/city_props/life_*.glb,
godot/assets/city_props/veg_*.glb). Each prop is the same model the Blender street reference uses
(tools/streetlife.py, tools/vegetation.py), standing on its origin, local +X along the street, -Y towards the road.

    Blender -b --factory-startup --python tools/export_life.py
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import streetlife as SL  # noqa: E402
import vegetation as VG  # noqa: E402

OUT = os.path.join(HERE, "..", "godot", "assets", "city_props")

PROPS = {
    "pole": SL.pole_collection, "stall0": lambda: SL.stall_collection(0), "stall1": lambda: SL.stall_collection(1),
    "thatched": lambda: SL.stall_collection(2, thatch=True), "flex0": lambda: SL.flex_collection_k(0),
    "flex1": lambda: SL.flex_collection_k(1), "flex2": lambda: SL.flex_collection_k(2), "shade0": lambda: SL.shade_collection(0),
    "shade1": lambda: SL.shade_collection(1), "shade2": lambda: SL.shade_collection(2), "goods": SL.goods_collection,
    "cart": SL.cart_collection, "flowers": SL.flower_collection, "sign": SL.sign_collection, "bin": SL.bin_collection,
    "bench": SL.bench_collection, "drums": SL.drum_collection, "kolam0": lambda: SL.kolam_collection(0),
    "kolam1": lambda: SL.kolam_collection(1), "transformer": SL.transformer_collection, "shrine": SL.shrine_collection,
    "school": SL.school_sign_collection, "manhole": SL.manhole_collection, "bollard": SL.bollard_collection,
}
VEG = {"neem1": lambda: VG.neem(1), "neem2": lambda: VG.neem(2), "rain1": lambda: VG.raintree(1),
       "gul1": lambda: VG.gulmohar(1), "bush1": lambda: VG.bush(1), "bush2": lambda: VG.bush(2), "bush3": lambda: VG.bush(3),
       "grass": lambda: VG.grass_tuft(1)}


def export_objects(objs, path):
    bpy.ops.object.select_all(action='DESELECT')
    meshes = [o for o in objs if o.type == 'MESH']
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    for o in meshes:
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except RuntimeError:
                o.modifiers.remove(m)
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in PROPS.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        coll = fn()
        bpy.context.scene.collection.children.link(coll)
        export_objects(list(coll.all_objects), os.path.join(OUT, "life_%s.glb" % name))
        print("LIFE", name, flush=True)
    for name, fn in VEG.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        VG._M.clear()                                       # the material cache dies with each fresh scene
        ob = fn()
        export_objects([ob], os.path.join(OUT, "veg_%s.glb" % name))
        print("VEG", name, len(ob.data.polygons), flush=True)


if __name__ == "__main__":
    main()
