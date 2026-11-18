"""Bake a model's ambient occlusion (the contact shading in corners, under eaves, round doors and steps: the light
the open sky can't reach, whatever the sun is doing) into a texture on a second UV map, and write a copy of the model
that carries it as glTF's occlusion texture. Godot applies a material's AO to ambient light only, so the sun, its
shadows and the game's morning-to-night lighting stay as they are.

    blender -b --factory-startup --python tools/bake/bake_ao.py -- IN.glb OUT.glb [--texel 20] [--max 2048]
            [--samples 96] [--dist 1.2] [--preview DIR]

The original IN.glb is left untouched; OUT.glb (by convention NAME_ao.glb beside it) is what the game loads when it
exists (city_streamer.gd, city_doors.gd; --noao loads the originals). Per mesh object: a second UV map "AO" (islands of
connected faces, no two surfaces sharing texels), an image sized to its area (texel px per metre,
power of two, 128..max), Cycles' AO bake (rays to dist metres: contact shading, not whole-building darkening),
padded at the islands' edges (no dark seams), its materials made the object's own and given the image as occlusion.
Glass, lamps and emissive surfaces are left out (no AO on light).
"""
import math
import os
import sys

import bmesh
import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = argv[0], argv[1]


def opt(name, default):
    return type(default)(argv[argv.index(name) + 1]) if name in argv else default


TEXEL = opt("--texel", 20.0)
MAXRES = opt("--max", 2048)
SAMPLES = opt("--samples", 96)
DIST = opt("--dist", 1.2)
PREVIEW = opt("--preview", "")
SKIP = ("glass", "lamp", "light", "bulb", "screen", "led", "drl", "emiss", "sign", "neon", "water")


def skip_mat(m):
    if m is None:
        return True
    n = m.name.lower()
    if any(k in n for k in SKIP):
        return True
    if m.use_nodes:
        for nd in m.node_tree.nodes:
            if nd.type == 'BSDF_PRINCIPLED':
                if nd.inputs["Alpha"].default_value < 0.99:
                    return True
                es = nd.inputs.get("Emission Strength")
                if es is not None and es.default_value > 0.0 and not nd.inputs["Emission Color"].is_linked \
                        and tuple(nd.inputs["Emission Color"].default_value)[:3] != (0.0, 0.0, 0.0):
                    return True
    return False


def gltf_output_group():
    """The node group the glTF exporter reads extra channels from (its Occlusion input)."""
    g = bpy.data.node_groups.get("glTF Material Output")
    if g is None:
        g = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        g.interface.new_socket("Occlusion", in_out='INPUT', socket_type='NodeSocketFloat')
        g.interface.new_socket("Thickness", in_out='INPUT', socket_type='NodeSocketFloat')
    return g


def area(o):
    me = o.data
    s = 0.0
    sc = o.matrix_world.to_scale()
    k = abs(sc.x * sc.y * sc.z) ** (2.0 / 3.0)
    for p in me.polygons:
        s += p.area
    return s * k


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    try:                                                   # (the M1's GPU through Metal, if Cycles has it)
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = 'GPU'
    except Exception:
        sc.cycles.device = 'CPU'
    w = bpy.data.worlds.new("AOWorld")                     # (AO doesn't use lights; a world keeps the baker happy)
    sc.world = w
    w.light_settings.distance = DIST
    sc.render.bake.margin = 16                             # (padding past each island: no dark seams at its edges)
    sc.render.bake.margin_type = 'EXTEND'
    group = gltf_output_group()
    meshes = [o for o in sc.objects if o.type == 'MESH' and len(o.data.polygons) > 0]
    tex_dir = opt("--texdir", os.path.join(os.environ.get("TMPDIR", "/tmp"), "bake_ao"))   # (the PNGs: also inside OUT.glb)
    os.makedirs(tex_dir, exist_ok=True)
    baked = 0
    for o in meshes:
        mats = [s.material for s in o.material_slots]
        if not mats or all(skip_mat(m) for m in mats):
            continue
        if o.data.users > 1:                               # (AO is where a thing stands: each copy its own)
            o.data = o.data.copy()
        me = o.data
        # Godot reads two UV sets (UV, UV2); the baked occlusion must be the second. Extra sets the materials don't
        # use (the importer's leftovers) are dropped first, so "AO" lands at index 1.
        used = set()
        for m in mats:
            if m and m.use_nodes:
                for nd in m.node_tree.nodes:
                    if nd.type == 'UVMAP' and nd.uv_map:
                        used.add(nd.uv_map)
        for layer in list(me.uv_layers)[1:]:
            if layer.name not in used and layer.name != "AO":
                me.uv_layers.remove(layer)
        if len(me.uv_layers) > 1 and me.uv_layers[1].name != "AO":
            print("BAKE %s: its second UV set (%s) is in use: AO would be a third, skipped" % (o.name, me.uv_layers[1].name), flush=True)
            continue
        if "AO" not in me.uv_layers:
            uv = me.uv_layers.new(name="AO")
        me.uv_layers.active = me.uv_layers["AO"]
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        # (islands of connected faces, split only at sharp turns: few vertices split, so the mesh doesn't grow
        #  much; lightmap packing every face alone nearly tripled the bunk's vertices)
        bpy.ops.uv.smart_project(angle_limit=math.radians(60.0), island_margin=0.004, area_weight=0.0, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode='OBJECT')
        res = 2 ** int(round(math.log2(max(128, min(MAXRES, math.sqrt(area(o)) * TEXEL)))))
        img = bpy.data.images.new(o.name + "_ao", res, res, alpha=False)
        img.generated_color = (1, 1, 1, 1)
        nodes_for = []
        for i, s in enumerate(o.material_slots):
            m = s.material
            if skip_mat(m):
                continue
            m = m.copy()                                   # (the object's own: its own AO image)
            m.name = (s.material.name + "_" + o.name)[:60]
            s.material = m
            m.use_nodes = True
            nt = m.node_tree
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = img
            t.interpolation = 'Linear'
            nt.nodes.active = t                            # (the bake writes into the active image node)
            nodes_for.append((m, t))
        if not nodes_for:
            continue
        # (not cleared: the space between the islands stays white, "no shading", so the blurred mip levels the game
        #  samples from a distance don't bleed black into every island)
        bpy.ops.object.bake(type='AO', use_clear=False, margin=16)
        img.filepath_raw = os.path.join(tex_dir, img.name + ".png")
        img.file_format = 'PNG'
        img.save()
        for m, t in nodes_for:                             # the image as the material's glTF occlusion, on UV "AO"
            nt = m.node_tree
            uvn = nt.nodes.new("ShaderNodeUVMap")
            uvn.uv_map = "AO"
            nt.links.new(uvn.outputs["UV"], t.inputs["Vector"])
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(t.outputs["Color"], sep.inputs["Color"])
            gn = nt.nodes.new("ShaderNodeGroup")
            gn.node_tree = group
            nt.links.new(sep.outputs[0], gn.inputs["Occlusion"])
        me.uv_layers.active = me.uv_layers[0]
        baked += 1
        print("BAKE %s: %d faces, %.0f m², %d px" % (o.name, len(me.polygons), area(o), res), flush=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=False, export_image_format='JPEG', export_image_quality=90)
    print("BAKE done: %d of %d objects, written %s (%.1f MB; the original %.1f MB)" % (baked, len(meshes), DST,
          os.path.getsize(DST) / 1e6, os.path.getsize(SRC) / 1e6), flush=True)


main()
