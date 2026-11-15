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
from mathutils import Matrix, Vector

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
def haymaker(a, u):
    """The gang's swing, telegraphed: the weight rocks back, the shoulder turns away and the right fist is drawn back
    by the ear, the elbow up behind (to 0.6: the wind-up you can see coming); then he steps into it and the fist
    comes round in a wide flat arc, the body turning right through, the back heel up."""
    c = 0.805
    if u < 0.6:
        lo, e = _smooth(u / 0.6), 0.0
    else:
        lo = 1.0 - _smooth((u - 0.6) / 0.12)
        e = min(1.0, (u - 0.6) / (c - 0.6)) if u <= c else max(0.0, 1.0 - _smooth((u - c - 0.05) / max(0.95 - c, 0.01)))
    t = 22.0 * lo - 40.0 * e
    _stance(a, shift=0.06 * lo - 0.1 * e, turn=t, low=0.02 * lo + 0.03 * e, toes={"r": 20.0 + 50.0 * e}, heels={"r": 0.08 * e})
    SC.turn(a, "spine_02", 'Z', 0.6 * t)
    _arms_guard(a, skip=("r",))
    sh = SC.head_of(a, "upperarm_r")
    back = sh + Vector((-0.12, 0.12, 0.12))              # (by the ear, behind)
    ang = math.radians(-20.0 + 105.0 * e)
    swing = sh + Vector((-(0.45 * math.cos(ang) - 0.25), -0.45 * math.sin(ang) - 0.05, 0.02))
    g = _guard_wrist(a, "r")
    w = _reach(a, "r", g.lerp(back, lo) if e <= 0.0 else back.lerp(swing, min(1.0, e * 1.3)), 0.92)
    SM.arm_to(a, "r", w, w + Vector((-0.8, 0.5, 0.3)), w + Vector((0.12, -0.05, 0.0)))
    SC.curl_fingers(a, "r", 88.0, 45.0)


# ---- hand-to-hand (the combat system, scripts/combat/; docs/COMBAT_ANIMATION_REPORT.md): every move built on one
# grounded stance. Conventions: he faces -Y, his left is +X, up +Z; 24 frames a second. The feet are PLANTED with
# two-bone leg IK (SC._leg_to) wherever they stand; moves that travel (steps, dodges, staggers) carry their travel in
# the feet: a foot on the ground stays where it is in the world while the body goes on, so with the game moving him
# along the same curve (combat/moves.gd: distance and the progress curve, the same numbers) nothing slides.
# Contact frames are the authored ones (combat/moves.gd "hit": the u the fist arrives, from STRIKES below).
STRIKES = {"Jab": (10, 0.4), "Cross": (13, 0.45), "Hook": (14, 0.5), "Heavy": (24, 0.58), "Punch": (13, 0.45),
           "JabR": (11, 0.4), "HookR": (14, 0.5), "Uppercut": (15, 0.55),
           "FrontKick": (16, 0.45), "LowKick": (15, 0.5), "BodyKick": (18, 0.5), "KneeStrike": (13, 0.45),
           "SideKick": (18, 0.5)}


def _smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def _rest_feet(a):
    out = {}
    for side in ("l", "r"):
        ank = SC.head_of(a, "foot_" + side)
        ball = SC.head_of(a, "ball_" + side) if "ball_" + side in a.pose.bones else ank + Vector((0.0, -0.13, -0.05))
        out[side] = (ank.copy(), (ball - ank).copy())
    return out


def _pelvis(a, d=Vector((0.0, 0.0, 0.0)), pitch=0.0, roll=0.0, yaw=0.0, pivot=None):
    """The hips moved by d (world) and turned (degrees: pitch about X, + leans forward; roll about Y; yaw about Z)
    about their own head (or `pivot`): the whole body above goes with them."""
    pb = a.pose.bones.get("pelvis")
    if pb is None:
        return
    m = a.matrix_world @ pb.matrix
    piv = m.translation.copy() if pivot is None else pivot
    r = (Matrix.Rotation(math.radians(yaw), 4, 'Z') @ Matrix.Rotation(math.radians(pitch), 4, 'X')
         @ Matrix.Rotation(math.radians(roll), 4, 'Y'))
    m = Matrix.Translation(piv + d) @ r @ Matrix.Translation(-piv) @ m
    pb.matrix = a.matrix_world.inverted() @ m
    bpy.context.view_layer.update()


def _plant(a, feet, side, at, toe_deg, lift=0.0, knee=None, heel=0.0, ball=None):
    """A foot to `at` (its ankle's place: x, y offsets from where it stood, z lift), toes turned toe_deg outward,
    the knee toward its toes (or `knee`, a world point); heel: the heel up off the floor (m), the ball staying down
    (a pivot, a push off); ball: the ball's place outright (kneeling, lying: the foot laid as it lies)."""
    ank0, ball_rel = feet[side]
    sg = 1.0 if side == "l" else -1.0
    rot = Matrix.Rotation(math.radians(sg * toe_deg), 3, 'Z')
    ank = ank0 + Vector((at[0], at[1], lift + heel))
    br = rot @ ball_rel
    bp = (ank - Vector((0.0, 0.0, heel)) + br) if ball is None else ball
    if lift > 0.0 and ball is None:
        bp.z = max(bp.z, ank0.z + ball_rel.z + lift * 0.6)
    pole = knee if knee is not None else ank + Vector((0.0, 0.0, 0.45)) + rot @ Vector((0.0, -0.7, 0.0))
    SC._leg_to(a, side, ank, bp, pole)


def _arms_guard(a, k=0.0, skip=()):
    chin = SC.head_of(a, "head") + Vector((0.0, -0.12, -0.08))
    for side, sg in (("l", 1.0), ("r", -1.0)):
        if side in skip:
            continue
        w = chin + Vector((sg * 0.1, -0.13 if side == "l" else -0.04, -0.06 + 0.01 * k))
        SM.arm_to(a, side, w, Vector((sg * 0.6, 0.3, -1.0)), w + Vector((0.0, -0.06, 0.1)))
        SC.curl_fingers(a, side, 80.0, 40.0)


def _reach(a, side, w, frac=0.97):
    """w brought within the arm's reach of its shoulder (a straight arm, not quite locked): past it the two-bone IK
    can only fold. The reach beyond that comes from the body: the hips, the shoulders, the weight."""
    sh = SC.head_of(a, "upperarm_" + side)
    L = (SC.head_of(a, "lowerarm_" + side) - sh).length + (SC.head_of(a, "hand_" + side) - SC.head_of(a, "lowerarm_" + side)).length
    d = w - sh
    return sh + d * (L * frac / d.length) if d.length > L * frac else w


def _guard_wrist(a, side):
    sg = 1.0 if side == "l" else -1.0
    chin = SC.head_of(a, "head") + Vector((0.0, -0.12, -0.08))
    return chin + Vector((sg * 0.1, -0.13 if side == "l" else -0.04, -0.06))


