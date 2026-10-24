"""
A person riding a motorcycle or a scooter (set VEHICLE below), self-contained (no add-ons, no project files): paste into Blender's Scripting tab and
press Run, or
    Blender --python tools/rider_scene.py
The rider's joints are solved to the bike (two-bone IK): hips on the seat, hands closed round the grips, feet on
the footpegs (on the scooter: sitting upright, feet flat on the floorboard), so changing the bike or the body sizes
keeps him riding it. +X is forward, Z up.
"""
import math

import bmesh
import bpy
from mathutils import Vector

# ---- settings: change and run again ----
VEHICLE = "scooter"                 # "motorcycle" or "scooter"
PAINT = (0.45, 0.04, 0.04)          # bike
SHIRT = (0.22, 0.38, 0.68)
PANTS = (0.18, 0.18, 0.2)
SKIN = (0.42, 0.26, 0.17)
HELMET = (0.75, 0.05, 0.05)        # helmet shell
STRIPE = (0.92, 0.92, 0.9)         # helmet centre stripe
GLOVES = (0.06, 0.06, 0.065)
LEAN = None                         # degrees the rider leans forward (None: the vehicle's own, below)
ANIMATE = True                      # ride past the camera, wheels turning
SPEED = 6.0                         # m/s when animated
# body sizes (metres)
TORSO, UPPER_ARM, FOREARM, THIGH, SHIN = 0.52, 0.30, 0.27, 0.44, 0.43
# points the rider is fitted to, per vehicle: pelvis centre on the seat, grip centres (x, z, ±y), where the left
# foot rests (footpeg / floorboard; the right is mirrored), wheel radius, wheels at ±axle, forward lean
FIT = {"motorcycle": dict(hip=(-0.15, 0.0, 0.97), grip=(0.42, 1.10, 0.36), foot=(0.02, 0.20, 0.38), r=0.31,
                          axle=0.68, lean=18.0),
       "scooter": dict(hip=(-0.2, 0.0, 0.93), grip=(0.32, 1.05, 0.34), foot=(0.14, 0.13, 0.33), r=0.23,
                       axle=0.62, lean=8.0)}[VEHICLE]
SEAT_HIP = Vector(FIT["hip"])
GRIP_X, GRIP_Z, GRIP_Y = FIT["grip"]
PEG = Vector(FIT["foot"])
R = FIT["r"]
AXLE_X = FIT["axle"]
if LEAN is None:
    LEAN = FIT["lean"]


def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for b in list(block):
            if b.users == 0:
                block.remove(b)


