"""
Close-up quality for every person (shared by hero_face.py and street_people.py):

  face_shape(h, rng)       a different face for everyone: MakeHuman's face targets (nose, mouth, chin, jaw,
                           cheeks, eyes, brows, forehead, head shape, ears, neck), symmetric, mild to moderate
  skin_upgrade(body, tone) the MakeSkin material with subsurface scattering, a darker/warmer tone, fine pores
  stubble(body, lm, rng)   a shaving shadow on the jaw, chin and upper lip (a vertex mask in the skin shader)
  strand_hair(...)         real hair strands on the scalp (combed back and to the side, greying at the temples
                           with age), over a matte dark base (MakeHuman's hair proxy, its shine taken off)
  police_uniform(...)      the khaki shirt made a uniform: weave and folds, two pockets with flaps, a button
                           placket, epaulettes with brass letters, a belt with a buckle, a name plate
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

TARGET_DIR = None


def _targets_root():
    global TARGET_DIR
    if TARGET_DIR is None:
        for base in (os.path.expanduser("~/Library/Application Support/Blender/5.2/extensions/user_default/mpfb/data/targets"),):
            if os.path.isdir(base):
                TARGET_DIR = base
    return TARGET_DIR


# pairs of opposite targets per face part: one side of each pair is chosen with a weight
FACE_PAIRS = {
    "nose": ["nose-base-{down,up}", "nose-compression-{compress,uncompress}", "nose-curve-{concave,convex}",
             "nose-flaring-{decr,incr}", "nose-hump-{decr,incr}", "nose-greek-{decr,incr}", "nose-scale-horiz-{decr,incr}",
             "nose-scale-vert-{decr,incr}", "nose-width1-{decr,incr}", "nose-nostrils-width-{decr,incr}"],
    "mouth": ["mouth-angles-{down,up}", "mouth-cupidsbow-{decr,incr}", "mouth-lowerlip-height-{decr,incr}",
              "mouth-upperlip-height-{decr,incr}", "mouth-scale-horiz-{decr,incr}", "mouth-lowerlip-volume-{decr,incr}",
              "mouth-upperlip-volume-{decr,incr}", "mouth-laugh-lines-{in,out}"],
    "chin": ["chin-bones-{decr,incr}", "chin-height-{decr,incr}", "chin-prominent-{decr,incr}", "chin-width-{decr,incr}",
             "chin-prognathism-{decr,incr}"],
    "cheek": ["{l,r}-cheek-bones-{decr,incr}", "{l,r}-cheek-volume-{decr,incr}", "{l,r}-cheek-inner-{decr,incr}"],
    "forehead": ["forehead-scale-vert-{decr,incr}", "forehead-temple-{decr,incr}", "forehead-trans-{backward,forward}"],
    "eyes": ["{l,r}-eye-bag-{decr,incr}", "{l,r}-eye-height2-{decr,incr}", "{l,r}-eye-scale-{decr,incr}",
             "{l,r}-eye-trans-{in,out}"],
    "eyebrows": ["eyebrows-angle-{down,up}", "eyebrows-trans-{down,up}"],
    "head": ["head-fat-{decr,incr}", "head-scale-horiz-{decr,incr}", "head-scale-vert-{decr,incr}"],
    "ears": ["{l,r}-ear-scale-{decr,incr}", "{l,r}-ear-flap-{decr,incr}", "{l,r}-ear-lobe-{decr,incr}"],
    "neck": ["neck-scale-horiz-{decr,incr}", "neck-double-{decr,incr}"],
}


def _expand(pattern):
    """'{l,r}-cheek-bones-{decr,incr}' → [(['l-cheek-bones-decr','r-cheek-bones-decr'], ['l-...-incr','r-...-incr'])]"""
    import re
    parts = re.findall(r"\{([^}]*)\}", pattern)
    sides = ["l", "r"] if parts and parts[0] == "l,r" else [None]
    dirs = parts[-1].split(",")
    out = []
    for d in dirs:
        names = []
        for sd in sides:
            p = pattern
            if sd is not None:
                p = p.replace("{l,r}", sd, 1)
            p = p.replace("{%s}" % parts[-1], d)
            names.append(p)
        out.append(names)
    return out


# a woman's face: these features always lean the feminine way (the rest stay random)
FEMININE = {"chin-bones": "decr", "chin-width": "decr", "chin-prominent": "decr", "chin-height": "decr",
            "chin-prognathism": "decr", "head-scale-horiz": "decr", "head-fat": "decr", "neck-scale-horiz": "decr",
            "neck-double": "decr", "nose-scale-horiz": "decr", "nose-width1": "decr", "nose-nostrils-width": "decr",
            "nose-scale-vert": "decr", "nose-hump": "decr", "mouth-upperlip-volume": "incr",
            "mouth-lowerlip-volume": "incr", "mouth-angles": "up", "eye-scale": "incr", "cheek-volume": "incr",
            "cheek-bones": "incr", "eyebrows-trans": "up", "eyebrows-angle": "up", "forehead-temple": "decr"}


def face_shape(h, rng, strength=0.55, feminine=False):
    """Load a random, symmetric set of face targets on the body (the shape a person's face is born with)."""
    import importlib
    import sys
    TS = None
    for m in sys.modules:
        if m.endswith("mpfb.services.targetservice"):
            TS = getattr(importlib.import_module(m), "TargetService")
    root = _targets_root()
    if TS is None or root is None:
        return 0
    n = 0
    for group, pats in FACE_PAIRS.items():
        for pat in pats:
            if rng.random() < 0.35:
                continue                                        # leave some features average
            choices = _expand(pat)
            names = rng.choice(choices)
            if feminine:
                for key, way in FEMININE.items():
                    if key in pat:
                        names = next((c_ for c_ in choices if c_[0].endswith("-" + way)), names)
                if "eye-scale" in pat:
                    w = min(w, 0.3)                              # bigger eyes, not staring ones
            w = rng.uniform(0.15, strength) * (1.0 if group in ("nose", "mouth", "chin", "cheek") else 0.8)
            for nm in names:
                path = os.path.join(root, group, nm + ".target.gz")
                if os.path.exists(path):
                    try:
                        TS.load_target(h, path, weight=w, name=nm)
                        n += 1
                    except Exception:
                        pass
    return n


DETAIL = os.path.expanduser("~/Library/Application Support/Blender/5.2/extensions/.user/user_default/mpfb/data/skins/"
                            "mindfront_skin_male_african_middleage/skin_male_african_middleage_NRM.png")


def skin_upgrade(body, tone=0.95, stubble_mask=False, detail=0.6, pores=0.12):
    """MakeSkin → close-up skin: subsurface scattering, warmer/darker tone, pore bump; optional stubble from the
    'Stubble' colour attribute (dark speckle over the shaved area)."""
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
        src = p.inputs["Base Color"].links[0].from_socket if p.inputs["Base Color"].is_linked else None
        col = src
        if src is not None:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = 'MULTIPLY'
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = (tone, tone * 0.88, tone * 0.78, 1)
            nt.links.new(src, mix.inputs[6])
            col = mix.outputs[2]
        tc = nt.nodes.new("ShaderNodeTexCoord")
        if stubble_mask and col is not None:
            attr = nt.nodes.new("ShaderNodeAttribute")
            attr.attribute_name = "Stubble"
            dots = nt.nodes.new("ShaderNodeTexNoise")
            dots.inputs["Scale"].default_value = 1400.0
            dots.inputs["Detail"].default_value = 2.0
            nt.links.new(tc.outputs["UV"], dots.inputs["Vector"])
            sp = nt.nodes.new("ShaderNodeMapRange")
            nt.links.new(dots.outputs["Fac"], sp.inputs["Value"])
            sp.inputs["From Min"].default_value = 0.45
            sp.inputs["From Max"].default_value = 0.62
            amt = nt.nodes.new("ShaderNodeMath")
            amt.operation = "MULTIPLY"
            nt.links.new(attr.outputs["Fac"], amt.inputs[0])
            nt.links.new(sp.outputs[0], amt.inputs[1])
            amt2 = nt.nodes.new("ShaderNodeMath")
            amt2.operation = "MULTIPLY_ADD"
            nt.links.new(attr.outputs["Fac"], amt2.inputs[0])
            amt2.inputs[1].default_value = 0.35                  # an overall shadow …
            nt.links.new(amt.outputs[0], amt2.inputs[2])         # … plus the speckle of the hair stubs
            st = nt.nodes.new("ShaderNodeMix")
            st.data_type = "RGBA"
            nt.links.new(amt2.outputs[0], st.inputs["Factor"])
            nt.links.new(col, st.inputs[6])
            st.inputs[7].default_value = (0.05, 0.04, 0.035, 1)
            col = st.outputs[2]
        if col is not None and "Makeup" in body.data.color_attributes:
            mk = nt.nodes.new("ShaderNodeAttribute")
            mk.attribute_name = "Makeup"
            sp3 = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(mk.outputs["Color"], sp3.inputs[0])
            for chan, tint in ((2, (0.66, 0.36, 0.3)), (1, (0.78, 0.42, 0.44)), (0, (0.03, 0.02, 0.02))):
                mx = nt.nodes.new("ShaderNodeMix")
                mx.data_type = "RGBA"
                mx.blend_type = 'MIX' if chan == 0 else 'MULTIPLY'
                nt.links.new(sp3.outputs[chan], mx.inputs["Factor"])
                nt.links.new(col, mx.inputs[6])
                mx.inputs[7].default_value = (*tint, 1)
                col = mx.outputs[2]
        if col is not None:
            nt.links.new(col, p.inputs["Base Color"])
        # every MakeHuman body shares one UV layout: skins without their own normal map borrow the detailed one
        if not p.inputs["Normal"].is_linked and os.path.exists(DETAIL) and detail > 0:
            im = nt.nodes.new("ShaderNodeTexImage")
            im.image = bpy.data.images.load(DETAIL, check_existing=True)
            im.image.colorspace_settings.name = "Non-Color"
            nt.links.new(tc.outputs["UV"], im.inputs["Vector"])
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = detail
            nt.links.new(im.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
        vo = nt.nodes.new("ShaderNodeTexVoronoi")
        vo.inputs["Scale"].default_value = 900.0
        nt.links.new(tc.outputs["UV"], vo.inputs["Vector"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = pores
        bump.inputs["Distance"].default_value = 0.0004
        nt.links.new(vo.outputs["Distance"], bump.inputs["Height"])
        if p.inputs["Normal"].is_linked:
            nt.links.new(p.inputs["Normal"].links[0].from_socket, bump.inputs["Normal"])
        nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])


def landmarks(body):
    """Nose tip, head top and centre, eye height, chin and shoulders from the posed body (face looks -Y)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    vs = [ev.matrix_world @ v.co for v in ev.data.vertices]
    zmax = max(v.z for v in vs)
    head = [v for v in vs if v.z > zmax - 0.27 and abs(v.x) < 0.11]
    nose = min(head, key=lambda v: v.y)
    cy = sum(v.y for v in head) / len(head)
    cx = sum(v.x for v in head) / len(head)
    shoulders = [v for v in vs if zmax - 0.36 < v.z < zmax - 0.26]
    sw = max(v.x for v in shoulders) - min(v.x for v in shoulders) if shoulders else 0.4
    return {"top": zmax, "nose": nose, "cx": cx, "cy": cy, "eye_z": nose.z + 0.035, "chin_z": nose.z - 0.075,
            "shoulder_z": zmax - 0.3, "shoulder_w": sw}


def stubble(body, lm, amount=0.8):
    """Paint the 'Stubble' mask: jaw, chin, cheeks below the cheekbones, upper lip (not the lips themselves)."""
    me = body.data
    if "Stubble" not in me.color_attributes:
        me.color_attributes.new("Stubble", 'FLOAT_COLOR', 'POINT')
    att = me.color_attributes["Stubble"]
    nose = lm["nose"]
    cy = lm["cy"]
    for i, v in enumerate(me.vertices):
        p = body.matrix_world @ v.co
        a = 0.0
        if p.y < cy + 0.02 and lm["chin_z"] - 0.035 < p.z < nose.z - 0.012 and abs(p.x - lm["cx"]) < 0.075:
            a = amount
            mouth = abs(p.x - lm["cx"]) < 0.026 and nose.z - 0.045 < p.z < nose.z - 0.028 and p.y < nose.y + 0.03
            if mouth:
                a = 0.0                                          # the lips
            if p.z > nose.z - 0.03 and abs(p.x - lm["cx"]) > 0.045:
                a *= 0.4                                         # fade up the cheeks
        att.data[i].color = (a, a, a, 1.0)


def _hair_material(name, melanin, grey=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type == 'BSDF_PRINCIPLED':
            nt.nodes.remove(n)
    hb = nt.nodes.new("ShaderNodeBsdfHairPrincipled")
    if hasattr(hb, "parametrization"):
        hb.parametrization = 'MELANIN'                       # colour from pigment (otherwise the melanin is ignored)
    for k, v in (("Melanin", melanin), ("Melanin Redness", 0.1), ("Random Color", 0.08 + grey * 0.25),
                 ("Roughness", 0.24), ("Random Roughness", 0.15)):
        if k in hb.inputs:
            hb.inputs[k].default_value = v
    nt.links.new(hb.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    return m


def strand_hair(body, lm, rng, length=(0.03, 0.07), grey=0.0, count=40000, part=1.0):
    """Hair strands grown on the scalp: roots found by casting from a sphere round the head onto the body,
    kept above the hairline (higher at the front, lower at the back and over the ears' tops), combed back and to
    one side, falling a little with gravity. Grey strands come in at the temples with age (grey 0..1)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    inv = ev.matrix_world.inverted()
    c = Vector((lm["cx"], lm["cy"], lm["top"] - 0.1))
    front_y = lm["nose"].y + 0.05
    roots = []
    tries = 0
    while len(roots) < count and tries < count * 6:
        tries += 1
        u = rng.uniform(-1, 1)
        a = rng.uniform(0, math.tau)
        d = Vector((math.sqrt(1 - u * u) * math.cos(a), math.sqrt(1 - u * u) * math.sin(a), abs(u)))
        o = c + d * 0.3
        hit, loc, nrm, idx = ev.ray_cast(inv @ o, inv.to_3x3() @ (-d), distance=0.4)
        if not hit:
            continue
        p = ev.matrix_world @ loc
        back = (p.y - front_y) / 0.18                            # 0 at the hairline in front, 1 at the back
        line = lm["eye_z"] + 0.065 - 0.11 * max(0.0, min(1.0, back))
        if abs(p.x - lm["cx"]) > 0.065 and back < 0.55:
            line = max(line, lm["eye_z"] + 0.035)                # above the ears and temples
        if p.z < line:
            continue
        n = (ev.matrix_world.to_3x3() @ nrm).normalized()
        roots.append((p, n, idx))
    curves = bpy.data.hair_curves.new("Hair")
    seg = 6
    curves.add_curves([seg] * len(roots))
    pts = curves.points
    k = 0
    scalp = set()
    for p, n, idx in roots:
        scalp.add(idx)
        side = 1.0 if (p.x - lm["cx"]) * part >= 0 else -1.0
        comb = Vector((side * 0.35, 1.0, -0.15)).normalized()   # back and a little to the side
        L = rng.uniform(*length)
        d = (n * 0.6 + comb).normalized()                        # lifted off the scalp: volume
        q = p.copy()
        for s in range(seg):
            pts[k].position = q
            pts[k].radius = 0.0001 * (1.0 - 0.6 * s / seg)
            # follow the head: pull towards the surface and down a little
            to_c = (c - q).normalized()
            d = (d + to_c * 0.07 + Vector((0, 0, -0.05)) + Vector((rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06), 0))).normalized()
            q = q + d * (L / (seg - 1))
            k += 1
    # the scalp under the hair, dark (the 'Stubble' mask at full strength on the faces the roots grew from)
    me = body.data
    if "Stubble" not in me.color_attributes:
        me.color_attributes.new("Stubble", 'FLOAT_COLOR', 'POINT')
    att = me.color_attributes["Stubble"]
    for fi in scalp:
        if fi < len(me.polygons):
            for vi in me.polygons[fi].vertices:
                att.data[vi].color = (3.0, 3.0, 3.0, 1.0)
    ob = bpy.data.objects.new("Hair strands", curves)
    bpy.context.scene.collection.objects.link(ob)
    curves.materials.append(_hair_material("Hair", 0.92, grey))
    return ob


def matte(obj, colour=(0.035, 0.03, 0.026)):
    """Take the plastic shine off a hair proxy: dark, rough, no clear-coat (the strands give the sheen)."""
    for m in obj.data.materials:
        if m and m.use_nodes:
            p = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
            if p:
                for l in list(p.inputs["Base Color"].links):
                    m.node_tree.links.remove(l)
                p.inputs["Base Color"].default_value = (*colour, 1)
                p.inputs["Roughness"].default_value = 0.85
                if "Specular IOR Level" in p.inputs:
                    p.inputs["Specular IOR Level"].default_value = 0.15
                if "Coat Weight" in p.inputs:
                    p.inputs["Coat Weight"].default_value = 0.0


# ----------------------------------------------------------------------------- uniform
def fabric(name, colour, weave=600.0):
    """Cloth with a twill weave and soft folds in the normal."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*colour, 1)
    p.inputs["Roughness"].default_value = 0.88
    if "Sheen Weight" in p.inputs:
        p.inputs["Sheen Weight"].default_value = 0.3
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wv = nt.nodes.new("ShaderNodeTexWave")
    wv.inputs["Scale"].default_value = weave
    wv.bands_direction = 'DIAGONAL'
    nt.links.new(tc.outputs["UV"], wv.inputs["Vector"])
    fold = nt.nodes.new("ShaderNodeTexNoise")
    fold.inputs["Scale"].default_value = 9.0
    fold.inputs["Detail"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], fold.inputs["Vector"])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "MULTIPLY_ADD"
    nt.links.new(fold.outputs["Fac"], add.inputs[0])
    add.inputs[1].default_value = 6.0
    nt.links.new(wv.outputs["Fac"], add.inputs[2])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    bump.inputs["Distance"].default_value = 0.002
    nt.links.new(add.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
    return m


def _surface(target, origin, direction):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = target.evaluated_get(dg)
    inv = ev.matrix_world.inverted()
    hit, loc, nrm, idx = ev.ray_cast(inv @ origin, inv.to_3x3() @ direction, distance=1.0)
    if not hit:
        return None, None
    return ev.matrix_world @ loc, (ev.matrix_world.to_3x3() @ nrm).normalized()


def police_uniform(shirt, lm, khaki=(0.4, 0.31, 0.17), name_plate="R. MURUGAN"):
    """The khaki shirt as a police uniform: fabric, chest pockets with flaps and buttons, a button placket,
    epaulettes with brass 'NP' (Nagar Police, fictional), a belt and buckle, a name plate."""
    shirt.data.materials.clear()
    shirt.data.materials.append(fabric("Uniform Khaki", khaki))
    shirt.data.materials.append(fabric("Uniform Trousers", (khaki[0] * 0.92, khaki[1] * 0.92, khaki[2] * 0.95)))
    for p in shirt.data.polygons:
        z = sum((shirt.data.vertices[i].co.z for i in p.vertices)) / len(p.vertices)
        p.material_index = 1 if z < 0.93 else 0
    brass = bpy.data.materials.new("Brass")
    brass.use_nodes = True
    bp = brass.node_tree.nodes["Principled BSDF"]
    bp.inputs["Base Color"].default_value = (0.8, 0.6, 0.25, 1)
    bp.inputs["Metallic"].default_value = 1.0
    bp.inputs["Roughness"].default_value = 0.3
    leather = bpy.data.materials.new("Belt Leather")
    leather.use_nodes = True
    lp_ = leather.node_tree.nodes["Principled BSDF"]
    lp_.inputs["Base Color"].default_value = (0.09, 0.05, 0.025, 1)
    lp_.inputs["Roughness"].default_value = 0.45
    plate = bpy.data.materials.new("Name Plate")
    plate.use_nodes = True
    plate.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.03, 0.035, 1)
    mats = [shirt.data.materials[0], brass, leather, plate]
    bm = bmesh.new()
    cx = lm["cx"]
    sz = lm["shoulder_z"]

    def card(pos, nrm, w, h, mi, up=Vector((0, 0, 1)), lift=0.003):
        n = nrm.normalized()
        r = up.cross(n).normalized()
        u = n.cross(r).normalized()
        c = pos + n * lift
        vs = [bm.verts.new(c + r * sx * w / 2 + u * sy * h / 2) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        back = [bm.verts.new(v.co - n * 0.002) for v in vs]
        f = bm.faces.new(vs)
        f.material_index = mi
        for a, b in zip(range(4), [1, 2, 3, 0]):
            s = bm.faces.new((back[a], back[b], vs[b], vs[a]))
            s.material_index = mi

    def button(pos, nrm, r=0.0055, mi=1):
        res = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=r, radius2=r * 0.8, depth=0.003,
                                    matrix=Matrix.Translation(pos + nrm * 0.003) @ nrm.to_track_quat('Z', 'Y').to_matrix().to_4x4())
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = mi
    # pockets (with flaps and a button each), left and right chest
    for sx in (-1, 1):
        p, n = _surface(shirt, Vector((cx + sx * 0.085, lm["nose"].y - 0.5, sz - 0.13)), Vector((0, 1, 0)))
        if p is not None:
            card(p, n, 0.1, 0.11, 0, lift=0.0018)
            fp, fn = _surface(shirt, Vector((cx + sx * 0.085, lm["nose"].y - 0.5, sz - 0.075)), Vector((0, 1, 0)))
            if fp is not None:
                card(fp, fn, 0.106, 0.036, 0, lift=0.0035)
                button(fp + Vector((0, 0, -0.008)), fn, 0.005)
    # placket buttons down the front
    for k in range(5):
        p, n = _surface(shirt, Vector((cx, lm["nose"].y - 0.5, sz - 0.05 - k * 0.085)), Vector((0, 1, 0)))
        if p is not None:
            button(p, n, 0.0055)
    # epaulettes: strips along the top of each shoulder, collar to shoulder point, a brass button at the collar end
    for sx in (-1, 1):
        a_, na = _surface(shirt, Vector((cx + sx * 0.075, lm["cy"] + 0.02, sz + 0.5)), Vector((0, 0, -1)))
        b_, nb = _surface(shirt, Vector((cx + sx * 0.175, lm["cy"] + 0.02, sz + 0.5)), Vector((0, 0, -1)))
        if a_ is not None and b_ is not None:
            along = (b_ - a_)
            L = along.length
            mid = (a_ + b_) / 2 + ((na + nb) / 2).normalized() * 0.005
            Rm = along.to_track_quat('X', 'Z').to_matrix().to_4x4()
            res = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(mid) @ Rm @ Matrix.Diagonal((L, 0.055, 0.006, 1)))
            for f in {f for v in res["verts"] for f in v.link_faces}:
                f.material_index = 0
            button(a_ + along.normalized() * 0.015 + na * 0.008, na, 0.005)
            for j in range(2):                                   # 'N P' in small brass bars
                button(b_ - along.normalized() * (0.02 + j * 0.015) + nb * 0.009, nb, 0.0035)
    # belt round the waist: a band fitted to the shirt's cross-section at the waist height
    waist_z = sz - 0.5
    ring = []
    for k in range(36):
        a = k / 36 * math.tau
        d = Vector((math.cos(a), math.sin(a), 0))
        p, n = _surface(shirt, Vector((cx, lm["cy"], waist_z)) + d * 0.5, -d)
        if p is not None:
            ring.append((p + n * 0.004, n))
    if len(ring) > 20:
        top = [bm.verts.new(p + Vector((0, 0, 0.022))) for p, n in ring]
        bot = [bm.verts.new(p - Vector((0, 0, 0.022))) for p, n in ring]
        for i in range(len(ring)):
            j = (i + 1) % len(ring)
            f = bm.faces.new((bot[i], bot[j], top[j], top[i]))
            f.material_index = 2
        fp, fn = _surface(shirt, Vector((cx, lm["nose"].y - 0.5, waist_z)), Vector((0, 1, 0)))
        if fp is not None:
            card(fp, fn, 0.06, 0.045, 1, lift=0.009)
    # name plate over the right pocket (the wearer's right: -x)
    p, n = _surface(shirt, Vector((cx - 0.085, lm["nose"].y - 0.5, sz - 0.055)), Vector((0, 1, 0)))
    if p is not None:
        card(p, n, 0.075, 0.016, 3, lift=0.01)
    me = bpy.data.meshes.new("Uniform kit")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Uniform kit", me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        me.materials.append(m)
    return ob


def moustache(body, lm, rng, style="full", grey=0.0):
    """A moustache grown from strands on the upper lip only: 'full' (the classic Tamil one), 'thin', or 'none'."""
    if style == "none":
        return None
    nose = lm["nose"]
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    inv = ev.matrix_world.inverted()
    half = 0.03 if style == "full" else 0.026
    depth = 0.011 if style == "full" else 0.006
    roots = []
    for _ in range(9000):
        x = rng.uniform(-half, half)
        zt = nose.z - 0.019 - 0.004 * (abs(x) / half) ** 2
        z = rng.uniform(zt - depth - 0.006 * (abs(x) / half), zt)
        hit, loc, nrm, idx = ev.ray_cast(inv @ Vector((nose.x + x, nose.y - 0.2, z)), Vector((0, 1, 0)), distance=0.4)
        if hit:
            roots.append((ev.matrix_world @ loc, (ev.matrix_world.to_3x3() @ nrm).normalized(), x))
        if len(roots) >= (3200 if style == "full" else 1600):
            break
    curves = bpy.data.hair_curves.new("Moustache")
    seg = 5
    curves.add_curves([seg] * len(roots))
    pts = curves.points
    k = 0
    for root, nrm, x in roots:
        side = 1.0 if x >= 0 else -1.0
        L = rng.uniform(0.006, 0.010) * (1.0 - 0.25 * abs(x) / half) * (1.0 if style == "full" else 0.7)
        d = (nrm * 0.55 + Vector((side * 0.45 * abs(x) / half, -0.1, -0.8))).normalized()
        p = root.copy()
        for sgi in range(seg):
            pts[k].position = p
            pts[k].radius = 0.00006 * (1.0 - sgi / seg) + 0.00002
            d = (d + Vector((0, 0, -0.18)) + Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.05, 0.05), 0))).normalized()
            p = p + d * (L / (seg - 1))
            k += 1
    ob = bpy.data.objects.new("Moustache", curves)
    bpy.context.scene.collection.objects.link(ob)
    curves.materials.append(_hair_material("Moustache", 0.93 - 0.5 * grey, grey))
    return ob


def police_cap(cx, cy, zmax, head_r=0.095, front_y=None):
    """A peaked service cap worn properly: a dark band round the forehead (not perched on top), a khaki crown
    flaring out to an oval top that dips a little at the back, a glossy black visor curving down over the eyes,
    a brass badge at the front. Smooth (48 segments)."""
    seg = 48
    band = bpy.data.materials.new("Cap Band")
    band.use_nodes = True
    band.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.04, 0.035, 1)
    band.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
    crown = fabric("Cap Khaki", (0.4, 0.31, 0.17), 700.0)
    visor = bpy.data.materials.new("Cap Visor")
    visor.use_nodes = True
    vp = visor.node_tree.nodes["Principled BSDF"]
    vp.inputs["Base Color"].default_value = (0.01, 0.01, 0.01, 1)
    vp.inputs["Roughness"].default_value = 0.12
    brass = bpy.data.materials.new("Cap Badge")
    brass.use_nodes = True
    bp = brass.node_tree.nodes["Principled BSDF"]
    bp.inputs["Base Color"].default_value = (0.82, 0.62, 0.25, 1)
    bp.inputs["Metallic"].default_value = 1.0
    bp.inputs["Roughness"].default_value = 0.28
    bm = bmesh.new()
    r0 = head_r + 0.006
    # profile (height above the band's foot, radius x, radius y), front of the oval at -y
    base_z = zmax - 0.085
    prof = [(0.0, r0, r0 * 1.08), (0.045, r0 + 0.002, r0 * 1.08 + 0.002), (0.06, r0 + 0.012, r0 * 1.1 + 0.012),
            (0.095, r0 + 0.04, r0 * 1.12 + 0.045), (0.105, r0 + 0.038, r0 * 1.12 + 0.043)]
    rings = []
    for z, rx, ry in prof:
        ring = []
        for k in range(seg):
            a = k / seg * math.tau
            back = max(0.0, math.sin(a))                         # +y is the back of the head
            dz = -0.012 * back * (z / 0.105)                     # the top dips towards the back
            ring.append(bm.verts.new((cx + math.cos(a) * rx, cy + 0.005 + math.sin(a) * ry, base_z + z + dz)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(seg):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % seg], rings[i + 1][(k + 1) % seg], rings[i + 1][k]))
            f.material_index = 0 if i == 0 else 1
            f.smooth = True
    top = bm.faces.new(rings[-1])
    top.material_index = 1
    top.smooth = True
    # the visor: a curved half-oval out of the band's front, sloping down
    vz = base_z + 0.004
    outer, inner = [], []
    for k in range(17):
        a = math.pi + k / 16 * math.pi                          # the front half (-y)
        ix, iy = cx + math.cos(a) * r0, cy + math.sin(a) * r0 * 1.08
        ox, oy = cx + math.cos(a) * (r0 + 0.012), cy + math.sin(a) * (r0 * 1.08 + 0.06) - 0.004
        depth = 0.06 * abs(math.sin(a))
        inner.append(bm.verts.new((ix, iy, vz)))
        outer.append(bm.verts.new((ox, oy, vz - 0.018 * (depth / 0.06) - 0.004)))
    for k in range(16):
        f = bm.faces.new((inner[k], inner[k + 1], outer[k + 1], outer[k]))
        f.material_index = 2
        f.smooth = True
    # badge on the front of the crown
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.016, radius2=0.012, depth=0.004,
                                matrix=Matrix.Translation((cx, cy - r0 * 1.1 - 0.012, base_z + 0.065))
                                @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = 3
    me = bpy.data.meshes.new("Police Cap")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Police Cap", me)
    bpy.context.scene.collection.objects.link(ob)
    for m in (band, crown, visor, brass):
        me.materials.append(m)
    return ob


def jasmine(lm, rng, count=46):
    """Malli poo: a string of jasmine buds round the back of the head and down the braid."""
    white = bpy.data.materials.new("Jasmine")
    white.use_nodes = True
    jp = white.node_tree.nodes["Principled BSDF"]
    jp.inputs["Base Color"].default_value = (0.95, 0.94, 0.86, 1)
    jp.inputs["Roughness"].default_value = 0.5
    jp.inputs["Subsurface Weight"].default_value = 0.3
    green = bpy.data.materials.new("Jasmine Stem")
    green.use_nodes = True
    green.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.2, 0.35, 0.08, 1)
    bm = bmesh.new()
    cx, cy, ez = lm["cx"], lm["cy"], lm["eye_z"]
    path = []
    for k in range(count):
        t = k / (count - 1)
        if t < 0.45:                                     # an arc across the back of the head
            a = math.pi * (0.15 + 0.7 * t / 0.45)
            path.append(Vector((cx + math.cos(a) * 0.075, cy + 0.07 + math.sin(a) * 0.02, ez + 0.035 - 0.01 * math.sin(a))))
        else:                                            # and down the braid
            u = (t - 0.45) / 0.55
            path.append(Vector((cx + 0.012 * math.sin(u * 9), cy + 0.105 + 0.02 * u, ez + 0.01 - 0.2 * u)))
    for p in path:
        for j in range(2):
            o = Vector((rng.uniform(-0.006, 0.006), rng.uniform(-0.004, 0.004), rng.uniform(-0.004, 0.004)))
            res = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=rng.uniform(0.0045, 0.006),
                                            matrix=Matrix.Translation(p + o) @ Matrix.Diagonal((1.0, 1.0, 1.6, 1.0)))
            for f in {f for v in res["verts"] for f in v.link_faces}:
                f.material_index = 0
                f.smooth = True
    me = bpy.data.meshes.new("Jasmine")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Jasmine", me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(white)
    me.materials.append(green)
    return ob


def silk(name, colour, border=(0.85, 0.62, 0.12)):
    """Saree silk: sheen, small woven motifs (buttas), a gold zari border along the cloth's edges (UV v near
    0 or 1) and a richer band at the pallu's end (UV u near 1)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.42
    if "Sheen Weight" in p.inputs:
        p.inputs["Sheen Weight"].default_value = 0.6
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["UV"], sep.inputs[0])
    # border mask: near the long edges, and the end band
    def near(src, lo, hi):
        a = nt.nodes.new("ShaderNodeMath")
        a.operation = "LESS_THAN"
        nt.links.new(src, a.inputs[0])
        a.inputs[1].default_value = lo
        b = nt.nodes.new("ShaderNodeMath")
        b.operation = "GREATER_THAN"
        nt.links.new(src, b.inputs[0])
        b.inputs[1].default_value = hi
        c = nt.nodes.new("ShaderNodeMath")
        c.operation = "MAXIMUM"
        nt.links.new(a.outputs[0], c.inputs[0])
        nt.links.new(b.outputs[0], c.inputs[1])
        return c.outputs[0]
    edge = near(sep.outputs["Y"], 0.08, 0.92)
    endb = nt.nodes.new("ShaderNodeMath")
    endb.operation = "GREATER_THAN"
    nt.links.new(sep.outputs["X"], endb.inputs[0])
    endb.inputs[1].default_value = 0.82
    mask = nt.nodes.new("ShaderNodeMath")
    mask.operation = "MAXIMUM"
    nt.links.new(edge, mask.inputs[0])
    nt.links.new(endb.outputs[0], mask.inputs[1])
    # buttas: small dots in a grid
    vo = nt.nodes.new("ShaderNodeTexVoronoi")
    vo.inputs["Scale"].default_value = 40.0
    vo.inputs["Randomness"].default_value = 0.0
    nt.links.new(tc.outputs["UV"], vo.inputs["Vector"])
    dot = nt.nodes.new("ShaderNodeMath")
    dot.operation = "LESS_THAN"
    nt.links.new(vo.outputs["Distance"], dot.inputs[0])
    dot.inputs[1].default_value = 0.12
    base = nt.nodes.new("ShaderNodeMix")
    base.data_type = "RGBA"
    nt.links.new(dot.outputs[0], base.inputs["Factor"])
    base.inputs[6].default_value = (*colour, 1)
    base.inputs[7].default_value = (*border, 1)
    fin = nt.nodes.new("ShaderNodeMix")
    fin.data_type = "RGBA"
    nt.links.new(mask.outputs[0], fin.inputs["Factor"])
    nt.links.new(base.outputs[2], fin.inputs[6])
    fin.inputs[7].default_value = (*border, 1)
    nt.links.new(fin.outputs[2], p.inputs["Base Color"])
    met = nt.nodes.new("ShaderNodeMath")
    met.operation = "MULTIPLY"
    nt.links.new(mask.outputs[0], met.inputs[0])
    met.inputs[1].default_value = 0.7
    nt.links.new(met.outputs[0], p.inputs["Metallic"])
    return m


