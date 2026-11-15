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
    """k -1..1: the laugh's beat. The chest jumps with each breath of it, the head goes back, one hand to the
    stomach, the other half up as if to say "stop"."""
    SC.idle(a, 0.3)
    SC.turn(a, "spine_02", 'X', -7.0 + 5.0 * k)          # shaking with it
    SC.turn(a, "spine_03", 'X', -4.0 + 3.0 * k)
    SC.turn(a, "head", 'X', -18.0 + 8.0 * k)
    SC.turn(a, "spine_03", 'Y', 4.0 * k)
    st = SC.head_of(a, "spine_02") + Vector((-0.04, -0.17, 0.0))
    up = SC.head_of(a, "spine_03") + Vector((0.2, -0.28, -0.02 + 0.03 * k))
    _hands_to(a, up, st, up + Vector((0.04, -0.06, 0.12)), st + Vector((0.1, 0.0, 0.0)))


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
    """Arms folded across the chest: each hand at the other arm's elbow (the chest, not the navel: spine_03)."""
    SC.idle(a, k)
    c = SC.head_of(a, "spine_03") + Vector((0.0, -0.19, -0.08))
    for side, sg, dz in (("l", 1.0, 0.0), ("r", -1.0, 0.025)):
        w = c + Vector((-sg * 0.12, 0.0, dz))
        SM.arm_to(a, side, w, Vector((sg * 0.9, -0.2, -0.9)), w + Vector((-sg * 0.1, 0.02, 0.0)))


def handshake(a, k):
    """The right hand out, waist high, a little to his left (to the other's right hand), shaking up and down."""
    SC.idle(a, 0.3)
    SC.turn(a, "spine_02", 'X', 3.0)
    sh = SC.head_of(a, "upperarm_r")
    w = sh + Vector((0.1, -0.46, -0.26 + 0.03 * k))
    SM.arm_to(a, "r", w, Vector((-0.6, 0.3, -1.0)), w + Vector((0.02, -0.12, 0.0)))
    SC.curl_fingers(a, "r", 35.0, 20.0)


def comfort(a, k):
    """A hand on the other's shoulder (their left, before him), the head a little down, the other arm easy."""
    SC.idle(a, 0.4)
    SC.turn(a, "head", 'X', 8.0)
    SC.turn(a, "spine_02", 'X', 4.0)
    sh = SC.head_of(a, "upperarm_r")
    w = sh + Vector((0.08, -0.45, -0.05 + 0.01 * k))
    SM.arm_to(a, "r", w, Vector((-0.8, 0.2, -0.8)), w + Vector((0.0, -0.1, -0.04)))
    SC.curl_fingers(a, "r", 25.0, 10.0)


def give(a, k):
    """Holding something out in both hands at the chest, (k 1) a little further forward: handing it over."""
    SC.idle(a, 0.3)
    SC.turn(a, "spine_02", 'X', 3.0 + 3.0 * k)
    c = SC.head_of(a, "spine_03") + Vector((0.0, -0.32 - 0.06 * k, -0.12))
    _hands_to(a, c + Vector((0.07, 0.0, 0.0)), c + Vector((-0.07, 0.0, 0.0)), c + Vector((0.07, -0.1, 0.02)), c + Vector((-0.07, -0.1, 0.02)))


# ---- at work: what people do for a living, where you can see it ----
def _chest(a):
    return SC.head_of(a, "spine_03")


def _lean(a, deg, knees=0.0):
    SC.turn(a, "spine_01", 'X', deg * 0.6)
    SC.turn(a, "spine_02", 'X', deg * 0.4)
    if knees:
        for side in ("l", "r"):
            SC.turn(a, "thigh_" + side, 'X', -knees)
            SC.turn(a, "calf_" + side, 'X', knees * 1.3)
            SC.turn(a, "foot_" + side, 'X', -knees * 0.3)
        SC.lower(a, "pelvis", -0.0035 * knees)
        bpy.context.view_layer.update()


