"""
A real person riding a motorcycle or a scooter: a MakeHuman body (MPFB2, the same people as the game's streets) posed
onto the vehicle by solving its arm and leg bones to the bike (hips on the seat, hands on the grips with the fingers
closed round them, feet on the footpegs / floorboard, head up looking down the road), in a detailed full-face
helmet, on the motorcycle or scooter of tools/rider_scene.py, under a real sky, riding past the camera.

Needs the MPFB add-on (so no --factory-startup):
    Blender --python tools/rider_real.py                                   (open it in Blender's window)
    Blender -b --python tools/rider_real.py -- --render previews/rider_real/rider   (+ _side/_close/_helmet.jpg)
Settings are just below.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if not os.path.exists(os.path.join(HERE, "rider_scene.py")):     # run from Blender's text editor: use its file path
    HERE = os.path.dirname(bpy.path.abspath(bpy.data.texts[os.path.basename(__file__)].filepath))
sys.path.insert(0, os.path.join(HERE, "humans"))
sys.path.insert(0, HERE)
import street_people as SP  # noqa: E402
import bikes_real as BR  # noqa: E402

# ---- settings: change and run again ----
VEHICLE = "motorcycle"              # "motorcycle" or "scooter"
# the rider: gender (1 man, 0 woman), age, weight, muscle, height (0..1), MakeHuman skin, eyebrows
RIDER = (1.0, 30, 0.55, 0.6, 0.6, "young_african_male", "mindfront_eyebrows_03")
SHIRT = (0.16, 0.3, 0.55)
PAINT = (0.5, 0.03, 0.04)           # the bike's paint (tools/bikes_real.py)
LEAN = None                         # forward lean in degrees (None: the vehicle's own)
CURL = 68.0                         # how far each finger joint closes round the grip (degrees)
# helmet
SHELL = (0.62, 0.03, 0.04)          # shell paint
GRAPHIC = (0.93, 0.93, 0.9)         # the stripes
VISOR_TINT = 0.75                   # 0 clear .. 1 dark smoke
ANIMATE = True


def load_bikes():
    """tools/rider_scene.py, set to this VEHICLE, as a library (its materials, helpers, road, camera, animation)."""
    src = open(os.path.join(HERE, "rider_scene.py")).read()
    src = src.replace('VEHICLE = "scooter"', 'VEHICLE = "%s"' % VEHICLE, 1)
    ns = {"__name__": "rider_scene_lib", "__file__": os.path.join(HERE, "rider_scene.py")}
    exec(compile(src, "rider_scene.py", "exec"), ns)
    return ns


RS = load_bikes()
FIT = BR.FIT[VEHICLE]                                 # where the rider goes on the bike
LEAN_DEG = LEAN if LEAN is not None else FIT["lean"] + 4.0
GRIP = Vector(FIT["grip"])                            # grip centres (x, ±y, z)
FOOT = Vector(FIT["foot"])                            # left footrest
HIP = Vector(FIT["hip"])                              # hip joints' midpoint, sitting on the seat
POSE = {}


# ---- posing: everything in the armature's frame (the person faces -Y, his left is +X) ----
def to_h(p, hip_h):
    """A point of the bike (X forward, Y left) to the person's frame, with the bike's hip point at his hips."""
    d = Vector(p) - HIP
    return hip_h + Vector((d.y, -d.x, d.z))


def head_of(arm, name):
    return arm.matrix_world @ arm.pose.bones[name].head


def tail_of(arm, name):
    return arm.matrix_world @ arm.pose.bones[name].tail


def turn(arm, name, q):
    """Rotate a pose bone (and everything below it) about its head by the world rotation q."""
    pb = arm.pose.bones[name]
    m = arm.matrix_world @ pb.matrix
    t = m.translation.copy()
    pb.matrix = arm.matrix_world.inverted() @ (Matrix.Translation(t) @ q.to_matrix().to_4x4()
                                               @ Matrix.Translation(-t) @ m)
    bpy.context.view_layer.update()


def aim(arm, name, tip, target):
    """Turn bone `name` about its head so that the point tip() (moving with it) lies towards target."""
    p = head_of(arm, name)
    turn(arm, name, (tip() - p).rotation_difference(Vector(target) - p))


def two_bone(root, target, l1, l2, pole):
    d = target - root
    dist = min(d.length, l1 + l2 - 1e-3)
    n = d.normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    return root + n * a + (pole - n * pole.dot(n)).normalized() * h


def ride_pose(arm, kind, rng, arm_angle=52):
    if kind != "ride":
        return ORIGINAL_POSE(arm, kind, rng, arm_angle)
    hip_h = (head_of(arm, "upperleg01.L") + head_of(arm, "upperleg01.R")) / 2
    POSE["hip_h"] = hip_h
    lean = math.radians(LEAN_DEG)
    turn(arm, "spine05", Quaternion((1, 0, 0), lean * 0.55))          # the back bends forward, lower and upper
    turn(arm, "spine02", Quaternion((1, 0, 0), lean * 0.45))
    turn(arm, "neck01", Quaternion((1, 0, 0), -lean * 0.85))          # head up, looking down the road
    for side, s in (("L", 1), ("R", -1)):
        b = lambda n: n + "." + side                                  # noqa: E731
        # legs: thigh along the seat / tank, shin down to the footrest, foot flat and forward
        hj = head_of(arm, b("upperleg01"))
        kn0, an0 = head_of(arm, b("lowerleg01")), head_of(arm, b("foot"))
        ankle = to_h(Vector((FOOT.x - 0.05, s * FOOT.y, FOOT.z + 0.085)), hip_h)
        knee = two_bone(hj, ankle, (kn0 - hj).length, (an0 - kn0).length, Vector((s * 0.25, -1.0, 0.35)))
        aim(arm, b("upperleg01"), lambda: head_of(arm, b("lowerleg01")), knee)
        aim(arm, b("lowerleg01"), lambda: head_of(arm, b("foot")), ankle)
        aim(arm, b("foot"), lambda: tail_of(arm, b("foot")), ankle + Vector((s * 0.02, -0.06, -0.03)))
        # arms: shoulder → elbow (out and down) → wrist just behind the grip
        sh = head_of(arm, b("upperarm01"))
        el0, wr0 = head_of(arm, b("lowerarm01")), head_of(arm, b("wrist"))
        grip = to_h(Vector((GRIP.x, s * GRIP.y, GRIP.z)), hip_h)
        wrist = to_h(Vector((GRIP.x - 0.075, s * (GRIP.y - 0.02), GRIP.z + 0.025)), hip_h)
        elbow = two_bone(sh, wrist, (el0 - sh).length, (wr0 - el0).length, Vector((s * 1.0, 0.25, -0.9)))
        aim(arm, b("upperarm01"), lambda: head_of(arm, b("lowerarm01")), elbow)
        aim(arm, b("lowerarm01"), lambda: head_of(arm, b("wrist")), wrist)
        # hand: knuckles over the bar, then the fingers closed round it (about the bar's own axis, X here)
        aim(arm, b("wrist"), lambda: head_of(arm, b("finger3-1")), grip + Vector((0, -0.025, 0.035)))
        for f in range(2, 6):
            for j in range(1, 4):
                turn(arm, b("finger%d-%d" % (f, j)), Quaternion((1, 0, 0), math.radians(CURL * (0.8 if j == 1 else 1.0))))
        for j in range(1, 4):                                         # thumb round the near side
            turn(arm, b("finger1-%d" % j), Quaternion((0, 0, 1), math.radians(-s * 20)))
        print("RIDER %s %s  wrist→target %.3f  ankle→target %.3f  fingertip→bar %.3f" % (
            VEHICLE, side, (head_of(arm, b("wrist")) - wrist).length, (head_of(arm, b("foot")) - ankle).length,
            (tail_of(arm, b("finger3-3")) - grip).length), flush=True)
    hb, ht = head_of(arm, "head"), tail_of(arm, "head")
    eyes = (head_of(arm, "eye.L") + head_of(arm, "eye.R")) / 2
    up = (ht - hb).normalized()
    centre = hb + (ht - hb) * 0.42
    fwd = (eyes - centre)
    fwd = (fwd - up * fwd.dot(up)).normalized()
    POSE["head"] = (eyes, fwd, up)


ORIGINAL_POSE = SP.pose
SP.pose = ride_pose
SP.STRIDE["ride"] = 0.0


# ---- the helmet: built at the origin facing +X, Z up, then put on the head ----
def deform(co, r):
    """The helmet's shape from a sphere of radius r: long at the back, the chin bar swept forward, a spoiler lip."""
    x, y, z = co
    nx, ny, nz = x * (1.06 if x > 0 else 1.2), y * 0.9, z
    if z < 0 and x > 0:                                       # the chin bar sweeps forward and down
        nx += 0.05 * (-z / r) * (x / r)
        nz *= 1.08
    if x < -0.05 and z > -0.02:                               # a small spoiler lip at the back of the crown
        nx -= 0.012 * max(0.0, 1 - abs(z - 0.06) / 0.05)
    return Vector((nx, ny, nz))