def _stance(a, shift=0.0, turn=0.0, low=0.0, k=0.0, feet_at=None, toes=None, travel=None, heels=None):
    """The fighting stance, planted: the left foot ~18 cm ahead and the right ~16 back, a shoulder's width apart,
    the front toes in a little and the back ones out (side-on), knees bent (hips 7 cm down + low), the hips turned
    18° side-on (+ turn: + brings the left shoulder on, - the right), the chest leaning a little in; shift moves the
    weight forward (-) or back (+) in metres; k a breath. feet_at: {side: (x, y, lift)} the feet's own moves;
    travel: (x, y) the body's own move over its feet (a step, a dodge)."""
    feet = _rest_feet(a)
    base = {"l": (-0.01, -0.17, 0.0), "r": (0.0, 0.15, 0.0)}
    tv = travel or (0.0, 0.0)
    _pelvis(a, Vector((tv[0], tv[1] + shift, -0.035 - low + 0.006 * k)), yaw=-(18.0 + turn))   # (SC.turn's sense)
    SC.turn(a, "spine_03", 'Z', -10.0 - 0.3 * turn)
    SC.turn(a, "spine_01", 'X', 8.0)
    for side in ("l", "r"):
        bx, by, bl = base[side]
        fx, fy, fl = (feet_at or {}).get(side, (0.0, 0.0, 0.0))
        tdeg = (toes or {}).get(side, -6.0 if side == "l" else 20.0)
        _plant(a, feet, side, (bx + fx, by + fy), tdeg, bl + fl, heel=(heels or {}).get(side, 0.0))
    return feet


def _guard_stance(a, k=0.0):
    """Fists up by the chin, elbows in, knees bent, the left foot ahead, the body turned a little side-on."""
    _stance(a, k=k)
    _arms_guard(a, k)


def _strike_curve(u, contact, hold=0.08):
    """0 → 1 by the contact (fast at the start, easing into it), held a moment, back to 0 by the end."""
    if u <= contact:
        return math.sin(0.5 * math.pi * u / contact)
    if u <= contact + hold:
        return 1.0
    return 1.0 - _smooth((u - contact - hold) / max(1.0 - contact - hold, 0.01))


def _straight(a, side, u, contact, reach, turn, weight, pivot_deg, drop=0.0):
    """A straight punch (a jab with the left, a cross with the right): the weight goes onto the front foot, the hip
    and the shoulder turn into it (the back heel pivoting for the cross), the arm drives out to the chin's height of a
    man in front and comes straight back; the other hand stays at the chin."""
    e = _strike_curve(u, contact)
    sg = 1.0 if side == "l" else -1.0
    t = sg * turn * e                                   # (+ brings the left shoulder on: a jab; - the right: a cross)
    toes = {"r": 20.0 + pivot_deg * e} if side == "r" else None
    _stance(a, shift=-weight * e, turn=t, low=0.015 * e, toes=toes,
            heels={"r": 0.07 * e * min(1.0, pivot_deg / 30.0)} if side == "r" else None)
    SC.turn(a, "spine_02", 'Z', 0.6 * t)
    SC.turn(a, "spine_01", 'X', 5.0 * e)
    _arms_guard(a, skip=(side,))
    sh = SC.head_of(a, "upperarm_" + side)
    out = _reach(a, side, sh + Vector((-sg * 0.1, -reach, 0.03 - drop)))
    home = _guard_wrist(a, side)
    w = _reach(a, side, home.lerp(out, e))
    SM.arm_to(a, side, w, Vector((sg * 0.7, 0.3, -0.7 + 0.5 * e)), w + Vector((0.0, -0.1, 0.0)))
    SC.curl_fingers(a, side, 88.0, 50.0)


def jab(a, u):
    _straight(a, "l", u, STRIKES["Jab"][1], 0.55, 10.0, 0.03, 0.0)


def cross(a, u):
    _straight(a, "r", u, STRIKES["Cross"][1], 0.64, 32.0, 0.07, 35.0)


def punch(a, u):
    cross(a, u)


def hook(a, u, side="l"):
    """A hook: a small load (the weight onto that side, turned open), then the hips whip round and carry the arm, the
    elbow up level with the fist, round in a short flat arc to the chin of a man in front; the foot on that side
    pivots on its ball (the back heel up for a right)."""
    c = STRIKES["Hook"][1]
    sg = 1.0 if side == "l" else -1.0
    if u < 0.25:                                        # the load
        e_load, e = _smooth(u / 0.25), 0.0
    else:
        e_load = 1.0 - _smooth((u - 0.25) / 0.25)
        e = _strike_curve((u - 0.25) / 0.75, (c - 0.25) / 0.75, 0.06)
    t = sg * (-10.0 * e_load + 28.0 * e)               # (+: the left side comes through)
    toes = {"l": -6.0 - 35.0 * e} if side == "l" else {"r": 20.0 + 40.0 * e}
    _stance(a, shift=-0.03 * e_load - 0.04 * e, turn=t, low=0.02 * e_load, toes=toes,
            heels={"r": 0.06 * e} if side == "r" else None)
    SC.turn(a, "spine_02", 'Z', 0.7 * t)
    _arms_guard(a, skip=(side,))
    sh = SC.head_of(a, "upperarm_" + side)
    ang = math.radians(10.0 + 75.0 * e)                  # (round from his side across to the front)
    out = sh + Vector((sg * (0.42 * math.cos(ang) - 0.2), -0.42 * math.sin(ang) - 0.05, 0.0))
    home = _guard_wrist(a, side)
    w = _reach(a, side, home.lerp(out, min(1.0, e * 1.2)), 0.9)
    SM.arm_to(a, side, w, w + Vector((sg * 0.9, 0.3, 0.35)), w + Vector((-sg * 0.12, -0.04, 0.0)))
    SC.curl_fingers(a, side, 88.0, 50.0)


def hook_r(a, u):
    hook(a, u, "r")


def jab_r(a, u):
    """A quick right: straight from the guard, short, no big pivot (to keep a man off)."""
    _straight(a, "r", u, STRIKES["JabR"][1], 0.52, 14.0, 0.03, 10.0)


def uppercut(a, u):
    """A right uppercut: the knees dip and the right shoulder drops back (the load), then the legs drive up, the hips
    turn through, and the fist comes up the middle, the elbow bent under it, to the chin of a man in front."""
    c = STRIKES["Uppercut"][1]
    if u < 0.3:
        lo, e = _smooth(u / 0.3), 0.0
    else:
        lo = 1.0 - _smooth((u - 0.3) / 0.2)
        e = _strike_curve((u - 0.3) / 0.7, (c - 0.3) / 0.7, 0.08)
    t = 10.0 * lo - 26.0 * e
    _stance(a, shift=-0.04 * e, turn=t, low=0.07 * lo - 0.02 * e, toes={"r": 20.0 + 35.0 * e}, heels={"r": 0.06 * e})
    SC.turn(a, "spine_02", 'Z', 0.6 * t)
    SC.turn(a, "spine_01", 'X', 6.0 * lo - 6.0 * e)
    _arms_guard(a, skip=("r",))
    sh = SC.head_of(a, "upperarm_r")
    low_ = sh + Vector((0.08, -0.14, -0.36))
    top = sh + Vector((0.12, -0.36, -0.02))
    g = _guard_wrist(a, "r")
    w = _reach(a, "r", g.lerp(low_, lo) if e <= 0.0 else low_.lerp(top, e), 0.9)
    SM.arm_to(a, "r", w, w + Vector((-0.35, 0.25, -1.0)), w + Vector((0.0, -0.04, 0.12)))
    SC.curl_fingers(a, "r", 90.0, 50.0)


