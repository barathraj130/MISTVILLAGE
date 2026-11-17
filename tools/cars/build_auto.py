"""Our own auto-rickshaw (docs/VEHICLE_AUDIT_2026-11-17.md, Stage 5): a Coimbatore three-wheeler, unbadged.

    blender -b --factory-startup --python tools/cars/build_auto.py -- [--export out.glb] [--preview dir]

The car kit's materials and wheels (tools/cars/carkit.py); its own body: the narrow front cowl with the round
headlamp, the footboard, the passenger tub with the rear arches, the black canvas hood on its frame (open sides, a
rear window), the windscreen, the handlebar on its steering head (SteeringPivot: jeep.gd turns it about its own X,
the steering axis), the driver's bench in the middle, the passengers' bench for three, a fare meter on the dash.
Real size (2.64 x 1.30 x 1.72 m, 2.0 m wheelbase, 4.00-8 tyres). A commercial vehicle's yellow plates (made up).

Blender's frame as the kit's: +X the nose, +Y its left, Z up, the ground at z 0, the middle of the wheelbase x 0.
The game finds: Wheel_F / Wheel_RL / Wheel_RR, the Body (Paint), Glass_*, Headlight_*, Taillight_*, Brake_*,
Indicator_<L|R>_<F|R>, SteeringPivot, NeedleSpeed / NeedleFuel, DriverHip, GripL / GripR, FootL / FootR, Eye.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import carkit as K  # noqa: E402

YELLOW = (0.7, 0.42, 0.0)      # (linear: a deep taxi yellow)
AX_F, AX_R = 1.0, -1.0           # axles
R, TYRE_W, RIM_D = 0.215, 0.105, 0.2032
TRACK_R = 1.15
XB = 0.62                        # the cowl's back edge
NOSE, TAIL = 1.33, -1.32
SIDE = 0.645                     # the tub's half width
ROOF = 1.72
FLOOR = 0.34


def box(name, size, at, mat, rot=(0, 0, 0), bevel=0.0, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    ob = K.mesh_obj(name, bm, [mat])
    ob.scale = size
    ob.location = at
    ob.rotation_euler = rot
    if bevel > 0:
        b = ob.modifiers.new("Bv", 'BEVEL')
        b.width = bevel
        b.segments = 3
        b.limit_method = 'ANGLE'
    if parent:
        ob.parent = parent
    return ob


def cyl(name, r, length, at, mat, axis='Y', segs=24, r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=length)
    ob = K.mesh_obj(name, bm, [mat])
    ob.location = at
    ob.rotation_euler = {'X': (0, math.pi / 2, 0), 'Y': (math.pi / 2, 0, 0), 'Z': (0, 0, 0)}[axis]
    K.smooth(ob, 40)
    return ob


def tube(name, pts, r, mat, segs=10):
    """A round tube along a polyline (frames, rails, the handlebar)."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    sp = cu.splines.new('POLY')
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (*p, 1.0)
    cu.bevel_depth = r
    cu.bevel_resolution = max(1, segs // 4)
    cu.use_fill_caps = True
    ob = bpy.data.objects.new(name, cu)
    K.link(ob)
    ob.data.materials.append(mat)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target='MESH')
    K.smooth(ob, 50)
    return ob


def smooth_path(pts, n=8):
    """A polyline rounded through its corners (Catmull-Rom), n points a span."""
    out = []
    P = [Vector(p) for p in pts]
    for i in range(len(P) - 1):
        p0, p1, p2, p3 = P[max(i - 1, 0)], P[i], P[i + 1], P[min(i + 2, len(P) - 1)]
        for k in range(n):
            t = k / n
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-1])
    return [tuple(v) for v in out]


def grid_mesh(name, rows, mats, closed=False, keep=None):
    """Quads between rows of points (each row the same length); keep(face centre) drops faces where False."""
    bm = bmesh.new()
    V = [[bm.verts.new(p) for p in row] for row in rows]
    n = len(rows[0])
    for i in range(len(rows) - 1):
        for j in range(n - 1 + (1 if closed else 0)):
            a, b = V[i][j], V[i][(j + 1) % n]
            c, d = V[i + 1][(j + 1) % n], V[i + 1][j]
            ctr = (a.co + b.co + c.co + d.co) / 4
            if keep is None or keep(ctr):
                bm.faces.new((a, b, c, d))
    bm.normal_update()
    return K.mesh_obj(name, bm, mats)


def skin(ob, th, offset=-1.0, inner=None):
    so = ob.modifiers.new("Skin", 'SOLIDIFY')
    so.thickness = th
    so.offset = offset
    if inner is not None:
        ob.data.materials.append(inner)
        so.material_offset = len(ob.data.materials) - 1
    K.apply_mods(ob)
    return ob


# ----------------------------------------------------------------------------------------------------- the body
def xf(z):
    return K.cr([(0.4, 1.24), (0.55, 1.31), (0.7, NOSE), (0.85, 1.3), (0.95, 1.22), (1.02, 1.12)], z)


