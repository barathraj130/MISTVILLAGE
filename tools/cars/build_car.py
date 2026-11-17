"""Our own cars (docs/VEHICLE_AUDIT_2026-11-17.md), no maker, no badges, right-hand drive, built from one description
each (SPECS): the reference sedan (3.995 × 1.735 × 1.515 m), a hatchback, a compact SUV, a three-row MPV.

The body is one surface swept through cross-sections (a rounded rocker, a shoulder crease, the tumblehome of the
glasshouse, the crown of the bonnet and the roof), nose to tail; on it, as zones, the glass, the pillars, the lamps,
the grille and intakes; its panel gaps cut in (the doors, the bonnet, the boot lid, the fuel lid); its wheel
arches cut and lined. Then the details, the wheels and the cabin (built in later passes, each checked in renders).

    Blender -b --factory-startup --python tools/cars/build_car.py -- --kind sedan|hatchback|suv|mpv [--preview DIR] [--export PATH.glb]
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import carkit as K  # noqa: E402

# ------------------------------------------------------------------------------------------------ the cars
# Each car: its size, axles and tyres; its side profile (TOP: the top of the car, nose + to tail -), the underside
# (BOT), the plan's half width (HALF), the beltline (BELT); where the glass begins and ends (COWL: the windscreen's
# foot, ROOF_F / ROOF_R: the roof's ends, BOOT: the rear screen's foot); how the glasshouse leans in (TUMBLE); a
# boot or a hatch; its doors' lines; its lamps', grille's and intake's outlines (front view, y z); its seats.
SED_TOP = [(1.9975, 0.56), (1.9855, 0.67), (1.9675, 0.71), (1.8775, 0.795), (1.5, 0.855), (1.15, 0.9), (0.84, 0.93), (0.62, 1.06),
           (0.36, 1.27), (0.08, 1.455), (-0.25, 1.505), (-0.62, 1.505), (-0.88, 1.47), (-1.1, 1.36), (-1.3, 1.2),
           (-1.46, 1.085), (-1.7, 1.07), (-1.88, 1.05), (-1.9375, 1.02), (-1.9775, 0.97), (-1.9975, 0.88)]
SPECS = {
    "sedan": dict(
        L=3.995, W=1.735, H=1.515, front_over=0.755, WB=2.45, R=0.31, TRACK=1.51, RIM_D=0.381, TYRE_W=0.185,
        TOP=SED_TOP,
        BOT=[(1.9975, 0.37), (1.9855, 0.3), (1.8975, 0.23), (1.55, 0.19), (0.0, 0.165), (-1.55, 0.19), (-1.8575, 0.26), (-1.9675, 0.31), (-1.9975, 0.4)],
        HALF=[(1.9975, 0.42), (1.9855, 0.66), (1.9575, 0.75), (1.7775, 0.832), (1.3, 0.862), (0.0, 0.8675), (-1.3, 0.864),
              (-1.7475, 0.845), (-1.9175, 0.81), (-1.9775, 0.74), (-1.9975, 0.52)],
        BELT=[(1.6, 0.86), (0.84, 0.935), (0.0, 0.965), (-1.0, 0.99), (-1.5, 1.01)],
        COWL=0.84, ROOF_F=0.08, ROOF_R=-0.88, BOOT=-1.46, TUMBLE=0.25, tail="boot",
        door_f=0.80, B=-0.325, door_r=-1.0, bump_f=0.44, bump_r=0.74, boot_z=0.86,
        head=[(0.44, 0.64), (0.62, 0.635), (0.8, 0.66), (0.86, 0.72), (0.84, 0.775), (0.62, 0.77), (0.47, 0.73)],
        tail_lamp=[(0.4, 0.86), (0.7, 0.86), (0.865, 0.88), (0.87, 0.96), (0.62, 0.975), (0.4, 0.95)],
        fog=(0.66, 0.33), grille=[(-0.42, 0.47), (0.42, 0.47), (0.44, 0.6), (0.38, 0.625), (-0.38, 0.625), (-0.44, 0.6)],
        intake=[(-0.55, 0.25), (0.55, 0.25), (0.6, 0.38), (-0.6, 0.38)], plate_f=0.43, plate_r=0.62,
        rows=[-0.92], int_dz=0.0, eye=(-0.24, 1.31), paint=(0.3, 0.012, 0.01), plate="TN 66 AB 4127"),
    "hatchback": dict(
        L=3.85, W=1.735, H=1.53, front_over=0.72, WB=2.45, R=0.305, TRACK=1.5, RIM_D=0.381, TYRE_W=0.175,
        TOP=[(1.925, 0.56), (1.913, 0.67), (1.895, 0.715), (1.805, 0.8), (1.45, 0.86), (1.1, 0.905), (0.8, 0.935), (0.58, 1.07),
             (0.32, 1.28), (0.05, 1.46), (-0.3, 1.515), (-0.8, 1.52), (-1.2, 1.505), (-1.45, 1.48), (-1.6, 1.36), (-1.74, 1.13),
             (-1.85, 1.02), (-1.895, 0.98), (-1.915, 0.95), (-1.925, 0.88)],
        BOT=[(1.925, 0.37), (1.913, 0.3), (1.825, 0.23), (1.5, 0.19), (0.0, 0.165), (-1.5, 0.19), (-1.785, 0.26), (-1.895, 0.31), (-1.925, 0.4)],
        HALF=[(1.925, 0.42), (1.913, 0.66), (1.885, 0.75), (1.705, 0.832), (1.25, 0.862), (0.0, 0.8675), (-1.25, 0.864),
              (-1.675, 0.85), (-1.845, 0.82), (-1.905, 0.75), (-1.925, 0.55)],
        BELT=[(1.55, 0.86), (0.8, 0.94), (0.0, 0.97), (-1.0, 1.0), (-1.6, 1.03)],
        COWL=0.8, ROOF_F=0.05, ROOF_R=-1.47, BOOT=-1.8, TUMBLE=0.24, tail="hatch",
        door_f=0.78, B=-0.33, door_r=-0.98, bump_f=0.44, bump_r=0.74, quarter=True,
        head=[(0.45, 0.645), (0.63, 0.64), (0.8, 0.665), (0.86, 0.73), (0.83, 0.78), (0.62, 0.775), (0.48, 0.735)],
        tail_lamp=[(0.62, 0.82), (0.86, 0.83), (0.872, 1.12), (0.8, 1.17), (0.66, 1.14)],
        fog=(0.66, 0.33), grille=[(-0.4, 0.47), (0.4, 0.47), (0.42, 0.6), (0.36, 0.625), (-0.36, 0.625), (-0.42, 0.6)],
        intake=[(-0.55, 0.25), (0.55, 0.25), (0.6, 0.38), (-0.6, 0.38)], plate_f=0.43, plate_r=0.6,
        rows=[-0.9], int_dz=0.0, eye=(-0.24, 1.32), paint=(0.36, 0.37, 0.39), plate="TN 37 CK 2290"),
    "suv": dict(
        L=4.3, W=1.8, H=1.7, front_over=0.85, WB=2.6, R=0.345, TRACK=1.56, RIM_D=0.432, TYRE_W=0.215,
        TOP=[(2.15, 0.7), (2.138, 0.82), (2.11, 0.9), (2.0, 0.96), (1.6, 1.0), (1.2, 1.04), (0.85, 1.07), (0.62, 1.2),
             (0.35, 1.42), (0.1, 1.62), (-0.3, 1.69), (-1.0, 1.7), (-1.6, 1.69), (-1.85, 1.66), (-1.98, 1.5), (-2.07, 1.25),
             (-2.12, 1.12), (-2.13, 1.08), (-2.15, 0.98)],
        BOT=[(2.15, 0.48), (2.138, 0.42), (2.03, 0.32), (1.65, 0.26), (0.0, 0.215), (-1.65, 0.26), (-2.01, 0.32), (-2.12, 0.4), (-2.15, 0.5)],
        HALF=[(2.15, 0.5), (2.138, 0.72), (2.1, 0.82), (1.9, 0.88), (1.3, 0.9), (0.0, 0.9), (-1.3, 0.9), (-1.9, 0.89),
              (-2.07, 0.86), (-2.13, 0.8), (-2.15, 0.6)],
        BELT=[(1.65, 1.0), (0.85, 1.08), (0.0, 1.1), (-1.2, 1.12), (-1.9, 1.14)],
        COWL=0.85, ROOF_F=0.1, ROOF_R=-1.86, BOOT=-2.1, TUMBLE=0.2, tail="hatch",
        door_f=0.83, B=-0.36, door_r=-1.05, bump_f=0.55, bump_r=0.82, quarter=True, cladding=True, rails=True,
        head=[(0.47, 0.8), (0.63, 0.795), (0.82, 0.82), (0.885, 0.87), (0.86, 0.925), (0.62, 0.92), (0.5, 0.885)],
        tail_lamp=[(0.62, 0.95), (0.89, 0.96), (0.9, 1.2), (0.82, 1.25), (0.64, 1.22)],
        fog=(0.7, 0.42), grille=[(-0.46, 0.6), (0.46, 0.6), (0.5, 0.76), (0.44, 0.79), (-0.44, 0.79), (-0.5, 0.76)],
        intake=[(-0.6, 0.29), (0.6, 0.29), (0.65, 0.44), (-0.65, 0.44)], plate_f=0.52, plate_r=0.7,
        rows=[-0.98], int_dz=0.12, eye=(-0.22, 1.47), paint=(0.02, 0.06, 0.13), plate="TN 38 BZ 7015"),
    "mpv": dict(
        L=4.45, W=1.775, H=1.69, front_over=0.82, WB=2.74, R=0.315, TRACK=1.52, RIM_D=0.381, TYRE_W=0.185,
        TOP=[(2.225, 0.6), (2.213, 0.71), (2.19, 0.76), (2.095, 0.84), (1.8, 0.9), (1.4, 0.95), (1.1, 0.985), (0.85, 1.15),
             (0.55, 1.42), (0.25, 1.62), (-0.2, 1.685), (-1.2, 1.69), (-1.8, 1.67), (-2.0, 1.64), (-2.1, 1.5), (-2.17, 1.25),
             (-2.2, 1.08), (-2.205, 1.02), (-2.225, 0.92)],
        BOT=[(2.225, 0.38), (2.213, 0.31), (2.125, 0.24), (1.7, 0.2), (0.0, 0.18), (-1.7, 0.2), (-2.085, 0.27), (-2.195, 0.33), (-2.225, 0.42)],
        HALF=[(2.225, 0.45), (2.213, 0.68), (2.185, 0.77), (2.005, 0.86), (1.4, 0.885), (0.0, 0.8875), (-1.4, 0.885),
              (-1.975, 0.875), (-2.145, 0.845), (-2.205, 0.78), (-2.225, 0.58)],
        BELT=[(1.7, 0.93), (1.1, 1.0), (0.0, 1.02), (-1.3, 1.04), (-2.0, 1.07)],
        COWL=1.1, ROOF_F=0.22, ROOF_R=-2.0, BOOT=-2.19, TUMBLE=0.22, tail="hatch",
        door_f=0.95, B=-0.18, door_r=-0.98, bump_f=0.45, bump_r=0.76, quarter=True,
        head=[(0.44, 0.645), (0.63, 0.64), (0.81, 0.665), (0.87, 0.73), (0.85, 0.785), (0.62, 0.78), (0.47, 0.74)],
        tail_lamp=[(0.6, 0.86), (0.875, 0.87), (0.885, 1.16), (0.8, 1.22), (0.64, 1.18)],
        fog=(0.67, 0.33), grille=[(-0.44, 0.48), (0.44, 0.48), (0.46, 0.62), (0.4, 0.645), (-0.4, 0.645), (-0.46, 0.62)],
        intake=[(-0.56, 0.25), (0.56, 0.25), (0.61, 0.39), (-0.61, 0.39)], plate_f=0.43, plate_r=0.62,
        rows=[-0.92, -1.72], int_dz=0.03, eye=(-0.24, 1.36), paint=(0.88, 0.88, 0.86), plate="TN 99 MP 3318"),
}
# The player's own SUV: a full-size luxury SUV of our own (the user's premium-SUV brief and references, 17 Nov: the
# proportions and poise of the modern British luxury SUVs, nothing copied): a long, high, flat bonnet; upright,
# nearly flat flanks under a high, level beltline; a long flat roof; slim high head lamps either side of a wide
# grille; vertical tail lamp strips joined by a black band; a vent in each front door; 22-inch multi-spoke wheels.
def _luxury():
    return dict(
        L=5.05, W=2.0, H=1.87, front_over=0.95, WB=3.0, R=0.405, TRACK=1.7, RIM_D=0.559, TYRE_W=0.285,
        TOP=[(2.525, 0.8), (2.515, 0.92), (2.49, 0.99), (2.42, 1.04), (2.2, 1.075), (1.7, 1.095), (1.2, 1.115), (0.95, 1.13),
             (0.7, 1.32), (0.45, 1.55), (0.2, 1.78), (-0.1, 1.86), (-0.8, 1.87), (-1.6, 1.865), (-2.1, 1.85), (-2.3, 1.82),
             (-2.42, 1.7), (-2.49, 1.45), (-2.515, 1.15), (-2.525, 0.95)],
        BOT=[(2.525, 0.55), (2.5, 0.45), (2.36, 0.37), (1.95, 0.31), (0.0, 0.27), (-1.95, 0.31), (-2.36, 0.37), (-2.5, 0.46), (-2.525, 0.56)],
        HALF=[(2.525, 0.64), (2.512, 0.86), (2.47, 0.94), (2.25, 0.985), (1.5, 1.0), (0.0, 1.0), (-1.5, 1.0), (-2.25, 0.99),
              (-2.46, 0.955), (-2.512, 0.89), (-2.525, 0.7)],
        BELT=[(2.0, 1.13), (0.95, 1.145), (0.0, 1.155), (-1.4, 1.165), (-2.3, 1.175)],
        COWL=0.95, ROOF_F=0.2, ROOF_R=-2.25, BOOT=-2.5, TUMBLE=0.22, tail="hatch",
        door_f=0.9, B=-0.36, door_r=-1.28, bump_f=0.62, bump_r=0.9, quarter=True, cladding=False, rails=False,
        head=[(0.58, 0.955), (0.9, 0.96), (0.95, 0.985), (0.93, 1.015), (0.6, 1.01)],
        tail_lamp=[(0.84, 0.97), (0.93, 0.97), (0.935, 1.36), (0.855, 1.36)],
        fog=(0.82, 0.46), grille=[(-0.52, 0.68), (0.52, 0.68), (0.55, 0.97), (-0.55, 0.97)],
        intake=[(-0.74, 0.36), (0.74, 0.36), (0.78, 0.52), (-0.78, 0.52)], plate_f=0.58, plate_r=0.78,
        rows=[-1.12], int_dz=0.2, eye=(-0.22, 1.62), paint=(0.46, 0.38, 0.27), plate="TN 38 AR 0007",
        spokes=10, gill=True, tail_band=True, dual_exhaust=True, lux=True)


SPECS["luxury"] = _luxury()
KIND = "sedan"
SPEC = SPECS[KIND]
L = W = H = HX = WB = AX_F = AX_R = R = TRACK = RIM_D = TYRE_W = 0.0
TOP = BOT = HALF = BELT = []
COWL = ROOF_F = ROOF_R = BOOT = TUMBLE = 0.0
CREASE = 0.07                     # the shoulder crease below the belt (m)


def use(kind):
    """This car's numbers into the builder's (the functions below read them)."""
    global KIND, SPEC, L, W, H, HX, WB, AX_F, AX_R, R, TRACK, RIM_D, TYRE_W, TOP, BOT, HALF, BELT, COWL, ROOF_F, ROOF_R, BOOT, TUMBLE
    KIND, SPEC = kind, SPECS[kind]
    sp = SPEC
    L, W, H = sp["L"], sp["W"], sp["H"]
    HX = L / 2
    WB = sp["WB"]
    AX_F = HX - sp["front_over"]
    AX_R = AX_F - WB
    R, TRACK, RIM_D, TYRE_W = sp["R"], sp["TRACK"], sp["RIM_D"], sp["TYRE_W"]
    TOP, BOT, HALF, BELT = sp["TOP"], sp["BOT"], sp["HALF"], sp["BELT"]
    COWL, ROOF_F, ROOF_R, BOOT, TUMBLE = sp["COWL"], sp["ROOF_F"], sp["ROOF_R"], sp["BOOT"], sp["TUMBLE"]


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def greenhouse(x):
    """0 over the bonnet and the boot, 1 under the roof: how much glasshouse this station has."""
    return smoothstep(COWL + 0.02, COWL - 0.18, x) * smoothstep(BOOT - 0.02, BOOT + 0.16, x)


# the section's control points (y, z), bottom centre to top centre; and how finely each span is divided
SPANS = [4, 3, 4, 5, 6, 3, 3, 5, 3, 10, 4, 5, 8]                 # (13 spans between 14 points)
# span → zone: 0 under, 1 rocker, 2 lower side, 3 crease, 4 upper side, 5 belt, 6 glass side, 7 rail, 8 roof
SPAN_ZONE = [0, 0, 1, 1, 2, 2, 3, 4, 5, 6, 7, 8, 8]


def section(x):
    top = K.cr(TOP, x)
    zb = K.cr(BOT, x)
    w = K.cr(HALF, x)
    g = greenhouse(x)
    belt = min(K.cr(BELT, x), top - 0.03)
    side_top = belt if g > 0.0 else top - 0.035
    side_top = side_top * g + (top - 0.035) * (1 - g) if g < 1.0 else side_top
    zc = side_top - CREASE - 0.06
    wt = w - TUMBLE * g - 0.05 * (1 - g)                          # the roof's side (or the bonnet's crown edge)
    rail = top - 0.05 * g - 0.012 * (1 - g)
    # (the side's heights kept in order however short it is: at a nose or a tail the fascia can be shorter than the
    #  rocker's and the crease's usual offsets, and the section folded over itself)
    h = max(side_top - zb, 0.02)
    z_r1 = zb + min(0.05, h * 0.1)
    z_r2 = zb + min(0.16, h * 0.28)
    z_c0 = max(zc - 0.12, zb + h * 0.42)
    zc = min(max(zc, zb + h * 0.62), side_top - h * 0.12)
    z_c1 = min(zc + 0.03, side_top - h * 0.06)
    pts = [(0.0, zb), (w * 0.5, zb + 0.002), (w - 0.09, zb + 0.008), (w - 0.022, z_r1), (w - 0.006, z_r2),
           (w + 0.002, z_c0), (w + 0.008, zc), (w - 0.002, z_c1), (w - 0.022, side_top - min(0.008, h * 0.03)),
           (w - 0.034 - 0.02 * g, side_top + 0.004),
           (wt + 0.012 * g, rail - 0.012 * g), (wt - 0.07, top - 0.004), (wt * 0.45, top + 0.012), (0.0, top + 0.016)]
    return pts


def cr_pts(pts, spans):
    """Catmull-Rom through the section's points, each span divided as told: [(y, z, span index)]."""
    out = []
    n = len(pts)
    for j in range(n - 1):
        p0 = Vector(pts[max(j - 1, 0)])
        p1, p2 = Vector(pts[j]), Vector(pts[j + 1])
        p3 = Vector(pts[min(j + 2, n - 1)])
        for k in range(spans[j]):
            t = k / spans[j]
            v = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)
            out.append((v.x, v.y, j))
    out.append((pts[-1][0], pts[-1][1], n - 2))
    return out


