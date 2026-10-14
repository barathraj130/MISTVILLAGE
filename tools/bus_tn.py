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
        "yellow": F.make_mat("Bus Yellow", (0.93, 0.36, 0.02), rough=0.35, coat=0.6),
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
    g = bpy.data.materials.new("Glass")
    g.use_nodes = True
    b = g.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.7, 0.8, 0.78, 1)
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


def body(M):
    # the shell: rounded box in bands (skirt, stripe, cream), with the window band glazed separately
    def band(z0, z1, mat, inset=0.0, x0=REAR, x1=FRONT):
        return F.box("Shell", ((x0 + x1) / 2, 0, (z0 + z1) / 2), (x1 - x0 - inset, W - inset, z1 - z0), mat, bev=0.06)
    band(0.45, 1.2, M["yellow"])
    band(1.2, 1.32, M["red"], -0.01)
    band(1.32, 1.6, M["blue"], -0.012)
    band(1.6, WIN0, M["cream"])
    band(WIN1, H - 0.12, M["cream"])
    F.box("Roof", (0, 0, H - 0.06), (L - 0.12, W - 0.12, 0.14), M["cream"], bev=0.07)
    F.box("RoofHatch", (-1.0, 0, H + 0.04), (0.9, 0.8, 0.08), M["cream"], bev=0.02)
    F.box("RoofHatch", (2.5, 0, H + 0.04), (0.9, 0.8, 0.08), M["cream"], bev=0.02)
    # window band: pillars between sliding windows on both sides, glass behind
    n = 10
    x0, x1 = REAR + 0.5, FRONT - 1.6
    for s in (1, -1):
        y = s * (W / 2)
        F.box("GlassSide", ((x0 + x1) / 2, y - s * 0.02, (WIN0 + WIN1) / 2), (x1 - x0, 0.02, WIN1 - WIN0), M["glass"], bev=0)
        for k in range(n + 1):
            x = x0 + (x1 - x0) * k / n
            F.box("Pillar", (x, y, (WIN0 + WIN1) / 2), (0.14, 0.05, WIN1 - WIN0), M["black"], bev=0.01)
        for k in range(n):                                          # sliding sash rails
            x = x0 + (x1 - x0) * (k + 0.5) / n
            F.box("Sash", (x, y + s * 0.01, WIN0 + 0.5), ((x1 - x0) / n - 0.16, 0.03, 0.04), M["black"], bev=0)
        F.box("Gutter", (0, y + s * 0.015, WIN1 + 0.05), (L - 0.4, 0.04, 0.05), M["black"], bev=0)
        F.box("SkirtLine", (0, y + s * 0.01, 0.5), (L - 0.3, 0.03, 0.05), M["black"], bev=0)
    # cab side windows (behind the windscreen) and the rear window
    for s in (1, -1):
        F.box("GlassCab", (FRONT - 0.85, s * (W / 2 - 0.02), (WIN0 + WIN1) / 2 - 0.1), (1.3, 0.02, WIN1 - WIN0 + 0.2), M["glass"], bev=0)
    F.box("GlassRear", (REAR + 0.02, 0, 2.2), (0.02, W - 0.4, 0.9), M["glass"], bev=0)


