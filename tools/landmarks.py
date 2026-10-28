"""
Coimbatore's well-known buildings as the city sees them from the street, each designed on its own real footprint
(OpenStreetMap, the same outlines the city tiles hold: tools/landmark_lots.py finds them). Public places carry their
real names; privately owned ones (businesses, trusts, associations) a name of the story's own. Lettering in Tamil and Hindi is not made here (Blender
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


# ---- civic and heritage ------------------------------------------------------------------------------------------
def gable(cx, cy, w, d, z, rise, m):
    """A pitched roof over a w (x) by d (y) block whose eaves are at z, ridge along y."""
    ang = math.atan2(rise, w / 2)
    ln = math.hypot(rise, w / 2)
    for s in (-1, 1):
        R.box((cx + s * w / 4, cy, z + rise / 2), (ln + 0.3, d + 0.6, 0.25), m, rot=(0, s * ang, 0))


def pointed_window(x, y, z, w, h, glass, frame, facing_y=True):
    """A tall window with a pointed (gothic) head, on a face looking -y (facing_y) or -x."""
    if facing_y:
        R.box((x, y, z), (w, 0.06, h), glass)
        R.box((x, y, z + h / 2), (w * 0.72, 0.06, w * 0.72), glass, rot=(0, math.radians(45), 0))
        R.box((x, y + 0.02, z - h / 2 - 0.1), (w + 0.3, 0.1, 0.12), frame)
    else:
        R.box((x, y, z), (0.06, w, h), glass)
        R.box((x, y, z + h / 2), (0.06, w * 0.72, w * 0.72), glass, rot=(math.radians(45), 0, 0))


def india_flag(x, y, top):
    from hotel_grand import flag
    flag(x, y, top, [(1.0, 0.318, 0.033), (0.95, 0.95, 0.93), (0.0065, 0.246, 0.0024)], chakra=True)


def collectorate():
    """The District Collectorate: a four-floor government building in red brick with white trim, arcaded verandahs
    on every floor along its 92 m front, a central entrance block rising to a tower with a small dome, the
    national flag in front, its name in English (and Tamil, by the game)."""
    W, D, H = 92.0, 40.0, 16.0
    brick = R.mat("collectorate_brick", (0.55, 0.2, 0.13), 0.8)
    white = R.mat("trim_white", (0.93, 0.92, 0.88), 0.6)
    glass = R.mat("rail_glass", (0.18, 0.22, 0.24), 0.2, 0.3)
    R.box((0, 0, H / 2), (W, D, H), brick, 0.03)
    for f in range(4):
        z0 = f * 4.0
        if f == 0:                                                   # the ground floor's arcade
            arcade(-W / 2 + 1, W / 2 - 1, -D / 2 - 1.4, z0 + 3.2, 4.2, 0.6, white, brick)
        R.box((0, -D / 2 - 0.1, z0 + 4.0), (W, 0.3, 0.3), white)
        windows_row(-W / 2 + 2, W / 2 - 2, -D / 2 - 0.02, z0 + 2.2, 1.2, 2.0, 22, glass, white, arched=True)
    R.box((0, 0, H + 0.4), (W + 0.6, D + 0.6, 0.8), white, 0.02)
    tw = 14.0                                                        # the entrance block and its tower
    R.box((0, -D / 2 - 3.0, 9.0), (tw, 6.0, 18.0), brick, 0.03)
    R.box((0, -D / 2 - 3.0, 18.3), (tw + 0.6, 6.6, 0.6), white)
    R.box((0, -D / 2 - 3.0, 22.0), (7.0, 6.0, 7.0), brick, 0.02)
    R.box((0, -D / 2 - 3.0, 25.7), (7.6, 6.6, 0.5), white)
    R.dome((0, -D / 2 - 3.0, 25.9), 2.8, 3.2, white, segs=24)
    R.cyl((0, -D / 2 - 3.0, 30.0), 0.12, 1.6, R.mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0), 8)
    R.cyl((0, -D / 2 - 6.02, 2.6), 2.2, 0.1, glass, 24, rot=(math.pi / 2, 0, 0))
    R.box((0, -D / 2 - 6.02, 1.3), (4.4, 0.1, 2.6), glass)
    R.box((0, -D / 2 - 6.1, 14.6), (12.0, 0.12, 1.8), white)
    R.text("DISTRICT COLLECTORATE", (0, -D / 2 - 6.2, 14.85), 0.62, R.mat("letters_maroon", (0.4, 0.05, 0.05), 0.5), "-y")
    india_flag(-10.0, -D / 2 - 8.0, 12.0)
    R.box((0, -D / 2 - 5.0, 0.06), (W, 10.0, 0.12), R.mat("forecourt", (0.5, 0.49, 0.47), 0.8))
    for x in (-30, -15, 15, 30):
        palm(x, -D / 2 - 7.0, 6.0)


def clock_tower():
    """The Town Hall clock tower: a stepped base, a cream shaft banded in maroon, the clock stage with a face on
    each side, a cornice, an open cupola and its finial (about 20 m)."""
    cream = R.mat("tower_cream", (0.9, 0.84, 0.68), 0.7)
    maroon = R.mat("tower_maroon", (0.45, 0.1, 0.08), 0.6)
    face = R.mat("clock_face", (0.97, 0.96, 0.9), 0.4)
    hand = R.mat("clock_hand", (0.05, 0.05, 0.05), 0.4)
    R.box((0, 0, 0.5), (6.5, 6.5, 1.0), maroon, 0.02)
    R.box((0, 0, 1.4), (5.5, 5.5, 0.8), cream, 0.02)
    R.box((0, 0, 7.15), (4.2, 4.2, 10.8), cream, 0.03)
    for z in (4.0, 8.0, 12.0):
        R.box((0, 0, z), (4.5, 4.5, 0.35), maroon)
    R.box((0, 0, 14.3), (4.8, 4.8, 3.6), cream, 0.03)
    for a in range(4):
        ang = a * math.pi / 2
        dx, dy = -math.sin(ang), -math.cos(ang)
        fx, fy = dx * 2.42, dy * 2.42
        R.cyl((fx, fy, 14.3), 1.35, 0.1, face, 32, rot=(math.pi / 2, 0, ang))
        R.cyl((fx, fy, 14.3), 1.5, 0.06, maroon, 32, rot=(math.pi / 2, 0, ang))
        for h_ang, ln in ((math.radians(-60), 0.8), (math.radians(60), 1.1)):
            R.box((fx + dx * 0.08 + math.cos(ang) * math.sin(h_ang) * ln / 2, fy + dy * 0.08 - math.sin(ang) * math.sin(h_ang) * ln / 2,
                   14.3 + math.cos(h_ang) * ln / 2), (0.08, 0.08, ln), hand, rot=(0, h_ang, -ang))
    R.box((0, 0, 16.3), (5.4, 5.4, 0.5), maroon, 0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            R.cyl((sx * 1.7, sy * 1.7, 17.6), 0.22, 2.2, cream, 12)
    R.box((0, 0, 18.8), (4.4, 4.4, 0.35), maroon)
    R.dome((0, 0, 18.95), 2.0, 2.2, cream, segs=24)
    R.cyl((0, 0, 21.6), 0.1, 1.4, R.mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0), 8)


def church():
    """Christ the King church: a white nave under a pitched roof with pointed windows, side aisles, a tall bell
    tower over the entrance with a spire and cross, a rose window, steps up to the doors, a cross on the gable."""
    white = R.mat("church_white", (0.94, 0.93, 0.9), 0.6)
    blue = R.mat("church_blue", (0.35, 0.55, 0.75), 0.5)
    roof = R.mat("church_roof", (0.55, 0.22, 0.15), 0.7)
    glass = R.mat("church_glass", (0.25, 0.35, 0.55), 0.1, 0.3)
    L, W, H = 52.0, 18.0, 13.0
    R.box((0, 6, H / 2), (W, L, H), white, 0.03)
    gable(0, 6, W, L, H, 6.5, roof)
    for s in (-1, 1):                                                     # side aisles
        R.box((s * (W / 2 + 3), 8, 3.5), (6.0, L - 6, 7.0), white, 0.02)
        gable(s * (W / 2 + 3), 8, 6.0, L - 6, 7.0, 1.5, roof)
        for k in range(8):
            pointed_window(s * (W / 2 + 0.05), -12 + k * 6.0, 10.0, 1.6, 3.6, glass, blue, facing_y=False)
            pointed_window(s * (W / 2 + 6.05), -10 + k * 6.0, 3.4, 1.2, 3.0, glass, blue, facing_y=False)
    y0 = 6 - L / 2                                                        # the front and the bell tower
    R.box((0, y0 - 1.0, 11.0), (W + 1.0, 2.0, 22.0), white, 0.03)
    ty = y0 + 2.5                                                         # the tower stands on the front wall
    R.box((0, ty, 23.0), (7.0, 7.0, 10.0), white, 0.03)
    R.box((0, ty, 28.2), (7.6, 7.6, 0.5), blue)
    R.cyl((0, ty, 33.5), 3.8, 10.0, white, 4, rot=(0, 0, math.pi / 4), r2=0.2)
    gold = R.mat("cross_gold", (0.85, 0.65, 0.2), 0.3, 1.0)
    R.box((0, ty, 40.0), (0.25, 0.25, 3.2), gold)
    R.box((0, ty, 40.7), (1.6, 0.25, 0.25), gold)
    for a in range(4):                                                    # its belfry openings
        ang = a * math.pi / 2
        R.box((-math.sin(ang) * 3.52, ty - math.cos(ang) * 3.52, 24.5), (2.0 if a % 2 == 0 else 0.06, 0.06 if a % 2 == 0 else 2.0, 3.6),
              R.mat("passage_dark", (0.1, 0.1, 0.1), 0.9))
    R.cyl((0, y0 - 2.05, 15.0), 2.4, 0.1, glass, 32, rot=(math.pi / 2, 0, 0))             # the rose window
    R.cyl((0, y0 - 2.0, 15.0), 2.7, 0.12, blue, 32, rot=(math.pi / 2, 0, 0))
    pointed_window(0, y0 - 2.06, 3.2, 3.2, 5.0, R.mat("church_door", (0.35, 0.2, 0.1), 0.6), blue)
    for s in (-1, 1):
        pointed_window(s * 5.5, y0 - 2.06, 9.0, 1.6, 4.0, glass, blue)
        R.box((s * (W / 2 + 0.3), y0 - 1.0, 11.0), (1.2, 2.4, 22.0), blue, 0.02)
    for k in range(4):
        R.box((0, y0 - 3.0 - k * 0.5, 0.15 + k * 0.15), (10.0 - k * 0.6, 0.6, 0.3), white)
    R.box((0, y0 - 14.0, 0.06), (40.0, 22.0, 0.12), R.mat("forecourt", (0.5, 0.49, 0.47), 0.8))


def hospital():
    """Coimbatore Medical College Hospital (the Government Hospital): the long three-floor main block with a corridor
    verandah on every floor behind its parapets, cream with red-oxide bands, the entrance porch for ambulances, the
    name over it in English (and Tamil, by the game), the wings behind."""
    W, D, H = 62.0, 15.0, 12.0
    cream = R.mat("gh_cream", (0.9, 0.86, 0.74), 0.8)
    oxide = R.mat("gh_oxide", (0.55, 0.22, 0.14), 0.7)
    shade = R.mat("verandah_shade", (0.3, 0.28, 0.26), 0.9)
    R.box((0, 0, H / 2), (W, D, H), cream, 0.03)
    for f in range(3):                                                    # corridor verandahs: shade, parapet, piers
        z0 = f * 4.0
        R.box((0, -D / 2 - 0.02, z0 + 2.4), (W - 1, 0.05, 2.4), shade)
        R.box((0, -D / 2 - 0.15, z0 + 0.6), (W, 0.3, 1.0), cream if f else oxide)
        R.box((0, -D / 2 - 0.15, z0 + 3.85), (W, 0.3, 0.3), oxide)
        for k in range(21):
            R.box((-W / 2 + 0.5 + k * (W - 1) / 20, -D / 2 - 0.15, z0 + 2.4), (0.4, 0.3, 2.4), cream)
    for s in (-1, 1):                                                     # the wings behind
        R.box((s * (W / 2 - 15), D / 2 + 12, H / 2), (12.0, 24.0, H), cream, 0.03)
    R.box((0, -D / 2 - 5.0, 4.2), (16.0, 10.0, 0.4), cream, 0.02)        # the porch
    for sx in (-1, 1):
        for yy in (-D / 2 - 9.4, -D / 2 - 1.0):
            R.box((sx * 7.4, yy, 2.0), (0.5, 0.5, 4.0), oxide)
    R.box((0, -D / 2 - 10.05, 4.5), (15.0, 0.1, 1.2), R.mat("gh_board_blue", (0.08, 0.2, 0.5), 0.5))
    R.text("COIMBATORE MEDICAL COLLEGE HOSPITAL", (0, -D / 2 - 10.12, 4.3), 0.42, R.mat("letters_white", (0.97, 0.97, 0.97), 0.4), "-y")
    R.box((0, 0, H + 0.4), (W + 0.4, D + 0.4, 0.8), oxide)


def stadium():
    """Jawaharlal Nehru Stadium: the football ground inside the red running track, concrete stands down both long
    sides (the west one under a canopy), floodlight masts at the corners, a perimeter wall round the oval and
    the gate at the north end with its name."""
    Wd, Ld = 150.0, 228.0
    grass = R.mat("stadium_grass", (0.18, 0.45, 0.15), 0.9)
    track = R.mat("stadium_track", (0.6, 0.22, 0.15), 0.85)
    concrete = R.mat("stadium_concrete", (0.72, 0.7, 0.66), 0.85)
    steel = R.mat("rail_steel", (0.3, 0.32, 0.35), 0.4, 0.8)
    for rx, ry, z, m in ((Wd * 0.36, Ld * 0.42, 0.05, track), (Wd * 0.28, Ld * 0.36, 0.08, grass)):   # track, ground
        R.cyl((0, 0, z), 1.0, 0.06, m, 64).scale = (rx, ry, 1.0)
    for k in range(4):                                                    # the pitch's lines
        R.box((0, (k - 1.5) * Ld * 0.24, 0.12), (Wd * 0.5, 0.15, 0.02), R.mat("line_white", (0.95, 0.95, 0.95), 0.5))
    for s in (-1, 1):                                                     # the stands: twelve tiers
        for t in range(12):
            R.box((s * (Wd * 0.38 + t * 0.9), 0, (t + 1) * 0.55 / 2), (0.9, Ld * 0.62, (t + 1) * 0.55), concrete)
        R.box((s * (Wd * 0.38 + 11.5), 0, 4.0), (1.0, Ld * 0.62, 8.0), concrete)
    R.box((-(Wd * 0.38 + 6.0), 0, 10.5), (13.0, Ld * 0.5, 0.3), R.mat("stand_roof", (0.85, 0.85, 0.87), 0.4, 0.5),
          rot=(0, math.radians(-8), 0))
    for k in range(9):
        R.cyl((-(Wd * 0.38 + 11.8), -Ld * 0.25 + k * Ld * 0.5 / 8, 6.0), 0.2, 12.0, steel, 10)
    for sx in (-1, 1):                                                    # floodlights
        for sy in (-1, 1):
            x, y = sx * Wd * 0.42, sy * Ld * 0.4
            R.cyl((x, y, 17.5), 0.45, 35.0, steel, 12, r2=0.25)
            R.box((x, y, 35.5), (4.0, 0.6, 3.0), R.mat("floodlight", (0.95, 0.95, 0.9), 0.3, emit=(1, 1, 0.95), strength=1.5),
                  rot=(math.radians(-30) * sy, 0, math.atan2(-y, -x) + math.pi / 2))
    for k in range(48):                                                   # the perimeter wall
        a, b = k * math.tau / 48, (k + 1) * math.tau / 48
        p = Vector((math.cos(a) * Wd / 2, math.sin(a) * Ld / 2, 0))
        q = Vector((math.cos(b) * Wd / 2, math.sin(b) * Ld / 2, 0))
        m = (p + q) / 2
        R.box((m.x, m.y, 1.5), ((q - p).length + 0.3, 0.4, 3.0), concrete, rot=(0, 0, math.atan2(q.y - p.y, q.x - p.x)))
    R.box((0, -Ld / 2, 4.5), (18.0, 2.0, 9.0), concrete, 0.02)            # the gate
    R.box((0, -Ld / 2 - 1.05, 2.5), (8.0, 0.1, 5.0), R.mat("passage_dark", (0.1, 0.1, 0.1), 0.9))
    R.text("JAWAHARLAL NEHRU STADIUM", (0, -Ld / 2 - 1.1, 7.2), 0.9, R.mat("letters_maroon", (0.4, 0.05, 0.05), 0.5), "-y")


LANDMARKS.update({"collectorate": collectorate, "clock_tower": clock_tower, "church": church, "hospital": hospital,
                  "stadium": stadium})


# ---- temple, campus, airport -------------------------------------------------------------------------------------
def gopuram(cx, cy, w, d, tiers, base_h, tier_h, colours, kalasam_m, stone):
    """A Dravidian gateway tower: a granite base with the gateway through it, then tapering stucco tiers (each
    with a cornice and a row of niches), the barrel-vaulted (shala) crown and its row of gilded kalasams."""
    R.box((cx, cy, base_h / 2), (w, d, base_h), stone, 0.02)
    R.box((cx, cy - d / 2 - 0.02, base_h * 0.4), (w * 0.22, 0.06, base_h * 0.8), R.mat("passage_dark", (0.1, 0.1, 0.1), 0.9))
    z = base_h
    for t in range(tiers):
        k = 1.0 - (t + 1) / (tiers + 2.2)
        tw, td = w * k, d * (0.55 + 0.45 * k)
        col = colours[t % len(colours)]
        R.box((cx, cy, z + tier_h / 2), (tw, td, tier_h), col, 0.02)
        R.box((cx, cy, z + tier_h - 0.15), (tw + 0.5, td + 0.5, 0.3), colours[(t + 1) % len(colours)])     # cornice
        for j in range(max(3, int(tw / 2.2))):                            # niches with their small shrines
            nx = cx - tw / 2 + 1.1 + j * (tw - 2.2) / max(1, max(3, int(tw / 2.2)) - 1)
            R.box((nx, cy - td / 2 - 0.12, z + tier_h * 0.45), (0.7, 0.25, tier_h * 0.55), colours[(t + 2) % len(colours)])
            R.dome((nx, cy - td / 2 - 0.12, z + tier_h * 0.73), 0.38, 0.4, colours[(t + 2) % len(colours)], segs=10)
        z += tier_h
    cw = w * (1.0 - (tiers + 1) / (tiers + 2.2)) + 1.0                    # the shala crown
    R.cyl((cx, cy, z + 1.2), 1.4, cw, colours[0], 20, rot=(0, math.pi / 2, 0))
    R.box((cx, cy, z + 0.5), (cw, 2.6, 1.2), colours[0])
    for j in range(7):
        kx = cx - cw / 2 + 0.6 + j * (cw - 1.2) / 6
        R.dome((kx, cy, z + 2.5), 0.32, 0.6, kalasam_m, segs=12)
        R.cyl((kx, cy, z + 3.25), 0.06, 0.5, kalasam_m, 8)
    return z + 3.5


def temple():
    """Perur Pateeswarar temple: the compound wall (madil) in the temple's red-and-white stripes, the five-tier
    rajagopuram over the gateway facing the road, the pillared mandapam inside, the vimana over the sanctum
    behind it and the gilded flagstaff (dhvajastambham) on its pedestal before the mandapam."""
    W, D = 33.8, 51.6
    stone = R.mat("temple_granite", (0.55, 0.52, 0.48), 0.8)
    red = R.mat("temple_kaavi", (0.62, 0.18, 0.1), 0.8)
    white = R.mat("temple_lime", (0.94, 0.92, 0.86), 0.8)
    gold = R.mat("kalasam_gold", (0.85, 0.62, 0.18), 0.3, 1.0)
    pastels = [R.mat("stucco_%d" % k, c, 0.75) for k, c in enumerate(((0.95, 0.88, 0.62), (0.55, 0.75, 0.82), (0.9, 0.62, 0.55),
                                                                        (0.7, 0.85, 0.6), (0.92, 0.92, 0.85)))]
    for (x0, y0, x1, y1) in ((-W / 2, -D / 2, W / 2, -D / 2), (W / 2, -D / 2, W / 2, D / 2), (W / 2, D / 2, -W / 2, D / 2),
                             (-W / 2, D / 2, -W / 2, -D / 2)):     # the madil, striped
        L = math.hypot(x1 - x0, y1 - y0)
        n = int(L / 0.9)
        for k in range(n):
            t = (k + 0.5) / n
            R.box((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, 2.0), ((x1 - x0) / n + 0.02 if x1 != x0 else 0.6,
                  (y1 - y0) / n + 0.02 if y1 != y0 else 0.6, 4.0), red if k % 2 else white)
    gopuram(0, -D / 2, 13.0, 9.0, 5, 7.0, 3.6, pastels, gold, stone)
    R.box((0, 2, 2.8), (12.0, 16.0, 0.5), stone, 0.02)                    # the mandapam: a flat roof on pillars
    for sx in range(-2, 3):
        for sy in range(-3, 4):
            R.box((sx * 2.8, 2 + sy * 2.4, 1.3), (0.5, 0.5, 2.6), stone)
    R.box((0, 16, 3.5), (8.0, 8.0, 7.0), stone, 0.02)                     # the sanctum and its vimana
    vz = 7.0
    for t in range(3):
        sz = 7.0 - t * 1.8
        R.box((0, 16, vz + 1.2), (sz, sz, 2.4), pastels[t], 0.02)
        vz += 2.4
    R.dome((0, 16, vz), 1.8, 2.2, pastels[0], segs=16)
    R.dome((0, 16, vz + 2.1), 0.3, 0.6, gold, segs=10)
    R.box((0, -8, 0.6), (2.0, 2.0, 1.2), stone)                            # the flagstaff
    R.cyl((0, -8, 7.5), 0.18, 13.0, gold, 12)
    R.box((0, -D / 2 - 6, 0.06), (W + 6, 12.0, 0.12), stone)


def codissia():
    """Kovai Trade Fair Complex (a name of the story's own, where CODISSIA's stands): the main exhibition hall, 190 m long under a barrel-vaulted steel roof, glazed
    ends, a grand entrance on the road end with the complex's name over it, flagpoles and a paved forecourt."""
    W, D, H = 66.0, 190.0, 12.0
    clad = R.mat("hall_cladding", (0.82, 0.84, 0.86), 0.4, 0.5)
    roof = R.mat("hall_roof", (0.6, 0.64, 0.68), 0.35, 0.7)
    glass = R.mat("mall_glass", (0.2, 0.32, 0.4), 0.05, 0.8)
    blue = R.mat("codissia_blue", (0.05, 0.25, 0.55), 0.5)
    R.box((0, 0, H / 2), (W, D, H), clad, 0.04)
    rise = 9.0
    n = 16
    for k in range(n):                                                    # the barrel vault, in strips
        a0, a1 = math.pi * k / n, math.pi * (k + 1) / n
        x0, z0 = -math.cos(a0) * W / 2, H + math.sin(a0) * rise
        x1, z1 = -math.cos(a1) * W / 2, H + math.sin(a1) * rise
        R.box(((x0 + x1) / 2, 0, (z0 + z1) / 2), (math.hypot(x1 - x0, z1 - z0) + 0.2, D + 1.0, 0.3), roof,
              rot=(0, -math.atan2(z1 - z0, x1 - x0), 0))
    for k in range(n):                                                    # the glazed end walls under the vault
        a = math.pi * (k + 0.5) / n
        x, h = -math.cos(a) * W / 2, math.sin(a) * rise
        for sy in (-1, 1):
            R.box((x, sy * (D / 2 + 0.05), H + h / 2), (W / n + 0.05, 0.1, h), glass)
    R.box((0, -D / 2 - 0.1, 5.0), (30.0, 0.15, 10.0), glass)              # the entrance
    R.box((0, -D / 2 - 6.0, 10.5), (36.0, 12.0, 0.6), roof, 0.02)
    for sx in (-1, 1):
        R.cyl((sx * 16.0, -D / 2 - 11.0, 5.2), 0.5, 10.4, blue, 16)
    R.box((0, -D / 2 - 12.05, 11.6), (34.0, 0.2, 1.8), blue)
    R.text("KOVAI TRADE FAIR COMPLEX", (0, -D / 2 - 12.2, 11.35), 1.15, R.mat("letters_white", (0.97, 0.97, 0.97), 0.4), "-y")
    india_flag(-24.0, -D / 2 - 20.0, 10.0)
    R.box((0, -D / 2 - 14.0, 0.06), (W + 20, 28.0, 0.12), R.mat("mall_paving", (0.62, 0.58, 0.52), 0.7))