def sweep(a, k):
    """Sweeping the footpath with a short broom (a coconut-frond broom): bent over from the hips, the knees soft, the
    right hand low sweeping side to side, the left on the knee; the head up enough to see the way."""
    SC.idle(a, 0.2)
    _lean(a, 38.0, 14.0)
    SC.turn(a, "neck_01", 'X', -16.0)
    feet = (SC.head_of(a, "foot_l") + SC.head_of(a, "foot_r")) * 0.5
    w = feet + Vector((-0.12 + 0.22 * k, -0.5, 0.52))
    SM.arm_to(a, "r", w, Vector((-0.9, 0.2, -0.5)), w + Vector((0.05 * k, -0.1, -0.15)))
    SM.grip(a, "r")
    knee = SC.head_of(a, "calf_l")
    SM.arm_to(a, "l", knee + Vector((0.0, -0.09, 0.08)), Vector((0.9, 0.2, -0.3)), knee + Vector((0.0, -0.2, 0.0)))


def pour_tea(a, k):
    """Pulling tea (the tea master's long pour): the jug high in the right hand, the glass low in the left, the
    stream between them lengthening and shortening; the head down, watching the glass."""
    SC.idle(a, 0.3)
    c = _chest(a)
    SC.turn(a, "neck_01", 'X', 10.0)
    hi = c + Vector((-0.27, -0.3, 0.46 + 0.07 * k))       # (the jug above the head, out to the side)
    lo = c + Vector((0.14, -0.32, -0.36 - 0.05 * k))
    SM.arm_to(a, "r", hi, Vector((-0.9, 0.3, -0.5)), hi + Vector((0.08, -0.04, 0.02)))
    SM.arm_to(a, "l", lo, Vector((0.9, 0.3, -0.7)), lo + Vector((-0.05, -0.1, 0.0)))
    SM.grip(a, "r")
    SM.grip(a, "l")


def stir(a, t):
    """At the stove: the ladle round the pot in the right hand (a circle a second), the left hand on the counter."""
    SC.idle(a, 0.3 * math.sin(2.0 * math.pi * t))
    _lean(a, 9.0)
    c = _chest(a)
    w = c + Vector((-0.08 + 0.07 * math.cos(2.0 * math.pi * t), -0.44 + 0.07 * math.sin(2.0 * math.pi * t), -0.3))
    SM.arm_to(a, "r", w, Vector((-0.9, 0.2, -0.6)), w + Vector((0.0, -0.05, -0.12)))
    SM.grip(a, "r")
    l = c + Vector((0.22, -0.38, -0.34))
    SM.arm_to(a, "l", l, Vector((0.9, 0.2, -0.6)), l + Vector((0.0, -0.12, -0.02)))


def type_(a, k):
    """At a desk, typing: sitting, a little forward, the hands at the keyboard, the fingers going, the eyes on the
    screen."""
    SC.sit(a)
    _lean(a, 9.0)
    SC.turn(a, "neck_01", 'X', 4.0)
    c = _chest(a)
    for side, sg in (("l", 1.0), ("r", -1.0)):
        w = c + Vector((sg * 0.13, -0.4, -0.17 + 0.012 * k * sg))   # (the desk's height, not the lap)
        SM.arm_to(a, side, w, Vector((sg * 0.9, 0.3, -0.6)), w + Vector((0.0, -0.12, -0.03)))
        SC.curl_fingers(a, side, 22.0 + 10.0 * k * sg, 8.0)


def write(a, k):
    """At a desk, writing: the head down over the paper, the right hand writing (small strokes), the left holding the
    page."""
    SC.sit(a)
    _lean(a, 13.0)
    SC.turn(a, "neck_01", 'X', 12.0)
    SC.turn(a, "head", 'X', 6.0)
    c = _chest(a)
    r = c + Vector((-0.07 + 0.02 * k, -0.38, -0.2))
    SM.arm_to(a, "r", r, Vector((-0.9, 0.3, -0.6)), r + Vector((0.03, -0.1, -0.05)))
    SM.grip(a, "r")
    l = c + Vector((0.16, -0.36, -0.21))
    SM.arm_to(a, "l", l, Vector((0.9, 0.3, -0.6)), l + Vector((-0.06, -0.12, -0.02)))


