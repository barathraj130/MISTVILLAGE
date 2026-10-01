"""
THE MIST VILLAGE — KOTAGIRI
Procedural architectural visualisation of a 0.35 acre boutique mountain resort
in Kotagiri, Nilgiris, Tamil Nadu.

Run inside Blender 4.2 LTS … 5.x:
    Scripting workspace → Open this file → Run Script
or headless:
    blender -b -P mist_village.py -- --save /path/MistVillage.blend

The script wipes the current file and builds everything from scratch:
survey-shaped site, terraced terrain, 3 villas, reception + café, gate,
parking, courtyard + campfire, valley deck, agricultural valley OUTSIDE the
property, layered Nilgiri ridges, mist/VFX, golden-hour lighting and a
45 s / 24 fps / 1920x1080 ten-shot camera sequence bound to timeline markers.

Coordinates: metres, +X = east (road side), +Y = north, +Z = up.
The valley and the mountains lie to the WEST (-X).

Survey reconstruction (conceptual, NOT a legal boundary):
    A → B   top edge            13.2 m
    B → C   upper/left segment  17.0 m
    C → D   left-side segment   24.8 m
    D → E   lower edge          26.0 m
    E → F   lower/right segment 20.2 m
    F → G → A  road frontage (east) — not dimensioned on the photograph,
               closed so the enclosed area is ≈ 1,416 m² (0.35 acre).
"""

import bpy, bmesh, math, random, sys
import numpy as np
from mathutils import Vector, Matrix, Euler
from mathutils.bvhtree import BVHTree

MODE = "GOLDEN"          # "GOLDEN" (golden hour) or "NIGHT"
for i, a in enumerate(sys.argv):
    if a == "--night":
        MODE = "NIGHT"

random.seed(7)
RNG = np.random.default_rng(7)
TAU = math.tau

# =============================================================================
# 0. RESET
# =============================================================================
def reset_file():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.lights,
                 bpy.data.cameras, bpy.data.node_groups, bpy.data.particles,
                 bpy.data.worlds, bpy.data.images, bpy.data.textures):
        for d in list(coll):
            try:
                coll.remove(d)
            except Exception:
                pass
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    sc = bpy.context.scene
    sc.timeline_markers.clear()
    return sc

S = reset_file()
S.name = "THE MIST VILLAGE"

def new_coll(name, parent=None, hide=False):
    c = bpy.data.collections.new(name)
    (parent or S.collection).children.link(c)
    if hide:
        c.hide_render = True
        c.hide_viewport = True
    return c

C_SITE   = new_coll("01 SITE + SURVEY")
C_TERR   = new_coll("02 TERRAIN + ROAD")
C_ARCH   = new_coll("03 ARCHITECTURE")
C_LAND   = new_coll("04 LANDSCAPE")
C_VALLEY = new_coll("05 VALLEY — OUTSIDE PROPERTY")
C_MTN    = new_coll("06 NILGIRI MOUNTAINS")
C_VFX    = new_coll("07 MIST + VFX")
C_LIGHT  = new_coll("08 LIGHTING")
C_CAM    = new_coll("09 CAMERAS")
C_ASSET  = new_coll("zz ASSET LIBRARY (instanced)", hide=True)

# =============================================================================
# 1. SMALL GEOMETRY + MATERIAL HELPERS
# =============================================================================
def link(o, coll):
    for c in o.users_collection:
        c.objects.unlink(o)
    coll.objects.link(o)
    return o

def mesh_obj(name, verts, faces, mat=None, coll=None, smooth=False, parent=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.validate(clean_customdata=False)
    me.update()
    o = bpy.data.objects.new(name, me)
    (coll or C_ARCH).objects.link(o)
    if mat is not None:
        for m in (mat if isinstance(mat, (list, tuple)) else [mat]):
            me.materials.append(m)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    if parent is not None:
        o.parent = parent
    return o

BOX_F = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]

def box_verts(x0, y0, z0, x1, y1, z1):
    return [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
            (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]

def box(name, c, s, mat, coll=None, parent=None, rz=0.0, bevel=0.0):
    """Axis box centred at c with size s (in parent space), optional rot about Z."""
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    o = mesh_obj(name, box_verts(-hx, -hy, -hz, hx, hy, hz), BOX_F, mat, coll, parent=parent)
    o.location = c
    o.rotation_euler.z = rz
    if bevel > 0:
        m = o.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = 2
        m.limit_method = "ANGLE"
    return o

def box_mm(name, lo, hi, mat, coll=None, parent=None):
    return box(name, ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2),
               (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]), mat, coll, parent)

