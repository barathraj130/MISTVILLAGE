"""Our own commuter motorcycle (docs/TWO_WHEELERS_2026-11-17.md): a 125 cc Indian commuter, unbadged, real size.

    blender -b --factory-startup --python tools/cars/build_moto.py -- [--export out.glb] [--preview dir]

1.285 m wheelbase, 2.02 m long, 0.74 m across the bars, 1.08 m high, the seat at 0.79 m; 2.75-18 / 3.00-18 tyres
on five-spoke alloys, a 240 mm front disc with a twin-piston caliper, a rear drum. Built on the car kit's PBR
library (tools/cars/carkit.py) with parts.py's shapes.

What the game reads (scripts/drive/jeep.gd): the wheels' pivots Wheel_F / Wheel_R (the front one steered and spun,
the rear spun; the disc and sprocket spin with them, the caliper and drum plate don't); everything that turns with
the bars joined into "Handlebar" (forks, yokes, headlamp nacelle, cluster, front mudguard, front plate), the grips
"Grip", the headlamp's emitter "Headlamp", the front indicators "Indicator_L_F" / "Indicator_R_F" (on the bars),
the rear ones "Indicator_L_R" / "Indicator_R_R", the tail and brake lamp "TailLamp", the speedometer's needle
"NeedleSpeed", the body "Body" (its paint the material "Paint", recoloured per bike).

Blender's frame: +X the nose, +Y the rider's left, Z up, the ground at z 0, the middle of the wheelbase near x 0.
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

PAINT = (0.36, 0.008, 0.012)                      # a deep candy red
AX_F, AX_R = 0.655, -0.63
RF, RR = 0.297, 0.305                             # 2.75-18 / 3.00-18
RIM_D = 0.457
RAKE = math.radians(26.0)
HEAD_TOP = Vector((0.30, 0.0, 0.985))             # the steering head's top
AXIS = Vector((math.sin(RAKE), 0.0, -math.cos(RAKE)))   # down the steering axis


def on_axis(z):
    """The point on the steering axis at height z."""
    t = (z - HEAD_TOP.z) / AXIS.z
    return HEAD_TOP + AXIS * t


def materials():
    M = K.materials(PAINT)
    weave = bpy.data.images.get("tex_fabric_weave")
    grain = bpy.data.images.get("tex_plastic_grain")
    M["EngineAlu"] = K._mat("EngineAlu", (0.62, 0.62, 0.6), metal=1.0, rough=0.32, normal=grain, normal_k=0.15, uv_scale=4.0)
    M["EngineDark"] = K._mat("EngineDark", (0.05, 0.05, 0.055), metal=0.6, rough=0.45)
    M["FrameBlack"] = K._mat("FrameBlack", (0.012, 0.012, 0.014), metal=0.2, rough=0.25, coat=0.7)
    M["SeatVinyl"] = K._mat("SeatVinyl", (0.02, 0.02, 0.022), rough=0.55, coat=0.15, normal=weave, normal_k=0.25, uv_scale=8.0)
    M["Stitch"] = K._mat("Stitch", (0.25, 0.02, 0.02), rough=0.8)
    M["Grip"] = K._mat("GripRubber", (0.02, 0.02, 0.021), rough=0.8, normal=grain, normal_k=0.6, uv_scale=6.0)
    M["RimBlack"] = K._mat("RimBlack", (0.02, 0.02, 0.022), metal=0.5, rough=0.3, coat=0.5)
    M["Machined"] = K._mat("Machined", (0.8, 0.8, 0.82), metal=1.0, rough=0.18)
    M["Spring"] = K._mat("SpringRed", (0.32, 0.008, 0.01), metal=0.3, rough=0.3, coat=0.8)
    M["Plastic"] = K._mat("Plastic", (0.025, 0.025, 0.028), rough=0.55, normal=grain, normal_k=0.5, uv_scale=8.0)
    M["Mirror"] = K._mat("MirrorGlass", (0.9, 0.9, 0.92), metal=1.0, rough=0.02)
    return M


# ----------------------------------------------------------------------------------------------------- wheels
def tyre(M, name, R, tw, rim_r):
    """A motorcycle tyre: a round crown (it leans on its shoulder), bulged sidewalls, a zig-zag tread."""
    prof = [(rim_r - 0.004, -tw * 0.36), (rim_r + 0.01, -tw * 0.44), (rim_r + (R - rim_r) * 0.35, -tw * 0.5),
            (rim_r + (R - rim_r) * 0.62, -tw * 0.49)]
    for k in range(13):                                     # the crown: an arc across the tread
        a = math.radians(-62 + 124 * k / 12)
        prof.append((R - tw * 0.5 * (1 - math.cos(a)) * 0.9, tw * 0.48 * math.sin(a)))
    prof += [(rim_r + (R - rim_r) * 0.62, tw * 0.49), (rim_r + (R - rim_r) * 0.35, tw * 0.5), (rim_r + 0.01, tw * 0.44),
             (rim_r - 0.004, tw * 0.36)]
    ob = K.lathe(name, prof, 120, 'Y', [M["Tyre"]])
    for v in ob.data.vertices:
        r = math.hypot(v.co.x, v.co.z)
        if r > R - tw * 0.3:
            ang = math.atan2(v.co.z, v.co.x)
            y = v.co.y / (tw * 0.5)
            zig = math.sin(ang * 30 + abs(y) * 2.6)                      # zig-zag blocks, mirrored about the centre
            if (0.25 < abs(y) < 0.9 and zig > 0.55) or abs(y) < 0.05:
                k = (r - 0.0045) / r
                v.co.x *= k
                v.co.z *= k
    K.smooth(ob, 60)
    return ob


def alloy(M, name, rim_r, rw):
    """A five-spoke alloy: the rim (two flanges and the well), Y-split spokes, the hub with its bearings."""
    out = []
    rim = K.lathe(name + "_Rim", [(rim_r + 0.012, -rw * 0.5), (rim_r + 0.014, -rw * 0.46), (rim_r, -rw * 0.42), (rim_r - 0.006, -rw * 0.2),
                                  (rim_r - 0.012, 0.0), (rim_r - 0.006, rw * 0.2), (rim_r, rw * 0.42), (rim_r + 0.014, rw * 0.46),
                                  (rim_r + 0.012, rw * 0.5), (rim_r - 0.002, rw * 0.5), (rim_r - 0.02, rw * 0.3),
                                  (rim_r - 0.024, 0.0), (rim_r - 0.02, -rw * 0.3), (rim_r - 0.002, -rw * 0.5)], 96, 'Y', [M["RimBlack"]])
    K.smooth(rim, 50)
    out.append(rim)
    lip = K.lathe(name + "_Lip", [(rim_r + 0.0125, rw * 0.5 + 0.0005), (rim_r + 0.003, rw * 0.5 + 0.0005)], 96, 'Y', [M["Machined"]])
    out.append(lip)
    lip2 = K.lathe(name + "_Lip", [(rim_r + 0.003, -rw * 0.5 - 0.0005), (rim_r + 0.0125, -rw * 0.5 - 0.0005)], 96, 'Y', [M["Machined"]])
    out.append(lip2)
    bm = bmesh.new()

    def spoke(a0, a1, r0, r1, w0, w1, t0, t1):
        vs = []
        for (a, r, w, t) in ((a0, r0, w0, t0), (a1, r1, w1, t1)):
            c, s = math.cos(a), math.sin(a)
            px, pz = -s, c
            for sw in (-1, 1):
                for st in (-1, 1):
                    vs.append(bm.verts.new((c * r + px * w * sw, st * t, s * r + pz * w * sw)))
        q = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        for f in q:
            bm.faces.new([vs[i] for i in f])
    for k in range(5):
        a = 2 * math.pi * k / 5 + 0.3
        spoke(a, a, 0.055, 0.13, 0.016, 0.013, 0.014, 0.011)
        for d in (-1, 1):
            spoke(a, a + d * 0.2, 0.13, rim_r - 0.018, 0.011, 0.009, 0.011, 0.008)
    sp = K.mesh_obj(name + "_Spokes", bm, [M["RimBlack"]])
    bv = sp.modifiers.new("Bv", 'BEVEL')
    bv.width = 0.003
    bv.segments = 2
    K.smooth(sp, 35)
    out.append(sp)
    hub = K.lathe(name + "_Hub", [(0.0, -0.06), (0.02, -0.06), (0.03, -0.052), (0.06, -0.045), (0.065, -0.02), (0.062, 0.02),
                                  (0.06, 0.045), (0.03, 0.052), (0.02, 0.06), (0.0, 0.06)], 48, 'Y', [M["RimBlack"]])
    K.smooth(hub, 50)
    out.append(hub)
    for s in (1, -1):
        out.append(P.cyl(name + "_AxleNut", 0.014, 0.012, (0, s * 0.066, 0), M["Chrome"], segs=6))
    return out


def disc(M, name, r_out, r_in, side):
    """A 240 mm disc: the braking ring drilled in a pattern, its carrier and five bolts (spins with the wheel)."""
    bm = bmesh.new()
    nseg, nr = 96, 5
    rows = []
    for i in range(nr + 1):
        r = r_in + (r_out - r_in) * i / nr
        rows.append([(math.cos(2 * math.pi * j / nseg) * r, math.sin(2 * math.pi * j / nseg) * r) for j in range(nseg)])
    holes = set()
    top = [[bm.verts.new((x, 0.002, z)) for x, z in row] for row in rows]
    bot = [[bm.verts.new((x, -0.002, z)) for x, z in row] for row in rows]
    for i in range(nr):
        for j in range(nseg):
            if (i, j) in holes:
                continue
            j1 = (j + 1) % nseg
            bm.faces.new((top[i][j], top[i][j1], top[i + 1][j1], top[i + 1][j]))
            bm.faces.new((bot[i][j], bot[i + 1][j], bot[i + 1][j1], bot[i][j1]))
    for j in range(nseg):
        j1 = (j + 1) % nseg
        bm.faces.new((top[nr][j], top[nr][j1], bot[nr][j1], bot[nr][j]))
        bm.faces.new((top[0][j], bot[0][j], bot[0][j1], top[0][j1]))
    d = K.mesh_obj(name + "_Disc", bm, [M["Disc"]])
    d.location = (0, side * 0.052, 0)
    out = [d]
    for k in range(30):
        a = 2 * math.pi * k / 30
        rh = r_in + (r_out - r_in) * (0.3 + 0.2 * (k % 3))
        out.append(P.cyl(name + "_Hole", 0.0042, 0.0046, (math.cos(a) * rh, side * 0.052, math.sin(a) * rh), M["EngineDark"], segs=10))
    car = K.lathe(name + "_Carrier", [(0.03, -0.003), (r_in + 0.004, -0.003), (r_in + 0.004, 0.003), (0.03, 0.003)], 40, 'Y', [M["RimBlack"]])
    car.location = (0, side * 0.05, 0)
    out.append(car)
    for k in range(5):
        a = 2 * math.pi * k / 5
        out.append(P.cyl(name + "_DiscBolt", 0.006, 0.01, (math.cos(a) * (r_in - 0.006), side * 0.056, math.sin(a) * (r_in - 0.006)), M["Chrome"], segs=6))
    return out


def wheels(M):
    out = []
    fixed = []
    for nm, x, R, tw in (("Wheel_F", AX_F, RF, 0.072), ("Wheel_R", AX_R, RR, 0.082)):
        piv = bpy.data.objects.new(nm, None)
        K.link(piv)
        piv.location = (x, 0, R)
        pn = "WF" if nm == "Wheel_F" else "WR"
        kids = [tyre(M, pn + "_Tyre", R, tw, RIM_D / 2 + 0.008)]
        kids += alloy(M, pn, RIM_D / 2, tw * 0.62)
        if nm == "Wheel_F":
            kids += disc(M, pn, 0.12, 0.072, 1.0)
        else:
            drum = K.lathe(pn + "_Drum", [(0.06, -0.075), (0.085, -0.07), (0.088, -0.03), (0.07, -0.02)], 48, 'Y', [M["EngineAlu"]])
            kids.append(drum)
            kids.append(P.sprocket(pn + "_Sprocket", (0, 0.07, 0), 0.105, 42, 0.005, M["Steel"]))
            for k in range(4):
                a = 2 * math.pi * k / 4
                kids.append(P.cyl(pn + "_SprocketBolt", 0.006, 0.014, (math.cos(a) * 0.05, 0.072, math.sin(a) * 0.05), M["Chrome"], segs=6))
        body = P.join(kids, pn + "_Wheel")
        body.parent = piv
        body.location = (0, 0, 0)
        out.append(piv)
    return out


# ----------------------------------------------------------------------------------------------------- front end
def front(M):
    """Everything that turns with the bars, joined as "Handlebar" (and the grips, headlamp, indicators apart)."""
    bars = []
    # forks: the lower sliders (polished alloy) round the axle, chrome stanchions, rubber gaiters
    fwd = -AXIS
    for s in (1, -1):
        axle = Vector((AX_F, s * 0.078, RF))
        top = axle + fwd * 0.78
        bars.append(P.tube("ForkSlider", [tuple(axle - fwd * 0.03), tuple(axle + fwd * 0.3)], 0.024, M["EngineAlu"]))
        bars.append(P.tube("ForkCap", [tuple(axle + fwd * 0.3), tuple(axle + fwd * 0.315)], 0.021, M["Rubber"]))
        bars.append(P.tube("Stanchion", [tuple(axle + fwd * 0.31), tuple(axle + fwd * 0.46)], 0.0165, M["Chrome"]))
        bars.append(P.tube("ForkCover", [tuple(axle + fwd * 0.46), tuple(top)], 0.024, M["Paint"]))
        bars.append(P.cyl("AxleClamp", 0.022, 0.03, tuple(axle - fwd * 0.01 + Vector((0.0, s * 0.012, 0))), M["EngineAlu"]))
        bars.append(P.cyl("ForkTopNut", 0.016, 0.02, tuple(top + fwd * 0.012), M["Chrome"], rot=(0, -RAKE, 0)))
    # the caliper on the left leg (behind the disc, above the axle), its hose to the bar
    ca = math.radians(125)
    cpos = Vector((AX_F + math.cos(ca) * 0.098, 0.052, RF + math.sin(ca) * 0.098))
    for s2, w in ((1, 0.018), (-1, 0.014)):                   # the two halves either side of the disc, bridged
        half = P.loft("Caliper", [(-0.04, w, 0.0, 0.026, 0.026, 3.0, 3.0), (0.0, w + 0.004, 0.0, 0.03, 0.03, 3.2, 3.2), (0.04, w, 0.0, 0.026, 0.026, 3.0, 3.0)], M["Caliper"], n=20)
        half.rotation_euler = (0, -(ca - math.pi / 2), 0)
        half.location = cpos + Vector((0, s2 * 0.017, 0))
        bars.append(half)
    bars.append(P.box("CaliperBridge", (0.06, 0.05, 0.012), tuple(cpos + Vector((math.cos(ca), 0, math.sin(ca))) * 0.028), M["Caliper"], rot=(0, -(ca - math.pi / 2), 0), bevel=0.004))
    bars.append(P.tube("CaliperBracket", [tuple(cpos + Vector((0, 0.03, 0))), (AX_F - 0.01, 0.08, RF + 0.1)], 0.01, M["EngineAlu"]))
    bars.append(P.tube("BrakeHose", [(AX_F - 0.08, 0.11, RF + 0.1), (AX_F - 0.05, 0.12, 0.6), (0.35, 0.12, 0.88), (0.22, -0.2, 1.04)],
                       0.004, M["Rubber"], smooth_pts=6))
    # the yokes, the steering stem's nut
    for z, th in ((HEAD_TOP.z - 0.215, 0.03), (HEAD_TOP.z + 0.015, 0.022)):
        c = on_axis(z)
        bars.append(P.box("Yoke", (0.07, 0.22, th), (c.x + 0.012, 0, c.z), M["EngineDark"], rot=(0, -RAKE, 0), bevel=0.01))
    bars.append(P.cyl("StemNut", 0.02, 0.02, tuple(on_axis(HEAD_TOP.z + 0.03)), M["Chrome"], rot=(0, -RAKE, 0), segs=6))
    # the front mudguard on its stays
    rows = []
    for k in range(25):
        a = math.radians(18 + 150 * k / 24)
        r = RF + 0.032
        rows.append([(AX_F + math.cos(a) * r * (1 + 0.04 * abs(y) / 0.05), y * (0.9 + 0.1 * math.sin(a)), RF + math.sin(a) * r)
                     for y in [-0.052 + 0.104 * j / 10 for j in range(11)]])
    mg = P.grid("FrontGuard", rows, M["Paint"])
    K.smooth(mg, 40)
    so = mg.modifiers.new("S", 'SOLIDIFY')
    so.thickness = 0.004
    bars.append(mg)
    for s in (1, -1):
        bars.append(P.tube("GuardStay", [(AX_F - 0.04, s * 0.07, RF + 0.03), (AX_F + 0.02, s * 0.056, RF + 0.33)], 0.005, M["Chrome"]))
    # the headlamp nacelle (painted), its chrome bezel, the lens; the visor and the cluster behind it
    hc = Vector((0.43, 0.0, 0.88))
    nac = P.loft("Nacelle", [(hc.x - 0.11, 0.075, hc.z + 0.01, 0.07, 0.07, 2.4, 2.4), (hc.x - 0.05, 0.1, hc.z, 0.095, 0.095, 2.6, 2.6),
                             (hc.x + 0.02, 0.105, hc.z, 0.1, 0.1, 2.6, 2.6), (hc.x + 0.045, 0.1, hc.z, 0.095, 0.095, 2.6, 2.6)],
                 M["Paint"], n=40)
    bars.append(nac)
    bez = K.lathe("Bezel", [(0.088, 0.0), (0.095, 0.004), (0.094, 0.012), (0.084, 0.016)], 48, 'X', [M["Chrome"]])
    bez.location = (hc.x + 0.045, 0, hc.z)
    bars.append(bez)
    refl = K.lathe("Reflector", [(0.0, -0.05), (0.04, -0.042), (0.07, -0.022), (0.084, 0.0)], 48, 'X', [M["Reflector"]])
    refl.location = (hc.x + 0.05, 0, hc.z)
    bars.append(refl)
    lens = K.lathe("HeadLens", [(0.0, 0.018), (0.05, 0.014), (0.085, 0.002)], 48, 'X', [M["Lens"]])
    lens.location = (hc.x + 0.05, 0, hc.z)
    bars.append(lens)
    lamp = K.lathe("Headlamp", [(0.0, -0.02), (0.018, -0.022), (0.024, -0.036), (0.0, -0.042)], 24, 'X', [M["Headlight"]])
    lamp.location = (hc.x + 0.05, 0, hc.z)
    visor = P.loft("Visor", [(hc.x - 0.12, 0.09, hc.z + 0.115, 0.03, 0.02, 2.2, 2.2), (hc.x - 0.02, 0.105, hc.z + 0.105, 0.035, 0.02, 2.2, 2.2),
                             (hc.x + 0.05, 0.08, hc.z + 0.095, 0.02, 0.012, 2.2, 2.2)], M["Paint"], n=28)
    bars.append(visor)
    # the cluster: a hooded analogue speedometer (its needle turned by the game), the fuel gauge, tell-tales
    cl_at = Vector((0.27, 0.0, 1.07))
    tilt = math.radians(50)
    cl = P.loft("Cluster", [(cl_at.x - 0.035, 0.08, cl_at.z, 0.048, 0.04, 2.6, 2.6), (cl_at.x + 0.025, 0.084, cl_at.z, 0.052, 0.044, 2.6, 2.6)],
                M["Plastic"], n=32)
    cl.data.transform(Matrix.Translation(-cl_at))
    cl.data.transform(Matrix.Rotation(tilt, 4, 'Y'))
    cl.location = cl_at
    bars.append(cl)
    face_n = Matrix.Rotation(tilt, 4, 'Y') @ Vector((-1, 0, 0))
    for nm, dy, r in (("DialSpeed", 0.025, 0.04), ("DialFuel", -0.055, 0.018)):
        d = K.lathe(nm, [(0.0, 0.0), (r, 0.0), (r + 0.003, -0.003)], 36, 'X', [M["Gauge"]])
        d.rotation_euler = (0, tilt, 0)
        d.location = cl_at + Vector((0, dy, 0)) + face_n * 0.036
        bars.append(d)
        ring = K.lathe(nm + "Ring", [(r + 0.002, 0.003), (r + 0.006, -0.004)], 36, 'X', [M["Chrome"]])
        ring.rotation_euler = d.rotation_euler
        ring.location = d.location
        bars.append(ring)
    needle = P.box("NeedleSpeed", (0.002, 0.003, 0.034), (0, 0, 0), M["Taillight"])
    needle.data.transform(Matrix.Translation(Vector((0, 0, 0.42))))
    needle.rotation_euler = (0, tilt, 0)
    needle.location = cl_at + Vector((0, 0.025, 0)) + face_n * 0.04
    for k, col in enumerate(("Indicator", "DRL", "Headlight")):
        bars.append(P.box("TellTale", (0.004, 0.008, 0.006), cl_at + Vector((0, -0.01 - k * 0.012, 0.045)) + face_n * 0.03, M[col]))
    # the handlebar (a commuter's swept-back tube), clamps, the switch housings, the master cylinder, levers, mirrors
    gz = 1.035
    bar_pts = [(0.17, 0.37, gz), (0.18, 0.3, gz), (0.215, 0.2, gz + 0.008), (0.25, 0.08, gz + 0.012), (0.255, 0.0, gz + 0.012),
               (0.25, -0.08, gz + 0.012), (0.215, -0.2, gz + 0.008), (0.18, -0.3, gz), (0.17, -0.37, gz)]
    bars.append(P.tube("Bar", bar_pts, 0.011, M["Chrome"], smooth_pts=6))
    for y in (0.045, -0.045):
        bars.append(P.box("BarClamp", (0.04, 0.03, 0.035), (0.255, y, gz + 0.005), M["EngineDark"], bevel=0.008))
    grips = []
    for s in (1, -1):
        g = P.tube("Grip", [(0.183, s * 0.29, gz), (0.168, s * 0.4, gz)], 0.016, M["Grip"])
        for k in range(9):                                          # the grip's rings
            t = 0.1 + 0.8 * k / 8
            p = Vector((0.183, s * 0.29, gz)).lerp(Vector((0.168, s * 0.4, gz)), t)
            grips.append(P.cyl("GripRib", 0.0175, 0.003, tuple(p), M["Grip"], rot=(math.pi / 2, 0, s * math.radians(-8)), segs=16))
        grips.append(g)
        grips.append(P.cyl("BarEnd", 0.018, 0.02, (0.167, s * 0.41, gz), M["Chrome"], rot=(math.pi / 2, 0, s * math.radians(-8))))
        bars.append(P.box("Switches", (0.05, 0.038, 0.045), (0.19, s * 0.262, gz + 0.004), M["Plastic"], bevel=0.012))
        bars.append(P.box("Switch", (0.012, 0.012, 0.008), (0.17, s * 0.262, gz + 0.022), M["BlackGloss"], bevel=0.003))
        lever = [(0.205, s * 0.275, gz + 0.01), (0.235, s * 0.3, gz + 0.008), (0.24, s * 0.36, gz + 0.003), (0.225, s * 0.41, gz - 0.004)]
        bars.append(P.tube("Lever", lever, 0.006, M["EngineAlu"], smooth_pts=5))
        bars.append(P.box("Perch", (0.03, 0.022, 0.03), (0.205, s * 0.28, gz + 0.006), M["EngineAlu"], bevel=0.006))
        stem = [(0.215, s * 0.245, gz + 0.02), (0.205, s * 0.27, gz + 0.12), (0.18, s * 0.3, gz + 0.24)]
        bars.append(P.tube("MirrorStem", stem, 0.0065, M["Chrome"], smooth_pts=4))
        mh = P.loft("Mirror", [(-0.012, 0.065, 0.0, 0.042, 0.042, 2.8, 2.8), (0.008, 0.06, 0.0, 0.038, 0.038, 2.8, 2.8)], M["BlackGloss"], n=28)
        mh.location = (0.175, s * 0.31, gz + 0.27)
        mh.rotation_euler = (0, 0, s * math.radians(-12))
        bars.append(mh)
        mgl = P.loft("MirrorGlass", [(-0.0135, 0.059, 0.0, 0.037, 0.037, 2.8, 2.8), (-0.0125, 0.059, 0.0, 0.037, 0.037, 2.8, 2.8)], M["Mirror"], n=28)
        mgl.location = mh.location
        mgl.rotation_euler = mh.rotation_euler
        bars.append(mgl)
        cable = [(0.2, s * 0.25, gz), (0.29, s * 0.2, gz - 0.03), (0.36, s * 0.1, 0.94), (0.33, s * 0.06, 0.83)]
        bars.append(P.tube("Cable", cable, 0.004, M["Rubber"], smooth_pts=6))
    bars.append(P.box("MasterCyl", (0.04, 0.035, 0.03), (0.215, -0.235, gz + 0.03), M["EngineAlu"], bevel=0.008))
    bars.append(P.box("Reservoir", (0.03, 0.03, 0.02), (0.215, -0.235, gz + 0.055), M["Lens"], bevel=0.006))
    bars.append(P.cyl("Throttle", 0.017, 0.03, (0.182, -0.283, gz), M["Plastic"], rot=(math.pi / 2, 0, math.radians(8))))
    bars.append(P.cyl("Horn", 0.04, 0.025, (0.5, 0.0, 0.73), M["BlackGloss"], axis='X'))
    # the front plate on the mudguard's front, a made-up registration
    pm = {"PlateWhite": M["PlateWhite"], "PlateText": M["PlateText"]}
    pl, tx = K.plate(pm, "PlateFront", "TN 38 BX 2741", Vector((AX_F + 0.2, 0, RF + 0.2)), Vector((1, 0, 0)), w=0.2, h=0.085)
    bars += [pl, tx]
    inds = {}
    for s, sl in ((1, "L"), (-1, "R")):
        st = P.tube("IndicatorStalk", [(hc.x - 0.02, s * 0.09, hc.z + 0.03), (hc.x - 0.01, s * 0.17, hc.z + 0.03)], 0.008, M["BlackGloss"])
        bars.append(st)
        lens_i = P.loft("Indicator_%s_F" % sl, [(-0.03, 0.022, 0.0, 0.018, 0.018, 2.2, 2.2), (0.0, 0.026, 0.0, 0.022, 0.022, 2.2, 2.2),
                                                (0.025, 0.018, 0.0, 0.014, 0.014, 2.0, 2.0)], M["Indicator"], n=20)
        lens_i.location = (hc.x, s * 0.185, hc.z + 0.03)
        inds[sl] = lens_i
    handle = P.join(bars, "Handlebar")
    grip = P.join(grips, "Grip")
    return [handle, grip, lamp, needle, inds["L"], inds["R"]]


# ----------------------------------------------------------------------------------------------------- the rest
def body(M):
    painted, frame, engine, chrome, black, other = [], [], [], [], [], []
    # the frame: the head tube, a downtube to the engine's front, the backbone under the tank to the pivot plates,
    # seat rails and the rear subframe
    ht0, ht1 = on_axis(HEAD_TOP.z - 0.2), on_axis(HEAD_TOP.z)
    frame.append(P.tube("HeadTube", [tuple(ht0), tuple(ht1)], 0.03, M["FrameBlack"]))
    frame.append(P.tube("Backbone", [tuple(ht1 + Vector((-0.02, 0, -0.03))), (0.05, 0, 0.86), (-0.12, 0, 0.75), (-0.17, 0, 0.55)], 0.026, M["FrameBlack"], smooth_pts=6))
    frame.append(P.tube("Downtube", [tuple(ht0 + Vector((-0.01, 0, 0.02))), (0.3, 0, 0.6), (0.27, 0, 0.42)], 0.024, M["FrameBlack"], smooth_pts=6))
    for s in (1, -1):
        frame.append(P.box("PivotPlate", (0.12, 0.012, 0.2), (-0.16, s * 0.105, 0.47), M["FrameBlack"], bevel=0.01))
        frame.append(P.tube("SeatRail", [(-0.05, s * 0.07, 0.79), (-0.3, s * 0.09, 0.77), (-0.82, s * 0.07, 0.8)], 0.014, M["FrameBlack"], smooth_pts=5))
        frame.append(P.tube("Strut", [(-0.17, s * 0.1, 0.52), (-0.5, s * 0.095, 0.77)], 0.014, M["FrameBlack"]))
        frame.append(P.tube("EngineHanger", [(0.3, s * 0.02, 0.45), (0.24, s * 0.09, 0.42)], 0.01, M["FrameBlack"]))
    frame.append(P.tube("SeatCross", [(-0.3, 0.09, 0.77), (-0.3, -0.09, 0.77)], 0.012, M["FrameBlack"]))
    # the swingarm (box-section arms, a brace), its pivot bolt, the chain adjusters
    for s in (1, -1):
        arm = P.loft("Swingarm", [(-0.16, 0.022, 0.43, 0.03, 0.03, 4, 4), (-0.4, 0.018, 0.37, 0.026, 0.026, 4, 4), (AX_R - 0.03, 0.016, RR, 0.022, 0.022, 4, 4)], M["FrameBlack"], n=16)
        arm.location.y = s * 0.1
        frame.append(arm)
        frame.append(P.box("Adjuster", (0.06, 0.012, 0.03), (AX_R + 0.01, s * 0.12, RR), M["EngineAlu"], bevel=0.004))
    frame.append(P.tube("ArmBrace", [(-0.25, 0.1, 0.41), (-0.25, -0.1, 0.41)], 0.016, M["FrameBlack"]))
    chrome.append(P.cyl("PivotBolt", 0.012, 0.25, (-0.16, 0, 0.43), M["Chrome"], segs=8))
    # rear shocks: damper bodies, chrome rods, red coil springs, the eyes
    for s in (1, -1):
        a, b = Vector((AX_R + 0.06, s * 0.118, RR + 0.06)), Vector((-0.44, s * 0.112, 0.79))
        d = (b - a).normalized()
        chrome.append(P.tube("ShockRod", [tuple(a), tuple(a + d * 0.2)], 0.008, M["Chrome"]))
        black.append(P.tube("ShockBody", [tuple(a + d * 0.18), tuple(b - d * 0.02)], 0.019, M["EngineDark"]))
        other.append(P.helix("ShockSpring", tuple(a + d * 0.05), tuple(b - d * 0.07), 0.026, 0.0045, 9, M["Spring"]))
        for e in (a, b):
            black.append(P.cyl("ShockEye", 0.016, 0.03, tuple(e), M["Rubber"]))
    # the engine: crankcase, covers, the finned barrel and head inclined forward, carburettor, starter, plug
    engine.append(P.loft("Crankcase", [(-0.17, 0.09, 0.36, 0.11, 0.12, 2.2, 2.6), (-0.08, 0.115, 0.35, 0.14, 0.14, 2.4, 2.8),
                                       (0.08, 0.12, 0.35, 0.15, 0.14, 2.4, 2.8), (0.2, 0.11, 0.37, 0.13, 0.12, 2.4, 2.6),
                                       (0.27, 0.07, 0.4, 0.09, 0.08, 2.2, 2.2)], M["EngineAlu"], n=36))
    cc = K.lathe("ClutchCover", [(0.0, -0.05), (0.06, -0.048), (0.1, -0.038), (0.115, -0.02), (0.118, 0.0)], 48, 'Y', [M["EngineAlu"]])
    cc.location = (0.08, -0.115, 0.36)
    engine.append(cc)
    for k in range(10):
        a = 2 * math.pi * k / 10
        chrome.append(P.cyl("CoverBolt", 0.006, 0.01, (0.08 + math.cos(a) * 0.105, -0.155, 0.36 + math.sin(a) * 0.105), M["Chrome"], segs=6))
    chrome.append(P.cyl("OilCap", 0.016, 0.02, (0.0, -0.15, 0.47), M["Chrome"], axis='Z', segs=12))
    mc = K.lathe("MagnetoCover", [(0.0, 0.035), (0.06, 0.033), (0.085, 0.023), (0.092, 0.0)], 48, 'Y', [M["EngineAlu"]])
    mc.location = (-0.06, 0.118, 0.37)
    engine.append(mc)
    spc = P.loft("SprocketCover", [(0.0, 0.01, 0.33, 0.04, 0.04, 2.2, 2.2), (0.06, 0.016, 0.33, 0.055, 0.05, 2.4, 2.4), (0.13, 0.01, 0.34, 0.035, 0.035, 2.2, 2.2)], M["Plastic"], n=24)
    spc.location.y = 0.142
    black.append(spc)
    base = Vector((0.2, 0, 0.47))
    cd = Vector((math.sin(math.radians(68)), 0, math.cos(math.radians(68))))
    tilt = (0, math.radians(68), 0)
    engine.append(P.cyl("Barrel", 0.05, 0.14, tuple(base + cd * 0.07), M["EngineDark"], rot=tilt, segs=24))
    for k in range(11):
        sz = 0.17 - 0.004 * abs(k - 4)
        engine.append(P.box("Fin", (0.004, sz, sz * 0.92), tuple(base + cd * (0.012 + k * 0.012)), M["EngineDark"], rot=tilt, bevel=0.0015, segs=1))
    hd = base + cd * 0.17
    engine.append(P.box("CylHead", (0.07, 0.165, 0.15), tuple(hd), M["EngineAlu"], rot=tilt, bevel=0.015))
    for k in range(4):
        engine.append(P.box("HeadFin", (0.004, 0.17, 0.14), tuple(hd + cd * (-0.03 + k * 0.02)), M["EngineAlu"], rot=tilt, bevel=0.0015, segs=1))
    engine.append(P.box("ValveCover", (0.04, 0.12, 0.11), tuple(hd + cd * 0.05), M["EngineAlu"], rot=tilt, bevel=0.012))
    black.append(P.tube("PlugCap", [tuple(hd + Vector((0, 0, 0.08))), tuple(hd + Vector((-0.04, -0.02, 0.12)))], 0.011, M["Rubber"]))
    black.append(P.tube("HTLead", [tuple(hd + Vector((-0.04, -0.02, 0.12))), (0.15, -0.06, 0.72), (0.05, -0.08, 0.7)], 0.004, M["Rubber"], smooth_pts=5))
    engine.append(P.box("Carburettor", (0.07, 0.06, 0.06), (0.14, 0.0, 0.62), M["EngineAlu"], bevel=0.012))
    black.append(P.tube("Intake", [(0.11, 0, 0.62), (0.0, 0, 0.64), (-0.08, 0, 0.62)], 0.022, M["Rubber"], smooth_pts=4))
    black.append(P.loft("AirBox", [(-0.08, 0.07, 0.64, 0.06, 0.06, 2.6, 2.6), (-0.18, 0.085, 0.64, 0.07, 0.07, 3.0, 3.0), (-0.28, 0.07, 0.65, 0.06, 0.06, 2.6, 2.6)], M["Plastic"], n=24))
    engine.append(P.cyl("Starter", 0.03, 0.12, (0.03, 0.02, 0.53), M["EngineDark"], rot=(math.pi / 2, 0, 0)))
    # the exhaust: the header out under the head, down under the engine, up into the silencer with its heat shield
    hdr = [tuple(hd + Vector((0.04, -0.02, -0.06))), (0.36, -0.04, 0.36), (0.3, -0.07, 0.2), (0.1, -0.1, 0.17), (-0.15, -0.14, 0.2),
           (-0.32, -0.16, 0.28)]
    chrome.append(P.tube("Header", hdr, 0.019, M["Chrome"], smooth_pts=6))
    sil_a, sil_b = Vector((-0.32, -0.165, 0.28)), Vector((-0.86, -0.17, 0.42))
    sd = (sil_b - sil_a).normalized()
    sil = K.lathe("Silencer", [(0.0, 0.0), (0.03, 0.0), (0.05, 0.06), (0.058, 0.14), (0.058, 0.44), (0.052, 0.53), (0.035, 0.55), (0.0, 0.55)], 40, 'X', [M["Chrome"]])
    P.place(sil, sil_a, sd)
    chrome.append(sil)
    tip = K.lathe("SilencerTip", [(0.02, 0.0), (0.025, 0.0), (0.025, 0.03), (0.02, 0.03)], 24, 'X', [M["EngineDark"]])
    P.place(tip, sil_b + sd * 0.01, sd)
    black.append(tip)
    hs = K.lathe("HeatShield", [(0.064, 0.12), (0.067, 0.16), (0.067, 0.36), (0.064, 0.4)], 40, 'X', [M["BlackGloss"]])
    bmh = bmesh.new()
    bmh.from_mesh(hs.data)                                     # (the shield covers the outer, upper side only)
    bmesh.ops.delete(bmh, geom=[f for f in bmh.faces if f.calc_center_median().y > 0.02 or f.calc_center_median().z < -0.03], context='FACES')
    bmh.to_mesh(hs.data)
    hs.modifiers.new("S", 'SOLIDIFY').thickness = 0.002
    P.place(hs, sil_a, sd)
    black.append(hs)
    for k in range(3):
        chrome.append(P.cyl("ShieldBolt", 0.007, 0.01, tuple(sil_a + sd * (0.18 + k * 0.1) + Vector((0, -0.066, 0.005))), M["Chrome"], segs=6))
    # the chain: links along both runs and round the sprockets; the front sprocket; the chain guard over the top run
    fs, fr = Vector((0.07, 0.12, 0.34)), 0.042
    rs, rr = Vector((AX_R, 0.12, RR)), 0.105
    ring = [(rs.x + math.cos(2 * math.pi * k / 90) * rr, rs.z + math.sin(2 * math.pi * k / 90) * rr) for k in range(90)]
    ring += [(fs.x + math.cos(2 * math.pi * k / 40) * fr, fs.z + math.sin(2 * math.pi * k / 40) * fr) for k in range(40)]
    ring.sort()
    hull = []                                             # (the chain's line: the outline round both sprockets)
    for half in (ring, list(reversed(ring))):
        h = []
        for q in half:
            while len(h) >= 2 and (h[-1][0] - h[-2][0]) * (q[1] - h[-2][1]) - (h[-1][1] - h[-2][1]) * (q[0] - h[-2][0]) <= 0:
                h.pop()
            h.append(q)
        hull += h[:-1]
    hull.append(hull[0])
    path = [Vector((x, 0.12, z)) for x, z in hull]
    pts = K.resample([(p.x, p.z) for p in path], 150)
    for k in range(len(pts) - 1):
        a, b = pts[k], pts[k + 1]
        mid = (a + b) / 2
        rot = math.atan2(b.y - a.y, b.x - a.x)
        other.append(P.box("ChainLink", (0.013, 0.012 if k % 2 else 0.008, 0.008), (mid.x, 0.12, mid.y), M["Steel"], rot=(0, -rot, 0)))
    other.append(P.sprocket("FrontSprocket", tuple(fs), fr, 14, 0.006, M["Steel"]))
    guard = []
    for k in range(13):
        t = k / 12
        p = rs.lerp(fs, 0.1 + 0.75 * t)
        guard.append([(p.x, 0.1, p.z + rr * (1 - t) + fr * t + 0.02), (p.x, 0.145, p.z + rr * (1 - t) + fr * t + 0.035), (p.x, 0.15, p.z + rr * (1 - t) + fr * t - 0.01)])
    cg = P.grid("ChainGuard", guard, M["BlackGloss"])
    cg.modifiers.new("S", 'SOLIDIFY').thickness = 0.003
    black.append(cg)
    # the tank: a sculpted loft with knee recesses, its filler cap, rubber knee pads
    tank = P.loft("Tank", [(0.31, 0.06, 0.93, 0.04, 0.06, 2.2, 2.2), (0.25, 0.12, 0.92, 0.075, 0.1, 2.4, 2.4),
                           (0.15, 0.15, 0.91, 0.09, 0.12, 2.6, 2.6), (0.04, 0.145, 0.895, 0.09, 0.12, 2.6, 2.6),
                           (-0.05, 0.12, 0.875, 0.075, 0.1, 2.4, 2.6), (-0.1, 0.09, 0.85, 0.05, 0.07, 2.2, 2.4)], M["Paint"], n=40)
    for v in tank.data.vertices:                                # knee recesses: the flanks drawn in low at the back
        if -0.08 < v.co.x < 0.12 and v.co.z < 0.9 and abs(v.co.y) > 0.07:
            k = 0.88 + 0.12 * min(1.0, abs(v.co.x - 0.02) / 0.1)
            v.co.y *= k
    painted.append(tank)
    chrome.append(P.cyl("FillerCap", 0.034, 0.012, (0.13, 0, 1.03), M["Chrome"], axis='Z', segs=32))
    chrome.append(P.cyl("FillerHinge", 0.008, 0.02, (0.168, 0, 1.03), M["Chrome"]))
    for s in (1, -1):
        pad = P.box("KneePad", (0.12, 0.008, 0.07), (0.0, s * 0.128, 0.86), M["Rubber"], rot=(s * math.radians(-12), 0, 0), bevel=0.02)
        black.append(pad)
    # the seat: one long cushion stepping up for the pillion, red piping and stitching along its edges
    seat = P.loft("Seat", [(-0.06, 0.08, 0.81, 0.02, 0.04, 2.2, 3.0), (-0.12, 0.135, 0.815, 0.035, 0.05, 2.6, 3.0),
                           (-0.3, 0.145, 0.815, 0.04, 0.055, 2.8, 3.0), (-0.45, 0.13, 0.83, 0.045, 0.055, 2.8, 3.0),
                           (-0.65, 0.12, 0.845, 0.045, 0.05, 2.6, 3.0), (-0.76, 0.08, 0.84, 0.035, 0.04, 2.2, 3.0)], M["SeatVinyl"], n=40)
    other.append(seat)
    for s in (1, -1):
        stitch = []
        for k in range(30):
            x = -0.1 - 0.62 * k / 29
            w = K.cr([(-0.06, 0.08), (-0.12, 0.135), (-0.3, 0.145), (-0.45, 0.13), (-0.65, 0.12), (-0.76, 0.08)], x)
            z = K.cr([(-0.06, 0.81), (-0.3, 0.815), (-0.45, 0.83), (-0.65, 0.845), (-0.76, 0.84)], x)
            stitch.append((x, s * (w - 0.012), z + 0.03))
        other.append(P.tube("Stitch", stitch, 0.0025, M["Stitch"]))
    other.append(P.tube("SeatPiping", [(-0.42, 0.13, 0.875), (-0.42, -0.13, 0.875)], 0.004, M["Stitch"], smooth_pts=0))
    # the side panels under the seat, the tail cowl, the tail lamp, the rear mudguard and plate
    for s in (1, -1):
        rows = []
        for k in range(9):
            x = -0.06 - 0.3 * k / 8
            zt = 0.78 - 0.02 * k / 8
            zb = 0.56 + 0.1 * (k / 8) ** 1.5
            rows.append([(x, s * (0.115 + 0.012 * math.sin(math.pi * j / 6)), zb + (zt - zb) * j / 6) for j in range(7)])
        sp = P.grid("SidePanel", rows, M["Paint"])
        sp.modifiers.new("S", 'SOLIDIFY').thickness = 0.004
        K.smooth(sp, 40)
        painted.append(sp)
        black.append(P.box("PanelLouvre", (0.08, 0.004, 0.004), (-0.18, s * 0.13, 0.67), M["Plastic"]))
        black.append(P.box("PanelLouvre", (0.08, 0.004, 0.004), (-0.18, s * 0.13, 0.65), M["Plastic"]))
    tail = P.loft("TailCowl", [(-0.38, 0.12, 0.74, 0.04, 0.07, 2.4, 2.4), (-0.6, 0.11, 0.765, 0.04, 0.06, 2.4, 2.4),
                               (-0.8, 0.08, 0.78, 0.035, 0.045, 2.2, 2.2), (-0.86, 0.05, 0.78, 0.03, 0.035, 2.0, 2.0)], M["Paint"], n=32)
    painted.append(tail)
    tl = P.loft("TailLamp", [(-0.855, 0.065, 0.775, 0.03, 0.03, 2.4, 2.4), (-0.89, 0.06, 0.772, 0.026, 0.026, 2.4, 2.4)], M["Taillight"], n=28)
    rear_ind = {}
    for s, sl in ((1, "L"), (-1, "R")):
        other.append(P.tube("IndicatorStalk", [(-0.8, s * 0.06, 0.73), (-0.81, s * 0.16, 0.73)], 0.008, M["BlackGloss"]))
        li = P.loft("Indicator_%s_R" % sl, [(0.02, 0.018, 0.0, 0.014, 0.014, 2.0, 2.0), (0.0, 0.026, 0.0, 0.022, 0.022, 2.2, 2.2),
                                            (-0.03, 0.022, 0.0, 0.018, 0.018, 2.2, 2.2)], M["Indicator"], n=20)
        li.location = (-0.81, s * 0.175, 0.73)
        rear_ind[sl] = li
    rows = []
    for k in range(21):
        a = math.radians(70 + 95 * k / 20)
        r = RR + 0.06
        rows.append([(AX_R + math.cos(a) * r, y, RR + math.sin(a) * r) for y in [-0.06 + 0.12 * j / 8 for j in range(9)]])
    rg = P.grid("RearGuard", rows, M["Plastic"])
    rg.modifiers.new("S", 'SOLIDIFY').thickness = 0.004
    K.smooth(rg, 40)
    black.append(rg)
    black.append(P.box("PlateHolder", (0.01, 0.2, 0.13), (-0.9, 0, 0.6), M["Plastic"], rot=(0, math.radians(10), 0), bevel=0.01))
    pm = {"PlateWhite": M["PlateWhite"], "PlateText": M["PlateText"]}
    pl, tx = K.plate(pm, "PlateRear", "TN 38 BX 2741", Vector((-0.908, 0, 0.6)), Vector((-1, 0, 0)), w=0.19, h=0.11)
    other += [pl, tx]
    chrome.append(P.box("PlateLamp", (0.03, 0.05, 0.02), (-0.89, 0, 0.67), M["Chrome"], bevel=0.005))
    # the grab rails (cast alloy loops each side), the saree guard on the left, the rear brake rod and arm
    for s in (1, -1):
        chrome.append(P.tube("GrabRail", [(-0.38, s * 0.13, 0.8), (-0.5, s * 0.16, 0.86), (-0.72, s * 0.14, 0.86), (-0.8, s * 0.1, 0.84)],
                             0.011, M["EngineAlu"], smooth_pts=6))
    sg = [(-0.36, 0.2, 0.5), (-0.44, 0.22, 0.66), (-0.62, 0.22, 0.7), (-0.82, 0.21, 0.6), (-0.86, 0.2, 0.42)]
    chrome.append(P.tube("SareeGuard", sg, 0.008, M["Chrome"], smooth_pts=6))
    chrome.append(P.tube("SareeGuard", [(-0.44, 0.22, 0.66), (-0.5, 0.21, 0.4), (-0.63, 0.2, 0.36)], 0.007, M["Chrome"], smooth_pts=4))
    chrome.append(P.tube("SareeStay", [(-0.62, 0.22, 0.7), (-0.6, 0.12, 0.77)], 0.007, M["Chrome"]))
    rows = []
    for k in range(10):
        t = k / 9
        p = Vector(sg[1]).lerp(Vector(sg[3]), t)
        rows.append([(p.x, 0.215, p.z - 0.008), (p.x, 0.215, p.z - 0.09 - 0.03 * math.sin(math.pi * t))])
    sgp = P.grid("SareePlate", rows, M["Plastic"])
    sgp.modifiers.new("S", 'SOLIDIFY').thickness = 0.003
    black.append(sgp)
    engine.append(K.lathe("DrumPlate", [(0.0, -0.08), (0.09, -0.08), (0.092, -0.07), (0.0, -0.07)], 48, 'Y', [M["EngineAlu"]]))
    engine[-1].location = (AX_R, 0, RR)
    black.append(P.tube("BrakeArm", [(AX_R + 0.02, -0.09, RR + 0.04), (AX_R + 0.06, -0.09, RR + 0.11)], 0.008, M["EngineDark"]))
    chrome.append(P.tube("BrakeRod", [(AX_R + 0.06, -0.09, RR + 0.11), (-0.02, -0.11, 0.3)], 0.004, M["Steel"]))
    # the footrests, the gear lever (left), the brake pedal (right), the pillion pegs, both stands (up)
    for s in (1, -1):
        black.append(P.tube("PegBracket", [(-0.02, s * 0.1, 0.33), (-0.02, s * 0.16, 0.32)], 0.012, M["FrameBlack"]))
        other.append(P.cyl("Footpeg", 0.016, 0.09, (-0.02, s * 0.2, 0.32), M["Rubber"], segs=12))
        for k in range(5):
            other.append(P.cyl("PegRib", 0.0175, 0.004, (-0.02, s * (0.165 + k * 0.016), 0.32), M["Rubber"], segs=12))
        frame.append(P.tube("PillionHanger", [(-0.3, s * 0.1, 0.6), (-0.36, s * 0.14, 0.44)], 0.012, M["EngineAlu"]))
        other.append(P.cyl("PillionPeg", 0.014, 0.07, (-0.36, s * 0.19, 0.43), M["Rubber"], segs=12))
    black.append(P.tube("GearLever", [(0.04, 0.15, 0.35), (0.12, 0.17, 0.31), (0.17, 0.18, 0.3)], 0.007, M["EngineDark"], smooth_pts=3))
    other.append(P.cyl("GearToe", 0.011, 0.05, (0.17, 0.2, 0.3), M["Rubber"], segs=10))
    black.append(P.tube("BrakePedal", [(-0.04, -0.15, 0.32), (0.08, -0.17, 0.28), (0.16, -0.18, 0.28)], 0.008, M["EngineDark"], smooth_pts=3))
    other.append(P.box("PedalPad", (0.04, 0.05, 0.012), (0.17, -0.19, 0.29), M["Rubber"], bevel=0.004))
    black.append(P.tube("SideStand", [(-0.05, 0.12, 0.3), (-0.25, 0.2, 0.2)], 0.012, M["FrameBlack"]))
    black.append(P.box("StandFoot", (0.04, 0.03, 0.01), (-0.26, 0.2, 0.19), M["FrameBlack"]))
    for s in (1, -1):
        black.append(P.tube("CentreStand", [(-0.12, s * 0.09, 0.33), (-0.38, s * 0.13, 0.17)], 0.013, M["FrameBlack"]))
    black.append(P.tube("CentreStandBar", [(-0.38, 0.13, 0.17), (-0.38, -0.13, 0.17)], 0.012, M["FrameBlack"]))
    # a crash guard in front of the engine (as most here are fitted), the battery and tool box behind the panels
    chrome.append(P.tube("CrashGuard", [(0.3, 0.06, 0.75), (0.36, 0.2, 0.62), (0.34, 0.24, 0.4), (0.26, 0.18, 0.3)], 0.013, M["Chrome"], smooth_pts=6))
    chrome.append(P.tube("CrashGuard", [(0.3, -0.06, 0.75), (0.36, -0.2, 0.62), (0.34, -0.24, 0.4), (0.26, -0.18, 0.3)], 0.013, M["Chrome"], smooth_pts=6))
    black.append(P.box("Battery", (0.1, 0.07, 0.12), (-0.2, 0.0, 0.52), M["Plastic"], bevel=0.008))
    out = [P.join(painted, "Body"), P.join(frame, "Frame"), P.join(engine, "Engine"), P.join(chrome, "Brightwork"),
           P.join(black, "Blackwork"), P.join(other, "Details"), tl, rear_ind["L"], rear_ind["R"]]
    return out


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = materials()
    root = bpy.data.objects.new("Motorcycle", None)
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
    print("MOTO done: %d objects, %d triangles" % (len([o for o in bpy.data.objects if o.type == 'MESH']), tris), flush=True)
    if "--export" in args:
        out = args[args.index("--export") + 1]
        bpy.ops.object.select_all(action='DESELECT')
        for o in bpy.data.objects:
            if not o.name.startswith("Preview"):
                o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_yup=True,
                                  export_apply=True, export_image_format='JPEG')
        print("MOTO exported %s (%.1f MB)" % (out, os.path.getsize(out) / 1e6), flush=True)
    if "--preview" in args:
        d = args[args.index("--preview") + 1]
        os.makedirs(d, exist_ok=True)
        views = {"front34": (35, 10), "side_l": (90, 3), "side_r": (270, 3), "rear34": (150, 12), "front": (0, 5), "rear": (180, 5)}
        K.previews(os.path.join(d, "moto"), target=Vector((0, 0, 0.55)), dist=3.4, views=views)
        cam = bpy.data.objects["PreviewCam"]
        sc = bpy.context.scene
        for nm, loc, tgt in (("engine", (0.25, -1.0, 0.45), (0.1, 0, 0.42)), ("wheel", (0.85, 0.75, 0.35), (AX_F, 0.05, RF)),
                             ("bars", (-0.35, 0.0, 1.35), (0.25, 0, 1.0))):
            cam.location = loc
            cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(d, "moto_%s.png" % nm)
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
