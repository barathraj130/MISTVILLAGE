"""
Sports Coupe Generator for Blender (3.6 / 4.x)
------------------------------------------------
How to run:
  1. Open Blender -> "Scripting" workspace
  2. Click "New", paste this file (or Open it), press "Run Script" (Alt+P)
  3. Press F12 to render (Cycles)

Builds: lofted smooth body, glass canopy, wheel arches, 4 five-spoke wheels,
headlights, tail-light bar, car-paint/glass/rubber/metal materials,
ground, studio lights and camera.

Tweak the PARAMETERS section to change colour, size and look.
"""

import bpy
import bmesh
import math
from mathutils import Vector

# =====================================================================
# PARAMETERS
# =====================================================================
PAINT_COLOR   = (0.45, 0.04, 0.02)   # deep red. Try (0.25,0.38,0.28) for sage green
WHEEL_RADIUS  = 0.34
FRONT_AXLE_X  = 1.30
REAR_AXLE_X   = -1.30
FRONT_TRACK_Y = 0.80
REAR_TRACK_Y  = 0.82
SECTION_SEGS  = 40                    # cross-section resolution
LOFT_STEPS    = 4                     # extra loops between key stations
SUBSURF_LEVEL = 2

# Body key stations, front -> back:
# (x position, half width, bottom z, top z, hood dip between fenders)
BODY_KEYS = [
    ( 2.28, 0.50, 0.26, 0.40, 0.00),
    ( 2.20, 0.78, 0.20, 0.52, 0.02),
    ( 2.00, 0.90, 0.17, 0.64, 0.06),
    ( 1.65, 0.95, 0.16, 0.78, 0.09),
    ( 1.30, 0.96, 0.16, 0.82, 0.09),
    ( 0.95, 0.93, 0.16, 0.82, 0.07),
    ( 0.60, 0.90, 0.16, 0.86, 0.02),
    ( 0.00, 0.90, 0.16, 0.90, 0.00),
    (-0.60, 0.93, 0.16, 0.92, 0.00),
    (-1.00, 0.99, 0.16, 0.95, 0.03),
    (-1.30, 1.00, 0.16, 0.95, 0.03),
    (-1.70, 0.97, 0.18, 0.90, 0.01),
    (-2.05, 0.90, 0.22, 0.82, 0.00),
    (-2.22, 0.78, 0.30, 0.76, 0.00),
    (-2.30, 0.50, 0.42, 0.68, 0.00),
]

# Glass canopy (greenhouse) stations
CABIN_KEYS = [
    ( 0.80, 0.70, 0.78, 0.85, 0.0),
    ( 0.50, 0.68, 0.78, 1.05, 0.0),
    ( 0.15, 0.64, 0.78, 1.22, 0.0),
    (-0.30, 0.62, 0.78, 1.27, 0.0),
    (-0.75, 0.60, 0.78, 1.20, 0.0),
    (-1.20, 0.55, 0.78, 1.04, 0.0),
    (-1.60, 0.45, 0.78, 0.93, 0.0),
]

# =====================================================================
# SCENE RESET
# =====================================================================
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()
for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.lights,
             bpy.data.cameras, bpy.data.curves):
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


# =====================================================================
# MATERIALS (works with Blender 3.x and 4.x input names)
# =====================================================================
def make_mat(name, color, metallic=0.0, rough=0.5, coat=0.0,
             emission=None, strength=0.0):
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
    s(["Coat Roughness", "Clearcoat Roughness"], 0.03)
    if emission:
        s(["Emission Color", "Emission"], (*emission, 1.0))
        s(["Emission Strength"], strength)
    return m


MAT_PAINT  = make_mat("CarPaint", PAINT_COLOR, metallic=0.55, rough=0.28, coat=1.0)
MAT_GLASS  = make_mat("TintedGlass", (0.01, 0.012, 0.015), rough=0.04, coat=1.0)
MAT_TIRE   = make_mat("Rubber", (0.02, 0.02, 0.02), rough=0.65)
MAT_RIM    = make_mat("RimSilver", (0.80, 0.80, 0.82), metallic=1.0, rough=0.18)
MAT_BARREL = make_mat("RimBarrel", (0.15, 0.15, 0.16), metallic=1.0, rough=0.35)
MAT_BLACK  = make_mat("BlackPlastic", (0.01, 0.01, 0.01), rough=0.45)
MAT_HEAD   = make_mat("Headlight", (0.9, 0.9, 0.95), rough=0.05,
                      emission=(1.0, 0.97, 0.9), strength=6.0)