class MeshBuilder:
    """Accumulate many boxes / prisms into ONE mesh object (keeps object count sane)."""
    def __init__(self):
        self.v, self.f, self.mi = [], [], []
    def add(self, verts, faces, mat_index=0):
        n = len(self.v)
        self.v += [tuple(v) for v in verts]
        self.f += [tuple(i + n for i in f) for f in faces]
        self.mi += [mat_index] * len(faces)
    def box(self, lo, hi, mi=0, M=None):
        vs = box_verts(*lo, *hi)
        if M is not None:
            vs = [tuple(M @ Vector(p)) for p in vs]
        self.add(vs, BOX_F, mi)
    def obox(self, c, size, rz, mi=0):
        M = Matrix.Translation(c) @ Matrix.Rotation(rz, 4, "Z")
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        self.box((-hx, -hy, -hz), (hx, hy, hz), mi, M)
    def seg(self, p0, p1, w, h, mi=0):
        """Rectangular bar between two points (w = width, h = height, centred)."""
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        L = d.length
        if L < 1e-6:
            return
        q = d.to_track_quat("X", "Z")
        M = Matrix.Translation(p0) @ q.to_matrix().to_4x4()
        self.box((0, -w / 2, -h / 2), (L, w / 2, h / 2), mi, M)
    def cyl(self, p0, p1, r, n=10, mi=0, cap=True):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        q = d.to_track_quat("Z", "Y").to_matrix()
        base = len(self.v)
        vs = []
        for k in (0, 1):
            for i in range(n):
                a = TAU * i / n
                vs.append(tuple((p0 if k == 0 else p1) + q @ Vector((r * math.cos(a), r * math.sin(a), 0))))
        fs = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
        if cap:
            fs += [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
        self.add(vs, fs, mi)
    def build(self, name, mats, coll=None, parent=None, smooth=False):
        o = mesh_obj(name, self.v, self.f, mats, coll, smooth, parent)
        for p, m in zip(o.data.polygons, self.mi):
            p.material_index = m
        return o

# ---------------------------------------------------------------- node helpers
def mat_new(name):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (900, 0)
    return m, nt, out

def N(nt, typ, inputs=None, **props):
    n = nt.nodes.new(typ)
    for k, v in props.items():
        try:
            setattr(n, k, v)
        except Exception:
            pass
    for k, v in (inputs or {}).items():
        sock = n.inputs[k] if not isinstance(k, int) else n.inputs[k]
        if hasattr(v, "is_output") or isinstance(v, bpy.types.NodeSocket):
            nt.links.new(v, sock)
        else:
            try:
                sock.default_value = v
            except Exception:
                try:
                    sock.default_value = (*v, 1.0) if len(v) == 3 else v
                except Exception:
                    pass
    return n

def L(nt, a, b):
    nt.links.new(a, b)

def rgba(c):
    return (c[0], c[1], c[2], 1.0)

def math_n(nt, op, a, b=None, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = clamp
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, bpy.types.NodeSocket):
            nt.links.new(v, n.inputs[i])
        else:
            n.inputs[i].default_value = v
    return n.outputs[0]

def ramp(nt, fac, stops, interp="LINEAR"):
    n = nt.nodes.new("ShaderNodeValToRGB")
    cr = n.color_ramp
    cr.interpolation = interp
    while len(cr.elements) > 1:
        cr.elements.remove(cr.elements[-1])
    cr.elements[0].position = stops[0][0]
    cr.elements[0].color = rgba(stops[0][1])
    for pos, col in stops[1:]:
        e = cr.elements.new(pos)
        e.color = rgba(col)
    if isinstance(fac, bpy.types.NodeSocket):
        nt.links.new(fac, n.inputs[0])
    return n.outputs[0]

def mix_rgb(nt, fac, a, b, blend="MIX"):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "RGBA"
    n.blend_type = blend
    ins = [s for s in n.inputs if s.enabled or True]
    # ShaderNodeMix sockets: 0 Factor(float) 1 Factor(vec) 2/3 A/B float 4/5 A/B vec 6/7 A/B color
    f = n.inputs[0]
    A, B = n.inputs[6], n.inputs[7]
    for s, v in ((f, fac), (A, a), (B, b)):
        if isinstance(v, bpy.types.NodeSocket):
            nt.links.new(v, s)
        else:
            s.default_value = v if s is f else rgba(v)
    return n.outputs[2]

def set_blend(m, blended=False):
    for attr, val in (("surface_render_method", "BLENDED" if blended else "DITHERED"),
                      ("blend_method", "BLEND" if blended else "HASHED")):
        try:
            setattr(m, attr, val)
        except Exception:
            pass
    try:
        m.use_transparent_shadow = True
    except Exception:
        pass

def principled(nt, color, rough=0.5, metal=0.0, **kw):
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    for name, val in (("Base Color", color), ("Roughness", rough), ("Metallic", metal)):
        if isinstance(val, bpy.types.NodeSocket):
            nt.links.new(val, p.inputs[name])
        else:
            p.inputs[name].default_value = rgba(val) if name == "Base Color" else val
    for k, v in kw.items():
        if k in p.inputs:
            if isinstance(v, bpy.types.NodeSocket):
                nt.links.new(v, p.inputs[k])
            else:
                try:
                    p.inputs[k].default_value = v
                except Exception:
                    p.inputs[k].default_value = rgba(v)
    return p

def coords(nt, kind="Object"):
    return N(nt, "ShaderNodeTexCoord").outputs[kind]

def bump(nt, height, strength=0.3, dist=0.02, normal=None):
    b = N(nt, "ShaderNodeBump", {"Strength": strength, "Distance": dist, "Height": height})
    if normal is not None:
        L(nt, normal, b.inputs["Normal"])
    return b.outputs[0]

# ---------------------------------------------------------------- haze group
HAZE = {"GOLDEN": ((0.62, 0.66, 0.76), 0.8, 11000.0),
        "NIGHT":  ((0.010, 0.014, 0.026), 1.0, 3500.0)}[MODE]

def make_haze_group():
    g = bpy.data.node_groups.new("MV_AtmosphericHaze", "ShaderNodeTree")
    g.interface.new_socket("Shader", in_out="INPUT", socket_type="NodeSocketShader")
    g.interface.new_socket("Shader", in_out="OUTPUT", socket_type="NodeSocketShader")
    gi = g.nodes.new("NodeGroupInput")
    go = g.nodes.new("NodeGroupOutput")
    cam = g.nodes.new("ShaderNodeCameraData")
    d = math_n(g, "DIVIDE", cam.outputs["View Distance"], HAZE[2])
    e = math_n(g, "EXPONENT", math_n(g, "MULTIPLY", d, -1.0))
    fac = math_n(g, "SUBTRACT", 1.0, e, clamp=True)
    fac = math_n(g, "MULTIPLY", fac, 0.93)
    em = g.nodes.new("ShaderNodeEmission")
    em.name = "HazeEmission"
    em.inputs[0].default_value = rgba(HAZE[0])
    em.inputs[1].default_value = HAZE[1]
    mix = g.nodes.new("ShaderNodeMixShader")
    g.links.new(fac, mix.inputs[0])
    g.links.new(gi.outputs[0], mix.inputs[1])
    g.links.new(em.outputs[0], mix.inputs[2])
    g.links.new(mix.outputs[0], go.inputs[0])
    return g

HAZE_G = make_haze_group()

def out_hazed(nt, out, shader_socket):
    g = nt.nodes.new("ShaderNodeGroup")
    g.node_tree = HAZE_G
    L(nt, shader_socket, g.inputs[0])
    L(nt, g.outputs[0], out.inputs["Surface"])

# =============================================================================
# 2. MATERIALS
# =============================================================================
MAT = {}

def mat_stone(name, dark, light, scale=3.2, mortar=(0.16, 0.15, 0.13), flat=1.7):
    m, nt, out = mat_new(name)
    co = coords(nt)
    mp = N(nt, "ShaderNodeMapping", {"Vector": co, "Scale": (1.0, 1.0, flat)})
    vor = N(nt, "ShaderNodeTexVoronoi", {"Vector": mp.outputs[0], "Scale": scale, "Randomness": 0.85},
            feature="DISTANCE_TO_EDGE")
    vorc = N(nt, "ShaderNodeTexVoronoi", {"Vector": mp.outputs[0], "Scale": scale, "Randomness": 0.85})
    noi = N(nt, "ShaderNodeTexNoise", {"Vector": co, "Scale": 22.0, "Detail": 8.0})
    stone_col = ramp(nt, math_n(nt, "ADD", N(nt, "ShaderNodeSeparateColor", {"Color": vorc.outputs["Color"]}).outputs[0],
                                 math_n(nt, "MULTIPLY", noi.outputs[0], 0.35)),
                     [(0.15, dark), (0.55, tuple((a + b) / 2 for a, b in zip(dark, light))), (0.95, light)])
    mortar_mask = ramp(nt, vor.outputs["Distance"], [(0.0, (1, 1, 1)), (0.045, (0, 0, 0))])
    col = mix_rgb(nt, N(nt, "ShaderNodeSeparateColor", {"Color": mortar_mask}).outputs[0], stone_col, mortar)
    h = math_n(nt, "ADD", math_n(nt, "MINIMUM", vor.outputs["Distance"], 0.08), math_n(nt, "MULTIPLY", noi.outputs[0], 0.03))
    p = principled(nt, col, 0.86)
    L(nt, bump(nt, h, 0.55, 0.05), p.inputs["Normal"])
    out_hazed(nt, out, p.outputs[0])
    return m

MAT["stone"] = mat_stone("Dark Nilgiri Stone", (0.045, 0.043, 0.042), (0.16, 0.135, 0.11), 4.6)
MAT["stone_wall"] = mat_stone("Stone Retaining Wall", (0.06, 0.055, 0.05), (0.22, 0.19, 0.155), 3.6)
MAT["stone_light"] = mat_stone("Weathered Stone Coping", (0.14, 0.13, 0.12), (0.30, 0.28, 0.25), 1.6, flat=1.0)

def mat_timber(name, c0, c1, rough=0.55, scale=(1, 16, 1), axis_scale=1.0):
    m, nt, out = mat_new(name)
    co = coords(nt)
    mp = N(nt, "ShaderNodeMapping", {"Vector": co, "Scale": (1.0 * axis_scale, 1.0, 1.0)})
    wav = N(nt, "ShaderNodeTexWave", {"Vector": mp.outputs[0], "Scale": 6.0, "Distortion": 7.0,
                                       "Detail": 4.0, "Detail Scale": 1.5}, wave_type="BANDS", bands_direction="Y")
    noi = N(nt, "ShaderNodeTexNoise", {"Vector": co, "Scale": 3.0, "Detail": 4.0})
    f = math_n(nt, "ADD", math_n(nt, "MULTIPLY", wav.outputs["Fac"], 0.6), math_n(nt, "MULTIPLY", noi.outputs[0], 0.4))
    col = ramp(nt, f, [(0.2, c0), (0.8, c1)])
    p = principled(nt, col, rough)
    L(nt, bump(nt, wav.outputs["Fac"], 0.08, 0.005), p.inputs["Normal"])
    out_hazed(nt, out, p.outputs[0])
    return m

MAT["timber"] = mat_timber("Warm Natural Timber", (0.20, 0.085, 0.035), (0.42, 0.21, 0.10), 0.5)
MAT["timber_dark"] = mat_timber("Dark Timber Deck", (0.045, 0.022, 0.012), (0.11, 0.058, 0.030), 0.42)
MAT["timber_int"] = mat_timber("Interior Oak", (0.30, 0.16, 0.08), (0.52, 0.32, 0.17), 0.45)

def simple(name, color, rough=0.5, metal=0.0, noise=0.0, noise_scale=40.0, hazed=True, **kw):
    m, nt, out = mat_new(name)
    col = color
    if noise > 0:
        n = N(nt, "ShaderNodeTexNoise", {"Vector": coords(nt), "Scale": noise_scale, "Detail": 6.0})
        col = ramp(nt, n.outputs[0], [(0.3, tuple(c * (1 - noise) for c in color)),
                                      (0.7, tuple(min(1, c * (1 + noise)) for c in color))])
    p = principled(nt, col, rough, metal, **kw)
    if noise > 0:
        L(nt, bump(nt, n.outputs[0], 0.08, 0.01), p.inputs["Normal"])
    if hazed:
        out_hazed(nt, out, p.outputs[0])
    else:
        L(nt, p.outputs[0], out.inputs["Surface"])
    return m

MAT["plaster"] = simple("Warm Mineral Plaster", (0.58, 0.47, 0.35), 0.88, noise=0.12, noise_scale=18)
MAT["plaster_int"] = simple("Interior Lime Plaster", (0.70, 0.60, 0.48), 0.9, noise=0.06, noise_scale=12)
MAT["roof"] = simple("Charcoal Standing Seam Roof", (0.030, 0.032, 0.036), 0.38, 0.65, noise=0.08, noise_scale=6)
MAT["alu"] = simple("Black Aluminium", (0.018, 0.018, 0.019), 0.32, 0.85)
MAT["metal"] = simple("Black Powder-Coat Steel", (0.012, 0.012, 0.013), 0.45, 0.6)
MAT["brass"] = simple("Aged Brass Lettering", (0.55, 0.38, 0.16), 0.3, 1.0)
MAT["concrete"] = simple("Drainage Concrete", (0.20, 0.19, 0.18), 0.85, noise=0.2)
MAT["fabric"] = simple("Linen Bedding", (0.78, 0.74, 0.66), 0.95, noise=0.05, noise_scale=200)
MAT["wool"] = simple("Charcoal Wool Throw", (0.06, 0.055, 0.05), 0.95)
MAT["cushion"] = simple("Ochre Cushion Fabric", (0.45, 0.25, 0.07), 0.95)
MAT["rug"] = simple("Handloom Rug", (0.30, 0.22, 0.15), 0.98, noise=0.25, noise_scale=90)
MAT["ceramic"] = simple("White Ceramic", (0.80, 0.79, 0.76), 0.12)
MAT["mirror"] = simple("Mirror", (0.9, 0.9, 0.9), 0.02, 1.0)
MAT["rubber"] = simple("Wheel Stop Rubber", (0.02, 0.02, 0.02), 0.8)
MAT["soil"] = simple("Red Nilgiri Soil", (0.16, 0.075, 0.04), 0.95, noise=0.3, noise_scale=12)
MAT["log"] = simple("Split Firewood", (0.12, 0.07, 0.04), 0.9, noise=0.4, noise_scale=30)
MAT["char"] = simple("Charred Wood", (0.01, 0.009, 0.008), 0.95)
MAT["bark"] = simple("Tree Bark", (0.07, 0.05, 0.035), 0.95, noise=0.5, noise_scale=25)
MAT["bark_pale"] = simple("Eucalyptus Bark", (0.36, 0.33, 0.28), 0.8, noise=0.35, noise_scale=10)
MAT["rock"] = mat_stone("Mossy Boulder", (0.05, 0.055, 0.045), (0.2, 0.2, 0.17), 1.2, flat=1.0)
MAT["tea"] = simple("Ceramic Tea Set", (0.72, 0.66, 0.55), 0.2)

def mat_paving(name, c0, c1, scale=1.6, brick=False):
    m, nt, out = mat_new(name)
    co = coords(nt)
    if brick:
        t = N(nt, "ShaderNodeTexBrick", {"Vector": co, "Scale": 1.0, "Mortar Size": 0.006,
                                         "Color1": rgba(c0), "Color2": rgba(c1), "Mortar": rgba((0.08, 0.075, 0.07)),
                                         "Brick Width": 0.4, "Row Height": 0.2}, offset=0.5)
        col, h = t.outputs["Color"], t.outputs["Fac"]
    else:
        v = N(nt, "ShaderNodeTexVoronoi", {"Vector": co, "Scale": scale, "Randomness": 0.7}, feature="DISTANCE_TO_EDGE")
        vc = N(nt, "ShaderNodeTexVoronoi", {"Vector": co, "Scale": scale, "Randomness": 0.7})
        c = ramp(nt, N(nt, "ShaderNodeSeparateColor", {"Color": vc.outputs["Color"]}).outputs[0], [(0.0, c0), (1.0, c1)])
        gap = ramp(nt, v.outputs["Distance"], [(0.0, (1, 1, 1)), (0.03, (0, 0, 0))])
        col = mix_rgb(nt, N(nt, "ShaderNodeSeparateColor", {"Color": gap}).outputs[0], c, (0.05, 0.06, 0.035))
        h = math_n(nt, "MINIMUM", v.outputs["Distance"], 0.05)
    wet = N(nt, "ShaderNodeTexNoise", {"Vector": co, "Scale": 0.35, "Detail": 3.0})
    r = ramp(nt, wet.outputs[0], [(0.45, (0.18, 0.18, 0.18)), (0.62, (0.75, 0.75, 0.75))])
    p = principled(nt, col, N(nt, "ShaderNodeSeparateColor", {"Color": r}).outputs[0])
    L(nt, bump(nt, h, 0.4, 0.02), p.inputs["Normal"])
    out_hazed(nt, out, p.outputs[0])
    return m

MAT["paving"] = mat_paving("Natural Stone Paving", (0.14, 0.13, 0.115), (0.30, 0.27, 0.23), 1.7)
MAT["pavers"] = mat_paving("Parking Pavers", (0.13, 0.12, 0.11), (0.20, 0.19, 0.17), brick=True)
MAT["flag"] = mat_paving("Flagstone Path", (0.12, 0.115, 0.10), (0.26, 0.24, 0.20), 2.3)

def mat_glass(name, tint=(0.8, 0.86, 0.88)):
    m, nt, out = mat_new(name)
    lw = N(nt, "ShaderNodeFresnel", {"IOR": 1.52})
    tr = N(nt, "ShaderNodeBsdfTransparent", {"Color": rgba(tint)})
    gl = N(nt, "ShaderNodeBsdfGlossy", {"Color": rgba((1, 1, 1)), "Roughness": 0.02})
    mix = N(nt, "ShaderNodeMixShader")
    f = math_n(nt, "ADD", math_n(nt, "MULTIPLY", lw.outputs[0], 0.85), 0.06)
    L(nt, f, mix.inputs[0]); L(nt, tr.outputs[0], mix.inputs[1]); L(nt, gl.outputs[0], mix.inputs[2])
    L(nt, mix.outputs[0], out.inputs["Surface"])
    set_blend(m, True)
    return m

MAT["glass"] = mat_glass("Architectural Glass")
MAT["shower_glass"] = mat_glass("Shower Glass", (0.9, 0.93, 0.93))

def mat_emit(name, color, strength, base=None):
    m, nt, out = mat_new(name)
    e = N(nt, "ShaderNodeEmission", {"Color": rgba(color), "Strength": strength})
    if base is not None:
        p = principled(nt, base, 0.6)
        mix = N(nt, "ShaderNodeAddShader")
        L(nt, p.outputs[0], mix.inputs[0]); L(nt, e.outputs[0], mix.inputs[1])
        L(nt, mix.outputs[0], out.inputs["Surface"])
    else:
        L(nt, e.outputs[0], out.inputs["Surface"])
    return m

K2700 = (1.0, 0.47, 0.17)          # ~2700 K in linear Rec.709
K2200 = (1.0, 0.33, 0.07)
night = MODE == "NIGHT"
MAT["lampshade"] = mat_emit("Lampshade 2700K", K2700, 14.0 if night else 7.0, base=(0.8, 0.7, 0.55))
MAT["bulb"] = mat_emit("Bulb 2700K", K2700, 60.0 if night else 30.0)
MAT["ember"] = mat_emit("Ember Glow", (1.0, 0.18, 0.02), 40.0)
MAT["title"] = mat_emit("Title Emission", (0.98, 0.93, 0.84), 1.0)

def mat_fire():
    m, nt, out = mat_new("Campfire Flame")
    co = coords(nt, "Generated")
    mp = N(nt, "ShaderNodeMapping", {"Vector": coords(nt, "Object")})
    mp.name = "FlameScroll"
    n = N(nt, "ShaderNodeTexNoise", {"Vector": mp.outputs[0], "Scale": 4.0, "Detail": 6.0, "Distortion": 1.2})
    z = N(nt, "ShaderNodeSeparateXYZ", {"Vector": co}).outputs[2]
    body = math_n(nt, "SUBTRACT", n.outputs[0], math_n(nt, "MULTIPLY", z, 0.75))
    alpha = ramp(nt, body, [(0.05, (0, 0, 0)), (0.35, (1, 1, 1))])
    col = ramp(nt, math_n(nt, "SUBTRACT", 1.0, z), [(0.0, (1.0, 0.05, 0.0)), (0.5, (1.0, 0.25, 0.02)), (1.0, (1.0, 0.65, 0.25))])
    e = N(nt, "ShaderNodeEmission", {"Color": col, "Strength": 22.0})
    tr = N(nt, "ShaderNodeBsdfTransparent")
    mix = N(nt, "ShaderNodeMixShader")
    L(nt, N(nt, "ShaderNodeSeparateColor", {"Color": alpha}).outputs[0], mix.inputs[0])
    L(nt, tr.outputs[0], mix.inputs[1]); L(nt, e.outputs[0], mix.inputs[2])
    L(nt, mix.outputs[0], out.inputs["Surface"])
    set_blend(m, True)
    # scroll the noise upward: linear keyframes + linear extrapolation
    mp.inputs["Location"].default_value = (0, 0, 0)
    mp.inputs["Location"].keyframe_insert("default_value", frame=1)
    mp.inputs["Location"].default_value = (0.3, 0.1, -18.0)
    mp.inputs["Location"].keyframe_insert("default_value", frame=1080)
    try:
        for fc in nt.animation_data.action.fcurves:
            for k in fc.keyframe_points:
                k.interpolation = "LINEAR"
    except Exception:
        pass
    return m

MAT["fire"] = mat_fire()

def mat_window_light():
    """Interior warm glow panel used behind curtains / lamps."""
    return mat_emit("Warm Interior Glow", K2700, 3.0 if night else 1.2)
MAT["glow"] = mat_window_light()

def mat_water():
    m, nt, out = mat_new("Tub Water")
    p = principled(nt, (0.05, 0.08, 0.08), 0.02, **{"Transmission Weight": 1.0, "IOR": 1.33})
    n = N(nt, "ShaderNodeTexNoise", {"Vector": coords(nt), "Scale": 6.0})
    L(nt, bump(nt, n.outputs[0], 0.05, 0.01), p.inputs["Normal"])
    L(nt, p.outputs[0], out.inputs["Surface"])
    set_blend(m, True)
    return m
MAT["water"] = mat_water()

def mat_wet_road():
    m, nt, out = mat_new("Wet Mountain Asphalt")
    co = coords(nt)
    n = N(nt, "ShaderNodeTexNoise", {"Vector": co, "Scale": 90.0, "Detail": 10.0})
    pud = N(nt, "ShaderNodeTexNoise", {"Vector": co, "Scale": 0.12, "Detail": 4.0})
    col = ramp(nt, n.outputs[0], [(0.35, (0.018, 0.018, 0.019)), (0.65, (0.05, 0.048, 0.046))])
    wet = ramp(nt, pud.outputs[0], [(0.46, (0.55, 0.55, 0.55)), (0.58, (0.06, 0.06, 0.06))])
    col = mix_rgb(nt, math_n(nt, "SUBTRACT", 1.0, N(nt, "ShaderNodeSeparateColor", {"Color": wet}).outputs[0]),
                  col, (0.008, 0.008, 0.009))
    p = principled(nt, col, N(nt, "ShaderNodeSeparateColor", {"Color": wet}).outputs[0])
    L(nt, bump(nt, n.outputs[0], 0.25, 0.004), p.inputs["Normal"])
    out_hazed(nt, out, p.outputs[0])
    return m
MAT["road"] = mat_wet_road()

# ------------------------------------------------------------- vegetation mats
def mat_leaf(name, c0, c1, trans=0.35, flower=None):
    m, nt, out = mat_new(name)
    oi = N(nt, "ShaderNodeObjectInfo")
    n = N(nt, "ShaderNodeTexNoise", {"Vector": coords(nt), "Scale": 1.5})
    f = math_n(nt, "ADD", math_n(nt, "MULTIPLY", oi.outputs["Random"], 0.6), math_n(nt, "MULTIPLY", n.outputs[0], 0.5))
    col = ramp(nt, f, [(0.15, c0), (0.9, c1)])
    if flower:
        fl = N(nt, "ShaderNodeTexVoronoi", {"Vector": coords(nt), "Scale": 9.0})
        fm = ramp(nt, fl.outputs["Distance"], [(0.0, (1, 1, 1)), (0.16, (0, 0, 0))])
        col = mix_rgb(nt, N(nt, "ShaderNodeSeparateColor", {"Color": fm}).outputs[0], col, flower)
    d = N(nt, "ShaderNodeBsdfDiffuse", {"Color": col})
    t = N(nt, "ShaderNodeBsdfTranslucent", {"Color": col})
    g = N(nt, "ShaderNodeBsdfGlossy", {"Roughness": 0.35})
    m1 = N(nt, "ShaderNodeMixShader", {0: trans})
    L(nt, d.outputs[0], m1.inputs[1]); L(nt, t.outputs[0], m1.inputs[2])
    m2 = N(nt, "ShaderNodeMixShader", {0: 0.08})
    L(nt, m1.outputs[0], m2.inputs[1]); L(nt, g.outputs[0], m2.inputs[2])
    out_hazed(nt, out, m2.outputs[0])
    return m

MAT["leaf_shola"] = mat_leaf("Shola Evergreen Leaves", (0.012, 0.035, 0.010), (0.045, 0.085, 0.022))
MAT["leaf_cypress"] = mat_leaf("Cypress Foliage", (0.008, 0.025, 0.012), (0.025, 0.05, 0.02), 0.2)
MAT["leaf_oak"] = mat_leaf("Silver Oak Leaves", (0.03, 0.05, 0.02), (0.09, 0.11, 0.05))
MAT["leaf_euc"] = mat_leaf("Eucalyptus Leaves", (0.05, 0.07, 0.05), (0.11, 0.14, 0.09))
MAT["fern"] = mat_leaf("Tree Fern + Fern Fronds", (0.02, 0.06, 0.012), (0.07, 0.14, 0.025), 0.45)
MAT["shrub"] = mat_leaf("Native Shrub", (0.02, 0.05, 0.015), (0.06, 0.10, 0.03))
MAT["grass"] = mat_leaf("Highland Grass", (0.05, 0.08, 0.02), (0.14, 0.16, 0.05), 0.4)
MAT["hydrangea"] = mat_leaf("Hydrangea", (0.02, 0.05, 0.015), (0.05, 0.09, 0.03), flower=(0.30, 0.35, 0.75))
MAT["hydrangea_p"] = mat_leaf("Hydrangea Pink", (0.02, 0.05, 0.015), (0.05, 0.09, 0.03), flower=(0.75, 0.30, 0.45))
MAT["flowers"] = mat_leaf("Wild Flowers", (0.03, 0.06, 0.02), (0.08, 0.12, 0.04), flower=(0.85, 0.62, 0.10))
MAT["hedge"] = mat_leaf("Hedgerow", (0.012, 0.035, 0.012), (0.04, 0.07, 0.022))
MAT["moss"] = simple("Moss", (0.035, 0.07, 0.015), 0.9, noise=0.4, noise_scale=15)

# =============================================================================
# 3. SURVEY BOUNDARY + TERRACE PLAN
# =============================================================================
def _step(p, L_, ang):
    a = math.radians(ang)
    return (p[0] + L_ * math.cos(a), p[1] + L_ * math.sin(a))

_A = (0.0, 0.0); _B = (-13.2, 0.0)
_C = _step(_B, 17.0, 234.88); _D = _step(_C, 24.8, 276.45)
_E = _step(_D, 26.0, -6.10);  _F = _step(_E, 20.2, 41.84)
_G = (23.47, -17.41)
OFF = (-1.0, 20.0)
BOUNDARY = [(p[0] + OFF[0], p[1] + OFF[1]) for p in (_A, _B, _C, _D, _E, _F, _G)]
BNAMES = "ABCDEFG"
BP = np.array(BOUNDARY)

def poly_area(P):
    return 0.5 * abs(sum(P[i][0] * P[(i + 1) % len(P)][1] - P[(i + 1) % len(P)][0] * P[i][1] for i in range(len(P))))

SITE_AREA = poly_area(BOUNDARY)
print(f"[MistVillage] survey polygon area = {SITE_AREA:.0f} m² = {SITE_AREA*10.7639:.0f} sq.ft = {SITE_AREA/4046.86:.3f} acre")

def inside_poly(x, y, P=BP):
    x = np.asarray(x, float); y = np.asarray(y, float)
    ins = np.zeros(x.shape, bool)
    n = len(P)
    for i in range(n):
        x0, y0 = P[i]; x1, y1 = P[(i + 1) % n]
        cond = ((y0 > y) != (y1 > y))
        xint = (x1 - x0) * (y - y0) / ((y1 - y0) + 1e-12) + x0
        ins ^= cond & (x < xint)
    return ins

def seg_dist(x, y, a, b):
    ax, ay = a; bx, by = b
    dx, dy = bx - ax, by - ay
    t = np.clip(((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy), 0, 1)
    px, py = ax + t * dx, ay + t * dy
    return np.hypot(x - px, y - py), px, py

def poly_dist(x, y, P=BOUNDARY, closed=True):
    x = np.asarray(x, float); y = np.asarray(y, float)
    best = np.full(x.shape, 1e18); bx = np.zeros(x.shape); by = np.zeros(x.shape); bt = np.zeros(x.shape)
    n = len(P)
    acc = 0.0
    for i in range(n if closed else n - 1):
        a, b = P[i], P[(i + 1) % n]
        d, px, py = seg_dist(x, y, a, b)
        seglen = math.dist(a, b)
        tt = acc + np.hypot(px - a[0], py - a[1])
        m = d < best
        best = np.where(m, d, best); bx = np.where(m, px, bx); by = np.where(m, py, by); bt = np.where(m, tt, bt)
        acc += seglen
    return best, bx, by, bt

# Terrace bands: level boundaries as x = f(y) polylines, levels from east (road) down to west (valley)
F0 = [(-40, 9.5), (40, 9.5)]
F1 = [(-40, -2.0), (-10.0, -2.0), (-8.5, 2.5), (4.4, 2.5), (5.2, -2.5), (40, -2.5)]
F2 = [(-40, -10.5), (4.5, -10.5), (5.5, -9.0), (40, -9.0)]
LEVELS = [3.0, 2.0, 0.9, -0.3]        # L0 parking/gate · L1 reception+forest villa · L2 courtyard · L3 west villas + deck

def f_eval(F, y):
    ys = np.array([p[0] for p in F]); xs = np.array([p[1] for p in F])
    return np.interp(y, ys, xs)

def band_of(x, y):
    x = np.asarray(x, float); y = np.asarray(y, float)
    b = np.full(x.shape, 3)
    b = np.where(x >= f_eval(F2, y), 2, b)
    b = np.where(x >= f_eval(F1, y), 1, b)
    b = np.where(x >= f_eval(F0, y), 0, b)
    return b

def site_level(x, y):
    return np.array(LEVELS)[band_of(x, y)]

# =============================================================================
# 4. TERRAIN FUNCTION (numpy)
# =============================================================================
def _hash2(ix, iy, seed):
    h = (ix * 374761393 + iy * 668265263 + seed * 144269504) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0

def vnoise(x, y, seed=0):
    x = np.asarray(x, float); y = np.asarray(y, float)
    ix = np.floor(x).astype(np.int64); iy = np.floor(y).astype(np.int64)
    fx = x - ix; fy = y - iy
    ux = fx * fx * (3 - 2 * fx); uy = fy * fy * (3 - 2 * fy)
    a = _hash2(ix, iy, seed); b = _hash2(ix + 1, iy, seed)
    c = _hash2(ix, iy + 1, seed); d = _hash2(ix + 1, iy + 1, seed)
    return (a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy) * 2 - 1

def fbm(x, y, octaves=6, seed=0, lac=2.03, gain=0.5):
    s = 0.0; amp = 1.0; f = 1.0; norm = 0.0
    for o in range(octaves):
        s = s + amp * vnoise(x * f, y * f, seed + o * 17)
        norm += amp; amp *= gain; f *= lac
    return s / norm

def ridged(x, y, octaves=6, seed=0):
    s = 0.0; amp = 0.5; f = 1.0
    for o in range(octaves):
        n = 1.0 - np.abs(vnoise(x * f, y * f, seed + o * 31))
        s = s + amp * n * n
        amp *= 0.5; f *= 2.05
    return s

def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

def natural_h(x, y):
    x = np.asarray(x, float); y = np.asarray(y, float)
    xm = x + 18 * np.sin(y / 160.0) + 9 * np.sin(y / 53.0 + 1.3)
    east = 0.16 * xm + 0.00011 * np.maximum(xm, 0) ** 2
    east = np.where(xm > 900, 0.16 * 900 + 0.00011 * 900 ** 2 + 0.05 * (xm - 900), east)
    west = -95.0 * (1 - np.exp(xm / 600.0))
    base = np.where(xm >= 0, east, west)
    base += 300.0 * smoothstep(-1300, -3400, xm) * (0.75 + 0.35 * fbm(y / 1400.0, x / 1400.0, 3, 5))
    # side spurs: hills closing the valley north & south
    base += 140.0 * smoothstep(900, 3000, np.abs(y)) * smoothstep(-200, -1400, xm)
    r = np.hypot(x, y)
    amp = np.clip(2.0 + r * 0.035, 2.0, 70.0)
    base += amp * fbm(x / 260.0, y / 260.0, 6, 11)
    base += 0.35 * fbm(x / 9.0, y / 9.0, 3, 23) * np.clip(r / 60.0, 0.2, 1.0)
    return base

# Road centre-line: from the south, along the east frontage, climbing out north
ROAD = [(40, -420), (46, -250), (38, -140), (31, -70), (27, -32), (24.8, -10.5), (25.9, 3.5),
        (14.5, 13.8), (1.8, 23.8), (-12, 36), (-22, 62), (-18, 100), (-4, 140), (18, 190), (44, 260), (58, 360)]
GATE = (15.6, 7.65)                    # on edge G-A
GATE_DIR = (-0.8, 0.6)                 # direction along G→A
GATE_IN = (-0.6, -0.8)                 # inward normal

def densify(P, step):
    out = []
    for i in range(len(P) - 1):
        a, b = np.array(P[i], float), np.array(P[i + 1], float)
        n = max(1, int(np.linalg.norm(b - a) / step))
        for k in range(n):
            out.append(tuple(a + (b - a) * k / n))
    out.append(tuple(P[-1]))
    return out

def catmull(P, samples=6):
    P = [np.array(p, float) for p in P]
    P = [P[0]] + P + [P[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(samples):
            t = k / samples
            out.append(tuple(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                                    + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)))
    out.append(tuple(P[-2]))
    return out

ROAD_PTS = densify(catmull(ROAD, 8), 2.0)
_rx = np.array([p[0] for p in ROAD_PTS]); _ry = np.array([p[1] for p in ROAD_PTS])
_rz = natural_h(_rx, _ry)
for _ in range(60):  # smooth road longitudinal profile
    _rz[1:-1] = 0.25 * _rz[:-2] + 0.5 * _rz[1:-1] + 0.25 * _rz[2:]
_gd = np.hypot(_rx - (GATE[0] + 3.0), _ry - (GATE[1] + 3.2))
_rz = _rz + (LEVELS[0] + 0.15 - _rz) * np.exp(-(_gd / 38.0) ** 2)
ROAD_Z = _rz
ROAD_HALF = 2.9

def road_info(x, y):
    x = np.asarray(x, float); y = np.asarray(y, float)
    best = np.full(x.shape, 1e18); zb = np.zeros(x.shape)
    for i in range(len(ROAD_PTS) - 1):
        a, b = ROAD_PTS[i], ROAD_PTS[i + 1]
        dx, dy = b[0] - a[0], b[1] - a[1]
        t = np.clip(((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy + 1e-12), 0, 1)
        d = np.hypot(x - a[0] - t * dx, y - a[1] - t * dy)
        m = d < best
        best = np.where(m, d, best)
        zb = np.where(m, ROAD_Z[i] + (ROAD_Z[i + 1] - ROAD_Z[i]) * t, zb)
    return best, zb

def terrain_h(x, y):
    x = np.asarray(x, float); y = np.asarray(y, float)
    nat = natural_h(x, y)
    ins = inside_poly(x, y)
    lvl = site_level(x, y) + 0.035 * fbm(x / 3.0, y / 3.0, 3, 41)
    # outside: graded bank toward the boundary wall, then natural ground
    d, bx, by, _ = poly_dist(x, y)
    # level just inside the nearest boundary point
    cx, cy = np.mean(BP[:, 0]), np.mean(BP[:, 1])
    vx, vy = cx - bx, cy - by
    vl = np.hypot(vx, vy) + 1e-9
    lvl_b = site_level(bx + vx / vl * 0.6, by + vy / vl * 0.6)
    w = smoothstep(0.0, 11.0, d)
    outside = (lvl_b - 0.7) * (1 - w) + nat * w
    z = np.where(ins, lvl, outside)
    # road bench
    rd, rz = road_info(x, y)
    wr = 1.0 - smoothstep(ROAD_HALF + 1.2, ROAD_HALF + 9.0, rd)
    wr = np.where(ins, 0.0, wr)
    z = z * (1 - wr) + (rz - 0.05) * wr
    return z

# ----------------------------------------------------------------- land masks
FARM_X = (-950.0, -48.0)

def farm_mask(x, y):
    x = np.asarray(x, float); y = np.asarray(y, float)
    m = smoothstep(FARM_X[1] + 6, FARM_X[1] - 14, x) * smoothstep(FARM_X[0] - 60, FARM_X[0] + 120, x)
    m *= smoothstep(1700, 1200, np.abs(y))
    groves = fbm(x / 140.0, y / 140.0, 4, 77)
    m *= smoothstep(0.30, 0.12, groves)            # forest groves / shola patches between fields
    return np.clip(m, 0, 1)

def forest_mask(x, y):
    x = np.asarray(x, float); y = np.asarray(y, float)
    f = smoothstep(-0.05, 0.25, fbm(x / 180.0, y / 180.0, 5, 91))
    f = np.maximum(f, smoothstep(0.12, 0.30, fbm(x / 140.0, y / 140.0, 4, 77)) * smoothstep(FARM_X[1], FARM_X[1] - 30, x))
    f *= 1.0 - farm_mask(x, y)
    return np.clip(f, 0, 1)

# =============================================================================
# 5. TERRAIN MESH (non-uniform grid: 0.2 m on site → ~150 m at the horizon)
# =============================================================================
def axis(dense_lo, dense_hi, step, far, ratio):
    core = list(np.arange(dense_lo, dense_hi + 1e-6, step))
    hi = []; s = step; v = dense_hi
    while v < far:
        s *= ratio; v += s; hi.append(v)
    lo = []; s = step; v = dense_lo
    while v > -far:
        s *= ratio; v -= s; lo.append(v)
    return np.array(lo[::-1] + core + hi)

def build_terrain():
    xs = axis(-29.0, 29.0, 0.2, 6500.0, 1.062)
    ys = axis(-26.0, 27.0, 0.2, 6500.0, 1.062)
    X, Y = np.meshgrid(xs, ys)
    Z = terrain_h(X.ravel(), Y.ravel()).reshape(X.shape)
    ny, nx = X.shape
    verts = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
    idx = np.arange(nx * ny).reshape(ny, nx)
    a = idx[:-1, :-1].ravel(); b = idx[:-1, 1:].ravel(); c = idx[1:, 1:].ravel(); d = idx[1:, :-1].ravel()
    me = bpy.data.meshes.new("Terrain")
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", verts.astype(np.float32).ravel())
    nf = len(a)
    me.loops.add(nf * 4)
    me.loops.foreach_set("vertex_index", np.stack([a, b, c, d], 1).astype(np.int32).ravel())
    me.polygons.add(nf)
    me.polygons.foreach_set("loop_start", (np.arange(nf) * 4).astype(np.int32))
    try:
        me.polygons.foreach_set("loop_total", np.full(nf, 4, np.int32))
    except Exception:
        pass
    me.update(calc_edges=True)
    me.polygons.foreach_set("use_smooth", np.ones(nf, bool))
    # masks → colour attribute (R farm, G site lawn, B forest)
    fx, fy = verts[:, 0], verts[:, 1]
    farm = farm_mask(fx, fy)
    forest = forest_mask(fx, fy)
    lawn = inside_poly(fx, fy).astype(float)
    ca = me.color_attributes.new("mv_mask", "FLOAT_COLOR", "POINT")
    col = np.stack([farm, lawn, forest, np.ones_like(farm)], 1).astype(np.float32)
    ca.data.foreach_set("color", col.ravel())
    o = bpy.data.objects.new("Terrain — Kotagiri hillside + valley", me)
    C_TERR.objects.link(o)
    return o, verts

# ----------------------------------------------------------------- terrain mat
def mat_terrain():
    m, nt, out = mat_new("Nilgiri Terrain")
    co = coords(nt, "Object")
    sep = N(nt, "ShaderNodeSeparateXYZ", {"Vector": co})
    x, y = sep.outputs[0], sep.outputs[1]
    attr = N(nt, "ShaderNodeAttribute", attribute_name="mv_mask")
    try:
        attr.attribute_type = "GEOMETRY"
    except Exception:
        pass
    msk = N(nt, "ShaderNodeSeparateColor", {"Color": attr.outputs["Color"]})
    farm, lawn, forest = msk.outputs[0], msk.outputs[1], msk.outputs[2]
    n1 = N(nt, "ShaderNodeTexNoise", {"Vector": co, "Scale": 0.35, "Detail": 8.0})
    n2 = N(nt, "ShaderNodeTexNoise", {"Vector": co, "Scale": 0.02, "Detail": 6.0})
    n3 = N(nt, "ShaderNodeTexNoise", {"Vector": co, "Scale": 4.0, "Detail": 4.0})
    # lawn / moss (inside property)
    lawn_c = ramp(nt, math_n(nt, "ADD", math_n(nt, "MULTIPLY", n1.outputs[0], 0.7), math_n(nt, "MULTIPLY", n3.outputs[0], 0.3)),
                  [(0.30, (0.030, 0.060, 0.014)), (0.55, (0.060, 0.095, 0.022)), (0.75, (0.085, 0.10, 0.030))])
    # natural meadow / scrub
    mead_c = ramp(nt, math_n(nt, "ADD", math_n(nt, "MULTIPLY", n2.outputs[0], 0.6), math_n(nt, "MULTIPLY", n1.outputs[0], 0.4)),
                  [(0.30, (0.035, 0.060, 0.014)), (0.5, (0.060, 0.085, 0.022)), (0.62, (0.085, 0.080, 0.035)), (0.8, (0.045, 0.070, 0.016))])
    # forest canopy seen from distance / forest floor
    fore_c = ramp(nt, n2.outputs[0], [(0.3, (0.010, 0.026, 0.010)), (0.7, (0.028, 0.050, 0.018))])
    # ---- agricultural patchwork (contour strips) -------------------------
    su = math_n(nt, "ADD", x, math_n(nt, "ADD", math_n(nt, "MULTIPLY", math_n(nt, "SINE", math_n(nt, "DIVIDE", y, 37.0)), 6.0),
                                            math_n(nt, "MULTIPLY", math_n(nt, "SINE", math_n(nt, "ADD", math_n(nt, "DIVIDE", y, 13.0), 1.0)), 3.0)))
    W = 16.0
    strip = math_n(nt, "FLOOR", math_n(nt, "DIVIDE", su, W))
    fu = math_n(nt, "FRACT", math_n(nt, "DIVIDE", su, W))
    v = math_n(nt, "ADD", y, math_n(nt, "MULTIPLY", strip, 37.3))
    Lc = 46.0
    cell = math_n(nt, "FLOOR", math_n(nt, "DIVIDE", v, Lc))
    fv = math_n(nt, "FRACT", math_n(nt, "DIVIDE", v, Lc))
    cv = N(nt, "ShaderNodeCombineXYZ", {"X": strip, "Y": cell, "Z": 0.37})
    wn = N(nt, "ShaderNodeTexWhiteNoise", {"Vector": cv.outputs[0]}, noise_dimensions="3D")
    crop = ramp(nt, wn.outputs["Value"], [
        (0.00, (0.050, 0.110, 0.070)),   # cabbage (blue-green)
        (0.22, (0.045, 0.095, 0.020)),   # potato
        (0.42, (0.080, 0.140, 0.030)),   # carrot / beans (bright)
        (0.58, (0.075, 0.045, 0.030)),   # freshly tilled red-brown soil
        (0.72, (0.070, 0.085, 0.030)),   # young crop over soil
        (0.86, (0.090, 0.085, 0.045)),   # fallow / harvested
    ], "CONSTANT")
    rows = math_n(nt, "SINE", math_n(nt, "MULTIPLY", su, TAU / 0.75))
    rows = math_n(nt, "MULTIPLY", math_n(nt, "ADD", rows, 1.0), 0.5)
    soil_rows = mix_rgb(nt, math_n(nt, "MULTIPLY", rows, 0.35), crop, (0.06, 0.038, 0.026))
    edge_u = math_n(nt, "MINIMUM", fu, math_n(nt, "SUBTRACT", 1.0, fu))
    edge_v = math_n(nt, "MINIMUM", fv, math_n(nt, "SUBTRACT", 1.0, fv))
    hedge = math_n(nt, "LESS_THAN", edge_u, 0.035)
    track = math_n(nt, "LESS_THAN", edge_v, 0.012)
    farm_c = mix_rgb(nt, track, soil_rows, (0.13, 0.085, 0.055))
    farm_c = mix_rgb(nt, hedge, farm_c, (0.015, 0.035, 0.012))
    # ---- combine ---------------------------------------------------------
    c = mix_rgb(nt, forest, mead_c, fore_c)
    c = mix_rgb(nt, farm, c, farm_c)
    c = mix_rgb(nt, lawn, c, lawn_c)
    # steep banks → red soil / rock
    geo = N(nt, "ShaderNodeNewGeometry")
    nz = N(nt, "ShaderNodeSeparateXYZ", {"Vector": geo.outputs["Normal"]}).outputs[2]
    steep = math_n(nt, "SUBTRACT", 1.0, math_n(nt, "MULTIPLY", math_n(nt, "SUBTRACT", nz, 0.55), 4.0), clamp=True)
    rockc = ramp(nt, n3.outputs[0], [(0.3, (0.07, 0.05, 0.035)), (0.7, (0.16, 0.14, 0.12))])
    c = mix_rgb(nt, math_n(nt, "MULTIPLY", steep, math_n(nt, "SUBTRACT", 1.0, lawn)), c, rockc)
    # wet patches → lower roughness
    wet = ramp(nt, n1.outputs[0], [(0.52, (0.92, 0.92, 0.92)), (0.66, (0.45, 0.45, 0.45))])
    p = principled(nt, c, N(nt, "ShaderNodeSeparateColor", {"Color": wet}).outputs[0])
    try:
        p.inputs["Specular IOR Level"].default_value = 0.35
    except Exception:
        pass
    L(nt, bump(nt, math_n(nt, "ADD", n3.outputs[0], math_n(nt, "MULTIPLY", rows, math_n(nt, "MULTIPLY", farm, 0.5))), 0.35, 0.05),
      p.inputs["Normal"])
    out_hazed(nt, out, p.outputs[0])
    return m

TERRAIN, TERR_V = build_terrain()
TERRAIN.data.materials.append(mat_terrain())

_dg = bpy.context.evaluated_depsgraph_get()
TERR_BVH = BVHTree.FromObject(TERRAIN, _dg)

def ground(x, y):
    hit = TERR_BVH.ray_cast(Vector((x, y, 5000.0)), Vector((0, 0, -1)))
    if hit[0] is not None:
        return hit[0].z
    return float(terrain_h(np.array([x]), np.array([y]))[0])

def lvl(x, y):
    return float(site_level(np.array([x]), np.array([y]))[0])

# =============================================================================
# 6. ROAD
# =============================================================================
def build_road():
    pts = [Vector((p[0], p[1], z)) for p, z in zip(ROAD_PTS, ROAD_Z)]
    verts, faces = [], []
    mb_edge = MeshBuilder()
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)])
        t.z = 0; t.normalize()
        nrm = Vector((-t.y, t.x, 0))
        for s in (-ROAD_HALF, -ROAD_HALF * 0.5, 0, ROAD_HALF * 0.5, ROAD_HALF):
            q = p + nrm * s
            verts.append((q.x, q.y, p.z + 0.06 - 0.02 * abs(s) / ROAD_HALF))
    k = 5
    for i in range(len(pts) - 1):
        for j in range(k - 1):
            faces.append((i * k + j, (i + 1) * k + j, (i + 1) * k + j + 1, i * k + j + 1))
    o = mesh_obj("Mountain road (east frontage)", verts, faces, MAT["road"], C_TERR, smooth=True)
    # stone kerb / drain channel on the hill side, painted edge dashes
    for i in range(0, len(pts) - 1):
        p, q = pts[i], pts[i + 1]
        t = (q - p); t.z = 0; t.normalize(); nrm = Vector((-t.y, t.x, 0))
        for side in (-1, 1):
            a = p + nrm * side * (ROAD_HALF + 0.12); b = q + nrm * side * (ROAD_HALF + 0.12)
            mb_edge.seg((a.x, a.y, p.z + 0.08), (b.x, b.y, q.z + 0.08), 0.22, 0.16, 0)
        if i % 3 == 0:
            a = p + t * 0.2; b = p + t * 1.6
            mb_edge.seg((a.x, a.y, p.z + 0.065), (b.x, b.y, p.z + 0.065 + (q.z - p.z) * 0.7), 0.1, 0.004, 1)
    mb_edge.build("Road kerbs + centre dashes", [MAT["stone_light"], simple("Road Paint (worn)", (0.55, 0.53, 0.48), 0.6)],
                  C_TERR)
    return o

build_road()

# =============================================================================
# 7. WALLS: survey boundary wall, terrace retaining walls, gate
# =============================================================================
def wall_along(name, pts, zbot_fn, ztop_fn, thick=0.5, mat=None, coping=True, coll=None, gaps=()):
    """Stone wall following a 2D polyline; heights per point via callables."""
    mb = MeshBuilder()
    pts = densify(pts, 0.6)
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        if any(math.dist(mid, g[0]) < g[1] for g in gaps):
            continue
        za0, zt0 = zbot_fn(*a), ztop_fn(*a)
        zb1, zt1 = zbot_fn(*b), ztop_fn(*b)
        d = Vector((b[0] - a[0], b[1] - a[1], 0))
        if d.length < 1e-4:
            continue
        d.normalize(); n = Vector((-d.y, d.x, 0)) * thick / 2
        A = Vector((a[0], a[1], 0)) - d * 0.02; B = Vector((b[0], b[1], 0)) + d * 0.02
        vs = [A - n, B - n, B + n, A + n]
        verts = [(v.x, v.y, z) for v, z in zip(vs, (za0, zb1, zb1, za0))] + \
                [(v.x, v.y, z) for v, z in zip(vs, (zt0, zt1, zt1, zt0))]
        mb.add(verts, BOX_F, 0)
        if coping:
            n2 = n * 1.2
            vs = [A - n2, B - n2, B + n2, A + n2]
            verts = [(v.x, v.y, z) for v, z in zip(vs, (zt0, zt1, zt1, zt0))] + \
                    [(v.x, v.y, z + 0.09) for v, z in zip(vs, (zt0, zt1, zt1, zt0))]
            mb.add(verts, BOX_F, 1)
    return mb.build(name, [mat or MAT["stone_wall"], MAT["stone_light"]], coll or C_SITE)

def boundary_heights(x, y):
    """(ground inside, ground outside) at a boundary point."""
    cx, cy = BP[:, 0].mean(), BP[:, 1].mean()
    v = Vector((cx - x, cy - y, 0)).normalized()
    zin = lvl(x + v.x * 0.6, y + v.y * 0.6)
    zout = ground(x - v.x * 0.7, y - v.y * 0.7)
    return zin, zout

GATE_GAP = (GATE, 3.0)

def build_boundary_wall():
    pts = BOUNDARY + [BOUNDARY[0]]
    def zb(x, y):
        zi, zo = boundary_heights(x, y)
        return min(zi, zo) - 0.35
    def zt(x, y):
        zi, zo = boundary_heights(x, y)
        return max(zi, zo) + 0.55
    w = wall_along("SURVEY BOUNDARY — dry stone wall", pts, zb, zt, 0.55, MAT["stone_wall"], gaps=[GATE_GAP])
    link(w, C_SITE)

build_boundary_wall()

def f_polyline(F):
    """Polyline of a terrace line clipped to the site polygon."""
    ys = np.linspace(-26, 26, 1041)
    xs = f_eval(F, ys)
    ins = inside_poly(xs, ys)
    # shrink 0.3 m from boundary so it butts into the boundary wall
    d, *_ = poly_dist(xs, ys)
    ok = ins & (d > 0.2)
    segs, cur = [], []
    for x, y, k in zip(xs, ys, ok):
        if k:
            cur.append((float(x), float(y)))
        elif cur:
            segs.append(cur); cur = []
    if cur:
        segs.append(cur)
    return segs

# ---------------------------------------------------------------- path network
PATHS = {
    "parking→reception": [(10.6, 5.2), (8.9, 6.4), (8.9, 9.0)],
    "reception→courtyard": [(3.0, 6.0), (1.2, 4.2), (-1.0, 3.2)],
    "courtyard→valley villa": [(-8.0, -3.2), (-10.0, -5.5), (-11.0, -8.5)],
    "courtyard→mist villa": [(-7.5, 2.2), (-8.8, 4.5), (-9.0, 7.0), (-9.3, 8.6)],
    "courtyard→valley deck": [(-9.2, -0.5), (-12.5, -0.8), (-16.0, -0.9), (-18.3, -0.9)],
    "courtyard→forest villa": [(-2.0, -5.6), (-1.0, -8.2), (0.5, -9.8), (1.8, -10.4)],
    "parking→forest villa": [(10.4, -4.4), (8.5, -6.0), (6.5, -8.5), (4.6, -10.4)],
}
PATH_W = 1.25
STEP_CROSS = []   # (point, dir, upper_z, lower_z)

def find_crossings():
    for name, pl in PATHS.items():
        pts = densify(pl, 0.05)
        prev = None
        for p in pts:
            b = lvl(*p)
            if prev is not None and abs(b - prev[1]) > 0.05:
                d = Vector((p[0] - prev[0][0], p[1] - prev[0][1], 0)).normalized()
                # direction pointing DOWNHILL
                if b > prev[1]:
                    d = -d
                STEP_CROSS.append((p, d, max(b, prev[1]), min(b, prev[1])))
            prev = (p, b)

find_crossings()

def build_terrace_walls():
    gaps = [(c[0], 0.9) for c in STEP_CROSS]
    for k, F in enumerate((F0, F1, F2)):
        for j, seg in enumerate(f_polyline(F)):
            up, lo = LEVELS[k], LEVELS[k + 1]
            wall_along(f"Retaining wall L{k}/L{k+1}.{j}", seg,
                       lambda x, y, lo=lo: lo - 0.3, lambda x, y, up=up: up + 0.08, 0.55, MAT["stone_wall"], gaps=gaps)

build_terrace_walls()

def build_steps():
    mb = MeshBuilder()
    for i, (p, d, zu, zl) in enumerate(STEP_CROSS):
        n = max(2, round((zu - zl) / 0.165))
        rise = (zu - zl) / n
        side = Vector((-d.y, d.x, 0))
        base = Vector((p[0], p[1], 0)) - d * 0.3
        for s in range(n):
            c = base + d * (s * 0.33 + 0.165)
            top = zu - rise * (s + 1) + rise
            M = Matrix.Translation((c.x, c.y, 0)) @ Matrix.Rotation(math.atan2(d.y, d.x), 4, "Z")
            mb.box((-0.18, -PATH_W / 2 - 0.05, zl - 0.2), (0.18, PATH_W / 2 + 0.05, top), 0, M)
        run = n * 0.33 + 0.3
        for sgn in (-1, 1):
            c = base + d * (run / 2) + side * sgn * (PATH_W / 2 + 0.3)
            M = Matrix.Translation((c.x, c.y, 0)) @ Matrix.Rotation(math.atan2(d.y, d.x), 4, "Z")
            mb.box((-run / 2, -0.25, zl - 0.3), (run / 2, 0.25, zu + 0.08), 1, M)
    mb.build("Stone steps + cheek walls", [MAT["stone_light"], MAT["stone_wall"]], C_SITE)

build_steps()

def build_paths():
    mb = MeshBuilder()
    for name, pl in PATHS.items():
        pts = densify(pl, 0.35)
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            # skip stretches occupied by steps
            if any(math.dist(a, c[0]) < 0.35 + 0.33 * 7 and (Vector((a[0] - c[0][0], a[1] - c[0][1], 0)).dot(c[1]) > -0.4)
                   and (Vector((a[0] - c[0][0], a[1] - c[0][1], 0)).dot(c[1]) < 0.33 * max(2, round((c[2] - c[3]) / 0.165)))
                   for c in STEP_CROSS):
                continue
            za, zb = lvl(*a) + 0.05, lvl(*b) + 0.05
            if abs(za - zb) > 0.1:
                continue
            d = Vector((b[0] - a[0], b[1] - a[1], 0)).normalized(); n = Vector((-d.y, d.x, 0)) * PATH_W / 2
            A, B = Vector((*a, 0)), Vector((*b, 0))
            vs = [A - n, B - n, B + n, A + n]
            mb.add([(v.x, v.y, za - 0.08) for v in vs[:1]] + [(vs[1].x, vs[1].y, zb - 0.08), (vs[2].x, vs[2].y, zb - 0.08), (vs[3].x, vs[3].y, za - 0.08)] +
                   [(vs[0].x, vs[0].y, za), (vs[1].x, vs[1].y, zb), (vs[2].x, vs[2].y, zb), (vs[3].x, vs[3].y, za)], BOX_F, 0)
    mb.build("Flagstone walking paths", [MAT["flag"]], C_LAND)

build_paths()

# ------------------------------------------------------------- drainage channels
def build_drains():
    mb = MeshBuilder()
    for k, F in enumerate((F0, F1, F2)):
        for seg in f_polyline(F):
            seg = densify(seg, 0.8)
            z = LEVELS[k + 1]
            for i in range(len(seg) - 1):
                a, b = seg[i], seg[i + 1]
                if any(math.dist(a, c[0]) < 1.6 for c in STEP_CROSS):
                    continue
                d = Vector((b[0] - a[0], b[1] - a[1], 0)).normalized(); n = Vector((-d.y, d.x, 0))
                off = -0.55   # on the lower (west) side of the wall
                a2 = Vector((a[0], a[1], 0)) + Vector((off, 0, 0)); b2 = Vector((b[0], b[1], 0)) + Vector((off, 0, 0))
                mb.seg((a2.x, a2.y, z + 0.005), (b2.x, b2.y, z + 0.005), 0.34, 0.03, 0)
                mb.seg((a2.x, a2.y, z - 0.01), (b2.x, b2.y, z - 0.01), 0.22, 0.03, 1)
    mb.build("Stone-lined drainage channels", [MAT["stone_light"], simple("Channel Water", (0.02, 0.025, 0.03), 0.03)], C_SITE)

build_drains()

# =============================================================================
# 8. TEXT HELPER
# =============================================================================
def text_obj(name, body, size, mat, loc, rot=(math.radians(90), 0, 0), extrude=0.008, coll=None, parent=None,
             align="CENTER", spacing=1.0):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = extrude
    cu.align_x = align
    cu.align_y = "CENTER"
    cu.space_character = spacing
    o = bpy.data.objects.new(name, cu)
    (coll or C_ARCH).objects.link(o)
    o.location = loc
    o.rotation_euler = rot
    cu.materials.append(mat)
    if parent:
        o.parent = parent
    return o

# =============================================================================
# 9. ARCHITECTURE
# =============================================================================
def frame(name, x, y, z, rz, coll):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "ARROWS"
    e.empty_display_size = 1.5
    e.location = (x, y, z)
    e.rotation_euler.z = rz
    coll.objects.link(e)
    return e

def add_point_light(name, loc, power, color=K2700, radius=0.08, parent=None, coll=None, shadow=True):
    ld = bpy.data.lights.new(name, "POINT")
    ld.energy = power
    ld.color = color
    ld.shadow_soft_size = radius
    try:
        ld.use_shadow = shadow
    except Exception:
        pass
    o = bpy.data.objects.new(name, ld)
    (coll or C_LIGHT).objects.link(o)
    o.location = loc
    if parent:
        o.parent = parent
    return o

def add_area_light(name, loc, size, power, color=K2700, parent=None, rot=(0, 0, 0), coll=None):
    ld = bpy.data.lights.new(name, "AREA")
    ld.energy = power; ld.color = color; ld.size = size
    o = bpy.data.objects.new(name, ld)
    (coll or C_LIGHT).objects.link(o)
    o.location = loc; o.rotation_euler = rot
    if parent:
        o.parent = parent
    return o

def gable_roof(mb_roof, mb_seam, mb_trim, W, D, eave_h, pitch, ov_side=0.55, ov_front=0.8, ov_back=0.45, thick=0.22):
    """Pitched roof with ridge along local Y. Returns ridge height."""
    t = math.tan(pitch)
    half = W / 2 + ov_side
    rise = (W / 2 + 0.12) * t
    ridge = eave_h + rise
    y0, y1 = -D / 2 - ov_back, D / 2 + ov_front
    for s in (-1, 1):
        # slab from ridge (x=0) to eave (x=s*half), top surface
        def zt(xa):
            return eave_h + (W / 2 + 0.12 - abs(xa)) * t + thick / math.cos(pitch)
        xe = s * half
        top = [(0, y0, ridge + thick / math.cos(pitch)), (xe, y0, zt(xe)), (xe, y1, zt(xe)), (0, y1, ridge + thick / math.cos(pitch))]
        bot = [(p[0], p[1], p[2] - thick / math.cos(pitch)) for p in top]
        mb_roof.add(bot + top, BOX_F if s > 0 else [tuple(reversed(f)) for f in BOX_F], 0)
        # standing seams every 0.45 m, running ridge → eave
        ny = int((y1 - y0) / 0.45)
        for i in range(1, ny):
            yy = y0 + i * (y1 - y0) / ny
            mb_seam.seg((0.02 * s, yy, zt(0.02) + 0.02), (xe * 0.995, yy, zt(xe) + 0.02), 0.025, 0.045, 0)
        # fascia board at eave
        mb_trim.seg((xe, y0, zt(xe) - thick / 2), (xe, y1, zt(xe) - thick / 2), 0.04, thick + 0.12, 1)
        # half-round gutter
        gz = zt(xe) - thick - 0.02
        for i in range(10):
            a0, a1 = math.pi * i / 10, math.pi * (i + 1) / 10
            r = 0.075
            p0 = (xe + s * (0.09 - r * math.cos(a0)), gz - r * math.sin(a0))
            p1 = (xe + s * (0.09 - r * math.cos(a1)), gz - r * math.sin(a1))
            mb_trim.add([(p0[0], y0, p0[1]), (p1[0], y0, p1[1]), (p1[0], y1, p1[1]), (p0[0], y1, p0[1])],
                        [(0, 1, 2, 3)], 0)
        # barge boards front/back
        for yy in (y0, y1):
            mb_trim.seg((0, yy, ridge + thick * 0.5), (xe, yy, zt(xe) - thick * 0.5), 0.05, thick + 0.14, 1)
    mb_trim.seg((0, y0, ridge + thick + 0.03), (0, y1, ridge + thick + 0.03), 0.22, 0.06, 0)   # ridge cap
    return ridge, half, y0, y1

def downpipes(mb, W, half, y_at, z_top, z_bottom, s_list=(-1, 1)):
    for s in s_list:
        gx = s * (half + 0.09)
        wx = s * (W / 2 + 0.06)
        mb.cyl((gx, y_at, z_top), (wx, y_at, z_top - 0.35), 0.04, 8, 0)
        mb.cyl((wx, y_at, z_top - 0.35), (wx, y_at, z_bottom + 0.15), 0.04, 8, 0)
        mb.cyl((wx, y_at, z_bottom + 0.15), (wx + s * 0.18, y_at, z_bottom + 0.05), 0.04, 8, 0)
        mb.box((wx + s * 0.1, y_at - 0.18, z_bottom - 0.02), (wx + s * 0.45, y_at + 0.18, z_bottom + 0.04), 1)   # gully

def glazed_gable(mb_glass, mb_frame, mb_timber, W, y, eave_h, pitch, door_bay=None, mull=1.1, transom=2.35):
    """Full-height glass gable (local, facing +Y) with black mullions and exposed timber frame."""
    t = math.tan(pitch)
    hw = W / 2 - 0.12
    def top(x):
        return eave_h + (hw - abs(x)) * t
    # glass as one pentagon (thin)
    pts = [(-hw, 0.0), (hw, 0.0), (hw, top(hw)), (0, top(0)), (-hw, top(-hw))]
    v = [(p[0], y - 0.01, p[1]) for p in pts] + [(p[0], y + 0.01, p[1]) for p in pts]
    mb_glass.add(v, [(0, 1, 2, 3, 4), (9, 8, 7, 6, 5)], 0)
    # mullions
    n = max(2, round(2 * hw / mull))
    for i in range(n + 1):
        x = -hw + i * 2 * hw / n
        mb_frame.box((x - 0.03, y - 0.06, 0), (x + 0.03, y + 0.06, top(x)), 0)
    # sill, head/transom
    mb_frame.box((-hw, y - 0.07, -0.02), (hw, y + 0.07, 0.05), 0)
    mb_frame.box((-hw, y - 0.06, transom - 0.03), (hw, y + 0.06, transom + 0.03), 0)
    # raking frame
    mb_frame.seg((-hw, y, top(-hw)), (0, y, top(0)), 0.12, 0.07, 0)
    mb_frame.seg((0, y, top(0)), (hw, y, top(hw)), 0.12, 0.07, 0)
    # sliding door: thicker frame + pull handle
    if door_bay is not None:
        x0 = -hw + door_bay * 2 * hw / n; x1 = x0 + 2 * hw / n
        mb_frame.box((x0 - 0.045, y + 0.02, 0), (x0 + 0.045, y + 0.09, transom), 0)
        mb_frame.box((x1 - 0.045, y + 0.02, 0), (x1 + 0.045, y + 0.09, transom), 0)
        mb_frame.box((x1 - 0.15, y + 0.09, 0.9), (x1 - 0.12, y + 0.12, 1.3), 0)
    # exposed glulam portal just outside the glass
    for s in (-1, 1):
        mb_timber.box((s * (W / 2) - 0.12, y + 0.02, 0), (s * (W / 2) + 0.12, y + 0.26, eave_h + 0.05), 0)
    mb_timber.seg((-W / 2 - 0.1, y + 0.14, eave_h + 0.04), (0, y + 0.14, eave_h + (W / 2 + 0.1) * t + 0.04), 0.22, 0.24, 0)
    mb_timber.seg((0, y + 0.14, eave_h + (W / 2 + 0.1) * t + 0.04), (W / 2 + 0.1, y + 0.14, eave_h + 0.04), 0.22, 0.24, 0)
    mb_timber.box((-W / 2 - 0.12, y + 0.02, eave_h - 0.1), (W / 2 + 0.12, y + 0.26, eave_h + 0.12), 0)   # tie beam

def wall_with_openings(mb, x0, x1, y, thick, h, openings, mi_wall, axis="X"):
    """Solid wall along axis between x0..x1 at coordinate y, openings=[(a,b,sill,head)]."""
    cuts = sorted(openings)
    pieces = []
    cur = x0
    for a, b, sill, head in cuts:
        pieces.append((cur, a, 0, h))
        pieces.append((a, b, 0, sill))
        pieces.append((a, b, head, h))
        cur = b
    pieces.append((cur, x1, 0, h))
    for a, b, z0, z1 in pieces:
        if b - a < 1e-3 or z1 - z0 < 1e-3:
            continue
        if axis == "X":
            mb.box((a, y - thick / 2, z0), (b, y + thick / 2, z1), mi_wall)
        else:
            mb.box((y - thick / 2, a, z0), (y + thick / 2, b, z1), mi_wall)

def window(mb_glass, mb_frame, a, b, sill, head, y, axis="X", mull=None):
    if axis == "X":
        mb_glass.box((a, y - 0.01, sill), (b, y + 0.01, head), 0)
        for xx in (a, b):
            mb_frame.box((xx - 0.035, y - 0.06, sill), (xx + 0.035, y + 0.06, head), 0)
        for zz in (sill, head):
            mb_frame.box((a, y - 0.06, zz - 0.035), (b, y + 0.06, zz + 0.035), 0)
        if mull:
            for xx in mull:
                mb_frame.box((xx - 0.025, y - 0.05, sill), (xx + 0.025, y + 0.05, head), 0)
    else:
        mb_glass.box((y - 0.01, a, sill), (y + 0.01, b, head), 0)
        for xx in (a, b):
            mb_frame.box((y - 0.06, xx - 0.035, sill), (y + 0.06, xx + 0.035, head), 0)
        for zz in (sill, head):
            mb_frame.box((y - 0.06, a, zz - 0.035), (y + 0.06, b, zz + 0.035), 0)

def railing(mb, pts, z, h=1.05, spacing=0.11):
    for i in range(len(pts) - 1):
        a, b = Vector((*pts[i], z)), Vector((*pts[i + 1], z))
        L_ = (b - a).length
        n = max(1, int(L_ / 1.2))
        for k in range(n + 1):
            p = a + (b - a) * k / n
            mb.box((p.x - 0.03, p.y - 0.03, z), (p.x + 0.03, p.y + 0.03, z + h), 0)
        mb.seg(a + Vector((0, 0, h)), b + Vector((0, 0, h)), 0.06, 0.012, 0)
        mb.seg(a + Vector((0, 0, 0.1)), b + Vector((0, 0, 0.1)), 0.04, 0.02, 0)
        nb = max(1, int(L_ / spacing))
        for k in range(1, nb):
            p = a + (b - a) * k / nb
            mb.box((p.x - 0.008, p.y - 0.008, z + 0.1), (p.x + 0.008, p.y + 0.008, z + h), 0)

def deck(mb_boards, mb_frame, x0, x1, y0, y1, z, board=0.14, gap=0.006, along="X", post_bottom=None):
    if along == "X":
        n = int((y1 - y0) / (board + gap))
        for i in range(n):
            yy = y0 + i * (board + gap)
            mb_boards.box((x0, yy, z - 0.028), (x1, yy + board, z), 0)
    else:
        n = int((x1 - x0) / (board + gap))
        for i in range(n):
            xx = x0 + i * (board + gap)
            mb_boards.box((xx, y0, z - 0.028), (xx + board, y1, z), 0)
    mb_frame.box((x0, y0, z - 0.25), (x1, y0 + 0.05, z - 0.028), 0)
    mb_frame.box((x0, y1 - 0.05, z - 0.25), (x1, y1, z - 0.028), 0)
    mb_frame.box((x0, y0, z - 0.25), (x0 + 0.05, y1, z - 0.028), 0)
    mb_frame.box((x1 - 0.05, y0, z - 0.25), (x1, y1, z - 0.028), 0)
    if post_bottom is not None:
        for xx in np.linspace(x0 + 0.1, x1 - 0.1, max(2, int((x1 - x0) / 1.8) + 1)):
            for yy in np.linspace(y0 + 0.1, y1 - 0.1, max(2, int((y1 - y0) / 1.8) + 1)):
                mb_frame.box((xx - 0.07, yy - 0.07, post_bottom - 0.3), (xx + 0.07, yy + 0.07, z - 0.25), 0)
                mb_frame.box((xx - 0.18, yy - 0.18, post_bottom - 0.4), (xx + 0.18, yy + 0.18, post_bottom + 0.05), 1)

# ---------------------------------------------------------------- furniture
def bed(mb, cx, cy, rz_front=1):
    """King bed, head at -Y, foot at +Y (local)."""
    w, l = 1.95, 2.08
    mb.box((cx - w / 2 - 0.05, cy - l / 2, 0), (cx + w / 2 + 0.05, cy + l / 2, 0.3), 0)            # timber base
    mb.box((cx - w / 2, cy - l / 2 + 0.02, 0.3), (cx + w / 2, cy + l / 2 - 0.02, 0.55), 1)          # mattress
    mb.box((cx - w / 2 - 0.02, cy - l / 2 + 0.6, 0.55), (cx + w / 2 + 0.02, cy + l / 2 - 0.01, 0.6), 1)  # duvet
    mb.box((cx - w / 2 - 0.03, cy + l / 2 - 0.6, 0.6), (cx + w / 2 + 0.03, cy + l / 2 - 0.05, 0.63), 2)  # throw
    for s in (-0.47, 0.47):
        mb.box((cx + s - 0.4, cy - l / 2 + 0.08, 0.55), (cx + s + 0.4, cy - l / 2 + 0.5, 0.72), 1)   # pillows
    mb.box((cx - w / 2 - 0.15, cy - l / 2 - 0.08, 0), (cx + w / 2 + 0.15, cy - l / 2, 1.15), 0)       # headboard
    for s in (-1, 1):
        x = cx + s * (w / 2 + 0.45)
        mb.box((x - 0.25, cy - l / 2 + 0.02, 0), (x + 0.25, cy - l / 2 + 0.45, 0.5), 0)                 # side tables

def lounge_chair(mb, cx, cy, rz, mi_frame=0, mi_cush=1):
    M = Matrix.Translation((cx, cy, 0)) @ Matrix.Rotation(rz, 4, "Z")
    mb.box((-0.35, -0.8, 0.0), (0.35, 0.8, 0.28), mi_frame, M)
    mb.box((-0.32, -0.78, 0.28), (0.32, 0.35, 0.36), mi_cush, M)
    back = Matrix.Translation((cx, cy, 0)) @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Translation((0, 0.45, 0.3)) @ Matrix.Rotation(math.radians(-38), 4, "X")
    mb.box((-0.32, 0.0, 0.0), (0.32, 0.65, 0.08), mi_cush, back)

def chair(mb, cx, cy, rz, mi=0, mi2=1):
    M = Matrix.Translation((cx, cy, 0)) @ Matrix.Rotation(rz, 4, "Z")
    for sx in (-0.2, 0.2):
        for sy in (-0.2, 0.2):
            mb.box((sx - 0.02, sy - 0.02, 0), (sx + 0.02, sy + 0.02, 0.45), mi, M)
    mb.box((-0.23, -0.23, 0.43), (0.23, 0.23, 0.48), mi, M)
    mb.box((-0.23, 0.2, 0.48), (0.23, 0.24, 0.85), mi, M)
    mb.box((-0.2, -0.2, 0.48), (0.2, 0.18, 0.52), mi2, M)

def table(mb, cx, cy, r=0.4, h=0.74, mi=0, square=False):
    if square:
        mb.box((cx - r, cy - r, h - 0.04), (cx + r, cy + r, h), mi)
    else:
        mb.cyl((cx, cy, h - 0.04), (cx, cy, h), r, 20, mi)
    mb.cyl((cx, cy, 0), (cx, cy, h - 0.04), 0.04, 8, mi)
    mb.cyl((cx, cy, 0), (cx, cy, 0.03), 0.22, 12, mi)

def lamp(mb_shade, x, y, z, parent, r=0.14, h=0.24, power=18.0, name="lamp"):
    mb_shade.cyl((x, y, z), (x, y, z + h), r, 16, 0)
    add_point_light(name, (x, y, z + h * 0.5), power, K2700, 0.06, parent)

# ---------------------------------------------------------------- VILLA
VILLA_W, VILLA_D, EAVE, PITCH = 5.6, 6.0, 2.75, math.radians(32)

def villa(name, cx, cy, rz, variant):
    zg = lvl(cx, cy)
    FFL = zg + 0.45
    root = frame(name, cx, cy, FFL, rz, C_ARCH)
    W, D = VILLA_W, VILLA_D
    th = 0.25
    stone_walls = variant == "forest"
    wall_mat = MAT["stone"] if stone_walls else MAT["plaster"]
    shell = MeshBuilder()      # 0 wall  1 stone  2 int plaster
    glass = MeshBuilder()
    alu = MeshBuilder()
    tim = MeshBuilder()
    roof = MeshBuilder(); seam = MeshBuilder(); trim = MeshBuilder()
    # --- plinth: stone base, 0.45 m above grade, founded 1.2 m below
    shell.box((-W / 2 - 0.15, -D / 2 - 0.15, -1.6), (W / 2 + 0.15, D / 2 + 0.02, 0.0), 1)
    # --- floor
    tim.box((-W / 2 + th, -D / 2 + th, 0.0), (W / 2 - th, D / 2, 0.025), 1)
    # --- back wall (stone for all: rear retaining feel) with small bathroom window
    wall_with_openings(shell, -W / 2, W / 2, -D / 2 + th / 2, th, EAVE, [(1.2, 2.0, 1.55, 2.25)], 1)
    window(glass, alu, 1.2, 2.0, 1.55, 2.25, -D / 2 + th / 2)
    # back gable triangle
    t = math.tan(PITCH)
    hw = W / 2
    shell.add([(-hw, -D / 2, EAVE), (hw, -D / 2, EAVE), (0, -D / 2, EAVE + hw * t),
               (-hw, -D / 2 + th, EAVE), (hw, -D / 2 + th, EAVE), (0, -D / 2 + th, EAVE + hw * t)],
              [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)], 0 if not stone_walls else 1)
    # --- side walls  (local x = ±W/2), openings: entry door on +x side, tall window on -x side
    side_open_minus = [(0.4, 2.3, 0.45, 2.35)] if variant != "valley" else [(0.3, D / 2 - 0.05, 0.0, 2.35)]
    side_open_plus = [(-1.6, -0.6, 0.0, 2.2), (0.9, 2.3, 0.45, 2.35)]
    wall_with_openings(shell, -D / 2, D / 2, -W / 2 + th / 2, th, EAVE, side_open_minus, 0 if not stone_walls else 1, axis="Y")
    wall_with_openings(shell, -D / 2, D / 2, W / 2 - th / 2, th, EAVE, side_open_plus, 0 if not stone_walls else 1, axis="Y")
    for a, b, s, h in side_open_minus:
        window(glass, alu, a, b, s, h, -W / 2 + th / 2, axis="Y")
    window(glass, alu, 0.9, 2.3, 0.45, 2.35, W / 2 - th / 2, axis="Y")
    # stone skirt on plastered walls (0.9 m high)
    if not stone_walls:
        shell.box((-W / 2 - 0.02, -D / 2 - 0.02, 0.0), (-W / 2 + 0.03, D / 2 - 0.3, 0.6), 1)
        shell.box((W / 2 - 0.03, -D / 2 - 0.02, 0.0), (W / 2 + 0.02, -1.62, 0.6), 1)
        shell.box((W / 2 - 0.03, -0.58, 0.0), (W / 2 + 0.02, D / 2 - 0.3, 0.6), 1)
    # entry door (timber) on +x side
    tim.box((W / 2 - 0.08, -1.58, 0.0), (W / 2 - 0.02, -0.62, 2.18), 0)
    alu.box((W / 2 - 0.01, -0.8, 0.95), (W / 2 + 0.03, -0.77, 1.35), 0)
    # entry canopy + landing
    tim.box((W / 2 + 0.0, -1.9, 2.35), (W / 2 + 1.1, -0.3, 2.45), 0)
    shell.box((W / 2 + 0.15, -1.9, -0.6), (W / 2 + 1.2, -0.3, -0.02), 1)
    # --- front glazed gable
    glazed_gable(glass, alu, tim, W, D / 2 - 0.05, EAVE, PITCH, door_bay=1)
    # --- interior finishes: ceiling lining following roof, partition to bathroom
    for s in (-1, 1):
        tim.add([(0, -D / 2 + th, EAVE + (W / 2 - th) * t), (s * (W / 2 - th), -D / 2 + th, EAVE),
                 (s * (W / 2 - th), D / 2 - 0.1, EAVE), (0, D / 2 - 0.1, EAVE + (W / 2 - th) * t)],
                [(0, 1, 2, 3)], 1)
    part_y = -D / 2 + 1.75
    shell.box((-W / 2 + th, part_y - 0.06, 0), (0.9, part_y + 0.06, 2.4), 2)
    # --- roof
    ridge, half, y0, y1 = gable_roof(roof, seam, trim, W, D, EAVE, PITCH)
    downpipes(alu, W, half, -D / 2 + 0.2, EAVE - 0.1, -0.45)
    # --- furniture
    furn = MeshBuilder()      # 0 timber 1 linen 2 wool 3 rug 4 ceramic 5 cushion
    bed(furn, -0.35, part_y + 0.08 + 1.04)
    furn.box((-1.7, part_y + 0.3, 0.026), (1.2, part_y + 3.3, 0.035), 3)
    lounge_chair(furn, 1.75, D / 2 - 1.1, math.radians(200), 0, 5)
    # bathroom: vanity + basin + mirror + rain shower glass
    furn.box((-W / 2 + th + 0.05, -D / 2 + th + 0.05, 0.0), (-W / 2 + th + 1.3, -D / 2 + th + 0.6, 0.82), 0)
    furn.cyl((-W / 2 + th + 0.68, -D / 2 + th + 0.35, 0.82), (-W / 2 + th + 0.68, -D / 2 + th + 0.35, 0.95), 0.2, 16, 4)
    furn.box((W / 2 - th - 1.1, -D / 2 + th, 0.0), (W / 2 - th, -D / 2 + th + 1.1, 0.04), 4)
    glass.box((W / 2 - th - 1.12, -D / 2 + th, 0.04), (W / 2 - th - 1.1, -D / 2 + th + 1.1, 2.1), 0)
    furn_o = furn.build(name + " · furniture", [MAT["timber_int"], MAT["fabric"], MAT["wool"], MAT["rug"], MAT["ceramic"], MAT["cushion"]],
                        C_ARCH, root)
    mirror = box(name + " · mirror", (-W / 2 + th + 0.68, -D / 2 + th + 0.02, 1.55), (0.8, 0.01, 0.9), MAT["mirror"], C_ARCH, root)
    shades = MeshBuilder()
    lamp(shades, -0.35 - 1.42, part_y + 0.3, 0.5, root, name=name + " bedside L")
    lamp(shades, -0.35 + 1.42, part_y + 0.3, 0.5, root, name=name + " bedside R")
    # pendant
    shades.cyl((0.9, 1.2, 2.55), (0.9, 1.2, 2.8), 0.18, 16, 0)
    add_point_light(name + " pendant", (0.9, 1.2, 2.6), 22.0 if not night else 45.0, K2700, 0.05, root)
    shades.build(name + " · lamps", [MAT["lampshade"]], C_ARCH, root)
    add_area_light(name + " ceiling wash", (0, 0.6, EAVE + 0.8), 2.0, 60.0 if not night else 120.0, K2700, root)
    # deck (front, +Y)
    dk_b = MeshBuilder(); dk_f = MeshBuilder()
    dz = -0.05
    deck(dk_b, dk_f, -W / 2 - 0.6, W / 2 + 0.6, D / 2 + 0.05, D / 2 + 2.85, dz, along="Y", post_bottom=-0.9)
    rail = MeshBuilder()
    x0, x1, y1d = -W / 2 - 0.55, W / 2 + 0.55, D / 2 + 2.8
    railing(rail, [(x0, D / 2 + 0.1), (x0, y1d), (x1 - 1.3, y1d)], dz)
    railing(rail, [(x1, y1d), (x1, D / 2 + 0.1)], dz)
    # steps down from deck opening
    for i in range(3):
        dk_f.box((x1 - 1.25, y1d + i * 0.3, dz - 0.18 * (i + 1) - 0.4), (x1 - 0.05, y1d + (i + 1) * 0.3, dz - 0.18 * (i + 1)), 1)
    dk_b.build(name + " · deck boards", [MAT["timber_dark"]], C_ARCH, root)
    dk_f.build(name + " · deck frame", [MAT["timber_dark"], MAT["stone_light"]], C_ARCH, root)
    rail.build(name + " · railing", [MAT["metal"]], C_ARCH, root)
    ext = MeshBuilder()
    if variant == "valley":
        lounge_chair(ext, -1.3, D / 2 + 1.5, math.radians(180), 0, 1)
        lounge_chair(ext, -0.3, D / 2 + 1.5, math.radians(180), 0, 1)
        table(ext, 0.55, D / 2 + 1.2, 0.25, 0.42, 0)
    if variant == "mist":
        # outdoor soaking tub (timber hoop tub)
        tx, ty = 1.4, D / 2 + 1.45
        ns = 36
        for i in range(ns):
            a0, a1 = TAU * i / ns, TAU * (i + 1) / ns
            r0, r1 = 0.72, 0.8
            v = [(tx + r0 * math.cos(a0), ty + r0 * math.sin(a0), dz), (tx + r1 * math.cos(a0), ty + r1 * math.sin(a0), dz),
                 (tx + r1 * math.cos(a1), ty + r1 * math.sin(a1), dz), (tx + r0 * math.cos(a1), ty + r0 * math.sin(a1), dz)]
            ext.add(v + [(p[0], p[1], dz + 0.72) for p in v], BOX_F, 0)
        for zz in (0.15, 0.55):
            ext.cyl((tx, ty, dz + zz), (tx, ty, dz + zz + 0.05), 0.815, 36, 2)
        wat = mesh_obj(name + " · tub water", [(tx + 0.72 * math.cos(TAU * i / 36), ty + 0.72 * math.sin(TAU * i / 36), dz + 0.6) for i in range(36)],
                       [tuple(range(36))], MAT["water"], C_ARCH, parent=root)
        lounge_chair(ext, -1.5, D / 2 + 1.5, math.radians(180), 0, 1)
        add_point_light(name + " tub glow", (tx, ty, dz + 0.9), 10.0, K2200, 0.3, root)
    if variant == "forest":
        lounge_chair(ext, -1.2, D / 2 + 1.5, math.radians(180), 0, 1)
        table(ext, -0.2, D / 2 + 1.3, 0.25, 0.42, 0)
    if ext.v:
        ext.build(name + " · deck furniture", [MAT["timber"], MAT["cushion"], MAT["metal"]], C_ARCH, root)
    # fireplace (mist villa)
    if variant == "mist":
        fp = MeshBuilder()
        fx = -W / 2 + th
        fp.box((fx, 0.2, 0.0), (fx + 0.55, 1.5, 2.2), 0)
        fp.box((fx + 0.55, 0.05, 0.0), (fx + 0.95, 1.65, 0.35), 0)
        fp_o = fp.build(name + " · stone fireplace", [MAT["stone"]], C_ARCH, root)
        fb = box(name + " · firebox glow", (fx + 0.56, 0.85, 0.65), (0.02, 0.8, 0.5), MAT["ember"], C_ARCH, root)
        add_point_light(name + " fireplace", (fx + 0.9, 0.85, 0.7), 35.0, K2200, 0.2, root)
        flue = MeshBuilder()
        flue.cyl((fx + 0.28, 0.85, 2.2), (fx + 0.28, 0.85, ridge + 1.0), 0.1, 16, 0)
        flue.cyl((fx + 0.28, 0.85, ridge + 1.0), (fx + 0.28, 0.85, ridge + 1.12), 0.2, 16, 0)
        flue.build(name + " · flue", [MAT["metal"]], C_ARCH, root)
    # build shells
    shell.build(name + " · walls + plinth", [wall_mat, MAT["stone"], MAT["plaster_int"]], C_ARCH, root)
    glass.build(name + " · glazing", [MAT["glass"]], C_ARCH, root)
    alu.build(name + " · black aluminium frames + rainwater goods", [MAT["alu"], MAT["concrete"]], C_ARCH, root)
    tim.build(name + " · exposed timber frame + lining", [MAT["timber"], MAT["timber_int"]], C_ARCH, root)
    roof.build(name + " · roof", [MAT["roof"]], C_ARCH, root)
    seam.build(name + " · standing seams", [MAT["roof"]], C_ARCH, root)
    trim.build(name + " · gutters + fascia + ridge", [MAT["alu"], MAT["timber_dark"]], C_ARCH, root)
    # porch light
    add_point_light(name + " entry light", (W / 2 + 0.6, -1.1, 2.2), 25.0 if not night else 45.0, K2700, 0.05, root)
    # external name plaque on stone plinth near path
    return root, FFL

