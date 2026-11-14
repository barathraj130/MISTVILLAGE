"""
The Sketchfab people (mapdata/sketchfab/people, credited in docs/DATA_SOURCES.md) as living people of the game: each
one skinned to a skeleton with the game's bone names (pelvis, spine_01..03, neck_01, head, clavicle/upperarm/lowerarm/
hand_l/r, the fingers, thigh/calf/foot/ball_l/r), so the game's head turns (head_look.gd), what they hold (crowd_clips
.gd: hand_r) and the gestures work on them as on our own people, and given the game's clips (Idle, Talk, Walk, Run,
Sit, SitTalk, SitEat from a crowd person; Namaste, Wave, Nod, Wobble, Shake, Laugh, Shrug, Point, Argue, Fold,
Handshake, Comfort, Give, Phone, PhoneLook, WalkPhone, WalkCarry from crowd_clips_w/m.glb) and a face: blend shapes
with the names of our faces' units (scripts/story/face.gd: eye-left/right-closure for the blinks, mouth-open for the
words, mouth-corner-puller, mouth-depression, the brows up, down, inner up, the eyes' slit), so acting.gd drives them.

  - the skeleton: a model's own (Mixamo, Renderpeople, Maya: its bones renamed ours) or, with none (rig "auto"), one
    put in from where a body's joints are (T-pose: the arms' line found from the mesh) and skinned by Blender's bone
    each point's nearness to the bones (Blender's bone heat fails on a scan's open surface)
  - the clips moved rig to rig frame by frame: the hips, spine, neck and head turn from where they rest as ours turn,
    the limbs point the way ours point (their rests differ: a T against our A), the hips move as ours, to her scale
  - a saree hangs from the hips: the legs' weights on the cloth eased onto the hips, and below the knee the left and
    the right leg's shared (a stride doesn't split it into trousers, nor stretch the hem between the feet)
  - thinned to its triangle budget, the head kept whole (thinned, a face's texture slides over an eye)
  - the face: a blink is a lid: the skin over each eye copied and, closed, drawn down over it, the lid's own colour
    from just above (open, folded away under the brow); the mouth opens with the chin; brows and the mouth's corners
    move with the skin round them. A Renderpeople rig has its own jaw and eyelid bones: those posed instead.
  - colour variants (tints): the saree's hues turned, a texture each, sfa_<name>_t<i>.jpg (the skin's hues kept)
  - far: one standing still, for the street's MultiMesh crowd far off (sf_<name>.glb; tools/sketchfab_people.py made
    the first ten's), when the model has none yet

Writes godot/assets/people/sfa_<name>.glb (+ sf_<name>.glb, sfa_<name>_t<i>.jpg).
    Blender -b --factory-startup --python tools/sketchfab_living.py -- [names...] [--faceshot DIR] [--tris N]
--faceshot: a picture of each face from the front (1 px a mm, a line each cm; DIR/face_<name>.png, its corner's
place printed) to find the eyes and the mouth for FACE below.
"""
import math
import os
import re
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
from mathutils.geometry import barycentric_transform

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "mapdata", "sketchfab", "people")
OUT = os.path.join(ROOT, "godot", "assets", "people")
REF = {"w": [os.path.join(OUT, "crowd_w1.glb"), os.path.join(OUT, "crowd_clips_w.glb")],
       "m": [os.path.join(OUT, "crowd_m1.glb"), os.path.join(OUT, "crowd_clips_m.glb")]}

# name: file, height (m), sex, saree (skirt), triangles, rig ("own" | "auto"), far (make the still one), rebuild (a
# scan's face given a real face's shape: rebuild_face()), tints (the
# cloth's hue ranges in degrees, and each variant's turn of them)
PEOPLE = {
    "woman_saree_yellow": dict(file="sareewoman/sareewoman.glb", h=1.58, sex="w", skirt=True, tris=45000, far=True,
                               rebuild=True, tints=dict(hues=[(38, 75), (255, 350)], turns=[-55, 150, 95])),
    "woman_saree_pink": dict(file="pink_saree_lady_3d_model/pink_saree_lady_3d_model.glb", h=1.56, sex="w", skirt=True,
                             tris=45000, rig="auto", far=True, rebuild=True, tints=dict(hues=[(285, 360), (0, 8)], turns=[-120, 160])),
    "woman_saree_green": dict(file="indian_woman_in_saree.glb", h=1.58, sex="w", skirt=True, tris=65000),
    "woman_office": dict(file="claudia_rigged_002_-_3d_rigged_business_women.glb", h=1.60, sex="w", tris=22000),
    "woman_office2": dict(file="carla_rigged_001_-_rigged_3d_business_women.glb", h=1.58, sex="w", tris=22000),
    "man_kurta_blue": dict(file="indian-man-with-blue-clothes.glb", h=1.70, sex="m", tris=30000),
    "man_kurta_red": dict(file="indian-man-with-red-clothes.glb", h=1.68, sex="m", tris=30000),
    "man_suit": dict(file="indian-man-with-suit.glb", h=1.74, sex="m", tris=27000),
    "man_office": dict(file="eric_rigged_001_-_rigged_3d_business_man.glb", h=1.75, sex="m", tris=22000),
    "man_old_coat": dict(file="old_man_in_coat_-_human_riged_model.glb", h=1.64, sex="m", tris=22000),
}
# where the face is, read off its --faceshot picture (mm from the picture's top left, which is at `at` (x, z) in the
# world: the model standing at the origin facing -Y): her left eye's middle (on the picture's right) and her right's,
# the eyes' half width and height; the mouth's middle and half width. brows: False where a hat's brim sits on them.
FACE = {
    "woman_saree_yellow": dict(at=(-0.054, 1.602), left=(144, 147), right=(85, 147), ew=14, eh=6, mouth=(113, 205), mw=23),
    "woman_saree_pink": dict(at=(-0.110, 1.565), left=(177, 124), right=(118, 133), ew=14, eh=6, mouth=(157, 188), mw=24),
    "woman_saree_green": dict(at=(-0.074, 1.610), left=(138, 144), right=(82, 144), ew=14, eh=6, mouth=(110, 200), mw=21),
    "woman_office": dict(at=(-0.110, 1.639), left=(137, 146), right=(85, 146), ew=13, eh=5, mouth=(110, 204), mw=21),
    "woman_office2": dict(at=(-0.098, 1.586), left=(140, 113), right=(80, 113), ew=13, eh=5, mouth=(110, 173), mw=23),
    "man_kurta_blue": dict(at=(-0.110, 1.684), left=(140, 105), right=(80, 105), ew=13, eh=6, mouth=(110, 173), mw=21),
    "man_kurta_red": dict(at=(-0.110, 1.670), left=(140, 115), right=(82, 115), ew=14, eh=6, mouth=(110, 188), mw=22),
    "man_suit": dict(at=(-0.110, 1.720), left=(143, 124), right=(76, 123), ew=15, eh=6, mouth=(110, 187), mw=25),
    "man_office": dict(at=(-0.110, 1.744), left=(122, 118), right=(65, 120), ew=13, eh=5, mouth=(95, 183), mw=24),
    "man_old_coat": dict(at=(-0.112, 1.600), left=(144, 100), right=(83, 100), ew=15, eh=5, mouth=(113, 168), mw=25, brows=False),
}

# the game's bones, by the names other rigs give them (lower case, Mixamo's prefix and Sketchfab's _NN taken off)
CORE = {"hips": "pelvis", "hip": "pelvis", "spine": "spine_01", "spine1": "spine_02", "spine2": "spine_03",
        "spine_01": "spine_01", "spine_02": "spine_02", "spine_03": "spine_03", "neck": "neck_01", "head": "head"}
RENAME = dict(CORE)
for S, s in (("left", "l"), ("right", "r")):
    for theirs, ours in (("shoulder", "clavicle"), ("arm", "upperarm"), ("forearm", "lowerarm"), ("hand", "hand"),
                         ("upleg", "thigh"), ("leg", "calf"), ("foot", "foot"), ("toebase", "ball")):
        RENAME[S + theirs] = ours + "_" + s
    for theirs, ours in (("shoulder", "clavicle"), ("upperarm", "upperarm"), ("lowerarm", "lowerarm"), ("hand", "hand"),
                         ("upperleg", "thigh"), ("lowerleg", "calf"), ("foot", "foot"), ("ball", "ball")):
        RENAME[theirs + "_" + s] = ours + "_" + s                       # (Renderpeople)
    for f in ("thumb", "index", "middle", "ring", "pinky"):
        for j in (1, 2, 3):
            RENAME["%shand%s%d" % (S, f, j)] = RENAME["%s_0%d_%s" % (f, j, s)] = "%s_0%d_%s" % (f, j, s)
RENAME.update({n: n for n in ("jaw", "eyelid_l", "eyelid_r", "eyebrow_l", "eyebrow_r")})   # (a face's bones: Renderpeople)
# the template faces (rebuild_face): the file, and where its eyes and mouth are on its --templateshot picture (as FACE)
TEMPLATE = {"w": dict(file=os.path.join(OUT, "story_divya.glb"), at=(-0.110, 1.544), left=(137, 166), right=(83, 166), mouth=(110, 222)),
            "m": dict(file=os.path.join(OUT, "story_suresh.glb"), at=(-0.110, 1.850), left=(142, 164), right=(80, 164), mouth=(110, 236))}
