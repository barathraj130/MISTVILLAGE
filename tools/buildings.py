"""
Houses and buildings for The Mist Village towns at the resort's quality, in their own forms.

Round 2 (more realism, every plot joined to the road):
  * real textures at true scale with normal maps — the resort's own baked stone / plaster / timber /
    standing-seam / paving sets (godot/assets/models/textures) and the ambientCG sets already on disk
    (godot/assets/drive/tex); nothing downloaded
  * walls built around real openings: reveals, recessed glass, frames, mullions, sills, sunshades,
    and a room behind the glass (back wall, curtain, warm lamp light in some)
  * hollow parapets, overhangs, gutters, downpipes, wall lamps, AC units, water tanks, house numbers
  * hedges, flowering shrubs, layered trees, lawns
  * the street: asphalt road with edge and centre lines, kerb, raised stone pavement, streetlight;
    every plot has a paved driveway over a dropped kerb to its gate (or an open forecourt with
    parking bays for shops, apartments, hotels) and a stone path to the front door

    Blender -b --factory-startup --python tools/buildings.py -- <out_dir> [--board] [--street] [--blend file]

`build(kind, w, d, floors, seed)` makes one building with its plot (front facing −Y, building centred
on the origin, ground z = 0, kerb line at y = -d/2 - setback - 2.35) and returns (object, info).
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
TEX_R = os.path.join(HERE, "..", "godot", "assets", "models", "textures")
TEX_D = os.path.join(HERE, "..", "godot", "assets", "drive", "tex")
FLOOR = 3.15
PAVE_W = 2.2

# ----------------------------------------------------------------------------- materials
_M = {}


def _img(path, colour=True):
    if not os.path.exists(path):
        print("missing texture", path)
        return None
    im = bpy.data.images.load(path, check_existing=True)
    if not colour:
        im.colorspace_settings.name = "Non-Color"
    return im


def tex_mat(name, base, normal=None, rough=None, tile=2.0, rough_val=0.8, tint=None, metal=0.0, nstrength=0.8):
    """Image-textured material, box-projected in object metres (parts are transform-applied, so
    object space is world metres and the texture keeps its real size on every face)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    co = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1 / tile, 1 / tile, 1 / tile)
    nt.links.new(co.outputs["Object"], mp.inputs["Vector"])

    def tex(path, colour=True):
        im = _img(path, colour)
        if im is None:
            return None
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = im
        t.projection = 'BOX'
        t.projection_blend = 0.25
        nt.links.new(mp.outputs[0], t.inputs["Vector"])
        return t
    tb = tex(base)
    if tb:
        out = tb.outputs["Color"]
        if tint:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(out, mix.inputs[6])
            mix.inputs[7].default_value = (*tint, 1)
            out = mix.outputs[2]
        nt.links.new(out, p.inputs["Base Color"])
    elif tint:
        p.inputs["Base Color"].default_value = (*tint, 1)
    if normal:
        tn = tex(normal, False)
        if tn:
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = nstrength
            nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    tr = tex(rough, False) if rough else None
    if tr:
        nt.links.new(tr.outputs["Color"], p.inputs["Roughness"])
    else:
        p.inputs["Roughness"].default_value = rough_val
    p.inputs["Metallic"].default_value = metal
    return m


def plain(name, color, rough=0.6, metal=0.0, emit=None, strength=0.0, transmission=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if transmission:
        for n in ("Transmission Weight", "Transmission"):
            if n in p.inputs:
                p.inputs[n].default_value = transmission
                break
    if emit:
        for n in ("Emission Color", "Emission"):
            if n in p.inputs:
                p.inputs[n].default_value = (*emit, 1)
                break
        p.inputs["Emission Strength"].default_value = strength
    return m


def R(n):
    return os.path.join(TEX_R, n)


def D(n):
    return os.path.join(TEX_D, n)


def materials():
    if _M:
        return _M
    plaster = (D("plaster_color.jpg"), D("plaster_normal.jpg"), D("plaster_rough.jpg"))
    _M.update({
        "stone": tex_mat("Nilgiri Stone", R("dark_nilgiri_stone_base.jpg"), R("dark_nilgiri_stone_normal.png"), tile=2.5, rough_val=0.85, nstrength=1.2),
        "stone_wall": tex_mat("Retaining Stone", R("stone_retaining_wall_base.jpg"), R("stone_retaining_wall_normal.png"), tile=2.5, nstrength=1.2),
        "coping": tex_mat("Stone Coping", R("weathered_stone_coping_base.jpg"), R("weathered_stone_coping_normal.png"), tile=1.5),
        "plaster": tex_mat("Warm Plaster", R("warm_mineral_plaster_base.jpg"), R("warm_mineral_plaster_normal.png"), tile=3.0),
        "plaster_w": tex_mat("White Plaster", *plaster, tile=2.5, tint=(0.95, 0.93, 0.88)),
        "plaster_t": tex_mat("Terracotta Plaster", *plaster, tile=2.5, tint=(0.78, 0.45, 0.32)),
        "plaster_g": tex_mat("Sage Plaster", *plaster, tile=2.5, tint=(0.62, 0.68, 0.56)),
        "plaster_y": tex_mat("Ochre Plaster", *plaster, tile=2.5, tint=(0.9, 0.75, 0.48)),
        "timber": tex_mat("Warm Timber", R("warm_natural_timber_base.jpg"), R("warm_natural_timber_normal.png"), tile=1.2, rough_val=0.5),
        "timber_dk": tex_mat("Dark Timber", R("dark_timber_deck_base.jpg"), R("dark_timber_deck_normal.png"), tile=1.2, rough_val=0.45),
        "roof": tex_mat("Standing Seam", R("charcoal_standing_seam_roof_base.jpg"), R("charcoal_standing_seam_roof_normal.png"), tile=2.0, rough_val=0.35, metal=0.6),
        "roof_tin": tex_mat("Green Tin Roof", D("tin_roof_color.jpg"), D("tin_roof_normal.jpg"), D("tin_roof_rough.jpg"), tile=2.0, tint=(0.45, 0.62, 0.48), metal=0.5),
        "concrete": tex_mat("Concrete", D("concrete_color.jpg"), D("concrete_normal.jpg"), D("concrete_rough.jpg"), tile=3.0),
        "paving": tex_mat("Stone Paving", R("natural_stone_paving_base.jpg"), R("natural_stone_paving_normal.png"), R("natural_stone_paving_rough.jpg"), tile=2.5),
        "pavers": tex_mat("Pavers", R("parking_pavers_base.jpg"), R("parking_pavers_normal.png"), R("parking_pavers_rough.jpg"), tile=2.0),
        "flag": tex_mat("Flagstone", R("flagstone_path_base.jpg"), R("flagstone_path_normal.png"), R("flagstone_path_rough.jpg"), tile=2.0),
        "asphalt": tex_mat("Asphalt", D("asphalt_color.jpg"), D("asphalt_normal.jpg"), D("asphalt_rough.jpg"), tile=4.0, tint=(0.38, 0.38, 0.4)),
        "verge": tex_mat("Verge", D("grass_color.jpg"), D("grass_normal.jpg"), D("grass_rough.jpg"), tile=6.0, tint=(0.8, 0.85, 0.7)),
        "grass": tex_mat("Lawn", D("grass_color.jpg"), D("grass_normal.jpg"), D("grass_rough.jpg"), tile=3.0),
        "hedge": tex_mat("Hedge", R("hedgerow_base.jpg"), None, tile=1.0, rough_val=0.9),
        "shrub": tex_mat("Shrub", R("native_shrub_base.jpg"), None, tile=0.8, rough_val=0.9),
        "flowers": tex_mat("Hydrangea", R("hydrangea_base.jpg"), None, tile=0.6, rough_val=0.85),
        "flowers_p": tex_mat("Pink Hydrangea", R("hydrangea_pink_base.jpg"), None, tile=0.6, rough_val=0.85),
        "leaves": tex_mat("Tree Leaves", R("silver_oak_leaves_base.jpg"), None, tile=1.5, rough_val=0.85),
        "leaves_s": tex_mat("Shola Leaves", R("shola_evergreen_leaves_base.jpg"), None, tile=1.5, rough_val=0.85),
        "bark": tex_mat("Bark", R("tree_bark_base.jpg"), R("tree_bark_normal.png"), tile=1.0),
        "tile": plain("Clay Tile", (0.42, 0.14, 0.07), 0.7),
        "alu": plain("Black Aluminium", (0.015, 0.015, 0.016), 0.3, 0.85),
        "steel": plain("Black Steel", (0.01, 0.01, 0.011), 0.45, 0.6),
        "steel_lt": plain("Galvanised", (0.55, 0.56, 0.57), 0.35, 0.9),
        "glass": plain("Glass", (0.9, 0.93, 0.94), 0.02, transmission=1.0),
        "room": plain("Room Wall", (0.55, 0.45, 0.36), 0.9),
        "room_lit": plain("Room Lamp", (1, 0.9, 0.75), 0.5, emit=(1.0, 0.72, 0.42), strength=2.5),
        "curtain": plain("Curtain", (0.82, 0.74, 0.6), 0.95),
        "lamp": plain("Wall Lamp", (1, 0.95, 0.85), 0.4, emit=(1.0, 0.78, 0.5), strength=8.0),
        "kerb": plain("Kerb", (0.55, 0.54, 0.52), 0.8),
        "line": plain("Road Line", (0.85, 0.85, 0.8), 0.6),
        "sign": plain("Signboard", (0.04, 0.04, 0.045), 0.4),
        "brass": plain("Brass", (0.55, 0.38, 0.16), 0.3, 1.0),
        "fabric": plain("Awning", (0.08, 0.22, 0.2), 0.9),
        "white": plain("White", (0.85, 0.85, 0.83), 0.5),
        "water": plain("Black Tank", (0.03, 0.03, 0.035), 0.5),
        "pot": plain("Terracotta Pot", (0.5, 0.22, 0.12), 0.8),
    })
    return _M


# ----------------------------------------------------------------------------- primitives
_parts = []


def box(c, s, m, rz=0.0, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=c, rotation=(0, 0, rz))
    o = bpy.context.active_object
    o.scale = s
    o.data.materials.append(materials()[m])
    if bevel:
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        b = o.modifiers.new("Bevel", 'BEVEL')
        b.width = bevel
        b.segments = 2
    _parts.append(o)
    return o


def cyl(c, r, h, m, verts=16, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=c, rotation=rot)
    o = bpy.context.active_object
    o.data.materials.append(materials()[m])
    for p in o.data.polygons:
        p.use_smooth = True
    _parts.append(o)
    return o


def blob(c, r, m, sub=2, squash=1.0, noise=0.25, seed=0):
    """A leafy mass: an icosphere roughened by a cloud displacement so it doesn't read as a ball."""
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, subdivisions=sub, location=c)
    o = bpy.context.active_object
    o.scale = (1, 1, squash)
    t = bpy.data.textures.get("leafnoise") or bpy.data.textures.new("leafnoise", 'CLOUDS')
    t.noise_scale = 0.5
    dm = o.modifiers.new("Displace", 'DISPLACE')
    dm.texture = t
    dm.texture_coords = 'GLOBAL'
    dm.strength = r * noise
    o.data.materials.append(materials()[m])
    for p in o.data.polygons:
        p.use_smooth = True
    _parts.append(o)
    return o


