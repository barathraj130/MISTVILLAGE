"""Kongu Fuels, a petrol bunk (our own made-up brand; docs/PROLOGUE_PLAN_2026-11-17.md and the dealership-and-bunk
redesign brief): built in Blender from code, no downloads.

    blender -b --factory-startup --python tools/cars/build_bunk.py -- [--export out.glb] [--preview dir]

  - the forecourt: concrete laid in 4 m panels with their joints, tyre marks, oil and dust (a texture made here,
    in metres), a grated drainage channel round the pump area, the entry and exit painted with arrows, a raised
    kerb and the road's edge
  - the canopy: a steel frame (two deep beams, purlins) on four clad columns, a lit soffit of panels with recessed
    LED fittings, the brand's fascia all round (lit white, a red band, a green line), the name front and back
  - two multi-product dispensers on raised islands: a steel body on a plinth, each face with three display windows
    (amount, litres, price) set in a black bezel, a keypad, a card terminal, the red emergency stop, the product
    panels (PETROL / DIESEL), two hoses a side on spring arms, nozzles in their holsters; crash barriers at the
    island ends, bollards
  - the price board on its totem (petrol, diesel, premium on LED rows) and a digital sign
  - the cashier's building: the sales window and counter, the door, the staff room and the store at the back, an
    awning, the UPI board; oil cans on their rack
  - the air and water stand with its tyre inflator gauge and coiled hose
  - the underground tanks' lids and the tanker's fill points, extinguishers on stands, sand buckets
Origin at the forecourt's middle on the ground; +X along the road, the road on the −Y side. The game reads Bay_1 / 2,
Screen_1 / 2, Attendant_1 / 2 (fuel_bunks.gd keeps their numbers: the pumps stay at x ±3.2, their screens 1.6 m up).
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import carkit as K  # noqa: E402
import parts as P  # noqa: E402


# ----------------------------------------------------------------------------------------------------- textures
def tex_concrete(size=1024, metres=24.0):
    """The forecourt's concrete: grey with grain, 4 m panel joints, darker tyre tracks and oil spots, dust at the edges."""
    def fn(xx, yy):
        g = 0.47 + (K._noise(size, 6, 11) - 0.5) * 0.08 + (K._noise(size, 1.5, 12) - 0.5) * 0.05
        u, v = xx * metres, yy * metres
        joint = (np.abs(((u + 2.0) % 4.0) - 2.0) > 1.97) | (np.abs(((v + 2.0) % 4.0) - 2.0) > 1.97)
        g = np.where(joint, g * 0.55, g)
        track = np.exp(-((v - metres * 0.42) ** 2) / 0.5) + np.exp(-((v - metres * 0.47) ** 2) / 0.5)
        g = g - track * 0.07 * K._noise(size, 3, 13)
        oil = np.clip(K._noise(size, 40, 14) - 0.72, 0, 1) * 1.6
        g = g - oil * 0.25
        dust = np.clip(np.minimum(np.minimum(xx, 1 - xx), np.minimum(yy, 1 - yy)) * 8.0, 0, 1)
        r = g * 1.02 + (1 - dust) * 0.05
        return r, g * 1.0 + (1 - dust) * 0.035, g * 0.97
    return K._img("tex_forecourt", size, fn)


def tex_soffit(size=512):
    """The canopy's underside: white panels in a 1.2 m grid with grey seams."""
    def fn(xx, yy):
        u, v = xx * 12.0, yy * 12.0
        seam = (np.abs((u % 1.0) - 0.5) > 0.485) | (np.abs((v % 1.0) - 0.5) > 0.485)
        g = np.where(seam, 0.55, 0.9) + (K._noise(size, 8, 21) - 0.5) * 0.03
        return g, g, g * 0.98
    return K._img("tex_soffit", size, fn)


def tex_wall(size=512):
    """Painted plaster, a little stained low down (the monsoon's splash)."""
    def fn(xx, yy):
        g = 0.86 + (K._noise(size, 4, 31) - 0.5) * 0.04
        stain = np.clip(yy * 4.0 - 3.0, 0, 1) * K._noise(size, 12, 32) * 0.18
        g = g - stain
        return g, g * 0.99, g * 0.95
    return K._img("tex_wall", size, fn)


