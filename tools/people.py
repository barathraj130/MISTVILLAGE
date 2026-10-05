"""
People for The Mist Village, designed from scratch in Blender (no downloaded assets).

    Blender -b --factory-startup --python tools/people.py -- godot/assets/people

Builds six South Indian everyday characters, each a single skinned mesh on a 19-bone skeleton
with hand-keyed animations, and exports person_<name>.glb:

    man_shirt     shirt and trousers, sandals
    man_lungi     half-sleeve shirt and checked lungi
    elder         white veshti (dhoti), shawl, grey hair, slower stance
    woman_saree   saree with pleats and pallu over the shoulder, long braid
    woman_kurta   churidar-kurta with dupatta
    schoolkid     school uniform: white shirt, navy shorts/skirt

Animations: Idle, Walk, Run, Sit (driving / riding), Talk.
Body: built from lofted cross-sections (torso, hips), tapered limb tubes with rounded joints,
a sculpted head (brow, nose, jaw, ears), hair caps / braid. Materials are named so the game can
recolour them per person: Skin, Hair, Top, Bottom, Drape, Shoes.
Blender +Y is the character's back (it faces -Y), so in Godot it faces +Z.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# ----------------------------------------------------------------------------- helpers
def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures, bpy.data.actions):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)


def mat(name, color, rough=0.8, sheen=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    return m


class Body:
    """Accumulates parts into one bmesh, each vertex tagged with bone weights."""

    def __init__(self):
        self.bm = bmesh.new()
        self.weights = []          # per vertex: {bone: w}
        self.mats = []             # material names, index = slot
        self.face_mat = []

    def slot(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def ring_tube(self, rings, material, weight_fn, cap0=True, cap1=True):
        """rings: list of (centre Vector, radius_x, radius_y, segs) along a path; weight_fn(i_ring, vert_pos) -> dict"""
        s = self.slot(material)
        vrings = []
        for ri, (c, rx, ry, segs, *rest) in enumerate(rings):
            axis = rest[0] if rest else Vector((0, 0, 1))
            # build a frame perpendicular to axis
            a = axis.normalized()
            up = Vector((0, 1, 0)) if abs(a.y) < 0.9 else Vector((1, 0, 0))
            u = a.cross(up).normalized()
            v = a.cross(u).normalized()
            ring = []
            for k in range(segs):
                t = 2 * math.pi * k / segs
                p = c + u * (math.cos(t) * rx) + v * (math.sin(t) * ry)
                vert = self.bm.verts.new(p)
                self.weights.append(weight_fn(ri, p))
                ring.append(vert)
            vrings.append(ring)
        for r1, r2 in zip(vrings, vrings[1:]):
            n = len(r1)
            for k in range(n):
                f = self.bm.faces.new((r1[k], r1[(k + 1) % n], r2[(k + 1) % n], r2[k]))
                self.face_mat.append((f, s))
        for cap, ring, idx in ((cap0, vrings[0], 0), (cap1, vrings[-1], len(rings) - 1)):
            if not cap:
                continue
            c = sum((v.co for v in ring), Vector()) / len(ring)
            cv = self.bm.verts.new(c + (rings[idx][4] if len(rings[idx]) > 5 else Vector()))
            self.weights.append(weight_fn(idx, c))
            n = len(ring)
            for k in range(n):
                f = self.bm.faces.new((ring[k], ring[(k + 1) % n], cv))
                self.face_mat.append((f, s))

    def ellipsoid(self, centre, radii, material, weights, segs=14, rings=10, squash=None):
        s = self.slot(material)
        verts = []
        for i in range(rings + 1):
            phi = math.pi * i / rings
            row = []
            for k in range(segs):
                th = 2 * math.pi * k / segs
                d = Vector((math.sin(phi) * math.cos(th), math.sin(phi) * math.sin(th), math.cos(phi)))
                p = Vector((d.x * radii[0], d.y * radii[1], d.z * radii[2]))
                if squash:
                    p = squash(p, d)
                v = self.bm.verts.new(centre + p)
                self.weights.append(dict(weights) if isinstance(weights, dict) else weights(centre + p))
                row.append(v)
            verts.append(row)
        for i in range(rings):
            for k in range(segs):
                a, b = verts[i][k], verts[i][(k + 1) % segs]
                c, d = verts[i + 1][(k + 1) % segs], verts[i + 1][k]
                if i == 0:
                    f = self.bm.faces.new((a, c, d)) if a != b else None
                elif i == rings - 1:
                    f = self.bm.faces.new((a, b, d))
                else:
                    f = self.bm.faces.new((a, b, c, d))
                if f:
                    self.face_mat.append((f, s))

    def finish(self, name, materials):
        # (no remove_doubles: merging would renumber vertices and break the weight list)
        self.bm.verts.index_update()
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        for f, s in self.face_mat:
            if f.is_valid:
                f.material_index = s
                f.smooth = True
        self.bm.to_mesh(me)
        for mname in self.mats:
            me.materials.append(materials[mname])
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        groups = {}
        for vi, w in enumerate(self.weights):
            if vi >= len(me.vertices):
                break
            for bone, val in w.items():
                if val <= 0.0:
                    continue
                if bone not in groups:
                    groups[bone] = obj.vertex_groups.new(name=bone)
                groups[bone].add([vi], val, 'REPLACE')
        return obj


def blend(b0, b1, t):
    t = max(0.0, min(1.0, t))
    return {b0: 1.0 - t, b1: t} if b0 != b1 else {b0: 1.0}


# ----------------------------------------------------------------------------- skeleton
def skeleton(H):
    """Bones for a person of height H (feet at z=0, facing -Y). Returns (armature obj, joints)."""
    s = H / 1.70
    J = {
        "hips": Vector((0, 0, 0.98 * s)), "spine": Vector((0, 0.0, 1.12 * s)), "chest": Vector((0, 0.01, 1.30 * s)),
        "neck": Vector((0, 0.01, 1.47 * s)), "head": Vector((0, 0.0, 1.56 * s)), "top": Vector((0, 0.0, 1.70 * s)),
    }
    for side, sx in (("L", 1), ("R", -1)):          # +X is the character's left (it faces -Y)
        J["shoulder." + side] = Vector((0.172 * s * sx, 0.01, 1.405 * s))
        J["elbow." + side] = Vector((0.23 * s * sx, 0.03, 1.13 * s))
        J["wrist." + side] = Vector((0.25 * s * sx, -0.01, 0.88 * s))
        J["hand_end." + side] = Vector((0.26 * s * sx, -0.02, 0.78 * s))
        J["hip." + side] = Vector((0.095 * s * sx, 0, 0.93 * s))
        J["knee." + side] = Vector((0.1 * s * sx, -0.01, 0.50 * s))
        J["ankle." + side] = Vector((0.1 * s * sx, 0.02, 0.08 * s))
        J["toe." + side] = Vector((0.1 * s * sx, -0.13 * s, 0.02))
    arm = bpy.data.armatures.new("Rig")
    rig = bpy.data.objects.new("Rig", arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones

    def bone(name, head, tail, parent=None):
        b = eb.new(name)
        b.head, b.tail = head, tail
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
        return b
    bone("Root", Vector((0, 0, 0)), Vector((0, 0.15, 0)))
    bone("Hips", J["hips"], J["spine"], "Root")
    bone("Spine", J["spine"], J["chest"], "Hips")
    bone("Chest", J["chest"], J["neck"], "Spine")
    bone("Neck", J["neck"], J["head"], "Chest")
    bone("Head", J["head"], J["top"], "Neck")
    for side in ("L", "R"):
        bone("UpperArm." + side, J["shoulder." + side], J["elbow." + side], "Chest")
        bone("LowerArm." + side, J["elbow." + side], J["wrist." + side], "UpperArm." + side)
        bone("Hand." + side, J["wrist." + side], J["hand_end." + side], "LowerArm." + side)
        bone("Thigh." + side, J["hip." + side], J["knee." + side], "Hips")
        bone("Shin." + side, J["knee." + side], J["ankle." + side], "Thigh." + side)
        bone("Foot." + side, J["ankle." + side], J["toe." + side], "Shin." + side)
    bpy.ops.object.mode_set(mode='OBJECT')
    return rig, J


# ----------------------------------------------------------------------------- body
def limb(body, a, b, ra, rb, material, bone_a, bone_b, parent_bone, segs=12, steps=6, blend_top=0.18, flat=1.0, joint=True):
    """A tapered tube from joint a to joint b, bulging a little mid-way (muscle), weighted to its
    bone with a soft blend into the parent bone at the top and the child bone at the bottom."""
    axis = (b - a)
    rings = []
    for i in range(steps + 1):
        t = i / steps
        r = ra + (rb - ra) * t
        r *= 1.0 + 0.12 * math.sin(math.pi * min(t * 1.3, 1.0))
        rings.append((a + axis * t, r, r * flat, segs, axis))

    def w(ri, p):
        t = ri / steps
        if t < blend_top:
            return blend(parent_bone, bone_a, 0.5 + t / blend_top * 0.5)
        if t > 1.0 - blend_top and bone_b:
            return blend(bone_a, bone_b, (t - (1.0 - blend_top)) / blend_top * 0.5)
        return {bone_a: 1.0}
    body.ring_tube(rings, material, w, cap0=False, cap1=False)
    # rounded joint ends
    if joint:
        body.ellipsoid(a, (ra * 0.82, ra * 0.82 * flat, ra * 0.82), material, blend(parent_bone, bone_a, 0.5), segs=segs, rings=6)


def torso(body, J, s, top_mat, bottom_mat, female):
    """Hips to neck as lofted ellipses: waist, ribcage, shoulders. Top garment above the belt."""
    z0, z1 = J["hip.L"].z - 0.05 * s, J["neck"].z
    keys = [  # (z, half width, half depth)
        (z0, 0.165 if female else 0.15, 0.11),
        (J["hips"].z, 0.17 if female else 0.155, 0.115),
        (J["spine"].z, 0.135 if female else 0.145, 0.105),
        (J["spine"].z + 0.08 * s, 0.14 if female else 0.155, 0.115 if female else 0.11),
        (J["chest"].z, 0.16 if female else 0.175, 0.125 if female else 0.12),
        (J["chest"].z + 0.08 * s, 0.185, 0.115),
        (J["neck"].z - 0.04 * s, 0.16, 0.09),
        (z1, 0.06, 0.055),
    ]
    belt = J["hips"].z + 0.02 * s
    for lo, hi in ((0, 2), (2, len(keys))):
        part = keys[lo:hi + 1] if lo == 0 else keys[lo - 0:]
        material = bottom_mat if lo == 0 else top_mat
        rings = [(Vector((0, 0.005, z)), hw * s / 1.0, hd * s, 16) for z, hw, hd in (keys[0:3] if lo == 0 else keys[2:])]

        def w(ri, p):
            z = p.z
            if z < J["hips"].z:
                return {"Hips": 1.0}
            if z < J["spine"].z:
                return blend("Hips", "Spine", (z - J["hips"].z) / (J["spine"].z - J["hips"].z))
            if z < J["chest"].z:
                return blend("Spine", "Chest", (z - J["spine"].z) / (J["chest"].z - J["spine"].z))
            if z < J["neck"].z - 0.03:
                return {"Chest": 1.0}
            return blend("Chest", "Neck", 0.5)
        body.ring_tube(rings, material, w, cap0=(lo == 0), cap1=False)
    return belt


def head(body, J, s, skin, hair, style, female, elder):
    c = J["head"] + Vector((0, -0.01, 0.075 * s))
    def shape(p, d):
        q = Vector(p)
        if d.z < -0.3:                   # jaw narrows
            q.x *= 0.82 + 0.18 * (1 + d.z)
        if d.y < -0.6 and abs(d.x) < 0.3 and -0.3 < d.z < 0.25:   # nose
            q.y -= 0.018 * s * (1 - abs(d.x) / 0.3)
        if d.y < -0.4 and 0.15 < d.z < 0.35:                         # brow
            q.y -= 0.006 * s
        return q
    body.ellipsoid(c, (0.078 * s, 0.092 * s, 0.108 * s), skin, {"Head": 1.0}, segs=18, rings=14, squash=shape)
    for sx in (1, -1):                   # ears
        body.ellipsoid(c + Vector((0.078 * s * sx, 0.01, -0.005)), (0.012 * s, 0.022 * s, 0.03 * s), skin, {"Head": 1.0}, segs=8, rings=5)
    # neck
    body.ring_tube([(J["neck"] - Vector((0, 0, 0.03)), 0.05 * s, 0.05 * s, 12), (J["head"] + Vector((0, 0, 0.02)), 0.046 * s, 0.05 * s, 12)],
                   skin, lambda ri, p: blend("Neck", "Head", ri * 0.6), cap0=False, cap1=False)
    # hair
    if style != "bald":
        def cap(p, d):
            q = Vector(p)
            if d.z < -0.05 and d.y < 0.2:
                q = q * 0.0 + Vector((p.x, p.y, max(p.z, 0.0)))      # keep the face clear
            return q
        hr = (0.084 * s, 0.098 * s, 0.112 * s)
        body.ellipsoid(c + Vector((0, 0.006, 0.01)), hr, hair, {"Head": 1.0}, segs=18, rings=10,
                       squash=lambda p, d: Vector((p.x, p.y, p.z if (d.z > -0.15 or d.y > 0.3) else -0.15 * hr[2])))
    if style == "braid":
        # a long plait down the back
        pts = [c + Vector((0, 0.09 * s, -0.04 * s - i * 0.07 * s)) for i in range(7)]
        body.ring_tube([(p, 0.03 * s * (1 - i * 0.07), 0.03 * s * (1 - i * 0.07), 8, Vector((0, 0.15, -1))) for i, p in enumerate(pts)],
                       hair, lambda ri, p: blend("Head", "Chest", min(ri / 3.0, 1.0)), cap0=False, cap1=True)
    if style == "bun":
        body.ellipsoid(c + Vector((0, 0.1 * s, 0.02)), (0.045 * s, 0.04 * s, 0.045 * s), hair, {"Head": 1.0}, segs=10, rings=7)
    if style == "moustache":
        body.ellipsoid(c + Vector((0, -0.088 * s, -0.035 * s)), (0.03 * s, 0.008 * s, 0.007 * s), hair, {"Head": 1.0}, segs=10, rings=4)


def person(spec, out_dir):
    reset()
    H = spec["height"]
    s = H / 1.70
    rig, J = skeleton(H)
    M = {
        "Skin": mat("Skin", spec["skin"], 0.55),
        "Hair": mat("Hair", spec.get("hair_col", (0.02, 0.018, 0.015)), 0.6),
        "Top": mat("Top", spec["top"], 0.85),
        "Bottom": mat("Bottom", spec["bottom"], 0.85),
        "Drape": mat("Drape", spec.get("drape", spec["top"]), 0.8),
        "Shoes": mat("Shoes", (0.12, 0.07, 0.04), 0.7),
    }
    female = spec.get("female", False)
    body = Body()
    sleeve = spec.get("sleeve", "half")              # half | full | none
    torso(body, J, s, "Top", "Bottom" if spec["lower"] in ("trousers", "shorts") else "Top", female)
    head(body, J, s, "Skin", "Hair", spec.get("hair", "short"), female, spec.get("elder", False))
    for side in ("L", "R"):
        sh, el, wr, he = J["shoulder." + side], J["elbow." + side], J["wrist." + side], J["hand_end." + side]
        upper = "Top" if sleeve in ("half", "full") else "Skin"
        limb(body, sh, el, 0.048 * s, 0.038 * s, upper if sleeve == "full" else "Top", "UpperArm." + side, "LowerArm." + side, "Chest")
        if sleeve == "half":
            # bare forearm below a short sleeve
            mid = sh + (el - sh) * 0.55
            limb(body, mid, el, 0.04 * s, 0.035 * s, "Skin", "UpperArm." + side, "LowerArm." + side, "UpperArm." + side, blend_top=0.05, joint=False)
        limb(body, el, wr, 0.036 * s, 0.027 * s, "Top" if sleeve == "full" else "Skin", "LowerArm." + side, "Hand." + side, "UpperArm." + side)
        body.ellipsoid(wr + (he - wr) * 0.5, (0.022 * s, 0.045 * s, 0.05 * s), "Skin", {"Hand." + side: 1.0}, segs=10, rings=6,
                       squash=lambda p, d: Vector((p.x, p.y * 0.5, p.z)))
        hp, kn, an, to = J["hip." + side], J["knee." + side], J["ankle." + side], J["toe." + side]
        leg = {"trousers": "Bottom", "shorts": "Skin", "lungi": "Skin", "veshti": "Skin", "saree": "Skin", "churidar": "Bottom"}[spec["lower"]]
        thigh = "Bottom" if spec["lower"] in ("trousers", "shorts", "churidar") else leg
        wrapped = spec["lower"] in ("lungi", "veshti", "saree")
        if not wrapped:                      # legs inside a wrap would only poke through it
            limb(body, hp, kn, 0.075 * s, 0.05 * s, thigh, "Thigh." + side, "Shin." + side, "Hips")
            limb(body, kn, an, 0.048 * s, 0.032 * s, "Bottom" if spec["lower"] in ("trousers", "churidar") else "Skin",
                 "Shin." + side, "Foot." + side, "Thigh." + side)
        else:                                # just the ankles below the hem
            limb(body, an + (kn - an) * 0.18, an, 0.035 * s, 0.031 * s, "Skin", "Shin." + side, "Foot." + side, "Shin." + side, joint=False)
        # sandal / shoe
        body.ellipsoid((an + to) * 0.5 + Vector((0, 0, -0.035)), (0.045 * s, 0.13 * s, 0.035 * s), "Shoes", {"Foot." + side: 1.0},
                       segs=10, rings=6)
    # wrapped garments: a skirt tube from the waist that the thighs carry as they swing
    if spec["lower"] in ("lungi", "veshti", "saree", "churidar"):
        hem = {"lungi": 0.1, "veshti": 0.08, "saree": 0.03, "churidar": 0.55}[spec["lower"]] * s
        mat_name = "Bottom" if spec["lower"] != "churidar" else "Top"    # kurta skirt in the top colour
        top_z = J["hips"].z + 0.04 * s
        zs = [top_z - (top_z - hem) * t for t in (0.0, 0.2, 0.45, 0.7, 1.0)]
        rings = [(Vector((0, 0.005, z)), (0.175 + 0.014 * i) * s, (0.13 + 0.016 * i) * s, 18) for i, z in enumerate(zs)]

        def skirt_w(ri, p):
            if ri == 0:
                return {"Hips": 1.0}
            t = min(ri / 4.0, 1.0)
            side = "L" if p.x > 0 else "R"
            k = min(abs(p.x) / (0.12 * s), 1.0) * t
            return {"Hips": 1.0 - k, "Thigh." + side: k}
        body.ring_tube(rings, mat_name, skirt_w, cap0=False, cap1=False)
    if spec.get("drape"):
        # pallu / shawl / dupatta: a band from the left shoulder across the chest to the right hip
        a = J["shoulder.L"] + Vector((0, 0, 0.03))
        b = J["hip.R"] + Vector((0, -0.12 * s, 0.05))
        pts = [a + (b - a) * (i / 6) + Vector((0, -0.11 * s * math.sin(math.pi * i / 6), 0)) for i in range(7)]
        body.ring_tube([(p, 0.09 * s, 0.015 * s, 10, (b - a)) for p in pts], "Drape",
                       lambda ri, p: {"Chest": 1.0} if ri < 4 else blend("Chest", "Hips", (ri - 3) / 3.0), cap0=True, cap1=True)
    mesh = body.finish("Body", M)
    mesh.parent = rig
    mod = mesh.modifiers.new("Armature", 'ARMATURE')
    mod.object = rig
    animate(rig, spec)
    out = os.path.join(out_dir, "person_%s.glb" % spec["name"])
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_animations=True,
                              export_animation_mode='ACTIONS', export_skins=True, export_yup=True)
    print("PERSON", spec["name"], len(mesh.data.vertices), "verts", "->", out)


# ----------------------------------------------------------------------------- animation
def key(rig, frame, poses):
    """poses: bone -> (rx, ry, rz) degrees in the bone's local frame, plus 'Hips_loc'."""
    for pb in rig.pose.bones:
        pb.rotation_mode = 'XYZ'
        r = poses.get(pb.name, (0, 0, 0))
        pb.rotation_euler = tuple(math.radians(v) for v in r)
        pb.keyframe_insert("rotation_euler", frame=frame)
    hb = rig.pose.bones["Hips"]
    up = poses.get("Hips_loc", (0, 0, 0))[2]          # the Hips bone points up: its local Y is world up
    hb.location = (0, up, 0)
    hb.keyframe_insert("location", frame=frame)


