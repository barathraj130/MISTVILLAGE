"""
Luxury SUV Generator for Blender (3.6 / 4.x)
---------------------------------------------
Run: Scripting tab -> New/Open this file -> Run Script (Alt+P) -> F12 to render.

Original boxy luxury SUV: lofted body, glass greenhouse, painted roof & pillars,
wheel arches, 4 multi-spoke wheels, slim LED lights, grille, cladding,
mirrors, light studio scene, camera.
"""

import bpy
import bmesh
import math
from mathutils import Vector

# =====================================================================
# PARAMETERS
# =====================================================================
PAINT_COLOR   = (0.20, 0.24, 0.28)   # satin blue-grey
ACCENT_COLOR  = (0.75, 0.55, 0.42)   # bronze trim
WHEEL_RADIUS  = 0.40
FRONT_AXLE_X  = 1.55
REAR_AXLE_X   = -1.45
TRACK_Y       = 0.86
SEGS          = 48
LOFT_STEPS    = 4
SUBSURF_LEVEL = 2

# (x, half width, bottom z, top z, dip)  front -> back
BODY_KEYS = [
    ( 2.50, 0.80, 0.40, 0.95, 0.00),
    ( 2.45, 0.95, 0.32, 1.05, 0.00),
    ( 2.30, 0.99, 0.30, 1.10, 0.02),
    ( 1.55, 1.00, 0.30, 1.15, 0.02),
    ( 0.00, 1.00, 0.30, 1.17, 0.00),
    (-1.45, 1.00, 0.30, 1.18, 0.00),
    (-2.30, 0.98, 0.32, 1.18, 0.00),
    (-2.48, 0.92, 0.38, 1.12, 0.00),
    (-2.52, 0.75, 0.45, 1.00, 0.00),
]

# Glass greenhouse
CABIN_KEYS = [
    ( 1.10, 0.86, 1.08, 1.16, 0.0),
    ( 0.80, 0.84, 1.08, 1.50, 0.0),
    ( 0.40, 0.83, 1.08, 1.80, 0.0),
    (-1.00, 0.83, 1.08, 1.84, 0.0),
    (-2.10, 0.82, 1.08, 1.83, 0.0),
    (-2.38, 0.80, 1.08, 1.72, 0.0),
    (-2.45, 0.75, 1.08, 1.40, 0.0),
]

# =====================================================================
# SCENE RESET
# =====================================================================
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()
for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras):
    for block in list(coll):
        if block.users == 0:
            coll.remove(block)

scene = bpy.context.scene


def link(obj):
    scene.collection.objects.link(obj)
    return obj


def smooth(obj):
    for p in obj.data.polygons:
        p.use_smooth = True


def bevel(obj, width=0.01, segs=3):
    b = obj.modifiers.new("Bevel", 'BEVEL')
    b.width = width
    b.segments = segs


# =====================================================================
# MATERIALS
# =====================================================================
def make_mat(name, color, metallic=0.0, rough=0.5, coat=0.0, emission=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")

    def s(names, val):
        for n in names:
            if n in b.inputs:
                b.inputs[n].default_value = val
                return

    s(["Base Color"], (*color, 1.0))
    s(["Metallic"], metallic)
    s(["Roughness"], rough)
    s(["Coat Weight", "Clearcoat"], coat)
    s(["Coat Roughness", "Clearcoat Roughness"], 0.05)
    if emission:
        s(["Emission Color", "Emission"], (*emission, 1.0))
        s(["Emission Strength"], strength)
    return m


MAT_PAINT  = make_mat("SatinPaint", PAINT_COLOR, metallic=0.6, rough=0.38, coat=0.4)
MAT_ACCENT = make_mat("BronzeTrim", ACCENT_COLOR, metallic=1.0, rough=0.25)
MAT_GLASS  = make_mat("Glass", (0.01, 0.012, 0.015), rough=0.03, coat=1.0)
MAT_TIRE   = make_mat("Rubber", (0.02, 0.02, 0.02), rough=0.7)
MAT_RIM    = make_mat("RimGunmetal", (0.18, 0.18, 0.19), metallic=1.0, rough=0.25)
MAT_BLACK  = make_mat("GlossBlack", (0.005, 0.005, 0.005), rough=0.15, coat=1.0)
MAT_CLAD   = make_mat("Cladding", (0.03, 0.03, 0.03), rough=0.6)
MAT_HEAD   = make_mat("LED", (0.9, 0.9, 0.95), emission=(0.9, 0.95, 1.0), strength=10.0)
MAT_TAIL   = make_mat("Tail", (0.4, 0.0, 0.0), emission=(1.0, 0.02, 0.01), strength=8.0)
MAT_FLOOR  = make_mat("Floor", (0.55, 0.56, 0.58), rough=0.6)


# =====================================================================
# LOFT HELPERS
# =====================================================================
def catmull_rom(keys, steps):
    out, n = [], len(keys)
    for i in range(n - 1):
        p0, p1 = keys[max(i - 1, 0)], keys[i]
        p2, p3 = keys[i + 1], keys[min(i + 2, n - 1)]
        for st in range(steps):
            t = st / steps
            out.append(tuple(
                0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t
                       + (-a + 3 * b - 3 * c + d) * t ** 3)
                for a, b, c, d in zip(p0, p1, p2, p3)))
    out.append(keys[-1])
    return out