MAT_TAIL   = make_mat("Taillight", (0.5, 0.0, 0.0), rough=0.1,
                      emission=(1.0, 0.03, 0.01), strength=8.0)
MAT_FLOOR  = make_mat("Floor", (0.05, 0.05, 0.055), rough=0.35)


# =====================================================================
# LOFT HELPERS
# =====================================================================
def catmull_rom(keys, steps):
    """Smoothly interpolate station tuples so the body has flowing loops."""
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


def section(hw, zb, zt, dip, segs):
    """Superellipse cross-section: rounder on top, boxier underneath.
    'dip' lowers the centre of the top so the fenders stand proud."""
    pts = []
    zc, hh = (zb + zt) / 2, (zt - zb) / 2
    for i in range(segs):
        a = 2 * math.pi * i / segs
        c, s = math.cos(a), math.sin(a)
        n = 3.0 if s > 0 else 6.0
        y = hw * math.copysign(abs(c) ** (2 / n), c)
        z = zc + hh * math.copysign(abs(s) ** (2 / n), s)
        if s > 0 and dip > 0:
            z -= dip * math.exp(-(y / (0.45 * hw)) ** 2) * s
        pts.append((y, z))
    return pts


def loft(name, keys, segs=SECTION_SEGS, steps=LOFT_STEPS):
    stations = catmull_rom(keys, steps)
    bm = bmesh.new()
    rings = []
    for x, hw, zb, zt, dip in stations:
        rings.append([bm.verts.new((x, y, z))
                      for y, z in section(hw, zb, zt, dip, segs)])

    for r1, r2 in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((r1[i], r1[j], r2[j], r2[i]))

    # rounded end caps
    for ring, push in ((rings[0], 0.03), (rings[-1], -0.03)):
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
    return obj


# =====================================================================
# BODY + CANOPY
# =====================================================================
body = loft("Body", BODY_KEYS)
body.data.materials.append(MAT_PAINT)
sub = body.modifiers.new("Subsurf", 'SUBSURF')
sub.levels = SUBSURF_LEVEL
sub.render_levels = SUBSURF_LEVEL + 1

# Wheel-arch cutters (one per wheel so the hood isn't cut)
for ax, ty in ((FRONT_AXLE_X, FRONT_TRACK_Y), (REAR_AXLE_X, REAR_TRACK_Y)):
    for side in (1, -1):
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=64, radius=WHEEL_RADIUS + 0.045, depth=0.55,
            location=(ax, side * (ty + 0.08), WHEEL_RADIUS),
            rotation=(math.pi / 2, 0, 0))
        cutter = bpy.context.active_object
        cutter.name = "ArchCutter"
        cutter.data.materials.append(MAT_BLACK)
        cutter.display_type = 'WIRE'
        cutter.hide_render = True
        mod = body.modifiers.new("Arch", 'BOOLEAN')
        mod.operation = 'DIFFERENCE'
        mod.object = cutter
        mod.solver = 'EXACT'
        if hasattr(mod, "material_mode"):
            mod.material_mode = 'TRANSFER'

cabin = loft("Canopy", CABIN_KEYS)
cabin.data.materials.append(MAT_GLASS)
csub = cabin.modifiers.new("Subsurf", 'SUBSURF')
csub.levels = SUBSURF_LEVEL
csub.render_levels = SUBSURF_LEVEL + 1


