"""
Heads from Google's GNM Head (third_party/gnm, Apache 2.0): a statistical head model learned from ~5,000 scans.
A head is the template plus identity and expression offsets; its semantic decoders (run here in plain numpy,
weights exported to third_party/gnm/sampler/decoders.npz) turn gender / ethnicity / expression labels into those
offsets. We give it our own materials: skin (tone, lips, blush, kajal from GNM's face regions, pores, subsurface
scattering), wet eyes, teeth; hair, brows and lashes come from quality.py.

    head = build_head(rng, female=1.0, ethnicity=dict(asian=.35, middle_eastern=.35, black=.3), smile=.6)
"""
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "third_party", "gnm")
_MODEL = None
_DEC = None
EXPRESSIONS = ["SURPRISE", "DISGUST", "SUCK", "COMPRESS_FACE", "STRETCH_FACE", "HAPPY", "SQUINT", "PLATYSMA", "BLOW",
               "FUNNELER", "SMILE_WIDE", "CORNERS_DOWN", "PUCKER", "WINK_LEFT", "WINK_RIGHT", "MOUTH_LEFT",
               "MOUTH_RIGHT", "LIPS_ROLL_IN", "SNARL", "TONGUE_CENTER"]


def model():
    global _MODEL, _DEC
    if _MODEL is None:
        _MODEL = dict(np.load(os.path.join(ROOT, "model", "gnm_head.npz"), allow_pickle=False))
        _DEC = dict(np.load(os.path.join(ROOT, "sampler", "decoders.npz"), allow_pickle=False))
    return _MODEL, _DEC


def _mlp(tag, x):
    _, d = model()
    for i in range(5):
        x = x @ d["%s_W%d" % (tag, i)] + d["%s_b%d" % (tag, i)]
        if i < 4:
            x = np.maximum(x, 0.0)
    return x


def identity_params(rng, female=1.0, ethnicity=None, spread=0.8):
    """253 identity values for a gender blend (female 0..1) and an ethnicity blend (weights of middle_eastern,
    asian, white, black) — the decoder's own labels, blended."""
    eth = {"middle_eastern": 0.0, "asian": 0.0, "white": 0.0, "black": 0.0}
    eth.update(ethnicity or {"middle_eastern": 0.6, "black": 0.3, "asian": 0.0, "white": 0.1})
    lab = np.array([[female, 1.0 - female, eth["middle_eastern"], eth["asian"], eth["white"], eth["black"]]], np.float32)
    z = rng.normal(size=(1, 64)).astype(np.float32) * spread
    return _mlp("identity", np.concatenate([z, lab], 1))[0]


def expression_params(rng, weights):
    """383 expression values for a blend of expression classes, e.g. {"HAPPY": .7}."""
    lab = np.zeros((1, 20), np.float32)
    for k, w in weights.items():
        lab[0, EXPRESSIONS.index(k)] = w
    z = rng.normal(size=(1, 64)).astype(np.float32) * 0.5
    return _mlp("expression", np.concatenate([z, lab], 1))[0]


def _smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def _landmarks(v):
    """Eye and mouth heights (GNM y) and the width of the face at the cheekbones, the mouth and the jaw."""
    S = v[_group("skin") > 0.5]
    front = S[S[:, 2] > np.percentile(S[:, 2], 55)]
    ey = v[_group("eyes") > 0.5][:, 1].mean()
    ly = v[(_group("upper_lip") > 0.5) | (_group("lower_lip") > 0.5)][:, 1].mean()

    def w(y):
        r = front[np.abs(front[:, 1] - y) < 0.004]
        return r[:, 0].max() - r[:, 0].min()
    return ey, ly, w(ey - 0.02), w(ly), w(ly - 0.03)


_FEM = None


def female_direction():
    """Mean female identity minus mean male identity over the same latents: the decoder separates the sexes
    only weakly (heads ~2 % apart), so a character is pushed further along this line."""
    global _FEM
    if _FEM is None:
        rng = np.random.default_rng(12345)
        z = rng.normal(size=(200, 64)).astype(np.float32) * 0.55
        lab = np.tile(np.array([[1, 0, .5, .1, .1, .3]], np.float32), (200, 1))
        f = _mlp("identity", np.concatenate([z, lab], 1)).mean(0)
        lab[:, :2] = (0, 1)
        _FEM = f - _mlp("identity", np.concatenate([z, lab], 1)).mean(0)
    return _FEM