def wf(z):
    return K.cr([(0.4, 0.4), (0.6, 0.43), (0.8, 0.475), (1.02, 0.52)], z)


def cowl_pt(t, z):
    """The cowl's surface: at height z, t (-1 right .. 1 left) round its front: a rounded U in plan."""
    a = t * math.pi / 2
    y = wf(z) * math.sin(a)
    c = abs(math.cos(a)) ** 0.5
    return (XB + (xf(z) - XB) * c, y, z)


def cowl_x(y, z):
    w = wf(z)
    s = max(-1.0, min(1.0, y / w))
    return cowl_pt(math.asin(s) * 2 / math.pi, z)[0]


def build_cowl(M):
    zs = [0.4 + (1.02 - 0.4) * k / 30 for k in range(31)]
    rows = [[cowl_pt(-1 + 2 * j / 40, z) for j in range(41)] for z in zs]
    # above the front wheel: the cowl's lower edge lifted (the mudguard shows below it)
    ob = grid_mesh("Body", rows, [M["Paint"]], keep=lambda c: not (c.x > 0.72 and abs(c.y) < 0.24 and c.z < 0.5))
    bm = bmesh.new()
    top = [cowl_pt(-1 + 2 * j / 40, 1.02) for j in range(41)]
    vs = [bm.verts.new(p) for p in top]
    bm.faces.new(vs)                                          # (the dash top: the cowl closed over)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    capm = K.mesh_obj("CowlTop", bm, [M["Paint"]])
    K.smooth(ob, 40)
    skin(ob, 0.012, inner=M["Paint"])
    skin(capm, 0.012, offset=1.0)
    return [ob, capm]


def tub_top(x):
    """The tub's side height along it: a low sill at the doorways, up at the rear quarter."""
    if x > 0.18:
        return 0.56
    if x > -0.42:
        return 0.5
    if x > -0.62:
        t = (x + 0.42) / -0.2
        return 0.5 + 0.47 * (0.5 - 0.5 * math.cos(math.pi * t))
    return 0.97


def tub_w(x):
    """Half width: the rear corners rounded in plan."""
    if x > 0.2:                                              # (in to meet the cowl at the footwell)
        t = min(1.0, (x - 0.2) / (XB + 0.02 - 0.2))
        return SIDE - (SIDE - 0.5) * (3 * t * t - 2 * t * t * t)
    if x > -1.1:
        return SIDE
    t = (x + 1.1) / (TAIL + 1.1)
    return SIDE - 0.09 * t * t


def build_tub(M):
    """The passenger tub, one skin from the cowl's back to the tail: the sides (their tops along tub_top), the floor
    round the lower corners, the rear panel; the rear arches cut out (their edges under a rubber lip)."""
    xs = [XB + 0.02 - (XB + 0.02 - TAIL) * k / 90 for k in range(91)]
    rows = []
    for x in xs:
        w = tub_w(x)
        ztop = tub_top(x)
        prof = []
        # left side top → down → the rounded bottom corner → the floor → right
        for k in range(12):
            z = ztop - (ztop - (FLOOR + 0.06)) * k / 11
            lean = 0.015 * (z - FLOOR) / 0.6
            prof.append((x, w - lean, z))
        for k in range(1, 6):
            a = math.pi / 2 * k / 6
            prof.append((x, w - 0.06 + 0.06 * math.cos(a), FLOOR + 0.06 - 0.06 * math.sin(a)))
        for k in range(1, 12):
            prof.append((x, (w - 0.06) * (1 - 2 * k / 12), FLOOR))
        for p in reversed(prof[:-11]):
            prof.append((p[0], -p[1], p[2]))
        rows.append(prof)

    def keep(c):
        return not (abs(c.y) > 0.4 and math.hypot(c.x - AX_R, c.z - R) < R + 0.07)
    ob = grid_mesh("Tub", rows, [M["Paint"]], keep=keep)
    # the rear panel: the last profile closed
    bm = bmesh.new()
    last = rows[-1]
    vs = [bm.verts.new(p) for p in last]
    bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    back = K.mesh_obj("TubBack", bm, [M["Paint"]])
    K.smooth(ob, 40)
    skin(ob, 0.012, inner=M["Inner"])
    skin(back, 0.012, offset=1.0, inner=M["Inner"])
    parts = [ob, back]
    # a black band along the tub's foot (rubbing strip) and the arch lips
    for s in (1, -1):
        parts.append(box("RubStrip", (XB - TAIL - 0.3, 0.012, 0.04), ((XB + TAIL) / 2 + 0.12, s * (SIDE + 0.004), FLOOR + 0.1), M["BlackTrim"], bevel=0.004))
        pts = [(AX_R + math.cos(a) * (R + 0.075), s * (SIDE + 0.006), R + math.sin(a) * (R + 0.075))
               for a in [math.radians(-5 + 190 * k / 30) for k in range(31)]]
        parts.append(tube("ArchLip", pts, 0.016, M["Rubber"]))
        # the wheel's housing inside (a half drum)
        hz = K.lathe("ArchHousing", [(R + 0.06, -0.06), (R + 0.06, 0.06)], 32, 'Y', [M["BlackTrim"]])
        hz.location = (AX_R, s * (TRACK_R / 2), R)
        for v in hz.data.vertices:
            if v.co.z < -0.06:
                v.co.z = -0.06
        parts.append(hz)
    return parts


