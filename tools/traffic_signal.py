"""
A Coimbatore traffic signal — design reference in Blender (our own design), before it goes into the game.

  * galvanised octagonal pole on a concrete plinth, black-and-yellow striped base
  * cantilever mast arm over the carriageway with an overhead 3-aspect head
  * near-side head on the left kerb at eye height (India drives on the left)
  * heads: black housing, three 300 mm LED aspects (red, amber, green) under long hoods, a yellow backboard with a
    white retro-reflective border
  * a two-digit countdown timer beside the near-side head (red while red, green while green)
  * a blue FREE LEFT board with a white arrow, and a pedestrian signal (red standing / green walking figure)

    Blender -b --factory-startup --python tools/traffic_signal.py -- --out previews/signals [--state red|green|amber]
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
_M = {}
GAME = False        # building the game version: lit parts get plain named materials the game's shaders replace

# lamp colours (lit) — LED red, amber, green (a little blue in it, as Indian LED greens are)
LIT = {"red": (1.0, 0.07, 0.03), "amber": (1.0, 0.55, 0.02), "green": (0.1, 1.0, 0.55)}


def mat(name, col, rough=0.5, metal=0.0, emit=None, strength=0.0):
    key = (name, col, rough, metal, emit, strength)
    if key in _M:
        return _M[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*col, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit:
        p.inputs["Emission Color"].default_value = (*emit, 1)
        p.inputs["Emission Strength"].default_value = strength
    _M[key] = m
    return m


def lens_mat(colour, lit):
    """An LED aspect: a dark tinted lens when off; lit, a bright core with a glowing ring of LEDs."""
    if GAME:
        return mat("SigLens %s" % colour.capitalize(), LIT[colour], 0.1)
    key = ("lens", colour, lit)
    if key in _M:
        return _M[key]
    m = bpy.data.materials.new("Lens %s %s" % (colour, "on" if lit else "off"))
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    c = LIT[colour]
    p.inputs["Base Color"].default_value = (c[0] * 0.08, c[1] * 0.08, c[2] * 0.08, 1)
    p.inputs["Roughness"].default_value = 0.08
    p.inputs["Coat Weight"].default_value = 1.0
    if lit:
        # LED dots: a fine grid of bright points over a softer glow
        co = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (55.0, 55.0, 55.0)
        nt.links.new(co.outputs["Object"], mp.inputs["Vector"])
        vo = nt.nodes.new("ShaderNodeTexVoronoi")
        nt.links.new(mp.outputs[0], vo.inputs["Vector"])
        rmp = nt.nodes.new("ShaderNodeMapRange")
        nt.links.new(vo.outputs["Distance"], rmp.inputs["Value"])
        rmp.inputs["From Min"].default_value = 0.15
        rmp.inputs["From Max"].default_value = 0.45
        rmp.inputs["To Min"].default_value = 60.0
        rmp.inputs["To Max"].default_value = 22.0
        p.inputs["Emission Color"].default_value = (*c, 1)
        nt.links.new(rmp.outputs[0], p.inputs["Emission Strength"])
    _M[key] = m
    return m


def obj(bm, name, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for f in me.polygons:
        f.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        me.materials.append(m)
    return ob


def box(bm, c, s, m=0, rot=None):
    M = Matrix.Translation(c) @ (rot.to_4x4() if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*s, 1))
    r = bmesh.ops.create_cube(bm, size=1.0, matrix=M)
    for v in r["verts"]:
        for f in v.link_faces:
            f.material_index = m
            f.smooth = False


def cyl(bm, a, b, r1, r2=None, segs=16, m=0, cap=True):
    a, b = Vector(a), Vector(b)
    d = b - a
    rot = d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    M = Matrix.Translation((a + b) / 2) @ rot
    r = bmesh.ops.create_cone(bm, cap_ends=cap, segments=segs, radius1=r1, radius2=r2 if r2 is not None else r1,
                              depth=d.length, matrix=M)
    for v in r["verts"]:
        for f in v.link_faces:
            f.material_index = m


def hood(bm, centre, facing, r, depth, m):
    """A lamp hood: the upper part of a tube standing out from the lens (open below, so the light is seen from
    a car below and the sun is kept off)."""
    f = Vector(facing).normalized()
    up = Vector((0, 0, 1))
    side = f.cross(up).normalized()
    segs = 12
    ring0, ring1 = [], []
    for k in range(segs + 1):
        a = math.pi * 0.05 + math.pi * 0.9 * k / segs            # top half and a bit
        o = side * math.cos(a) * r + up * math.sin(a) * r
        ring0.append(bm.verts.new(centre + o))
        ring1.append(bm.verts.new(centre + o * 1.04 + f * depth))
    for k in range(segs):
        face = bm.faces.new((ring0[k], ring0[k + 1], ring1[k + 1], ring1[k]))
        face.material_index = m


def head(bm, base, facing, state, mats, board=True):
    """A 3-aspect signal head, its back at `base` (the middle of the housing), turned to face `facing`.
    mats: dict of material indices."""
    f = Vector(facing).normalized()
    yaw = math.atan2(f.y, f.x) - math.pi / 2
    R = Matrix.Rotation(yaw, 3, 'Z')
    P = lambda v: Vector(base) + R @ Vector(v)                   # noqa: E731  local: x across, y out, z up
    if board:
        box(bm, P((0, -0.02, 0)), (0.78, 0.03, 1.5), mats["border"], R)
        box(bm, P((0, -0.005, 0)), (0.7, 0.03, 1.42), mats["board"], R)
    box(bm, P((0, 0.15, 0)), (0.42, 0.3, 1.18), mats["housing"], R)
    for k, colour in enumerate(("red", "amber", "green")):
        z = 0.37 - k * 0.37
        lit = state == colour
        cyl(bm, P((0, 0.3, z)), P((0, 0.31, z)), 0.15, segs=24, m=mats["lens_%s_%s" % (colour, "on" if lit else "off")])
        cyl(bm, P((0, 0.299, z)), P((0, 0.302, z)), 0.172, segs=24, m=mats["housing"])     # bezel
        hood(bm, P((0, 0.31, z)), R @ Vector((0, 1, 0)), 0.17, 0.26, mats["housing"])


def seven_segment(bm, origin, right, up, digit, h, m_on, m_off):
    """One seven-segment digit (LED bars) on a plane: origin = bottom-left."""
    segs = {0: "abcdef", 1: "bc", 2: "abged", 3: "abgcd", 4: "fgbc", 5: "afgcd", 6: "afgedc", 7: "abc", 8: "abcdefg",
            9: "abcdfg"}[digit]
    w = h * 0.55
    t = h * 0.12
    pos = {"a": ((0.5, 1.0), True), "b": ((1.0, 0.75), False), "c": ((1.0, 0.25), False), "d": ((0.5, 0.0), True),
           "e": ((0.0, 0.25), False), "f": ((0.0, 0.75), False), "g": ((0.5, 0.5), True)}
    for s, ((u, v), horiz) in pos.items():
        c = Vector(origin) + right * (u * w) + up * (v * h)
        a = right * (w * 0.42) if horiz else up * (h * 0.21)
        b = up * (t * 0.5) if horiz else right * (t * 0.5)
        n = right.cross(up).normalized() * 0.004
        vs = [bm.verts.new(c - a - b + n), bm.verts.new(c + a - b + n), bm.verts.new(c + a + b + n), bm.verts.new(c - a + b + n)]
        face = bm.faces.new(vs)
        face.material_index = m_on if s in segs else m_off


def countdown(bm, base, facing, value, colour_idx, off_idx, case_idx):
    f = Vector(facing).normalized()
    yaw = math.atan2(f.y, f.x) - math.pi / 2
    R = Matrix.Rotation(yaw, 3, 'Z')
    box(bm, Vector(base), (0.62, 0.12, 0.46), case_idx, R)
    right = -(R @ Vector((1, 0, 0)))                            # the viewer's right, looking at the face
    up = Vector((0, 0, 1))
    front = Vector(base) + R @ Vector((0, 0.065, 0))
    if GAME:
        uv = bm.loops.layers.uv.verify()
        c0 = front - right * 0.27 - up * 0.19
        vs = [bm.verts.new(c0), bm.verts.new(c0 + right * 0.54), bm.verts.new(c0 + right * 0.54 + up * 0.38),
              bm.verts.new(c0 + up * 0.38)]
        face = bm.faces.new(vs)
        face.material_index = colour_idx
        for lp, t in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            lp[uv].uv = t
        return
    for i, dgt in enumerate((value // 10, value % 10)):
        seven_segment(bm, front + right * (-0.24 + i * 0.25) + up * (-0.15), right, up, dgt, 0.3, colour_idx, off_idx)


def text_obj(txt, loc, rot_z, size, m, extrude=0.004):
    bpy.ops.object.text_add(location=loc, rotation=(math.pi / 2, 0, rot_z))
    t = bpy.context.active_object
    t.data.body = txt
    t.data.size = size
    t.data.align_x = 'CENTER'
    t.data.align_y = 'CENTER'
    t.data.extrude = extrude
    for name in ("Arial Bold", "Helvetica"):
        p = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
        if os.path.exists(p):
            t.data.font = bpy.data.fonts.load(p, check_existing=True)
            break
    t.data.materials.append(m)
    return t


def signal(state="red", count=27, at=Vector((0, 0, 0)), facing=Vector((0, -1, 0)), arm=5.6, side_sign=-1):
    """The whole installation on the left kerb at `at`, the traffic coming towards `facing`'s opposite; the
    arm reaches over the road to the right of the pole (seen by the driver)."""
    mats_list = [mat("Galvanised", (0.42, 0.43, 0.44), 0.45, 0.8), mat("Stripe Black", (0.02, 0.02, 0.02), 0.6),
                 mat("Stripe Yellow", (0.85, 0.62, 0.02), 0.5), mat("Concrete", (0.45, 0.44, 0.41), 0.9),
                 mat("Housing", (0.015, 0.015, 0.016), 0.45), mat("Backboard", (0.85, 0.6, 0.02), 0.5),
                 mat("Board Border", (0.9, 0.9, 0.88), 0.35),
                 lens_mat("red", state == "red"), lens_mat("red", False), lens_mat("amber", state == "amber"),
                 lens_mat("amber", False), lens_mat("green", state == "green"), lens_mat("green", False),
                 mat("SigTimer" if GAME else "LED Red", (0.3, 0.02, 0.01), 0.3, 0, LIT["red"], 30.0),
                 mat("LED Green", (0.02, 0.3, 0.1), 0.3, 0, LIT["green"], 30.0),
                 mat("LED Off", (0.03, 0.02, 0.02), 0.3), mat("Sign Blue", (0.02, 0.12, 0.45), 0.4), mat("Sign White", (0.9, 0.9, 0.88), 0.4)]
    I = {"pole": 0, "black": 1, "yellow": 2, "concrete": 3, "housing": 4, "board": 5, "border": 6,
         "lens_red_on": 7, "lens_red_off": 8, "lens_amber_on": 9, "lens_amber_off": 10, "lens_green_on": 11,
         "lens_green_off": 12, "led_r": 13, "led_g": 14, "led_off": 15, "blue": 16, "white": 17}
    # the lens slots used by head(): pick lit/unlit per state
    for c in ("red", "amber", "green"):
        if state != c:
            I["lens_%s_on" % c] = I["lens_%s_off" % c]
    bm = bmesh.new()
    f = Vector(facing).normalized()
    side = Vector((-f.y, f.x, 0)) if side_sign < 0 else Vector((f.y, -f.x, 0))   # towards the road
    # plinth, striped base, pole
    box(bm, at + Vector((0, 0, 0.25)), (0.7, 0.7, 0.5), I["concrete"])
    for k in range(6):
        cyl(bm, at + Vector((0, 0, 0.5 + k * 0.25)), at + Vector((0, 0, 0.75 + k * 0.25)), 0.125, 0.124, 8,
            I["black"] if k % 2 == 0 else I["yellow"])
    cyl(bm, at + Vector((0, 0, 2.0)), at + Vector((0, 0, 6.4)), 0.12, 0.085, 8, I["pole"])
    # the mast arm over the road, rising a little, with a brace, and the overhead head at its end
    a0 = at + Vector((0, 0, 6.0))
    a1 = at + side * arm + Vector((0, 0, 6.25))
    cyl(bm, a0, a1, 0.075, 0.055, 8, I["pole"])
    cyl(bm, at + Vector((0, 0, 5.2)), at + side * (arm * 0.45) + Vector((0, 0, 6.08)), 0.035, None, 6, I["pole"])
    head(bm, a1 - Vector((0, 0, 0.95)) - side * 0.15, -f, state, I)
    head(bm, at + side * (arm * 0.55) + Vector((0, 0, 5.3)), -f, state, I)                     # second overhead
    # near-side head at eye height on a bracket, the countdown timer beside it
    nh = at + side * 0.35 + Vector((0, 0, 3.15))
    box(bm, at + side * 0.18 + Vector((0, 0, 3.15)), (0.36, 0.08, 0.08), I["pole"])
    head(bm, nh, -f, state, I)
    led = I["led_r"] if (state == "red" or GAME) else (I["led_g"] if state == "green" else I["led_off"])
    countdown(bm, at - side * 0.42 + Vector((0, 0, 3.3)) - f * 0.05, -f, count, led, I["led_off"], I["housing"])
    box(bm, at - side * 0.2 + Vector((0, 0, 3.3)), (0.3, 0.06, 0.06), I["pole"])
    # FREE LEFT board below the timer
    fl = at - side * 0.42 + Vector((0, 0, 2.45)) - f * 0.06
    yaw = math.atan2(-f.y, -f.x) - math.pi / 2
    R = Matrix.Rotation(yaw, 3, 'Z')
    box(bm, fl, (0.62, 0.03, 0.62), I["blue"], R)
    box(bm, at - side * 0.2 + Vector((0, 0, 2.45)), (0.3, 0.06, 0.06), I["pole"])
    ob = obj(bm, "Signal", mats_list)
    # the board's arrow and words (text objects, white)
    arr = text_obj("←", fl - f * 0.02 + Vector((0, 0, 0.1)), yaw + math.pi, 0.32, mats_list[I["white"]])
    words = text_obj("FREE LEFT", fl - f * 0.02 + Vector((0, 0, -0.17)), yaw + math.pi, 0.11, mats_list[I["white"]])
    return ob


def pedestrian_signal(at, facing, walking=False):
    """A short pole by the crossing with a two-aspect head: red standing figure, green walking figure."""
    bm = bmesh.new()
    mats = [mat("Galvanised", (0.42, 0.43, 0.44), 0.45, 0.8), mat("Housing", (0.015, 0.015, 0.016), 0.45),
            mat("Ped Red", (0.3, 0.02, 0.01), 0.3, 0, LIT["red"], 0.0 if walking else 35.0),
            mat("Ped Green", (0.02, 0.3, 0.1), 0.3, 0, LIT["green"], 35.0 if walking else 0.0)]
    cyl(bm, at, at + Vector((0, 0, 2.9)), 0.07, 0.06, 8, 0)
    f = Vector(facing).normalized()
    yaw = math.atan2(f.y, f.x) - math.pi / 2
    R = Matrix.Rotation(yaw, 3, 'Z')
    c = at + Vector((0, 0, 2.5)) + f * 0.12
    box(bm, c, (0.34, 0.2, 0.7), 1, R)
    right = -(R @ Vector((1, 0, 0)))                            # the viewer's right, looking at the face
    out = f * 0.105
    # the figures, as little bars of LEDs: standing (top) and walking (bottom)
    def fig(cz, m, walk):
        ctr = c + out + Vector((0, 0, cz))
        cyl(bm, ctr + Vector((0, 0, 0.1)), ctr + Vector((0, 0, 0.1)) + f * 0.004, 0.025, None, 10, m)
        legs = ((-0.03, -0.11), (0.03, -0.11)) if not walk else ((-0.06, -0.1), (0.05, -0.1))
        for lx, lz in legs:
            box(bm, ctr + right * (lx * 0.5) + Vector((0, 0, (lz + 0.0) / 2)), (0.018, 0.004, abs(lz)), m,
                R @ Matrix.Rotation((lx * 4 if walk else 0), 3, 'Y'))
        box(bm, ctr + Vector((0, 0, 0.02)), (0.04, 0.004, 0.11), m, R)
    fig(0.16, 2, False)
    fig(-0.16, 3, True)
    return obj(bm, "Pedestrian signal", mats)


# ----------------------------------------------------------------------------- a junction to stand it in
def junction():
    bm = bmesh.new()
    mats = [mat("Asphalt", (0.05, 0.05, 0.052), 0.85), mat("Paint White", (0.85, 0.85, 0.82), 0.6),
            mat("Kerb", (0.5, 0.49, 0.46), 0.8), mat("Footpath", (0.45, 0.4, 0.36), 0.85),
            mat("Kerb Black", (0.03, 0.03, 0.03), 0.7), mat("Kerb Yellow", (0.8, 0.62, 0.05), 0.6)]
    box(bm, Vector((0, 0, -0.05)), (16.0, 140.0, 0.1), 0)            # main road (y), 16 m
    box(bm, Vector((0, 22.0, -0.049)), (140.0, 12.0, 0.1), 0)        # cross road
    box(bm, Vector((4.0, -6.0, 0.002)), (8.0, 0.4, 0.004), 1)        # stop line (left half, our side)
    for k in range(9):                                                 # zebra
        box(bm, Vector((-7.0 + k * 1.75, -3.5, 0.002)), (0.9, 3.0, 0.004), 1)
    for k in range(-12, 0):                                            # centre dashes
        box(bm, Vector((0, k * 6.0 - 3.0, 0.002)), (0.15, 3.0, 0.004), 1)
    for sx in (-1, 1):
        for y0, y1 in ((-70, 15.5), (28.5, 70)):
            L = y1 - y0
            box(bm, Vector((sx * 8.15, (y0 + y1) / 2, 0.08)), (0.3, L, 0.2), 2)
            box(bm, Vector((sx * 10.3, (y0 + y1) / 2, 0.075)), (4.0, L, 0.15), 3)
            for k in range(int(L / 1.0)):                              # painted kerb near the junction
                if y1 > 0 and k > L - 25:
                    box(bm, Vector((sx * 8.15, y0 + k + 0.5, 0.185)), (0.31, 1.0, 0.012), 4 + (k % 2))
    obj(bm, "Junction", mats)


def setup(out_samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _M.clear()
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = out_samples
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
    sc.render.image_settings.file_format = 'JPEG'
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.exposure = -0.4
    sc.world = bpy.data.worlds.new("Sky")
    sc.world.use_nodes = True
    sky = sc.world.node_tree.nodes.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_elevation = math.radians(35)
    sky.sun_rotation = math.radians(-120)
    sc.world.node_tree.links.new(sky.outputs[0], sc.world.node_tree.nodes["Background"].inputs[0])
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.12
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(55), 0, math.radians(-150))
    sc.collection.objects.link(sun)
    return sc


def shoot(sc, path, loc, target, lens):
    cam = bpy.data.objects.get("Cam")
    if cam is None:
        cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
    cam.location = loc
    cam.data.lens = lens
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDER", path, flush=True)


def export_game():
    """The game version: one installation at the origin, heads facing Blender -Y (the game's +Z, towards the
    oncoming driver), the arm reaching along +X (the game's +X, over the road on the driver's right) —
    city_streamer.gd places it on the left kerb of each approach. Lenses (SigLens Red / Amber / Green) and the
    countdown face (SigTimer, a UV quad) are lit by the game's shaders."""
    global GAME
    GAME = True
    import export_life as EL
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _M.clear()
    signal("red", 0, Vector((0, 0, 0)), Vector((0, 1, 0)), side_sign=1)
    for t in [o for o in bpy.data.objects if o.type == 'FONT']:
        bpy.ops.object.select_all(action='DESELECT')
        t.select_set(True)
        bpy.context.view_layer.objects.active = t
        bpy.ops.object.convert(target='MESH')
    out = os.path.join(HERE, "..", "godot", "assets", "city_props", "traffic_signal.glb")
    EL.export_objects([o for o in bpy.data.objects if o.type == 'MESH'], out)
    print("EXPORT", out, flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--export" in args:
        sys.path.insert(0, HERE)
        export_game()
        return
    out = os.path.abspath(args[args.index("--out") + 1]) if "--out" in args else os.path.join(HERE, "..", "previews", "signals")
    os.makedirs(out, exist_ok=True)
    for state, count in (("red", 27), ("green", 14)):
        sc = setup(64)
        junction()
        # our approach: traffic drives north (+y) on the left half (x > 0); the pole on the left kerb at x = +8.5
        signal(state, count, Vector((8.6, -7.0, 0.15)), Vector((0, 1, 0)))
        pedestrian_signal(Vector((8.6, -2.6, 0.15)), Vector((-1, 0, 0)), walking=(state == "red"))
        # the far-side signal across the junction for the opposite flow
        signal(state, count, Vector((-8.6, 29.5, 0.15)), Vector((0, -1, 0)))
        shoot(sc, os.path.join(out, "signal_%s_driver.jpg" % state), (4.0, -30.0, 1.35), (5.0, 0.0, 3.5), 30)
        if state == "red":
            shoot(sc, os.path.join(out, "signal_close.jpg"), (5.4, -10.5, 2.6), (8.6, -7.0, 3.6), 32)


if __name__ == "__main__":
    main()
