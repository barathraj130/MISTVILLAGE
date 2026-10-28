"""
Coimbatore's well-known buildings as the city sees them from the street, each designed on its own real footprint
(OpenStreetMap, the same outlines the city tiles hold: tools/landmark_lots.py finds them). Public places carry their
real names; private businesses a name of the story's own. Lettering in Tamil and Hindi is not made here (Blender
cannot shape those scripts): it is listed with the landmark in godot/assets/landmarks/landmarks.json "labels" and
drawn by the game (Label3D).

Each design: origin on its footprint at ground level, its front (the street side) towards -Y.

    Blender -b --factory-startup --python tools/landmarks.py -- [names...] [--preview DIR] [--no-export]

Writes godot/assets/landmarks/<name>.glb; city_streamer.gd puts each in place of the plain blocks on its lots.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import story_rooms as R  # noqa: E402  (box / cyl / text / mat / dome)
from hotel_grand import palm  # noqa: E402

OUT = os.path.join(HERE, "..", "godot", "assets", "landmarks")
BUS = os.path.join(HERE, "..", "godot", "assets", "vehicles", "fleet_bus.glb")
RAIL_YELLOW = (1.0, 0.78, 0.0)


def bus(x, y, yaw):
    """A city bus (godot/assets/vehicles/fleet_bus.glb: 10.9 m along its X) parked at x, y."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=BUS)
    new = set(bpy.data.objects) - before
    pivot = R._link(bpy.data.objects.new("BusPivot", None))        # the whole bus turns about one point
    for o in new:
        if o.parent is None:
            o.parent = pivot
    pivot.location = (x, y, 0.0)
    pivot.rotation_euler = (0, 0, yaw)
    bpy.context.view_layer.update()


def arcade(x0, x1, y, h, bay, pier, arch_m, wall_m):
    """A colonnade along a front: square piers every `bay` metres, round arches between them (a verandah)."""
    n = max(1, int(round((x1 - x0) / bay)))
    step = (x1 - x0) / n
    for k in range(n + 1):
        R.box((x0 + k * step, y, h / 2), (pier, pier, h), wall_m, 0.01)
    for k in range(n):                                   # each opening's arch: a band round its top (a half ring)
        cx = x0 + (k + 0.5) * step
        r = step / 2 - pier / 2
        for j in range(9):
            a = math.pi * j / 8
            R.box((cx + math.cos(a) * r, y, h - r * 0.55 + math.sin(a) * r * 0.55), (0.35, pier, 0.35), arch_m,
                  rot=(0, -a, 0))
    R.box(((x0 + x1) / 2, y, h + 0.35), (x1 - x0 + pier, pier, 0.7), wall_m, 0.01)


def windows_row(x0, x1, y, z, w, h, n, glass, frame, arched=False):
    for k in range(n):
        cx = x0 + (k + 0.5) * (x1 - x0) / n
        R.box((cx, y - 0.02, z), (w + 0.16, 0.06, h + 0.16), frame)
        R.box((cx, y - 0.05, z), (w, 0.04, h), glass)
        if arched:
            R.cyl((cx, y - 0.05, z + h / 2), w / 2, 0.04, glass, 16, rot=(math.pi / 2, 0, 0))
            R.cyl((cx, y - 0.02, z + h / 2), w / 2 + 0.08, 0.06, frame, 16, rot=(math.pi / 2, 0, 0))