def _path(keys, u):
    """A point along keyed (u, (x, y, z)) positions, smoothstep between."""
    for i in range(len(keys) - 1):
        if u <= keys[i + 1][0]:
            f = _smooth((u - keys[i][0]) / max(keys[i + 1][0] - keys[i][0], 1e-4))
            p, q = keys[i][1], keys[i + 1][1]
            return Vector(tuple(p[j] + (q[j] - p[j]) * f for j in range(3)))
    return Vector(keys[-1][1])


def _kick_leg(a, feet, ankle_off, ball_dir, pole_dir):
    """The right leg to a kick: its ankle at ankle_off from where it stood (clamped to the leg's reach from the hip:
    past it the knee could only fold), the foot along ball_dir, the knee toward pole_dir."""
    ank0 = feet["r"][0]
    hip = SC.head_of(a, "thigh_r")
    L = (SC.head_of(a, "calf_r") - hip).length + (SC.head_of(a, "foot_r") - SC.head_of(a, "calf_r")).length
    w = ank0 + ankle_off
    d = w - hip
    if d.length > L * 0.985:
        w = hip + d * (L * 0.985 / d.length)
    SC._leg_to(a, "r", w, w + Vector(ball_dir).normalized() * 0.14, w + Vector(pole_dir))


def _balance_arm(a, side, e):
    """The arm on the kicking side, eased down from the guard by e (0..1) to balance him: close by the ribs, the
    elbow bent and behind, the fist loosely closed and in line with the forearm (never flung out)."""
    sg = 1.0 if side == "l" else -1.0
    sh = SC.head_of(a, "upperarm_" + side)
    g = _guard_wrist(a, side)
    low_ = sh + Vector((sg * 0.06, -0.16, -0.36))
    w = g.lerp(low_, e)
    el = sh + Vector((sg * 0.03, 0.22, -0.25))          # (the elbow's way: down and back along the body, not out)
    SM.arm_to(a, side, w, el, w + (w - el).normalized() * 0.1)
    SC.curl_fingers(a, side, 80.0 - 20.0 * e, 40.0)


def front_kick(a, u):
    """A push kick with the right: the knee comes up (the chamber), the hips drive forward and the leg straightens,
    the ball of the foot into a man's middle, the body leaning back over the standing leg; the leg comes back to the
    chamber and steps down where it was. The guard stays up."""
    c = STRIKES["FrontKick"][1]
    e = _strike_curve(max(0.0, (u - 0.25) / 0.75), (c - 0.25) / 0.75, 0.08) if u > 0.25 else 0.0
    up = _smooth(u / 0.25) if u < 0.25 else (1.0 if u < 0.8 else 1.0 - _smooth((u - 0.8) / 0.2))
    feet = _stance(a, shift=-0.07 * e, turn=-8.0 * up, low=0.04 * up, toes={"l": 10.0 * up})   # (the standing knee bent)
    SC.turn(a, "spine_01", 'X', -14.0 * e)
    knee = (0.0, -0.08, 0.5)
    out = (0.02, -0.72, 0.78)
    off = Vector((0.0, 0.15, 0.0)).lerp(Vector(knee), up).lerp(Vector(out), e)
    _kick_leg(a, feet, off, (0.0, -0.6 - 0.4 * e, 0.6 * e - 0.3 * (1.0 - e)), (0.0, -1.0, 0.6))
    _arms_guard(a, skip=("r",))                         # (the left guards the face, the right eases down to balance)
    _balance_arm(a, "r", 0.6 * up)


def round_kick(a, u, name):
    """A round kick with the right: the front foot turns out on its ball and the hips turn through, the leg comes
    round from behind in a flat arc, the shin into the man's thigh (LowKick) or his ribs (BodyKick: higher, the body
    leaning away, the front heel up), through, and back down to the stance. The guard stays up; the right arm swings
    down and back against it, as a man's does."""
    c = STRIKES[name][1]
    high = name == "BodyKick"
    h = 0.95 if high else 0.5
    e = _strike_curve(u, c, 0.06)
    keys = [(0.0, (0.0, 0.15, 0.0)), (0.22, (-0.3, 0.05, 0.3 + 0.2 * high)), (c, (0.4, -0.8, h)),
            (c + 0.12, (0.55, -0.5, h - 0.1)), (0.8, (-0.1, 0.0, 0.25)), (1.0, (0.0, 0.15, 0.0))]
    off = _path(keys, u)
    t = -(45.0 + 15.0 * high) * e
    lift = _smooth(u / 0.22) if u < 0.22 else (1.0 if u < 0.8 else 1.0 - _smooth((u - 0.8) / 0.2))
    feet = _stance(a, shift=-0.03 * e, turn=t, low=0.02 + 0.03 * lift, toes={"l": -6.0 + (60.0 + 15.0 * high) * e},
                   heels={"l": 0.05 * e * high})
    SC.turn(a, "spine_02", 'Z', 0.5 * t)
    SC.turn(a, "spine_01", 'Y', -(6.0 + 4.0 * high) * e)  # (leaning away from the kick: enough to balance, not to fall)
    _kick_leg(a, feet, off, (0.6, -0.5, -0.2), (0.4, -0.7, 0.5))
    _arms_guard(a, skip=("r",))
    _balance_arm(a, "r", e)


def knee_strike(a, u):
    """Close in: both hands reach to his shoulders (the clinch), the right knee drives up and forward into his
    middle as the hands pull down, the hips push in; the knee comes back down to the stance."""
    c = STRIKES["KneeStrike"][1]
    e = _strike_curve(u, c, 0.08)
    reach = _smooth(u / 0.3) if u < 0.3 else (1.0 if u < 0.7 else 1.0 - _smooth((u - 0.7) / 0.3))
    feet = _stance(a, shift=-0.06 * e, turn=-10.0 * e, low=0.02 + 0.025 * e)
    SC.turn(a, "spine_01", 'X', 6.0 * e)
    knee_at = Vector((0.02, -0.25 - 0.15 * e, 0.12 + 0.3 * e))
    _kick_leg(a, feet, Vector((0.0, 0.15, 0.0)).lerp(knee_at, e), (0.0, 0.2, -1.0), (0.0, -1.0, 0.8))
    for side, sg in (("l", 1.0), ("r", -1.0)):           # (the hands on his shoulders, pulling him onto it)
        g = _guard_wrist(a, side)
        sh = SC.head_of(a, "upperarm_" + side)
        clinch = sh + Vector((-sg * 0.05, -0.42, -0.02 - 0.12 * e))
        w = _reach(a, side, g.lerp(clinch, reach), 0.95)
        SM.arm_to(a, side, w, w + Vector((sg * 0.5, 0.3, -0.8)), w + Vector((-sg * 0.05, -0.12, -0.04)))
        SC.curl_fingers(a, side, 55.0, 30.0)


