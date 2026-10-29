"""
The insides of the city's big public buildings and of its ordinary houses, for walking in (city_doors.gd: every
building has a door). Built with story_rooms.py's kit (materials, boxes, text, the shell and its marks), each one a
room of its own:
    station      Coimbatore Junction's booking hall: reservation and unreserved-ticket counters behind glass, the
                 train indicator board, the platform way out, railway benches, the ticket machines, the enquiry
    bus          a Gandhipuram bus stand's waiting hall: the TNSTC timing board, the enquiry and reservation
                 counters, granite benches, a snack and tea kiosk, the bays (and a bus) through the arches behind
    airport      the departure check-in hall: check-in islands with their bag belts, the flight screens, the queue
                 lines, trolleys, rows of seats, the glass front, the way to security
    mall_avinashi, mall_sathy
                 the malls' atrium: two floors of shopfronts (names of the story's own), the gallery and its glass
                 railing, the escalators up the middle, the skylight, a kiosk and planters
    stadium      Nehru Stadium: the concourse under the stand (ticket window, turnstiles), the tunnels onto the
                 stand's tiers, and the ground below (track, pitch, goals, the far stand, floodlights, the sky)
    collectorate the District Collectorate's public hall: petition counters behind a teak screen, the token display,
                 rows of chairs, files, notices, the stair
    college      Velliangiri College of Technology (where PSG Tech stands): the lobby and a classroom
    trade_fair   a hall of the Kovai Trade Fair Complex (where CODISSIA's stands) during an industrial expo
    hospital_gov the Government Hospital's out-patient hall: OP ticket counters and queues, rows of chairs, the wards
    hospital_pvt Kongu Multispeciality Hospital's lobby: reception, lounge, pharmacy, billing, café, lifts
    temple_hall  Perur Pateeswarar temple's mandapam: granite pillars, the flagstaff, lamps, the sanctum's lit
                 doorway (nothing within it shown)
    church       Christ the King's nave: pews either side of the aisle, the columns, the stained-glass windows, the
                 sanctuary steps, the altar and the cross, candles, the fans on their long rods
    house_mid    a middle-class family's hall: a wooden sofa set, the showcase, the fridge in the hall, a dining
                 table, the children's study corner, a pooja shelf
    house_flat   a modern apartment: an L sofa, the TV wall, an open kitchen with its island, a dining table of six,
                 the false ceiling's cove lights, the balcony door
    house_old    an old Kongu house round a courtyard open to the sky: wooden pillars, the swing, red-oxide floor,
                 the tulasi maadam, the brass vessels, the rooms' doors round it
Each has Entry / Exit at its door (Blender -Y, the game's +Z) and a Staff mark where a person stands, and its
Light_* marks; private businesses carry names of the story's own (no real brands).

    Blender -b --factory-startup --python tools/city_rooms.py -- [names...] [--preview DIR] [--shots a,b] [--no-export]
"""
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import story_rooms as R  # noqa: E402
from story_rooms import box, cyl, mat, text, sign, empty, shot  # noqa: E402

BUS = os.path.join(HERE, "..", "godot", "assets", "vehicles", "fleet_bus.glb")
GTEX = R.GTEX
DTEX = R.DTEX
COND = R.FONT_COND
_LK = {}


def lamp(loc, kind="tube"):
    """A Light_ mark (the game puts a light there): numbered per kind."""
    k = _LK.get(kind, 0)
    _LK[kind] = k + 1
    R.light(kind, loc, k)


