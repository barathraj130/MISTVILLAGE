"""
Brushing and bathing with the real Karthik (scripts/story/groom.gd): the story cast's body (tools/humans/story_cast.py)
with a GNM head (the face work's scanned-head model, tools/humans/gnm_head.py, fitted on as tools/humans/gnm_heroine.py
does) in every expression the chores need (a wide smile with the teeth, cheeks blown out, lips funnelled, eyes
squeezed shut), strand hair, a moustache, brows and lashes, rendered in Cycles in a tiled bathroom; the props as
cut-outs; the masks and points the game needs to put foam, stains and water in the right places.

    godot/assets/story/groom/
        brush_<face>.jpg        head and shoulders in a vest: idle blink open giggle puff spit grin
        bath_<face>_<dry|wet>.jpg  sitting on a stool in his shorts: idle blink shiver giggle squeeze grin
        bath_mask.png           white where he is (soap and water land on him)
        ..._close.jpg/png       the same, framed close on his face and chest (the player zooms in)
        prop_<name>.png         brush, brush_paste, tube, tumbler, mug, soap, towel (transparent)
        groom.json              the mouth's teeth (brush) and the head (bath), as fractions of the picture

Needs the MPFB add-on (no --factory-startup):
    Blender -b --python tools/story_groom.py -- [--only brush|bath|props]
"""
import json
import math
import os
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "humans"))
import gnm_head as G  # noqa: E402
import quality as Q  # noqa: E402
import story_cast as C  # noqa: E402
import street_people as SP  # noqa: E402

OUT = os.path.abspath(os.path.join(HERE, "..", "godot", "assets", "story", "groom"))
W, H = 1152, 752                                     # the picture (groom.gd's area is about 1.53 : 1)

# the faces, as GNM Head expression classes (tools/humans/gnm_head.py EXPRESSIONS); BLINK closes both eyes
BRUSH = {
    "idle": {"HAPPY": 0.15},
    "blink": {"HAPPY": 0.15, "WINK_LEFT": 1.0, "WINK_RIGHT": 1.0},
    "open": {"SMILE_WIDE": 0.8, "SURPRISE": 0.45, "STRETCH_FACE": 0.3},
    "giggle": {"SMILE_WIDE": 0.9, "HAPPY": 0.5, "SQUINT": 0.7},
    "puff": {"BLOW": 1.0},
    "spit": {"FUNNELER": 0.85, "SQUINT": 0.4},
    "grin": {"SMILE_WIDE": 1.0, "HAPPY": 0.6},
}
BATH = {
    "idle": {"HAPPY": 0.2},
    "blink": {"HAPPY": 0.2, "WINK_LEFT": 1.0, "WINK_RIGHT": 1.0},
    "shiver": {"CORNERS_DOWN": 0.6, "COMPRESS_FACE": 0.5, "WINK_LEFT": 0.8, "WINK_RIGHT": 0.8, "STRETCH_FACE": 0.3},
    "giggle": {"SMILE_WIDE": 0.8, "SQUINT": 0.7, "HAPPY": 0.4},
    "squeeze": {"COMPRESS_FACE": 1.0, "WINK_LEFT": 1.0, "WINK_RIGHT": 1.0},
    "grin": BRUSH["grin"],
}
SEED = 404                                                           # Karthik's own head (the story cast's seed)
ETH = dict(middle_eastern=0.5, black=0.3, asian=0.2)
TONE = (0.3, 0.17, 0.1)                                              # medium brown