# ----------------------------------------------------------------------------------------------------- the hood
def hood_bottom(x):
    """Where the canvas ends down the sides: open over the doorways, down to the tub at the rear quarter."""
    if x > 0.75:
        return 1.42
    if x > -0.3:
        return 1.5
    if x > -0.62:
        t = (x + 0.3) / -0.32
        return 1.5 - 0.55 * (0.5 - 0.5 * math.cos(math.pi * t))
    return 0.95


def hood_section(x, n_side=10, n_top=14):
    w = SIDE + 0.012
    top = ROOF - 0.05 * max(0.0, (x + 1.05) / -0.27) ** 2 if x < -1.05 else ROOF
    top += 0.015 * math.cos(math.pi * 0.5 * max(-1.0, min(1.0, x / 1.2)))
    zb = hood_bottom(x)
    rc = 0.14
    pts = []
    for k in range(n_side):                                    # the left side, up
        z = zb + (top - rc - zb) * k / n_side
        pts.append((x, w - 0.03 * (z - 0.95) / 0.8, z))
    wt = w - 0.03 * (top - rc - 0.95) / 0.8
    for k in range(7):                                         # the rounded corner
        a = math.pi / 2 * k / 6
        pts.append((x, wt - rc + rc * math.cos(a), top - rc + rc * math.sin(a)))
    for k in range(1, n_top):
        y = (wt - rc) * (1 - 2 * k / n_top)
        pts.append((x, y, top + 0.012 * (1 - (y / wt) ** 2)))
    for p in reversed(pts):
        pts.append((p[0], -p[1], p[2]))
    return pts


def build_hood(M):
    xs = [0.98 - (0.98 - (TAIL - 0.015)) * k / 80 for k in range(81)]
    rows = [hood_section(x) for x in xs]
    ob = grid_mesh("Hood", rows, [M["Canvas"]])
    K.smooth(ob, 35)
    # the canvas sags a little between the hoops
    for v in ob.data.vertices:
        if v.co.z > 1.6 and abs(v.co.y) < 0.45:
            v.co.z -= 0.006 * (math.sin((v.co.x - 0.98) / 0.77 * math.pi) ** 2)
    skin(ob, 0.006, offset=1.0, inner=M["CanvasIn"])
    parts = [ob]
    # the back: the canvas closed, a clear window in it (the cells inside the hood's outline, outside the window)
    last = hood_section(TAIL - 0.015)
    outline = [(p[1], p[2]) for p in last]

    def inside(y, z):
        c = False
        n = len(outline)
        for i in range(n):
            (y1, z1), (y2, z2) = outline[i], outline[(i + 1) % n]
            if (z1 > z) != (z2 > z) and y < (y2 - y1) * (z - z1) / (z2 - z1) + y1:
                c = not c
        return c
    ny, nz = 70, 42
    rows2 = [[(TAIL - 0.015, -0.68 + 1.36 * j / ny, 0.95 + (ROOF + 0.05 - 0.95) * i / nz) for j in range(ny + 1)] for i in range(nz + 1)]
    win = lambda y, z: abs(y) < 0.36 and 1.24 < z < 1.5
    back = grid_mesh("HoodBack", rows2, [M["Canvas"]], keep=lambda c: inside(c.y, c.z) and not win(c.y, c.z))
    skin(back, 0.006, offset=1.0, inner=M["CanvasIn"])
    parts.append(back)
    parts.append(box("Glass_Rear", (0.004, 0.72, 0.26), (TAIL - 0.012, 0, 1.37), M["Glass"]))
    for z in (1.24, 1.5):
        parts.append(tube("RearWinPiping", [(TAIL - 0.02, -0.37, z), (TAIL - 0.02, 0.37, z)], 0.008, M["Rubber"]))
    for y in (-0.365, 0.365):
        parts.append(tube("RearWinPiping", [(TAIL - 0.02, y, 1.235), (TAIL - 0.02, y, 1.505)], 0.008, M["Rubber"]))
    # piping round the hood's edges, and the hoops inside it
    for xx in (0.98, TAIL - 0.015):
        sec = hood_section(xx)
        parts.append(tube("HoodPiping", [(xx - 0.004 if xx > 0 else xx + 0.004, p[1], p[2]) for p in sec], 0.009, M["Rubber"]))
    for s in (1, -1):
        edge = []
        for k in range(61):
            x = 0.98 - (0.98 - (TAIL - 0.015)) * k / 60
            p = hood_section(x)[0]
            edge.append((x, s * p[1], p[2]))
        parts.append(tube("HoodPiping", edge, 0.009, M["Rubber"]))
        # the fringe at the open side's edge (short strips)
        for k in range(40):
            x = 0.72 - k * 0.026
            if x < -0.3:
                break
            parts.append(box("Fringe", (0.016, 0.003, 0.03 if k % 2 else 0.022), (x, s * (SIDE + 0.006), hood_bottom(x) - 0.018), M["CanvasIn"]))
    for xx in (0.55, -0.25, -0.95):
        sec = hood_section(xx)
        inner = [(xx, p[1] * 0.97, p[2] - 0.025) for p in sec if p[2] > 1.45]
        parts.append(tube("Hoop", inner, 0.013, M["Steel"]))
    # the frame: pillars from the cowl to the hood beside the windscreen
    for s in (1, -1):
        parts.append(tube("Pillar", [(1.02, s * 0.5, 1.0), (0.99, s * 0.53, 1.3), (0.96, s * 0.58, 1.62)], 0.02, M["BlackGloss"]))
        parts.append(tube("Rail", [(0.62, s * 0.55, 1.5), (-0.3, s * 0.6, 1.52)], 0.014, M["Steel"]))   # the grab rail inside
    return parts


