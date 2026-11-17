"""Kongu Two-Wheelers, Avinashi Road (made up; the dealer for Vela motorcycles and scooters, also made up): the
prologue's showroom interior, built in Blender from code (the redesign brief, stage 2).

    blender -b --factory-startup --python tools/cars/build_showroom.py -- [--export godot/assets/interiors/room_showroom.glb]
                                                                         [--preview dir]

18 × 12 m, 4.5 m high, the door on the −Y side (as every room: tools/building_interiors.py), laid out as a
dealership is: the glass front with its double door and the street's daylight beyond; large polished floor tiles;
a ceiling with lines of LED and spots over the vehicles; the brand wall at the back (backlit letters, an offers
screen); six display stands in two rows (white gloss tops on a lit edge, a spec tablet on a post beside each:
Mark_show_1..6, the story puts the vehicles there); the reception counter by the door; two sales desks with chairs;
the finance cabin behind glass at the back right; the visitors' sofas and a table of brochures; the accessories
wall (helmets, jackets, gloves on lit shelves); the service-information wall; the delivery bay (its floor
graphic, the ribbon arch). Marks the story uses: door, show_1..6, sales, karthik_sales, finance, karthik_finance,
reception, delivery, accessories; Cam_ / Look_ shots floor, sales, finance; Light_ empties for its lamps.
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

W, D, H = 18.0, 12.0, 4.5


def tex_tiles(size=1024, metres=18.0):
    """Large polished porcelain tiles (0.9 m), light grey with faint veining, thin dark grout."""
    def fn(xx, yy):
        u, v = xx * metres, yy * metres
        grout = (np.abs((u % 0.9) - 0.45) > 0.443) | (np.abs((v % 0.9) - 0.45) > 0.443)
        vein = np.clip(K._noise(size, 30, 41) - 0.5, 0, 1) * 0.12
        tile_tone = (np.floor(u / 0.9) * 7 + np.floor(v / 0.9) * 13) % 5 * 0.006
        g = 0.8 - vein + tile_tone + (K._noise(size, 3, 42) - 0.5) * 0.02
        g = np.where(grout, 0.42, g)
        return g, g * 0.995, g * 0.985
    return K._img("tex_showroom_tiles", size, fn)


def tex_plaster(size=512):
    def fn(xx, yy):
        g = 0.9 + (K._noise(size, 5, 51) - 0.5) * 0.025
        return g, g * 0.99, g * 0.97
    return K._img("tex_showroom_plaster", size, fn)


def tmat(name, img, rough=0.5, metal=0.0, coat=0.0):
    m = K._mat(name, (1, 1, 1), metal=metal, rough=rough, coat=coat)
    nt = m.node_tree
    p = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    nt.links.new(t.outputs[0], p.inputs["Base Color"])
    return m


def quad(name, pts, mat, uv_scale=(1.0, 1.0)):
    """A flat quad through four points with UVs in metres / uv_scale."""
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in pts]
    f = bm.faces.new(vs)
    uv = bm.loops.layers.uv.new()
    a, b, d = Vector(pts[0]), Vector(pts[1]), Vector(pts[3])
    eu, ev = (b - a), (d - a)
    for lp in f.loops:
        r = lp.vert.co - a
        lp[uv].uv = (r.dot(eu.normalized()) / uv_scale[0], r.dot(ev.normalized()) / uv_scale[1])
    return K.mesh_obj(name, bm, [mat])


def text(name, body, at, size, mat, rot=(math.pi / 2, 0, 0), align='CENTER', extrude=0.01):
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


def mark(name, x, y, yaw):
    """Where a person stands (yaw 0: facing +Y, the back wall), as the other rooms' marks."""
    return empty("Mark_" + name, (x, y, 0.0), yaw)


def shot(name, cam, look):
    empty("Cam_" + name, cam)
    empty("Look_" + name, look)


