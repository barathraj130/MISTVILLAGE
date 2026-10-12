"""
Coimbatore street buildings for the city (round 3), on top of tools/buildings.py (same primitives,
materials, plots and game-kit export).

What makes them read as Kovai and not as generic boxes:
  * tn_house      — the common RCC house: pastel paint, plinth, a grilled sit-out (portico) with square
                    columns, MS window grills under concrete chajjas, an open RCC staircase up the side,
                    a stair-head room (mumty) on the terrace with a black water tank, spouts through the
                    parapet, a clothes line, tulsi madam, kolam at the gate, EB meter box
  * commercial    — the main-road row building: a run of shops behind a raised plinth and steps,
                    rolling shutters (open, half, shut), each shop with its own signboard (fictional
                    names), a continuous sunshade, grilled offices above with AC units, flex banners,
                    tanks and a hoarding frame on the roof, blank weathered party walls at the sides
  * mill_shed     — the textile mill / godown: whitewashed walls, high grilled windows, a sawtooth
                    roof of cement sheets with north-light glazing, a big rolling gate, a two-storey
                    office in front with the mill's name
  * weathering on every painted wall: rain streaks, a darker splash band at the foot, faded patches

    Blender -b --python tools/buildings_tn.py -- <out_dir> [--street] [--board] [--export godot/assets/buildings]
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import buildings as B  # noqa: E402
from buildings import box, cyl, wall, railing, downpipe, ac_unit, parapet, mesh, beam, blob, FLOOR  # noqa: E402

FONT_DIR = "/System/Library/Fonts/Supplemental"
PASTELS = {"pink": ("Pink Plaster", (0.95, 0.52, 0.58)), "mint": ("Mint Plaster", (0.5, 0.82, 0.58)),
           "sky": ("Sky Plaster", (0.48, 0.7, 0.92)), "lavender": ("Lavender Plaster", (0.7, 0.58, 0.88)),
           "cream": ("Cream Plaster", (0.95, 0.82, 0.55)), "lemon": ("Lemon Plaster", (0.95, 0.85, 0.3)),
           "peach": ("Peach Plaster", (0.96, 0.64, 0.42)), "white_wash": ("Whitewash", (0.9, 0.89, 0.85))}
SIGN_COLOURS = {"sign_red": (0.55, 0.04, 0.03), "sign_blue": (0.03, 0.12, 0.42), "sign_yellow": (0.85, 0.62, 0.04),
                "sign_green": (0.02, 0.3, 0.1), "sign_maroon": (0.3, 0.02, 0.06), "sign_orange": (0.8, 0.28, 0.02)}
SHOPS = ["SRI VELAN STORES", "KOVAI SILKS", "MANI MEDICALS", "RAJA BAKERY", "SELVAM HARDWARES",
         "THENDRAL MOBILES", "ARUN OPTICALS", "MEENA FANCY STORE", "KAVIN ELECTRICALS", "SARAVANA TEA STALL",
         "PRIYA TAILORS", "VETRI AUTO SPARES", "MUTHU FOOTWEAR", "NILA SWEETS", "GURU XEROX", "ANBU RICE MANDI"]
ADS = ["ADMISSION OPEN", "AADI SALE 50% OFF", "NEW ARRIVALS", "TUITION CENTRE", "TO-LET", "COMPUTER CLASSES"]
MILLS = ["KOVAI VELAN SPINNERS", "NOYYAL TEXTILE MILLS", "SIRUVANI COTTON WORKS", "PERUR WEAVING MILLS"]
_BASE_MATS = B.materials


def materials():
    M = _BASE_MATS()
    if "pink" in M:
        return M
    plaster = (B.D("plaster_color.jpg"), B.D("plaster_normal.jpg"), B.D("plaster_rough.jpg"))
    for key, (name, tint) in PASTELS.items():
        M[key] = B.tex_mat(name, *plaster, tile=2.5, tint=tint)
    M["ac_sheet"] = B.tex_mat("AC Sheet", B.D("tin_roof_color.jpg"), B.D("tin_roof_normal.jpg"), B.D("tin_roof_rough.jpg"),
                              tile=1.6, tint=(0.66, 0.66, 0.64))
    for key, c in SIGN_COLOURS.items():
        M[key] = B.plain(key.replace("_", " ").title(), c, 0.45)
    M.update({
        "sign_white": B.plain("Sign White", (0.92, 0.92, 0.9), 0.4),
        "grill_g": B.plain("Grill Green", (0.04, 0.2, 0.12), 0.45, 0.3),
        "grill_b": B.plain("Grill Blue", (0.05, 0.12, 0.3), 0.45, 0.3),
        "grill_k": B.plain("Grill Brown", (0.16, 0.07, 0.03), 0.45, 0.3),
        "granite": B.plain("Granite", (0.1, 0.09, 0.09), 0.25),
        "kolam": B.plain("Kolam", (0.95, 0.95, 0.93), 0.9),
        "acp": B.plain("ACP Panel", (0.62, 0.64, 0.66), 0.3, 0.6),
        "shutter": B.plain("Shutter", (0.42, 0.43, 0.44), 0.4, 0.8),
        "cable": B.plain("Cable", (0.02, 0.02, 0.02), 0.6),
        "cloth1": B.plain("Washing Red", (0.6, 0.08, 0.1), 0.9),
        "cloth2": B.plain("Washing Blue", (0.1, 0.25, 0.55), 0.9),
        "goods": B.plain("Goods", (0.55, 0.4, 0.25), 0.8),
    })
    for k in list(PASTELS) + ["plaster_w", "plaster", "plaster_t", "plaster_y", "plaster_g", "concrete", "ac_sheet"]:
        weather(M[k], 0.6 if k == "concrete" else 1.0)
    return M


B.materials = materials
for _name, _tint in PASTELS.values():
    B.KIT_LAYERS[_name] = 5
    B.KIT_TINTS[_name] = _tint
B.KIT_LAYERS["AC Sheet"] = 9
B.KIT_TINTS["AC Sheet"] = (0.66, 0.66, 0.64)


def weather(m, amount=1.0):
    """Rain streaks, a splash band at the foot of the wall, faded patches (object space = world metres)."""
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    links = p.inputs["Base Color"].links
    src = links[0].from_socket if links else None
    co = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(co.outputs["Object"], sep.inputs[0])
    foot = nt.nodes.new("ShaderNodeMapRange")
    nt.links.new(sep.outputs["Z"], foot.inputs["Value"])
    foot.inputs["From Min"].default_value = 0.0
    foot.inputs["From Max"].default_value = 1.1
    foot.inputs["To Min"].default_value = 1.0 - 0.38 * amount
    foot.inputs["To Max"].default_value = 1.0
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (3.5, 3.5, 0.16)
    nt.links.new(co.outputs["Object"], mp.inputs["Vector"])
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 2.2
    nz.inputs["Detail"].default_value = 4.0
    nt.links.new(mp.outputs[0], nz.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.48
    ramp.color_ramp.elements[0].color = (1, 1, 1, 1)
    ramp.color_ramp.elements[1].position = 0.78
    g = 1.0 - 0.32 * amount
    ramp.color_ramp.elements[1].color = (g, g * 0.98, g * 0.95, 1)
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    nz2 = nt.nodes.new("ShaderNodeTexNoise")
    nz2.inputs["Scale"].default_value = 0.35
    nt.links.new(co.outputs["Object"], nz2.inputs["Vector"])
    patch = nt.nodes.new("ShaderNodeMapRange")
    nt.links.new(nz2.outputs["Fac"], patch.inputs["Value"])
    patch.inputs["From Min"].default_value = 0.35
    patch.inputs["From Max"].default_value = 0.7
    patch.inputs["To Min"].default_value = 1.0 - 0.14 * amount
    patch.inputs["To Max"].default_value = 1.04
    m1 = nt.nodes.new("ShaderNodeMath")
    m1.operation = "MULTIPLY"
    nt.links.new(foot.outputs[0], m1.inputs[0])
    nt.links.new(patch.outputs[0], m1.inputs[1])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    if src:
        nt.links.new(src, mix.inputs[6])
    else:
        mix.inputs[6].default_value = p.inputs["Base Color"].default_value
    nt.links.new(ramp.outputs["Color"], mix.inputs[7])
    mix2 = nt.nodes.new("ShaderNodeMix")
    mix2.data_type = "RGBA"
    mix2.blend_type = "MULTIPLY"
    mix2.inputs["Factor"].default_value = 1.0
    nt.links.new(mix.outputs[2], mix2.inputs[6])
    nt.links.new(m1.outputs[0], mix2.inputs[7])
    nt.links.new(mix2.outputs[2], p.inputs["Base Color"])


# ----------------------------------------------------------------------------- details
def grill(face, uc, zb, w, h, depth, m, gap=0.13):
    """MS window grill a few cm proud of the wall: vertical rods and three flat bars."""
    along_x = face in ("-y", "+y")
    out = -1.0 if face in ("-y", "-x") else 1.0
    dd = depth + out * 0.05

    def P(u, z):
        return (u, dd, z) if along_x else (dd, u, z)

    def S(su, sz):
        return (su, 0.022, sz) if along_x else (0.022, su, sz)
    n = max(2, int(w / gap))
    for k in range(n + 1):
        box(P(uc - w / 2 + w * k / n, zb + h / 2), S(0.016, h), m)
    for z in (zb + 0.02, zb + h * 0.5, zb + h - 0.02):
        box(P(uc, z), S(w + 0.04, 0.035), m)


def text(txt, x, y, z, size, m, width=None, face=-1, font="Arial Black"):
    """A signboard's lettering as mesh, standing on the plane y (facing −y when face < 0)."""
    path = os.path.join(FONT_DIR, font + ".ttf")
    f = bpy.data.fonts.load(path, check_existing=True)
    bpy.ops.object.text_add(location=(x, y, z), rotation=(math.pi / 2, 0, 0 if face < 0 else math.pi))
    o = bpy.context.active_object
    o.data.body = txt
    o.data.font = f
    o.data.size = size
    o.data.align_x = 'CENTER'
    o.data.align_y = 'CENTER'
    o.data.extrude = 0.006
    o.data.resolution_u = 2
    bpy.context.view_layer.update()
    if width and o.dimensions.x > width:
        o.scale = (width / o.dimensions.x, 1, 1)
    bpy.ops.object.convert(target='MESH')
    o.data.materials.clear()
    o.data.materials.append(materials()[m])
    B._parts.append(o)
    return o