def windscreen(M):
    out = []
    rows = []
    for i in range(13):
        z = 1.03 + 0.55 * i / 12
        x = 1.03 - 0.07 * i / 12
        w = 0.47 + 0.05 * i / 12
        rows.append([(x - 0.04 * (y / w) ** 2, y, z) for y in [-w + 2 * w * j / 20 for j in range(21)]])
    g = grid_mesh("Glass_Front", rows, [M["Glass"]])
    K.smooth(g, 50)
    skin(g, 0.005, offset=0.0)
    out.append(g)
    fr = [rows[0][0], *rows[0], rows[-1][-1]]
    edge = [*rows[0], *[r[-1] for r in rows], *reversed(rows[-1]), *[r[0] for r in reversed(rows)]]
    out.append(tube("ScreenSeal", edge, 0.012, M["Rubber"]))
    # one wiper, parked along the screen's foot
    wp = tube("Wiper", [(1.05, 0.25, 1.06), (1.03, -0.2, 1.1)], 0.006, M["BlackTrim"])
    out.append(wp)
    out.append(box("WiperBlade", (0.012, 0.42, 0.012), (1.04, 0.03, 1.075), M["Rubber"], rot=(math.radians(5), 0, 0)))
    out.append(cyl("WiperBoss", 0.018, 0.04, (1.06, 0.25, 1.05), M["BlackTrim"], axis='X'))
    return out