def psg_tech():
    """Velliangiri College of Technology (a college of the story's own, where PSG Tech stands): the main block on Avinashi Road, four floors in cream with red-brick
    piers and deep sunshades, the central entrance with its portico and the college's name, lawns and trees."""
    W, D, H = 85.0, 50.0, 16.0
    cream = R.mat("psg_cream", (0.9, 0.86, 0.76), 0.8)
    brick = R.mat("psg_brick", (0.6, 0.24, 0.15), 0.8)
    glass = R.mat("rail_glass", (0.18, 0.22, 0.24), 0.2, 0.3)
    R.box((0, 0, H / 2), (W, D, H), cream, 0.03)
    for k in range(18):
        R.box((-W / 2 + 1 + k * (W - 2) / 17, -D / 2 - 0.3, H / 2), (0.8, 0.6, H), brick)
    for f in range(4):
        R.box((0, -D / 2 - 0.5, f * 4.0 + 3.6), (W, 1.0, 0.18), cream)       # the sunshades
        R.box((0, -D / 2 - 0.05, f * 4.0 + 2.0), (W - 1, 0.06, 2.0), glass)
    R.box((0, -D / 2 - 5.0, 8.2), (20.0, 10.0, 0.5), cream, 0.02)          # the portico
    for sx in (-1, 1):
        for yy in (-D / 2 - 9.4, -D / 2 - 1.0):
            R.cyl((sx * 9.0, yy, 4.0), 0.45, 8.0, cream, 16)
    R.box((0, -D / 2 - 10.05, 9.3), (19.0, 0.12, 1.6), brick)
    R.text("VELLIANGIRI COLLEGE OF TECHNOLOGY", (0, -D / 2 - 10.15, 9.5), 0.8, R.mat("letters_white", (0.97, 0.97, 0.97), 0.4), "-y")
    R.box((0, -D / 2 - 18.0, 0.04), (W + 10, 16.0, 0.08), R.mat("lawn_grass", (0.22, 0.48, 0.18), 0.9))
    for x in (-34, -20, 20, 34):
        palm(x, -D / 2 - 14.0, 7.0)