def chair(C, x, y, yaw, out):
    """An office chair: five-star base on castors, the gas column, a moulded seat and back."""
    for k in range(5):
        a = yaw + 2 * math.pi * k / 5
        out.append(P.box("ChairLeg", (0.32, 0.04, 0.03), (x + math.cos(a) * 0.16, y + math.sin(a) * 0.16, 0.08), C["chrome"], rot=(0, 0, a)))
        out.append(P.cyl("Castor", 0.025, 0.025, (x + math.cos(a) * 0.31, y + math.sin(a) * 0.31, 0.03), C["black"], segs=10))
    out.append(P.cyl("ChairColumn", 0.025, 0.35, (x, y, 0.27), C["chrome"], axis='Z', segs=12))
    out.append(P.box("ChairSeat", (0.48, 0.46, 0.08), (x, y, 0.47), C["upholstery"], bevel=0.03))
    bx, by = x - math.sin(yaw) * 0.22, y + math.cos(yaw) * 0.22
    out.append(P.box("ChairBack", (0.46, 0.06, 0.5), (bx, by, 0.8), C["upholstery"], rot=(math.radians(-8), 0, yaw), bevel=0.03))


def build(M):
    out = []
    C = {
        "tiles": tmat("ShowroomTiles", tex_tiles(), rough=0.12, coat=0.4),
        "plaster": tmat("ShowroomPlaster", tex_plaster(), rough=0.85),
        "ceiling": K._mat("Ceiling", (0.9, 0.9, 0.89), rough=0.9),
        "brand_red": K._mat("BrandRed", (0.5, 0.025, 0.03), rough=0.35, coat=0.4),
        "brand_dark": K._mat("BrandGraphite", (0.06, 0.065, 0.07), rough=0.4),
        "white_gloss": K._mat("WhiteGloss", (0.88, 0.88, 0.87), rough=0.15, coat=0.6),
        "chrome": M["Chrome"],
        "alu": K._mat("Aluminium", (0.75, 0.76, 0.78), metal=1.0, rough=0.25),
        "black": M["BlackGloss"],
        "glass": K._mat("ShowroomGlass", (0.6, 0.7, 0.72), rough=0.02, alpha=0.18, ior=1.52),
        "daylight": K._mat("Daylight", (1, 1, 1), rough=0.5, emit=(1.0, 0.98, 0.93), emit_k=2.2),
        "led": K._mat("LEDStrip", (1, 1, 1), rough=0.3, emit=(1.0, 0.98, 0.95), emit_k=6.0),
        "led_red": K._mat("LEDRed", (0.6, 0.0, 0.0), rough=0.3, emit=(1.0, 0.08, 0.05), emit_k=3.0),
        "letters": K._mat("BacklitWhite", (1, 1, 1), rough=0.3, emit=(1.0, 1.0, 0.97), emit_k=3.0),
        "screen": K._mat("OffersScreen", (0.05, 0.07, 0.12), rough=0.1, emit=(0.15, 0.3, 0.6), emit_k=1.0),
        "wood": K._mat("Walnut", (0.2, 0.1, 0.05), rough=0.45, coat=0.3),
        "upholstery": K._mat("Upholstery", (0.08, 0.08, 0.09), rough=0.7, normal=bpy.data.images.get("tex_fabric_weave"), normal_k=0.5, uv_scale=10.0),
        "sofa": K._mat("SofaGrey", (0.25, 0.26, 0.28), rough=0.85, normal=bpy.data.images.get("tex_fabric_weave"), normal_k=0.5, uv_scale=10.0),
        "paper": M["PlateWhite"],
        "helmet_r": K._mat("HelmetRed", (0.5, 0.03, 0.03), rough=0.2, coat=1.0),
        "helmet_b": K._mat("HelmetBlack", (0.03, 0.03, 0.035), rough=0.2, coat=1.0),
        "helmet_w": K._mat("HelmetWhite", (0.8, 0.8, 0.8), rough=0.2, coat=1.0),
        "helmet_y": K._mat("HelmetYellow", (0.8, 0.6, 0.05), rough=0.2, coat=1.0),
        "jacket": K._mat("Jacket", (0.07, 0.07, 0.08), rough=0.7),
        "plant": K._mat("Plant", (0.08, 0.3, 0.1), rough=0.8),
        "pot": K._mat("PotGrey", (0.35, 0.35, 0.36), rough=0.6),
        "ribbon": K._mat("Ribbon", (0.7, 0.05, 0.05), rough=0.4),
        "floor_graphic": K._mat("FloorGraphic", (0.5, 0.03, 0.04), rough=0.3),
        "poster": K._mat("PosterWhite", (0.92, 0.92, 0.9), rough=0.6),
        "poster_img": K._mat("PosterImage", (0.15, 0.2, 0.3), rough=0.5),
    }
    x0, x1, y0, y1 = -W / 2, W / 2, -D / 2, D / 2
    # ---- the shell: floor, ceiling, walls, the glass front ----
    out.append(quad("Floor", [(x0, y0, 0), (x1, y0, 0), (x1, y1, 0), (x0, y1, 0)], C["tiles"], (W, D)))
    out.append(P.box("FloorBase", (W, D, 0.1), (0, 0, -0.05), C["brand_dark"]))
    out.append(quad("Ceiling", [(x0, y1, H), (x1, y1, H), (x1, y0, H), (x0, y0, H)], C["ceiling"], (4, 4)))
    out.append(quad("BackWall", [(x1, y1, 0), (x0, y1, 0), (x0, y1, H), (x1, y1, H)], C["plaster"], (4, 4)))
    out.append(quad("LeftWall", [(x0, y1, 0), (x0, y0, 0), (x0, y0, H), (x0, y1, H)], C["plaster"], (4, 4)))
    out.append(quad("RightWall", [(x1, y0, 0), (x1, y1, 0), (x1, y1, H), (x1, y0, H)], C["plaster"], (4, 4)))
    for s, sx in ((1, x1), (-1, x0)):                           # skirting
        out.append(P.box("Skirting", (0.03, D, 0.1), (sx - s * 0.015, 0, 0.05), C["brand_dark"]))
    out.append(P.box("Skirting", (W, 0.03, 0.1), (0, y1 - 0.015, 0.05), C["brand_dark"]))
    # the glass front: a mullion every 2 m, a transom, the double door in the middle; daylight beyond
    out.append(P.box("FrontHeader", (W, 0.3, 0.6), (0, y0, H - 0.3), C["brand_dark"]))
    for k in range(10):
        x = x0 + k * 2.0
        out.append(P.box("Mullion", (0.08, 0.14, H - 0.6), (x, y0, (H - 0.6) / 2), C["alu"]))
    out.append(P.box("Mullion", (0.08, 0.14, H - 0.6), (x1, y0, (H - 0.6) / 2), C["alu"]))
    out.append(P.box("Transom", (W, 0.12, 0.08), (0, y0, 2.6), C["alu"]))
    out.append(P.box("FrontSill", (W, 0.2, 0.08), (0, y0, 0.04), C["alu"]))
    for k in range(9):
        cx = x0 + 1.0 + k * 2.0
        if abs(cx) < 0.5:
            continue                                            # (the doorway: its two leaves, open)
        out.append(P.box("FrontGlass", (1.9, 0.02, 2.55), (cx, y0, 1.32), C["glass"]))
        out.append(P.box("FrontGlassTop", (1.9, 0.02, H - 0.6 - 2.65), (cx, y0, 2.65 + (H - 0.6 - 2.65) / 2), C["glass"]))
    for s in (-1, 1):                                          # the door leaves swung open, their pull handles
        out.append(P.box("DoorLeaf", (0.95, 0.03, 2.5), (s * 1.35, y0 + 0.5, 1.3), C["glass"], rot=(0, 0, s * math.radians(80))))
        out.append(P.box("DoorFrame", (0.05, 0.05, 2.5), (s * 1.0, y0 + 0.02, 1.3), C["alu"]))
        out.append(P.cyl("DoorHandle", 0.015, 1.2, (s * 1.3, y0 + 0.9, 1.1), C["chrome"], axis='Z', segs=10))
    out.append(P.box("Doormat", (2.2, 1.2, 0.01), (0, y0 + 0.75, 0.005), C["brand_dark"]))
    out.append(P.box("DaylightOut", (W + 4, 0.05, H + 2), (0, y0 - 2.5, H / 2), C["daylight"]))
    out.append(P.box("Pavement", (W + 4, 2.6, 0.1), (0, y0 - 1.3, -0.04), C["tiles"]))
    # ---- the ceiling: LED lines and spots over the vehicles ----
    for y in (-3.5, -0.3, 2.9):
        out.append(P.box("LEDLine", (13.0, 0.08, 0.03), (-1.0, y, H - 0.02), C["led"]))
    for (sx, sy) in ((-5.0, -2.0), (-1.6, -2.0), (1.8, -2.0), (-5.0, 1.4), (-1.6, 1.4), (1.8, 1.4)):
        for dx in (-0.6, 0.6):
            out.append(P.cyl("Spot", 0.09, 0.08, (sx + dx, sy, H - 0.04), C["black"], axis='Z', segs=16))
            out.append(P.cyl("SpotLens", 0.07, 0.01, (sx + dx, sy, H - 0.085), C["led"], axis='Z', segs=16))
    # ---- the brand wall ----
    out.append(P.box("BrandPanel", (11.0, 0.08, 2.6), (-1.5, y1 - 0.06, 2.9), C["brand_red"], bevel=0.01))
    out.append(P.box("BrandPanelEdge", (11.1, 0.06, 0.04), (-1.5, y1 - 0.11, 1.58), C["led"]))
    out.append(text("BrandLetters", "KONGU TWO-WHEELERS", (-1.5, y1 - 0.12, 3.45), 0.62, C["letters"], rot=(math.pi / 2, 0, 0), extrude=0.04))
    out.append(text("BrandSub", "AUTHORISED DEALER  ·  VELA MOTORCYCLES & SCOOTERS", (-1.5, y1 - 0.11, 2.75), 0.17, C["letters"], rot=(math.pi / 2, 0, 0)))
    out.append(P.box("OffersScreen", (2.4, 0.06, 1.35), (-1.5, y1 - 0.15, 1.75) if False else (-6.2, y1 - 0.06, 1.7), C["screen"], bevel=0.01))
    out.append(P.box("OffersBezel", (2.5, 0.05, 1.45), (-6.2, y1 - 0.03, 1.7), C["black"], bevel=0.01))
    out.append(text("OffersText", "FESTIVE OFFER  ·  EASY EMI", (-6.2, y1 - 0.1, 1.95), 0.12, C["letters"]))
    out.append(text("OffersText2", "Down payment from 10%", (-6.2, y1 - 0.1, 1.65), 0.1, C["letters"]))
    # ---- six display stands ----
    for k, (sx, sy) in enumerate(((-5.0, -2.0), (-1.6, -2.0), (1.8, -2.0), (-5.0, 1.4), (-1.6, 1.4), (1.8, 1.4))):
        out.append(P.box("StandBase", (2.6, 1.3, 0.1), (sx, sy, 0.05), C["brand_dark"], bevel=0.02))
        out.append(P.box("StandTop", (2.5, 1.2, 0.04), (sx, sy, 0.12), C["white_gloss"], bevel=0.01))
        out.append(P.box("StandLED", (2.62, 1.32, 0.012), (sx, sy, 0.085), C["led"]))
        out.append(P.box("WheelChock", (0.25, 0.16, 0.08), (sx + 1.05, sy, 0.18), C["brand_dark"], bevel=0.02))
        px, py = sx + 0.9, sy - 0.85                            # the spec tablet on its post
        out.append(P.cyl("TabletPost", 0.025, 1.05, (px, py, 0.55), C["alu"], axis='Z', segs=12))
        out.append(P.box("TabletFoot", (0.3, 0.3, 0.02), (px, py, 0.01), C["alu"], bevel=0.01))
        out.append(P.box("Tablet", (0.32, 0.03, 0.22), (px, py, 1.12), C["black"], bevel=0.01, rot=(math.radians(-25), 0, 0)))
        out.append(P.box("TabletScreen", (0.28, 0.005, 0.18), (px, py - 0.017, 1.125), C["screen"], rot=(math.radians(-25), 0, 0)))
        mark("show_%d" % (k + 1), sx, sy, math.pi / 2)
    # ---- the reception counter by the door ----
    rx, ry = 6.2, -3.6
    out.append(P.box("Reception", (2.8, 0.7, 1.05), (rx, ry, 0.525), C["white_gloss"], bevel=0.03))
    out.append(P.box("ReceptionBand", (2.82, 0.72, 0.18), (rx, ry, 0.75), C["brand_red"]))
    out.append(P.box("ReceptionTop", (2.9, 0.8, 0.04), (rx, ry, 1.07), C["wood"], bevel=0.01))
    out.append(text("ReceptionWord", "RECEPTION", (rx, ry - 0.36, 0.75), 0.12, C["letters"]))
    out.append(P.box("ReceptionScreen", (0.45, 0.03, 0.3), (rx + 0.6, ry + 0.2, 1.3), C["black"], bevel=0.01))
    chair(C, rx, ry + 0.75, math.pi, out)
    mark("reception", rx, ry + 0.75, math.pi)
    # ---- two sales desks at the back ----
    for k, (dx, dy) in enumerate(((-5.0, 4.3), (-1.6, 4.3))):
        out.append(P.box("Desk", (1.7, 0.8, 0.04), (dx, dy, 0.75), C["wood"], bevel=0.01))
        for s in (-1, 1):
            out.append(P.box("DeskLeg", (0.05, 0.75, 0.73), (dx + s * 0.8, dy, 0.37), C["alu"]))
        out.append(P.box("Monitor", (0.55, 0.03, 0.34), (dx + 0.3, dy + 0.25, 1.05), C["black"], bevel=0.01))
        out.append(P.box("MonitorStand", (0.08, 0.08, 0.2), (dx + 0.3, dy + 0.28, 0.86), C["alu"]))
        out.append(P.box("Brochure", (0.22, 0.3, 0.01), (dx - 0.4, dy - 0.15, 0.775), C["brand_red"]))
        out.append(P.box("Nameplate", (0.3, 0.05, 0.08), (dx - 0.1, dy - 0.32, 0.8), C["black"], bevel=0.01))
        chair(C, dx, dy + 0.7, math.pi, out)
        for s in (-1, 1):
            chair(C, dx + s * 0.45, dy - 0.75, 0.0, out)
        if k == 0:
            mark("sales", dx, dy + 0.62, math.pi)
            mark("karthik_sales", dx, dy - 1.1, 0.0)
        else:
            mark("sales_2", dx, dy + 0.62, math.pi)
    # ---- the finance cabin behind glass, back right ----
    fx0, fx1, fy0 = 4.3, 8.9, 2.4
    out.append(P.box("CabinGlassL", (0.03, D / 2 - fy0, 2.6), (fx0, (fy0 + y1) / 2, 1.3), C["glass"]))
    out.append(P.box("CabinGlassF", (fx1 - fx0 - 1.0, 0.03, 2.6), ((fx0 + fx1) / 2 + 0.5, fy0, 1.3), C["glass"]))
    out.append(P.box("CabinFrame", (0.06, D / 2 - fy0, 0.06), (fx0, (fy0 + y1) / 2, 2.6), C["alu"]))
    out.append(P.box("CabinFrame", (fx1 - fx0, 0.06, 0.06), ((fx0 + fx1) / 2, fy0, 2.6), C["alu"]))
    out.append(P.box("CabinSign", (2.2, 0.04, 0.35), (6.6, fy0 - 0.03, 2.85), C["brand_dark"]))
    out.append(text("CabinWord", "FINANCE  ·  KONGU TWO-WHEELER FINANCE", (6.6, fy0 - 0.06, 2.85), 0.08, C["letters"]))
    fdx, fdy = 6.6, 4.3
    out.append(P.box("FinDesk", (2.0, 0.85, 0.04), (fdx, fdy, 0.75), C["wood"], bevel=0.01))
    out.append(P.box("FinDeskFront", (2.0, 0.04, 0.72), (fdx, fdy - 0.42, 0.38), C["white_gloss"]))
    out.append(P.box("FinMonitor", (0.55, 0.03, 0.34), (fdx + 0.4, fdy + 0.25, 1.05), C["black"], bevel=0.01))
    out.append(P.box("FinPrinter", (0.42, 0.35, 0.2), (fdx - 0.7, fdy + 0.2, 0.87), C["white_gloss"], bevel=0.02))
    for k in range(3):
        out.append(P.box("Forms", (0.21, 0.3, 0.004), (fdx - 0.1 + k * 0.02, fdy - 0.1, 0.775 + k * 0.004), C["paper"]))
    out.append(P.box("Almirah", (0.9, 0.5, 2.0), (8.4, 5.5, 1.0), C["brand_dark"], bevel=0.01))
    chair(C, fdx, fdy + 0.72, math.pi, out)
    for s in (-1, 1):
        chair(C, fdx + s * 0.45, fdy - 0.8, 0.0, out)
    mark("finance", fdx, fdy + 0.65, math.pi)
    mark("karthik_finance", fdx, fdy - 1.15, 0.0)
    # ---- the delivery bay, right side ----
    out.append(P.box("DeliveryFloor", (3.4, 3.2, 0.006), (6.6, 0.0, 0.004), C["floor_graphic"]))
    out.append(text("DeliveryWord", "DELIVERY", (6.6, -1.2, 0.009), 0.32, C["letters"], rot=(0, 0, 0), extrude=0.0))
    for s in (-1, 1):
        out.append(P.cyl("ArchPost", 0.05, 2.4, (6.6 + s * 1.5, 1.0, 1.2), C["alu"], axis='Z', segs=12))
    out.append(P.box("ArchTop", (3.1, 0.12, 0.3), (6.6, 1.0, 2.45), C["brand_red"], bevel=0.02))
    out.append(text("ArchWord", "CONGRATULATIONS", (6.6, 0.93, 2.45), 0.13, C["letters"]))
    out.append(P.tube("Ribbon", [(5.1, 1.0, 1.0), (6.6, 0.98, 0.9), (8.1, 1.0, 1.0)], 0.025, C["ribbon"], smooth_pts=4))
    mark("delivery", 6.6, -0.6, 0.0)
    # ---- the visitors' sofas and brochures, left of the door ----
    for k, (sx, sy, yaw) in enumerate(((-6.4, -4.6, 0.0), (-3.6, -4.6, 0.0))):
        out.append(P.box("SofaSeat", (2.0, 0.8, 0.42), (sx, sy, 0.21), C["sofa"], bevel=0.06))
        out.append(P.box("SofaBack", (2.0, 0.2, 0.5), (sx, sy - 0.32, 0.62), C["sofa"], bevel=0.06))
        for s in (-1, 1):
            out.append(P.box("SofaArm", (0.18, 0.8, 0.55), (sx + s * 0.95, sy, 0.3), C["sofa"], bevel=0.05))
    out.append(P.box("CoffeeTable", (1.2, 0.6, 0.04), (-5.0, -3.6, 0.42), C["glass"]))
    out.append(P.box("CoffeeTableBase", (1.1, 0.5, 0.38), (-5.0, -3.6, 0.2), C["alu"]))
    for k in range(4):
        out.append(P.box("Brochure", (0.22, 0.3, 0.01), (-5.4 + k * 0.26, -3.6, 0.445), [C["brand_red"], C["paper"], C["brand_red"], C["helmet_b"]][k], rot=(0, 0, 0.2 * k)))
    for (x, y) in ((-8.3, -5.4), (8.3, -5.4), (-8.3, 5.4)):
        out.append(P.cyl("Pot", 0.28, 0.6, (x, y, 0.3), C["pot"], axis='Z', segs=20))
        out.append(P.cyl("Plant", 0.45, 1.1, (x, y, 1.15), C["plant"], axis='Z', segs=10, r2=0.15))
    # ---- the accessories wall, left: helmets, jackets, gloves on lit shelves ----
    out.append(P.box("AccPanel", (0.06, 5.6, 2.8), (x0 + 0.03, 0.4, 1.7), C["brand_dark"]))
    out.append(text("AccWord", "GENUINE ACCESSORIES", (x0 + 0.08, 0.4, 3.35), 0.18, C["letters"], rot=(math.pi / 2, 0, -math.pi / 2)))
    for r, z in enumerate((0.9, 1.6, 2.3)):
        out.append(P.box("Shelf", (0.42, 5.2, 0.03), (x0 + 0.25, 0.4, z), C["white_gloss"]))
        out.append(P.box("ShelfLED", (0.02, 5.2, 0.01), (x0 + 0.45, 0.4, z - 0.02), C["led"]))
        if r < 2:
            for k in range(7):
                out.append(P.cyl("Helmet", 0.14, 0.2, (x0 + 0.25, -2.0 + k * 0.72, z + 0.13), [C["helmet_r"], C["helmet_b"], C["helmet_w"], C["helmet_y"]][k % 4],
                                 axis='Z', segs=20, r2=0.11))
                out.append(P.box("Visor", (0.04, 0.18, 0.08), (x0 + 0.38, -2.0 + k * 0.72, z + 0.14), C["black"]))
        else:
            for k in range(9):
                out.append(P.box("Gloves", (0.12, 0.16, 0.05), (x0 + 0.25, -2.1 + k * 0.56, z + 0.03), C["jacket"]))
    for k in range(4):                                         # jackets on a rail below
        out.append(P.box("Jacket", (0.08, 0.5, 0.65), (x0 + 0.3, 3.2 + k * 0.0 - 0.0, 1.3) if False else (x0 + 0.3, -4.8 + k * 0.55, 1.3), C["jacket"]))
    out.append(P.cyl("JacketRail", 0.015, 2.4, (x0 + 0.3, -4.0, 1.68), C["chrome"], axis='Y', segs=10))
    mark("accessories", x0 + 1.4, 0.4, -math.pi / 2)
    # ---- the service-information wall, right ----
    for k, (title, line) in enumerate((("SERVICE SCHEDULE", "1st free at 1,000 km"), ("GENUINE PARTS", "Ask at reception"), ("EASY EMI", "Kongu Two-Wheeler Finance"))):
        y = -1.8 + k * 1.5 if k < 2 else -4.6
        if k == 2:
            continue
        out.append(P.box("Poster", (0.03, 1.1, 1.5), (x1 - 0.02, y + 3.3, 1.8), C["poster"], bevel=0.005))
        out.append(P.box("PosterImg", (0.02, 0.9, 0.7), (x1 - 0.04, y + 3.3, 2.0), C["poster_img"]))
        out.append(text("PosterTitle", title, (x1 - 0.05, y + 3.3, 1.45), 0.07, C["brand_red"], rot=(math.pi / 2, 0, math.pi / 2)))
        out.append(text("PosterLine", line, (x1 - 0.05, y + 3.3, 1.3), 0.05, C["black"], rot=(math.pi / 2, 0, math.pi / 2)))
    # ---- lights the game makes (Light_<kind>_<n>), the shots ----
    n = 0
    for (lx, ly) in ((-5.0, -2.0), (-1.6, -2.0), (1.8, -2.0), (-5.0, 1.4), (-1.6, 1.4), (1.8, 1.4), (6.6, 4.0), (6.2, -3.0), (-5.0, -4.2)):
        empty("Light_tube_%d" % n, (lx, ly, H - 0.3))
        n += 1
    for k, lx in enumerate((-6.0, 0.0, 6.0)):
        empty("Light_window_%d" % k, (lx, y0 + 1.2, 2.2))
    mark("door", 0.0, y0 + 1.2, 0.0)
    empty("Entry", (0.0, y0 + 1.0, 0.0))
    empty("Exit", (0.0, y0 + 0.4, math.pi))
    shot("floor", (0.0, y0 + 0.8, 2.0), (-1.0, 0.5, 0.8))
    shot("sales", (-3.2, 2.4, 1.6), (-5.0, 4.6, 1.2))
    shot("finance", (5.0, 2.9, 1.6), (6.6, 4.8, 1.0))
    return out


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = K.materials()
    build(M)
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o.modifiers:
            K.apply_mods(o)
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == 'MESH' for p in o.data.polygons)
    print("SHOWROOM done: %d triangles" % tris, flush=True)
    if "--preview" in args:
        d = args[args.index("--preview") + 1]
        os.makedirs(d, exist_ok=True)
        sc = bpy.context.scene
        engines = [e.identifier for e in sc.render.bl_rna.properties["engine"].enum_items]
        sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
        sc.render.resolution_x, sc.render.resolution_y = 1280, 720
        w = bpy.data.worlds.new("W")
        sc.world = w
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.4
        for o in [o for o in bpy.data.objects if o.name.startswith("Light_")]:
            ld = bpy.data.lights.new(o.name, 'POINT')
            ld.energy = 900 if "tube" in o.name else 600
            ld.shadow_soft_size = 0.4
            lo = bpy.data.objects.new(o.name + "_L", ld)
            K.link(lo)
            lo.location = o.location
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        K.link(cam)
        cam.data.lens = 20
        sc.camera = cam
        for nm in ("floor", "sales", "finance"):
            c = bpy.data.objects["Cam_" + nm].location
            l = bpy.data.objects["Look_" + nm].location
            cam.location = c
            cam.rotation_euler = (l - c).to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(d, "showroom_%s.png" % nm)
            bpy.ops.render.render(write_still=True)
        for nm, c, l in (("back", (0, 5.5, 3.2), (0, -3, 0.8)), ("left", (6, -4, 2.5), (-7, 1, 1.2))):
            cam.location = c
            cam.rotation_euler = (Vector(l) - Vector(c)).to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(d, "showroom_%s.png" % nm)
            bpy.ops.render.render(write_still=True)
        for o in [o for o in bpy.data.objects if o.name.endswith("_L") or o.name == "PreviewCam"]:
            bpy.data.objects.remove(o)
    if "--export" in args:
        meshes = [o for o in bpy.data.objects if o.type == 'MESH']
        P.join(meshes, "Room")
        out = args[args.index("--export") + 1]
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_yup=True, export_apply=True,
                                  export_image_format='JPEG')
        print("SHOWROOM exported %s (%.1f MB)" % (out, os.path.getsize(out) / 1e6), flush=True)


if __name__ == "__main__":
    main()
