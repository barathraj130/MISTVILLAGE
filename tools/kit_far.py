"""
Far versions of the designed buildings (godot/assets/buildings/<name>.glb → <name>_far.glb), for the city beyond
~180 m: the same shape, colours baked in (each face's texture layer becomes that texture's average colour times
its tint, glass a dark blue-grey, lit rooms warm), decimated to about 1,500 triangles. The game draws them with a
plain vertex-colour material, so the far city keeps the near city's houses, shops and mills instead of blocks.

    Blender -b --factory-startup --python tools/kit_far.py [-- names...]
"""
import json
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import buildings as B  # noqa: E402
import buildings_tn  # noqa: E402,F401  (adds the Coimbatore layers and tints)

DIR = os.path.join(HERE, "..", "godot", "assets", "buildings")
TARGET = 1500


def layer_colours():
    """layer index → average linear colour of its texture (the layers of shaders/building_kit.gdshader)"""
    M = B.materials()
    out = {}
    for name, li in B.KIT_LAYERS.items():
        if li in out:
            continue
        m = next((m for m in M.values() if m.name.split(".")[0] == name), None)
        img = None
        if m:
            for n in m.node_tree.nodes:
                if n.type == 'TEX_IMAGE' and n.image and n.image.colorspace_settings.name != "Non-Color":
                    img = n.image
                    break
        if img is not None and img.size[0] > 0:
            px = np.array(img.pixels[:]).reshape(-1, 4)[::97, :3]
            out[li] = px.mean(axis=0) ** 2.2          # image pixels are sRGB; vertex colours are linear
        else:
            out[li] = np.array([0.5, 0.5, 0.5])
    out[0] = np.array([1.0, 1.0, 1.0])
    return out


def far(name, avg):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(DIR, name + ".glb"))
    obs = [o for o in bpy.data.objects if o.type == 'MESH']
    if not obs:
        return
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    me = ob.data
    src = me.color_attributes.get("Col") or (me.color_attributes[0] if len(me.color_attributes) else None)
    n = len(me.loops)
    vals = np.zeros(n * 4)
    if src is not None:
        if src.domain == 'CORNER':
            src.data.foreach_get("color", vals)
        else:
            pv = np.zeros(len(me.vertices) * 4)
            src.data.foreach_get("color", pv)
            vi = np.zeros(n, dtype=int)
            me.loops.foreach_get("vertex_index", vi)
            vals = pv.reshape(-1, 4)[vi].ravel()
    c = vals.reshape(-1, 4)
    out = np.ones((n, 4))
    glass = {i for i, m in enumerate(me.materials) if m and m.name.startswith("KitGlass")}
    for p in me.polygons:
        for li in p.loop_indices:
            if p.material_index in glass:
                rgb = np.array([0.12, 0.15, 0.17])
            else:
                layer = int(round(c[li, 3] * 255))
                if layer >= 100:
                    rgb = np.array([0.75, 0.55, 0.35]) if layer == 100 else np.array([0.9, 0.85, 0.75])
                else:
                    rgb = c[li, :3] * avg.get(layer, np.array([0.6, 0.6, 0.6]))
            out[li, :3] = rgb
    col = me.color_attributes.new("FarCol", 'FLOAT_COLOR', 'CORNER')
    col.data.foreach_set("color", out.ravel())
    for nm in [a.name for a in me.color_attributes if a.name != "FarCol"]:
        me.color_attributes.remove(me.color_attributes[nm])
    me.color_attributes.active_color = me.color_attributes["FarCol"]
    me.color_attributes.render_color_index = me.color_attributes.active_color_index
    for nm in [a.name for a in me.attributes if a.domain == 'CORNER' and a.data_type in ('FLOAT_COLOR', 'BYTE_COLOR')
               and a.name != "FarCol"]:
        me.attributes.remove(me.attributes[nm])
    me.materials.clear()
    me.materials.append(bpy.data.materials.new("KitFar"))
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if tris > TARGET:
        d = ob.modifiers.new("Dec", 'DECIMATE')
        d.ratio = TARGET / tris
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier="Dec")
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    kw = dict(filepath=os.path.join(DIR, name + "_far.glb"), export_format='GLB', use_selection=True, export_apply=True,
              export_yup=True, export_materials='EXPORT')
    kw["export_vertex_color"] = 'ACTIVE'
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError:
        kw.pop("export_vertex_color")
        bpy.ops.export_scene.gltf(**kw)
    print("FAR", name, tris, "->", sum(len(p.vertices) - 2 for p in ob.data.polygons), flush=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = args or sorted(json.load(open(os.path.join(DIR, "manifest.json"))))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    B._M.clear()
    avg = layer_colours()
    print("LAYERS", {k: [round(x, 2) for x in v] for k, v in avg.items()}, flush=True)
    for nm in names:
        far(nm, avg)