def mesh(name, verts, faces, m):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(materials()[m])
    _parts.append(o)
    return o


def beam(p0, p1, wid, hgt, m):
    """A box from p0 to p1 (any direction), wid across, hgt thick."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    o = box((p0 + p1) / 2, (d.length, wid, hgt), m)
    o.rotation_euler = d.to_track_quat('X', 'Z').to_euler()
    return o


def parapet(w, d, z, h, m, t=0.22):
    """A hollow parapet round a flat roof, with a coping."""
    for s in (-1, 1):
        box((0, s * (d / 2 - t / 2), z + h / 2), (w, t, h), m)
        box((s * (w / 2 - t / 2), 0, z + h / 2), (t, d - 2 * t, h), m)
        box((0, s * (d / 2 - t / 2), z + h + 0.03), (w + 0.06, t + 0.08, 0.06), "coping")
        box((s * (w / 2 - t / 2), 0, z + h + 0.03), (t + 0.08, d, 0.06), "coping")


# ----------------------------------------------------------------------------- walls with real openings
def wall(face, a0, a1, z0, z1, depth, m, openings, t=0.25, lit=None, rng=None, frame="alu", shades=True):
    """A wall slab on one face of the volume with real holes for its openings.
    face: '-y' / '+y' (runs along x, outer face at y=depth) or '-x' / '+x' (runs along y at x=depth).
    openings: [(u_centre, z_bottom, width, height, kind)] kind: 'win' | 'door' | 'french' | 'shop'."""
    along_x = face in ("-y", "+y")
    out = -1.0 if face in ("-y", "-x") else 1.0

    def put(u0, u1, zz0, zz1):
        if u1 - u0 < 0.01 or zz1 - zz0 < 0.01:
            return
        cu, cz = (u0 + u1) / 2, (zz0 + zz1) / 2
        c = depth - out * t / 2
        if along_x:
            box((cu, c, cz), (u1 - u0, t, zz1 - zz0), m)
        else:
            box((c, cu, cz), (t, u1 - u0, zz1 - zz0), m)
    u = a0
    for (uc, zb, w, h, kind) in sorted(openings, key=lambda o: o[0]):
        put(u, uc - w / 2, z0, z1)
        put(uc - w / 2, uc + w / 2, z0, zb)
        put(uc - w / 2, uc + w / 2, zb + h, z1)
        u = uc + w / 2
        _fill(along_x, out, depth, uc, zb, w, h, kind, lit, rng, frame, shades)
    put(u, a1, z0, z1)


def _fill(along_x, out, depth, uc, zb, w, h, kind, lit, rng, frame, shades):
    def at(du, dz, dd):
        """a point on the opening: du along the wall, dz up from its bottom, dd outward from the face"""
        if along_x:
            return (uc + du, depth + out * dd, zb + dz)
        return (depth + out * dd, uc + du, zb + dz)

    def size(su, sz, sd):
        return (su, sd, sz) if along_x else (sd, su, sz)
    inset = 0.12
    is_lit = lit is not None and rng is not None and rng.random() < lit
    if kind != "door":
        box(at(0, h / 2, -inset), size(w, h, 0.02), "glass")
        fr = 0.06
        for s in (-1, 1):
            box(at(s * (w / 2 - fr / 2), h / 2, -inset + 0.02), size(fr, h, 0.08), frame)
        for zz in (fr / 2, h - fr / 2):
            box(at(0, zz, -inset + 0.02), size(w, fr, 0.08), frame)
        nm = max(1, int(w / 0.9))
        for k in range(1, nm):
            box(at(-w / 2 + w * k / nm, h / 2, -inset + 0.02), size(0.04, h, 0.07), frame)
        if kind == "win" and h > 1.2:
            box(at(0, h * 0.7, -inset + 0.02), size(w, 0.04, 0.07), frame)               # transom
        # the room behind: back and side walls, ceiling, a curtain drawn to one side
        rd = 1.8
        box(at(0, h / 2 + 0.2, -inset - rd), size(w + 1.0, h + 1.2, 0.05), "room_lit" if is_lit else "room")
        for s in (-1, 1):
            box(at(s * (w / 2 + 0.5), h / 2 + 0.2, -inset - rd / 2), size(0.05, h + 1.2, rd), "room")
        box(at(0, h + 0.4, -inset - rd / 2), size(w + 1.0, 0.05, rd), "room_lit" if is_lit else "room")
        box(at(0, -0.05, -inset - rd / 2), size(w + 1.0, 0.05, rd), "timber_dk")       # floor
        if kind != "shop":
            box(at(-w * 0.34, h / 2, -inset - 0.15), size(w * 0.26, h - 0.1, 0.04), "curtain")
    else:
        box(at(0, h / 2, -inset + 0.03), size(w, h, 0.06), "timber")
        for k in range(4):                                                                 # door panels
            box(at(0, 0.3 + k * (h - 0.4) / 4 + (h - 0.4) / 8, -inset + 0.065), size(w - 0.25, 0.04, 0.02), "timber_dk")
        box(at(w * 0.36, h * 0.47, -inset + 0.09), size(0.03, 0.2, 0.04), "brass")         # handle
    # reveals (the wall's thickness round the opening), sill, sunshade
    for s in (-1, 1):
        box(at(s * (w / 2 + 0.005), h / 2, -inset / 2), size(0.01, h, inset), "plaster_w")
    box(at(0, h + 0.005, -inset / 2), size(w, 0.01, inset), "plaster_w")
    if kind in ("win", "french"):
        box(at(0, -0.035, 0.05), size(w + 0.15, 0.07, 0.34), "coping")
        if shades and kind == "win":
            box(at(0, h + 0.22, 0.3), size(w + 0.45, 0.07, 0.62), "concrete")             # chajja


# ----------------------------------------------------------------------------- details
def railing(p0, p1, z, h=1.05, m="steel", glass_panel=False):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    L = d.length
    rz = math.atan2(d.y, d.x)
    mid = (p0 + p1) / 2
    box((mid.x, mid.y, z + h), (L, 0.06, 0.045), m, rz=rz)
    if glass_panel:
        box((mid.x, mid.y, z + h / 2), (L, 0.015, h - 0.1), "glass", rz=rz)
        n = max(int(L / 1.2), 1)
        for i in range(n + 1):
            q = p0 + d * (i / n)
            box((q.x, q.y, z + h / 2), (0.045, 0.045, h), m)
    else:
        n = max(int(L / 0.12), 2)
        for i in range(n + 1):
            q = p0 + d * (i / n)
            box((q.x, q.y, z + h / 2), (0.02, 0.02, h), m, rz=rz)
        box((mid.x, mid.y, z + 0.08), (L, 0.04, 0.03), m, rz=rz)


def downpipe(x, y, z_top):
    box((x, y, z_top / 2), (0.09, 0.09, z_top), "steel_lt")
    for k in range(int(z_top / 1.5)):
        box((x, y, 0.8 + k * 1.5), (0.12, 0.12, 0.04), "steel_lt")                      # clamps
    box((x, y, 0.08), (0.12, 0.12, 0.16), "steel_lt")


def wall_lamp(x, y, z, face=-1):
    box((x, y + face * 0.06, z), (0.14, 0.12, 0.24), "alu")
    box((x, y + face * 0.125, z - 0.04), (0.1, 0.01, 0.13), "lamp")


def ac_unit(x, y, z, face=-1):
    box((x, y + face * 0.2, z), (0.82, 0.3, 0.56), "white", bevel=0.02)
    cyl((x + 0.15, y + face * 0.36, z), 0.19, 0.02, "steel", 20, rot=(math.pi / 2, 0, 0))
    box((x, y + face * 0.14, z - 0.32), (0.5, 0.26, 0.04), "steel")


def tree(x, y, h=6.0, seed=0, leaf="leaves"):
    rng = random.Random(seed)
    cyl((x, y, h * 0.32), 0.14, h * 0.64, "bark", 10)
    for k in range(3):                                                                    # main limbs
        a = rng.random() * math.tau
        beam((x, y, h * 0.45), (x + math.cos(a) * h * 0.18, y + math.sin(a) * h * 0.18, h * 0.7), 0.1, 0.1, "bark")
    for k in range(9):
        a = rng.random() * math.tau
        r = h * rng.uniform(0.13, 0.2)
        rr = h * rng.uniform(0.05, 0.17)
        blob((x + math.cos(a) * rr, y + math.sin(a) * rr, h * rng.uniform(0.58, 0.9)), r, leaf, 3, 0.75, 0.5, seed * 7 + k)


def hedge(p0, p1, h=1.1, w=0.7):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    if d.length < 0.5:
        return
    o = box(((p0 + p1) / 2).to_tuple() if False else ((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, h / 2),
            (d.length, w, h), "hedge", rz=math.atan2(d.y, d.x))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    sd = o.modifiers.new("Sub", 'SUBSURF')
    sd.levels = 2
    dm = o.modifiers.new("Displace", 'DISPLACE')
    dm.texture = bpy.data.textures.get("leafnoise") or bpy.data.textures.new("leafnoise", 'CLOUDS')
    dm.texture_coords = 'GLOBAL'
    dm.strength = 0.12
    _ = o


def shrubs(x, y, n=4, spread=1.2, seed=0, flowers=True):
    rng = random.Random(seed)
    for k in range(n):
        m = rng.choice(["flowers", "flowers_p"]) if (flowers and k % 2 == 0) else "shrub"
        blob((x + rng.uniform(-spread, spread), y + rng.uniform(-spread * 0.4, spread * 0.4), 0.3),
             rng.uniform(0.35, 0.55), m, 2, 0.75, 0.3, seed * 13 + k)


def planter(x, y, w=0.9):
    box((x, y, 0.3), (w, 0.55, 0.6), "concrete", bevel=0.02)
    blob((x - w * 0.2, y, 0.75), 0.33, "shrub", 2, 0.85, 0.3)
    blob((x + w * 0.2, y, 0.72), 0.28, "flowers", 2, 0.85, 0.3)


# ----------------------------------------------------------------------------- the plot and the street
def plot(w, d, setback, gate_x=0.0, gate_w=3.4, walled=True, wall_m="stone_wall", side=2.5, drive_w=3.2, drive_in=0.0):
    """Lawn, compound wall with gate pillars and a slatted gate, a paved driveway from the house to the
    road across the pavement on a dropped kerb with ramps, the road, a streetlight. Returns kerb y."""
    front = -d / 2 - setback                    # property line
    pave = front - PAVE_W                       # road side of the pavement
    kerb = pave - 0.15                          # road edge
    W = w / 2 + side
    box((0, (front + d / 2 + 4) / 2, -0.03), (2 * W, d + setback + 4, 0.06), "grass")
    if walled:
        h = 1.4
        for (a, b) in [((-W, front), (gate_x - gate_w / 2 - 0.5, front)), ((gate_x + gate_w / 2 + 0.5, front), (W, front)),
                       ((W, front), (W, d / 2 + 2)), ((-W, front), (-W, d / 2 + 2))]:
            a, b = Vector(a), Vector(b)
            if (b - a).length < 0.2:
                continue
            mid, L = (a + b) / 2, (b - a).length
            rz = math.atan2(b.y - a.y, b.x - a.x)
            box((mid.x, mid.y, h / 2), (L, 0.28, h), wall_m, rz=rz)
            box((mid.x, mid.y, h + 0.04), (L + 0.04, 0.38, 0.08), "coping", rz=rz)
        for s in (-1, 1):
            px = gate_x + s * (gate_w / 2 + 0.25)
            box((px, front, 0.95), (0.5, 0.5, 1.9), "stone")
            box((px, front, 1.95), (0.62, 0.62, 0.1), "coping")
            box((px, front, 2.12), (0.22, 0.22, 0.25), "lamp")
        for i in range(int(gate_w / 0.12)):                                               # slatted gate
            box((gate_x - gate_w / 2 + 0.06 + i * 0.12, front, 0.85), (0.07, 0.04, 1.5), "steel")
        for zz in (0.12, 1.55):
            box((gate_x, front, zz), (gate_w, 0.05, 0.05), "steel")
        box((gate_x + gate_w / 2 + 0.25, front - 0.26, 1.35), (0.3, 0.02, 0.2), "brass")  # house number
        hedge((-W + 0.6, front + 0.75), (gate_x - gate_w / 2 - 0.9, front + 0.75))
        hedge((gate_x + gate_w / 2 + 0.9, front + 0.75), (W - 0.6, front + 0.75))
    # driveway: house → gate → across the pavement (dropped kerb) → road
    dl = setback + drive_in
    box((gate_x, front + dl / 2, 0.005), (drive_w, dl, 0.03), "pavers")
    cw = drive_w + 0.8
    box((gate_x, (front + kerb) / 2, 0.01), (cw, front - kerb, 0.04), "pavers")
    L = 2 * W + 6
    for s in (-1, 1):
        rx = gate_x + s * cw / 2                     # where the crossing meets the pavement
        x0 = rx + s * 0.7                            # full pavement height from here on
        x1 = s * L / 2
        cx, lw = (x0 + x1) / 2, abs(x1 - x0)
        if s * (x1 - x0) > 0:
            box((cx, (front + pave) / 2, 0.075), (lw, front - pave, 0.15), "paving")
            box((cx, kerb + 0.075, 0.075), (lw, 0.15, 0.18), "kerb")
        mesh("KerbRamp", [(rx, kerb, 0.03), (x0, kerb, 0.15), (x0, front, 0.15), (rx, front, 0.03)],
             [(0, 1, 2, 3) if s > 0 else (3, 2, 1, 0)], "paving")
        mesh("KerbRampFace", [(rx, kerb, 0.0), (x0, kerb, 0.0), (x0, kerb, 0.15), (rx, kerb, 0.03)],
             [(0, 1, 2, 3) if s > 0 else (3, 2, 1, 0)], "kerb")
    box((0, kerb - 4.0, -0.02), (L, 8.0, 0.04), "asphalt")
    box((0, kerb - 0.3, 0.0), (L, 0.12, 0.02), "line")                                    # edge line
    for k in range(int(L / 6)):                                                           # dashed centre line
        box((-L / 2 + 1.5 + k * 6, kerb - 4.0, 0.0), (3.0, 0.12, 0.02), "line")
    sx = (W - 1.2) * (1 if gate_x <= 0 else -1)                                           # streetlight
    cyl((sx, pave + 0.45, 4.0), 0.075, 8.0, "steel", 12)
    box((sx, pave + 0.45, 0.3), (0.3, 0.3, 0.6), "concrete")
    box((sx, pave - 0.35, 7.95), (0.12, 1.6, 0.1), "steel")
    box((sx, pave - 1.05, 7.86), (0.36, 0.5, 0.08), "alu")
    box((sx, pave - 1.05, 7.81), (0.3, 0.42, 0.02), "lamp")
    return kerb


# ----------------------------------------------------------------------------- typologies
def city_house(w, d, floors, rng):
    H = floors * FLOOR
    body = rng.choice(["plaster_w", "plaster", "plaster_g"])
    front = -d / 2
    # ground floor in stone, set back 0.6 for a shaded entrance under the floor above
    gf = [(-w / 4, 0.0, 1.1, 2.3, "door"), (w / 5, 0.85, 2.0, 1.5, "win")]
    wall("-y", -w / 2, w / 2, 0, FLOOR, front + 0.6, "stone", gf, lit=0.6, rng=rng, shades=False)
    for face, x in (("-x", -w / 2), ("+x", w / 2)):
        wall(face, front + 0.6, d / 2, 0, FLOOR, x, "stone", [(0.5, 0.9, 1.3, 1.4, "win")], lit=0.3, rng=rng, shades=False)
    wall("+y", -w / 2, w / 2, 0, FLOOR, d / 2, "stone", [(0, 0.9, 1.4, 1.4, "win")])
    for f in range(1, floors):
        z0, z1 = f * FLOOR, (f + 1) * FLOOR
        box((0, 0, z0 + 0.0), (w + 0.3, d + 0.3, 0.2), "concrete")                         # floor band
        ops = [(-w * 0.18, z0 + 0.16, 2.2, 2.3, "french"), (w * 0.28, z0 + 0.9, 1.4, 1.4, "win")]
        wall("-y", -w / 2, w / 2, z0 + 0.1, z1, front, body, ops, lit=0.4, rng=rng)
        for face, x in (("-x", -w / 2), ("+x", w / 2)):
            wall(face, front, d / 2, z0 + 0.1, z1, x, body, [(-d / 6, z0 + 0.9, 1.2, 1.3, "win"), (d / 4, z0 + 0.9, 1.0, 1.3, "win")],
                 lit=0.3, rng=rng)
        wall("+y", -w / 2, w / 2, z0 + 0.1, z1, d / 2, body, [(0, z0 + 0.9, 1.6, 1.3, "win")])
        # cantilevered balcony: slab, timber soffit, glass rail; timber louvre fin at the corner
        box((-w * 0.08, front - 0.65, z0 + 0.06), (w * 0.72, 1.3, 0.16), "concrete")
        box((-w * 0.08, front - 0.65, z0 - 0.03), (w * 0.7, 1.25, 0.03), "timber")
        railing((-w * 0.44, front - 1.27), (w * 0.28, front - 1.27), z0 + 0.14, glass_panel=True)
        for i in range(5):
            box((w * 0.5 - 0.06, front - 0.1 - i * 0.12, z0 + FLOOR / 2), (0.05, 0.08, FLOOR - 0.2), "timber")
        ac_unit(w * 0.35, d / 2, z0 + 0.6, face=1)
    # roof: overhanging slab edge, hollow parapet, paved terrace, pergola, tank
    box((0, 0, H + 0.1), (w + 0.8, d + 0.8, 0.2), "concrete")
    parapet(w + 0.5, d + 0.5, H + 0.2, 0.9, body)
    box((0, 0, H + 0.21), (w, d, 0.02), "paving")
    for x in (-w / 4, w / 4):
        for y in (-d / 4, d / 4):
            box((x, y, H + 1.4), (0.14, 0.14, 2.4), "timber_dk")
    for y in (-d / 4, d / 4):
        box((0, y, H + 2.55), (w / 2 + 0.6, 0.12, 0.2), "timber_dk")
    for i in range(12):
        box((-w / 4 - 0.3 + i * (w / 2 + 0.6) / 11, 0, H + 2.72), (0.06, d / 2 + 0.6, 0.14), "timber")
    cyl((w * 0.32, d * 0.3, H + 1.0), 0.6, 1.2, "water", 24)
    box((w * 0.32, d * 0.3, H + 0.3), (1.4, 1.4, 0.2), "concrete")
    downpipe(w / 2 + 0.05, -d / 2 + 0.2, H)
    downpipe(-w / 2 - 0.05, d / 2 - 0.2, H)
    wall_lamp(-w / 4 + 0.95, front + 0.6, 2.3)
    box((-w / 4, front + 0.1, 2.75), (2.4, 1.6, 0.14), "concrete")                         # entrance canopy
    for k in range(2):
        box((-w / 4, front - 0.1 - k * 0.32, 0.075 + k * -0.0), (1.8, 0.32, 0.15 - k * 0.07), "coping")
    # car porch beside the house, a planter bed along the porch
    box((w / 2 + 1.75, -d / 4, 2.9), (3.5, d / 2 + 1.4, 0.16), "concrete")
    box((w / 2 + 1.75, -d / 4, 2.8), (3.4, d / 2 + 1.3, 0.04), "timber")
    for y in (-d / 2 - 0.4, 0.4):
        box((w / 2 + 3.35, y, 1.4), (0.16, 0.16, 2.8), "steel")
    return {"gate_x": w / 2 + 1.75, "setback": 4.0, "side": 4.5, "door_x": -w / 4, "drive_in": d / 2}


def apartment(w, d, floors, rng):
    H = floors * FLOOR
    body = rng.choice(["plaster_w", "plaster", "plaster_y"])
    bays = max(2, int(w / 4.6))
    bw = w / bays
    front = -d / 2
    gf = [(-w / 2 + bw * (b + 0.5), 0.0, bw - 0.9, 2.7, "shop") for b in range(bays)]
    wall("-y", -w / 2, w / 2, 0, FLOOR, front, "stone", gf, lit=0.8, rng=rng, shades=False)
    for face, x in (("-x", -w / 2), ("+x", w / 2)):
        wall(face, front, d / 2, 0, FLOOR, x, "stone", [(-d / 4, 0.9, 1.4, 1.4, "win")], lit=0.4, rng=rng, shades=False)
    wall("+y", -w / 2, w / 2, 0, FLOOR, d / 2, "stone", [])
    for f in range(1, floors):
        z0, z1 = f * FLOOR, (f + 1) * FLOOR
        ops = []
        for b in range(bays):
            x = -w / 2 + bw * (b + 0.5)
            ops += [(x - bw * 0.14, z0 + 0.16, bw * 0.42, 2.3, "french"), (x + bw * 0.3, z0 + 0.9, bw * 0.22, 1.4, "win")]
        wall("-y", -w / 2, w / 2, z0, z1, front, body, ops, lit=0.3, rng=rng, shades=False)
        for face, x in (("-x", -w / 2), ("+x", w / 2)):
            wall(face, front, d / 2, z0, z1, x, body, [(-d / 4, z0 + 0.9, 1.2, 1.3, "win"), (d / 4, z0 + 0.9, 1.2, 1.3, "win")],
                 lit=0.3, rng=rng)
        wall("+y", -w / 2, w / 2, z0, z1, d / 2, body, [(0, z0 + 0.9, 1.4, 1.3, "win")])
        box((0, front - 0.7, z0 + 0.07), (w + 0.2, 1.4, 0.16), "concrete")
        box((0, front - 0.7, z0 - 0.02), (w + 0.1, 1.35, 0.03), "timber")
        for b in range(bays):
            x = -w / 2 + bw * (b + 0.5)
            railing((x - bw / 2 + 0.2, front - 1.36), (x + bw / 2 - 0.2, front - 1.36), z0 + 0.15, glass_panel=True)
            box((x + bw / 2, front - 0.7, z0 + FLOOR / 2 + 0.07), (0.16, 1.4, FLOOR - 0.14), "timber")
            if (b + f) % 2 == 0:
                ac_unit(x + bw * 0.36, front - 0.15, z0 + 0.55)
            for k in range(3):                                                           # balcony pots
                if rng.random() < 0.5:
                    cyl((x - bw * 0.35 + k * 0.4, front - 1.15, z0 + 0.32), 0.15, 0.3, "pot", 12)
                    blob((x - bw * 0.35 + k * 0.4, front - 1.15, z0 + 0.6), 0.2, "shrub", 1, 1.0, 0.3)
    box((0, front - 1.4, 3.0), (w + 0.6, 2.8, 0.18), "concrete")                            # street canopy
    for b in range(bays + 1):
        box((-w / 2 + bw * b, front - 2.65, 1.45), (0.2, 0.2, 2.9), "steel")
    box((0, 0, H + 0.12), (w + 0.6, d + 0.6, 0.24), "concrete")
    parapet(w + 0.4, d + 0.4, H + 0.24, 0.9, body)
    box((0, 0, H + 0.25), (w, d, 0.02), "concrete")
    # glazed stair tower
    tx = w / 2 + 1.4
    wall("-y", tx - 1.4, tx + 1.4, 0, H + 1.4, -0.8, "stone", [(tx, 0.0, 2.0, 2.4, "door")] +
         [(tx, FLOOR * f - 0.9, 2.0, 2.4, "shop") for f in range(1, floors)], lit=0.9, rng=rng, shades=False)
    for face, x in (("-x", tx - 1.4), ("+x", tx + 1.4)):
        wall(face, -0.8, 2.4, 0, H + 1.4, x, "stone", [])
    wall("+y", tx - 1.4, tx + 1.4, 0, H + 1.4, 2.4, "stone", [])
    box((tx, 0.8, H + 1.45), (3.0, 3.4, 0.12), "concrete")
    box((-w / 4, 0, H + 1.6), (3.2, 2.6, 1.3), "concrete")                                  # plant room
    for i in range(13):
        box((-w / 4 - 1.6 + i * 0.27, -1.33, H + 1.6), (0.1, 0.05, 1.3), "timber")
    for b in range(bays + 1):
        downpipe(-w / 2 + bw * b + (0.15 if b == 0 else -0.15), d / 2 + 0.06, H)
    return {"gate_x": 0.0, "setback": 6.5, "side": 4.0, "walled": False, "forecourt": True, "drive_w": 6.0}


def shop_house(w, d, floors, rng):
    H = floors * FLOOR
    body = rng.choice(["plaster_t", "plaster_y", "plaster_w"])
    front = -d / 2
    wall("-y", -w / 2, w / 2, 0, FLOOR, front, "stone", [(0, 0.0, w - 1.0, 2.75, "shop")], lit=1.0, rng=rng, shades=False)
    for face, x in (("-x", -w / 2), ("+x", w / 2)):
        wall(face, front, d / 2, 0, FLOOR, x, "stone", [])
    wall("+y", -w / 2, w / 2, 0, FLOOR, d / 2, "stone", [(0, 0, 1.0, 2.2, "door")])
    # the shop inside: shelves along the back wall of the room, a counter
    for k in range(3):
        box((0, front + 1.75, 0.5 + k * 0.7), (w - 1.6, 0.4, 0.04), "timber")
    box((w * 0.25, front + 1.0, 0.5), (1.6, 0.6, 1.0), "timber_dk")
    n = max(2, int(w / 2.5))
    for f in range(1, floors):
        z0, z1 = f * FLOOR, (f + 1) * FLOOR
        ops = [(-w / 2 + w / n * (k + 0.5), z0 + 0.25, 1.1, 2.1, "french") for k in range(n)]
        wall("-y", -w / 2, w / 2, z0, z1, front, body, ops, lit=0.4, rng=rng, frame="timber_dk")
        for face, x in (("-x", -w / 2), ("+x", w / 2)):
            wall(face, front, d / 2, z0, z1, x, body, [(0, z0 + 0.9, 1.0, 1.3, "win")], lit=0.3, rng=rng)
        wall("+y", -w / 2, w / 2, z0, z1, d / 2, body, [(0, z0 + 0.9, 1.2, 1.3, "win")])
        for k in range(n):
            x = -w / 2 + w / n * (k + 0.5)
            for s in (-1, 1):
                box((x + s * 0.82, front - 0.04, z0 + 1.3), (0.5, 0.05, 2.1), "timber")       # open shutters
                for j in range(8):
                    box((x + s * 0.82, front - 0.075, z0 + 0.4 + j * 0.24), (0.44, 0.02, 0.05), "timber_dk")
            box((x, front - 0.32, z0 + 0.2), (1.5, 0.64, 0.1), "concrete")
            railing((x - 0.72, front - 0.6), (x + 0.72, front - 0.6), z0 + 0.25, h=0.95)
        box((0, front - 0.06, z0 - 0.1), (w + 0.1, 0.2, 0.2), "coping")
    # awning on steel brackets, signboard with a brass name strip, lamps
    box((0, front - 0.65, 2.98), (w + 0.2, 1.3, 0.04), "fabric")
    box((0, front - 1.29, 2.86), (w + 0.2, 0.03, 0.26), "fabric")
    for s in (-1, 0, 1):
        beam((s * (w / 2 - 0.2), front, 2.6), (s * (w / 2 - 0.2), front - 1.25, 2.95), 0.04, 0.04, "steel")
    box((0, front - 0.1, 3.35), (w * 0.8, 0.12, 0.5), "sign")
    box((0, front - 0.17, 3.35), (w * 0.55, 0.02, 0.16), "brass")
    for s in (-1, 1):
        wall_lamp(s * (w / 2 - 0.3), front, 3.35)
    box((0, 0, H + 0.1), (w + 0.4, d + 0.4, 0.2), "concrete")
    parapet(w + 0.2, d + 0.2, H + 0.2, 0.7, body)
    box((0, front - 0.1, H + 0.94), (w + 0.3, 0.3, 0.06), "coping")
    cyl((-w / 4, d / 4, H + 0.9), 0.55, 1.1, "water", 24)
    downpipe(w / 2 + 0.05, front + 0.1, H)
    return {"gate_x": 0.0, "setback": 3.0, "side": 1.5, "walled": False, "forecourt": True, "drive_w": w - 0.5}


def hill_cottage(w, d, floors, rng):
    fl = min(floors, 2)
    H = fl * FLOOR
    front = -d / 2
    wall("-y", -w / 2, w / 2, 0, H, front, "stone", [(0, 0.0, w * 0.6, H - 0.2, "french")], lit=1.0, rng=rng,
         frame="timber_dk", shades=False)
    for face, x in (("-x", -w / 2), ("+x", w / 2)):
        ops = [(-d / 5, 0.9, 1.2, 1.4, "win")] + ([(d / 5, FLOOR + 0.6, 1.0, 1.2, "win")] if fl > 1 else [])
        wall(face, front, d / 2, 0, H, x, "stone", ops, lit=0.5, rng=rng, frame="timber_dk", shades=False)
    wall("+y", -w / 2, w / 2, 0, H, d / 2, "stone", [(0, 0, 1.0, 2.2, "door")])
    roof_m = rng.choice(["roof", "roof_tin"])
    ov = 0.6
    pitch = 0.8
    ridge = H + (w / 2 + 0.5) * pitch
    x_e = w / 2 + ov
    z_e = H - ov * pitch + 0.1
    slope = (ridge - z_e) / x_e

    def z_at(x):
        return ridge - slope * abs(x)
    y0, y1 = front - 0.7, d / 2 + 0.7
    for s in (-1, 1):
        q = [(0, y0, ridge), (s * x_e, y0, z_e), (s * x_e, y1, z_e), (0, y1, ridge)]
        mesh("Roof", q, [(0, 1, 2, 3)], roof_m)
        mesh("Soffit", [(a, b, c - 0.04) for (a, b, c) in q], [(3, 2, 1, 0)], "timber")
        for y in (y0, y1):
            beam((0, y, ridge + 0.05), (s * x_e, y, z_e + 0.05), 0.06, 0.24, "timber")     # bargeboards
        box((s * (x_e - 0.05), (y0 + y1) / 2, z_e - 0.02), (0.14, y1 - y0, 0.12), "steel_lt")  # gutter
        downpipe(s * (x_e - 0.05), front - 0.6, z_e)
        box((s * (w / 2 - 0.15), 0, H + 0.1), (0.3, d, 0.25), "timber_dk")                  # wall plate
    box((0, (y0 + y1) / 2, ridge + 0.06), (0.25, y1 - y0, 0.1), "steel")                    # ridge cap
    ze = z_at(w / 2)
    mesh("Gable", [(-w / 2, front - 0.01, H), (w / 2, front - 0.01, H), (w / 2, front - 0.01, ze), (0, front - 0.01, ridge),
                   (-w / 2, front - 0.01, ze)], [(0, 1, 2, 3, 4)], "timber")
    for i in range(int(w / 0.18)):                                                          # board battens
        x = -w / 2 + 0.09 + i * 0.18
        zt = z_at(x) - 0.05
        if zt > H + 0.1:
            box((x, front - 0.03, (H + zt) / 2), (0.03, 0.03, zt - H), "timber_dk")
    mesh("GableGlass", [(-w * 0.3, front - 0.06, H + 0.15), (w * 0.3, front - 0.06, H + 0.15), (0, front - 0.06, ridge - 0.6)],
         [(0, 1, 2)], "glass")
    mesh("GableRoom", [(-w * 0.3, front + 1.4, H + 0.15), (w * 0.3, front + 1.4, H + 0.15), (0, front + 1.4, ridge - 0.6)],
         [(0, 1, 2)], "room_lit")
    mesh("GableBack", [(-w / 2, d / 2 + 0.01, H), (-w / 2, d / 2 + 0.01, ze), (0, d / 2 + 0.01, ridge), (w / 2, d / 2 + 0.01, ze),
                       (w / 2, d / 2 + 0.01, H)], [(0, 1, 2, 3, 4)], "stone")
    box((0, front - 0.06, H + 0.02), (w + 0.1, 0.18, 0.26), "timber_dk")                    # tie beam
    # deck on stone piers, steel rail, two steps, lantern
    box((0, front - 1.5, 0.45), (w + 1.2, 3.0, 0.1), "timber_dk")
    for x in (-w / 2 - 0.4, 0, w / 2 + 0.4):
        box((x, front - 2.8, 0.2), (0.35, 0.35, 0.4), "stone")
    railing((-w / 2 - 0.6, front - 2.95), (w / 2 - 0.6, front - 2.95), 0.5)
    railing((-w / 2 - 0.6, front - 2.95), (-w / 2 - 0.6, front), 0.5)
    for k in range(2):
        top = 0.45 - 0.15 * (k + 1)
        box((w / 2 + 0.05, front - 3.15 - k * 0.3, top / 2), (1.1, 0.3, top), "stone")
    for k in range(2):                                                                      # deck chairs
        x = -w / 4 + k * 1.2
        box((x, front - 1.6, 0.72), (0.6, 0.6, 0.06), "timber")
        beam((x, front - 1.3, 0.72), (x, front - 1.15, 1.25), 0.6, 0.05, "timber")
    wall_lamp(w / 2 - 0.4, front, 2.3)
    cx = w * 0.28
    box((cx, d / 4, z_at(cx) + 0.7), (0.75, 0.75, 2.8), "stone")                            # chimney
    box((cx, d / 4, z_at(cx) + 2.15), (0.9, 0.9, 0.1), "coping")
    return {"gate_x": w / 2 + 0.6, "setback": 5.5, "side": 3.5, "wall_m": "stone_wall", "drive_w": 2.4,
            "door_x": w / 2 + 0.05, "door_y": -3.45}


def bungalow(w, d, floors, rng):
    H = FLOOR * (1 if floors < 3 else 2)
    body = rng.choice(["plaster_w", "plaster_y", "plaster_t"])
    pl = 0.6
    box((0, 0, pl / 2), (w + 1.4, d + 1.4, pl), "stone")                                    # plinth
    box((0, 0, pl + 0.02), (w + 1.3, d + 1.3, 0.04), "paving")
    front = -d / 2 + 1.4                                                                     # walls behind the veranda
    wins = [(s * (k * w / 6 + 0.9), pl + 0.6, 1.1, 1.6, "win") for s in (-1, 1) for k in (1, 2)]
    wall("-y", -w / 2, w / 2, pl, pl + H, front, body, [(0, pl, 1.4, 2.4, "door")] + wins, lit=0.5, rng=rng,
         frame="timber_dk", shades=False)
    for face, x in (("-x", -w / 2), ("+x", w / 2)):
        wall(face, front, d / 2, pl, pl + H, x, body, [(1.0, pl + 0.6, 1.1, 1.6, "win")], lit=0.4, rng=rng, frame="timber_dk", shades=False)
    wall("+y", -w / 2, w / 2, pl, pl + H, d / 2, body, [(0, pl, 1.0, 2.2, "door")])
    for (uc, zb, ww, hh, kind) in wins:                                                     # louvred shutters
        for s in (-1, 1):
            box((uc + s * (ww / 2 + 0.27), front - 0.04, zb + hh / 2), (0.5, 0.04, hh), "timber")
            for j in range(int(hh / 0.12)):
                box((uc + s * (ww / 2 + 0.27), front - 0.07, zb + 0.1 + j * 0.12), (0.44, 0.02, 0.04), "timber_dk")
    n = max(3, int(w / 2.2))
    for k in range(n + 1):                                                                   # veranda pillars
        x = -w / 2 + 0.3 + (w - 0.6) * k / n
        cyl((x, -d / 2 + 0.25, pl + H / 2), 0.15, H, "white", 24)
        box((x, -d / 2 + 0.25, pl + 0.1), (0.42, 0.42, 0.2), "coping")
        box((x, -d / 2 + 0.25, pl + H - 0.1), (0.42, 0.42, 0.2), "coping")
    box((0, -d / 2 + 0.25, pl + H + 0.12), (w + 0.6, 0.45, 0.25), "timber_dk")
    box((0, (-d / 2 + front) / 2, pl + H + 0.02), (w, front + d / 2, 0.05), "timber")          # veranda ceiling
    for k in range(2):                                                                       # swing seat + pots
        cyl((-w / 2 + 0.8 + k * (w - 1.6), -d / 2 + 0.6, pl + 0.25), 0.22, 0.5, "pot", 14)
        blob((-w / 2 + 0.8 + k * (w - 1.6), -d / 2 + 0.6, pl + 0.75), 0.35, "flowers_p", 2, 0.9, 0.3)
    box((w / 4, front - 0.6, pl + 0.45), (1.6, 0.5, 0.06), "timber")
    for s in (-1, 1):
        box((w / 4 + s * 0.75, front - 0.6, pl + 0.22), (0.06, 0.45, 0.44), "timber_dk")
    for k in range(4):
        box((0, -d / 2 - 0.85 - k * 0.32, (pl - 0.15 * k) / 2), (2.6, 0.32, pl - 0.15 * k), "coping")   # steps
    # hipped clay-tile roof: overhang, fascia, tile courses following the slope
    top = pl + H + 0.25
    a, b = w / 2 + 0.9, d / 2 + 0.9
    r = max(a - b, 0.3)
    rh = b * 0.75
    mesh("HipRoof", [(-a, -b, top), (a, -b, top), (a, b, top), (-a, b, top), (-r, 0, top + rh), (r, 0, top + rh)],
         [(0, 1, 5, 4), (1, 2, 5), (2, 3, 4, 5), (3, 0, 4)], "tile")
    mesh("HipSoffit", [(-a, -b, top - 0.02), (a, -b, top - 0.02), (a, b, top - 0.02), (-a, b, top - 0.02)], [(3, 2, 1, 0)], "timber")
    Ls = math.hypot(b, rh)
    for sy in (-1, 1):
        for i in range(int(2 * a / 0.22)):
            x = -a + 0.11 + i * 0.22
            f = 1.0 if abs(x) <= r else max((a - abs(x)) / (a - r), 0.0)
            if f < 0.05:
                continue
            p0 = Vector((x, sy * b, top + 0.04))
            p1 = Vector((x, sy * b * (1 - f), top + rh * f + 0.04))
            beam(p0, p1, 0.06, 0.05, "tile")
        for k in range(1, 9):                                                                # tile courses
            f = k / 9
            half = a - (a - r) * f
            box((0, sy * b * (1 - f), top + rh * f + 0.03), (2 * half, 0.05, 0.04), "tile")
    _ = Ls
    for s in (-1, 1):
        box((0, s * b, top - 0.06), (2 * a + 0.1, 0.06, 0.22), "timber_dk")
        box((s * a, 0, top - 0.06), (0.06, 2 * b, 0.22), "timber_dk")
    wall_lamp(-0.95, front, pl + 2.3)
    wall_lamp(0.95, front, pl + 2.3)
    return {"gate_x": 0.0, "setback": 6.0, "side": 3.5, "wall_m": "plaster_w", "drive_w": 2.6, "door_y": -2.1}


def hotel(w, d, floors, rng):
    H = floors * FLOOR
    front = -d / 2
    wall("-y", -w / 2, w / 2, 0, FLOOR, front, "stone", [(0, 0, w * 0.55, 2.8, "shop")], lit=1.0, rng=rng, shades=False)
    for face, x in (("-x", -w / 2), ("+x", w / 2)):
        wall(face, front, d / 2, 0, FLOOR, x, "stone", [(-d / 4, 0.9, 1.6, 1.4, "win")], lit=0.6, rng=rng, shades=False)
    wall("+y", -w / 2, w / 2, 0, FLOOR, d / 2, "stone", [])
    # the lobby: reception desk, a pendant cluster
    box((0, front + 1.3, 0.55), (3.0, 0.7, 1.1), "timber_dk")
    for k in range(5):
        box((-1.2 + k * 0.6, front + 1.0, 2.4 - (k % 2) * 0.3), (0.18, 0.18, 0.25), "lamp")
    cols = max(3, int(w / 3.3))
    cw = w / cols
    for f in range(1, floors):
        z0, z1 = f * FLOOR, (f + 1) * FLOOR
        ops = [(-w / 2 + cw * (c + 0.5) - cw * 0.08, z0 + 0.25, cw * 0.62, 2.3, "french") for c in range(cols)]
        wall("-y", -w / 2, w / 2, z0, z1, front, "plaster_w", ops, lit=0.35, rng=rng, shades=False)
        for face, x in (("-x", -w / 2), ("+x", w / 2)):
            wall(face, front, d / 2, z0, z1, x, "plaster_w", [(-d / 4, z0 + 0.9, 1.4, 1.4, "win"), (d / 4, z0 + 0.9, 1.4, 1.4, "win")],
                 lit=0.3, rng=rng, shades=False)
        wall("+y", -w / 2, w / 2, z0, z1, d / 2, "plaster_w", [(0, z0 + 0.9, 1.4, 1.4, "win")])
        for c in range(cols):
            x = -w / 2 + cw * (c + 0.5)
            for i in range(6):                                                               # timber screens
                box((x + cw * 0.3 - 0.22 + i * 0.09, front - 0.35, z0 + 1.4), (0.05, 0.06, 2.4), "timber")
            box((x - cw * 0.08, front - 0.25, z0 + 0.2), (cw * 0.7, 0.5, 0.08), "concrete")
            railing((x - cw * 0.43, front - 0.48), (x + cw * 0.27, front - 0.48), z0 + 0.24, glass_panel=True)
        box((0, front - 0.25, z0 - 0.1), (w + 0.5, 0.5, 0.3), "plaster_w")                     # floor frames
    for c in range(cols + 1):
        box((-w / 2 + cw * c, front - 0.25, FLOOR + (H - FLOOR) / 2), (0.32, 0.5, H - FLOOR), "plaster_w")
    # porte-cochère reaching out over the drop-off lane
    box((0, front - 2.6, 3.3), (w * 0.5, 5.2, 0.28), "timber_dk")
    box((0, front - 2.6, 3.47), (w * 0.5 + 0.1, 5.3, 0.06), "steel")
    for s in (-1, 1):
        box((s * w * 0.22, front - 4.9, 1.65), (0.34, 0.34, 3.3), "stone")
    for k in range(6):
        box((-w * 0.2 + k * w * 0.08, front - 2.6, 3.15), (0.25, 0.25, 0.04), "lamp")
    box((0, front - 0.12, 3.8), (w * 0.4, 0.12, 0.6), "sign")
    box((0, front - 0.19, 3.8), (w * 0.3, 0.02, 0.22), "brass")
    box((0, 0, H + 0.12), (w + 0.6, d + 0.6, 0.24), "concrete")
    parapet(w + 0.4, d + 0.4, H + 0.24, 1.0, "plaster_w")
    for i in range(int(w / 0.8)):
        box((-w / 2 + 0.5 + i * 0.8, 0, H + 3.2), (0.08, d * 0.6, 0.18), "timber")
    for x in (-w / 2 + 0.6, w / 2 - 0.6):
        for y in (-d * 0.28, d * 0.28):
            box((x, y, H + 2.1), (0.18, 0.18, 2.2), "steel")
    for x in (-w / 2 + 0.6, w / 2 - 0.6):
        box((x, 0, H + 3.05), (0.14, d * 0.6, 0.14), "steel")
    return {"gate_x": 0.0, "setback": 9.0, "side": 4.0, "walled": False, "forecourt": True, "drive_w": w * 0.5}


BUILD = {"city_house": city_house, "apartment": apartment, "shop_house": shop_house,
         "hill_cottage": hill_cottage, "bungalow": bungalow, "hotel": hotel}


def build(kind, w, d, floors, seed=0, with_plot=True):
    global _parts
    _parts = []
    rng = random.Random(seed)
    info = BUILD[kind](w, d, floors, rng) or {}
    sb = info.get("setback", 4.0)
    if with_plot:
        gx = info.get("gate_x", 0.0)
        plot(w, d, sb, gate_x=gx, walled=info.get("walled", True), wall_m=info.get("wall_m", "stone_wall"),
             side=info.get("side", 2.5), drive_w=info.get("drive_w", 3.2), drive_in=info.get("drive_in", 0.0))
        front = -d / 2
        if info.get("walled", True):
            # a stone path from the driveway to the front door, with planting along it
            dx = info.get("door_x", 0.0)
            dy = front + info.get("door_y", -0.2)
            py = front - sb * 0.5
            if abs(gx - dx) > 0.5:
                box(((dx + gx) / 2, py, 0.012), (abs(gx - dx), 1.2, 0.03), "flag")
            if dy > py:
                box((dx, (py + dy) / 2, 0.012), (1.2, dy - py + 1.2, 0.03), "flag")
            shrubs(-w / 2 - 0.6, front - 0.9, 5, 1.0, seed)
            shrubs(w / 2 - 1.0, py - 1.2, 3, 0.6, seed + 3) if gx < w / 2 else None
            tree(-w / 2 - 1.8, front - sb + 1.6, rng.uniform(5.5, 7.5), seed, rng.choice(["leaves", "leaves_s"]))
        if info.get("forecourt"):
            box((0, front - sb / 2, 0.012), (w + 2.0, sb, 0.03), "pavers")
            nb = int((w + 1.0) / 2.6)
            for k in range(nb + 1):                                                         # parking bay lines
                x = -(nb * 2.6) / 2 + k * 2.6
                box((x, front - sb * 0.55, 0.03), (0.08, min(sb - 1.5, 5.0), 0.01), "line")
            for x in (-w / 2 - 1.6, w / 2 + 1.6):
                planter(x, front - 0.8, 1.2)
                tree(x, front - sb + 1.0, rng.uniform(5.5, 7.0), seed + int(x), "leaves_s")
    for o in _parts:
        if o.modifiers:
            bpy.context.view_layer.objects.active = o
            for m in list(o.modifiers):
                try:
                    bpy.ops.object.modifier_apply(modifier=m.name)
                except RuntimeError:
                    o.modifiers.remove(m)
    bpy.ops.object.select_all(action='DESELECT')
    for o in _parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = _parts[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = kind
    info["kerb_y"] = -d / 2 - sb - PAVE_W - 0.15
    return ob, info


# ----------------------------------------------------------------------------- game export
# Each exported building is one mesh with two materials, "Kit" and "KitGlass". Its vertex colour
# carries the look: RGB = tint, A = layer / 255, where the layer picks a texture in the game's
# building shader (godot/shaders/building_kit.gdshader, same order and tile sizes as below).
KIT_LAYERS = {"Nilgiri Stone": 1, "Retaining Stone": 2, "Stone Coping": 3, "Warm Plaster": 4,
              "White Plaster": 5, "Terracotta Plaster": 5, "Sage Plaster": 5, "Ochre Plaster": 5,
              "Warm Timber": 6, "Dark Timber": 7, "Standing Seam": 8, "Green Tin Roof": 9, "Concrete": 10,
              "Stone Paving": 11, "Pavers": 12, "Flagstone": 13}
KIT_TINTS = {"White Plaster": (0.95, 0.93, 0.88), "Terracotta Plaster": (0.78, 0.45, 0.32),
             "Sage Plaster": (0.62, 0.68, 0.56), "Ochre Plaster": (0.9, 0.75, 0.48), "Green Tin Roof": (0.45, 0.62, 0.48)}
GREENS = ("Hedge", "Shrub", "Hydrangea", "Pink Hydrangea", "Tree Leaves", "Shola Leaves")
VARIANTS = [("city_house", 8, 10, f) for f in (2, 3, 4)] + [("city_house", 12, 14, f) for f in (2, 3, 4)] + \
           [("apartment", 12, 12, f) for f in (4, 5, 6)] + [("apartment", 20, 15, f) for f in (4, 5, 6)] + \
           [("shop_house", 6, 10, f) for f in (2, 3, 4)] + [("shop_house", 10, 14, f) for f in (2, 3, 4)] + \
           [("hill_cottage", 7, 9, f) for f in (1, 2)] + [("hill_cottage", 10, 12, f) for f in (1, 2)] + \
           [("bungalow", 10, 9, 1), ("bungalow", 15, 12, 1)] + \
           [("hotel", 16, 13, f) for f in (4, 5)] + [("hotel", 24, 16, f) for f in (4, 5)]


def kit_code(m):
    n = m.name.split(".")[0]
    if n == "Glass":
        return None
    if n in KIT_LAYERS:
        return (*KIT_TINTS.get(n, (1.0, 1.0, 1.0)), KIT_LAYERS[n] / 255.0)
    if n == "Room Lamp":
        return (1.0, 0.9, 0.75, 100 / 255.0)
    if n in ("Wall Lamp",):
        return (1.0, 0.95, 0.85, 101 / 255.0)
    if n in GREENS:
        return (0.18, 0.3, 0.12, 0.0)
    if n == "Bark":
        return (0.25, 0.18, 0.12, 0.0)
    p = m.node_tree.nodes.get("Principled BSDF")
    c = tuple(p.inputs["Base Color"].default_value)[:3]
    return (*c, (14 if p.inputs["Metallic"].default_value > 0.5 else 0) / 255.0)


def kit_encode(ob):
    """Bake each face's material into the vertex colour and leave two materials: Kit, KitGlass."""
    me = ob.data
    codes = [kit_code(m) for m in me.materials]
    col = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
    vals = [0.0] * (len(me.loops) * 4)
    mi = []
    for p in me.polygons:
        c = codes[p.material_index]
        mi.append(1 if c is None else 0)
        c = c or (1.0, 1.0, 1.0, 0.0)
        for li in p.loop_indices:
            vals[li * 4:li * 4 + 4] = c
    col.data.foreach_set("color", vals)
    me.color_attributes.active_color = col
    me.materials.clear()
    me.materials.append(bpy.data.materials.get("Kit") or bpy.data.materials.new("Kit"))
    me.materials.append(bpy.data.materials.get("KitGlass") or bpy.data.materials.new("KitGlass"))
    me.polygons.foreach_set("material_index", mi)
    me.update()