CHILD = {}                                                 # a bone → its next joint's (where it points)
for s_ in ("l", "r"):
    CHILD.update({"clavicle_" + s_: "upperarm_" + s_, "upperarm_" + s_: "lowerarm_" + s_, "lowerarm_" + s_: "hand_" + s_,
                  "hand_" + s_: "middle_01_" + s_, "thigh_" + s_: "calf_" + s_, "calf_" + s_: "foot_" + s_, "foot_" + s_: "ball_" + s_})
    for f_ in ("thumb", "index", "middle", "ring", "pinky"):
        CHILD["%s_01_%s" % (f_, s_)] = "%s_02_%s" % (f_, s_)
        CHILD["%s_02_%s" % (f_, s_)] = "%s_03_%s" % (f_, s_)
TURN = {"pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head"}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _PIX.clear()


def load(path, merge=False):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path, merge_vertices=merge)
    return [o for o in bpy.data.objects if o not in before]


def world_mat(arm, name):
    return arm.matrix_world @ arm.pose.bones[name].matrix


def curves(act):
    """An action's curves (Blender 5's actions are layered: layers, strips, channel bags)."""
    if hasattr(act, "fcurves"):
        return list(act.fcurves)
    return [fc for ly in act.layers for st in ly.strips for cb in st.channelbags for fc in cb.fcurves]


def use(ob, act):
    ob.animation_data.action = act
    if act is not None and hasattr(ob.animation_data, "action_slot") and act.slots:
        ob.animation_data.action_slot = act.slots[0]


def rest_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
        pb.scale = Vector((1, 1, 1))