def section(hw, zb, zt, dip, segs, n_top, n_bot):
    pts = []
    zc, hh = (zb + zt) / 2, (zt - zb) / 2
    for i in range(segs):
        a = 2 * math.pi * i / segs
        c, s = math.cos(a), math.sin(a)
        n = n_top if s > 0 else n_bot
        y = hw * math.copysign(abs(c) ** (2 / n), c)
        z = zc + hh * math.copysign(abs(s) ** (2 / n), s)
        if s > 0 and dip > 0:
            z -= dip * math.exp(-(y / (0.45 * hw)) ** 2) * s
        pts.append((y, z))
    return pts


def loft(name, keys, n_top, n_bot, segs=SEGS, steps=LOFT_STEPS):
    stations = catmull_rom(keys, steps)
    bm = bmesh.new()
    rings = [[bm.verts.new((x, y, z)) for y, z in section(hw, zb, zt, dip, segs, n_top, n_bot)]
             for x, hw, zb, zt, dip in stations]
    for r1, r2 in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((r1[i], r1[j], r2[j], r2[i]))
    for ring, push in ((rings[0], 0.02), (rings[-1], -0.02)):
        c = sum((v.co for v in ring), Vector()) / len(ring)
        c.x += push
        cv = bm.verts.new(c)
        for i in range(segs):
            bm.faces.new((ring[i], ring[(i + 1) % segs], cv))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = link(bpy.data.objects.new(name, me))
    smooth(obj)
    sub = obj.modifiers.new("Subsurf", 'SUBSURF')
    sub.levels = SUBSURF_LEVEL
    sub.render_levels = SUBSURF_LEVEL + 1
    return obj


def box(name, loc, dims, mat, bev=0.01, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = dims
    o.data.materials.append(mat)
    if bev:
        bevel(o, bev)
    return o


# =====================================================================
# BODY
# =====================================================================
body = loft("Body", BODY_KEYS, n_top=5.0, n_bot=8.0)
body.data.materials.append(MAT_PAINT)

for ax in (FRONT_AXLE_X, REAR_AXLE_X):
    for side in (1, -1):
        bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=WHEEL_RADIUS + 0.06, depth=0.6,
                                            location=(ax, side * (TRACK_Y + 0.12), WHEEL_RADIUS),
                                            rotation=(math.pi / 2, 0, 0))
        cutter = bpy.context.active_object
        cutter.name = "ArchCutter"
        cutter.data.materials.append(MAT_CLAD)
        cutter.display_type = 'WIRE'
        cutter.hide_render = True
        mod = body.modifiers.new("Arch", 'BOOLEAN')
        mod.operation = 'DIFFERENCE'
        mod.object = cutter
        mod.solver = 'EXACT'
        if hasattr(mod, "material_mode"):
            mod.material_mode = 'TRANSFER'

# Glass greenhouse
cabin = loft("Greenhouse", CABIN_KEYS, n_top=6.0, n_bot=8.0)
cabin.data.materials.append(MAT_GLASS)

