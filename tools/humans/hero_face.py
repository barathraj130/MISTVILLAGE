"""
Close-up ("hero") characters for cutscenes and conversations — face quality far above the street crowd:

  * MakeHuman body (MPFB2), subdivided once for close-ups
  * the best skin in the library (mindfront middle-aged male: colour, normal and specular maps — pores and
    wrinkles) darkened to a South Indian tone, with subsurface scattering, fine pore bump and an oilier T-zone
  * high-poly eyes (brown), eyelashes, thick eyebrows, teeth, tongue
  * a real moustache grown from strands on the upper lip, greying temples
  * thin metal spectacles (optional)
  * the khaki police uniform with epaulettes (the sergeant at the checking point)
  * a warm cutscene light: key, rim and a dim fill against a dark room

    Blender -b --python tools/humans/hero_face.py -- --out previews/faces
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import street_people as SP  # noqa: E402

HS, HOP, TS = SP.HS, SP.HOP, SP.TS


def skin_upgrade(body, tone=0.95):
    """The MakeSkin material → a close-up skin: subsurface scattering (red-weighted radius), the colour a little
    darker and warmer (South Indian), micro-pore bump on top of the normal map, roughness lower on the T-zone."""
    for m in body.data.materials:
        if m is None or not m.use_nodes:
            continue
        nt = m.node_tree
        p = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if p is None:
            continue
        p.inputs["Subsurface Weight"].default_value = 0.22
        p.inputs["Subsurface Radius"].default_value = (1.0, 0.38, 0.22)
        p.inputs["Subsurface Scale"].default_value = 0.012
        if "Coat Weight" in p.inputs:
            p.inputs["Coat Weight"].default_value = 0.05
        # darker, warmer tone
        src = p.inputs["Base Color"].links[0].from_socket if p.inputs["Base Color"].is_linked else None
        if src is not None:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = 'MULTIPLY'
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = (tone, tone * 0.86, tone * 0.74, 1)
            nt.links.new(src, mix.inputs[6])
            nt.links.new(mix.outputs[2], p.inputs["Base Color"])
        # pores: a fine Voronoi bump in UV space, added to whatever normal the material has
        tc = nt.nodes.new("ShaderNodeTexCoord")
        vo = nt.nodes.new("ShaderNodeTexVoronoi")
        vo.inputs["Scale"].default_value = 900.0
        nt.links.new(tc.outputs["UV"], vo.inputs["Vector"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.12
        bump.inputs["Distance"].default_value = 0.0004
        nt.links.new(vo.outputs["Distance"], bump.inputs["Height"])
        if p.inputs["Normal"].is_linked:
            nt.links.new(p.inputs["Normal"].links[0].from_socket, bump.inputs["Normal"])
        nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
        if not p.inputs["Roughness"].is_linked:
            p.inputs["Roughness"].default_value = 0.45


def landmarks(body):
    """Nose tip, eye centres and the upper lip from the posed body (face looks -Y)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    vs = [ev.matrix_world @ v.co for v in ev.data.vertices]
    zmax = max(v.z for v in vs)
    head = [v for v in vs if v.z > zmax - 0.27 and abs(v.x) < 0.1]
    nose = min(head, key=lambda v: v.y)
    return {"top": zmax, "nose": nose, "cx": nose.x}