def drape_pallu(body, top, colour, rng, frames=45, lm=None):
    """The pallu as real cloth: a wide band laid from the right hip, up across the chest, over the left shoulder
    and down the back, pinned where it is tucked at the waist and where it sits on the shoulder, then let fall
    under gravity over the body (cloth simulation), so its folds are its own."""
    lm = lm or landmarks(body)
    k_ = lm["top"] / 1.72                                       # the path was laid out on a 1.72 m body
    path = [Vector((lm["cx"] + x * k_, lm["cy"] + 0.02 + y * k_, z * k_))
            for x, y, z in ((-0.13, -0.13, 1.0), (-0.07, -0.16, 1.12), (0.0, -0.17, 1.24), (0.08, -0.14, 1.36),
                            (0.15, -0.06, 1.46), (0.17, 0.04, 1.47), (0.16, 0.12, 1.32), (0.15, 0.15, 1.1),
                            (0.14, 0.16, 0.88), (0.13, 0.16, 0.7))]
    # pleated narrow across the chest and pinned at the shoulder, fanning out down the back
    widths = [0.13, 0.13, 0.12, 0.11, 0.1, 0.12, 0.3, 0.42, 0.46, 0.48]
    pleat = [1.0, 1.0, 1.0, 1.0, 1.0, 0.8, 0.3, 0.0, 0.0, 0.0]
    rows, cols = 52, 19
    # resample the path by length
    seg = [(path[i + 1] - path[i]).length for i in range(len(path) - 1)]
    total = sum(seg)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    grid = []
    for r in range(rows):
        t = r / (rows - 1) * total
        i = 0
        while i < len(seg) - 1 and t > seg[i]:
            t -= seg[i]
            i += 1
        f = min(1.0, t / max(seg[i], 1e-6))
        c = path[i].lerp(path[i + 1], f)
        w = widths[i] + (widths[i + 1] - widths[i]) * f
        run = (path[i + 1] - path[i]).normalized()
        out = Vector((c.x, c.y * 1.3, 0)).normalized()
        if c.z > 1.42:
            out = (out + Vector((0, 0, 1.4))).normalized()
        side = run.cross(out).normalized()
        pl = pleat[i] + (pleat[i + 1] - pleat[i]) * f
        row = []
        for k in range(cols):
            v = k / (cols - 1)
            amp = 0.0045 + 0.004 * ((k * 7919 + 13) % 11) / 10.0         # uneven, hand-made folds
            zig = out * (amp * pl * (1 if k % 2 else -1))
            row.append(bm.verts.new(c + out * 0.03 + zig + side * (v - 0.5) * w))
        grid.append(row)
    for r in range(rows - 1):
        for k in range(cols - 1):
            face = bm.faces.new((grid[r][k], grid[r][k + 1], grid[r + 1][k + 1], grid[r + 1][k]))
            for lp, (rr, kk) in zip(face.loops, ((r, k), (r, k + 1), (r + 1, k + 1), (r + 1, k))):
                lp[uvl].uv = (rr / (rows - 1), kk / (cols - 1))
    me = bpy.data.meshes.new("Pallu")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Pallu", me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(silk("Saree Silk", colour))
    pin = ob.vertex_groups.new(name="Pin")
    for v in me.vertices:
        r = round(v.co.z * 1000)
        if v.co.z < 1.04 * k_ or (v.co.z > 1.42 * k_ and v.co.x - lm["cx"] > 0.1 * k_):
            pin.add([v.index], 1.0, 'REPLACE')
    for o in (body, top):
        if o is not None:
            o.modifiers.new("Collision", 'COLLISION')
            o.collision.thickness_outer = 0.006
    cl = ob.modifiers.new("Cloth", 'CLOTH')
    st = cl.settings
    st.quality = 8
    st.mass = 0.12
    st.tension_stiffness = 8.0
    st.compression_stiffness = 8.0
    st.bending_stiffness = 0.45                                  # silk: crisp folds
    st.vertex_group_mass = "Pin"
    cl.collision_settings.distance_min = 0.004
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, frames
    cl.point_cache.frame_start, cl.point_cache.frame_end = 1, frames
    for f in range(1, frames + 1):
        sc.frame_set(f)
    dg = bpy.context.evaluated_depsgraph_get()
    baked = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.clear()
    ob.data = baked
    for pl in baked.polygons:
        pl.use_smooth = True
    ob.modifiers.new("Smooth", 'SUBSURF').levels = 1
    sol = ob.modifiers.new("Thick", 'SOLIDIFY')
    sol.thickness = 0.003
    for o in (body, top):
        if o is not None:
            for m in list(o.modifiers):
                if m.type == 'COLLISION':
                    o.modifiers.remove(m)
    sc.frame_set(1)
    return ob