def tmat(name, img, rough=0.6, metal=0.0, normal=None, normal_k=0.4):
    """A material whose colour is an image (on the mesh's own UVs, in metres)."""
    m = K._mat(name, (1, 1, 1), metal=metal, rough=rough, normal=normal, normal_k=normal_k)
    nt = m.node_tree
    p = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    nt.links.new(t.outputs[0], p.inputs["Base Color"])
    return m


def plane(name, x0, x1, y0, y1, z, mat, uv_w, uv_h, flip=False):
    """A flat rectangle with UVs over (uv_w × uv_h) of its texture (0..1 across it)."""
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in ((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z))]
    f = bm.faces.new(list(reversed(vs)) if flip else vs)
    uv = bm.loops.layers.uv.new()
    for lp in f.loops:
        lp[uv].uv = ((lp.vert.co.x - x0) / (x1 - x0) * uv_w, (lp.vert.co.y - y0) / (y1 - y0) * uv_h)
    return K.mesh_obj(name, bm, [mat])


def wall(name, a, b, z0, z1, mat, metres_per_uv=4.0):
    """A vertical wall from a to b (x, y), with UVs in metres."""
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in ((a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1))]
    f = bm.faces.new(vs)
    uv = bm.loops.layers.uv.new()
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    for lp, (s, t) in zip(f.loops, ((0, z0), (L, z0), (L, z1), (0, z1))):
        lp[uv].uv = (s / metres_per_uv, t / metres_per_uv)
    ob = K.mesh_obj(name, bm, [mat])
    ob.modifiers.new("S", 'SOLIDIFY').thickness = 0.2
    return ob


def text(name, body, at, size, mat, rot=(math.pi / 2, 0, 0), align='CENTER', extrude=0.004):
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body = body
    cu.size = size
    cu.extrude = extrude
    cu.align_x = align
    cu.align_y = 'CENTER'
    ob = bpy.data.objects.new(name, cu)
    K.link(ob)
    ob.location = at
    ob.rotation_euler = rot
    ob.data.materials.append(mat)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target='MESH')
    return ob


def empty(name, at, yaw=0.0):
    e = bpy.data.objects.new(name, None)
    K.link(e)
    e.location = at
    e.rotation_euler = (0, 0, yaw)
    return e