def export_kit(out_dir, only=None):
    import json
    os.makedirs(out_dir, exist_ok=True)
    man_path = os.path.join(out_dir, "manifest.json")
    manifest = json.load(open(man_path)) if os.path.exists(man_path) else {}
    for kind, w, d, fl in VARIANTS:
        name = "%s_%dx%d_%d" % (kind, w, d, fl)
        if only and kind not in only and name not in only:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        _M.clear()
        global _parts
        _parts = []
        rng = random.Random(hash(name) & 0xffff)
        info = BUILD[kind](w, d, fl, rng) or {}
        box((0, 0, -0.6), (w + 0.1, d + 0.1, 1.2), "stone")                 # plinth into sloping ground
        for o in _parts:
            if o.modifiers:
                bpy.context.view_layer.objects.active = o
                for m in list(o.modifiers):
                    try:
                        bpy.ops.object.modifier_apply(modifier=m.name)
                    except RuntimeError:
                        o.modifiers.remove(m)
        bpy.ops.object.select_all(action='DESELECT')
        for o in _parts:
            o.select_set(True)
        bpy.context.view_layer.objects.active = _parts[0]
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active
        ob.name = name
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.remove_doubles(threshold=0.0005)
        bpy.ops.object.mode_set(mode='OBJECT')
        kit_encode(ob)
        xs = [v.co.x for v in ob.data.vertices]
        ys = [v.co.y for v in ob.data.vertices]
        zs = [v.co.z for v in ob.data.vertices]
        kw = dict(filepath=os.path.join(out_dir, name + ".glb"), export_format='GLB', use_selection=True,
                  export_apply=True, export_yup=True, export_materials='EXPORT')
        for k, v in (("export_vertex_color", 'ACTIVE'), ("export_image_format", 'NONE')):
            kw[k] = v
        try:
            bpy.ops.export_scene.gltf(**kw)
        except TypeError:
            kw.pop("export_image_format", None)
            bpy.ops.export_scene.gltf(**kw)
        manifest[name] = {"kind": kind, "w": w, "d": d, "floors": fl,
                          "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)],
                          "door_x": info.get("door_x", info.get("gate_x", 0.0)), "tris": sum(len(p.vertices) - 2 for p in ob.data.polygons)}
        print("KIT", name, manifest[name]["tris"], "tris", flush=True)
        json.dump(manifest, open(man_path, "w"), indent=1)