def signboard(x, y, z, w, h, txt, rng, face=-1):
    bg = rng.choice(list(SIGN_COLOURS))
    box((x, y, z), (w, 0.08, h), bg)
    box((x, y + face * 0.045, z + h / 2 - 0.04), (w, 0.01, 0.05), "sign_white")
    box((x, y + face * 0.045, z - h / 2 + 0.04), (w, 0.01, 0.05), "sign_white")
    text(txt, x, y + face * 0.05, z, h * 0.48, "sign_white" if bg != "sign_yellow" else "sign_maroon", width=w * 0.9, face=face)


def shutter(x, y, zb, w, h, state, face=-1):
    """Rolling shutter: a ribbed curtain down to `state` (0 open … 1 shut) and its housing."""
    box((x, y + face * 0.18, zb + h + 0.18), (w + 0.2, 0.36, 0.36), "shutter")
    down = h * state
    if down < 0.05:
        return
    box((x, y + face * 0.06, zb + h - down / 2), (w, 0.02, down), "shutter")
    k = 0
    while k * 0.12 < down:
        box((x, y + face * 0.075, zb + h - 0.06 - k * 0.12), (w, 0.012, 0.03), "steel_lt")
        k += 1
    if state > 0.95:
        box((x, y + face * 0.09, zb + 0.08), (w, 0.03, 0.08), "steel")
        box((x - w * 0.2, y + face * 0.1, zb + 0.12), (0.12, 0.04, 0.1), "brass")              # padlock