def moustache(body, lm, rng, colour=(0.02, 0.016, 0.012)):
    """A Tamil moustache: ~2500 strands grown from the upper lip (raycast onto the face), combed out and down,
    thicker in the middle, as Blender hair curves (rendered as real strands)."""
    nose = lm["nose"]
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    inv = ev.matrix_world.inverted()
    roots = []
    for _ in range(9000):
        x = rng.uniform(-0.03, 0.03)
        zt = nose.z - 0.019 - 0.004 * (abs(x) / 0.03) ** 2           # just under the nostrils
        z = rng.uniform(zt - 0.011 - 0.006 * (abs(x) / 0.03), zt)       # the upper lip only, never the mouth
        o = inv @ Vector((nose.x + x, nose.y - 0.2, z))
        hit, loc, nrm, idx = ev.ray_cast(o, Vector((0, 1, 0)), distance=0.4)
        if hit:
            roots.append((ev.matrix_world @ loc, (ev.matrix_world.to_3x3() @ nrm).normalized(), x))
        if len(roots) >= 3200:
            break
    curves = bpy.data.hair_curves.new("Moustache") if hasattr(bpy.data, "hair_curves") else None
    if curves is None:
        return None
    seg = 5
    curves.add_curves([seg] * len(roots))
    pts = curves.points
    k = 0
    for root, nrm, x in roots:
        side = 1.0 if x >= 0 else -1.0
        L = rng.uniform(0.006, 0.010) * (1.0 - 0.25 * abs(x) / 0.03)
        d = (nrm * 0.55 + Vector((side * 0.45 * abs(x) / 0.03, -0.1, -0.8))).normalized()
        p = root.copy()
        for s in range(seg):
            pts[k].position = p
            pts[k].radius = 0.00006 * (1.0 - s / seg) + 0.00002
            d = (d + Vector((0, 0, -0.18)) + Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.05, 0.05), 0))).normalized()
            p = p + d * (L / (seg - 1))
            k += 1
    ob = bpy.data.objects.new("Moustache", curves)
    bpy.context.scene.collection.objects.link(ob)
    m = bpy.data.materials.new("Moustache Hair")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type == 'BSDF_PRINCIPLED':
            nt.nodes.remove(n)
    hb = nt.nodes.new("ShaderNodeBsdfHairPrincipled")
    # black hair by pigment: high melanin, a little red, a touch of grey in some strands
    for k, v in (("Melanin", 0.93), ("Melanin Redness", 0.25), ("Random Color", 0.15), ("Roughness", 0.38),
                 ("Random Roughness", 0.2)):
        if k in hb.inputs:
            hb.inputs[k].default_value = v
    nt.links.new(hb.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    curves.materials.append(m)
    return ob


def spectacles(lm, eye_z, eye_dx, mat):
    """Thin metal frames: two rounded-rectangle rims, a bridge, temples back to the ears; clear lenses."""
    bm = bmesh.new()
    nose = lm["nose"]
    y = nose.y + 0.022
    for sx in (-1, 1):
        cx = nose.x + sx * eye_dx
        ring = []
        for k in range(28):
            a = k / 28 * math.tau
            rx, rz = 0.026, 0.019
            ring.append(Vector((cx + math.cos(a) * rx, y + 0.002 * math.sin(a), eye_z + math.sin(a) * rz)))
        for a, b in zip(ring, ring[1:] + ring[:1]):
            res = bmesh.ops.create_cone(bm, cap_ends=False, segments=6, radius1=0.0009, radius2=0.0009, depth=(b - a).length,
                                        matrix=Matrix.Translation((a + b) / 2) @ (b - a).to_track_quat('Z', 'Y').to_matrix().to_4x4())
        # temples from the outer edge of the rim back over the ear
        a = Vector((cx + sx * 0.026, y, eye_z + 0.006))
        b = Vector((cx + sx * 0.03, y + 0.1, eye_z + 0.012))
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.001, radius2=0.001, depth=(b - a).length,
                              matrix=Matrix.Translation((a + b) / 2) @ (b - a).to_track_quat('Z', 'Y').to_matrix().to_4x4())
    a = Vector((nose.x - eye_dx + 0.026, y, eye_z + 0.008))
    b = Vector((nose.x + eye_dx - 0.026, y, eye_z + 0.008))
    bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.001, radius2=0.001, depth=(b - a).length,
                          matrix=Matrix.Translation((a + b) / 2) @ (b - a).to_track_quat('Z', 'Y').to_matrix().to_4x4())
    me = bpy.data.meshes.new("Spectacles")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Spectacles", me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat)
    return ob