# ---- Coimbatore Junction ----------------------------------------------------------------------------------------
def station():
    """Coimbatore Junction: the long two-floor station building beside platform 1 (124 m), cream with terracotta
    pilasters, cornice and arches, a verandah along the front; the entrance block standing forward of it with a
    porch on pillars for cars and autos, a clock in its gable and the yellow Indian Railways name board on top;
    behind, the platform under its long roof on steel columns, and the tracks."""
    L, Dp = 124.0, 13.7
    cream = R.mat("rail_cream", (0.86, 0.78, 0.6), 0.75)
    terra = R.mat("rail_terracotta", (0.55, 0.18, 0.1), 0.7)
    glass = R.mat("rail_glass", (0.18, 0.22, 0.24), 0.2, 0.3)
    frame = R.mat("rail_frame", (0.92, 0.9, 0.85), 0.5)
    roof = R.mat("platform_roof", (0.45, 0.47, 0.5), 0.5, 0.4)
    steel = R.mat("rail_steel", (0.3, 0.32, 0.35), 0.4, 0.8)
    yellow = R.mat("rail_board_yellow", RAIL_YELLOW, 0.5)
    # the long body: two floors, a terracotta plinth, pilasters, cornice and parapet
    R.box((0, 0, 4.5), (L, Dp, 9.0), cream, 0.03)
    R.box((0, -Dp / 2 - 0.05, 0.5), (L, 0.12, 1.0), terra)
    R.box((0, 0, 9.3), (L + 0.6, Dp + 0.6, 0.6), terra, 0.02)
    R.box((0, 0, 10.0), (L, Dp, 0.9), cream)
    for k in range(32):
        x = -L / 2 + 2 + k * (L - 4) / 31
        R.box((x, -Dp / 2 - 0.15, 4.6), (0.6, 0.3, 9.2), terra)
    windows_row(-L / 2 + 2, L / 2 - 2, -Dp / 2 - 0.02, 6.6, 1.3, 2.0, 31, glass, frame, arched=True)
    arcade(-L / 2 + 2, L / 2 - 2, -Dp / 2 - 1.9, 4.2, 4.0, 0.7, terra, cream)       # the verandah
    R.box((0, -Dp / 2 - 1.0, 4.9), (L - 3, 2.6, 0.3), cream)
    # the entrance block: three floors, forward of the body, a porch on pillars, the clock and the name board
    ex, ew, ed = 11.0, 23.0, 11.0
    R.box((ex, -Dp / 2 - ed / 2, 6.5), (ew, ed, 13.0), cream, 0.03)
    R.box((ex, -Dp / 2 - ed / 2, 13.3), (ew + 0.6, ed + 0.6, 0.6), terra, 0.02)
    R.cyl((ex, -Dp / 2 - ed - 0.02, 3.4), 3.2, 0.3, glass, 32, rot=(math.pi / 2, 0, 0))       # the great arch
    R.box((ex, -Dp / 2 - ed - 0.02, 1.7), (6.4, 0.3, 3.4), glass)
    for j in range(13):                                             # its terracotta ring
        a = math.pi * j / 12
        R.box((ex + math.cos(a) * 3.4, -Dp / 2 - ed - 0.12, 3.4 + math.sin(a) * 3.4), (0.45, 0.2, 0.9), terra, rot=(0, -a, 0))
    for s in (-1, 1):
        R.box((ex + s * 3.4, -Dp / 2 - ed - 0.12, 1.7), (0.45, 0.2, 3.4), terra)
    windows_row(ex - ew / 2 + 1, ex + ew / 2 - 1, -Dp / 2 - ed - 0.02, 9.2, 1.4, 2.4, 6, glass, frame, arched=True)
    for s in (-1, 1):
        R.box((ex + s * (ew / 2 - 0.6), -Dp / 2 - ed - 0.15, 6.6), (1.2, 0.3, 13.2), terra)
    pz = -Dp / 2 - ed                                               # the porch for cars and autos
    R.box((ex, pz - 6.5, 5.2), (ew - 2, 13.0, 0.5), cream, 0.02)
    R.box((ex, pz - 13.0, 5.2), (ew - 2, 0.12, 0.7), terra)
    for sx in (-1, 1):
        for yy in (pz - 12.4, pz - 6.0):
            R.cyl((ex + sx * (ew / 2 - 2.0), yy, 2.5), 0.4, 5.0, cream, 20)
    gable_z = 14.2                                                  # the clock in the gable
    R.box((ex, -Dp / 2 - ed + 0.5, gable_z + 1.5), (7.0, 1.0, 3.2), cream, 0.02)
    R.cyl((ex, -Dp / 2 - ed - 0.02, gable_z + 1.6), 1.2, 0.12, R.mat("clock_face", (0.97, 0.96, 0.9), 0.4), 32,
          rot=(math.pi / 2, 0, 0))
    for a, ln in ((math.radians(-60), 0.8), (math.radians(30), 1.0)):
        R.box((ex + math.sin(a) * ln / 2, -Dp / 2 - ed - 0.1, gable_z + 1.6 + math.cos(a) * ln / 2), (0.08, 0.04, ln),
              R.mat("clock_hand", (0.05, 0.05, 0.05), 0.4), rot=(0, a, 0))
    # the yellow name board on the porch's front (Tamil, Hindi, English: drawn by the game, landmarks.json labels)
    R.box((ex, pz - 13.12, 6.6), (17.0, 0.12, 2.6), yellow)
    R.box((ex, pz - 13.06, 6.6), (17.3, 0.06, 2.9), R.mat("board_frame_black", (0.05, 0.05, 0.05), 0.5))
    # the platform: its roof on steel columns, the platform edge, two tracks
    py = Dp / 2 + 5.5
    R.box((0, py, 0.45), (L + 40, 11.0, 0.9), R.mat("platform_slab", (0.62, 0.6, 0.56), 0.8))
    R.box((0, py + 5.3, 0.88), (L + 40, 0.4, 0.04), yellow)
    R.box((0, py, 6.0), (L + 40, 10.0, 0.25), roof)
    for k in range(28):
        R.cyl((-L / 2 - 20 + 2 + k * (L + 36) / 27, py, 3.4), 0.15, 5.2, steel, 12)
    ballast = R.mat("ballast", (0.36, 0.34, 0.32), 0.95)
    rail = R.mat("rail_steel_top", (0.55, 0.55, 0.56), 0.3, 0.9)
    sleeper = R.mat("sleeper", (0.42, 0.4, 0.38), 0.8)
    for ty in (py + 9.0, py + 14.0):
        R.box((0, ty, 0.15), (L + 40, 3.6, 0.3), ballast)
        for k in range(110):
            R.box((-L / 2 - 20 + k * (L + 40) / 109, ty, 0.33), (0.25, 2.6, 0.08), sleeper)
        for s in (-1, 1):
            R.box((0, ty + s * 0.84, 0.44), (L + 40, 0.08, 0.15), rail)
    # the forecourt: paving, the auto stand's railing, two palms
    R.box((ex, pz - 9.0, 0.06), (ew + 30, 20.0, 0.12), R.mat("forecourt", (0.5, 0.49, 0.47), 0.8))
    for x in (ex - 20, ex + 20):
        palm(x, pz - 15.0, 5.0)


