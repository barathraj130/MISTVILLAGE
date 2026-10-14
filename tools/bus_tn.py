"""
A Tamil Nadu state-transport style express bus (our own design, no maker badges, a fictional operator):
cream upper body, a blue band with a red pinstripe, deep yellow-orange skirt; a black front with a big split
windscreen and an LED destination board (EXP in red, the destination in green); twin round headlamps in black
pods on the bumper; long "rabbit-ear" mirrors on stalks; a row of sliding passenger windows with black pillars;
the passenger door on the left behind the front wheel and one mid-way; dual rear wheels; a roof hatch; a lit
interior with rows of seats and yellow grab poles you can see through the glass.
+X is the nose, +Y the bus's left (the door side), Z up. 11.2 m long, 2.55 m wide, 3.2 m tall.

    Blender -b --factory-startup --python tools/bus_tn.py -- --preview out.png
    Blender -b --factory-startup --python tools/bus_tn.py -- --export godot/assets/vehicles/fleet_bus.glb
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fleet as F  # noqa: E402

L, W, H = 11.2, 2.55, 3.2
FLOOR = 1.05                 # passenger floor height
WIN0, WIN1 = 1.75, 2.75      # window band
FRONT = L / 2
REAR = -L / 2
FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
DEST = "OOTY"
OPERATOR = "KOVAI ROAD TRANSPORT"


def mats():
    M = F.mats((0.95, 0.87, 0.62))
    M.update({
        "cream": F.make_mat("Paint", (0.93, 0.72, 0.32), rough=0.35, coat=0.6),
        "yellow": F.make_mat("Bus Yellow", (0.98, 0.39, 0.02), rough=0.35, coat=0.6),
        "blue": F.make_mat("Bus Blue", (0.01, 0.04, 0.32), rough=0.35, coat=0.6),
        "red": F.make_mat("Bus Red", (0.75, 0.06, 0.05), rough=0.4),
        "led_g": F.make_mat("LED Green", (0.1, 0.9, 0.3), rough=0.3, emission=(0.2, 1.0, 0.35), strength=4.0),
        "led_r": F.make_mat("LED Red", (0.9, 0.08, 0.05), rough=0.3, emission=(1.0, 0.1, 0.05), strength=4.0),
        "board": F.make_mat("Board", (0.01, 0.01, 0.012), rough=0.4),
        "seat_b": F.make_mat("Seat Blue", (0.08, 0.18, 0.45), rough=0.8),
        "pole": F.make_mat("Grab Pole", (0.9, 0.7, 0.05), rough=0.35, metallic=0.4),
        "floor": F.make_mat("Bus Floor", (0.22, 0.2, 0.18), rough=0.9),
        "ceil": F.make_mat("Bus Ceiling", (0.85, 0.85, 0.82), rough=0.8),
        "tube": F.make_mat("Tube Light", (0.95, 0.95, 0.9), rough=0.3, emission=(1, 1, 0.95), strength=2.0),
        "white": F.make_mat("White Text", (0.95, 0.95, 0.92), rough=0.5),
        "rubber": F.make_mat("Door Rubber", (0.02, 0.02, 0.02), rough=0.8),
    })
    M["livery"] = img_mat("Livery", "livery.png")
    M["board_f"] = img_mat("Board Front", "board_front.png", emit=3.0, coat=0.0)
    M["board_r"] = img_mat("Board Rear", "board_rear.png", emit=3.0, coat=0.0)
    M["route"] = img_mat("Route Board", "board_route.png", emit=0.6, coat=0.0)
    g = bpy.data.materials.new("Glass")
    g.use_nodes = True
    b = g.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.35, 0.45, 0.45, 1)
    b.inputs["Roughness"].default_value = 0.02
    for nm in ("Transmission Weight", "Transmission"):
        if nm in b.inputs:
            b.inputs[nm].default_value = 0.92
    M["glass"] = g
    return M


def text(t, loc, rot, size, mat, width=None, align='CENTER'):
    f = bpy.data.fonts.load(FONT, check_existing=True)
    bpy.ops.object.text_add(location=loc, rotation=rot)
    o = bpy.context.active_object
    o.data.body = t
    o.data.font = f
    o.data.size = size
    o.data.align_x = align
    o.data.align_y = 'CENTER'
    o.data.extrude = 0.004
    bpy.context.view_layer.update()
    if width and o.dimensions.x > width:
        o.scale = (width / o.dimensions.x, 1, 1)
    bpy.ops.object.convert(target='MESH')
    o.data.materials.clear()
    o.data.materials.append(mat)
    o.name = "Text"
    return o


ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "bus")
S = 4096.0 / 11.2                 # livery pixels per metre (godot/tools/paint_livery.gd)
SIDE, FW = 1170.0, 933.0


def img_mat(name, file, emit=0.0, rough=0.4, coat=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(os.path.join(ART, file), check_existing=True)
    nt.links.new(t.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough
    for nm in ("Coat Weight", "Clearcoat"):
        if nm in p.inputs:
            p.inputs[nm].default_value = coat
    if emit:
        for nm in ("Emission Color", "Emission"):
            if nm in p.inputs:
                nt.links.new(t.outputs["Color"], p.inputs[nm])
        p.inputs["Emission Strength"].default_value = emit
    return m


def picture(name, centre, w, h, mat, facing=1):
    """A flat board showing a whole image the right way round, facing +X (front) or -X (rear)."""
    x, y, z = centre
    s = facing
    verts = [(x, y - s * w / 2, z - h / 2), (x, y + s * w / 2, z - h / 2), (x, y + s * w / 2, z + h / 2), (x, y - s * w / 2, z + h / 2)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], [(0, 1, 2, 3) if s > 0 else (3, 2, 1, 0)])
    me.update()
    uv = me.uv_layers.new()
    for li, (u, v) in zip(me.polygons[0].loop_indices, [(0, 0), (1, 0), (1, 1), (0, 1)] if s > 0 else [(0, 1), (1, 1), (1, 0), (0, 0)]):
        uv.data[li].uv = (u, v)
    o = F.link(bpy.data.objects.new(name, me))
    o.data.materials.append(mat)
    return o


def cutter(c, s):
    o = F.box("Cutter", c, s, bpy.data.materials.get("Cutter") or bpy.data.materials.new("Cutter"), bev=0)
    o.display_type = 'WIRE'
    return o


def uv_livery(ob):
    """Wrap the livery image round the shell: each face takes its place on the sheet by which way it faces."""
    import bmesh
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        for lp in f.loops:
            x, y, z = lp.vert.co
            if abs(n.y) >= max(abs(n.x), abs(n.z)) * 0.8:
                if n.y > 0:                                         # left side, nose at the image's left
                    px, py = (FRONT - x) * S, (H - z) * S
                else:                                               # right side, nose at the image's right
                    px, py = (x - REAR) * S, SIDE + (H - z) * S
            elif abs(n.x) > abs(n.z):
                if n.x > 0:                                         # front: bus's right at the image's left
                    px, py = (y + W / 2) * S, 2 * SIDE + (H - z) * S
                else:                                               # rear: bus's left at the image's left
                    px, py = FW + (W / 2 - y) * S, 2 * SIDE + (H - z) * S
            else:                                                   # roof and floor
                px, py = (FRONT - x) * S, 3 * SIDE + 40 + (y + W / 2) * S * 0.5
            lp[uv].uv = (px / 4096.0, 1.0 - py / 4096.0)
    bm.to_mesh(me)
    bm.free()


def body(M):
    """One rounded shell (lofted, rounded roof edges and corners) with the window band, windscreen, rear window
    and doorways cut out of it, wearing the painted livery."""
    keys = [(REAR, W / 2 - 0.04, 0.36, H - 0.05, 0), (REAR + 0.12, W / 2, 0.33, H, 0), (0.0, W / 2, 0.33, H, 0),
            (FRONT - 0.12, W / 2, 0.33, H - 0.01, 0), (FRONT, W / 2 - 0.05, 0.36, H - 0.07, 0)]
    shell = F.loft("Shell", keys, M["livery"], n_top=7.0, n_bot=14.0, segs=56, steps=2, sub=1)
    bpy.context.view_layer.objects.active = shell
    bpy.ops.object.modifier_apply(modifier="Subsurf")
    cuts = []
    for s in (1, -1):
        cuts.append(cutter((-0.35, s * (W / 2 + 0.1), (WIN0 + WIN1) / 2), (L - 1.6 - 1.4, 0.5, WIN1 - WIN0)))
        cuts.append(cutter((FRONT - 0.95, s * (W / 2 + 0.1), (WIN0 + WIN1) / 2 - 0.08), (1.1, 0.5, WIN1 - WIN0 + 0.16)))
    cuts.append(cutter((FRONT + 0.1, 0, 2.05), (0.6, W - 0.22, 1.46)))                # windscreen 1.32 … 2.78
    cuts.append(cutter((REAR - 0.1, 0, 2.3), (0.6, W - 0.5, 0.85)))                   # rear window
    for xc in DOORS:                                                                      # doorways (left side)
        cuts.append(cutter((xc, W / 2 + 0.1, (0.4 + WIN1) / 2), (0.98, 0.5, WIN1 - 0.4)))
    for x in (FRONT - 1.75, REAR + 3.05):                                                # wheel arches
        c = F.cyl("Cutter", (x, 0, 0.52), 0.63, W + 1.0, bpy.data.materials.get("Cutter") or bpy.data.materials.new("Cutter"),
                  rot=(math.pi / 2, 0, 0), verts=40)
        cuts.append(c)
    for c in cuts:
        m = shell.modifiers.new("Cut", 'BOOLEAN')
        m.operation = 'DIFFERENCE'
        m.object = c
        m.solver = 'EXACT'
        bpy.context.view_layer.objects.active = shell
        bpy.ops.object.modifier_apply(modifier=m.name)
        bpy.data.objects.remove(c, do_unlink=True)
    F.smooth(shell)
    uv_livery(shell)
    # window band: glass a little inside, black rubber frames, pillars between sliding windows
    n = 9
    x0, x1 = REAR + 0.4 + 0.3, FRONT - 1.6 - 0.15
    for s in (1, -1):
        y = s * (W / 2 - 0.05)
        F.box("GlassSide", ((x0 + x1) / 2, y, (WIN0 + WIN1) / 2), (x1 - x0, 0.015, WIN1 - WIN0), M["glass"], bev=0)
        for k in range(n + 1):
            x = x0 + (x1 - x0) * k / n
            F.box("Pillar", (x, s * (W / 2 - 0.03), (WIN0 + WIN1) / 2), (0.13, 0.07, WIN1 - WIN0 + 0.02), M["black"], bev=0.015)
        for k in range(n):
            x = x0 + (x1 - x0) * (k + 0.5) / n
            F.box("Sash", (x, s * (W / 2 - 0.04), WIN1 - 0.32), ((x1 - x0) / n - 0.13, 0.04, 0.03), M["black"], bev=0)
            F.box("SashV", (x + 0.02, s * (W / 2 - 0.06), (WIN0 + WIN1 - 0.32) / 2), (0.025, 0.03, WIN1 - WIN0 - 0.34), M["chrome"], bev=0)
        for z in (WIN0 + 0.015, WIN1 - 0.015):
            F.box("Rubber", (-0.35, s * (W / 2 - 0.03), z), (L - 3.0, 0.07, 0.035), M["black"], bev=0)
        F.box("GlassCab", (FRONT - 0.95, s * (W / 2 - 0.05), (WIN0 + WIN1) / 2 - 0.08), (1.1, 0.015, WIN1 - WIN0 + 0.16), M["glass"], bev=0)
        F.box("Gutter", (0, s * (W / 2 + 0.01), WIN1 + 0.16), (L - 0.5, 0.04, 0.04), M["black"], bev=0)
    F.box("GlassRear", (REAR + 0.06, 0, 2.3), (0.015, W - 0.5, 0.85), M["glass"], bev=0)
    for hx in (-2.5, 1.5):
        F.box("RoofHatch", (hx, 0, H + 0.03), (0.85, 0.8, 0.07), M["cream"], bev=0.02)


def front(M):
    x = FRONT
    # windscreen: two panes in a black rubber surround, the destination board behind the glass at the top,
    # the Tamil route board in the lower corner
    for s in (1, -1):
        g = F.box("GlassFront", (x - 0.06, s * 0.6, 2.05), (0.015, 1.16, 1.44), M["glass"], bev=0)
        g.rotation_euler = (0, math.radians(-5), 0)
    F.box("Divider", (x - 0.04, 0, 2.05), (0.05, 0.06, 1.46), M["black"], bev=0)
    for s in (1, -1):
        F.box("Surround", (x - 0.05, s * (W / 2 - 0.1), 2.05), (0.07, 0.07, 1.48), M["black"], bev=0)
    for z in (1.32, 2.78):
        F.box("Surround", (x - 0.05, 0, z), (0.07, W - 0.2, 0.06), M["black"], bev=0)
    picture("BoardFront", (x + 0.05, 0, 2.93), W - 0.7, 0.24, M["board_f"], 1)
    F.box("BoardBack", (x + 0.0, 0, 2.93), (0.09, W - 0.6, 0.3), M["black"], bev=0.02)
    picture("RouteBoard", (x - 0.13, -0.55, 1.42), 1.0, 0.1, M["route"], 1)
    bf = None
    # bumper, lamps in black pods, grille, fogs, plate, wipers, rabbit-ear mirrors
    F.box("Bumper", (x + 0.04, 0, 0.5), (0.22, W + 0.02, 0.32), M["yellow"], bev=0.08)
    F.box("BumperLip", (x + 0.1, 0, 0.36), (0.12, W - 0.1, 0.06), M["black"], bev=0.02)
    F.box("Grille", (x + 0.01, 0, 1.0), (0.04, 0.85, 0.2), M["black"], bev=0.03)
    for k in range(5):
        F.box("Slat", (x + 0.035, 0, 0.92 + k * 0.04), (0.01, 0.8, 0.014), M["chrome"], bev=0)
    for s in (1, -1):
        F.box("Pod", (x + 0.01, s * 0.8, 1.0), (0.05, 0.66, 0.27), M["black"], bev=0.09)
        for k in (0, 1):
            yy = s * (0.64 + k * 0.32)
            F.cyl("Bezel", (x + 0.04, yy, 1.0), 0.115, 0.03, M["chrome"], rot=(0, math.pi / 2, 0), verts=28)
            F.cyl("Headlight", (x + 0.055, yy, 1.0), 0.097, 0.02, M["head"], rot=(0, math.pi / 2, 0), verts=28)
        F.cyl("Fog", (x + 0.16, s * 0.6, 0.5), 0.055, 0.03, M["head"], rot=(0, math.pi / 2, 0), verts=16)
        F.box("Indicator", (x + 0.15, s * 1.12, 0.52), (0.03, 0.15, 0.08), M["amber"], bev=0.01)
        F.box("Marker", (x - 0.15, s * (W / 2 - 0.1), H - 0.04), (0.08, 0.08, 0.05), M["amber"], bev=0.01)
        F.beam("MirrorArm", (x - 0.35, s * (W / 2 - 0.02), 2.78), (x + 0.12, s * (W / 2 + 0.3), 2.95), 0.04, 0.04, M["black"])
        F.beam("MirrorArm", (x + 0.12, s * (W / 2 + 0.3), 2.95), (x + 0.32, s * (W / 2 + 0.33), 2.5), 0.04, 0.04, M["black"])
        F.box("Mirror", (x + 0.33, s * (W / 2 + 0.33), 2.28), (0.07, 0.27, 0.44), M["black"], bev=0.03)
        F.box("MirrorGlass", (x + 0.29, s * (W / 2 + 0.33), 2.28), (0.01, 0.23, 0.4), M["chrome"], bev=0)
        F.box("Wiper", (x - 0.03, s * 0.58, 1.5), (0.02, 0.9, 0.025), M["black"], bev=0).rotation_euler = (s * 0.3, 0, 0)
    F.box("Plate", (x + 0.16, 0, 0.5), (0.01, 0.52, 0.13), M["plate"], bev=0)
    _ = bf


def rear(M):
    x = REAR
    F.box("RearGrille", (x - 0.02, 0, 0.82), (0.04, 1.3, 0.38), M["black"], bev=0.02)
    for k in range(6):
        F.box("RearSlat", (x - 0.045, 0, 0.67 + k * 0.06), (0.01, 1.25, 0.02), M["chrome"], bev=0)
    for s in (1, -1):
        F.box("TailBar", (x - 0.04, s * 1.0, 1.28), (0.05, 0.22, 0.34), M["tail"], bev=0.03)
        F.box("Indicator", (x - 0.04, s * 1.0, 1.02), (0.05, 0.2, 0.1), M["amber"], bev=0.01)
        F.box("Marker", (x + 0.15, s * (W / 2 - 0.1), H - 0.04), (0.08, 0.08, 0.05), M["tail"], bev=0.01)
    F.box("RearBumper", (x - 0.03, 0, 0.45), (0.16, W, 0.2), M["black"], bev=0.04)
    F.box("Plate", (x - 0.12, 0, 0.62), (0.01, 0.52, 0.13), M["plate"], bev=0)
    picture("BoardRear", (x - 0.012, 0, 2.95), 1.5, 0.3, M["board_r"], -1)
    F.cyl("Ladder", (x - 0.06, -0.9, 2.2), 0.02, 1.6, M["chrome"], verts=8)


DOORS = (FRONT - 3.0, -0.9)


def doors(M):
    """Folding glass doors in the doorways on the left (+Y), steps up to the floor."""
    for xc in DOORS:
        w = 0.95
        y = W / 2 - 0.06
        for sgn in (-1, 1):
            F.box("DoorLeaf", (xc + sgn * w / 4, y, (0.45 + WIN1) / 2), (w / 2 - 0.02, 0.04, WIN1 - 0.45), M["black"], bev=0.015)
            F.box("GlassDoor", (xc + sgn * w / 4, y + 0.025, 1.9), (w / 2 - 0.14, 0.01, 1.35), M["glass"], bev=0)
            F.box("GlassDoorLow", (xc + sgn * w / 4, y + 0.025, 0.85), (w / 2 - 0.14, 0.01, 0.55), M["glass"], bev=0)
        for k in range(3):
            F.box("Step", (xc, W / 2 - 0.3, 0.42 + k * 0.21), (w - 0.06, 0.42 - k * 0.1, 0.04), M["floor"], bev=0)


def interior(M):
    F.box("Floor", (0, 0, FLOOR), (L - 0.4, W - 0.25, 0.04), M["floor"], bev=0)
    F.box("Ceiling", (0, 0, H - 0.2), (L - 0.4, W - 0.25, 0.03), M["ceil"], bev=0)
    for s in (1, -1):
        F.box("TubeLight", (0, s * 0.45, H - 0.23), (L - 1.5, 0.08, 0.03), M["tube"], bev=0)
    # 2 + 3 seating rows, aisle on the left of centre
    for k in range(10):
        x = FRONT - 2.8 - k * 0.78
        for y, nseat in ((-0.6, 3), (0.72, 2)):
            for j in range(nseat):
                yy = y + (j - (nseat - 1) / 2) * 0.42
                F.box("Seat", (x, yy, FLOOR + 0.45), (0.45, 0.4, 0.1), M["seat_b"], bev=0.03)
                F.box("SeatBack", (x - 0.22, yy, FLOOR + 0.82), (0.08, 0.4, 0.62), M["seat_b"], bev=0.03)
        if k % 2 == 0:
            for y in (0.32, -0.12):
                F.cyl("Pole", (x + 0.3, y, FLOOR + 0.95), 0.02, 1.9, M["pole"], verts=8)
    for y in (0.32, -0.12):
        F.cyl("Rail", (0, y, H - 0.35), 0.018, L - 2.0, M["pole"], rot=(0, math.pi / 2, 0), verts=8)
    # driver's seat and wheel (right-hand drive: -Y)
    F.box("DriverSeat", (FRONT - 1.2, -0.75, FLOOR + 0.55), (0.5, 0.5, 0.12), M["seat"], bev=0.03)
    F.box("Dash", (FRONT - 0.45, 0, FLOOR + 0.55), (0.4, W - 0.3, 0.5), M["black"], bev=0.05)
    F.cyl("SteeringWheel", (FRONT - 0.7, -0.75, FLOOR + 1.0), 0.25, 0.04, M["black"], rot=(0, math.radians(-55), 0), verts=24)
    F.box("Bulkhead", (FRONT - 1.75, 0.45, FLOOR + 0.6), (0.05, 1.2, 1.2), M["cream"], bev=0)


def sides(M):
    for s_ in (1, -1):
        F.box("SideMarker", (0.0, s_ * (W / 2 + 0.005), 0.42), (0.1, 0.01, 0.05), M["amber"], bev=0)


def wheels(M):
    R, WD = 0.52, 0.3
    xf, xr = FRONT - 1.75, REAR + 3.05
    F.wheel("Wheel_FL", (xf, W / 2 - 0.2, R), R, WD, M, True, hub_cap=True)
    F.wheel("Wheel_FR", (xf, -W / 2 + 0.2, R), R, WD, M, False, hub_cap=True)
    F.wheel("Wheel_RL", (xr, W / 2 - 0.22, R), R, WD * 1.9, M, True, hub_cap=True)
    F.wheel("Wheel_RR", (xr, -W / 2 + 0.22, R), R, WD * 1.9, M, False, hub_cap=True)
    for x in (xf, xr):                                                  # arches cut as black wells
        for s in (1, -1):
            arch = F.lathe("Arch", [(R + 0.1, s * (W / 2 - 0.02)), (R + 0.14, s * (W / 2 + 0.03)), (R + 0.2, s * (W / 2 + 0.03))],
                           M["black"], 32, arc=(-math.pi / 2, math.pi / 2))
            arch.location = (x, 0, R)
            F.box("Well", (x, s * (W / 2 - 0.62), R + 0.25), (2 * R + 0.2, 0.08, 2 * R - 0.2), M["under"], bev=0)
    F.box("Chassis", (0, 0, 0.5), (L - 1.0, W - 0.6, 0.25), M["under"], bev=0)


def build():
    M = mats()
    body(M)
    front(M)
    rear(M)
    doors(M)
    interior(M)
    sides(M)
    wheels(M)


def preview(out):
    F.reset()
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 64
    sc.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = 'GPU'
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.view_settings.view_transform = 'AgX'
    try:
        sc.view_settings.look = 'AgX - Punchy'
    except TypeError:
        pass
    sc.view_settings.exposure = -0.3
    sc.world = bpy.data.worlds.new("Sky")
    sc.world.use_nodes = True
    sky = sc.world.node_tree.nodes.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_elevation = math.radians(42)
    sky.sun_rotation = math.radians(-35)
    sc.world.node_tree.links.new(sky.outputs[0], sc.world.node_tree.nodes["Background"].inputs[0])
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.12
    F.box("Ground", (0, 0, -0.06), (300, 300, 0.1), F.make_mat("Dry Field", (0.42, 0.33, 0.2), rough=0.95), bev=0)
    F.box("Road", (0, 3.0, -0.01), (300, 9.0, 0.02), F.make_mat("Asphalt", (0.05, 0.05, 0.055), rough=0.85), bev=0)
    for k in range(-20, 20):
        F.box("Line", (k * 9.0, 3.0, 0.005), (4.5, 0.15, 0.01), F.make_mat("Paint", (0.85, 0.85, 0.8), rough=0.6), bev=0)
    F.box("Edge", (0, -1.3, 0.005), (300, 0.15, 0.01), F.make_mat("Paint", (0.85, 0.85, 0.8), rough=0.6), bev=0)
    build()
    cams = {"front": ((16, 4.0, 2.2), (0, 0.2, 1.7), 50), "side": ((-2, 14, 2.4), (-0.5, 0, 1.6), 35),
            "rear": ((-15, -5.5, 2.8), (0, 0, 1.6), 45)}
    for name, (loc, tgt, lens) in cams.items():
        cam = F.link(bpy.data.objects.new("Cam" + name, bpy.data.cameras.new("Cam" + name)))
        cam.location = loc
        cam.data.lens = lens
        cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        sc.camera = cam
        sc.render.filepath = out.replace(".png", "_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("SHOT", name, flush=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--preview" in args:
        preview(os.path.abspath(args[args.index("--preview") + 1]))
    if "--export" in args:
        F.reset()
        build()
        F.finish(os.path.abspath(args[args.index("--export") + 1]))