# ----------------------------------------------------------------------------------------------------- lamps etc.
def front_details(M):
    out = []
    # the headlamp: a chrome-rimmed round lamp in the cowl's nose, its reflector and bulb lit by the game
    z = 0.8
    x = cowl_x(0.0, z)
    rim = K.lathe("HeadRim", [(0.075, 0.0), (0.09, -0.005), (0.095, -0.03), (0.088, -0.05)], 48, 'X', [M["Chrome"]])
    rim.location = (x + 0.04, 0, z)
    out.append(rim)
    refl = K.lathe("HeadReflector", [(0.0, -0.06), (0.03, -0.055), (0.06, -0.035), (0.078, -0.005)], 48, 'X', [M["Reflector"]])
    refl.location = (x + 0.04, 0, z)
    out.append(refl)
    bulb = K.lathe("Headlight_C", [(0.0, -0.03), (0.018, -0.032), (0.022, -0.045), (0.0, -0.05)], 24, 'X', [M["Headlight"]])
    bulb.location = (x + 0.04, 0, z)
    out.append(bulb)
    lens = K.lathe("HeadLens", [(0.0, 0.012), (0.04, 0.009), (0.076, -0.002)], 48, 'X', [M["Lens"]])
    lens.location = (x + 0.04, 0, z)
    out.append(lens)
    # the visor: half a ring over it
    vis = K.lathe("HeadHood", [(0.098, 0.0), (0.102, 0.06)], 32, 'X', [M["Paint"]])
    for v in vis.data.vertices:
        if v.co.z < 0.0:
            v.co.z = 0.0
    vis.location = (x + 0.02, 0, z)
    out.append(vis)
    # the indicators: amber lenses either side, high on the cowl's front
    for s, sl in ((1, "L"), (-1, "R")):
        y = s * 0.3
        zz = 0.9
        xx = cowl_x(y, zz)
        a = math.atan2(1.0, 1.4) * s
        ind = box("Indicator_%s_F" % sl, (0.03, 0.09, 0.05), (xx - 0.004, y, zz), M["Indicator"], rot=(0, 0, s * 0.6), bevel=0.012)
        out.append(ind)
        out.append(box("IndBezel", (0.025, 0.1, 0.06), (xx - 0.012, y, zz), M["BlackGloss"], rot=(0, 0, s * 0.6), bevel=0.012))
    # the horn grille below the lamp, the plate below that
    hg = box("HornGrille", (0.03, 0.2, 0.06), (cowl_x(0, 0.64) - 0.01, 0, 0.64), M["BlackTrim"], bevel=0.02)
    out.append(hg)
    for k in range(4):
        out.append(box("HornSlat", (0.034, 0.18, 0.004), (cowl_x(0, 0.64) - 0.006, 0, 0.62 + k * 0.013), M["Chrome"]))
    pl, tx = K.plate(M, "PlateFront", "TN 37 AK 5162", Vector((cowl_x(0, 0.53) + 0.0, 0, 0.53)), Vector((1, 0, 0)), w=0.34, h=0.11)
    pl.data.materials[0] = M["PlateYellow"]
    out += [pl, tx]
    # the front mudguard over the wheel, the fork's legs, the wheel's hub
    mg = K.lathe("FrontGuard", [(R + 0.035, -0.07), (R + 0.045, -0.06), (R + 0.045, 0.06), (R + 0.035, 0.07)], 40, 'Y', [M["Paint"]])
    for v in mg.data.vertices:
        if v.co.z < -0.02 and v.co.x < 0.05:
            v.co.z = -0.02
        if v.co.z < -0.1:
            v.co.z = -0.1
    mg.location = (AX_F, 0, R)
    out.append(mg)
    for s in (1, -1):
        out.append(tube("Fork", [(AX_F, s * 0.075, R), (AX_F - 0.05, s * 0.075, 0.5), (AX_F - 0.09, s * 0.03, 0.75)], 0.017, M["BlackGloss"]))
        out.append(cyl("Shock", 0.022, 0.18, (AX_F - 0.03, s * 0.085, 0.38), M["Chrome"], axis='Z'))
    # the mirrors: round, on stalks from the cowl's top
    for s in (1, -1):
        out.append(tube("MirrorStalk", [(1.0, s * 0.47, 1.02), (1.0, s * 0.62, 1.12), (0.98, s * 0.7, 1.24)], 0.007, M["Chrome"]))
        mh = cyl("MirrorHead", 0.065, 0.025, (0.98, s * 0.7, 1.29), M["BlackGloss"], axis='X')
        out.append(mh)
        mgl = cyl("MirrorGlass", 0.058, 0.004, (0.966, s * 0.7, 1.29), M["Chrome"], axis='X')
        out.append(mgl)
    return out


def rear_details(M):
    out = []
    for s, sl in ((1, "L"), (-1, "R")):
        y = s * 0.47
        out.append(box("TailHousing", (0.03, 0.12, 0.24), (TAIL - 0.01, y, 0.66), M["BlackGloss"], bevel=0.01))
        out.append(box("Taillight_" + sl, (0.022, 0.1, 0.08), (TAIL - 0.022, y, 0.73), M["Taillight"], bevel=0.006))
        out.append(box("Brake_" + sl, (0.022, 0.1, 0.06), (TAIL - 0.022, y, 0.655), M["Brake"], bevel=0.006))
        out.append(box("Indicator_%s_R" % sl, (0.022, 0.1, 0.05), (TAIL - 0.022, y, 0.59), M["Indicator"], bevel=0.006))
        out.append(box("Reflector", (0.01, 0.06, 0.03), (TAIL - 0.016, s * 0.3, 0.44), M["Taillight"]))
    pl, tx = K.plate(M, "PlateRear", "TN 37 AK 5162", Vector((TAIL - 0.02, 0, 0.62)), Vector((-1, 0, 0)), w=0.3, h=0.15)
    pl.data.materials[0] = M["PlateYellow"]
    out += [pl, tx]
    out.append(box("PlateLamp", (0.03, 0.06, 0.02), (TAIL - 0.03, 0, 0.715), M["Chrome"], bevel=0.005))
    # the rear guard: a tube across the back, on two stays
    out.append(tube("RearGuard", [(TAIL + 0.02, 0.6, 0.38), (TAIL - 0.07, 0.55, 0.36), (TAIL - 0.08, -0.55, 0.36), (TAIL + 0.02, -0.6, 0.38)], 0.017, M["BlackGloss"]))
    for y in (0.3, -0.3):
        out.append(tube("GuardStay", [(TAIL - 0.08, y, 0.36), (TAIL + 0.08, y, 0.34)], 0.012, M["BlackGloss"]))
    # the engine under the passengers' bench, the silencer on the right, the chassis
    out.append(box("Engine", (0.38, 0.42, 0.3), (-0.82, 0.05, 0.28), M["AlloyDark"], bevel=0.03))
    out.append(cyl("Silencer", 0.06, 0.42, (-1.0, -0.36, 0.2), M["Steel"], axis='X'))
    out.append(tube("Exhaust", [(-0.7, -0.05, 0.2), (-0.8, -0.3, 0.2), (-0.82, -0.36, 0.2)], 0.018, M["Steel"]))
    out.append(tube("Tailpipe", [(-1.2, -0.36, 0.2), (-1.36, -0.4, 0.19)], 0.016, M["Steel"]))
    out.append(box("Chassis", (2.2, 0.12, 0.08), (-0.1, 0, 0.27), M["BlackTrim"]))
    out.append(box("Axle", (0.08, TRACK_R - 0.1, 0.06), (AX_R, 0, R), M["BlackTrim"]))
    for s in (1, -1):
        out.append(box("SwingArm", (0.5, 0.05, 0.05), (AX_R + 0.25, s * 0.42, R + 0.02), M["BlackTrim"], rot=(0, math.radians(-6), 0)))
        out.append(cyl("RearShock", 0.024, 0.24, (AX_R + 0.08, s * 0.45, 0.36), M["Chrome"], axis='Z'))
    # the side: a small fuel-and-oil lid on the right, the step
    out.append(box("FuelLid", (0.12, 0.004, 0.1), (-0.8, -SIDE - 0.004, 0.78), M["Paint"], bevel=0.01))
    return out