# ---- Gandhipuram bus stands --------------------------------------------------------------------------------------
def bus_shed(length, width, h, roof_m, col_m):
    """A bus stand's platform: a raised island, a long butterfly roof on a row of concrete columns, benches."""
    R.box((0, 0, 0.15), (width * 0.45, length, 0.3), R.mat("bus_platform", (0.6, 0.58, 0.54), 0.8))
    for s in (-1, 1):
        R.box((s * width / 4, 0, h + 0.35 * s * 0 + 0.3), (width / 2 + 0.1, length, 0.25), roof_m, 0.01,
              rot=(0, s * math.radians(-6), 0))
    for k in range(int(length / 6) + 1):
        y = -length / 2 + k * length / int(length / 6)
        R.box((0, y, h / 2), (0.6, 0.6, h), col_m, 0.01)
        if k % 2:
            R.box((0, y + 1.5, 0.75), (0.5, 2.2, 0.08), R.mat("bench_steel", (0.6, 0.62, 0.64), 0.3, 0.7))


def bus_central():
    """Gandhipuram Central Bus Stand (mofussil buses): the long island platform under its butterfly roof, the office
    and enquiry block at the south end with the stand's name, buses angled in the bays both sides."""
    Ln = 78.0
    concrete = R.mat("bus_concrete", (0.78, 0.76, 0.72), 0.85)
    roof = R.mat("bus_roof_green", (0.15, 0.42, 0.3), 0.6)
    bus_shed(Ln, 14.0, 4.6, roof, concrete)
    R.box((0, -Ln / 2 - 4.0, 3.5), (9.0, 8.0, 7.0), concrete, 0.02)               # the office and enquiry
    R.box((0, -Ln / 2 - 8.05, 2.0), (6.0, 0.1, 2.4), R.mat("enquiry_glass", (0.2, 0.25, 0.28), 0.2, 0.3))
    R.box((0, -Ln / 2 - 8.1, 5.6), (8.6, 0.12, 1.8), R.mat("bus_board_green", (0.05, 0.35, 0.2), 0.5))
    R.text("GANDHIPURAM CENTRAL BUS STAND", (0, -Ln / 2 - 8.18, 5.25), 0.42, R.mat("letters_white", (0.97, 0.97, 0.97), 0.4), "-y")
    for k in range(5):
        for s in (-1, 1):
            bus(s * 7.0, -Ln / 2 + 12 + k * 14.0, math.pi / 2 + s * math.radians(20))