def pick_identity(rng, female=1.0, ethnicity=None, spread=0.55, tries=24, push=2.5):
    """The slimmest, most V-shaped face of a few samples (narrow at the mouth and jaw for the cheekbones),
    pushed `push` x further along the female (or, for men, male) direction."""
    best = None
    for _ in range(tries):
        idp = identity_params(rng, female, ethnicity, spread) + push * (2 * female - 1) * female_direction()
        _, _, we, wm, wc = _landmarks(vertices(idp))
        score = (wm / we + 0.6 * wc / we) * (1 if female >= 0.5 else -1)
        if best is None or score < best[0]:
            best = (score, idp)
    return best[1]


def sculpt(v, slim=1.0, eyes=1.0):
    """A character artist's pass on a neutral head: a V-line jaw and leaner cheeks (narrowed towards the middle,
    most at the chin, fading out towards the ears) and slightly larger eyes (eyeballs, lids and sockets scaled
    about each eye's centre)."""
    v = v.copy()
    ey, ly, _, _, _ = _landmarks(v)
    S = v[_group("skin") > 0.5]
    zc = 0.5 * (S[:, 2].min() + S[:, 2].max())                 # the ears' depth
    depth = _smooth((v[:, 2] - zc) / 0.07)                     # 0 at the ears and back, 1 on the face
    below = _smooth((ly + 0.012 - v[:, 1]) / 0.055)           # 0 above the mouth, 1 from the chin down
    cheek = _smooth((ey - 0.005 - v[:, 1]) / 0.03) * (1 - below)
    cx = np.median(v[:, 0])
    k = 1.0 - slim * depth * (0.13 * below + 0.045 * cheek)
    v[:, 0] = cx + (v[:, 0] - cx) * k
    nose = _group("nose_region")
    if nose is not None:                                       # a slimmer nose
        v[:, 0] = cx + (v[:, 0] - cx) * (1.0 - 0.09 * slim * np.clip(nose, 0, 1))
    E = v[_group("eyes") > 0.5]
    for sx in (1, -1):
        e = E[(E[:, 0] - cx) * sx > 0]
        c = e.mean(axis=0)
        r = np.linalg.norm(v - c, axis=1)
        a = eyes * 0.1 * (1 - _smooth((r - 0.014) / 0.02))
        v += (v - c) * a[:, None] * np.array([1.0, 1.5, 1.0])     # the opening taller more than wider
    # open the eyes: lift the upper lid and drop the lower one (skin only; the eyeballs stay)
    skin = _group("skin") > 0.5
    for g in ("scleras", "irises", "pupils", "eye_exteriors", "eyes"):
        w = _group(g)
        if w is not None:
            skin &= w < 0.5
    for sx in (1, -1):
        e = v[_group("eyes") > 0.5]
        e = e[(e[:, 0] - cx) * sx > 0]
        c = e.mean(axis=0)
        dx = np.abs(v[:, 0] - c[0])
        dy = v[:, 1] - c[1]
        front = v[:, 2] > c[2]
        across = 1 - _smooth(dx / 0.019)
        near = 1 - _smooth((np.abs(dy) - 0.004) / 0.014)
        up = eyes * 0.0012 * across * near * (dy > 0)
        down = eyes * 0.0005 * across * near * (dy <= 0)
        m = skin & front
        v[m, 1] += (up - down)[m]
        # an eyelid crease ~7 mm above the lid line, and a slightly deeper socket: shadow and depth
        crease = eyes * 0.0011 * across * (1 - _smooth(np.abs(dy - 0.0085) / 0.003)) * (dy > 0)
        socket = eyes * 0.0008 * (1 - _smooth((np.hypot(dx, dy) - 0.01) / 0.012))
        v[m, 2] -= (crease + socket)[m]
    return v


_MIRROR = None


def mirror_index():
    """For every vertex, its mirror twin across the face's middle (x → -x) on the template."""
    global _MIRROR
    if _MIRROR is None:
        from mathutils.kdtree import KDTree
        m, _ = model()
        T = m["template_vertex_positions"]
        kd = KDTree(len(T))
        for i, p in enumerate(T):
            kd.insert(Vector(p), i)
        kd.balance()
        _MIRROR = np.array([kd.find(Vector((-p[0], p[1], p[2])))[1] for p in T])
    return _MIRROR


def symmetric(v, amount=0.8):
    """Evens out left and right (real faces are lopsided; screen faces are nearly symmetric)."""
    mi = mirror_index()
    w = v[mi] * np.array([-1.0, 1.0, 1.0])
    return v + amount * 0.5 * (w - v)