def hospital_private():
    """Kongu Multispeciality Hospital (a hospital of the story's own, where KMCH stands): a ten-floor white tower
    with blue glazing on a two-floor podium, the emergency entrance under its canopy, the name on the crown."""
    W, D = 60.0, 26.0
    white = R.mat("kmh_white", (0.93, 0.94, 0.95), 0.5)
    glass = R.mat("kmh_glass", (0.18, 0.35, 0.55), 0.06, 0.8)
    red = R.mat("emergency_red", (0.75, 0.08, 0.08), 0.5)
    R.box((0, 0, 4.5), (W + 10, D + 10, 9.0), white, 0.03)
    R.box((0, -D / 2 - 5.05, 4.0), (W + 6, 0.1, 6.0), glass)
    tz0, th = 9.0, 34.0
    R.box((0, 0, tz0 + th / 2), (W, D, th), glass)
    for f in range(11):
        R.box((0, 0, tz0 + f * 3.4), (W + 0.3, D + 0.3, 0.5), white)
    for k in range(9):
        R.box((-W / 2 + k * W / 8, -D / 2 - 0.2, tz0 + th / 2), (0.6, 0.5, th), white)
    R.box((0, 0, tz0 + th + 1.5), (W + 0.6, D + 0.6, 3.0), white, 0.02)
    R.text("KONGU MULTISPECIALITY HOSPITAL", (0, -D / 2 - 0.35, tz0 + th + 1.2), 1.3, R.mat("kmh_blue_text", (0.06, 0.2, 0.5), 0.4), "-y")
    R.box((W / 2 - 6, -D / 2 - 12.0, 4.2), (14.0, 10.0, 0.4), white, 0.02)  # emergency
    R.box((W / 2 - 6, -D / 2 - 17.05, 4.8), (12.0, 0.12, 1.2), red)
    R.text("EMERGENCY", (W / 2 - 6, -D / 2 - 17.15, 4.6), 0.8, R.mat("letters_white", (0.97, 0.97, 0.97), 0.4), "-y")
    for sx in (-1, 1):
        R.cyl((W / 2 - 6 + sx * 6.5, -D / 2 - 16.5, 2.0), 0.25, 4.0, white, 12)