def bus_town():
    """Gandhipuram Town Bus Stand: the four-floor shops-and-offices block along the road with the stand's name,
    an arched passage through to the bays; behind it the long platform under its roof, the city buses at it."""
    W, D, H = 92.0, 13.0, 14.0
    plaster = R.mat("town_plaster", (0.85, 0.82, 0.74), 0.85)
    band = R.mat("town_band_blue", (0.12, 0.3, 0.55), 0.6)
    glass = R.mat("rail_glass", (0.18, 0.22, 0.24), 0.2, 0.3)
    frame = R.mat("rail_frame", (0.92, 0.9, 0.85), 0.5)
    R.box((0, 0, H / 2), (W, D, H), plaster, 0.03)
    for f in range(1, 4):
        R.box((0, -D / 2 - 0.1, f * 3.5), (W, 0.25, 0.35), band)
        windows_row(-W / 2 + 1, W / 2 - 1, -D / 2 - 0.02, f * 3.5 + 1.7, 1.6, 1.5, 24, glass, frame)
    for k in range(18):                                             # shop shutters on the ground floor
        x = -W / 2 + 3 + k * (W - 6) / 17
        if abs(x) < 6:
            continue
        R.box((x, -D / 2 - 0.03, 1.4), (3.6, 0.05, 2.6), R.mat("shutter_grey", (0.55, 0.56, 0.57), 0.5, 0.6))
        R.box((x, -D / 2 - 0.4, 3.1), (4.6, 0.8, 0.12), R.mat("shop_awning", (0.75, 0.25, 0.15), 0.7))
    R.box((0, -D / 2 - 0.05, 2.2), (9.0, 0.1, 4.4), R.mat("passage_dark", (0.1, 0.1, 0.1), 0.9))      # the passage
    R.cyl((0, -D / 2 - 0.06, 4.4), 4.5, 0.1, R.mat("passage_dark", (0.1, 0.1, 0.1), 0.9), 24, rot=(math.pi / 2, 0, 0))
    R.box((0, -D / 2 - 0.15, H - 1.2), (30.0, 0.15, 2.0), R.mat("bus_board_green", (0.05, 0.35, 0.2), 0.5))
    R.text("GANDHIPURAM TOWN BUS STAND", (0, -D / 2 - 0.25, H - 1.0), 0.75, R.mat("letters_white", (0.97, 0.97, 0.97), 0.4), "-y")
    R.box((0, 0, H + 0.4), (W + 0.4, D + 0.4, 0.8), band)
    # the platform behind (its footprint: 70 m x 6.5 m, 19.3 m back, 12 m along)
    R.box((12.0, 19.3, 0.15), (70.0, 6.5, 0.3), R.mat("bus_platform", (0.6, 0.58, 0.54), 0.8))
    R.box((12.0, 19.3, 4.8), (72.0, 13.0, 0.25), R.mat("bus_roof_green", (0.15, 0.42, 0.3), 0.6))
    for k in range(13):
        R.box((12.0 - 35 + k * 70 / 12, 19.3, 2.4), (0.5, 0.5, 4.8), R.mat("bus_concrete", (0.78, 0.76, 0.72), 0.85))
    for k in range(5):
        bus(12.0 - 28 + k * 14.0, 19.3 + 7.5, math.radians(-70))