def stations():
    xs = []
    n = 180
    for i in range(n + 1):
        u = i / n
        u = 0.5 - 0.5 * math.cos(math.pi * u)                    # (closer at the nose and the tail)
        xs.append(HX - u * L)
    return xs


def zone_material(x, y, z, zone, M):
    """The body surface's own material: paint, the underside black. (Glass, lamps, the grille and the intakes are
    cut out of it to their outlines and made separate parts: patches(), so their edges are clean.)"""
    if zone == 0:
        return "BlackTrim"
    if x < -HX + 0.14 and z < 0.36:
        return "BlackTrim"                                        # (the rear bumper's lower part)
    return "Paint"


def build_body(M):
    xs = stations()
    rings = []
    for x in xs:
        rings.append((x, cr_pts(section(x), SPANS)))
    names = ["Paint", "Glass", "GlassTint", "BlackGloss", "BlackTrim", "LampZoneF", "LampZoneR", "GrilleZone", "IntakeZone"]
    mats = [M.get(n) or K._mat(n, (0.5, 0.5, 0.5)) for n in names]
    bm = bmesh.new()
    vr = []
    for x, ring in rings:
        right = [bm.verts.new((x, -y, z)) for (y, z, j) in ring]
        left = [bm.verts.new((x, y, z)) for (y, z, j) in reversed(ring[1:-1])]
        vr.append((right + left, [j for (_y, _z, j) in ring]))
    n = len(vr[0][0])
    nr = len(rings[0][1])
    for (a, ja), (b, jb), (xa, _r) in zip(vr, vr[1:], rings):
        for k in range(n):
            k2 = (k + 1) % n
            f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            c = f.calc_center_median()
            kk = k if k < nr else (n - k - 1)                     # (which point of the half-section)
            span = ja[min(kk, nr - 1)]
            zone = SPAN_ZONE[min(span, len(SPAN_ZONE) - 1)]
            mn = zone_material(c.x, c.y, c.z, zone, M)
            f.material_index = names.index(mn)
    # close the nose and the tail
    for ring, _j in (vr[0], vr[-1]):
        bm.faces.new(ring)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    body = K.mesh_obj("Body", bm, mats)
    return body