def shell_shape(r):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=96, v_segments=64, radius=r)
    for v in bm.verts:
        v.co = deform(v.co.copy(), r)
    return bm


def snap_port(bm, grows):
    """Pull the edge points of a cut round the eye port onto the exact rounded rectangle (cutting whole faces
    leaves a staircase): each point moves along its ray from the port's centre to the nearest outline in grows."""
    for v in bm.verts:
        if not v.is_boundary or v.co.x < 0.0 or abs(v.co.z) > 0.09:
            continue
        best = None
        for g in grows:
            val = (abs(v.co.y) / (0.105 + g)) ** 4 + (abs(v.co.z) / (0.05 + g)) ** 4
            k = val ** -0.25
            if best is None or abs(k - 1) < abs(best - 1):
                best = k
        v.co.y *= best
        v.co.z *= best


def cut_neck(bm, lift=0.0):
    """Open underneath along one clean slanted plane: higher at the back of the neck, lower under the chin."""
    n = Vector((0.375, 0.0, 1.0)).normalized()
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, -0.085 + lift),
                           plane_no=n, clear_inner=True)


def on_shell(d, r):
    """The point of the shape of radius r in direction d, and its outward normal."""
    d = Vector(d).normalized()
    p = deform(d * r, r)
    q = deform(d * (r + 0.004), r)
    return p, (q - p).normalized()