def _gold():
    g = bpy.data.materials.new("Gold")
    g.use_nodes = True
    gp = g.node_tree.nodes["Principled BSDF"]
    gp.inputs["Base Color"].default_value = (0.95, 0.68, 0.28, 1)
    gp.inputs["Metallic"].default_value = 1.0
    gp.inputs["Roughness"].default_value = 0.22
    return g


def feminine(body, lm, eyes_obj, rng):
    """Makeup and jewellery: kajal round the eyes, rose-brown lips, a little blush (the 'Makeup' mask the skin
    shader reads — call before skin_upgrade), a red bindi, gold jhumka earrings, a nose stud, a thin chain."""
    me = body.data
    if "Makeup" not in me.color_attributes:
        me.color_attributes.new("Makeup", 'FLOAT_COLOR', 'POINT')
    att = me.color_attributes["Makeup"]
    nose = lm["nose"]
    eyes = []
    if eyes_obj is not None:
        vs = [eyes_obj.matrix_world @ v.co for v in eyes_obj.data.vertices]
        for side in (-1, 1):
            e = [v for v in vs if (v.x - lm["cx"]) * side > 0]
            if e:
                eyes.append(sum(e, Vector()) / len(e))
    for i, v in enumerate(me.vertices):
        p = body.matrix_world @ v.co
        k = l = b = 0.0
        for e in eyes:
            d = math.hypot((p.x - e.x) / 1.25, p.z - e.z)
            if p.y < e.y + 0.01 and 0.0112 < d < 0.0142:
                k = max(k, 0.6 * (1.0 - abs(d - 0.0127) / 0.0016))
        mz = nose.z - 0.036                                     # the lips: an ellipse, fading at its edge
        e2 = ((p.x - lm["cx"]) / 0.023) ** 2 + ((p.z - mz) / 0.0095) ** 2
        if e2 < 1.0 and p.y < nose.y + 0.03:
            l = 0.85 * min(1.0, (1.0 - e2) * 2.5)
        for side in (-1, 1):
            cxk = lm["cx"] + side * 0.045
            d = math.hypot(p.x - cxk, p.z - (nose.z - 0.005))
            if d < 0.03 and p.y < nose.y + 0.05:
                b = max(b, 0.35 * (1.0 - d / 0.03))
        att.data[i].color = (max(0.0, k), l, b, 1.0)
    gold = _gold()
    red = bpy.data.materials.new("Bindi")
    red.use_nodes = True
    red.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.01, 0.02, 1)
    red.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.3
    bm = bmesh.new()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    inv = ev.matrix_world.inverted()

    def on_face(x, z):
        hit, loc, nrm, idx = ev.ray_cast(inv @ Vector((x, nose.y - 0.3, z)), Vector((0, 1, 0)), distance=0.5)
        return (ev.matrix_world @ loc, (ev.matrix_world.to_3x3() @ nrm).normalized()) if hit else (None, None)

    def disc(p, n, r, mi, depth=0.0015):
        res = bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=r, radius2=r, depth=depth,
                                    matrix=Matrix.Translation(p + n * depth) @ n.to_track_quat('Z', 'Y').to_matrix().to_4x4())
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = mi
    # bindi between the brows
    bp, bn = on_face(lm["cx"], lm["eye_z"] + 0.028)
    if bp is not None:
        disc(bp, bn, 0.0042, 1)
    # nose stud on the left nostril
    sp_, sn = on_face(lm["cx"] + 0.016, nose.z - 0.008)
    if sp_ is not None:
        res = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=0.0022, matrix=Matrix.Translation(sp_ + sn * 0.0015))
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = 0
    # jhumkas: the ear lobes are the outermost points just below the nose's height
    vs = [ev.matrix_world @ v.co for v in ev.data.vertices]
    for side in (-1, 1):
        band = [v for v in vs if nose.z - 0.035 < v.z < nose.z - 0.005 and (v.x - lm["cx"]) * side > 0.05 and v.y > nose.y + 0.06]
        if not band:
            continue
        lobe = max(band, key=lambda v: (v.x - lm["cx"]) * side)
        top = lobe + Vector((side * 0.004, 0, -0.004))
        res = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=0.0035, matrix=Matrix.Translation(top))
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = 0
        bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.0007, radius2=0.0007, depth=0.008,
                              matrix=Matrix.Translation(top + Vector((0, 0, -0.006))))
        bell = top + Vector((0, 0, -0.018))
        res = bmesh.ops.create_cone(bm, cap_ends=False, segments=16, radius1=0.0085, radius2=0.002, depth=0.012,
                                    matrix=Matrix.Translation(bell))
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = 0
        for j in range(8):                                  # the little drops round the bell's rim
            a = j / 8 * math.tau
            res = bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=0.0012,
                                            matrix=Matrix.Translation(bell + Vector((math.cos(a) * 0.0085, math.sin(a) * 0.0085, -0.0075))))
    # a thin chain round the neck, lower at the front
    ring = []
    for j in range(40):
        a = j / 40 * math.tau
        d = Vector((math.cos(a), math.sin(a), 0))
        z = lm["chin_z"] - 0.07 - 0.03 * max(0.0, -math.sin(a))
        hit, loc, nrm, idx = ev.ray_cast(inv @ (Vector((lm["cx"], lm["cy"], z)) + d * 0.3), inv.to_3x3() @ (-d), distance=0.35)
        if hit:
            ring.append(ev.matrix_world @ loc + (ev.matrix_world.to_3x3() @ nrm).normalized() * 0.002)
    for a, b in zip(ring, ring[1:] + ring[:1]):
        if (b - a).length < 0.05:
            bmesh.ops.create_cone(bm, cap_ends=False, segments=6, radius1=0.0009, radius2=0.0009, depth=(b - a).length,
                                  matrix=Matrix.Translation((a + b) / 2) @ (b - a).to_track_quat('Z', 'Y').to_matrix().to_4x4())
    me2 = bpy.data.meshes.new("Jewellery")
    bm.to_mesh(me2)
    bm.free()
    ob = bpy.data.objects.new("Jewellery", me2)
    bpy.context.scene.collection.objects.link(ob)
    me2.materials.append(gold)
    me2.materials.append(red)
    for pl in me2.polygons:
        pl.use_smooth = True
    return ob


