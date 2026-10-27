"""
The story's main cast as game characters (docs/STORY_BIBLE.md): MakeHuman bodies (MPFB2) built the way
street_people.py builds them (skins, eyes, brows, lashes, hair, clothes) with a face of their own
(quality.face_shape), but KEEPING the skeleton (MPFB's 53-bone game rig) so they can move in the game, with
hand-keyed clips named like the street people's (tools/people.py): Idle (breathing, weight shifting), Talk (a
gesture, a nod), Walk (a 1 s cycle), Run (two strides in 16 frames), Sit (hands on the thighs), Ride (the scooter). Exported as godot/assets/people/story_<key>.glb for scripts/story/actor.gd.

    Blender -b --python tools/humans/story_cast.py -- [--only karthik,amma] [--preview out.jpg]

Reads street_people.py and quality.py (the face work) without changing them.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import street_people as SP  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "godot", "assets", "people")
# key, gender (1 man), years, weight, muscle, height, skin, hair, brows, outfit, main colour, face seed
# (hair "sf:<style>": a style from the Sketchfab hair collection, fitted to the head: sketchfab_hair)
# skin tones across the range you see in Coimbatore: fair (Suresh, Divya, the clerk, Ashwin), medium brown
# (Karthik, Amma, the hotel owner), dark (Raghavan)
CAST = [
    ("karthik", 1.0, 28, 0.5, 0.55, 0.58, "young_asian_male", "sf:hair09", "mindfront_eyebrows_03", "trousers",
     (0.25, 0.42, 0.7), 404),
    ("raghavan", 1.0, 61, 0.6, 0.45, 0.52, "old_african_male", "short01", "eyebrow004", "veshti",
     (0.95, 0.95, 0.92), 303),
    ("suresh", 1.0, 46, 0.68, 0.5, 0.55, "middleage_asian_male", "short04", "eyebrow004", "trousers",
     (0.82, 0.76, 0.62), 909),
    ("amma", 0.0, 52, 0.62, 0.4, 0.4, "cutoff3d_indian_female_skin", "bob02", "mindfront_eyebrows_08", "saree",
     (0.55, 0.1, 0.15), 505),
    ("divya", 0.0, 19, 0.45, 0.35, 0.45, "young_asian_female", "braid01", "mindfront_eyebrows_10",
     "modern_f", (0.2, 0.55, 0.55), 606),
    ("clerk", 1.0, 44, 0.58, 0.45, 0.5, "middleage_asian_male", "short04", "eyebrow004", "trousers",
     (0.93, 0.93, 0.9), 711),
    ("cook", 1.0, 52, 0.7, 0.5, 0.5, "middleage_african_male", "short01", "eyebrow004", "trousers",
     (0.85, 0.55, 0.25), 812),
    ("ashwin", 1.0, 27, 0.5, 0.5, 0.6, "young_asian_male", "short02", "mindfront_eyebrows_03", "trousers",
     (0.15, 0.15, 0.17), 913),
]
FPS = 24


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.armatures, bpy.data.actions):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)


def build(c):
    """One cast member, rigged (the street people's build() without baking the pose away)."""
    key, g, yrs, w, mu, hgt, skin, hair, brows, outfit, colour, seed = c
    rng = random.Random(seed)
    h = SP.HS.create_human()
    h.name = key
    for k, v in (("gender", g), ("age", SP.age(yrs)), ("weight", w), ("muscle", mu), ("height", hgt),
                 ("african", 0.45), ("asian", 0.13), ("caucasian", 0.42)):
        SP.HOP.set_value(k, v, entity_reference=h)
    SP.TS.reapply_macro_details(h)
    try:                                                  # a face of their own (the face work's tools)
        import quality as Q
        Q.face_shape(h, random.Random(seed), feminine=g < 0.5, strength=0.5)
    except Exception as e:                                # noqa: BLE001
        print("CAST face_shape skipped:", e, flush=True)
    arm = SP.HS.add_builtin_rig(h, "game_engine")
    sk = SP.asset(skin + ".mhmat", "skins")
    if sk:
        SP.HS.set_character_skin(sk, h, skin_type="MAKESKIN")
    objs = [h]
    for sub, fname, typ in (("eyes", "low-poly.mhclo", "Eyes"), ("eyebrows", brows + ".mhclo", "Eyebrows"),
                            ("eyelashes", ("mindfront_eyelashes_02" if g > 0.5 else "mindfront_eyelashes_04") + ".mhclo", "Eyelashes"),
                            ("hair", hair + ".mhclo", "Hair")):
        p = SP.asset(fname, sub)
        if p:
            o = SP.HS.add_mhclo_asset(p, h, asset_type=typ, subdiv_levels=0, material_type="MAKESKIN")
            if typ == "Hair":
                SP.tint(o, (0.05, 0.04, 0.035) if yrs < 55 else (0.45, 0.44, 0.42), 0.9)
            objs.append(o)
    top = {"trousers": "male_casualsuit03", "veshti": "male_casualsuit03", "saree": "female_casualsuit02",
           "modern_f": "female_casualsuit01"}[outfit]
    p = SP.asset(top + ".mhclo", "clothes")
    if p:
        cl = SP.HS.add_mhclo_asset(p, h, asset_type="Clothes", subdiv_levels=0, material_type="MAKESKIN")
        shirt = {"trousers": colour, "veshti": (0.92, 0.92, 0.88),
                 "saree": (colour[0] * 0.6 + 0.25, colour[1] * 0.6 + 0.2, colour[2] * 0.6 + 0.15), "modern_f": colour}[outfit]
        SP.plain_clothes(cl, shirt, outfit)
        if key == "divya":                                 # navy trousers: the waistband reads as jeans, not a grey band
            for m in cl.data.materials:
                if m and m.name.startswith("Pants") and m.node_tree:
                    bsdf = m.node_tree.nodes.get("Principled BSDF")
                    if bsdf:
                        bsdf.inputs["Base Color"].default_value = (0.06, 0.08, 0.2, 1.0)
        if outfit == "veshti":                           # no trouser legs under the draped cloth
            SP.cut_below(cl, 0.95)
        elif outfit == "saree":                          # the T-shirt becomes a fitted saree blouse
            SP.blouse_cut(cl, colour)
        objs.append(cl)
    shoes = SP.asset("shoes0%d.mhclo" % (1 + rng.randrange(3)), "clothes")
    if shoes and outfit == "trousers":                    # (Divya is at home in her scenes: barefoot, as at home)
        objs.append(SP.HS.add_mhclo_asset(shoes, h, asset_type="Clothes", subdiv_levels=0, material_type="MAKESKIN"))
    if outfit == "saree":
        objs += saree(h, arm, cl if p else None, colour, rng)
    # the veshti is a cloth tube round the legs: it rides on the pelvis bone
    if outfit == "veshti":
        bpy.context.view_layer.update()
        names = {vg.index: vg.name for vg in h.vertex_groups}
        bv = []
        for v in h.data.vertices:
            if v.groups:
                top_g = max(v.groups, key=lambda gg: gg.weight)
                if names.get(top_g.group, "").startswith(("thigh", "calf", "pelvis", "foot", "spine_01")):
                    bv.append(tuple(h.matrix_world @ v.co))
        SP.BODY.update({"verts": [v for v in bv if v[2] < 1.08], "obj": h, "top": None, "quality": False, "rng": rng})
        SP.BODY["cy"] = sum(v[1] for v in SP.BODY["verts"]) / max(len(SP.BODY["verts"]), 1)
        for wo in SP.wrap(outfit, colour, 0.0):
            loose = {"Saree": 1.12, "Zari": 1.12, "Veshti": 1.07, "Border": 1.07}.get(wo.name.split(".")[0], 1.0)
            if loose != 1.0 and wo.type == 'MESH':       # hang clear of the hips and legs (they showed through)
                vs = wo.data.vertices
                cx = sum(v.co.x for v in vs) / len(vs)
                cy = sum(v.co.y for v in vs) / len(vs)
                for v in vs:
                    v.co.x = cx + (v.co.x - cx) * loose
                    v.co.y = cy + (v.co.y - cy) * loose
            mw = wo.matrix_world.copy()
            wo.parent = arm
            wo.parent_type = 'BONE'
            wo.parent_bone = "spine_03" if wo.name.startswith("Pallu") else "pelvis"   # the drape rides the chest
            wo.matrix_world = mw                          # (stays where it was, now moving with the body)
            objs.append(wo)
    # flatten the shape keys (the body's targets) so the modifiers can be exported
    for o in objs:
        if o.type == 'MESH' and o.data.shape_keys:
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.select_all(action='DESELECT')
            o.select_set(True)
            bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    if hair.startswith("sf:"):
        objs.append(sketchfab_hair(h, arm, hair[3:], (0.025, 0.02, 0.018)))
    return arm, objs


HAIRS = os.path.join(HERE, "..", "..", "mapdata", "sketchfab", "people", "free_male_fashion_hair_collection_02_lowpoly.glb")


def sketchfab_hair(body, arm, style, colour):
    """A hairstyle from the Sketchfab hair collection (Vincent Page, CC-BY; docs/DATA_SOURCES.md) fitted to this
    head: the style (and its scalp cap) comes off its bust, scaled so the bust's skull (its width and depth 6 cm
    under the crown) matches this one's, set just under the crown, pushed out wherever the scalp would show
    through, and skinned to the head bone (arm None: left as it is, for a still). body: the head it sits on (a
    whole body uses its "head" vertex group; a head alone, all of it)."""
    from mathutils.bvhtree import BVHTree
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(HAIRS))
    new = [o for o in bpy.data.objects if o not in before]
    num = style.replace("hair", "").lstrip("0")
    parts = [o for o in new if o.type == 'MESH' and o.name.split("_")[0] in (style, "hair%scap" % num, "hair%s" % num + "cap")]
    for o in new:                                          # bake every transform in (the busts sit in a grid)
        if o.type == 'MESH':
            o.data = o.data.copy()
            o.data.transform(o.matrix_world)
    hv = [v.co.copy() for o in parts for v in o.data.vertices]
    hc = sum(hv, Vector()) / len(hv)
    def centre(o):
        vs = [v.co for i, v in enumerate(o.data.vertices) if i % 50 == 0]
        return sum(vs, Vector()) / len(vs)
    bust = min((o for o in new if o.type == 'MESH' and not o.name.startswith("hair")), key=lambda o: (centre(o) - hc).xy.length)
    bv = [v.co for v in bust.data.vertices if (v.co - hc).xy.length < 0.2]

    def skull(vs):
        top = max(v.z for v in vs)
        ring = [v for v in vs if top - 0.07 < v.z < top - 0.05]
        xs, ys = [v.x for v in ring], [v.y for v in ring]
        return top, max(xs) - min(xs), max(ys) - min(ys), Vector(((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2))
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    be = body.evaluated_get(dg)
    me = be.to_mesh()
    gi = body.vertex_groups["head"].index if "head" in body.vertex_groups else None
    heads = [be.matrix_world @ v.co for v in me.vertices
             if gi is None or any(g.group == gi and g.weight > 0.5 for g in body.data.vertices[v.index].groups)]
    t1, w1, d1, c1 = skull(heads)
    t0, w0, d0, c0 = skull(bv)
    sx, sy = w1 / w0, d1 / d0
    # height as the width (a deep skull made it stand tall); 1 cm down so the front comes to the hairline
    m = (Matrix.Translation(Vector((c1.x, c1.y, t1 - 0.01))) @ Matrix.Diagonal((sx, sy, min(sx, sy), 1.0))
         @ Matrix.Translation(-Vector((c0.x, c0.y, t0))))
    for o in parts:
        o.data.transform(m)
    # wherever the scalp would show through, out just past it
    tri = [tuple(p.vertices) for p in me.polygons]
    tree = BVHTree.FromPolygons([be.matrix_world @ v.co for v in me.vertices], tri)
    pushed = 0
    for o in parts:
        for v in o.data.vertices:
            loc, nrm, _, dist = tree.find_nearest(v.co, 0.08)
            if loc is not None and (v.co - loc).dot(nrm) < 0.004:
                v.co = loc + nrm * 0.004
                pushed += 1
    be.to_mesh_clear()
    for o in [o for o in new if o not in parts]:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    hair = bpy.context.view_layer.objects.active
    hair.name = hair.data.name = "Hair"
    hair.data.materials.clear()
    mat = bpy.data.materials.new("Hair")
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*colour, 1)
    b.inputs["Roughness"].default_value = 0.85                 # (the cards caught bright lights at grazing angles:
    if "Specular IOR Level" in b.inputs:                       # grey streaks; hair reads matte and dark)
        b.inputs["Specular IOR Level"].default_value = 0.12
    hair.data.materials.append(mat)
    for p in hair.data.polygons:                           # (the style and its cap came with a material each)
        p.material_index = 0
        p.use_smooth = True
    if arm is not None:                                    # (a still, like the grooming pictures, has no rig)
        vg = hair.vertex_groups.new(name="head")
        vg.add(range(len(hair.data.vertices)), 1.0, 'REPLACE')
        hair.parent = arm
        md = hair.modifiers.new("Armature", 'ARMATURE')
        md.object = arm
    print("CAST hair %s: skull x%.2f y%.2f, %d points pushed out of the scalp, %d tris" % (
        style, sx, sy, pushed, sum(len(p.vertices) - 2 for p in hair.data.polygons)), flush=True)
    return hair