def stick(name, d, r, dims, mat, parent, lift=0.0):
    """A part set onto the surface in direction d, flat against it: dims = (thickness along the normal, width
    across (Y), length up the surface)."""
    p, n = on_shell(d, r)
    y = (Vector((0, 1, 0)) - n * n.y).normalized()
    rot = Matrix((n, y, n.cross(y))).transposed().to_euler()
    return RS["box"](tuple(p + n * (dims[0] / 2 + lift - 0.003)), dims, mat, parent, min(dims) * 0.3, rot=rot)


def port(p, grow=0.0):
    """The eye port: a rounded rectangle on the front, wider than tall."""
    if p.x < 0.02 - grow:
        return False
    u = abs(p.y) / (0.105 + grow)
    w = abs(p.z - 0.0) / (0.05 + grow)
    return u ** 4 + w ** 4 < 1.0


def solid(name, bm, mats, thick, parent, rim=None, levels=2):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for m in mats:
        me.materials.append(m)
    sol = ob.modifiers.new("Thickness", 'SOLIDIFY')
    sol.thickness = thick
    sol.offset = -1.0
    if rim is not None:
        sol.material_offset = rim
        sol.material_offset_rim = rim
    sub = ob.modifiers.new("Smooth", 'SUBSURF')
    sub.levels = sub.render_levels = levels
    for p in me.polygons:
        p.use_smooth = True
    ob.parent = parent
    return ob


def helmet(M):
    hel = bpy.data.objects.new("Helmet", None)
    bpy.context.collection.objects.link(hel)
    # shell: painted, with the graphic stripes, liner inside and on the cut edges
    bm = shell_shape(0.152)
    cut_neck(bm)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if port(f.calc_center_median())], context='FACES')
    snap_port(bm, (0.0,))
    solid("Shell", bm, (M["shell"], M["graphic"], M["liner"], M["liner"]), 0.016, hel, rim=2)
    # comfort padding showing at the port and round the neck
    bm = shell_shape(0.136)
    cut_neck(bm, 0.008)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if port(f.calc_center_median(), 0.01)
                               or f.calc_center_median().z > 0.06], context='FACES')
    solid("Padding", bm, (M["padding"],), 0.012, hel, levels=1)
    # visor: the shell's shape a little bigger, covering the port with a margin, smoked polycarbonate
    bm = shell_shape(0.1585)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not port(f.calc_center_median(), 0.016)], context='FACES')
    snap_port(bm, (0.016,))
    solid("Visor", bm, (M["visor"],), 0.003, hel)
    # visor gasket round the port, the hinge plates with their screws, the lift tab
    bm = shell_shape(0.1545)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if port(f.calc_center_median()) or not port(f.calc_center_median(), 0.008)],
                     context='FACES')
    snap_port(bm, (0.0, 0.008))
    solid("Gasket", bm, (M["rubber"],), 0.006, hel, levels=1)
    for s in (1, -1):
        bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.026, depth=0.008,
                                            location=(0.03, s * 0.142, 0.012), rotation=(math.pi / 2, 0, 0))
        RS["finish"](bpy.context.object, M["rubber"], hel)
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.007, depth=0.012,
                                            location=(0.03, s * 0.146, 0.012), rotation=(math.pi / 2, 0, 0))
        RS["finish"](bpy.context.object, M["metal"], hel)
    stick("LiftTab", (0.8, 0.42, -0.42), 0.1585, (0.01, 0.022, 0.016), M["rubber"], hel)
    # vents, all sitting on the shell: two sliders on the crown, the slotted chin vent, the rear exhaust
    for s in (1, -1):
        stick("CrownVent", (0.45, s * 0.25, 0.86), 0.152, (0.012, 0.022, 0.05), M["rubber"], hel)
    chin = (math.cos(math.radians(40)), 0, -math.sin(math.radians(40)))
    stick("ChinVent", chin, 0.152, (0.012, 0.07, 0.034), M["rubber"], hel)
    for k in (-1, 0, 1):
        d = (chin[0], 0, chin[2] + k * 0.07)
        stick("ChinSlat", d, 0.152, (0.004, 0.06, 0.004), M["metal"], hel, lift=0.011)
    stick("RearVent", (-0.95, 0, 0.3), 0.152, (0.012, 0.09, 0.024), M["rubber"], hel)
    return hel