def mesh_points(meshes):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for m in meshes:
        ev = m.evaluated_get(dg)
        me = ev.to_mesh()
        pts += [m.matrix_world @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    return pts


def own_rest(objs, frame):
    """A model whose skeleton's rest is no pose at all (its parts collapse; it's only right in its own clip): a frame
    of its own clip made its rest. The meshes take that shape (their Armature applied, the weights kept), the
    skeleton that pose as its rest, the Armature put back."""
    arm = next(o for o in objs if o.type == 'ARMATURE')
    act = arm.animation_data.action if arm.animation_data and arm.animation_data.action else \
        (bpy.data.actions[0] if bpy.data.actions else None)
    if act is None:
        return
    use(arm, act)
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    for m in [o for o in objs if o.type == 'MESH']:
        mods = [md for md in m.modifiers if md.type == 'ARMATURE']
        if not mods:
            continue
        bpy.context.view_layer.objects.active = m
        if m.data.shape_keys:
            m.shape_key_clear()
        name = mods[0].name
        bpy.ops.object.modifier_copy(modifier=name)
        bpy.ops.object.modifier_apply(modifier=name)
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.animation_data.action = None
    print("REST from its own clip's frame", frame, flush=True)


def flatten(objs):
    """Everything out of the importer's nodes (Sketchfab's Y-up turn, an FBX's centimetres) and those applied: the
    skeleton's space is the world's, in metres (the game's head turns reckon in the skeleton's space)."""
    keep = [o for o in objs if o.type in ('ARMATURE', 'MESH')]
    for o in keep:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in objs:
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in keep:
        o.select_set(True)
    bpy.context.view_layer.objects.active = keep[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return keep


def rename_bones(arm, meshes):
    """Its bones given ours' names (the vertex groups with them)."""
    names = [b.name for b in arm.data.bones]
    suffixed = sum(1 for n in names if re.search(r"_\d+$", n)) > len(names) * 0.6
    taken = set()
    for n in names:
        k = n.split(":")[-1]
        if suffixed:
            k = re.sub(r"_\d+$", "", k)
        new = RENAME.get(k.lower())
        if new is None or new in taken:
            continue
        taken.add(new)
        arm.data.bones[n].name = new
        for m in meshes:
            g = m.vertex_groups.get(n)
            if g is not None:
                g.name = new
    return taken


def auto_rig(meshes, h, chin=None):
    """A skeleton put into a model that has none, standing in a T at the origin facing -Y, from where a body's
    joints are (its height's fractions; the arms along the line the mesh's arms take), and skinned by nearness."""
    pts = mesh_points(meshes)
    arms = [p for p in pts if abs(p.x) > 0.28 * h]
    arm_z = sum(p.z for p in arms) / max(len(arms), 1) if arms else 0.81 * h
    reach = max(abs(p.x) for p in pts)
    mid_y = sorted(p.y for p in pts if 0.45 * h < p.z < 0.6 * h)
    yc = mid_y[len(mid_y) // 2] if mid_y else 0.0
    hp = [p for p in pts if 0.9 * h < p.z < 0.98 * h]
    hx = sum(p.x for p in hp) / max(len(hp), 1)            # (the head over its own middle: she may lean)
    hy = sum(p.y for p in hp) / max(len(hp), 1)
    ad = bpy.data.armatures.new("rig")
    arm = bpy.data.objects.new("rig", ad)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    eb = ad.edit_bones

    def bone(name, a, b, parent=None, connect=False):
        e = eb.new(name)
        e.head, e.tail = Vector(a), Vector(b)
        if parent:
            e.parent = eb[parent]
            e.use_connect = connect
        return e
    Z = lambda f: f * h
    bone("pelvis", (0, yc, Z(0.53)), (0, yc, Z(0.585)))
    bone("spine_01", (0, yc, Z(0.585)), (0, yc, Z(0.655)), "pelvis", True)
    bone("spine_02", (0, yc, Z(0.655)), (0, yc, Z(0.725)), "spine_01", True)
    bone("spine_03", (0, yc, Z(0.725)), (0, yc, arm_z - Z(0.01)), "spine_02", True)
    cz_ = chin if chin is not None else Z(0.85)              # (the head from the chin up: all the face one bone's)
    bone("neck_01", (0, yc, arm_z - Z(0.01)), (hx, hy, cz_), "spine_03", True)
    bone("head", (hx, hy, cz_), (hx, hy, Z(1.0)), "neck_01", True)
    sh = 0.1 * h
    span = reach - sh
    for s, sx in (("l", 1.0), ("r", -1.0)):
        bone("clavicle_" + s, (sx * 0.015 * h, yc, arm_z - 0.012 * h), (sx * sh, yc, arm_z), "spine_03")
        e1 = sx * (sh + span * 0.42)
        e2 = sx * (sh + span * 0.75)
        bone("upperarm_" + s, (sx * sh, yc, arm_z), (e1, yc, arm_z), "clavicle_" + s, True)
        bone("lowerarm_" + s, (e1, yc, arm_z), (e2, yc, arm_z), "upperarm_" + s, True)
        bone("hand_" + s, (e2, yc, arm_z), (sx * reach, yc, arm_z), "lowerarm_" + s, True)
        bone("thigh_" + s, (sx * 0.055 * h, yc, Z(0.5)), (sx * 0.06 * h, yc, Z(0.285)), "pelvis")
        bone("calf_" + s, (sx * 0.06 * h, yc, Z(0.285)), (sx * 0.062 * h, yc + 0.01, Z(0.048)), "thigh_" + s, True)
        bone("foot_" + s, (sx * 0.062 * h, yc + 0.01, Z(0.048)), (sx * 0.065 * h, yc - 0.075 * h, Z(0.012)), "calf_" + s, True)
        bone("ball_" + s, (sx * 0.065 * h, yc - 0.075 * h, Z(0.012)), (sx * 0.066 * h, yc - 0.11 * h, Z(0.012)), "foot_" + s, True)
    for e in eb:                                           # (rolls as Blender's own: the clips point bones, not roll them)
        e.roll = 0.0
    bpy.ops.object.mode_set(mode='OBJECT')
    # skinned by nearness: each point to the bones nearest it (their segments), the nearer the more (1/d^3), the three
    # nearest at most. (Blender's bone heat fails on a scan: its surface isn't closed.) In a T the arms, the legs
    # and the body are well apart; the saree's legs are eased onto the hips after (skirt_weights).
    segs = [(b.name, Vector(b.head_local), Vector(b.tail_local)) for b in ad.bones]
    A = np.array([s_[1] for s_ in segs])
    B = np.array([s_[2] for s_ in segs])
    cos, ws = [], []
    for m in meshes:
        co = np.array([m.matrix_world @ v.co for v in m.data.vertices])
        ab = B - A
        t = np.clip(np.einsum("nbk,bk->nb", co[:, None, :] - A[None], ab) / np.maximum((ab * ab).sum(1), 1e-9), 0, 1)
        near = A[None] + t[..., None] * ab[None]
        d = np.linalg.norm(co[:, None, :] - near, axis=2)
        for bi, (n, _, _) in enumerate(segs):                # (a point well on the right isn't the left arm's or leg's)
            if n.endswith("_l"):
                d[co[:, 0] < -0.03 * h, bi] += 1.0
            elif n.endswith("_r"):
                d[co[:, 0] > 0.03 * h, bi] += 1.0
        w = 1.0 / (d + 0.02) ** 3
        order = np.argsort(d, axis=1)[:, 3:]
        np.put_along_axis(w, order, 0.0, axis=1)
        w /= w.sum(1, keepdims=True)
        cos.append(co)
        ws.append(w)
    # smoothed over 4 cm, all the meshes together: a scan is layers (the body under the cloth, a cm apart) that must
    # move as one, or the one shows through the other
    allc = np.concatenate(cos)
    allw = np.concatenate(ws)
    kd = KDTree(len(allc))
    for i, c in enumerate(allc):
        kd.insert(Vector(c), i)
    kd.balance()
    sm = np.empty_like(allw)
    for i, c in enumerate(allc):
        idx = [j for _, j, _ in kd.find_range(Vector(c), 0.04)]
        sm[i] = allw[idx].mean(0)
    if chin is not None:                                    # the face the head's alone (a share of it the neck's, the
        hi_ = [n for n, _, _ in segs].index("head")         #  face shears as the head turns), from 3 cm under the chin
        k = np.clip((allc[:, 2] - (chin - 0.03)) / 0.03, 0, 1)[:, None]
        one = np.zeros_like(sm)
        one[:, hi_] = 1.0
        sm = sm * (1 - k) + one * k
    start = 0
    for m, co in zip(meshes, cos):
        w = sm[start:start + len(co)]
        start += len(co)
        groups = {n: m.vertex_groups.get(n) or m.vertex_groups.new(name=n) for n, _, _ in segs}
        for bi, (n, _, _) in enumerate(segs):
            g = groups[n]
            for vi in np.nonzero(w[:, bi] > 0.02)[0]:
                g.add([int(vi)], float(w[vi, bi]), 'REPLACE')
        am = m.modifiers.new("Armature", 'ARMATURE')
        am.object = arm
        m.parent = arm
    print("RIG by nearness:", len(segs), "bones", flush=True)
    return arm


def skirt_weights(m, knee_z, hip_z):
    """The saree from the hips: the legs' share of the cloth eased onto the pelvis, and from the knee down the left
    and right legs' weights shared out evenly (the hem moves with both feet's middle, not torn between them)."""
    gi = {g.name: g.index for g in m.vertex_groups}
    pel = m.vertex_groups.get("pelvis")
    if pel is None:
        return
    give = {"thigh": 0.6, "calf": 0.8, "foot": 0.65, "ball": 0.65}
    pairs = [(gi.get(k + "_l"), gi.get(k + "_r"), f) for k, f in give.items()]
    mw = m.matrix_world
    for v in m.data.vertices:
        z = (mw @ v.co).z
        ws = {g.group: g.weight for g in v.groups}
        share = min(1.0, max(0.0, (hip_z - z) / max(hip_z - knee_z, 0.01)))      # 0 at the hips, 1 at the knee and below
        moved = 0.0
        for gl, gr, f in pairs:
            if gl is None or gr is None:
                continue
            wl, wr = ws.get(gl, 0.0), ws.get(gr, 0.0)
            if wl + wr <= 0.0:
                continue
            avg = (wl + wr) / 2.0
            wl, wr = wl + (avg - wl) * share, wr + (avg - wr) * share
            moved += (wl + wr) * f
            wl, wr = wl * (1 - f), wr * (1 - f)
            for gid, w in ((gl, wl), (gr, wr)):
                if w > 0.0:
                    m.vertex_groups[gid].add([v.index], w, 'REPLACE')
                elif gid in ws:
                    m.vertex_groups[gid].remove([v.index])
        if moved > 0.0:
            pel.add([v.index], ws.get(pel.index, 0.0) + moved, 'REPLACE')


def thin(meshes, budget, chin_z, head=None):
    """Thinned to its budget, the face kept whole: above the chin and in front of the head's middle (thinned, a face's
    texture slides over the eyes and the mouth), softly from 4 cm under it; the hair behind thinned as the rest (it can
    be most of a model's triangles: kept, the body would be thinned to blocks)."""
    tris = sum(len(p.vertices) - 2 for m in meshes for p in m.data.polygons)
    for m in meshes:
        th = m.vertex_groups.new(name="Thin")
        mw = m.matrix_world
        # a part (a material) that's a small share of the whole kept as it is (a body of 5k under 45k of hair:
        # thinned with it, its arms go to blades); the big ones (the hair, the cloth) take the thinning
        per = {}
        for poly in m.data.polygons:
            per[poly.material_index] = per.get(poly.material_index, 0) + len(poly.vertices) - 2
        small = {mi for mi, n in per.items() if n < 0.08 * tris} if len(per) > 2 else set()
        keep_v = set()
        for poly in m.data.polygons:
            if poly.material_index in small:
                keep_v.update(poly.vertices)
        for v in m.data.vertices:
            p = mw @ v.co
            if v.index in keep_v:
                th.add([v.index], 0.0, 'REPLACE')
                continue
            w = min(1.0, max(0.0, (chin_z - p.z) / 0.04))
            if head is not None:                            # (behind the head's middle, or out past its sides: thinned)
                w = max(w, min(1.0, max(0.0, (p.y - head.y) / 0.02)), min(1.0, max(0.0, (abs(p.x - head.x) - 0.085) / 0.02)))
            th.add([v.index], w, 'REPLACE')
        if tris > budget:
            d = m.modifiers.new("Thin", 'DECIMATE')
            d.ratio = budget / tris
            if small:
                kept = sum(per[mi] for mi in small)
                d.ratio = max(0.05, (budget - kept) / max(tris - kept, 1)) * (tris - kept) / tris + kept / tris
            d.vertex_group = "Thin"
            d.vertex_group_factor = 1000.0
            bpy.context.view_layer.objects.active = m
            bpy.ops.object.modifier_move_to_index(modifier=d.name, index=0)
            bpy.ops.object.modifier_apply(modifier=d.name)
        m.vertex_groups.remove(m.vertex_groups["Thin"])
    return tris, sum(len(p.vertices) - 2 for m in meshes for p in m.data.polygons)


def retarget(arm, sex):
    """Our clips onto her: baked a frame at a time (her clip only made after: an action of hers playing would put
    each pose back), each its action of the clip's name."""
    objs = []
    for p in REF[sex]:
        objs += load(p)
    ours = [o for o in objs if o.type == 'ARMATURE']
    for o in objs:
        if o.type == 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    actions = [a for a in bpy.data.actions if a.users and curves(a)]
    for a in actions:
        a.name = "src_" + a.name
    src = ours[0]
    if src.animation_data:
        for tr in src.animation_data.nla_tracks:
            tr.mute = True
    pairs = [n for n in (b.name for b in src.data.bones) if n in arm.pose.bones]
    order = sorted(pairs, key=lambda n: len(arm.data.bones[n].parent_recursive))
    rest_pose(src)
    rest_pose(arm)
    src.animation_data_create()
    src.animation_data.action = None
    arm.animation_data_create()
    arm.animation_data.action = None
    bpy.context.view_layer.update()
    rest_ours = {n: world_mat(src, n) for n in pairs}
    rest_hers = {n: world_mat(arm, n) for n in pairs}
    s = (arm.matrix_world @ arm.pose.bones["head"].head).z / (src.matrix_world @ src.pose.bones["head"].head).z
    made = []
    for act in actions:
        name = act.name[4:].split("|")[-1].split(".")[0]
        if name in [n for n, _, _ in made]:
            continue
        use(src, act)
        f0, f1 = (int(x) for x in act.frame_range)
        baked = []
        for f in range(f0, f1 + 1):
            bpy.context.scene.frame_set(f)
            rest_pose(arm)
            bpy.context.view_layer.update()
            for n in order:
                now = world_mat(src, n)
                pb = arm.pose.bones[n]
                cur = world_mat(arm, n)
                if n in TURN:                               # the same turn from rest as ours
                    want = (now.to_quaternion() @ rest_ours[n].to_quaternion().inverted()) @ rest_hers[n].to_quaternion()
                else:                                       # pointing the way ours points: at its next joint (a
                    c = CHILD.get(n)                        #  rig's bones needn't lie along their own axis)
                    if c and c in arm.pose.bones and c in src.pose.bones:
                        d_ours = ((src.matrix_world @ src.pose.bones[c].head) - (src.matrix_world @ src.pose.bones[n].head)).normalized()
                        d_cur = ((arm.matrix_world @ arm.pose.bones[c].head) - (arm.matrix_world @ arm.pose.bones[n].head)).normalized()
                    else:
                        d_ours = (now.to_3x3() @ Vector((0, 1, 0))).normalized()
                        d_cur = (cur.to_3x3() @ Vector((0, 1, 0))).normalized()
                    want = d_cur.rotation_difference(d_ours) @ cur.to_quaternion()
                m = Matrix.Translation(cur.translation) @ want.to_matrix().to_4x4()
                if n == "pelvis":                           # the hips move as ours do (to her scale)
                    m.translation = rest_hers[n].translation + (now.translation - rest_ours[n].translation) * s
                pb.matrix = arm.matrix_world.inverted() @ m
                bpy.context.view_layer.update()
            baked.append({n: (arm.pose.bones[n].rotation_quaternion.copy(), arm.pose.bones[n].location.copy()) for n in pairs})
        new = bpy.data.actions.new(name)
        arm.animation_data.action = new
        for i, pose in enumerate(baked):
            for n, (q, l) in pose.items():
                pb = arm.pose.bones[n]
                pb.rotation_quaternion = q
                pb.location = l
                pb.keyframe_insert("rotation_quaternion", frame=f0 + i)
                pb.keyframe_insert("location", frame=f0 + i)
        arm.animation_data.action = None
        made.append((name, f0, new))
    for name, f0, new in made:                              # (as tracks only now: a track plays while the next is posed)
        tr = arm.animation_data.nla_tracks.new()
        tr.name = name
        st = tr.strips.new(name, f0, new)
        if hasattr(st, "action_slot") and new.slots:
            st.action_slot = new.slots[0]
    for o in ours:
        bpy.data.objects.remove(o, do_unlink=True)
    keep = {n for n, _, _ in made}
    for a in list(bpy.data.actions):
        if a.name not in keep:
            bpy.data.actions.remove(a)
    rest_pose(arm)
    print("LIVE clips", len(made), flush=True)
    return sorted(keep)


# ---- the face ----------------------------------------------------------------------------------------------------

def _texture(m):
    for mat in m.data.materials:
        if mat and mat.use_nodes:
            for n in mat.node_tree.nodes:
                if n.type == 'TEX_IMAGE' and n.image is not None:
                    return n.image
    return None


def faceshot(name, arm, meshes, out):
    """The face from the front: each triangle near it filled with its texture (1 px a mm), a grey line each cm, a
    darker each 5 cm. Its top left corner's place is printed (x, z)."""
    hd = arm.matrix_world @ arm.pose.bones["head"].head
    x0, z1 = hd.x - 0.11, hd.z + 0.2
    W, H = 220, 290
    img = np.ones((H, W, 3)) * 0.6
    zb = np.full((H, W), 9.0)
    for m in meshes:
        tex = _texture(m)
        if tex is None:
            continue
        tw, th = tex.size
        px = np.array(tex.pixels[:]).reshape(th, tw, 4)
        me = m.data
        uv = me.uv_layers.active.data
        mw = m.matrix_world
        co = [mw @ v.co for v in me.vertices]
        me.calc_loop_triangles()
        for t in me.loop_triangles:
            ps = [co[i] for i in t.vertices]
            if min(p.y for p in ps) > hd.y + 0.02 or not all(x0 - 0.01 < p.x < x0 + W / 1000 + 0.01 and z1 - H / 1000 - 0.01 < p.z < z1 + 0.01 for p in ps):
                continue
            us = [uv[li].uv for li in t.loops]
            xs = [(p.x - x0) * 1000 for p in ps]
            ys = [(z1 - p.z) * 1000 for p in ps]
            for yy in range(max(0, int(min(ys))), min(H, int(max(ys)) + 2)):
                for xx in range(max(0, int(min(xs))), min(W, int(max(xs)) + 2)):
                    d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
                    if abs(d) < 1e-9:
                        continue
                    a = ((ys[1] - ys[2]) * (xx - xs[2]) + (xs[2] - xs[1]) * (yy - ys[2])) / d
                    b = ((ys[2] - ys[0]) * (xx - xs[2]) + (xs[0] - xs[2]) * (yy - ys[2])) / d
                    c = 1 - a - b
                    if a < -0.01 or b < -0.01 or c < -0.01:
                        continue
                    y = a * ps[0].y + b * ps[1].y + c * ps[2].y
                    if y >= zb[yy, xx]:
                        continue
                    zb[yy, xx] = y
                    u = a * us[0].x + b * us[1].x + c * us[2].x
                    v = a * us[0].y + b * us[1].y + c * us[2].y
                    img[yy, xx] = px[int(min(th - 1, max(0, v * th))) % th, int(min(tw - 1, max(0, u * tw))) % tw, :3]
    for i in range(0, W, 10):
        img[:, i] = img[:, i] * 0.5 + (0.0 if (i % 50 == 0) else 0.3)
    for j in range(0, H, 10):
        img[j, :] = img[j, :] * 0.5 + (0.0 if (j % 50 == 0) else 0.3)
    os.makedirs(out, exist_ok=True)
    im = bpy.data.images.new("face_" + name, W, H)
    im.pixels = np.concatenate([img[::-1], np.ones((H, W, 1))], axis=2).ravel()
    im.filepath_raw = os.path.join(out, "face_%s.png" % name)
    im.file_format = 'PNG'
    im.save()
    print("FACESHOT %s corner x %.3f z %.3f head %.3f %.3f %.3f" % (name, x0, z1, hd.x, hd.y, hd.z), flush=True)


def _keys(m):
    if m.data.shape_keys is None:
        m.shape_key_add(name="Basis", from_mix=False)
    return m.data.shape_keys.key_blocks


def _surface(meshes):
    """A tree to find the nearest skin by (world), with which mesh and face."""
    trees = []
    for m in meshes:
        bm = bmesh.new()
        bm.from_mesh(m.data)
        bm.transform(m.matrix_world)
        bm.faces.ensure_lookup_table()
        trees.append((m, BVHTree.FromBMesh(bm), bm))
    return trees


def _front(trees, x, z, y_from=-2.0):
    """The skin's y where a line from in front (along +y) at (x, z) first meets it."""
    best = None
    for m, t, bm in trees:
        hit = t.ray_cast(Vector((x, y_from, z)), Vector((0, 1, 0)))
        if hit[0] is not None and (best is None or hit[0].y < best):
            best = hit[0].y
    return best


def _uv_at(m, bm, tree, p):
    """The texture's place on the skin nearest p."""
    loc, nrm, fi, dist = tree.find_nearest(p)
    f = bm.faces[fi]
    lay = bm.loops.layers.uv.active
    vs = [l.vert.co for l in f.loops]
    uvs = [l[lay].uv for l in f.loops]
    for i in range(1, len(vs) - 1):                        # (the face's fan: the triangle it's in)
        tri = (vs[0], vs[i], vs[i + 1])
        tu = (uvs[0].to_3d(), uvs[i].to_3d(), uvs[i + 1].to_3d())
        r = barycentric_transform(loc, *tri, *tu)
        if i == len(vs) - 2 or (r.x >= -0.01 and r.y >= -0.01):
            return Vector((r.x, r.y))
    return uvs[0].copy()


def face_shapes(name, arm, meshes):
    """Blend shapes of our faces' names on whichever meshes have the skin there. A rig with eyelid and jaw bones
    (Renderpeople: its eyes are balls in sockets, no skin over them to copy) has its blinks and its mouth from those."""
    f = FACE.get(name)
    if f is None:
        print("FACE none for", name, flush=True)
        return
    bones = False                                           # (a rig's own eyelid bones close nothing seen: the lid
                                                            #  sheet over its eyeballs instead, as on the others)
    if bones:
        face_bones(arm, meshes)
    trees = _surface(meshes)
    w = lambda p: (f["at"][0] + p[0] / 1000.0, f["at"][1] - p[1] / 1000.0)
    ew, eh = f["ew"] / 1000.0, f["eh"] / 1000.0
    mx, mz = w(f["mouth"])
    mw_ = f["mw"] / 1000.0

    def move(key, centre, rx, rz, delta, below=None):
        """The skin round centre (an ellipse rx by rz, softly) moved by delta (world); below: only under that z."""
        cx, cz = centre
        cy = _front(trees, cx, cz)
        if cy is None:
            return
        for m in meshes:
            kb = _keys(m)
            k = kb.get(key) or m.shape_key_add(name=key, from_mix=False)
            inv = m.matrix_world.inverted().to_3x3()
            mwm = m.matrix_world
            for i, v in enumerate(m.data.vertices):
                p = mwm @ v.co
                if p.y > cy + 0.03:
                    continue
                d = ((p.x - cx) / rx) ** 2 + ((p.z - cz) / rz) ** 2
                if d >= 1.0:
                    continue
                wt = (1.0 - d) ** 2
                if below is not None:
                    wt *= min(1.0, max(0.0, (below - p.z) / 0.004))
                if wt > 0.0:
                    k.data[i].co = k.data[i].co + inv @ (Vector(delta) * wt)
    for side, sx in (("left", 1.0), ("right", -1.0)):
        cx, cz = w(f[side])
        if not bones:
            lid(meshes, trees, "eye-%s-closure" % side, "eye-%s-slit" % side, cx, cz, ew, eh)
        if f.get("brows", True):
            bz = cz + eh + 0.008
            move("eyebrows-%s-up" % side, (cx, bz), ew * 1.4, 0.012, (0, 0, 0.0035))
            move("eyebrows-%s-down" % side, (cx, bz), ew * 1.4, 0.012, (0, 0.0005, -0.0025))
            move("eyebrows-%s-inner-up" % side, (cx - sx * ew * 0.6, bz), ew * 0.9, 0.011, (0, 0, 0.003))
            move("eye-%s-opened-up" % side, (cx, cz + eh + 0.004), ew * 1.3, 0.009, (0, 0, 0.0015))
        move("mouth-corner-puller", (mx + sx * mw_, mz), 0.02, 0.016, (sx * 0.0028, 0.0015, 0.0036))
        move("mouth-corner-puller", (mx + sx * (mw_ + 0.012), mz + 0.014), 0.02, 0.014, (0, -0.0006, 0.0015))   # (the cheek)
        move("mouth-depression", (mx + sx * mw_, mz), 0.016, 0.013, (0, 0, -0.0022))
    if not bones:
        jaw(meshes, trees, "mouth-open", mx, mz, mw_)
    move("mouth-compression", (mx, mz), mw_ * 1.2, 0.01, (0, -0.0006, 0))
    print("FACE shapes on", name, "(lids and jaw from its bones)" if bones else "", flush=True)


def jaw(meshes, trees, key, mx, mz, mw_):
    """The mouth open: the face below the lips turned down about the jaw's hinge (behind and a little above the mouth),
    9 degrees at 1; the lower lip goes, the upper stays; it fades out over the cheeks and down the neck."""
    front = _front(trees, mx, mz)
    if front is None:
        return
    pivot = Vector((mx, front + 0.085, mz + 0.012))
    rot = Matrix.Rotation(math.radians(9.0), 3, 'X')       # (+x turns the chin down and back for one facing -y)
    for m in meshes:
        kb = _keys(m)
        k = kb.get(key) or m.shape_key_add(name=key, from_mix=False)
        inv = m.matrix_world.inverted().to_3x3()
        mwm = m.matrix_world
        for i, v in enumerate(m.data.vertices):
            p = mwm @ v.co
            if p.y > front + 0.075 or p.z > mz + 0.002:
                continue
            ax = abs(p.x - mx)
            wt = min(1.0, max(0.0, (mz + 0.002 - p.z) / 0.004))                  # (from the lips' line down)
            wt *= min(1.0, max(0.0, (mw_ + 0.03 - ax) / 0.022))                  # (not the cheeks)
            wt *= min(1.0, max(0.0, (p.z - (mz - 0.085)) / 0.03))                 # (nor the neck)
            if wt <= 0.0:
                continue
            q = pivot + rot @ (p - pivot)
            k.data[i].co = k.data[i].co + inv @ ((q - p) * wt)


def _hit(trees, x, z):
    """Where a line from in front (along +y) at (x, z) first meets the skin: (point, normal, mesh, face index)."""
    best = None
    for m, t, bm in trees:
        loc, nrm, fi, dist = t.ray_cast(Vector((x, -2.0, z)), Vector((0, 1, 0)))
        if loc is not None and (best is None or loc.y < best[0].y):
            best = (loc, nrm, m, fi)
    return best


_PIX = {}


def _mat_texture(mat):
    if mat and mat.node_tree:
        for n in mat.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image is not None:
                return n.image
    return None


def _lid_colours(m, mat, skin_uvs, lash_uvs):
    """The lid's colour (the cheek's skin under the eye, a shade darker: a lid in its own shadow) and its edge's (the
    lashes' line, darker), from the texture of the face's own material: a blink is a fifth of a second, a plain colour
    is enough, and the texture stretched that far shows its blocks."""
    tex = _mat_texture(m.data.materials[mat]) if mat < len(m.data.materials) else None
    if tex is None:
        return (0.3, 0.17, 0.12), (0.06, 0.03, 0.02)
    if tex.name not in _PIX:
        w0, h0 = int(tex.size[0]), int(tex.size[1])
        _PIX[tex.name] = (np.array(tex.pixels[:]).reshape(h0, w0, 4), (w0, h0))
    px, (w, h) = _PIX[tex.name]
    at = lambda uv: px[int(min(h - 1, max(0, uv.y * h))), int(min(w - 1, max(0, uv.x * w))), :3]
    lin = lambda c: np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)   # (the texture's sRGB; a colour linear)
    skin = lin(np.median([at(uv) for uv in skin_uvs], axis=0) * 0.9)
    lash = lin(np.mean([at(uv) for uv in lash_uvs], axis=0) * 0.6)
    return tuple(float(c) for c in skin), tuple(float(c) for c in lash)


def lid(meshes, trees, key, slit_key, cx, cz, ew, eh):
    """A blink's lid: a small sheet of skin laid over the eye (an almond, 13 by 7 points, each on the skin in front of
    it), its colour the lid's own skin's just above the eye, its edge the lashes' line's (_lid_colours). Closed (the blend shape) it lies over the eye; open it's
    folded up into its top edge, tucked under the skin there (unseen). Put in the mesh whose skin it takes."""
    rx, rz = ew * 1.3, eh * 1.7
    NU, NV = 13, 7
    top = lambda x: cz + rz * math.sqrt(max(0.0, 1.0 - ((x - cx) / rx) ** 2))
    src = _hit(trees, cx, cz + rz + 0.004)
    if src is None:
        print("LID no skin above", key, flush=True)
        return
    m = src[2]
    tree, sbm = next((t, b) for mm, t, b in trees if mm == m)
    mat = sbm.faces[src[3]].material_index
    head = m.vertex_groups.get("head")
    pts = []                                               # [u][v]: (closed, opened, uv) in the world
    for i in range(NU):
        u = -1.0 + 2.0 * i / (NU - 1)
        x = cx + u * rx * 0.999
        col = []
        for j in range(NV):
            v = 1.0 - 2.0 * j / (NV - 1) if j != NV - 2 else -0.84   # (the top row first; the last but one near
                                                               #  the edge: the lashes' line a thin one)
            z = cz + v * rz * math.sqrt(max(0.0, 1.0 - u * u))
            h = _hit(trees, x, z)
            if h is None:
                return
            n = h[1] if h[1].y < 0 else Vector((0, -1, 0))
            closed = h[0] + n.normalized() * 0.0009
            ht = _hit(trees, x, top(x))
            opened = (ht[0] if ht else h[0]) - (ht[1] if ht else n).normalized() * 0.0012
            sx_, sz = cx + u * rx * 0.35, top(cx) + 0.0025 + (1.0 - (v + 1.0) / 2.0) * 0.0015   # (the lid's skin: one
            if j == NV - 1:                                                                # smooth patch above the eye)
                sx_, sz = x, top(x) - 0.0006                 # (its edge: the lashes' dark line)
            sh = _hit(trees, sx_, sz)
            uv = _uv_at(m, sbm, tree, sh[0] if sh else h[0])
            col.append((closed, opened, uv))
        pts.append(col)
    inv = m.matrix_world.inverted()
    cheek = []                                             # (the skin under the eye: the lid's colour)
    for i in range(NU):
        hc = _hit(trees, cx + (-1.0 + 2.0 * i / (NU - 1)) * rx * 0.6, cz - rz - 0.007)
        if hc is not None and hc[2] == m:
            cheek.append(_uv_at(m, sbm, tree, hc[0]))
    skin, lash = _lid_colours(m, mat, cheek or [pts[i][0][2] for i in range(NU)], [pts[i][NV - 1][2] for i in range(NU)])
    mats = []
    for nm, col in (("lid skin", skin), ("lid lash", lash)):
        mt = bpy.data.materials.get(nm + " " + m.name) or bpy.data.materials.new(nm + " " + m.name)
        mt.diffuse_color = (*col, 1.0)
        mt.use_nodes = True
        bsdf = next(n for n in mt.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        bsdf.inputs["Base Color"].default_value = (*col, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.6
        if mt.name not in [x.name for x in m.data.materials if x]:
            m.data.materials.append(mt)
        mats.append([x.name for x in m.data.materials if x].index(mt.name))
    bm = bmesh.new()
    bm.from_mesh(m.data)
    n0 = len(bm.verts)
    dl = bm.verts.layers.deform.verify()
    vs = [[None] * NV for _ in range(NU)]
    for i in range(NU):
        for j in range(NV):
            v = bm.verts.new(inv @ pts[i][j][1])
            if head is not None:
                v[dl][head.index] = 1.0
            vs[i][j] = v
    for i in range(NU - 1):
        for j in range(NV - 1):
            quad = [vs[i][j], vs[i + 1][j], vs[i + 1][j + 1], vs[i][j + 1]]
            try:
                f = bm.faces.new(quad[::-1])               # (facing out, -y)
            except ValueError:
                continue
            f.material_index = mats[1] if j == NV - 2 else mats[0]
            f.smooth = True
    bm.verts.index_update()
    idx = {(i, j): vs[i][j].index for i in range(NU) for j in range(NV)}
    bm.to_mesh(m.data)
    bm.free()
    kb = _keys(m)
    for (i, j), vi in idx.items():
        for k in kb:
            k.data[vi].co = inv @ pts[i][j][1]
    k = kb.get(key) or m.shape_key_add(name=key, from_mix=False)
    s = kb.get(slit_key) or m.shape_key_add(name=slit_key, from_mix=False)
    for (i, j), vi in idx.items():
        c, o = inv @ pts[i][j][0], inv @ pts[i][j][1]
        k.data[vi].co = c
        s.data[vi].co = o.lerp(c, 0.4)
    print("LID %s on %s: %d points (the mesh had %d), skin %s lash %s" % (key, m.name, len(idx), n0,
          tuple(round(c, 2) for c in skin), tuple(round(c, 2) for c in lash)), flush=True)


def face_bones(arm, meshes):
    """A rig with a face's bones (Renderpeople: jaw, eyelid_l/r, eyebrow_l/r): each unit its bone posed, the meshes'
    shape there kept as the blend shape."""
    poses = {"mouth-open": [("jaw", (math.radians(9), 0, 0))],
             "eye-left-closure": [("eyelid_l", (math.radians(28), 0, 0))],
             "eye-right-closure": [("eyelid_r", (math.radians(28), 0, 0))],
             "eye-left-slit": [("eyelid_l", (math.radians(11), 0, 0))],
             "eye-right-slit": [("eyelid_r", (math.radians(11), 0, 0))]}
    for key, bones in poses.items():
        rest_pose(arm)
        for b, e in bones:
            if b in arm.pose.bones:
                pb = arm.pose.bones[b]
                pb.rotation_mode = 'XYZ'
                pb.rotation_euler = e
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        for m in meshes:
            mods = [md for md in m.modifiers if md.type == 'ARMATURE']
            ev = m.evaluated_get(dg).to_mesh()
            dco = [v.co.copy() for v in ev.vertices]
            m.evaluated_get(dg).to_mesh_clear()
            rest_pose(arm)
            bpy.context.view_layer.update()
            dg2 = bpy.context.evaluated_depsgraph_get()
            ev2 = m.evaluated_get(dg2).to_mesh()
            rco = [v.co.copy() for v in ev2.vertices]
            m.evaluated_get(dg2).to_mesh_clear()
            if len(dco) != len(m.data.vertices) or all((a - b).length < 1e-5 for a, b in zip(dco, rco)):
                for b, e in bones:
                    if b in arm.pose.bones:
                        arm.pose.bones[b].rotation_euler = e
                bpy.context.view_layer.update()
                dg = bpy.context.evaluated_depsgraph_get()
                continue
            kb = _keys(m)
            k = kb.get(key) or m.shape_key_add(name=key, from_mix=False)
            for i, v in enumerate(m.data.vertices):
                k.data[i].co = v.co + (dco[i] - rco[i])
            for b, e in bones:                              # (posed again for the next mesh)
                if b in arm.pose.bones:
                    arm.pose.bones[b].rotation_euler = e
            bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
    for b in arm.pose.bones:
        b.rotation_mode = 'QUATERNION'
    rest_pose(arm)
    print("FACE from bones", flush=True)


# ---- colours, the still one, out --------------------------------------------------------------------------------

def tints(name, meshes, spec):
    tex = None
    for m in meshes:
        tex = tex or _texture(m)
    if tex is None:
        return
    w, h = tex.size
    px = np.array(tex.pixels[:]).reshape(-1, 4)
    rgb = px[:, :3]
    mx, mn = rgb.max(1), rgb.min(1)
    d = mx - mn + 1e-6
    hue = np.where(mx == rgb[:, 0], ((rgb[:, 1] - rgb[:, 2]) / d) % 6,
                   np.where(mx == rgb[:, 1], (rgb[:, 2] - rgb[:, 0]) / d + 2, (rgb[:, 0] - rgb[:, 1]) / d + 4)) * 60
    sat = d / (mx + 1e-6)
    cloth = np.zeros(len(px), bool)
    for a, b in spec["hues"]:
        cloth |= (hue >= a) & (hue <= b)
    cloth &= (sat > 0.32) & (mx > 0.18)
    soft = np.clip((sat - 0.32) / 0.1, 0, 1) * cloth
    for i, turn in enumerate(spec["turns"]):
        h2 = (hue + turn) % 360
        c = mx * (1 - sat * (1 - np.abs((h2 / 60) % 2 - 1)))      # (back to rgb at the same value and saturation)
        x_ = mx - mx * sat
        sec = (h2 // 60).astype(int)
        r = np.choose(sec, [mx, c, x_, x_, c, mx])
        g = np.choose(sec, [c, mx, mx, c, x_, x_])
        bl = np.choose(sec, [x_, x_, c, mx, mx, c])
        new = np.stack([r, g, bl], 1)
        out = rgb * (1 - soft[:, None]) + new * soft[:, None]
        im = bpy.data.images.new("t%d" % i, w, h)
        im.pixels = np.concatenate([out, np.ones((len(px), 1))], 1).ravel()
        im.filepath_raw = os.path.join(OUT, "sfa_%s_t%d.jpg" % (name, i))
        im.file_format = 'JPEG'
        bpy.context.scene.render.image_settings.quality = 88
        im.save()
        print("TINT", im.filepath_raw, flush=True)


def far_one(name, arm, meshes, budget=16000):
    """One standing still (Idle's first frame), for the street's crowd far off: sf_<name>.glb as sketchfab_people
    .py makes them (one mesh at the origin, textures 1024 px, no skeleton)."""
    use(arm, bpy.data.actions.get("Idle"))
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    baked = []
    for o in meshes:
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        me.transform(o.matrix_world)
        if me.shape_keys:
            pass
        ob = bpy.data.objects.new(o.name + "_far", me)
        bpy.context.scene.collection.objects.link(ob)
        baked.append(ob)
    arm.animation_data.action = None
    rest_pose(arm)
    bpy.ops.object.select_all(action='DESELECT')
    for o in baked:
        o.select_set(True)
    bpy.context.view_layer.objects.active = baked[0]
    if len(baked) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = "sf_" + name
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > budget:
        md = ob.modifiers.new("thin", 'DECIMATE')
        md.ratio = budget / tris
        bpy.ops.object.modifier_apply(modifier=md.name)
    small = {}
    for m in ob.data.materials:                             # (its own copy of the texture, 1024: the moving one keeps 2048)
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                im = getattr(n, "image", None)
                if im is not None and max(im.size) > 1024:
                    if im.name not in small:
                        c = im.copy()
                        c.scale(*(max(1, v * 1024 // max(im.size)) for v in im.size))
                        small[im.name] = c
                    n.image = small[im.name]
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    path = os.path.join(OUT, "sf_%s.glb" % name)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
                              export_image_format='JPEG', export_animations=False, export_skins=False)
    for m in ob.data.materials:                             # (the moving one's texture back as it was)
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                im = getattr(n, "image", None)
                for orig, c in small.items():
                    if im is c:
                        n.image = bpy.data.images[orig]
    bpy.data.objects.remove(ob, do_unlink=True)
    print("FAR", path, "%.1f MB" % (os.path.getsize(path) / 1e6), flush=True)


def build(name, faceshot_dir=None, budget=None):
    spec = PEOPLE[name]
    reset()
    objs = load(os.path.join(SRC, spec["file"]), merge=True)       # (one vertex at a seam: thinned, the seams don't open)
    for o in list(objs):
        if o.type == 'MESH' and ("icosphere" in (o.name + o.data.name).lower() or not o.data.polygons):
            objs.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)
    if "rest_frame" in spec:
        own_rest(objs, spec["rest_frame"])
    for o in objs:
        if o.animation_data:
            o.animation_data.action = None
            for tr in list(o.animation_data.nla_tracks):
                o.animation_data.nla_tracks.remove(tr)
    for o in objs:
        if o.type == 'ARMATURE':
            rest_pose(o)
    bpy.context.view_layer.update()
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    objs = flatten(objs)
    # one mesh: a big scan comes split in two (glTF's 65k vertices a part) with the parts' triangles interleaved;
    # thinned apart, their shared edges open everywhere. Joined, the seam's points merged, it's one surface.
    ms = [o for o in objs if o.type == 'MESH']
    if len(ms) > 1:
        bpy.ops.object.select_all(action='DESELECT')
        for o in ms:
            o.select_set(True)
        bpy.context.view_layer.objects.active = ms[0]
        bpy.ops.object.join()
        for o in ms[1:]:
            objs.remove(o)
    one = next(o for o in objs if o.type == 'MESH')
    bm = bmesh.new()
    bm.from_mesh(one.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00002)
    bm.to_mesh(one.data)
    bm.free()
    meshes = [o for o in objs if o.type == 'MESH']
    arm = next((o for o in objs if o.type == 'ARMATURE'), None)
    # her height and place: standing at the origin, feet on the ground (measured at rest)
    if arm:
        arm.data.pose_position = 'REST'
    bpy.context.view_layer.update()
    pts = mesh_points(meshes)
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    k = spec["h"] / (hi.z - lo.z)
    feet = [p for p in pts if p.z < lo.z + 0.05 * (hi.z - lo.z)]
    fx = sum(p.x for p in feet) / len(feet)
    fy = sum(p.y for p in feet) / len(feet)
    for o in objs:
        o.matrix_world = Matrix.Scale(k, 4) @ Matrix.Translation(Vector((-fx, -fy, -lo.z))) @ o.matrix_world
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if arm:
        arm.data.pose_position = 'POSE'
        rename_bones(arm, meshes)
        for m in meshes:
            m.parent = arm
            m.matrix_parent_inverse = Matrix.Identity(4)
    else:
        f = FACE.get(name)
        arm = auto_rig(meshes, spec["h"], (f["at"][1] - f["mouth"][1] / 1000.0 - 0.04) if f else None)
    bpy.context.view_layer.update()
    if faceshot_dir:
        faceshot(name, arm, meshes, faceshot_dir)
        return
    if spec.get("skirt"):
        kz = (arm.matrix_world @ arm.data.bones["calf_l"].head_local).z
        hz = (arm.matrix_world @ arm.data.bones["thigh_l"].head_local).z
        for m in meshes:
            skirt_weights(m, kz, hz)
    chin = (arm.matrix_world @ arm.data.bones["head"].head_local).z - 0.035
    f = FACE.get(name)
    if f:                                                  # (the mouth known: the chin a little under it)
        chin = min(chin, f["at"][1] - f["mouth"][1] / 1000.0 - 0.05)
    a, b = thin(meshes, budget or spec.get("tris", 30000), chin, arm.matrix_world @ arm.data.bones["head"].head_local)
    print("LIVE %s: %d → %d tris, %.2f m" % (name, a, b, spec["h"]), flush=True)
    rebuilt = spec.get("rebuild") and name in FACE and rebuild_face(name, arm, meshes)   # (after the thinning: shape keys)
    clips = [] if "--noclips" in sys.argv else retarget(arm, spec["sex"])     # (--noclips: trying the face out)
    if not rebuilt:                                        # (a rebuilt face has its template's units)
        face_shapes(name, arm, meshes)
    if spec.get("tints") and clips:
        tints(name, meshes, spec["tints"])
    if spec.get("far") and clips:
        far_one(name, arm, meshes)
    bpy.ops.object.select_all(action='DESELECT')
    for o in [arm] + meshes:
        o.select_set(True)
    out = os.path.join(OUT, "sfa_%s.glb" % name)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_skins=True, export_morph=True,
                              export_animations=True, export_animation_mode='ACTIONS', export_image_format='WEBP')
    print("LIVE wrote", out, "%.1f MB" % (os.path.getsize(out) / 1e6), len(clips), "clips", flush=True)


def template(sex):
    """The face that gives a scan's its shape (rebuild_face): one of our story cast's (story_divya / story_suresh:
    MakeHuman, a real nose, brows, lids, lips, jaw, and its face's units as blend shapes), at rest."""
    reset()
    objs = load(TEMPLATE[sex]["file"])
    arm = next(o for o in objs if o.type == 'ARMATURE')
    if arm.animation_data:
        arm.animation_data.action = None
    rest_pose(arm)
    bpy.context.view_layer.update()
    meshes = [o for o in objs if o.type == 'MESH']
    return arm, meshes


def bake_front(meshes, x0, z0, wm, hm, ppm=4):
    """Her face as seen from in front (each triangle's texture, the nearest surface), a picture wm by hm metres from
    (x0, z0) its bottom left, ppm pixels a mm: what the rebuilt face wears."""
    W, H = int(wm * 1000 * ppm), int(hm * 1000 * ppm)
    img = np.zeros((H, W, 3))
    zb = np.full((H, W), 9.0)
    pix = {}
    for m in meshes:
        me = m.data
        uv = me.uv_layers.active.data
        mw = m.matrix_world
        co = [mw @ v.co for v in me.vertices]
        me.calc_loop_triangles()
        for t in me.loop_triangles:
            mat = me.materials[t.material_index] if t.material_index < len(me.materials) else None
            tex = _mat_texture(mat)
            if tex is None:
                continue
            if tex.name not in pix:
                pix[tex.name] = (np.array(tex.pixels[:]).reshape(int(tex.size[1]), int(tex.size[0]), 4), int(tex.size[0]), int(tex.size[1]))
            px, tw, th = pix[tex.name]
            ps = [co[i] for i in t.vertices]
            xs = [(p.x - x0) * 1000 * ppm for p in ps]
            ys = [(p.z - z0) * 1000 * ppm for p in ps]
            if max(xs) < 0 or min(xs) >= W or max(ys) < 0 or min(ys) >= H:
                continue
            d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(d) < 1e-9:
                continue
            us = [uv[li].uv for li in t.loops]
            gx, gy = np.meshgrid(np.arange(max(0, int(min(xs))), min(W, int(max(xs)) + 2)),
                                 np.arange(max(0, int(min(ys))), min(H, int(max(ys)) + 2)))
            a = ((ys[1] - ys[2]) * (gx + 0.5 - xs[2]) + (xs[2] - xs[1]) * (gy + 0.5 - ys[2])) / d
            b = ((ys[2] - ys[0]) * (gx + 0.5 - xs[2]) + (xs[0] - xs[2]) * (gy + 0.5 - ys[2])) / d
            c = 1 - a - b
            inside = (a >= -0.02) & (b >= -0.02) & (c >= -0.02)
            if not inside.any():
                continue
            y = a * ps[0].y + b * ps[1].y + c * ps[2].y
            gx, gy, a, b, c, y = gx[inside], gy[inside], a[inside], b[inside], c[inside], y[inside]
            near = y < zb[gy, gx]
            if not near.any():
                continue
            gx, gy, a, b, c, y = gx[near], gy[near], a[near], b[near], c[near], y[near]
            zb[gy, gx] = y
            u = a * us[0].x + b * us[1].x + c * us[2].x
            v = a * us[0].y + b * us[1].y + c * us[2].y
            img[gy, gx] = px[np.clip((v * th).astype(int), 0, th - 1), np.clip((u * tw).astype(int), 0, tw - 1), :3]
    hole = zb > 8.0                                          # (nothing there: the nearest colour, so edges don't go black)
    if hole.any() and (~hole).any():
        for _ in range(6):
            sh = [np.roll(img, k, axis=ax) for ax in (0, 1) for k in (-1, 1)]
            hs = [np.roll(~hole, k, axis=ax) for ax in (0, 1) for k in (-1, 1)]
            cnt = sum(h.astype(float) for h in hs)
            acc = sum(s_ * h[..., None] for s_, h in zip(sh, hs))
            fill = hole & (cnt > 0)
            img[fill] = acc[fill] / cnt[fill][:, None]
            hole = hole & ~fill
    return img


def _chin(trees, x, mz, eye_dist):
    """The chin's bottom under a mouth at (x, mz): going down the face's front a mm at a time, where it turns back
    (the skin there 2 cm behind the chin's front: the neck)."""
    ymin, last = None, None
    for i in range(8, int(eye_dist * 2000)):
        z = mz - i / 1000.0
        y = _front(trees, x, z)
        if y is None:
            break
        ymin = y if ymin is None else min(ymin, y)
        if y > ymin + 0.02:
            return last
        last = z
    return last


def rebuild_face(name, arm, meshes):
    """A scan's face made a real face: a scan is a photograph laid over a rough head (from the side its bumps tear
    the picture, and its features are flat). The face of one of our own people (TEMPLATE: MakeHuman, a nose, brows,
    lids, lips, a chin) put over hers, fitted to her eyes and mouth (an affine fit of the three, its depth to hers
    between the eyes), wearing her face as seen from in front (bake_front): the same face, its shape a face's. Her
    own skin under it taken out; its edge laid onto her skin (no step), the template's units (blinks, the mouth, the
    brows: our faces' blend shapes) and its teeth and tongue with it."""
    f = FACE[name]
    sex = PEOPLE[name]["sex"]
    tp = TEMPLATE[sex]
    W = lambda d, p: Vector((d["at"][0] + p[0] / 1000.0, 0.0, d["at"][1] - p[1] / 1000.0))
    hers = [W(f, f["left"]), W(f, f["right"]), W(f, f["mouth"])]
    # her picture first (before her face is taken out) and her skin's depth
    trees = _surface(meshes)
    ec = (hers[0] + hers[1]) / 2
    ed = (hers[0] - hers[1]).length
    x0, z0 = ec.x - ed * 1.4, hers[2].z - ed * 1.25
    wm, hm = ed * 2.8, (ec.z - hers[2].z) + ed * 2.1
    img = bake_front(meshes, x0, z0, wm, hm)
    im = bpy.data.images.new("face_" + name, img.shape[1], img.shape[0])
    im.pixels = np.concatenate([img, np.ones(img.shape[:2] + (1,))], axis=2).ravel()
    im.pack()
    her_front = _front(trees, ec.x, ec.z + ed * 0.05)
    # the template, at rest, in this scene
    before = set(bpy.data.objects)
    keep_actions = set(bpy.data.actions)
    tobjs = load(tp["file"])
    tarm = next(o for o in tobjs if o.type == 'ARMATURE')
    if tarm.animation_data:
        tarm.animation_data.action = None
    rest_pose(tarm)
    bpy.context.view_layer.update()
    skin = next(o for o in tobjs if o.type == 'MESH' and o.data.shape_keys and len(o.data.vertices) > 5000)
    parts = [o for o in tobjs if o.type == 'MESH' and (o.name.endswith("low-poly") or "teeth" in o.name or "tongue" in o.name)]
    tl = [W(tp, tp["left"]), W(tp, tp["right"]), W(tp, tp["mouth"])]
    # the fit: x, z affine from the template's three to hers; y scaled as the face is, to her depth between the eyes
    Ms = np.array([[p.x, p.z, 1.0] for p in tl])
    ax = np.linalg.solve(Ms, np.array([p.x for p in hers]))
    az = np.linalg.solve(Ms, np.array([p.z for p in hers]))
    ky = math.sqrt(abs(ax[0] * az[1] - ax[1] * az[0]))
    tt = _surface([skin])
    tec = (tl[0] + tl[1]) / 2
    ted = (tl[0] - tl[1]).length
    t_front = _front(tt, tec.x, tec.z + ted * 0.05)
    for _, _, b in tt:
        b.free()
    oy = (her_front if her_front is not None else 0.0) - t_front * ky
    # the chins: under the mouth, where the face's front turns back into the neck. Below the mouth the template is
    # stretched (or shrunk) so its chin comes to hers (else her own chin's skin hangs under the new one).
    tt2 = _surface([skin])
    t_chin = _chin(tt2, tl[2].x, tl[2].z, ted)
    for _, _, b in tt2:
        b.free()
    h_chin = _chin(trees, hers[2].x, hers[2].z, ed)
    kc = ((hers[2].z - h_chin) / ((tl[2].z - t_chin) * az[1])) if (t_chin and h_chin) else 1.0
    kc = min(1.4, max(0.75, kc))
    print("FACE chins: hers %.3f, the template's %.3f, under the mouth x%.2f" % (h_chin or 0, t_chin or 0, kc), flush=True)

    def fit(p):
        z = p.z if p.z >= tl[2].z else tl[2].z + (p.z - tl[2].z) * kc
        return Vector((ax[0] * p.x + ax[1] * z + ax[2], p.y * ky + oy, az[0] * p.x + az[1] * z + az[2]))
    lin = Matrix(((ax[0], 0, ax[1]), (0, ky, 0), (az[0], 0, az[1])))
    # the region: from above the brows to under the chin, cheek to cheek (the template's)
    rc = Vector((tec.x, 0, (tec.z + tl[2].z) / 2 - ted * 0.12))
    rx, rz = ted * 0.9, (tec.z - tl[2].z) * 1.75
    r_of = lambda p: (abs((p.x - rc.x) / rx) ** 3 + abs((p.z - rc.z) / rz) ** 3) ** (1 / 3)   # (a rounded box: the
                                                                                             #  jaw's corners in)
    thead = (tarm.matrix_world @ tarm.pose.bones["head"].head)
    # her mesh: her face's skin taken out (front, inside 0.9 of the region mapped onto her)
    inv2 = np.linalg.inv(np.array([[ax[0], ax[1]], [az[0], az[1]]]))
    to_t = lambda p: Vector((*(inv2 @ np.array([p.x - ax[2], p.z - az[2]])),))
    m = meshes[0]
    mw = m.matrix_world
    bm = bmesh.new()
    bm.from_mesh(m.data)
    gone = []
    for fc in bm.faces:
        ok = True
        for v in fc.verts:
            p = mw @ v.co
            t2 = to_t(p)
            tz = t2[1] if t2[1] >= tl[2].z else tl[2].z + (t2[1] - tl[2].z) / kc      # (in the template's, unstretched)
            if her_front is None or p.y > her_front + 0.035 or r_of(Vector((t2[0], 0, tz))) > 0.9:
                ok = False
                break
        if ok:
            gone.append(fc)
    bmesh.ops.delete(bm, geom=gone, context='FACES')
    # the template's face in: its skin in the region (facing forward, not its mouth's inside) and its eyes, teeth, tongue
    mats = [x.name for x in m.data.materials]
    fm = bpy.data.materials.new("face " + name)
    fm.use_nodes = True
    bsdf = next(n for n in fm.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    tn = fm.node_tree.nodes.new("ShaderNodeTexImage")
    tn.image = im
    fm.node_tree.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.65
    m.data.materials.append(fm)
    fmi = len(m.data.materials) - 1
    dl = bm.verts.layers.deform.verify()
    uvl = bm.loops.layers.uv.verify()
    head_g = m.vertex_groups.get("head") or m.vertex_groups.new(name="head")
    units = [k.name for k in skin.data.shape_keys.key_blocks[1:]]
    added = []                                               # [(new vert, its places in each unit)]
    for part in [skin] + parts:
        pm = part.data
        pmw = part.matrix_world
        keys = pm.shape_keys.key_blocks if pm.shape_keys else None
        own = None
        if part is not skin:                                 # (eyes, teeth, tongue: their own materials; the eyes' irises
            if part.name.endswith("low-poly"):               #  darkened, a brown nearly black)
                for mt in pm.materials:
                    tx = _mat_texture(mt)
                    if tx is not None and not tx.name.startswith("dark "):
                        px_ = np.array(tx.pixels[:]).reshape(-1, 4)
                        mx_, mn_ = px_[:, :3].max(1), px_[:, :3].min(1)
                        iris = (mx_ - mn_) / (mx_ + 1e-6) > 0.2
                        px_[iris, :3] *= np.array([0.42, 0.34, 0.3])
                        dk = bpy.data.images.new("dark " + tx.name, int(tx.size[0]), int(tx.size[1]))
                        dk.pixels = px_.ravel()
                        dk.pack()
                        next(n for n in mt.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image == tx).image = dk
            own = []
            for mt in pm.materials:
                if mt.name not in [x.name for x in m.data.materials]:
                    m.data.materials.append(mt)
                own.append([x.name for x in m.data.materials].index(mt.name))
        vmap = {}
        puv = pm.uv_layers.active.data if pm.uv_layers.active else None
        for poly in pm.polygons:
            ps = [pmw @ pm.vertices[i].co for i in poly.vertices]
            if part is skin:
                n = (pmw.to_3x3() @ poly.normal)
                if any(r_of(p) > 1.0 for p in ps) or n.y > 0.35 or any(p.y > thead.y for p in ps):
                    continue
            elif any(r_of(p) > 1.0 for p in ps):
                continue
            vs = []
            for i in poly.vertices:
                if i not in vmap:
                    p = pmw @ pm.vertices[i].co
                    q = fit(p)
                    rr = r_of(p) if part is skin else 0.0
                    b = 1.0 - min(1.0, max(0.0, (rr - 0.72) / 0.28))     # (1 inside, 0 at the edge: onto her skin)
                    if b < 1.0:
                        hy = _front(trees, q.x, q.z)
                        if hy is not None:
                            q.y = hy * (1 - b) + q.y * b
                    q.y -= 0.0004                                         # (a breath in front of what's left of hers)
                    if own is not None:
                        q.y += 0.004                                      # (the teeth back behind the closed lips)
                    nv = bm.verts.new(mw.inverted() @ q)
                    nv[dl][head_g.index] = 1.0
                    pos = []
                    for u in units:
                        if keys is not None and u in keys:
                            dlt = pmw.to_3x3() @ (keys[u].data[i].co - pm.vertices[i].co)
                            pos.append(mw.inverted() @ (q + (lin @ dlt) * b))
                        else:
                            pos.append(mw.inverted() @ q)
                    vmap[i] = nv
                    added.append((nv, pos))
                vs.append(vmap[i])
            try:
                nf = bm.faces.new(vs)
            except ValueError:
                continue
            nf.smooth = True
            if own is None:
                nf.material_index = fmi
                for l in nf.loops:
                    pw = mw @ l.vert.co
                    l[uvl].uv = ((pw.x - x0) / wm, (pw.z - z0) / hm)
            else:
                nf.material_index = own[poly.material_index] if poly.material_index < len(own) else own[0]
                if puv is not None:
                    for l, li in zip(nf.loops, poly.loop_indices):
                        l[uvl].uv = puv[li].uv
    bm.verts.index_update()
    idx = [(v.index, pos) for v, pos in added]
    bm.to_mesh(m.data)
    bm.free()
    for _, _, b in trees:
        b.free()
    kb = _keys(m)
    for ui, u in enumerate(units):
        k = kb.get(u) or m.shape_key_add(name=u, from_mix=False)
        for vi, pos in idx:
            k.data[vi].co = pos[ui]
    for o in tobjs:                                          # (the template gone; its materials stay with her)
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a not in keep_actions:
            bpy.data.actions.remove(a)
    print("FACE rebuilt on %s: %d of her faces out, %d points in, %d units" % (name, len(gone), len(idx), len(units)), flush=True)
    return True


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--templateshot" in args:                           # (the template faces' pictures, for TEMPLATE below)
        out = args[args.index("--templateshot") + 1]
        for sx in ("w", "m"):
            arm, meshes = template(sx)
            print("TEMPLATE meshes", [(m.name, len(m.data.vertices)) for m in meshes], flush=True)
            faceshot("template_" + sx, arm, [m for m in meshes if len(m.data.vertices) > 5000 and m.data.shape_keys], out)
        return
    shot = args[args.index("--faceshot") + 1] if "--faceshot" in args else None
    budget = int(args[args.index("--tris") + 1]) if "--tris" in args else None
    names = [a for a in args if a in PEOPLE] or list(PEOPLE)
    for n in names:
        build(n, shot, budget)


if __name__ == "__main__":
    main()