# ---- the scene ----
class Gnm:
    """Karthik's GNM head on the posed body: built once, then re-shaped for each expression (brows, lashes and the
    moustache regrown on the new face, so they follow it)."""

    def __init__(self, h):
        self.body = h
        blm = Q.landmarks(h)
        G.pick_identity = young_face                                 # (Karthik is 28 and lean, not the widest face)
        self.head = G.build_head(np.random.default_rng(SEED), female=0.0, ethnicity=ETH, smile=0.0, tone=TONE,
                                 name="Karthik head")
        raw = np.array([v.co for v in self.head.data.vertices])
        self.s = G.fit_to_body(self.head, blm)
        fitted = np.array([v.co for v in self.head.data.vertices])
        self.off = fitted[0] - raw[0] * self.s
        zb, _ = G.neck_bottom(self.head)
        import bmesh                                                 # the body's own head and neck off, under the join
        bm = bmesh.new()
        bm.from_mesh(h.data)
        chin = G.lm_of(self.head)["chin_z"]                         # the join goes up under the jaw, in its shadow
        gone = [v for v in bm.verts if v.co.z > chin + 0.006 and math.hypot(v.co.x - blm["cx"], v.co.y - blm["cy"]) < 0.068]
        bmesh.ops.delete(bm, geom=gone, context='VERTS')
        bm.to_mesh(h.data)
        bm.free()
        # the scan's neck ends in a ragged shelf: in every face it is tucked inside the body's own neck (kept below
        # the join), so the body carries on smoothly (deleting it would break the head's vertex numbering)
        fitted_z = np.array([v.co.z for v in self.head.data.vertices])
        self.low = (G._group("skin") > 0.5) & (fitted_z < chin - 0.012)
        self.neck_c = (blm["cx"], blm["cy"])
        skin = self.head.data.materials[0].copy()                  # the body in the face's skin, a little more matte
        for n_ in skin.node_tree.nodes:
            if n_.type == 'MAP_RANGE':
                n_.inputs["To Min"].default_value = 0.62
                n_.inputs["To Max"].default_value = 0.55
        h.data.materials.clear()
        h.data.materials.append(skin)
        pa = h.data.color_attributes.new("Paint", 'FLOAT_COLOR', 'POINT')
        pa.data.foreach_set("color", np.tile(np.array([1, 1, 1, 0], np.float32), len(h.data.vertices)))
        G.darken_scalp(self.head)
        self.idp = young_face(np.random.default_rng(SEED), 0.0, ETH, 0.55)
        self.strands = []
        self.hair = None
        self.face({})

    def grow_hair(self):
        """His haircut as in the game (the story cast's: a combed side part from the Sketchfab hair collection),
        fitted again to the GNM head (the one the cast build put on fits MakeHuman's head, not this one)."""
        if os.path.exists(C.HAIRS):
            for o in [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith("Hair")]:
                bpy.data.objects.remove(o, do_unlink=True)
            spec = [c for c in C.CAST if c[0] == "karthik"][0]
            self.hair = C.sketchfab_hair(self.head, None, spec[7][3:] if spec[7].startswith("sf:") else "hair09",
                                         (0.012, 0.01, 0.009))      # (Cycles' bright bathroom light: darker)
            return
        """(Without the collection: MakeHuman's own hair mesh, grown a little about the skull's centre so the scan
        never pokes through.)"""
        hair = [o for o in bpy.data.objects if o.type == 'MESH' and "short0" in o.name.lower()]
        if hair:
            lm = G.lm_of(self.head)
            c = Vector((lm["cx"], lm["cy"], lm["eye_z"]))
            for o in hair:
                me = o.data
                for v in me.vertices:
                    w = o.matrix_world @ v.co
                    v.co = o.matrix_world.inverted() @ (c + (w - c) * 1.05)
                me.update()
                for ms in o.material_slots:                          # the hair texture is light: dark brown-black
                    m = ms.material
                    b = m.node_tree.nodes.get("Principled BSDF") if m and m.node_tree else None
                    if b is not None:
                        mixer = m.node_tree.nodes.new("ShaderNodeMix")
                        mixer.data_type = 'RGBA'
                        mixer.blend_type = 'MULTIPLY'
                        mixer.inputs["Factor"].default_value = 1.0
                        mixer.inputs["B"].default_value = (0.22, 0.18, 0.15, 1)
                        src = b.inputs["Base Color"].links[0].from_socket if b.inputs["Base Color"].links else None
                        if src is not None:
                            m.node_tree.links.new(src, mixer.inputs["A"])
                            m.node_tree.links.new(mixer.outputs["Result"], b.inputs["Base Color"])
                        else:
                            b.inputs["Base Color"].default_value = (0.03, 0.025, 0.02, 1)
            self.hair = hair[0]
            return
        """(Without the hair mesh: short strands, combed back and to one side.)"""
        tmp = [o.copy() for o in (self.head, self.body)]
        for t in tmp:
            t.data = t.data.copy()
            bpy.context.scene.collection.objects.link(t)
        bpy.ops.object.select_all(action='DESELECT')
        for t in tmp:
            t.select_set(True)
        bpy.context.view_layer.objects.active = tmp[0]
        bpy.ops.object.join()
        coll = bpy.context.view_layer.objects.active
        import random
        self.hair = young_hair(coll, G.lm_of(self.head), random.Random(SEED))
        bpy.data.objects.remove(coll, do_unlink=True)

    def face(self, weights):
        """Re-shape the head to an expression (a blend of GNM classes), then regrow brows, lashes, moustache."""
        v0 = G.vertices(self.idp)
        v = G.symmetric(G.sculpt(v0, 0.45, 0.0))                     # a leaner jaw and cheeks
        if weights:
            exp = G.expression_params(np.random.default_rng(SEED + 1), weights)
            v = v + (G.vertices(self.idp, exp, 1.6) - v0)            # (the decoder's faces are mild: shown strongly)
        V = np.stack([v[:, 0], -v[:, 2], v[:, 1]], 1) * self.s + self.off
        if hasattr(self, "low"):
            cx, cy = self.neck_c
            V[self.low, 0] = cx + (V[self.low, 0] - cx) * 0.3
            V[self.low, 1] = cy + 0.02 + (V[self.low, 1] - cy) * 0.3
        self.head.data.vertices.foreach_set("co", V.astype(np.float32).ravel())
        self.head.data.update()
        for o in self.strands:
            if o.name in bpy.data.objects:
                bpy.data.objects.remove(o, do_unlink=True)
        import random
        self.strands = list(G.brows_and_lashes(self.head, random.Random(SEED), False))
        m = self.moustache()
        if m is not None:
            self.strands.append(m)
        bpy.context.view_layer.update()

    def moustache(self):
        """The thin moustache, grown once on the resting face and then carried by the upper lip: each hair moves
        with the point of skin it grows from. (Grown afresh for each face it was looked for at a fixed height under
        the nose: a grin or an open mouth pulls the lip away from there and it vanished.)"""
        import random
        from mathutils.kdtree import KDTree
        mw = self.head.matrix_world
        vw = np.array([tuple(mw @ v.co) for v in self.head.data.vertices], np.float64)
        if getattr(self, "_m0", None) is None:
            m = Q.moustache(self.head, G.lm_of(self.head), random.Random(SEED), "thin")
            if m is None:
                return None
            pos = np.empty(len(m.data.points) * 3, np.float32)
            m.data.points.foreach_get("position", pos)
            pos = pos.reshape(-1, 3)
            kd = KDTree(len(vw))
            for i, co in enumerate(vw):
                kd.insert(co, i)
            kd.balance()
            starts = [c.first_point_index for c in m.data.curves]
            sizes = [c.points_length for c in m.data.curves]
            root = np.array([kd.find(Vector(pos[st]))[1] for st in starts])
            per_point = np.repeat(root, sizes)
            self._m0 = (m.data.copy(), pos.copy(), per_point, vw.copy())
            self._m0[0].use_fake_user = True
            return m
        data0, pos0, per_point, v0 = self._m0
        cd = data0.copy()
        moved = pos0 + (vw[per_point] - v0[per_point]).astype(np.float32)
        cd.points.foreach_set("position", moved.ravel())
        ob = bpy.data.objects.new("Moustache", cd)
        bpy.context.scene.collection.objects.link(ob)
        return ob

    def teeth_points(self):
        w = G._group("teeth")
        return [self.head.matrix_world @ v.co for v, k in zip(self.head.data.vertices, w) if k > 0.5]