# ---- shader helpers ----
def mnode(nt, op, a, b=None):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def ramp(nt, v, lo, hi, a=0.0, b=1.0):
    """Smoothstep v from lo..hi onto a..b (clamped): soft, anti-aliased edges for painted shapes."""
    n = nt.nodes.new("ShaderNodeMapRange")
    n.interpolation_type = 'SMOOTHSTEP'
    n.clamp = True
    nt.links.new(v, n.inputs["Value"])
    for k, val in (("From Min", lo), ("From Max", hi), ("To Min", a), ("To Max", b)):
        n.inputs[k].default_value = val
    return n.outputs["Result"]


def coords(nt):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    return tc, sep


def mix_in(nt, mask, rgb, rough, coat=0.0):
    """Mix a second paint over the material's own where mask is 1."""
    out = nt.nodes["Material Output"]
    base = nt.nodes["Principled BSDF"]
    g = nt.nodes.new("ShaderNodeBsdfPrincipled")
    g.inputs["Base Color"].default_value = (*rgb, 1.0)
    g.inputs["Roughness"].default_value = rough
    for n in ("Coat Weight", "Clearcoat"):
        if n in g.inputs:
            g.inputs[n].default_value = coat
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(mask, mix.inputs[0])
    nt.links.new(base.outputs[0], mix.inputs[1])
    nt.links.new(g.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])


def stripes(m):
    """The helmet's graphic painted by position, not by mesh faces: a thin centre stripe over the crown and a
    wider one either side of it, down to the brow and the back, with clean soft edges."""
    nt = m.node_tree
    _, sep = coords(nt)
    ay = mnode(nt, 'ABSOLUTE', sep.outputs["Y"])
    z = sep.outputs["Z"]
    e = 0.0012
    side = mnode(nt, 'MULTIPLY', ramp(nt, ay, 0.013 - e, 0.013 + e), ramp(nt, ay, 0.03 - e, 0.03 + e, 1.0, 0.0))
    side = mnode(nt, 'MULTIPLY', side, ramp(nt, z, -0.03, -0.012))
    centre = mnode(nt, 'MULTIPLY', ramp(nt, ay, 0.005 - e, 0.005 + e, 1.0, 0.0), ramp(nt, z, -0.004, 0.012))
    mix_in(nt, mnode(nt, 'MAXIMUM', side, centre), GRAPHIC, 0.18, 1.0)


def mats():
    M = {}
    mat = RS["mat"]
    M["shell"] = mat("Helmet Paint", SHELL, 0.18, 0.35)
    M["graphic"] = mat("Helmet Graphic", GRAPHIC, 0.2)
    M["liner"] = mat("Helmet Liner", (0.015, 0.015, 0.017), 0.95)
    M["padding"] = mat("Helmet Padding", (0.03, 0.03, 0.035), 0.95)
    M["rubber"] = mat("Rubber Trim", (0.02, 0.02, 0.022), 0.6)
    M["metal"] = mat("Hinge Screw", (0.6, 0.6, 0.62), 0.25, 1.0)
    M["visor"] = mat("Visor", (0.03, 0.03, 0.035), 0.0)
    for k in ("shell", "graphic"):
        b = M[k].node_tree.nodes["Principled BSDF"]
        for n in ("Coat Weight", "Clearcoat"):
            if n in b.inputs:
                b.inputs[n].default_value = 1.0
    stripes(M["shell"])
    b = M["visor"].node_tree.nodes["Principled BSDF"]
    for n, v in (("Transmission Weight", 1.0 - VISOR_TINT * 0.6), ("Transmission", 1.0 - VISOR_TINT * 0.6),
                 ("IOR", 1.58)):
        if n in b.inputs:
            b.inputs[n].default_value = v
    b.inputs["Base Color"].default_value = (0.06 * (1 - VISOR_TINT) + 0.02,) * 3 + (1.0,)
    return M