def wheels(M):
    """Three steel 8-inch wheels on 4.00-8 tyres (the kit's tyre; a pressed-steel rim, four nuts; drums)."""
    out = []
    for nm, at, left in (("Wheel_F", (AX_F, 0.0, R), True), ("Wheel_RL", (AX_R, TRACK_R / 2, R), True), ("Wheel_RR", (AX_R, -TRACK_R / 2, R), False)):
        piv, fixed = K.wheel(M, nm, at, R, TYRE_W, RIM_D, spokes=1, left=left, steer=(nm == "Wheel_F"))
        for f in fixed:
            K.remove(f)
        for c in list(piv.children):
            if c.name.endswith("_Spokes") or c.name.endswith("_Hub") or c.name.endswith("_Cap"):
                K.remove(c)
            elif c.name.endswith("_Barrel"):
                c.data.materials[0] = M["RimSteel"]
        pn = nm.replace("Wheel_", "W")
        side = 1.0 if left else -1.0
        face = K.lathe(pn + "_Face", [(0.0, 0.035), (0.045, 0.035), (0.06, 0.02), (0.085, 0.012), (RIM_D / 2 - 0.004, 0.0)], 48, 'Y', [M["RimSteel"]])
        face.parent = piv
        if not left:
            face.matrix_basis = Matrix.Scale(-1, 4, Vector((0, 1, 0)))
        for k in range(4):
            a = math.pi / 2 * k + math.pi / 4
            nut = cyl(pn + "_Nut", 0.008, 0.016, (math.cos(a) * 0.035, side * 0.042, math.sin(a) * 0.035), M["Chrome"], axis='Y', segs=6)
            nut.parent = piv
        hubc = cyl(pn + "_HubCap", 0.022, 0.012, (0, side * 0.045, 0), M["Chrome"], axis='Y')
        hubc.parent = piv
        drum = cyl(pn + "_Drum", 0.07, 0.05, Vector(at) + Vector((0, -side * 0.035, 0)), M["Disc"], axis='Y')
        out += [piv, drum]
    return out


