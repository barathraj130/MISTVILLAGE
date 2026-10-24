"""
Detailed two-wheelers for the rider scenes (tools/rider_real.py): a commuter motorcycle and a step-through scooter in
the fleet's lofted style (tools/fleet.py), with round tubes, real wheels, the engine, exhaust, chain, coil-spring
shocks, forks, switchgear, levers and cables, lamps and indicators. +X is forward, +Y the rider's left, Z up, the
wheels on the ground at z = 0.

    build(kind, root, paint) -> (wheel empties, FIT[kind])
FIT says where a rider goes on each: hip joints' midpoint on the seat, grip centres (x, ±y, z), where the left foot
rests (footpeg / floor; the right is mirrored), the wheel radius and the forward lean.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fleet as F  # noqa: E402

FIT = {"motorcycle": dict(hip=(-0.17, 0.0, 0.985), grip=(0.42, 0.36, 1.08), foot=(0.03, 0.2, 0.32), r=0.3, lean=18.0),
       "scooter": dict(hip=(-0.17, 0.0, 0.945), grip=(0.335, 0.345, 1.05), foot=(0.14, 0.13, 0.338), r=0.24,
                       lean=6.0)}


# ---- helpers ----
def tube(name, pts, r, mat, res=8):
    """A round tube along the points (a smooth curve through them when there are more than two)."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = r
    cu.bevel_resolution = 4
    cu.use_fill_caps = True
    cu.resolution_u = res
    if len(pts) > 2:
        sp = cu.splines.new('BEZIER')
        sp.bezier_points.add(len(pts) - 1)
        for bp, p in zip(sp.bezier_points, pts):
            bp.co = p
            bp.handle_left_type = bp.handle_right_type = 'AUTO'
    else:
        sp = cu.splines.new('POLY')
        sp.points.add(1)
        for pt, p in zip(sp.points, pts):
            pt.co = (*p, 1.0)
    ob = F.link(bpy.data.objects.new(name, cu))
    cu.materials.append(mat)
    return ob


def helix(name, a, b, coil_r, wire_r, turns, mat):
    """A coil spring from a to b."""
    a, b = Vector(a), Vector(b)
    ax = (b - a).normalized()
    u = ax.orthogonal().normalized()
    v = ax.cross(u)
    n = int(turns * 16)
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = wire_r
    cu.bevel_resolution = 2
    sp = cu.splines.new('POLY')
    sp.points.add(n)
    for i, pt in enumerate(sp.points):
        t = i / n
        th = 2 * math.pi * turns * t
        p = a.lerp(b, t) + (u * math.cos(th) + v * math.sin(th)) * coil_r
        pt.co = (*p, 1.0)
    ob = F.link(bpy.data.objects.new(name, cu))
    cu.materials.append(mat)
    return ob