def front(M):
    x = FRONT
    # black frame round the windscreen (top band carries the board, posts at the corners, sill below)
    F.box("Mask", (x - 0.05, 0, 3.0), (0.1, W - 0.06, 0.35), M["black"], bev=0.04)
    for s2 in (1, -1):
        F.box("Mask", (x - 0.05, s2 * (W / 2 - 0.08), 2.05), (0.1, 0.16, 1.6), M["black"], bev=0.03)
    F.box("Mask", (x - 0.05, 0, 1.36), (0.1, W - 0.06, 0.08), M["black"], bev=0.02)
    # split windscreen with a centre divider, a little raked back
    for s in (1, -1):
        g = F.box("GlassFront", (x + 0.005, s * 0.6, 2.05), (0.02, 1.16, 1.35), M["glass"], bev=0)
        g.rotation_euler = (0, math.radians(-4), 0)
    F.box("Divider", (x + 0.02, 0, 2.05), (0.04, 0.08, 1.38), M["black"], bev=0)
    # destination board: black panel, EXP red, destination green, a little lip
    F.box("Board", (x + 0.03, 0, 2.95), (0.06, W - 0.2, 0.42), M["board"], bev=0.01)
    text("EXP", (x + 0.07, -0.78, 2.95), (math.pi / 2, 0, math.pi / 2), 0.25, M["led_r"], width=0.55)
    text(DEST, (x + 0.07, 0.25, 2.95), (math.pi / 2, 0, math.pi / 2), 0.32, M["led_g"], width=1.5)
    # cream upper face, blue swoosh, yellow-orange bumper face
    F.box("FaceCream", (x - 0.02, 0, 1.15), (0.1, W - 0.04, 0.5), M["cream"], bev=0.04)
    F.box("FaceBlue", (x + 0.02, 0, 0.88), (0.06, W - 0.1, 0.1), M["blue"], bev=0.02)
    F.box("Bumper", (x + 0.04, 0, 0.62), (0.18, W + 0.02, 0.42), M["yellow"], bev=0.06)
    F.box("Grille", (x + 0.07, 0, 1.0), (0.04, 1.1, 0.16), M["black"], bev=0.02)
    for k in range(4):
        F.box("Slat", (x + 0.09, 0, 0.94 + k * 0.04), (0.01, 1.05, 0.015), M["chrome"], bev=0)
    for s in (1, -1):
        # twin round headlamps in a black pod each side, fog lamp and indicator below
        F.box("Pod", (x + 0.06, s * 0.82, 0.98), (0.08, 0.62, 0.26), M["black"], bev=0.06)
        for k in (0, 1):
            F.cyl("Headlight", (x + 0.1, s * (0.66 + k * 0.3), 0.98), 0.1, 0.04, M["head"], rot=(0, math.pi / 2, 0), verts=24)
            F.cyl("Bezel", (x + 0.09, s * (0.66 + k * 0.3), 0.98), 0.115, 0.03, M["chrome"], rot=(0, math.pi / 2, 0), verts=24)
        F.cyl("Fog", (x + 0.14, s * 0.55, 0.62), 0.06, 0.04, M["head"], rot=(0, math.pi / 2, 0), verts=16)
        F.box("Indicator", (x + 0.13, s * 1.12, 0.66), (0.03, 0.14, 0.08), M["amber"], bev=0.01)
        # rabbit-ear mirror: a stalk curving out and forward, a tall mirror head
        F.beam("MirrorArm", (x - 0.3, s * (W / 2), 2.75), (x + 0.15, s * (W / 2 + 0.3), 2.9), 0.04, 0.04, M["black"])
        F.beam("MirrorArm", (x + 0.15, s * (W / 2 + 0.3), 2.9), (x + 0.35, s * (W / 2 + 0.32), 2.45), 0.04, 0.04, M["black"])
        F.box("Mirror", (x + 0.36, s * (W / 2 + 0.32), 2.25), (0.06, 0.26, 0.42), M["black"], bev=0.03)
        F.box("MirrorGlass", (x + 0.32, s * (W / 2 + 0.32), 2.25), (0.01, 0.22, 0.38), M["chrome"], bev=0)
    F.box("Plate", (x + 0.14, 0, 0.5), (0.01, 0.52, 0.13), M["plate"], bev=0)
    for s in (1, -1):
        F.box("Wiper", (x + 0.04, s * 0.6, 1.42), (0.02, 0.85, 0.03), M["black"], bev=0).rotation_euler = (s * 0.25, 0, 0)