def hero(name="sergeant", years=50, glasses=True, cap=False, seed=3):
    rng = random.Random(seed)
    h = HS.create_human()
    h.name = name
    for k, v in (("gender", 1.0), ("age", SP.age(years)), ("weight", 0.66), ("muscle", 0.5), ("height", 0.52),
                 ("african", 0.42), ("asian", 0.2), ("caucasian", 0.38)):
        HOP.set_value(k, v, entity_reference=h)
    TS.reapply_macro_details(h)
    arm = HS.add_builtin_rig(h, "default")
    sk = SP.asset("mindfront_skin_male_african_middleage.mhmat", "skins")
    HS.set_character_skin(sk, h, skin_type="MAKESKIN")
    skin_upgrade(h)
    objs = [h]
    for sub, fname, typ in (("eyes", "high-poly.mhclo", "Eyes"), ("eyebrows", "mindfront_eyebrows_03.mhclo", "Eyebrows"),
                            ("eyelashes", "mindfront_eyelashes_02.mhclo", "Eyelashes"), ("teeth", "teeth_base.mhclo", "Teeth"),
                            ("tongue", "tongue01.mhclo", "Tongue"), ("hair", "short04.mhclo", "Hair")):
        p = SP.asset(fname, sub)
        if p:
            o = HS.add_mhclo_asset(p, h, asset_type=typ, subdiv_levels=1, material_type="MAKESKIN")
            if typ == "Hair":
                SP.tint(o, (0.06, 0.05, 0.045), 0.85)
            objs.append(o)
    p = SP.asset("male_casualsuit03.mhclo", "clothes")
    if p:
        c = HS.add_mhclo_asset(p, h, asset_type="Clothes", subdiv_levels=1, material_type="MAKESKIN")
        SP.plain_clothes(c, SP.KHAKI, "police")
        objs.append(c)
    SP.pose(arm, "stand", rng, 52)
    for m in h.modifiers:
        if m.type == 'SUBSURF':
            m.levels = 1
            m.render_levels = 1
    if not any(m.type == 'SUBSURF' for m in h.modifiers):
        s = h.modifiers.new("Subsurf", 'SUBSURF')
        s.levels, s.render_levels = 1, 1
    bpy.context.view_layer.update()
    lm = landmarks(h)
    must = moustache(h, lm, rng)
    extras = []
    if glasses:
        eyes = [o for o in objs if "high-poly" in o.name or "eyes" in o.name.lower()]
        eye_z = lm["nose"].z + 0.035
        if eyes:
            dg = bpy.context.evaluated_depsgraph_get()
            e = eyes[0].evaluated_get(dg)
            ev = [e.matrix_world @ v.co for v in e.data.vertices]
            eye_z = sum(v.z for v in ev) / len(ev)
        metal = bpy.data.materials.new("Spectacle Frame")
        metal.use_nodes = True
        pp = metal.node_tree.nodes["Principled BSDF"]
        pp.inputs["Base Color"].default_value = (0.6, 0.55, 0.45, 1)
        pp.inputs["Metallic"].default_value = 1.0
        pp.inputs["Roughness"].default_value = 0.25
        extras.append(spectacles(lm, eye_z, 0.032, metal))
    if cap:
        SP.police_kit(h, "police", objs)
    return h, lm, objs + extras + ([must] if must else [])


def room_and_light(sc, lm):
    """A dark wooden room behind, a warm key light from the front-left (like a lamp on the table), a cool rim
    from behind-right, a dim fill."""
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 2.0, 1.5), rotation=(math.pi / 2, 0, 0))
    wall = bpy.context.active_object
    wm = bpy.data.materials.new("Wood Wall")
    wm.use_nodes = True
    nt = wm.node_tree
    wv = nt.nodes.new("ShaderNodeTexWave")
    wv.inputs["Scale"].default_value = 3.0
    wv.inputs["Distortion"].default_value = 6.0
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].color = (0.03, 0.018, 0.01, 1)
    r.color_ramp.elements[1].color = (0.12, 0.07, 0.035, 1)
    nt.links.new(wv.outputs["Fac"], r.inputs["Fac"])
    nt.links.new(r.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    wall.data.materials.append(wm)
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
    def area(name, loc, energy, colour, size, target):
        l = bpy.data.lights.new(name, 'AREA')
        l.energy = energy
        l.color = colour
        l.size = size
        o = bpy.data.objects.new(name, l)
        o.location = loc
        o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        sc.collection.objects.link(o)
    face = Vector((lm["cx"], lm["nose"].y, lm["nose"].z))
    area("Key", face + Vector((-0.9, -1.0, 0.25)), 55.0, (1.0, 0.72, 0.45), 0.5, face)
    area("Rim", face + Vector((0.9, 0.9, 0.5)), 35.0, (0.75, 0.85, 1.0), 0.4, face)
    area("Fill", face + Vector((0.8, -1.4, -0.2)), 6.0, (0.9, 0.85, 0.8), 1.2, face)
    sc.world = bpy.data.worlds.new("Dark")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.01, 0.008, 0.006, 1)


