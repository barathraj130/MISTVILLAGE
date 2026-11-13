"""
Karthik's morning clips (docs/MORNING_ROUTINE_AUDIT.md), on his own rig, for the bathroom at home
(scripts/story/brush3d.gd). Built on story_cast.py's Karthik (the same body, so the same bone lengths) and its IK
helpers, but exported ALONE: the armature with the clips and one hidden triangle (so Godot makes a Skeleton3D of it),
as godot/assets/people/story_karthik_morning.glb. The game adds these clips to his own AnimationPlayer; his model
(story_karthik.glb) isn't rebuilt or changed. The character faces -Y, his left is +X.
    Reach      the right hand out to the shelf in front, about chest height: taking the brush, putting it back
    BrushHold  the brush held in front of his chest in the right hand, looking at it (the paste goes on), breathing
    Brush      brushing: the brush in his mouth from the right, scrubbing three strokes a second, the head moving
               with it; the left arm hanging
    Rinse      3 s: the tumbler (left hand) to his mouth, a mouthful; head back, a gargle; leaning forward to spit
               into the drain; up again
    Blender -b --python tools/humans/story_morning.py -- [--strip DIR]   (--strip: pictures of each clip to judge)
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import story_cast as SC  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "godot", "assets", "people", "story_karthik_morning.glb")


def arm_to(a, side, wrist, pole, point):
    """The arm's wrist to `wrist` (two-bone IK, the elbow toward `pole`), the hand pointing at `point`."""
    sh = SC.head_of(a, "upperarm_" + side)
    el0, wr0 = SC.head_of(a, "lowerarm_" + side), SC.head_of(a, "hand_" + side)
    elbow = SC.two_bone(sh, wrist, (el0 - sh).length, (wr0 - el0).length, pole)
    SC.aim(a, "upperarm_" + side, lambda: SC.head_of(a, "lowerarm_" + side), elbow)
    SC.aim(a, "lowerarm_" + side, lambda: SC.head_of(a, "hand_" + side), wrist)
    mid = "middle_01_" + side
    if mid in a.pose.bones:
        SC.aim(a, "hand_" + side, lambda: SC.head_of(a, mid), point)


def grip(a, side):                                       # fingers closed round a handle, the thumb along it
    SC.curl_fingers(a, side, 76.0, 42.0)


def breathe(a, k):
    SC.turn(a, "spine_02", 'X', -1.4 * k)
    SC.turn(a, "spine_03", 'X', -0.7 * k)


def mouth(a):
    return SC.head_of(a, "head") + Vector((0.0, -0.11, -0.02))


def reach(a):
    SC.turn(a, "spine_01", 'X', 6.0)
    SC.turn(a, "head", 'X', 10.0)
    sh = SC.head_of(a, "upperarm_r")
    w = sh + Vector((0.08, -0.42, -0.1))
    arm_to(a, "r", w, Vector((-0.9, 0.3, -0.6)), w + Vector((0.0, -0.1, -0.02)))
    grip(a, "r")


def brush_hold(a, k):
    breathe(a, k)
    SC.turn(a, "neck_01", 'X', 8.0)
    SC.turn(a, "head", 'X', 14.0)                        # looking down at the brush
    chest = SC.head_of(a, "spine_03")
    w = chest + Vector((-0.02, -0.33, 0.1))
    arm_to(a, "r", w, Vector((-0.9, 0.2, -0.7)), w + Vector((0.09, -0.03, 0.0)))   # the brush across, its head left
    grip(a, "r")


def brush(a, t):
    """t in [0, 1): three strokes; the head turns a little against the hand, the chin up."""
    s = math.sin(2.0 * math.pi * 3.0 * t)
    SC.turn(a, "head", 'X', -4.0)
    SC.turn(a, "head", 'Z', 3.0 * math.sin(2.0 * math.pi * t) - 1.5 * s)
    SC.turn(a, "spine_02", 'X', -1.0 * math.cos(2.0 * math.pi * t))
    m = mouth(a)
    w = m + Vector((-0.2 + 0.022 * s, -0.04, -0.035 + 0.006 * math.cos(2.0 * math.pi * 3.0 * t)))
    arm_to(a, "r", w, Vector((-0.5, 0.1, -1.0)), m + Vector((0.0, -0.02, -0.035)))
    grip(a, "r")


