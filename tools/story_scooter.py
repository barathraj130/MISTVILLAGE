"""
Karthik's scooter for the story's night delivery (docs/STORY_BIBLE.md): the detailed 110 cc step-through of the rider
scenes (tools/bikes_real.py) in his own paint, exported for the game as godot/assets/vehicles/karthik_scooter.glb
(nose along +X, wheels "Wheel_F" / "Wheel_R", the glb vehicle loader in scripts/drive/jeep.gd), and his full-face
helmet (tools/rider_real.py's) as godot/assets/vehicles/helmet.glb: its origin at the centre of the head, facing the
way the person faces. Prints the helmet's offset from the head bone in the Ride pose (scripts/drive/jeep.gd puts it
there), and renders Karthik riding it (the story cast's Ride clip) to check the design.

Needs the MPFB add-on (no --factory-startup):
    Blender -b --python tools/story_scooter.py -- [--render previews/story_scooter]
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "humans"))
import bikes_real as BR  # noqa: E402
import story_cast as C  # noqa: E402

OUT = os.path.join(HERE, "..", "godot", "assets", "vehicles")
PAINT = (0.16, 0.2, 0.28)                 # a dusky blue-grey, a few years old
SHELL = (0.05, 0.05, 0.055)               # a black helmet with white stripes


def rider_real():
    """tools/rider_real.py as a library (its helmet), set to the scooter, without running its scene."""
    path = os.path.join(HERE, "rider_real.py")
    src = open(path).read()
    src = src.replace('VEHICLE = "motorcycle"', 'VEHICLE = "scooter"', 1)
    src = src.replace("SHELL = (0.62, 0.03, 0.04)", "SHELL = %r" % (SHELL,), 1)
    src = src[:src.rindex("\nmain()")]
    ns = {"__name__": "rider_real_lib", "__file__": path}
    exec(compile(src, path, "exec"), ns)
    return ns


def select_tree(root):
    bpy.ops.object.select_all(action='DESELECT')
    stack = [root]
    while stack:
        o = stack.pop()
        o.select_set(True)
        stack.extend(o.children)
    bpy.context.view_layer.objects.active = root


def export(root, name):
    select_tree(root)
    path = os.path.abspath(os.path.join(OUT, name))
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_image_format='JPEG')
    print("SCOOTER", name, "%.1f MB" % (os.path.getsize(path) / 1e6), flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    RR = rider_real()
    RR["RS"]["clear"]()
    # the scooter, exported on its own
    root = bpy.data.objects.new("KarthikScooter", None)
    bpy.context.collection.objects.link(root)
    BR.build("scooter", root, PAINT)
    export(root, "karthik_scooter.glb")
    # Karthik in the Ride pose (the cast's own clip pose)
    spec = [c for c in C.CAST if c[0] == "karthik"][0]
    arm, objs = C.build(spec)
    C.rest(arm)
    C.arms_down(arm)
    C.ride(arm)
    hip_h = (C.head_of(arm, "thigh_l") + C.head_of(arm, "thigh_r")) / 2
    head = C.head_of(arm, "head")
    up = (C.tail_of(arm, "head") - head).normalized()
    eyes_o = [o for o in objs if o.type == 'MESH' and o.name.endswith(".low-poly")]      # MakeHuman's eyes
    dg = bpy.context.evaluated_depsgraph_get()
    if eyes_o:
        ev = eyes_o[0].evaluated_get(dg)
        vs = [ev.matrix_world @ v.co for v in ev.data.vertices]
        eyes = sum(vs, Vector()) / len(vs)
    else:
        eyes = head + up * 0.1 + Vector((0, -0.09, 0))
    fwd = Vector((0, -1, 0))
    fwd = (fwd - up * fwd.dot(up)).normalized()
    centre = eyes - fwd * 0.105 + up * 0.004                       # the helmet's eye port at the eyes
    off = centre - head                                             # in the person's frame (left +X, forward -Y)
    print("HELMET offset from the head bone (Blender, person frame): (%.4f, %.4f, %.4f)" % tuple(off), flush=True)
    print("HELMET godot offset: Vector3(%.4f, %.4f, %.4f)" % (off.x, off.z, -off.y), flush=True)
    print("RIDE hip point (person frame): (%.4f, %.4f, %.4f)" % tuple(hip_h), flush=True)
    # the helmet, built facing +X at the origin, turned to face the person's way (-Y) and exported
    hel = RR["helmet"](RR["mats"]())
    hel.matrix_world = Matrix.Rotation(-math.pi / 2, 4, 'Z')
    # the shell's colour comes from the stripes shader (a Blender node effect that doesn't export): give the game
    # the plain paint, and the stripes as their own white material on the graphic faces already there
    for m in bpy.data.materials:
        if m.name.startswith("Helmet Paint") and m.node_tree:
            b = m.node_tree.nodes.get("Principled BSDF")
            for ln in list(b.inputs["Base Color"].links):
                m.node_tree.links.remove(ln)
            b.inputs["Base Color"].default_value = (*SHELL, 1)
    export(hel, "helmet.glb")
    # the design check: him on the scooter in the helmet, on the rider scenes' street
    if "--render" in args:
        place = Matrix.Translation(BR.FIT["scooter"]["hip"]) @ Matrix.Rotation(math.pi / 2, 4, 'Z') @ Matrix.Translation(-hip_h)
        for o in objs + [arm]:
            if o.parent is None:
                o.matrix_world = place @ o.matrix_world
        hel.matrix_world = place @ Matrix.Translation(centre) @ Matrix.Rotation(-math.pi / 2, 4, 'Z')
        RR["RS"]["R"] = BR.FIT["scooter"]["r"]
        RR["street"]()
        RR["sky"]()
        sc = bpy.context.scene
        out = os.path.abspath(args[args.index("--render") + 1])
        os.makedirs(out, exist_ok=True)
        sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [e.identifier for e in sc.render.bl_rna.properties["engine"].enum_items] else 'BLENDER_EEVEE'
        sc.render.resolution_x, sc.render.resolution_y = 1280, 900
        sc.render.image_settings.file_format = 'JPEG'
        cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
        for name, at, look, lens in (("side", (0.0, -3.4, 1.0), (0.0, 0.0, 0.85), 40),
                                     ("front", (2.9, -1.6, 1.35), (0.0, 0.0, 0.95), 45),
                                     ("close", (0.9, -1.1, 1.55), (0.05, 0.0, 1.25), 40),
                                     ("hands", (0.75, -0.55, 1.3), (0.33, 0.0, 1.05), 50)):
            cam.location = at
            cam.data.lens = lens
            cam.rotation_euler = (Vector(look) - Vector(at)).to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(out, "karthik_scooter_%s.jpg" % name)
            bpy.ops.render.render(write_still=True)
            print("PREVIEW", sc.render.filepath, flush=True)


if __name__ == "__main__":
    main()