def side_kick(a, u):
    """A side kick with the right: the front foot turns right round on its ball and the body turns side-on, the right
    knee comes up across (the chamber), the leg drives straight out heel first at his middle, the foot level and the
    toes turned down; back to the chamber and down. The body leans back over the standing leg just enough; the left
    arm guards, the right drops along the kicking leg to balance."""
    c = STRIKES["SideKick"][1]
    up = _smooth(u / 0.3) if u < 0.3 else (1.0 if u < 0.78 else 1.0 - _smooth((u - 0.78) / 0.22))
    e = _strike_curve(max(0.0, (u - 0.3) / 0.7), (c - 0.3) / 0.7, 0.08) if u > 0.3 else 0.0
    t = -55.0 * up
    feet = _stance(a, turn=t, low=0.05 * up, toes={"l": -6.0 + 70.0 * up})
    SC.turn(a, "spine_01", 'Y', -8.0 * e)
    chamber = Vector((0.12, -0.12, 0.5))
    out = Vector((0.18, -0.85, 0.7))
    off = Vector((0.0, 0.15, 0.0)).lerp(chamber, up).lerp(out, e)
    _kick_leg(a, feet, off, (0.8, -0.2, -0.3), (0.9, -0.3, 0.4))   # (the knee pointing across: the edge of the foot leads)
    _arms_guard(a, skip=("r",))
    _balance_arm(a, "r", 0.8 * up)


def low_kick(a, u):
    round_kick(a, u, "LowKick")


def body_kick(a, u):
    round_kick(a, u, "BodyKick")


def guard_low(a, k):
    """The guard let down to the chest (out of wind): the same stance, the hands lower, the shoulders easing."""
    _stance(a, low=-0.01, k=k)
    chin = SC.head_of(a, "head") + Vector((0.0, -0.12, -0.08))
    for side, sg in (("l", 1.0), ("r", -1.0)):
        w = chin + Vector((sg * 0.13, -0.12 if side == "l" else -0.05, -0.3 + 0.01 * k))
        SM.arm_to(a, side, w, Vector((sg * 0.6, 0.3, -1.0)), w + Vector((0.0, -0.08, 0.08)))
        SC.curl_fingers(a, side, 70.0, 35.0)


def heavy(a, u):
    """The big right: the weight rocks back onto the back leg and the fist draws back by the ear (to 0.45: you can
    see it coming), then everything goes through it: the back heel turns, the hips and shoulders whip round, the
    weight drives forward over the front knee, the fist arrives a little downward (0.58); a long way back."""
    c = STRIKES["Heavy"][1]
    if u < 0.45:
        lo, e = _smooth(u / 0.45), 0.0
    else:
        lo = 1.0 - _smooth((u - 0.45) / 0.13)
        e = _strike_curve((u - 0.45) / 0.55, (c - 0.45) / 0.55, 0.1)
    t = 14.0 * lo - 40.0 * e
    _stance(a, shift=0.06 * lo - 0.11 * e, turn=t, low=0.03 * lo + 0.03 * e, toes={"r": 20.0 + 55.0 * e},
            heels={"r": 0.09 * e})
    SC.turn(a, "spine_02", 'Z', 0.6 * t)
    SC.turn(a, "spine_01", 'X', -4.0 * lo + 9.0 * e)
    _arms_guard(a, skip=("r",))
    sh = SC.head_of(a, "upperarm_r")
    back = _guard_wrist(a, "r") + Vector((-0.05, 0.12, 0.05))
    out = _reach(a, "r", sh + Vector((0.12, -0.68, -0.03)))
    w = _reach(a, "r", _guard_wrist(a, "r").lerp(back, lo) if e <= 0.0 else back.lerp(out, e))
    SM.arm_to(a, "r", w, Vector((-0.8, 0.4, -0.3 + 0.6 * e)), w + Vector((0.0, -0.1, -0.02)))
    SC.curl_fingers(a, "r", 90.0, 50.0)


def block(a, k):
    """Forearms up before the face, the head down behind them, the weight back a little."""
    _stance(a, shift=0.03, low=0.02, k=k)
    SC.turn(a, "neck_01", 'X', 12.0)
    f = SC.head_of(a, "head") + Vector((0.0, -0.2, 0.0))
    for side, sg in (("l", 1.0), ("r", -1.0)):
        w = f + Vector((sg * 0.06, -0.04, 0.05))
        SM.arm_to(a, side, w, Vector((sg * 0.3, -0.2, -1.0)), w + Vector((0.0, 0.0, 0.15)))
        SC.curl_fingers(a, side, 80.0, 40.0)


def block_hit(a, u):
    """A blow taken on the guard: the arms are driven back into the face, the body rocks back over the back foot
    and comes forward again."""
    e = math.sin(0.5 * math.pi * u / 0.28) if u < 0.28 else 1.0 - _smooth((u - 0.28) / 0.72)
    _stance(a, shift=0.03 + 0.07 * e, turn=-6.0 * e, low=0.02 + 0.02 * e)
    SC.turn(a, "spine_01", 'X', -9.0 * e)
    SC.turn(a, "neck_01", 'X', 12.0 - 8.0 * e)
    f = SC.head_of(a, "head") + Vector((0.0, -0.2 + 0.07 * e, 0.0))
    for side, sg in (("l", 1.0), ("r", -1.0)):
        w = f + Vector((sg * 0.06, -0.04, 0.05))
        SM.arm_to(a, side, w, Vector((sg * 0.3, -0.2, -1.0)), w + Vector((0.0, 0.0, 0.15)))
        SC.curl_fingers(a, side, 80.0, 40.0)


def guard_break(a, u):
    """The guard knocked open: the arms thrown apart and up, the chest open, he rocks back onto his heel, and finds
    his guard again (by u 1)."""
    e = math.sin(math.pi * min(u / 0.35, 1.0) * 0.5) if u < 0.35 else 1.0 - _smooth((u - 0.45) / 0.55) if u > 0.45 else 1.0
    _stance(a, shift=0.12 * e, turn=-4.0 * e, low=0.01, feet_at={"l": (0.0, 0.06 * e, 0.03 * math.sin(math.pi * min(u / 0.45, 1.0)))})
    SC.turn(a, "spine_01", 'X', -14.0 * e)
    SC.turn(a, "neck_01", 'X', -10.0 * e)
    for side, sg in (("l", 1.0), ("r", -1.0)):
        g = _guard_wrist(a, side)
        sh = SC.head_of(a, "upperarm_" + side)
        open_ = sh + Vector((sg * 0.3, -0.24, -0.16))       # (thrown open, the elbows still bent)
        w = g.lerp(open_, e)
        SM.arm_to(a, side, w, Vector((sg * 0.7, 0.4, -0.6)), w + Vector((sg * 0.1, -0.1, 0.0)))
        SC.curl_fingers(a, side, 60.0, 30.0)