def glow_tex(key, img, strength=2.0, rough=0.3):
    """A material whose picture glows (stained glass, a skylight)."""
    m = mat(key, (1, 1, 1), rough, tex=img)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    it = next(n for n in nt.nodes if n.type == 'TEX_IMAGE')
    nt.links.new(it.outputs["Color"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = strength
    return m


def textures():
    T = R.make_textures()
    n = 1024
    rng = np.random.default_rng(5)
    # grey cement floor, trowelled and worn (the bus stand)
    T["cement"] = R._save("cement", R._tint((0.55, 0.54, 0.51), n, 0.12, 51, 6))
    # terrazzo: a warm grey ground with chips of white, black and rust, cut in 60 cm squares by brass strips
    tz = R._tint((0.66, 0.62, 0.56), n, 0.05, 52, 4)
    for c, k in (((0.95, 0.94, 0.9), 9000), ((0.12, 0.12, 0.12), 6000), ((0.55, 0.3, 0.2), 4000)):
        ys, xs = rng.integers(0, n - 3, k), rng.integers(0, n - 3, k)
        for d in range(3):
            tz[ys + d, xs] = c
            tz[ys, xs + d] = c
    tz[:5, :] = tz[:, :5] = (0.7, 0.55, 0.3)
    T["terrazzo"] = R._save("terrazzo", tz)
    # white marble with soft grey veins (the mall, the church sanctuary)
    v = R._noise(n, 6, 53)
    mw = np.ones((n, n, 3)) * np.array([0.92, 0.91, 0.88])
    mw *= (1.0 - 0.18 * np.exp(-((np.sin(v * 30) * 0.5 + 0.5) ** 2) * 40))[:, :, None]
    mw[:3, :] = mw[:, :3] = (0.75, 0.74, 0.72)
    T["marble_white"] = R._save("marble_white", mw)
    # the airport's big pale grey tiles (1.2 m, one per repeat)
    ap = R._tint((0.78, 0.78, 0.77), n, 0.04, 54, 3)
    ap[:3, :] = ap[:, :3] = (0.55, 0.55, 0.55)
    T["tile_airport"] = R._save("tile_airport", ap)
    # mosaic chip floor of older houses: pink, white and grey chips
    mo = R._tint((0.78, 0.68, 0.64), n, 0.05, 55, 4)
    for c, k in (((0.95, 0.93, 0.9), 12000), ((0.5, 0.48, 0.46), 9000), ((0.7, 0.4, 0.38), 6000)):
        ys, xs = rng.integers(0, n - 4, k), rng.integers(0, n - 4, k)
        for d in range(4):
            mo[ys + d, xs] = c
            mo[ys, xs + d] = c
    T["mosaic"] = R._save("mosaic", mo)
    # walls: peach, lime-washed white, a teal feature wall, the station's cream
    T["wall_peach"] = R._save("wall_peach", R._tint((0.93, 0.76, 0.62), n, 0.05, 56, 4))
    T["wall_lime"] = R._save("wall_lime", R._tint((0.93, 0.92, 0.87), n, 0.08, 57, 5))
    T["wall_teal"] = R._save("wall_teal", R._tint((0.2, 0.42, 0.44), 512, 0.05, 58, 4))
    T["wall_rail"] = R._save("wall_rail", R._tint((0.88, 0.82, 0.66), n, 0.06, 59, 4))
    # temple granite: warm dark grey-brown, speckled, worn
    tg = R._tint((0.36, 0.32, 0.27), n, 0.14, 63, 5)
    ys, xs = rng.integers(0, n, 14000), rng.integers(0, n, 14000)
    tg[ys, xs] = (0.55, 0.5, 0.42)
    T["temple_stone"] = R._save("temple_stone", tg)
    T["wall_church"] = R._save("wall_church", R._tint((0.95, 0.95, 0.93), n, 0.03, 60, 4))
    # a red carpet runner, a handloom-grey rug
    T["carpet_red"] = R._save("carpet_red", R._tint((0.5, 0.06, 0.07), 512, 0.12, 61, 7))
    T["rug_grey"] = R._save("rug_grey", R._tint((0.55, 0.55, 0.57), 512, 0.12, 62, 7))
    # stained glass: panes of deep blue, red, gold and green between dark lead, a lighter cross in the middle
    m = 512
    yy, xx = np.mgrid[0:m, 0:m]
    cells = (yy // 48) * 13 + (xx // 48)
    pal = np.array([(0.1, 0.2, 0.7), (0.7, 0.08, 0.08), (0.9, 0.7, 0.15), (0.1, 0.5, 0.25), (0.15, 0.3, 0.85),
                    (0.5, 0.1, 0.5)])
    sg = pal[(cells * 7 + cells // 5) % len(pal)].astype(float)
    sg[(np.abs(xx - m / 2) < 30) & (yy > 60) & (yy < m - 60)] = (0.95, 0.9, 0.7)
    sg[(np.abs(yy - m * 0.35) < 30) & (np.abs(xx - m / 2) < 120)] = (0.95, 0.9, 0.7)
    sg[(yy % 48 < 4) | (xx % 48 < 4)] = (0.03, 0.03, 0.03)
    T["stained_glass"] = R._save("stained_glass", sg)
    # a skylight's glass seen from below: bright, with the shadows of its steel grid
    sk = np.ones((m, m, 3)) * np.array([0.9, 0.95, 1.0])
    sk[(yy % 128 < 8) | (xx % 128 < 8)] = (0.35, 0.37, 0.4)
    T["skylight"] = R._save("skylight", sk)
    return T


# ============================================================================ the shell of a big room
def hall(W, D, h, floor, wall, ceil, door_w=1.2, door_h=2.2, door_x=0.0, hole=None, frame=None, back=()):
    """Floor, ceiling (with an opening `hole` = (x, y, w, d) to the sky, a courtyard), four walls and a doorway in the
    front one (door_w × door_h at door_x), daylight beyond it; `back` = [(x, w, top)]: openings in the back wall
    (onto what lies beyond, built by the room). Entry / Exit at the doorway."""
    t = 0.15
    box((0, 0, -0.05), (W, D, 0.1), floor)
    if hole is None:
        box((0, 0, h + 0.05), (W, D, 0.1), ceil)
    else:
        hx, hy, hw, hd = hole
        x0, x1, y0, y1 = hx - hw / 2, hx + hw / 2, hy - hd / 2, hy + hd / 2
        box(((-W / 2 + x0) / 2, 0, h + 0.05), (x0 + W / 2, D, 0.1), ceil)
        box(((W / 2 + x1) / 2, 0, h + 0.05), (W / 2 - x1, D, 0.1), ceil)
        box((hx, (-D / 2 + y0) / 2, h + 0.05), (hw, y0 + D / 2, 0.1), ceil)
        box((hx, (D / 2 + y1) / 2, h + 0.05), (hw, D / 2 - y1, 0.1), ceil)
    a = -W / 2 - t
    for bx, bw, top in sorted(back):
        box(((a + bx - bw / 2) / 2, D / 2 + t / 2, h / 2), (bx - bw / 2 - a, t, h), wall)
        box((bx, D / 2 + t / 2, (h + top) / 2), (bw, t, h - top), wall)
        a = bx + bw / 2
    box(((a + W / 2 + t) / 2, D / 2 + t / 2, h / 2), (W / 2 + t - a, t, h), wall)
    for s in (-1, 1):
        box((s * (W / 2 + t / 2), 0, h / 2), (t, D, h), wall)
    left = door_x - door_w / 2 + W / 2
    right = W / 2 - door_x - door_w / 2
    box((-W / 2 + left / 2, -D / 2 - t / 2, h / 2), (left, t, h), wall)
    box((W / 2 - right / 2, -D / 2 - t / 2, h / 2), (right, t, h), wall)
    box((door_x, -D / 2 - t / 2, (h + door_h) / 2), (door_w, t, h - door_h), wall)
    fm = frame or mat("door_frame", (0.35, 0.2, 0.1), 0.5, tex=os.path.join(GTEX, "warm_natural_timber_base.jpg"))
    box((door_x, -D / 2 - 0.03, door_h + 0.04), (door_w + 0.16, 0.2, 0.08), fm, 0.005)
    for s in (-1, 1):
        box((door_x + s * (door_w / 2 + 0.04), -D / 2 - 0.03, door_h / 2), (0.08, 0.2, door_h), fm, 0.005)
    box((door_x, -D / 2 - 0.8, door_h / 2), (door_w + 0.4, 0.02, door_h + 0.2),
        mat("daylight", (1, 1, 1), 0.5, emit=(1.0, 0.98, 0.92), strength=2.2))
    empty("Entry", (door_x, -D / 2 + 0.9, 0), 0.0)
    empty("Exit", (door_x, -D / 2 + 0.35, 0), math.pi)


def sky_window(x, y, z, w, hgt, facing, frame_m, bars=True):
    """A window on a wall's inside face: a frame, bars, bright daylight behind (no opening is cut)."""
    sky = mat("daylight", (1, 1, 1), 0.5, emit=(1.0, 0.98, 0.92), strength=2.2)
    along_x = facing in ("-y", "+y")
    n = Vector((0, -1, 0)) if facing == "-y" else Vector((0, 1, 0)) if facing == "+y" else \
        Vector((1, 0, 0)) if facing == "+x" else Vector((-1, 0, 0))
    c = Vector((x, y, z))
    box(c, (w, 0.02, hgt) if along_x else (0.02, w, hgt), sky)
    for dz in (-hgt / 2, hgt / 2):
        box(c + n * 0.04 + Vector((0, 0, dz)), (w + 0.1, 0.08, 0.06) if along_x else (0.08, w + 0.1, 0.06), frame_m)
    span = Vector((1, 0, 0)) if along_x else Vector((0, 1, 0))
    for s in (-1, 1):
        box(c + n * 0.04 + span * s * w / 2, (0.06, 0.08, hgt) if along_x else (0.08, 0.06, hgt), frame_m)
    if bars:
        bm = mat("window_bars", (0.1, 0.12, 0.1), 0.4, 0.6)
        for k in range(1, int(w / 0.13)):
            box(c + n * 0.05 + span * (-w / 2 + k * 0.13), (0.016, 0.016, hgt), bm)
    lamp(tuple(c + n * 0.6), "window")


def tube(x, y, z, along_x=True, light_z=None):
    """A tube light: its fitting, the glowing tube, a Light_ mark below it."""
    box((x, y, z), (1.22, 0.07, 0.07) if along_x else (0.07, 1.22, 0.07), mat("tube_fitting", (0.9, 0.9, 0.88), 0.4), 0.01)
    box((x, y, z - 0.035), (1.18, 0.04, 0.03) if along_x else (0.04, 1.18, 0.03),
        mat("tube_glow", (1, 1, 1), 0.3, emit=(0.95, 0.97, 1.0), strength=5.0))
    lamp((x, y, light_z if light_z is not None else z - 0.15))


def rail_bench(x, y, yaw, seats=3):
    """A station's perforated steel bench: seats on a steel frame, armrests between."""
    blue = mat("bench_steel_blue", (0.2, 0.32, 0.5), 0.4, 0.6)
    frame_m = mat("rack_grey", (0.5, 0.52, 0.5), 0.4, 0.5)
    ca, sa = math.cos(yaw), math.sin(yaw)
    L = 0.55 * seats

    def at(u, v, z):
        return (x + u * ca - v * sa, y + u * sa + v * ca, z)
    box(at(0, 0, 0.44), (L, 0.45, 0.03), blue, 0.005, rot=(0, 0, yaw))
    box(at(0, 0.22, 0.72), (L, 0.03, 0.42), blue, 0.005, rot=(-0.12, 0, yaw))
    for k in range(seats + 1):
        u = -L / 2 + k * 0.55
        box(at(u, 0, 0.6), (0.04, 0.4, 0.03), frame_m, rot=(0, 0, yaw))
    for u in (-L / 2 + 0.1, L / 2 - 0.1):
        box(at(u, 0, 0.22), (0.05, 0.4, 0.44), frame_m, rot=(0, 0, yaw))


def chrome_seats(x, y, yaw, seats=4):
    """Airport beam seating: black padded seats on a chrome beam."""
    chrome = mat("chrome", (0.82, 0.82, 0.84), 0.2, 0.6)
    black = mat("seat_black", (0.07, 0.07, 0.08), 0.5)
    ca, sa = math.cos(yaw), math.sin(yaw)
    L = 0.62 * seats

    def at(u, v, z):
        return (x + u * ca - v * sa, y + u * sa + v * ca, z)
    box(at(0, 0.05, 0.36), (L, 0.08, 0.06), chrome, 0.01, rot=(0, 0, yaw))
    for k in range(seats):
        u = -L / 2 + 0.31 + k * 0.62
        box(at(u, 0, 0.45), (0.52, 0.48, 0.08), black, 0.03, rot=(0, 0, yaw))
        box(at(u, 0.24, 0.78), (0.52, 0.06, 0.55), black, 0.03, rot=(-0.12, 0, yaw))
    for u in (-L / 2 + 0.2, L / 2 - 0.2):
        box(at(u, 0.05, 0.17), (0.06, 0.5, 0.34), chrome, rot=(0, 0, yaw))


def stone_bench(x, y, L, T, along_x=True):
    gran = mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"])
    box((x, y, 0.42), (L, 0.5, 0.06) if along_x else (0.5, L, 0.06), gran, 0.01)
    for k in range(int(L / 1.6) + 1):
        u = -L / 2 + 0.2 + k * (L - 0.4) / max(int(L / 1.6), 1)
        box((x + u, y, 0.2) if along_x else (x, y + u, 0.2), (0.1, 0.42, 0.4) if along_x else (0.42, 0.1, 0.4),
            mat("cement_block", (0.55, 0.54, 0.5), 0.9))


def column(x, y, h, m, w=0.6, round_=False):
    if round_:
        cyl((x, y, h / 2), w / 2, h, m, 24)
    else:
        box((x, y, h / 2), (w, w, h), m, 0.01)


def fan_on_rod(x, y, z, top):
    R.ceiling_fan(x, y, z)
    cyl((x, y, (z + top) / 2), 0.012, top - z, mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55), 8)


def ltext(s, loc, size, m, facing="-y", font=COND):
    """Lettering that starts at loc (left-aligned as the reader sees it), for boards of columns."""
    ob = text(s, loc, size, m, facing, font)
    w = ob.dimensions.x
    d = Vector((w / 2, 0, 0))
    d.rotate(ob.rotation_euler.to_matrix())
    ob.location += Vector((d.x, d.y, 0))
    return ob


def staff(x, y, yaw=math.pi):
    empty("Staff", (x, y, 0), yaw)


_CROWD = [0]


def route(name, pts, loop=False):
    """A way people walk through the place (city_doors.gd sends a few along it): points on the floor, along clear
    aisles; walked to and fro, or round and round when loop. Walk_<name>[o]_<n> (o: a loop)."""
    for k, p in enumerate(pts):
        empty("Walk_%s%s_%02d" % (name, "o" if loop else "", k), (p[0], p[1], p[2] if len(p) > 2 else 0.0))


def crowd(pose, x, y, yaw, z=0.0):
    """A spot for one of the people in the place (city_doors.gd fills most of them): pose "sit" (on the seat at
    this spot), "stand" or "talk"; facing +Y turned by yaw (0: towards the back wall, pi: towards the door)."""
    _CROWD[0] += 1
    empty("Crowd_%s_%d" % (pose, _CROWD[0]), (x, y, z), yaw)


# ============================================================================ Coimbatore Junction
TRAINS = (("12676", "KOVAI EXP", "MGR CHENNAI CTL", "15:15", "1"),
          ("12244", "SHATABDI EXP", "MGR CHENNAI CTL", "15:05", "1"),
          ("16525", "ISLAND EXP", "KSR BENGALURU", "15:40", "2"),
          ("22668", "UDAY EXP", "BENGALURU", "16:10", "3"),
          ("56324", "PASSENGER", "MANGALURU CTL", "16:30", "5"),
          ("12682", "SUPERFAST EXP", "MGR CHENNAI CTL", "17:20", "4"),
          ("66612", "MEMU", "PALAKKAD TOWN", "17:45", "6"))


def station(T):
    W, D, h = 26.0, 16.0, 7.5
    floor = mat("granite_grey", (1, 1, 1), 0.15, tex=T["granite_grey"], scale=1.2)
    wall = mat("wall_rail", (1, 1, 1), 0.85, tex=T["wall_rail"], normal=os.path.join(DTEX, "plaster_normal.jpg"), scale=3.0)
    ceil = mat("ceiling_white", (0.93, 0.93, 0.9), 0.95)
    terra = mat("rail_terracotta", (0.55, 0.18, 0.1), 0.7)
    hall(W, D, h, floor, wall, ceil, door_w=4.0, door_h=3.6, door_x=0.0, frame=terra)
    yellow = mat("rail_board_yellow", (1.0, 0.78, 0.0), 0.5)
    black = mat("ink_black", (0.05, 0.05, 0.05), 0.4)
    white = mat("letters_white", (0.97, 0.97, 0.97), 0.4)
    wood = mat("counter_wood", (1, 1, 1), 0.45, tex=os.path.join(GTEX, "warm_natural_timber_base.jpg"))
    gran = mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"])
    glass = mat("glass", (0.6, 0.72, 0.75), 0.05, alpha=0.12)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    # terracotta dado and pilasters, the columns down the hall
    box((0, D / 2 - 0.01, 0.6), (W, 0.02, 1.2), terra)
    for s in (-1, 1):
        box((s * (W / 2 - 0.01), 0, 0.6), (0.02, D, 1.2), terra)
        for k in range(3):
            column(s * 4.5, -3.5 + k * 4.5, h, mat("rail_column", (0.9, 0.86, 0.75), 0.7), 0.7)
            box((s * 4.5, -3.5 + k * 4.5, 0.6), (0.74, 0.74, 1.2), terra, 0.01)
    # the booking counters along the left wall: reservation (3) and unreserved (4) windows behind glass
    x = -W / 2 + 0.8
    box((x, 0.5, 0.55), (0.7, 12.0, 1.1), wood, 0.01)
    box((x + 0.05, 0.5, 1.12), (0.85, 12.1, 0.04), gran, 0.005)
    box((x - 0.05, 0.5, 2.3), (0.02, 12.0, 2.3), glass)
    box((x - 0.05, 0.5, 3.6), (0.3, 12.2, 0.3), wood, 0.01)
    for k in range(7):
        y = -4.7 + k * 1.7
        box((x - 0.05, y + 0.85, 2.3), (0.08, 0.06, 2.3), wood)                      # between the windows
        box((x + 0.28, y, 1.15), (0.35, 0.3, 0.04), mat("ticket_slot", (0.6, 0.6, 0.6), 0.3, 0.6))
        sign(str(k + 1), (x + 0.12, y, 3.15), 0.35, 0.3, mat("board_navy", (0.08, 0.12, 0.3), 0.4), white, "+x", 0.2)
        R.monitor(x - 0.45, y - 0.2, 0.76, -math.pi / 2)
        R.office_chair(x - 0.85, y, -math.pi / 2)
    box((x - 0.8, 0.5, 0.38), (0.9, 12.0, 0.76), wood)                              # the clerks' desk behind
    sign("RESERVATION", (x + 0.2, -3.0, 4.3), 4.6, 0.6, yellow, black, "+x", 0.36)
    sign("UNRESERVED TICKETS", (x + 0.2, 3.3, 4.3), 6.2, 0.6, yellow, black, "+x", 0.36)
    for k in range(7):                                                               # the queue rails
        y = -4.7 + k * 1.7 + 0.6
        box((x + 2.3, y, 0.9), (3.6, 0.04, 0.04), steel)
        for u in (x + 0.6, x + 2.3, x + 4.0):
            cyl((u, y, 0.45), 0.025, 0.9, steel, 10)
    # the train indicator board high on the back wall, amber lights on black
    bx0 = -0.5
    box((bx0, D / 2 - 0.15, 5.2), (12.0, 0.25, 3.0), mat("led_board", (0.02, 0.02, 0.02), 0.5), 0.02)
    amber = mat("led_amber", (1, 0.6, 0.1), 0.4, emit=(1.0, 0.55, 0.08), strength=6)
    green = mat("led_green", (0.2, 1, 0.3), 0.4, emit=(0.2, 1.0, 0.3), strength=5)
    red = mat("led_red", (1, 0.15, 0.1), 0.4, emit=(1.0, 0.12, 0.06), strength=5)
    yt = D / 2 - 0.3
    for col, lab, m in ((-5.5, "TRAIN", red), (-4.0, "NAME", red), (-0.6, "TO", red), (3.6, "DEP", red), (4.9, "PF", red)):
        ltext(lab, (bx0 + col, yt, 6.35), 0.2, m)
    for r, (no, name, to, t, pf) in enumerate(TRAINS):
        z = 5.95 - r * 0.36
        for col, s, m in ((-5.5, no, amber), (-4.0, name, amber), (-0.6, to, amber), (3.6, t, green), (4.9, pf, amber)):
            ltext(s, (bx0 + col, yt, z), 0.22, m)
    lamp((bx0, D / 2 - 2.0, 4.0), "lamp")
    for x3, y3 in ((-2.0, 5.6), (0.8, 6.2), (3.2, 5.4), (5.0, 6.6)):     # reading the board
        crowd("stand", x3, y3, 0.0)
    for k in range(7):                                                   # queueing at the windows
        for j in range(1 + (k * 5) % 3):
            crowd("stand", -W / 2 + 1.9 + j * 0.7, -4.7 + k * 1.7 + 0.25, math.pi / 2)
    crowd("stand", W / 2 - 1.7, -3.2, -math.pi / 2)                      # at the enquiry
    crowd("talk", 6.0, -1.5, math.pi / 2)
    crowd("talk", 5.2, -1.5, -math.pi / 2)
    route("platform", [(1.6, -6.6), (3.0, -5.5), (3.0, 5.5), (6.5, 6.5), (9.0, 7.3)])          # in, to the trains
    route("counters", [(-1.6, -6.6), (-3.0, -5.8), (-7.5, -5.8), (-7.5, 5.0)])                # in, to the windows
    route("round", [(-3.4, -5.8), (2.4, -5.8), (2.4, 4.6), (-3.4, 4.6)], loop=True)          # round the benches
    # the way to the platforms: an opening in the back wall at the right, the platform's light beyond
    px = 9.0
    box((px, D / 2 - 0.02, 1.6), (3.6, 0.06, 3.2), mat("daylight", (1, 1, 1), 0.5, emit=(1.0, 0.98, 0.92), strength=2.2))
    for s in (-1, 1):
        box((px + s * 1.9, D / 2 - 0.08, 1.7), (0.2, 0.2, 3.4), terra)
    box((px, D / 2 - 0.08, 3.4), (4.0, 0.2, 0.2), terra)
    sign("TO PLATFORMS  1 - 6  >", (px, D / 2 - 0.2, 4.0), 4.2, 0.5, yellow, black, "-y", 0.3)
    sign("FOOT OVER BRIDGE", (px + 3.5, D / 2 - 0.2, 2.8), 2.6, 0.4, yellow, black, "-y", 0.22)
    # the enquiry counter on the right wall, an ATVM pair, the railway clock, Indian Railways' board
    ex = W / 2 - 0.8
    box((ex, -3.0, 0.55), (0.7, 3.4, 1.1), wood, 0.01)
    box((ex - 0.05, -3.0, 1.12), (0.85, 3.5, 0.04), gran, 0.005)
    box((ex + 0.05, -3.0, 2.2), (0.02, 3.4, 2.1), glass)
    sign("ENQUIRY", (ex - 0.2, -3.0, 3.6), 2.4, 0.55, yellow, black, "-x", 0.34)
    R.monitor(ex + 0.4, -3.0, 0.76, math.pi / 2)
    staff(ex + 0.6, -3.0, -math.pi / 2)
    orange = mat("atvm_orange", (0.9, 0.42, 0.08), 0.4)
    scr = mat("screen", (0.05, 0.1, 0.15), 0.1, emit=(0.25, 0.45, 0.7), strength=1.5)
    for k in range(2):
        y = 1.0 + k * 1.2
        box((W / 2 - 0.4, y, 0.85), (0.55, 0.8, 1.7), orange, 0.03)
        box((W / 2 - 0.69, y, 1.25), (0.02, 0.5, 0.4), scr)
    text("ATVM", (W / 2 - 0.68, 1.6, 1.85), 0.12, white, "-x")
    sign("INDIAN RAILWAYS  -  COIMBATORE JUNCTION", (0, -D / 2 + 0.1, 5.2), 12.0, 0.8, yellow, black, "+y", 0.45)
    R.wall_clock(-1.0, D / 2 - 0.02, 3.4)
    # benches down the middle, back to back; a water cooler; dust bins
    for k in range(3):
        for s in (-1, 1):
            rail_bench(-0.5 + s * 0.25 - 0.0, -3.0 + k * 3.2 + s * 0.26, math.pi if s < 0 else 0.0, 4)
            for i in range(4):                                      # sitting on it, facing away from its back
                crowd("sit", -0.25 + s * 0.25 - 1.1 + 0.275 + 0.55 * i, -3.0 + k * 3.2 + s * 0.26 + s * 0.05, 0.0 if s < 0 else math.pi)
    box((4.5, D / 2 - 0.5, 0.7), (0.8, 0.5, 1.4), steel, 0.02)
    text("DRINKING WATER", (4.5, D / 2 - 0.77, 1.2), 0.08, black, "-y")
    for x2 in (-2.0, 6.0):
        cyl((x2, -D / 2 + 0.6, 0.35), 0.22, 0.7, mat("bin_green", (0.1, 0.4, 0.2), 0.5), 16)
    # lights and fans
    for x2 in (-8.0, -2.5, 3.0, 8.5):
        for y2 in (-4.0, 1.0, 5.5):
            tube(x2, y2, h - 0.05, light_z=4.0)
    for x2 in (-5.0, 0.5, 6.0):
        for y2 in (-2.0, 3.5):
            fan_on_rod(x2, y2, 4.4, h)
    shot("wide", (6.5, -D / 2 + 1.2, 2.2), (-6.0, 2.0, 2.4))
    shot("board", (0.0, -1.0, 1.7), (2.0, D / 2, 4.6))


# ============================================================================ Gandhipuram bus stand
TIMINGS = (("SALEM", "05:30", "06:15", "07:00"), ("ERODE", "every 10 min", "", ""),
           ("TIRUPPUR", "every 5 min", "", ""), ("MADURAI", "06:00", "08:30", "13:45"),
           ("TIRUCHY", "05:45", "09:15", "14:30"), ("POLLACHI", "every 10 min", "", ""),
           ("METTUPALAYAM", "every 15 min", "", ""), ("OOTY", "06:20", "09:40", "15:10"),
           ("PALANI", "07:10", "11:30", "16:00"), ("SATHYAMANGALAM", "every 30 min", "", ""))


def bus_stand(T):
    W, D, h = 22.0, 13.0, 5.0
    floor = mat("cement", (1, 1, 1), 0.85, tex=T["cement"], scale=3.0)
    wall = mat("wall_offwhite", (1, 1, 1), 0.9, tex=T["wall_offwhite"], normal=os.path.join(DTEX, "plaster_normal.jpg"), scale=2.5)
    ceil = mat("ceiling_white", (0.9, 0.9, 0.87), 0.95)
    green = mat("tnstc_green", (0.05, 0.38, 0.22), 0.5)
    yellow = mat("letters_yellow", (1.0, 0.85, 0.2), 0.4)
    white = mat("letters_white", (0.97, 0.97, 0.97), 0.4)
    black = mat("ink_black", (0.05, 0.05, 0.05), 0.4)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    hall(W, D, h, floor, wall, ceil, door_w=3.0, door_h=3.0, door_x=-4.0, frame=green,
         back=((-7.0, 5.3, 3.6), (0.0, 5.3, 3.6), (7.0, 5.3, 3.6)))
    # a green dado; the back wall opens onto the bays in three arches, a railing and the buses beyond
    for s in (-1, 1):
        box((s * (W / 2 - 0.01), 0, 0.6), (0.02, D, 1.2), mat("dado_green", (0.15, 0.4, 0.25), 0.4))
    by = D / 2
    for k, x in enumerate((-7.0, 0.0, 7.0)):
        for s in (-1, 1):
            column(x + s * 2.9, by, h, wall, 0.5)
    sky = mat("daylight", (1, 1, 1), 0.5, emit=(1.0, 0.98, 0.92), strength=2.2)
    platform = mat("bay_platform", (0.6, 0.58, 0.54), 0.85)
    box((0, by + 3.5, -0.05), (W, 7.0, 0.1), platform)
    box((0, by + 3.5, 0.08), (W, 0.25, 0.16), mat("kerb_yellow", (0.9, 0.75, 0.1), 0.6))
    box((0, by + 7.1, 2.5), (W + 4, 0.1, 5.0), sky)
    for s in (-1, 1):
        box((s * (W / 2 + 0.07), by + 3.5, 2.5), (0.14, 7.0, 5.0), wall)
    box((0, by + 3.5, 4.6), (W, 7.0, 0.15), mat("shed_roof", (0.45, 0.47, 0.5), 0.5, 0.4))
    for k in range(int(W / 0.25)):                                       # the railing at the platform's edge
        cyl((-W / 2 + 0.125 + k * 0.25, by + 3.3, 0.5), 0.012, 1.0, steel, 6)
    box((0, by + 3.3, 1.0), (W, 0.05, 0.05), steel)
    for k, x in enumerate((-7.0, 7.0)):
        if os.path.exists(BUS):
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=BUS)
            new = set(bpy.data.objects) - before
            pivot = R._link(bpy.data.objects.new("BusPivot", None))
            for o in new:
                if o.parent is None:
                    o.parent = pivot
            pivot.location = (x, by + 5.4, 0.0)
            pivot.rotation_euler = (0, 0, 0.0)
            bpy.context.view_layer.update()
    for k, (x, dest) in enumerate(((-7.0, "BAY 4  SALEM - ERODE"), (0.0, "BAY 5  TIRUPPUR"), (7.0, "BAY 6  POLLACHI"))):
        sign(dest, (x, by - 0.1, 3.9), 4.6, 0.45, green, white, "-y", 0.24)
    lamp((0, by + 3.0, 3.5), "window")
    # the timing board on the right wall: green, white lettering, the routes and times
    tx = W / 2 - 0.05
    box((tx, -0.5, 2.95), (0.05, 7.0, 3.7), green, 0.01)
    text("TNSTC  -  KOVAI  -  BUS TIMINGS", (tx - 0.04, -0.5, 4.45), 0.26, yellow, "-x")
    for r, (dest, a, b, c) in enumerate(TIMINGS):
        z = 4.0 - r * 0.29
        ltext(dest, (tx - 0.04, 2.7, z), 0.17, white, "-x")
        ltext("   ".join(s for s in (a, b, c) if s), (tx - 0.04, -0.3, z), 0.17, white, "-x")
    # the enquiry and reservation counters on the left wall
    for k, (y, lab) in enumerate(((-2.5, "ENQUIRY"), (1.5, "RESERVATION"))):
        x = -W / 2 + 0.7
        box((x, y, 0.55), (0.9, 2.6, 1.1), mat("counter_blue", (0.2, 0.35, 0.6), 0.5), 0.01)
        box((x + 0.05, y, 1.12), (1.0, 2.7, 0.04), mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"]))
        for u in range(9):
            box((x + 0.4, y - 1.2 + u * 0.3, 1.9), (0.02, 0.02, 1.5), mat("window_bars", (0.1, 0.12, 0.1), 0.4, 0.6))
        box((x + 0.4, y, 2.7), (0.1, 2.7, 0.1), mat("window_bars", (0.1, 0.12, 0.1), 0.4, 0.6))
        sign(lab, (x + 0.2, y, 3.2), 2.4, 0.45, green, yellow, "+x", 0.28)
        R.monitor(x - 0.2, y, 1.14, -math.pi / 2)
    staff(-W / 2 + 0.25, -2.5, -math.pi / 2)
    # the snack and tea kiosk in the front right corner: biscuit jars, banana bunches, strings of packets
    kx, ky = 7.5, -D / 2 + 1.4
    wood = mat("timber", (1, 1, 1), 0.55, tex=os.path.join(GTEX, "warm_natural_timber_base.jpg"), scale=1.2)
    box((kx, ky + 0.6, 0.5), (3.2, 0.7, 1.0), wood, 0.01)
    box((kx, ky - 0.75, 1.6), (3.4, 0.08, 3.2), mat("kiosk_blue", (0.2, 0.4, 0.7), 0.5))
    box((kx, ky + 0.2, 2.9), (3.6, 1.9, 0.08), mat("kiosk_blue", (0.2, 0.4, 0.7), 0.5))
    box((kx, ky + 1.14, 2.8), (3.6, 0.04, 0.3), mat("kiosk_blue", (0.2, 0.4, 0.7), 0.5))
    for s in (-1, 1):
        box((kx + s * 1.75, ky + 1.1, 1.45), (0.06, 0.06, 2.9), mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55))
    for k in range(4):                                                   # shelves of packets behind the vendor
        box((kx, ky - 0.6, 1.2 + k * 0.4), (3.0, 0.25, 0.03), wood)
        for j in range(9):
            box((kx - 1.3 + j * 0.32, ky - 0.6, 1.33 + k * 0.4), (0.22, 0.12, 0.22),
                mat("packet_%d" % ((j + k) % 4), ((0.9, 0.15, 0.1), (0.95, 0.75, 0.1), (0.1, 0.5, 0.85), (0.2, 0.7, 0.3))[(j + k) % 4], 0.35), 0.005)
    jar = mat("jar_glass", (0.8, 0.85, 0.85), 0.05, alpha=0.4)
    for k in range(7):
        cyl((kx - 1.3 + k * 0.42, ky + 0.45, 1.13), 0.12, 0.26, jar, 16)
        cyl((kx - 1.3 + k * 0.42, ky + 0.45, 1.08), 0.11, 0.14, mat("biscuit_%d" % (k % 3), ((0.75, 0.5, 0.2), (0.9, 0.75, 0.4), (0.5, 0.25, 0.1))[k % 3], 0.7), 16)
        cyl((kx - 1.3 + k * 0.42, ky + 0.45, 1.29), 0.1, 0.03, mat("lid_red", (0.8, 0.1, 0.1), 0.4), 16)
    cols = ((0.9, 0.15, 0.1), (0.95, 0.75, 0.1), (0.1, 0.5, 0.85), (0.2, 0.7, 0.3))
    for s in range(6):                                                   # strings of chips packets from the awning
        for k in range(5):
            box((kx - 1.5 + s * 0.6, ky + 1.05, 2.55 - k * 0.2), (0.16, 0.02, 0.18), mat("packet_%d" % ((s + k) % 4), cols[(s + k) % 4], 0.35), 0.005)
    for s in (-1, 1):
        for k in range(10):
            cyl((kx + s * 1.6 + 0.04 * math.sin(k), ky + 0.95, 2.4 - k * 0.06), 0.03, 0.18,
                mat("banana", (0.85, 0.75, 0.15), 0.6), 8, rot=(0.3 * math.sin(k * 2), 0.4, 0))
    cyl((kx + 1.1, ky + 0.6, 1.25), 0.15, 0.4, mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55), 20)   # the tea boiler
    staff(kx, ky - 0.15, 0.0)
    for x3 in (kx - 0.8, kx + 0.5):                                      # buying tea
        crowd("stand", x3, ky + 1.35, math.pi)
    for y3 in (-2.5, 1.5):                                               # at the counters
        for j in range(2):
            crowd("stand", -W / 2 + 1.6 + j * 0.7, y3, math.pi / 2)
    for x3 in (-8.5, -6.0, 2.0, 4.5, 8.0):                               # waiting by the bays
        crowd("stand", x3, D / 2 - 1.0, 0.0)
    crowd("talk", 3.0, 3.5, math.pi / 2)
    crowd("talk", 3.8, 3.5, -math.pi / 2)
    route("bays", [(-2.4, -5.4), (-2.5, -4.0), (-2.5, 4.5), (-7.0, 5.4)])                     # in, out to a bus
    route("bays2", [(4.0, -4.6), (4.0, 2.8), (6.8, 5.0)])
    route("counters", [(-8.5, -4.3), (4.5, -4.3)])
    text("TEA  -  COFFEE  -  SNACKS", (kx, ky + 1.17, 2.8), 0.16, white, "+y")
    # granite benches in rows; a water tap, dustbins, posters, fans and tubes
    for k in range(3):
        for x in (-5.5, 0.5):
            stone_bench(x, -2.6 + k * 2.0, 4.2, T)
            for i in range(5):
                crowd("sit", x - 1.6 + 0.8 * i, -2.6 + k * 2.0 + (0.08 if i % 2 else -0.08), 0.0 if i % 2 else math.pi)
    box((W / 2 - 0.4, 4.5, 0.6), (0.5, 0.9, 1.2), steel, 0.01)
    text("DRINKING WATER", (W / 2 - 0.66, 4.5, 1.05), 0.08, black, "-x")
    for x in (-9.0, 4.0):
        cyl((x, -D / 2 + 0.5, 0.35), 0.22, 0.7, mat("bin_green", (0.1, 0.4, 0.2), 0.5), 16)
    box((-W / 2 + 0.03, 4.8, 2.2), (0.02, 1.0, 1.4), mat("poster_loan", (0.9, 0.6, 0.15), 0.6))
    text("WOMEN TRAVEL FREE", (-W / 2 + 0.05, 4.8, 2.5), 0.09, black, "+x")
    text("IN TOWN BUSES", (-W / 2 + 0.05, 4.8, 2.3), 0.09, black, "+x")
    for x in (-8.0, -3.0, 2.0, 7.0):
        for y in (-3.5, 1.5):
            tube(x, y, h - 0.05)
            if x != 7.0 or y > 0:
                R.ceiling_fan(x, y + 1.2, h)
    shot("wide", (-6.0, -D / 2 + 1.0, 2.1), (4.0, D / 2, 1.4))
    shot("board", (2.0, 0.0, 1.7), (W / 2, -0.5, 2.8))


# ============================================================================ the airport
FLIGHTS = (("NILA 512", "CHENNAI", "14:40", "A1-A4", "CHECK-IN"), ("VAIGAI 671", "MUMBAI", "15:05", "B1-B3", "CHECK-IN"),
           ("KURINJI 302", "BENGALURU", "15:30", "A5-A8", "CHECK-IN"), ("NILA 853", "DELHI", "16:20", "B4-B6", "ON TIME"),
           ("PONNI 482", "SHARJAH", "17:15", "C1-C4", "ON TIME"), ("VAIGAI 713", "HYDERABAD", "17:50", "A1-A4", "ON TIME"),
           ("PONNI 384", "SINGAPORE", "23:55", "C5-C8", "ON TIME"))     # (airlines of the story's own)


def airport(T):
    W, D, h = 32.0, 20.0, 9.0
    floor = mat("tile_airport", (1, 1, 1), 0.08, tex=T["tile_airport"], scale=1.2)
    wall = mat("wall_offwhite", (1, 1, 1), 0.8, tex=T["wall_offwhite"], scale=3.0)
    ceil = mat("ceiling_metal", (0.85, 0.86, 0.87), 0.4, 0.3)
    steel = mat("chrome", (0.82, 0.82, 0.84), 0.2, 0.6)
    glass_frame = mat("mullion", (0.3, 0.32, 0.35), 0.3, 0.8)
    hall(W, D, h, floor, wall, ceil, door_w=3.0, door_h=3.0, door_x=0.0, frame=glass_frame)
    sky = mat("daylight", (1, 1, 1), 0.5, emit=(1.0, 0.98, 0.92), strength=2.2)
    # the glass front: daylight between mullions, the full width and height, the door in its middle
    for k in range(16):
        x = -W / 2 + 1.0 + k * 2.0
        if abs(x) < 2.0:
            box((x, -D / 2 + 0.02, 6.0), (2.0, 0.02, 6.0), sky)
            continue
        box((x, -D / 2 + 0.02, h / 2), (2.0, 0.02, h - 0.2), sky)
        box((x - 1.0, -D / 2 + 0.06, h / 2), (0.1, 0.12, h), glass_frame)
    for z in (3.0, 6.0):
        box((0, -D / 2 + 0.06, z), (W, 0.12, 0.1), glass_frame)
    for k in range(4):
        lamp((-W / 2 + 4 + k * 8, -D / 2 + 1.5, 3.5), "window")
    # the ceiling: long slats, light lines between them; columns clad in steel
    slat = mat("ceiling_slat", (0.92, 0.92, 0.9), 0.4)
    for k in range(int(D / 0.8)):
        box((0, -D / 2 + 0.4 + k * 0.8, h - 0.15), (W, 0.3, 0.12), slat)
    for x in (-10.0, 0.0, 10.0):
        for y in (-3.0, 5.0):
            cyl((x, y, h / 2), 0.45, h, steel, 24)
    for x in (-12.0, -4.0, 4.0, 12.0):
        for y in (-6.0, 0.0, 6.0):
            box((x, y, h - 0.22), (3.0, 0.15, 0.03), mat("panel_light", (1, 1, 1), 0.3, emit=(1.0, 0.98, 0.95), strength=4.0))
            lamp((x, y, 4.2))
    # the check-in islands: three rows of counters with bag belts, a lit back panel over each
    belt = mat("belt_black", (0.06, 0.06, 0.07), 0.6)
    desk = mat("checkin_desk", (0.85, 0.85, 0.85), 0.3, 0.2)
    navy = mat("board_navy", (0.08, 0.12, 0.3), 0.4)
    white = mat("letters_white", (0.97, 0.97, 0.97), 0.4)
    lit_white = mat("letters_lit", (1, 1, 1), 0.3, emit=(1, 1, 1), strength=3)
    for i, (x, zone) in enumerate(((-10.0, "A"), (0.0, "B"), (10.0, "C"))):
        y = 4.5
        box((x, y + 1.6, 1.6), (7.0, 0.3, 3.2), navy, 0.02)              # the island's back wall
        text("CHECK-IN  %s" % zone, (x, y + 1.43, 2.6), 0.36, lit_white, "-y")
        for k in range(4):
            cx = x - 2.6 + k * 1.75
            box((cx, y + 0.6, 0.55), (1.2, 0.6, 1.1), desk, 0.02)
            box((cx + 0.75, y + 0.4, 0.25), (0.55, 0.9, 0.5), belt, 0.01)
            R.monitor(cx, y + 0.75, 1.1, math.pi)
            sign("%s%d" % (zone, k + 1), (cx, y + 1.44, 1.6), 0.5, 0.3, white, navy, "-y", 0.2)
            box((cx, y + 0.31, 1.25), (0.3, 0.02, 0.2), mat("screen", (0.05, 0.1, 0.15), 0.1, emit=(0.25, 0.45, 0.7), strength=1.5))
        R.stanchion_row(x - 3.0, x + 3.0, y - 1.0)
        R.stanchion_row(x - 3.0, x + 3.0, y - 2.4)
    staff(-10.0 - 2.6, 4.5 + 1.15, math.pi)
    for x, zone in ((-10.0, "A"), (0.0, "B"), (10.0, "C")):              # at the desks and in the lines
        for k in range(4):
            crowd("stand", x - 2.6 + k * 1.75, 4.5 + 0.0, 0.0)
        for j in range(6):
            crowd("stand", x - 2.5 + j * 1.0, 4.5 - 1.7, -math.pi / 2)
    route("checkin", [(1.6, -8.6), (1.5, -5.0), (1.5, 1.5)])                                  # in, to check-in
    route("across", [(-12.0, -8.0), (-12.0, 1.5), (-4.0, 1.5), (4.0, 1.5), (12.0, 1.5), (12.0, -8.0)])
    route("front", [(-13.0, -7.9), (13.0, -7.9)])
    # the flight information screens hanging over the hall
    fids = mat("fids", (0.02, 0.05, 0.15), 0.2, emit=(0.02, 0.05, 0.2), strength=1.0)
    yellow = mat("fids_yellow", (1, 0.85, 0.2), 0.3, emit=(1.0, 0.85, 0.2), strength=4)
    for x0 in (-6.0, 6.0):
        box((x0, -2.0, 5.2), (5.0, 0.15, 2.8), fids, 0.02)
        for s in (-1, 1):
            cyl((x0 + s * 2.0, -2.0, 7.6), 0.02, 2.0, steel, 8)
        text("DEPARTURES", (x0, -2.09, 6.35), 0.22, yellow, "-y")
        for r, (fl, to, t, ci, st) in enumerate(FLIGHTS):
            z = 6.0 - r * 0.3
            for dx, s in ((-2.35, fl), (-1.15, to), (0.1, t), (0.85, ci), (1.65, st)):
                ltext(s, (x0 + dx, -2.09, z), 0.15, lit_white if dx != 1.65 else yellow, "-y")
    # the way on: security at the back right
    sign("SECURITY CHECK  >  DEPARTURE GATES", (10.0, D / 2 - 0.15, 4.5), 7.5, 0.6, mat("sign_yellow", (1.0, 0.8, 0.1), 0.4), mat("ink_black", (0.05, 0.05, 0.05), 0.4), "-y", 0.32)
    box((14.0, D / 2 - 0.02, 1.4), (3.0, 0.04, 2.8), mat("daylight", (1, 1, 1), 0.5, emit=(1.0, 0.98, 0.92), strength=2.2))
    sign("WELCOME TO COIMBATORE INTERNATIONAL AIRPORT", (-6.0, D / 2 - 0.15, 6.5), 13.0, 0.7, navy, white, "-y", 0.36)
    # seats facing the screens, trolleys, planters
    for k in range(3):
        for s in (-1, 1):
            chrome_seats(s * 7.0, -6.5 + k * 1.6, 0.0, 5)
            for i in range(5):
                crowd("sit", s * 7.0 - 1.55 + 0.31 + 0.62 * i, -6.5 + k * 1.6 - 0.05, math.pi)
    tro = mat("trolley_steel", (0.6, 0.62, 0.64), 0.3, 0.7)
    for k in range(6):
        x = -14.5 + k * 0.35
        box((x, -7.5, 0.45), (0.06, 1.0, 0.04), tro)
        box((x, -7.95, 0.8), (0.06, 0.04, 0.7), tro)
        box((x, -7.5, 0.18), (0.06, 0.9, 0.04), tro)
    for x in (-14.5, 14.5, -3.0, 3.0):
        R.plant(x, -D / 2 + 1.2, 1.4)
    shot("wide", (-13.0, -D / 2 + 1.0, 2.6), (2.0, 5.0, 2.2))
    shot("counters", (4.5, -4.5, 1.7), (-1.0, 5.5, 1.5))


# ============================================================================ the malls' atrium
MALL_SHOPS = {
    "mall_avinashi": ("THE NOYYAL GALLERIA", (0.62, 0.08, 0.1),
                      ("NOYYAL SILKS", "STEPWELL SHOES", "MERIDIAN WATCHES", "BOOKNOOK", "MULLAI CAFE", "KURINJI TOYS",
                       "PERUR LOOM", "KOVAI OPTICALS", "GADGET BAY", "MARUDHAM KITCHEN", "LITTLE FEET", "NOYYAL SILVER")),
    "mall_sathy": ("KONGU MALL", (0.05, 0.38, 0.42),
                   ("KONGU HANDLOOM", "KONGU SPORTS", "PIXEL MOBILES", "THE BAKE HOUSE", "SIRUVANI STYLE", "THENNAI FRESH",
                    "SUNRISE JEWELS", "KOVAI GAMES", "HOME NEST", "VELLIANGIRI PLAY", "KOVAI DENIM", "KAAPI KADAI")),
}


def shopfront(x, y, z, w, facing, name, colour, k):
    """A shop's glass front and its lit name band, the shop's own colour inside and a display or two."""
    n = Vector((0, -1, 0)) if facing == "-y" else Vector((1, 0, 0)) if facing == "+x" else Vector((-1, 0, 0))
    along_x = facing == "-y"
    span = Vector((1, 0, 0)) if along_x else Vector((0, 1, 0))
    c = Vector((x, y, z))
    inside = mat("shop_%d" % k, colour, 0.5, emit=tuple(0.35 * v for v in colour), strength=1.0)
    box(c + Vector((0, 0, 1.6)) - n * 1.2, (w, 0.05, 3.2) if along_x else (0.05, w, 3.2), inside)
    for s in (-1, 1):
        box(c + span * s * (w / 2) + Vector((0, 0, 2.0)) - n * 0.6, (0.12, 1.2, 4.0) if along_x else (1.2, 0.12, 4.0),
            mat("acp_grey", (0.3, 0.3, 0.32), 0.4, 0.3))
    box(c + Vector((0, 0, 1.55)), (w, 0.02, 3.1) if along_x else (0.02, w, 3.1), mat("glass", (0.6, 0.72, 0.75), 0.05, alpha=0.12))
    box(c + Vector((0, 0, 3.55)), (w + 0.1, 0.25, 0.8) if along_x else (0.25, w + 0.1, 0.8), mat("band_black", (0.05, 0.05, 0.06), 0.3))
    lit = mat("shop_lit_%d" % (k % 4), (1, 1, 1), 0.3, emit=((1, 1, 1), (1, 0.85, 0.5), (0.7, 0.9, 1), (1, 0.75, 0.75))[k % 4], strength=4)
    text(name, c + Vector((0, 0, 3.52)) + n * 0.14, min(0.42, w / (len(name) * 0.68)), lit, facing)
    rng = random.Random(k)
    for j in range(3):                                                    # a display stand or a mannequin inside
        p = c - n * 0.7 + span * (-w / 3 + j * w / 3)
        if rng.random() < 0.5:
            cyl((p.x, p.y, z + 0.5), 0.3, 1.0, mat("display_white", (0.95, 0.95, 0.94), 0.3), 20)
            box((p.x, p.y, z + 1.1), (0.3, 0.3, 0.2), mat("goods_%d" % (j % 3), colour, 0.5), 0.02)
        else:
            cyl((p.x, p.y, z + 0.45), 0.08, 0.9, mat("mannequin", (0.9, 0.88, 0.85), 0.4), 12)
            cyl((p.x, p.y, z + 1.25), 0.17, 0.7, mat("goods_%d" % (j % 3), colour, 0.5), 16, r2=0.12)
            cyl((p.x, p.y, z + 1.72), 0.1, 0.22, mat("mannequin", (0.9, 0.88, 0.85), 0.4), 12)
    lamp(tuple(c - n * 0.8 + Vector((0, 0, 2.6))), "lamp")


def escalator(x, y0, y1, z1, rising=True):
    """An escalator from (x, y0) on the floor up to height z1 at y1: its truss, the steps, glass sides, rubber rails."""
    L = y1 - y0
    a = math.atan2(z1, L)
    run = math.hypot(L, z1)
    truss = mat("acp_grey", (0.3, 0.3, 0.32), 0.4, 0.3)
    steel = mat("chrome", (0.82, 0.82, 0.84), 0.2, 0.6)
    glass = mat("glass", (0.6, 0.72, 0.75), 0.05, alpha=0.18)
    black = mat("rubber_black", (0.04, 0.04, 0.04), 0.6)
    mid = Vector((x, (y0 + y1) / 2, z1 / 2))
    box(mid - Vector((0, 0, 0.45)), (1.4, run, 0.6), truss, 0.02, rot=(a, 0, 0))
    for k in range(int(run / 0.4)):                                       # the steps
        t = (k + 0.5) / int(run / 0.4)
        box((x, y0 + L * t, z1 * t - 0.08), (1.0, 0.38, 0.06), steel)
    for s in (-1, 1):
        box(mid + Vector((s * 0.6, 0, 0.5)), (0.02, run, 0.9), glass, rot=(a, 0, 0))
        box(mid + Vector((s * 0.6, 0, 0.97)), (0.08, run, 0.06), black, 0.02, rot=(a, 0, 0))
    box((x, y0 - 0.6, 0.05), (1.4, 1.2, 0.1), steel)                     # the landing plates
    box((x, y1 + 0.5, z1 + 0.05), (1.4, 1.0, 0.1), steel)


def mall(T, key):
    title, accent, shops = MALL_SHOPS[key]
    W, D, h = 30.0, 24.0, 12.0
    z1 = 5.5                                                              # the first floor
    floor = mat("marble_white", (1, 1, 1), 0.1, tex=T["marble_white"], scale=1.2)
    wall = mat("mall_wall", (0.9, 0.89, 0.86), 0.6)
    ceil = mat("ceiling_white", (0.93, 0.93, 0.9), 0.95)
    acc = mat("mall_accent_" + key, accent, 0.4, 0.2)
    hall(W, D, h, floor, wall, ceil, door_w=4.0, door_h=3.6, door_x=0.0, frame=acc)
    glass = mat("glass", (0.6, 0.72, 0.75), 0.05, alpha=0.15)
    steel = mat("chrome", (0.82, 0.82, 0.84), 0.2, 0.6)
    # ground floor shops: the back wall (4) and each side (2 each, 2 on the front), first floor the same above
    names = list(shops)
    cols = [(0.8, 0.3, 0.3), (0.3, 0.5, 0.8), (0.85, 0.7, 0.4), (0.4, 0.7, 0.5), (0.7, 0.45, 0.75), (0.95, 0.6, 0.3)]
    k = 0
    for level, z in enumerate((0.0, z1)):
        for j in range(3):
            if k >= len(names):
                break
            shopfront(-9.0 + j * 9.0, D / 2 - 1.4, z, 6.5, "-y", names[k], cols[k % 6], k)
            k += 1
        for s in (-1, 1):
            for j in range(2 if level == 0 else 1):
                if k >= len(names):
                    break
                shopfront(s * (W / 2 - 1.4), -3.0 + j * 7.0 + (3.0 if level else 0), z, 5.5,
                          "-x" if s > 0 else "+x", names[k], cols[k % 6], k)
                k += 1
    # the first floor: a gallery round the back and sides, its glass railing, the slab's lit edge
    gd = 4.0
    edge = mat("slab_edge", (0.95, 0.95, 0.94), 0.4)
    box((0, D / 2 - gd / 2, z1 - 0.2), (W, gd, 0.4), edge)
    for s in (-1, 1):
        box((s * (W / 2 - gd / 2), -1.0, z1 - 0.2), (gd, D - 2 * gd + 6.0, 0.4), edge)
    box((0, D / 2 - gd / 2, z1 + 0.005), (W, gd, 0.01), floor)
    for s in (-1, 1):
        box((s * (W / 2 - gd / 2), -1.0, z1 + 0.005), (gd, D - 2 * gd + 6.0, 0.01), floor)
    rail_y = D / 2 - gd
    box((0, rail_y, z1 + 0.55), (W - 2 * gd, 0.02, 1.1), glass)
    box((0, rail_y, z1 + 1.12), (W - 2 * gd, 0.08, 0.06), steel)
    for s in (-1, 1):
        rx = s * (W / 2 - gd)
        box((rx, -1.0 + 0.0, z1 + 0.55), (0.02, D - 2 * gd + 6.0, 1.1), glass)
        box((rx, -1.0, z1 + 1.12), (0.08, D - 2 * gd + 6.0, 0.06), steel)
    lit_edge = mat("cove_lit", (1, 0.95, 0.85), 0.3, emit=(1.0, 0.9, 0.75), strength=3)
    box((0, rail_y - 0.01, z1 - 0.38), (W - 2 * gd, 0.02, 0.04), lit_edge)
    for s in (-1, 1):
        for x2 in (s * (W / 2 - gd),):
            for y2 in (-6.0, 1.0, D / 2 - gd):
                cyl((x2, y2, z1 / 2), 0.35, z1, edge, 20)
    # the escalators up the middle to the back gallery
    escalator(-1.0, -1.5, rail_y - 0.6, z1)
    escalator(1.0, -1.5, rail_y - 0.6, z1)
    # the skylight; the mall's name over the gallery; a kiosk, planters, benches, a directory
    box((0, 0, h - 0.04), (14.0, 10.0, 0.04), glow_tex("skylight", T["skylight"], 3.0))
    sign(title, (0, D / 2 - 0.15, 10.5), 12.0, 1.1, acc, mat("letters_lit", (1, 1, 1), 0.3, emit=(1, 1, 1), strength=3), "-y", 0.75)
    box((-7.0, -5.0, 0.55), (2.4, 1.2, 1.1), mat("kiosk_white", (0.95, 0.95, 0.94), 0.3), 0.04)
    box((-7.0, -5.0, 2.4), (2.6, 1.4, 0.1), acc, 0.02)
    for s in (-1, 1):
        cyl((-7.0 + s * 1.2, -5.0, 1.75), 0.03, 1.3, steel, 8)
    text("CHAI & CORN", (-7.0, -5.72, 2.42), 0.16, mat("letters_white", (0.97, 0.97, 0.97), 0.4), "-y")
    staff(-7.0, -4.2, math.pi)
    bx, by_ = -W / 2 + 0.6, -8.5                                         # the multiplex box office, left of the door
    box((bx, by_, 0.55), (0.9, 3.0, 1.1), acc, 0.02)
    box((bx + 0.05, by_, 1.12), (1.0, 3.1, 0.04), mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"]))
    box((bx - 0.2, by_, 2.2), (0.02, 3.0, 2.1), glass)
    lit = mat("letters_lit", (1, 1, 1), 0.3, emit=(1, 1, 1), strength=3)
    for k, (film, times) in enumerate((("KOVAI EXPRESS", "12:30  16:00  19:30"), ("MAZHAI KAALAM", "13:15  18:45"),
                                       ("THE LAST GHAT", "15:00  21:30"))):  # (films of the story's own)
        y3 = by_ + 1.0 - k * 1.0
        box((bx - 0.25, y3, 3.0), (0.05, 0.9, 0.55), mat("screen", (0.05, 0.1, 0.15), 0.1, emit=(0.25, 0.45, 0.7), strength=1.5))
        text(film, (bx - 0.22, y3, 3.1), 0.08, lit, "+x")
        text(times, (bx - 0.22, y3, 2.92), 0.065, mat("fids_yellow", (1, 0.85, 0.2), 0.3, emit=(1.0, 0.85, 0.2), strength=4), "+x")
    R.mark("ticket", bx + 1.4, by_, -math.pi / 2)
    for x2, y2 in ((6.5, -6.0), (-4.0, 2.0), (4.0, 2.0)):
        box((x2, y2, 0.3), (1.6, 1.6, 0.6), mat("planter", (0.4, 0.38, 0.36), 0.5), 0.03)
        R.plant(x2, y2, 1.6)
    for x2 in (-4.0, 4.0):
        box((x2, -3.0, 0.23), (2.2, 0.55, 0.46), mat("seat_black", (0.07, 0.07, 0.08), 0.5), 0.05)
        for i in range(3):
            crowd("sit", x2 - 0.7 + 0.7 * i, -3.1, math.pi)
    for x3 in (-10.0, -7.5, -1.0, 8.0, 10.5):                            # looking in at the shops
        crowd("stand", x3, D / 2 - 2.2, 0.0)
    for s3 in (-1, 1):
        for y3 in (-4.0, 4.5):
            crowd("stand", s3 * (W / 2 - 2.2), y3, -s3 * math.pi / 2)
    crowd("stand", -7.0, -5.9, 0.0)                                      # at the kiosk
    for j in range(3):                                                   # the box office line
        crowd("stand", -W / 2 + 2.2 + j * 0.7, -8.5, math.pi / 2)
    for x3, y3 in ((2.5, -6.5), (-3.0, 5.0), (5.5, 3.0)):               # friends talking
        crowd("talk", x3 - 0.4, y3, -math.pi / 2)
        crowd("talk", x3 + 0.4, y3, math.pi / 2)
    route("round", [(-9.5, -9.5), (9.0, -9.5), (9.5, 8.9), (-9.5, 8.9)], loop=True)          # round the atrium
    route("in", [(1.6, -10.6), (0.0, -4.0), (-6.0, -1.5), (-6.0, 6.5), (-2.5, 8.6)])
    box((5.0, -9.5, 1.0), (1.0, 0.15, 2.0), acc, 0.02)
    box((5.0, -9.59, 1.15), (0.85, 0.01, 1.4), mat("screen", (0.05, 0.1, 0.15), 0.1, emit=(0.25, 0.45, 0.7), strength=1.5))
    for x2 in (-9.0, 0.0, 9.0):
        for y2 in (-8.0, -2.0, 4.0):
            lamp((x2, y2, 4.0))
    for x2 in (-9.0, 0.0, 9.0):
        lamp((x2, D / 2 - 2.0, z1 + 3.0))
    for y2 in (-6.0, 1.0, 8.0):                                          # downlights under the galleries
        for s in (-1, 1):
            cyl((s * (W / 2 - 2.0), y2, z1 - 0.42), 0.12, 0.02, mat("downlight", (1, 1, 1), 0.3, emit=(1, 0.95, 0.85), strength=6), 16)
    for x2 in (-12.0, -6.0, 6.0, 12.0):
        cyl((x2, -9.5, z1 - 0.42), 0.12, 0.02, mat("downlight", (1, 1, 1), 0.3, emit=(1, 0.95, 0.85), strength=6), 16)
    shot("wide", (-10.0, -D / 2 + 1.0, 2.0), (2.0, 4.0, 4.5))
    shot("up", (0.0, -8.0, 1.6), (0.0, 6.0, 6.0))
    shot("boxoffice", (-8.0, -8.5, 1.7), (-W / 2, -8.5, 2.4))


def mall_avinashi(T):
    mall(T, "mall_avinashi")


def mall_sathy(T):
    mall(T, "mall_sathy")


# ============================================================================ Christ the King church
def church(T):
    W, D, h = 15.0, 30.0, 11.0
    floor = mat("terrazzo", (1, 1, 1), 0.2, tex=T["terrazzo"], scale=1.2)
    wall = mat("wall_church", (1, 1, 1), 0.8, tex=T["wall_church"], normal=os.path.join(DTEX, "plaster_normal.jpg"), scale=3.0)
    ceil = mat("ceiling_white", (0.93, 0.93, 0.9), 0.95)
    blue = mat("church_blue", (0.35, 0.55, 0.75), 0.5)
    teak = mat("pew_wood", (1, 1, 1), 0.45, tex=os.path.join(GTEX, "dark_timber_deck_base.jpg"), scale=1.0)
    gold = mat("cross_gold", (0.85, 0.65, 0.2), 0.3, 1.0)
    hall(W, D, h, floor, wall, ceil, door_w=2.6, door_h=4.0, door_x=0.0, frame=teak)
    sg = glow_tex("stained_glass", T["stained_glass"], 2.5)
    # the columns and arches between nave and aisles, the blue band along the walls
    for s in (-1, 1):
        for k in range(6):
            y = -11.0 + k * 4.6
            column(s * 4.6, y, 7.0, wall, 0.7, round_=True)
            box((s * 4.6, y, 7.1), (0.9, 0.9, 0.2), blue, 0.02)
        box((s * 4.6, 0.5, 7.8), (0.7, 25.0, 1.4), wall)
        box((s * (W / 2 - 0.01), 0, 1.0), (0.02, D, 0.1), blue)
        for k in range(6):                                                # the stained-glass windows
            y = -11.0 + k * 4.6
            box((s * (W / 2 - 0.02), y, 4.3), (0.02, 1.3, 3.2), sg)
            cyl((s * (W / 2 - 0.02), y, 5.9), 0.65, 0.02, sg, 3, rot=(0, math.pi / 2, 0))
            box((s * (W / 2 - 0.05), y, 4.3), (0.06, 0.08, 3.4), blue)
            lamp((s * (W / 2 - 1.0), y, 4.2), "window")
            for dy in (-0.7, 0.7):
                box((s * (W / 2 - 0.05), y + dy, 4.3), (0.06, 0.08, 3.4), blue)
    for k in range(10):                                                   # the ceiling's beams
        box((0, -D / 2 + 1.5 + k * 3.0, h - 0.25), (W, 0.3, 0.5), teak)
    # the pews either side of the aisle, a red runner up the aisle
    box((0, -1.0, 0.003), (1.6, 24.0, 0.006), mat("carpet_red", (1, 1, 1), 0.9, tex=T["carpet_red"], scale=1.0))
    for k in range(12):
        y = -11.5 + k * 1.6
        for s in (-1, 1):
            cx = s * 2.4
            box((cx, y, 0.44), (2.9, 0.42, 0.05), teak, 0.01)
            box((cx, y - 0.24, 0.8), (2.9, 0.05, 0.6), teak, 0.01)        # (facing the altar)
            box((cx, y + 0.45, 0.15), (2.8, 0.18, 0.06), mat("kneeler", (0.45, 0.1, 0.1), 0.8), 0.01)
            for i in range(4):
                crowd("sit", cx - 1.05 + 0.7 * i, y + 0.05, 0.0)
            for e in (-1.45, 1.45):
                box((cx + e, y, 0.5), (0.06, 0.6, 1.0), teak, 0.01)
    # the sanctuary: steps, the marble floor, the altar, the cross on the blue apse wall, candles, flowers
    sy = D / 2 - 3.5
    marble = mat("marble_white", (1, 1, 1), 0.12, tex=T["marble_white"], scale=1.2)
    for k in range(3):
        box((0, sy - 1.2 + k * 0.3 + 1.6, 0.1 + k * 0.15), (W - 1.0, 7.0 - k * 0.6, 0.2 + k * 0.0), marble)
    zt = 0.55
    box((0, D / 2 - 0.02, 5.5), (6.0, 0.03, 9.0), mat("apse_blue", (0.55, 0.72, 0.9), 0.6))
    for k in range(9):                                                    # rays behind the cross
        box((0, D / 2 - 0.04, 6.5), (0.08, 0.01, 5.0), mat("rays_gold", (0.95, 0.85, 0.5), 0.4, 0.4),
            rot=(0, (k - 4) * 0.22, 0))
    box((0, D / 2 - 0.12, 6.0), (0.35, 0.15, 4.5), teak, 0.01)            # the cross
    box((0, D / 2 - 0.12, 7.2), (2.4, 0.15, 0.35), teak, 0.01)
    box((0, D / 2 - 0.2, 7.2), (0.5, 0.02, 0.5), gold)
    lamp((0, D / 2 - 2.0, 6.0), "lamp")
    box((0, sy + 0.6, zt + 0.5), (2.8, 1.0, 1.0), marble, 0.01)           # the altar, its cloth
    box((0, sy + 0.6, zt + 1.02), (3.0, 1.1, 0.04), mat("altar_cloth", (0.97, 0.97, 0.95), 0.8))
    box((0, sy + 0.04, zt + 0.85), (3.0, 0.02, 0.35), mat("altar_cloth", (0.97, 0.97, 0.95), 0.8))
    box((0, sy + 0.03, zt + 0.72), (3.0, 0.02, 0.05), gold)
    box((0, D / 2 - 1.0, zt + 0.8), (0.7, 0.5, 0.6), gold, 0.02)          # the tabernacle
    flame = mat("flame", (1, 0.6, 0.2), 0.5, emit=(1, 0.55, 0.15), strength=10)
    for s in (-1, 1):
        cyl((s * 1.2, sy + 0.6, zt + 1.15), 0.04, 0.25, gold, 12)
        cyl((s * 1.2, sy + 0.6, zt + 1.43), 0.025, 0.3, mat("candle_white", (0.97, 0.96, 0.9), 0.5), 12)
        cyl((s * 1.2, sy + 0.6, zt + 1.62), 0.008, 0.04, flame, 8)
        cyl((s * 2.2, sy + 0.4, zt + 0.45), 0.25, 0.9, mat("vase_brass", (0.8, 0.6, 0.25), 0.3, 1.0), 16, r2=0.15)
        for j in range(8):
            a = j * 0.8
            R.dome((s * 2.2 + 0.18 * math.cos(a), sy + 0.4 + 0.18 * math.sin(a), zt + 0.9 + 0.05 * (j % 3)), 0.09, 0.08,
                   mat("flower_%d" % (j % 3), ((0.95, 0.95, 0.9), (0.9, 0.2, 0.25), (0.95, 0.75, 0.2))[j % 3], 0.7))
    box((3.8, sy - 0.6, zt + 0.6), (0.6, 0.45, 1.2), teak, 0.01)          # the lectern
    box((3.8, sy - 0.75, zt + 1.25), (0.7, 0.5, 0.05), teak, 0.01, rot=(0.3, 0, 0))
    box((3.8, sy - 0.85, zt + 0.7), (0.4, 0.02, 0.5), mat("lectern_cloth", (0.6, 0.1, 0.12), 0.8))
    # votive candles by the door, a holy-water stoup, the fans on their long rods, tubes on the columns
    box((-5.8, -D / 2 + 1.5, 0.45), (1.6, 0.6, 0.9), mat("candle_stand", (0.25, 0.25, 0.27), 0.4, 0.7), 0.01)
    for j in range(16):
        cx2, cy2 = -6.45 + (j % 8) * 0.18, -D / 2 + 1.35 + (j // 8) * 0.25
        cyl((cx2, cy2, 0.95), 0.02, 0.1, mat("candle_white", (0.97, 0.96, 0.9), 0.5), 8)
        cyl((cx2, cy2, 1.02), 0.006, 0.03, flame, 6)
    lamp((-5.8, -D / 2 + 1.8, 1.4), "lamp")
    cyl((2.0, -D / 2 + 0.4, 1.0), 0.18, 0.12, marble, 20, r2=0.25)
    cyl((2.0, -D / 2 + 0.4, 0.5), 0.06, 0.9, marble, 12)
    for k in range(5):
        y = -10.0 + k * 4.6
        fan_on_rod(-2.4, y, 5.0, h - 0.5)
        fan_on_rod(2.4, y, 5.0, h - 0.5)
    for s in (-1, 1):
        for k in range(6):
            y = -11.0 + k * 4.6
            box((s * 4.25, y, 4.0), (0.07, 1.22, 0.07), mat("tube_fitting", (0.9, 0.9, 0.88), 0.4))
            box((s * 4.21, y, 4.0), (0.03, 1.18, 0.04), mat("tube_glow", (1, 1, 1), 0.3, emit=(0.95, 0.97, 1.0), strength=5.0))
            lamp((s * 3.6, y, 3.8))
    R.mark("pray", -1.2, -11.5 + 6 * 1.6 - 0.05, math.pi)                # a pew halfway up, by the aisle
    route("aisle", [(0.0, -12.6), (0.0, 9.0)])                                                 # up the aisle
    route("back", [(-4.5, -13.8), (5.5, -13.8)])
    shot("wide", (1.2, -D / 2 + 1.2, 1.8), (0.0, D / 2, 3.2))
    shot("altar", (0.0, 3.0, 1.7), (0.0, D / 2, 3.5))


# ============================================================================ houses
def house_mid(T):
    """A middle-class family's front hall in an independent house: mosaic floor, peach walls."""
    W, D, h = 7.0, 6.0, 3.0
    floor = mat("mosaic", (1, 1, 1), 0.2, tex=T["mosaic"], scale=1.2)
    wall = mat("wall_peach", (1, 1, 1), 0.9, tex=T["wall_peach"], normal=os.path.join(DTEX, "plaster_normal.jpg"), scale=2.5)
    ceil = mat("ceiling_white", (0.93, 0.93, 0.9), 0.95)
    R.shell(W, D, h, floor, wall, ceil, None, door_w=1.0, door_x=1.8,
            windows=[("L", -0.8, 1.2, 0.9, 1.2), ("B", -2.0, 0.9, 0.0, 2.1), ("R", 1.4, 1.0, 0.9, 1.2)])
    wood = mat("timber", (1, 1, 1), 0.55, tex=os.path.join(GTEX, "warm_natural_timber_base.jpg"), scale=1.2)
    teak = mat("door_teak", (1, 1, 1), 0.5, tex=os.path.join(GTEX, "dark_timber_deck_base.jpg"), scale=1.0)
    cushion = mat("cushion_maroon", (0.5, 0.12, 0.15), 0.85)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    # beyond the back doorway, the kitchen: a curtain half drawn
    box((-2.0, D / 2 + 1.2, 1.4), (1.2, 0.05, 2.8), mat("kitchen_wall", (0.85, 0.85, 0.8), 0.8))
    box((-2.0, D / 2 + 0.6, -0.05), (1.2, 1.2, 0.1), floor)
    # the wooden sofa set: a three-seater and two chairs with cushions round a glass-topped teapoy
    def sofa(x, y, yaw, seats):
        ca, sa = math.cos(yaw), math.sin(yaw)
        L = 0.62 * seats

        def at(u, v, z):
            return (x + u * ca - v * sa, y + u * sa + v * ca, z)
        box(at(0, 0, 0.32), (L, 0.65, 0.08), teak, 0.01, rot=(0, 0, yaw))
        box(at(0, 0, 0.42), (L - 0.1, 0.6, 0.12), cushion, 0.04, rot=(0, 0, yaw))
        box(at(0, 0.32, 0.72), (L, 0.06, 0.6), teak, 0.01, rot=(0, 0, yaw))
        box(at(0, 0.26, 0.7), (L - 0.15, 0.08, 0.4), cushion, 0.03, rot=(0, 0, yaw))
        for e in (-L / 2, L / 2):
            box(at(e, 0, 0.33), (0.06, 0.65, 0.66), teak, 0.01, rot=(0, 0, yaw))
    sofa(-1.0, 1.6, 0.0, 3)
    sofa(-3.0, 0.0, -math.pi / 2, 1)
    sofa(0.8, 0.0, math.pi / 2, 1)
    box((-1.0, 0.2, 0.38), (1.2, 0.6, 0.03), mat("glass", (0.6, 0.72, 0.75), 0.05, alpha=0.3))
    box((-1.0, 0.2, 0.18), (1.1, 0.5, 0.36), teak, 0.01)
    box((-1.2, 0.2, 0.42), (0.25, 0.3, 0.04), mat("newspaper", (0.85, 0.84, 0.8), 0.9))
    # the showcase on the back wall: glass doors, dolls, a trophy, a framed wedding photo; the TV beside it
    box((1.5, D / 2 - 0.25, 1.1), (1.6, 0.45, 2.2), teak, 0.01)
    box((1.5, D / 2 - 0.48, 1.4), (1.5, 0.01, 1.4), mat("showcase_glass", (0.7, 0.8, 0.82), 0.02, alpha=0.06))
    for r in range(3):
        box((1.5, D / 2 - 0.25, 0.75 + r * 0.45), (1.5, 0.4, 0.02), wood)
        for j in range(4):
            c = ((0.9, 0.3, 0.4), (0.85, 0.7, 0.3), (0.3, 0.6, 0.8), (0.95, 0.95, 0.9))[(r + j) % 4]
            cyl((0.95 + j * 0.36, D / 2 - 0.27, 0.86 + r * 0.45), 0.05, 0.2, mat("curio_%d" % ((r + j) % 4), c, 0.4), 12)
    R.frame(1.5, D / 2 - 0.05, 2.45, 0.6, 0.4, mat("photo_family", (1, 1, 1), 0.7, tex=T["photo_family"]))
    box((2.95, D / 2 - 0.3, 0.35), (1.0, 0.45, 0.7), teak, 0.01)
    box((2.95, D / 2 - 0.3, 1.05), (0.9, 0.08, 0.55), mat("tv_black", (0.02, 0.02, 0.025), 0.15), 0.01)
    # the fridge in the hall by the kitchen door, its magnets; the dining table and steel chairs
    box((-3.05, D / 2 - 0.45, 0.85), (0.65, 0.65, 1.7), mat("fridge_maroon", (0.45, 0.1, 0.12), 0.3, 0.3), 0.04)
    for j in range(5):
        box((-3.0 + 0.1 * (j % 3), D / 2 - 0.79, 1.2 + 0.12 * j), (0.06, 0.01, 0.05),
            mat("magnet_%d" % (j % 3), ((0.9, 0.8, 0.2), (0.2, 0.6, 0.9), (0.9, 0.3, 0.3))[j % 3], 0.4))
    box((-3.05, D / 2 - 0.45, 1.75), (0.5, 0.4, 0.04), mat("fridge_cover", (0.8, 0.75, 0.6), 0.9))
    R.table(-0.9, -1.9, 1.2, 0.8, 0.75, mat("table_sunmica", (0.75, 0.62, 0.45), 0.4), steel)
    for dx, dy, yaw in ((-0.4, -0.55, math.pi), (0.4, -0.55, math.pi), (-0.4, 0.55, 0.0), (0.4, 0.55, 0.0)):   # facing the table
        R.steel_chair(-0.9 + dx, -1.9 + dy, yaw, mat("chair_seat_green", (0.15, 0.4, 0.3), 0.5))
    cyl((-0.9, -1.9, 0.86), 0.1, 0.22, steel, 20)                        # a water jug, a hot box
    cyl((-0.6, -1.85, 0.82), 0.12, 0.14, mat("hotbox_red", (0.7, 0.12, 0.1), 0.4), 20)
    # the children's corner: a study table with a school bag, books and a lamp; a wall chart
    R.table(2.9, -1.6, 0.9, 0.55, 0.72, wood, wood)
    box((2.75, -1.55, 0.86), (0.36, 0.26, 0.25), mat("schoolbag_blue", (0.15, 0.3, 0.7), 0.7), 0.04)
    for j in range(4):
        box((3.15, -1.6, 0.76 + j * 0.03), (0.22, 0.3, 0.025), mat("book_%d" % j, ((0.8, 0.2, 0.2), (0.2, 0.5, 0.3), (0.9, 0.8, 0.3), (0.3, 0.3, 0.7))[j], 0.7))
    R.chair_poly(2.9, -1.1, math.pi, (0.15, 0.35, 0.7))
    box((W / 2 - 0.02, -1.6, 1.6), (0.01, 0.6, 0.8), mat("calendar", (1, 1, 1), 0.8, tex=T["calendar"]))
    # the pooja shelf on the left wall with a lamp, the clock, a switchboard, the tubes and the fan
    box((-W / 2 + 0.15, 1.9, 1.5), (0.3, 0.7, 0.04), wood)
    R.frame(-W / 2 + 0.03, 1.9, 1.8, 0.28, 0.32, mat("photo_god", (1, 1, 1), 0.5, tex=T["photo_god"]), facing="+x")
    cyl((-W / 2 + 0.18, 1.75, 1.58), 0.04, 0.1, mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0), 16)
    cyl((-W / 2 + 0.18, 1.75, 1.65), 0.008, 0.02, mat("flame", (1, 0.6, 0.2), 0.5, emit=(1, 0.55, 0.15), strength=10), 8)
    R.wall_clock(0.0, D / 2 - 0.02, 2.4)
    R.switchboard(1.15, -D / 2 + 0.02, 1.25, "-y")
    tube(-1.0, 0.0, h - 0.05)
    tube(2.2, -1.0, h - 0.05, False)
    R.ceiling_fan(-1.0, 0.6, h)
    R.skirting(W, D, mat("skirting_grey", (0.45, 0.43, 0.4), 0.3), 1.8, 1.0)
    R.door_leaf(1.3, -D / 2, 0.95, teak, -1)
    staff(-1.0, 1.25, math.pi)
    shot("wide", (2.6, -2.6, 2.0), (-1.5, 1.6, 0.9))


def house_flat(T):
    """A modern flat in a gated apartment block: big vitrified tiles, an L sofa, the TV wall, an open kitchen."""
    W, D, h = 9.0, 7.0, 2.9
    floor = mat("tile_cream", (1, 1, 1), 0.08, tex=T["tile_cream"], scale=1.2)
    wall = mat("wall_offwhite", (1, 1, 1), 0.9, tex=T["wall_offwhite"], scale=2.5)
    ceil = mat("ceiling_white", (0.95, 0.95, 0.93), 0.95)
    R.shell(W, D, h, floor, wall, ceil, None, door_w=1.0, door_x=3.4, windows=[])
    fabric = mat("sofa_grey", (0.42, 0.43, 0.45), 0.9)
    teal = mat("wall_teal", (1, 1, 1), 0.8, tex=T["wall_teal"])
    oak = mat("timber", (1, 1, 1), 0.5, tex=os.path.join(GTEX, "warm_natural_timber_base.jpg"), scale=1.2)
    gran = mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"])
    white_gloss = mat("cabinet_white", (0.93, 0.93, 0.92), 0.2)
    steel = mat("steel_brushed", (0.7, 0.71, 0.72), 0.3, 0.8)
    # the balcony: a sliding glass door the width of the right wall's back half, daylight and the railing
    sky = mat("daylight", (1, 1, 1), 0.5, emit=(1.0, 0.98, 0.92), strength=2.2)
    box((W / 2 - 0.02, 1.4, 1.2), (0.02, 3.0, 2.4), sky)
    for dy in (-1.5, 0.0, 1.5):
        box((W / 2 - 0.05, 1.4 + dy, 1.2), (0.05, 0.06, 2.4), mat("mullion", (0.3, 0.32, 0.35), 0.3, 0.8))
    lamp((W / 2 - 0.8, 1.4, 1.6), "window")
    R.curtain(W / 2 - 0.15, -0.3, 0.4, 0.05, 2.5, mat("curtain_linen", (0.85, 0.8, 0.7), 0.9))
    # the living: the TV wall (teal, a wooden unit, the TV), an L sofa, a rug, a coffee table, a split AC
    box((-W / 2 + 0.02, -0.8, h / 2), (0.03, 3.6, h), teal)
    box((-W / 2 + 0.25, -0.8, 0.25), (0.45, 2.6, 0.4), oak, 0.01)
    box((-W / 2 + 0.07, -0.8, 1.35), (0.05, 1.45, 0.82), mat("tv_black", (0.02, 0.02, 0.025), 0.12), 0.01)
    box((-W / 2 + 0.25, -1.9, 0.6), (0.15, 0.15, 0.3), mat("speaker", (0.08, 0.08, 0.09), 0.4))
    box((-1.0, -0.8, 0.22), (0.9, 3.0, 0.42), fabric, 0.05)            # the long arm, facing the TV
    box((-0.6, -0.8, 0.55), (0.18, 3.0, 0.55), fabric, 0.05)
    box((-1.8, -2.5, 0.22), (1.6, 0.9, 0.42), fabric, 0.05)            # the short arm
    box((-1.8, -2.9, 0.55), (1.6, 0.18, 0.55), fabric, 0.05)
    for j, y in enumerate((-1.8, -0.8, 0.2)):
        box((-0.8, y, 0.62), (0.15, 0.45, 0.4), mat("cushion_%d" % j, ((0.85, 0.6, 0.2), (0.75, 0.75, 0.72), (0.2, 0.4, 0.45))[j], 0.85), 0.05)
    box((-2.4, -0.8, 0.005), (2.0, 2.6, 0.01), mat("rug_grey", (1, 1, 1), 0.95, tex=T["rug_grey"]))
    box((-2.4, -0.8, 0.38), (0.8, 1.2, 0.05), oak, 0.01)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((-2.4 + sx * 0.34, -0.8 + sy * 0.54, 0.18), (0.04, 0.04, 0.36), mat("leg_black", (0.05, 0.05, 0.05), 0.4))
    box((-W / 2 + 0.15, 1.7, 2.45), (0.25, 1.0, 0.3), mat("ac_white", (0.95, 0.95, 0.94), 0.35), 0.03)
    # dining: an oak table of six with upholstered chairs, a pendant lamp
    R.table(1.8, -1.6, 1.8, 0.95, 0.76, oak, mat("leg_black", (0.05, 0.05, 0.05), 0.4))
    for dx in (-0.6, 0.0, 0.6):
        for s in (-1, 1):
            R.dining_chair(1.8 + dx, -1.6 + s * 0.68, math.pi if s > 0 else 0.0, mat("chair_fabric", (0.75, 0.68, 0.55), 0.85), oak)
    cyl((1.8, -1.6, 2.2), 0.25, 0.25, mat("pendant_black", (0.08, 0.08, 0.08), 0.4), 24, r2=0.08)
    cyl((1.8, -1.6, 2.06), 0.2, 0.01, mat("pendant_glow", (1, 1, 1), 0.3, emit=(1, 0.9, 0.7), strength=6), 24)
    cyl((1.8, -1.6, 2.6), 0.005, 0.6, mat("leg_black", (0.05, 0.05, 0.05), 0.4), 6)
    lamp((1.8, -1.6, 1.9), "lamp")
    cyl((1.8, -1.6, 0.85), 0.15, 0.04, mat("bowl_white", (0.95, 0.95, 0.94), 0.3), 24, r2=0.08)
    # the open kitchen at the back: base and wall cabinets, granite top, hob and chimney, the island, the fridge
    ky = D / 2 - 0.32
    box((0.5, ky, 0.43), (5.0, 0.6, 0.86), white_gloss, 0.01)
    box((0.5, ky - 0.02, 0.88), (5.05, 0.65, 0.04), gran, 0.005)
    box((-1.25, ky + 0.12, 1.95), (1.5, 0.36, 0.7), white_gloss, 0.01)
    box((1.75, ky + 0.12, 1.95), (2.5, 0.36, 0.7), white_gloss, 0.01)
    for j in range(8):
        box((-1.6 + j * 0.62, ky - 0.31, 0.45), (0.01, 0.01, 0.8), mat("cabinet_line", (0.6, 0.6, 0.6), 0.4))
    box((0.0, ky, 0.91), (0.75, 0.5, 0.02), mat("hob_glass", (0.02, 0.02, 0.02), 0.05))
    for j in range(3):
        cyl((-0.22 + j * 0.22, ky, 0.93), 0.08, 0.02, mat("burner", (0.15, 0.15, 0.15), 0.3, 0.8), 16)
    box((0.0, ky + 0.02, 1.72), (0.8, 0.5, 0.06), mat("hob_glass", (0.02, 0.02, 0.02), 0.05), 0.01, rot=(-0.35, 0, 0))
    box((0.0, ky + 0.15, 2.25), (0.3, 0.25, 0.9), steel)
    box((1.6, ky, 0.9), (0.6, 0.45, 0.04), steel)                        # the sink
    box((-2.65, ky - 0.05, 0.9), (0.9, 0.7, 1.8), steel, 0.03)           # the double-door fridge
    box((-2.65, ky - 0.41, 0.9), (0.01, 0.01, 1.7), mat("cabinet_line", (0.6, 0.6, 0.6), 0.4))
    box((0.6, ky - 1.7, 0.45), (2.4, 0.8, 0.9), white_gloss, 0.01)       # the island and its stools
    box((0.6, ky - 1.7, 0.92), (2.5, 0.9, 0.04), gran, 0.005)
    for j in range(3):
        cyl((-0.1 + j * 0.7, ky - 2.35, 0.35), 0.18, 0.04, mat("leg_black", (0.05, 0.05, 0.05), 0.4), 20)
        cyl((-0.1 + j * 0.7, ky - 2.35, 0.65), 0.17, 0.06, oak, 20)
        cyl((-0.1 + j * 0.7, ky - 2.35, 0.32), 0.02, 0.62, steel, 8)
    box((1.4, ky - 1.7, 1.02), (0.3, 0.3, 0.15), mat("fruit_bowl", (0.9, 0.6, 0.2), 0.6), 0.04)
    # the pooja unit by the door: a wooden cabinet with a carved arch, brass lamps, a picture
    px, py = 1.9, -D / 2 + 0.3
    box((px, py, 0.4), (0.9, 0.45, 0.8), oak, 0.01)
    box((px, py + 0.1, 1.5), (0.9, 0.3, 1.2), oak, 0.01)
    box((px, py - 0.06, 1.45), (0.65, 0.01, 0.85), mat("pooja_back", (0.75, 0.35, 0.1), 0.6))
    R.frame(px, py - 0.03, 1.5, 0.3, 0.38, mat("photo_god", (1, 1, 1), 0.5, tex=T["photo_god"]), face_y=1)
    for s in (-1, 1):
        cyl((px + s * 0.25, py - 0.1, 0.9), 0.04, 0.18, mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0), 16, r2=0.02)
    # the false ceiling: a lowered band round the room, a lit cove, downlights
    lc = mat("ceiling_white", (0.95, 0.95, 0.93), 0.95)
    cove = mat("cove_lit", (1, 0.95, 0.85), 0.3, emit=(1.0, 0.9, 0.75), strength=3)
    for s in (-1, 1):
        box((0, s * (D / 2 - 0.45), h - 0.15), (W, 0.9, 0.3), lc)
        box((0, s * (D / 2 - 0.92), h - 0.06), (W - 1.8, 0.04, 0.03), cove)
        box((s * (W / 2 - 0.45), 0, h - 0.15), (0.9, D, 0.3), lc)
        box((s * (W / 2 - 0.92), 0, h - 0.06), (0.04, D - 1.8, 0.03), cove)
    for x, y in ((-2.4, -0.8), (-2.4, 1.5), (1.8, 1.0), (0.5, 2.5), (3.4, -2.6)):
        cyl((x, y, h - 0.31), 0.07, 0.02, mat("downlight", (1, 1, 1), 0.3, emit=(1, 0.95, 0.85), strength=6), 16)
        lamp((x, y, h - 0.6))
    R.plant(W / 2 - 0.5, -0.9, 1.3)
    R.plant(-W / 2 + 0.5, 2.9, 1.0)
    R.frame(-0.6, -D / 2 + 0.04, 1.6, 1.2, 0.8, mat("photo_hills", (1, 1, 1), 0.6, tex=T["photo_hills"]), face_y=1)
    R.skirting(W, D, mat("skirting_grey", (0.6, 0.58, 0.55), 0.3), 3.4, 1.0)
    staff(0.6, ky - 0.9, math.pi)
    shot("wide", (3.6, -2.6, 1.9), (-1.5, 1.2, 0.9))
    shot("kitchen", (-2.0, -1.5, 1.7), (0.5, D / 2, 1.0))


def house_old(T):
    """An old Kongu house built round a courtyard open to the sky: wooden pillars, the swing, the tulasi maadam."""
    W, D, h = 9.0, 9.0, 3.2
    floor = mat("red_oxide", (1, 1, 1), 0.18, tex=T["red_oxide"], scale=2.0)
    wall = mat("wall_lime", (1, 1, 1), 0.92, tex=T["wall_lime"], normal=os.path.join(DTEX, "plaster_normal.jpg"), scale=2.5)
    ceil = mat("ceiling_rafters", (0.35, 0.22, 0.12), 0.7)
    cx, cy, cw = 0.0, 0.5, 3.2
    hall(W, D, h, floor, wall, ceil, door_w=1.1, door_h=2.1, door_x=0.0, hole=(cx, cy, cw, cw))
    teak = mat("door_teak", (1, 1, 1), 0.5, tex=os.path.join(GTEX, "dark_timber_deck_base.jpg"), scale=1.0)
    brass = mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0)
    stone = mat("court_stone", (0.62, 0.6, 0.56), 0.6, tex=T["cement"], scale=1.5)
    sky = mat("sky_open", (1, 1, 1), 0.5, emit=(0.75, 0.85, 1.0), strength=2.5)
    # the courtyard: sunk a step, stone-paved, open above (the sky over a parapet), a tulasi maadam in the middle
    box((cx, cy, -0.04), (cw, cw, 0.1), stone)
    for s in (-1, 1):
        box((cx + s * cw / 2, cy, 0.0), (0.12, cw, 0.08), stone)
        box((cx, cy + s * cw / 2, 0.0), (cw, 0.12, 0.08), stone)
        box((cx + s * (cw / 2 + 0.05), cy, h + 0.6), (0.1, cw, 1.2), wall)     # the parapet round the opening
        box((cx, cy + s * (cw / 2 + 0.05), h + 0.6), (cw, 0.1, 1.2), wall)
    box((cx, cy, h + 1.25), (cw + 0.4, cw + 0.4, 0.02), sky)
    for k in range(4):
        lamp((cx - 0.8 + (k % 2) * 1.6, cy - 0.8 + (k // 2) * 1.6, 2.6), "window")
    maadam = mat("maadam_white", (0.92, 0.9, 0.85), 0.7)
    mred = mat("maadam_red", (0.6, 0.15, 0.1), 0.6)
    box((cx, cy, 0.1), (0.8, 0.8, 0.2), maadam, 0.01)                    # the tulasi maadam: a stepped base,
    box((cx, cy, 0.5), (0.55, 0.55, 0.6), maadam, 0.01)                  # a niche for the lamp, a red-bordered top
    box((cx, cy - 0.27, 0.48), (0.22, 0.02, 0.3), mat("niche_dark", (0.15, 0.1, 0.08), 0.8))
    for z in (0.22, 0.79):
        box((cx, cy, z), (0.6, 0.6, 0.04), mred)
    box((cx, cy, 0.86), (0.66, 0.66, 0.1), maadam, 0.01)
    leaf = mat("tulasi_leaf", (0.18, 0.4, 0.14), 0.7)
    for k in range(9):
        a = k * 0.7
        rr = 0.05 + 0.03 * (k % 3)
        R.dome((cx + rr * math.cos(a), cy + rr * math.sin(a), 0.91 + 0.08 * (k % 4)), 0.09, 0.12, leaf)
    cyl((cx, cy - 0.22, 0.38), 0.03, 0.03, mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0), 12)
    kolam = mat("kolam_white", (0.97, 0.97, 0.95), 0.9)
    for k in range(12):                                                  # a kolam on the step in front of it
        a = k * math.tau / 12
        cyl((cx + 0.55 * math.cos(a), cy - 1.0 + 0.25 * math.sin(a), 0.012), 0.025, 0.004, kolam, 8)
    # the wooden pillars at the courtyard's corners, beams over them
    for sx in (-1, 1):
        for sy in (-1, 1):
            px, py = cx + sx * (cw / 2 + 0.15), cy + sy * (cw / 2 + 0.15)
            cyl((px, py, h / 2), 0.11, h, teak, 12)
            box((px, py, 0.08), (0.32, 0.32, 0.16), stone, 0.01)
            box((px, py, h - 0.1), (0.3, 0.3, 0.2), teak, 0.01)
    for s in (-1, 1):
        box((cx + s * (cw / 2 + 0.15), cy, h - 0.12), (0.18, cw + 0.5, 0.22), teak)
        box((cx, cy + s * (cw / 2 + 0.15), h - 0.12), (cw + 0.5, 0.18, 0.22), teak)
    for k in range(12):                                                  # rafters (not over the open courtyard)
        x = -W / 2 + 0.4 + k * 0.75
        if abs(x - cx) > cw / 2 + 0.2:
            box((x, 0, h - 0.04), (0.08, D, 0.08), teak)
    # the swing on its chains on the left, a brass lamp stand, the vessels on a shelf, a big wooden chest
    sx0 = -3.2
    box((sx0, 0.5, 0.55), (0.8, 1.8, 0.06), teak, 0.01)
    for dy in (-0.8, 0.8):
        for dx in (-0.3, 0.3):
            cyl((sx0 + dx, 0.5 + dy, (0.58 + h) / 2), 0.008, h - 0.58, mat("chain_iron", (0.25, 0.25, 0.25), 0.5, 0.8), 6)
    box((sx0, 0.5, 0.62), (0.5, 0.6, 0.06), mat("pillow", (0.93, 0.93, 0.9), 0.85), 0.03)
    cyl((-3.8, -2.8, 0.03), 0.14, 0.06, brass, 20)                        # the kuthu vilakku
    cyl((-3.8, -2.8, 0.6), 0.025, 1.1, brass, 12)
    cyl((-3.8, -2.8, 1.17), 0.12, 0.05, brass, 20)
    cyl((-3.8, -2.8, 1.28), 0.03, 0.12, brass, 10, r2=0.01)
    box((W / 2 - 0.2, -2.0, 1.6), (0.3, 2.2, 0.04), teak)
    for k in range(6):
        cyl((W / 2 - 0.22, -2.9 + k * 0.36, 1.75), 0.11 + 0.02 * (k % 2), 0.25, brass if k % 2 == 0 else mat("copper", (0.75, 0.4, 0.25), 0.35, 1.0), 16, r2=0.07)
    box((W / 2 - 0.5, 2.2, 0.4), (0.7, 1.4, 0.8), teak, 0.01)            # the chest
    for z in (0.15, 0.65):
        box((W / 2 - 0.86, 2.2, z), (0.02, 1.45, 0.06), brass)
    cyl((-3.6, 3.5, 0.08), 0.08, 0.9, mat("mat_reed", (0.75, 0.62, 0.38), 0.9), 16, rot=(0, math.pi / 2, 0))
    # the rooms round the courtyard: closed doors in the side and back walls, old photos, a clock
    for x, y, facing in ((-2.5, D / 2, "-y"), (2.5, D / 2, "-y")):
        box((x, y - 0.03, 1.05), (0.95, 0.04, 2.1), teak, 0.006)
        for z in (0.55, 1.5):
            box((x, y - 0.055, z), (0.75, 0.012, 0.75), mat("door_panel", (0.3, 0.17, 0.08), 0.45), 0.004)
        box((x, y - 0.03, 2.15), (1.1, 0.06, 0.1), teak)
    for y in (-2.0, 3.0):
        box((W / 2 - 0.03, y, 1.05), (0.04, 0.95, 2.1), teak, 0.006)
    R.frame(-1.0, D / 2 - 0.02, 2.2, 0.4, 0.5, mat("photo_sepia", (1, 1, 1), 0.7, tex=T["photo_sepia"]))
    R.frame(0.0, D / 2 - 0.02, 2.25, 0.36, 0.46, mat("photo_appa", (1, 1, 1), 0.7, tex=T["photo_appa"]))
    R.frame(1.0, D / 2 - 0.02, 2.2, 0.3, 0.38, mat("photo_god", (1, 1, 1), 0.5, tex=T["photo_god"]))
    R.wall_clock(-W / 2 + 0.02, -1.0, 2.4, "+x")
    box((0, D / 2 - 0.01, 0.5), (W, 0.02, 1.0), mat("dado_red", (0.45, 0.12, 0.08), 0.4))
    for s in (-1, 1):
        box((s * (W / 2 - 0.01), 0, 0.5), (0.02, D, 1.0), mat("dado_red", (0.45, 0.12, 0.08), 0.4))
    for x, y in ((-3.0, -3.0), (3.0, -3.0), (-3.0, 3.5), (3.0, 3.5)):
        cyl((x, y, h - 0.25), 0.1, 0.12, mat("bulb_glow", (1, 0.9, 0.7), 0.3, emit=(1, 0.85, 0.6), strength=5), 12)
        lamp((x, y, h - 0.5), "lamp")
    staff(-3.2, 0.9, -math.pi / 2)
    shot("wide", (2.8, -3.6, 1.8), (-1.5, 2.0, 1.2))


# ============================================================================ Nehru Stadium
def stadium(T):
    """In at the gate: the concourse under the stand (ticket window, turnstiles), through the tunnels onto the top
    of the stand, its concrete tiers down to the railing, and the ground beyond: the red track, the football pitch,
    the far stand and the floodlight masts under an open sky."""
    W = 48.0
    yf, yc = -28.0, -22.0                                                 # the gate's wall, the concourse's back
    hc = 3.2
    concrete = mat("stadium_concrete", (0.72, 0.7, 0.66), 0.85, tex=T["cement"], scale=3.0)
    paint = mat("stadium_wall", (0.85, 0.82, 0.74), 0.85, tex=T["wall_rail"], scale=3.0)
    maroon = mat("letters_maroon", (0.4, 0.05, 0.05), 0.5)
    white = mat("letters_white", (0.97, 0.97, 0.97), 0.4)
    steel = mat("rail_steel", (0.3, 0.32, 0.35), 0.4, 0.8)
    sky = mat("sky_open", (1, 1, 1), 0.5, emit=(0.75, 0.85, 1.0), strength=2.5)
    # the concourse: floor, ceiling (the stand above), the gate wall with its doorway, the back wall's three tunnels
    box((0, (yf + yc) / 2, -0.05), (W, yc - yf, 0.1), concrete)
    box((0, (yf + yc) / 2, hc + 0.1), (W, yc - yf, 0.2), concrete)
    dw = 3.0
    box((-(W / 2 + dw / 2) / 2, yf - 0.1, hc / 2), (W / 2 - dw / 2, 0.2, hc), paint)
    box(((W / 2 + dw / 2) / 2, yf - 0.1, hc / 2), (W / 2 - dw / 2, 0.2, hc), paint)
    box((0, yf - 0.1, (hc + 2.6) / 2), (dw, 0.2, hc - 2.6), paint)
    box((0, yf - 0.9, 1.3), (dw + 0.4, 0.02, 2.8), mat("daylight", (1, 1, 1), 0.5, emit=(1.0, 0.98, 0.92), strength=2.2))
    empty("Entry", (0, yf + 0.9, 0), 0.0)
    empty("Exit", (0, yf + 0.35, 0), math.pi)
    tunnels = (-12.0, 0.0, 12.0)
    a = -W / 2
    for x in tunnels:
        box(((a + x - 1.6) / 2, yc + 0.1, hc / 2), (x - 1.6 - a, 0.2, hc), paint)
        box((x, yc + 0.1, (hc + 2.6) / 2), (3.2, 0.2, hc - 2.6), paint)
        a = x + 1.6
        sign("STAND  %s" % "ABC"[tunnels.index(x)], (x, yc - 0.05, 2.9), 1.6, 0.3, maroon, white, "-y", 0.18)
    box(((a + W / 2) / 2, yc + 0.1, hc / 2), (W / 2 - a, 0.2, hc), paint)
    for sx in (-1, 1):
        box((sx * (W / 2 + 0.1), (yf + yc) / 2, hc / 2), (0.2, yc - yf, hc), paint)
    box((0, yf + 0.02, 0.6), (W, 0.02, 1.2), maroon)
    # the ticket window, the turnstiles, the name board, a snack counter, the notices
    box((-6.0, yf + 0.5, 0.55), (2.4, 0.8, 1.1), paint, 0.01)
    for k in range(7):
        box((-7.0 + k * 0.33, yf + 0.15, 1.8), (0.02, 0.02, 1.4), mat("window_bars", (0.1, 0.12, 0.1), 0.4, 0.6))
    sign("TICKETS", (-6.0, yf + 0.15, 2.75), 2.0, 0.35, maroon, white, "+y", 0.22)
    staff(-6.0, yf + 0.2, 0.0)
    R.mark("ticket", -6.0, yf + 1.3, math.pi)
    for k in range(3):                                                   # turnstiles before the middle tunnel
        x = -2.0 + k * 2.0
        cyl((x, yc - 2.0, 0.5), 0.12, 1.0, steel, 12)
        for j in range(3):
            ang = j * math.tau / 3
            box((x + 0.3 * math.cos(ang), yc - 2.0 + 0.3 * math.sin(ang), 0.95), (0.6, 0.04, 0.04), steel, rot=(0, 0, ang))
        if k < 2:
            box((x + 1.0, yc - 2.0, 0.5), (0.1, 1.2, 1.0), steel)
    sign("JAWAHARLAL NEHRU STADIUM  -  SDAT", (0, yf + 0.15, 2.6), 9.0, 0.45, maroon, white, "+y", 0.28)
    box((9.0, yf + 0.5, 0.5), (3.0, 0.7, 1.0), mat("kiosk_blue", (0.2, 0.4, 0.7), 0.5), 0.01)
    text("TEA  -  SNACKS  -  WATER", (9.0, yf + 0.86, 0.75), 0.13, white, "+y")
    for k in range(4):
        cyl((8.0 + k * 0.6, yf + 0.5, 1.12), 0.1, 0.24, mat("jar_glass", (0.8, 0.85, 0.85), 0.05, alpha=0.4), 16)
    box((W / 2 - 0.03, -25.0, 1.6), (0.02, 1.2, 0.9), mat("notice", (1, 1, 1), 0.8, tex=T["notice"]))
    for x in (-18.0, -10.0, -2.0, 6.0, 14.0, 20.0):
        tube(x, -25.0, hc - 0.05)
    # the stand: twelve tiers down from the tunnels to the front railing, a stair aisle down from each tunnel
    tiers, td, tz = 12, 1.0, 0.4
    for t in range(tiers):
        y = yc + 0.2 + t * td
        z = -t * tz
        box((0, y + td / 2, z - 3.0), (W, td, 6.0), concrete)
        box((0, y + 0.02, z - 0.02), (W, 0.04, 0.04), mat("tier_edge", (0.6, 0.58, 0.54), 0.8))
        if 3 <= t <= 9:                                                  # coloured seats in the middle block
            for k in range(int(20 / 0.5)):
                x = -10.0 + k * 0.5
                if min(abs(x - tx) for tx in tunnels) < 1.0:
                    continue
                c = ((0.85, 0.15, 0.1), (0.95, 0.75, 0.1))[(t + (k // 8)) % 2]
                box((x, y + 0.65, z + 0.2), (0.42, 0.42, 0.06), mat("seat_%d" % ((t + (k // 8)) % 2), c, 0.4), 0.01)
                box((x, y + 0.85, z + 0.42), (0.42, 0.05, 0.38), mat("seat_%d" % ((t + (k // 8)) % 2), c, 0.4), 0.01)
    for x in tunnels:                                                    # stairs: two steps a tier
        for t in range(tiers * 2):
            y = yc + 0.2 + t * td / 2
            box((x, y + td / 4, -t * tz / 2 + 0.01), (1.4, td / 2, 0.02), mat("stair_yellow", (0.8, 0.65, 0.15), 0.7))
            box((x, y + td / 4, -t * tz / 2 - 0.1), (1.4, td / 2, 0.2), concrete)
        for sx in (-1, 1):
            for t in range(0, tiers * 2, 4):
                cyl((x + sx * 0.75, yc + 0.2 + t * td / 2, -t * tz / 2 + 0.5), 0.025, 1.0, steel, 8)
    yr = yc + 0.2 + tiers * td
    zr = -tiers * tz
    box((0, yr + 0.3, zr - 0.2), (W, 0.6, 0.4), concrete)
    box((0, yr + 0.5, zr + 0.6), (W, 0.05, 0.05), steel)
    box((0, yr + 0.5, zr + 1.1), (W, 0.06, 0.06), steel)
    for k in range(int(W / 2) + 1):
        cyl((-W / 2 + k * 2.0, yr + 0.5, zr + 0.55), 0.025, 1.1, steel, 8)
    for sx in (-1, 1):                                                   # the stand's side walls
        box((sx * (W / 2 + 0.1), yc + 6.0, -1.0), (0.2, 12.4, 8.0), concrete)
    # the ground below: the red track round the green pitch, its lines and goals, sunlit (a little emission)
    zg = zr - 1.6
    yg0, yg1 = yr + 0.6, yr + 60.0
    box((0, yr + 0.6 + 0.05, (zg + zr) / 2), (W, 0.1, zr - zg), concrete)
    box((0, (yg0 + yg1) / 2, zg - 0.05), (W + 20, yg1 - yg0, 0.1),
        mat("stadium_track", (0.6, 0.22, 0.15), 0.85, emit=(0.6, 0.22, 0.15), strength=0.35))
    px0, px1, py0, py1 = -17.0, 17.0, yg0 + 8.0, yg1 - 8.0
    box((0, (py0 + py1) / 2, zg + 0.005), (px1 - px0, py1 - py0, 0.01),
        mat("stadium_grass", (0.2, 0.5, 0.17), 0.9, emit=(0.18, 0.45, 0.15), strength=0.4))
    for k in range(6):                                                   # mowing stripes
        box((0, py0 + (k * 2 + 0.5) * (py1 - py0) / 12, zg + 0.008), (px1 - px0, (py1 - py0) / 12, 0.01),
            mat("stadium_grass_dark", (0.16, 0.42, 0.14), 0.9, emit=(0.15, 0.38, 0.12), strength=0.4))
    line = mat("line_white", (0.95, 0.95, 0.95), 0.5, emit=(0.9, 0.9, 0.9), strength=0.4)
    for y in (py0 + 1, py1 - 1, (py0 + py1) / 2):
        box((0, y, zg + 0.012), (px1 - px0 - 2, 0.12, 0.01), line)
    for x in (px0 + 1, px1 - 1):
        box((x, (py0 + py1) / 2, zg + 0.012), (0.12, py1 - py0 - 2, 0.01), line)
    for k in range(48):
        ang = k * math.tau / 48
        box((5.0 * math.cos(ang), (py0 + py1) / 2 + 5.0 * math.sin(ang), zg + 0.012), (0.12, 0.7, 0.01), line, rot=(0, 0, ang))
    for k in range(6):                                                   # the track's lanes
        for sx in (-1, 1):
            box((sx * (px1 + 1.0 + k * 1.2), (py0 + py1) / 2, zg + 0.012), (0.06, py1 - py0 + 10, 0.01), line)
    for y, sgn in ((py0 + 1, 1), (py1 - 1, -1)):                          # the goals
        for sx in (-1, 1):
            cyl((sx * 3.66, y, zg + 1.22), 0.06, 2.44, mat("goal_white", (1, 1, 1), 0.4), 10)
        cyl((0, y, zg + 2.44), 0.06, 7.32, mat("goal_white", (1, 1, 1), 0.4), 10, rot=(0, math.pi / 2, 0))
        box((0, y - sgn * 0.9, zg + 1.2), (7.3, 0.02, 2.4), mat("goal_net", (0.9, 0.9, 0.9), 0.8, alpha=0.3))
    # the far stand, the floodlight masts, the sky over it all
    for t in range(12):
        box((0, yg1 + 1.0 + t * 1.0, zg + 0.3 + t * 0.55), (W + 20, 1.0, 0.6 + t * 1.1),
            mat("far_stand", (0.7, 0.68, 0.64), 0.85, emit=(0.5, 0.48, 0.45), strength=0.4))
    box((0, yg1 + 8.0, zg + 13.0), (40.0, 14.0, 0.3), mat("stand_roof", (0.85, 0.85, 0.87), 0.4, 0.5,
                                                         emit=(0.6, 0.6, 0.62), strength=0.4), rot=(0.15, 0, 0))
    for sx in (-1, 1):
        for y in (yg0 + 2.0, yg1 + 2.0):
            x = sx * (W / 2 + 6.0)
            cyl((x, y, zg + 17.0), 0.45, 34.0, steel, 12, r2=0.25)
            box((x, y, zg + 34.5), (4.0, 0.6, 3.0), mat("floodlight", (0.95, 0.95, 0.9), 0.3, emit=(1, 1, 0.95), strength=1.5))
    ys0, ys1 = yc, yg1 + 16.0
    box((0, ys1, zg + 25.0), (W + 60, 0.2, 60.0), sky)
    for sx in (-1, 1):
        box((sx * (W / 2 + 15.0), (ys0 + ys1) / 2, zg + 25.0), (0.2, ys1 - ys0, 60.0), sky)
    box((0, (ys0 + ys1) / 2, zg + 50.0), (W + 60, ys1 - ys0, 0.2), sky)
    box((0, yc + 0.3, hc + 10.0), (W + 30, 0.2, 14.0), sky)               # (the sky behind the stand's top)
    for x in (-16.0, -6.0, 6.0, 16.0):
        for y in (yc + 2.0, yc + 7.0, yc + 11.5):
            lamp((x, y, -(y - yc) * tz + 3.0), "window")
    route("concourse", [(-20.0, -25.3), (20.0, -25.3)])                                       # along the concourse
    route("stand", [(16.0, -26.0), (12.0, -25.0), (12.0, -21.4), (18.0, -21.4)])              # out onto the stand
    t6 = 6                                                               # the seat: tier 7 of the middle block
    empty("Mark_seat", (-4.0, yc + 0.2 + t6 * td + 0.55, -t6 * tz + 0.25), math.pi)
    for t in range(3, 10):                                               # the crowd, in the coloured seats
        for k in range(int(20 / 0.5)):
            x = -10.0 + k * 0.5
            if min(abs(x - tx) for tx in tunnels) < 1.0 or (t == t6 and abs(x + 4.0) < 1.2) or (k + t) % 2:
                continue
            crowd("sit", x, yc + 0.2 + t * td + 0.62, 0.0, z=-t * tz - 0.22)
    shot("wide", (4.0, yc + 1.5, 1.6), (0.0, (py0 + py1) / 2, zg))
    shot("concourse", (12.0, yf + 1.0, 1.7), (-6.0, yc - 1.0, 1.2))


# ============================================================================ the Collectorate
def collectorate(T):
    """The District Collectorate's public hall (the 19th-century building): high ceiling on timber beams, arched
    windows, red-oxide floor; the petition counters behind a teak screen with their numbers, a token display, rows
    of steel chairs for the people waiting with their papers, the clerks' tables piled with files behind, notice
    boards, the wide stair up to the offices."""
    W, D, h = 20.0, 13.0, 6.0
    floor = mat("red_oxide", (1, 1, 1), 0.2, tex=T["red_oxide"], scale=2.0)
    wall = mat("wall_lime", (1, 1, 1), 0.9, tex=T["wall_lime"], normal=os.path.join(DTEX, "plaster_normal.jpg"), scale=3.0)
    ceil = mat("ceiling_white", (0.93, 0.93, 0.9), 0.95)
    teak = mat("door_teak", (1, 1, 1), 0.5, tex=os.path.join(GTEX, "dark_timber_deck_base.jpg"), scale=1.0)
    maroon = mat("collectorate_maroon", (0.45, 0.1, 0.08), 0.6)
    white = mat("letters_white", (0.97, 0.97, 0.97), 0.4)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    hall(W, D, h, floor, wall, ceil, door_w=2.4, door_h=3.6, door_x=0.0, frame=teak)
    for s3 in (-1, 1):                                                   # a maroon dado, arched windows both sides
        box((s3 * (W / 2 - 0.01), 0, 0.6), (0.02, D, 1.2), maroon)
        for k in range(3):
            y = -3.5 + k * 3.5
            sky_window(s3 * (W / 2 - 0.02), y, 2.9, 1.2, 2.6, "+x" if s3 < 0 else "-x", teak)
            cyl((s3 * (W / 2 - 0.06), y, 4.2), 0.66, 0.05, teak, 16, rot=(0, math.pi / 2, 0))     # the fanlight
            cyl((s3 * (W / 2 - 0.09), y, 4.2), 0.58, 0.02, mat("daylight", (1, 1, 1), 0.5, emit=(1.0, 0.98, 0.92), strength=2.2),
                16, rot=(0, math.pi / 2, 0))
    box((0, D / 2 - 0.01, 0.6), (W, 0.02, 1.2), maroon)
    for k in range(7):                                                   # timber beams
        box((-W / 2 + 1.5 + k * 2.83, 0, h - 0.2), (0.3, D, 0.4), teak)
    # the counters: a teak screen with windows, numbers and their work, a token display
    cy = 2.0
    box((0, cy, 0.55), (14.0, 0.6, 1.1), teak, 0.01)
    box((0, cy - 0.05, 1.12), (14.2, 0.7, 0.04), mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"]))
    for k, lab in enumerate(("1  PETITIONS", "2  CERTIFICATES", "3  PATTA / LAND", "4  e-SEVAI", "5  ENQUIRY")):
        x = -5.6 + k * 2.8
        box((x - 1.4, cy, 2.0), (0.12, 0.12, 1.8), teak)
        for j in range(8):
            box((x - 0.9 + j * 0.26, cy, 1.85), (0.02, 0.02, 1.4), mat("window_bars", (0.1, 0.12, 0.1), 0.4, 0.6))
        sign(lab, (x, cy - 0.08, 2.9), 2.4, 0.35, maroon, white, "-y", 0.17)
        R.monitor(x + 0.4, cy + 0.6, 0.76, math.pi)
        R.office_chair(x, cy + 1.1, math.pi)
        R.bundles(x - 0.6, cy + 0.65, 0.76, 2 + k % 3, mat("paper", (0.97, 0.97, 0.95), 0.8), mat("tie_red", (0.7, 0.08, 0.06), 0.8))
    box((7.0, cy, 2.0), (0.12, 0.12, 1.8), teak)
    box((0, cy, 2.95), (14.2, 0.15, 0.15), teak)
    for x in (-5.6, 0.0, 5.6):
        R.table(x, cy + 0.65, 1.6, 0.8, 0.75, teak, teak)
    staff(-5.6, cy + 1.1, math.pi)
    box((0, D / 2 - 0.12, 3.9), (3.0, 0.2, 0.7), mat("led_board", (0.02, 0.02, 0.02), 0.5), 0.02)    # tokens
    red = mat("led_red", (1, 0.15, 0.1), 0.4, emit=(1.0, 0.12, 0.06), strength=5)
    text("TOKEN  047   COUNTER  2", (0, D / 2 - 0.23, 3.9), 0.22, red, "-y", COND)
    R.box_files(-9.2, -6.0, D / 2 - 0.25, 0.05, 4, -1)
    R.box_files(6.0, 9.2, D / 2 - 0.25, 0.05, 4, -1)
    # the waiting: rows of steel chairs, notice boards, the stair, a water can, a clock
    seat = mat("chair_seat_green", (0.15, 0.4, 0.3), 0.5)
    for r in range(3):
        for k in range(10):
            x = -6.75 + k * 1.5 if k < 5 else -6.75 + k * 1.5 + 1.5
            R.steel_chair(x, -1.4 - r * 1.4, math.pi, seat)              # facing the counters
            crowd("sit", x, -1.4 - r * 1.4 + 0.02, 0.0)
    for k, lab in enumerate(("GRIEVANCE DAY - MONDAYS 10 AM", "FORMS FREE OF COST", "BEWARE OF TOUTS")):
        y = -4.5 + k * 3.0
        box((-W / 2 + 0.03, y, 1.9), (0.02, 1.6, 1.0), mat("notice", (1, 1, 1), 0.8, tex=T["notice"]))
        text(lab, (-W / 2 + 0.05, y, 2.5), 0.07, mat("ink_black", (0.05, 0.05, 0.05), 0.4), "+x")
    for k in range(12):                                                  # the stair, up the right wall
        box((W / 2 - 1.0, -4.5 + k * 0.3, 0.09 + k * 0.18), (1.8, 0.3, 0.18), mat("granite_grey", (1, 1, 1), 0.4, tex=T["granite_grey"]), 0.005)
    box((W / 2 - 1.95, -2.85, 1.6), (0.06, 3.6, 0.06), teak, rot=(0.54, 0, 0))
    R.wall_clock(-3.0, D / 2 - 0.02, 4.3)
    cyl((-W / 2 + 0.4, 4.6, 0.55), 0.14, 0.5, mat("water_can", (0.3, 0.5, 0.85), 0.2, alpha=0.7), 20)
    box((-W / 2 + 0.4, 4.6, 0.15), (0.35, 0.35, 0.3), steel)
    for k in range(5):                                                   # people at the counters
        for j in range(1 + k % 2):
            crowd("stand", -5.6 + k * 2.8, cy - 0.7 - j * 0.7, 0.0)
    crowd("talk", 6.0, -5.0, math.pi / 2)
    crowd("talk", 5.2, -5.0, -math.pi / 2)
    route("in", [(1.6, -5.6), (1.6, 0.6), (-7.5, 0.6)])
    route("across", [(-8.5, -5.6), (-8.5, 0.6), (7.5, 0.6), (7.5, -3.0)])
    for x in (-6.0, 0.0, 6.0):
        for y in (-4.0, 0.8, 4.4):
            tube(x, y, h - 0.45, light_z=4.0)
        fan_on_rod(x, -2.0, 4.0, h - 0.4)
    shot("wide", (6.5, -D / 2 + 1.0, 2.2), (-3.0, 3.0, 1.6))


# ============================================================================ Velliangiri College of Technology
def college(T):
    """The college's main block: the entrance lobby (granite floor, the reception, notice boards of fests and
    placements, the trophy case, a bench) and, through a wide doorway on the left, a classroom (rows of benches
    and desks, the green board, the teacher's table, ceiling fans, tall windows)."""
    W, D, h = 22.0, 12.0, 3.6
    floor = mat("granite_grey", (1, 1, 1), 0.2, tex=T["granite_grey"], scale=1.2)
    wall = mat("wall_offwhite", (1, 1, 1), 0.9, tex=T["wall_offwhite"], normal=os.path.join(DTEX, "plaster_normal.jpg"), scale=2.5)
    ceil = mat("ceiling_white", (0.93, 0.93, 0.9), 0.95)
    navy = mat("board_navy", (0.08, 0.12, 0.3), 0.4)
    gold = mat("letters_gold", (0.95, 0.78, 0.35), 0.3, 0.8)
    white = mat("letters_white", (0.97, 0.97, 0.97), 0.4)
    teak = mat("door_teak", (1, 1, 1), 0.5, tex=os.path.join(GTEX, "dark_timber_deck_base.jpg"), scale=1.0)
    wood = mat("timber", (1, 1, 1), 0.55, tex=os.path.join(GTEX, "warm_natural_timber_base.jpg"), scale=1.2)
    hall(W, D, h, floor, wall, ceil, door_w=2.4, door_h=2.6, door_x=4.0, frame=teak)
    # the partition between the lobby (right) and the classroom (left), a wide doorway in it
    px = -2.0
    box((px, -3.5, h / 2), (0.15, 5.0, h), wall)
    box((px, 4.2, h / 2), (0.15, 3.6, h), wall)
    box((px, 0.25, h - 0.4), (0.15, 2.5, 0.8), wall)
    # the lobby: the college's name, reception, notice boards, trophies, a bench, plants
    sign("VELLIANGIRI COLLEGE OF TECHNOLOGY", (5.0, D / 2 - 0.05, 2.9), 8.5, 0.55, navy, gold, "-y", 0.3)
    text("Estd. 1951  -  Affiliated to Anna University", (5.0, D / 2 - 0.08, 2.45), 0.12, mat("ink_black", (0.05, 0.05, 0.05), 0.4), "-y")
    box((7.5, 1.5, 0.55), (2.6, 0.7, 1.1), wood, 0.02)
    box((7.5, 1.45, 1.12), (2.7, 0.8, 0.04), mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"]))
    R.monitor(7.9, 1.75, 1.14, math.pi)
    sign("ENQUIRY", (7.5, 1.1, 1.8), 1.4, 0.3, navy, white, "-y", 0.16)
    staff(7.5, 2.3, math.pi)
    for k, (lab, c) in enumerate((("TECH FEST  -  KURINJI '26", (0.85, 0.35, 0.1)), ("PLACEMENTS  2026", (0.1, 0.45, 0.3)),
                                   ("NSS BLOOD DONATION CAMP", (0.7, 0.1, 0.12)))):
        y = -3.5 + k * 2.6
        box((W / 2 - 0.03, y, 1.7), (0.02, 1.8, 1.2), mat("notice", (1, 1, 1), 0.8, tex=T["notice"]))
        box((W / 2 - 0.05, y, 2.15), (0.02, 1.6, 0.25), mat("poster_%d" % k, c, 0.6))
        text(lab, (W / 2 - 0.07, y, 2.15), 0.08, white, "-x")
    glass = mat("showcase_glass", (0.7, 0.8, 0.82), 0.02, alpha=0.06)
    box((1.5, D / 2 - 0.3, 1.0), (2.2, 0.45, 2.0), teak, 0.01)            # the trophy case
    box((1.5, D / 2 - 0.53, 1.25), (2.0, 0.01, 1.4), glass)
    for r in range(3):
        for j in range(4):
            cyl((0.8 + j * 0.45, D / 2 - 0.3, 0.7 + r * 0.45), 0.05, 0.25 + 0.05 * (j % 2), mat("trophy", (0.85, 0.7, 0.3), 0.25, 1.0), 12)
    box((4.5, -3.0, 0.23), (2.2, 0.5, 0.46), wood, 0.03)
    R.plant(W / 2 - 0.6, -D / 2 + 0.7, 1.2)
    R.plant(-1.2, D / 2 - 0.7, 1.2)
    for x in (0.5, 4.0, 8.0):
        R.ceiling_fan(x, 0.0, h)
        tube(x, -3.0, h - 0.05)
        tube(x, 3.0, h - 0.05)
    # the classroom: benches and desks in rows, the green board, the teacher's table, windows down the side
    board = mat("chalkboard", (0.08, 0.25, 0.15), 0.8)
    box((-6.5, D / 2 - 0.05, 1.7), (5.0, 0.06, 1.3), board)
    chalk = mat("chalk", (0.92, 0.92, 0.88), 0.9)
    text("Unit 3 - Thermodynamics", (-7.5, D / 2 - 0.09, 2.15), 0.13, chalk, "-y")
    text("dU = dQ - dW", (-7.5, D / 2 - 0.09, 1.8), 0.13, chalk, "-y")
    box((-6.5, D / 2 - 0.9, 0.12), (6.0, 1.4, 0.24), wood)               # the dais
    R.table(-5.0, D / 2 - 1.0, 1.2, 0.6, 0.99, teak, teak)
    for r in range(4):
        for c in range(3):
            x = -9.0 + c * 2.5
            y = 2.6 - r * 1.6
            box((x, y + 0.35, 0.75), (2.0, 0.45, 0.04), wood, 0.005)    # the desk
            box((x, y + 0.45, 0.38), (2.0, 0.04, 0.75), wood)
            box((x, y - 0.15, 0.44), (2.0, 0.32, 0.04), wood, 0.005)    # the bench
            for e in (-0.95, 0.95):
                box((x + e, y + 0.1, 0.38), (0.05, 0.9, 0.76), mat("rack_grey", (0.5, 0.52, 0.5), 0.4, 0.5))
            for j in range(3):
                crowd("sit", x - 0.65 + 0.65 * j, y - 0.18, 0.0)
    for k in range(3):
        sky_window(-W / 2 + 0.02, -3.0 + k * 3.0, 1.9, 1.4, 1.6, "+x", teak)
    for x in (-8.0, -4.5):
        R.ceiling_fan(x, 0.5, h)
        tube(x, -2.5, h - 0.05)
        tube(x, 3.0, h - 0.05)
    for x3, y3 in ((3.0, -1.0), (6.0, -4.0)):                            # students in the lobby
        crowd("talk", x3 - 0.4, y3, -math.pi / 2)
        crowd("talk", x3 + 0.4, y3, math.pi / 2)
    for y3 in (-3.0, 0.0):
        crowd("stand", W / 2 - 1.0, y3 - 0.5, -math.pi / 2)              # reading the notices
    route("in", [(5.6, -5.4), (5.6, -1.5), (2.0, 0.2), (-0.8, 0.2)])
    route("lobby", [(9.0, -4.8), (9.0, 3.6), (2.5, 3.6)])
    shot("wide", (9.5, -D / 2 + 1.0, 1.9), (-5.0, 2.0, 1.2))
    shot("class", (-3.0, -5.0, 1.8), (-7.0, D / 2, 1.2))


# ============================================================================ Kovai Trade Fair Complex
FAIR_STALLS = ("SIRUVANI PUMPS", "NOYYAL MOTORS", "KONGU FOUNDRY", "PERUR TEXTILE MACHINES", "VELLIANGIRI CNC",
               "KOVAI WET GRINDERS", "MARUDHAM SOLAR", "THENNAI AGRO TOOLS", "KURINJI CASTINGS", "PALLADAM SPINNERS")


def trade_fair(T):
    """A hall of the trade fair complex during an industrial expo: a big steel shed lit from the roof, carpeted
    aisles between rows of stalls (shell-scheme panels, each firm's name on its fascia, its machines out front: a
    pump on a stand, a wet grinder, a lathe, a panel), the expo banner, people going round."""
    W, D, h = 36.0, 24.0, 10.0
    floor = mat("cement", (1, 1, 1), 0.7, tex=T["cement"], scale=3.0)
    wall = mat("acp_grey", (0.62, 0.64, 0.66), 0.5, 0.3)
    ceil = mat("shed_roof", (0.45, 0.47, 0.5), 0.5, 0.4)
    steel = mat("rail_steel", (0.3, 0.32, 0.35), 0.4, 0.8)
    hall(W, D, h, floor, wall, ceil, door_w=4.0, door_h=4.0, door_x=0.0, frame=steel)
    for k in range(7):                                                   # the roof trusses, skylights between
        x = -W / 2 + 3.0 + k * 5.0
        box((x, 0, h - 0.6), (0.3, D, 0.8), steel)
        if k < 6:
            box((x + 2.5, 0, h - 0.02), (2.0, D - 2.0, 0.04), glow_tex("skylight", T["skylight"], 3.0))
    carpet = mat("carpet_red", (1, 1, 1), 0.9, tex=T["carpet_red"], scale=1.0)
    box((0, 0, 0.005), (3.0, D - 1.0, 0.01), carpet)                     # the main aisle and the cross aisles
    for y in (-4.0, 4.5):
        box((0, y, 0.006), (W - 2.0, 2.4, 0.01), carpet)
    sign("COIMBATORE INDUSTRIAL EXPO 2026", (0, D / 2 - 0.15, 7.0), 16.0, 1.2, mat("expo_blue", (0.05, 0.2, 0.5), 0.4),
         mat("letters_lit", (1, 1, 1), 0.3, emit=(1, 1, 1), strength=3), "-y", 0.7)
    panel = mat("shell_white", (0.95, 0.95, 0.94), 0.4)
    fascia = mat("fascia_blue", (0.08, 0.15, 0.35), 0.4)
    lit = mat("letters_lit", (1, 1, 1), 0.3, emit=(1, 1, 1), strength=3)
    machines = ("pump", "grinder", "lathe", "panel")
    k = 0
    for row_y, facing in ((-8.0, 1), (0.25, -1), (0.25, 1), (8.8, -1)):  # four rows of stalls facing the aisles
        for c in range(6):
            sx = (-15.0 + c * 3.2) if c < 3 else (5.4 + (c - 3) * 3.2)
            back = row_y - facing * 1.4
            box((sx, back, 1.25), (3.0, 0.05, 2.5), panel)
            for e in (-1.5, 1.5):
                box((sx + e, row_y - facing * 0.7, 1.25), (0.05, 1.4, 2.5), panel)
            box((sx, row_y, 2.6), (3.0, 0.05, 0.35), fascia)
            name = FAIR_STALLS[k % len(FAIR_STALLS)]
            text(name, (sx, row_y + facing * 0.04, 2.6), min(0.2, 2.8 / (len(name) * 0.62)), lit, "-y" if facing < 0 else "+y")
            m = machines[k % 4]
            mx, my = sx, row_y - facing * 0.6
            accent = mat("machine_%d" % (k % 3), ((0.1, 0.35, 0.65), (0.75, 0.15, 0.1), (0.2, 0.5, 0.25))[k % 3], 0.4, 0.4)
            if m == "pump":
                box((mx, my, 0.3), (0.9, 0.6, 0.6), steel)
                cyl((mx, my, 0.85), 0.25, 0.5, accent, 20, rot=(0, math.pi / 2, 0))
            elif m == "grinder":
                cyl((mx, my, 0.45), 0.3, 0.9, mat("grinder_steel", (0.8, 0.8, 0.82), 0.25, 0.8), 24)
                cyl((mx, my, 0.95), 0.33, 0.1, accent, 24)
            elif m == "lathe":
                box((mx, my, 0.45), (1.8, 0.5, 0.9), accent, 0.02)
                box((mx - 0.6, my, 1.1), (0.5, 0.45, 0.4), steel, 0.02)
                cyl((mx + 0.1, my, 1.05), 0.05, 1.0, steel, 12, rot=(0, math.pi / 2, 0))
            else:
                box((mx, my, 1.0), (1.2, 0.3, 2.0), mat("panel_grey", (0.7, 0.72, 0.7), 0.4, 0.3), 0.02)
                for j in range(6):
                    cyl((mx - 0.4 + (j % 3) * 0.4, my + facing * 0.16, 1.4 - (j // 3) * 0.4), 0.05, 0.03, accent, 12, rot=(math.pi / 2, 0, 0))
            box((sx + 1.0, row_y - facing * 0.25, 0.45), (0.8, 0.5, 0.9), panel, 0.01)    # the stall's counter
            crowd("stand", sx + 1.0, row_y - facing * 0.95, 0.0 if facing > 0 else math.pi)   # the man at the stall
            crowd("stand", sx - 0.3, row_y + facing * 0.9, math.pi if facing > 0 else 0.0)   # a visitor
            k += 1
            lamp((sx, row_y - facing * 0.6, 2.4), "lamp")
    for x in (-12.0, -4.0, 4.0, 12.0):
        for y in (-6.0, 4.5):
            lamp((x, y, 4.5))
    route("main", [(1.0, -10.6), (1.0, 10.0)])
    route("cross", [(-16.0, -4.0), (16.0, -4.0)])
    route("cross2", [(16.0, 4.5), (-16.0, 4.5)])
    route("round", [(-1.0, -4.6), (-1.0, 3.9), (-16.0, 3.9), (-16.0, -4.6)], loop=True)
    shot("wide", (-6.0, -D / 2 + 1.0, 2.6), (6.0, 6.0, 1.4))


# ============================================================================ hospitals
def hospital_gov(T):
    """The Government Hospital's out-patient hall: the OP ticket counters with their queues, the token board, long
    rows of steel chairs, a wheelchair and a stretcher trolley by the wall, the nurses' table, the signs to the
    wards and the pharmacy, health posters, the green dado, fans."""
    W, D, h = 22.0, 14.0, 4.2
    floor = mat("terrazzo", (1, 1, 1), 0.25, tex=T["terrazzo"], scale=1.2)
    wall = mat("wall_offwhite", (1, 1, 1), 0.9, tex=T["wall_offwhite"], normal=os.path.join(DTEX, "plaster_normal.jpg"), scale=2.5)
    ceil = mat("ceiling_white", (0.93, 0.93, 0.9), 0.95)
    green = mat("dado_green", (0.15, 0.4, 0.25), 0.4)
    hgreen = mat("hosp_green", (0.05, 0.35, 0.25), 0.5)
    white = mat("letters_white", (0.97, 0.97, 0.97), 0.4)
    steel = mat("steel", (0.74, 0.75, 0.77), 0.32, 0.55)
    hall(W, D, h, floor, wall, ceil, door_w=3.0, door_h=3.0, door_x=0.0, frame=hgreen)
    for s3 in (-1, 1):
        box((s3 * (W / 2 - 0.01), 0, 0.6), (0.02, D, 1.2), green)
        for k in range(3):
            sky_window(s3 * (W / 2 - 0.02), -4.0 + k * 4.0, 1.9, 1.4, 1.5, "+x" if s3 < 0 else "-x", hgreen)
    box((0, D / 2 - 0.01, 0.6), (W, 0.02, 1.2), green)
    # the OP ticket counters on the back wall
    cy = D / 2 - 1.0
    box((-3.0, cy, 0.55), (10.0, 0.7, 1.1), hgreen, 0.01)
    box((-3.0, cy - 0.05, 1.12), (10.2, 0.8, 0.04), mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"]))
    for k, lab in enumerate(("OP TICKET - MEN", "OP TICKET - WOMEN", "SENIOR CITIZENS", "CMCHIS INSURANCE")):
        x = -6.75 + k * 2.5
        for j in range(8):
            box((x - 0.9 + j * 0.26, cy - 0.3, 1.85), (0.02, 0.02, 1.4), mat("window_bars", (0.1, 0.12, 0.1), 0.4, 0.6))
        sign(lab, (x, cy - 0.35, 2.85), 2.3, 0.35, hgreen, white, "-y", 0.15)
        R.monitor(x + 0.3, cy + 0.2, 1.14, math.pi)
        for j in range(3 + k % 2):                                       # the queue
            crowd("stand", x, cy - 1.0 - j * 0.65, 0.0)
    staff(-6.75, cy + 0.5, math.pi)
    box((5.0, D / 2 - 0.12, 2.9), (3.0, 0.2, 0.7), mat("led_board", (0.02, 0.02, 0.02), 0.5), 0.02)
    text("TOKEN  112  -  ROOM 4", (5.0, D / 2 - 0.23, 2.9), 0.2, mat("led_red", (1, 0.15, 0.1), 0.4, emit=(1.0, 0.12, 0.06), strength=5), "-y", COND)
    # waiting: rows of steel chairs, patients sitting
    seat = mat("chair_seat_blue", (0.2, 0.35, 0.6), 0.5)
    for r in range(4):
        for k in range(8):
            x = -8.0 + k * 1.0 + (2.0 if k >= 4 else 0.0)
            y = 1.2 - r * 1.3
            R.steel_chair(x, y, math.pi, seat)                          # facing the counters
            crowd("sit", x, y + 0.02, 0.0)
    # the nurses' table, a wheelchair, a stretcher trolley, the way to the wards and the pharmacy, posters
    R.table(W / 2 - 1.6, -2.0, 1.4, 0.7, 0.75, mat("desk_top", (0.75, 0.68, 0.55), 0.5), steel)
    R.steel_chair(W / 2 - 0.9, -2.0, math.pi / 2, seat)
    crowd("stand", W / 2 - 2.6, -2.0, -math.pi / 2)
    blue = mat("wheelchair_blue", (0.15, 0.25, 0.5), 0.5)
    for k in range(2):
        x = -W / 2 + 0.8 + k * 0.9
        for s3 in (-1, 1):
            cyl((x + s3 * 0.3, D / 2 - 0.6, 0.3), 0.3, 0.04, steel, 20, rot=(0, math.pi / 2, 0))
        box((x, D / 2 - 0.5, 0.5), (0.5, 0.45, 0.05), blue)
        box((x, D / 2 - 0.3, 0.8), (0.5, 0.05, 0.5), blue)
    box((W / 2 - 0.6, 4.0, 0.8), (0.65, 2.0, 0.08), mat("stretcher", (0.85, 0.85, 0.85), 0.4), 0.02)
    for dx in (-0.25, 0.25):
        for dy in (-0.9, 0.9):
            cyl((W / 2 - 0.6 + dx, 4.0 + dy, 0.4), 0.02, 0.8, steel, 8)
    sign("WARDS  >", (W / 2 - 0.05, 0.6, 2.9), 2.0, 0.4, hgreen, white, "-x", 0.22)
    sign("<  PHARMACY", (-W / 2 + 0.05, -1.0, 2.9), 2.4, 0.4, hgreen, white, "+x", 0.22)
    for k, (lab, c) in enumerate((("WASH YOUR HANDS", (0.2, 0.5, 0.8)), ("DENGUE: NO STANDING WATER", (0.85, 0.5, 0.1)))):
        box((-W / 2 + 0.03, 3.0 + k * 1.6, 1.8), (0.02, 1.0, 1.3), mat("hposter_%d" % k, c, 0.6))
        text(lab, (-W / 2 + 0.05, 3.0 + k * 1.6, 2.2), 0.06, white, "+x")
    route("in", [(1.6, -6.0), (1.6, 3.6), (-4.0, 3.9)])
    route("wards", [(8.0, -5.5), (8.0, 0.6), (W / 2 - 1.0, 0.6)])
    route("pharmacy", [(-9.8, 3.6), (-9.8, -5.0)])
    for x in (-6.0, 0.0, 6.0):
        for y in (-3.5, 2.5):
            tube(x, y, h - 0.05)
            R.ceiling_fan(x, y + 1.0, h)
    shot("wide", (7.0, -D / 2 + 1.0, 2.0), (-4.0, 4.0, 1.2))


def hospital_pvt(T):
    """Kongu Multispeciality Hospital's lobby (a private hospital of the story's own): polished marble, a curved
    reception under the hospital's name, the token screen, a lounge of upholstered seats, the pharmacy counter,
    a coffee corner, the billing desk, the lifts, plants and soft cove light."""
    W, D, h = 22.0, 14.0, 4.5
    floor = mat("marble_white", (1, 1, 1), 0.08, tex=T["marble_white"], scale=1.5)
    wall = mat("wall_offwhite", (1, 1, 1), 0.85, tex=T["wall_offwhite"], scale=2.5)
    ceil = mat("ceiling_white", (0.96, 0.96, 0.95), 0.95)
    teal = mat("kongu_teal", (0.0, 0.42, 0.45), 0.35)
    wood = mat("timber", (1, 1, 1), 0.45, tex=os.path.join(GTEX, "warm_natural_timber_base.jpg"), scale=1.2)
    lit = mat("letters_lit", (1, 1, 1), 0.3, emit=(1, 1, 1), strength=3)
    glass = mat("glass", (0.6, 0.72, 0.75), 0.05, alpha=0.15)
    hall(W, D, h, floor, wall, ceil, door_w=3.0, door_h=3.0, door_x=0.0, frame=mat("mullion", (0.3, 0.32, 0.35), 0.3, 0.8))
    sky = mat("daylight", (1, 1, 1), 0.5, emit=(1.0, 0.98, 0.92), strength=2.2)
    for s3 in (-1, 1):                                                   # glass front either side of the door
        box((s3 * 5.5, -D / 2 + 0.02, 1.9), (7.0, 0.02, 3.6), sky)
    sign("KONGU MULTISPECIALITY HOSPITAL", (0, D / 2 - 0.05, 3.6), 10.0, 0.6, teal, lit, "-y", 0.34)
    box((0, D / 2 - 0.02, 1.6), (10.0, 0.04, 2.6), mat("wall_teal", (1, 1, 1), 0.8, tex=T["wall_teal"]))
    for k in range(9):                                                   # the curved reception
        a = math.pi * (k + 0.5) / 9
        x, y = -3.0 * math.cos(a), D / 2 - 3.2 + 1.2 * math.sin(a)
        box((x, y, 0.55), (0.75, 0.6, 1.1), wood, 0.02, rot=(0, 0, -a + math.pi / 2))
        box((x, y, 1.12), (0.8, 0.7, 0.04), mat("granite_black", (1, 1, 1), 0.15, tex=T["granite_black"]), rot=(0, 0, -a + math.pi / 2))
    for x in (-1.5, 1.5):
        R.monitor(x, D / 2 - 2.0, 1.14, math.pi)
    staff(0.0, D / 2 - 1.7, math.pi)
    box((-6.5, D / 2 - 0.12, 2.6), (2.6, 0.15, 1.1), mat("fids", (0.02, 0.05, 0.15), 0.2, emit=(0.02, 0.05, 0.2), strength=1.0), 0.02)
    for r, line in enumerate(("CARDIOLOGY      T-18", "ORTHO           T-07", "PAEDIATRICS     T-23")):
        text(line, (-6.5, D / 2 - 0.2, 2.9 - r * 0.28), 0.14, lit, "-y", COND)
    fabric = mat("sofa_grey", (0.42, 0.43, 0.45), 0.9)                    # the lounge
    for r in range(3):
        for c in range(2):
            x, y = -6.5 + c * 4.0, -0.5 - r * 1.8
            box((x, y, 0.22), (3.0, 0.6, 0.44), fabric, 0.05)
            box((x, y - 0.32, 0.62), (3.0, 0.15, 0.5), fabric, 0.05)
            for j in range(4):
                crowd("sit", x - 1.1 + 0.73 * j, y + 0.05, 0.0)
    box((W / 2 - 1.0, 2.5, 0.55), (0.8, 4.0, 1.1), teal, 0.02)           # the pharmacy
    box((W / 2 - 0.1, 2.5, 1.8), (0.15, 4.0, 2.4), mat("shelf_white", (0.95, 0.95, 0.94), 0.4))
    for j in range(24):
        box((W / 2 - 0.25, 0.8 + (j % 8) * 0.45, 1.0 + (j // 8) * 0.55), (0.12, 0.35, 0.3),
            mat("medicine_%d" % (j % 4), ((0.9, 0.9, 0.95), (0.85, 0.3, 0.3), (0.3, 0.6, 0.85), (0.95, 0.8, 0.3))[j % 4], 0.5))
    sign("PHARMACY  24 x 7", (W / 2 - 0.1, 2.5, 3.4), 3.0, 0.4, teal, lit, "-x", 0.2)
    for j in range(2):
        crowd("stand", W / 2 - 1.9, 1.5 + j * 1.2, -math.pi / 2)
    box((W / 2 - 1.0, -4.5, 0.55), (0.8, 2.4, 1.1), wood, 0.02)          # the billing desk
    sign("BILLING  &  INSURANCE", (W / 2 - 0.05, -4.5, 2.5), 3.0, 0.4, teal, lit, "-x", 0.17)
    crowd("stand", W / 2 - 1.9, -4.5, -math.pi / 2)
    box((-W / 2 + 0.8, 4.5, 0.5), (1.0, 2.0, 1.0), wood, 0.02)          # the coffee corner
    cyl((-W / 2 + 0.8, 4.0, 1.15), 0.12, 0.3, mat("steel_brushed", (0.7, 0.71, 0.72), 0.3, 0.8), 20)
    text("CAFE", (-W / 2 + 0.05, 4.5, 2.4), 0.25, mat("ink_black", (0.05, 0.05, 0.05), 0.4), "+x")
    for x in (3.5, 5.5):                                                 # the lifts
        box((x, D / 2 - 0.04, 1.2), (1.2, 0.04, 2.3), mat("steel_brushed", (0.7, 0.71, 0.72), 0.3, 0.8))
        box((x, D / 2 - 0.06, 1.2), (0.01, 0.02, 2.3), mat("ink_black", (0.05, 0.05, 0.05), 0.4))
    crowd("stand", 4.5, D / 2 - 1.2, 0.0)
    for x in (-9.5, 9.5, -3.0, 3.0):
        R.plant(x, -D / 2 + 1.0, 1.3)
    for s3 in (-1, 1):                                                   # cove light
        box((0, s3 * (D / 2 - 0.9), h - 0.06), (W - 1.8, 0.04, 0.03), mat("cove_lit", (1, 0.95, 0.85), 0.3, emit=(1.0, 0.9, 0.75), strength=3))
    for x in (-7.0, -2.0, 3.0, 8.0):
        for y in (-3.5, 2.5):
            cyl((x, y, h - 0.01), 0.1, 0.02, mat("downlight", (1, 1, 1), 0.3, emit=(1, 0.95, 0.85), strength=6), 16)
            lamp((x, y, 3.6))
    route("in", [(1.6, -6.0), (1.6, 2.4), (-1.0, 2.6)])
    route("lifts", [(-1.6, -6.0), (-1.6, -3.0), (4.5, 3.0), (4.5, 5.6)])
    route("pharmacy", [(8.5, -6.0), (8.5, 4.6)])
    shot("wide", (8.0, -D / 2 + 1.0, 2.0), (-3.0, 3.5, 1.4))


# ============================================================================ Perur Pateeswarar temple
def temple_hall(T):
    """The great mandapam of Perur Pateeswarar temple: rows of carved granite pillars under a stone roof, the
    flagstaff (kodimaram) sheathed in brass with the bali peetam before it, the sanctum's doorway at the far end
    glowing with lamps, brass lamp stands, a kolam on the floor, a priest by the doorway, devotees standing and
    sitting along the pillars. (Nothing of the sanctum is shown: only its lit doorway.)"""
    W, D, h = 16.0, 26.0, 6.0
    stone = mat("temple_granite", (1, 1, 1), 0.75, tex=T["temple_stone"], scale=1.5)
    floor = mat("temple_floor", (1, 1, 1), 0.5, tex=T["temple_stone"], scale=1.0)
    ceil = mat("temple_ceiling", (0.4, 0.38, 0.35), 0.8)
    brass = mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0)
    flame = mat("flame", (1, 0.6, 0.2), 0.5, emit=(1, 0.55, 0.15), strength=10)
    hall(W, D, h, floor, stone, ceil, door_w=3.0, door_h=4.0, door_x=0.0, frame=stone)
    for s3 in (-1, 1):                                                   # two rows of pillars, carved bands
        for k in range(8):
            x, y = s3 * 3.2, -9.0 + k * 2.6
            box((x, y, h / 2), (0.7, 0.7, h), stone, 0.02)
            for z in (0.8, 2.6, 4.4):
                box((x, y, z), (0.82, 0.82, 0.3), mat("temple_band", (0.48, 0.45, 0.4), 0.7), 0.01)
            box((x, y, h - 0.3), (1.0, 1.0, 0.6), stone, 0.02)          # the bracket
            if k % 2 == 0:                                              # standing by the pillars, facing in
                crowd("stand", x - s3 * 0.75, y + 0.6, s3 * math.pi / 2)
        box((s3 * 3.2, 0, h - 0.1), (1.0, D, 0.2), stone)               # beams along the rows
    for k in range(10):
        box((0, -11.5 + k * 2.6, h - 0.15), (W, 0.25, 0.3), stone)
    # the flagstaff and the bali peetam, the kolam, the lamps
    fy = -6.0
    box((0, fy, 0.3), (1.4, 1.4, 0.6), stone, 0.02)
    cyl((0, fy, 0.6 + 2.6), 0.18, 5.2, brass, 16, r2=0.12)
    for k in range(6):
        cyl((0, fy, 1.0 + k * 0.8), 0.22, 0.08, brass, 16)
    cyl((0, fy + 1.5, 0.35), 0.5, 0.7, stone, 20, r2=0.35)              # the bali peetam
    R.dome((0, fy + 1.5, 0.7), 0.3, 0.25, stone)
    kolam = mat("kolam_white", (0.97, 0.97, 0.95), 0.9)
    for k in range(24):
        a = k * math.tau / 24
        cyl((0.9 * math.cos(a), fy - 2.5 + 0.9 * math.sin(a), 0.006), 0.035, 0.004, kolam, 8)
        cyl((0.5 * math.cos(a + 0.13), fy - 2.5 + 0.5 * math.sin(a + 0.13), 0.006), 0.03, 0.004, kolam, 8)
    for y in (-8.0, 0.0, 6.0):                                           # brass lamp stands down the middle
        for s3 in (-1, 1):
            x = s3 * 1.6
            cyl((x, y, 0.04), 0.2, 0.08, brass, 20)
            cyl((x, y, 0.7), 0.035, 1.3, brass, 12)
            cyl((x, y, 1.38), 0.16, 0.06, brass, 20)
            for j in range(5):
                a = j * math.tau / 5
                cyl((x + 0.12 * math.cos(a), y + 0.12 * math.sin(a), 1.45), 0.008, 0.03, flame, 6)
            lamp((x, y, 1.8), "lamp")
    # the sanctum's doorway at the far end: a carved stone frame, lamplight within (nothing more is shown)
    sy = D / 2 - 0.1
    box((0, sy, 1.6), (2.0, 0.1, 3.2), mat("sanctum_glow", (1, 0.7, 0.35), 0.5, emit=(1.0, 0.62, 0.25), strength=2.5))
    for s3 in (-1, 1):
        box((s3 * 1.2, sy - 0.1, 1.8), (0.4, 0.3, 3.6), stone, 0.02)
    box((0, sy - 0.1, 3.8), (2.8, 0.3, 0.5), stone, 0.02)
    for j in range(7):                                                   # the lamps hung before it
        cyl((-0.9 + j * 0.3, sy - 0.5, 2.6), 0.05, 0.03, brass, 12)
        cyl((-0.9 + j * 0.3, sy - 0.5, 2.62), 0.006, 0.02, flame, 6)
    lamp((0, sy - 1.5, 2.0), "lamp")
    for k in range(3):
        box((0, sy - 1.2 - k * 0.35, 0.08 + k * 0.08), (3.0 - k * 0.3, 0.35, 0.16 + k * 0.16), stone, 0.01)
    crowd("stand", 1.6, sy - 1.6, math.pi)                               # the priest by the doorway
    for k in range(6):                                                   # devotees before the sanctum
        crowd("stand", -1.6 + (k % 3) * 1.6, sy - 3.2 - (k // 3) * 1.0, 0.0)
    route("in", [(1.6, -11.6), (1.0, 8.0)])
    route("round", [(-5.2, -11.0), (-5.2, 10.0), (5.2, 10.0), (5.2, -11.0)], loop=True)   # round the hall, as one goes
    for y in (-10.0, -2.0, 6.0):
        for s3 in (-1, 1):
            lamp((s3 * 5.5, y, 3.0), "lamp")
    shot("wide", (2.0, -D / 2 + 1.5, 1.8), (0.0, D / 2, 1.8))


ROOMS = {"station": station, "bus": bus_stand, "airport": airport, "mall_avinashi": mall_avinashi,
         "mall_sathy": mall_sathy, "church": church, "house_mid": house_mid, "house_flat": house_flat,
         "house_old": house_old, "stadium": stadium, "collectorate": collectorate, "college": college,
         "trade_fair": trade_fair, "hospital_gov": hospital_gov, "hospital_pvt": hospital_pvt, "temple_hall": temple_hall}


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    prev = args[args.index("--preview") + 1] if "--preview" in args else None
    shots = args[args.index("--shots") + 1].split(",") if "--shots" in args else ()
    names = [a for a in args if a in ROOMS] or list(ROOMS)
    for name in names:
        R.reset()
        _LK.clear()
        T = textures()
        ROOMS[name](T)
        if prev:
            R.preview(name, os.path.abspath(prev), shots)
            for o in [o for o in bpy.data.objects if o.type == 'LIGHT' or o.name == "Cam"]:
                bpy.data.objects.remove(o, do_unlink=True)
        if "--no-export" not in args:
            R.export(name)


if __name__ == "__main__":
    main()