# ----------------------------------------------------------------------------- rendering
SPECS = [("city_house", 10, 12, 3, 1), ("apartment", 16, 13, 5, 2), ("shop_house", 8, 12, 3, 3),
         ("hill_cottage", 8, 10, 2, 4), ("bungalow", 12, 10, 1, 5), ("hotel", 18, 14, 4, 6)]


def scene_setup(samples=40, res=(1440, 900)):
    sc = bpy.context.scene
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.2
    sun.data.color = (1.0, 0.86, 0.7)
    sun.data.angle = math.radians(1.0)
    sun.rotation_euler = (math.radians(64), 0, math.radians(-42))
    sc.collection.objects.link(sun)
    sc.world = bpy.data.worlds.new("Sky")
    sc.world.use_nodes = True
    wn = sc.world.node_tree
    sky = wn.nodes.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_elevation = math.radians(26)
    sky.sun_rotation = math.radians(-132)
    sky.sun_disc = False
    wn.links.new(sky.outputs[0], wn.nodes["Background"].inputs[0])
    wn.nodes["Background"].inputs[1].default_value = 0.25
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for dv in prefs.devices:
            dv.use = True
        sc.cycles.device = 'GPU'
    except Exception as e:
        print("GPU unavailable", e)
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.view_settings.exposure = -0.35
    sc.render.image_settings.file_format = 'JPEG'
    sc.render.image_settings.quality = 90
    try:
        sc.view_settings.view_transform = 'AgX'
        sc.view_settings.look = 'AgX - Medium High Contrast'
    except TypeError:
        pass
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