def _travel_feet(u, dist, d, lead, wins):
    """Where each foot is (x, y, lift) relative to the body while the body travels `dist` m along d (a unit (x, y)):
    the body's progress p = smooth(u); a foot stays put in the world till its window, then swings to the far end.
    lead: the foot that goes first ("l"/"r")."""
    p = _smooth(u)
    out = {}
    for side, (w0, w1) in (("l" if lead == "l" else "r", wins[0]), ("r" if lead == "l" else "l", wins[1])):
        f = _smooth((u - w0) / max(w1 - w0, 0.01))
        lift = 0.07 * math.sin(math.pi * f) if 0.0 < f < 1.0 else 0.0
        rel = (f - p) * dist
        out[side] = (d[0] * rel, d[1] * rel, lift)
    return out, (d[0] * p * dist, d[1] * p * dist)


TRAVEL = {"DodgeL": (10, 0.55, (1.0, 0.0), "l"), "DodgeR": (10, 0.55, (-1.0, 0.0), "r"),
          "DodgeB": (10, 0.5, (0.0, 1.0), "r"), "StaggerF": (14, 0.32, (0.0, 1.0), "r"),
          "StaggerL": (14, 0.28, (-1.0, 0.0), "r"), "StaggerR": (14, 0.28, (1.0, 0.0), "l"),
          "StaggerB": (14, 0.32, (0.0, -1.0), "l")}


def dodge_move(a, u, name):
    """A dodge: a quick step out of the line (left, right, or back), the head slipping the other way of the blow,
    knees deeper in the middle of it, then settled back in the stance where he's landed. The body's own travel is
    keyed only relative to the feet (the game moves him; see _travel_feet)."""
    n, dist, d, lead = TRAVEL[name]
    feet_at, tv = _travel_feet(u, dist, d, lead, ((0.0, 0.5), (0.3, 0.85)))
    e = math.sin(math.pi * u)
    _stance(a, low=0.08 * e, feet_at=feet_at, travel=(0.0, 0.0))
    SC.turn(a, "spine_02", 'Y', -16.0 * e * d[0])        # (the head slips: leaning the way he goes)
    SC.turn(a, "spine_01", 'X', 10.0 * e * (1.0 if d[1] == 0.0 else -1.0))
    _arms_guard(a)


def dodge(a, u):
    dodge_move(a, u, "DodgeB")


def stagger(a, u, name):
    """Hit and pushed: the head and chest snap away from the blow, the hips are shoved the way it went, the foot on
    that side steps to catch him, the other follows, the guard comes back up."""
    n, dist, d, lead = TRAVEL[name]
    feet_at, tv = _travel_feet(u, dist, d, lead, ((0.12, 0.5), (0.4, 0.85)))
    e = math.sin(math.pi * min(u / 0.3, 1.0) * 0.5) if u < 0.3 else 1.0 - _smooth((u - 0.3) / 0.7)
    _stance(a, shift=0.0, low=0.03 * e, feet_at=feet_at, turn=-10.0 * e * d[0])
    SC.turn(a, "spine_01", 'X', -16.0 * e * d[1])        # (from in front: back)
    SC.turn(a, "spine_02", 'Y', 14.0 * e * d[0])         # (from a side: away)
    SC.turn(a, "neck_01", 'X', -18.0 * e * max(d[1], 0.3))
    SC.turn(a, "neck_01", 'Y', 16.0 * e * d[0])
    for side, sg in (("l", 1.0), ("r", -1.0)):
        g = _guard_wrist(a, side)
        w = g + Vector((sg * 0.12 * e, 0.06 * e, -0.2 * e))
        SM.arm_to(a, side, w, Vector((sg * 0.6, 0.3, -1.0)), w + Vector((0.0, -0.06, 0.1)))
        SC.curl_fingers(a, side, 70.0, 35.0)


def hit_react(a, u):
    stagger(a, u, "StaggerF")


# On the floor: falls, lying, kneeling and getting up, each a few whole-body poses blended in u (smoothstep between):
#   (u, hips (dx, dy, dz, pitch, roll, yaw): their move from standing and their turn, degrees (pitch + forward,
#    roll + onto his left, yaw in SC.turn's sense),
#    left foot, right foot: (x, y, lift) from where each stood,
#    left hand, right hand: None (the guard), "knee" (on that knee), or (x, y, z) from the hips (z -2: on the floor),
#    knees (l, r): "toe" (over the toes), "front" (up in front), "floor" (down on the floor), "up" (lying, raised),
#                  "prone" (lying face down, straight),
#    head (pitch, turn): degrees)
# The floor: no bone goes under it (strip prints FLOOR for any that does: crowd_clips.py --strip --only combat).
ST = (0.0, (0.0, 0.0, -0.035, 0.0, 0.0, -18.0), (-0.01, -0.17, 0.0), (0.0, 0.15, 0.0), None, None, ("toe", "toe"), (0.0, 0.0))
LYING = (1.0, (0.0, 0.6, -0.87, -88.0, 0.0, 0.0), (0.14, -0.25, 0.0), (-0.16, -0.18, 0.0), (0.5, 0.25, -2.0), (-0.45, 0.4, -2.0), ("up", "up"), (16.0, 0.0))
PRONE = (1.0, (0.0, -0.05, -0.86, 88.0, 0.0, 0.0), (0.12, 0.85, 0.0), (-0.12, 0.85, 0.0), (0.34, -0.5, -2.0), (-0.3, -0.42, -2.0), ("prone", "prone"), (-4.0, 40.0))
KNEEL = (0.0, (0.0, 0.28, -0.45, 10.0, 0.0, 5.0), (0.02, -0.12, 0.0), (-0.08, 0.62, 0.0), "knee", (-0.16, -0.06, -0.22), ("front", "floor"), (-5.0, 0.0))
UP_TAIL = [(0.6,) + KNEEL[1:],
           (0.78, (0.0, 0.1, -0.22, 38.0, 0.0, 0.0), (0.02, -0.12, 0.0), (-0.06, 0.18, 0.0), "knee", "knee", ("front", "front"), (-15.0, 0.0)),
           (0.9, (0.0, 0.02, -0.08, 12.0, 0.0, -10.0), (0.0, -0.15, 0.0), (0.0, 0.15, 0.0), None, None, ("toe", "toe"), (0.0, 0.0)),
           (1.0,) + ST[1:]]

def _at(k, u):
    return (u,) + k[1:]


