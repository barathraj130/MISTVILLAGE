"""
More things for the city's crowd to do (docs/WORLD_LIFE_AUDIT_2026-11-13.md: nobody on a phone, nobody carrying
anything): clips on the crowd's own rig (crowd_cast.py, the game rig), built on one man (m1) and one woman (w1) so
the arm reaches suit each, exported ALONE (the armature, its clips and one hidden triangle, as story_morning.py
does) as godot/assets/people/crowd_clips_m.glb and crowd_clips_w.glb. scripts/city/crowd_clips.gd adds them to any
crowd person's AnimationPlayer (the tracks moved onto that person's skeleton) and puts the phone or the bag in the
hand.
    Phone      standing, the phone to the right ear: listening, a word now and then (a small nod), weight shifting
    PhoneLook  standing, looking down at the phone held before the chest in the right hand, the thumb on it
    WalkPhone  walking (the cast's Walk) with the phone to the ear: the right arm still, the head a little tilted
    WalkCarry  walking with a cloth bag in the right hand: that arm hangs straight and hardly swings
    Blender -b --python tools/humans/crowd_clips.py -- [--strip DIR]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import story_cast as SC  # noqa: E402
import story_morning as SM  # noqa: E402
import crowd_cast as CC  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "godot", "assets", "people")


def ear(a):
    return SC.head_of(a, "head") + Vector((-0.085, -0.02, 0.03))       # his right ear (-X is his right)


def phone_arm(a):
    e = ear(a)
    w = e + Vector((-0.015, -0.055, -0.1))             # the wrist below the jaw, a little ahead of it
    SM.arm_to(a, "r", w, Vector((-0.25, -0.8, -1.0)), e + Vector((0.01, 0.01, 0.03)))   # the elbow down, in front
    SM.grip(a, "r")


def phone(a, k):
    SC.idle(a, k)
    SC.turn(a, "head", 'Y', 6.0)                       # the head leaning a little to the phone
    SC.turn(a, "head", 'X', 3.0 * k)                   # a nod with the words
    phone_arm(a)


def phone_look(a, k):
    SC.idle(a, k * 0.6)
    SC.turn(a, "neck_01", 'X', 12.0)
    SC.turn(a, "head", 'X', 16.0)
    chest = SC.head_of(a, "spine_03")
    w = chest + Vector((-0.06, -0.26, -0.06))
    SM.arm_to(a, "r", w, Vector((-0.9, 0.2, -0.8)), w + Vector((0.06, -0.06, 0.03)))
    SC.curl_fingers(a, "r", 45.0, 15.0 + 10.0 * k)     # the thumb moving on the screen


def walk_phone(a, t):
    SC.walk_phase(a, t)
    SC.turn(a, "head", 'Y', 6.0)
    phone_arm(a)


def walk_carry(a, t):
    SC.walk_phase(a, t)
    sh = SC.head_of(a, "upperarm_r")                   # the bag's weight: the arm straight down, a little out
    w = sh + Vector((-0.07, 0.01 + 0.025 * math.sin(2.0 * math.pi * t), -0.52))
    SM.arm_to(a, "r", w, Vector((-0.6, 0.6, -0.2)), w + Vector((0.0, 0.0, -0.1)))
    SC.curl_fingers(a, "r", 70.0, 35.0)               # round the handles


def clips(arm):
    SC.clip(arm, "Phone", [(1, lambda a: phone(a, -1)), (49, lambda a: phone(a, 1)), (97, lambda a: phone(a, -1))])
    SC.clip(arm, "PhoneLook", [(1, lambda a: phone_look(a, -1)), (37, lambda a: phone_look(a, 1)), (73, lambda a: phone_look(a, -1))])
    SC.clip(arm, "WalkPhone", [(1 + k, (lambda kk: (lambda a: walk_phone(a, (kk % 24) / 24.0)))(k)) for k in range(25)])
    SC.clip(arm, "WalkCarry", [(1 + k, (lambda kk: (lambda a: walk_carry(a, (kk % 24) / 24.0)))(k)) for k in range(25)])
    for tr in arm.animation_data.nla_tracks:
        tr.mute = False


def strip(arm, out_dir):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [e.identifier for e in sc.render.bl_rna.properties["engine"].enum_items] else 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 500, 800
    sc.render.image_settings.file_format = 'JPEG'
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.data.lens = 40
    cam.location = (-1.6, -2.4, 1.3)
    cam.rotation_euler = (Vector((0, 0, 1.0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    os.makedirs(out_dir, exist_ok=True)
    for name, fn in (("phone", lambda a: phone(a, 1)), ("look", lambda a: phone_look(a, 1)),
                     ("walkphone", lambda a: walk_phone(a, 0.25)), ("carry", lambda a: walk_carry(a, 0.25))):
        SC.rest(arm)
        SC.arms_down(arm)
        fn(arm)
        sc.render.filepath = os.path.join(out_dir, "%s_%s.jpg" % (arm.name.split(".")[0], name))
        bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for key, sex in (("m1", "m"), ("w1", "w")):
        c = [c for c in CC.CROWD if c[0] == key][0]
        SC.clear()
        SC.stride = SC.STRIDE.get(c[9], 1.0)
        arm, objs = SC.build(c)
        if "--strip" in args:
            if arm.animation_data:
                for tr in arm.animation_data.nla_tracks:
                    tr.mute = True
            strip(arm, os.path.abspath(args[args.index("--strip") + 1]))
            continue
        for o in objs:
            if o.name in bpy.data.objects and o != arm:
                o.hide_render = True
        clips(arm)
        SM.OUT = os.path.join(OUT, "crowd_clips_%s.glb" % sex)
        SM.export(arm)
    print("CROWDCLIPS done", flush=True)


if __name__ == "__main__":
    main()
