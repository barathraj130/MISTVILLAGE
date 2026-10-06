"""
Car cabins built to fit the bodies from tools/carbody.py (same SPECS, same frame): a sculpted dash with a
hooded cluster, centre stack, screen, slatted vents and climate knobs; a three-spoke wheel with an airbag
hub, column shroud and stalks; bolstered seats with inserts and headrests on posts; door cards (armrest,
pull, handle, window switches, speaker, pocket); pillar trims, headliner, visors, rear-view mirror, dome
lamp and grab handles; console with gear lever, handbrake and cupholders; pedals and carpet.

    Blender -b --factory-startup --python tools/carcabin.py -- <out_dir> [hatchback sedan taxi]

Exports interior_<kind>.glb with the markers the game uses: "Eye" (driver's eyes), "SteeringPivot"
(local Z = column, the wheel turns about it) and "Cluster" (where the gauges go). Driver sits on the
right (India): -Y.
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import carbody as CB  # noqa: E402
import interiors as IN  # noqa: E402  (empties, export)

STYLE = {
    # upper dash, lower dash, seat sides, seat insert, accents, door insert, headliner, gearbox
    "hatchback": dict(up=(0.06, 0.06, 0.065), low=(0.42, 0.4, 0.37), side=(0.1, 0.1, 0.11), insert=(0.32, 0.33, 0.36),
                      accent=(0.55, 0.56, 0.58), door=(0.36, 0.35, 0.33), head=(0.62, 0.6, 0.57), manual=True, screen=0.17),
    "sedan": dict(up=(0.03, 0.03, 0.035), low=(0.55, 0.47, 0.37), side=(0.5, 0.42, 0.33), insert=(0.62, 0.54, 0.43),
                  accent=(0.32, 0.17, 0.08), door=(0.55, 0.47, 0.37), head=(0.68, 0.65, 0.6), manual=False, screen=0.23),
    "taxi": dict(up=(0.06, 0.06, 0.065), low=(0.3, 0.29, 0.28), side=(0.92, 0.92, 0.9), insert=(0.95, 0.95, 0.93),
                 accent=(0.5, 0.5, 0.52), door=(0.3, 0.29, 0.28), head=(0.62, 0.6, 0.57), manual=True, screen=0.0),
}
BODY = {"taxi": "sedan"}


def mats(st):
    m = IN.mat
    return {
        "up": m("DashUpper", st["up"], 0.75), "low": m("DashLower", st["low"], 0.8), "side": m("SeatSide", st["side"], 0.7),
        "insert": m("SeatInsert", st["insert"], 0.95), "accent": m("Accent", st["accent"], 0.3, 0.6 if st["accent"][0] > 0.4 else 0.0),
        "door": m("DoorInsert", st["door"], 0.85), "head": m("Headliner", st["head"], 0.95),
        "black": m("PianoBlack", (0.01, 0.01, 0.012), 0.12), "dark": m("DarkPlastic", (0.035, 0.035, 0.04), 0.6),
        "chrome": m("Chrome", (0.75, 0.75, 0.77), 0.18, 1.0), "carpet": m("Carpet", (0.05, 0.05, 0.055), 1.0),
        "rubber": m("Rubber", (0.02, 0.02, 0.02), 0.85), "screen": m("Screen", (0.02, 0.03, 0.05), 0.1, 0, (0.15, 0.32, 0.55), 1.2),
        "gauge": m("GaugeFace", (0.02, 0.02, 0.025), 0.4), "lamp": m("Lamp", (0.95, 0.93, 0.88), 0.4, 0, (1, 0.95, 0.85), 0.6),
        "leather": m("Leather", (0.08, 0.07, 0.065), 0.55), "meter": m("Meter", (0.05, 0.02, 0.02), 0.3, 0, (1.0, 0.2, 0.1), 2.0),
        "switch": m("Switch", (0.06, 0.06, 0.07), 0.4),
    }


# ----------------------------------------------------------------------------- primitives
def box(loc, dims, m, bev=0.0, rot=(0, 0, 0), soft=False):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(m)
    if bev:
        b = o.modifiers.new("Bevel", 'BEVEL')
        b.width = min(bev, min(dims) * 0.45)
        b.segments = 3 if soft else 1
    if soft:
        s = o.modifiers.new("Sub", 'SUBSURF')
        s.levels = 1
        s.render_levels = 1
        for p in o.data.polygons:
            p.use_smooth = True
    return o


def cyl(loc, r, depth, m, rot=(0, 0, 0), verts=20):
    return IN.cyl(loc, r, depth, m, rot, verts)


def beam(p0, p1, wid, hgt, m, soft=False):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    o = box((p0 + p1) / 2, (d.length, wid, hgt), m, bev=min(wid, hgt) * 0.3 if soft else 0.0, soft=soft)
    o.rotation_euler = d.to_track_quat('X', 'Z').to_euler()
    return o


def group(parts, pivot, rot):
    """Rotate parts about a pivot point (Euler XYZ), keeping them as loose objects."""
    R = Matrix.Translation(pivot) @ rot.to_matrix().to_4x4() @ Matrix.Translation(-Vector(pivot))
    for p in parts:
        p.matrix_world = R @ p.matrix_world


def sphere(loc, r, m, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=r, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    o.data.materials.append(m)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


# ----------------------------------------------------------------------------- pieces
def seat(x, y, z, M, w=0.5, front=True, lean=-15):
    """Bolstered seat: cushion with side bolsters and a fabric insert, backrest likewise, headrest on posts."""
    parts = []
    box((x, y, z), (0.5, w, 0.13), M["side"], bev=0.04, soft=True)
    box((x + 0.01, y, z + 0.07), (0.42, w * 0.56, 0.03), M["insert"], bev=0.01, soft=True)
    if front:
        for s in (1, -1):
            beam((x - 0.24, y + s * (w / 2 - 0.05), z + 0.06), (x + 0.22, y + s * (w / 2 - 0.05), z + 0.07), 0.09, 0.08, M["side"], soft=True)
    bx, bz = x - 0.27, z + 0.06                                  # backrest hinge
    back = [box((bx - 0.02, y, bz + 0.33), (0.12, w, 0.62), M["side"], bev=0.04, soft=True),
            box((bx + 0.045, y, bz + 0.31), (0.02, w * 0.56, 0.48), M["insert"], bev=0.008, soft=True)]
    if front:
        for s in (1, -1):
            back.append(box((bx + 0.02, y + s * (w / 2 - 0.05), bz + 0.3), (0.12, 0.09, 0.5), M["side"], bev=0.03, soft=True))
    back.append(box((bx - 0.03, y, bz + 0.78), (0.1, w * 0.52, 0.17), M["side"], bev=0.04, soft=True))          # headrest
    for s in (1, -1):
        back.append(cyl((bx - 0.03, y + s * 0.07, bz + 0.66), 0.007, 0.1, M["chrome"], verts=8))
    group(back, (bx, y, bz), Euler((0, math.radians(lean), 0)))
    parts += back
    box((x, y, z - 0.12), (0.4, w * 0.75, 0.12), M["dark"], bev=0.01)                                       # base
    return parts


def vent(x, y, z, M, w=0.12, h=0.06, facing=Vector((-1, 0, 0))):
    box((x, y, z), (0.02, w + 0.016, h + 0.016), M["accent"], bev=0.004)
    box((x - 0.006, y, z), (0.02, w, h), M["black"])
    for k in range(4):
        box((x - 0.014, y, z - h / 2 + h * (k + 0.5) / 4), (0.008, w * 0.96, 0.006), M["dark"])


def steering(centre, deg, r, M, spokes=3):
    a = math.radians(deg)
    piv = IN.empty("SteeringPivot", centre)
    zax = Vector((-math.cos(a), 0, math.sin(a)))
    xax = Vector((0, 1, 0))
    yax = zax.cross(xax)
    piv.matrix_world = Matrix.Translation(centre) @ Matrix((xax, yax, zax)).transposed().to_4x4()
    parts = []
    bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=0.019, major_segments=48, minor_segments=12)
    t = bpy.context.active_object
    t.data.materials.append(M["leather"])
    for p in t.data.polygons:
        p.use_smooth = True
    parts.append(t)
    low = math.pi / 2                                           # (this pivot's local +Y points down the wheel)
    for ang in (0.0, math.pi, low):                             # spokes at 3, 9 and 6 o'clock
        ln = r * 0.82 if ang != low else r * 0.8
        sp = box((math.cos(ang) * ln * 0.55, math.sin(ang) * ln * 0.55, 0.012), (ln, 0.05 if ang != low else 0.06, 0.016),
                 M["dark"], bev=0.006, rot=(0, 0, ang))
        parts.append(sp)
        if ang != low:                                 # button pads on the side spokes
            parts.append(box((math.cos(ang) * r * 0.5, 0.0, 0.024), (0.05, 0.035, 0.006), M["switch"], bev=0.003, rot=(0, 0, ang)))
    hub = box((0, 0, 0.03), (0.13, 0.11, 0.045), M["dark"], bev=0.025, soft=True)         # airbag
    parts.append(hub)
    parts.append(cyl((0, 0, -0.03), 0.045, 0.06, M["dark"], verts=16))
    for p in parts:
        p.parent = piv
        p.matrix_parent_inverse = Matrix.Identity(4)
    # column shroud and stalks (not turning)
    base = Vector(centre) - zax * 0.16
    beam(base - zax * 0.12, base + zax * 0.08, 0.1, 0.1, M["dark"], soft=True)
    for s in (1, -1):
        beam(base + Vector((0, s * 0.04, 0.02)), base + Vector((-0.02, s * 0.17, 0.04)), 0.016, 0.016, M["dark"])
    return piv


# ----------------------------------------------------------------------------- the cabin
def cabin(kind):
    st = STYLE[kind]
    sp = CB.SPECS[BODY.get(kind, kind)]
    M = mats(st)
    top = lambda x: CB.cr(sp["top"], x)          # noqa: E731
    belt = lambda x: CB.cr(sp["belt"], x)        # noqa: E731
    half = lambda x: CB.cr(sp["half"], x)        # noqa: E731
    g0, g1 = sp["glass"]
    ws = sp["ws_top"]
    roof = max(z for _, z in sp["top"])
    bx = sp["pillars"][0][0]
    tum = sp["tumble"]
    yd = -0.37                                   # driver (right-hand drive)
    xd = g0 - 0.5                                # dash face
    zt = belt(g0) + 0.02                         # dash top at the windscreen
    hw = half(xd) - 0.07
    # --- dashboard: a swept profile across the car
    prof = [(g0 - 0.01, zt - 0.01), (xd + 0.14, zt + 0.07), (xd + 0.02, zt + 0.05), (xd - 0.01, zt - 0.02),
            (xd + 0.02, zt - 0.2), (xd + 0.1, 0.56), (xd + 0.3, 0.5), (g0 - 0.08, 0.6)]
    import bmesh
    bm = bmesh.new()
    rings = []
    ny = 24
    for i in range(ny + 1):
        y = -hw + 2 * hw * i / ny
        edge = 1.0 - 0.6 * (abs(y) / hw) ** 6               # the dash ends round off into the doors
        rings.append([bm.verts.new((px if k < 2 or k > 5 else px + (1 - edge) * 0.1, y, pz)) for k, (px, pz) in enumerate(prof)])
    for a, b in zip(rings, rings[1:]):
        for k in range(len(prof)):
            bm.faces.new((a[k], a[(k + 1) % len(prof)], b[(k + 1) % len(prof)], b[k]))
    for ring, rev in ((rings[0], True), (rings[-1], False)):
        f = bm.faces.new(ring[::-1] if rev else ring)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Dash")
    bm.to_mesh(me)
    bm.free()
    dash = bpy.data.objects.new("Dash", me)
    bpy.context.scene.collection.objects.link(dash)
    dash.data.materials.append(M["up"])
    dash.data.materials.append(M["low"])
    for p in dash.data.polygons:
        p.material_index = 0 if p.center.z > zt - 0.06 else 1
        p.use_smooth = True
    bev = dash.modifiers.new("Bevel", 'BEVEL')
    bev.width = 0.02
    bev.segments = 2
    # accent strip across the dash face, glovebox, passenger airbag seam
    box((xd - 0.015, 0.12, zt - 0.07), (0.012, 1.0, 0.03), M["accent"], bev=0.004)
    box((xd + 0.02, 0.4, zt - 0.17), (0.01, 0.36, 0.004), M["dark"])
    box((xd + 0.02, 0.4, zt - 0.17), (0.012, 0.07, 0.02), M["chrome"], bev=0.003)
    # cluster: a hood over the driver and a black gauge panel facing the eyes
    hood = IN.cyl((xd + 0.08, yd, zt + 0.04), 0.15, 0.16, M["up"], rot=(0, math.pi / 2, 0), verts=32)
    hood.scale = (0.55, 1.0, 1.0)
    box((xd + 0.06, yd, zt - 0.01), (0.03, 0.3, 0.12), M["gauge"], bev=0.01, rot=(0, math.radians(-12), 0))
    for dy in (-0.075, 0.075):
        cyl((xd + 0.045, yd + dy, zt - 0.01), 0.052, 0.008, M["chrome"], rot=(0, math.pi / 2 - math.radians(12), 0), verts=28)
    IN.empty("Cluster", (xd + 0.04, yd, zt - 0.01))
    # centre stack: screen, vents, climate knobs
    if st["screen"] >= 0.2:
        box((xd + 0.06, 0.0, zt + 0.12), (0.02, st["screen"] + 0.02, st["screen"] * 0.6), M["black"], bev=0.008)   # floating tablet
        box((xd + 0.048, 0.0, zt + 0.12), (0.006, st["screen"], st["screen"] * 0.56), M["screen"])
        vent(xd - 0.005, -0.08, zt - 0.06, M)
        vent(xd - 0.005, 0.08, zt - 0.06, M)
    elif st["screen"] > 0:
        box((xd - 0.01, 0.0, zt - 0.06), (0.02, st["screen"] + 0.02, 0.11), M["black"], bev=0.006)
        box((xd - 0.02, 0.0, zt - 0.06), (0.006, st["screen"], 0.09), M["screen"])
        vent(xd - 0.005, -0.14, zt - 0.06, M, w=0.06, h=0.07)
        vent(xd - 0.005, 0.14, zt - 0.06, M, w=0.06, h=0.07)
    else:                                                                    # taxi: radio + fare meter
        box((xd - 0.01, 0.0, zt - 0.06), (0.02, 0.18, 0.06), M["black"], bev=0.006)
        box((xd + 0.08, -0.12, zt + 0.1), (0.1, 0.16, 0.07), M["dark"], bev=0.01)
        box((xd + 0.025, -0.12, zt + 0.1), (0.004, 0.12, 0.04), M["meter"])
    for s in (1, -1):                                                        # outboard vents
        vent(xd - 0.005, s * (hw - 0.12), zt - 0.05, M, w=0.1, h=0.07)
    box((xd + 0.0, 0.0, zt - 0.2), (0.03, 0.26, 0.09), M["black"], bev=0.01)              # climate panel
    for dy in (-0.08, 0.0, 0.08):
        cyl((xd - 0.02, dy, zt - 0.2), 0.022, 0.03, M["accent"], rot=(0, math.pi / 2, 0), verts=24)
    # --- console, gear lever, handbrake, cupholders
    xs = xd - 0.82                                                           # front seat cushion centre
    box(((xd + xs) / 2 - 0.05, 0, 0.42), (xd - xs + 0.05, 0.22, 0.28), M["low"], bev=0.03, soft=True)
    box(((xd + xs) / 2 - 0.05, 0, 0.565), (xd - xs, 0.2, 0.01), M["black"], bev=0.003)
    for k in range(2):
        cyl((xd - 0.32 - k * 0.09, 0, 0.565), 0.035, 0.012, M["dark"], verts=20)
    if st["manual"]:
        cyl((xd - 0.15, 0, 0.6), 0.008, 0.18, M["chrome"], verts=8)
        sphere((xd - 0.15, 0, 0.7), 0.028, M["leather"], (1.0, 1.0, 0.9))
        IN.cyl((xd - 0.15, 0, 0.6), 0.05, 0.05, M["rubber"], verts=16).scale = (1, 1, 0.6)        # gaiter
        beam((xs + 0.1, 0.0, 0.58), (xs + 0.32, 0.0, 0.63), 0.03, 0.03, M["dark"], soft=True)    # handbrake
    else:
        box((xd - 0.17, 0, 0.62), (0.07, 0.05, 0.08), M["leather"], bev=0.02, soft=True)
        box((xd - 0.17, 0, 0.575), (0.12, 0.08, 0.01), M["chrome"], bev=0.003)
        box((xs - 0.05, 0, 0.6), (0.3, 0.2, 0.06), M["leather"], bev=0.025, soft=True)            # armrest
    # --- steering wheel
    wc = (xd - 0.27, yd, zt - 0.06)
    steering(wc, 24.0, 0.185, M)
    # --- seats
    seat(xs, yd, 0.44, M)
    seat(xs, -yd, 0.44, M)
    xr = xs - 0.86
    seat(xr, 0.0, 0.42, M, w=1.25, front=False, lean=-20)
    for s in (1, -1):
        box((xr - 0.32, s * 0.4, 0.98), (0.09, 0.24, 0.13), M["side"], bev=0.03, soft=True)   # rear headrests
    # --- pedals
    pz = 0.36
    pedals = [(yd - 0.1, 0.05, 0.12)] + [(yd + 0.04, 0.09, 0.07)] + ([(yd + 0.17, 0.07, 0.07)] if st["manual"] else [])
    for (py, w, h) in pedals:
        box((xd + 0.12, py, pz), (0.02, w, h), M["rubber"], bev=0.004, rot=(0, math.radians(-25), 0))
    # --- floor carpet
    box(((xd + 0.3 + xr - 0.4) / 2, 0, 0.27), (xd + 0.3 - xr + 0.4, 2 * hw, 0.02), M["carpet"])
    # --- door cards (front and rear) and pillar trims
    xr_end = sp["dlo_end"] + 0.12
    for s in (1, -1):
        for (x0, x1) in ((g0 - 0.12, bx + 0.05), (bx - 0.05, xr_end)):
            xm = (x0 + x1) / 2
            yy = s * (half(xm) - 0.075)
            bz = belt(xm)
            box((xm, yy, (0.32 + bz) / 2), (x0 - x1, 0.03, bz - 0.32), M["low"], bev=0.01)
            box((xm, yy - s * 0.02, bz - 0.17), (x0 - x1 - 0.12, 0.012, 0.16), M["door"], bev=0.006)   # insert
            box((xm - 0.05, yy - s * 0.045, bz - 0.27), (x0 - x1 - 0.2, 0.07, 0.045), M["up"], bev=0.015, soft=True)  # armrest
            box((x0 - 0.12, yy - s * 0.022, bz - 0.12), (0.08, 0.012, 0.025), M["chrome"], bev=0.004)       # handle
            cyl((xm + 0.05, yy - s * 0.018, 0.48), 0.07, 0.008, M["dark"], rot=(math.pi / 2, 0, 0), verts=24)  # speaker
            box((xm, yy - s * 0.035, 0.4), (x0 - x1 - 0.2, 0.04, 0.08), M["up"], bev=0.01)                     # pocket
            box((xm + 0.12, yy - s * 0.05, bz - 0.245), (0.08, 0.03, 0.012), M["switch"], bev=0.003)          # window switch
            box((xm, yy - s * 0.01, bz + 0.005), (x0 - x1, 0.05, 0.02), M["up"], bev=0.006)                   # sill
        # A pillar (along the windscreen edge), B pillar, C pillar
        beam((g0 - 0.06, s * (half(g0) - 0.17), belt(g0) + 0.03), (ws + 0.03, s * (half(ws) - tum - 0.05), top(ws) - 0.04),
             0.085, 0.035, M["head"], soft=True)
        box((bx, s * (half(bx) - tum * 0.55 - 0.05), (belt(bx) + roof) / 2), (0.13, 0.04, roof - belt(bx) - 0.06), M["head"], bev=0.01)
        box((xr_end - 0.08, s * (half(xr_end) - tum * 0.6 - 0.05), (belt(xr_end) + roof) / 2 - 0.03), (0.22, 0.05, roof - belt(xr_end) - 0.1),
            M["head"], bev=0.01)
        box((bx - 0.1, s * (half(bx) - tum - 0.03), roof - 0.09), (0.18, 0.03, 0.025), M["dark"], bev=0.008)   # grab handle
    # --- headliner, visors, mirror, dome lamp
    xh0, xh1 = ws - 0.02, (sp["rear_glass"] + 0.05 if sp["tailgate"] else g1 + 0.25)
    box(((xh0 + xh1) / 2, 0, roof - 0.04), (xh0 - xh1, 2 * (half(0) - tum - 0.03), 0.02), M["head"], bev=0.01)
    for s in (1, -1):
        box((ws - 0.08, s * 0.33, roof - 0.065), (0.17, 0.42, 0.022), M["head"], bev=0.01, soft=True)
    beam((ws - 0.01, 0, roof - 0.05), (ws - 0.05, 0, top(ws) - 0.11), 0.02, 0.02, M["dark"])
    box((ws - 0.06, 0, top(ws) - 0.14), (0.03, 0.25, 0.065), M["dark"], bev=0.015, soft=True)
    box((ws - 0.08, 0, top(ws) - 0.14), (0.004, 0.23, 0.05), M["chrome"])
    box((-0.3, 0, roof - 0.055), (0.12, 0.2, 0.012), M["lamp"], bev=0.004)
    # --- the eyes
    IN.empty("Eye", (xs - 0.13, yd, roof - 0.31))


def finish(out):
    IN.finish(out)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(args[0] if args else "godot/assets/vehicles")
    kinds = args[1:] or list(STYLE.keys())
    os.makedirs(out_dir, exist_ok=True)
    for kind in kinds:
        IN.reset()
        cabin(kind)
        finish(os.path.join(out_dir, "interior_%s.glb" % kind))
