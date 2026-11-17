"""Our own 110 cc step-through scooter (docs/TWO_WHEELERS_2026-11-17.md): the family scooter of every Indian street,
unbadged, real size. Not a motorcycle with panels: the steel step-through frame is hidden by a curved front apron and
leg shield, a flat floorboard, and a rear body over the under-seat storage; the engine and its belt drive are one
unit swinging on the left with the rear wheel on its end (a single shock), the exhaust on the right.

    blender -b --factory-startup --python tools/cars/build_scooter.py -- [--export out.glb] [--preview dir]

1.84 m long, 1.265 m wheelbase, 0.70 m across the bars, 1.15 m high, the seat at 0.77 m; 90/90-12 front and
90/100-10 rear tyres on five-spoke alloys, a 190 mm front disc, a rear drum. The motorcycle's tyre, alloy, disc and
materials (build_moto.py) on the car kit.

What the game reads (scripts/drive/jeep.gd): Wheel_F / Wheel_R; what turns with the bars joined as "Handlebar"
(the bar cowl and cluster, mirrors, levers, the fork and front mudguard), "Grip", "NeedleSpeed"; the apron's lamps
stay put: "HeadlampApron" (the head lamp, lit), "Indicator_L_Front" / "Indicator_R_Front", the rear
"Indicator_L_R" / "Indicator_R_R", "TailLamp"; the painted panels "Body" (the material "Paint").
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import carkit as K  # noqa: E402
import parts as P  # noqa: E402
import build_moto as BM  # noqa: E402

AX_F, AX_R = 0.6, -0.665
RF, RR = 0.235, 0.218                         # 90/90-12, 90/100-10
RAKE = math.radians(27.0)
FLOOR = 0.31


def on_axis(z):
    """The steering axis (through the front axle, raked back) at height z."""
    return Vector((AX_F - (z - RF) * math.tan(RAKE), 0.0, z))


def ring_xy(z, cx, dx_f, dx_b, w, n=32, p=2.4, y0=0.0):
    """A closed section in plan at height z: centre cx, reaching dx_f ahead and dx_b behind, half width w."""
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        u = math.copysign(abs(c) ** (2 / p), c) * (dx_f if c >= 0 else dx_b)
        v = math.copysign(abs(s) ** (2 / p), s) * w
        pts.append((cx + u, y0 + v, z))
    return pts


def wheels(M):
    out = []
    for nm, x, R, tw, rim_d, disc in (("Wheel_F", AX_F, RF, 0.09, 0.3048, True), ("Wheel_R", AX_R, RR, 0.092, 0.254, False)):
        piv = bpy.data.objects.new(nm, None)
        K.link(piv)
        piv.location = (x, 0, R)
        pn = "WF" if nm == "Wheel_F" else "WR"
        kids = [BM.tyre(M, pn + "_Tyre", R, tw, rim_d / 2 + 0.008)]
        kids += BM.alloy(M, pn, rim_d / 2, tw * 0.62)
        if disc:
            kids += BM.disc(M, pn, 0.095, 0.058, 1.0)
        else:
            drum = K.lathe(pn + "_Drum", [(0.05, 0.075), (0.075, 0.07), (0.078, 0.03), (0.06, 0.02)], 40, 'Y', [M["EngineAlu"]])
            kids.append(drum)
        body = P.join(kids, pn + "_Wheel")
        body.parent = piv
        body.location = (0, 0, 0)
        out.append(piv)
    return out


# ----------------------------------------------------------------------------------------------------- the bars
def front(M):
    bars, grips = [], []
    fwd = Vector((math.sin(RAKE), 0, -math.cos(RAKE)))        # down the axis
    up = -fwd
    # a short telescopic fork, the mudguard over the wheel on it
    for s in (1, -1):
        axle = Vector((AX_F, s * 0.07, RF))
        bars.append(P.tube("ForkSlider", [tuple(axle - up * 0.02), tuple(axle + up * 0.22)], 0.022, M["EngineAlu"]))
        bars.append(P.tube("Stanchion", [tuple(axle + up * 0.21), tuple(axle + up * 0.36)], 0.015, M["Chrome"]))
        bars.append(P.cyl("AxleClamp", 0.02, 0.026, tuple(axle + Vector((0, s * 0.01, 0))), M["EngineAlu"]))
    ca = math.radians(125)
    cpos = Vector((AX_F + math.cos(ca) * 0.078, 0.047, RF + math.sin(ca) * 0.078))
    for s2, w in ((1, 0.016), (-1, 0.012)):
        half = P.loft("Caliper", [(-0.035, w, 0.0, 0.022, 0.022, 3.0, 3.0), (0.0, w + 0.004, 0.0, 0.026, 0.026, 3.2, 3.2),
                                  (0.035, w, 0.0, 0.022, 0.022, 3.0, 3.0)], M["Caliper"], n=20)
        half.rotation_euler = (0, -(ca - math.pi / 2), 0)
        half.location = cpos + Vector((0, s2 * 0.015, 0))
        bars.append(half)
    bars.append(P.box("ForkBridge", (0.06, 0.18, 0.03), tuple(on_axis(0.62) + Vector((0.02, 0, 0))), M["EngineDark"], rot=(0, -RAKE, 0), bevel=0.01))
    rows = []
    for k in range(25):
        a = math.radians(10 + 160 * k / 24)
        r = RF + 0.035
        rows.append([(AX_F + math.cos(a) * r, y * (0.92 + 0.08 * math.sin(a)), RF + math.sin(a) * r) for y in [-0.065 + 0.13 * j / 10 for j in range(11)]])
    mg = P.grid("FrontGuard", rows, M["Paint"])
    K.smooth(mg, 40)
    mg.modifiers.new("S", 'SOLIDIFY').thickness = 0.004
    bars.append(mg)
    # the bar cowl: a moulded cover over the handlebar, the cluster set in its top; grips out of its ends
    hz = 1.03
    hc = on_axis(hz)
    cowl = P.loft("BarCowl", [(hc.x - 0.12, 0.17, hz - 0.005, 0.035, 0.05, 2.6, 2.4), (hc.x - 0.06, 0.27, hz, 0.05, 0.06, 2.8, 2.4),
                              (hc.x + 0.02, 0.28, hz + 0.005, 0.06, 0.07, 2.8, 2.4), (hc.x + 0.09, 0.2, hz, 0.05, 0.06, 2.6, 2.4),
                              (hc.x + 0.13, 0.09, hz - 0.01, 0.03, 0.04, 2.2, 2.2)], M["Paint"], n=40)
    bars.append(cowl)
    bars.append(P.loft("CowlLower", [(hc.x - 0.1, 0.16, hz - 0.055, 0.012, 0.02, 2.4, 2.4), (hc.x + 0.06, 0.24, hz - 0.06, 0.012, 0.02, 2.6, 2.6),
                                     (hc.x + 0.11, 0.14, hz - 0.06, 0.012, 0.018, 2.4, 2.4)], M["Plastic"], n=32))
    # the cluster: an analogue speedometer (the needle the game turns) beside a small LCD (fuel, the clock, trip)
    tilt = math.radians(35)
    cl = Vector((hc.x - 0.02, 0.0, hz + 0.05))
    face_n = Matrix.Rotation(tilt, 4, 'Y') @ Vector((-1, 0, 0))
    bez = P.loft("ClusterBezel", [(-0.012, 0.12, 0.0, 0.05, 0.05, 2.6, 2.6), (0.012, 0.125, 0.0, 0.055, 0.055, 2.6, 2.6)], M["BlackGloss"], n=36)
    bez.rotation_euler = (0, tilt, 0)
    bez.location = cl
    bars.append(bez)
    d = K.lathe("DialSpeed", [(0.0, 0.0), (0.042, 0.0), (0.045, -0.003)], 36, 'X', [M["Gauge"]])
    d.rotation_euler = (0, tilt, 0)
    d.location = cl + Vector((0, 0.035, 0)) + face_n * 0.013
    bars.append(d)
    ring = K.lathe("DialRing", [(0.044, 0.003), (0.049, -0.004)], 36, 'X', [M["Chrome"]])
    ring.rotation_euler = d.rotation_euler
    ring.location = d.location
    bars.append(ring)
    lcd = P.box("LCD", (0.004, 0.06, 0.04), tuple(cl + Vector((0, -0.05, 0)) + face_n * 0.013), M["Screen"], rot=(0, tilt, 0))
    bars.append(lcd)
    for k, col in enumerate(("Indicator", "DRL", "Headlight", "Taillight")):
        bars.append(P.box("TellTale", (0.004, 0.008, 0.006), tuple(cl + Vector((0, -0.02 - k * 0.012, -0.035)) + face_n * 0.013), M[col], rot=(0, tilt, 0)))
    needle = P.box("NeedleSpeed", (0.002, 0.003, 0.036), (0, 0, 0), M["Taillight"])
    needle.data.transform(Matrix.Translation(Vector((0, 0, 0.42))))
    needle.rotation_euler = (0, tilt, 0)
    needle.location = d.location + face_n * 0.004
    # grips, bar ends, switch pods, both brake levers (no clutch: an automatic), mirrors on the cowl
    for s in (1, -1):
        a, b = Vector((hc.x - 0.07, s * 0.27, hz - 0.01)), Vector((hc.x - 0.085, s * 0.38, hz - 0.012))
        grips.append(P.tube("Grip", [tuple(a), tuple(b)], 0.016, M["Grip"]))
        for k in range(8):
            p = a.lerp(b, 0.12 + 0.76 * k / 7)
            grips.append(P.cyl("GripRib", 0.0172, 0.003, tuple(p), M["Grip"], rot=(math.pi / 2, 0, s * math.radians(-8)), segs=16))
        grips.append(P.cyl("BarEnd", 0.018, 0.02, tuple(b + Vector((0, s * 0.012, 0))), M["Chrome"], rot=(math.pi / 2, 0, s * math.radians(-8))))
        bars.append(P.box("Switches", (0.05, 0.035, 0.042), tuple(a + Vector((0.005, -s * 0.012, 0.005))), M["Plastic"], bevel=0.012))
        lever = [tuple(a + Vector((0.025, -s * 0.0, 0.01))), tuple(a + Vector((0.05, s * 0.03, 0.005))), tuple(a + Vector((0.045, s * 0.09, -0.002))),
                 tuple(a + Vector((0.03, s * 0.12, -0.008)))]
        bars.append(P.tube("Lever", lever, 0.0055, M["EngineAlu"], smooth_pts=5))
        stem = [(hc.x + 0.02, s * 0.2, hz + 0.04), (hc.x + 0.0, s * 0.24, hz + 0.14), (hc.x - 0.02, s * 0.28, hz + 0.24)]
        bars.append(P.tube("MirrorStem", stem, 0.0065, M["BlackGloss"], smooth_pts=4))
        mh = P.loft("Mirror", [(-0.012, 0.07, 0.0, 0.04, 0.04, 2.8, 2.8), (0.008, 0.066, 0.0, 0.036, 0.036, 2.8, 2.8)], M["BlackGloss"], n=28)
        mh.location = (hc.x - 0.025, s * 0.29, hz + 0.27)
        mh.rotation_euler = (0, 0, s * math.radians(-12))
        bars.append(mh)
        mgl = P.loft("MirrorGlass", [(-0.0135, 0.064, 0.0, 0.035, 0.035, 2.8, 2.8), (-0.0125, 0.064, 0.0, 0.035, 0.035, 2.8, 2.8)], M["Mirror"], n=28)
        mgl.location = mh.location
        mgl.rotation_euler = mh.rotation_euler
        bars.append(mgl)
    bars.append(P.cyl("Throttle", 0.017, 0.03, (hc.x - 0.074, -0.255, hz - 0.01), M["Plastic"], rot=(math.pi / 2, 0, math.radians(8))))
    return [P.join(bars, "Handlebar"), P.join(grips, "Grip"), needle]


# ----------------------------------------------------------------------------------------------------- the body
def body(M):
    painted, black, bright, engine, other = [], [], [], [], []
    # the front apron: a curved shell from the floor to the bar cowl, raked with the steering, its back the leg shield
    secs = [(FLOOR + 0.02, 0.535, 0.05, 0.12, 0.17), (0.42, 0.535, 0.055, 0.1, 0.2), (0.55, 0.515, 0.06, 0.085, 0.225),
            (0.68, 0.48, 0.06, 0.08, 0.24), (0.8, 0.44, 0.055, 0.075, 0.235), (0.9, 0.395, 0.05, 0.07, 0.215),
            (0.97, 0.35, 0.045, 0.06, 0.18), (1.01, 0.31, 0.035, 0.045, 0.12)]
    rows = [ring_xy(z, cx, df, db, w, n=40, p=2.6) for (z, cx, df, db, w) in secs]
    ap = P.grid("Apron", rows, M["Paint"], closed=True, cap_ends=True)
    K.smooth(ap, 45)
    painted.append(ap)
    # the leg shield's inner face (black, grained), a glovebox lid and the bag hook on it
    rows = []
    for (z, cx, df, db, w) in secs[:-1]:
        pts = ring_xy(z, cx, df, db + 0.004, w - 0.005, n=40, p=2.6)
        rows.append([q for q in pts if q[0] < cx - db * 0.25])
    n = min(len(r) for r in rows)
    rows = [r[:n] for r in rows]
    ls = P.grid("LegShield", rows, M["Plastic"])
    K.smooth(ls, 45)
    black.append(ls)
    black.append(P.box("Glovebox", (0.01, 0.2, 0.1), (0.36, 0.0, 0.8), M["Plastic"], rot=(0, math.radians(-25), 0), bevel=0.01))
    bright.append(P.box("GloveLatch", (0.012, 0.03, 0.012), (0.352, 0.0, 0.83), M["Chrome"], bevel=0.003))
    black.append(P.tube("BagHook", [(0.395, 0.0, 0.66), (0.37, 0.0, 0.64), (0.36, 0.0, 0.67)], 0.006, M["Plastic"], smooth_pts=3))
    # the apron's face: the head lamp (a wide lens with an LED strip), a chrome garnish, the indicators, the plate
    hl_z, hl_x = 0.84, 0.475
    hl = P.loft("HeadLens", [(-0.02, 0.1, 0.0, 0.04, 0.035, 2.6, 2.6), (0.02, 0.11, 0.0, 0.045, 0.04, 2.6, 2.6)], M["Lens"], n=36)
    hl.rotation_euler = (0, math.radians(-25), 0)
    hl.location = (hl_x, 0, hl_z)
    other.append(hl)
    hh = P.loft("HeadHousing", [(-0.035, 0.1, 0.0, 0.04, 0.035, 2.6, 2.6), (0.0, 0.106, 0.0, 0.043, 0.038, 2.6, 2.6)], M["Reflector"], n=36)
    hh.rotation_euler = hl.rotation_euler
    hh.location = hl.location + Vector((-0.012, 0, 0))
    other.append(hh)
    lamp = P.loft("HeadlampApron", [(-0.004, 0.05, 0.0, 0.016, 0.016, 2.0, 2.0), (0.004, 0.05, 0.0, 0.016, 0.016, 2.0, 2.0)], M["Headlight"], n=24)
    lamp.rotation_euler = hl.rotation_euler
    lamp.location = hl.location + Vector((0.006, 0, 0))
    drl = P.box("DRL", (0.006, 0.17, 0.008), (hl_x + 0.02, 0, hl_z - 0.055), M["DRL"], rot=(0, math.radians(-25), 0), bevel=0.002)
    other.append(drl)
    for s in (1, -1):
        bright.append(P.tube("Garnish", [(0.585, s * 0.02, 0.45), (0.555, s * 0.09, 0.6), (0.52, s * 0.13, 0.7)], 0.006, M["Chrome"], smooth_pts=4))
    inds = {}
    for s, sl in ((1, "L"), (-1, "R")):
        li = P.loft("Indicator_%s_Front" % sl, [(-0.015, 0.03, 0.0, 0.012, 0.012, 2.4, 2.4), (0.01, 0.034, 0.0, 0.014, 0.014, 2.4, 2.4)], M["Indicator"], n=20)
        li.rotation_euler = (0, math.radians(-20), s * math.radians(35))
        li.location = (0.465, s * 0.2, 0.79)
        inds[sl + "F"] = li
    pm = {"PlateWhite": M["PlateWhite"], "PlateText": M["PlateText"]}
    pl, tx = K.plate(pm, "PlateFront", "TN 66 F 9083", Vector((0.59, 0, 0.4)), Vector((1, 0, 0)), w=0.17, h=0.075)
    pl.rotation_euler.y = math.radians(-15)
    other += [pl, tx]
    # the floorboard: its panel, the ribbed rubber mats, the skirts under it, the central tunnel
    black.append(P.box("FloorPanel", (0.5, 0.31, 0.03), (0.16, 0, FLOOR - 0.015), M["Plastic"], bevel=0.01))
    for s in (1, -1):
        other.append(P.box("FloorMat", (0.44, 0.11, 0.006), (0.17, s * 0.075, FLOOR + 0.003), M["Rubber"], bevel=0.002))
        for k in range(16):
            other.append(P.box("MatRib", (0.006, 0.1, 0.005), (-0.04 + k * 0.028, s * 0.075, FLOOR + 0.008), M["Rubber"]))
        sk = P.loft("Skirt", [(0.42, 0.012, 0.25, 0.05, 0.05, 3, 3), (0.2, 0.012, 0.24, 0.06, 0.06, 3, 3), (-0.05, 0.012, 0.25, 0.06, 0.06, 3, 3)], M["Paint"], n=16)
        sk.location.y = s * 0.15
        painted.append(sk)
        bright.append(P.box("SkirtStrip", (0.45, 0.004, 0.008), (0.19, s * 0.165, 0.27), M["Chrome"]))
    black.append(P.box("Underbody", (0.5, 0.28, 0.08), (0.17, 0, 0.23), M["Plastic"], bevel=0.02))
    # the rear body: one moulded shell over the frame and the storage bin, the rear wheel's well cut out underneath
    rb = P.loft("RearBody", [(-0.04, 0.13, 0.55, 0.2, 0.22, 2.4, 2.6), (-0.2, 0.17, 0.57, 0.19, 0.22, 2.6, 2.8),
                             (-0.45, 0.19, 0.58, 0.18, 0.2, 2.8, 3.0), (-0.68, 0.18, 0.6, 0.16, 0.16, 2.8, 2.8),
                             (-0.85, 0.14, 0.63, 0.12, 0.1, 2.6, 2.6), (-0.96, 0.08, 0.65, 0.08, 0.06, 2.4, 2.4), (-0.99, 0.04, 0.66, 0.05, 0.04, 2.2, 2.2)],
                M["Paint"], n=44)
    bmr = bmesh.new()
    bmr.from_mesh(rb.data)
    cut = [f for f in bmr.faces if abs(f.calc_center_median().y) < 0.115 and f.calc_center_median().z < 0.5 and -0.95 < f.calc_center_median().x < -0.3]
    cut += [f for f in bmr.faces if f.calc_center_median().z < 0.42 and f.calc_center_median().x < -0.25]
    bmesh.ops.delete(bmr, geom=list(set(cut)), context='FACES')
    bmr.to_mesh(rb.data)
    rb.modifiers.new("S", 'SOLIDIFY').thickness = 0.004
    painted.append(rb)
    liner = K.lathe("WheelLiner", [(RR + 0.04, -0.075), (RR + 0.045, 0.075)], 40, 'Y', [M["Plastic"]])
    for v in liner.data.vertices:
        if v.co.z < -0.02:
            v.co.z = -0.02
    liner.location = (AX_R, 0, RR)
    black.append(liner)
    for s in (1, -1):                                     # a body-coloured graphic line and the side vents
        bright.append(P.tube("SideLine", [(-0.12, s * 0.172, 0.6), (-0.45, s * 0.19, 0.64), (-0.8, s * 0.155, 0.68)], 0.004, M["Chrome"], smooth_pts=4))
        for k in range(3):
            black.append(P.box("Vent", (0.07, 0.004, 0.006), (-0.3 - k * 0.015, s * 0.188, 0.5 + k * 0.018), M["Plastic"]))
    # the storage bin under the seat, the seat on its hinge, its stitching; the grab rail; the pillion footrests
    black.append(P.box("StorageBin", (0.5, 0.26, 0.2), (-0.38, 0, 0.66), M["Plastic"], bevel=0.03))
    seat = P.loft("Seat", [(-0.04, 0.1, 0.77, 0.02, 0.035, 2.2, 3.0), (-0.12, 0.17, 0.77, 0.035, 0.04, 2.8, 3.0), (-0.38, 0.18, 0.775, 0.04, 0.045, 3.0, 3.0),
                           (-0.62, 0.17, 0.79, 0.045, 0.045, 3.0, 3.0), (-0.78, 0.13, 0.795, 0.04, 0.04, 2.6, 3.0), (-0.84, 0.08, 0.79, 0.03, 0.03, 2.2, 3.0)],
                  M["SeatVinyl"], n=40)
    other.append(seat)
    for s in (1, -1):
        st = []
        for k in range(30):
            x = -0.08 - 0.72 * k / 29
            w = K.cr([(-0.04, 0.1), (-0.12, 0.17), (-0.38, 0.18), (-0.62, 0.17), (-0.78, 0.13), (-0.84, 0.08)], x)
            z = K.cr([(-0.04, 0.77), (-0.38, 0.775), (-0.62, 0.79), (-0.78, 0.795), (-0.84, 0.79)], x)
            st.append((x, s * (w - 0.014), z + 0.032))
        other.append(P.tube("Stitch", st, 0.0025, M["Stitch"]))
    other.append(P.tube("SeatPiping", [(-0.5, 0.17, 0.83), (-0.5, -0.17, 0.83)], 0.004, M["Stitch"]))
    bright.append(P.tube("GrabRail", [(-0.58, 0.17, 0.79), (-0.72, 0.18, 0.84), (-0.9, 0.12, 0.84), (-0.95, 0.0, 0.84), (-0.9, -0.12, 0.84),
                                      (-0.72, -0.18, 0.84), (-0.58, -0.17, 0.79)], 0.012, M["EngineAlu"], smooth_pts=6))
    for s in (1, -1):
        other.append(P.box("PillionPeg", (0.08, 0.05, 0.02), (-0.2, s * 0.2, 0.42), M["Rubber"], bevel=0.006))
    # the tail lamp and rear indicators in the body's end, the rear mudguard and plate below
    tl = P.loft("TailLamp", [(-0.975, 0.07, 0.68, 0.025, 0.02, 2.4, 2.4), (-1.0, 0.065, 0.678, 0.022, 0.018, 2.4, 2.4)], M["Taillight"], n=28)
    for s, sl in ((1, "L"), (-1, "R")):
        li = P.loft("Indicator_%s_R" % sl, [(0.01, 0.025, 0.0, 0.012, 0.012, 2.4, 2.4), (-0.015, 0.028, 0.0, 0.013, 0.013, 2.4, 2.4)], M["Indicator"], n=20)
        li.rotation_euler = (0, 0, s * math.radians(-30))
        li.location = (-0.93, s * 0.12, 0.66)
        inds[sl + "R"] = li
    rows = []
    for k in range(17):
        a = math.radians(95 + 70 * k / 16)
        r = RR + 0.05
        rows.append([(AX_R + math.cos(a) * r, y, RR + math.sin(a) * r) for y in [-0.055 + 0.11 * j / 8 for j in range(9)]])
    rg = P.grid("RearGuard", rows, M["Plastic"])
    rg.modifiers.new("S", 'SOLIDIFY').thickness = 0.004
    black.append(rg)
    black.append(P.box("PlateHolder", (0.01, 0.2, 0.12), (-0.93, 0, 0.47), M["Plastic"], rot=(0, math.radians(15), 0), bevel=0.01))
    pl, tx = K.plate(pm, "PlateRear", "TN 66 F 9083", Vector((-0.938, 0, 0.47)), Vector((-1, 0, 0)), w=0.19, h=0.1)
    other += [pl, tx]
    bright.append(P.box("PlateLamp", (0.025, 0.05, 0.018), (-0.93, 0, 0.535), M["Chrome"], bevel=0.004))
    # the engine and belt-drive unit on the left: the cylinder lying forward under the floor's end, the long CVT case
    # back to the rear axle, its air filter on top, the kick lever; the single shock from its end up to the frame
    engine.append(P.loft("Crankcase", [(0.05, 0.08, 0.27, 0.07, 0.08, 2.4, 2.4), (-0.08, 0.11, 0.27, 0.09, 0.09, 2.6, 2.6),
                                       (-0.2, 0.09, 0.28, 0.08, 0.08, 2.4, 2.4)], M["EngineAlu"], n=32))
    engine.append(P.cyl("Barrel", 0.042, 0.13, (0.1, -0.01, 0.27), M["EngineDark"], axis='X'))
    for k in range(7):
        engine.append(P.box("Fin", (0.004, 0.14, 0.12), (0.05 + k * 0.016, -0.01, 0.27), M["EngineDark"], bevel=0.0015, segs=1))
    engine.append(P.box("CylHead", (0.06, 0.13, 0.11), (0.19, -0.01, 0.27), M["EngineAlu"], bevel=0.012))
    black.append(P.box("Shroud", (0.2, 0.16, 0.14), (0.1, -0.01, 0.29), M["Plastic"], bevel=0.03))
    cvt = P.loft("CVTCase", [(-0.05, 0.035, 0.3, 0.09, 0.07, 2.4, 2.4), (-0.25, 0.04, 0.29, 0.08, 0.06, 2.8, 2.6),
                             (-0.5, 0.04, 0.26, 0.07, 0.05, 2.8, 2.6), (AX_R - 0.05, 0.035, RR, 0.065, 0.06, 2.4, 2.4)], M["EngineAlu"], n=32)
    cvt.location.y = 0.115
    engine.append(cvt)
    cvc = P.loft("CVTCover", [(-0.08, 0.008, 0.3, 0.07, 0.05, 2.4, 2.4), (-0.4, 0.01, 0.27, 0.06, 0.045, 2.8, 2.6), (AX_R + 0.01, 0.008, RR, 0.05, 0.045, 2.4, 2.4)],
                  M["Plastic"], n=28)
    cvc.location.y = 0.158
    black.append(cvc)
    black.append(P.loft("AirFilter", [(-0.15, 0.05, 0.42, 0.05, 0.04, 2.6, 2.6), (-0.35, 0.06, 0.41, 0.055, 0.04, 2.8, 2.8), (-0.48, 0.05, 0.4, 0.04, 0.035, 2.4, 2.4)],
                        M["Plastic"], n=24))
    black[-1].location.y = 0.1
    black.append(P.tube("KickLever", [(-0.32, 0.17, 0.33), (-0.22, 0.2, 0.42), (-0.18, 0.21, 0.42)], 0.008, M["EngineDark"], smooth_pts=3))
    a, b = Vector((AX_R + 0.04, 0.13, RR + 0.07)), Vector((-0.5, 0.12, 0.6))
    dd = (b - a).normalized()
    bright.append(P.tube("ShockRod", [tuple(a), tuple(a + dd * 0.16)], 0.008, M["Chrome"]))
    black.append(P.tube("ShockBody", [tuple(a + dd * 0.15), tuple(b)], 0.02, M["EngineDark"]))
    other.append(P.helix("ShockSpring", tuple(a + dd * 0.04), tuple(b - dd * 0.05), 0.027, 0.0045, 8, M["Spring"]))
    # the exhaust on the right: a header from under the engine to a black-shielded silencer with a chrome tip
    bright.append(P.tube("Header", [(0.2, -0.04, 0.22), (0.15, -0.08, 0.17), (-0.1, -0.12, 0.17), (-0.3, -0.15, 0.24)], 0.016, M["Chrome"], smooth_pts=5))
    sil_a, sil_b = Vector((-0.3, -0.155, 0.24)), Vector((-0.78, -0.16, 0.36))
    sd = (sil_b - sil_a).normalized()
    sil = K.lathe("Silencer", [(0.0, 0.0), (0.03, 0.0), (0.055, 0.05), (0.06, 0.12), (0.058, 0.42), (0.045, 0.49), (0.0, 0.5)], 40, 'X', [M["EngineDark"]])
    P.place(sil, sil_a, sd)
    engine.append(sil)
    hs = K.lathe("HeatShield", [(0.064, 0.08), (0.068, 0.12), (0.068, 0.36), (0.064, 0.4)], 40, 'X', [M["BlackGloss"]])
    bmh = bmesh.new()
    bmh.from_mesh(hs.data)
    bmesh.ops.delete(bmh, geom=[f for f in bmh.faces if f.calc_center_median().y > 0.02 or f.calc_center_median().z < -0.03], context='FACES')
    bmh.to_mesh(hs.data)
    hs.modifiers.new("S", 'SOLIDIFY').thickness = 0.002
    P.place(hs, sil_a, sd)
    black.append(hs)
    tip = K.lathe("SilencerTip", [(0.018, 0.0), (0.024, 0.0), (0.024, 0.04), (0.018, 0.04)], 24, 'X', [M["Chrome"]])
    P.place(tip, sil_b, sd)
    bright.append(tip)
    # the stands (up): the centre stand under the floor's end, the side stand on the left
    for s in (1, -1):
        black.append(P.tube("CentreStand", [(-0.12, s * 0.1, 0.22), (-0.36, s * 0.14, 0.12)], 0.013, M["FrameBlack"]))
    black.append(P.tube("CentreStandBar", [(-0.36, 0.14, 0.12), (-0.36, -0.14, 0.12)], 0.012, M["FrameBlack"]))
    black.append(P.tube("SideStand", [(-0.02, 0.15, 0.2), (-0.22, 0.2, 0.13)], 0.011, M["FrameBlack"]))
    black.append(P.box("StandFoot", (0.04, 0.03, 0.01), (-0.23, 0.2, 0.12), M["FrameBlack"]))
    out = [P.join(painted, "Body"), P.join(black, "Blackwork"), P.join(bright, "Brightwork"), P.join(engine, "Engine"), P.join(other, "Details"),
           lamp, tl, inds["LF"], inds["RF"], inds["LR"], inds["RR"]]
    return out


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bpy.ops.wm.read_factory_settings(use_empty=True)
    BM.PAINT = (0.02, 0.09, 0.2)                       # a metallic blue
    M = BM.materials()
    root = bpy.data.objects.new("Scooter", None)
    K.link(root)
    objs = wheels(M) + front(M) + body(M)
    for o in objs:
        if o.parent is None:
            o.parent = root
    tris = 0
    dg = bpy.context.evaluated_depsgraph_get()
    for o in bpy.data.objects:
        if o.type == 'MESH' and not o.name.startswith("Preview"):
            tris += sum(len(p.vertices) - 2 for p in o.evaluated_get(dg).data.polygons)
    print("SCOOTER done: %d objects, %d triangles; bar axis at z 1.03: %s" % (len([o for o in bpy.data.objects if o.type == 'MESH']), tris,
                                                                            tuple(round(c, 3) for c in on_axis(1.03))), flush=True)
    if "--export" in args:
        out = args[args.index("--export") + 1]
        bpy.ops.object.select_all(action='DESELECT')
        for o in bpy.data.objects:
            if not o.name.startswith("Preview"):
                o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_yup=True,
                                  export_apply=True, export_image_format='JPEG')
        print("SCOOTER exported %s (%.1f MB)" % (out, os.path.getsize(out) / 1e6), flush=True)
    if "--preview" in args:
        d = args[args.index("--preview") + 1]
        os.makedirs(d, exist_ok=True)
        views = {"front34": (35, 10), "side_l": (90, 3), "side_r": (270, 3), "rear34": (150, 12), "front": (0, 5), "rear": (180, 5)}
        K.previews(os.path.join(d, "scooter"), target=Vector((0, 0, 0.55)), dist=3.3, views=views)
        cam = bpy.data.objects["PreviewCam"]
        sc = bpy.context.scene
        for nm, loc, tgt in (("engine", (-0.3, 0.95, 0.4), (-0.25, 0.1, 0.3)), ("floor", (-0.35, 0.0, 1.45), (0.2, 0, 0.6))):
            cam.location = loc
            cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(d, "scooter_%s.png" % nm)
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