def action(rig, name, frames):
    act = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = act
    for f, poses in frames:
        key(rig, f, poses)
    act.use_fake_user = True
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, int(frames[0][0]), act)
    rig.animation_data.action = None


def animate(rig, spec):
    elder = spec.get("elder", False)
    sw = 0.7 if elder else 1.0
    if spec["lower"] in ("lungi", "veshti", "saree"):
        sw *= 0.6                                       # short steps in a wrap: legs stay inside it
    # bones hang down with roll 0: local X rotation swings them forward (−) / back (+)
    def walk_pose(ph, amp=1.0, run=False):
        a = math.sin(ph)
        k = 1.0 if not run else 1.7
        bob = abs(math.cos(ph)) * (0.02 if not run else 0.05)
        return {
            "Thigh.L": (-28 * a * amp * sw * k, 0, 0), "Thigh.R": (28 * a * amp * sw * k, 0, 0),
            "Shin.L": (max(0, 40 * math.sin(ph + 1.2)) * amp * k, 0, 0), "Shin.R": (max(0, 40 * math.sin(ph + 1.2 + math.pi)) * amp * k, 0, 0),
            "Foot.L": (-10 * a * amp, 0, 0), "Foot.R": (10 * a * amp, 0, 0),
            "UpperArm.L": (22 * a * amp * sw * k, 0, 6), "UpperArm.R": (-22 * a * amp * sw * k, 0, -6),
            "LowerArm.L": (-15 - 10 * max(a, 0) * k, 0, 0), "LowerArm.R": (-15 - 10 * max(-a, 0) * k, 0, 0),
            "Spine": (4 if not run else 10, 4 * a, 0), "Chest": (0, -6 * a * amp, 0),
            "Head": (-3 if not elder else 6, 3 * a, 0),
            "Hips_loc": (0, 0, -bob),
        }
    action(rig, "Walk", [(1 + i * 4, walk_pose(i * math.pi / 4)) for i in range(9)])
    action(rig, "Run", [(1 + i * 2, walk_pose(i * math.pi / 4, 1.0, True)) for i in range(9)])
    idle = lambda b: {"UpperArm.L": (0, 0, 4), "UpperArm.R": (0, 0, -4), "LowerArm.L": (-8, 0, 0), "LowerArm.R": (-8, 0, 0),
                      "Chest": (b, 0, 0), "Head": (6 if elder else 0, 0, 0)}
    action(rig, "Idle", [(1, idle(0)), (36, idle(1.5)), (72, idle(0))])
    talk = lambda t: {"UpperArm.R": (-30, 0, -10), "LowerArm.R": (-60 - 20 * t, 0, 0), "Hand.R": (0, 30 * t, 0),
                      "UpperArm.L": (0, 0, 4), "Head": (0, 10 * t, 0), "Chest": (0, 5 * t, 0)}
    action(rig, "Talk", [(1, talk(0)), (12, talk(1)), (24, talk(-0.5)), (36, talk(0.8)), (48, talk(0))])
    # seated (driving / riding): thighs forward, shins down, hands out to the wheel or bars
    sit = {"Thigh.L": (-85, 0, 4), "Thigh.R": (-85, 0, -4), "Shin.L": (80, 0, 0), "Shin.R": (80, 0, 0),
           "UpperArm.L": (-45, 0, 12), "UpperArm.R": (-45, 0, -12), "LowerArm.L": (-35, 0, 0), "LowerArm.R": (-35, 0, 0),
           "Spine": (-6, 0, 0), "Hips_loc": (0, 0, -0.45)}
    action(rig, "Sit", [(1, sit), (24, sit)])