FLOORS = {
    "KnockDown": [ST,   # backward: driven back a step, the knees go, he sits with a hand back to the floor, onto his back
        (0.2, (0.0, 0.18, -0.08, -12.0, 0.0, -8.0), (-0.01, -0.1, 0.0), (0.0, 0.36, 0.0), (0.35, -0.05, 0.35), (-0.35, -0.05, 0.3), ("toe", "toe"), (-10.0, 0.0)),
        (0.45, (0.0, 0.42, -0.52, -18.0, 0.0, 0.0), (0.06, 0.0, 0.0), (-0.08, 0.22, 0.0), (0.3, 0.1, -0.2), (-0.28, 0.3, -2.0), ("front", "front"), (5.0, 0.0)),
        (0.65, (0.0, 0.55, -0.84, -35.0, 0.0, 0.0), (0.1, -0.22, 0.0), (-0.12, -0.15, 0.0), (0.3, 0.22, -2.0), (-0.3, 0.3, -2.0), ("up", "up"), (10.0, 0.0)),
        (0.82, (0.0, 0.6, -0.86, -70.0, 0.0, 0.0), (0.12, -0.25, 0.0), (-0.14, -0.2, 0.0), (0.42, 0.3, -2.0), (-0.4, 0.35, -2.0), ("up", "up"), (18.0, 0.0)),
        LYING],
    "FallF": [ST,       # forward: pushed from behind, a step, the knees go, hands out to the floor, down onto his front
        (0.2, (0.0, -0.12, -0.08, 18.0, 0.0, -8.0), (-0.01, -0.32, 0.04), (0.0, 0.15, 0.0), (0.3, -0.35, 0.3), (-0.3, -0.35, 0.3), ("toe", "toe"), (-5.0, 0.0)),
        (0.45, (0.0, -0.05, -0.5, 40.0, 0.0, 0.0), (0.05, -0.2, 0.0), (-0.05, 0.25, 0.0), (0.28, -0.55, -2.0), (-0.28, -0.55, -2.0), ("floor", "floor"), (-15.0, 0.0)),
        (0.7, (0.0, 0.0, -0.57, 70.0, 0.0, 0.0), (0.1, 0.55, 0.0), (-0.1, 0.55, 0.0), (0.3, -0.6, -2.0), (-0.3, -0.6, -2.0), ("floor", "floor"), (-20.0, 0.0)),
        PRONE],
    "FallSide": [ST,    # to his right: knocked sideways, the right arm to the floor, down on his hip and shoulder, over onto his back
        (0.2, (-0.12, 0.05, -0.1, 0.0, -12.0, -10.0), (0.02, -0.15, 0.05), (-0.22, 0.1, 0.0), (0.35, 0.0, 0.3), (-0.3, 0.0, 0.1), ("toe", "toe"), (0.0, 15.0)),
        (0.45, (-0.12, 0.2, -0.55, -10.0, -30.0, 0.0), (0.1, -0.1, 0.0), (-0.15, 0.15, 0.0), (0.2, -0.2, 0.1), (-0.45, 0.1, -2.0), ("front", "front"), (0.0, 20.0)),
        (0.72, (-0.08, 0.45, -0.84, -40.0, -45.0, 0.0), (0.04, -0.28, 0.0), (-0.2, -0.22, 0.0), (0.15, -0.2, -2.0), (-0.5, 0.05, -2.0), ("up", "up"), (10.0, 20.0)),
        LYING],
    "GetUp": [_at(LYING, 0.0),   # from his back: sits up, a hand behind, turns over onto his hands and knees, the right knee down and the left foot planted, hands on the knees, up
        (0.15, (0.0, 0.5, -0.82, -35.0, 0.0, 15.0), (0.0, 0.05, 0.0), (-0.2, 0.05, 0.0), (0.3, 0.0, -2.0), (-0.25, 0.25, -2.0), ("up", "up"), (0.0, 0.0)),
        (0.32, (0.05, 0.4, -0.55, 45.0, 0.0, 50.0), (0.25, 0.55, 0.0), (0.0, 0.75, 0.0), (0.15, -0.5, -2.0), (-0.3, -0.4, -2.0), ("floor", "floor"), (-20.0, 0.0)),
        (0.45, (0.0, 0.35, -0.48, 72.0, 0.0, 25.0), (0.12, 0.8, 0.0), (-0.12, 0.8, 0.0), (0.22, -0.55, -2.0), (-0.22, -0.55, -2.0), ("floor", "floor"), (-30.0, 0.0))] + UP_TAIL,
    "GetUpF": [_at(PRONE, 0.0),  # from his front: pushes up on his hands, onto his knees, the right knee down, up
        (0.22, (0.0, -0.02, -0.72, 80.0, 0.0, 0.0), (0.12, 0.85, 0.0), (-0.12, 0.85, 0.0), (0.25, -0.5, -2.0), (-0.25, -0.5, -2.0), ("prone", "prone"), (-25.0, 0.0)),
        (0.42, (0.0, 0.15, -0.48, 72.0, 0.0, 0.0), (0.12, 0.6, 0.0), (-0.12, 0.6, 0.0), (0.22, -0.55, -2.0), (-0.22, -0.55, -2.0), ("floor", "floor"), (-30.0, 0.0))] + UP_TAIL,
}


def _keys_at(keys, u):
    for i in range(len(keys) - 1):
        if u <= keys[i + 1][0]:
            f = _smooth((u - keys[i][0]) / max(keys[i + 1][0] - keys[i][0], 1e-4))
            return keys[i], keys[i + 1], f
    return keys[-1], keys[-1], 1.0


def _mix(p, q, f):
    """Between two keys' values: numbers blended; a hand going to or from the guard or a knee hands over halfway."""
    if isinstance(p, tuple) and isinstance(q, tuple) and len(p) == len(q):
        return tuple(p[i] + (q[i] - p[i]) * f for i in range(len(p)))
    return q if f > 0.5 else p


def _floor_z(feet):
    return min(feet["l"][0].z + feet["l"][1].z, feet["l"][0].z) - 0.02