def rider(root):
    g, yrs, w, mu, hgt, skin, brows = RIDER
    spec = ("rider", g, yrs, w, mu, hgt, skin, "none", brows, "trousers" if g > 0.5 else "modern_f", "ride", [SHIRT])
    before = set(bpy.data.objects)
    objs = SP.build(spec, 0.0)
    for o in set(bpy.data.objects) - before - set(objs):          # anything else it left (helpers)
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    # from the person's frame onto the bike: his hips on the seat, turned to face +X
    hip_h = POSE["hip_h"]
    place = Matrix.Translation(HIP) @ Matrix.Rotation(math.pi / 2, 4, 'Z') @ Matrix.Translation(-hip_h)
    for o in objs:
        if o.name in bpy.data.objects:
            o.matrix_world = place @ o.matrix_world
            o.parent = root
    eyes, fwd, up = POSE["head"]
    c = place @ eyes
    f = (place.to_3x3() @ fwd).normalized()
    u = (place.to_3x3() @ up).normalized()
    side = u.cross(f).normalized()
    hel = helmet(mats())                                            # (after the person: building him purges unused materials)
    basis = Matrix((f, side, f.cross(side))).transposed()          # helmet X forward, Y left, Z up
    hel.matrix_world = Matrix.Translation(c - f * 0.105 + u * 0.004) @ basis.to_4x4()   # eye port at the eyes
    hel.parent = root
    hel.matrix_parent_inverse = root.matrix_world.inverted()


# ---- the street: the bike rides along +X in the left lane (India keeps left) ----
def slab(name, lo, hi, m):
    """A box from corner lo to corner hi, its scale applied (so textures keep real-world size)."""
    lo, hi = Vector(lo), Vector(hi)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(lo + hi) / 2)
    o = bpy.context.active_object
    o.name = name
    o.scale = hi - lo
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(m)
    return o


