"""Quick look at GNM heads: four female faces (a South Indian blend), smiling, in a soft light.
    Blender -b --factory-startup --python tools/humans/gnm_test.py -- out.jpg"""
import math, os, sys
import bpy
import numpy as np
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gnm_head as G

out = sys.argv[sys.argv.index("--") + 1]
sc = bpy.context.scene
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
CLOSE = os.environ.get("CLOSE")
for k in ([int(CLOSE)] if CLOSE else range(3)):
    import quality as Q, random
    h = G.build_head(np.random.default_rng(201 + k), female=1.0, ethnicity=dict(middle_eastern=.55, black=.25, white=.2), smile=0.12, tone=(0.31 - 0.03 * k, 0.175 - 0.02 * k, 0.105 - 0.012 * k))
    extra = G.brows_and_lashes(h, random.Random(k), True)
    if CLOSE:
        extra.append(G.peach_fuzz(h, np.random.default_rng(k)))
    lm = G.lm_of(h)
    extra.append(Q.long_hair(h, lm, random.Random(k), length=0.36, children=60000, melanin=0.95, part=(-0.5, 0.0, 0.6, -0.2)[k]))
    for o in [h] + extra:
        o.location.x = 0.0 if CLOSE else (k - 1) * 0.34
sc.render.engine = 'CYCLES'
sc.cycles.samples = 128
sc.cycles.use_denoising = True
sc.cycles.denoising_input_passes = 'RGB_ALBEDO_NORMAL'
sc.cycles.denoising_prefilter = 'ACCURATE'
try:
    pr = bpy.context.preferences.addons["cycles"].preferences
    pr.compute_device_type = 'METAL'; pr.get_devices()
    for d in pr.devices: d.use = True
    sc.cycles.device = 'GPU'
except Exception:
    pass
sc.view_settings.view_transform = 'AgX'
sc.render.image_settings.file_format = 'JPEG'
sc.render.resolution_x, sc.render.resolution_y = 1600, 900
sc.view_settings.look = 'AgX - Medium High Contrast'
sc.world = bpy.data.worlds.new("W"); sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.045, 0.04, 1)
sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
bg = bpy.data.objects.new("Backdrop", bpy.data.meshes.new("Backdrop")); sc.collection.objects.link(bg)
bg.data.from_pydata([(-3, 2.5, -2), (3, 2.5, -2), (3, 2.5, 3), (-3, 2.5, 3)], [], [(0, 1, 2, 3)])
bm = bpy.data.materials.new("Backdrop"); bm.use_nodes = True
bm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.035, 0.03, 0.027, 1)
bm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
bg.data.materials.append(bm)
for name, loc, e, s_, col in (("Key", (-1.1, -1.2, 0.9), 55.0, 1.4, (1.0, 0.9, 0.8)),
                              ("Fill", (1.3, -1.1, 0.25), 9.0, 1.8, (0.85, 0.9, 1.0)),
                              ("Rim", (0.9, 1.0, 0.75), 35.0, 0.5, (1.0, 0.88, 0.75)),
                              ("RimL", (-0.9, 1.0, 0.6), 22.0, 0.5, (0.9, 0.92, 1.0)),
                              ("Back", (0, 2.3, 0.5), 6.0, 1.5, (1.0, 0.75, 0.55))):
    l = bpy.data.lights.new(name, 'AREA'); l.energy = e; l.size = s_; l.color = col
    o = bpy.data.objects.new(name, l); o.location = loc; sc.collection.objects.link(o)
    tgt = Vector((0, 2.5, 0.4)) if name == "Back" else Vector((0, 0, 0.3))
    o.rotation_euler = (tgt - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.location = (0, -2.3, 0.3); cam.data.lens = 85
cam.rotation_euler = (Vector((0, 0, 0.27)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.dof.use_dof = True
cam.data.dof.focus_distance = 2.17
cam.data.dof.aperture_fstop = 2.8
if CLOSE:
    cam.location = (-0.55, -1.3, 0.34)
    cam.rotation_euler = (Vector((0.0, 0, 0.29)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.dof.focus_distance = (Vector((-0.02, -0.12, 0.3)) - cam.location).length
    cam.data.dof.aperture_fstop = 4.0
    sc.cycles.samples = 256
if CLOSE:
    cam.location = (-0.5, -1.15, 0.36)
    cam.rotation_euler = (Vector((0.035, 0, 0.27)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.dof.focus_distance = (Vector((-0.02, -0.12, 0.31)) - cam.location).length
# a photograph, not a render: a little glow, lens fringing, vignette and grain
try:
    tree = bpy.data.node_groups.new("Comp", 'CompositorNodeTree')
    sc.compositing_node_group = tree
    rl = tree.nodes.new("CompositorNodeRLayers")
    out_ = tree.interface.new_socket("Image", in_out='OUTPUT', socket_type='NodeSocketColor')
    go = tree.nodes.new("NodeGroupOutput")
    glare = tree.nodes.new("CompositorNodeGlare")
    for k_, v_ in (("Type", 'Fog Glow'), ("Quality", 'High')):
        if k_ in glare.inputs:
            glare.inputs[k_].default_value = v_
    for k_, v_ in (("Threshold", 0.8), ("Strength", 0.25), ("Size", 0.6)):
        if k_ in glare.inputs:
            glare.inputs[k_].default_value = v_
    ld = tree.nodes.new("CompositorNodeLensdist")
    for k_, v_ in (("Distortion", -0.005), ("Dispersion", 0.012)):
        if k_ in ld.inputs:
            ld.inputs[k_].default_value = v_
    tree.links.new(rl.outputs["Image"], glare.inputs["Image"])
    tree.links.new(glare.outputs["Image"], ld.inputs["Image"])
    tree.links.new(ld.outputs["Image"], go.inputs[0])
    print("COMPOSITOR ok", flush=True)
except Exception as e:
    print("COMPOSITOR skipped", e, flush=True)
sc.render.film_transparent = False
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("RENDER", out, flush=True)