# Painted roof panel
box("Roof", (-0.85, 0, 1.855), (2.95, 1.62, 0.05), MAT_PAINT, bev=0.025)

# Body-colour pillars (A is the windshield frame edge, B, C, D)
for side in (1, -1):
    for x, w in ((-0.15, 0.10), (-1.35, 0.10), (-2.30, 0.14)):
        box("Pillar", (x, side * 0.84, 1.47), (w, 0.03, 0.74), MAT_PAINT, bev=0.008)
    # A pillar: raked along the windscreen edge, not upright
    _a = math.atan2(1.80 - 1.13, 1.08 - 0.38)
    box("Pillar", ((1.08 + 0.38) / 2, side * 0.845, (1.13 + 1.80) / 2), (math.hypot(0.7, 0.67) + 0.04, 0.035, 0.09),
        MAT_PAINT, bev=0.008, rot=(0, _a, 0))
    # belt-line chrome strip
    box("BeltTrim", (-0.6, side * 0.92, 1.12), (3.4, 0.02, 0.015), MAT_ACCENT, bev=0.004)
    # side cladding between the wheels
    box("SideSkirt", (0.05, side * 0.97, 0.40), (2.0, 0.05, 0.12), MAT_CLAD, bev=0.02)
    # side mirror
    # (real proportions: wider than tall, on a short arm; the game puts a live mirror on its back)
    box("Mirror", (0.88, side * 1.1, 1.2), (0.12, 0.27, 0.17), MAT_BLACK, bev=0.03)
    box("MirrorArm", (0.9, side * 0.97, 1.16), (0.07, 0.07, 0.04), MAT_BLACK, bev=0.01)
    # door shut lines (thin dark strips)
    for x in (0.70, -0.30, -1.10):
        box("DoorGap", (x, side * 1.0, 0.75), (0.006, 0.015, 0.75), MAT_CLAD, bev=0)

# =====================================================================
# FRONT & REAR DETAILS
# =====================================================================
# Grille + slats
box("Grille", (2.47, 0, 0.84), (0.06, 0.80, 0.20), MAT_BLACK, bev=0.02)
for k in range(4):
    box("Slat", (2.505, 0, 0.77 + k * 0.045), (0.01, 0.76, 0.008), MAT_ACCENT, bev=0)
# Slim LED headlights
for side in (1, -1):
    box("Headlight", (2.46, side * 0.70, 0.99), (0.05, 0.36, 0.05), MAT_HEAD, bev=0.01)
    box("FogDRL", (2.44, side * 0.82, 0.55), (0.04, 0.14, 0.02), MAT_HEAD, bev=0.005)
# Lower skid plate
box("SkidFront", (2.44, 0, 0.42), (0.08, 0.90, 0.05), MAT_ACCENT, bev=0.01)
box("SkidRear", (-2.47, 0, 0.47), (0.08, 0.90, 0.05), MAT_ACCENT, bev=0.01)
# Tail lights: vertical corner bars + full-width strip
for side in (1, -1):
    box("TailCorner", (-2.48, side * 0.80, 0.98), (0.04, 0.14, 0.26), MAT_TAIL, bev=0.01)
box("TailStrip", (-2.51, 0, 1.05), (0.03, 1.40, 0.02), MAT_TAIL, bev=0.005)


# =====================================================================
# WHEELS (22-inch-style multi-spoke)
# =====================================================================
def add_child(obj, parent, mat):
    obj.parent = parent
    obj.data.materials.append(mat)
    smooth(obj)
    return obj