def tank(x, y, z, r=0.62, h=1.15):
    """A black plastic water tank on the roof with its ribs and lid."""
    cyl((x, y, z + h / 2), r, h, "water", 24)
    for k in range(3):
        cyl((x, y, z + 0.25 + k * 0.33), r + 0.02, 0.05, "water", 24)
    cyl((x, y, z + h + 0.05), r * 0.35, 0.1, "water", 16)
    beam((x + r, y, z + 0.2), (x + r + 0.6, y, z - 0.3), 0.04, 0.04, "steel_lt")


def mumty(x, y, z, w, d, body, door_face=-1, rng=None):
    """Stair-head room on the terrace with its door, slab and the tank on top."""
    h = 2.5
    for s in (-1, 1):
        box((x, y + s * (d / 2 - 0.1), z + h / 2), (w, 0.2, h), body)
        box((x + s * (w / 2 - 0.1), y, z + h / 2), (0.2, d - 0.4, h), body)
    box((x, y + door_face * (d / 2 + 0.01), z + 1.05), (0.9, 0.06, 2.1), "timber_dk")
    box((x, y, z + h + 0.07), (w + 0.4, d + 0.4, 0.14), "concrete")
    box((x, y + door_face * (d / 2 + 0.3), z + 2.25), (1.3, 0.6, 0.07), "concrete")             # chajja over door
    tank(x - w * 0.15, y + d * 0.1, z + h + 0.14)


def clothes_line(x0, x1, y, z, rng):
    for x in (x0, x1):
        box((x, y, z + 0.85), (0.04, 0.04, 1.7), "steel_lt")
    box(((x0 + x1) / 2, y, z + 1.65), (x1 - x0, 0.008, 0.008), "cable")
    for k in range(rng.randint(2, 5)):
        cx = x0 + 0.4 + rng.random() * (x1 - x0 - 0.8)
        box((cx, y, z + 1.35), (rng.uniform(0.4, 0.9), 0.01, rng.uniform(0.4, 0.7)), rng.choice(["cloth1", "cloth2", "kolam"]))


def kolam(x, y, r=0.9):
    """Rice-flour kolam at the gate: a dot grid ringed by loops, lying on the ground."""
    for i in range(-3, 4):
        for j in range(-3, 4):
            if abs(i) + abs(j) <= 4:
                box((x + i * r / 4, y + j * r / 4, 0.022), (0.05, 0.05, 0.005), "kolam")
    n = 24
    for k in range(n):
        a = k / n * math.tau
        box((x + math.cos(a) * r, y + math.sin(a) * r, 0.022), (0.03, r * math.tau / n, 0.005), "kolam", rz=a)


def tulsi(x, y):
    box((x, y, 0.35), (0.5, 0.5, 0.7), "plaster_t")
    box((x, y, 0.72), (0.6, 0.6, 0.05), "concrete")
    blob((x, y, 0.95), 0.22, "shrub", 2, 1.2, 0.4)


def meter_box(x, y, z, face=-1):
    box((x, y + face * 0.08, z), (0.45, 0.16, 0.55), "grill_k")
    box((x, y + face * 0.165, z + 0.05), (0.2, 0.01, 0.15), "glass")
    box((x + 0.1, y + face * 0.05, z + 1.2), (0.03, 0.03, 2.0), "cable")