VILLAS = {}
VILLAS["valley"] = villa("VALLEY VIEW VILLA", -14.8, -10.2, math.radians(100), "valley")
VILLAS["mist"] = villa("MIST VIEW VILLA", -12.5, 9.0, math.radians(82), "mist")
VILLAS["forest"] = villa("FOREST VIEW VILLA", 1.8, -13.5, math.radians(180), "forest")

def villa_sign(label, x, y, rz):
    z = lvl(x, y)
    root = frame(label + " sign", x, y, z, rz, C_ARCH)
    box(label + " sign · plinth", (0, 0, 0.35), (1.2, 0.3, 0.7), MAT["stone"], C_ARCH, root)
    box(label + " sign · plate", (0, -0.16, 0.45), (1.05, 0.02, 0.32), MAT["metal"], C_ARCH, root)
    text_obj(label + " sign · text", label, 0.085, MAT["brass"], (0, -0.175, 0.45), (math.radians(90), 0, 0),
             0.003, C_ARCH, root, spacing=1.15)
    add_point_light(label + " sign light", (0, -0.45, 0.1), 3.0, K2700, 0.05, root)

villa_sign("VALLEY VIEW VILLA", -11.3, -7.4, math.radians(-40))
villa_sign("MIST VIEW VILLA", -8.4, 6.6, math.radians(-10))
villa_sign("FOREST VIEW VILLA", 2.9, -9.6, math.radians(0))