def _body(a, keys, u, breath=0.0):
    k0, k1, f = _keys_at(keys, u)
    hips = _mix(k0[1], k1[1], f)
    fl, fr = _mix(k0[2], k1[2], f), _mix(k0[3], k1[3], f)
    knees = k1[6] if f > 0.5 else k0[6]
    head = _mix(k0[7], k1[7], f)
    feet = _rest_feet(a)
    floor = _floor_z(feet)
    up = max(0.0, 1.0 - abs(hips[2] + 0.035) / 0.25) * max(0.0, 1.0 - abs(hips[3]) / 25.0)   # (how much he's standing)
    _pelvis(a, Vector((hips[0], hips[1], hips[2])), pitch=hips[3], roll=hips[4])
    SC.turn(a, "pelvis", 'Z', -hips[5])                 # (yaw, in SC.turn's sense: the stance's side-on is -18 → +18)
    SC.turn(a, "spine_03", 'Z', -10.0 * up)
    SC.turn(a, "spine_01", 'X', 8.0 * up + 3.0 * breath)
    pb = a.pose.bones.get("pelvis")
    hp = (a.matrix_world @ pb.matrix).translation.copy()
    for side, at in (("l", fl), ("r", fr)):
        mode = knees[0 if side == "l" else 1]
        hip = SC.head_of(a, "thigh_" + side)
        ank = feet[side][0] + Vector((at[0], at[1], at[2]))
        knee, ball = None, None
        if mode == "up":
            knee = hp + Vector((0.0, -0.9, 0.7))
        elif mode == "side":                            # (cross-legged: the knees out to the sides, low)
            sg = 1.0 if side == "l" else -1.0
            knee = hip + Vector((sg * 1.0, -0.6, -0.2))
        elif mode == "front":
            knee = ank + Vector((0.0, -1.0, 0.4))
        elif mode in ("floor", "prone"):
            knee = (hip + ank) * 0.5 + Vector((0.0, -0.3 if mode == "floor" else 0.0, -1.0))
            ball = ank + Vector((0.0, 0.12, -0.05))     # (toes behind, curled under / laid on the floor)
            ball.z = max(ball.z, floor + 0.02)
        _plant(a, feet, side, at[:2], 10.0 if mode == "up" else (-6.0 if side == "l" else 20.0), at[2], knee, ball=ball)
    SC.turn(a, "neck_01", 'X', head[0])
    SC.turn(a, "neck_01", 'Z', head[1])
    for side, sg in (("l", 1.0), ("r", -1.0)):
        h = _mix(k0[4 if side == "l" else 5], k1[4 if side == "l" else 5], f)
        if h is None:
            g = _guard_wrist(a, side)
            SM.arm_to(a, side, g, Vector((sg * 0.6, 0.3, -1.0)), g + Vector((0.0, -0.06, 0.1)))
            SC.curl_fingers(a, side, 80.0, 40.0)
            continue
        if h == "knee":
            w = SC.head_of(a, "calf_" + side) + Vector((0.0, -0.06, 0.07))
            pt = w + Vector((0.0, -0.12, -0.06))
        else:
            w = hp + Vector(h)
            on_floor = w.z <= floor + 0.07
            w.z = max(w.z, floor + 0.07)
            pt = w + Vector((sg * 0.03, -0.15, -0.02 if on_floor else 0.0))
        w = _reach(a, side, w, 0.98)
        SM.arm_to(a, side, w, w + Vector((sg * 0.5, 0.3, 0.6)), pt)
        SC.curl_fingers(a, side, 8.0, 5.0)


def floor_move(a, u, name, breath=0.0):
    _body(a, FLOORS[name], u, breath)


def knock_down(a, u):
    floor_move(a, u, "KnockDown")


def get_up(a, u):
    floor_move(a, u, "GetUp")


def down_idle(a, k, name="KnockDown"):
    """Lying (on his back, or his front after FallF), breathing: the chest rising, the head a little."""
    _body(a, FLOORS[name], 1.0, k)
    SC.turn(a, "spine_02", 'X', 2.5 * k)


def kneel_idle(a, k):
    """On one knee, a hand on it, getting his breath."""
    _body(a, [KNEEL], 0.0, k)
    SC.turn(a, "spine_02", 'X', 3.0 * k)


def sit_floor(a, k, pray=False):
    """Sitting on the floor cross-legged (a temple, a home): the hips on the floor, the back upright with a little
    lean, the shins crossed in front (the left under the right), the knees out and low; the hands on the knees, or
    joined at the chest in prayer; breathing."""
    _body(a, [(0.0, (0.0, 0.08, -0.84, 4.0, 0.0, 0.0), (-0.16, -0.3, 0.0), (0.16, -0.34, 0.05),
               "knee", "knee", ("side", "side"), (6.0, 0.0))], 0.0, k)
    SC.turn(a, "spine_02", 'X', 2.0 * k)
    if pray:                                            # (palms together before the chest, the elbows soft and out)
        c = SC.head_of(a, "spine_03") + Vector((0.0, -0.22, 0.02))
        for side, sg in (("l", 1.0), ("r", -1.0)):
            w = c + Vector((sg * 0.02, 0.0, 0.0))
            SM.arm_to(a, side, w, w + Vector((sg * 0.6, 0.2, -0.5)), w + Vector((0.0, -0.02, 0.15)))
            SC.curl_fingers(a, side, 5.0, 5.0)


def relief(a, k):
    """It's over: bent over, hands on his knees, getting his breath."""
    _body(a, [(0.0, (0.0, 0.08, -0.1, 32.0, 0.0, 0.0), (0.02, -0.04, 0.0), (-0.02, 0.06, 0.0), "knee", "knee", ("front", "front"), (-18.0 + 4.0 * k, 0.0))], 0.0, k)
    SC.turn(a, "spine_02", 'X', 4.0 * k)

def guard_step(a, u, d, lead):
    """Footwork in the guard: step and drag (the lead foot goes first, the other follows; never crossing), 36 cm a
    cycle, the hips bobbing a little; the guard up."""
    S = 0.36
    out = {}
    for side, (w0, w1) in (("l" if lead == "l" else "r", (0.0, 0.32)), ("r" if lead == "l" else "l", (0.45, 0.8))):
        if w0 <= u <= w1:
            f = _smooth((u - w0) / (w1 - w0))
            o = -S / 2 + S * f
            lift = 0.05 * math.sin(math.pi * f)
        else:
            tau = ((u - w1) % 1.0) / (1.0 - (w1 - w0))
            o = S / 2 - S * tau
            lift = 0.0
        out[side] = (d[0] * o, d[1] * o, lift)
    _stance(a, low=0.01 * math.sin(2.0 * math.pi * u * 2.0), feet_at=out)
    _arms_guard(a)


STEPS = {"GuardStepF": ((0.0, -1.0), "l"), "GuardStepB": ((0.0, 1.0), "r"), "GuardStepL": ((1.0, 0.0), "l"),
         "GuardStepR": ((-1.0, 0.0), "r")}