def make_wheel(name, loc, outward_positive_y):
    R = WHEEL_RADIUS
    root = link(bpy.data.objects.new(name, None))
    root.location = loc
    if not outward_positive_y:
        root.rotation_euler = (0, 0, math.pi)

    bpy.ops.mesh.primitive_torus_add(major_radius=R - 0.10, minor_radius=0.10,
                                     major_segments=72, minor_segments=24,
                                     rotation=(math.pi / 2, 0, 0))
    tire = bpy.context.active_object
    tire.scale = (1, 1, 1.35)
    add_child(tire, root, MAT_TIRE)

    rim_r = R - 0.115
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=rim_r, depth=0.24,
                                        rotation=(math.pi / 2, 0, 0))
    add_child(bpy.context.active_object, root, MAT_CLAD)

    spoke_len = rim_r - 0.04
    for k in range(10):
        th = 2 * math.pi * k / 10
        bpy.ops.mesh.primitive_cube_add(size=1,
            location=(spoke_len / 2 * math.sin(th), 0.12, spoke_len / 2 * math.cos(th)),
            rotation=(0, th + math.radians(6), 0))
        sp = bpy.context.active_object
        sp.scale = (0.022, 0.025, spoke_len)
        bevel(sp, 0.005)
        add_child(sp, root, MAT_RIM)

    bpy.ops.mesh.primitive_torus_add(major_radius=rim_r, minor_radius=0.012,
                                     major_segments=72, minor_segments=12,
                                     location=(0, 0.12, 0), rotation=(math.pi / 2, 0, 0))
    add_child(bpy.context.active_object, root, MAT_RIM)

    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.07, depth=0.05,
                                        location=(0, 0.13, 0), rotation=(math.pi / 2, 0, 0))
    add_child(bpy.context.active_object, root, MAT_RIM)

    # brake disc behind spokes
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=rim_r - 0.04, depth=0.02,
                                        location=(0, 0.02, 0), rotation=(math.pi / 2, 0, 0))
    add_child(bpy.context.active_object, root, MAT_RIM)
    return root


make_wheel("Wheel_FL", (FRONT_AXLE_X,  TRACK_Y, WHEEL_RADIUS), True)
make_wheel("Wheel_FR", (FRONT_AXLE_X, -TRACK_Y, WHEEL_RADIUS), False)
make_wheel("Wheel_RL", (REAR_AXLE_X,   TRACK_Y, WHEEL_RADIUS), True)
make_wheel("Wheel_RR", (REAR_AXLE_X,  -TRACK_Y, WHEEL_RADIUS), False)


# =====================================================================
# STUDIO
# =====================================================================
bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
bpy.context.active_object.data.materials.append(MAT_FLOOR)

target = link(bpy.data.objects.new("Target", None))
target.location = (0, 0, 0.9)


def area_light(name, loc, energy, size, size_y=None):
    ld = bpy.data.lights.new(name, 'AREA')
    ld.energy = energy
    if size_y:
        ld.shape = 'RECTANGLE'
        ld.size, ld.size_y = size, size_y
    else:
        ld.size = size
    lo = link(bpy.data.objects.new(name, ld))
    lo.location = loc
    c = lo.constraints.new('TRACK_TO')
    c.target = target
    c.track_axis = 'TRACK_NEGATIVE_Z'
    c.up_axis = 'UP_Y'


area_light("KeyTop",  (0, 0, 7),     2000, 7, 3)
area_light("Side",    (2, -6, 3),     800, 7, 0.6)
area_light("Sun",     (-6, -3, 6),   1500, 4)
area_light("Fill",    (8, 2, 2),      400, 3)

cam_data = bpy.data.cameras.new("Camera")
cam_data.lens = 45
cam = link(bpy.data.objects.new("Camera", cam_data))
cam.location = (7.8, -6.4, 1.9)
tc = cam.constraints.new('TRACK_TO')
tc.target = target
tc.track_axis = 'TRACK_NEGATIVE_Z'
tc.up_axis = 'UP_Y'
scene.camera = cam

if scene.world is None:
    scene.world = bpy.data.worlds.new("World")
scene.world.use_nodes = True
bg = scene.world.node_tree.nodes.get("Background")
if bg:
    bg.inputs[0].default_value = (0.55, 0.57, 0.6, 1)
    bg.inputs[1].default_value = 0.8

scene.render.engine = 'CYCLES'
scene.cycles.samples = 128
scene.cycles.use_denoising = True
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
for vt in ("AgX", "Filmic"):
    try:
        scene.view_settings.view_transform = vt
        break
    except TypeError:
        continue

bpy.ops.object.select_all(action='DESELECT')
print("Luxury SUV built. Press F12 to render.")