# ---------------------------------------------------------------- RECEPTION + CAFÉ
def reception():
    cx, cy = 3.6, 11.1
    zg = lvl(cx, cy)
    FFL = zg + 0.3
    root = frame("RECEPTION + CAFÉ", cx, cy, FFL, math.radians(180), C_ARCH)
    # local: ridge along local X (long side 9 m), front (+Y local) faces courtyard → world south
    Wl, Dl, eave = 9.0, 5.6, 2.9
    th = 0.25
    shell = MeshBuilder(); glass = MeshBuilder(); alu = MeshBuilder(); tim = MeshBuilder()
    roof = MeshBuilder(); seam = MeshBuilder(); trim = MeshBuilder()
    shell.box((-Wl / 2 - 0.15, -Dl / 2 - 0.15, -1.2), (Wl / 2 + 0.15, Dl / 2 + 0.15, 0.0), 1)
    tim.box((-Wl / 2 + th, -Dl / 2 + th, 0), (Wl / 2 - th, Dl / 2 - th, 0.025), 1)
    # back wall (plaster, windows) along X at -Dl/2
    wall_with_openings(shell, -Wl / 2, Wl / 2, -Dl / 2 + th / 2, th, eave, [(-3.0, -1.6, 0.9, 2.3), (1.6, 3.0, 0.9, 2.3)], 0)
    window(glass, alu, -3.0, -1.6, 0.9, 2.3, -Dl / 2 + th / 2)
    window(glass, alu, 1.6, 3.0, 0.9, 2.3, -Dl / 2 + th / 2)
    # front: café glazing with mullions & door
    hw = Wl / 2 - th
    glass.box((-hw, Dl / 2 - th / 2 - 0.01, 0.0), (hw, Dl / 2 - th / 2 + 0.01, eave - 0.05), 0)
    for i in range(9):
        x = -hw + i * 2 * hw / 8
        alu.box((x - 0.035, Dl / 2 - th / 2 - 0.06, 0), (x + 0.035, Dl / 2 - th / 2 + 0.06, eave), 0)
    alu.box((-hw, Dl / 2 - th / 2 - 0.06, 2.3), (hw, Dl / 2 - th / 2 + 0.06, 2.36), 0)
    alu.box((-hw, Dl / 2 - th / 2 - 0.07, eave - 0.08), (hw, Dl / 2 - th / 2 + 0.07, eave), 0)
    # gable ends in stone (local ±X); east gable (local -X → world +X since rot 180) has entrance
    t = math.tan(math.radians(30))
    for s in (-1, 1):
        x = s * (Wl / 2 - th / 2)
        ops = [(-0.6, 0.6, 0.0, 2.3)] if s == -1 else [(-0.5, 0.5, 0.8, 2.3)]
        wall_with_openings(shell, -Dl / 2, Dl / 2, x, th, eave, ops, 1, axis="Y")
        for a, b, sl, hd in ops:
            if sl > 0:
                window(glass, alu, a, b, sl, hd, x, axis="Y")
        # gable triangles
        xa, xb = x - th / 2, x + th / 2
        shell.add([(xa, -Dl / 2, eave), (xa, Dl / 2, eave), (xa, 0, eave + Dl / 2 * t),
                   (xb, -Dl / 2, eave), (xb, Dl / 2, eave), (xb, 0, eave + Dl / 2 * t)],
                  [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)], 1)
    tim.box((-Wl / 2 - 0.02, -0.6, 0), (-Wl / 2 + 0.06, 0.6, 2.3), 0)   # entrance door leaf (glass+timber)
    # roof: ridge along X → build in rotated frame
    rroot = bpy.data.objects.new("RECEPTION roof frame", None)
    C_ARCH.objects.link(rroot); rroot.parent = root; rroot.rotation_euler.z = math.radians(90)
    ridge, half, y0, y1 = gable_roof(roof, seam, trim, Dl, Wl, eave, math.radians(30), 0.6, 0.7, 0.7)
    downpipes(alu, Wl, 0, 0, 0, 0, ())
    # entrance canopy (east, local -X)
    tim.box((-Wl / 2 - 1.6, -1.2, 2.55), (-Wl / 2, 1.2, 2.68), 0)
    for yy in (-1.1, 1.1):
        tim.box((-Wl / 2 - 1.5, yy - 0.08, 0), (-Wl / 2 - 1.34, yy + 0.08, 2.55), 0)
    # interior: reception desk + café counter + tables
    furn = MeshBuilder()
    furn.box((-3.2, -1.6, 0), (-1.2, -1.0, 1.05), 1)          # desk (stone front)
    furn.box((-3.3, -1.7, 1.05), (-1.1, -0.9, 1.1), 0)
    furn.box((1.2, -2.3, 0), (3.8, -1.7, 0.95), 0)            # café counter
    furn.box((1.1, -2.4, 0.95), (3.9, -1.6, 1.0), 1)
    for (tx, ty) in ((0.0, 0.8), (1.8, 0.9), (3.3, 0.6)):
        table(furn, tx, ty, 0.35, 0.74, 0)
        chair(furn, tx - 0.55, ty, math.radians(90), 0, 2)
        chair(furn, tx + 0.55, ty, math.radians(-90), 0, 2)
    furn.build("RECEPTION · interior", [MAT["timber_int"], MAT["stone"], MAT["cushion"]], C_ARCH, root)
    shades = MeshBuilder()
    for x in (-2.2, 0.0, 1.8, 3.3):
        shades.cyl((x, 0.6 if x > -1 else -1.3, 2.35), (x, 0.6 if x > -1 else -1.3, 2.6), 0.2, 16, 0)
        add_point_light(f"RECEPTION pendant {x}", (x, 0.6 if x > -1 else -1.3, 2.4), 30.0 if not night else 60.0, K2700, 0.05, root)
    shades.build("RECEPTION · pendants", [MAT["lampshade"]], C_ARCH, root)
    # café terrace deck toward courtyard
    dk_b = MeshBuilder(); dk_f = MeshBuilder(); rail = MeshBuilder(); ext = MeshBuilder()
    deck(dk_b, dk_f, -Wl / 2 + 0.3, Wl / 2 - 0.2, Dl / 2 + 0.05, Dl / 2 + 2.9, -0.03, along="X")
    for (tx, ty) in ((-2.6, Dl / 2 + 1.5), (0.0, Dl / 2 + 1.5), (2.6, Dl / 2 + 1.5)):
        table(ext, tx, ty, 0.35, 0.74, 0)
        chair(ext, tx - 0.55, ty, math.radians(90), 0, 1)
        chair(ext, tx + 0.55, ty, math.radians(-90), 0, 1)
    dk_b.build("CAFÉ terrace boards", [MAT["timber_dark"]], C_ARCH, root)
    dk_f.build("CAFÉ terrace frame", [MAT["timber_dark"], MAT["stone_light"]], C_ARCH, root)
    ext.build("CAFÉ terrace furniture", [MAT["timber"], MAT["cushion"]], C_ARCH, root)
    # string of warm festoon bulbs above terrace
    fest = MeshBuilder()
    for i in range(14):
        x = -Wl / 2 + 0.5 + i * (Wl - 1) / 13
        fest.cyl((x, Dl / 2 + 2.6, 2.45 - 0.12 * math.sin(math.pi * i / 13)), (x, Dl / 2 + 2.6, 2.5 - 0.12 * math.sin(math.pi * i / 13)), 0.035, 8, 0)
    fest.build("CAFÉ festoon bulbs", [MAT["bulb"]], C_ARCH, root)
    for x in (-3, 0, 3):
        add_point_light(f"CAFÉ terrace light {x}", (x, Dl / 2 + 2.3, 2.3), 18.0 if not night else 35.0, K2700, 0.3, root)
    # buildings
    shell.build("RECEPTION · walls + plinth", [MAT["plaster"], MAT["stone"]], C_ARCH, root)
    glass.build("RECEPTION · glazing", [MAT["glass"]], C_ARCH, root)
    alu.build("RECEPTION · frames", [MAT["alu"], MAT["concrete"]], C_ARCH, root)
    tim.build("RECEPTION · timber", [MAT["timber"], MAT["timber_int"]], C_ARCH, root)
    roof.build("RECEPTION · roof", [MAT["roof"]], C_ARCH, rroot)
    seam.build("RECEPTION · standing seams", [MAT["roof"]], C_ARCH, rroot)
    trim.build("RECEPTION · gutters + fascia", [MAT["alu"], MAT["timber_dark"]], C_ARCH, rroot)
    # downpipes at 4 corners (drop from gutter to gully)
    dp = MeshBuilder()
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (Wl / 2 - 0.1), sy * (Dl / 2 + 0.72)
            dp.cyl((x, y, eave - 0.05), (x, sy * (Dl / 2 + 0.06), eave - 0.4), 0.04, 8, 0)
            dp.cyl((x, sy * (Dl / 2 + 0.06), eave - 0.4), (x, sy * (Dl / 2 + 0.06), 0.1), 0.04, 8, 0)
            dp.box((x - 0.18, sy * (Dl / 2 + 0.06) - 0.18, -0.3), (x + 0.18, sy * (Dl / 2 + 0.06) + 0.18, -0.25), 1)
    dp.build("RECEPTION · downpipes", [MAT["alu"], MAT["concrete"]], C_ARCH, root)
    text_obj("RECEPTION sign", "RECEPTION  ·  CAFÉ", 0.2, MAT["brass"], (-Wl / 2 - 0.16, 0, 2.05),
             (math.radians(90), 0, math.radians(-90)), 0.01, C_ARCH, root, spacing=1.2)
    add_area_light("RECEPTION interior wash", (0, 0, eave + 0.6), 4.0, 140.0 if not night else 260.0, K2700, root)
    return root