def long_hair(body, lm, rng, length=0.42, guides=320, children=60000, part=0.0, bangs=True, melanin=1.0,
              wave=0.004, clump=0.3):
    """Long open hair: guide strands grown from the scalp, styled with gravity and pushed out of the body (a
    BVH collision with the head, neck and shoulders), then thousands of child strands following their nearest
    guide, clumped towards it at the tips — layered lengths, a parting (part: -1 left .. 0 middle .. +1 right)
    and soft face-framing strands in front."""
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    bvh = BVHTree.FromObject(ev, dg)
    mw = ev.matrix_world
    inv = mw.inverted()
    c = Vector((lm["cx"], lm["cy"], lm["top"] - 0.1))
    front_y = lm["nose"].y + 0.05
    part_x = lm["cx"] + part * 0.03

    def scalp_point():
        for _ in range(60):
            u = rng.uniform(-1, 1)
            a = rng.uniform(0, math.tau)
            d = Vector((math.sqrt(1 - u * u) * math.cos(a), math.sqrt(1 - u * u) * math.sin(a), abs(u)))
            hit, loc, nrm, idx = ev.ray_cast(inv @ (c + d * 0.3), inv.to_3x3() @ (-d), distance=0.4)
            if not hit:
                continue
            p = mw @ loc
            back = (p.y - front_y) / 0.18
            ax = min(1.0, abs(p.x - lm["cx"]) / 0.075)
            # a rounded hairline: highest mid-forehead, curving down to the temples; soft and uneven at the edge
            line = lm["eye_z"] + 0.064 - 0.024 * ax * ax + 0.004 * math.sin(p.x * 900.0)
            line -= 0.12 * max(0.0, min(1.0, back))
            if ax >= 1.0 and back < 0.55:
                line = max(line, lm["eye_z"] + 0.03)
            if p.z >= line + rng.uniform(-0.002, 0.008):
                return p, (mw.to_3x3() @ nrm).normalized()
        return None, None

    def collide(q, d):
        loc, nrm, idx, dist = bvh.find_nearest(inv @ q)
        if loc is None:
            return q, d
        sp = mw @ loc
        n = (mw.to_3x3() @ nrm).normalized()
        gap = (q - sp).dot(n)
        if gap < 0.006:                                          # inside or skimming: lift it out, slide along
            q = sp + n * 0.006
            d = (d - n * min(0.0, d.dot(n)) * 1.2).normalized()
        return q, d
    seg = 16
    guide_curves = []
    for g in range(guides):
        root, n = scalp_point()
        if root is None:
            continue
        side = 1.0 if root.x >= part_x else -1.0
        front = root.y < front_y + 0.03
        L = length * rng.uniform(0.75, 1.05)
        if bangs and front and abs(root.x - part_x) < 0.06:
            L *= rng.uniform(0.55, 0.8)                          # face-framing front layers
        comb = Vector((side * 0.55, 0.55, -0.5)) if not front else Vector((side * 0.35, 0.95, -0.05))   # front: swept back
        d = (comb - n * comb.dot(n)).normalized()                   # along the scalp, not out of it
        d = (d + n * 0.12).normalized()
        pts = [root.copy()]
        q = root.copy()
        for k in range(1, seg):
            t = k / (seg - 1)
            d = (d + Vector((0, 0.015, -0.35 - 0.35 * t))).normalized()  # gravity takes over down the length
            q = q + d * (L / (seg - 1))
            q, d = collide(q, d)
            if t < 0.35:                                          # the top lies close to the head
                loc, nrm2, idx2, dist2 = bvh.find_nearest(inv @ q)
                if loc is not None and dist2 > 0.034:
                    q = q.lerp(mw @ loc + (mw.to_3x3() @ nrm2).normalized() * 0.026, 0.3)   # some volume
            q = q + Vector((math.sin(t * 7 + g) * wave * t, 0, 0))
            # never across the face: in front of it, push the strand out to the side
            if q.y < lm["nose"].y + 0.06 and abs(q.x - lm["cx"]) < 0.08 and lm["chin_z"] - 0.03 < q.z < lm["eye_z"] + 0.05:
                q.x = lm["cx"] + side * 0.08
                d = (d + Vector((side * 0.5, 0.2, 0))).normalized()
            pts.append(q.copy())
        guide_curves.append(pts)
    gr = [g[0] for g in guide_curves]
    curves = bpy.data.hair_curves.new("Long hair")
    from mathutils.kdtree import KDTree
    kdg = KDTree(len(gr))
    for j, r in enumerate(gr):
        kdg.insert(r, j)
    kdg.balance()
    kids = []
    for i in range(children):
        root, n = scalp_point()
        if root is None:
            continue
        near = kdg.find_n(root, 3)                               # blend the three nearest guides: smooth, not clumped
        w = [1.0 / (d + 0.004) for _, _, d in near]
        sw = sum(w)
        fly = (0.012 + 0.02 * rng.random()) if rng.random() < 0.035 else 0.0              # a few flyaways
        drift = Vector((rng.gauss(0, 1), rng.gauss(0, 0.5), rng.gauss(0, 0.3))) * (0.0025 + fly)
        kids.append((root, [(j, wj / sw) for (_, j, _), wj in zip(near, w)], rng.uniform(0.75, 1.0), drift,
                     rng.uniform(0, 6.28)))
    curves.add_curves([seg] * len(kids))
    P = curves.points
    k = 0
    for root, gws, lf, drift, ph in kids:
        for s_ in range(seg):
            t = s_ / (seg - 1)
            si = min(seg - 1, int(round(s_ * lf)))
            pos = Vector((0, 0, 0))
            for j, wj in gws:
                g = guide_curves[j]
                pos += (g[si] + (root - g[0]) * (1.0 - clump * t)) * wj
            P[k].position = pos + drift * (t * t) + Vector((math.sin(t * 9 + ph), 0, math.cos(t * 7 + ph))) * 0.0008 * t
            P[k].radius = 0.000036 * (1.0 - 0.6 * t) + 0.000008
            k += 1
    ob = bpy.data.objects.new("Long hair", curves)
    bpy.context.scene.collection.objects.link(ob)
    curves.materials.append(_hair_material("Long Hair", melanin))
    return ob