def arrange(a, k):
    """At a stall: bent a little over the goods, picking one up and setting it down, the hands taking turns."""
    SC.idle(a, 0.4 * k)
    _lean(a, 15.0)
    SC.turn(a, "neck_01", 'X', 10.0)
    c = _chest(a)
    r = c + Vector((-0.12 + 0.05 * k, -0.45, -0.42 + 0.05 * max(k, 0.0)))
    l = c + Vector((0.14 - 0.05 * k, -0.42, -0.4 + 0.05 * max(-k, 0.0)))
    SM.arm_to(a, "r", r, Vector((-0.9, 0.2, -0.6)), r + Vector((0.0, -0.08, -0.1)))
    SM.arm_to(a, "l", l, Vector((0.9, 0.2, -0.6)), l + Vector((0.0, -0.08, -0.1)))


def wipe(a, t):
    """Wiping a counter (or an auto's seat) with a cloth: the right hand going round, the left resting by it."""
    SC.idle(a, 0.3 * math.sin(2.0 * math.pi * t))
    _lean(a, 14.0)
    SC.turn(a, "neck_01", 'X', 8.0)
    c = _chest(a)
    r = c + Vector((-0.1 + 0.09 * math.cos(2.0 * math.pi * t), -0.46 + 0.06 * math.sin(2.0 * math.pi * t), -0.42))
    SM.arm_to(a, "r", r, Vector((-0.9, 0.2, -0.6)), r + Vector((0.0, -0.1, -0.12)))
    l = c + Vector((0.2, -0.4, -0.4))
    SM.arm_to(a, "l", l, Vector((0.9, 0.2, -0.6)), l + Vector((0.0, -0.1, -0.1)))


def head_load(a, t):
    """Walking with a load on the head (a basket, a bundle): both hands up steadying it, the elbows out, the head
    and neck held still under it."""
    SC.walk_phase(a, t)
    top = SC.head_of(a, "head") + Vector((0.0, 0.0, 0.2))
    bob = 0.01 * math.sin(4.0 * math.pi * t)
    for side, sg in (("l", 1.0), ("r", -1.0)):
        w = top + Vector((sg * 0.14, -0.02, bob))
        SM.arm_to(a, side, w, Vector((sg * 0.9, 0.1, 0.1)), w + Vector((-sg * 0.1, 0.0, 0.03)))


# ---- standing and sitting as people do (the body-language brief) ----
def stand_wait(a, k, look):
    SC.idle(a, k)
    SC.turn(a, "neck_01", 'Z', look * 0.35)
    SC.turn(a, "head", 'Z', look * 0.65)


def hands_behind(a, k):
    """Hands clasped behind the back (an elder, a policeman, someone patient): the chest a little up."""
    SC.idle(a, k * 0.7)
    SC.turn(a, "spine_02", 'X', -2.5)
    p = SC.head_of(a, "pelvis") + Vector((0.0, 0.14, 0.1))
    for side, sg in (("l", 1.0), ("r", -1.0)):
        w = p + Vector((sg * 0.05, 0.0, 0.0))
        SM.arm_to(a, side, w, Vector((sg * 0.9, 0.6, -0.3)), w + Vector((-sg * 0.08, 0.04, 0.0)))


def hands_front(a, k):
    """Hands loosely together in front (a receptionist, a respectful listener)."""
    SC.idle(a, k * 0.6)
    SC.turn(a, "head", 'X', 3.0)
    p = SC.head_of(a, "pelvis") + Vector((0.0, -0.17, 0.02))
    for side, sg in (("l", 1.0), ("r", -1.0)):
        w = p + Vector((sg * 0.035, 0.0, 0.0))
        SM.arm_to(a, side, w, Vector((sg * 0.9, 0.2, -0.6)), w + Vector((-sg * 0.08, -0.03, -0.02)))