# ---- the saree ----
def saree_material(colour):
    """Silk with small gold buttas, a zari border along both edges (v near 0 and 1) and a richer gold band at the
    pallu's end (u near 1): an image (procedural shaders don't survive the export to the game)."""
    import numpy as np
    n = 1024
    yy, xx = np.mgrid[0:n, 0:n] / n                     # yy: v (0 at the top row of the array), xx: u
    base = np.array(colour)[None, None, :] * (0.92 + 0.08 * np.sin(xx * n * 0.9))[:, :, None]   # the weave
    img = np.repeat(base, 1, axis=0).copy()
    gold = np.array((0.85, 0.62, 0.16))
    gx, gy = (xx * 24) % 1.0, (yy * 24) % 1.0           # buttas: little gold dots on a grid, every other row offset
    off = (np.floor(yy * 24) % 2) * 0.5
    d = np.hypot(((xx * 24 + off) % 1.0) - 0.5, gy - 0.5)
    img[d < 0.13] = gold
    for lo, hi in ((0.0, 0.085), (0.915, 1.0)):         # the zari borders, with a darker line pattern inside
        band = (yy >= lo) & (yy < hi)
        img[band] = gold
        stripe = band & (((yy - lo) * n).astype(int) % 14 < 3)
        img[stripe] = gold * 0.6
    img[xx > 0.86] = img[xx > 0.86] * 0.4 + gold * 0.6  # the pallu's end
    px = np.ones((n, n, 4), dtype=np.float32)
    px[:, :, :3] = img[::-1]
    im = bpy.data.images.new("SareeSilk", n, n)
    im.pixels.foreach_set(px.ravel())
    im.pack()
    m = bpy.data.materials.new("Saree Silk")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.42
    if "Sheen Weight" in b.inputs:
        b.inputs["Sheen Weight"].default_value = 0.5
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = im
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    return m


