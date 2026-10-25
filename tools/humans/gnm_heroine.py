"""The heroine in her saree with a GNM head: the MakeHuman body, blouse, saree and pose from street_people.py;
its own head and upper neck removed and the scanned-model head (gnm_head.py) fitted on, with long hair, brows,
lashes, fine facial hair and jasmine.

    Blender -b --python tools/humans/gnm_heroine.py -- out.jpg     (needs MPFB2: no --factory-startup)
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import street_people as SP  # noqa: E402
import quality as Q  # noqa: E402
import gnm_head as G  # noqa: E402

out = sys.argv[sys.argv.index("--") + 1]
SEED = int(os.environ.get("SEED", "203"))
TONE = (0.25, 0.135, 0.081)

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
spec = next(s for s in SP.PEOPLE if s[0] == "heroine_saree")
objs = SP.build(spec, 0.0, random.Random(707), quality=True, face_seed=707, tone=0.74)   # the silk saree, cloth pallu
body = objs[0]
for o in list(objs[1:]):                                       # the body's own eyes, brows, hair: the GNM head has its own
    n = o.name.lower()
    if o.type in ('MESH', 'CURVES') and any(k in n for k in ("eye", "brow", "hair", "lash", "teeth", "tongue", "jewel")):
        objs.remove(o)
        bpy.data.objects.remove(o, do_unlink=True)
blm = Q.landmarks(body)


def by_name(prefix):
    return next((o for o in objs if o.name.startswith(prefix)), None)


# --- the saree's top hugs the waist (not a stiff tube), with the front pleats (kosuvam) fanning down
from mathutils.bvhtree import BVHTree
dg = bpy.context.evaluated_depsgraph_get()
body_bvh = BVHTree.FromObject(body.evaluated_get(dg), dg)
saree = by_name("Saree")
if saree is not None:
    me = saree.data
    zs = [(saree.matrix_world @ v.co).z for v in me.vertices]
    top_z = max(zs)
    inv = saree.matrix_world.inverted()
    W = [saree.matrix_world @ v.co for v in me.vertices]
    # the body under the clothes is removed by MakeHuman, so the waist is shaped, not fitted: the top of the
    # tube narrows smoothly from the hips to the waist about the tube's own middle
    topring = [q for q in W if q.z > top_z - 0.005]
    tcx = sum(q.x for q in topring) / len(topring)
    tcy = sum(q.y for q in topring) / len(topring)
    for v, p in zip(me.vertices, W):
        t = (p.z - (top_z - 0.2)) / 0.2
        if t <= 0:
            continue
        t = min(1.0, t)
        k = 1.0 - 0.2 * t * t * (3 - 2 * t)
        v.co = inv @ Vector((tcx + (p.x - tcx) * k, tcy + (p.y - tcy) * k, p.z))
    me.update()
    # the tuck: a soft roll of cloth along the top edge, hiding the raw edge
    W2 = [saree.matrix_world @ v.co for v in me.vertices]
    tz = max(q.z for q in W2)
    rim = [q for q in W2 if q.z > tz - 0.004]
    c0 = sum(rim, Vector()) / len(rim)
    rim.sort(key=lambda q: math.atan2(q.y - c0.y, q.x - c0.x))
    bmr = bmesh.new()
    ringv = []
    for q in rim:
        out_ = Vector((q.x - c0.x, q.y - c0.y, 0)).normalized()
        ringv.append([bmr.verts.new(q + out_ * (0.006 * math.cos(a)) + Vector((0, 0, 0.012 * math.sin(a) - 0.006)))
                      for a in [i * math.tau / 8 for i in range(8)]])
    for i in range(len(ringv)):
        a_, b_ = ringv[i], ringv[(i + 1) % len(ringv)]
        for j in range(8):
            bmr.faces.new((a_[j], a_[(j + 1) % 8], b_[(j + 1) % 8], b_[j]))
    rm = bpy.data.meshes.new("Tuck")
    bmr.to_mesh(rm)
    bmr.free()
    rm.materials.append(saree.data.materials[0])
    for pl in rm.polygons:
        pl.use_smooth = True
    tk = bpy.data.objects.new("Tuck", rm)
    bpy.context.scene.collection.objects.link(tk)
    objs.append(tk)
    sm = saree.data.materials[0]
    zari = by_name("Zari")
    zm = zari.data.materials[0] if zari else sm
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    sb = BVHTree.FromObject(saree.evaluated_get(dg), dg)
    bm = bmesh.new()
    rows, cols = 44, 27
    cx = blm["cx"]
    grid = []
    for r in range(rows):
        z = (top_z - 0.03) - (top_z - 0.05) * r / (rows - 1)
        u = r / (rows - 1)
        w = 0.1 + 0.07 * u
        amp = 0.004 + 0.011 * u
        x0 = cx + 0.035 - w / 2
        row = []
        for k in range(cols):
            x = x0 + w * k / (cols - 1)
            hit, n_, _, _ = sb.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)))
            y = (hit.y if hit else blm["cy"] - 0.15) - 0.005 - (amp if k % 2 else 0.0)
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for r in range(rows - 1):
        for k in range(cols - 1):
            bm.faces.new((grid[r][k], grid[r][k + 1], grid[r + 1][k + 1], grid[r + 1][k]))
    pm = bpy.data.meshes.new("Kosuvam")
    bm.to_mesh(pm)
    bm.free()
    pm.materials.append(sm)
    pm.materials.append(zm)
    for pl in pm.polygons:
        pl.use_smooth = True
        pl.material_index = 1 if pl.center.z < 0.1 else 0
    ko = bpy.data.objects.new("Kosuvam", pm)
    bpy.context.scene.collection.objects.link(ko)
    ko.modifiers.new("Thick", 'SOLIDIFY').thickness = 0.002
    objs.append(ko)
# --- the midriff: skin between the blouse hem and the saree's top (the body there was removed under the clothes)
blouse0 = next((o for o in objs if o.get("outfit") == "saree" and o.type == 'MESH' and o is not body), None)
if saree is not None and blouse0 is not None:
    SW = [saree.matrix_world @ v.co for v in saree.data.vertices]
    stz = max(q.z for q in SW)
    sring = [q for q in SW if q.z > stz - 0.005]
    BW = [blouse0.matrix_world @ v.co for v in blouse0.data.vertices]
    bz = min(q.z for q in BW)
    bring = [q for q in BW if q.z < bz + 0.02 and abs(q.x - tcx) < 0.2]
    print("MIDRIFF from", stz, "to", bz, len(sring), len(bring), flush=True)

    def r_at(ring, ang):
        best = None
        for q in ring:
            a_ = math.atan2(q.y - tcy, q.x - tcx)
            d = abs((a_ - ang + math.pi) % math.tau - math.pi)
            if best is None or d < best[0]:
                best = (d, math.hypot(q.x - tcx, q.y - tcy))
        return best[1]
    if bz > stz - 0.01 and bring:
        bmm = bmesh.new()
        n_a, n_r = 48, 6
        z0, z1 = stz - 0.03, bz + 0.015
        rows_ = []
        for j in range(n_r):
            u = j / (n_r - 1)
            z = z0 + (z1 - z0) * u
            row = []
            for i in range(n_a):
                ang = i / n_a * math.tau
                r = (r_at(sring, ang) - 0.012) * (1 - u) + (r_at(bring, ang) - 0.006) * u
                r -= 0.006 * math.sin(u * math.pi)                     # the waist curves in a little
                row.append(bmm.verts.new((tcx + math.cos(ang) * r, tcy + math.sin(ang) * r, z)))
            rows_.append(row)
        for j in range(n_r - 1):
            for i in range(n_a):
                bmm.faces.new((rows_[j][i], rows_[j][(i + 1) % n_a], rows_[j + 1][(i + 1) % n_a], rows_[j + 1][i]))
        mm = bpy.data.meshes.new("Midriff")
        bmm.to_mesh(mm)
        bmm.free()
        for pl in mm.polygons:
            pl.use_smooth = True
        mo = bpy.data.objects.new("Midriff", mm)
        bpy.context.scene.collection.objects.link(mo)
        MIDRIFF = mo
# --- a green silk blouse against the pink saree
blouse = next((o for o in objs if o.get("outfit") == "saree" and o.type == 'MESH' and o is not body), None)
if blouse is not None:
    bmat = Q.fabric("Blouse Silk", (0.02, 0.15, 0.065), weave=900.0)
    bp = bmat.node_tree.nodes["Principled BSDF"]
    bp.inputs["Sheen Weight"].default_value = 0.3
    bp.inputs["Roughness"].default_value = 0.72
    bp.inputs["Specular IOR Level"].default_value = 0.3
    blouse.data.materials.clear()
    blouse.data.materials.append(bmat)
    for n_ in bmat.node_tree.nodes:
        if n_.type == 'BUMP':
            n_.inputs["Strength"].default_value = 0.4
    # gold zari piping along every edge of the blouse: neckline, sleeve hems, the hem
    bmb = bmesh.new()
    bmb.from_mesh(blouse.data)
    edges = [e for e in bmb.edges if e.is_boundary]
    em = bpy.data.meshes.new("Piping")
    vmap = {}
    verts, eds = [], []
    for e in edges:
        ids = []
        for v_ in e.verts:
            if v_.index not in vmap:
                vmap[v_.index] = len(verts)
                verts.append(tuple(blouse.matrix_world @ v_.co))
            ids.append(vmap[v_.index])
        eds.append(tuple(ids))
    bmb.free()
    em.from_pydata(verts, eds, [])
    po = bpy.data.objects.new("Piping", em)
    bpy.context.scene.collection.objects.link(po)
    bpy.ops.object.select_all(action='DESELECT')
    po.select_set(True)
    bpy.context.view_layer.objects.active = po
    bpy.ops.object.convert(target='CURVE')
    po.data.bevel_depth = 0.0025
    po.data.bevel_resolution = 2
    zm_ = by_name("Zari")
    po.data.materials.append(zm_.data.materials[0] if zm_ else bmat)
    objs.append(po)

head = G.build_head(np.random.default_rng(SEED), female=1.0, ethnicity=dict(middle_eastern=.55, black=.25, white=.2),
                    smile=0.1, tone=TONE)
s = G.fit_to_body(head, blm)
zb, rb = G.neck_bottom(head)
print("HEAD scale %.3f, neck ends at %.3f (r %.3f), body top %.3f" % (s, zb, rb, blm["top"]), flush=True)

# remove the body's head and neck down to a little below where the GNM neck ends (overlap hides the join)
cut = zb + 0.025
bm = bmesh.new()
bm.from_mesh(body.data)
gone = [v for v in bm.verts if v.co.z > cut and math.hypot(v.co.x - blm["cx"], v.co.y - blm["cy"]) < 0.12]
bmesh.ops.delete(bm, geom=gone, context='VERTS')
bm.to_mesh(body.data)
bm.free()
# the body wears the same skin as the face
body.data.materials.clear()
skin = head.data.materials[0].copy()                          # the same skin, a little more matte on the body
for n_ in skin.node_tree.nodes:
    if n_.type == 'MAP_RANGE':
        n_.inputs["To Min"].default_value = 0.62
        n_.inputs["To Max"].default_value = 0.55
skin.node_tree.nodes["Principled BSDF"].inputs["Coat Weight"].default_value = 0.0
body.data.materials.append(skin)
if "MIDRIFF" in globals():
    MIDRIFF.data.materials.append(skin)
    pm_ = MIDRIFF.data.color_attributes.new("Paint", 'FLOAT_COLOR', 'POINT')
    pm_.data.foreach_set("color", np.tile(np.array([1, 1, 1, 0], np.float32), len(MIDRIFF.data.vertices)))
pa = body.data.color_attributes.new("Paint", 'FLOAT_COLOR', 'POINT')
pa.data.foreach_set("color", np.tile(np.array([1, 1, 1, 0], np.float32), len(body.data.vertices)))

G.darken_scalp(head)
extra = G.brows_and_lashes(head, random.Random(SEED), True)
extra.append(G.peach_fuzz(head, np.random.default_rng(SEED)))
lm = G.lm_of(head)
# hair collides with head, body and clothes: a joined copy to grow on
tmp = [o.copy() for o in [head, body] + [o for o in objs[1:] if o.type == 'MESH']]
for t in tmp:
    t.data = t.data.copy()
    bpy.context.scene.collection.objects.link(t)
bpy.ops.object.select_all(action='DESELECT')
for t in tmp:
    t.select_set(True)
bpy.context.view_layer.objects.active = tmp[0]
bpy.ops.object.join()
coll = bpy.context.view_layer.objects.active
lm_h = dict(lm)
lm_h["shoulder_z"] = blm["shoulder_z"]
lm_h["shoulder_w"] = blm["shoulder_w"]
extra.append(Q.long_hair(coll, lm_h, random.Random(SEED), length=0.45, children=60000, melanin=0.95, part=0.6))
bpy.data.objects.remove(coll, do_unlink=True)
# --- jewellery on the GNM face: a red bindi, a gold nose stud, jhumka earrings
def gold():
    g = bpy.data.materials.new("Gold")
    g.use_nodes = True
    gp = g.node_tree.nodes["Principled BSDF"]
    gp.inputs["Base Color"].default_value = (0.95, 0.68, 0.3, 1)
    gp.inputs["Metallic"].default_value = 1.0
    gp.inputs["Roughness"].default_value = 0.2
    return g


GOLD = gold()
hb = BVHTree.FromObject(head.evaluated_get(bpy.context.evaluated_depsgraph_get()), bpy.context.evaluated_depsgraph_get())
HV = np.array([v.co for v in head.data.vertices])
SK = HV[G._group("skin") > 0.5]
nose = lm["nose"]


def stud(name, centre, normal, radius, depth, mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=radius, depth=depth, location=centre + normal * depth * 0.5)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler = normal.to_track_quat('Z', 'Y').to_euler()
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


eye_gap = lm["eye_z"] - nose.z
hit, n_, _, _ = hb.ray_cast(Vector((lm["cx"], -1.0, lm["eye_z"] + eye_gap * 0.62)), Vector((0, 1, 0)))
if hit:
    red = bpy.data.materials.new("Bindi")
    red.use_nodes = True
    red.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.008, 0.02, 1)
    red.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.65   # a flat, matte felt dot
    bo = stud("Bindi", hit, n_, 0.0032, 0.00015, red)
    bpy.ops.object.shade_flat()
    extra.append(bo)
hit, n_, _, _ = hb.ray_cast(Vector((nose.x + 0.011 * (lm["top"] - nose.z) / 0.15, nose.y - 0.3, nose.z + 0.002)),
                            Vector((0, 1, 0)))
if hit:
    extra.append(stud("Nose stud", hit, n_, 0.0014, 0.0012, GOLD))
for sx in (1, -1):                                             # ear lobes: the outermost skin at the nose's height
    band = SK[(np.abs(SK[:, 2] - (nose.z - 0.005)) < 0.012) & ((SK[:, 0] - lm["cx"]) * sx > 0)]
    if not len(band):
        continue
    lobe = band[np.argmax(np.abs(band[:, 0] - lm["cx"]))]
    lob = band[(np.abs(band[:, 0] - lobe[0]) < 0.01)]
    low = lob[np.argmin(lob[:, 2])]
    top_ = Vector((low[0], low[1], low[2] - 0.003))
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.0032, location=top_ - Vector((0, 0, 0.004)))
    s1 = bpy.context.active_object
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=0.0085, radius2=0.002, depth=0.013,
                                    location=top_ - Vector((0, 0, 0.0135)))
    c1 = bpy.context.active_object
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.0016, location=top_ - Vector((0, 0, 0.022)))
    d1 = bpy.context.active_object
    for o in (s1, c1, d1):
        o.data.materials.append(GOLD)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_smooth()
    extra += [s1, c1, d1]
try:
    extra.append(Q.jasmine(lm, random.Random(SEED)))
except Exception as e:
    print("jasmine skipped", e, flush=True)

# --- light and camera (as gnm_test.py)
sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.samples = 256
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
sc.view_settings.look = 'AgX - Medium High Contrast'
sc.render.image_settings.file_format = 'JPEG'
sc.render.resolution_x, sc.render.resolution_y = 1200, 1500
if os.environ.get("OUTDOOR"):
    # an outdoor portrait at golden hour: the sun low behind her (a warm rim on the hair and shoulders), the open sky
    # lighting the face, a reflector below the frame, and a garden far behind, blurred by the lens
    sc.world = bpy.data.worlds.new("Sky")
    sc.world.use_nodes = True
    wn = sc.world.node_tree
    sky = wn.nodes.new("ShaderNodeTexSky")
    for t_ in ('MULTIPLE_SCATTERING', 'NISHITA', 'HOSEK_WILKIE'):
        try:
            sky.sky_type = t_
            break
        except Exception:
            pass
    try:
        sky.sun_disc = False
        sky.sun_elevation = math.radians(14)
        sky.sun_rotation = math.radians(150)
    except Exception:
        pass
    wn.links.new(sky.outputs[0], wn.nodes["Background"].inputs[0])
    wn.nodes["Background"].inputs[1].default_value = 0.12
    face = Vector((lm["cx"], lm["nose"].y, lm["nose"].z))


    def plane(name, verts, mat):
        o = bpy.data.objects.new(name, bpy.data.meshes.new(name))
        sc.collection.objects.link(o)
        o.data.from_pydata(verts, [], [(0, 1, 2, 3)])
        o.data.uv_layers.new()
        o.data.materials.append(mat)
        return o


    gm = bpy.data.materials.new("Garden")
    gm.use_nodes = True
    gt = gm.node_tree
    gp = gt.nodes["Principled BSDF"]
    gn = gt.nodes.new("ShaderNodeTexNoise")
    gn.inputs["Scale"].default_value = 3.0
    gn.inputs["Detail"].default_value = 8.0
    gr = gt.nodes.new("ShaderNodeValToRGB")
    gr.color_ramp.elements[0].color = (0.01, 0.025, 0.008, 1)
    gr.color_ramp.elements[1].color = (0.12, 0.2, 0.05, 1)
    gt.links.new(gn.outputs["Fac"], gr.inputs["Fac"])
    gt.links.new(gr.outputs["Color"], gp.inputs["Base Color"])
    gv = gt.nodes.new("ShaderNodeTexVoronoi")                      # sky through the leaves: bokeh when blurred
    gv.inputs["Scale"].default_value = 9.0
    gk = gt.nodes.new("ShaderNodeMapRange")
    gt.links.new(gv.outputs["Distance"], gk.inputs["Value"])
    gk.inputs["From Min"].default_value = 0.0
    gk.inputs["From Max"].default_value = 0.09
    gk.inputs["To Min"].default_value = 6.0
    gk.inputs["To Max"].default_value = 0.0
    gk.clamp = True
    gp.inputs["Emission Color"].default_value = (1.0, 0.85, 0.6, 1)
    gt.links.new(gk.outputs[0], gp.inputs["Emission Strength"])
    plane("Garden", [(-12, 8, -1), (12, 8, -1), (12, 8, 9), (-12, 8, 9)], gm)
    fm = bpy.data.materials.new("Paving")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.27, 0.22, 1)
    fm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    plane("Ground", [(-12, -6, 0), (12, -6, 0), (12, 9, 0), (-12, 9, 0)], fm)
    sun = bpy.data.lights.new("Sun", 'SUN')
    sun.energy = 7.0
    sun.angle = math.radians(1.5)
    sun.color = (1.0, 0.78, 0.55)
    so = bpy.data.objects.new("Sun", sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (Vector((0, 0, 0)) - Vector((0.55, 1.0, 0.3))).to_track_quat('-Z', 'Y').to_euler()
    for name, d, e, s_, col in (("Key", (-1.0, -1.1, 0.5), 60.0, 1.4, (1.0, 0.86, 0.7)),
                                ("Reflector", (-0.3, -1.0, -0.55), 20.0, 1.2, (1.0, 0.9, 0.78)),
                                ("Sky fill", (0.9, -1.2, 0.4), 8.0, 2.0, (0.85, 0.9, 1.0))):
        l = bpy.data.lights.new(name, 'AREA'); l.energy = e; l.size = s_; l.color = col
        o = bpy.data.objects.new(name, l); o.location = face + Vector(d); sc.collection.objects.link(o)
        o.rotation_euler = (face - o.location).to_track_quat('-Z', 'Y').to_euler()
else:                                                          # the studio portrait (the default: it reads best)
    sc.world = bpy.data.worlds.new("W")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.045, 0.04, 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    face = Vector((lm["cx"], lm["nose"].y, lm["nose"].z))
    bg = bpy.data.objects.new("Backdrop", bpy.data.meshes.new("Backdrop"))
    sc.collection.objects.link(bg)
    bg.data.from_pydata([(-3, 2.5, -1), (3, 2.5, -1), (3, 2.5, 4), (-3, 2.5, 4)], [], [(0, 1, 2, 3)])
    bmat = bpy.data.materials.new("Backdrop")
    bmat.use_nodes = True
    bmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.035, 0.03, 0.027, 1)
    bg.data.materials.append(bmat)
    for name, d, e, s_, col in (("Key", (-1.1, -1.2, 0.6), 70.0, 1.4, (1.0, 0.9, 0.8)),
                                ("Fill", (1.3, -1.1, -0.05), 12.0, 1.8, (0.85, 0.9, 1.0)),
                                ("Rim", (0.9, 1.0, 0.45), 40.0, 0.5, (1.0, 0.88, 0.75)),
                                ("RimL", (-0.9, 1.0, 0.3), 25.0, 0.5, (0.9, 0.92, 1.0))):
        l = bpy.data.lights.new(name, 'AREA'); l.energy = e; l.size = s_; l.color = col
        o = bpy.data.objects.new(name, l); o.location = face + Vector(d); sc.collection.objects.link(o)
        o.rotation_euler = (face - o.location).to_track_quat('-Z', 'Y').to_euler()
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
sc.collection.objects.link(cam)
sc.camera = cam
aim = face + Vector((0, 0, -0.17))                              # head and shoulders, the blouse and pallu
cam.location = aim + Vector((-0.6, -1.9, 0.08))
cam.data.lens = 85
cam.rotation_euler = (aim - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.dof.use_dof = True
cam.data.dof.focus_distance = (face - cam.location).length
cam.data.dof.aperture_fstop = 4.0
sc.render.filepath = out
if not os.environ.get("FACE_ONLY"):
    bpy.ops.render.render(write_still=True)
    print("RENDER", out, flush=True)
# and a portrait of the face
cam.location = face + Vector((-0.3, -0.72, 0.05))
cam.rotation_euler = ((face + Vector((0.0, 0, 0.005))) - cam.location).to_track_quat('-Z', 'Y').to_euler()
eyes_at = Vector((lm["cx"], lm["nose"].y + 0.025, lm["eye_z"]))
cam.data.dof.focus_distance = (eyes_at - cam.location).length
sc.render.resolution_x, sc.render.resolution_y = 960, 1200
sc.render.filepath = out.replace(".jpg", "_face.jpg")
bpy.ops.render.render(write_still=True)
print("RENDER", sc.render.filepath, flush=True)