def vertices(idp, exp=None, exp_amount=1.0):
    m, _ = model()
    v = m["template_vertex_positions"] + np.tensordot(idp, m["vertex_identity_basis"], axes=(0, 0))
    if exp is not None:
        v = v + exp_amount * np.tensordot(exp, m["expression_basis"], axes=(0, 0))
    return v


def _group(name):
    m, _ = model()
    names = [str(n) for n in m["vertex_group_names"]]
    return m["vertex_groups"][names.index(name)] if name in names else None


def skin_material(tone=(0.42, 0.25, 0.16), name="GNM Skin"):
    """Skin without a scanned texture. Colour: the tone x large blotchy redness x fine mottling x faint freckles x
    the 'Paint' colour attribute (lips, blush, kajal, under-eye, painted from GNM's face regions). Light: random-
    walk skin subsurface scattering, a thin oily coat, a soft sheen for the fine facial hair. Surface: pores and
    fine creases as two bump layers; shinier on the T-zone (paint alpha)."""
    mt = bpy.data.materials.new(name)
    mt.use_nodes = True
    nt = mt.node_tree
    N, L = nt.nodes.new, nt.links.new
    p = nt.nodes["Principled BSDF"]
    attr = N("ShaderNodeAttribute")
    attr.attribute_name = "Paint"
    tc = N("ShaderNodeTexCoord")

    def noise(scale, detail=4.0, rough=0.5):
        n = N("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        L(tc.outputs["Object"], n.inputs["Vector"])
        return n

    def ramp(src, c0, c1, p0=0.0, p1=1.0):
        r = N("ShaderNodeValToRGB")
        r.color_ramp.elements[0].color = (*c0, 1)
        r.color_ramp.elements[1].color = (*c1, 1)
        r.color_ramp.elements[0].position = p0
        r.color_ramp.elements[1].position = p1
        L(src, r.inputs["Fac"])
        return r

    def mul(a, b):
        m = N("ShaderNodeMix")
        m.data_type = "RGBA"
        m.blend_type = 'MULTIPLY'
        m.inputs["Factor"].default_value = 1.0
        L(a, m.inputs[6]) if not isinstance(a, tuple) else m.inputs[6].__setattr__("default_value", (*a, 1))
        L(b, m.inputs[7])
        return m.outputs[2]

    blotch = ramp(noise(7.0, 3.0).outputs["Fac"], (1.08, 0.94, 0.93), (0.93, 1.02, 1.04), 0.3, 0.7)
    mott = ramp(noise(70.0, 6.0, 0.6).outputs["Fac"], (0.9, 0.89, 0.89), (1.05, 1.04, 1.02))
    vo = N("ShaderNodeTexVoronoi")
    vo.inputs["Scale"].default_value = 260.0
    L(tc.outputs["Object"], vo.inputs["Vector"])
    freck = ramp(vo.outputs["Distance"], (0.8, 0.76, 0.76), (1.0, 1.0, 1.0), 0.0, 0.1)
    col = mul(tuple(tone), blotch.outputs["Color"])
    col = mul(col, mott.outputs["Color"])
    col = mul(col, freck.outputs["Color"])
    fine = ramp(noise(380.0, 4.0, 0.6).outputs["Fac"], (0.93, 0.92, 0.92), (1.04, 1.03, 1.03))
    col = mul(col, fine.outputs["Color"])
    col = mul(col, attr.outputs["Color"])
    L(col, p.inputs["Base Color"])
    p.inputs["Specular IOR Level"].default_value = 0.42
    p.subsurface_method = 'RANDOM_WALK_SKIN'
    p.inputs["Subsurface Weight"].default_value = 1.0
    p.inputs["Subsurface Radius"].default_value = (1.0, 0.36, 0.2)
    p.inputs["Subsurface Scale"].default_value = 0.0032
    p.inputs["Subsurface IOR"].default_value = 1.4
    p.inputs["Coat Weight"].default_value = 0.025
    p.inputs["Coat Roughness"].default_value = 0.35
    p.inputs["Sheen Weight"].default_value = 0.12
    p.inputs["Sheen Roughness"].default_value = 0.45
    p.inputs["Sheen Tint"].default_value = (0.95, 0.85, 0.8, 1)
    rough = N("ShaderNodeMapRange")
    L(attr.outputs["Alpha"], rough.inputs["Value"])
    rough.inputs["To Min"].default_value = 0.58
    rough.inputs["To Max"].default_value = 0.47
    rn = noise(140.0, 2.0)
    rm = N("ShaderNodeMath")
    rm.operation = 'MULTIPLY_ADD'
    L(rn.outputs["Fac"], rm.inputs[0])
    rm.inputs[1].default_value = 0.14
    L(rough.outputs[0], rm.inputs[2])
    sub = N("ShaderNodeMath")
    sub.operation = 'SUBTRACT'
    L(rm.outputs[0], sub.inputs[0])
    sub.inputs[1].default_value = 0.07
    L(sub.outputs[0], p.inputs["Roughness"])
    pores = N("ShaderNodeTexVoronoi")                          # pores: small round pits ~0.7 mm apart
    pores.inputs["Scale"].default_value = 1400.0
    pores.inputs["Randomness"].default_value = 0.9
    L(tc.outputs["Object"], pores.inputs["Vector"])
    pit = ramp(pores.outputs["Distance"], (0.0, 0.0, 0.0), (1.0, 1.0, 1.0), 0.05, 0.28)
    b1 = N("ShaderNodeBump")
    b1.inputs["Strength"].default_value = 0.4
    b1.inputs["Distance"].default_value = 0.00025
    L(pit.outputs["Color"], b1.inputs["Height"])
    crease = noise(300.0, 10.0, 0.75)                          # orange-peel texture and fine lines, 1-4 mm
    b2 = N("ShaderNodeBump")
    b2.inputs["Strength"].default_value = 0.3
    b2.inputs["Distance"].default_value = 0.0003
    L(crease.outputs["Fac"], b2.inputs["Height"])
    L(b1.outputs["Normal"], b2.inputs["Normal"])
    L(b2.outputs["Normal"], p.inputs["Normal"])
    return mt


def painted(name, col, rough):
    """A plain material whose colour is multiplied by the 'Paint' attribute (sclera veins and pink corners)."""
    mt = _plain(name, col, rough)
    nt = mt.node_tree
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = "Paint"
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    m.blend_type = 'MULTIPLY'
    m.inputs["Factor"].default_value = 1.0
    m.inputs[6].default_value = (*col, 1)
    nt.links.new(a.outputs["Color"], m.inputs[7])
    nt.links.new(m.outputs[2], nt.nodes["Principled BSDF"].inputs["Base Color"])
    return mt


def iris_material(iris):
    """The iris: its colour x the 'Paint' attribute, which carries the radial fibres, a darker limbal ring and a
    lighter collarette round the pupil (painted per vertex in build_head)."""
    mt = _plain("Iris", iris, 0.35)
    nt = mt.node_tree
    p = nt.nodes["Principled BSDF"]
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = "Paint"
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    m.blend_type = 'MULTIPLY'
    m.inputs["Factor"].default_value = 1.0
    m.inputs[6].default_value = (*iris, 1)
    nt.links.new(a.outputs["Color"], m.inputs[7])
    nt.links.new(m.outputs[2], p.inputs["Base Color"])
    return mt


def _plain(name, col, rough=0.5, metal=0.0, alpha=None, transmission=0.0, ior=1.45, emission=None):
    mt = bpy.data.materials.new(name)
    mt.use_nodes = True
    p = mt.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*col, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    p.inputs["IOR"].default_value = ior
    if transmission:
        p.inputs["Transmission Weight"].default_value = transmission
    if alpha is not None:
        p.inputs["Alpha"].default_value = alpha
    return mt


def build_head(rng, female=1.0, ethnicity=None, smile=0.6, tone=(0.42, 0.25, 0.16), makeup=1.0, iris=(0.09, 0.04, 0.016),
               name="GNM head", spread=0.55, slim=1.0, big_eyes=1.0):
    """A head mesh in Blender (Z up, the face looking -Y), metres. Returns the object; its 'lm' dict holds
    landmarks (top, nose, cx, cy, eye_z, chin_z) for hair and jewellery placement."""
    m, _ = model()
    idp = pick_identity(rng, female, ethnicity, spread)
    exp = expression_params(rng, {"HAPPY": smile}) if smile > 0 else None
    v = vertices(idp)
    v = symmetric(sculpt(v, 0.6 * slim * female, big_eyes * female)) + (vertices(idp, exp, 0.8) - v)
    V = np.stack([v[:, 0], -v[:, 2], v[:, 1]], 1)               # GNM: y up, face +z → Blender: z up, face -y
    quads = m["quads"]
    quvs = m["quad_uvs"]
    me = bpy.data.meshes.new(name)
    me.from_pydata(V.tolist(), [], quads.tolist())
    me.update()
    uv = me.uv_layers.new(name="UVMap")
    loops = np.asarray(quvs).reshape(-1, 2)
    uv.data.foreach_set("uv", loops.ravel())
    for pl in me.polygons:
        pl.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    # materials by component
    comp = {}
    for g in ("scleras", "irises", "pupils", "eye_exteriors", "teeth", "gums", "tongue", "mouth_sock"):
        w = _group(g)
        if w is not None:
            comp[g] = w > 0.5
    mats = [skin_material(tone), painted("Sclera", (0.76, 0.71, 0.66), 0.08), iris_material(iris),
            _plain("Pupil", (0.005, 0.005, 0.005), 0.2), _plain("Cornea", (1, 1, 1), 0.0, transmission=1.0, ior=1.38),
            _plain("Teeth", (0.86, 0.83, 0.75), 0.25), _plain("Gums", (0.55, 0.2, 0.2), 0.4), _plain("Tongue", (0.6, 0.25, 0.25), 0.45),
            _plain("Mouth", (0.08, 0.02, 0.02), 0.8)]
    for mt in mats[1:4]:                                          # sclera, iris, pupil: a wet tear film
        p_ = mt.node_tree.nodes["Principled BSDF"]
        p_.inputs["Coat Weight"].default_value = 1.0
        p_.inputs["Coat Roughness"].default_value = 0.02
        p_.inputs["Coat IOR"].default_value = 1.376
    for mt in mats:
        me.materials.append(mt)
    order = [("scleras", 1), ("irises", 2), ("pupils", 3), ("eye_exteriors", 4), ("teeth", 5), ("gums", 6), ("tongue", 7),
             ("mouth_sock", 8)]
    idx = np.zeros(len(me.polygons), np.int32)
    for g, mi in order:
        if g in comp:
            mask = comp[g]
            in_g = mask[quads].all(axis=1)
            idx[in_g] = mi
    me.polygons.foreach_set("material_index", idx)
    # paint: rgb multiplier (lips, blush, kajal, shadows), alpha = oiliness (T-zone)
    paint = np.ones((len(V), 4), np.float32)
    paint[:, 3] = 0.0

    def tint(group, rgb, amount):
        w = _group(group)
        if w is None:
            return
        a = (np.clip(w, 0, 1) * amount)[:, None]
        paint[:, :3] = paint[:, :3] * (1 - a) + paint[:, :3] * np.array(rgb)[None, :] * a
    tint("upper_lip", (0.6, 0.4, 0.43), 0.8 * makeup + 0.3)
    tint("lower_lip", (0.66, 0.44, 0.48), 0.8 * makeup + 0.3)
    tint("left_cheek_region", (1.0, 0.82, 0.8), 0.5)
    tint("right_cheek_region", (1.0, 0.82, 0.8), 0.5)
    tint("left_infraorbital_region", (0.8, 0.73, 0.74), 0.6)       # darker under the eyes, as in Indian skin
    tint("right_infraorbital_region", (0.8, 0.73, 0.74), 0.6)
    for g in ("nose_region", "forehead_region", "chin_region"):
        w = _group(g)
        if w is not None:
            paint[:, 3] = np.maximum(paint[:, 3], np.clip(w, 0, 1) * 0.8)
    # kajal: skin vertices right at the edge of the eye opening (next to the eye exteriors), darkest at the lid line
    eyes = _group("eye_exteriors")
    sock = _group("eye_sockets")
    if eyes is not None and sock is not None and makeup > 0:
        ex = V[eyes > 0.5]
        skin_idx = np.where((sock > 0.5) & (eyes < 0.5))[0]
        if len(ex) and len(skin_idx):
            from mathutils.kdtree import KDTree
            kd = KDTree(len(ex))
            for i, p in enumerate(ex):
                kd.insert(Vector(p), i)
            kd.balance()
            for i in skin_idx:
                co, j, d = kd.find(Vector(V[i]))
                if d < 0.0035:
                    k = 0.85 * makeup * (1.0 - d / 0.0035)
                    paint[i, :3] *= (1 - k) + k * np.array([0.12, 0.1, 0.1])
    # skin zones: a redder nose, darker skin round the mouth and on the lids, pink inner eye corners, moist lips
    from mathutils.kdtree import KDTree
    tint("nose_region", (1.0, 0.86, 0.84), 0.45)
    lipm = np.zeros(len(V), bool)
    for g in ("upper_lip", "lower_lip"):
        w = _group(g)
        if w is not None:
            lipm |= w > 0.5
            paint[:, 3] = np.maximum(paint[:, 3], np.clip(w, 0, 1) * 1.0)
    skinm = (_group("skin") > 0.5) & ~lipm
    if lipm.any():
        kdl = KDTree(int(lipm.sum()))
        for i, p_ in enumerate(V[lipm]):
            kdl.insert(Vector(p_), i)
        kdl.balance()
        for i in np.where(skinm)[0]:
            d = kdl.find(Vector(V[i]))[2]
            if d < 0.014:
                k = 0.22 * (1 - _smooth((d - 0.002) / 0.012))
                paint[i, :3] *= (1 - k) + k * np.array([0.78, 0.72, 0.72])
    E_all = _group("eyes")
    if E_all is not None:
        cx0 = np.median(V[:, 0])
        for sx in (1, -1):
            e = V[E_all > 0.5]
            e = e[(e[:, 0] - cx0) * sx > 0]
            c = e.mean(axis=0)
            d = V - c
            lid = skinm & (d[:, 2] > 0.003) & (d[:, 2] < 0.016) & (np.abs(d[:, 0]) < 0.018) & (d[:, 1] < 0.0)
            k = (0.3 * (1 - _smooth(np.abs(d[:, 0]) / 0.018)))[lid]
            paint[lid, :3] *= (1 - k)[:, None] + k[:, None] * np.array([0.72, 0.62, 0.6])[None, :]
            inner = skinm & (np.abs(V[:, 0] - (c[0] - sx * 0.016)) < 0.004) & (np.abs(d[:, 2]) < 0.004) & (d[:, 1] < 0)
            paint[inner, :3] *= np.array([1.0, 0.8, 0.8])
            scl = _group("scleras")
            if scl is not None:
                si = np.where((scl > 0.5) & ((V[:, 0] - cx0) * sx > 0))[0]
                r = np.hypot(V[si, 0] - c[0], V[si, 2] - c[2])
                kk = _smooth((r - 0.006) / 0.008)[:, None]
                paint[si, :3] = (1 - kk) + kk * np.array([1.0, 0.86, 0.82])[None, :]
    # irises: radial fibres, a dark limbal ring at the edge, a lighter, warmer collarette near the pupil
    irw = _group("irises")
    if irw is not None:
        ii = np.where(irw > 0.5)[0]
        cx0 = np.median(V[:, 0])
        for sx in (1, -1):
            side = ii[(V[ii, 0] - cx0) * sx > 0]
            if not len(side):
                continue
            c = V[side].mean(axis=0)
            d = V[side] - c
            r = np.hypot(d[:, 0], d[:, 2])
            r = r / max(r.max(), 1e-6)
            ang = np.arctan2(d[:, 2], d[:, 0])
            fib = 0.82 + 0.18 * np.sin(ang * 47 + rng.uniform(0, 6)) * np.sin(ang * 13 + 1.0)
            ring = 1.0 - 0.6 * _smooth((r - 0.78) / 0.2)
            coll = 1.0 + 0.7 * (1 - _smooth((r - 0.25) / 0.25))
            k = (fib * ring * coll)[:, None]
            paint[side, :3] = np.clip(k * np.array([1.0, 0.95, 0.85])[None, :], 0, 2)
    att = me.color_attributes.new("Paint", 'FLOAT_COLOR', 'POINT')
    att.data.foreach_set("color", paint.ravel())
    # landmarks
    skin = _group("skin")
    S = V[skin > 0.5] if skin is not None else V
    top = float(S[:, 2].max())
    face = S[S[:, 2] > top - 0.27]
    nose_i = int(np.argmin(face[:, 1]))
    nose = Vector(face[nose_i])
    eyes_v = V[_group("eyes") > 0.5] if _group("eyes") is not None else None
    eye_z = float(eyes_v[:, 2].mean()) if eyes_v is not None else nose.z + 0.035
    ob["lm"] = {"top": top, "nose": tuple(nose), "cx": float(face[:, 0].mean()), "cy": float(face[:, 1].mean()),
                "eye_z": eye_z, "chin_z": nose.z - 0.075}
    return ob


def lm_of(ob):
    d = dict(ob["lm"])
    d["nose"] = Vector(d["nose"])
    d["shoulder_z"] = d["top"] - 0.3
    d["shoulder_w"] = 0.4
    return d


def _strands(name, roots, length, segs, radius, melanin, rng, shape):
    """Hair curves: shape(root, normal, t) → the direction at fraction t along the strand."""
    from quality import _hair_material
    curves = bpy.data.hair_curves.new(name)
    curves.add_curves([segs] * len(roots))
    P = curves.points
    k = 0
    for root, n in roots:
        L = length * rng.uniform(0.8, 1.15)
        q = root.copy()
        for s_ in range(segs):
            t = s_ / (segs - 1)
            P[k].position = q
            P[k].radius = radius * (1.0 - 0.75 * t)
            q = q + shape(root, n, t) * (L / (segs - 1))
            k += 1
    ob = bpy.data.objects.new(name, curves)
    bpy.context.scene.collection.objects.link(ob)
    curves.materials.append(_hair_material(name, melanin))
    return ob


def peach_fuzz(head, rng, count=40000):
    """Vellus hair: tiny, pale, fine hairs over the face and neck that catch the rim light."""
    me = head.data
    V = np.array([v.co for v in me.vertices])
    N_ = np.array([v.normal for v in me.vertices])
    sk = _group("skin") > 0.5
    for g in ("upper_lip", "lower_lip", "eye_sockets", "eyes", "eye_exteriors"):
        w = _group(g)
        if w is not None:
            sk &= w < 0.5
    cand = np.where(sk & (N_[:, 1] < 0.3))[0]                       # the front and sides, not inside or behind
    tris = [(pl.vertices[0], pl.vertices[1], pl.vertices[2]) for pl in me.polygons if all(sk[i] for i in pl.vertices[:3])]
    tris = np.array(tris)
    roots = []
    for _ in range(count):
        a, b, c = tris[rng.integers(len(tris))]
        u, v = rng.random(), rng.random()
        if u + v > 1:
            u, v = 1 - u, 1 - v
        p = V[a] + (V[b] - V[a]) * u + (V[c] - V[a]) * v
        n = Vector(N_[a] + N_[b] + N_[c]).normalized()
        roots.append((Vector(p) + n * 0.00005, n))
    import random as _r
    pr = _r.Random(int(rng.integers(1 << 30)))

    def flow(r, n, t):
        d = Vector((0, 0, -1.0)) + Vector((pr.uniform(-0.6, 0.6), 0, 0))
        d = d - n * d.dot(n)
        return (d.normalized() + n * 0.6).normalized()
    ob = _strands("Peach fuzz", roots, 0.0018, 3, 0.000007, 0.15, pr, flow)
    return ob


def brows_and_lashes(head, rng, female=True, melanin=1.0):
    """Eyebrows (short strands lying on the brow, growing outward and up) and upper lashes (curving out and up
    from the lid line) on a GNM head."""
    me = head.data
    V = np.array([v.co for v in me.vertices])
    out = []
    lm = lm_of(head)
    cx = lm["cx"]
    from mathutils.bvhtree import BVHTree
    bvh = BVHTree.FromPolygons([tuple(v) for v in V], [tuple(pl.vertices) for pl in me.polygons
                                                       if pl.material_index == 0])
    for side_name, sx in (("left_brow_region", 1), ("right_brow_region", -1)):
        w = _group(side_name)
        if w is None:
            continue
        idx = np.where(w > 0.6)[0]
        if not len(idx):
            continue
        B = V[idx]
        zlo, zhi = np.percentile(B[:, 2], 5), np.percentile(B[:, 2], 55)     # the brow sits low on its region
        xs = B[:, 0]
        x0, x1 = (xs.min(), xs.max()) if sx > 0 else (xs.max(), xs.min())
        roots = []
        for _ in range(1100 if female else 2400):
            u = rng.uniform(0.06, 0.86)                             # along the brow, inner → outer
            x = x0 + (x1 - x0) * u
            arch = math.sin(min(1.0, u * 1.3) * math.pi) * 0.004 * (1.4 if female else 0.8) - max(0.0, u - 0.75) * 0.02
            if rng.random() < 0.6 * max(0.0, u - 0.5):               # the tail thins out
                continue
            thick = (0.0042 if female else 0.008) * (1.0 - 0.6 * u)
            z = zlo + (zhi - zlo) * 0.45 + arch + rng.gauss(0, thick * 0.35)
            hit, nrm, _, _ = bvh.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)))
            if hit is None:
                continue
            roots.append((hit + nrm * 0.0001, nrm))

        def flow(r, n, t, sx=sx):                                    # lying on the skin, outward, rising then falling
            d = Vector((sx * 0.9, 0.0, 0.35 - 0.6 * t))
            d = d - n * d.dot(n)
            return (d.normalized() + n * 0.12).normalized()
        out.append(_strands("Brow", roots, 0.008, 5, 0.000022, min(1.0, melanin * 0.95), rng, flow))
    eyes = _group("eye_exteriors")
    if eyes is not None:
        E = V[eyes > 0.5]
        for sx in (1, -1):
            e = E[(E[:, 0] - cx) * sx > 0]
            if not len(e):
                continue
            c = Vector(e.mean(axis=0))
            rx = (e[:, 0].max() - e[:, 0].min()) / 2
            rz = (e[:, 2].max() - e[:, 2].min()) / 2
            roots = []
            n_l = 110 if female else 70
            for i in range(n_l):
                a = math.pi * (0.1 + 0.8 * i / (n_l - 1))           # the upper lid arc
                p = Vector((c.x + math.cos(a) * rx * 1.02, c.y - 0.003, c.z + math.sin(a) * rz * 0.9))
                roots.append((p, Vector((0, -1, 0.3)).normalized()))
            out.append(_strands("Lashes", roots, 0.0095 if female else 0.007, 5, 0.00004, melanin, rng,
                                lambda r, n, t: Vector((0, -1.0, 0.25 + 1.2 * t)).normalized()))
            low = []
            for i in range(45 if female else 30):                   # lower lashes: sparse, short, down and out
                a_ = math.pi * (1.15 + 0.7 * i / 44)
                low.append((Vector((c.x + math.cos(a_) * rx * 1.0, c.y - 0.003, c.z + math.sin(a_) * rz * 0.95)),
                            Vector((0, -1, -0.3)).normalized()))
            out.append(_strands("Lower lashes", low, 0.0045, 4, 0.00003, melanin, rng,
                                lambda r, n, t: Vector((0, -1.0, -0.3 - 0.8 * t)).normalized()))
    return out


