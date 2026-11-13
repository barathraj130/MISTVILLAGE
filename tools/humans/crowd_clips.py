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
and the body language of people with each other (scripts/city/city_living.gd, city_walkers.gd: a conversation's
mood, a greeting for Karthik):
    Namaste    the palms together before the chest, a small bow of the head
    Wave       the right hand up, a few waves
    Nod        a few nods, agreeing
    Wobble     the South Indian head wobble (side to side, the head tilting): "yes, OK"
    Shake      the head turning side to side: "no"
    Laugh      the shoulders shaking, the head back, a hand to the stomach
    Shrug      the shoulders up, the hands open, palms up
    Point      the right arm out, pointing the way, the head turning to it
    Argue      both hands out, palms up, beating with the words, leaning in
    Fold       listening with the arms folded, weight on one leg
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


def _hands_to(a, lw, rw, lpoint=None, rpoint=None):
    for side, w, pt, pole in (("l", lw, lpoint, Vector((0.9, 0.3, -0.7))), ("r", rw, rpoint, Vector((-0.9, 0.3, -0.7)))):
        if w is not None:
            SM.arm_to(a, side, w, pole, pt if pt is not None else w + Vector((0.0, -0.08, 0.04)))


def namaste(a, k):
    SC.idle(a, k * 0.5)
    SC.turn(a, "head", 'X', 10.0 * max(k, 0.0))           # (k 1: the bow)
    SC.turn(a, "spine_02", 'X', 4.0 * max(k, 0.0))
    c = SC.head_of(a, "spine_03") + Vector((0.0, -0.2, 0.02))
    _hands_to(a, c + Vector((0.025, 0.0, 0.0)), c + Vector((-0.025, 0.0, 0.0)), c + Vector((0.02, -0.02, 0.15)), c + Vector((-0.02, -0.02, 0.15)))


def wave(a, k):
    SC.idle(a, 0.3)
    sh = SC.head_of(a, "upperarm_r")
    w = sh + Vector((-0.18, -0.12, 0.2))
    SM.arm_to(a, "r", w, Vector((-1.0, 0.2, -0.6)), w + Vector((-0.04 * k, 0.0, 0.12)))


def nod(a, k):
    SC.idle(a, 0.2 * k)
    SC.turn(a, "head", 'X', 9.0 * k)


def wobble(a, k):
    SC.idle(a, 0.2)
    SC.turn(a, "head", 'Y', 11.0 * k)                    # the tilt side to side, the face staying on you
    SC.turn(a, "head", 'Z', -3.0 * k)


def shake(a, k):
    SC.idle(a, 0.2)
    SC.turn(a, "head", 'Z', 14.0 * k)


def laugh(a, k):
    SC.idle(a, 0.3)
    SC.turn(a, "spine_02", 'X', -4.0 + 3.0 * k)          # shaking with it
    SC.turn(a, "head", 'X', -10.0 + 5.0 * k)
    SC.turn(a, "spine_03", 'Y', 2.0 * k)
    c = SC.head_of(a, "spine_01") + Vector((-0.06, -0.16, 0.06))
    _hands_to(a, None, c, None, c + Vector((0.08, 0.0, 0.0)))


def shrug(a, k):
    SC.idle(a, 0.3)
    for b in ("clavicle_l", "clavicle_r"):
        SC.lower(a, b, 0.035 * max(k, 0.0))
    SC.turn(a, "head", 'Y', 6.0 * k)
    h = SC.head_of(a, "spine_01")
    _hands_to(a, h + Vector((0.24, -0.2, -0.02)), h + Vector((-0.24, -0.2, -0.02)), h + Vector((0.34, -0.3, 0.0)), h + Vector((-0.34, -0.3, 0.0)))   # (palms up, out by the hips)


def point(a, k):
    SC.idle(a, 0.3)
    sh = SC.head_of(a, "upperarm_r")
    w = sh + Vector((-0.45, -0.32, 0.0 + 0.02 * k))
    SM.arm_to(a, "r", w, Vector((-0.5, 0.2, -1.0)), w + Vector((-0.2, -0.15, 0.0)))
    SC.curl_fingers(a, "r", 60.0, 10.0)
    SC.turn(a, "head", 'Z', -22.0)                         # looking where he points (his right)


def argue(a, k):
    SC.idle(a, 0.4)
    SC.turn(a, "spine_01", 'X', 5.0)
    h = SC.head_of(a, "spine_02") + Vector((0.0, -0.3, 0.02 + 0.05 * k))
    _hands_to(a, h + Vector((0.2, 0.0, 0.0)), h + Vector((-0.2, 0.0, 0.0)), h + Vector((0.3, -0.12, 0.06)), h + Vector((-0.3, -0.12, 0.06)))
    SC.turn(a, "head", 'X', -4.0 * k)


def fold(a, k):
    SC.idle(a, k)
    c = SC.head_of(a, "spine_02") + Vector((0.0, -0.17, 0.0))
    _hands_to(a, c + Vector((-0.11, 0.0, 0.0)), c + Vector((0.11, 0.0, 0.02)), c + Vector((-0.22, 0.0, 0.0)), c + Vector((0.22, 0.0, 0.02)))


def clips(arm):
    for name, fn, keys in (("Namaste", namaste, (0, 1, 1, 0)), ("Wave", wave, (-1, 1, -1, 1, -1)), ("Nod", nod, (0, 1, 0, 1, 0)),
                           ("Wobble", wobble, (0, 1, -1, 1, 0)), ("Shake", shake, (0, 1, -1, 1, -1, 0)), ("Laugh", laugh, (-1, 1, -1, 1, -1, 1, -1)),
                           ("Shrug", shrug, (0, 1, 1, 0)), ("Point", point, (0, 1, 1, 1)), ("Argue", argue, (-1, 1, -1, 1, -1)),
                           ("Fold", fold, (-1, 1, -1))):
        step = 12 if name not in ("Fold", "Namaste", "Shrug", "Point") else 24
        SC.clip(arm, name, [(1 + i * step, (lambda ff, kk: (lambda a: ff(a, kk)))(fn, k)) for i, k in enumerate(keys)])
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
                     ("walkphone", lambda a: walk_phone(a, 0.25)), ("carry", lambda a: walk_carry(a, 0.25)),
                     ("namaste", lambda a: namaste(a, 1)), ("wave", lambda a: wave(a, 1)), ("laugh", lambda a: laugh(a, 1)),
                     ("shrug", lambda a: shrug(a, 1)), ("point", lambda a: point(a, 1)), ("argue", lambda a: argue(a, 1)),
                     ("fold", lambda a: fold(a, 1)), ("wobble", lambda a: wobble(a, 1))):
        SC.rest(arm)
        SC.arms_down(arm)
        fn(arm)
        sc.render.filepath = os.path.join(out_dir, "%s_%s.jpg" % (arm.name.split(".")[0], name))
        bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for key, sex in ((("m1", "m"),) if "--manonly" in args else (("m1", "m"), ("w1", "w"))):
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