RECEPTION = reception()

# ---------------------------------------------------------------- GATE
def gate():
    gx, gy = GATE
    z = LEVELS[0]
    rz = math.atan2(GATE_DIR[1], GATE_DIR[0])
    root = frame("STONE ENTRANCE GATE", gx, gy, z, rz, C_ARCH)
    mb = MeshBuilder()
    for s in (-1, 1):
        x = s * 2.9
        mb.box((x - 0.45, -0.45, -0.6), (x + 0.45, 0.45, 2.45), 0)
        mb.box((x - 0.55, -0.55, 2.45), (x + 0.55, 0.55, 2.6), 1)
    # timber pergola beam across opening
    tim = MeshBuilder()
    tim.box((-3.5, -0.2, 2.6), (3.5, 0.2, 2.95), 0)
    for x in np.linspace(-3.2, 3.2, 7):
        tim.box((x - 0.06, -0.55, 2.95), (x + 0.06, 0.55, 3.07), 0)
    # wing wall with name board (outside face = +y local? outward normal is (0.6,0.8) = local -Y… compute)
    mb.box((3.35, -0.3, -0.5), (7.2, 0.3, 1.6), 0)
    mb.box((3.3, -0.35, 1.6), (7.25, 0.35, 1.7), 1)
    mb.box((-7.2, -0.3, -0.5), (-3.35, 0.3, 1.2), 0)
    mb.box((-7.25, -0.35, 1.2), (-3.3, 0.35, 1.3), 1)
    mb.build("GATE · stone piers + wing walls", [MAT["stone"], MAT["stone_light"]], C_ARCH, root)
    tim.build("GATE · timber pergola", [MAT["timber"]], C_ARCH, root)
    # name board faces the road (local +Y points inward? inward normal (-0.6,-0.8); local Y after rz)
    ly = Vector((-math.sin(rz), math.cos(rz)))
    out_sign = 1 if ly.dot(Vector(GATE_IN)) < 0 else -1
    oy = out_sign * 0.32
    box("GATE · name panel", (5.28, oy, 0.95), (3.4, 0.03, 0.9), MAT["metal"], C_ARCH, root)
    rot = (math.radians(90), 0, 0 if out_sign < 0 else math.radians(180))
    text_obj("GATE · THE MIST VILLAGE", "THE MIST VILLAGE", 0.34, MAT["brass"], (5.28, oy + out_sign * 0.03, 1.1), rot, 0.012,
             C_ARCH, root, spacing=1.18)
    text_obj("GATE · KOTAGIRI", "K O T A G I R I   ·   N I L G I R I S", 0.12, MAT["brass"], (5.28, oy + out_sign * 0.03, 0.72), rot, 0.006,
             C_ARCH, root)
    for s in (-1, 1):
        box(f"GATE · wall lantern {s}", (s * 2.9, out_sign * 0.5, 2.1), (0.16, 0.12, 0.3), MAT["lampshade"], C_ARCH, root)
        add_point_light(f"GATE lantern {s}", (s * 2.9, out_sign * 0.7, 2.1), 40.0 if not night else 80.0, K2700, 0.1, root)
    add_point_light("GATE name uplight", (5.28, out_sign * 1.2, 0.05), 30.0, K2700, 0.05, root)
    # driveway apron from road to parking
    ap = MeshBuilder()
    ap.box((-2.5, -9.0 if out_sign > 0 else -1.0, -0.25), (2.5, 1.0 if out_sign > 0 else 9.0, 0.03), 0)
    ap.build("GATE · driveway apron", [MAT["pavers"]], C_ARCH, root)
    return root

GATE_OBJ = gate()

# ---------------------------------------------------------------- PARKING (4 cars)
def parking():
    z = LEVELS[0]
    mb = MeshBuilder(); st = MeshBuilder()
    x0, x1, y0, y1 = 9.7, 18.0, -5.2, 5.4
    mb.box((x0, y0, z - 0.2), (x1, y1, z + 0.04), 0)
    # bays along the east edge, 2.6 m wide, 5.0 m deep, marked by stone setts
    for i in range(5):
        y = y0 + 0.2 + i * 2.6
        st.box((13.0, y - 0.05, z + 0.04), (18.0, y + 0.05, z + 0.055), 0)
    for i in range(4):
        y = y0 + 0.2 + i * 2.6 + 1.3
        st.box((17.2, y - 0.8, z + 0.04), (17.4, y + 0.8, z + 0.16), 1)   # wheel stop
    # kerb
    st.box((x0 - 0.15, y0, z - 0.2), (x0, y1, z + 0.15), 0)
    mb.build("PARKING · 4 bays (permeable pavers)", [MAT["pavers"]], C_SITE)
    st.build("PARKING · setts + wheel stops", [MAT["stone_light"], MAT["rubber"]], C_SITE)
    # bollard lights
    bl = MeshBuilder(); bh = MeshBuilder()
    for (x, y) in ((10.2, -4.6), (10.2, 0.0), (10.2, 4.8)):
        bl.cyl((x, y, z), (x, y, z + 0.7), 0.07, 12, 0)
        bh.cyl((x, y, z + 0.55), (x, y, z + 0.66), 0.071, 12, 0)
        add_point_light(f"PARKING bollard {y}", (x, y, z + 0.6), 6.0 if not night else 12.0, K2700, 0.04)
    bl.build("PARKING · bollards", [MAT["metal"]], C_SITE)
    bh.build("PARKING · bollard lenses", [MAT["lampshade"]], C_SITE)

parking()

# ---------------------------------------------------------------- COURTYARD + CAMPFIRE
CAMPFIRE = (-3.9, -0.9)