def mat(name, rgb, rough=0.5, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def finish(ob, m, parent, smooth=True):
    ob.data.materials.append(m)
    if smooth:
        for p in ob.data.polygons:
            p.use_smooth = True
    ob.parent = parent
    return ob


def limb(a, b, r1, r2, m, parent, verts=24):
    """A tapered tube from a to b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=d.length, location=(a + b) / 2)
    ob = bpy.context.object
    ob.rotation_euler = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
    return finish(ob, m, parent)


def ball(c, r, m, parent, scale=(1, 1, 1), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=r, location=c, rotation=rot)
    ob = bpy.context.object
    ob.scale = scale
    return finish(ob, m, parent)


def box(c, size, m, parent, bevel=0.02, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=c, rotation=rot)
    ob = bpy.context.object
    ob.scale = size
    if bevel:
        mod = ob.modifiers.new("Bevel", 'BEVEL')
        mod.width = bevel
        mod.segments = 3
        mod.affect = 'EDGES'
        bpy.ops.object.transform_apply(scale=True)
    return finish(ob, m, parent, smooth=False)


def ik(root, target, l1, l2, pole):
    """Two-bone IK: the middle joint for a limb from root towards target, bending towards pole."""
    root, target, pole = Vector(root), Vector(target), Vector(pole)
    d = target - root
    dist = min(d.length, l1 + l2 - 1e-3)
    n = d.normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    side = (pole - n * pole.dot(n)).normalized()
    return root + n * a + side * h, root + n * dist


def wheel(x, root, M):
    hub = bpy.data.objects.new("Wheel", None)
    bpy.context.collection.objects.link(hub)
    hub.location = (x, 0, R)
    hub.parent = root
    up = (math.pi / 2, 0, 0)                         # parts made at the origin, then hung on the hub
    bpy.ops.mesh.primitive_torus_add(major_radius=R - 0.05, minor_radius=0.055, major_segments=48,
                                     minor_segments=16, rotation=up)
    finish(bpy.context.object, M["tyre"], hub)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=R - 0.09, depth=0.03, rotation=up)
    finish(bpy.context.object, M["chrome"], hub)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.06, depth=0.12, rotation=up)
    finish(bpy.context.object, M["steel"], hub)
    for k in range(8):                               # spokes, so you can see it turning
        t = k * math.pi / 4
        limb((0, 0, 0), (math.cos(t) * (R - 0.1), 0, math.sin(t) * (R - 0.1)), 0.008, 0.008, M["steel"], hub, 8)
    return hub


def bike(root, M):
    return motorcycle(root, M) if VEHICLE == "motorcycle" else scooter(root, M)


def handlebar(root, M, mirror_h=0.2):
    """The bar across, the rubber grips at its ends and the mirrors."""
    limb((GRIP_X, GRIP_Y - 0.06, GRIP_Z), (GRIP_X, -(GRIP_Y - 0.06), GRIP_Z), 0.012, 0.012, M["chrome"], root)
    for s in (1, -1):
        limb((GRIP_X, s * (GRIP_Y - 0.06), GRIP_Z), (GRIP_X, s * (GRIP_Y + 0.06), GRIP_Z), 0.022, 0.022,
             M["tyre"], root)
        limb((GRIP_X, s * (GRIP_Y - 0.09), GRIP_Z), (GRIP_X - 0.04, s * (GRIP_Y - 0.04), GRIP_Z + mirror_h), 0.008,
             0.008, M["chrome"], root)
        ball((GRIP_X - 0.04, s * (GRIP_Y - 0.03), GRIP_Z + mirror_h + 0.02), 0.05, M["tyre"], root,
             scale=(0.4, 1.2, 0.8))


def scooter(root, M):
    """A step-through scooter: small wheels, the rounded rear body over the engine, a flat floorboard for the
    feet, the leg shield in front of the knees and the steering column up to the handlebar cowl."""
    rear = wheel(-AXLE_X, root, M)
    front = wheel(AXLE_X, root, M)
    box((0.12, 0, 0.29), (0.52, 0.34, 0.06), M["seat"], root, 0.02)                      # floorboard (mat top)
    box((0.12, 0, 0.24), (0.56, 0.36, 0.06), M["paint"], root, 0.025)
    ball((-0.43, 0, 0.56), 1.0, M["paint"], root, scale=(0.42, 0.21, 0.25))               # rear body
    box((-0.3, 0, 0.66), (0.5, 0.3, 0.2), M["paint"], root, 0.06)
    box((-0.3, 0, 0.82), (0.62, 0.28, 0.08), M["seat"], root, 0.035)
    box((-0.84, 0, 0.62), (0.04, 0.14, 0.05), M["tail"], root, 0.01)
    box((-0.86, 0, 0.48), (0.01, 0.18, 0.1), M["plate"], root, 0.0)
    box((0.43, 0, 0.62), (0.06, 0.42, 0.66), M["paint"], root, 0.03, rot=(0, math.radians(-14), 0))  # leg shield
    limb((0.56, 0, 0.42), (0.36, 0, 1.0), 0.045, 0.04, M["paint"], root)                 # steering column
    limb((0.52, 0.06, 0.5), (AXLE_X, 0.06, R), 0.03, 0.025, M["chrome"], root)           # single-sided fork
    ball((AXLE_X, 0, 2 * R + 0.02), 1.0, M["paint"], root, scale=(0.22, 0.075, 0.07))     # front mudguard
    ball((GRIP_X + 0.02, 0, GRIP_Z - 0.01), 1.0, M["paint"], root, scale=(0.13, 0.21, 0.07))  # handlebar cowl
    ball((GRIP_X + 0.13, 0, GRIP_Z - 0.01), 0.06, M["lamp"], root, scale=(0.3, 1.2, 0.9))  # headlamp
    handlebar(root, M, 0.24)
    box((-0.48, -0.09, 0.27), (0.42, 0.16, 0.18), M["engine"], root, 0.04)                # engine on the right
    limb((-0.42, -0.19, 0.3), (-0.86, -0.2, 0.38), 0.035, 0.045, M["chrome"], root)       # silencer
    return rear, front


def motorcycle(root, M):
    rear = wheel(-AXLE_X, root, M)
    front = wheel(AXLE_X, root, M)
    # frame, engine, tank, seat, tail
    limb((-0.45, 0, 0.62), (0.45, 0, 0.95), 0.03, 0.03, M["frame"], root)
    limb((0.45, 0, 0.95), (0.12, 0, 0.32), 0.03, 0.03, M["frame"], root)
    box((0.02, 0, 0.42), (0.36, 0.24, 0.3), M["engine"], root, 0.04)
    for k in range(5):                               # cooling fins
        box((0.2, 0, 0.32 + k * 0.05), (0.04, 0.26, 0.012), M["chrome"], root, 0)
    ball((0.22, 0, 0.9), 1.0, M["paint"], root, scale=(0.3, 0.17, 0.11), rot=(0, math.radians(-8), 0))
    box((-0.22, 0, 0.85), (0.58, 0.27, 0.07), M["seat"], root, 0.03)
    box((-0.47, 0, 0.72), (0.34, 0.2, 0.18), M["paint"], root, 0.05)
    box((-0.66, 0, 0.74), (0.04, 0.14, 0.05), M["tail"], root, 0.01)
    box((-0.7, 0, 0.6), (0.01, 0.18, 0.1), M["plate"], root, 0.0)
    # rear suspension and swingarm
    for s in (1, -1):
        limb((-0.05, s * 0.11, 0.42), (-AXLE_X, s * 0.11, R), 0.025, 0.02, M["frame"], root)
        limb((-0.56, s * 0.12, 0.36), (-0.45, s * 0.12, 0.76), 0.025, 0.025, M["chrome"], root)
    limb((0.0, -0.16, 0.28), (-0.78, -0.17, 0.42), 0.04, 0.05, M["chrome"], root)          # silencer
    # front: forks, handlebar, grips, headlamp, mirrors, mudguard
    for s in (1, -1):
        limb((0.47, s * 0.09, 1.0), (AXLE_X, s * 0.09, R), 0.025, 0.025, M["chrome"], root)
        limb((0.47, s * 0.09, 1.0), (GRIP_X + 0.03, s * 0.13, GRIP_Z - 0.01), 0.018, 0.018, M["chrome"], root)
        limb((0.02, s * 0.12, PEG.z), (0.02, s * 0.25, PEG.z), 0.015, 0.015, M["tyre"], root)  # footpeg
    handlebar(root, M)
    ball((0.6, 0, 0.97), 0.09, M["chrome"], root, scale=(0.7, 1, 1))
    ball((0.665, 0, 0.97), 0.075, M["lamp"], root, scale=(0.25, 1, 1))
    ball((AXLE_X, 0, 2 * R + 0.03), 1.0, M["paint"], root, scale=(0.3, 0.075, 0.07))      # front mudguard
    return rear, front


class Skel:
    """A stick figure (points with radii, joined by edges) that Blender's Skin modifier turns into one smooth,
    continuous body, so limbs flow into each other instead of being tubes and balls."""

    def __init__(self):
        self.v, self.r, self.e = [], [], []

    def add(self, p, r, after=None):
        self.v.append(Vector(p))
        self.r.append(r)
        i = len(self.v) - 1
        if after is not None:
            self.e.append((after, i))
        return i

    def chain(self, start, pts, radii):
        for p, r in zip(pts, radii):
            start = self.add(p, r, start)
        return start

    def build(self, name, m, parent, levels=2):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(p) for p in self.v], self.e, [])
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        sk = ob.modifiers.new("Skin", 'SKIN')
        sk.use_smooth_shade = True
        if len(me.skin_vertices) == 0:
            me.skin_vertices.new()
        for i, r in enumerate(self.r):
            d = me.skin_vertices[0].data[i]
            d.radius = r if isinstance(r, tuple) else (r, r)
            d.use_root = i == 0
        sub = ob.modifiers.new("Smooth", 'SUBSURF')
        sub.levels = sub.render_levels = levels
        me.materials.append(m)
        ob.parent = parent
        return ob


def lerp(a, b, t):
    return Vector(a).lerp(Vector(b), t)


def helmet(c, M, parent):
    """A full-face helmet: a shell longer at the back, open at the neck, with a face port above the chin bar,
    a black liner inside, a centre stripe and a top vent, and a curved tinted visor closing the port."""
    def shaped(r):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=32, radius=r)
        for v in bm.verts:
            v.co.x *= 1.08 if v.co.x > 0 else 1.16
            v.co.y *= 0.92
        return bm

    def port(p, grow=0.0):                                       # the face opening, in front, above the chin bar
        return p.x > 0.045 - grow and -0.065 - grow < p.z < 0.04 + grow and abs(p.y) < 0.1 + grow

    bm = shaped(0.15)
    kill = [f for f in bm.faces if port(f.calc_center_median())
            or f.calc_center_median().z < (-0.115 if f.calc_center_median().x > 0.06 else -0.09)]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    for f in bm.faces:
        p = f.calc_center_median()
        f.material_index = 1 if abs(p.y) < 0.022 and p.z > 0.0 else 0
    me = bpy.data.meshes.new("Helmet")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Helmet", me)
    bpy.context.collection.objects.link(ob)
    for m in (M["helmet"], M["stripe"], M["liner"], M["liner"]):
        me.materials.append(m)
    sol = ob.modifiers.new("Shell", 'SOLIDIFY')
    sol.thickness = 0.014
    sol.offset = -1.0
    sol.material_offset = 2                                      # the inside and the edges in the liner
    sol.material_offset_rim = 2
    sub = ob.modifiers.new("Smooth", 'SUBSURF')
    sub.levels = sub.render_levels = 2
    for p in me.polygons:
        p.use_smooth = True
    ob.location = c
    ob.parent = parent
    # visor: the same shape a little bigger, only where it covers the port
    bm = shaped(0.156)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not port(f.calc_center_median(), 0.012)], context='FACES')
    me = bpy.data.meshes.new("Visor")
    bm.to_mesh(me)
    bm.free()
    vis = bpy.data.objects.new("Visor", me)
    bpy.context.collection.objects.link(vis)
    me.materials.append(M["visor"])
    vis.modifiers.new("Thick", 'SOLIDIFY').thickness = 0.004
    sub = vis.modifiers.new("Smooth", 'SUBSURF')
    sub.levels = sub.render_levels = 2
    for p in me.polygons:
        p.use_smooth = True
    vis.location = c
    vis.parent = parent
    box(c + Vector((0.07, 0, 0.135)), (0.06, 0.05, 0.016), M["liner"], parent, 0.006,
        rot=(0, math.radians(18), 0))                                                        # top vent
    for s in (1, -1):                                                                        # visor pivots
        ball(c + Vector((0.04, s * 0.142, 0.01)), 0.02, M["liner"], parent, scale=(1, 0.35, 1))


def rider(root, M):
    lean = math.radians(LEAN)
    up = Vector((math.sin(lean), 0, math.cos(lean)))
    hip = SEAT_HIP
    top = hip + up * TORSO                                       # base of the neck
    joints = {}
    for s in (1, -1):
        sh = top + Vector((-0.01, s * 0.2, -0.06))
        grip = Vector((GRIP_X, s * GRIP_Y, GRIP_Z))
        elbow, wrist = ik(sh, grip - Vector((0.075, 0, -0.01)), UPPER_ARM, FOREARM, (-0.2, s * 1.0, -1.0))
        hj = hip + Vector((0.02, s * 0.095, -0.02))
        peg = Vector((PEG.x, s * PEG.y, PEG.z))
        knee, ankle = ik(hj, peg + Vector((-0.04, 0, 0.09)), THIGH, SHIN, (1.0, s * 0.25, 0.3))
        joints[s] = (sh, elbow, wrist, grip, hj, knee, ankle, peg)
        print("RIDER %s side %+d  wrist→grip %.3f m  ankle→peg %.3f m" % (VEHICLE, s, (wrist - grip).length,
                                                                         (ankle - peg).length))
    # trousers: waist, pelvis, the two legs down to the ankles (thigh, knee, calf shaped)
    t = Skel()
    w = t.add(hip + up * 0.14, 0.13)
    pelvis = t.add(hip, 0.14, w)
    for s in (1, -1):
        sh, elbow, wrist, grip, hj, knee, ankle, peg = joints[s]
        h = t.add(hj, 0.1, pelvis)
        t.chain(h, [lerp(hj, knee, 0.45), lerp(hj, knee, 0.85), knee, lerp(knee, ankle, 0.3), lerp(knee, ankle, 0.7),
                    ankle], [0.085, 0.063, 0.058, 0.057, 0.045, 0.043])
    t.build("Trousers", M["pants"], root)
    # shirt: tucked over the waist, belly, chest, shoulders and full sleeves to the wrists
    sh_ = Skel()
    w = sh_.add(hip + up * 0.1, 0.15)
    belly = sh_.add(hip + up * 0.24, 0.158, w)
    chest = sh_.add(hip + up * 0.37, 0.168, belly)
    upper = sh_.add(top - up * 0.07, 0.15, chest)
    sh_.add(top + up * 0.01, 0.07, upper)                        # collar
    sh_.build("Shirt", M["shirt"], root)
    for s in (1, -1):                                            # sleeves: their own pieces, starting inside the
        sh, elbow, wrist, grip, hj, knee, ankle, peg = joints[s]   # chest (one branchy mesh grows flaps)
        sl = Skel()
        a = sl.add(lerp(top - up * 0.08, sh, 0.35), 0.085)
        sl.chain(a, [sh, lerp(sh, elbow, 0.5), elbow, lerp(elbow, wrist, 0.5), wrist],
                 [0.07, 0.054, 0.045, 0.042, 0.037])
        sl.build("Sleeve", M["shirt"], root)
    # neck and head (the face is behind the visor)
    n = Skel()
    n0 = n.add(top - up * 0.02, 0.058)
    head = top + Vector((0.04, 0, 0.11))
    n.chain(n0, [head - Vector((0.01, 0, 0.07))], [0.054])
    n.build("Neck", M["skin"], root)
    ball(head, 0.1, M["skin"], root, scale=(1.05, 0.88, 1.15))
    helmet(head + Vector((-0.005, 0, 0.02)), M, root)
    # gloved hands closed round the grips, shoes on the pegs / floorboard
    for s in (1, -1):
        sh, elbow, wrist, grip, hj, knee, ankle, peg = joints[s]
        g = Skel()
        g0 = g.add(wrist - (grip - wrist).normalized() * 0.03, 0.038)
        g.chain(g0, [lerp(wrist, grip, 0.6) + Vector((0, 0, 0.022)), grip + Vector((0.005, 0, 0.028))],
                [0.034, 0.03])
        g.build("Glove", M["glove"], root)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.031, minor_radius=0.019, major_segments=32,
                                         minor_segments=12, location=grip, rotation=(math.pi / 2, 0, 0))
        fingers = bpy.context.object                                # the fingers wrapped round the grip
        fingers.scale = (1, 1, 2.2)
        finish(fingers, M["glove"], root)
        limb(grip + Vector((-0.02, -s * 0.04, 0.025)), grip + Vector((0.035, -s * 0.045, 0.01)), 0.014, 0.012,
             M["glove"], root)                                      # thumb over the top
        f = Skel()
        f0 = f.add(ankle, 0.045)
        f.chain(f0, [ankle + Vector((-0.035, 0, -0.06)), ankle + Vector((0.07, 0, -0.065)),
                     ankle + Vector((0.17, 0, -0.07))], [0.047, 0.046, 0.04])
        f.build("Shoe", M["shoe"], root)


def scene(root):
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    road = bpy.context.object
    road.data.materials.append(mat("Asphalt", (0.05, 0.05, 0.052), 0.85))
    for k in range(-5, 6):
        bpy.ops.mesh.primitive_plane_add(size=1, location=(k * 6.0, -1.6, 0.002))
        d = bpy.context.object
        d.scale = (1.5, 0.07, 1)
        d.data.materials.append(mat("Line", (0.85, 0.85, 0.8), 0.6))
    bpy.ops.object.light_add(type='SUN', rotation=(math.radians(50), 0, math.radians(-40)))
    bpy.context.object.data.energy = 4.0
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    bpy.context.collection.objects.link(cam)
    cam.location = (3.2, -5.5, 1.5)
    cam.data.lens = 45
    t = cam.constraints.new('TRACK_TO')
    aim = bpy.data.objects.new("CameraAim", None)               # the camera looks at the rider's middle
    bpy.context.collection.objects.link(aim)
    aim.parent = root
    aim.location = (0, 0, 0.9)
    t.target = aim
    t.track_axis = 'TRACK_NEGATIVE_Z'
    t.up_axis = 'UP_Y'
    bpy.context.scene.camera = cam
    w = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.68, 0.85, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.8


def animate(root, wheels):
    sc = bpy.context.scene
    fps = sc.render.fps
    sc.frame_start, sc.frame_end = 1, 4 * fps                       # four seconds past the camera
    bpy.context.preferences.edit.keyframe_new_interpolation_type = 'LINEAR'
    dist = SPEED * 4.0
    for f, x in ((1, -dist / 2), (sc.frame_end, dist / 2)):
        root.location.x = x
        root.keyframe_insert("location", index=0, frame=f)
        for w in wheels:
            w.rotation_euler.y = (x + dist / 2) / R                 # rolling: turned by distance / radius
            w.keyframe_insert("rotation_euler", index=1, frame=f)
    sc.frame_set(1)


def main():
    clear()
    M = {"paint": mat("Paint", PAINT, 0.25), "seat": mat("Seat", (0.08, 0.07, 0.065), 0.7),
         "frame": mat("Frame", (0.03, 0.03, 0.03), 0.4), "engine": mat("Engine", (0.35, 0.35, 0.37), 0.4, 0.8),
         "chrome": mat("Chrome", (0.8, 0.8, 0.82), 0.12, 1.0), "steel": mat("Steel", (0.5, 0.5, 0.52), 0.3, 1.0),
         "tyre": mat("Rubber", (0.02, 0.02, 0.02), 0.85), "tail": mat("Tail", (0.7, 0.02, 0.02), 0.3),
         "plate": mat("Plate", (0.9, 0.9, 0.88), 0.5), "lamp": mat("Lamp", (0.95, 0.95, 0.85), 0.05),
         "shirt": mat("Shirt", SHIRT, 0.8), "pants": mat("Pants", PANTS, 0.8), "skin": mat("Skin", SKIN, 0.55),
         "shoe": mat("Shoe", (0.05, 0.035, 0.025), 0.5), "helmet": mat("Helmet", HELMET, 0.15),
         "stripe": mat("Stripe", STRIPE, 0.15), "liner": mat("Liner", (0.02, 0.02, 0.022), 0.9),
         "visor": mat("Visor", (0.015, 0.015, 0.02), 0.02), "glove": mat("Gloves", GLOVES, 0.6)}
    for k in ("helmet", "stripe", "visor"):                 # glossy clear coat, like paint and polycarbonate
        b = M[k].node_tree.nodes["Principled BSDF"]
        for name in ("Coat Weight", "Clearcoat"):
            if name in b.inputs:
                b.inputs[name].default_value = 1.0
    b = M["skin"].node_tree.nodes["Principled BSDF"]
    for name in ("Subsurface Weight", "Subsurface"):
        if name in b.inputs:
            b.inputs[name].default_value = 0.15 if name == "Subsurface Weight" else 0.02
    root = bpy.data.objects.new("Motorcycle", None)
    bpy.context.collection.objects.link(root)
    wheels = bike(root, M)
    rider(root, M)
    scene(root)
    if ANIMATE:
        animate(root, wheels)


if __name__ == "__main__":                     # (tools/rider_real.py borrows the bikes and the scene)
    main()