def young_hair(body, lm, rng, count=150000, length=(0.04, 0.075)):
    """A young man's short hair, parted on his right and combed over and back, lying close to the head (the face
    work's strand_hair, quality.py, with a side parting and less lift)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    inv = ev.matrix_world.inverted()
    c = Vector((lm["cx"], lm["cy"], lm["top"] - 0.1))
    front_y = lm["nose"].y + 0.05
    part_x = lm["cx"] - 0.03                                         # the parting, over his right eye
    roots = []
    tries = 0
    while len(roots) < count and tries < count * 6:
        tries += 1
        u = rng.uniform(-1, 1)
        a = rng.uniform(0, math.tau)
        d = Vector((math.sqrt(1 - u * u) * math.cos(a), math.sqrt(1 - u * u) * math.sin(a), abs(u)))
        o = c + d * 0.3
        hit, loc, nrm, idx = ev.ray_cast(inv @ o, inv.to_3x3() @ (-d), distance=0.4)
        if not hit:
            continue
        p = ev.matrix_world @ loc
        back = (p.y - front_y) / 0.18
        line = lm["eye_z"] + 0.062 - 0.11 * max(0.0, min(1.0, back))
        if abs(p.x - lm["cx"]) > 0.065 and back < 0.55:
            line = max(line, lm["eye_z"] + 0.035)
        if p.z < line:
            continue
        roots.append((p, (ev.matrix_world.to_3x3() @ nrm).normalized()))
    curves = bpy.data.hair_curves.new("Hair")
    seg = 6
    curves.add_curves([seg] * len(roots))
    pts = curves.points
    k = 0
    for p, n in roots:
        big = p.x > part_x                                           # the big side sweeps over, the small side down
        # a short men's cut: the top longer with some lift, the sides and back cropped close to the head
        top = max(0.0, 1.0 - abs(p.x - lm["cx"]) / 0.06) * max(0.0, min(1.0, (p.z - (lm["eye_z"] + 0.06)) / 0.05))
        comb = Vector((0.45, 0.9, -0.1) if big else (-0.3, 0.8, -0.35)).normalized()
        if top < 0.3:
            comb = Vector((0.0, 0.5, -1.0)).normalized()             # the sides lie down and back
        L = rng.uniform(*length) * (0.3 + 0.7 * top)
        d = (n * (0.1 + 0.4 * top) + comb).normalized()
        q = p.copy()
        for si in range(seg):
            pts[k].position = q
            pts[k].radius = 0.00018 * (1.0 - 0.6 * si / seg)          # thick enough to hide the scalp
            to_c = (c - q).normalized()
            d = (d + to_c * 0.09 + Vector((0, 0, -0.04)) + Vector((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), 0))).normalized()
            q = q + d * (L / (seg - 1))
            k += 1
    ob = bpy.data.objects.new("Hair strands", curves)
    bpy.context.scene.collection.objects.link(ob)
    curves.materials.append(Q._hair_material("Hair", 0.95, 0.0))
    return ob


def young_face(rng, female=0.0, ethnicity=None, spread=0.55, tries=24, push=0.8):
    """Of a few sampled men's faces, the leanest (narrow at the mouth and jaw): a young man's, not the widest."""
    best = None
    for _ in range(tries):
        idp = G.identity_params(rng, 0.0, ethnicity, spread) - push * G.female_direction()
        _, _, we, wm, wc = G._landmarks(G.vertices(idp))
        score = wm / we + 0.6 * wc / we
        if best is None or score < best[0]:
            best = (score, idp)
    return best[1]


def bake_pose(arm):
    """The pose made permanent on the body and clothes (the pictures are stills): the head swap works on it then."""
    for o in [o for o in bpy.data.objects if o.type == 'MESH' and (o.parent is arm or o.find_armature() is arm)]:
        bpy.context.view_layer.objects.active = o
        for md in list(o.modifiers):
            if md.type == 'ARMATURE':
                bpy.ops.object.select_all(action='DESELECT')
                o.select_set(True)
                bpy.ops.object.modifier_apply(modifier=md.name)


def drop_face_parts(objs_root):
    """MakeHuman's own eyes, brows, lashes, hair, teeth and tongue: the GNM head brings its own."""
    for o in list(bpy.data.objects):
        n = o.name.lower()
        if o.type == 'MESH' and any(k in n for k in ("low-poly", "eyebrow", "eyelash", "teeth", "tongue")):
            bpy.data.objects.remove(o, do_unlink=True)