def saree(h, arm, top, colour, rng):
    """The saree as it is worn: the skirt fitted round the hips and legs with the pleats fanned in front and the
    zari at the hem, skinned to the pelvis and thighs so it swings with her walk; the pallu draped as cloth from
    the waist across the chest, over the left shoulder and down the back."""
    import bmesh
    mat = saree_material(colour)
    bpy.context.view_layer.update()
    # the hips and legs as they are: the body mesh's own vertices (not MakeHuman's hidden helper shapes), below the
    # waist and inside the hands
    gi = h.vertex_groups.find("body")
    bv = []
    for v in h.data.vertices:
        if gi < 0 or any(g.group == gi for g in v.groups):
            w = h.matrix_world @ v.co
            if w.z < 1.08 and abs(w.x) < 0.27:
                bv.append(tuple(w))
    SP.BODY.update({"verts": bv, "obj": h, "top": None, "quality": False, "rng": rng})
    cy = SP.BODY["cy"] = sum(v[1] for v in SP.BODY["verts"]) / max(len(SP.BODY["verts"]), 1)
    prof = SP.fit_profile([1.04, 0.97, 0.88, 0.78, 0.66, 0.54, 0.42, 0.3, 0.18, 0.07, 0.03], flare=0.0, ease=0.016)
    segs = 112
    front = 1.5 * math.pi                                # the body faces -Y
    z0, z1 = prof[-1][1], prof[0][1]
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rings = []
    for rx, z, k in prof:
        hf = (z1 - z) / (z1 - z0)                        # 0 at the waist, 1 at the hem
        ring = []
        for i in range(segs):
            a = i / segs * math.tau
            r = rx
            d = (a - front + math.pi) % math.tau - math.pi
            if abs(d) < 0.6:                              # the pleats, deeper and wider towards the hem
                fan = (1.0 - abs(d) / 0.6) ** 0.5
                r += (0.004 + 0.02 * hf) * fan * (1 if i % 2 else -1)
            ring.append(bm.verts.new((math.cos(a) * r, cy + math.sin(a) * r * k, z)))
        rings.append((ring, hf))
    for (r1, h1), (r2, h2) in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            f = bm.faces.new((r1[i], r2[i], r2[j], r1[j]))           # wound so the faces look outward
            for lp, (u, hv) in zip(f.loops, ((i, h1), (i, h2), (i + 1, h2), (i + 1, h1))):
                lp[uv].uv = (u / segs * 0.85, 0.04 + 0.86 * (1.0 - hv))     # the hem at the zari band (v ~ 0); short of the pallu end
    me = bpy.data.meshes.new("Saree")
    bm.to_mesh(me)
    bm.free()
    sk = bpy.data.objects.new("Saree", me)
    bpy.context.scene.collection.objects.link(sk)
    me.materials.append(mat)
    for pl in me.polygons:
        pl.use_smooth = True
    # skin it: the waist rides the pelvis, down to the knees each side follows its thigh, below the knees its shin
    # (mostly), blended across the middle. (Thighs alone carried the whole skirt: seated, the thighs go forward
    # and the skirt below the knees stuck straight out like a bell instead of falling with the shins.)
    left_x = arm.data.bones["thigh_l"].head_local.x
    sgn = 1.0 if left_x > 0 else -1.0
    hip_z = (arm.matrix_world @ arm.data.bones["thigh_l"].head_local).z
    knee_z = (arm.matrix_world @ arm.data.bones["calf_l"].head_local).z
    groups = {n: sk.vertex_groups.new(name=n) for n in ("pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r")}
    for v in me.vertices:
        z = v.co.z
        pel = max(0.0, min(1.0, (z - (hip_z - 0.08)) / 0.1))           # the waist and hips: the pelvis
        shin = max(0.0, min(1.0, ((knee_z + 0.06) - z) / 0.18)) * 0.85  # below the knee: mostly the shin
        thigh = (1.0 - pel) * (1.0 - shin)
        calf = (1.0 - pel) * shin
        side = max(0.0, min(1.0, 0.5 + 1.4 * sgn * v.co.x / 0.2))
        groups["pelvis"].add([v.index], pel, 'REPLACE')
        groups["thigh_l"].add([v.index], thigh * side, 'REPLACE')
        groups["thigh_r"].add([v.index], thigh * (1.0 - side), 'REPLACE')
        groups["calf_l"].add([v.index], calf * side, 'REPLACE')
        groups["calf_r"].add([v.index], calf * (1.0 - side), 'REPLACE')
    sk.parent = arm
    am = sk.modifiers.new("Armature", 'ARMATURE')
    am.object = arm
    parts = [sk]
    # the pallu: the face work's cloth drape (quality.py), in the same silk
    try:
        import quality as Q
        pa = Q.drape_pallu(h, top, colour, rng)
        pa.data.materials.clear()
        pa.data.materials.append(mat)
        mw = pa.matrix_world.copy()
        pa.parent = arm
        pa.parent_type = 'BONE'
        pa.parent_bone = "spine_03"
        pa.matrix_world = mw
        parts.append(pa)
    except Exception as e:                               # noqa: BLE001
        print("CAST pallu skipped:", e, flush=True)
    return parts