def hip_hand(a, k):
    """One hand on the hip (the right), the weight on that side: casual, waiting."""
    SC.idle(a, 0.6 + 0.4 * k)
    hip = SC.head_of(a, "thigh_r") + Vector((-0.11, 0.0, 0.1))
    SM.arm_to(a, "r", hip, Vector((-1.0, 0.4, 0.2)), hip + Vector((0.03, 0.0, -0.1)))


def nervous(a, k):
    """Uneasy: the hands rubbing in front, small shifts, the eyes going here and there."""
    SC.idle(a, 0.3 * k)
    p = SC.head_of(a, "pelvis") + Vector((0.0, -0.2, 0.1))
    SM.arm_to(a, "l", p + Vector((0.03 + 0.015 * k, 0.0, 0.01 * k)), Vector((0.9, 0.2, -0.6)), p + Vector((-0.06, -0.03, 0.0)))
    SM.arm_to(a, "r", p + Vector((-0.03 + 0.015 * k, 0.0, -0.01 * k)), Vector((-0.9, 0.2, -0.6)), p + Vector((0.06, -0.03, 0.0)))
    SC.turn(a, "head", 'Z', 9.0 * k)


def _sit_shift(a, u):
    """Between standing and the chair, u 0..1: the hips back and down onto the seat, knees and hips bending together,
    the chest forward to balance and back up as the weight settles, the hands to the thighs."""
    e = u * u * (3.0 - 2.0 * u)
    pb = a.pose.bones.get("pelvis")
    if pb is not None:
        m = a.matrix_world @ pb.matrix
        m.translation.y += 0.42 * e                        # back onto the seat (the feet stay where they are)
        m.translation.z -= 0.42 * e
        pb.matrix = a.matrix_world.inverted() @ m
        bpy.context.view_layer.update()
    for side in ("l", "r"):
        SC.turn(a, "thigh_" + side, 'X', -84.0 * e)
        SC.turn(a, "calf_" + side, 'X', 84.0 * e)
    SC.turn(a, "spine_01", 'X', 26.0 * math.sin(math.pi * e))
    SC.turn(a, "neck_01", 'X', -10.0 * math.sin(math.pi * e))


def sit_down(a, u):
    _sit_shift(a, u)


def stand_up(a, u):
    _sit_shift(a, 1.0 - u)


# ---- a fight (the godown, Day 18): stance, punch, the gang's telegraphed haymaker, block, being hit, a dodge ----
def _guard_stance(a, k=0.0):
    """Fists up by the chin, elbows in, knees bent, the left foot ahead, the body turned a little side-on."""
    SC.idle(a, 0.2 * k)
    SC.turn(a, "pelvis", 'Z', 18.0)
    SC.turn(a, "spine_03", 'Z', -8.0)
    for side in ("l", "r"):
        SC.turn(a, "thigh_" + side, 'X', -14.0)
        SC.turn(a, "calf_" + side, 'X', 22.0)
        SC.turn(a, "foot_" + side, 'X', -8.0)
    SC.lower(a, "pelvis", -0.05)
    bpy.context.view_layer.update()
    SC.turn(a, "spine_01", 'X', 8.0)
    chin = SC.head_of(a, "head") + Vector((0.0, -0.12, -0.08))
    for side, sg in (("l", 1.0), ("r", -1.0)):
        w = chin + Vector((sg * 0.1, -0.12 if side == "l" else -0.04, -0.06 + 0.01 * k))
        SM.arm_to(a, side, w, Vector((sg * 0.6, 0.3, -1.0)), w + Vector((0.0, -0.06, 0.1)))
        SC.curl_fingers(a, side, 80.0, 40.0)