VEH = os.path.join(HERE, "..", "godot", "assets", "vehicles")
PEOPLE = os.path.join(HERE, "..", "godot", "assets", "people")


def place_glb(path, loc, rz):
    if not os.path.exists(path):
        return None
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    root = bpy.data.objects.new("Prop " + os.path.basename(path), None)
    bpy.context.collection.objects.link(root)
    for o in bpy.data.objects:
        if o not in before and o is not root and o.parent is None:
            o.parent = root
    root.location = loc
    root.rotation_euler = (0, 0, rz)
    return root


def ground(x0, x1, ky):
    """The world round the plots: verge, the road carrying on both ways, the far kerb and pavement."""
    global _parts
    _parts = []
    cx, L = (x0 + x1) / 2, (x1 - x0) + 400
    box((cx, ky + 60, -0.09), (L, 520, 0.1), "verge")
    box((cx, ky - 4.0, -0.035), (L, 8.0, 0.04), "asphalt")
    box((cx, ky - 8.075, 0.075), (L, 0.15, 0.18), "kerb")
    box((cx, ky - 9.25, 0.075), (L, 2.2, 0.15), "paving")
    # a tree line behind the plots and in front across the road
    rng = random.Random(7)
    x = x0 - 30
    while x < x1 + 30:
        tree(x, ky + rng.uniform(34, 48), rng.uniform(8, 13), int(x * 3) % 997, rng.choice(["leaves", "leaves_s"]))
        x += rng.uniform(6, 11)
    # Nilgiri hills: a forested ridge rising behind the town
    y0 = ky + 140
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=160, y_subdivisions=70, size=1, location=(cx, y0 + 300, 0))
    g = bpy.context.active_object
    g.scale = (1600, 600, 1)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    vg = g.vertex_groups.new(name="rise")
    for v in g.data.vertices:
        vg.add([v.index], min(max((v.co.y + 300) / 260, 0.0), 1.0) ** 1.5, 'REPLACE')
    t = bpy.data.textures.new("hills", 'CLOUDS')
    t.noise_scale = 2.6
    dm = g.modifiers.new("Hills", 'DISPLACE')
    dm.texture = t
    dm.texture_coords = 'LOCAL'
    dm.strength = 130
    dm.mid_level = 0.25
    dm.vertex_group = "rise"
    g.modifiers.new("Smooth", 'SUBSURF').levels = 1
    g.data.materials.append(materials()["leaves_s"])
    for p_ in g.data.polygons:
        p_.use_smooth = True
    _parts.append(g)
    bpy.ops.object.select_all(action='DESELECT')
    for o in _parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = _parts[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)   # textures at true size
    return _parts