def prism_side(name, pts_xz, y0, y1):
    """A solid from a side-view outline (x, z), from y0 to y1: for cutting shut lines through the side."""
    bm = bmesh.new()
    a = [bm.verts.new((x, y0, z)) for x, z in pts_xz]
    b = [bm.verts.new((x, y1, z)) for x, z in pts_xz]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(len(a)):
        j = (i + 1) % len(a)
        bm.faces.new((a[i], b[i], b[j], a[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return K.mesh_obj(name, bm)


def prism_top(name, pts_xy, z0, z1):
    """A solid from a plan outline (x, y), from z0 to z1: for shut lines on the bonnet and the boot."""
    bm = bmesh.new()
    a = [bm.verts.new((x, y, z0)) for x, y in pts_xy]
    b = [bm.verts.new((x, y, z1)) for x, y in pts_xy]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(len(a)):
        j = (i + 1) % len(a)
        bm.faces.new((a[i], b[i], b[j], a[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return K.mesh_obj(name, bm)


def prism_front_line(name, outline, x0, x1):
    """A thin slab across the car's front or back at a height (outline: a line's offset in (u, z), u unused)."""
    zs = [p[1] for p in outline]
    z0, z1 = min(zs), max(zs)
    pts = [(-0.9, z0), (0.9, z0), (0.9, z1), (-0.9, z1)]
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for y, z in pts]
    b = [bm.verts.new((x1, y, z)) for y, z in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((a[i], b[i], b[j], a[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return K.mesh_obj(name, bm)


def line_cutter(name, poly, gap, maker, a, b):
    """A thin slab (gap wide) along a polyline: its outline is the line offset either side."""
    pts = [Vector(p) for p in poly]
    left, right = [], []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        nrm = Vector((-d.y, d.x)) * (gap / 2)
        left.append(p + nrm)
        right.append(p - nrm)
    outline = [(v.x, v.y) for v in left] + [(v.x, v.y) for v in reversed(right)]
    return maker(name, outline, a, b)


def cut_panels(body):
    """The shut lines: doors, bonnet, boot lid or tailgate, bumpers, fuel lid; 3.5 mm wide, 3–5 cm into the body."""
    gap = 0.0035
    sp = SPEC
    cutters = []
    sill = K.cr(BOT, 0.0) + 0.145
    hw = W / 2
    for side in (1.0, -1.0):
        y0, y1 = side * (hw - 0.053), side * (hw + 0.08)
        df, b, dr = sp["door_f"], sp["B"], sp["door_r"]
        bf, br = K.cr(BELT, df), K.cr(BELT, dr)
        # front door: behind the front arch, up to the belt; the B pillar (between the doors); the rear door's rear
        # edge, down to where the rear arch begins
        cutters.append(line_cutter("C_dfront", [(df, sill - 0.03), (df + 0.02, (sill + bf) / 2), (df - 0.03, bf + 0.015)], gap, prism_side, y0, y1))
        cutters.append(line_cutter("C_dB", [(b - 0.005, sill - 0.04), (b - 0.005, K.cr(BELT, b) + 0.035)], gap, prism_side, y0, y1))
        cutters.append(line_cutter("C_drear", [(dr, br + 0.025), (dr - 0.01, br - 0.29), (AX_R + R + 0.05, R + 0.31), (AX_R + R + 0.12, sill + 0.09),
                                               (AX_R + R + 0.12, sill - 0.04)], gap, prism_side, y0, y1))
        cutters.append(line_cutter("C_sill", [(df, sill), (AX_R + R + 0.12, sill)], gap, prism_side, y0, y1))
        if side < 0:                                          # the fuel lid (the right rear quarter)
            a0, a1 = AX_R - 0.25, AX_R - 0.08
            z1 = K.cr(BELT, a1) - 0.075
            z0 = z1 - 0.13
            for n, q in enumerate([[(a0, z1), (a1, z1)], [(a1, z1), (a1, z0)], [(a1, z0), (a0, z0)], [(a0, z0), (a0, z1)]]):
                cutters.append(line_cutter("C_fuel%d" % n, q, gap, prism_side, y0, y1))
    # bonnet: across the cowl, along both fender tops, to the headlamps
    bz = K.cr(TOP, (HX + COWL) / 2)
    hb = hw - 0.125
    cutters.append(line_cutter("C_bonnet", [(HX - 0.18, hb), (COWL + 0.45, hb), (COWL - 0.01, hb - 0.02), (COWL - 0.02, 0.0),
                                            (COWL - 0.01, -(hb - 0.02)), (COWL + 0.45, -hb), (HX - 0.18, -hb)], gap, prism_top, bz - 0.15, bz + 0.15))
    if sp["tail"] == "boot":                                  # a boot lid: behind the rear screen, along its sides, across the tail
        tz = K.cr(TOP, (BOOT - HX) / 2)
        cutters.append(line_cutter("C_boot", [(-HX - 0.05, hb - 0.01), (BOOT - 0.24, hb - 0.01), (BOOT - 0.01, hb - 0.04), (BOOT - 0.02, 0.0),
                                              (BOOT - 0.01, -(hb - 0.04)), (BOOT - 0.24, -(hb - 0.01)), (-HX - 0.05, -(hb - 0.01))], gap, prism_top, tz - 0.12, tz + 0.08))
        cutters.append(line_cutter("C_bootT", [(-HX - 0.1, sp["boot_z"]), (-HX + 0.1, sp["boot_z"])], gap, prism_side, -(hw - 0.1), hw - 0.1))
    else:                                                     # a tailgate: across the roof's end, down each side, its foot at the bumper
        rz = K.cr(TOP, ROOF_R)
        cutters.append(line_cutter("C_gateTop", [(ROOF_R + 0.03, hw - 0.14), (ROOF_R + 0.03, -(hw - 0.14))], gap, prism_top, rz - 0.15, rz + 0.1))
        for side in (1.0, -1.0):
            gy = side * (hw - 0.12)
            cutters.append(line_cutter("C_gateSide", [(gy, sp["bump_r"]), (gy * 0.98, rz - 0.04)], gap, prism_front, -HX - 0.1, ROOF_R + 0.1))
    for side in (1.0, -1.0):                                  # the bumpers' lines, round the corners to the arches
        y0, y1 = side * (hw - 0.27), side * (hw + 0.08)
        cutters.append(line_cutter("C_bumpF", [(HX + 0.05, sp["bump_f"]), (HX - 0.25, sp["bump_f"]), (AX_F + R + 0.06, sp["bump_f"] + 0.02)], gap, prism_side, y0, y1))
        cutters.append(line_cutter("C_bumpR", [(-HX - 0.05, sp["bump_r"]), (-HX + 0.28, sp["bump_r"]), (AX_R - R - 0.06, sp["bump_r"] - 0.08)], gap, prism_side, y0, y1))
    cutters.append(line_cutter("C_bumpFF", [(HX - 0.3, sp["bump_f"]), (HX + 0.1, sp["bump_f"])], gap, prism_side, -(hw - 0.25), hw - 0.25))
    cutters.append(line_cutter("C_bumpRR", [(-HX - 0.1, sp["bump_r"]), (-HX + 0.3, sp["bump_r"])], gap, prism_side, -(hw - 0.25), hw - 0.25))
    for c in cutters:
        K.boolean(body, c)
        K.remove(c)


def prism_front(name, pts_yz, x0, x1):
    """A solid from a front-view outline (y, z), from x0 to x1."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for y, z in pts_yz]
    b = [bm.verts.new((x1, y, z)) for y, z in pts_yz]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(len(a)):
        j = (i + 1) % len(a)
        bm.faces.new((a[i], b[i], b[j], a[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return K.mesh_obj(name, bm)


def cut_arches(body, M):
    """The wheel arches: cut round each wheel with room to turn and to move on its springs, the edge rolled; a
    black liner inside each."""
    liners = []
    for ax in (AX_F, AX_R):
        for side in (1.0, -1.0):
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=64, radius1=R + 0.038, radius2=R + 0.038, depth=0.5)
            cut = K.mesh_obj("C_arch", bm)
            cut.rotation_euler = (math.pi / 2, 0, 0)
            cut.location = (ax, side * (W / 2 - 0.1), R + 0.02)
            bpy.context.view_layer.update()
            K.boolean(body, cut)
            K.remove(cut)
            # the liner: a half drum of black plastic over the wheel, inside the body
            lin = K.lathe("ArchLiner", [(R + 0.05, -0.17), (R + 0.05, 0.12)], 48, 'Y', [M["BlackTrim"]])
            me = lin.data
            bm2 = bmesh.new()
            bm2.from_mesh(me)
            for f in list(bm2.faces):
                if f.calc_center_median().z < -0.02:
                    bm2.faces.remove(f)
            bm2.to_mesh(me)
            bm2.free()
            lin.location = (ax, side * (W / 2 - 0.2), R + 0.02)
            liners.append(lin)
    return liners


def rail_z(x):
    """Where the side glass meets the roof, at x."""
    g = greenhouse(x)
    return K.cr(TOP, x) - 0.05 * g


def a_line(z):
    """The A pillar's rear edge (x) at height z: along the windscreen's side, set back by the pillar."""
    zc = K.cr(TOP, COWL)
    zr = K.cr(TOP, ROOF_F)
    t = min(max((z - zc) / (zr - zc), 0.0), 1.0)
    return COWL - 0.05 + (ROOF_F + 0.02 - (COWL - 0.05)) * t


def c_line(z):
    """The rearmost side glass's rear edge (x) at height z: the C pillar (a sedan's, before its rear screen) or the D
    pillar (a hatch's, beside its tailgate)."""
    zb = K.cr(TOP, BOOT)
    zr = K.cr(TOP, ROOF_R)
    t = min(max((z - zb) / (zr - zb), 0.0), 1.0)
    if SPEC["tail"] == "boot":
        return BOOT + 0.32 + (ROOF_R + 0.04 - (BOOT + 0.32)) * t
    return BOOT + 0.14 + (ROOF_R + 0.1 - (BOOT + 0.14)) * t


def dlo(x0, x1, front_fn=None, rear_fn=None, n=24):
    """A side window's outline (x, z): along the belt below and the roof rail above, from x1 (rear) to x0 (front);
    its ends along the pillars where they lean."""
    top, bot = [], []
    for i in range(n + 1):
        x = x1 + (x0 - x1) * i / n
        bot.append((x, K.cr(BELT, x) + 0.012))
        top.append((x, rail_z(x) - 0.018))
    pts = bot + list(reversed(top))
    out = []
    for (x, z) in pts:                                          # (the leaning pillars clip the ends)
        if front_fn:
            x = min(x, front_fn(z))
        if rear_fn:
            x = max(x, rear_fn(z))
        out.append((x, z))
    return out


def ellipse(cy, cz, ry, rz, n=28):
    return [(cy + math.cos(2 * math.pi * i / n) * ry, cz + math.sin(2 * math.pi * i / n) * rz) for i in range(n)]


AXES = {"side": (0, 2, 1), "front": (1, 2, 0), "top": (0, 1, 2)}   # (the outline's two coordinates, the depth's)


def _inside(pt, poly):
    x, y = pt
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            c = not c
        j = i
    return c


def mark(bm, outline, view, depth, mat_index):
    """The body's faces inside an outline (seen from the side, the front or above, within a depth range on the
    third axis) given a material; the surface first sliced along each of the outline's edges, near it only, so the
    material's edge follows the outline exactly over the curves."""
    a, b, d = AXES[view]
    lo = [min(p[0] for p in outline) - 0.02, min(p[1] for p in outline) - 0.02]
    hi = [max(p[0] for p in outline) + 0.02, max(p[1] for p in outline) + 0.02]

    def near(f):
        c = f.calc_center_median()
        return lo[0] <= c[a] <= hi[0] and lo[1] <= c[b] <= hi[1] and depth[0] <= c[d] <= depth[1]
    n = len(outline)
    for i in range(n):
        p, q = outline[i], outline[(i + 1) % n]
        e = Vector((q[0] - p[0], q[1] - p[1]))
        if e.length < 1e-6:
            continue
        no = [0.0, 0.0, 0.0]
        no[a], no[b] = -e.y, e.x
        co = [0.0, 0.0, 0.0]
        co[a], co[b] = p[0], p[1]
        faces = [f for f in bm.faces if near(f)]
        if not faces:
            continue
        geom = list({v for f in faces for v in f.verts}) + list({ed for f in faces for ed in f.edges}) + faces
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no)
    hit = 0
    for f in bm.faces:
        c = f.calc_center_median()
        if depth[0] <= c[d] <= depth[1] and _inside((c[a], c[b]), outline):
            f.material_index = mat_index
            hit += 1
    return hit


def openings(body, M, names):
    """Glass, lamps, the grille and intakes marked on the body to their outlines (clean edges on its curves); split
    off by material at the end."""
    sp = SPEC
    for n in ["Glass", "GlassTint", "Lens", "TailLens", "BlackGloss", "BlackTrim"]:
        if n not in names:
            names.append(n)
            body.data.materials.append(M.get(n) or K._mat(n, (0.5, 0.5, 0.5)))
    bm = bmesh.new()
    bm.from_mesh(body.data)
    got = {}
    b0, b1 = sp["B"] - 0.035, sp["B"] + 0.035
    for side in (1.0, -1.0):
        dep = (0.35, 1.1) if side > 0 else (-1.1, -0.35)
        fw = dlo(b0, a_line(K.cr(BELT, COWL)) + 0.1, front_fn=a_line)
        got["glass_f"] = mark(bm, fw, "side", dep, names.index("Glass"))
        if sp.get("quarter"):                                 # rear door glass to its door's edge; a quarter light behind
            rw = dlo(sp["door_r"] - 0.03, b1)
            got["glass_r"] = mark(bm, rw, "side", dep, names.index("Glass"))
            qw = dlo(c_line(1.2) - 0.1, sp["door_r"] + 0.05, rear_fn=c_line)
            got["glass_q"] = mark(bm, qw, "side", dep, names.index("GlassTint"))
        else:
            rw = [(min(x, b1), z) for x, z in dlo(c_line(1.0) - 0.1, b1, rear_fn=c_line)]
            got["glass_r"] = mark(bm, rw, "side", dep, names.index("Glass"))
        hl = [(side * y, z) for y, z in sp["head"]]
        if side < 0:
            hl = list(reversed(hl))
        got["head"] = mark(bm, hl, "front", (HX - 0.42, HX + 0.1), names.index("Lens"))
        tl = [(side * y, z) for y, z in sp["tail_lamp"]]
        if side < 0:
            tl = list(reversed(tl))
        got["tail"] = mark(bm, tl, "front", (-HX - 0.1, -HX + 0.4), names.index("TailLens"))
        fy, fz = sp["fog"]
        got["fog"] = mark(bm, ellipse(side * fy, fz, 0.055, 0.045), "front", (HX - 0.25, HX + 0.1), names.index("Lens"))

    def screen(x0, x1, inset):
        left, right = [], []
        for i in range(21):
            x = x0 + (x1 - x0) * i / 20
            w = K.cr(HALF, x) - TUMBLE * greenhouse(x) - inset
            left.append((x, w))
            right.append((x, -w))
        return left + list(reversed(right))
    got["ws"] = mark(bm, screen(COWL - 0.03, ROOF_F + 0.03, 0.028), "top", (K.cr(BELT, COWL), H + 0.1), names.index("Glass"))
    if sp["tail"] == "boot":
        got["bs"] = mark(bm, screen(ROOF_R - 0.03, BOOT + 0.04, 0.09), "top", (K.cr(BELT, BOOT), H + 0.1), names.index("GlassTint"))
    else:                                                     # the tailgate's glass, seen from behind
        gz0, gz1 = K.cr(TOP, BOOT) + 0.03, K.cr(TOP, ROOF_R) - 0.06
        gw = K.cr(HALF, (BOOT + ROOF_R) / 2) - TUMBLE - 0.1
        rs = [(-gw, gz0), (gw, gz0), (gw * 0.93, gz1), (-gw * 0.93, gz1)]
        got["bs"] = mark(bm, rs, "front", (-HX - 0.1, ROOF_R + 0.05), names.index("GlassTint"))
    got["grille"] = mark(bm, sp["grille"], "front", (HX - 0.3, HX + 0.1), names.index("BlackGloss"))
    got["intake"] = mark(bm, sp["intake"], "front", (HX - 0.3, HX + 0.1), names.index("BlackTrim"))
    for side in (1.0, -1.0):                                  # the B pillars, gloss black
        dep = (0.35, 1.1) if side > 0 else (-1.1, -0.35)
        bz = K.cr(BELT, sp["B"]) - 0.01
        bp = [(b0, bz), (b1, bz), (b1, H), (b0, H)]
        mark(bm, bp, "side", dep, names.index("BlackGloss"))
    bm.to_mesh(body.data)
    bm.free()
    return got


# ------------------------------------------------------------------------------------------------ details
from mathutils.bvhtree import BVHTree  # noqa: E402


def surface(body):
    dg = bpy.context.evaluated_depsgraph_get()
    return BVHTree.FromObject(body, dg)


def hit(tree, origin, direction):
    loc, nrm, _i, _d = tree.ray_cast(Vector(origin), Vector(direction).normalized(), 5.0)
    return loc, nrm


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


def extract(body, mat_name, pred, name, mat):
    """The body's faces of `mat_name` where pred(centre) holds, made their own object (taken off the body)."""
    names = [m.name if m else "-" for m in body.data.materials]
    if mat_name not in names:
        return None
    idx = names.index(mat_name)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    faces = [f for f in bm.faces if f.material_index == idx and pred(f.calc_center_median())]
    if not faces:
        bm.free()
        return None
    nb = bmesh.new()
    vmap = {}
    for f in faces:
        vs = []
        for v in f.verts:
            if v.index not in vmap:
                vmap[v.index] = nb.verts.new(v.co)
            vs.append(vmap[v.index])
        try:
            nb.faces.new(vs)
        except ValueError:
            pass
    bmesh.ops.delete(bm, geom=faces, context='FACES')
    bm.to_mesh(body.data)
    bm.free()
    ob = K.mesh_obj(name, nb, [mat])
    return ob


def cup(lens, depth, mat, name):
    """The lamp's housing behind its lens: the lens's shape pushed in by `depth`, with walls round it."""
    bm = bmesh.new()
    bm.from_mesh(lens.data)
    bm.normal_update()
    nrm = Vector()
    for f in bm.faces:
        nrm += f.normal * f.calc_area()
    nrm.normalize()
    ret = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    moved = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=moved, vec=-nrm * depth)
    old = [f for f in bm.faces if not all(v in moved for v in f.verts) and not any(v in moved for v in f.verts)]
    bmesh.ops.delete(bm, geom=old, context='FACES')           # (open where the lens sits)
    ob = K.mesh_obj(name, bm, [mat])
    return ob, nrm


def bbox(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def lamps(body, M):
    """Every lamp: its lens (clear), the reflector housing behind it, and what lights, by the game's names:
    Headlight_*, DRL_*, Indicator_<L|R>_<F|R>, Taillight_*, Brake_*, Reverse_*, Fog_*."""
    out = []
    for side, sl in ((1.0, "L"), (-1.0, "R")):
        ins = (lambda c, s=side: c.y * s > 0.2)
        hl = extract(body, "Lens", lambda c, s=side: c.x > HX - 0.45 and c.z > SPEC["bump_f"] + 0.1 and c.y * s > 0.2, "HeadLens_" + sl, M["Lens"])
        if hl:
            hs, n = cup(hl, 0.07, M["Reflector"], "HeadHousing_" + sl)
            lo, hi = bbox(hl)
            mid = (lo + hi) / 2 - n * 0.045
            for k, yy in enumerate((0.55, 0.72)):          # two projectors, their bulbs lit as headlamps
                pr = K.lathe("Headlight_%s%d" % (sl, k), [(0.0, 0.0), (0.032, 0.0), (0.034, -0.02), (0.02, -0.05)], 32, 'X', [M["Headlight"]])
                pr.location = (mid.x + 0.01, side * yy, mid.z + 0.01)
                rim = K.lathe("HeadRing_%s%d" % (sl, k), [(0.034, 0.005), (0.046, -0.005), (0.05, -0.04)], 32, 'X', [M["Chrome"]])
                rim.location = pr.location
                out += [pr, rim]
            drl = box("DRL_" + sl, (0.008, 0.19, 0.008), (mid.x + 0.02, side * 0.63, lo.z + 0.02), M["DRL"], bevel=0.003)
            ind = box("Indicator_%s_F" % sl, (0.01, 0.05, 0.02), (mid.x - 0.03, side * (hi.y * side - 0.04) * 1.0 if side > 0 else side * (-lo.y - 0.04), mid.z + 0.012), M["Indicator"])
            out += [hl, hs, drl, ind]
        fog = extract(body, "Lens", lambda c, s=side: c.x > HX - 0.3 and c.z < SPEC["bump_f"] and c.y * s > 0.2, "FogLens_" + sl, M["Lens"])
        if fog:
            fh, n = cup(fog, 0.05, M["Reflector"], "FogHousing_" + sl)
            lo, hi = bbox(fog)
            fb = K.lathe("Fog_" + sl, [(0.0, 0.0), (0.03, 0.0), (0.03, -0.01)], 24, 'X', [M["Headlight"]])
            fb.location = ((lo.x + hi.x) / 2 - 0.03, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
            out += [fog, fh, fb]
        tl = extract(body, "TailLens", lambda c, s=side: c.y * s > 0.2, "TailLens_" + sl, M["Lens"])
        if tl:
            th, n = cup(tl, 0.06, M["BlackGloss"], "TailHousing_" + sl)
            lo, hi = bbox(tl)
            x = lo.x + 0.035
            yo = hi.y if side > 0 else lo.y                  # (the outer end)
            yi = lo.y if side > 0 else hi.y
            span = abs(yo - yi)
            seg = lambda f0, f1: (side * (abs(yi) + span * f0), side * (abs(yi) + span * f1))
            tall = (hi.z - lo.z) > abs(hi.y - lo.y)
            for nm, f0, f1, zz, mat in (("Taillight_" + sl, 0.35, 0.95, 0.03, M["Taillight"]), ("Brake_" + sl, 0.35, 0.95, -0.015, M["Brake"]),
                                        ("Indicator_%s_R" % sl, 0.05, 0.32, 0.03, M["Indicator"]), ("Reverse_" + sl, 0.05, 0.32, -0.015, M["Reverse"])):
                if tall:                                      # (an upright lamp on the corner: its parts stacked, top down)
                    zt = {"Taillight_": (0.62, 0.95), "Brake_": (0.38, 0.6), "Indicator": (0.18, 0.36), "Reverse_": (0.03, 0.16)}
                    key = next(k for k in zt if nm.startswith(k))
                    z0 = lo.z + (hi.z - lo.z) * zt[key][0]
                    z1 = lo.z + (hi.z - lo.z) * zt[key][1]
                    yc = (lo.y + hi.y) / 2
                    out.append(box(nm, (0.012, abs(hi.y - lo.y) * 0.32, (z1 - z0) * 0.45), (x, yc, (z0 + z1) / 2), mat, bevel=0.004))
                else:
                    a, b = seg(f0, f1)
                    out.append(box(nm, (0.012, abs(b - a) / 2, 0.018), (x, (a + b) / 2, (lo.z + hi.z) / 2 + zz), mat, bevel=0.004))
            out += [tl, th]
    return out


def front_trim(body, tree, M):
    """The grille's slats and chrome strip, the intake's mesh, the plates, the bonnet's washer jets."""
    out = []
    gz0 = min(p[1] for p in SPEC["grille"])
    gz1 = max(p[1] for p in SPEC["grille"])
    gyw = min(abs(p[0]) for p in SPEC["grille"]) * 0.98
    for k in range(4):                                        # grille slats, following the fascia's curve
        z = gz0 + (gz1 - gz0) * (k + 0.8) / 4.6
        pts = []
        for y in [i / 12 * gyw * 2 - gyw for i in range(13)]:
            loc, _n = hit(tree, (HX + 0.5, y, z), (-1, 0, 0))
            if loc:
                pts.append(loc)
        if len(pts) > 2:
            bm = bmesh.new()
            prev = None
            for p in pts:
                a = bm.verts.new(p + Vector((0.008, 0, 0.007)))
                b = bm.verts.new(p + Vector((0.008, 0, -0.007)))
                if prev:
                    bm.faces.new((prev[0], prev[1], b, a))
                prev = (a, b)
            sl = K.mesh_obj("GrilleSlat%d" % k, bm, [M["BlackGloss"] if k else M["Chrome"]])
            so = sl.modifiers.new("S", 'SOLIDIFY')
            so.thickness = 0.012
            out.append(sl)
    # the intake's honeycomb: a grid of small cells recessed in it
    iz = sum(p[1] for p in SPEC["intake"]) / len(SPEC["intake"])
    loc, _n = hit(tree, (HX + 0.5, 0.0, iz), (-1, 0, 0))
    if loc:
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=22, y_segments=5, size=0.5)
        hc = K.mesh_obj("IntakeMesh", bm, [M["BlackTrim"]])
        hc.rotation_euler = (0, math.pi / 2, 0)
        hc.scale = (0.12, 1.08, 1.0)
        hc.location = loc + Vector((-0.03, 0, 0))
        wf = hc.modifiers.new("W", 'WIREFRAME')
        wf.thickness = 0.008
        out.append(hc)
    # plates (made-up registrations; front on the bumper under the grille, rear on the boot's face)
    loc, _n = hit(tree, (HX + 0.5, 0.0, SPEC["plate_f"]), (-1, 0, 0))
    if loc:
        out += list(K.plate(M, "PlateFront", SPEC["plate"], loc + Vector((0.008, 0, 0)), Vector((1, 0, 0))))
    loc, _n = hit(tree, (-HX - 0.5, 0.0, SPEC["plate_r"]), (1, 0, 0))
    if loc:
        out += list(K.plate(M, "PlateRear", SPEC["plate"], loc + Vector((-0.008, 0, 0)), Vector((-1, 0, 0))))
    return out


def side_trim(body, tree, M):
    """Mirrors (a shell, the glass, an indicator strip), door handles, the wipers, the aerial, the exhaust."""
    out = []
    for side, sl in ((1.0, "L"), (-1.0, "R")):
        mx = COWL - 0.21
        loc, n = hit(tree, (mx, side * 1.5, K.cr(BELT, mx) + 0.055), (0, -side, 0))
        if loc:
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=0.5)
            sh = K.mesh_obj("Mirror_" + sl, bm, [M["Paint"]])
            sh.scale = (0.07, 0.11, 0.065)
            sh.location = loc + Vector((-0.02, side * 0.17, 0.035))
            for v in sh.data.vertices:                        # (flat at the back, where the glass is)
                if v.co.x < -0.1:
                    v.co.x = -0.1
            gl = box("MirrorGlass_" + sl, (0.002, 0.095, 0.05), sh.location + Vector((-0.0072, 0, 0)), M["Chrome"])
            st = box("MirrorStalk_" + sl, (0.04, 0.12, 0.025), loc + Vector((-0.01, side * 0.07, 0.01)), M["BlackTrim"], bevel=0.008)
            ind = box("Indicator_%s_M" % sl, (0.03, 0.06, 0.006), sh.location + Vector((0.035, side * 0.03, -0.03)), M["Indicator"])
            out += [sh, gl, st, ind]
        for x in (SPEC["B"] + 0.53, SPEC["door_r"] + 0.28):   # flush handles, a dark recess behind each
            loc, n = hit(tree, (x, side * 1.5, K.cr(BELT, x) - 0.08), (0, -side, 0))
            if loc:
                out.append(box("Handle_%s%d" % (sl, int(x * 10)), (0.065, 0.008, 0.012), loc + Vector((0, side * 0.006, 0)), M["Paint"], bevel=0.004))
                out.append(box("HandleRecess_%s%d" % (sl, int(x * 10)), (0.07, 0.003, 0.016), loc + Vector((0, side * 0.001, -0.004)), M["BlackTrim"]))
    for k, (y0, y1) in enumerate(((-0.62, 0.05), (0.05, 0.6))):   # wipers parked at the windscreen's foot
        a, _n = hit(tree, (COWL - 0.03, y0, 2.0), (0, 0, -1))
        b, _n = hit(tree, (COWL - 0.03, y1, 2.0), (0, 0, -1))
        if a and b:
            mid = (a + b) / 2 + Vector((0, 0, 0.015))
            ln = (b - a).length
            out.append(box("Wiper%d" % k, (0.01, ln / 2, 0.008), mid, M["BlackTrim"], rot=(0, 0, 0)))
    a, _n = hit(tree, (ROOF_R + 0.1, 0.0, 3.0), (0, 0, -1))
    if a:                                                      # the shark-fin aerial
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.5, radius2=0.08, depth=1.0)
        fin = K.mesh_obj("Aerial", bm, [M["Paint"]])
        fin.scale = (0.11, 0.035, 0.06)
        fin.location = a + Vector((0, 0, 0.03))
        out.append(fin)
    ex = K.lathe("Exhaust", [(0.024, 0.0), (0.03, 0.0), (0.03, 0.12), (0.024, 0.12)], 24, 'X', [M["Chrome"]])
    ex.location = (-HX + 0.06, -0.48, K.cr(BOT, -HX + 0.2) - 0.02)
    out.append(ex)
    return out


def wheels(M):
    out = []
    for nm, x, side in (("Wheel_FL", AX_F, 1.0), ("Wheel_FR", AX_F, -1.0), ("Wheel_RL", AX_R, 1.0), ("Wheel_RR", AX_R, -1.0)):
        piv, fixed = K.wheel(M, nm, (x, side * TRACK / 2, R), R, TYRE_W, RIM_D, spokes=int(SPEC.get("spokes", 5)), left=side > 0, steer=nm[-2] == "F")
        out += [piv] + fixed
    return out


def interior(M):
    """The cabin, right-hand drive (the driver on the car's right, -Y): the dash (its top, its face, the hooded
    cluster with real dials and needles the game turns, the centre stack with a screen, vents, the hazard switch,
    the climate knobs, a glovebox), the wheel on its column with stalks, the pedals, the seats (bolstered cushions
    and backs, headrests on posts), the rear bench, the console with a manual gear lever and the handbrake, the door
    cards (armrest, pull, window switches, a speaker), the floor's carpet, the headliner, visors, the rear-view
    mirror, the belts, the cabin light; and the marks the game reads: Eye (the driver's eyes), SteeringPivot."""
    out = []
    root = bpy.data.objects.new("Interior", None)
    K.link(root)
    out.append(root)

    def add(ob):
        ob.parent = root
        out.append(ob)
        return ob
    DY = -0.37                                               # the driver's centre line
    # floor and firewall
    dx = COWL - 0.84                                          # (this cabin, built for the sedan's frame, moved to this car's)
    dz = SPEC["int_dz"]
    back = min(SPEC["rows"]) - 0.55
    add(box("Floor", (0.8 - back, 1.42, 0.02), ((0.8 + back) / 2, 0.0, 0.29), M["Carpet"]))
    add(box("Firewall", (0.04, 1.42, 0.4), (0.78, 0.0, 0.5), M["Dash"]))
    add(box("Tunnel", (1.3, 0.24, 0.12), (0.05, 0.0, 0.36), M["Carpet"], bevel=0.03))
    # the dash: a loft across the car (sections in x-z, from the windscreen's foot back to the knee)
    bm = bmesh.new()
    rows = []
    prof = [(0.84, 0.925), (0.7, 0.935), (0.55, 0.915), (0.47, 0.88), (0.45, 0.8), (0.46, 0.68), (0.52, 0.58), (0.6, 0.5), (0.72, 0.46)]
    ny = 28
    for j in range(ny + 1):
        y = -0.72 + 1.44 * j / ny
        bulge = 0.02 * math.cos(math.pi * y / 1.44)
        rows.append([bm.verts.new((x - bulge * (1 if k > 2 else 0), y, z + (bulge if k < 3 else 0))) for k, (x, z) in enumerate(prof)])
    for j in range(ny):
        for k in range(len(prof) - 1):
            bm.faces.new((rows[j][k], rows[j + 1][k], rows[j + 1][k + 1], rows[j][k + 1]))
    dash = K.mesh_obj("Dash", bm, [M["Dash"]])
    so = dash.modifiers.new("S", 'SOLIDIFY')
    so.thickness = 0.01
    K.smooth(dash, 45)
    add(dash)
    # a light-coloured insert across the passenger side, the glovebox below it (its outline a dark gap)
    add(box("DashInsert", (0.02, 0.55, 0.06), (0.462, 0.3, 0.78), M["DashLight"], bevel=0.01))
    add(box("Glovebox", (0.02, 0.38, 0.14), (0.468, 0.33, 0.62), M["Dash"], bevel=0.008))
    add(box("GloveGap", (0.018, 0.39, 0.15), (0.472, 0.33, 0.62), M["BlackTrim"]))
    # the cluster: a hood over two dials (speed, revs) with a fuel and a temperature dial between
    hood = K.lathe("ClusterHood", [(0.13, -0.08), (0.15, -0.05), (0.16, 0.05), (0.13, 0.07)], 24, 'X', [M["Dash"]])
    me = hood.data
    for v in me.vertices:
        if v.co.z < -0.02:
            v.co.z = -0.02                                    # (a hood: open below)
    hood.scale = (0.6, 1.25, 0.6)
    hood.location = (0.5, DY, 0.9)
    add(hood)
    for nm, dy, r in (("DialSpeed", 0.07, 0.055), ("DialRPM", -0.07, 0.055), ("DialFuel", 0.0, 0.025)):
        d = K.lathe(nm, [(0.0, 0.0), (r, 0.0), (r + 0.006, -0.004)], 32, 'X', [M["Gauge"]])
        d.location = (0.475, DY + dy, 0.885 if nm != "DialFuel" else 0.86)
        d.rotation_euler = (0, math.radians(-12), 0)
        add(d)
        ring = K.lathe(nm + "Ring", [(r + 0.002, 0.002), (r + 0.008, -0.004)], 32, 'X', [M["Chrome"]])
        ring.location = d.location
        ring.rotation_euler = d.rotation_euler
        add(ring)
        nd = box(nm.replace("Dial", "Needle"), (0.002, 0.003, r * 0.85), d.location + Vector((0.004, 0, 0)), M["Taillight"])
        nd.data.transform(Matrix.Translation(Vector((0, 0, 0.42))))   # (pivots at the dial's centre)
        add(nd)
    # the centre stack: a screen, two vents, the hazard switch, climate knobs; vents at the ends too
    add(box("Screen", (0.01, 0.2, 0.12), (0.452, 0.0, 0.83), M["Screen"], bevel=0.004))
    add(box("ScreenBezel", (0.012, 0.22, 0.14), (0.456, 0.0, 0.83), M["BlackGloss"], bevel=0.006))
    for vy in (-0.12, 0.12, -0.62, 0.62):
        add(box("Vent", (0.02, 0.1, 0.05), (0.455 if abs(vy) < 0.3 else 0.47, vy, 0.73 if abs(vy) < 0.3 else 0.82), M["BlackTrim"], bevel=0.006))
        for k in range(4):
            add(box("VentSlat", (0.022, 0.095, 0.003), (0.452 if abs(vy) < 0.3 else 0.467, vy, (0.73 if abs(vy) < 0.3 else 0.82) - 0.018 + k * 0.012), M["Chrome"]))
    add(box("Hazard", (0.012, 0.025, 0.015), (0.452, 0.0, 0.745), M["Taillight"], bevel=0.003))
    for ky in (-0.08, 0.0, 0.08):
        kn = K.lathe("ClimateKnob", [(0.0, 0.0), (0.022, 0.0), (0.022, 0.02), (0.0, 0.022)], 24, 'X', [M["BlackGloss"]])
        kn.location = (0.47, ky, 0.66)
        add(kn)
    # the wheel: a rim, three spokes, the hub (an airbag cover); on its column, the stalks behind it
    piv = bpy.data.objects.new("SteeringPivot", None)
    K.link(piv)
    piv.location = (0.33, DY, 0.84)
    piv.rotation_euler = (0, math.radians(-24), 0)           # (the column leans back toward him)
    add(piv)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, segments=48, radius=0.185)
    rim = K.mesh_obj("WheelRim", bm, [M["Rubber"]])
    rim.rotation_euler = (0, math.pi / 2, 0)
    rim.parent = piv
    cu = rim.modifiers.new("Tube", 'SCREW')                  # (the rim's tube: a circle swept round)
    rim.modifiers.remove(cu)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, segments=12, radius1=0.016, radius2=0.016, depth=0.01)
    K.remove(rim)
    tor = bpy.data.meshes.new("WheelRimTorus")
    bm = bmesh.new()
    for i in range(48):
        a = 2 * math.pi * i / 48
        for j in range(10):
            b = 2 * math.pi * j / 10
            r = 0.185 + 0.017 * math.cos(b)
            bm.verts.new((0.017 * 1.2 * math.sin(b), math.cos(a) * r, math.sin(a) * r))
    bm.verts.ensure_lookup_table()
    for i in range(48):
        for j in range(10):
            a0 = i * 10 + j
            a1 = i * 10 + (j + 1) % 10
            b0 = ((i + 1) % 48) * 10 + j
            b1 = ((i + 1) % 48) * 10 + (j + 1) % 10
            bm.faces.new((bm.verts[a0], bm.verts[b0], bm.verts[b1], bm.verts[a1]))
    rim = K.mesh_obj("WheelRim", bm, [M["Rubber"]])
    K.smooth(rim, 60, weighted=False)
    rim.parent = piv
    out.append(rim)
    hub = K.lathe("WheelHub", [(0.0, 0.03), (0.055, 0.03), (0.07, 0.0), (0.06, -0.04)], 32, 'X', [M["Dash"]])
    hub.parent = piv
    out.append(hub)
    for a in (90, 210, 330):
        ang = math.radians(a)
        sp = box("WheelSpoke", (0.016, 0.03, 0.11), (0.0, math.cos(ang) * 0.12, math.sin(ang) * 0.12), M["Dash"], rot=(ang - math.pi / 2, 0, 0), bevel=0.008)
        sp.parent = piv
        out.append(sp)
    col = K.lathe("Column", [(0.035, 0.0), (0.045, 0.2), (0.06, 0.3)], 16, 'X', [M["Dash"]])
    col.location = (0.36, DY, 0.83)
    col.rotation_euler = (0, math.radians(-24), 0)
    add(col)
    for sy, nm in ((0.09, "StalkWiper"), (-0.09, "StalkIndicator")):
        add(box(nm, (0.012, 0.11, 0.012), (0.4, DY + sy * 1.6, 0.83), M["Dash"], bevel=0.004))
    # pedals (clutch, brake, accelerator) and the footwell
    for py, nm in ((-0.24, "PedalClutch"), (-0.36, "PedalBrake"), (-0.48, "PedalAccel")):
        add(box(nm, (0.015, 0.06 if nm != "PedalAccel" else 0.045, 0.07 if nm != "PedalAccel" else 0.12), (0.62, py, 0.38), M["Rubber"], rot=(0, math.radians(-25), 0), bevel=0.004))
    # seats: the fronts (cushion, back, headrest on posts), the rear bench
    def seat(name, x, y, width, back_h=0.62, mat=M["Fabric"]):
        cush = box(name + "Cushion", (0.5, width, 0.12), (x, y, 0.47), mat, rot=(0, math.radians(-6), 0), bevel=0.035)
        backr = box(name + "Back", (0.12, width, back_h), (x - 0.27, y, 0.47 + back_h / 2 + 0.04), mat, rot=(0, math.radians(-18), 0), bevel=0.035)
        for o in (cush, backr):
            o.modifiers.new("Sub", 'SUBSURF').levels = 1
        parts = [cush, backr]
        if width < 0.7:                                       # (bolsters each side of the back)
            for s2 in (-1, 1):
                parts.append(box(name + "Bolster", (0.13, 0.06, back_h * 0.8), (x - 0.24, y + s2 * (width / 2 - 0.02), 0.47 + back_h * 0.45), mat,
                                 rot=(0, math.radians(-18), 0), bevel=0.025))
        hr = box(name + "Headrest", (0.09, min(width, 0.26), 0.15), (x - 0.42, y, 0.47 + back_h + 0.15), mat, rot=(0, math.radians(-10), 0), bevel=0.03)
        parts.append(hr)
        for s2 in (-1, 1):
            parts.append(box(name + "HeadPost", (0.01, 0.01, 0.07), (x - 0.4, y + s2 * 0.07, 0.47 + back_h + 0.06), M["Chrome"]))
        return parts
    rear = []
    for k, rx in enumerate(SPEC["rows"]):                     # the rows behind: a bench each
        rear += seat("SeatRear%d" % k, rx, 0.0, 1.3, 0.6, M["Fabric"])
    for o in seat("SeatDriver", -0.08, DY, 0.5) + seat("SeatPassenger", -0.08, -DY, 0.5) + rear:
        add(o)
    # the console: the gear lever in its boot, the handbrake
    add(box("Console", (0.55, 0.2, 0.14), (0.15, 0.0, 0.43), M["Dash"], bevel=0.02))
    add(box("GearBoot", (0.07, 0.07, 0.05), (0.32, 0.0, 0.52), M["Rubber"], bevel=0.02))
    gl = K.lathe("GearLever", [(0.008, 0.0), (0.008, 0.16), (0.022, 0.17), (0.024, 0.2), (0.0, 0.215)], 16, 'Z', [M["BlackGloss"]])
    gl.location = (0.32, 0.0, 0.52)
    add(gl)
    add(box("Handbrake", (0.22, 0.03, 0.03), (-0.02, 0.0, 0.53), M["Dash"], rot=(0, math.radians(-12), 0), bevel=0.012))
    # door cards (four), each with an armrest, a pull, window switches and a speaker
    for side in (1.0, -1.0):
        for x0, x1 in ((SPEC["door_f"] - 0.1 - dx, SPEC["B"] - 0.01 - dx), (SPEC["B"] - 0.04 - dx, SPEC["door_r"] - dx)):
            xc = (x0 + x1) / 2
            add(box("DoorCard", ((x0 - x1) / 2 - 0.02, 0.02, 0.32), (xc, side * 0.75, 0.66), M["Dash"], bevel=0.01))
            add(box("DoorInsert", ((x0 - x1) / 2 - 0.12, 0.012, 0.09), (xc, side * 0.735, 0.74), M["FabricLight"], bevel=0.008))
            add(box("Armrest", ((x0 - x1) / 2 - 0.2, 0.04, 0.025), (xc - 0.05, side * 0.715, 0.62), M["Dash"], bevel=0.01))
            add(box("WindowSwitch", (0.04, 0.02, 0.01), (xc + 0.12, side * 0.71, 0.648), M["BlackGloss"]))
            sp = K.lathe("Speaker", [(0.0, 0.0), (0.06, 0.0), (0.065, 0.006)], 24, 'Y', [M["BlackTrim"]])
            sp.location = (xc + 0.15, side * 0.737, 0.45)
            add(sp)
            add(box("DoorPull", (0.05, 0.015, 0.012), (x0 - 0.12, side * 0.725, 0.8), M["Chrome"], bevel=0.004))
    # the roof: headliner, visors, the mirror, the cabin light; belts from the B pillars
    hm = (ROOF_F + ROOF_R) / 2
    add(box("Headliner", (ROOF_F - ROOF_R + 0.02, 1.2, 0.012), (hm - dx, 0.0, K.cr(TOP, hm) - 0.085 - dz), M["Headliner"], bevel=0.03))
    for vy in (DY, -DY):
        add(box("Visor", (0.02, 0.32, 0.13), (0.1, vy, 1.39), M["Headliner"], rot=(0, math.radians(70), 0), bevel=0.01))
    add(box("RearMirror", (0.012, 0.13, 0.035), (0.22, 0.0, 1.32), M["BlackTrim"], bevel=0.008))
    add(box("RearMirrorGlass", (0.002, 0.125, 0.03), (0.212, 0.0, 1.32), M["Chrome"]))
    add(box("RearMirrorStem", (0.01, 0.01, 0.06), (0.24, 0.0, 1.36), M["BlackTrim"]))
    add(box("CabinLight", (0.06, 0.12, 0.01), (-0.45, 0.0, 1.43), M["DashLight"], bevel=0.004))
    for side in (1.0, -1.0):
        add(box("Belt", (0.02, 0.004, 0.62), (SPEC["B"] - 0.03 - (COWL - 0.84), side * 0.7, 0.96), M["BlackTrim"], rot=(math.radians(-side * 8), math.radians(25), 0)))
    eye = bpy.data.objects.new("Eye", None)
    K.link(eye)
    eye.location = (SPEC["eye"][0] - (COWL - 0.84), DY, SPEC["eye"][1] - SPEC["int_dz"])   # (a seated man's eyes, ~0.79 m over the cushion)
    add(eye)
    # where the driver goes (jeep.gd seats Karthik by these): his hips on the cushion, his hands at ten to two on the
    # rim (on the pivot: they turn with it), his feet on the clutch's rest and the accelerator
    for nm, at, par in (("DriverHip", (-0.17, DY, 0.56), None), ("GripL", (0.0, 0.158, 0.092), piv), ("GripR", (0.0, -0.158, 0.092), piv),
                        ("FootL", (0.58, DY + 0.13, 0.36), None), ("FootR", (0.58, DY - 0.11, 0.37), None)):
        mk = bpy.data.objects.new(nm, None)
        K.link(mk)
        if par is not None:
            mk.parent = par
            mk.location = at
            out.append(mk)
        else:
            mk.location = at
            add(mk)
    if SPEC.get("lux"):                                       # a luxury cabin: a wide touchscreen, a digital cluster, wood
        add(box("Infotainment", (0.012, 0.36, 0.2), (0.45, 0.0, 0.9), M["Screen"], rot=(0, math.radians(-12), 0), bevel=0.006))
        add(box("InfotainmentBezel", (0.016, 0.38, 0.22), (0.456, 0.0, 0.9), M["BlackGloss"], rot=(0, math.radians(-12), 0), bevel=0.01))
        add(box("DigitalCluster", (0.004, 0.3, 0.12), (0.486, DY, 0.885), M["Screen"], rot=(0, math.radians(-12), 0)))
        add(box("DashWood", (0.012, 1.3, 0.035), (0.462, 0.0, 0.72), K._mat("Walnut", (0.2, 0.1, 0.05), rough=0.35, coat=0.6)))
        add(box("DashLeather", (0.08, 1.36, 0.03), (0.55, 0.0, 0.93), K._mat("Leather", (0.05, 0.045, 0.04), rough=0.55, coat=0.1), bevel=0.012))
        sel = box("GearSelector", (0.07, 0.05, 0.06), (0.05, 0.0, 0.53), M["Chrome"], bevel=0.02)
        add(sel)
        add(box("ConsoleTop", (0.5, 0.2, 0.02), (0.0, 0.0, 0.5), K._mat("Walnut", (0.2, 0.1, 0.05), rough=0.35, coat=0.6), bevel=0.01))
    root.location = (COWL - 0.84, 0.0, SPEC["int_dz"])       # (the cabin into this car's frame)
    return out


def extras(body, tree, M):
    """An SUV's black cladding over its arches and along its sills, and its roof rails; a luxury SUV's vent in each
    front door, the black band across its tailgate between the lamps, its twin exhaust tips."""
    out = []
    if SPEC.get("gill"):
        for side in (1.0, -1.0):
            x = SPEC["door_f"] - 0.09
            y = side * (K.cr(HALF, x) + 0.004)
            out.append(box("DoorVent", (0.06, 0.012, 0.36), (x, y, 0.86), M["Chrome"], bevel=0.015))
            out.append(box("DoorVentSlot", (0.03, 0.014, 0.3), (x, y, 0.86), M["BlackGloss"], bevel=0.008))
    if SPEC.get("tail_band"):
        out.append(box("TailBand", (0.012, 1.68, 0.11), (-HX - 0.002, 0.0, 1.27), M["BlackGloss"], bevel=0.01))
        out.append(box("TailTrim", (0.012, 1.4, 0.018), (-HX - 0.003, 0.0, 0.88), M["Chrome"]))
    if SPEC.get("lux"):
        # a panoramic glass roof; chrome round the side windows; flush door handles; a gloss-black sill line; the
        # rear LED bar across the tailgate (lit with the tail lamps: its name begins Taillight)
        roof_z = K.cr(TOP, -0.8) + 0.004
        out.append(box("PanoRoof", (1.75, 1.32, 0.012), (-0.85, 0.0, roof_z), M["GlassTint"], bevel=0.02))
        out.append(box("PanoFrame", (1.82, 1.4, 0.008), (-0.85, 0.0, roof_z - 0.004), M["BlackGloss"], bevel=0.02))
        for side in (1.0, -1.0):
            zb = K.cr(BELT, -0.6) + 0.012
            for (x0, x1) in ((0.9, -0.36), (-0.36, -2.22)):
                xm = (x0 + x1) / 2
                out.append(box("WindowChrome", (abs(x1 - x0), 0.012, 0.014), (xm, side * (K.cr(HALF, xm) - 0.05), zb), M["Chrome"]))
            for hx in (0.15, -1.0):
                out.append(box("FlushHandle", (0.2, 0.012, 0.03), (hx, side * (K.cr(HALF, hx) + 0.002), 1.04), M["BlackGloss"], bevel=0.01))
                out.append(box("HandleTrim", (0.21, 0.013, 0.006), (hx, side * (K.cr(HALF, hx) + 0.003), 1.058), M["Chrome"]))
            sl = WB - 2 * R - 0.32                            # (between the arches only)
            out.append(box("SillBlack", (sl, 0.014, 0.06), (AX_F - WB / 2, side * (K.cr(HALF, 0.0) + 0.001), 0.36), M["BlackGloss"]))
        out.append(box("Taillight_Bar", (0.012, 1.5, 0.022), (-HX - 0.004, 0.0, 1.36), M["Taillight"], bevel=0.006))
    if SPEC.get("dual_exhaust"):
        for side in (1.0, -1.0):
            out.append(box("ExhaustTip", (0.04, 0.16, 0.06), (-HX + 0.02, side * 0.55, 0.42), M["Chrome"], bevel=0.02))
    if SPEC.get("cladding"):
        for ax in (AX_F, AX_R):                               # arch flares: a band round each arch
            for side in (1.0, -1.0):
                bm = bmesh.new()
                rr0, rr1 = R + 0.04, R + 0.1
                ring0, ring1 = [], []
                for i in range(25):
                    a = math.radians(-8 + 196 * i / 24)
                    ring0.append((ax + math.cos(a) * rr0, R + 0.02 + math.sin(a) * rr0))
                    ring1.append((ax + math.cos(a) * rr1, R + 0.02 + math.sin(a) * rr1))
                vs0, vs1 = [], []
                for (x0, z0), (x1, z1) in zip(ring0, ring1):
                    y = side * (K.cr(HALF, x0) + 0.012)
                    vs0.append(bm.verts.new((x0, y, z0)))
                    vs1.append(bm.verts.new((x1, y - side * 0.01, z1)))
                for i in range(len(vs0) - 1):
                    bm.faces.new((vs0[i], vs0[i + 1], vs1[i + 1], vs1[i]))
                fl = K.mesh_obj("ArchFlare", bm, [M["BlackTrim"]])
                so = fl.modifiers.new("S", 'SOLIDIFY')
                so.thickness = 0.025
                out.append(fl)
        for side in (1.0, -1.0):                              # sill cladding between the arches
            x0, x1 = AX_F - R - 0.1, AX_R + R + 0.1
            z = K.cr(BOT, 0.0) + 0.07
            y = side * (W / 2 + 0.005)
            out.append(box("SillClad", ((x0 - x1) / 2 * 2, 0.03, 0.12), ((x0 + x1) / 2, y, z), M["BlackTrim"], bevel=0.01))
    if SPEC.get("rails"):
        for side in (1.0, -1.0):
            pts = []
            for i in range(11):
                x = ROOF_F - 0.15 + (ROOF_R + 0.1 - (ROOF_F - 0.15)) * i / 10
                a, _n = hit(tree, (x, side * (K.cr(HALF, x) - TUMBLE - 0.08), 3.0), (0, 0, -1))
                if a:
                    pts.append(a)
            if len(pts) > 2:
                bm = bmesh.new()
                prev = None
                for p in pts:
                    q0 = bm.verts.new(p + Vector((0, -0.012, 0.045)))
                    q1 = bm.verts.new(p + Vector((0, 0.012, 0.045)))
                    if prev:
                        bm.faces.new((prev[0], prev[1], q1, q0))
                    prev = (q0, q1)
                rl = K.mesh_obj("RoofRail", bm, [M["Alloy"]])
                so = rl.modifiers.new("S", 'SOLIDIFY')
                so.thickness = 0.025
                out.append(rl)
                for p in (pts[0], pts[-1]):
                    out.append(box("RailFoot", (0.08, 0.03, 0.05), p + Vector((0, 0, 0.022)), M["BlackTrim"], bevel=0.008))
    return out


def finish(body, M, extra):
    """The body: its glass and trim split off by material, the paint a 10 mm skin. Every part stays a top-level
    object (the game knows lamps and glass by their top-level names: Headlight_*, DRL_*, Taillight_*, Glass_*)."""
    root = None
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.separate(type='MATERIAL')
    bpy.ops.object.mode_set(mode='OBJECT')
    parts = [o for o in bpy.context.selected_objects]
    for o in parts:
        mats = [m.name for m in o.data.materials if m]
        used = {o.data.materials[p.material_index].name for p in o.data.polygons if o.data.materials[p.material_index]}
        main = next(iter(used)) if used else "Body"
        o.name = "Body" if main == "Paint" else ("Glass_" + main if main.startswith("Glass") else "Trim_" + main)
        th = 0.004 if main.startswith("Glass") else (0.01 if main == "Paint" else 0.006)
        so = o.modifiers.new("Skin", 'SOLIDIFY')
        so.thickness = th
        so.offset = -1.0
        if main == "Paint":                                     # (its inside: the cabin's trim, not paint: the pillars,
            o.data.materials.append(M["DashLight"])            #  the door frames, seen from the seat)
            so.material_offset = len(o.data.materials) - 1
        K.apply_mods(o)
    return root


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    kind = args[args.index("--kind") + 1] if "--kind" in args else "sedan"
    use(kind)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = K.materials(SPEC["paint"])
    body = build_body(M)
    print("CAR %s loft %d faces" % (kind, len(body.data.polygons)), flush=True)
    cut_panels(body)
    names = [m.name if m else "-" for m in body.data.materials]
    got = openings(body, M, names)
    print("CAR openings (faces): %s, body %d faces" % (got, len(body.data.polygons)), flush=True)
    liners = cut_arches(body, M)
    K.smooth(body, 32)
    extra = list(liners)
    extra += lamps(body, M)
    tree = surface(body)
    extra += front_trim(body, tree, M)
    extra += side_trim(body, tree, M)
    extra += extras(body, tree, M)
    extra += wheels(M)
    extra += interior(M)
    finish(body, M, extra)
    tris = 0
    dg = bpy.context.evaluated_depsgraph_get()
    for o in bpy.data.objects:
        if o.type == 'MESH' and not o.name.startswith("Preview"):
            ev = o.evaluated_get(dg)
            tris += sum(len(p.vertices) - 2 for p in ev.data.polygons)
    print("CAR %s done: %d objects, %d triangles" % (kind, len([o for o in bpy.data.objects if o.type == 'MESH']), tris), flush=True)
    if "--export" in args:
        out = args[args.index("--export") + 1]
        bpy.ops.object.select_all(action='DESELECT')
        for o in bpy.data.objects:
            if not o.name.startswith("Preview"):
                o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_yup=True,
                                  export_apply=True, export_image_format='JPEG')
        print("CAR exported %s (%.1f MB)" % (out, os.path.getsize(out) / 1e6), flush=True)
    if "--preview" in args:
        d = args[args.index("--preview") + 1]
        os.makedirs(d, exist_ok=True)
        K.previews(os.path.join(d, kind), target=Vector((0, 0, H * 0.45)), dist=L * 1.55)

if __name__ != "probe":
    main()