CAST = [
    # (file, street_people spec name, face seed, years override, glasses, tone)
    ("sergeant", "police_stand", 101, 50, True, 0.95),
    ("constable", "police_stop", 202, 29, False, 0.9),
    ("old_veshti", "man_veshti", 303, 63, False, 1.0),
    ("young_shirt", "man_shirt_stand", 404, 24, False, 0.98),
    ("woman_saree", "woman_saree_red", 505, 40, False, 1.02),
    ("young_woman", "woman_saree_blue", 606, 23, False, 1.05),
    ("heroine_saree", "heroine_saree", 707, 23, False, 0.74),
    ("heroine_modern", "heroine_modern", 808, 21, False, 0.77),
]


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.hair_curves, bpy.data.armatures,
                 bpy.data.lights, bpy.data.cameras):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)


def character(entry):
    """Build one cast member at close-up quality; police get the full uniform, the sergeant his glasses."""
    import quality as Q
    fname, spec_name, seed, years, glasses, tone = entry
    spec = list(next(s_ for s_ in SP.PEOPLE if s_[0] == spec_name))
    spec[2] = years
    spec[0] = fname
    objs = SP.build(tuple(spec), 0.0, random.Random(seed), quality=True, face_seed=seed, tone=tone)
    h = objs[0]
    lm = Q.landmarks(h)
    if spec[9].startswith("police"):
        shirt = next((o for o in objs if o.get("outfit", "").startswith("police")), None)
        if shirt:
            Q.police_uniform(shirt, lm, name_plate=fname.upper())
    if fname.startswith("heroine"):
        import quality as Q2
        Q2.long_hair(h, lm, random.Random(seed), length=0.45 if "saree" in fname else 0.38,
                     part=0.6 if "saree" in fname else -0.4, melanin=0.92 if "saree" in fname else 0.85)
    if glasses:
        metal = bpy.data.materials.new("Spectacle Frame")
        metal.use_nodes = True
        pp = metal.node_tree.nodes["Principled BSDF"]
        pp.inputs["Base Color"].default_value = (0.6, 0.55, 0.45, 1)
        pp.inputs["Metallic"].default_value = 1.0
        pp.inputs["Roughness"].default_value = 0.25
        spectacles(lm, lm["eye_z"], 0.032, metal)
    return h, lm


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = os.path.abspath(args[args.index("--out") + 1]) if "--out" in args else os.path.join(HERE, "..", "..", "previews", "faces")
    os.makedirs(out, exist_ok=True)
    only = args[args.index("--cast") + 1].split(",") if "--cast" in args else [c[0] for c in CAST]
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 96
    sc.cycles.use_denoising = True
    try:
        pr = bpy.context.preferences.addons["cycles"].preferences
        pr.compute_device_type = 'METAL'
        pr.get_devices()
        for d in pr.devices:
            d.use = True
        sc.cycles.device = 'GPU'
    except Exception:
        pass
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Medium High Contrast'
    sc.render.image_settings.file_format = 'JPEG'
    for entry in sorted((c_ for c_ in CAST if c_[0] in only), key=lambda c_: only.index(c_[0])):
        clear()
        h, lm = character(entry)
        room_and_light(sc, lm)
        if entry[0].startswith("heroine"):
            for ln, en, sz in (("Key", 90.0, 1.2), ("Fill", 22.0, 1.6), ("Rim", 55.0, 0.6)):
                lo = bpy.data.objects.get(ln)
                if lo:
                    lo.data.energy = en
                    lo.data.size = sz
        cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
        face = Vector((lm["cx"], lm["nose"].y, lm["nose"].z - 0.02))
        cam.location = face + Vector((-0.14 if "saree" in entry[0] else 0.12, -0.95, 0.03))
        cam.data.lens = 85
        cam.data.dof.use_dof = True
        cam.data.dof.focus_distance = 0.95
        cam.data.dof.aperture_fstop = 4.0
        cam.rotation_euler = ((face + Vector((0, 0, -0.05))) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.resolution_x, sc.render.resolution_y = 960, 1200
        sc.render.filepath = os.path.join(out, "cast_%s.jpg" % entry[0])
        bpy.ops.render.render(write_still=True)
        print("RENDER", sc.render.filepath, flush=True)


if __name__ == "__main__":
    main()