# ----------------------------------------------------------------------------------------------------- the parts
def dispenser(M, C, ix, out):
    """A multi-product dispenser at x = ix on its island (the island's middle at y 1.0): both faces alike."""
    y0 = 1.0
    out.append(P.box("Plinth", (1.15, 0.7, 0.22), (ix, y0, 0.33), C["concrete_dark"], bevel=0.02))
    out.append(P.box("DispBody", (1.0, 0.52, 1.55), (ix, y0, 1.22), C["steel_brushed"], bevel=0.02))
    out.append(P.box("DispColumn", (0.22, 0.4, 2.3), (ix - 0.62, y0, 1.6), C["white_panel"], bevel=0.02))
    out.append(P.box("DispColumn", (0.22, 0.4, 2.3), (ix + 0.62, y0, 1.6), C["white_panel"], bevel=0.02))
    out.append(P.box("DispHead", (1.5, 0.48, 0.42), (ix, y0, 2.62), C["brand_red"], bevel=0.03))
    out.append(P.box("DispHeadBand", (1.52, 0.5, 0.06), (ix, y0, 2.42), C["brand_green"], bevel=0.005))
    for s in (-1, 1):
        y = y0 + s * 0.262
        fy = y + s * 0.006
        rot = (math.pi / 2, 0, 0) if s < 0 else (math.pi / 2, 0, math.pi)
        out.append(text("DispName", "KONGU FUELS", (ix, y + s * 0.245, 2.64), 0.13, M["PlateWhite"], rot=rot))
        out.append(P.box("Bezel", (0.66, 0.012, 0.5), (ix, fy, 1.6), C["black_gloss"], bevel=0.01))
        for r, (z, w) in enumerate(((1.76, 0.5), (1.6, 0.42), (1.45, 0.34))):
            out.append(P.box("Window", (w, 0.004, 0.1), (ix + (0.5 - w) * 0.4, fy + s * 0.006, z), C["lcd"]))
        for r, (lab, z) in enumerate((("AMOUNT", 1.76), ("LITRES", 1.6), ("PRICE/L", 1.45))):
            out.append(text("WinLabel", lab, (ix - 0.27, fy + s * 0.008, z), 0.03, M["PlateWhite"], rot=rot))
        out.append(P.box("Keypad", (0.2, 0.012, 0.16), (ix - 0.18, fy, 1.2), C["black_gloss"], bevel=0.01))
        for k in range(12):
            out.append(P.box("Key", (0.035, 0.008, 0.025), (ix - 0.245 + (k % 3) * 0.065, fy + s * 0.004, 1.25 - (k // 3) * 0.035), C["steel_brushed"]))
        out.append(P.box("CardTerminal", (0.16, 0.03, 0.2), (ix + 0.17, fy + s * 0.01, 1.22), C["black_gloss"], bevel=0.015))
        out.append(P.box("TermScreen", (0.11, 0.004, 0.07), (ix + 0.17, fy + s * 0.027, 1.27), C["screen"]))
        out.append(P.cyl("EStop", 0.035, 0.03, (ix + 0.38, fy + s * 0.015, 1.4), C["estop"], rot=(math.pi / 2, 0, 0), segs=20))
        out.append(P.box("EStopBase", (0.1, 0.01, 0.1), (ix + 0.38, fy, 1.4), C["estop_yellow"]))
        for k, (prod, col) in enumerate((("PETROL", C["brand_green"]), ("DIESEL", C["diesel_yellow"]))):
            px = ix + (-0.27 if k == 0 else 0.27)
            out.append(P.box("ProdPanel", (0.36, 0.012, 0.16), (px, fy, 0.82), col, bevel=0.005))
            out.append(text("ProdLabel", prod, (px, fy + s * 0.008, 0.82), 0.07, M["PlateWhite"] if k == 0 else C["black_gloss"], rot=rot))
            hx = ix + (-0.62 if k == 0 else 0.62)
            out.append(P.box("Holster", (0.1, 0.12, 0.2), (hx, y + s * 0.12, 1.2), C["black_gloss"], bevel=0.015))
            out.append(P.box("Nozzle", (0.05, 0.07, 0.28), (hx, y + s * 0.2, 1.24), col, bevel=0.012, rot=(s * 0.35, 0, 0)))
            out.append(P.tube("Hose", [(hx, y0 + s * 0.15, 2.4), (hx + (0.25 if k else -0.25) * 0.5, y0 + s * 0.55, 2.1),
                                       (hx + (0.15 if k else -0.15), y0 + s * 0.45, 1.3), (hx, y + s * 0.2, 1.38)], 0.019, M["Rubber"], smooth_pts=7))
    return out


def build(M):
    out = []
    C = {
        "forecourt": tmat("Forecourt", tex_concrete(), rough=0.85),
        "soffit": tmat("Soffit", tex_soffit(), rough=0.6),
        "wall": tmat("BunkWall", tex_wall(), rough=0.85),
        "concrete_dark": K._mat("ConcreteDark", (0.3, 0.3, 0.29), rough=0.9),
        "white_panel": K._mat("CladWhite", (0.86, 0.86, 0.84), rough=0.35, coat=0.3),
        "brand_red": K._mat("BrandRed", (0.55, 0.03, 0.04), rough=0.35, coat=0.4),
        "brand_green": K._mat("BrandGreen", (0.02, 0.3, 0.15), rough=0.4, coat=0.3),
        "diesel_yellow": K._mat("DieselYellow", (0.8, 0.6, 0.04), rough=0.4),
        "steel_brushed": K._mat("SteelBrushed", (0.68, 0.69, 0.7), metal=1.0, rough=0.32),
        "steel_dark": K._mat("SteelDark", (0.22, 0.23, 0.24), metal=0.9, rough=0.45),
        "black_gloss": M["BlackGloss"],
        "lcd": K._mat("LCD", (0.04, 0.05, 0.04), rough=0.15, emit=(0.15, 0.2, 0.12), emit_k=0.6),
        "screen": M["Screen"],
        "estop": K._mat("EStopRed", (0.7, 0.02, 0.02), rough=0.3),
        "estop_yellow": K._mat("EStopYellow", (0.9, 0.7, 0.05), rough=0.5),
        "led_panel": K._mat("CanopyLED", (0.95, 0.95, 0.92), rough=0.3, emit=(1.0, 0.98, 0.93), emit_k=4.0),
        "fascia": K._mat("FasciaLit", (0.95, 0.95, 0.92), rough=0.3, emit=(1.0, 0.98, 0.94), emit_k=1.0),
        "led_price": K._mat("PriceLED", (0.1, 0.02, 0.0), rough=0.3, emit=(1.0, 0.3, 0.05), emit_k=3.0),
        "led_green": K._mat("SignLED", (0.0, 0.1, 0.03), rough=0.3, emit=(0.15, 1.0, 0.35), emit_k=2.0),
        "paint_white": K._mat("RoadPaint", (0.9, 0.9, 0.86), rough=0.7),
        "paint_yellow": K._mat("KerbYellow", (0.82, 0.62, 0.05), rough=0.7),
        "kerb_black": K._mat("KerbBlack", (0.06, 0.06, 0.06), rough=0.8),
        "grate": K._mat("Grate", (0.15, 0.15, 0.15), metal=0.8, rough=0.6),
        "glass": M["Glass"],
        "awning": K._mat("Awning", (0.02, 0.3, 0.15), rough=0.6),
    }
    # ---- the forecourt ----
    out.append(plane("Forecourt", -12.0, 12.0, -7.5, 9.8, 0.03, C["forecourt"], 1.0, 1.0))
    out.append(P.box("ForecourtBase", (24.0, 17.3, 0.04), (0, 1.15, 0.0), C["concrete_dark"]))
    for s in (1, -1):                                          # the kerb at the road with gaps for the way in and out
        for x0, x1 in ((-12.0, -10.2), (-4.3, 4.3), (10.2, 12.0)):
            out.append(P.box("Kerb", (x1 - x0, 0.25, 0.15), ((x0 + x1) / 2, -7.4, 0.08), C["concrete_dark"] if s > 0 else C["kerb_black"], bevel=0.01))
    for k in range(8):                                         # kerb stripes, black and yellow
        x = -4.3 + k * 1.075 + 0.54
        out.append(P.box("KerbPaint", (0.54, 0.26, 0.152), (x, -7.4, 0.081), C["paint_yellow"] if k % 2 else C["kerb_black"]))
    for x, ang in ((-7.2, 0.0), (7.2, math.pi)):                # the way in and the way out: arrows and lane lines
        out.append(P.box("ArrowShaft", (1.6, 0.25, 0.006), (x, -5.0, 0.036), C["paint_white"], rot=(0, 0, ang)))
        bm = bmesh.new()
        vs = [bm.verts.new(p) for p in ((0.0, 0.5, 0), (0.9, 0.0, 0), (0.0, -0.5, 0))]
        bm.faces.new(vs)
        head = K.mesh_obj("ArrowHead", bm, [C["paint_white"]])
        head.location = (x + (0.8 if ang == 0 else -0.8), -5.0, 0.037)
        head.rotation_euler = (0, 0, ang)
        out.append(head)
        out.append(text("LaneWord", "IN" if ang == 0 else "OUT", (x, -6.0, 0.038), 0.45, C["paint_white"], rot=(0, 0, 0)))
    # a grated drainage channel round the pumps
    for (cx, cy, w, h) in ((0.0, -2.6, 13.0, 0.25), (0.0, 4.6, 13.0, 0.25), (-6.5, 1.0, 0.25, 7.2), (6.5, 1.0, 0.25, 7.2)):
        out.append(P.box("Drain", (w, h, 0.02), (cx, cy, 0.032), C["grate"]))
        n = int(max(w, h) / 0.12)
        for k in range(n):
            t = -max(w, h) / 2 + (k + 0.5) * max(w, h) / n
            out.append(P.box("GrateBar", (0.02 if w > h else w, h if w > h else 0.02, 0.008), (cx + (t if w > h else 0), cy + (0 if w > h else t), 0.045), C["steel_dark"]))
    # the tanks' lids and the tanker's fill points
    for k, x in enumerate((-9.5, -8.2, -6.9)):
        out.append(P.cyl("TankLid", 0.42, 0.04, (x, 6.2, 0.045), C["steel_dark"], axis='Z', segs=32))
        out.append(P.cyl("TankLidRim", 0.46, 0.03, (x, 6.2, 0.035), C["paint_yellow"], axis='Z', segs=32))
        out.append(text("TankLabel", ["PETROL", "DIESEL", "PREMIUM"][k], (x, 6.2, 0.07), 0.12, C["paint_white"], rot=(0, 0, 0)))
    # ---- the islands and the dispensers ----
    for ix in (-3.2, 3.2):
        out.append(P.box("Island", (5.4, 1.3, 0.2), (ix, 1.0, 0.13), C["concrete_dark"], bevel=0.03))
        for s in (1, -1):
            for k in range(10):                                # its edge painted in yellow and black
                out.append(P.box("IslandEdge", (0.54, 0.02, 0.2), (ix - 2.43 + k * 0.54, 1.0 + s * 0.655, 0.13), C["paint_yellow"] if k % 2 else C["kerb_black"]))
        for ex in (-1, 1):                                     # crash barriers at its ends, bollards
            bx = ix + ex * 2.55
            out.append(P.tube("Barrier", [(bx - ex * 0.3, 0.45, 0.25), (bx, 0.45, 0.25), (bx, 0.45, 1.0), (bx, 1.55, 1.0), (bx, 1.55, 0.25),
                                          (bx - ex * 0.3, 1.55, 0.25)], 0.05, C["paint_yellow"], smooth_pts=3))
            out.append(P.cyl("Bollard", 0.09, 1.0, (bx + ex * 0.35, 1.0, 0.7), C["paint_yellow"], axis='Z', segs=16))
            out.append(P.cyl("BollardBand", 0.092, 0.12, (bx + ex * 0.35, 1.0, 0.95), C["kerb_black"], axis='Z', segs=16))
        dispenser(M, C, ix, out)
    # ---- the canopy ----
    for x in (-6.5, 6.5):
        out.append(P.box("ColumnCore", (0.42, 0.42, 5.4), (x, 1.0, 2.73), C["steel_dark"]))
        out.append(P.box("ColumnClad", (0.55, 0.55, 3.0), (x, 1.0, 1.55), C["white_panel"], bevel=0.04))
        out.append(P.box("ColumnBand", (0.56, 0.56, 0.35), (x, 1.0, 3.2), C["brand_red"], bevel=0.03))
        out.append(P.box("ColumnFoot", (0.8, 0.8, 0.25), (x, 1.0, 0.15), C["concrete_dark"], bevel=0.03))
    for y in (-1.6, 3.6):                                      # the deep beams and the purlins
        out.append(P.box("Beam", (17.0, 0.3, 0.6), (0, y, 5.2), C["steel_dark"]))
    for k in range(9):
        out.append(P.box("Purlin", (0.12, 9.0, 0.25), (-8.0 + k * 2.0, 1.0, 5.45), C["steel_dark"]))
    out.append(P.box("Deck", (17.4, 9.4, 0.2), (0, 1.0, 5.9), C["white_panel"]))
    out.append(plane("Soffit", -8.6, 8.6, -3.6, 5.6, 5.12, C["soffit"], 1.4, 0.75, flip=True))
    for x in (-6.0, -3.2, 0.0, 3.2, 6.0):                      # recessed LED fittings
        for y in (-1.2, 1.0, 3.2):
            out.append(P.box("LEDPanel", (1.2, 0.6, 0.04), (x, y, 5.1), C["led_panel"]))
            out.append(P.box("LEDTrim", (1.28, 0.68, 0.03), (x, y, 5.11), C["steel_brushed"]))
    for s in (1, -1):                                          # the fascia: lit white, the red band, the green line
        out.append(P.box("Fascia", (17.8, 0.12, 1.0), (0, 1.0 + s * 4.75, 5.55), C["fascia"], bevel=0.02))
        out.append(P.box("FasciaRed", (17.82, 0.13, 0.26), (0, 1.0 + s * 4.75, 5.12), C["brand_red"]))
        out.append(P.box("FasciaGreen", (17.82, 0.13, 0.07), (0, 1.0 + s * 4.75, 6.02), C["brand_green"]))
    for s in (1, -1):
        out.append(P.box("FasciaEnd", (0.12, 9.6, 1.0), (s * 8.9, 1.0, 5.55), C["fascia"], bevel=0.02))
        out.append(P.box("FasciaEndRed", (0.13, 9.62, 0.26), (s * 8.9, 1.0, 5.12), C["brand_red"]))
    out.append(text("BrandFront", "KONGU FUELS", (0, 1.0 - 4.83, 5.6), 0.62, C["brand_red"], extrude=0.02))
    out.append(text("BrandBack", "KONGU FUELS", (0, 1.0 + 4.83, 5.6), 0.62, C["brand_red"], rot=(math.pi / 2, 0, math.pi), extrude=0.02))
    out.append(P.box("Logo", (0.75, 0.05, 0.75), (-5.6, 1.0 - 4.84, 5.55), C["brand_green"], bevel=0.05, rot=(0, math.radians(45), 0)))
    # ---- the price board and the digital sign ----
    out.append(P.box("TotemFoot", (2.0, 0.9, 0.4), (-10.3, -5.6, 0.2), C["concrete_dark"], bevel=0.04))
    out.append(P.box("Totem", (1.7, 0.6, 6.8), (-10.3, -5.6, 3.6), C["white_panel"], bevel=0.04))
    out.append(P.box("TotemTop", (1.8, 0.65, 1.5), (-10.3, -5.6, 6.4), C["brand_red"], bevel=0.04))
    out.append(text("TotemBrand", "KONGU", (-10.3, -5.94, 6.55), 0.42, M["PlateWhite"], extrude=0.01))
    out.append(text("TotemBrand2", "FUELS", (-10.3, -5.94, 6.1), 0.3, M["PlateWhite"], extrude=0.01))
    for r, (nm, price) in enumerate((("PETROL", "101.50"), ("DIESEL", "93.40"), ("PREMIUM", "108.90"))):
        z = 4.95 - r * 0.8
        out.append(P.box("PriceRow", (1.5, 0.03, 0.66), (-10.3, -5.92, z), C["black_gloss"], bevel=0.01))
        out.append(text("PriceName", nm, (-10.85, -5.945, z + 0.14), 0.13, M["PlateWhite"], align='LEFT'))
        out.append(text("PriceVal", price, (-10.0, -5.945, z - 0.07), 0.3, C["led_price"]))
    out.append(P.box("DigitalSign", (1.5, 0.04, 0.9), (-10.3, -5.92, 2.2), C["black_gloss"], bevel=0.01))
    out.append(text("SignText", "UPI · CARDS", (-10.3, -5.945, 2.35), 0.13, C["led_green"]))
    out.append(text("SignText2", "FREE AIR", (-10.3, -5.945, 2.05), 0.16, C["led_green"]))
    # ---- the cashier's building: sales window, staff room, store ----
    bx0, bx1, by0, by1 = -4.2, 4.2, 6.2, 9.6
    out.append(P.box("BldPlinth", (8.6, 3.6, 0.3), (0, (by0 + by1) / 2, 0.15), C["concrete_dark"]))
    out.append(wall("BldFrontL", (bx0, by0), (-1.4, by0), 0.3, 3.3, C["wall"]))
    out.append(wall("BldFrontR", (1.4, by0), (bx1, by0), 0.3, 3.3, C["wall"]))
    out.append(wall("BldFrontTop", (-1.4, by0), (1.4, by0), 2.2, 3.3, C["wall"]))
    out.append(wall("BldFrontLow", (-1.4, by0), (1.4, by0), 0.3, 0.95, C["wall"]))
    out.append(wall("BldBack", (bx1, by1), (bx0, by1), 0.3, 3.3, C["wall"]))
    out.append(wall("BldSideL", (bx0, by1), (bx0, by0), 0.3, 3.3, C["wall"]))
    out.append(wall("BldSideR", (bx1, by0), (bx1, by1), 0.3, 3.3, C["wall"]))
    out.append(P.box("BldRoof", (8.8, 3.8, 0.2), (0, (by0 + by1) / 2, 3.4), C["concrete_dark"]))
    out.append(P.box("BldBand", (8.82, 3.82, 0.35), (0, (by0 + by1) / 2, 3.1), C["brand_green"]))
    out.append(P.box("SalesGlass", (2.8, 0.03, 1.25), (0, by0 - 0.01, 1.58), C["glass"]))
    out.append(P.box("SalesFrame", (2.9, 0.08, 0.06), (0, by0 - 0.03, 2.22), C["steel_brushed"]))
    out.append(P.box("SalesFrame", (2.9, 0.08, 0.06), (0, by0 - 0.03, 0.95), C["steel_brushed"]))
    out.append(P.box("SalesCounter", (3.0, 0.45, 0.06), (0, by0 - 0.2, 0.98), C["steel_brushed"]))
    out.append(P.box("Cashbox", (0.5, 0.4, 0.25), (0.7, by0 + 0.4, 1.1), C["black_gloss"], bevel=0.02))
    out.append(P.box("UPIBoard", (0.5, 0.02, 0.6), (-1.0, by0 - 0.04, 1.35), M["PlateWhite"], bevel=0.01))
    out.append(P.box("UPICode", (0.35, 0.01, 0.35), (-1.0, by0 - 0.055, 1.38), C["black_gloss"]))
    out.append(text("UPIText", "SCAN & PAY", (-1.0, by0 - 0.06, 1.12), 0.06, C["brand_red"]))
    out.append(P.box("Awning", (5.0, 1.4, 0.06), (0, by0 - 0.65, 2.6), C["awning"], rot=(math.radians(-10), 0, 0)))
    for x, lab in ((2.6, "STAFF"), (-2.9, "STORE")):
        out.append(P.box("Door", (0.95, 0.04, 2.1), (x, by0 - 0.02, 1.35), C["steel_dark"], bevel=0.01))
        out.append(P.box("DoorSign", (0.5, 0.01, 0.14), (x, by0 - 0.045, 2.55), M["PlateWhite"]))
        out.append(text("DoorLabel", lab, (x, by0 - 0.05, 2.55), 0.08, C["black_gloss"]))
    for k in range(5):                                         # oil cans on their rack
        for j in range(3):
            out.append(P.cyl("OilCan", 0.07, 0.22, (-4.0 + k * 0.17, by0 - 0.25, 0.42 + j * 0.36),
                             [C["brand_red"], C["brand_green"], C["diesel_yellow"]][j], axis='Z', segs=12))
    out.append(P.box("OilRack", (0.95, 0.35, 1.2), (-3.65, by0 - 0.25, 0.6), C["steel_dark"]))
    # ---- the air and water stand, the safety things ----
    out.append(P.box("AirStand", (0.55, 0.45, 1.5), (9.6, -2.5, 0.75), C["brand_green"], bevel=0.04))
    out.append(P.cyl("AirGauge", 0.13, 0.05, (9.6, -2.75, 1.25), C["white_panel"], rot=(math.pi / 2, 0, 0), segs=28))
    out.append(P.box("AirScreen", (0.3, 0.02, 0.12), (9.6, -2.74, 0.95), C["screen"]))
    out.append(text("AirLabel", "AIR · WATER", (9.6, -2.75, 1.48), 0.07, M["PlateWhite"]))
    out.append(P.helix("AirCoil", (9.35, -2.6, 0.5), (9.35, -2.6, 1.1), 0.12, 0.012, 5, M["Rubber"]))
    out.append(P.tube("AirHose", [(9.35, -2.6, 0.5), (9.2, -3.0, 0.15), (9.6, -3.3, 0.1), (9.9, -2.8, 0.4)], 0.013, M["Rubber"], smooth_pts=4))
    out.append(P.cyl("WaterTap", 0.04, 0.2, (9.85, -2.72, 0.7), C["steel_brushed"], rot=(math.pi / 2, 0, 0), segs=12))
    for (x, y) in ((-6.5, -1.0), (6.5, -1.0)):
        out.append(P.box("ExtStand", (0.5, 0.25, 0.08), (x + 0.6, y, 0.04), C["steel_dark"]))
        out.append(P.cyl("Extinguisher", 0.085, 0.55, (x + 0.6, y, 0.36), C["estop"], axis='Z', segs=18))
        out.append(P.cyl("ExtHead", 0.03, 0.1, (x + 0.6, y, 0.68), C["black_gloss"], axis='Z', segs=10))
    out.append(P.box("SandStand", (1.4, 0.3, 1.5), (-8.4, 8.0, 0.75), C["brand_red"]))
    for k in range(4):
        out.append(P.cyl("SandBucket", 0.13, 0.26, (-8.9 + k * 0.33, 7.82, 0.75), C["brand_red"], axis='Z', segs=16))
    out.append(text("SandLabel", "FIRE · SAND", (-8.4, 7.84, 1.3), 0.1, M["PlateWhite"]))
    # ---- what the game reads ----
    for k, ix in enumerate((-3.2, 3.2)):
        empty("Screen_%d" % (k + 1), (ix, 1.0 - 0.27, 1.6))
        empty("Bay_%d" % (k + 1), (ix, -0.6, 0.0), 0.0)
        empty("Attendant_%d" % (k + 1), (ix + 0.9, 0.2, 0.0), math.pi)
    return out


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = K.materials()
    objs = build(M)
    for o in list(bpy.data.objects):                       # (the modifiers applied: what the game gets is what's seen)
        if o.type == 'MESH' and o.modifiers:
            K.apply_mods(o)
    if "--export" in args:                                 # (one mesh: a draw call a material, not one a part)
        meshes = [o for o in bpy.data.objects if o.type == 'MESH']
        P.join(meshes, "KonguFuels")
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == 'MESH' for p in o.data.polygons)
    print("BUNK done: %d objects, %d triangles" % (len(objs), tris), flush=True)
    if "--export" in args:
        out = args[args.index("--export") + 1]
        bpy.ops.object.select_all(action='DESELECT')
        for o in bpy.data.objects:
            if not o.name.startswith("Preview"):
                o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_yup=True, export_apply=True,
                                  export_image_format='JPEG')
        print("BUNK exported %s (%.1f MB)" % (out, os.path.getsize(out) / 1e6), flush=True)
    if "--preview" in args:
        d = args[args.index("--preview") + 1]
        os.makedirs(d, exist_ok=True)
        K.previews(os.path.join(d, "bunk"), target=Vector((0, 1, 2.0)), dist=22.0,
                   views={"front34": (60, 14), "front": (90, 8), "side": (10, 10), "pumps": (75, 4)})
        cam = bpy.data.objects["PreviewCam"]
        sc = bpy.context.scene
        for nm, loc, tgt in (("pump", (-3.2, -2.3, 1.7), (-3.2, 1.0, 1.4)), ("building", (1.5, 1.5, 1.8), (0, 6.5, 1.5))):
            cam.location = loc
            cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(d, "bunk_%s.png" % nm)
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