PEOPLE = [
    # a bronze statue for junction islands (the game holds it in the raised-arm frame of "Talk")
    {"name": "statue", "height": 1.75, "skin": (0.3, 0.2, 0.11), "top": (0.3, 0.2, 0.11), "bottom": (0.3, 0.2, 0.11),
     "drape": (0.32, 0.21, 0.12), "hair_col": (0.27, 0.18, 0.1), "lower": "veshti", "sleeve": "full", "hair": "short"},
    {"name": "man_shirt", "height": 1.71, "skin": (0.36, 0.22, 0.14), "top": (0.82, 0.84, 0.86), "bottom": (0.12, 0.13, 0.18),
     "lower": "trousers", "sleeve": "full", "hair": "moustache"},
    {"name": "man_lungi", "height": 1.68, "skin": (0.3, 0.18, 0.11), "top": (0.25, 0.42, 0.62), "bottom": (0.55, 0.12, 0.1),
     "lower": "lungi", "sleeve": "half", "hair": "short"},
    {"name": "elder", "height": 1.64, "skin": (0.33, 0.2, 0.13), "top": (0.9, 0.9, 0.86), "bottom": (0.93, 0.92, 0.88),
     "drape": (0.85, 0.8, 0.7), "lower": "veshti", "sleeve": "half", "hair": "short", "hair_col": (0.7, 0.7, 0.68), "elder": True},
    {"name": "woman_saree", "height": 1.57, "skin": (0.38, 0.24, 0.15), "top": (0.55, 0.08, 0.2), "bottom": (0.65, 0.12, 0.28),
     "drape": (0.72, 0.5, 0.1), "lower": "saree", "sleeve": "half", "hair": "braid", "female": True},
    {"name": "woman_kurta", "height": 1.6, "skin": (0.42, 0.27, 0.17), "top": (0.12, 0.45, 0.42), "bottom": (0.9, 0.85, 0.75),
     "drape": (0.95, 0.75, 0.3), "lower": "churidar", "sleeve": "full", "hair": "bun", "female": True},
    {"name": "schoolkid", "height": 1.38, "skin": (0.35, 0.22, 0.14), "top": (0.92, 0.92, 0.94), "bottom": (0.1, 0.14, 0.32),
     "lower": "shorts", "sleeve": "half", "hair": "short"},
]

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(args[0] if args else "godot/assets/people")
    only = args[1:]
    os.makedirs(out_dir, exist_ok=True)
    for spec in PEOPLE:
        if not only or spec["name"] in only:
            person(spec, out_dir)
