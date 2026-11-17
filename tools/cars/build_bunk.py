"""A petrol bunk (docs/PROLOGUE_PLAN_2026-11-17.md, the fuel stage): a made-up brand ("Kongu Fuels"), as the
privately run bunks keep made-up names in the game. The canopy on four columns with its lit fascia, two pump islands
with a dispenser each (two faces: the amount, the litres and the price on lit screens; nozzles in their holsters;
hoses), kerbed islands with bollards, the price board on its totem (petrol, diesel, premium), the sales kiosk with its
counter window, the air-and-water stand, oil cans on a rack, a fire-sand bucket stand.

    blender -b --factory-startup --python tools/cars/build_bunk.py -- [--export out.glb] [--preview dir]

Origin at the forecourt's middle on the ground; +X along the road (the bays run along X), the road on the −Y side.
Empties the game reads: Bay_1 / Bay_2 (where a vehicle stops beside its pump, facing +X), Attendant_1 / _2 (where
the attendant stands), Screen_1 / _2 (the dispenser's front screen, for the running figures).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import carkit as K  # noqa: E402
import parts as P  # noqa: E402


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


def build(M):
    out = []
    white = K._mat("CanopyWhite", (0.88, 0.88, 0.86), rough=0.4)
    red = K._mat("BrandRed", (0.6, 0.04, 0.05), rough=0.35, coat=0.3)
    green = K._mat("BrandGreen", (0.02, 0.32, 0.16), rough=0.4)
    lit = K._mat("FasciaLit", (0.95, 0.95, 0.9), rough=0.3, emit=(1.0, 0.98, 0.92), emit_k=1.2)
    led = K._mat("PriceLED", (0.1, 0.02, 0.0), rough=0.3, emit=(1.0, 0.25, 0.05), emit_k=3.0)
    concrete = K._mat("Forecourt", (0.42, 0.42, 0.41), rough=0.9)
    kerb = K._mat("KerbYellow", (0.75, 0.6, 0.06), rough=0.7)
    steel = M["Steel"]
    # the forecourt slab and the islands
    out.append(P.box("Forecourt", (22.0, 14.0, 0.06), (0, 0.5, 0.03), concrete))
    for ix in (-3.2, 3.2):
        out.append(P.box("Island", (5.2, 1.2, 0.18), (ix, 1.0, 0.12), concrete, bevel=0.02))
        for s in (1, -1):
            out.append(P.box("IslandKerb", (5.24, 0.06, 0.2), (ix, 1.0 + s * 0.6, 0.12), kerb))
        for ex in (-2.3, 2.3):
            out.append(P.cyl("Bollard", 0.08, 0.9, (ix + ex, 1.0, 0.6), kerb, axis='Z', segs=16))
    # the canopy: four columns, the deck, the lit fascia in the brand's colours, lights under it
    for x in (-6.5, 6.5):
        for y in (1.0,):
            out.append(P.box("Column", (0.45, 0.45, 5.4), (x, y, 2.75), white, bevel=0.02))
    out.append(P.box("CanopyDeck", (17.0, 9.0, 0.35), (0, 1.0, 5.55), white, bevel=0.03))
    for s in (1, -1):
        out.append(P.box("Fascia", (17.1, 0.08, 0.9), (0, 1.0 + s * 4.52, 5.5), lit))
        out.append(P.box("FasciaStripe", (17.12, 0.09, 0.22), (0, 1.0 + s * 4.53, 5.15), red))
        out.append(P.box("FasciaStripe", (17.12, 0.09, 0.08), (0, 1.0 + s * 4.53, 5.92), green))
    for s in (1, -1):
        out.append(P.box("FasciaEnd", (0.08, 9.1, 0.9), (s * 8.52, 1.0, 5.5), lit))
    out.append(text("BrandFront", "KONGU FUELS", (0, 1.0 - 4.58, 5.52), 0.55, red))
    out.append(text("BrandBack", "KONGU FUELS", (0, 1.0 + 4.58, 5.52), 0.55, red, rot=(math.pi / 2, 0, math.pi)))
    for x in (-5.0, -2.0, 2.0, 5.0):
        for y in (-1.5, 3.5):
            out.append(P.box("CanopyLight", (1.2, 0.5, 0.04), (x, y, 5.36), lit))
    # the dispensers: a body, the two lit faces (amount / litres / price), nozzles, hoses
    for k, ix in enumerate((-3.2, 3.2)):
        out.append(P.box("Dispenser", (0.9, 0.5, 1.95), (ix, 1.0, 1.18), white, bevel=0.03))
        out.append(P.box("DispenserTop", (0.92, 0.52, 0.35), (ix, 1.0, 2.15), red, bevel=0.02))
        out.append(text("DispLabel", "PETROL", (ix, 1.0 - 0.27, 2.15), 0.13, M["PlateWhite"]))
        out.append(text("DispLabelB", "PETROL", (ix, 1.0 + 0.27, 2.15), 0.13, M["PlateWhite"], rot=(math.pi / 2, 0, math.pi)))
        for s in (-1, 1):
            y = 1.0 + s * 0.255
            out.append(P.box("DispScreen", (0.62, 0.01, 0.42), (ix, y, 1.6), M["Screen"]))
            # (the figures on the screen are the game's own: fuel_bunks.gd writes them as the pump runs)
            out.append(P.box("Keypad", (0.24, 0.012, 0.18), (ix - 0.18, y, 1.25), M["BlackGloss"], bevel=0.01))
            nz = P.box("Nozzle", (0.06, 0.08, 0.25), (ix + 0.32, y + s * 0.06, 1.05), M["BlackGloss"], bevel=0.01, rot=(s * 0.3, 0, 0))
            out.append(nz)
            out.append(P.tube("Hose", [(ix + 0.3, 1.0 + s * 0.24, 1.95), (ix + 0.55, 1.0 + s * 0.45, 1.3), (ix + 0.45, 1.0 + s * 0.35, 0.6),
                                       (ix + 0.34, 1.0 + s * 0.3, 1.0)], 0.018, M["Rubber"], smooth_pts=6))
        empty("Screen_%d" % (k + 1), (ix, 1.0 - 0.27, 1.6))
        empty("Bay_%d" % (k + 1), (ix, -0.6, 0.0), 0.0)
        empty("Attendant_%d" % (k + 1), (ix + 0.9, 0.2, 0.0), math.pi)
    # the price board on its totem, by the road
    out.append(P.box("Totem", (1.5, 0.5, 6.2), (-9.8, -4.6, 3.1), white, bevel=0.03))
    out.append(P.box("TotemTop", (1.6, 0.55, 1.3), (-9.8, -4.6, 5.8), red, bevel=0.03))
    out.append(text("TotemBrand", "KONGU", (-9.8, -4.9, 5.85), 0.4, M["PlateWhite"]))
    for r, (nm, price) in enumerate((("PETROL", "101.50"), ("DIESEL", "93.40"), ("PREMIUM", "108.90"))):
        z = 4.5 - r * 0.85
        out.append(P.box("PriceRow", (1.3, 0.02, 0.62), (-9.8, -4.86, z), M["BlackGloss"]))
        out.append(text("PriceName", nm, (-10.15, -4.88, z + 0.12), 0.15, M["PlateWhite"]))
        out.append(text("PriceVal", price, (-9.6, -4.88, z - 0.08), 0.28, led))
    # the sales kiosk at the back: walls, a window and its counter, the roof
    out.append(P.box("Kiosk", (5.0, 3.2, 3.0), (0, 7.2, 1.5), white, bevel=0.02))
    out.append(P.box("KioskBand", (5.05, 3.25, 0.4), (0, 7.2, 2.8), green))
    out.append(P.box("KioskWindow", (2.4, 0.03, 1.2), (0, 5.59, 1.55), M["Glass"]))
    out.append(P.box("KioskCounter", (2.6, 0.4, 0.06), (0, 5.45, 0.98), steel))
    out.append(P.box("KioskDoor", (0.9, 0.03, 2.1), (1.9, 5.59, 1.05), M["BlackTrim"]))
    out.append(text("KioskSign", "SALES · UPI ACCEPTED", (0, 5.57, 2.35), 0.2, M["PlateWhite"]))
    for k in range(4):                                         # oil cans on a rack by the kiosk
        for j in range(3):
            out.append(P.cyl("OilCan", 0.07, 0.22, (-2.2 + k * 0.17, 5.4, 0.4 + j * 0.35), [red, green, M["Paint"]][j], axis='Z', segs=12))
    out.append(P.box("OilRack", (0.8, 0.3, 1.1), (-1.95, 5.45, 0.55), steel))
    # the air-and-water stand, the fire-sand buckets
    out.append(P.box("AirStand", (0.4, 0.4, 1.3), (8.0, -1.0, 0.65), M["Paint"], bevel=0.02))
    out.append(P.tube("AirHose", [(8.0, -1.2, 1.1), (8.2, -1.5, 0.5), (8.0, -1.3, 0.2)], 0.012, M["Rubber"], smooth_pts=4))
    out.append(P.box("FireStand", (1.2, 0.25, 1.4), (-7.5, 5.6, 0.7), red))
    for k in range(4):
        out.append(P.cyl("FireBucket", 0.13, 0.25, (-7.95 + k * 0.3, 5.45, 0.6), red, axis='Z', segs=14))
    return out


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = K.materials()
    objs = build(M)
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == 'MESH' for p in o.data.polygons)
    print("BUNK done: %d objects, %d triangles" % (len(objs), tris), flush=True)
    if "--export" in args:
        out = args[args.index("--export") + 1]
        bpy.ops.object.select_all(action='DESELECT')
        for o in bpy.data.objects:
            if not o.name.startswith("Preview"):
                o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_yup=True, export_apply=True)
        print("BUNK exported %s (%.1f MB)" % (out, os.path.getsize(out) / 1e6), flush=True)
    if "--preview" in args:
        d = args[args.index("--preview") + 1]
        os.makedirs(d, exist_ok=True)
        K.previews(os.path.join(d, "bunk"), target=Vector((0, 1, 2.0)), dist=20.0,
                   views={"front34": (300, 14), "front": (270, 8), "top34": (320, 40)})


if __name__ == "__main__":
    main()