# ---- the malls (names of the story's own) ------------------------------------------------------------------------
def mall(W, D, H, name, panel, accent, forecourt):
    """A modern Coimbatore mall: a big box in aluminium-composite panels of two tones with glazed bands, a full-height
    glass atrium at the middle of the front under a steel canopy with the name lit above it, a multiplex block on
    the roof, side entrances, palms and bollards on the forecourt (`forecourt` metres deep, in front of -D/2)."""
    glass = R.mat("mall_glass", (0.2, 0.32, 0.4), 0.05, 0.8)
    lit = R.mat("mall_lit", (1.0, 0.95, 0.85), 0.3, emit=(1.0, 0.92, 0.75), strength=2.5)
    steel = R.mat("mall_steel", (0.75, 0.76, 0.78), 0.3, 0.9)
    paving = R.mat("mall_paving", (0.62, 0.58, 0.52), 0.7)
    y0 = -D / 2
    R.box((0, 0, H / 2), (W, D, H), panel, 0.05)
    for z in (H * 0.33, H * 0.66):                                       # glazed bands round the box
        R.box((0, y0 - 0.05, z), (W - 0.5, 0.1, 1.6), glass)
        for sx in (-1, 1):
            R.box((sx * (W / 2 + 0.05), 0, z), (0.1, D - 0.5, 1.6), glass)
    for k in range(int(W / 6)):                                          # panel joints in the accent tone
        x = -W / 2 + 3 + k * 6.0
        R.box((x, y0 - 0.06, H / 2), (0.3, 0.12, H), accent)
    aw = min(40.0, W * 0.4)                                              # the atrium
    R.box((0, y0 - 1.5, (H + 6) / 2), (aw, 3.0, H + 6), glass)
    for k in range(9):
        R.box((-aw / 2 + k * aw / 8, y0 - 3.05, (H + 6) / 2), (0.25, 0.25, H + 6), steel)
    for z in range(5, int(H + 6), 5):
        R.box((0, y0 - 3.05, z), (aw, 0.2, 0.2), steel)
    R.box((0, y0 - 7.0, 5.2), (aw + 6, 8.0, 0.5), steel, 0.02)          # the canopy
    for sx in (-1, 1):
        R.cyl((sx * (aw / 2 + 2), y0 - 10.5, 2.6), 0.25, 5.2, steel, 16)
    R.box((0, y0 - 3.4, H + 3.5), (aw - 2, 0.3, 4.0), accent)            # the name over the atrium
    R.text(name, (0, y0 - 3.6, H + 3.0), min(2.6, (aw - 3) / (len(name) * 0.62)), lit, "-y")
    mw, md = W * 0.38, D * 0.35                                          # the multiplex on the roof
    R.box((W / 2 - mw / 2 - 2, D / 2 - md / 2 - 2, H + 5), (mw, md, 10), accent, 0.05)
    R.text("MULTIPLEX", (W / 2 - mw / 2 - 2, D / 2 - md - 2.1, H + 6), 1.6, lit, "-y")
    for sx in (-1, 1):                                                   # side entrances
        R.box((sx * (W / 2 + 0.1), -D / 6, 3.0), (0.2, 10.0, 6.0), glass)
        R.box((sx * (W / 2 + 2.5), -D / 6, 6.2), (5.0, 12.0, 0.4), steel)
    R.box((0, y0 - forecourt / 2, 0.06), (W + 10, forecourt, 0.12), paving)
    for k in range(-3, 4):
        if k:
            palm(k * W / 8, y0 - forecourt + 3.0, 6.0)
    for k in range(14):
        R.cyl((-W / 2 + 4 + k * (W - 8) / 13, y0 - forecourt + 0.6, 0.45), 0.12, 0.9, steel, 10)
    R.text("FOOD COURT", (-W / 4, y0 - 0.1, H * 0.66 + 1.6), 1.0, lit, "-y")