FACEUNITS = os.path.expanduser("~/Library/Application Support/Blender/5.2/extensions/.user/user_default/mpfb/data/targets/faceunits")


def expression(h, rng, smile=0.35):
    """A soft, natural expression: a gentle smile reaching the cheeks and eyes, relaxed lids, a hint of lifted
    brows (MakeHuman's face units)."""
    import importlib
    import sys
    TS = None
    for m in sys.modules:
        if m.endswith("mpfb.services.targetservice"):
            TS = getattr(importlib.import_module(m), "TargetService")
    if TS is None:
        return
    units = {"mouthSmileLeft": smile, "mouthSmileRight": smile * rng.uniform(0.85, 1.0),
             "cheekSquintLeft": smile * 0.6, "cheekSquintRight": smile * 0.55, "eyeSquintLeft": smile * 0.45,
             "eyeSquintRight": smile * 0.45, "eyeBlinkLeft": 0.1, "eyeBlinkRight": 0.1, "browInnerUp": 0.06,
             "mouthDimpleLeft": smile * 0.3, "mouthDimpleRight": smile * 0.3}
    for name, w in units.items():
        path = os.path.join(FACEUNITS, name + ".target")
        if os.path.exists(path):
            try:
                TS.load_target(h, path, weight=w, name="fu-" + name)
            except Exception:
                pass