def tex_image(name, rgb):
    n = rgb.shape[0]
    im = bpy.data.images.new(name, n, n)
    px = np.ones((n, n, 4), dtype=np.float32)
    px[:, :, :3] = rgb[::-1]
    im.pixels.foreach_set(px.ravel())
    im.pack()
    return im


def tiles(size, colour, grout=(0.55, 0.58, 0.6), n=512, per=4, seed=1):
    rng = np.random.default_rng(seed)
    img = np.ones((n, n, 3)) * np.array(colour)[None, None, :]
    t = n // per
    for i in range(per):
        for j in range(per):
            img[i * t:(i + 1) * t, j * t:(j + 1) * t] *= 0.96 + 0.06 * rng.random()
    for k in range(per + 1):
        p = min(k * t, n - 1)
        img[max(p - 3, 0):p + 3, :] = grout
        img[:, max(p - 3, 0):p + 3] = grout
    return img


def material(name, colour, rough=0.5, metal=0.0, image=None, coat=0.0, emit=None, strength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*colour, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if coat and "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    if image is not None:
        t = m.node_tree.nodes.new("ShaderNodeTexImage")
        t.image = image
        uv = m.node_tree.nodes.new("ShaderNodeTexCoord")
        mp = m.node_tree.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (4, 4, 4)
        m.node_tree.links.new(uv.outputs["Generated"], mp.inputs["Vector"])
        m.node_tree.links.new(mp.outputs["Vector"], t.inputs["Vector"])
        m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    return m


def plane(name, loc, size, rot, mat):
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.scale = (size[0], size[1], 1)
    o.data.materials.append(mat)
    return o


def light(kind, loc, energy, size=1.0, colour=(1, 1, 1), target=(0, 0, 1.4)):
    ld = bpy.data.lights.new(kind, 'AREA')
    ld.energy = energy
    ld.size = size
    ld.color = colour
    o = bpy.data.objects.new(kind, ld)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return o


def camera(at, look, lens):
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    bpy.context.scene.collection.objects.link(cam)
    cam.location = at
    cam.data.lens = lens
    cam.rotation_euler = (Vector(look) - Vector(at)).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = cam
    return cam


def setup_render(transparent=False):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'                                     # the GNM skin's scattering wants a path tracer
    sc.cycles.samples = 64
    sc.cycles.use_denoising = True
    try:
        pr = bpy.context.preferences.addons["cycles"].preferences
        pr.compute_device_type = 'METAL'
        pr.get_devices()
        for d in pr.devices:
            d.use = True
        sc.cycles.device = 'GPU'
    except Exception:                                               # noqa: BLE001
        pass
    sc.render.resolution_x, sc.render.resolution_y = W, H
    sc.render.film_transparent = transparent
    sc.view_settings.view_transform = 'Standard'                   # true colours (AgX washed the skin out)
    looks = [v.identifier for v in sc.view_settings.bl_rna.properties["look"].enum_items]
    for want in ("Medium High Contrast", "Standard - Medium High Contrast"):
        if want in looks:
            sc.view_settings.look = want
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.52, 0.55, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.12
    sc.world = w


def render(path, jpg=True):
    sc = bpy.context.scene
    sc.render.image_settings.file_format = 'JPEG' if jpg else 'PNG'
    if not jpg:
        sc.render.image_settings.color_mode = 'RGBA'
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("GROOM", os.path.basename(path), flush=True)


def project(cam, pts):
    sc = bpy.context.scene
    out = []
    for p in pts:
        v = world_to_camera_view(sc, cam, Vector(p))
        out.append((v.x, 1.0 - v.y))
    return out


def evaluated_points(o):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(dg)
    return [ev.matrix_world @ v.co for v in ev.data.vertices]


def add_proxy(h, sub, fname, typ):
    p = SP.asset(fname, sub)
    if p:
        return SP.HS.add_mhclo_asset(p, h, asset_type=typ, subdiv_levels=0, material_type="MAKESKIN")
    return None


def karthik(outfit):
    """Karthik's body as the story cast builds him; outfit 'vest' (a white banian) or 'bath' (bare to the waist,
    in cotton shorts)."""
    spec = [c for c in C.CAST if c[0] == "karthik"][0]
    arm, objs = C.build(spec)
    h = objs[0]
    teeth = None
    for o in objs:
        if o.type != 'MESH' or o is h:
            continue
        if "casualsuit" in o.name:
            import bmesh
            bm = bmesh.new()
            bm.from_mesh(o.data)
            if outfit == "bath":                                    # the trousers cut down to cotton shorts
                kill = [f for f in bm.faces if any(v.co.z > 1.1 or v.co.z < 0.5 for v in f.verts)]
                bmesh.ops.delete(bm, geom=kill, context='FACES')
                bm.to_mesh(o.data)
                bm.free()
                o.data.materials.clear()
                o.data.materials.append(material("Shorts", (0.5, 0.12, 0.12), 0.85))
                for p in o.data.polygons:
                    p.material_index = 0
                continue
            kill = [f for f in bm.faces if any(abs(v.co.x) > 0.185 and v.co.z > 1.05 for v in f.verts)]   # a vest
            bmesh.ops.delete(bm, geom=kill, context='FACES')
            bm.to_mesh(o.data)
            bm.free()
            vest = material("Vest", (0.92, 0.92, 0.89), 0.85)
            o.data.materials.clear()
            o.data.materials.append(vest)
            for p in o.data.polygons:
                p.material_index = 0
        elif "shoes" in o.name and outfit == "bath":
            bpy.data.objects.remove(o, do_unlink=True)
    if outfit == "bath":                                            # the skin the shirt hid, shown again
        for md in list(h.modifiers):                                # (keep the one hiding MakeHuman's helper shapes)
            if md.type == 'MASK':
                print("GROOM mask", md.name, md.vertex_group, md.invert_vertex_group, flush=True)
                if md.vertex_group != "body":
                    h.modifiers.remove(md)
    C.rest(arm)
    C.arms_down(arm)
    return arm, h, teeth


def wet(on, h, extra=()):
    """Wet skin and hair: a thin glossy coat, the hair darker and shiny."""
    for o in [h] + list(extra) + list(h.children) + [c for c in bpy.data.objects if c.parent and c.parent.type == 'ARMATURE']:
        if o.type != 'MESH':
            continue
        for ms in o.material_slots:
            m = ms.material
            if not m or not m.node_tree:
                continue
            for n in m.node_tree.nodes:
                if n.type == 'BSDF_PRINCIPLED':
                    if "Coat Weight" in n.inputs:
                        n.inputs["Coat Weight"].default_value = 0.7 if on else 0.0
                    if "Coat Roughness" in n.inputs:
                        n.inputs["Coat Roughness"].default_value = 0.08


def bathroom(back_y, floor=True):
    blue = material("Wall tiles", (1, 1, 1), 0.45, image=tex_image("wall_tiles", tiles(0.2, (0.72, 0.84, 0.9))), coat=0.1)
    plane("Wall", (0, back_y, 1.5), (4, 3), (math.pi / 2, 0, 0), blue)
    if floor:
        grey = material("Floor tiles", (1, 1, 1), 0.35, image=tex_image("floor_tiles", tiles(0.3, (0.6, 0.62, 0.63), per=3, seed=4)))
        plane("Floor", (0, back_y - 1.5, 0), (4, 3), (0, 0, 0), grey)
    steel = material("Tap steel", (0.8, 0.8, 0.82), 0.15, 1.0)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.025, depth=0.16, location=(0.75, back_y - 0.08, 1.0), rotation=(math.pi / 2, 0, 0))
    bpy.context.object.data.materials.append(steel)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=0.05, location=(0.75, back_y - 0.03, 1.08))
    bpy.context.object.data.materials.append(steel)