def combat_clips(arm):
    """The hand-to-hand clips (Karthik and the men share them: the same rig)."""
    SC.clip(arm, "Guard", [(1 + 12 * i, (lambda kk: (lambda a: _guard_stance(a, kk)))(k)) for i, k in enumerate((-1, 1, -1))])
    for name, fn in (("Jab", jab), ("Cross", cross), ("Punch", punch), ("Hook", hook), ("Heavy", heavy),
                     ("JabR", jab_r), ("HookR", hook_r), ("Uppercut", uppercut),
                     ("FrontKick", front_kick), ("LowKick", low_kick), ("BodyKick", body_kick),
                     ("KneeStrike", knee_strike), ("SideKick", side_kick)):
        n = STRIKES[name][0]
        SC.clip(arm, name, [(1 + i, (lambda ff, uu: (lambda a: ff(a, uu)))(fn, i / float(n - 1))) for i in range(n)])
    SC.clip(arm, "Haymaker", [(1 + 2 * i, (lambda uu: (lambda a: haymaker(a, uu)))(i / 14.0)) for i in range(15)])
    SC.clip(arm, "Block", [(1 + 12 * i, (lambda kk: (lambda a: block(a, kk)))(k)) for i, k in enumerate((-1, 1, -1))])
    SC.clip(arm, "BlockHit", [(1 + i, (lambda uu: (lambda a: block_hit(a, uu)))(i / 9.0)) for i in range(10)])
    SC.clip(arm, "GuardBreak", [(1 + i, (lambda uu: (lambda a: guard_break(a, uu)))(i / 19.0)) for i in range(20)])
    for name in ("DodgeL", "DodgeR", "DodgeB"):
        n = TRAVEL[name][0]
        SC.clip(arm, name, [(1 + i, (lambda nn, uu: (lambda a: dodge_move(a, uu, nn)))(name, i / float(n - 1))) for i in range(n)])
    SC.clip(arm, "Dodge", [(1 + i, (lambda uu: (lambda a: dodge(a, uu)))(i / 9.0)) for i in range(10)])
    for name in ("StaggerF", "StaggerL", "StaggerR", "StaggerB"):
        n = TRAVEL[name][0]
        SC.clip(arm, name, [(1 + i, (lambda nn, uu: (lambda a: stagger(a, uu, nn)))(name, i / float(n - 1))) for i in range(n)])
    SC.clip(arm, "HitReact", [(1 + i, (lambda uu: (lambda a: hit_react(a, uu)))(i / 13.0)) for i in range(14)])
    for name, n in (("KnockDown", 19), ("FallF", 19), ("FallSide", 19), ("GetUp", 25), ("GetUpF", 25)):
        SC.clip(arm, name, [(1 + 2 * i, (lambda nn, uu: (lambda a: floor_move(a, uu, nn)))(name, i / float(n - 1))) for i in range(n)])
    for name, fn in (("DownIdle", lambda a, k: down_idle(a, k)), ("DownIdleF", lambda a, k: down_idle(a, k, "FallF")),
                     ("KneelIdle", kneel_idle), ("Relief", relief), ("GuardLow", guard_low),
                     ("SitFloor", lambda a, k: sit_floor(a, k)), ("SitFloorPray", lambda a, k: sit_floor(a, k, True))):
        SC.clip(arm, name, [(1 + 24 * i, (lambda ff, kk: (lambda a: ff(a, kk)))(fn, k)) for i, k in enumerate((-1, 1, -1))])
    for name, (d, lead) in STEPS.items():
        SC.clip(arm, name, [(1 + i, (lambda dd, ll, uu: (lambda a: guard_step(a, uu, dd, ll)))(d, lead, i / 16.0)) for i in range(17)])


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
    combat_clips(arm)          # a fight: crowd_clips.py combat section (Karthik and the men)
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
    cam.location = tuple(float(v) for v in sys.argv[sys.argv.index("--cam") + 1].split(",")) if "--cam" in sys.argv else (-1.6, -2.4, 1.3)
    cam.rotation_euler = (Vector((0, 0, 1.0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    os.makedirs(out_dir, exist_ok=True)
    combat = (("guard", lambda a: _guard_stance(a, 0)), ("guardlow", lambda a: guard_low(a, 0)), ("jab", lambda a: jab(a, 0.4)),
              ("cross", lambda a: cross(a, 0.45)), ("jabr", lambda a: jab_r(a, 0.4)), ("hook", lambda a: hook(a, 0.5)),
              ("hookr", lambda a: hook_r(a, 0.5)), ("upper_load", lambda a: uppercut(a, 0.28)), ("uppercut", lambda a: uppercut(a, 0.55)),
              ("heavy_wind", lambda a: heavy(a, 0.44)), ("heavy", lambda a: heavy(a, 0.6)), ("haywind", lambda a: haymaker(a, 0.55)),
              ("hayswing", lambda a: haymaker(a, 0.8)), ("block", lambda a: block(a, 0)), ("blockhit", lambda a: block_hit(a, 0.28)),
              ("guardbreak", lambda a: guard_break(a, 0.4)), ("dodgeL", lambda a: dodge_move(a, 0.5, "DodgeL")),
              ("dodgeB", lambda a: dodge_move(a, 0.5, "DodgeB")), ("staggerF", lambda a: stagger(a, 0.3, "StaggerF")),
              ("staggerB", lambda a: stagger(a, 0.3, "StaggerB")), ("staggerL", lambda a: stagger(a, 0.3, "StaggerL")),
              ("stepF", lambda a: guard_step(a, 0.2, (0.0, -1.0), "l")),
              ("fk_chamber", lambda a: front_kick(a, 0.25)), ("fk", lambda a: front_kick(a, 0.45)),
              ("lk_wind", lambda a: low_kick(a, 0.22)), ("lk", lambda a: low_kick(a, 0.5)),
              ("bk_wind", lambda a: body_kick(a, 0.22)), ("bk", lambda a: body_kick(a, 0.5)),
              ("sitfloor", lambda a: sit_floor(a, 0)), ("sitpray", lambda a: sit_floor(a, 0, True)),
              ("knee", lambda a: knee_strike(a, 0.45)), ("sk_chamber", lambda a: side_kick(a, 0.3)), ("sk", lambda a: side_kick(a, 0.5))) + tuple(
              ("%s_%02d" % (nm, int(uu * 100)), (lambda n2, u2: (lambda a: floor_move(a, u2, n2)))(nm, uu))
              for nm, us in (("KnockDown", (0.2, 0.45, 0.65, 0.82, 1.0)), ("FallF", (0.2, 0.45, 0.7, 1.0)),
                             ("FallSide", (0.2, 0.45, 0.72, 1.0)), ("GetUp", (0.15, 0.32, 0.45, 0.6, 0.78, 0.9)),
                             ("GetUpF", (0.22, 0.42))) for uu in us) + (("relief", lambda a: relief(a, 0)), ("kneel", lambda a: kneel_idle(a, 0)))
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else ""
    if "--names" in sys.argv:                           # (just these poses: --names a,b)
        keep = sys.argv[sys.argv.index("--names") + 1].split(",")
        combat = tuple(c for c in combat if c[0] in keep)
    for name, fn in combat if only == "combat" else (("phone", lambda a: phone(a, 1)), ("look", lambda a: phone_look(a, 1)),
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
        fz = min(SC.head_of(arm, "ball_l").z, SC.head_of(arm, "foot_l").z) - 0.02 if "ball_l" in arm.pose.bones else 0.0
        fn(arm)
        low = [(b.name, (arm.matrix_world @ b.head).z) for b in arm.pose.bones if (arm.matrix_world @ b.head).z < fz - 0.03]
        if only == "combat" and name.split("_")[0] in ("fk", "lk", "bk", "knee", "sk"):
            def bend(sd):
                th = SC.head_of(arm, "calf_" + sd) - SC.head_of(arm, "thigh_" + sd)
                ca = SC.head_of(arm, "foot_" + sd) - SC.head_of(arm, "calf_" + sd)
                return math.degrees(th.angle(ca))
            print("KNEE %s: standing knee bent %.0f deg, kicking knee %.0f deg; standing foot %.3f m off the floor, ankle at (%.2f, %.2f)" % (
                name, bend("l"), bend("r"), SC.head_of(arm, "ball_l").z - fz - 0.02, SC.head_of(arm, "foot_l").x, SC.head_of(arm, "foot_l").y), flush=True)
        if low and only == "combat":
            print("FLOOR %s: under the floor: %s" % (name, ", ".join("%s %.2f" % (n, z - fz) for n, z in low[:6])), flush=True)
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