# ----------------------------------------------------------------------------- typologies
def tn_house(w, d, floors, rng):
    fl = max(1, min(floors, 3))
    H = fl * FLOOR
    pl = 0.45
    body = rng.choice(list(PASTELS)[:7])
    gm = rng.choice(["grill_g", "grill_b", "grill_k"])
    front = -d / 2
    so_w = min(w * 0.55, 4.8)                       # sit-out on the left of the front
    sx0, sx1 = -w / 2, -w / 2 + so_w
    fw = front + 2.0                                # house wall behind the sit-out
    box((0, 0, pl / 2), (w + 0.2, d + 0.2, pl), "concrete")
    box((0, front - 0.06, pl / 2), (w + 0.25, 0.1, pl), "granite")                         # plinth facing
    for k in range(3):                                                                       # steps into the sit-out
        box(((sx0 + sx1) / 2, front - 0.3 - k * 0.28, pl - 0.15 * (k + 1) + 0.075), (1.6, 0.28, 0.15), "granite")
    # ground floor
    gz0, gz1 = pl, pl + FLOOR
    wall("-y", sx0, sx1, gz0, gz1, fw, body, [((sx0 + sx1) / 2 + 0.6, gz0, 1.05, 2.15, "door"),
                                             ((sx0 + sx1) / 2 - 1.1, gz0 + 0.9, 1.0, 1.3, "win")], lit=0.5, rng=rng)
    grill("-y", (sx0 + sx1) / 2 - 1.1, gz0 + 0.9, 1.0, 1.3, fw, gm)
    wall("-y", sx1, w / 2, gz0, gz1, front, body, [((sx1 + w / 2) / 2, gz0 + 0.85, 1.4, 1.35, "win")], lit=0.4, rng=rng)
    grill("-y", (sx1 + w / 2) / 2, gz0 + 0.85, 1.4, 1.35, front, gm)
    wall("-x", front, fw, gz0, gz1, sx1, body, [], ends=(0.25, 0.0))                       # sit-out side wall
    for face, x in (("-x", -w / 2), ("+x", w / 2)):
        y0 = fw if face == "-x" else front
        ops = [((y0 + d / 2) / 2, gz0 + 0.9, 1.2, 1.3, "win")]
        wall(face, y0, d / 2, gz0, gz1, x, body, ops, lit=0.3, rng=rng)
        grill(face, ops[0][0], ops[0][1], 1.2, 1.3, x, gm)
    wall("+y", -w / 2, w / 2, gz0, gz1, d / 2, body, [(-w / 4, gz0, 0.9, 2.1, "door"), (w / 4, gz0 + 1.2, 0.9, 0.9, "win")])
    box(((sx0 + sx1) / 2, (front + fw) / 2, pl + 0.01), (so_w, fw - front, 0.02), "flag")    # sit-out floor
    for x in (sx0 + 0.15, sx1 - 0.15):                                                        # square columns
        box((x, front + 0.15, gz0 + FLOOR / 2), (0.3, 0.3, FLOOR), body)
    # the grilled enclosure across the sit-out with its own gate
    gx = (sx0 + sx1) / 2
    for (a, b) in ((sx0 + 0.3, gx - 0.6), (gx + 0.6, sx1 - 0.3)):
        n = max(2, int((b - a) / 0.12))
        for k in range(n + 1):
            box((a + (b - a) * k / n, front + 0.15, gz0 + 1.1), (0.018, 0.022, 2.2), gm)
        for z in (gz0 + 0.05, gz0 + 1.1, gz0 + 2.2):
            box(((a + b) / 2, front + 0.15, z), (b - a, 0.03, 0.04), gm)
    for k in range(10):
        box((gx - 0.55 + k * 0.122, front + 0.12, gz0 + 1.0), (0.02, 0.022, 2.0), gm)
    box((gx, front + 0.12, gz0 + 2.0), (1.2, 0.03, 0.05), gm)
    box((gx, front + 0.12, gz0 + 0.05), (1.2, 0.03, 0.05), gm)
    box((gx, front + 0.15, gz0 + 2.55), (so_w - 0.6, 0.03, 0.7), gm)                         # grill transom
    box((sx1 - 0.6, fw - 0.06, gz0 + 2.4), (0.25, 0.03, 0.18), "brass")                      # name plate
    B.wall_lamp(gx + 1.3, fw, gz0 + 2.3)
    for k in range(3):
        cyl((sx0 + 0.6 + k * 0.45, front + 0.55, pl + 0.15), 0.14, 0.3, "pot", 12)
        blob((sx0 + 0.6 + k * 0.45, front + 0.55, pl + 0.42), 0.2, rng.choice(["shrub", "flowers_p"]), 1, 1.0, 0.3)
    # upper floors
    for f in range(1, fl):
        z0, z1 = pl + f * FLOOR, pl + (f + 1) * FLOOR
        box((0, 0, z0), (w + 0.3, d + 0.3, 0.16), "concrete")                                 # floor band
        ops = [(-w / 4, z0 + 0.15, 1.1, 2.15, "french"), (w / 4, z0 + 0.85, 1.4, 1.35, "win")]
        wall("-y", -w / 2, w / 2, z0 + 0.08, z1, front, body, ops, lit=0.35, rng=rng)
        grill("-y", w / 4, z0 + 0.85, 1.4, 1.35, front, gm)
        for face, x in (("-x", -w / 2), ("+x", w / 2)):
            ops = [(-d / 5, z0 + 0.9, 1.2, 1.3, "win"), (d / 4, z0 + 1.2, 0.8, 0.9, "win")]
            wall(face, front, d / 2, z0 + 0.08, z1, x, body, ops, lit=0.3, rng=rng)
            for o in ops:
                grill(face, o[0], o[1], o[2], o[3], x, gm)
        wall("+y", -w / 2, w / 2, z0 + 0.08, z1, d / 2, body, [(0, z0 + 0.9, 1.2, 1.3, "win")])
        # balcony over the sit-out / along the front
        box((-w / 4, front - 0.5, z0 + 0.05), (so_w, 1.0 if f > 1 else 0.3, 0.14), "concrete")
        bx0, bx1 = -w / 4 - so_w / 2 + 0.1, -w / 4 + so_w / 2 - 0.1
        yb = front - 0.95 if f > 1 else front + 0.05
        if f > 1:
            box((-w / 4, front - 0.5, z0 + 0.5), (so_w, 0.12, 0.8), body)                       # solid balcony wall
        else:
            railing((bx0, yb - 0.1), (bx1, yb - 0.1), z0 + 0.12, h=1.0, m=gm)
        if rng.random() < 0.6:
            ac_unit(w / 2 - 0.9, d / 2, z0 + 0.6, face=1)
    if fl == 1 or True:
        box((-w / 4, front + 1.0, pl + FLOOR + 0.0), (so_w + 0.2, 2.4, 0.16), "concrete")      # sit-out roof slab
    # open RCC staircase up the right side, outside the wall, to the first landing / terrace
    sxs = w / 2 + 0.55
    top = pl + FLOOR
    n = 17
    run = 0.27
    y0 = front + 0.6
    for k in range(n):
        zt = pl * 0 + (k + 1) * top / n
        box((sxs, y0 + k * run + run / 2, zt - 0.08), (1.0, run, 0.16), "concrete")
        box((sxs, y0 + k * run + run / 2, zt - 0.005), (1.0, run, 0.02), "granite")
    mesh("StairWaist", [(sxs - 0.5, y0, 0), (sxs + 0.5, y0, 0), (sxs + 0.5, y0 + n * run, top - 0.25), (sxs - 0.5, y0 + n * run, top - 0.25)],
         [(3, 2, 1, 0)], "concrete")
    box((sxs, y0 + n * run + 0.6, top - 0.08), (1.0, 1.2, 0.16), "concrete")                   # landing
    railing((sxs + 0.48, y0), (sxs + 0.48, y0 + n * run), 0.0, h=1.0, m=gm)
    beam((sxs + 0.48, y0, 1.0), (sxs + 0.48, y0 + n * run, top + 1.0), 0.05, 0.05, gm)
    # terrace
    R = pl + H
    box((0, 0, R + 0.08), (w + 0.5, d + 0.5, 0.16), "concrete")
    parapet(w + 0.3, d + 0.3, R + 0.16, 0.9, body)
    for x in (-w / 2 + 0.6, w / 2 - 0.6):
        cyl((x, -d / 2 - 0.3, R + 0.25), 0.05, 0.5, "steel_lt", 8, rot=(math.pi / 2, 0, 0))   # spouts
    mumty(w / 2 - 1.6, d / 2 - 1.8, R + 0.16, 2.6, 3.0, body, door_face=-1, rng=rng)
    clothes_line(-w / 2 + 0.8, w / 4, -d / 6, R + 0.16, rng)
    if rng.random() < 0.5:
        cyl((-w / 2 + 0.8, d / 2 - 0.8, R + 1.4), 0.32, 0.03, "white", 20, rot=(math.radians(60), 0, 0.6))   # dish
        box((-w / 2 + 0.8, d / 2 - 0.8, R + 0.8), (0.04, 0.04, 1.2), "steel_lt")
    for k in range(rng.randint(2, 5)):                                                        # pots on the parapet
        x = -w / 2 + 0.6 + k * 0.7
        cyl((x, front - 0.15, R + 1.15), 0.13, 0.22, "pot", 12)
        blob((x, front - 0.15, R + 1.38), 0.18, "shrub", 1, 1.0, 0.3)
    downpipe(-w / 2 - 0.05, d / 2 - 0.3, R)
    downpipe(w / 2 + 0.05, d / 2 - 0.3, R)
    meter_box(sx1 + 0.5, front, pl + 1.4)
    return {"gate_x": gx, "setback": 3.2, "side": 1.8 + 1.1, "wall_m": body, "drive_w": 2.6, "door_x": gx,
            "door_y": -0.9, "tn": True}