def egg(name, c, scale, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.0, location=c, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    o.data.materials.append(mat)
    F.smooth(o)
    return o


def guard(name, axle, r, w, a0, a1, mat):
    """A mudguard: a curved strip round the wheel from angle a0 to a1 (0 = straight up, + = forward)."""
    prof = [(r, -w), (r + 0.012, -w * 0.9), (r + 0.017, 0.0), (r + 0.012, w * 0.9), (r, w), (r - 0.004, 0.0), (r, -w)]
    o = F.lathe(name, prof, mat, 40, arc=(a0, a1))
    o.location = axle
    return o


def along_x(o, loc, tilt=0.0, back=True):
    """Lay a lathed part (axis Y) along X: its +Y end to the rear (back) or the front, tilted up by tilt."""
    o.rotation_euler = (tilt, 0, math.pi / 2 if back else -math.pi / 2)
    o.location = loc
    return o


def wheel(name, x, R, W, M):
    before = set(bpy.data.objects)
    w = F.wheel(name, (x, 0, R), R, W, M, True, spokes=5)
    for o in set(bpy.data.objects) - before:
        if o.name.startswith("Nut"):                         # a car's lug nuts: a bike's hub has none
            bpy.data.objects.remove(o, do_unlink=True)
        elif o is not w and o.parent is None:                # (fleet leaves the spokes loose: hang them on the hub)
            o.parent = w
    return w


def lerp(a, b, t):
    return Vector(a).lerp(Vector(b), t)


# ---- the motorcycle: a 125 cc commuter ----
def motorcycle(M):
    R = 0.3
    FX, RX = 0.66, -0.62
    wf, wr = wheel("Wheel_F", FX, R, 0.09, M), wheel("Wheel_R", RX, R, 0.11, M)
    guard("FrontGuard", (FX, 0, R), R + 0.04, 0.055, -1.1, 0.9, M["paint"])
    guard("RearGuard", (RX, 0, R), R + 0.035, 0.06, -1.5, -0.25, M["black"])
    # frame: a single cradle of round tubes, the backbone under the tank, seat rails and struts
    head = (0.46, 0, 0.96)
    for pts in ([head, (0.36, 0, 0.6), (0.27, 0, 0.3), (0.1, 0, 0.22), (-0.1, 0, 0.24), (-0.14, 0, 0.4)],
                [head, (0.2, 0, 0.84), (-0.2, 0, 0.77)]):
        tube("Frame", pts, 0.022, M["frame"])
    for s in (1, -1):
        tube("SeatRail", [(-0.2, s * 0.09, 0.77), (-0.82, s * 0.08, 0.79)], 0.014, M["frame"])
        tube("Strut", [(-0.14, s * 0.09, 0.4), (-0.56, s * 0.09, 0.77)], 0.014, M["frame"])
        tube("Swingarm", [(-0.14, s * 0.09, 0.38), (RX, s * 0.09, R)], 0.021, M["frame"])
    tube("HeadTube", [(0.48, 0, 0.9), (0.45, 0, 1.0)], 0.032, M["frame"])
    # engine: crankcase, the side covers, the finned cylinder inclined forward, head, carburettor
    F.loft("Crankcase", [(-0.12, 0.11, 0.22, 0.46, 0), (0.05, 0.13, 0.2, 0.5, 0), (0.22, 0.12, 0.22, 0.48, 0),
                         (0.3, 0.09, 0.27, 0.42, 0)], M["engine"], n_top=3.0, n_bot=3.0, segs=24)
    F.lathe("ClutchCover", [(0.105, 0.0), (0.1, -0.025), (0.08, -0.04), (0.0, -0.046)], M["engine"], 40).location = (0.12, -0.125, 0.36)
    F.lathe("MagnetoCover", [(0.085, 0.0), (0.08, 0.022), (0.06, 0.034), (0.0, 0.038)], M["engine"], 40).location = (-0.02, 0.125, 0.36)
    base, d = Vector((0.2, 0, 0.46)), Vector((math.sin(math.radians(15)), 0, math.cos(math.radians(15))))
    tilt = (0, math.radians(15), 0)
    F.box("Barrel", base + d * 0.1, (0.09, 0.11, 0.2), M["steel"], bev=0.01, rot=tilt)
    for k in range(9):
        F.box("Fin", base + d * (0.02 + k * 0.021), (0.17, 0.2, 0.007), M["engine"], bev=0.002, rot=tilt)
    F.box("Head", base + d * 0.225, (0.15, 0.17, 0.06), M["engine"], bev=0.015, rot=tilt)
    tube("PlugCap", [tuple(base + d * 0.17 + Vector((-0.07, 0, 0))), tuple(base + d * 0.2 + Vector((-0.12, 0, 0.02)))],
         0.012, M["black"])
    F.box("Carburettor", (0.04, 0.0, 0.6), (0.1, 0.1, 0.08), M["engine"], bev=0.015)
    F.box("AirBox", (-0.12, 0.0, 0.62), (0.16, 0.16, 0.14), M["black"], bev=0.02)
    # exhaust: the header curving down under the engine, the muffler rising to the rear
    tube("Header", [(0.3, -0.03, 0.5), (0.37, -0.06, 0.37), (0.3, -0.1, 0.24), (0.0, -0.14, 0.21), (-0.24, -0.17, 0.27)],
         0.021, M["chrome"])
    along_x(F.lathe("Muffler", [(0.0, -0.3), (0.035, -0.3), (0.055, -0.24), (0.06, 0.2), (0.048, 0.29), (0.025, 0.3),
                                (0.0, 0.3)], M["chrome"], 32), (-0.5, -0.17, 0.33), tilt=0.12)
    along_x(F.lathe("HeatShield", [(0.064, -0.18), (0.066, 0.0), (0.064, 0.14)], M["black"], 32, arc=(-2.2, -0.6)),
            (-0.5, -0.17, 0.33), tilt=0.12)
    # chain drive on the left: sprockets, the two runs, the guard
    F.cyl("Sprocket", (RX, 0.1, R), 0.1, 0.008, M["steel"], rot=(math.pi / 2, 0, 0), verts=36)
    F.cyl("Sprocket", (0.0, 0.1, 0.3), 0.042, 0.008, M["steel"], rot=(math.pi / 2, 0, 0), verts=20)
    tube("Chain", [(0.0, 0.1, 0.342), (RX, 0.1, R + 0.1)], 0.007, M["steel"])
    tube("Chain", [(0.0, 0.1, 0.258), (RX, 0.1, R - 0.1)], 0.007, M["steel"])
    F.beam("ChainGuard", (0.04, 0.118, 0.36), (RX + 0.06, 0.118, R + 0.12), 0.012, 0.06, M["black"])
    # rear shocks: damper and coil spring
    for s in (1, -1):
        a, b = Vector((-0.58, s * 0.115, 0.33)), Vector((-0.5, s * 0.115, 0.74))
        tube("Damper", [tuple(a), tuple(b)], 0.013, M["chrome"])
        helix("Spring", lerp(a, b, 0.15), lerp(a, b, 0.85), 0.03, 0.006, 9, M["spring"])
        egg("ShockEye", a, (0.022, 0.02, 0.022), M["black"])
        egg("ShockEye", b, (0.022, 0.02, 0.022), M["black"])
    # forks: aluminium sliders, chrome stanchions, the clamps
    for s in (1, -1):
        axle, top = Vector((FX, s * 0.085, R)), Vector((0.47, s * 0.085, 1.0))
        tube("ForkSlider", [tuple(lerp(axle, top, -0.03)), tuple(lerp(axle, top, 0.42))], 0.027, M["engine"])
        tube("Stanchion", [tuple(lerp(axle, top, 0.4)), tuple(lerp(axle, top, 0.97))], 0.018, M["chrome"])
    F.box("LowerClamp", (0.5, 0, 0.88), (0.06, 0.22, 0.035), M["black"], bev=0.01)
    F.box("TopClamp", (0.47, 0, 1.0), (0.07, 0.22, 0.025), M["black"], bev=0.01)
    # headlamp in its chrome bezel, the small visor above it, twin dials
    along_x(F.lathe("Bezel", [(0.08, -0.05), (0.09, 0.0), (0.086, 0.03), (0.076, 0.04)], M["chrome"], 40),
            (0.62, 0, 0.93), back=False)
    along_x(F.lathe("Headlamp", [(0.076, 0.035), (0.05, 0.05), (0.0, 0.056)], M["head"], 40), (0.62, 0, 0.93), back=False)
    F.loft("Visor", [(0.53, 0.09, 0.99, 1.05, 0), (0.62, 0.11, 0.98, 1.07, 0), (0.69, 0.07, 1.0, 1.04, 0)], M["paint"],
           n_top=3.0, n_bot=3.0, segs=20)
    F.box("Cluster", (0.53, 0, 1.1), (0.06, 0.17, 0.07), M["black"], bev=0.015, rot=(0, math.radians(-35), 0))
    for s in (1, -1):
        F.cyl("Dial", (0.51, s * 0.042, 1.128), 0.03, 0.006, M["lens"], rot=(0, math.radians(-37), 0), verts=28)
    # handlebar, grips, switchgear, levers and cables, mirrors
    tube("Handlebar", [(0.42, 0.41, 1.08), (0.43, 0.3, 1.08), (0.47, 0.2, 1.06), (0.48, 0.0, 1.04), (0.47, -0.2, 1.06),
                       (0.43, -0.3, 1.08), (0.42, -0.41, 1.08)], 0.011, M["chrome"])
    for s in (1, -1):
        tube("Grip", [(0.428, s * 0.3, 1.08), (0.42, s * 0.415, 1.08)], 0.017, M["rubber"])
        egg("BarEnd", (0.42, s * 0.42, 1.08), (0.016, 0.01, 0.016), M["chrome"])
        F.box("Switches", (0.435, s * 0.272, 1.078), (0.05, 0.04, 0.045), M["black"], bev=0.01)
        tube("Lever", [(0.452, s * 0.28, 1.086), (0.476, s * 0.36, 1.08), (0.47, s * 0.41, 1.075)], 0.0055, M["chrome"])
        tube("Cable", [(0.45, s * 0.27, 1.09), (0.56, s * 0.22, 1.1), (0.6, s * 0.12, 0.98), (0.5, s * 0.07, 0.84)],
             0.004, M["black"])
        tube("MirrorStem", [(0.44, s * 0.25, 1.09), (0.42, s * 0.28, 1.2), (0.4, s * 0.31, 1.31)], 0.007, M["chrome"])
        egg("Mirror", (0.395, s * 0.322, 1.335), (0.02, 0.07, 0.05), M["black"])
        egg("MirrorGlass", (0.376, s * 0.322, 1.335), (0.005, 0.062, 0.043), M["mirror"])
        tube("IndicatorStalk", [(0.6, s * 0.07, 0.92), (0.62, s * 0.165, 0.92)], 0.008, M["black"])
        egg("Indicator", (0.627, s * 0.18, 0.92), (0.03, 0.02, 0.018), M["amber"])
    # tank with knee pads and filler cap, seat, side panel, tail with its lamp, grab rail, plate, rear indicators
    F.loft("Tank", [(-0.05, 0.12, 0.76, 0.9, 0), (0.1, 0.17, 0.72, 0.99, 0), (0.3, 0.17, 0.74, 1.01, 0),
                    (0.45, 0.1, 0.8, 0.97, 0)], M["paint"], n_top=3.0, n_bot=4.0, segs=28)
    for s in (1, -1):
        egg("KneePad", (0.1, s * 0.165, 0.84), (0.09, 0.012, 0.055), M["rubber"])
    F.cyl("FuelCap", (0.22, 0, 1.006), 0.045, 0.02, M["chrome"], verts=28)
    F.loft("Seat", [(-0.62, 0.1, 0.78, 0.86, 0), (-0.45, 0.15, 0.79, 0.9, 0), (-0.15, 0.16, 0.8, 0.92, 0),
                    (0.02, 0.13, 0.82, 0.93, 0)], M["seat"], n_top=3.0, n_bot=6.0, segs=28)
    F.loft("SidePanel", [(-0.4, 0.13, 0.56, 0.78, 0), (-0.12, 0.15, 0.55, 0.8, 0), (0.0, 0.12, 0.6, 0.78, 0)],
           M["paint"], n_top=4.0, n_bot=4.0, segs=20)
    F.loft("Tail", [(-0.87, 0.05, 0.72, 0.8, 0), (-0.7, 0.1, 0.7, 0.84, 0), (-0.55, 0.13, 0.68, 0.84, 0)], M["paint"],
           n_top=3.0, n_bot=4.0, segs=20)
    egg("TailLamp", (-0.865, 0, 0.775), (0.03, 0.08, 0.035), M["tail"])
    tube("GrabRail", [(-0.42, 0.15, 0.83), (-0.6, 0.16, 0.86), (-0.76, 0.13, 0.86), (-0.8, 0.0, 0.86),
                      (-0.76, -0.13, 0.86), (-0.6, -0.16, 0.86), (-0.42, -0.15, 0.83)], 0.012, M["black"])
    tube("PlateBracket", [(-0.78, 0, 0.72), (-0.82, 0, 0.62)], 0.01, M["black"])
    F.box("Plate", (-0.825, 0, 0.6), (0.01, 0.2, 0.12), M["plate"], bev=0.003, rot=(0, math.radians(12), 0))
    for s in (1, -1):
        tube("IndicatorStalk", [(-0.78, s * 0.08, 0.74), (-0.8, s * 0.155, 0.74)], 0.008, M["black"])
        egg("Indicator", (-0.805, s * 0.17, 0.74), (0.03, 0.02, 0.018), M["amber"])
    # footpegs (rider, pillion), gear lever on the left, brake pedal and kick lever on the right
    for s in (1, -1):
        tube("Footpeg", [(0.03, s * 0.12, 0.32), (0.03, s * 0.25, 0.32)], 0.018, M["rubber"])
        tube("PegBracket", [(0.0, s * 0.1, 0.27), (0.03, s * 0.13, 0.32)], 0.012, M["frame"])
        tube("PillionPeg", [(-0.42, s * 0.14, 0.42), (-0.42, s * 0.23, 0.42)], 0.014, M["rubber"])
    tube("GearLever", [(0.05, 0.15, 0.3), (0.12, 0.19, 0.33), (0.17, 0.22, 0.34)], 0.008, M["black"])
    tube("BrakePedal", [(-0.02, -0.15, 0.3), (0.1, -0.2, 0.31), (0.17, -0.22, 0.33)], 0.008, M["black"])
    tube("KickLever", [(-0.1, -0.17, 0.4), (-0.22, -0.2, 0.43)], 0.01, M["chrome"])
    return (wf, wr)


# ---- the scooter: a 110 cc step-through ----
def scooter(M):
    R = 0.24
    FX, RX = 0.6, -0.62
    wf, wr = wheel("Wheel_F", FX, R, 0.1, M), wheel("Wheel_R", RX, R, 0.1, M)
    guard("FrontGuard", (FX, 0, R), R + 0.04, 0.06, -0.8, 1.2, M["paint"])
    guard("RearGuard", (RX, 0, R), R + 0.03, 0.06, -1.5, -0.6, M["black"])
    # body: the rounded side panels over the engine, the seat on them, the grab rail, tail lamp and plate
    F.loft("Body", [(-0.92, 0.08, 0.46, 0.62, 0), (-0.82, 0.16, 0.36, 0.76, 0), (-0.58, 0.2, 0.33, 0.8, 0),
                    (-0.32, 0.19, 0.31, 0.78, 0), (-0.12, 0.14, 0.3, 0.68, 0)], M["paint"], n_top=3.5, n_bot=5.0, segs=32)
    F.loft("Seat", [(-0.86, 0.12, 0.75, 0.83, 0), (-0.6, 0.17, 0.77, 0.88, 0), (-0.3, 0.17, 0.77, 0.88, 0),
                    (-0.1, 0.14, 0.74, 0.84, 0)], M["seat"], n_top=3.0, n_bot=6.0, segs=28)
    tube("GrabRail", [(-0.55, 0.17, 0.83), (-0.75, 0.17, 0.86), (-0.9, 0.1, 0.85), (-0.92, 0.0, 0.85),
                      (-0.9, -0.1, 0.85), (-0.75, -0.17, 0.86), (-0.55, -0.17, 0.83)], 0.012, M["chrome"])
    egg("TailLamp", (-0.925, 0, 0.6), (0.025, 0.12, 0.03), M["tail"])
    for s in (1, -1):
        egg("Indicator", (-0.9, s * 0.135, 0.6), (0.02, 0.03, 0.02), M["amber"])
    F.box("Plate", (-0.905, 0, 0.44), (0.01, 0.18, 0.1), M["plate"], bev=0.003, rot=(0, math.radians(10), 0))
    # the floor with its ribbed mat
    F.box("Floor", (0.1, 0, 0.3), (0.48, 0.34, 0.06), M["black"], bev=0.02)
    for k in range(-4, 5):
        F.box("MatRib", (0.1, k * 0.034, 0.334), (0.42, 0.014, 0.008), M["rubber"], bev=0.003)
    # leg shield in front of the knees (painted outside, black inside), the front indicators
    F.loft("Apron", [(0.32, 0.19, 0.28, 0.5, 0), (0.42, 0.25, 0.3, 0.88, 0), (0.47, 0.24, 0.5, 1.0, 0),
                     (0.5, 0.16, 0.68, 1.02, 0)], M["paint"], n_top=3.0, n_bot=3.0, segs=28)
    F.loft("InnerShield", [(0.3, 0.2, 0.33, 0.86, 0), (0.33, 0.215, 0.33, 0.9, 0)], M["black"], n_top=3.0, n_bot=3.0,
           segs=24)
    for s in (1, -1):
        egg("Indicator", (0.49, s * 0.2, 0.9), (0.02, 0.035, 0.02), M["amber"])
    # handlebar cowl with the headlamp and speedometer, the bar ends, grips, levers, mirrors
    F.loft("Cowl", [(0.31, 0.1, 0.97, 1.07, 0), (0.4, 0.19, 0.96, 1.1, 0), (0.5, 0.12, 0.96, 1.08, 0)], M["paint"],
           n_top=3.0, n_bot=4.0, segs=28)
    egg("Headlamp", (0.5, 0, 1.02), (0.03, 0.09, 0.035), M["head"])
    F.cyl("Speedo", (0.36, 0, 1.08), 0.045, 0.006, M["lens"], rot=(0, math.radians(-50), 0), verts=28)
    for s in (1, -1):
        tube("Bar", [(0.37, s * 0.17, 1.05), (0.34, s * 0.29, 1.05)], 0.011, M["chrome"])
        tube("Grip", [(0.343, s * 0.285, 1.05), (0.333, s * 0.405, 1.05)], 0.017, M["rubber"])
        egg("BarEnd", (0.333, s * 0.41, 1.05), (0.016, 0.01, 0.016), M["chrome"])
        F.box("Switches", (0.35, s * 0.258, 1.05), (0.045, 0.035, 0.04), M["black"], bev=0.01)
        tube("Lever", [(0.37, s * 0.25, 1.06), (0.385, s * 0.33, 1.055), (0.38, s * 0.395, 1.05)], 0.0055, M["chrome"])
        tube("MirrorStem", [(0.4, s * 0.2, 1.09), (0.39, s * 0.24, 1.2), (0.37, s * 0.27, 1.3)], 0.007, M["chrome"])
        egg("Mirror", (0.365, s * 0.28, 1.325), (0.02, 0.065, 0.045), M["black"])
        egg("MirrorGlass", (0.346, s * 0.28, 1.325), (0.005, 0.058, 0.039), M["mirror"])
    # front suspension
    for s in (1, -1):
        tube("ForkSlider", [(FX, s * 0.07, R - 0.02), (0.575, s * 0.07, 0.42)], 0.025, M["engine"])
        tube("Stanchion", [(0.58, s * 0.07, 0.4), (0.52, s * 0.07, 0.64)], 0.018, M["chrome"])
    # drive casing on the left, the engine under the body, shock and exhaust on the right
    case = F.loft("DriveCase", [(-0.12, 0.045, 0.2, 0.42, 0), (-0.4, 0.05, 0.19, 0.4, 0), (-0.64, 0.045, 0.2, 0.32, 0)],
                  M["engine"], n_top=3.0, n_bot=3.0, segs=24)
    case.location.y = 0.11
    F.lathe("CaseCover", [(0.07, 0.0), (0.065, 0.02), (0.0, 0.026)], M["engine"], 32).location = (RX, 0.155, R)
    F.box("Engine", (-0.3, -0.02, 0.3), (0.26, 0.18, 0.18), M["under"], bev=0.03)
    a, b = Vector((-0.64, -0.1, R + 0.03)), Vector((-0.48, -0.11, 0.62))
    tube("Damper", [tuple(a), tuple(b)], 0.013, M["chrome"])
    helix("Spring", lerp(a, b, 0.12), lerp(a, b, 0.88), 0.03, 0.006, 8, M["spring"])
    tube("Header", [(-0.22, -0.05, 0.24), (-0.34, -0.12, 0.23), (-0.42, -0.17, 0.3)], 0.019, M["chrome"])
    along_x(F.lathe("Muffler", [(0.0, -0.25), (0.035, -0.25), (0.052, -0.2), (0.056, 0.16), (0.045, 0.24),
                                (0.022, 0.25), (0.0, 0.25)], M["chrome"], 32), (-0.66, -0.18, 0.36), tilt=0.1)
    along_x(F.lathe("HeatShield", [(0.06, -0.16), (0.062, 0.0), (0.06, 0.12)], M["black"], 32, arc=(-2.2, -0.6)),
            (-0.66, -0.18, 0.36), tilt=0.1)
    return (wf, wr)


def build(kind, root, paint=(0.5, 0.03, 0.04)):
    M = F.mats(paint)
    M.update(engine=F.make_mat("Aluminium", (0.6, 0.6, 0.6), metallic=1.0, rough=0.35),
             rubber=F.make_mat("Grip Rubber", (0.02, 0.02, 0.021), rough=0.75),
             spring=F.make_mat("Spring Paint", (0.55, 0.04, 0.03), rough=0.3, coat=1.0),
             frame=F.make_mat("Frame Paint", (0.02, 0.02, 0.022), rough=0.3, coat=0.6),
             mirror=F.make_mat("Mirror Glass", (0.85, 0.87, 0.9), metallic=1.0, rough=0.02))
    before = set(bpy.data.objects)
    wheels = (motorcycle if kind == "motorcycle" else scooter)(M)
    for o in set(bpy.data.objects) - before:
        if o.parent is None and o is not root:
            o.parent = root
    return wheels, FIT[kind]