# =====================================================================
# WHEELS
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

    # tyre
    bpy.ops.mesh.primitive_torus_add(major_radius=R - 0.09, minor_radius=0.09,
                                     major_segments=64, minor_segments=24,
                                     rotation=(math.pi / 2, 0, 0))
    tire = bpy.context.active_object
    tire.scale = (1, 1, 1.4)
    add_child(tire, root, MAT_TIRE)

    # rim barrel
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=R - 0.1, depth=0.22,
                                        rotation=(math.pi / 2, 0, 0))
    add_child(bpy.context.active_object, root, MAT_BARREL)

    # 5 spokes on the outer face
    spoke_len = R - 0.13
    for k in range(5):
        th = 2 * math.pi * k / 5
        bpy.ops.mesh.primitive_cube_add(
            size=1,
            location=(spoke_len / 2 * math.sin(th), 0.115, spoke_len / 2 * math.cos(th)),
            rotation=(0, th, 0))
        sp = bpy.context.active_object
        sp.scale = (0.055, 0.03, spoke_len)
        bev = sp.modifiers.new("Bevel", 'BEVEL')
        bev.width = 0.008
        bev.segments = 3
        add_child(sp, root, MAT_RIM)

    # outer rim lip
    bpy.ops.mesh.primitive_torus_add(major_radius=R - 0.1, minor_radius=0.012,
                                     major_segments=64, minor_segments=12,
                                     location=(0, 0.115, 0),
                                     rotation=(math.pi / 2, 0, 0))
    add_child(bpy.context.active_object, root, MAT_RIM)

    # hub
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.06, depth=0.05,
                                        location=(0, 0.125, 0),
                                        rotation=(math.pi / 2, 0, 0))
    add_child(bpy.context.active_object, root, MAT_RIM)
    return root


make_wheel("Wheel_FR", (FRONT_AXLE_X, -FRONT_TRACK_Y, WHEEL_RADIUS), False)
make_wheel("Wheel_FL", (FRONT_AXLE_X,  FRONT_TRACK_Y, WHEEL_RADIUS), True)
make_wheel("Wheel_RR", (REAR_AXLE_X,  -REAR_TRACK_Y,  WHEEL_RADIUS), False)
make_wheel("Wheel_RL", (REAR_AXLE_X,   REAR_TRACK_Y,  WHEEL_RADIUS), True)


# =====================================================================
# LIGHTS ON THE CAR
# =====================================================================
for side in (1, -1):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24,
                                         location=(1.97, side * 0.60, 0.60),
                                         rotation=(0, math.radians(-15), side * math.radians(12)))
    hl = bpy.context.active_object
    hl.name = "Headlight"
    hl.scale = (0.09, 0.15, 0.065)
    hl.data.materials.append(MAT_HEAD)
    smooth(hl)

bpy.ops.mesh.primitive_cube_add(size=1, location=(-2.24, 0, 0.68))
tail = bpy.context.active_object
tail.name = "TailBar"
tail.scale = (0.06, 1.20, 0.025)
tail.data.materials.append(MAT_TAIL)
tb = tail.modifiers.new("Bevel", 'BEVEL')
tb.width = 0.01
tb.segments = 3


# =====================================================================
# STUDIO: FLOOR, LIGHTS, CAMERA, WORLD
# =====================================================================
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
bpy.context.active_object.data.materials.append(MAT_FLOOR)

target = link(bpy.data.objects.new("Target", None))
target.location = (0, 0, 0.55)


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
    return lo


area_light("KeyTop",    (0, 0, 6),      1500, 6, 2.5)   # long softbox overhead
area_light("StripLeft", (1.5, -5, 2.5),  500, 6, 0.4)   # reflection streak on side
area_light("Rim",       (-5, 4, 3),      700, 3)
area_light("FrontFill", (6, 1, 1.5),     250, 2)

cam_data = bpy.data.cameras.new("Camera")
cam_data.lens = 50
cam = link(bpy.data.objects.new("Camera", cam_data))
cam.location = (6.4, -5.2, 1.7)
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
    bg.inputs[0].default_value = (0.02, 0.022, 0.026, 1)
    bg.inputs[1].default_value = 1.0

# =====================================================================
# RENDER SETTINGS
# =====================================================================
scene.render.engine = 'CYCLES'
scene.cycles.samples = 128
scene.cycles.use_denoising = True
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
for vt in ("AgX", "Filmic"):
    try:
        scene.view_settings.view_transform = vt
        scene.view_settings.look = 'AgX - Punchy' if vt == "AgX" else 'High Contrast'
        break
    except TypeError:
        continue

bpy.ops.object.select_all(action='DESELECT')
print("Sports coupe built. Press F12 to render.")
