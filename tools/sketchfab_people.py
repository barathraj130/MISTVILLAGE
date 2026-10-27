"""
Sketchfab people for the street crowd (mapdata/sketchfab/people, credited in docs/DATA_SOURCES.md) made like the
city's own street people (godot/assets/people/street_*.glb): one posed, static mesh standing on its origin, facing
-Y, thinned for crowds (TRIS), textures at most 1024 px. Arms come down from the T / A pose (the upper arms turned to
hang beside the body, the forearms a little bent); a model with its own idle takes that frame instead.

    Blender -b --factory-startup --python tools/sketchfab_people.py -- [names...] [--preview DIR] [--no-export]

Writes godot/assets/people/sf_<name>.glb; the city streamer mixes them into the crowd (city_streamer.gd SF_PEOPLE).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "mapdata", "sketchfab", "people")
OUT = os.path.join(ROOT, "godot", "assets", "people")
TRIS = 9000
TRIS_MORE = {"woman_saree_green": 24000}     # her blouse and pleats tear when thinned that far

# name: (file, height m, pose: "arms" | frame of its own animation, turn: degrees about Z; they face -Y as imported, like
# the city's own street people)
PEOPLE = {
    "man_kurta_blue": ("indian-man-with-blue-clothes", 1.70, "arms", 0),
    "man_kurta_red": ("indian-man-with-red-clothes", 1.68, "arms", 0),
    "man_suit": ("indian-man-with-suit", 1.74, 40, 0),
    "man_office": ("eric_rigged_001_-_rigged_3d_business_man", 1.75, "arms", 0),
    "woman_saree_green": ("indian_woman_in_saree", 1.58, 0, 0),
    "woman_office": ("claudia_rigged_002_-_3d_rigged_business_women", 1.60, "arms", 0),
    "woman_office2": ("carla_rigged_001_-_rigged_3d_business_women", 1.58, "arms", 0),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def arm_bones(arm):
    """The upper and lower arm bones of each side, whatever the rig calls them (Mixamo, Renderpeople, Maya)."""
    found = {}
    for b in arm.pose.bones:
        n = b.name.lower().replace("mixamorig:", "")
        side = "l" if ("left" in n or "_l_" in n or n.endswith("_l")) else ("r" if ("right" in n or "_r_" in n or n.endswith("_r")) else None)
        if side is None or "twist" in n or "hand" in n or "shoulder" in n or "clav" in n:
            continue
        if ("forearm" in n or "lowerarm" in n) and "forearm1" not in n and "forearm2" not in n:
            found.setdefault(side + "_fore", b)
        elif "upperarm" in n or n.split("_")[0] in ("leftarm", "rightarm"):
            found.setdefault(side + "_upper", b)
    return found


def aim(arm, pb, tip, target_dir):
    """Turn a pose bone about its head so the joint after it (tip: the child bone whose head is the elbow / wrist)
    lies along target_dir (world space). glTF rigs import with guessed bone tails, so the child is the real line."""
    mw = arm.matrix_world
    head = mw @ pb.head
    cur = ((mw @ tip.head) - head).normalized()
    rot = cur.rotation_difference(target_dir.normalized()).to_matrix().to_4x4()
    world = mw @ pb.matrix
    new_world = Matrix.Translation(head) @ rot @ Matrix.Translation(-head) @ world
    pb.matrix = mw.inverted() @ new_world
    bpy.context.view_layer.update()


def child_named(pb, *parts):
    return next((c for c in pb.children if any(p in c.name.lower() for p in parts) and "twist" not in c.name.lower()), None)


def build(name):
    file, height, pose, turn = PEOPLE[name]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, file + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    arm = next((o for o in new if o.type == 'ARMATURE'), None)
    for o in new:
        if o.animation_data and pose == "arms":
            o.animation_data.action = None
    if arm is not None and pose == "arms":
        arm.data.pose_position = 'POSE'
        for b in arm.pose.bones:
            b.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        bones = arm_bones(arm)
        mw = arm.matrix_world
        for side, sx in (("l", 1.0), ("r", -1.0)):
            up, fore = bones.get(side + "_upper"), bones.get(side + "_fore")
            if up is None:
                print("NO ARM", name, side, flush=True)
                continue
            fore = fore or child_named(up, "fore", "lowerarm")
            if fore is None:
                print("NO FOREARM", name, side, flush=True)
                continue
            # which way is out: the side the elbow is on now (away from the body's middle)
            sgn = 1.0 if (mw @ fore.head).x - (mw @ up.head).x > 0 else -1.0
            aim(arm, up, fore, Vector((0.18 * sgn, -0.02, -1.0)))
            hand = child_named(fore, "hand", "fore")             # (Maya-style rigs chain forearm1 / forearm2)
            if hand is not None:
                aim(arm, fore, hand, Vector((0.08 * sgn, -0.2, -1.0)))
    elif arm is not None:
        bpy.context.scene.frame_set(int(pose))
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    meshes = [o for o in new if o.type == 'MESH' and o.visible_get() and not o.hide_render and o.data.polygons]
    baked = []
    for o in meshes:
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        me.transform(o.matrix_world)
        ob = bpy.data.objects.new(o.name + "_baked", me)
        bpy.context.scene.collection.objects.link(ob)
        baked.append(ob)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in baked:
        o.select_set(True)
    bpy.context.view_layer.objects.active = baked[0]
    if len(baked) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = "sf_" + name
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    budget = TRIS_MORE.get(name, TRIS)
    if tris > budget:
        md = ob.modifiers.new("thin", 'DECIMATE')
        md.ratio = budget / tris
        bpy.ops.object.modifier_apply(modifier=md.name)
    vs = [v.co for v in ob.data.vertices]
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    k = height / (hi.z - lo.z)
    feet = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    ob.data.transform(Matrix.Rotation(math.radians(turn), 4, 'Z') @ Matrix.Scale(k, 4) @ Matrix.Translation(-feet))
    for m in ob.data.materials:
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                im = getattr(n, "image", None)
                if im is not None and max(im.size) > 1024:
                    im.scale(*(max(1, v * 1024 // max(im.size)) for v in im.size))
    print("PERSON %s %d tris, %.2f m" % (name, sum(len(p.vertices) - 2 for p in ob.data.polygons), height), flush=True)
    return ob


def preview(out, obs):
    """All of them in a row, seen from in front (-Y, the way they face) and three-quarter."""
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
    sc.view_settings.view_transform = "Standard"
    sc.render.image_settings.file_format = 'JPEG'
    bpy.ops.mesh.primitive_plane_add(size=60)
    g = bpy.context.object
    gm = bpy.data.materials.new("ground")
    gm.diffuse_color = (0.5, 0.48, 0.45, 1)
    g.data.materials.append(gm)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(160))
    sc.collection.objects.link(sun)
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.7, 0.78, 0.9, 1)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 50
    span = (len(obs) - 1) * 0.9
    for i, ob in enumerate(obs):
        ob.location.x = i * 0.9 - span / 2
    for k, (ang, tag) in enumerate(((90, "front"), (45, "three_quarter"))):
        a = math.radians(ang)
        d = max(span, 2.0) * 1.25 + 2.5
        cam.location = Vector((math.cos(a) * d * 0.35, -math.sin(a) * d, 1.1))
        cam.rotation_euler = (Vector((0, 0, 0.85)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(out, "people_%s.jpg" % tag)
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", sc.render.filepath, flush=True)


def export(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    path = os.path.join(OUT, ob.name + ".glb")
    loc = ob.location.copy()
    ob.location = (0, 0, 0)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_image_format='JPEG')
    ob.location = loc
    print("EXPORT", path, "%.1f MB" % (os.path.getsize(path) / 1e6), flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    prev = args[args.index("--preview") + 1] if "--preview" in args else None
    names = [a for a in args if a in PEOPLE] or list(PEOPLE)
    reset()
    obs = []
    for n in names:
        obs.append(build(n))
    if "--no-export" not in args:
        for ob in obs:
            export(ob)
    if prev:
        os.makedirs(prev, exist_ok=True)
        preview(os.path.abspath(prev), obs)


if __name__ == "__main__":
    main()