def commercial(w, d, floors, rng):
    fl = max(2, min(floors, 5))
    H = fl * FLOOR + 0.3
    pl = 0.45
    front = -d / 2
    body = rng.choice(["plaster_w", "cream", "peach", "sky", "white_wash"])
    n = max(2, int(round(w / 4.4)))
    sw = w / n
    box((0, 0, pl / 2), (w, d, pl), "concrete")
    for k in range(2):                                                                        # steps the full width
        box((0, front - 0.25 - k * 0.3, pl - 0.15 * (k + 1) + 0.075), (w, 0.3, 0.15), "granite")
    gz0, gz1 = pl, pl + FLOOR + 0.3
    ops = [(-w / 2 + sw * (i + 0.5), gz0, sw - 0.55, 2.95, "shop") for i in range(n)]
    wall("-y", -w / 2, w / 2, gz0, gz1, front, "concrete", ops, lit=0.9, rng=rng, shades=False)
    names = rng.sample(SHOPS, min(n, len(SHOPS)))
    for i in range(n):
        x = -w / 2 + sw * (i + 0.5)
        state = rng.choice([0.0, 0.0, 0.0, 0.45, 1.0])
        shutter(x, front, gz0, sw - 0.55, 2.95, state)
        if state < 0.5:                                                                       # goods inside
            for k in range(3):
                box((x, front + 1.5, gz0 + 0.45 + k * 0.6), (sw - 1.0, 0.45, 0.05), "timber")
                for j in range(int((sw - 1.2) / 0.35)):
                    if rng.random() < 0.7:
                        box((x - sw / 2 + 0.75 + j * 0.35, front + 1.5, gz0 + 0.6 + k * 0.6),
                            (0.25, 0.3, rng.uniform(0.15, 0.3)), rng.choice(["goods", "sign_red", "sign_blue", "sign_yellow", "white"]))
            box((x + sw * 0.2, front + 0.8, gz0 + 0.5), (1.2, 0.5, 1.0), "timber_dk")
        signboard(x, front - 0.12, gz1 + 0.45, sw - 0.15, 0.85, names[i % len(names)], rng)
    box((0, front - 0.55, gz1 - 0.05), (w + 0.2, 1.1, 0.12), "concrete")                     # sunshade
    for face, x in (("-x", -w / 2), ("+x", w / 2)):
        wall(face, front, d / 2, gz0, pl + H, x, body, [])                                    # blank party walls
    wall("+y", -w / 2, w / 2, gz0, gz1, d / 2, "concrete", [(0, gz0, 1.2, 2.2, "door")])
    # offices above: a big brand-free banner band on the first floor, windows with grills and chajjas
    for f in range(1, fl):
        z0 = pl + f * FLOOR + 0.3
        z1 = z0 + FLOOR
        box((0, front - 0.08, z0 + 0.0), (w + 0.1, 0.25, 0.18), "concrete")
        nw = max(2, int(w / 2.6))
        ops = [(-w / 2 + w / nw * (k + 0.5), z0 + 0.85, 1.5, 1.4, "win") for k in range(nw)]
        if f == 1 and rng.random() < 0.6:
            box((0, front - 0.25, z0 + FLOOR / 2), (w * 0.92, 0.12, FLOOR * 0.72), "acp")
            signboard(0, front - 0.33, z0 + FLOOR / 2, w * 0.8, FLOOR * 0.5, rng.choice(SHOPS), rng)
            wall("-y", -w / 2, w / 2, z0, z1, front, body, [], rng=rng)
        else:
            wall("-y", -w / 2, w / 2, z0, z1, front, body, ops, lit=0.35, rng=rng)
            for o in ops:
                grill("-y", o[0], o[1], o[2], o[3], front, rng.choice(["grill_g", "grill_k", "steel"]))
                if rng.random() < 0.25:
                    ac_unit(o[0] + 1.2, front, o[1] - 0.2)
        wall("+y", -w / 2, w / 2, z0, z1, d / 2, body, [(0, z0 + 0.9, 1.2, 1.2, "win")])
        if rng.random() < 0.4:                                                               # flex banner
            bx, bw = rng.uniform(-w / 3, w / 3), rng.uniform(2.6, 4.0)
            box((bx, front - 0.2, z0 + 1.6), (bw, 0.02, 1.2), rng.choice(["sign_orange", "sign_green", "sign_blue"]))
            text(rng.choice(ADS), bx, front - 0.215, z0 + 1.6, 0.42, "sign_white", width=bw * 0.88)
    R = pl + H
    box((0, 0, R + 0.08), (w + 0.3, d + 0.3, 0.16), "concrete")
    parapet(w + 0.2, d + 0.2, R + 0.16, 1.0, body)
    mumty(w / 2 - 2.0, d / 2 - 2.2, R + 0.16, 3.0, 3.4, body, rng=rng)
    for k in range(rng.randint(1, 3)):
        tank(-w / 2 + 1.5 + k * 1.6, d / 2 - 1.2, R + 0.16)
    if rng.random() < 0.5:                                                                    # hoarding frame
        hx = -w / 4
        for s in (-1, 1):
            box((hx + s * 2.8, -d / 4, R + 2.4), (0.12, 0.12, 4.6), "steel_lt")
            beam((hx + s * 2.8, -d / 4 + 1.6, R + 0.2), (hx + s * 2.8, -d / 4, R + 3.2), 0.08, 0.08, "steel_lt")
        box((hx, -d / 4 - 0.08, R + 3.6), (6.2, 0.06, 2.6), "white")
        box((hx, -d / 4 - 0.12, R + 3.6), (5.6, 0.02, 2.0), rng.choice(list(SIGN_COLOURS)))
    for k in range(n + 1):
        downpipe(-w / 2 + sw * k + (0.12 if k == 0 else -0.12), d / 2 + 0.06, R)
    box((0, front - 0.45, gz1 + 1.1), (w + 0.4, 0.015, 0.015), "cable")                       # sagging cable
    return {"gate_x": 0.0, "setback": 2.0, "side": 0.4, "walled": False, "forecourt": False, "drive_w": w}