def _ease(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def rinse(a, t):
    """t in [0, 1] over 3 s: 0–0.2 the tumbler up to the mouth; 0.2–0.32 a mouthful; 0.32–0.42 down to the chest,
    head back; 0.42–0.66 gargling; 0.66–0.82 leaning forward to spit; 0.82–1 up, the tumbler at the chest."""
    up = _ease(t / 0.2) * (1.0 - _ease((t - 0.32) / 0.1))           # the tumbler at the mouth
    back = _ease((t - 0.32) / 0.1) * (1.0 - _ease((t - 0.62) / 0.06))   # the head tipped back
    spit = _ease((t - 0.66) / 0.08) * (1.0 - _ease((t - 0.84) / 0.14))  # leaning over the drain
    wob = math.sin(2.0 * math.pi * 7.0 * t) * (1.0 if 0.42 < t < 0.64 else 0.0)
    SC.turn(a, "spine_01", 'X', 28.0 * spit)
    SC.turn(a, "spine_02", 'X', 10.0 * spit - 4.0 * back)
    SC.turn(a, "neck_01", 'X', -16.0 * back + 12.0 * spit)
    SC.turn(a, "head", 'X', -14.0 * back - 6.0 * up + 10.0 * spit + 1.5 * wob)
    m = mouth(a)
    chest = SC.head_of(a, "spine_03") + Vector((0.08, -0.26, -0.06))
    w = chest.lerp(m + Vector((0.03, -0.07, -0.11)), up)
    arm_to(a, "l", w, Vector((0.9, 0.3, -0.7)), w + Vector((-0.06, -0.06, 0.03 + 0.06 * up)))
    grip(a, "l")


def morning(arm):
    SC.clip(arm, "Reach", [(1, reach), (25, reach)])
    SC.clip(arm, "BrushHold", [(1, lambda a: brush_hold(a, -1)), (25, lambda a: brush_hold(a, 1)),
                               (49, lambda a: brush_hold(a, -1))])
    SC.clip(arm, "Brush", [(1 + k, (lambda kk: (lambda a: brush(a, kk / 24.0)))(k % 24)) for k in range(25)])
    SC.clip(arm, "Rinse", [(1 + 2 * k, (lambda kk: (lambda a: rinse(a, kk / 36.0)))(k)) for k in range(37)])
    for tr in arm.animation_data.nla_tracks:
        tr.mute = False


def strip(arm, objs, out_dir):
    """Each clip at a few moments, from his front right (Eevee): <clip>_<n>.jpg."""
    sc = bpy.context.scene
    for tr in (arm.animation_data.nla_tracks if arm.animation_data else []):
        tr.mute = True
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [e.identifier for e in sc.render.bl_rna.properties["engine"].enum_items] else 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 600, 700
    sc.render.image_settings.file_format = 'JPEG'
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.data.lens = 40
    cam.location = (-1.1, -1.6, 1.55)
    cam.rotation_euler = (Vector((0, 0, 1.25)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    os.makedirs(out_dir, exist_ok=True)
    for name, fn, ts in (("reach", lambda a, t: reach(a), [0]), ("hold", lambda a, t: brush_hold(a, 1), [0]),
                         ("brush", brush, [0.0, 1 / 12.0]), ("rinse", rinse, [0.1, 0.25, 0.5, 0.75])):
        for i, t in enumerate(ts):
            SC.rest(arm)
            SC.arms_down(arm)
            fn(arm, t)
            sc.render.filepath = os.path.join(out_dir, "%s_%d.jpg" % (name, i))
            bpy.ops.render.render(write_still=True)
    print("STRIP", out_dir, flush=True)


def export(arm):
    """The armature and its clips, and one tiny triangle weighted to the pelvis (hidden inside him)."""
    me = bpy.data.meshes.new("morning_anchor")
    me.from_pydata([(0, 0, 1.0), (0.001, 0, 1.0), (0, 0.001, 1.0)], [], [(0, 1, 2)])
    o = bpy.data.objects.new("morning_anchor", me)
    bpy.context.scene.collection.objects.link(o)
    o.parent = arm
    vg = o.vertex_groups.new(name="pelvis")
    vg.add([0, 1, 2], 1.0, 'REPLACE')
    o.modifiers.new("Armature", 'ARMATURE').object = arm
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(OUT), export_format='GLB', use_selection=True,
                              export_yup=True, export_skins=True, export_animations=True,
                              export_animation_mode='NLA_TRACKS')
    print("MORNING", os.path.abspath(OUT), "%.2f MB" % (os.path.getsize(os.path.abspath(OUT)) / 1e6), flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    c = [c for c in SC.CAST if c[0] == "karthik"][0]
    SC.clear()
    SC.stride = SC.STRIDE.get(c[9], 1.0)
    arm, objs = SC.build(c)
    print("MORNING rig", arm.name, flush=True)
    if "--strip" in args:
        strip(arm, objs, os.path.abspath(args[args.index("--strip") + 1]))
        return
    for o in objs:                                     # (only the armature goes out)
        if o.name in bpy.data.objects and o != arm:
            o.hide_render = True
    morning(arm)
    export(arm)


if __name__ == "__main__":
    main()