def dress(info, ox, ky, kind, seed):
    """Cars and people that show how the plot is used: a car on the driveway or in the bays, traffic on
    the road keeping left, someone on the pavement."""
    rng = random.Random(seed)
    fp = ky + PAVE_W + 0.15                         # property line
    sb = info.get("setback", 4.0)
    cars = ["fleet_hatchback", "fleet_sedan", "luxury_suv", "coupe"]
    if info.get("walled", True):
        y = fp + sb * 0.5 + (2.8 if info.get("drive_in") else 0.6)
        place_glb(os.path.join(VEH, rng.choice(cars) + ".glb"), (ox + info.get("gate_x", 0.0), y, 0.03), math.pi / 2)
    elif sb >= 6:
        for k in range(2):
            x = ox + (-1 + 2 * k) * 2.6 * (1 + k)
            place_glb(os.path.join(VEH, rng.choice(cars) + ".glb"), (x, fp + 2.6, 0.03), math.pi / 2)
    else:
        place_glb(os.path.join(VEH, "fleet_auto.glb"), (ox - 2.0, ky - 1.2, 0.0), 0.0)
    place_glb(os.path.join(VEH, rng.choice(cars) + ".glb"), (ox + rng.uniform(-9, -4), ky - 2.0, 0.0), 0.0)
    place_glb(os.path.join(VEH, rng.choice(["fleet_auto", "fleet_sedan", "fleet_hatchback"]) + ".glb"),
              (ox + rng.uniform(14, 20), ky - 6.0, 0.0), math.pi)
    who = ["man_shirt", "woman_saree", "woman_kurta", "elder", "schoolkid", "man_lungi"]
    for k in range(2):
        place_glb(os.path.join(PEOPLE, "person_%s.glb" % rng.choice(who)),
                  (ox + rng.uniform(-6, 6), ky + 0.5 + rng.uniform(0.2, 1.6), 0.15), rng.uniform(0, math.tau))