def mill_shed(w, d, floors, rng):
    front = -d / 2
    pl = 0.45
    Hw = 6.0
    body = "white_wash"
    box((0, 0, pl / 2), (w, d, pl), "concrete")
    nwin = max(2, int(w / 4.0))
    hi = [(-w / 2 + w / nwin * (k + 0.5), Hw - 2.2, 1.8, 1.3, "win") for k in range(nwin)]
    gate_x = -w / 4
    wall("-y", -w / 2, w / 2, pl, Hw, front, body, [(gate_x, pl, 4.8, 4.2, "door")] + [o for o in hi if abs(o[0] - gate_x) > 3.4],
         lit=0.2, rng=rng)
    for o in hi:
        if abs(o[0] - gate_x) > 3.4:
            grill("-y", o[0], o[1], o[2], o[3], front, "grill_k", 0.16)
    shutter(gate_x, front, pl, 4.8, 4.2, rng.choice([0.0, 1.0, 1.0]))
    nside = max(2, int(d / 4.0))
    for face, x in (("-x", -w / 2), ("+x", w / 2)):
        ops = [(-d / 2 + d / nside * (k + 0.5), Hw - 2.2, 1.8, 1.3, "win") for k in range(nside)]
        wall(face, front, d / 2, pl, Hw, x, body, ops, lit=0.1, rng=rng)
        for o in ops:
            grill(face, o[0], o[1], o[2], o[3], x, "grill_k", 0.16)
    wall("+y", -w / 2, w / 2, pl, Hw, d / 2, body, [])
    # sawtooth roof: teeth run front to back (along y), north lights face +x
    tw = 6.0
    nt_ = max(1, int(round(w / tw)))
    tw = w / nt_
    rise = 2.4
    for k in range(nt_):
        x0 = -w / 2 + k * tw
        x1 = x0 + tw
        y0, y1 = front - 0.3, d / 2 + 0.3
        mesh("Tooth", [(x0, y0, Hw), (x1, y0, Hw + rise), (x1, y1, Hw + rise), (x0, y1, Hw)], [(0, 1, 2, 3)], "ac_sheet")
        mesh("ToothUnder", [(x0, y0, Hw - 0.03), (x1, y0, Hw + rise - 0.03), (x1, y1, Hw + rise - 0.03), (x0, y1, Hw - 0.03)],
             [(3, 2, 1, 0)], "concrete")
        mesh("NorthLight", [(x1, y0, Hw), (x1, y1, Hw), (x1, y1, Hw + rise - 0.1), (x1, y0, Hw + rise - 0.1)], [(0, 1, 2, 3)], "glass")
        for yy in range(int((y1 - y0) / 1.2) + 1):
            box((x1, y0 + yy * 1.2, Hw + rise / 2), (0.06, 0.06, rise), "steel")
        for (yy, flip) in ((front, False), (d / 2, True)):                                    # gable triangles
            tri = [(x0, yy, Hw), (x1, yy, Hw), (x1, yy, Hw + rise)]
            mesh("Gable", tri, [(2, 1, 0) if flip else (0, 1, 2)], body)
        box((x0 + 0.05, (y0 + y1) / 2, Hw - 0.05), (0.2, y1 - y0, 0.2), "steel_lt")          # valley gutter
    # two-storey office in front of the shed, with the mill's name
    ow = min(10.0, w * 0.4)
    ox = w / 4
    od = 5.0
    oy = front - od / 2
    for f in range(2):
        z0, z1 = pl + f * FLOOR, pl + (f + 1) * FLOOR
        ops = [(ox - ow / 4, z0 + 0.9, 1.4, 1.3, "win"), (ox + ow / 4, z0 + 0.9, 1.4, 1.3, "win")]
        if f == 0:
            ops[0] = (ox - ow / 4, z0, 1.1, 2.2, "door")
        wall("-y", ox - ow / 2, ox + ow / 2, z0, z1, oy - od / 2, "cream", ops, lit=0.5, rng=rng)
        for o in ops:
            if o[4] == "win":
                grill("-y", o[0], o[1], o[2], o[3], oy - od / 2, "grill_g")
        for face, x in (("-x", ox - ow / 2), ("+x", ox + ow / 2)):
            wall(face, oy - od / 2, front, z0, z1, x, "cream", [(oy, z0 + 0.9, 1.2, 1.3, "win")], lit=0.3, rng=rng,
                 ends=(0.25, 0.0))
    box((ox, oy, pl + 2 * FLOOR + 0.08), (ow + 0.4, od + 0.4, 0.16), "concrete")
    parapet(ow + 0.2, od + 0.2, pl + 2 * FLOOR + 0.16, 0.9, "cream")
    box((ox, oy - od / 2 - 0.4, pl + FLOOR - 0.15), (ow + 0.4, 0.8, 0.12), "concrete")
    signboard(ox, oy - od / 2 - 0.14, pl + 2 * FLOOR + 0.62, ow * 0.95, 1.0, rng.choice(MILLS), rng)
    tank(ox + ow / 2 - 1.0, oy + 1.0, pl + 2 * FLOOR + 0.16)
    # a brick chimney stack behind
    cyl((w / 2 - 3, d / 2 - 3, 10), 0.9, 20, "plaster_t", 20)
    cyl((w / 2 - 3, d / 2 - 3, 20.1), 1.0, 0.3, "concrete", 20)
    for k in range(int(w / 8)):
        downpipe(-w / 2 + 2 + k * 8, front - 0.05, Hw)
    return {"gate_x": gate_x, "setback": 9.0, "side": 2.0, "walled": True, "wall_m": "white_wash", "drive_w": 5.5,
            "door_x": gate_x, "forecourt": False}