# ----------------------------------------------------------------------------------------------------- the cabin
def interior(M):
    out = []
    # the floorboard: a ribbed rubber mat from the footwell back
    out.append(box("FloorMat", (XB - 0.0 + 0.3, 0.42, 0.01), ((XB + 0.3) / 2 + 0.05, 0, FLOOR + 0.008), M["Rubber"]))
    for k in range(14):
        out.append(box("MatRib", (0.008, 0.4, 0.006), (0.4 + k * 0.035, 0, FLOOR + 0.016), M["Rubber"]))
    out.append(box("FloorRear", (0.95, 1.18, 0.01), (-0.15, 0, FLOOR + 0.006), M["Rubber"]))
    # the leg shield: the cowl's inside closed behind the fork (a curved panel from the floor to the dash)
    rows = []
    for i in range(9):
        z = FLOOR + (0.92 - FLOOR) * i / 8
        rows.append([(0.76 + 0.06 * (y / 0.44) ** 2 + 0.05 * (z - FLOOR), y, z) for y in [-0.44 + 0.88 * j / 16 for j in range(17)]])
    ls = grid_mesh("LegShield", rows, [M["Inner"]])
    K.smooth(ls, 40)
    skin(ls, 0.01, offset=0.0)
    out.append(ls)
    # the dash: a panel across under the screen, the speedometer in the middle (its needle the game turns), the
    # fuel gauge, the key, switches, a cubby each side; the fare meter on its bracket at the left
    dash = box("Dash", (0.05, 0.92, 0.22), (0.92, 0, 0.9), M["Dash"], rot=(0, math.radians(-18), 0), bevel=0.02)
    out.append(dash)
    for s in (1, -1):
        out.append(box("Cubby", (0.06, 0.24, 0.1), (0.9, s * 0.3, 0.86), M["BlackTrim"], rot=(0, math.radians(-18), 0), bevel=0.01))
    out.append(cyl("Key", 0.012, 0.03, (0.9, -0.16, 0.93), M["Chrome"], axis='X'))
    for k in range(3):
        out.append(box("Switch", (0.02, 0.025, 0.015), (0.9, 0.12 + k * 0.035, 0.94), M["BlackGloss"], bevel=0.003))
    # the fare meter (a box on a bracket, its red digits lit)
    out.append(tube("MeterArm", [(0.92, 0.4, 1.02), (0.88, 0.42, 1.12)], 0.008, M["Steel"]))
    out.append(box("FareMeter", (0.07, 0.17, 0.11), (0.86, 0.43, 1.17), M["BlackGloss"], rot=(0, math.radians(-10), math.radians(-12)), bevel=0.01))
    out.append(box("MeterDigits", (0.004, 0.12, 0.03), (0.823, 0.437, 1.19), M["MeterLed"], rot=(0, math.radians(-10), math.radians(-12))))
    # the steering head: SteeringPivot on its axis (raked back 20°), the handlebar and its controls on it
    head = Vector((0.8, 0.0, 1.12))
    gz = 1.15
    piv = bpy.data.objects.new("SteeringPivot", None)
    K.link(piv)
    piv.location = head
    piv.rotation_euler = (0, math.radians(70), 0)             # (its X down the steering axis, forward: jeep.gd turns it)
    out.append(piv)
    bpy.context.view_layer.update()
    inv = piv.matrix_world.inverted()

    def on_bars(ob):
        ob.parent = piv
        ob.matrix_parent_inverse = inv
        out.append(ob)
        return ob
    cl = K.lathe("ClusterPod", [(0.0, 0.0), (0.085, 0.0), (0.095, -0.03), (0.07, -0.06)], 32, 'X', [M["BlackGloss"]])
    cl.location = (0.79, 0, gz + 0.08)
    cl.rotation_euler = (0, math.radians(-35), 0)
    on_bars(cl)
    for nm, dy, r in (("DialSpeed", 0.0, 0.06), ("DialFuel", 0.0, 0.02)):
        d = K.lathe(nm, [(0.0, 0.0), (r, 0.0), (r + 0.004, -0.003)], 32, 'X', [M["Gauge"]])
        zz = gz + 0.08 if nm == "DialSpeed" else gz + 0.02
        d.location = (0.788 if nm == "DialSpeed" else 0.8, dy, zz)
        d.rotation_euler = (0, math.radians(-35), 0)
        on_bars(d)
        nd = box(nm.replace("Dial", "Needle"), (0.002, 0.003, r * 0.85), d.location + Vector((-0.004, 0, 0.002)), M["Taillight"])
        nd.data.transform(Matrix.Translation(Vector((0, 0, 0.42))))
        nd.rotation_euler = (0, math.radians(-35), 0)
        on_bars(nd)
    on_bars(tube("HeadStock", [tuple(head + Vector((0.34, 0, -0.94)) * 0.4), tuple(head + Vector((-0.02, 0, 0.05)))], 0.028, M["BlackGloss"]))

    bar = smooth_path([(0.58, 0.37, gz), (0.64, 0.3, gz + 0.01), (0.74, 0.14, gz + 0.02), (0.8, 0.0, gz + 0.02),
                       (0.74, -0.14, gz + 0.02), (0.64, -0.3, gz + 0.01), (0.58, -0.37, gz)], 6)
    on_bars(tube("Handlebar", bar, 0.012, M["Chrome"]))
    on_bars(box("BarClamp", (0.06, 0.08, 0.05), (0.8, 0, gz + 0.0), M["BlackGloss"], bevel=0.01))
    for s in (1, -1):
        g = cyl("Grip", 0.017, 0.12, (0.59, s * 0.34, gz), M["Rubber"], axis='Y')
        g.rotation_euler = (math.pi / 2, 0, s * math.radians(-40))
        on_bars(g)
        on_bars(box("SwitchPod", (0.04, 0.035, 0.035), (0.64, s * 0.27, gz + 0.005), M["BlackGloss"], bevel=0.008))
        lv = tube("Lever", [(0.645, s * 0.27, gz + 0.01), (0.61, s * 0.33, gz + 0.015), (0.56, s * 0.38, gz + 0.01)], 0.006, M["Steel"])
        on_bars(lv)
    # the driver's bench in the middle, the backrest behind him (the passengers' knees behind that)
    out.append(box("DriverCushion", (0.4, 0.6, 0.1), (0.36, 0, 0.66), M["Vinyl"], rot=(0, math.radians(-4), 0), bevel=0.035))
    out.append(box("DriverSeatBase", (0.36, 0.56, 0.3), (0.36, 0, 0.47), M["Paint"], bevel=0.02))
    out.append(box("DriverBack", (0.09, 0.74, 0.34), (0.12, 0, 0.92), M["Vinyl"], rot=(0, math.radians(8), 0), bevel=0.035))
    out.append(box("DriverBackPanel", (0.03, 1.2, 0.5), (0.06, 0, 0.83), M["Paint"], bevel=0.01))
    out.append(tube("GrabRail", [(0.04, -0.55, 1.12), (0.03, -0.5, 1.16), (0.03, 0.5, 1.16), (0.04, 0.55, 1.12)], 0.013, M["Chrome"]))
    # the passengers' bench for three, its back, the engine cover under it
    out.append(box("RearCushion", (0.44, 1.2, 0.12), (-0.62, 0, 0.66), M["Vinyl"], rot=(0, math.radians(-4), 0), bevel=0.04))
    out.append(box("RearBase", (0.5, 1.22, 0.3), (-0.64, 0, 0.47), M["Inner"], bevel=0.02))
    out.append(box("RearBack", (0.11, 1.18, 0.5), (-0.92, 0, 1.0), M["Vinyl"], rot=(0, math.radians(-12), 0), bevel=0.04))
    for k in range(4):
        out.append(box("Pleat", (0.012, 1.1, 0.008), (-0.87 - k * 0.01, 0, 0.84 + k * 0.1), M["Vinyl"], rot=(0, math.radians(-12), 0)))
    # the cabin lamp, a small shelf behind the bench
    out.append(box("CabinLamp", (0.08, 0.14, 0.02), (-0.2, 0, ROOF - 0.04), M["DashLight"], bevel=0.006))
    # what the game reads
    eye = bpy.data.objects.new("Eye", None)
    K.link(eye)
    eye.location = (0.36, 0.0, 1.5)
    out.append(eye)
    bpy.context.view_layer.update()
    for nm, at, par in (("DriverHip", (0.33, 0.0, 0.74), None), ("GripL", (0.59, 0.33, gz), piv), ("GripR", (0.59, -0.33, gz), piv),
                        ("FootL", (0.62, 0.12, FLOOR + 0.07), None), ("FootR", (0.62, -0.12, FLOOR + 0.07), None)):
        mk = bpy.data.objects.new(nm, None)
        K.link(mk)
        mk.location = at
        if par is not None:
            mk.parent = par
            mk.matrix_parent_inverse = inv
        out.append(mk)
    return out