# ---- brushing: head and shoulders, like looking in the mirror ----
def brush():
    C.clear()
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    arm, h, _ = karthik("bath")                         # bare-chested, as men brush in the morning
    head = C.head_of(arm, "head")
    bake_pose(arm)
    drop_face_parts(arm)
    g = Gnm(h)
    g.grow_hair()
    setup_render()
    bathroom(head.y + 0.55, floor=False)
    eye = Vector((0, head.y, head.z + 0.04))
    cam = camera((0.02, head.y - 1.05, head.z + 0.06), (0, head.y, head.z + 0.02), 55)
    light("Key", (-0.6, head.y - 0.9, head.z + 0.5), 30, 0.9, (1.0, 0.95, 0.88), eye)
    light("Fill", (0.8, head.y - 0.7, head.z + 0.1), 6, 1.2, (0.9, 0.95, 1.0), eye)
    light("Rim", (0.3, head.y + 0.5, head.z + 0.4), 14, 0.5, (1, 1, 1), eye)
    meta = {}
    only = os.environ.get("GROOM_FACES", "")                       # (testing: a few faces only)
    for name, units in BRUSH.items():
        if only and name not in only.split(","):
            continue
        g.face(units)
        if name == "open":
            pts = project(cam, g.teeth_points())
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            meta["teeth"] = [min(xs), min(ys), max(xs), max(ys)]
        render(os.path.join(OUT, "brush_%s.jpg" % name))
    hp = project(cam, [head + Vector((0, -0.05, 0.08))])[0]
    meta["head"] = list(hp)
    return meta