# ---- the clips ----
def rest(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    bpy.context.view_layer.update()


def turn(arm, bone, axis, deg):
    """Turn a bone about a world axis (the character faces -Y, its left is +X)."""
    if bone in arm.pose.bones:
        SP.rotate_bone(arm, bone, axis, math.radians(deg))


def lower(arm, bone, dz):
    pb = arm.pose.bones.get(bone)
    if pb is None:
        return
    m = arm.matrix_world @ pb.matrix
    m.translation.z += dz
    pb.matrix = arm.matrix_world.inverted() @ m
    bpy.context.view_layer.update()


def arms_down(arm):
    """The game rig rests in an A-pose (arms ~45° down): the neutral standing pose every clip starts from (relax)."""
    relax(arm)


def key_all(arm, frame):
    for pb in arm.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def clip(arm, name, frames):
    """frames: [(frame, fn(arm))]: each pose built from the rest pose, keyed, pushed to its own NLA track."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    for tr in arm.animation_data.nla_tracks:          # the clips made before this one must not shape its pose
        tr.mute = True
    arm.animation_data.action = act
    for f, fn in frames:
        rest(arm)
        arms_down(arm)
        fn(arm)
        key_all(arm, f)
    arm.animation_data.action = None
    tr = arm.animation_data.nla_tracks.new()
    tr.name = name
    tr.strips.new(name, int(frames[0][0]), act)


def idle(a, k):                     # breathing, the weight shifting from foot to foot, a small look about
    pb = a.pose.bones.get("pelvis")
    if pb is not None:                                     # hips over one foot, then the other
        m = a.matrix_world @ pb.matrix
        m.translation.x += 0.012 * k
        pb.matrix = a.matrix_world.inverted() @ m
        bpy.context.view_layer.update()
    turn(a, "pelvis", 'Y', -1.5 * k)
    turn(a, "spine_02", 'Y', 1.2 * k)
    turn(a, "spine_02", 'X', -1.2 * k)
    turn(a, "head", 'Z', 2.5 * k)


def talk(a, k):                     # the right hand comes up and moves with the words, the head nods
    turn(a, "upperarm_r", 'X', -22)
    turn(a, "lowerarm_r", 'X', -45 - 15 * k)
    turn(a, "hand_r", 'Z', 10 * k)
    turn(a, "head", 'X', 3 * k)
    turn(a, "spine_02", 'X', -1.0 * k)


def walk_phase(a, t):
    """One moment of the walk cycle, t in [0, 1): the left leg is furthest forward at t = 0.25 (heel strike),
    the right at 0.75. Thighs swing ±25°; the swinging leg's knee folds up to ~60° as it passes under the body,
    the standing knee keeps a slight give; the foot rolls heel to toe; the pelvis turns and drops a little with
    each step and the body bobs; the chest counter-turns, the arms swing against the legs with soft elbows, the
    head stays level."""
    w = 2.0 * math.pi * t
    sw = math.sin(w)
    turn(a, "thigh_l", 'X', -25.0 * sw)
    turn(a, "thigh_r", 'X', 25.0 * sw)
    turn(a, "calf_l", 'X', 6.0 + 58.0 * max(0.0, math.cos(w)) ** 1.6)
    turn(a, "calf_r", 'X', 6.0 + 58.0 * max(0.0, math.cos(w - math.pi)) ** 1.6)
    turn(a, "foot_l", 'X', 14.0 * sw - 6.0 * max(0.0, math.cos(w)))
    turn(a, "foot_r", 'X', -14.0 * sw - 6.0 * max(0.0, math.cos(w - math.pi)))
    lower(a, "pelvis", -0.028 * abs(sw))                   # down on the double support, up as a leg passes
    turn(a, "pelvis", 'Z', 5.0 * sw)
    turn(a, "pelvis", 'Y', 2.5 * math.sin(2.0 * w))
    turn(a, "spine_03", 'Z', -6.0 * sw)
    turn(a, "upperarm_l", 'X', 18.0 * sw)
    turn(a, "upperarm_r", 'X', -18.0 * sw)
    turn(a, "lowerarm_l", 'X', -(14.0 + 12.0 * max(0.0, -sw)))
    turn(a, "lowerarm_r", 'X', -(14.0 + 12.0 * max(0.0, sw)))
    turn(a, "neck_01", 'Z', 3.0 * sw)


def run_phase(a, t):
    """One moment of the run cycle, t in [0, 1) (two strides in 16 frames, ~3.9 m/s): the thighs swing further than
    walking (+35° forward, -30° back), the trailing knee folds right up (~105°) as it comes through, the standing
    leg gives on landing; the body leans into it and lifts off between steps; the arms bent near 90° pump against
    the legs, the chest turns with them a little, the head stays steady."""
    w = 2.0 * math.pi * t
    sw = math.sin(w)
    turn(a, "spine_01", 'X', 9.0)                          # leaning into the run
    turn(a, "neck_01", 'X', -7.0)
    turn(a, "thigh_l", 'X', -(2.5 + 32.5 * sw))
    turn(a, "thigh_r", 'X', -(2.5 - 32.5 * sw))
    turn(a, "calf_l", 'X', 18.0 + 87.0 * max(0.0, math.cos(w + 0.6)) ** 1.3)
    turn(a, "calf_r", 'X', 18.0 + 87.0 * max(0.0, math.cos(w + 0.6 - math.pi)) ** 1.3)
    turn(a, "foot_l", 'X', 12.0 * sw - 8.0)
    turn(a, "foot_r", 'X', -12.0 * sw - 8.0)
    lower(a, "pelvis", -0.07 + 0.05 * abs(math.sin(w + 0.4)))     # down on landing, up off the toes
    turn(a, "pelvis", 'Z', 7.0 * sw)
    turn(a, "spine_03", 'Z', -10.0 * sw)
    turn(a, "upperarm_l", 'X', 48.0 * sw + 10.0)           # the hands pump from the chest back past the hips
    turn(a, "upperarm_r", 'X', -48.0 * sw + 10.0)
    turn(a, "lowerarm_l", 'X', -(70.0 - 12.0 * sw))
    turn(a, "lowerarm_r", 'X', -(70.0 + 12.0 * sw))
    turn(a, "neck_01", 'Z', 3.0 * sw)


def sit(a):
    lower(a, "pelvis", -0.42)
    turn(a, "thigh_l", 'X', -84)
    turn(a, "thigh_r", 'X', -84)
    turn(a, "calf_l", 'X', 84)
    turn(a, "calf_r", 'X', 84)
    for side, sg in (("l", 1.0), ("r", -1.0)):            # the hands resting on the thighs
        sh = head_of(a, "upperarm_" + side)
        el0, wr0 = head_of(a, "lowerarm_" + side), head_of(a, "hand_" + side)
        knee, hip = head_of(a, "calf_" + side), head_of(a, "thigh_" + side)
        wrist = hip.lerp(knee, 0.45) + Vector((sg * 0.04, 0.0, 0.09))
        elbow = two_bone(sh, wrist, (el0 - sh).length, (wr0 - el0).length, Vector((sg * 0.6, 0.6, -0.4)))
        aim(a, "upperarm_" + side, lambda: head_of(a, "lowerarm_" + side), elbow)
        aim(a, "lowerarm_" + side, lambda: head_of(a, "hand_" + side), wrist)
        mid = "middle_01_" + side
        if mid in a.pose.bones:
            aim(a, "hand_" + side, lambda: head_of(a, mid), knee + Vector((sg * 0.03, 0.0, 0.06)))


# ---- riding Karthik's scooter (tools/bikes_real.py FIT["scooter"]: X forward, Y left, Z up) ----
RIDE = dict(hip=Vector((-0.17, 0.0, 0.945)), grip=Vector((0.335, 0.345, 1.05)), foot=Vector((0.14, 0.13, 0.338)), lean=6.0)
CURL = 68.0


def head_of(arm, name):
    return arm.matrix_world @ arm.pose.bones[name].head


def tail_of(arm, name):
    return arm.matrix_world @ arm.pose.bones[name].tail


def qturn(arm, name, q):
    """Rotate a pose bone (and all below it) about its head by the world rotation q."""
    pb = arm.pose.bones[name]
    m = arm.matrix_world @ pb.matrix
    t = m.translation.copy()
    pb.matrix = arm.matrix_world.inverted() @ (Matrix.Translation(t) @ q.to_matrix().to_4x4() @ Matrix.Translation(-t) @ m)
    bpy.context.view_layer.update()


def aim(arm, name, tip, target):
    p = head_of(arm, name)
    qturn(arm, name, (tip() - p).rotation_difference(Vector(target) - p))


def two_bone(root, target, l1, l2, pole):
    d = target - root
    dist = min(d.length, l1 + l2 - 1e-3)
    n = d.normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    return root + n * a + (pole - n * pole.dot(n)).normalized() * h


def ride(a):
    """Sitting on the scooter: hips on the seat (they stay where they are; the game puts the scooter under them),
    back a little forward, head up, hands round the grips, feet flat on the floorboard."""
    hip_h = (head_of(a, "thigh_l") + head_of(a, "thigh_r")) / 2

    def to_h(p):                                       # a point of the scooter in the person's frame
        d = Vector(p) - RIDE["hip"]
        return hip_h + Vector((d.y, -d.x, d.z))
    lean = math.radians(RIDE["lean"] + 4.0)
    qturn(a, "spine_02", Quaternion((1, 0, 0), lean * 0.55))
    qturn(a, "spine_03", Quaternion((1, 0, 0), lean * 0.45))
    qturn(a, "neck_01", Quaternion((1, 0, 0), -lean * 0.9))
    for side, sg in (("l", 1), ("r", -1)):
        hj = head_of(a, "thigh_" + side)
        kn0, an0 = head_of(a, "calf_" + side), head_of(a, "foot_" + side)
        ankle = to_h(Vector((RIDE["foot"].x - 0.05, sg * RIDE["foot"].y, RIDE["foot"].z + 0.085)))
        knee = two_bone(hj, ankle, (kn0 - hj).length, (an0 - kn0).length, Vector((sg * 0.25, -1.0, 0.35)))
        aim(a, "thigh_" + side, lambda: head_of(a, "calf_" + side), knee)
        aim(a, "calf_" + side, lambda: head_of(a, "foot_" + side), ankle)
        aim(a, "foot_" + side, lambda: tail_of(a, "foot_" + side), ankle + Vector((sg * 0.02, -0.12, -0.06)))
        sh = head_of(a, "upperarm_" + side)
        el0, wr0 = head_of(a, "lowerarm_" + side), head_of(a, "hand_" + side)
        grip = to_h(Vector((RIDE["grip"].x, sg * RIDE["grip"].y, RIDE["grip"].z)))
        wrist = to_h(Vector((RIDE["grip"].x - 0.075, sg * (RIDE["grip"].y - 0.02), RIDE["grip"].z + 0.025)))
        elbow = two_bone(sh, wrist, (el0 - sh).length, (wr0 - el0).length, Vector((sg * 1.0, 0.25, -0.9)))
        aim(a, "upperarm_" + side, lambda: head_of(a, "lowerarm_" + side), elbow)
        aim(a, "lowerarm_" + side, lambda: head_of(a, "hand_" + side), wrist)
        mid = "middle_01_" + side
        if mid in a.pose.bones:
            aim(a, "hand_" + side, lambda: head_of(a, mid), grip + Vector((0, -0.025, 0.035)))
        for f in ("index", "middle", "ring", "pinky"):               # the fingers closed round the grip
            for j in (1, 2, 3):
                bn = "%s_0%d_%s" % (f, j, side)
                if bn in a.pose.bones:
                    qturn(a, bn, Quaternion((1, 0, 0), math.radians(CURL * (0.8 if j == 1 else 1.0))))
        for j in (1, 2, 3):                                           # the thumb wrapped under the grip
            bn = "thumb_0%d_%s" % (j, side)
            if bn in a.pose.bones:
                qturn(a, bn, Quaternion((1, 0, 0), math.radians(40 if j > 1 else 25)))
                qturn(a, bn, Quaternion((0, 0, 1), math.radians(-sg * 12)))


def curl_fingers(a, side, deg, thumb_deg):
    """Close the fingers towards the palm by deg at each joint (less at the knuckle), the thumb a little in. The bend
    axis is the knuckle line (index to pinky); its sign is whichever brings the fingertip towards the palm."""
    knuckles = head_of(a, "index_01_" + side) - head_of(a, "pinky_01_" + side)
    if knuckles.length < 1e-4:
        return
    axis = knuckles.normalized()
    palm = head_of(a, "thumb_01_" + side)
    for f in ("index", "middle", "ring", "pinky"):
        chain = ["%s_0%d_%s" % (f, j, side) for j in (1, 2, 3)]
        if any(b not in a.pose.bones for b in chain):
            continue
        tip = lambda: tail_of(a, chain[2])                               # noqa: E731
        d0 = (tip() - palm).length
        qturn(a, chain[0], Quaternion(axis, math.radians(10)))
        sgn = 1.0 if (tip() - palm).length < d0 else -1.0
        qturn(a, chain[0], Quaternion(axis, math.radians(-10)))
        for j, b in enumerate(chain):
            qturn(a, b, Quaternion(axis, sgn * math.radians(deg * (0.7 if j == 0 else 1.0))))
    for j in (1, 2, 3):
        b = "thumb_0%d_%s" % (j, side)
        if b in a.pose.bones:
            qturn(a, b, Quaternion(axis, math.radians(thumb_deg) * (1 if side == "l" else -1)))


def hang_arm(a, side, out=0.10, back=0.04, bend=0.18):
    """An arm hanging at the side (the character faces -Y, its left is +X): the elbow just out from the waist and a
    little behind the shoulder line, the forearm a touch forward, the wrist straight, the palm towards the thigh."""
    sg = 1.0 if side == "l" else -1.0
    sh = head_of(a, "upperarm_" + side)
    l1 = (head_of(a, "lowerarm_" + side) - sh).length
    elbow = sh + Vector((sg * out, back, -1.0)).normalized() * l1
    aim(a, "upperarm_" + side, lambda: head_of(a, "lowerarm_" + side), elbow)
    el = head_of(a, "lowerarm_" + side)
    l2 = (head_of(a, "hand_" + side) - el).length
    wrist = el + Vector((sg * 0.03, -bend, -1.0)).normalized() * l2
    aim(a, "lowerarm_" + side, lambda: head_of(a, "hand_" + side), wrist)
    fdir = (head_of(a, "hand_" + side) - el).normalized()
    mid = "middle_01_" + side
    if mid in a.pose.bones:                                # the hand straight on from the forearm
        aim(a, "hand_" + side, lambda: head_of(a, mid), head_of(a, "hand_" + side) + fdir * 0.09)
    # palm to the thigh: turn the forearm about its own line until the knuckles (pinky to index) point forward
    if "index_01_" + side in a.pose.bones:
        k = head_of(a, "index_01_" + side) - head_of(a, "pinky_01_" + side)
        k -= fdir * k.dot(fdir)
        want = Vector((0, -1, 0)) - fdir * (-fdir.y)
        if k.length > 1e-4 and want.length > 1e-4:
            ang = k.normalized().angle(want.normalized())
            if k.normalized().cross(want.normalized()).dot(fdir) < 0:
                ang = -ang
            qturn(a, "lowerarm_" + side, Quaternion(fdir, ang))


def relax(a):
    """Standing at ease: arms hanging beside the body, elbows soft, fingers gently curled."""
    if "upperarm_l" not in a.pose.bones:
        return
    for side in ("l", "r"):
        hang_arm(a, side)
        curl_fingers(a, side, 18.0, 12.0)


def animate(arm):
    clip(arm, "Idle", [(1, lambda a: idle(a, -1)), (37, lambda a: idle(a, 1)), (73, lambda a: idle(a, -1))])
    clip(arm, "Talk", [(1, lambda a: talk(a, -1)), (13, lambda a: talk(a, 1)), (25, lambda a: talk(a, -0.4)),
                       (37, lambda a: talk(a, 1)), (49, lambda a: talk(a, -1))])
    clip(arm, "Walk", [(1 + 2 * k, (lambda kk: (lambda a: walk_phase(a, (kk % 12) / 12.0)))(k)) for k in range(13)])
    clip(arm, "Run", [(1 + 2 * k, (lambda kk: (lambda a: run_phase(a, (kk % 8) / 8.0)))(k)) for k in range(9)])
    clip(arm, "Sit", [(1, sit), (25, sit)])
    clip(arm, "Ride", [(1, ride), (25, ride)])
    for tr in arm.animation_data.nla_tracks:
        tr.mute = False
    rest(arm)
    arms_down(arm)


def export(arm, objs, path):
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    for o in objs:
        if o.name in bpy.data.objects:
            o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_skins=True, export_animations=True,
                              export_animation_mode='NLA_TRACKS', export_image_format='JPEG')
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs if o.type == 'MESH')
    print("CAST", os.path.basename(path), "tris %d, %.1f MB" % (tris, os.path.getsize(path) / 1e6), flush=True)


def preview(arm, objs, out):
    """A quick look at the character standing in its idle pose (Eevee, front three-quarter)."""
    sc = bpy.context.scene
    for tr in arm.animation_data.nla_tracks:              # standing still for the picture
        tr.mute = True
    rest(arm)
    arms_down(arm)
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [e.identifier for e in sc.render.bl_rna.properties["engine"].enum_items] else 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 900, 1100
    sc.render.image_settings.file_format = 'JPEG'
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.data.lens = 50
    cam.location = (0.9, -3.4, 1.35)
    cam.rotation_euler = (Vector((0, 0, 1.0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", out, flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = args[args.index("--only") + 1].split(",") if "--only" in args else [c[0] for c in CAST]
    os.makedirs(OUT, exist_ok=True)
    for c in CAST:
        if c[0] not in only:
            continue
        clear()
        arm, objs = build(c)
        animate(arm)
        export(arm, objs, os.path.abspath(os.path.join(OUT, "story_%s.glb" % c[0])))
        if "--preview" in args:
            p = args[args.index("--preview") + 1]
            preview(arm, objs, os.path.abspath(p.replace(".jpg", "_%s.jpg" % c[0])))


if __name__ == "__main__":
    main()