def courtyard():
    cx, cy = CAMPFIRE
    z = LEVELS[2]
    mb = MeshBuilder()
    # circular paved hearth plaza
    n = 64
    R = 3.9
    vs = [(cx, cy, z + 0.04)] + [(cx + R * math.cos(TAU * i / n), cy + R * math.sin(TAU * i / n), z + 0.04) for i in range(n)]
    fs = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    plaza = mesh_obj("COURTYARD · stone hearth plaza", vs, fs, MAT["paving"], C_LAND)
    ring = MeshBuilder()
    # stone ring of rough blocks
    for i in range(16):
        a = TAU * i / 16
        r = 0.95
        c = (cx + r * math.cos(a), cy + r * math.sin(a), z + 0.2)
        ring.obox(c, (0.34, 0.28, 0.36 + random.uniform(-0.04, 0.05)), a + random.uniform(-0.1, 0.1), 0)
    ring.cyl((cx, cy, z + 0.03), (cx, cy, z + 0.07), 0.8, 24, 1)
    ring.build("CAMPFIRE · natural stone ring", [MAT["stone"], MAT["char"]], C_LAND)
    # logs (teepee)
    logs = MeshBuilder()
    for i in range(7):
        a = TAU * i / 7 + 0.3
        p0 = (cx + 0.5 * math.cos(a), cy + 0.5 * math.sin(a), z + 0.08)
        p1 = (cx + 0.06 * math.cos(a + 0.4), cy + 0.06 * math.sin(a + 0.4), z + 0.75)
        logs.cyl(p0, p1, 0.055, 8, 0)
    logs.build("CAMPFIRE · firewood", [MAT["log"]], C_LAND)
    # flames: several twisted cones with animated emissive shader
    for i in range(5):
        a = TAU * i / 5
        h = random.uniform(0.7, 1.05)
        r = random.uniform(0.16, 0.24)
        bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=r, radius2=0.0, depth=h,
                                        location=(cx + 0.12 * math.cos(a), cy + 0.12 * math.sin(a), z + 0.12 + h / 2))
        fl = bpy.context.object
        fl.name = f"CAMPFIRE · flame {i}"
        link(fl, C_VFX)
        fl.rotation_euler = (random.uniform(-0.12, 0.12), random.uniform(-0.12, 0.12), a)
        fl.data.materials.append(MAT["fire"])
        sub = fl.modifiers.new("sub", "SUBSURF"); sub.levels = 2; sub.render_levels = 2
        # flicker: keyframed scale wobble
        for f in range(1, 1081, 3):
            s = 1.0 + 0.18 * math.sin(f * 0.9 + i) + 0.1 * random.uniform(-1, 1)
            fl.scale = (1.0, 1.0, s)
            fl.keyframe_insert("scale", index=2, frame=f)
    # seats: 8 timber-topped stone seats
    seats = MeshBuilder()
    for i in range(8):
        a = TAU * i / 8 + math.radians(11)
        c = Vector((cx + 2.7 * math.cos(a), cy + 2.7 * math.sin(a), 0))
        M = Matrix.Translation((c.x, c.y, z)) @ Matrix.Rotation(a + math.pi / 2, 4, "Z")
        seats.box((-0.55, -0.2, 0.0), (0.55, 0.2, 0.38), 0, M)
        seats.box((-0.6, -0.24, 0.38), (0.6, 0.24, 0.46), 1, M)
    seats.build("CAMPFIRE · 8 stone + timber seats", [MAT["stone"], MAT["timber"]], C_LAND)
    cush = MeshBuilder()
    for i in (0, 2, 3, 5, 6):
        a = TAU * i / 8 + math.radians(11)
        c = Vector((cx + 2.7 * math.cos(a), cy + 2.7 * math.sin(a), 0))
        M = Matrix.Translation((c.x, c.y, z)) @ Matrix.Rotation(a + math.pi / 2, 4, "Z")
        cush.box((-0.35, -0.18, 0.46), (0.35, 0.18, 0.53), 0, M)
    cush.build("CAMPFIRE · wool cushions", [MAT["cushion"]], C_LAND)
    # low landscape lights around plaza edge
    bl = MeshBuilder(); bh = MeshBuilder()
    for i in range(6):
        a = TAU * i / 6 + 0.25
        x, y = cx + 4.3 * math.cos(a), cy + 4.3 * math.sin(a)
        bl.cyl((x, y, z), (x, y, z + 0.45), 0.055, 10, 0)
        bh.cyl((x, y, z + 0.35), (x, y, z + 0.42), 0.056, 10, 0)
        add_point_light(f"COURTYARD path light {i}", (x, y, z + 0.38), 4.0 if not night else 9.0, K2700, 0.03)
    bl.build("COURTYARD · low bollards", [MAT["metal"]], C_LAND)
    bh.build("COURTYARD · bollard lenses", [MAT["lampshade"]], C_LAND)
    # fire light with flicker
    fire_l = add_point_light("CAMPFIRE flicker light", (cx, cy, z + 0.75), 420.0 if night else 260.0, K2200, 0.35)
    base = fire_l.data.energy
    random.seed(3)
    for f in range(1, 1081, 2):
        fire_l.data.energy = base * (0.75 + 0.5 * random.random())
        fire_l.data.keyframe_insert("energy", frame=f)
    return (cx, cy, z)

COURT = courtyard()

# ---------------------------------------------------------------- VALLEY VIEW DECK
def valley_deck():
    z = LEVELS[3] + 0.3
    root = frame("VALLEY VIEW DECK", -20.6, -0.9, z, 0.0, C_ARCH)
    # local coords: deck from x -2.4 .. 2.2 (west end sits on boundary wall), y -2.4 .. 2.4
    bx = [p for p in BOUNDARY]
    dk_b = MeshBuilder(); dk_f = MeshBuilder(); rail = MeshBuilder(); fur = MeshBuilder()
    x0, x1, y0, y1 = -2.25, 2.3, -2.4, 2.4
    deck(dk_b, dk_f, x0, x1, y0, y1, 0.0, along="Y", post_bottom=-0.6)
    railing(rail, [(x1 - 1.3, y0), (x0, y0), (x0, y1), (x1 - 1.3, y1)], 0.0)
    lounge_chair(fur, -1.1, -0.9, math.radians(90), 0, 1)
    lounge_chair(fur, -1.1, 0.9, math.radians(90), 0, 1)
    table(fur, -1.25, 0.0, 0.28, 0.45, 0)
    tea = MeshBuilder()
    tea.cyl((-1.25, 0.05, 0.45), (-1.25, 0.05, 0.6), 0.07, 16, 0)
    for dy in (-0.14, 0.16):
        tea.cyl((-1.2, dy, 0.45), (-1.2, dy, 0.52), 0.04, 12, 0)
    dk_b.build("VALLEY DECK · boards", [MAT["timber_dark"]], C_ARCH, root)
    dk_f.build("VALLEY DECK · frame + footings", [MAT["timber_dark"], MAT["stone_light"]], C_ARCH, root)
    rail.build("VALLEY DECK · black metal railing", [MAT["metal"]], C_ARCH, root)
    fur.build("VALLEY DECK · loungers + tea table", [MAT["timber"], MAT["cushion"]], C_ARCH, root)
    tea.build("VALLEY DECK · tea set", [MAT["tea"]], C_ARCH, root)
    # warm under-rail strip lights
    strip = MeshBuilder()
    strip.box((x0 + 0.05, y0 + 0.05, 0.02), (x0 + 0.08, y1 - 0.05, 0.05), 0)
    strip.build("VALLEY DECK · LED strip", [MAT["bulb"]], C_ARCH, root)
    for yy in (-1.6, 0.0, 1.6):
        add_point_light(f"VALLEY DECK light {yy}", (x0 + 0.25, yy, 0.25), 6.0 if not night else 14.0, K2700, 0.1, root)
    return root

DECK = valley_deck()

# =============================================================================
# 9b. SHOT LIST (used for cameras in section 15)
# =============================================================================
G = lambda x, y, dz: (x, y, ground(x, y) + dz)
gx, gy = GATE
SHOT_DEFS = [
    (1, "Aerial — Nilgiri mountains + mist", 0, 4,
         [(-420, -760, 170), (-390, -640, 160), (-360, -520, 150)],
         [(-6000, -900, 560), (-6000, -600, 540), (-6000, -300, 520)], 30),
    (2, "Along the mountain road", 4, 8,
         [(-30, 150, 42), (-26, 98, 26), (-10, 52, 15)],
         [(10, 40, 2), (12, 18, 3), (13, 8, 3)], 30),
    (3, "Approach — stone entrance gate", 8, 12,
         [(gx + 13, gy + 13, LEVELS[0] + 3.0), (gx + 9.0, gy + 8.5, LEVELS[0] + 2.3), (gx + 6.5, gy + 5.8, LEVELS[0] + 1.9)],
         [(gx - 1.2, gy + 1.0, LEVELS[0] + 1.6), (gx - 1.4, gy + 1.0, LEVELS[0] + 1.5), (gx - 2.2, gy + 0.2, LEVELS[0] + 1.4)], 30, 5.6),
    (4, "Reveal — reception + café", 12, 16,
         [(14.5, 1.0, LEVELS[0] + 2.2), (12.0, 3.5, LEVELS[0] + 2.0), (10.5, 6.2, LEVELS[0] + 1.9)],
         [(4.0, 10.0, LEVELS[1] + 1.6), (3.5, 10.0, LEVELS[1] + 1.6), (3.0, 9.5, LEVELS[1] + 1.4)], 28),
    (5, "Through the garden to the campfire", 16, 21,
         [(4.5, 3.8, LEVELS[1] + 2.4), (1.5, 2.0, LEVELS[2] + 2.3), (-0.8, 0.6, LEVELS[2] + 1.6)],
         [(-3.9, -0.9, LEVELS[2] + 0.9), (-4.0, -1.0, LEVELS[2] + 0.7), (-4.1, -1.2, LEVELS[2] + 0.6)], 30, 4.0),
    (6, "Reveal — VALLEY VIEW VILLA", 21, 27,
         [(-38, -26, 6.5), (-35, -16, 4.8), (-32, -6, 3.8)],
         [(-14.8, -10.2, 1.8), (-14.8, -10.2, 1.6), (-15.2, -10.5, 1.4)], 30),
    (7, "Reveal — MIST VIEW VILLA", 27, 32,
         [(-34, 22, 6.0), (-31, 15.5, 4.6), (-28.5, 9.5, 3.8)],
         [(-12.5, 9.0, 1.8), (-12.5, 9.0, 1.6), (-12.8, 9.0, 1.5)], 32, 5.6),
    (8, "Reveal — FOREST VIEW VILLA through vegetation", 32, 36,
         [(9.0, -36, 7.5), (6.5, -32, 6.4), (4.2, -28.5, 5.6)],
         [(1.8, -13.5, 3.4), (1.8, -13.5, 3.2), (1.8, -13.7, 3.0)], 30, 4.0),
    (9, "Toward the valley-view deck", 36, 41,
         [(-7.8, -1.4, LEVELS[2] + 1.9), (-12.6, -1.0, LEVELS[3] + 1.8), (-16.4, -0.9, LEVELS[3] + 1.7)],
         [(-60, -1, -8), (-90, -3, -18), (-140, -4, -32)], 26),
    (10, "Final aerial pull-back — THE MIST VILLAGE", 41, 45,
         [(30, -26, 16), (64, -58, 44), (110, -96, 88)],
         [(-6, -1, -2), (-300, 230, -80), (-663, 537, -161)], 22),
]

# camera paths are defined up-front so vegetation can keep clear of the lenses
def _dense_path(P, step=1.0):
    return densify([(p[0], p[1]) for p in P], step)

CAM_CLEAR = [q for d in SHOT_DEFS[1:9] for q in _dense_path(d[4])]
_CCX = np.array([q[0] for q in CAM_CLEAR]); _CCY = np.array([q[1] for q in CAM_CLEAR])

def near_camera(x, y, r=3.5):
    x = np.atleast_1d(np.asarray(x, float)); y = np.atleast_1d(np.asarray(y, float))
    out = np.zeros(x.shape, bool)
    for cx, cy in zip(_CCX, _CCY):
        out |= (x - cx) ** 2 + (y - cy) ** 2 < r * r
    return out