def aim(cam, loc, target, lens=28):
    cam.location = loc
    cam.data.lens = lens
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()


def board(out_dir, only=None):
    os.makedirs(out_dir, exist_ok=True)
    for kind, w, d, fl, seed in SPECS:
        if only and kind not in only:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        _M.clear()
        cam = scene_setup()
        ob, info = build(kind, w, d, fl, seed)
        size = max(w, d) + fl * 1.5
        ky = info["kerb_y"]
        ground(-30, 30, ky)
        dress(info, 0.0, ky, kind, seed)
        aim(cam, (size * 0.75, ky - size * 0.75 - 2, 1.7 + size * 0.2), (0, ky * 0.4, fl * FLOOR * 0.42), 24)
        bpy.context.scene.render.filepath = os.path.join(out_dir, "design_%s.jpg" % kind)
        bpy.ops.render.render(write_still=True)
        print("BOARD", kind, flush=True)


def street(out_dir, blend=None):
    """All six on one street, side by side, every plot meeting the same kerb line (y = 0)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _M.clear()
    cam = scene_setup(48, (1920, 1000))
    x = 0.0
    for kind, w, d, fl, seed in SPECS:
        col = bpy.data.collections.new(kind)
        bpy.context.scene.collection.children.link(col)
        bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection.children[kind]
        ob, info = build(kind, w, d, fl, seed)
        half = w / 2 + info.get("side", 2.5) + 0.3
        x += half
        ob.location = (x, -info["kerb_y"], 0)
        dress(info, x, 0.0, kind, seed)
        x += half
    bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection
    ground(0, x, 0.0)
    aim(cam, (x * 0.5, -x * 0.36, x * 0.13), (x * 0.5, 12, 4), 24)
    if blend:
        bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
        print("SAVED", blend, flush=True)
    if out_dir:
        bpy.context.scene.render.filepath = os.path.join(out_dir, "design_street.jpg")
        bpy.ops.render.render(write_still=True)
        print("STREET", flush=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = os.path.abspath(args[0]) if args and not args[0].startswith("--") else os.path.abspath("previews/buildings")
    blend = os.path.abspath(args[args.index("--blend") + 1]) if "--blend" in args else None
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    if "--export" in args:
        export_kit(os.path.abspath(args[args.index("--export") + 1]), only)
    if "--street" in args or blend:
        street(out if "--street" in args else None, blend)
    if "--board" in args:
        board(out, only)
