"""
SUV Interior Add-on for Blender (3.6 / 4.x)
--------------------------------------------
STEP 1: Run luxury_suv_blender.py first (builds the exterior).
STEP 2: Run this script (Scripting tab -> Run Script).
STEP 3: F12 = still from inside the cabin, Ctrl+F12 = 150-frame walkthrough.

To switch back to the outside view: select "Camera" in the Outliner,
then View -> Cameras -> Set Active Object as Camera (Ctrl+Numpad0).

Adds: opened cabin, clear glass, front seats + rear bench, dashboard with
floating screens, steering wheel (right-hand drive), centre console,
door trims, wood + bronze inlays, ambient LED strips, headliner, carpet,
interior fill light and an animated interior camera.
"""

import bpy
import math

scene = bpy.context.scene

body = bpy.data.objects.get("Body")
if body is None:
    raise RuntimeError("Run luxury_suv_blender.py first - no 'Body' object found.")

DRIVER_Y = -0.42          # right-hand drive (India). Use +0.42 for left-hand drive.
LEATHER_COLOR = (0.55, 0.55, 0.57)

# =====================================================================
# CLEAN PREVIOUS RUN + INTERIOR COLLECTION
# =====================================================================
old = bpy.data.collections.get("Interior")
if old:
    for o in list(old.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(old)
for name in ("CabinCut",):
    if name in body.modifiers:
        body.modifiers.remove(body.modifiers[name])

coll = bpy.data.collections.new("Interior")
scene.collection.children.link(coll)
bpy.context.view_layer.active_layer_collection = \
    bpy.context.view_layer.layer_collection.children["Interior"]


# =====================================================================
# MATERIALS
# =====================================================================
def get_or_make(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    return m


def set_in(bsdf, names, val):
    for n in names:
        if n in bsdf.inputs:
            bsdf.inputs[n].default_value = val
            return


def make_mat(name, color, metallic=0.0, rough=0.5, coat=0.0, emission=None, strength=0.0):
    m = get_or_make(name)
    b = m.node_tree.nodes.get("Principled BSDF")
    set_in(b, ["Base Color"], (*color, 1.0))
    set_in(b, ["Metallic"], metallic)
    set_in(b, ["Roughness"], rough)
    set_in(b, ["Coat Weight", "Clearcoat"], coat)
    if emission:
        set_in(b, ["Emission Color", "Emission"], (*emission, 1.0))
        set_in(b, ["Emission Strength"], strength)
    return m


MAT_LEATHER  = make_mat("INT_Leather", LEATHER_COLOR, rough=0.55)
MAT_DARK     = make_mat("INT_DarkLeather", (0.04, 0.04, 0.045), rough=0.5)
MAT_HEADLINE = make_mat("INT_Headliner", (0.62, 0.62, 0.63), rough=0.95)
MAT_CARPET   = make_mat("INT_Carpet", (0.05, 0.05, 0.055), rough=1.0)
MAT_METAL    = make_mat("INT_Bronze", (0.75, 0.55, 0.42), metallic=1.0, rough=0.25)
MAT_SCREEN   = make_mat("INT_Screen", (0.01, 0.01, 0.02), rough=0.08, coat=1.0,
                        emission=(0.12, 0.30, 0.55), strength=2.0)
MAT_AMBIENT  = make_mat("INT_Ambient", (1, 0.6, 0.3), emission=(1.0, 0.55, 0.25), strength=12.0)

# Wood with procedural grain
MAT_WOOD = make_mat("INT_Wood", (0.2, 0.1, 0.04), rough=0.3, coat=0.7)
nt = MAT_WOOD.node_tree
bsdf = nt.nodes["Principled BSDF"]
if not any(n.type == 'TEX_WAVE' for n in nt.nodes):
    wave = nt.nodes.new('ShaderNodeTexWave')
    wave.inputs['Scale'].default_value = 2.5
    wave.inputs['Distortion'].default_value = 10.0
    wave.inputs['Detail'].default_value = 4.0
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (0.07, 0.03, 0.012, 1)
    ramp.color_ramp.elements[1].color = (0.30, 0.15, 0.06, 1)
    nt.links.new(wave.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])

# Make the exterior glass actually see-through so the cabin is lit and visible
glass = bpy.data.materials.get("Glass")
if glass:
    g = glass.node_tree.nodes.get("Principled BSDF")
    set_in(g, ["Base Color"], (0.80, 0.86, 0.88, 1.0))
    set_in(g, ["Roughness"], 0.0)
    set_in(g, ["Transmission Weight", "Transmission"], 1.0)
    set_in(g, ["IOR"], 1.5)
    set_in(g, ["Coat Weight", "Clearcoat"], 0.0)


# =====================================================================
# OPEN THE CABIN
# =====================================================================
# 1) carve the interior tub out of the body (cut faces become leather trim)
bpy.ops.mesh.primitive_cube_add(size=1, location=(-0.60, 0, 1.34))
cutter = bpy.context.active_object
cutter.name = "INT_CabinCutter"
cutter.scale = (3.30, 1.60, 1.72)
cutter.data.materials.append(MAT_LEATHER)
cutter.display_type = 'WIRE'
cutter.hide_render = True
mod = body.modifiers.new("CabinCut", 'BOOLEAN')
mod.operation = 'DIFFERENCE'
mod.object = cutter
mod.solver = 'EXACT'
if hasattr(mod, "material_mode"):
    mod.material_mode = 'TRANSFER'

# 2) remove the bottom of the glass shell so it doesn't slice through the cabin
import bmesh
gh = bpy.data.objects.get("Greenhouse")
if gh:
    bm = bmesh.new()
    bm.from_mesh(gh.data)
    bm.normal_update()
    bottom = [f for f in bm.faces
              if f.normal.z < -0.5 and f.calc_center_median().z < 1.25]
    bmesh.ops.delete(bm, geom=bottom, context='FACES')
    bm.to_mesh(gh.data)
    bm.free()


# =====================================================================
# HELPERS
# =====================================================================
def soft_box(name, loc, dims, mat, rot=(0, 0, 0), bev=0.02, sub=2):
    """Box with tight bevel + subdivision = padded, upholstered look."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = dims
    o.data.materials.append(mat)
    if bev:
        b = o.modifiers.new("Bevel", 'BEVEL')
        b.width = bev
        b.segments = 2
    if sub:
        s = o.modifiers.new("Subsurf", 'SUBSURF')
        s.levels = sub
        s.render_levels = sub
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def hard_box(name, loc, dims, mat, rot=(0, 0, 0)):
    return soft_box(name, loc, dims, mat, rot, bev=0.004, sub=0)


def cyl(name, loc, r, depth, mat, rot=(0, 0, 0), verts=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth,
                                        location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


# =====================================================================
# FLOOR, HEADLINER, WHEEL-HOUSE COVERS
# =====================================================================
hard_box("INT_Carpet", (-0.60, 0, 0.50), (3.30, 1.58, 0.03), MAT_CARPET)
hard_box("INT_Headliner", (-0.85, 0, 1.815), (2.90, 1.55, 0.02), MAT_HEADLINE)
for s in (1, -1):
    soft_box("INT_WheelHouse", (-1.45, s * 0.74, 0.62), (0.95, 0.14, 0.50), MAT_DARK, bev=0.03, sub=1)


# =====================================================================
# SEATS
# =====================================================================
def seat(prefix, x, y, width, headrests):
    soft_box(prefix + "_Base", (x, y, 0.60), (0.40, width * 0.8, 0.18), MAT_DARK, bev=0.02, sub=1)
    soft_box(prefix + "_Cushion", (x, y, 0.72), (0.52, width, 0.13), MAT_LEATHER, bev=0.03)
    lean = math.radians(-12)
    soft_box(prefix + "_Back", (x - 0.29, y, 1.08), (0.13, width, 0.62), MAT_LEATHER,
             rot=(0, lean, 0), bev=0.03)
    # side bolsters on the backrest
    for s in (1, -1):
        soft_box(prefix + "_Bolster", (x - 0.26, y + s * (width / 2 - 0.04), 1.02),
                 (0.16, 0.08, 0.50), MAT_LEATHER, rot=(0, lean, 0), bev=0.03)
    # bronze piping along the back
    hard_box(prefix + "_Piping", (x - 0.365, y, 1.08), (0.006, width * 0.9, 0.012), MAT_METAL,
             rot=(0, lean, 0))
    for hy in headrests:
        soft_box(prefix + "_Headrest", (x - 0.37, y + hy, 1.47), (0.09, 0.28, 0.17),
                 MAT_LEATHER, rot=(0, lean, 0), bev=0.03)


seat("INT_SeatDriver", -0.05, DRIVER_Y, 0.52, [0])
seat("INT_SeatPassenger", -0.05, -DRIVER_Y, 0.52, [0])
seat("INT_RearBench", -1.20, 0, 1.48, [-0.50, 0, 0.50])


# =====================================================================
# DASHBOARD
# =====================================================================
soft_box("INT_Dash", (0.86, 0, 0.88), (0.42, 1.60, 0.26), MAT_LEATHER, bev=0.04)
soft_box("INT_DashTop", (0.90, 0, 1.03), (0.36, 1.60, 0.06), MAT_DARK, bev=0.02)
soft_box("INT_ClusterHood", (0.78, DRIVER_Y, 1.13), (0.22, 0.46, 0.07), MAT_DARK, bev=0.02)
hard_box("INT_DashWood", (0.645, 0, 0.955), (0.015, 1.50, 0.035), MAT_WOOD)
hard_box("INT_DashAmbient", (0.640, 0, 0.985), (0.006, 1.50, 0.005), MAT_AMBIENT)
for s in (1, -1):
    hard_box("INT_Vent", (0.648, s * 0.58, 1.025), (0.01, 0.22, 0.028), MAT_DARK)
hard_box("INT_VentCenter", (0.648, 0, 1.025), (0.01, 0.30, 0.028), MAT_DARK)

# Driver display + floating centre touchscreen + lower climate screen
hard_box("INT_Cluster", (0.69, DRIVER_Y, 1.09), (0.012, 0.34, 0.11), MAT_SCREEN,
         rot=(0, math.radians(-10), 0))
hard_box("INT_CenterScreen", (0.64, 0, 1.13), (0.012, 0.42, 0.22), MAT_SCREEN,
         rot=(0, math.radians(-14), 0))
hard_box("INT_ScreenFrame", (0.646, 0, 1.13), (0.010, 0.44, 0.24), MAT_DARK,
         rot=(0, math.radians(-14), 0))
hard_box("INT_ClimateScreen", (0.66, 0, 0.84), (0.012, 0.26, 0.09), MAT_SCREEN,
         rot=(0, math.radians(-35), 0))


# =====================================================================
# STEERING WHEEL (tilted towards the driver)
# =====================================================================
tilt = math.radians(-65)
wc = (0.42, DRIVER_Y, 1.00)
bpy.ops.mesh.primitive_torus_add(major_radius=0.19, minor_radius=0.024,
                                 major_segments=64, minor_segments=16,
                                 location=wc, rotation=(0, tilt, 0))
rim = bpy.context.active_object
rim.name = "INT_SteeringRim"
rim.data.materials.append(MAT_DARK)
for p in rim.data.polygons:
    p.use_smooth = True
cyl("INT_SteeringHub", wc, 0.065, 0.05, MAT_DARK, rot=(0, tilt, 0))
hard_box("INT_SteeringSpoke", wc, (0.03, 0.34, 0.025), MAT_LEATHER, rot=(0, tilt, 0))
hard_box("INT_SteeringSpokeLow", (wc[0] + 0.05, wc[1], wc[2] - 0.08),
         (0.025, 0.04, 0.16), MAT_LEATHER, rot=(0, tilt, 0))
cyl("INT_SteeringBadge", (wc[0] - 0.012, wc[1], wc[2] + 0.005), 0.025, 0.01, MAT_METAL,
    rot=(0, tilt, 0))
cyl("INT_Column", (0.533, DRIVER_Y, 0.947), 0.04, 0.25, MAT_DARK, rot=(0, tilt, 0))


# =====================================================================
# CENTRE CONSOLE
# =====================================================================
soft_box("INT_Console", (0.20, 0, 0.72), (1.10, 0.27, 0.40), MAT_DARK, bev=0.02, sub=1)
hard_box("INT_ConsoleWood", (0.28, 0, 0.925), (0.85, 0.25, 0.015), MAT_WOOD)
for s in (1, -1):
    hard_box("INT_ConsoleTrim", (0.20, s * 0.138, 0.88), (1.05, 0.006, 0.012), MAT_METAL)
soft_box("INT_Armrest", (-0.17, 0, 0.97), (0.42, 0.27, 0.08), MAT_LEATHER, bev=0.03)
cyl("INT_DriveSelector", (0.42, 0, 0.955), 0.035, 0.05, MAT_METAL)
cyl("INT_RotaryKnob", (0.55, 0, 0.945), 0.028, 0.03, MAT_METAL)
cyl("INT_CupHolder", (0.20, 0, 0.93), 0.045, 0.012, MAT_DARK)


# =====================================================================
# DOOR TRIMS
# =====================================================================
for s in (1, -1):
    # A-pillar trim along each windscreen edge (raked, the width of a real pillar), headliner fabric
    ax0, az0, ax1, az1 = 1.08, 1.13, 0.38, 1.80
    th = math.atan2(az1 - az0, ax0 - ax1)
    hard_box("INT_APillar", ((ax0 + ax1) / 2, s * 0.79, (az0 + az1) / 2 - 0.01),
             (math.hypot(ax0 - ax1, az1 - az0) + 0.04, 0.12, 0.05), MAT_DARK, rot=(0, th, 0))
    # the door card itself: closes the cabin side from the floor up to the window line
    hard_box("INT_DoorCard", (-0.55, s * 0.875, 0.72), (2.62, 0.03, 0.66), MAT_DARK)
    hard_box("INT_DoorSill", (-0.55, s * 0.87, 1.065), (2.62, 0.07, 0.035), MAT_DARK)
    hard_box("INT_DoorPocket", (-0.55, s * 0.855, 0.5), (2.4, 0.05, 0.12), MAT_DARK)
    for x in (0.32, -0.78):
        hard_box("INT_DoorPull", (x, s * 0.84, 0.93), (0.16, 0.02, 0.03), MAT_METAL)
    soft_box("INT_DoorArmrest", (-0.55, s * 0.83, 0.86), (2.60, 0.07, 0.05), MAT_LEATHER, bev=0.02, sub=1)
    hard_box("INT_DoorWood", (-0.55, s * 0.845, 1.00), (2.60, 0.02, 0.03), MAT_WOOD)
    hard_box("INT_DoorAmbient", (-0.55, s * 0.838, 0.975), (2.60, 0.006, 0.005), MAT_AMBIENT)
    for x in (0.30, -0.80):
        cyl("INT_Speaker", (x, s * 0.85, 0.66), 0.07, 0.01, MAT_METAL,
            rot=(math.pi / 2, 0, 0))


# =====================================================================
# LIGHT + CAMERA
# =====================================================================
ld = bpy.data.lights.new("INT_CabinFill", 'AREA')
ld.shape = 'RECTANGLE'
ld.size, ld.size_y = 2.0, 1.2
ld.energy = 80
fill = bpy.data.objects.new("INT_CabinFill", ld)
coll.objects.link(fill)
fill.location = (-0.5, 0, 1.76)

target = bpy.data.objects.new("INT_CamTarget", None)
coll.objects.link(target)

cam_data = bpy.data.cameras.new("InteriorCam")
cam_data.lens = 18
cam = bpy.data.objects.new("InteriorCam", cam_data)
coll.objects.link(cam)
tc = cam.constraints.new('TRACK_TO')
tc.target = target
tc.track_axis = 'TRACK_NEGATIVE_Z'
tc.up_axis = 'UP_Y'

# Walkthrough: from the rear-left seat, gliding forward toward the driver's dash
side = -1 if DRIVER_Y < 0 else 1
keys = [
    (1,   (-1.15, -side * 0.55, 1.50), (0.75, side * 0.35, 1.00)),
    (90,  (-0.70, -side * 0.30, 1.45), (0.70, side * 0.10, 1.05)),
    (150, (-0.35, -side * 0.10, 1.40), (0.70, -side * 0.15, 1.05)),
]
for frame, cpos, tpos in keys:
    cam.location = cpos
    target.location = tpos
    cam.keyframe_insert("location", frame=frame)
    target.keyframe_insert("location", frame=frame)

scene.frame_start, scene.frame_end = 1, 150
scene.frame_set(1)
scene.camera = cam

bpy.ops.object.select_all(action='DESELECT')
print("Interior added. F12 for a still, Ctrl+F12 for the walkthrough.")