def punch(a, u):
    """A straight right from the guard: the hip and shoulder turn into it, the arm drives out to the chin's height;
    u 0..1 out and back."""
    _guard_stance(a)
    e = math.sin(math.pi * min(u * 1.6, 1.0)) if u < 0.62 else max(0.0, 1.0 - (u - 0.62) / 0.38) * 0.0
    SC.turn(a, "spine_02", 'Z', -16.0 * e)
    SC.turn(a, "spine_01", 'X', 6.0 * e)
    sh = SC.head_of(a, "upperarm_r")
    out = sh + Vector((0.08, -0.62, 0.02))
    home = SC.head_of(a, "head") + Vector((-0.1, -0.16, -0.14))
    w = home.lerp(out, e)
    SM.arm_to(a, "r", w, Vector((-0.7, 0.3, -0.7)), w + Vector((0.0, -0.1, 0.0)))
    SC.curl_fingers(a, "r", 85.0, 45.0)


def haymaker(a, u):
    """The gang's swing, telegraphed: the right arm drawn far back and up (u to 0.6: the wind-up you can see coming),
    then round in a wide arc across."""
    SC.idle(a, 0.2)
    if u < 0.6:
        e = u / 0.6
        SC.turn(a, "spine_02", 'Z', 25.0 * e)
        sh = SC.head_of(a, "upperarm_r")
        w = sh + Vector((-0.35 * e, 0.25 * e, 0.12 * e - 0.3 * (1.0 - e)))
        SM.arm_to(a, "r", w, Vector((-0.8, 0.5, 0.2)), w + Vector((0.0, -0.1, 0.05)))
    else:
        e = (u - 0.6) / 0.4
        SC.turn(a, "spine_02", 'Z', 25.0 - 50.0 * e)
        SC.turn(a, "spine_01", 'X', 8.0 * e)
        sh = SC.head_of(a, "upperarm_r")
        ang = math.radians(-60.0 + 140.0 * e)
        w = sh + Vector((0.5 * math.sin(ang) - 0.1, -0.5 * math.cos(ang) + 0.1, 0.0))
        SM.arm_to(a, "r", w, Vector((-0.6, 0.6, 0.2)), w + Vector((0.1, -0.05, 0.0)))
    SC.curl_fingers(a, "r", 85.0, 45.0)


def block(a, k):
    """Forearms up before the face, the head down behind them."""
    _guard_stance(a, k)
    SC.turn(a, "neck_01", 'X', 12.0)
    f = SC.head_of(a, "head") + Vector((0.0, -0.2, 0.0))
    for side, sg in (("l", 1.0), ("r", -1.0)):
        w = f + Vector((sg * 0.06, -0.04, 0.05))
        SM.arm_to(a, side, w, Vector((sg * 0.3, -0.2, -1.0)), w + Vector((0.0, 0.0, 0.15)))


def hit_react(a, u):
    """Hit: the chest and head snap back, the arms fly a little, then come back to the guard."""
    _guard_stance(a)
    e = math.sin(math.pi * min(u * 2.0, 1.0)) if u < 0.5 else max(0.0, 1.0 - (u - 0.5) * 2.0)
    SC.turn(a, "spine_01", 'X', -14.0 * e)
    SC.turn(a, "spine_02", 'X', -8.0 * e)
    SC.turn(a, "neck_01", 'X', -16.0 * e)
    SC.turn(a, "spine_02", 'Z', 10.0 * e)


def dodge(a, u):
    """A quick step back and down out of the swing's reach, then up again."""
    _guard_stance(a)
    e = math.sin(math.pi * u)
    pb = a.pose.bones.get("pelvis")
    if pb is not None:
        m = a.matrix_world @ pb.matrix
        m.translation.y += 0.22 * e
        m.translation.z -= 0.08 * e
        pb.matrix = a.matrix_world.inverted() @ m
        bpy.context.view_layer.update()
    SC.turn(a, "spine_01", 'X', -10.0 * e)