def place(head, scale, offset):
    """Scale the head about the origin and move it (baked into the mesh), keeping its landmarks in step."""
    me = head.data
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3) * scale + np.array(offset, np.float32)
    me.vertices.foreach_set("co", co.ravel())
    me.update()
    lm = dict(head["lm"])
    off = Vector(offset)
    lm["nose"] = tuple(Vector(lm["nose"]) * scale + off)
    for k, ax in (("top", 2), ("eye_z", 2), ("chin_z", 2), ("cx", 0), ("cy", 1)):
        lm[k] = lm[k] * scale + offset[ax]
    head["lm"] = lm


def fit_to_body(head, body_lm):
    """Size and place a GNM head on an MPFB body: the same head height above the nose tip, nose on nose."""
    lm = lm_of(head)
    s = (body_lm["top"] - body_lm["nose"].z) / (lm["top"] - lm["nose"].z)
    n = lm["nose"] * s
    place(head, s, (body_lm["nose"].x - n.x, body_lm["nose"].y - n.y, body_lm["nose"].z - n.z))
    return s


def neck_bottom(head):
    """Height of the lowest skin of the GNM neck (where the scan ends) and its radius there."""
    V = np.array([v.co for v in head.data.vertices])
    S = V[_group("skin") > 0.5]
    zb = float(S[:, 2].min())
    ring = S[S[:, 2] < zb + 0.01]
    return zb, float(np.ptp(ring[:, 0]) / 2)


def darken_scalp(head):
    """Paint the scalp (above the hairline, behind it at the back) a dark brown: gaps between strands then read
    as hair and shadow, not bare skin."""
    lm = lm_of(head)
    me = head.data
    att = me.color_attributes["Paint"]
    col = np.empty(len(me.vertices) * 4, np.float32)
    att.data.foreach_get("color", col)
    col = col.reshape(-1, 4)
    V = np.array([v.co for v in me.vertices])
    front_y = lm["nose"].y + 0.05
    back = np.clip((V[:, 1] - front_y) / 0.18, 0, 1)
    ax = np.clip(np.abs(V[:, 0] - lm["cx"]) / 0.075, 0, 1)
    line = lm["eye_z"] + 0.064 - 0.024 * ax * ax - 0.12 * back
    k = _smooth((V[:, 2] - line + 0.004) / 0.012)[:, None]
    col[:, :3] = col[:, :3] * (1 - k) + col[:, :3] * np.array([0.14, 0.11, 0.1])[None, :] * k
    att.data.foreach_set("color", col.ravel())