def mall_avinashi():
    """The Noyyal Galleria on Avinashi Road (where Fun Republic stands): 62 m along the road, 104 m deep."""
    mall(62.0, 104.0, 18.0, "THE NOYYAL GALLERIA", R.mat("acp_silver", (0.72, 0.73, 0.75), 0.35, 0.6),
         R.mat("acp_red", (0.62, 0.08, 0.1), 0.4, 0.3), 10.0)


def mall_sathy():
    """Kongu Mall on Sathy Road, Saravanampatti (where Prozone stands): 170 m along the road, 100 m deep."""
    mall(170.0, 100.0, 22.0, "KONGU MALL", R.mat("acp_sand", (0.78, 0.7, 0.58), 0.4, 0.4),
         R.mat("acp_teal", (0.05, 0.38, 0.42), 0.4, 0.4), 15.0)


LANDMARKS = {"station": station, "bus_central": bus_central, "bus_town": bus_town, "mall_avinashi": mall_avinashi,
             "mall_sathy": mall_sathy}


def export(name):
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    path = os.path.join(OUT, name + ".glb")
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
                              export_image_format='JPEG')
    print("EXPORT", path, "%.1f MB, %d tris" % (os.path.getsize(path) / 1e6, sum(len(p.vertices) - 2 for p in ob.data.polygons)),
          flush=True)


def preview(name, out_dir):
    sc = bpy.context.scene
    engines = [e.identifier for e in sc.render.bl_rna.properties["engine"].enum_items]
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 1280, 800
    sc.render.image_settings.file_format = 'JPEG'
    sc.view_settings.view_transform = "Standard"
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.65, 0.78, 0.95, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    sc.world = w
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for o in bpy.data.objects:
        if o.type == 'MESH':
            for c in o.bound_box:
                v = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, v))
                hi = Vector(map(max, hi, v))
    R.box((0, -40, -0.05), (400, 400, 0.1), R.mat("road_asphalt", (0.3, 0.3, 0.31), 0.8))
    size = max(hi.x - lo.x, hi.y - lo.y, 20.0)
    mid = (lo + hi) / 2
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    for tag, off, lens in (("street", (-0.25, -0.75, 0.02), 22), ("aerial", (-0.6, -0.9, 0.55), 30)):
        cam.data.lens = lens
        cam.location = mid + Vector(off) * size + Vector((0, 0, 1.7))
        cam.rotation_euler = (mid + Vector((0, 0, 4)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(out_dir, "%s_%s.jpg" % (name, tag))
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", sc.render.filepath, flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in args if a in LANDMARKS] or list(LANDMARKS)
    prev = os.path.abspath(args[args.index("--preview") + 1]) if "--preview" in args else None
    for n in names:
        R.reset()
        LANDMARKS[n]()
        if "--no-export" not in args:
            export(n)
        if prev:
            os.makedirs(prev, exist_ok=True)
            preview(n, prev)


if __name__ == "__main__":
    main()