def rear(M):
    x = REAR
    F.box("RearYellow", (x - 0.03, 0, 0.8), (0.08, W - 0.04, 0.72), M["yellow"], bev=0.05)
    F.box("RearGrille", (x - 0.06, 0, 0.85), (0.03, 1.4, 0.4), M["black"], bev=0.02)
    for s in (1, -1):
        F.box("TailBar", (x - 0.06, s * 1.0, 1.25), (0.04, 0.22, 0.32), M["tail"], bev=0.02)
        F.box("Indicator", (x - 0.06, s * 1.0, 1.0), (0.04, 0.2, 0.1), M["amber"], bev=0.01)
    F.box("Plate", (x - 0.06, 0, 0.55), (0.01, 0.52, 0.13), M["plate"], bev=0)
    F.box("RearBoard", (x - 0.04, 0, 2.95), (0.05, 1.6, 0.3), M["board"], bev=0.01)
    text(DEST, (x - 0.08, 0, 2.95), (math.pi / 2, 0, -math.pi / 2), 0.22, M["led_g"], width=1.4)


def doors(M):
    """Front door just behind the front wheel and a centre door, both on the left (+Y), folding glass doors."""
    for xc, w in ((FRONT - 3.0, 0.95), (-0.9, 0.95)):
        y = W / 2 + 0.005
        F.box("Door", (xc, y, (0.45 + WIN1) / 2), (w, 0.04, WIN1 - 0.45), M["black"], bev=0.02)
        for s in (-1, 1):
            F.box("GlassDoor", (xc + s * w / 4, y + 0.025, 1.85), (w / 2 - 0.12, 0.01, 1.4), M["glass"], bev=0)
        for k in range(3):
            F.box("Step", (xc, W / 2 - 0.25, 0.45 + k * 0.2), (w - 0.1, 0.4, 0.04), M["floor"], bev=0)


def interior(M):
    F.box("Floor", (0, 0, FLOOR), (L - 0.4, W - 0.25, 0.04), M["floor"], bev=0)
    F.box("Ceiling", (0, 0, H - 0.2), (L - 0.4, W - 0.25, 0.03), M["ceil"], bev=0)
    for s in (1, -1):
        F.box("TubeLight", (0, s * 0.45, H - 0.23), (L - 1.5, 0.08, 0.03), M["tube"], bev=0)
    # 2 + 3 seating rows, aisle on the left of centre
    for k in range(10):
        x = FRONT - 2.8 - k * 0.78
        for y, nseat in ((-0.72, 3), (0.78, 2)):
            for j in range(nseat):
                yy = y + (j - (nseat - 1) / 2) * 0.45
                F.box("Seat", (x, yy, FLOOR + 0.45), (0.45, 0.42, 0.1), M["seat_b"], bev=0.03)
                F.box("SeatBack", (x - 0.22, yy, FLOOR + 0.82), (0.08, 0.42, 0.62), M["seat_b"], bev=0.03)
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
    for s in (1, -1):
        y = s * (W / 2 + 0.012)
        rot = (math.pi / 2, 0, 0 if s < 0 else math.pi)
        text(OPERATOR, (-3.3, y, 1.46), rot, 0.17, M["white"], width=3.6)
        text("EXPRESS", (FRONT - 3.0, y, 2.95), rot, 0.18, M["red"], width=1.6)
        F.box("Reflector", (REAR + 0.6, y, 0.75), (0.12, 0.01, 0.06), M["amber"], bev=0)


def wheels(M):
    R, WD = 0.52, 0.3
    xf, xr = FRONT - 1.75, REAR + 3.05
    F.wheel("Wheel_FL", (xf, W / 2 - 0.2, R), R, WD, M, True, hub_cap=True)
    F.wheel("Wheel_FR", (xf, -W / 2 + 0.2, R), R, WD, M, False, hub_cap=True)
    F.wheel("Wheel_RL", (xr, W / 2 - 0.22, R), R, WD * 1.9, M, True, hub_cap=True)
    F.wheel("Wheel_RR", (xr, -W / 2 + 0.22, R), R, WD * 1.9, M, False, hub_cap=True)
    for x in (xf, xr):                                                  # arches cut as black wells
        for s in (1, -1):
            arch = F.lathe("Arch", [(R + 0.1, s * (W / 2 + 0.012)), (R + 0.2, s * (W / 2 + 0.012))], M["black"], 32,
                           arc=(-math.pi / 2, math.pi / 2))
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
    sc.cycles.samples = 128
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