def materials():
    M = K.materials(YELLOW)
    M["Canvas"] = K._mat("Canvas", (0.018, 0.018, 0.02), rough=0.92, normal=bpy.data.images.get("tex_fabric_weave"), normal_k=0.6, uv_scale=10.0)
    M["CanvasIn"] = K._mat("CanvasIn", (0.04, 0.04, 0.042), rough=0.95)
    M["Vinyl"] = K._mat("Vinyl", (0.09, 0.02, 0.02), rough=0.45, coat=0.2, normal=bpy.data.images.get("tex_plastic_grain"), normal_k=0.3, uv_scale=6.0)
    M["Inner"] = K._mat("Inner", (0.5, 0.36, 0.03), rough=0.55)
    M["RimSteel"] = K._mat("RimSteel", (0.02, 0.02, 0.022), metal=0.6, rough=0.4)
    M["PlateYellow"] = K._mat("PlateYellow", (0.8, 0.55, 0.02), rough=0.4)
    M["MeterLed"] = K._mat("MeterLed", (0.2, 0.01, 0.01), rough=0.2, emit=(1.0, 0.08, 0.02), emit_k=2.0)
    return M


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = materials()
    parts = build_cowl(M)
    parts += build_tub(M)
    parts += build_hood(M)
    parts += windscreen(M)
    parts += front_details(M)
    parts += rear_details(M)
    parts += wheels(M)
    parts += interior(M)
    tris = 0
    dg = bpy.context.evaluated_depsgraph_get()
    for o in bpy.data.objects:
        if o.type == 'MESH' and not o.name.startswith("Preview"):
            tris += sum(len(p.vertices) - 2 for p in o.evaluated_get(dg).data.polygons)
    print("AUTO done: %d objects, %d triangles" % (len([o for o in bpy.data.objects if o.type == 'MESH']), tris), flush=True)
    if "--export" in args:
        out = args[args.index("--export") + 1]
        bpy.ops.object.select_all(action='DESELECT')
        for o in bpy.data.objects:
            if not o.name.startswith("Preview"):
                o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_yup=True,
                                  export_apply=True, export_image_format='JPEG')
        print("AUTO exported %s (%.1f MB)" % (out, os.path.getsize(out) / 1e6), flush=True)
    if "--preview" in args:
        d = args[args.index("--preview") + 1]
        os.makedirs(d, exist_ok=True)
        K.previews(os.path.join(d, "auto"), target=Vector((0, 0, 0.8)), dist=4.6)


if __name__ != "probe":
    main()