def clips(arm):
    for name, fn, keys in (("Namaste", namaste, (0, 1, 1, 0)), ("Wave", wave, (-1, 1, -1, 1, -1)), ("Nod", nod, (0, 1, 0, 1, 0)),
                           ("Wobble", wobble, (0, 1, -1, 1, 0)), ("Shake", shake, (0, 1, -1, 1, -1, 0)), ("Laugh", laugh, (-1, 1, -1, 1, -1, 1, -1)),
                           ("Shrug", shrug, (0, 1, 1, 0)), ("Point", point, (0, 1, 1, 1)), ("Argue", argue, (-1, 1, -1, 1, -1)),
                           ("Fold", fold, (-1, 1, -1)), ("Handshake", handshake, (-1, 1, -1, 1, -1, 0)),
                           ("Comfort", comfort, (-1, 1, -1)), ("Give", give, (0, 1, 1, 0))):
        step = 12 if name not in ("Fold", "Namaste", "Shrug", "Point", "Comfort", "Give") else 24
        step = 6 if name == "Handshake" else step
        SC.clip(arm, name, [(1 + i * step, (lambda ff, kk: (lambda a: ff(a, kk)))(fn, k)) for i, k in enumerate(keys)])
    SC.clip(arm, "Phone", [(1, lambda a: phone(a, -1)), (49, lambda a: phone(a, 1)), (97, lambda a: phone(a, -1))])
    SC.clip(arm, "PhoneLook", [(1, lambda a: phone_look(a, -1)), (37, lambda a: phone_look(a, 1)), (73, lambda a: phone_look(a, -1))])
    SC.clip(arm, "WalkPhone", [(1 + k, (lambda kk: (lambda a: walk_phone(a, (kk % 24) / 24.0)))(k)) for k in range(25)])
    SC.clip(arm, "WalkCarry", [(1 + k, (lambda kk: (lambda a: walk_carry(a, (kk % 24) / 24.0)))(k)) for k in range(25)])
    # at work
    SC.clip(arm, "Sweep", [(1 + 9 * i, (lambda kk: (lambda a: sweep(a, kk)))(k)) for i, k in enumerate((-1, 1, -1, 1, -1))])
    SC.clip(arm, "PourTea", [(1 + 12 * i, (lambda kk: (lambda a: pour_tea(a, kk)))(k)) for i, k in enumerate((-1, 1, -1, 1, -1))])
    SC.clip(arm, "Stir", [(1 + k, (lambda kk: (lambda a: stir(a, (kk % 24) / 24.0)))(k)) for k in range(0, 25, 3)])
    SC.clip(arm, "Type", [(1 + 3 * i, (lambda kk: (lambda a: type_(a, kk)))(k)) for i, k in enumerate((-1, 1, -1, 1, 0, 0, -1, 1, -1))])
    SC.clip(arm, "Write", [(1 + 6 * i, (lambda kk: (lambda a: write(a, kk)))(k)) for i, k in enumerate((-1, 1, -1, 1, -1, 1, -1))])
    SC.clip(arm, "Arrange", [(1 + 18 * i, (lambda kk: (lambda a: arrange(a, kk)))(k)) for i, k in enumerate((-1, 1, -1))])
    SC.clip(arm, "Wipe", [(1 + k, (lambda kk: (lambda a: wipe(a, (kk % 24) / 24.0)))(k)) for k in range(0, 25, 3)])
    SC.clip(arm, "HeadLoad", [(1 + k, (lambda kk: (lambda a: head_load(a, (kk % 24) / 24.0)))(k)) for k in range(25)])
    # standing and sitting
    SC.clip(arm, "StandWait", [(1 + 24 * i, (lambda kk, ll: (lambda a: stand_wait(a, kk, ll)))(k, l))
                               for i, (k, l) in enumerate(((-1, 0), (-1, 28), (0, 28), (1, 0), (1, -32), (1, -32), (0, 0), (-1, 0)))])
    for name, fn in (("HandsBehind", hands_behind), ("HandsFront", hands_front), ("HipHand", hip_hand)):
        SC.clip(arm, name, [(1 + 48 * i, (lambda ff, kk: (lambda a: ff(a, kk)))(fn, k)) for i, k in enumerate((-1, 1, -1))])
    SC.clip(arm, "Nervous", [(1 + 8 * i, (lambda kk: (lambda a: nervous(a, kk)))(k)) for i, k in enumerate((-1, 1, -1, 1, -1, 1, -1))])
    SC.clip(arm, "SitWait", [(1 + 24 * i, (lambda kk, ll: (lambda a: SC.sit_idle(a, kk, ll)))(k, l))
                             for i, (k, l) in enumerate(((-1, 0), (1, 25), (-1, 25), (1, -20), (-1, 0)))])
    SC.clip(arm, "SitDown", [(1 + 3 * i, (lambda uu: (lambda a: sit_down(a, uu)))(i / 10.0)) for i in range(11)])
    # a fight: Guard loops; Punch 0.5 s, Haymaker 1.2 s (0.7 of it the wind-up), Block loops, HitReact 0.5 s, Dodge 0.45 s
    SC.clip(arm, "Guard", [(1 + 12 * i, (lambda kk: (lambda a: _guard_stance(a, kk)))(k)) for i, k in enumerate((-1, 1, -1))])
    SC.clip(arm, "Punch", [(1 + i, (lambda uu: (lambda a: punch(a, uu)))(i / 12.0)) for i in range(13)])
    SC.clip(arm, "Haymaker", [(1 + 2 * i, (lambda uu: (lambda a: haymaker(a, uu)))(i / 14.0)) for i in range(15)])
    SC.clip(arm, "Block", [(1 + 12 * i, (lambda kk: (lambda a: block(a, kk)))(k)) for i, k in enumerate((-1, 1, -1))])
    SC.clip(arm, "HitReact", [(1 + i, (lambda uu: (lambda a: hit_react(a, uu)))(i / 12.0)) for i in range(13)])
    SC.clip(arm, "Dodge", [(1 + i, (lambda uu: (lambda a: dodge(a, uu)))(i / 10.0)) for i in range(11)])
    SC.clip(arm, "StandUp", [(1 + 3 * i, (lambda uu: (lambda a: stand_up(a, uu)))(i / 10.0)) for i in range(11)])
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
                     ("fold", lambda a: fold(a, 1)), ("wobble", lambda a: wobble(a, 1)), ("handshake", lambda a: handshake(a, 1)),
                     ("comfort", lambda a: comfort(a, 1)), ("give", lambda a: give(a, 1)),
                     ("sweep", lambda a: sweep(a, 1)), ("pourtea", lambda a: pour_tea(a, 1)), ("stir", lambda a: stir(a, 0.25)),
                     ("type", lambda a: type_(a, 1)), ("write", lambda a: write(a, 1)), ("arrange", lambda a: arrange(a, 1)),
                     ("wipe", lambda a: wipe(a, 0.25)), ("headload", lambda a: head_load(a, 0.25)),
                     ("behind", lambda a: hands_behind(a, 1)), ("front", lambda a: hands_front(a, 1)), ("hip", lambda a: hip_hand(a, 1)),
                     ("nervous", lambda a: nervous(a, 1)), ("sitdown", lambda a: sit_down(a, 0.5)),
                     ("guard", lambda a: _guard_stance(a, 0)), ("punch", lambda a: punch(a, 0.31)),
                     ("haywind", lambda a: haymaker(a, 0.55)), ("hayswing", lambda a: haymaker(a, 0.85)),
                     ("block", lambda a: block(a, 0)), ("hit", lambda a: hit_react(a, 0.25)), ("dodge", lambda a: dodge(a, 0.5))):
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