def asphalt():
    m = RS["mat"]("Asphalt", (0.06, 0.06, 0.062), 0.88)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    fine = nt.nodes.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 260.0
    fine.inputs["Detail"].default_value = 6.0
    patch = nt.nodes.new("ShaderNodeTexNoise")
    patch.inputs["Scale"].default_value = 0.6
    for n in (fine, patch):
        nt.links.new(tc.outputs["Object"], n.inputs["Vector"])
    cr = nt.nodes.new("ShaderNodeValToRGB")
    cr.color_ramp.elements[0].color = (0.035, 0.035, 0.037, 1)
    cr.color_ramp.elements[1].color = (0.1, 0.098, 0.095, 1)
    nt.links.new(mnode(nt, 'MULTIPLY', fine.outputs["Fac"], patch.outputs["Fac"]), cr.inputs[0])
    nt.links.new(cr.outputs["Color"], b.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    nt.links.new(fine.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def kerb_paint():
    """Kerb stones painted black and yellow, alternating every metre."""
    m = RS["mat"]("Kerb Black", (0.03, 0.03, 0.03), 0.7)
    nt = m.node_tree
    _, sep = coords(nt)
    band = mnode(nt, 'GREATER_THAN', mnode(nt, 'FLOORED_MODULO', sep.outputs["X"], 2.0), 1.0)
    mix_in(nt, band, (0.85, 0.65, 0.05), 0.6)
    return m


def pavers():
    m = RS["mat"]("Pavers", (0.4, 0.39, 0.37), 0.8)
    nt = m.node_tree
    tc = nt.nodes.new("ShaderNodeTexCoord")
    br = nt.nodes.new("ShaderNodeTexBrick")
    br.inputs["Color1"].default_value = (0.42, 0.4, 0.37, 1)
    br.inputs["Color2"].default_value = (0.33, 0.32, 0.3, 1)
    br.inputs["Mortar"].default_value = (0.2, 0.19, 0.18, 1)
    br.inputs["Scale"].default_value = 2.5
    br.inputs["Mortar Size"].default_value = 0.012
    nt.links.new(tc.outputs["Object"], br.inputs["Vector"])
    b = nt.nodes["Principled BSDF"]
    nt.links.new(br.outputs["Color"], b.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.4
    bump.invert = True
    nt.links.new(br.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def weathered(name, rgb, grime=0.25, rough=0.9):
    """Painted plaster as it really looks: the paint's colour mottled a little, and darker grime rising from the
    ground (grime: how far up, as a share of the height)."""
    m = RS["mat"](name, rgb, rough)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    gen = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], gen.inputs[0])
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = 1.2
    n.inputs["Detail"].default_value = 8.0
    nt.links.new(tc.outputs["Object"], n.inputs["Vector"])
    dirt = ramp(nt, gen.outputs["Z"], 0.0, max(grime, 0.01), 1.0, 0.0)
    mottle = mnode(nt, 'ADD', mnode(nt, 'MULTIPLY', n.outputs["Fac"], 0.3), 0.75)        # 0.75 .. 1.05
    f = mnode(nt, 'MULTIPLY', mottle, mnode(nt, 'SUBTRACT', 1.0, mnode(nt, 'MULTIPLY', dirt, 0.4)))
    sc = nt.nodes.new("ShaderNodeVectorMath")
    sc.operation = 'SCALE'
    sc.inputs[0].default_value = rgb
    nt.links.new(f, sc.inputs["Scale"])
    nt.links.new(sc.outputs["Vector"], b.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.08
    nt.links.new(n.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def glass_mat():
    m = RS["mat"]("Window Glass", (0.07, 0.09, 0.11), 0.04, 0.6)
    b = m.node_tree.nodes["Principled BSDF"]
    for n in ("Coat Weight", "Clearcoat"):
        if n in b.inputs:
            b.inputs[n].default_value = 1.0
    return m


def add_box(bm, lo, hi, mi):
    lo, hi = Vector(lo), Vector(hi)
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((lo + hi) / 2) @ Matrix.Diagonal((*(hi - lo), 1.0)))
    for v in res["verts"]:
        for f in v.link_faces:
            f.material_index = mi


def window(bm, cx, z, w=1.0, h=1.3):
    """One window on a facade facing -Y at y = 6: reflective glass, a white frame with a centre mullion and a
    transom, an iron grill in front, a sill below and a concrete sunshade (chajja) above."""
    add_box(bm, (cx, 5.975, z), (cx + w, 6.0, z + h), 1)                                        # glass
    t = 0.06
    for lo, hi in (((cx - t, 5.94, z - t), (cx, 6.0, z + h + t)), ((cx + w, 5.94, z - t), (cx + w + t, 6.0, z + h + t)),
                   ((cx, 5.94, z + h), (cx + w, 6.0, z + h + t)), ((cx, 5.94, z - t), (cx + w, 6.0, z)),
                   ((cx + w / 2 - 0.025, 5.95, z), (cx + w / 2 + 0.025, 5.98, z + h)),
                   ((cx, 5.95, z + h * 0.72), (cx + w, 5.98, z + h * 0.72 + 0.04))):
        add_box(bm, lo, hi, 0)                                                                  # frame
    k = cx + 0.1
    while k < cx + w - 0.05:                                                                    # grill bars
        add_box(bm, (k - 0.008, 5.9, z), (k + 0.008, 5.916, z + h), 2)
        k += 0.13
    for zz in (z + 0.35, z + h - 0.35):
        add_box(bm, (cx, 5.9, zz - 0.01), (cx + w, 5.916, zz + 0.01), 2)
    add_box(bm, (cx - 0.1, 5.86, z - t - 0.06), (cx + w + 0.1, 6.0, z - t), 4)                 # sill
    add_box(bm, (cx - 0.2, 5.5, z + h + t + 0.12), (cx + w + 0.2, 6.0, z + h + t + 0.2), 3)    # sunshade


def leaf_spray():
    """A small neem spray: a stalk with paired pointed leaflets, the instance scattered over the crowns.
    Each copy takes its own green from its random number (Object Info)."""
    bm = bmesh.new()
    for k in range(7):
        x = 0.03 + k * 0.035
        for s in (1, -1):
            if k == 6 and s < 0:
                continue
            ang = math.radians(50 * s) if k < 6 else 0.0
            dirv = Vector((math.cos(ang), math.sin(ang), 0.15))
            side = Vector((-dirv.y, dirv.x, 0)).normalized() * 0.012
            base = Vector((x, 0, 0))
            tip = base + dirv * 0.075
            mid = base + dirv * 0.035
            vs = [bm.verts.new(p) for p in (base, mid + side, tip, mid - side)]
            bm.faces.new(vs)
    me = bpy.data.meshes.new("LeafSpray")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("LeafSpray", me)
    bpy.context.collection.objects.link(ob)
    ob.location = (0, 0, -100)                                      # (only its copies are seen)
    m = RS["mat"]("Neem Leaf", (0.1, 0.25, 0.05), 0.6)
    nt = m.node_tree
    info = nt.nodes.new("ShaderNodeObjectInfo")
    cr = nt.nodes.new("ShaderNodeValToRGB")
    cr.color_ramp.elements[0].color = (0.05, 0.14, 0.03, 1)
    cr.color_ramp.elements[1].color = (0.2, 0.36, 0.07, 1)
    nt.links.new(info.outputs["Random"], cr.inputs[0])
    nt.links.new(cr.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    me.materials.append(m)
    return ob


def street():
    for o in [o for o in bpy.data.objects if o.name.startswith("Plane")]:     # rider_scene's plain road
        bpy.data.objects.remove(o, do_unlink=True)
    L, Y0, Y1 = 40.0, -5.3, 1.7                                    # road along X, 7 m wide, the bike at y = 0
    mat = RS["mat"]
    slab("Ground", (-120, -60, -0.06), (120, 60, -0.02), mat("Earth", (0.22, 0.19, 0.15), 0.95))
    slab("Road", (-L, Y0, -0.1), (L, Y1, 0.0), asphalt())
    paint = mat("Road Paint", (0.82, 0.82, 0.78), 0.55)
    x = -L
    while x < L:                                                   # dashed centre line
        slab("Dash", (x, -1.86, 0.0), (x + 3.0, -1.74, 0.003), paint)
        x += 9.0
    for y in (Y1 - 0.25, Y0 + 0.25):                               # edge lines
        slab("EdgeLine", (-L, y - 0.06, 0.0), (L, y + 0.06, 0.003), paint)
    kerb, pv = kerb_paint(), pavers()
    for side, (k0, k1, f0, f1) in ((1, (Y1, Y1 + 0.15, Y1 + 0.15, 4.2)), (-1, (Y0 - 0.15, Y0, -7.6, Y0 - 0.15))):
        slab("Kerb", (-L, k0, 0.0), (L, k1, 0.17), kerb)
        slab("Footpath", (-L, f0, 0.0), (L, f1, 0.15), pv)
    # a compound wall along the footpath: ochre plaster panels between terracotta pillars, a coping on top
    plaster = weathered("Wall Plaster", (0.55, 0.37, 0.18), 0.35)
    pillar = weathered("Wall Pillar", (0.42, 0.15, 0.1), 0.35)
    coping = weathered("Coping", (0.6, 0.57, 0.5), 0.1)
    slab("Wall", (-L, 4.2, 0.15), (L, 4.4, 1.7), plaster)
    slab("Coping", (-L, 4.17, 1.7), (L, 4.43, 1.76), coping)
    for k in range(-13, 14):
        slab("Pillar", (k * 3.0 - 0.17, 4.14, 0.15), (k * 3.0 + 0.17, 4.46, 1.95), pillar)
    # buildings behind the wall, each its own colour, with real windows (one mesh for all of them)
    colours = [(0.62, 0.42, 0.18), (0.22, 0.4, 0.5), (0.58, 0.25, 0.2), (0.4, 0.48, 0.28), (0.66, 0.6, 0.46),
               (0.38, 0.3, 0.5), (0.68, 0.45, 0.1)]
    win = bmesh.new()
    x, i = -L, 0
    while x < L:
        w, h = 7.0 + (i * 3.7) % 5, 6.5 + (i * 4.3) % 7
        body = weathered("Building %d" % i, colours[i % len(colours)], 0.12)
        slab("Building", (x, 6.0, 0.0), (x + w, 14.0, h), body)
        slab("Parapet", (x - 0.05, 5.95, h), (x + w + 0.05, 6.2, h + 0.5), body)
        z = 1.3
        while z + 1.4 < h:
            add_box(win, (x, 5.93, z - 0.5), (x + w, 6.0, z - 0.38), 3)                 # floor band
            cx = x + 1.0
            while cx + 1.2 < x + w:
                window(win, cx, z)
                cx += 1.8
            z += 3.1
        x += w + 0.6
        i += 1
    me = bpy.data.meshes.new("Windows")
    win.to_mesh(me)
    win.free()
    wo = bpy.data.objects.new("Windows", me)
    bpy.context.collection.objects.link(wo)
    for m in (mat("Window Frame", (0.85, 0.85, 0.82), 0.5), glass_mat(), mat("Window Grill", (0.03, 0.06, 0.04), 0.45, 0.6),
              mat("Sunshade", (0.62, 0.6, 0.56), 0.9), mat("Sill", (0.8, 0.79, 0.75), 0.8)):
        me.materials.append(m)
    # neem trees on the footpath: trunk and branches, a dark inner crown, and thousands of leaf sprays over it
    bark = mat("Bark", (0.16, 0.13, 0.1), 0.9)
    inner = mat("Inner Crown", (0.03, 0.07, 0.02), 0.9)
    tex = bpy.data.textures.new("Foliage", 'CLOUDS')
    tex.noise_scale = 0.45
    spray = leaf_spray()
    for tx in (-15.0, -6.5, 9.0, 19.0):
        top = (tx + 0.05, 3.3, 3.2)
        BR.tube("Trunk", [(tx, 3.35, 0.15), (tx + 0.12, 3.35, 2.0), top], 0.14, bark)
        for k, (dx, dy, dz, r) in enumerate(((0, 0, 4.0, 1.7), (0.9, 0.2, 3.6, 1.2), (-1.0, -0.1, 3.7, 1.25),
                                              (0.2, 0.3, 4.9, 1.2))):
            c = Vector((tx + dx, 3.35 + dy, dz))
            BR.tube("Branch", [top, tuple(Vector(top).lerp(c, 0.5) + Vector((0, 0, 0.25))), tuple(c)], 0.055, bark)
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=r * 0.9, location=c)
            crown = bpy.context.active_object
            d = crown.modifiers.new("Leafy", 'DISPLACE')
            d.texture = tex
            d.strength = 0.45
            crown.data.materials.append(inner)
            F_smooth(crown)
            ps = crown.modifiers.new("Leaves", 'PARTICLE_SYSTEM').particle_system
            ps.seed = int(tx * 10) + k
            st = ps.settings
            st.type = 'HAIR'
            st.use_advanced_hair = True
            st.count = int(1300 * r * r)
            st.hair_length = 0.2
            st.emit_from = 'FACE'
            st.distribution = 'RAND'
            st.render_type = 'OBJECT'
            st.instance_object = spray
            st.particle_size = 2.8                       # a spray about 0.6 m across, like a real neem frond
            st.size_random = 0.4
            st.use_rotations = True
            st.rotation_mode = 'NOR'
            st.rotation_factor_random = 1.0
            st.phase_factor_random = 2.0
    # electric poles with their wires
    concrete = mat("Concrete", (0.55, 0.54, 0.5), 0.9)
    wire = mat("Wire", (0.02, 0.02, 0.02), 0.5)
    poles = (-14.0, 3.5, 21.0)
    for px in poles:
        BR.tube("Pole", [(px, 2.05, 0.15), (px, 2.05, 8.6)], 0.09, concrete)
        slab("CrossArm", (px - 0.06, 1.45, 8.2), (px + 0.06, 2.65, 8.32), concrete)
    for wy in (1.55, 2.05, 2.55):
        pts = [(-L, wy, 8.0)]
        for a, b in zip(poles, poles[1:]):
            pts += [(a, wy, 8.35), ((a + b) / 2, wy, 7.75)]
        pts += [(poles[-1], wy, 8.35), (L, wy, 8.0)]
        BR.tube("Wire", pts, 0.008, wire)


def F_smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True


def sky():
    w = bpy.context.scene.world
    nt = w.node_tree
    sk = nt.nodes.new("ShaderNodeTexSky")
    for t in ("MULTIPLE_SCATTERING", "NISHITA"):
        try:
            sk.sky_type = t
            break
        except TypeError:
            pass
    sk.sun_elevation = math.radians(32)
    sk.sun_rotation = math.radians(-130)
    nt.links.new(sk.outputs[0], nt.nodes["Background"].inputs[0])
    nt.nodes["Background"].inputs[1].default_value = 0.25
    for o in bpy.data.objects:
        if o.type == 'LIGHT':
            o.data.energy = 3.0
            o.rotation_euler = (math.radians(58), 0, math.radians(-130 + 180))
    sc = bpy.context.scene                                      # pale walls under the midday sun: not blown out
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.exposure = -0.9
    for look in ("AgX - Medium High Contrast", "Medium High Contrast"):     # (the look's name by Blender version)
        try:
            sc.view_settings.look = look
            break
        except TypeError:
            pass


def render_stills(out):
    sc = bpy.context.scene
    sc.frame_set((sc.frame_start + sc.frame_end) // 2)
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 96
    sc.cycles.use_denoising = True
    try:
        pr = bpy.context.preferences.addons["cycles"].preferences
        pr.compute_device_type = 'METAL'
        pr.get_devices()
        for d in pr.devices:
            d.use = True
        sc.cycles.device = 'GPU'
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.render.image_settings.file_format = 'JPEG'
    sc.view_settings.view_transform = 'AgX'
    aim_ = bpy.data.objects["CameraAim"]
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    for name, loc, z, lens in (("side", None, 0.95, 45), ("close", (1.9, -2.5, 1.5), 1.0, 45),
                               ("helmet", (1.25, -0.95, 1.85), 1.62, 75)):
        if loc:
            sc.camera.location = loc
        aim_.location.z = z
        sc.camera.data.lens = lens
        sc.render.filepath = os.path.abspath("%s_%s_%s.jpg" % (out, VEHICLE, name))
        bpy.ops.render.render(write_still=True)
        print("RENDER", sc.render.filepath, flush=True)


def main():
    RS["clear"]()
    root = bpy.data.objects.new("Ride", None)
    bpy.context.collection.objects.link(root)
    wheels, _ = BR.build(VEHICLE, root, PAINT)
    RS["R"] = FIT["r"]                                              # (the wheels turn by distance / radius)
    rider(root)
    RS["scene"](root)
    street()
    sky()
    if ANIMATE:
        RS["animate"](root, wheels)
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--render" in args:
        render_stills(args[args.index("--render") + 1])


main()