def airport():
    """Coimbatore International Airport's terminal: a 160 m glass front under a broad roof that sweeps out over the
    departures kerb on slender columns, the airport's name on the roof's edge in English (Tamil and Hindi by the
    game), the kerb with its drop-off lanes, and the control tower beside it."""
    W, D, H = 160.0, 80.0, 14.0
    glass = R.mat("terminal_glass", (0.25, 0.42, 0.5), 0.05, 0.8)
    roof = R.mat("terminal_roof", (0.88, 0.89, 0.9), 0.3, 0.6)
    steel = R.mat("mall_steel", (0.75, 0.76, 0.78), 0.3, 0.9)
    concrete = R.mat("bus_concrete", (0.78, 0.76, 0.72), 0.85)
    R.box((0, 0, H / 2), (W, D, H), concrete, 0.04)
    R.box((0, -D / 2 - 0.05, H / 2), (W - 4, 0.1, H - 1), glass)
    for k in range(33):
        R.box((-W / 2 + 2 + k * (W - 4) / 32, -D / 2 - 0.12, H / 2), (0.25, 0.25, H - 1), steel)
    n = 10
    for k in range(n):                                                    # the roof, rising to the front in a sweep
        y0, y1 = D / 2 - k * (D + 18) / n, D / 2 - (k + 1) * (D + 18) / n
        z0, z1 = H + 1.0 + 2.5 * math.sin(math.pi * k / n), H + 1.0 + 2.5 * math.sin(math.pi * (k + 1) / n)
        R.box((0, (y0 + y1) / 2, (z0 + z1) / 2), (W + 12, abs(y1 - y0) + 0.2, 0.6), roof,
              rot=(math.atan2(z1 - z0, abs(y1 - y0)) * -1, 0, 0))
    for k in range(9):
        R.cyl((-W / 2 + 6 + k * (W - 12) / 8, -D / 2 - 14.0, (H + 1.5) / 2), 0.35, H + 1.5, steel, 12)
    R.box((0, -D / 2 - 18.3, H + 2.4), (W * 0.62, 0.3, 2.2), R.mat("airport_board", (0.05, 0.2, 0.4), 0.5))
    R.text("COIMBATORE INTERNATIONAL AIRPORT", (0, -D / 2 - 18.5, H + 2.6), 1.5, R.mat("letters_white", (0.97, 0.97, 0.97), 0.4), "-y")
    for k in range(3):                                                    # the kerb lanes
        R.box((0, -D / 2 - 10.0 - k * 7.0, 0.05), (W, 0.25, 0.02), R.mat("line_white", (0.95, 0.95, 0.95), 0.5))
    R.box((0, -D / 2 - 4.0, 0.12), (W, 8.0, 0.24), R.mat("mall_paving", (0.62, 0.58, 0.52), 0.7))
    tx, ty = W / 2 + 25, D / 2 - 10                                       # the control tower
    R.cyl((tx, ty, 16.0), 2.5, 32.0, concrete, 24)
    R.cyl((tx, ty, 34.0), 5.0, 4.0, glass, 24, r2=5.6)
    R.cyl((tx, ty, 36.4), 5.8, 0.8, roof, 24)


LANDMARKS.update({"temple": temple, "codissia": codissia, "psg_tech": psg_tech, "hospital_private": hospital_private,
                  "airport": airport})


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