# ---- bathing: on the stool, bare to the waist, the bucket beside him ----
def bath():
    C.clear()
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    arm, h, _ = karthik("bath")
    C.sit(arm)
    bpy.context.view_layer.update()
    hip = (C.head_of(arm, "thigh_l") + C.head_of(arm, "thigh_r")) / 2
    head = C.head_of(arm, "head")
    bake_pose(arm)
    drop_face_parts(arm)
    g = Gnm(h)
    g.grow_hair()
    setup_render()
    bathroom(hip.y + 0.9)
    red = material("Stool", (0.7, 0.08, 0.06), 0.4)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.2, depth=0.06, location=(0, hip.y + 0.05, hip.z - 0.1))
    bpy.context.object.data.materials.append(red)
    for sx in (-1, 1):
        for sy in (-1, 1):
            bpy.ops.mesh.primitive_cylinder_add(radius=0.02, depth=hip.z - 0.12, location=(sx * 0.13, hip.y + 0.05 + sy * 0.13, (hip.z - 0.12) / 2))
            bpy.context.object.data.materials.append(red)
    # the bucket of water, on his left (the picture's right)
    blue = material("Bucket", (0.1, 0.35, 0.75), 0.35)
    bpy.ops.mesh.primitive_cone_add(vertices=48, radius1=0.2, radius2=0.25, depth=0.42, location=(0.75, hip.y - 0.15, 0.21))
    bpy.context.object.data.materials.append(blue)
    water = material("Water", (0.35, 0.6, 0.8), 0.05, coat=1.0)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.235, depth=0.01, location=(0.75, hip.y - 0.15, 0.38))
    bpy.context.object.data.materials.append(water)
    mid = Vector((0.18, hip.y, (hip.z + head.z) / 2 - 0.12))
    cam = camera((0.18, hip.y - 2.05, mid.z + 0.25), mid, 35)
    near = Vector((0.0, hip.y, head.z - 0.2))                        # the close framing: his face and chest
    cams = {"": (cam.location.copy(), mid), "_close": (Vector((0.04, hip.y - 1.4, head.z - 0.05)), near)}
    light("Key", (-1.0, hip.y - 1.4, head.z + 0.6), 70, 1.2, (1.0, 0.95, 0.88), head)
    light("Fill", (1.2, hip.y - 1.2, head.z), 25, 1.6, (0.9, 0.95, 1.0), head)
    light("Top", (0, hip.y - 0.3, head.z + 1.0), 20, 1.0, (1, 1, 1), hip)
    def frame(key):
        at, look = cams[key]
        cam.location = at
        cam.rotation_euler = (Vector(look) - Vector(at)).to_track_quat('-Z', 'Y').to_euler()
        bpy.context.view_layer.update()
    for state in ("dry", "wet"):
        wet(state == "wet", h, [g.head])
        for name, units in BATH.items():
            g.face(units)
            for key in cams:
                frame(key)
                render(os.path.join(OUT, "bath_%s_%s%s.jpg" % (name, state, key)))
    # the mask: white where he is, black elsewhere
    white = material("MaskWhite", (0, 0, 0), 1.0, emit=(1, 1, 1), strength=1.0)
    black = material("MaskBlack", (0, 0, 0), 1.0)
    him = {h.name, g.head.name}
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        on_him = o.name in him or (o.parent is not None and o.parent.type == 'ARMATURE')
        o.data.materials.clear() if o.data.users == 1 else None
        for i in range(len(o.material_slots)):
            o.material_slots[i].material = white if on_him else black
        if not o.material_slots:
            o.data.materials.append(white if on_him else black)
    bpy.context.scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.0
    for o in [o for o in bpy.data.objects if o.type == 'LIGHT']:
        o.hide_render = True
    bpy.context.scene.view_settings.view_transform = 'Standard'
    out = {}
    for key in cams:                                                # the mask and the points, per framing
        frame(key)
        render(os.path.join(OUT, "bath_mask%s.png" % key), jpg=False)
        hp = project(cam, [head + Vector((0, -0.04, 0.08))])[0]
        out["head" + key] = list(hp)
        out["hip" + key] = list(project(cam, [hip])[0])           # (with the head: maps one framing onto the other)
    out["head_r"] = 0.057
    return out