B.BUILD.update({"tn_house": tn_house, "commercial": commercial, "mill_shed": mill_shed})
B.VARIANTS += [("tn_house", 7, 9, f) for f in (1, 2, 3)] + [("tn_house", 9, 12, f) for f in (1, 2, 3)] + \
              [("tn_house", 12, 14, f) for f in (2, 3)] + \
              [("commercial", 16, 14, f) for f in (2, 3, 4)] + [("commercial", 24, 16, f) for f in (2, 3, 4)] + \
              [("commercial", 34, 18, f) for f in (3, 4)] + \
              [("mill_shed", 30, 24, 1), ("mill_shed", 48, 32, 1)]
TN_SPECS = [("tn_house", 9, 12, 2, 11), ("commercial", 24, 16, 3, 12), ("tn_house", 7, 9, 1, 13),
            ("commercial", 16, 14, 4, 14), ("tn_house", 12, 14, 3, 15), ("mill_shed", 30, 24, 1, 16)]


def street(out_dir, blend=None, specs=TN_SPECS, shots=("wide", "walk", "shops")):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    B._M.clear()
    cam = B.scene_setup(64, (1920, 1080))
    x = 0.0
    centres = {}
    for kind, w, d, fl, seed in specs:
        col = bpy.data.collections.new(kind + str(seed))
        bpy.context.scene.collection.children.link(col)
        bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection.children[col.name]
        ob, info = B.build(kind, w, d, fl, seed)
        half = w / 2 + info.get("side", 2.5) + 0.3
        x += half
        ob.location = (x, -info["kerb_y"], 0)
        centres[kind + str(seed)] = (x, -info["kerb_y"], w, d, fl)
        B.dress(info, x, 0.0, kind, seed)
        x += half
    bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection
    B.ground(0, x, 0.0)
    road = [box((x / 2, -4.0, 0.012), (x + 400, 8.0, 0.008), "asphalt")]                     # one continuous carriageway
    for k in range(int((x + 400) / 6)):
        road.append(box((-200 + 1.5 + k * 6, -4.0, 0.019), (3.0, 0.12, 0.006), "line"))
    for yy in (-0.3, -7.7):
        road.append(box((x / 2, yy, 0.019), (x + 400, 0.12, 0.006), "line"))
    bpy.ops.object.select_all(action='DESELECT')
    for o in road:
        o.select_set(True)
    bpy.context.view_layer.objects.active = road[0]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)              # texture at true size
    if blend:
        bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
        print("SAVED", blend, flush=True)
    sc = bpy.context.scene
    views = {
        "wide": ((x * 0.5, -x * 0.42, x * 0.12), (x * 0.5, 14, 5), 24),
        "walk": ((-4, -9.2, 1.65), (x * 0.35, 6, 3.2), 26),                     # standing on the far pavement
        "shops": ((centres["commercial12"][0] - 10, -9.2, 1.7), (centres["commercial12"][0] + 4, 3, 4.2), 24),
        "house": ((centres["tn_house11"][0] + 7, -9.2, 1.7), (centres["tn_house11"][0] - 1, 6, 3.4), 24),
        "mill": ((centres["mill_shed16"][0] - 22, -9.4, 2.2), (centres["mill_shed16"][0] + 2, 14, 5), 24),
    }
    for name in shots:
        loc, tgt, lens = views[name]
        B.aim(cam, loc, tgt, lens)
        sc.render.filepath = os.path.join(out_dir, "kovai_%s.jpg" % name)
        bpy.ops.render.render(write_still=True)
        print("SHOT", name, flush=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = os.path.abspath(args[0]) if args and not args[0].startswith("--") else os.path.abspath("previews/buildings")
    os.makedirs(out, exist_ok=True)
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    shots = args[args.index("--shots") + 1].split(",") if "--shots" in args else ("wide", "walk", "shops", "house", "mill")
    if "--export" in args:
        B.export_kit(os.path.abspath(args[args.index("--export") + 1]), only)
    if "--street" in args:
        street(out, os.path.abspath(args[args.index("--blend") + 1]) if "--blend" in args else None, shots=shots)