# =============================================================================
# 10. VEGETATION ASSETS (instanced)
# =============================================================================
def leaf_core(mb, centre, radii, mi=0, sub=3):
    """Irregular opaque crown mass under the leaf cards so crowns read solid."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    ph = random.uniform(0, 10)
    for v in bm.verts:
        n = v.co.normalized()
        k = 1 + 0.25 * math.sin(n.x * 4 + ph) * math.cos(n.y * 5 - ph) + 0.12 * math.sin(n.z * 9 + ph) + random.uniform(-0.1, 0.1)
        v.co = Vector((n.x * radii[0] * k, n.y * radii[1] * k, n.z * radii[2] * k)) + Vector(centre)
    mb.add([tuple(v.co) for v in bm.verts], [tuple(v.index for v in f.verts) for f in bm.faces], mi)
    bm.free()

def leaf_cloud(mb, centre, radii, count, leaf=0.16, mi=0, flat=0.6, jitter=0.25, core=True):
    cx, cy, cz = centre
    if core:
        leaf_core(mb, centre, (radii[0] * 0.72, radii[1] * 0.72, radii[2] * 0.72), mi)
    count = int(count * 4.0)
    leaf *= 0.95
    for _ in range(count):
        # point in ellipsoid shell (denser near surface)
        d = Vector((random.gauss(0, 1), random.gauss(0, 1), random.gauss(0, 1))).normalized()
        r = random.uniform(0.55, 1.0) ** 0.5
        p = Vector((cx + d.x * radii[0] * r, cy + d.y * radii[1] * r, cz + d.z * radii[2] * r))
        # leaf card: small rhombus, oriented roughly outward + random
        n = (d + Vector((random.uniform(-jitter, jitter), random.uniform(-jitter, jitter), 0.6))).normalized()
        t = n.orthogonal().normalized()
        b = n.cross(t)
        rot = random.uniform(0, TAU)
        t, b = t * math.cos(rot) + b * math.sin(rot), b * math.cos(rot) - t * math.sin(rot)
        s = leaf * random.uniform(0.7, 1.3)
        v = [p + t * s, p + b * s * flat, p - t * s, p - b * s * flat]
        mb.add([tuple(q) for q in v], [(0, 1, 2, 3)], mi)

def branchy_trunk(mb, base, height, r0, mi=0, lean=0.0, branches=5, crown_z=0.55):
    x, y, z = base
    top = Vector((x + lean, y + lean * 0.3, z + height))
    mb.cyl((x, y, z - 0.3), tuple(top), r0, 10, mi)
    ends = []
    for i in range(branches):
        a = TAU * i / branches + random.uniform(-0.4, 0.4)
        t = random.uniform(crown_z, 0.9)
        p0 = Vector((x, y, z)).lerp(top, t)
        L_ = height * random.uniform(0.22, 0.38)
        p1 = p0 + Vector((math.cos(a) * L_, math.sin(a) * L_, L_ * random.uniform(0.35, 0.8)))
        mb.cyl(tuple(p0), tuple(p1), r0 * 0.35, 6, mi)
        ends.append(p1)
    return top, ends

def make_asset(name, builder_fn, mats):
    mb = MeshBuilder()
    builder_fn(mb)
    o = mb.build(name, mats, C_ASSET)
    return o

def tree_shola(mb, h=None):
    """Shola evergreen: short trunk, broad irregular dome of overlapping masses."""
    h = h or random.uniform(7, 10)
    top, ends = branchy_trunk(mb, (0, 0, 0), h * 0.62, 0.18, 0, random.uniform(-0.3, 0.3), 6, 0.5)
    blobs = [tuple(top)] + [tuple(e) for e in ends]
    for b in blobs:
        rr = random.uniform(1.7, 2.3)
        leaf_cloud(mb, (b[0] * 0.8, b[1] * 0.8, b[2] + 0.4), (rr, rr, rr * 0.72), 420, 0.13, 1)

def tree_cypress(mb):
    h = random.uniform(9, 13)
    mb.cyl((0, 0, -0.3), (0, 0, h * 0.95), 0.18, 8, 0)
    for i in range(16):
        t = i / 16
        z = 1.4 + t * (h - 1.4)
        r = (1.0 - t) ** 0.8 * 1.55 + 0.2
        leaf_cloud(mb, (random.uniform(-0.15, 0.15), random.uniform(-0.15, 0.15), z), (r, r, 0.8), int(70 * r + 20), 0.12, 1, 0.5)

def columnar(mb, h, trunk_r, bark_mi, n_masses, r_range, spread, start=0.35):
    """Tall oval crown: one elongated irregular mass + overlapping lateral lobes."""
    lean = random.uniform(-0.3, 0.3)
    top = Vector((lean, lean * 0.4, h))
    mb.cyl((0, 0, -0.3), tuple(top), trunk_r, 10, bark_mi)
    zc = h * (start + (1 - start) * 0.55)
    half = h * (1 - start) * 0.5
    rw = sum(r_range) / 2
    leaf_cloud(mb, (lean * 0.6, lean * 0.25, zc), (rw, rw, half), 900, 0.11, 1, 0.35)
    for i in range(n_masses):
        t = random.uniform(0.15, 0.85)
        a = random.uniform(0, TAU)
        c = Vector((lean * 0.6, lean * 0.25, zc - half + 2 * half * t))
        c += Vector((math.cos(a), math.sin(a), 0)) * rw * random.uniform(0.35, 0.6) * spread
        rr = random.uniform(*r_range) * 0.75
        mb.cyl(tuple(Vector((0, 0, 0)).lerp(top, min(0.95, c.z / h))), tuple(c), trunk_r * 0.3, 6, bark_mi)
        leaf_cloud(mb, tuple(c), (rr, rr, rr * 1.1), 260, 0.11, 1, 0.35)

def tree_silver_oak(mb):
    """Grevillea (silver oak): tall, narrow, irregular columnar crown."""
    columnar(mb, random.uniform(12, 16), 0.17, 0, 4, (1.5, 2.0), 1.0)

def tree_eucalyptus(mb):
    columnar(mb, random.uniform(16, 22), 0.22, 0, 4, (1.9, 2.6), 1.2, 0.45)

def tree_fern(mb):
    h = random.uniform(1.8, 3.0)
    mb.cyl((0, 0, -0.1), (0, 0, h), 0.1, 8, 0)
    for i in range(14):
        a = TAU * i / 14 + random.uniform(-0.1, 0.1)
        frond(mb, (0, 0, h), a, random.uniform(1.3, 1.9), random.uniform(0.2, 0.55), 1)

def frond(mb, base, a, L_, lift, mi, pinna=0.12, n=12):
    bx, by, bz = base
    d = Vector((math.cos(a), math.sin(a), 0))
    side = Vector((-d.y, d.x, 0))
    prev = Vector(base)
    n = n * 2
    for k in range(1, n + 1):
        t = k / n
        p = Vector((bx, by, bz)) + d * L_ * t + Vector((0, 0, L_ * (lift * t - 0.55 * t * t)))
        mb.add([tuple(prev + side * 0.006), tuple(p + side * 0.006), tuple(p - side * 0.006), tuple(prev - side * 0.006)], [(0, 1, 2, 3)], mi)
        w = pinna * math.sin(math.pi * min(1.0, t * 1.15)) * 1.5 + 0.015
        for sgn in (-1, 1):
            tip = p + side * sgn * w + d * w * 0.45 + Vector((0, 0, -w * 0.25))
            mb.add([tuple(p), tuple(p + d * L_ / n * 0.9), tuple(tip)], [(0, 1, 2)], mi)
        prev = p

def fern_clump(mb):
    for i in range(random.randint(9, 14)):
        frond(mb, (random.uniform(-0.05, 0.05), random.uniform(-0.05, 0.05), 0.0), random.uniform(0, TAU),
              random.uniform(0.5, 0.85), random.uniform(0.9, 1.4), 0, 0.07, 9)

def shrub(mb, r=None, mi=0):
    r = r or random.uniform(0.5, 0.9)
    for _ in range(random.randint(2, 4)):
        c = (random.uniform(-r * 0.4, r * 0.4), random.uniform(-r * 0.4, r * 0.4), r * random.uniform(0.55, 0.8))
        leaf_cloud(mb, c, (r * 0.8, r * 0.8, r * 0.65), 220, 0.09, mi, 0.6, 0.5)

def grass_clump(mb):
    for i in range(26):
        a = random.uniform(0, TAU)
        r = random.uniform(0, 0.12)
        h = random.uniform(0.18, 0.42)
        base = Vector((r * math.cos(a), r * math.sin(a), -0.02))
        lean = Vector((math.cos(a), math.sin(a), 0)) * random.uniform(0.05, 0.18)
        side = Vector((-math.sin(a), math.cos(a), 0)) * 0.008
        tip = base + lean + Vector((0, 0, h))
        mid = base + lean * 0.4 + Vector((0, 0, h * 0.55))
        mb.add([tuple(base - side), tuple(base + side), tuple(mid + side * 0.7), tuple(tip), tuple(mid - side * 0.7)],
               [(0, 1, 2, 3, 4)], 0)

def rock(mb, r=None):
    r = r or random.uniform(0.4, 1.1)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=r)
    for v in bm.verts:
        n = v.co.normalized()
        v.co *= 1 + 0.25 * math.sin(n.x * 5 + 1) * math.cos(n.y * 4) + random.uniform(-0.05, 0.05)
        v.co.z *= 0.6
        v.co.z -= r * 0.15
    verts = [tuple(v.co) for v in bm.verts]
    faces = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    mb.add(verts, faces, 0)

random.seed(21)
ASSETS = {
    "shola": [make_asset(f"asset · shola evergreen {i}", tree_shola, [MAT["bark"], MAT["leaf_shola"]]) for i in range(4)],
    "cypress": [make_asset(f"asset · cypress {i}", tree_cypress, [MAT["bark"], MAT["leaf_cypress"]]) for i in range(3)],
    "oak": [make_asset(f"asset · silver oak {i}", tree_silver_oak, [MAT["bark"], MAT["leaf_oak"]]) for i in range(2)],
    "euc": [make_asset(f"asset · eucalyptus {i}", tree_eucalyptus, [MAT["bark_pale"], MAT["leaf_euc"]]) for i in range(2)],
    "treefern": [make_asset(f"asset · tree fern {i}", tree_fern, [MAT["bark"], MAT["fern"]]) for i in range(2)],
    "fern": [make_asset(f"asset · fern {i}", fern_clump, [MAT["fern"]]) for i in range(3)],
    "shrub": [make_asset(f"asset · shrub {i}", shrub, [MAT["shrub"]]) for i in range(3)],
    "hydr": [make_asset("asset · hydrangea blue", lambda mb: shrub(mb, 0.55), [MAT["hydrangea"]]),
             make_asset("asset · hydrangea pink", lambda mb: shrub(mb, 0.5), [MAT["hydrangea_p"]])],
    "flowers": [make_asset("asset · wild flowers", lambda mb: shrub(mb, 0.3), [MAT["flowers"]])],
    "hedge": [make_asset(f"asset · hedgerow bush {i}", lambda mb: shrub(mb, random.uniform(0.9, 1.3)), [MAT["hedge"]]) for i in range(2)],
    "grass": [make_asset(f"asset · grass clump {i}", grass_clump, [MAT["grass"]]) for i in range(3)],
    "rock": [make_asset(f"asset · boulder {i}", rock, [MAT["rock"]]) for i in range(3)],
}
# far-distance low-poly tree (for hill forests)
def far_tree(mb):
    mb.cyl((0, 0, -0.5), (0, 0, 4), 0.25, 5, 0)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=3.2)
    for v in bm.verts:
        v.co.z = v.co.z * 1.1 + 6.5
        v.co += v.co.normalized() * random.uniform(-0.4, 0.4)
    mb.add([tuple(v.co) for v in bm.verts], [tuple(v.index for v in f.verts) for f in bm.faces], 1)
    bm.free()
ASSETS["far"] = [make_asset(f"asset · far canopy {i}", far_tree, [MAT["bark"], MAT["leaf_shola"]]) for i in range(3)]

# ---------------------------------------------------------------- scatter via Geometry Nodes
def scatter_group():
    g = bpy.data.node_groups.new("MV_ScatterInstances", "GeometryNodeTree")
    g.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    g.interface.new_socket("Collection", in_out="INPUT", socket_type="NodeSocketCollection")
    g.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    n = g.nodes; l = g.links
    gi = n.new("NodeGroupInput"); go = n.new("NodeGroupOutput")
    ci = n.new("GeometryNodeCollectionInfo")
    ci.transform_space = "ORIGINAL"
    ci.inputs["Separate Children"].default_value = True
    ci.inputs["Reset Children"].default_value = True
    l.new(gi.outputs[1], ci.inputs["Collection"])
    m2p = n.new("GeometryNodeMeshToPoints")
    l.new(gi.outputs[0], m2p.inputs["Mesh"])
    iop = n.new("GeometryNodeInstanceOnPoints")
    iop.inputs["Pick Instance"].default_value = True
    l.new(m2p.outputs[0], iop.inputs["Points"])
    l.new(ci.outputs[0], iop.inputs["Instance"])
    na_v = n.new("GeometryNodeInputNamedAttribute"); na_v.data_type = "INT"; na_v.inputs["Name"].default_value = "variant"
    na_s = n.new("GeometryNodeInputNamedAttribute"); na_s.data_type = "FLOAT"; na_s.inputs["Name"].default_value = "scale"
    na_r = n.new("GeometryNodeInputNamedAttribute"); na_r.data_type = "FLOAT"; na_r.inputs["Name"].default_value = "rotz"
    comb = n.new("ShaderNodeCombineXYZ")
    l.new(na_r.outputs["Attribute"], comb.inputs["Z"])
    l.new(na_v.outputs["Attribute"], iop.inputs["Instance Index"])
    l.new(comb.outputs[0], iop.inputs["Rotation"])
    l.new(na_s.outputs["Attribute"], iop.inputs["Scale"])
    l.new(iop.outputs[0], go.inputs[0])
    return g

SCATTER_G = scatter_group()

def scatter(name, assets, pts, coll, smin=0.8, smax=1.2, weights=None):
    """pts: list of (x,y) or (x,y,z). Places instances of `assets` via GN."""
    if not pts:
        return None
    sub = bpy.data.collections.new("inst · " + name)
    C_ASSET.children.link(sub)
    for a in assets:
        sub.objects.link(a)
    verts, var, sc, rz = [], [], [], []
    for p in pts:
        z = p[2] if len(p) > 2 else ground(p[0], p[1])
        verts.append((p[0], p[1], z))
        var.append(random.randrange(len(assets)) if weights is None else random.choices(range(len(assets)), weights)[0])
        sc.append(random.uniform(smin, smax))
        rz.append(random.uniform(0, TAU))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], [])
    for nm, typ, vals in (("variant", "INT", var), ("scale", "FLOAT", sc), ("rotz", "FLOAT", rz)):
        at = me.attributes.new(nm, typ, "POINT")
        at.data.foreach_set("value", vals)
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    md = o.modifiers.new("scatter", "NODES")
    md.node_group = SCATTER_G
    # set collection input
    for key in md.keys():
        pass
    try:
        ident = SCATTER_G.interface.items_tree["Collection"].identifier
        md[ident] = sub
    except Exception:
        md["Socket_1"] = sub
    return o

# ---------------------------------------------------------------- exclusion + placement
BUILD_RECTS = []   # (cx, cy, rz, hw, hd) world footprints incl. decks

def add_rect(cx, cy, rz, hw, hd):
    BUILD_RECTS.append((cx, cy, rz, hw, hd))

for key, (root, ffl) in VILLAS.items():
    add_rect(root.location.x, root.location.y, root.rotation_euler.z, VILLA_W / 2 + 1.4, VILLA_D / 2 + 1.0)
    # deck in front
    fwd = Vector((-math.sin(root.rotation_euler.z), math.cos(root.rotation_euler.z)))
    c = Vector((root.location.x, root.location.y)) + fwd * (VILLA_D / 2 + 1.6)
    add_rect(c.x, c.y, root.rotation_euler.z, VILLA_W / 2 + 1.2, 2.2)
add_rect(RECEPTION.location.x, RECEPTION.location.y + 1.2, 0, 6.8, 5.0)
add_rect(13.8, 0.1, 0, 4.8, 6.0)                           # parking
add_rect(DECK.location.x, DECK.location.y, 0, 2.8, 2.9)
add_rect(GATE[0] - 2.5, GATE[1] - 2.8, 0, 3.8, 3.8)        # gate/driveway

def free_spot(x, y, margin=0.4):
    for cx, cy, rz, hw, hd in BUILD_RECTS:
        dx, dy = x - cx, y - cy
        c, s = math.cos(-rz), math.sin(-rz)
        lx, ly = dx * c - dy * s, dx * s + dy * c
        if abs(lx) < hw + margin and abs(ly) < hd + margin:
            return False
    if math.dist((x, y), CAMPFIRE) < 4.4 + margin:
        return False
    if near_camera(x, y, 3.0)[0]:
        return False
    for pl in PATHS.values():
        for p in densify(pl, 0.5):
            if math.dist(p, (x, y)) < PATH_W / 2 + 0.35 + margin:
                return False
    for c in STEP_CROSS:
        if math.dist(c[0], (x, y)) < 3.0:
            return False
    # keep off retaining walls
    for F in (F0, F1, F2):
        if abs(x - float(f_eval(F, np.array([y]))[0])) < 0.6 + margin:
            return False
    d, *_ = poly_dist(np.array([x]), np.array([y]))
    if d[0] < 0.55 + margin and inside_poly(np.array([x]), np.array([y]))[0]:
        return False
    return True

def sample_inside(n, margin=0.4, region=None, tries=40000):
    out = []
    xs = RNG.uniform(BP[:, 0].min(), BP[:, 0].max(), tries)
    ys = RNG.uniform(BP[:, 1].min(), BP[:, 1].max(), tries)
    ins = inside_poly(xs, ys)
    for x, y, k in zip(xs, ys, ins):
        if not k:
            continue
        if region and not region(x, y):
            continue
        if free_spot(x, y, margin):
            out.append((float(x), float(y), lvl(x, y)))
        if len(out) >= n:
            break
    return out

random.seed(5)
# --- privacy planting along the boundary (inside), leaving valley-view gaps on the west
bpts = densify(BOUNDARY + [BOUNDARY[0]], 2.2)
edge_trees, edge_shrubs = [], []
cx0, cy0 = BP[:, 0].mean(), BP[:, 1].mean()
for (x, y) in bpts:
    v = Vector((cx0 - x, cy0 - y)).normalized()
    px, py = x + v.x * 1.4, y + v.y * 1.4
    west_view = x < -17 and -14 < y < 8        # keep valley views open (valley villa, deck, mist villa)
    if math.dist((x, y), GATE) < 5.5:
        continue
    if not free_spot(px, py, 0.2):
        continue
    if not west_view and random.random() < 0.55:
        edge_trees.append((px + random.uniform(-0.4, 0.4), py + random.uniform(-0.4, 0.4), lvl(px, py)))
    else:
        edge_shrubs.append((px, py, lvl(px, py)))
scatter("Boundary privacy trees", ASSETS["cypress"] + ASSETS["shola"], edge_trees, C_LAND, 0.55, 0.85, [2, 2, 2, 1, 1, 1, 1])
scatter("Boundary hedge planting", ASSETS["shrub"] + ASSETS["hydr"], edge_shrubs, C_LAND, 0.8, 1.2)

# --- forest villa: dense native planting + tree ferns
fv = VILLAS["forest"][0].location
forest_region = lambda x, y: math.dist((x, y), (fv.x, fv.y)) < 9.5
scatter("Forest villa · trees", ASSETS["shola"] + ASSETS["treefern"], sample_inside(14, 0.6, forest_region), C_LAND, 0.55, 0.9)
scatter("Forest villa · understorey", ASSETS["fern"] + ASSETS["shrub"] + ASSETS["hydr"], sample_inside(70, 0.1, forest_region), C_LAND, 0.8, 1.3)

# --- courtyard garden
court_region = lambda x, y: 4.5 < math.dist((x, y), CAMPFIRE) < 8.5
scatter("Courtyard · specimen trees", ASSETS["shola"][:2] + ASSETS["treefern"], sample_inside(4, 1.2, court_region), C_LAND, 0.5, 0.7)
scatter("Courtyard · planting", ASSETS["fern"] + ASSETS["hydr"] + ASSETS["flowers"] + ASSETS["shrub"],
        sample_inside(90, 0.05, court_region), C_LAND, 0.7, 1.2)

# --- general landscaping
scatter("Site · ferns + flowering plants", ASSETS["fern"] + ASSETS["flowers"] + ASSETS["hydr"],
        sample_inside(140, 0.1), C_LAND, 0.6, 1.1)
scatter("Site · shrubs", ASSETS["shrub"], sample_inside(45, 0.2), C_LAND, 0.6, 1.0)
scatter("Site · natural rocks", ASSETS["rock"], sample_inside(26, 0.3), C_LAND, 0.4, 0.9)
scatter("Site · grass tussocks", ASSETS["grass"], sample_inside(2600, -0.25, tries=60000), C_LAND, 0.7, 1.5)

# =============================================================================
# 11. OUTSIDE THE PROPERTY: hillside forest, valley agriculture, farmsteads
# =============================================================================
def outside_points(n, rmin, rmax, weight_fn, xbias=None):
    pts = []
    tries = 0
    while len(pts) < n and tries < n * 30:
        tries += 1000
        r = np.sqrt(RNG.uniform(rmin ** 2, rmax ** 2, 1000))
        a = RNG.uniform(0, TAU, 1000)
        x = r * np.cos(a); y = r * np.sin(a)
        if xbias is not None:
            keep = xbias(x, y)
            x, y = x[keep], y[keep]
        ins = inside_poly(x, y)
        rd, _ = road_info(x, y)
        d, *_ = poly_dist(x, y)
        w = weight_fn(x, y) * (~ins) * (rd > ROAD_HALF + 2.0) * (d > 1.6) * (~near_camera(x, y, 7.5))
        keep = RNG.uniform(0, 1, len(x)) < w
        for xx, yy in zip(x[keep], y[keep]):
            pts.append((float(xx), float(yy)))
    return pts[:n]

random.seed(9)
near_forest = outside_points(2600, 12, 320, lambda x, y: np.clip(forest_mask(x, y) * 1.4 + 0.12 * (1 - farm_mask(x, y)), 0, 1))
scatter("Outside · native shola + cypress (near)", ASSETS["shola"] + ASSETS["cypress"] + ASSETS["euc"] + ASSETS["oak"],
        near_forest, C_VALLEY, 0.75, 1.25, [4, 4, 4, 4, 2, 2, 2, 1, 1, 1, 1])
mid_forest = outside_points(26000, 280, 2600, lambda x, y: forest_mask(x, y) ** 0.7)
scatter("Outside · hill forest (mid)", ASSETS["far"], mid_forest, C_VALLEY, 0.8, 1.6)
near_shrub = outside_points(1600, 8, 160, lambda x, y: np.clip(forest_mask(x, y) * 0.9 + 0.04, 0, 1) * (1 - farm_mask(x, y)))
near_grass = outside_points(5000, 3, 70, lambda x, y: 0.8 * (1 - farm_mask(x, y)))
scatter("Outside · grass tussocks", ASSETS["grass"], near_grass, C_VALLEY, 0.9, 1.8)
scatter("Outside · scrub + ferns", ASSETS["shrub"] + ASSETS["fern"] + ASSETS["rock"], near_shrub, C_VALLEY, 0.8, 1.4, [4, 4, 4, 3, 3, 3, 0.3, 0.3, 0.3])

# hedgerows along the contour-strip field boundaries (same formula as the terrain shader)
hedges = []
W = 16.0
for k in range(int(-620 / W), int(FARM_X[1] / W) + 1):
    for yv in np.arange(-900, 900, 3.2):
        x = k * W - 6 * math.sin(yv / 37.0) - 3 * math.sin(yv / 13.0 + 1.0)
        if random.random() < 0.55 and farm_mask(np.array([x]), np.array([yv]))[0] > 0.6:
            if (k * 7 + int((yv + 1000) / 60)) % 3 != 0:   # broken hedgerows
                hedges.append((x + random.uniform(-0.5, 0.5), yv + random.uniform(-1, 1)))
scatter("Valley · hedgerows (outside property)", ASSETS["hedge"] + ASSETS["shrub"], hedges, C_VALLEY, 0.8, 1.4)
shade_trees = [p for p in hedges if random.random() < 0.03]
scatter("Valley · silver oak shade trees", ASSETS["oak"] + ASSETS["euc"], shade_trees, C_VALLEY, 0.8, 1.2)

def farmsteads():
    mb = MeshBuilder()
    roofcols = [simple("Farm roof blue", (0.05, 0.12, 0.25), 0.5, 0.4), simple("Farm roof red", (0.25, 0.05, 0.03), 0.5, 0.4),
                simple("Farm roof green", (0.05, 0.15, 0.08), 0.5, 0.4)]
    random.seed(12)
    pts = []
    while len(pts) < 26:
        x, y = random.uniform(-700, -80), random.uniform(-800, 800)
        if farm_mask(np.array([x]), np.array([y]))[0] > 0.7:
            pts.append((x, y))
    for (x, y) in pts:
        z = ground(x, y)
        rz = random.uniform(0, math.pi)
        w, d = random.uniform(5, 9), random.uniform(4, 6)
        M = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
        mb.box((-w / 2, -d / 2, -1), (w / 2, d / 2, 2.6), 0, M)
        mi = 1 + random.randrange(3)
        for s in (-1, 1):
            v = [(-w / 2 - 0.3, 0, 3.6), (w / 2 + 0.3, 0, 3.6), (w / 2 + 0.3, s * (d / 2 + 0.4), 2.45), (-w / 2 - 0.3, s * (d / 2 + 0.4), 2.45)]
            vv = [tuple(M @ Vector(p)) for p in v]
            mb.add(vv, [(0, 1, 2, 3) if s > 0 else (3, 2, 1, 0)], mi)
    mb.build("Valley · farmsteads (outside property)", [MAT["plaster"]] + roofcols, C_VALLEY)

farmsteads()

# =============================================================================
# 12. NILGIRI MOUNTAIN RANGES (layered ridges)
# =============================================================================
def mat_mountain(name, c_forest, c_grass):
    m, nt, out = mat_new(name)
    co = coords(nt)
    n = N(nt, "ShaderNodeTexNoise", {"Vector": co, "Scale": 0.0012, "Detail": 10.0, "Roughness": 0.6})
    geo = N(nt, "ShaderNodeNewGeometry")
    nz = N(nt, "ShaderNodeSeparateXYZ", {"Vector": geo.outputs["Normal"]}).outputs[2]
    z = N(nt, "ShaderNodeSeparateXYZ", {"Vector": co}).outputs[2]
    # shola forest in folds, grassland (downs) on upper convex slopes — classic Nilgiri mosaic
    fold = math_n(nt, "ADD", n.outputs[0], math_n(nt, "MULTIPLY", z, 0.0004))
    g = ramp(nt, fold, [(0.52, (0, 0, 0)), (0.62, (1, 1, 1))])
    c = mix_rgb(nt, N(nt, "ShaderNodeSeparateColor", {"Color": g}).outputs[0], c_forest, c_grass)
    rockm = math_n(nt, "SUBTRACT", 1.0, math_n(nt, "MULTIPLY", math_n(nt, "SUBTRACT", nz, 0.45), 5.0), clamp=True)
    c = mix_rgb(nt, rockm, c, (0.10, 0.10, 0.09))
    p = principled(nt, c, 0.9)
    n2 = N(nt, "ShaderNodeTexNoise", {"Vector": co, "Scale": 0.02, "Detail": 8.0})
    L(nt, bump(nt, n2.outputs[0], 0.6, 8.0), p.inputs["Normal"])
    out_hazed(nt, out, p.outputs[0])
    return m

MTN_MAT = mat_mountain("Nilgiri Ridge — shola + grassland", (0.012, 0.03, 0.014), (0.07, 0.085, 0.035))

def ridge_layer(name, x_near, depth, height, seed, y_span=26000, step=70.0, z0=-40.0):
    xs = np.arange(0, depth + step, step)
    ys = np.arange(-y_span / 2, y_span / 2 + step, step * 1.6)
    U, V = np.meshgrid(xs, ys)             # U across (0 near → depth far), V along ridge
    X = -(x_near + U)
    Y = V
    # irregular massif: warped ridged noise × crest profile, never conical
    wx = X / 3200.0 + 0.6 * fbm(X / 5000.0, Y / 5000.0, 3, seed + 3)
    wy = Y / 3200.0 + 0.6 * fbm(Y / 5000.0, X / 5000.0, 3, seed + 7)
    rid = ridged(wx, wy, 7, seed)
    crest = np.exp(-((U - depth * 0.55) / (depth * 0.38)) ** 2)
    mass = 0.55 + 0.45 * fbm(Y / 7000.0, seed * 0.13, 4, seed + 9)
    H = z0 + height * crest * mass * (0.45 + 0.9 * rid) + 25 * fbm(X / 300.0, Y / 300.0, 4, seed + 11)
    H = np.where(U < step * 1.5, z0 - 200, H)        # sink the near edge
    ny, nx = U.shape
    verts = np.stack([X.ravel(), Y.ravel(), H.ravel()], 1)
    idx = np.arange(nx * ny).reshape(ny, nx)
    faces = np.stack([idx[:-1, :-1].ravel(), idx[1:, :-1].ravel(), idx[1:, 1:].ravel(), idx[:-1, 1:].ravel()], 1)
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts.tolist(), [], faces.tolist())
    me.polygons.foreach_set("use_smooth", np.ones(len(faces), bool))
    me.materials.append(MTN_MAT)
    o = bpy.data.objects.new(name, me)
    C_MTN.objects.link(o)
    return o

ridge_layer("Ridge 1 — near spur (4 km)", 3600, 3200, 640, 101, z0=60)
ridge_layer("Ridge 2 — Kotagiri–Kodanad range (7 km)", 6200, 4200, 1050, 202, z0=40)
ridge_layer("Ridge 3 — Doddabetta massif (11 km)", 9800, 5200, 1500, 303, z0=0)
ridge_layer("Ridge 4 — far Nilgiri escarpment (17 km)", 15500, 7000, 1900, 404, z0=-60)
# southern & northern flanking masses so the valley reads enclosed
def flank(name, y0, sign, seed):
    xs = np.arange(-9000, 3000, 120.0)
    ys = np.arange(0, 4000, 120.0)
    U, V = np.meshgrid(xs, ys)
    X = U; Y = sign * (y0 + V)
    rid = ridged(X / 2600.0, Y / 2600.0, 6, seed)
    crest = np.exp(-((V - 2000) / 1300.0) ** 2)
    H = 150 + 650 * crest * (0.4 + 0.9 * rid)
    ny, nx = U.shape
    verts = np.stack([X.ravel(), Y.ravel(), H.ravel()], 1)
    idx = np.arange(nx * ny).reshape(ny, nx)
    f = np.stack([idx[:-1, :-1].ravel(), idx[:-1, 1:].ravel(), idx[1:, 1:].ravel(), idx[1:, :-1].ravel()], 1)
    if sign < 0:
        f = f[:, ::-1]
    me = bpy.data.meshes.new(name); me.from_pydata(verts.tolist(), [], f.tolist())
    me.polygons.foreach_set("use_smooth", np.ones(len(f), bool))
    me.materials.append(MTN_MAT)
    o = bpy.data.objects.new(name, me); C_MTN.objects.link(o)

flank("Flank — southern hills", 6300, -1, 505)
flank("Flank — northern hills", 6300, 1, 606)

# =============================================================================
# 13. MIST + VFX
# =============================================================================
def mat_mist_sheet(name, density=0.55, scale=0.004, col=(0.85, 0.88, 0.92)):
    m, nt, out = mat_new(name)
    co = coords(nt, "Object")
    gen = coords(nt, "Generated")
    mp = N(nt, "ShaderNodeMapping", {"Vector": co})
    n = N(nt, "ShaderNodeTexNoise", {"Vector": mp.outputs[0], "Scale": scale, "Detail": 6.0, "Roughness": 0.55})
    # soft edges
    g = N(nt, "ShaderNodeSeparateXYZ", {"Vector": gen})
    ex = math_n(nt, "MULTIPLY", math_n(nt, "MULTIPLY", g.outputs[0], math_n(nt, "SUBTRACT", 1.0, g.outputs[0])), 4.0)
    ey = math_n(nt, "MULTIPLY", math_n(nt, "MULTIPLY", g.outputs[1], math_n(nt, "SUBTRACT", 1.0, g.outputs[1])), 4.0)
    edge = math_n(nt, "POWER", math_n(nt, "MULTIPLY", ex, ey), 0.8)
    a = ramp(nt, n.outputs[0], [(0.48, (0, 0, 0)), (0.78, (1, 1, 1))])
    alpha = math_n(nt, "MULTIPLY", math_n(nt, "MULTIPLY", N(nt, "ShaderNodeSeparateColor", {"Color": a}).outputs[0], edge), density)
    d = N(nt, "ShaderNodeBsdfDiffuse", {"Color": rgba(col)})
    t = N(nt, "ShaderNodeBsdfTranslucent", {"Color": rgba(col)})
    ms = N(nt, "ShaderNodeMixShader", {0: 0.5})
    L(nt, d.outputs[0], ms.inputs[1]); L(nt, t.outputs[0], ms.inputs[2])
    tr = N(nt, "ShaderNodeBsdfTransparent")
    mix = N(nt, "ShaderNodeMixShader")
    L(nt, alpha, mix.inputs[0]); L(nt, tr.outputs[0], mix.inputs[1]); L(nt, ms.outputs[0], mix.inputs[2])
    g2 = nt.nodes.new("ShaderNodeGroup"); g2.node_tree = HAZE_G
    L(nt, mix.outputs[0], g2.inputs[0])
    # keep transparency outside the haze (haze only where there is mist)
    mix2 = N(nt, "ShaderNodeMixShader")
    L(nt, alpha, mix2.inputs[0]); L(nt, tr.outputs[0], mix2.inputs[1]); L(nt, g2.outputs[0], mix2.inputs[2])
    L(nt, mix2.outputs[0], out.inputs["Surface"])
    set_blend(m, True)
    try:
        m.use_backface_culling = False
    except Exception:
        pass
    # slow drift
    mp.inputs["Location"].keyframe_insert("default_value", frame=1)
    mp.inputs["Location"].default_value = (140.0, 60.0, 0.0)
    mp.inputs["Location"].keyframe_insert("default_value", frame=1080)
    return m

MIST_NEAR = mat_mist_sheet("Valley Mist Sheet", 0.45, 0.006)
MIST_FAR = mat_mist_sheet("Ridge Mist Sheet", 0.7, 0.0009, (0.80, 0.84, 0.90))

def mist_sheet(name, cx, cy, z, sx, sy, mat):
    vs = [(-sx / 2, -sy / 2, 0), (sx / 2, -sy / 2, 0), (sx / 2, sy / 2, 0), (-sx / 2, sy / 2, 0)]
    o = mesh_obj(name, vs, [(0, 1, 2, 3)], mat, C_VFX)
    o.location = (cx, cy, z)
    try:
        o.visible_shadow = False
    except Exception:
        pass
    return o

# valley fog lying in the folds below the property
for i, (x, y, z, sx, sy) in enumerate([(-420, 0, -44, 900, 2600), (-700, -300, -58, 1200, 1800), (-300, 500, -30, 700, 900),
                                       (-1000, 200, -66, 1400, 3000), (-220, -350, -24, 500, 700)]):
    mist_sheet(f"Valley mist layer {i}", x, y, z, sx, sy, MIST_NEAR)
# mist between the mountain ridges
for i, (x, y, z, sx, sy) in enumerate([(-3400, 0, 30, 1600, 22000), (-6000, 0, 110, 2400, 24000), (-9600, 0, 220, 3200, 26000),
                                       (-15000, 0, 260, 5000, 30000), (-2000, 0, -30, 1600, 12000)]):
    mist_sheet(f"Ridge mist band {i}", x, y, z, sx, sy, MIST_FAR)

def volume_box(name, center, size, density, color=(0.9, 0.92, 0.95), falloff_z=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    o = bpy.context.object
    o.name = name
    o.scale = size
    link(o, C_VFX)
    m, nt, out = mat_new(name + " volume")
    co = coords(nt, "Generated")
    z = N(nt, "ShaderNodeSeparateXYZ", {"Vector": co}).outputs[2]
    n = N(nt, "ShaderNodeTexNoise", {"Vector": coords(nt, "Object"), "Scale": 2.5, "Detail": 3.0})
    dens = math_n(nt, "MULTIPLY", math_n(nt, "POWER", math_n(nt, "SUBTRACT", 1.0, z), 2.2), density)
    dens = math_n(nt, "MULTIPLY", dens, math_n(nt, "ADD", math_n(nt, "MULTIPLY", n.outputs[0], 1.2), 0.2))
    pv = N(nt, "ShaderNodeVolumePrincipled", {"Color": rgba(color), "Density": dens, "Anisotropy": 0.35})
    L(nt, pv.outputs[0], out.inputs["Volume"])
    o.data.materials.append(m)
    try:
        o.visible_shadow = False
    except Exception:
        pass
    return o

volume_box("Low ground fog — property", (-4, -1, 0.3), (70, 60, 3.0), 0.012)
volume_box("Valley haze volume", (-190, 0, -30), (260, 420, 30), 0.0015)

# floating mist puffs (particles)
def mist_puff_asset():
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=1.0)
    o = bpy.context.object; o.name = "asset · mist puff"; link(o, C_ASSET)
    bpy.ops.object.shade_smooth()
    m, nt, out = mat_new("Mist Puff")
    lw = N(nt, "ShaderNodeLayerWeight", {"Blend": 0.5})
    a = math_n(nt, "MULTIPLY", math_n(nt, "POWER", math_n(nt, "SUBTRACT", 1.0, lw.outputs["Facing"]), 3.0), 0.05)
    d = N(nt, "ShaderNodeBsdfTranslucent", {"Color": rgba((0.9, 0.92, 0.95))})
    tr = N(nt, "ShaderNodeBsdfTransparent")
    mix = N(nt, "ShaderNodeMixShader")
    L(nt, a, mix.inputs[0]); L(nt, tr.outputs[0], mix.inputs[1]); L(nt, d.outputs[0], mix.inputs[2])
    L(nt, mix.outputs[0], out.inputs["Surface"])
    set_blend(m, True)
    o.data.materials.append(m)
    try:
        o.visible_shadow = False
    except Exception:
        pass
    return o

PUFF = mist_puff_asset()

def ember_asset():
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1.0)
    o = bpy.context.object; o.name = "asset · ember"; link(o, C_ASSET)
    o.data.materials.append(MAT["ember"])
    return o

EMBER = ember_asset()

def particle_emitter(name, loc, size, inst, count, life, vel, size_p, rand_size=0.5, brown=0.0, frame_start=-200, gravity=0.0, coll=C_VFX):
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc)
    em = bpy.context.object; em.name = name; em.scale = size
    link(em, coll)
    ps = em.modifiers.new(name, "PARTICLE_SYSTEM").particle_system
    st = ps.settings
    st.count = count
    st.frame_start = frame_start
    st.frame_end = 1080
    st.lifetime = life
    st.lifetime_random = 0.4
    st.emit_from = "FACE"
    st.normal_factor = vel
    st.factor_random = vel * 0.6
    st.render_type = "OBJECT"
    st.instance_object = inst
    st.particle_size = size_p
    st.size_random = rand_size
    st.brownian_factor = brown
    st.effector_weights.gravity = gravity
    st.use_rotations = True
    st.rotation_factor_random = 1.0
    em.show_instancer_for_render = False
    em.show_instancer_for_viewport = False
    return em

cf = COURT
particle_emitter("VFX · fire embers", (cf[0], cf[1], cf[2] + 0.35), (0.6, 0.6, 1), EMBER, 900, 45, 1.2, 0.012, 0.6, 1.2, gravity=-0.05)
particle_emitter("VFX · drifting mist puffs", (-6, -2, 1.2), (60, 50, 1), PUFF, 160, 900, 0.03, 2.2, 0.6, 0.15)

# =============================================================================
# 14. LIGHTING + WORLD
# =============================================================================
SUN_AZ, SUN_EL = math.radians(228), math.radians(7.0)       # WSW, low golden-hour sun over the valley
SUN_DIR = Vector((math.cos(SUN_EL) * math.cos(SUN_AZ), math.cos(SUN_EL) * math.sin(SUN_AZ), math.sin(SUN_EL)))

def lights_world():
    sun = bpy.data.lights.new("Golden Hour Sun", "SUN")
    sun.energy = 4.2 if not night else 0.0
    sun.color = (1.0, 0.60, 0.33)
    sun.angle = math.radians(1.2)
    so = bpy.data.objects.new("Golden Hour Sun", sun)
    C_LIGHT.objects.link(so)
    so.rotation_euler = (-SUN_DIR).to_track_quat("-Z", "Y").to_euler()
    fill = bpy.data.lights.new("Cool Mountain Fill", "SUN")
    fill.energy = 0.25 if not night else 0.06
    fill.color = (0.55, 0.68, 1.0)
    fill.angle = math.radians(40)
    try:
        fill.use_shadow = False
    except Exception:
        pass
    fo = bpy.data.objects.new("Cool Mountain Fill", fill)
    C_LIGHT.objects.link(fo)
    fo.rotation_euler = Vector((0.5, 0.6, 0.62)).normalized().to_track_quat("Z", "Y").to_euler()
    fo.rotation_euler = (-Vector((0.45, 0.3, 0.84)).normalized()).to_track_quat("-Z", "Y").to_euler()
    # world: custom gradient sky with sun glow (identical in Cycles & EEVEE)
    w = bpy.data.worlds.new("Nilgiri Golden Hour Sky" if not night else "Nilgiri Night Sky")
    S.world = w
    try:
        w.use_nodes = True
    except Exception:
        pass
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    norm = nt.nodes.new("ShaderNodeVectorMath"); norm.operation = "NORMALIZE"
    nt.links.new(tc.outputs["Generated"], norm.inputs[0])
    sep = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(norm.outputs[0], sep.inputs[0])
    el = sep.outputs[2]
    dot = nt.nodes.new("ShaderNodeVectorMath"); dot.operation = "DOT_PRODUCT"
    nt.links.new(norm.outputs[0], dot.inputs[0]); dot.inputs[1].default_value = tuple(SUN_DIR)
    if not night:
        sky = ramp(nt, math_n(nt, "ADD", math_n(nt, "MULTIPLY", el, 1.4), 0.5),
                   [(0.40, (0.55, 0.52, 0.52)), (0.5, (1.00, 0.62, 0.38)), (0.56, (0.95, 0.70, 0.52)),
                    (0.68, (0.55, 0.62, 0.78)), (1.0, (0.16, 0.30, 0.62))])
        glow = math_n(nt, "POWER", math_n(nt, "MAXIMUM", dot.outputs["Value"], 0.0), 28.0)
        glow2 = math_n(nt, "POWER", math_n(nt, "MAXIMUM", dot.outputs["Value"], 0.0), 4.0)
        g = math_n(nt, "ADD", math_n(nt, "MULTIPLY", glow, 6.0), math_n(nt, "MULTIPLY", glow2, 0.8))
        glowc = mix_rgb(nt, 1.0, (0, 0, 0), (1.0, 0.55, 0.25))
        add = nt.nodes.new("ShaderNodeMix"); add.data_type = "RGBA"; add.blend_type = "ADD"
        nt.links.new(g, add.inputs[0]); nt.links.new(sky, add.inputs[6]); nt.links.new(glowc, add.inputs[7])
        bg = nt.nodes.new("ShaderNodeBackground"); bg.inputs[1].default_value = 1.6
        nt.links.new(add.outputs[2], bg.inputs[0])
    else:
        sky = ramp(nt, math_n(nt, "ADD", math_n(nt, "MULTIPLY", el, 1.4), 0.5),
                   [(0.40, (0.004, 0.005, 0.009)), (0.5, (0.02, 0.028, 0.05)), (1.0, (0.002, 0.004, 0.012))])
        bg = nt.nodes.new("ShaderNodeBackground"); bg.inputs[1].default_value = 1.0
        nt.links.new(sky, bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs["Surface"])
    return so

SUN = lights_world()

# =============================================================================
# 15. CAMERAS — 45 s, 24 fps, ten shots bound to timeline markers
# =============================================================================
FPS = 24
S.render.fps = FPS
S.frame_start, S.frame_end = 1, 45 * FPS

def sec(t):
    return int(round(t * FPS)) + 1

def shot(idx, name, t0, t1, path, target_path, lens=35, dof=None):
    cd = bpy.data.cameras.new(f"CAM {idx:02d}")
    cd.lens = lens
    cd.sensor_width = 36
    cd.clip_start = 0.1
    cd.clip_end = 40000
    cam = bpy.data.objects.new(f"SHOT {idx:02d} — {name}", cd)
    C_CAM.objects.link(cam)
    tgt = bpy.data.objects.new(f"SHOT {idx:02d} target", None)
    tgt.empty_display_size = 0.5
    C_CAM.objects.link(tgt)
    con = cam.constraints.new("TRACK_TO")
    con.target = tgt; con.track_axis = "TRACK_NEGATIVE_Z"; con.up_axis = "UP_Y"
    f0, f1 = sec(t0), sec(t1)
    n = len(path)
    for i, (p, q) in enumerate(zip(path, target_path)):
        f = f0 + (f1 - f0) * i / (n - 1)
        cam.location = p; cam.keyframe_insert("location", frame=f)
        tgt.location = q; tgt.keyframe_insert("location", frame=f)
    for ob in (cam, tgt):
        try:
            for fc in ob.animation_data.action.fcurves:
                for k in fc.keyframe_points:
                    k.interpolation = "BEZIER"
                    k.handle_left_type = k.handle_right_type = "AUTO_CLAMPED"
                fc.extrapolation = "LINEAR"
        except Exception:
            pass
    if dof:
        cd.dof.use_dof = True
        cd.dof.focus_object = tgt
        cd.dof.aperture_fstop = dof
    mk = S.timeline_markers.new(f"S{idx:02d} {name}", frame=f0)
    mk.camera = cam
    return cam

SHOTS = [shot(*d) for d in SHOT_DEFS]
S.camera = SHOTS[0]

# title card for the final shot (parented to shot 10 camera, fades in)
def title_card():
    cam = SHOTS[9]
    mat = MAT["title"]
    nt = mat.node_tree
    em = [n for n in nt.nodes if n.type == "EMISSION"][0]
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    out = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"][0]
    nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    set_blend(mat, True)
    fac = mix.inputs[0]
    for f, v in ((1, 0.0), (sec(42.0), 0.0), (sec(43.2), 1.0), (sec(45) + 5, 1.0)):
        fac.default_value = v; fac.keyframe_insert("default_value", frame=f)
    t1 = text_obj("TITLE · THE MIST VILLAGE", "THE MIST VILLAGE", 0.055, mat, (0, 0.028, -1.0), (0, 0, 0), 0.0, C_CAM, cam, spacing=1.25)
    t2 = text_obj("TITLE · KOTAGIRI", "K O T A G I R I   ·   N I L G I R I S", 0.016, mat, (0, -0.012, -1.0), (0, 0, 0), 0.0, C_CAM, cam)
    t3 = text_obj("TITLE · tagline", "Where the mist slows you down.", 0.022, mat, (0, -0.2, -1.0), (0, 0, 0), 0.0, C_CAM, cam)
    for t in (t1, t2, t3):
        try:
            t.visible_shadow = False
        except Exception:
            pass
        # only visible during shot 10
        t.hide_render = True; t.keyframe_insert("hide_render", frame=1)
        t.hide_render = False; t.keyframe_insert("hide_render", frame=sec(41))

title_card()

# =============================================================================
# 16. RENDER SETTINGS (EEVEE for the film; Cycles-ready)
# =============================================================================
S.render.resolution_x, S.render.resolution_y, S.render.resolution_percentage = 1920, 1080, 100
S.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
ev = S.eevee
for attr, val in (("taa_render_samples", 96), ("use_raytracing", True), ("use_shadows", True), ("shadow_ray_count", 2),
                  ("shadow_step_count", 8), ("volumetric_start", 0.5), ("volumetric_end", 1500.0), ("volumetric_tile_size", "4"),
                  ("volumetric_samples", 96), ("use_volumetric_shadows", True), ("fast_gi_method", "GLOBAL_ILLUMINATION"),
                  ("use_gtao", True), ("use_bloom", True), ("bloom_intensity", 0.03), ("use_motion_blur", True)):
    try:
        setattr(ev, attr, val)
    except Exception:
        pass
try:
    ev.ray_tracing_options.resolution_scale = "2"
except Exception:
    pass
try:
    S.cycles.samples = 128
    S.cycles.use_denoising = True
    S.cycles.max_bounces = 8
    S.cycles.volume_step_rate = 4.0
except Exception:
    pass
S.render.use_motion_blur = True
try:
    S.view_settings.view_transform = "AgX"
    S.view_settings.look = "AgX - Medium High Contrast"
except Exception:
    try:
        S.view_settings.look = "Medium High Contrast"
    except Exception:
        pass
S.view_settings.exposure = 0.0 if not night else 0.6
S.render.image_settings.file_format = "PNG"
S.render.filepath = "//render/mist_village_"
try:
    S.render.image_settings.media_type = "VIDEO"
except Exception:
    pass
try:
    S.render.image_settings.file_format = "FFMPEG"
    S.render.ffmpeg.format = "MPEG4"
    S.render.ffmpeg.codec = "H264"
    S.render.ffmpeg.constant_rate_factor = "HIGH"
    S.render.filepath = "//render/THE_MIST_VILLAGE_45s_1080p.mp4"
except Exception:
    S.render.image_settings.file_format = "PNG"

# compositor: subtle bloom (fog glow) + gentle vignette — works in 4.x and 5.x APIs
def compositor():
    try:
        if hasattr(S, "compositing_node_group"):
            tree = bpy.data.node_groups.new("MV Compositor", "CompositorNodeTree")
            S.compositing_node_group = tree
            new_api = True
        else:
            S.use_nodes = True
            tree = S.node_tree
            tree.nodes.clear()
            new_api = False
        n, l = tree.nodes, tree.links
        rl = n.new("CompositorNodeRLayers")
        gl = n.new("CompositorNodeGlare")
        try:
            gl.glare_type = "FOG_GLOW"; gl.quality = "HIGH"; gl.mix = -0.82; gl.threshold = 1.0; gl.size = 8
        except Exception:
            pass
        for k, v in (("Type", "Fog Glow"), ("Strength", 0.22), ("Threshold", 1.0), ("Size", 0.6)):
            try:
                gl.inputs[k].default_value = v
            except Exception:
                pass
        l.new(rl.outputs["Image"], gl.inputs["Image"])
        if new_api:
            tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
            go = n.new("NodeGroupOutput")
            l.new(gl.outputs[0], go.inputs[0])
        else:
            comp = n.new("CompositorNodeComposite")
            l.new(gl.outputs[0], comp.inputs[0])
    except Exception as e:
        print("[MistVillage] compositor skipped:", e)

compositor()

# survey annotations (viewport only) — boundary polyline with dimension labels
def survey_overlay():
    pts = [(p[0], p[1], ground(*p) + 1.4) for p in BOUNDARY]
    cu = bpy.data.curves.new("SURVEY BOUNDARY (overlay)", "CURVE")
    cu.dimensions = "3D"
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts))
    for i, p in enumerate(pts + [pts[0]]):
        sp.points[i].co = (*p, 1)
    cu.bevel_depth = 0.05
    o = bpy.data.objects.new("SURVEY BOUNDARY (overlay)", cu)
    C_SITE.objects.link(o)
    o.hide_render = True
    for i in range(len(BOUNDARY)):
        a, b = BOUNDARY[i], BOUNDARY[(i + 1) % len(BOUNDARY)]
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        t = text_obj(f"SURVEY dim {BNAMES[i]}{BNAMES[(i+1)%7]}", f"{BNAMES[i]}–{BNAMES[(i+1)%7]}  {math.dist(a,b):.1f} m", 0.7,
                     MAT["title"], (mid[0], mid[1], ground(*mid) + 3.0), (0, 0, 0), 0.0, C_SITE)
        t.hide_render = True
    info = text_obj("SURVEY area", f"AREA ≈ {SITE_AREA:.0f} m²  ({SITE_AREA*10.7639:,.0f} sq.ft · {SITE_AREA/4046.86:.2f} acre)",
                    0.8, MAT["title"], (0, 26, 8), (0, 0, 0), 0.0, C_SITE)
    info.hide_render = True
    # empties naming the site sequence
    for label, p in (("ROAD (east)", (30, 0)), ("VALLEY + AGRICULTURE (outside property, west)", (-120, 0)),
                     ("NILGIRI RANGES", (-6000, 0))):
        e = bpy.data.objects.new(label, None)
        e.location = (p[0], p[1], ground(*p) + 5)
        e.empty_display_size = 3
        C_SITE.objects.link(e)

survey_overlay()

S.frame_set(1)
print("[MistVillage] build complete:", len(bpy.data.objects), "objects")

# optional save when run headless:  blender -b -P mist_village.py -- --save out.blend
if "--save" in sys.argv:
    path = sys.argv[sys.argv.index("--save") + 1]
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
    print("[MistVillage] saved", path)