# ---- the props: each alone, lit, on a transparent ground ----
def props():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    setup_render(transparent=True)
    sc = bpy.context.scene
    sc.render.resolution_x = sc.render.resolution_y = 256
    cam = camera((0, -1.0, 0), (0, 0, 0), 50)
    cam.data.type = 'ORTHO'
    light("Key", (-1, -1.5, 1.2), 70, 1.5, (1, 0.97, 0.92), (0, 0, 0))
    light("Fill", (1.2, -1, 0.2), 15, 1.5, (0.9, 0.95, 1), (0, 0, 0))

    def shoot(name, scale):
        cam.data.ortho_scale = scale
        render(os.path.join(OUT, "prop_%s.png" % name), jpg=False)
        for o in [o for o in bpy.data.objects if o.type == 'MESH']:
            bpy.data.objects.remove(o, do_unlink=True)

    def cyl(r, d, loc, rot, m, r2=None, verts=32):
        if r2 is None:
            bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=d, location=loc, rotation=rot)
        else:
            bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=d, location=loc, rotation=rot)
        o = bpy.context.object
        o.data.materials.append(m)
        bpy.ops.object.shade_smooth()
        return o

    def cube(loc, size, m, bev=0.004):
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
        o = bpy.context.object
        o.scale = size
        o.data.materials.append(m)
        if bev:
            md = o.modifiers.new("B", 'BEVEL')
            md.width = bev
            md.segments = 3
        return o
    blue = material("Brush blue", (0.1, 0.45, 0.9), 0.25, coat=0.5)
    white = material("Bristle", (0.95, 0.97, 1.0), 0.6)
    paste = material("Paste", (0.97, 0.98, 1.0), 0.3)
    stripe = material("Paste stripe", (0.2, 0.55, 1.0), 0.3)
    for with_paste in (False, True):
        # a toothbrush: a slim curved handle with a rubber grip, a thin neck, the head with rows of bristle tufts
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.0075, depth=0.13, location=(0.035, 0, 0), rotation=(0, math.pi / 2, 0))
        hdl = bpy.context.object
        hdl.scale = (1.0, 1.5, 1.0)
        hdl.data.materials.append(blue)
        bpy.ops.object.shade_smooth()
        cube((0.05, 0, 0.0), (0.05, 0.016, 0.017), material("Grip", (0.15, 0.75, 0.85), 0.6), 0.007)
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.004, depth=0.04, location=(-0.045, 0, 0.003), rotation=(0, math.pi / 2 + 0.12, 0))
        bpy.context.object.data.materials.append(blue)
        cube((-0.08, 0, 0.004), (0.032, 0.013, 0.006), blue, 0.003)
        for i in range(6):                                          # the bristle tufts, white and blue rows
            for j in (-1, 0, 1):
                cyl(0.0022, 0.012, (-0.094 + i * 0.0055, j * 0.0042, 0.013), (0, 0, 0), white if j else stripe, verts=8)
        if with_paste:
            for k in range(5):
                cyl(0.0045, 0.006, (-0.093 + k * 0.006, 0, 0.022 + 0.002 * math.sin(k)), (math.pi / 2, 0, 0), paste if k % 2 else stripe, verts=16)
        shoot("brush_paste" if with_paste else "brush", 0.2)
    red = material("Tube red", (0.8, 0.1, 0.1), 0.35)
    tw = material("Tube white", (0.95, 0.95, 0.94), 0.35)
    cyl(0.022, 0.11, (0.01, 0, 0), (0, math.pi / 2, 0), tw, r2=0.016)
    cube((-0.06, 0, 0), (0.012, 0.05, 0.03), red, 0.003)
    cyl(0.011, 0.02, (0.07, 0, 0), (0, math.pi / 2, 0), material("Cap", (0.15, 0.35, 0.8), 0.3))
    shoot("tube", 0.2)
    steel = material("Steel", (0.82, 0.83, 0.85), 0.18, 1.0)
    cyl(0.035, 0.1, (0, 0, 0), (0, 0, 0), steel, r2=0.04, verts=48)
    shoot("tumbler", 0.16)
    orange = material("Mug", (0.95, 0.4, 0.15), 0.3, coat=0.4)
    cyl(0.045, 0.1, (0, 0, 0), (0, 0, 0), orange, verts=48)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.03, minor_radius=0.008, location=(0.055, 0, 0.0), rotation=(math.pi / 2, 0, 0))
    bpy.context.object.data.materials.append(orange)
    cyl(0.04, 0.004, (0, 0, 0.045), (0, 0, 0), material("Mug water", (0.4, 0.65, 0.85), 0.05, coat=1.0), verts=48)
    shoot("mug", 0.17)
    soap = material("Soap", (0.95, 0.62, 0.48), 0.4, coat=0.3)
    cube((0, 0, 0), (0.09, 0.025, 0.055), soap, 0.02)                   # a rounded bar of sandal soap
    cube((0, -0.013, 0), (0.05, 0.002, 0.02), material("Soap mark", (0.85, 0.5, 0.38), 0.4), 0.004)
    shoot("soap", 0.13)
    towel = material("Towel", (0.96, 0.96, 0.93), 0.95)
    cube((0, 0, 0), (0.12, 0.03, 0.14), towel, 0.01)
    for k in range(3):
        cube((0, -0.016, -0.03 + k * 0.012), (0.121, 0.002, 0.004), material("Towel line", (0.75, 0.15, 0.12), 0.8), 0)
    shoot("towel", 0.2)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = args[args.index("--only") + 1] if "--only" in args else "all"
    os.makedirs(OUT, exist_ok=True)
    jpath = os.path.join(OUT, "groom.json")
    meta = json.load(open(jpath)) if os.path.exists(jpath) else {}
    if only in ("all", "props"):
        props()
    if only in ("all", "brush"):
        meta["brush"] = brush()
    if only in ("all", "bath"):
        meta["bath"] = bath()
    json.dump(meta, open(jpath, "w"), indent=1)
    print("GROOM meta", meta, flush=True)


if __name__ == "__main__":
    main()
