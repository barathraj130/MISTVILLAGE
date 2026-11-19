extends "res://scripts/drive/rider_ik.gd"
## Eating at the table with the right hand, South Indian home style (dine3d.gd drives it): over his "Sit" pose, each
## frame, after the animation. The rider's two-bone arms and hand turning (rider_ik.gd), with eating's own targets:
##   r_at, r_fingers, r_knuckles  the right hand: where its fingertips are (world), the way the fingers point, the line
##                                across the knuckles (the hand turned to them)
##   pinch                        0 open … 1 a morsel held between the thumb and the index and middle fingertips (the
##                                ring and little fingers tucked, as people eat with their fingers)
##   l_at, l_fingers, l_knuckles  the left hand: resting by the plate (flat, fingers forward), now and then moving
##   look_at                      where he looks (world): the plate, the morsel, ahead while he chews; the head and
##                                neck share the turn, the spine leans in (`lean`, radians) as he reaches
## It never crosses the hands: the left stays on its side of the plate.

var r_at := Vector3.ZERO
var r_fingers := Vector3.FORWARD
var r_knuckles := Vector3.RIGHT
var pinch := 0.0
var l_at := Vector3.ZERO
var l_fingers := Vector3.FORWARD
var l_knuckles := Vector3.RIGHT
var look_at_pt := Vector3.ZERO
var r_thumb := Vector3.LEFT             # which way each thumb points (world): the palm's facing (the right hand palm
var l_thumb := Vector3.RIGHT            #  down: its thumb to his left; the left hand palm down: its thumb to his right)
var r_palm := Vector3.DOWN              # the way each palm faces (world): with the fingers' way, the hand's whole pose;
var l_palm := Vector3.DOWN              #  _arm() turns the forearm and bends the wrist to it within what a wrist can do
var wrist_log := {}                     # (testing) the last solve per side: forearm roll, wrist twist, flexion, deviation
var lean_in := 0.0
var face_fwd := Vector3.FORWARD         # the way he faces (to the table), in the world (on and off: `active`)
var wrist_floor := -INF                 # the wrist never lower than this (world y): the hand stays above the plate
# Measured INSIDE the modification, just after the grip (Godot keeps a modifier's result only for drawing: read from
# outside, the bones are the animation's again, so the food would follow the wrong hand):
var pinch_world := Vector3.ZERO         # between the thumb tip and the index fingertip (where the food is held)
var pinch_gap := 0.0                    # how far apart they are (m)
var hold_size := 0.012                  # what's held: the thumb stops this short of the index fingertip (no squeezing
                                        # through the food: a 1.2 cm piece of poori, the test's ball)
var _corr := Vector3.ZERO               # the held food's offset from r_at last frame: the hand moved by it, so the food
                                        # (not the fingertip estimate) arrives where it's aimed: the lips, the masala

const FINGER_LEN := 0.085               # (wrist to the fingertips of a pinch, about)
var r_grip := "pinch"                   # the right hand's grip kind (eat_profiles.gd): pinch, scoop, spoon, wrap, hold
var l_grip := "pinch"
var l_pinch := 0.0                      # the left hand closing on what it holds (0 relaxed)
var l_grip_world := Vector3.ZERO
# The hand socket: what the hand holds is placed here, inside the solve, the same frame as the fingers (never a frame
# behind, never floating). held_mode: "" nothing; "pinch" at the grip's centre, turned with the hand (a piece, a
# spoon's handle); "upright" at the grip's centre, kept upright and tipped toward him by held_tilt (a tumbler, a
# glass); "both" between the two hands' grips, upright (a burger). held_basis: the thing's own turn in the hand.
var held: Node3D = null
var held_mode := ""
var held_basis := Basis.IDENTITY
var held_offset := Vector3.ZERO         # (in the hand's frame for "pinch"; in the world for the others)
var held_tilt := 0.0
var lips_local := Vector3.ZERO          # his lips in the head bone's frame (eater.gd measures them from the face's
var lips_world := Vector3.ZERO          #  mouth-pursing shape); where they are this frame, the head's turn in it
var aim_on := false                     # r_at is where the held thing's aim_local point (its own space) should be
var aim_local := Vector3.ZERO
var request_keep := false               # set when something is taken: on the next solve its place relative to the grip
                                        # is measured and kept from then on (no jump as the hand closes on it)
var _keep_rel := Transform3D.IDENTITY


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not active or weight < 0.005:
		return
	var right := face_fwd.cross(Vector3.UP).normalized()
	forward = face_fwd
	up = Vector3.UP
	# the body: leaning in over the plate as he reaches, the head and neck turned to what he's looking at
	_turn_bone(sk, "spine_02", right, -lean_in * 0.6)
	_turn_bone(sk, "spine_03", right, -lean_in * 0.4)
	_look(sk, right)
	if lips_local != Vector3.ZERO:
		var hb := sk.find_bone("head")
		lips_world = sk.global_transform * (sk.get_bone_global_pose(hb) * lips_local)
	# the right hand: the wrist where the fingers reach the target from, then turned, then the fingers
	var rf := r_fingers.normalized()
	var wrist := r_at - rf * FINGER_LEN - _corr + (_lift["r"] as Vector3)
	if wrist.y < wrist_floor:                          # (never the hand into the plate: the wrist held above it)
		wrist.y = wrist_floor
	grip = 0.0
	_arm(sk, "r", wrist, Vector3.DOWN * 1.0 + right * 0.3 - face_fwd * 0.1, rf, r_palm)   # (the elbow low, a little out)
	_grip(sk, "r", pinch, r_grip)
	_contact(sk, "r")
	var tt := _tip(sk, "thumb", "r")
	var it := _tip(sk, "index", "r")
	pinch_gap = tt.distance_to(it)
	pinch_world = sk.global_transform * _grip_centre(sk, "r", r_grip)
	# (what arrives at the target: the food in the fingers; or, holding something, its working point: a spoon's bowl,
	#  a tumbler's rim, a slice's tip; measured where it was placed last frame)
	var aimed := pinch_world
	if aim_on and held != null and is_instance_valid(held):
		aimed = held.global_transform * aim_local
	var err := aimed - r_at
	_corr = (_corr + err * 0.5).limit_length(0.16) if pinch > 0.5 else _corr * 0.85
	# the left: flat by the plate, fingers forward, the elbow out to his left and down (or holding: a burger's other
	# side, a bowl's rim)
	var lf := l_fingers.normalized()
	var l_target := l_at - lf * 0.07 - (_corr if held_mode == "both" and aim_on else Vector3.ZERO) + (_lift["l"] as Vector3)   # (two hands: moved together)
	_arm(sk, "l", l_target, Vector3.DOWN * 1.0 - right * 0.3 - face_fwd * 0.1, lf, l_palm)
	_grip(sk, "l", l_pinch, l_grip)
	_contact(sk, "l")
	l_grip_world = sk.global_transform * _grip_centre(sk, "l", l_grip)
	_place_held(sk)


## ---- contact: the hands never into the table, the plate, a katori, a tumbler, the food (the collision brief) ----
## Cheap contact constraints instead of physics queries for every finger: the solids are simple shapes (the table's
## top a plane; a plate, a katori, a bowl, a tumbler upright cylinders; the food on the plate soft domes), kept in
## the world by eater.gd each frame. After the grip, every finger joint and fingertip (about 25 points a hand) is
## measured against them:
##   a finger in a solid: that finger opened at its joints (less curl), a step at a time, until it rests on the
##     surface: it adapts, it doesn't freeze or poke through;
##   the palm or the knuckles in a solid (or a finger that can't open enough): the whole hand lifted (or moved out
##     of the cylinder) by the depth, eased over the next frames: the hand comes to rest on the surface;
##   the food: the fingertips may touch it (they pick it up), the palm and the knuckles may not go into it.
## `contact_log` (testing) keeps the deepest point left after the pass, per side.
var solids: Array = []                  # [{kind: "plane", y} | {kind: "cyl", c (base centre), r, h} | {kind: "dome", c, r, h}]
var held_solid: Node3D = null           # (what the hand holds: its own solid is skipped, the fingers wrap it)
var contact_log := {"r": 0.0, "l": 0.0, "r_before": 0.0, "l_before": 0.0}
var _lift := {"r": Vector3.ZERO, "l": Vector3.ZERO}
var debug_contact := false
var contact_warm := false               # (testing: measured only once the hands have settled)
const SKIN := 0.007                     # a finger's half-thickness: its centre line keeps this far from a surface


## How far a point is inside the solids and which way is out (world): the deepest one.
func _push(p: Vector3, food: bool) -> Vector3:
	var best := Vector3.ZERO
	for so in solids:
		var v := Vector3.ZERO
		match str(so["kind"]):
			"plane":
				var d := float(so["y"]) + SKIN - p.y
				if d > 0.0:
					v = Vector3.UP * d
			"cup":                                             # (an open vessel: its wall and rim are solid; inside
				if so.has("node") and so["node"] == held_solid:  #  is where fingers dip, into the sambar)
					continue
				var c2: Vector3 = so["c"]
				var dh2 := Vector2(p.x - c2.x, p.z - c2.z).length()
				var y2 := p.y - c2.y
				var r_out := float(so["r"]) + SKIN
				var r_in := float(so["r"]) - 0.004 - SKIN
				if dh2 < r_out and dh2 > r_in and y2 > -SKIN and y2 < float(so["h"]) + SKIN:
					var up_ := float(so["h"]) + SKIN - y2
					var out_ := r_out - dh2
					var in_ := dh2 - r_in
					var o2 := Vector2(p.x - c2.x, p.z - c2.z).normalized() if dh2 > 1e-4 else Vector2(1, 0)
					if up_ <= minf(out_, in_):
						v = Vector3.UP * up_
					elif out_ <= in_:
						v = Vector3(o2.x, 0.0, o2.y) * out_
					else:
						v = -Vector3(o2.x, 0.0, o2.y) * in_
			"cyl", "dome":
				if str(so["kind"]) == "dome" and not food:
					continue
				if so.has("node") and so["node"] == held_solid:
					continue
				var c: Vector3 = so["c"]
				var r := float(so["r"]) + SKIN
				var h := float(so["h"]) + SKIN
				var dh := Vector2(p.x - c.x, p.z - c.z)
				var y := p.y - c.y
				if dh.length() < r and y > -SKIN and y < h:
					var top := h - y                               # (out through the top, or out through the side)
					if str(so["kind"]) == "dome":                  # (a dome's height falls off toward its rim)
						top = h * sqrt(maxf(1.0 - pow(dh.length() / r, 2.0), 0.0)) - y
						if top <= 0.0:
							continue
					var side := r - dh.length()
					if top <= side:
						v = Vector3.UP * top
					else:
						var o := dh.normalized() if dh.length() > 1e-4 else Vector2(1, 0)
						v = Vector3(o.x, 0.0, o.y) * side
		if v.length() > best.length():
			best = v
	return best


func _which(p: Vector3, food: bool) -> String:
	var keep := solids
	for so in keep:
		solids = [so]
		if _push(p, food).length() > 0.01:
			solids = keep
			return "%s %s" % [so["kind"], str(so.get("c", so.get("y", "")))]
	solids = keep
	return "?"


func _contact(sk: Skeleton3D, side: String) -> void:
	if solids.is_empty():
		return
	var g := sk.global_transform
	var worst_before := 0.0
	var body := Vector3.ZERO
	# the fingers: each opened until its joints and tip are out (three steps at most)
	for fn in ["index", "middle", "ring", "pinky", "thumb"]:
		for step in 4:
			var deep := Vector3.ZERO
			for j in [2, 3]:
				var b := sk.find_bone("%s_%02d_%s" % [fn, j, side])
				if b >= 0:
					var v := _push(g * sk.get_bone_global_pose(b).origin, false)
					if v.length() > deep.length():
						deep = v
			var tv := _push(g * _tip(sk, fn, side), false)
			if tv.length() > deep.length():
				deep = tv
			if step == 0:
				worst_before = maxf(worst_before, deep.length())
			if deep.length() < 0.0005:
				break
			if step == 3:                                        # (a digit that can't turn out more: the hand moves)
				body = body if body.length() >= deep.length() else deep
				break
			# turned at its root so its tip moves out along the push (the finger opens, the thumb lifts alongside)
			var rb := sk.find_bone("%s_01_%s" % [fn, side])
			if rb < 0:
				break
			var rg := sk.get_bone_global_pose(rb)
			var arm := _tip(sk, fn, side) - rg.origin
			var push_l := (g.basis.inverse() * deep).normalized()
			var ax := arm.cross(push_l)
			if ax.length() < 1e-5 or arm.length() < 0.01:
				break
			var ang := clampf(deep.length() * 1.3 / arm.length(), 0.0, 0.7) * weight
			sk.set_bone_global_pose(rb, Transform3D(Basis(ax.normalized(), ang) * rg.basis, rg.origin))
	# the hand's own body: its root and the knuckles, against everything (the food too)
	var pts: Array = [g * sk.get_bone_global_pose(sk.find_bone("hand_" + side)).origin]
	for fn in ["index", "middle", "ring", "pinky"]:
		var b1 := sk.find_bone("%s_01_%s" % [fn, side])
		if b1 >= 0:
			pts.append(g * sk.get_bone_global_pose(b1).origin)
	for p in pts:
		var v := _push(p, true)
		worst_before = maxf(worst_before, v.length())
		if v.length() > body.length():
			body = v
	if contact_warm:
		contact_log[side + "_before"] = maxf(float(contact_log[side + "_before"]), worst_before)
	# eased: up to the depth (no jump), back down slowly once clear (so it settles on the surface, no buzzing)
	# the hand moved out by what's still in (built up over a few frames, so it never jumps), and once clear let back
	# down only slowly (it settles on the surface instead of bouncing off it)
	var cur: Vector3 = _lift[side]
	_lift[side] = (cur + body * 0.7).limit_length(0.12) if body.length() > 0.0005 else cur * 0.985
	var after := 0.0
	for fn in ["index", "middle", "ring", "pinky", "thumb"]:
		after = maxf(after, _push(g * _tip(sk, fn, side), false).length())
	for p in pts:
		after = maxf(after, _push(p, true).length())
	if debug_contact and after > 0.003:
		for fn in ["index", "middle", "ring", "pinky", "thumb"]:
			var q := g * _tip(sk, fn, side)
			if _push(q, false).length() > 0.003:
				print("CONTACT %s %s tip at %s pushed %s by %s" % [side, fn, q, _push(q, false), _which(q, false)])
		for i in pts.size():
			if _push(pts[i], true).length() > 0.003:
				print("CONTACT %s body point %d at %s pushed %s by %s" % [side, i, pts[i], _push(pts[i], true), _which(pts[i], true)])
	if contact_warm:
		contact_log[side] = maxf(float(contact_log[side]), after)
		contact_log[side + "_n"] = int(contact_log.get(side + "_n", 0)) + 1
		if after > 0.003:
			contact_log[side + "_over3"] = int(contact_log.get(side + "_over3", 0)) + 1


## ---- the arm, as an arm moves (the zombie-wrist brief) ----
## The rig has no forearm twist bones (upperarm, lowerarm, hand; checked in the glb) and its clips key only those
## three. The old way (rider_ik _limb, then _hand and _thumb_toward) turned each bone by the shortest arc from the
## clip's pose, so the upper arm's roll, and with it the elbow's hinge, was left to chance (the forearm bent a little
## sideways), and then turned the hand freely in the world, in up to three turns, with no limit: all of a palm's
## turning in the wrist (a candy-wrapper twist) and now and then the hand flipped about its knuckles.
## Now, in one solve:
##   1. the elbow placed by the two lengths toward the pole (as before);
##   2. the upper arm aimed at it AND rolled so the elbow's own hinge (measured from the rig's Idle clip: the lower
##      arm's local (0.99, 0, +-0.15)) is the normal of the plane the arm bends in: the forearm bends only about its
##      hinge, never sideways;
##   3. the hand's wanted pose (fingers' way and palm's facing) split into twist about the forearm and swing: the
##      twist clamped to what a forearm turns (pronation and supination), FOREARM_SHARE of it as the forearm's roll
##      (the radius turning: the lower arm bone about its own length), the rest at the wrist;
##   4. the swing at the wrist clamped to a wrist's range: flexion 70 deg, extension 55 deg, toward the thumb 20 deg,
##      toward the little finger 30 deg.
const HINGE := {"r": Vector3(0.99, 0.0, 0.15), "l": Vector3(0.99, 0.0, -0.15)}   # (in the lower arm's frame)
const PALM_N := {"r": Vector3(-0.65, 0.06, 0.75), "l": Vector3(0.65, 0.06, 0.75)}  # (in the hand's frame, at rest)
const FOREARM_SHARE := 0.7
var _prev_twist := {}
const TWIST_RANGE := Vector2(-1.75, 1.75)     # the whole turn, forearm and wrist, from the rig's own rest (radians)
const WRIST_TWIST := 0.45                     # what the wrist itself may add or take (radians, either way)
const FLEX := 1.22
const EXTEND := 0.96
const RADIAL := 0.35
const ULNAR := 0.52


static func _frame(a: Vector3, b: Vector3) -> Basis:      # (an orthonormal frame: a, then b made square to it)
	var x := a.normalized()
	var y := (b - x * b.dot(x)).normalized()
	return Basis(x, y, x.cross(y))


static func _twist_about(q: Quaternion, axis: Vector3) -> float:
	return wrapf(2.0 * atan2(Vector3(q.x, q.y, q.z).dot(axis), q.w), -PI, PI)


func _arm(sk: Skeleton3D, side: String, target_w: Vector3, pole_w: Vector3, fingers_w: Vector3, palm_w: Vector3) -> void:
	var bu := sk.find_bone("upperarm_" + side)
	var bl := sk.find_bone("lowerarm_" + side)
	var bh := sk.find_bone("hand_" + side)
	if bu < 0 or bl < 0 or bh < 0:
		return
	var inv := sk.global_basis.inverse()
	var t := sk.global_transform.affine_inverse() * target_w
	var pd := (inv * pole_w).normalized()
	var F := (inv * fingers_w).normalized()
	var P := (inv * palm_w).normalized()
	var ug := sk.get_bone_global_pose(bu)
	var s := ug.origin
	var a := sk.get_bone_rest(bl).origin.length()
	var b := sk.get_bone_rest(bh).origin.length()
	var to := t - s
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.004)
	var dir := to.normalized()
	var cos_s := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var bend := pd - dir * pd.dot(dir)
	if bend.length() < 0.001:
		bend = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	bend = bend.normalized()
	var e := s + dir * (a * cos_s) + bend * (a * sqrt(maxf(1.0 - cos_s * cos_s, 0.0)))
	var w := s + dir * d
	var ud := (e - s).normalized()
	var ld := (w - e).normalized()
	var H := ud.cross(ld)
	if H.length() < 1e-4:                                 # (straight: the hinge from the pole)
		H = ud.cross(bend)
	H = H.normalized()
	# 2. the upper and lower arm: each bone's length axis (local Y) along its segment, the hinge on H
	var hl: Vector3 = (HINGE[side] as Vector3).normalized()
	var lrest := sk.get_bone_rest(bl).basis.orthonormalized()
	var hu := lrest * hl                                  # (the hinge in the upper arm's frame: flexion keeps it)
	var Ug := _frame(ud, H) * _frame(Vector3.UP, hu).inverse()
	Ug = Basis(Ug.x, Ug.y, Ug.z)
	sk.set_bone_global_pose(bu, Transform3D(ug.basis.orthonormalized().slerp(Ug, weight), s))
	var Lg := _frame(ld, H) * _frame(Vector3.UP, hl).inverse()
	# 3. the hand's wanted frame (fingers along its Y, the palm's normal to P) and the turn from the forearm to it
	var pn: Vector3 = (PALM_N[side] as Vector3).normalized()
	F = F.lerp(ld, 0.3).normalized()                      # (the hand partly in the forearm's line, as a relaxed wrist is)
	var Hd := _frame(F, P) * _frame(Vector3.UP, pn).inverse()
	var hrest := sk.get_bone_rest(bh).basis.orthonormalized()
	var natural := Lg * hrest                             # (the hand as the forearm carries it, the wrist at rest)
	var Wq := (Hd * natural.inverse()).get_rotation_quaternion()
	var twist := _twist_about(Wq, ld)
	if _prev_twist.has(side):                             # (continuous with the last frame: never the long way round,
		var pt: float = _prev_twist[side]                 #  which flipped the hand over between -108 and +108 deg)
		twist = pt + wrapf(twist - pt, -PI, PI)
	var tw_c := clampf(twist, TWIST_RANGE.x, TWIST_RANGE.y)
	_prev_twist[side] = tw_c
	var fore := tw_c * FOREARM_SHARE
	Lg = Basis(ld, fore) * Lg                              # (the forearm rolled about its own length: the elbow stays)
	sk.set_bone_global_pose(bl, Transform3D(Lg, e))
	# 4. what's left at the wrist: its own twist (limited), then the swing (flexion, deviation) limited
	natural = Lg * hrest
	var Wq2 := (Hd * natural.inverse()).get_rotation_quaternion()
	var hy := natural.y.normalized()
	var wt := clampf(_twist_about(Wq2, hy), -WRIST_TWIST, WRIST_TWIST)
	var twisted := Basis(hy, wt) * natural
	var Sq := (Hd * twisted.inverse()).get_rotation_quaternion()
	var pn_now := (twisted * pn).normalized()             # (the palm's normal, the hand's length and its thumb side)
	var flex_ax := hy.cross(pn_now).normalized()          # (a turn about this bends the fingers toward the palm)
	var dev_ax := hy.cross(pn_now.cross(hy)).normalized().cross(hy)
	var thumb_side := (twisted * sk.get_bone_rest(sk.find_bone("index_01_" + side)).origin - twisted * sk.get_bone_rest(sk.find_bone("pinky_01_" + side)).origin).normalized()
	dev_ax = hy.cross(thumb_side).normalized()            # (a turn about this takes the fingers toward the thumb)
	var sw_ang := Sq.get_angle()
	var sw_axis := Sq.get_axis() if sw_ang > 1e-5 else flex_ax
	var flex := clampf(sw_ang * sw_axis.dot(flex_ax), -EXTEND, FLEX)
	var dev := clampf(sw_ang * sw_axis.dot(dev_ax), -ULNAR, RADIAL)
	var Hf := Basis(dev_ax, dev) * Basis(flex_ax, flex) * twisted
	var hg := sk.get_bone_global_pose(bh)
	sk.set_bone_global_pose(bh, Transform3D(hg.basis.orthonormalized().slerp(Hf.orthonormalized(), weight), sk.get_bone_global_pose(bh).origin))
	wrist_log[side] = Vector4(rad_to_deg(fore), rad_to_deg(wt), rad_to_deg(flex), rad_to_deg(dev))
	if absf(twist - tw_c) > 0.01:
		wrist_log[side + "_clamped"] = rad_to_deg(twist)
	else:
		wrist_log.erase(side + "_clamped")


## The head toward look_at_pt: the neck a third, the head the rest; yaw about up, pitch about his right.
func _look(sk: Skeleton3D, right: Vector3) -> void:
	var hb := sk.find_bone("head")
	if hb < 0:
		return
	var head_w: Vector3 = sk.global_transform * sk.get_bone_global_pose(hb).origin
	var to := look_at_pt - head_w
	if to.length() < 0.05:
		return
	to = to.normalized()
	var flat := Vector3(to.x, 0.0, to.z)
	var yaw := 0.0
	if flat.length() > 0.01:
		yaw = clampf(face_fwd.signed_angle_to(flat.normalized(), Vector3.UP), -0.7, 0.7)
	var pitch := clampf(asin(clampf(-to.y, -1.0, 1.0)), -0.05, 0.75)  # (+: down; never thrown back)
	_turn_bone(sk, "neck_01", Vector3.UP, yaw * 0.35)
	_turn_bone(sk, "neck_01", right, -pitch * 0.3)      # (about his right: a negative turn tips the face down)
	_turn_bone(sk, "head", Vector3.UP, yaw * 0.6)
	_turn_bone(sk, "head", right, -pitch * 0.55)


## The hand turned about its own fingers' line until the thumb points toward `want` (world): palm down or up, as
## the moment needs (the Sit clip's palms, left as they were, faced up on the table).
func _thumb_toward(sk: Skeleton3D, side: String, want: Vector3) -> void:
	var bh := sk.find_bone("hand_" + side)
	var bt := sk.find_bone("thumb_01_" + side)
	var bm := sk.find_bone("middle_01_" + side)
	if bh < 0 or bt < 0 or bm < 0:
		return
	var g := sk.get_bone_global_pose(bh)
	var f := (sk.get_bone_global_pose(bm).origin - g.origin).normalized()
	var off := sk.get_bone_global_pose(bt).origin - g.origin
	var w := (sk.global_basis.inverse() * want).normalized()
	var a := off - f * off.dot(f)
	var b := w - f * w.dot(f)
	if a.length() < 1e-4 or b.length() < 1e-4:
		return
	var ang := a.normalized().signed_angle_to(b.normalized(), f) * weight
	sk.set_bone_global_pose(bh, Transform3D(Basis(f, ang) * g.basis, g.origin))


## The hand-pose system (the grip): each finger joint bent about its OWN hinge (the bone's local X: the rig's bones
## point along local Y; checked from the rig), toward the palm (the side measured once from the rest pose: never
## backward, which spread the fingers open before), by amounts that make the eating grip:
##   p = 0   relaxed: the fingers a little curled, the thumb loose
##   p = 1   the pinch: the index bent to the thumb, the middle a little more (under the food, supporting it), the
##           ring and little fingers curled in, the thumb turned and bent until its tip meets the index fingertip
##           (two passes of a small solver: real opposition)
const GRIP := {"index": [[0.25, 0.35, 0.2], [0.55, 0.75, 0.55]], "middle": [[0.32, 0.42, 0.25], [0.7, 0.85, 0.6]],
	"ring": [[0.42, 0.52, 0.3], [1.1, 1.25, 0.85]], "pinky": [[0.5, 0.6, 0.35], [1.2, 1.3, 0.9]]}
	# (relaxed: a cascade, each finger a little more curled than the one before it, as a hand at rest lies)
var _flex := {}                          # bone → +1 / -1: the sign about local X that bends it toward the palm


func _flex_sign(sk: Skeleton3D, side: String, bone: String) -> float:
	if _flex.has(bone):
		return _flex[bone]
	var b := sk.find_bone(bone)
	var h := sk.find_bone("hand_" + side)
	var i1 := sk.find_bone("index_01_" + side)
	var p1 := sk.find_bone("pinky_01_" + side)
	var m1 := sk.find_bone("middle_01_" + side)
	var t2 := sk.find_bone("thumb_02_" + side)
	if b < 0 or h < 0 or i1 < 0 or p1 < 0 or m1 < 0 or t2 < 0:
		return 1.0
	# the palm's normal at rest (the side the thumb is on: a hand's palm faces the way its thumb leans)
	var hr := sk.get_bone_global_rest(h).origin
	var n := (sk.get_bone_global_rest(i1).origin - sk.get_bone_global_rest(p1).origin).cross(sk.get_bone_global_rest(m1).origin - hr).normalized()
	if n.dot(sk.get_bone_global_rest(t2).origin - hr) < 0.0:
		n = -n
	var palm := hr + n * 0.06 + (sk.get_bone_global_rest(m1).origin - hr) * 0.6
	var g := sk.get_bone_global_rest(b)
	var tip := g.origin + g.basis.y.normalized() * 0.03
	var out := 1.0
	var best := INF
	for sgn in [1.0, -1.0]:
		var r := Basis(g.basis.x.normalized(), sgn * 0.5)
		var t := g.origin + r * (tip - g.origin)
		if t.distance_to(palm) < best:
			best = t.distance_to(palm)
			out = sgn
	_flex[bone] = out
	return out


func _bend(sk: Skeleton3D, side: String, bone: String, ang: float) -> void:
	var b := sk.find_bone(bone)
	if b < 0 or absf(ang) < 0.0005:
		return
	var q := sk.get_bone_pose_rotation(b)
	sk.set_bone_pose_rotation(b, q * Quaternion(Vector3.RIGHT, _flex_sign(sk, side, bone) * ang * weight))


func _tip(sk: Skeleton3D, finger: String, side: String, along := 0.85) -> Vector3:
	var b2 := sk.find_bone("%s_02_%s" % [finger, side])
	var b3 := sk.find_bone("%s_03_%s" % [finger, side])
	if b2 < 0 or b3 < 0:
		return Vector3.ZERO
	var a := sk.get_bone_global_pose(b2).origin
	var c := sk.get_bone_global_pose(b3).origin
	return c + (c - a) * along                            # (the last joint's length again, about: the fingertip)


var _palm_n := {}                         # side → the palm's normal at rest (skeleton space)


func _palm_normal(sk: Skeleton3D, side: String) -> Vector3:
	if _palm_n.has(side):
		return _palm_n[side]
	var h := sk.get_bone_global_rest(sk.find_bone("hand_" + side)).origin
	var i1 := sk.get_bone_global_rest(sk.find_bone("index_01_" + side)).origin
	var p1 := sk.get_bone_global_rest(sk.find_bone("pinky_01_" + side)).origin
	var m1 := sk.get_bone_global_rest(sk.find_bone("middle_01_" + side)).origin
	var t2 := sk.get_bone_global_rest(sk.find_bone("thumb_02_" + side)).origin
	var n := (i1 - p1).cross(m1 - h).normalized()
	if n.dot(t2 - h) < 0.0:
		n = -n
	_palm_n[side] = n
	return n


## The fingers drawn together (adduction): the rig's rest pose has them spread 33-41 mm apart at the middle joints
## (a relaxed hand's are 18-20 mm; measured in tools: the hand audit), so bending alone left a splayed hand. Each of
## the index, ring and little fingers turned about the palm's normal, at its root, toward the middle finger's line.
func _close_fingers(sk: Skeleton3D, side: String, amt: float) -> void:
	var hb := sk.find_bone("hand_" + side)
	var mb := sk.find_bone("middle_01_" + side)
	if hb < 0 or mb < 0:
		return
	var hg := sk.get_bone_global_pose(hb)
	var n := (hg.basis * (sk.get_bone_global_rest(hb).basis.inverse() * _palm_normal(sk, side))).normalized()
	var mid_dir := sk.get_bone_global_pose(sk.find_bone("middle_02_" + side)).origin - sk.get_bone_global_pose(mb).origin
	for fn in ["index", "ring", "pinky"]:
		var b1 := sk.find_bone("%s_01_%s" % [fn, side])
		var b2 := sk.find_bone("%s_02_%s" % [fn, side])
		if b1 < 0 or b2 < 0:
			continue
		var g := sk.get_bone_global_pose(b1)
		var d := sk.get_bone_global_pose(b2).origin - g.origin
		var a := d - n * d.dot(n)
		var b := mid_dir - n * mid_dir.dot(n)
		if a.length() < 1e-5 or b.length() < 1e-5:
			continue
		var ang := a.signed_angle_to(b, n) * amt * (0.6 if fn == "index" else 0.75)
		sk.set_bone_global_pose(b1, Transform3D(Basis(n, ang * weight) * g.basis, g.origin))


## The other grips (each finger's curl at full grip, the thumb's target and how far short of it it stops):
##   scoop  the four fingertips together and a little cupped, the thumb behind them (rice gathered on the fingers)
##   spoon  a pinch on a handle: the index straighter along it, the thumb on top, the middle under
##   wrap   round a tumbler or a glass (about 6 cm across): all four fingers curled round, the thumb opposite
##   hold   a burger, a slice: the fingers under and a little curled, the thumb over it
const GRIP_KINDS := {
	"scoop": {"curl": {"index": [0.35, 0.45, 0.3], "middle": [0.38, 0.45, 0.3], "ring": [0.45, 0.5, 0.32], "pinky": [0.5, 0.55, 0.35]},
		"thumb_to": "index_02", "hold": 0.016},
	"spoon": {"curl": {"index": [0.4, 0.45, 0.3], "middle": [0.75, 0.9, 0.6], "ring": [1.1, 1.25, 0.85], "pinky": [1.2, 1.3, 0.9]},
		"thumb_to": "index_02", "hold": 0.008},
	"wrap": {"curl": {"index": [0.75, 0.85, 0.6], "middle": [0.8, 0.9, 0.6], "ring": [0.85, 0.9, 0.6], "pinky": [0.9, 0.9, 0.6]},
		"thumb_to": "middle_02", "hold": 0.055},
	"hold": {"curl": {"index": [0.4, 0.5, 0.35], "middle": [0.45, 0.55, 0.35], "ring": [0.5, 0.6, 0.4], "pinky": [0.55, 0.6, 0.4]},
		"thumb_to": "index_02", "hold": 0.05},
}


## Where what's held sits (skeleton space): for a pinch, on the pads of the thumb, the index and the middle finger
## (the food between the three); for the others, between the thumb and the fingers they close on.
func _grip_centre(sk: Skeleton3D, side: String, kind: String) -> Vector3:
	if kind in ["pinch", "spoon"]:
		var t := _tip(sk, "thumb", side, 0.45)
		var i := _tip(sk, "index", side, 0.45)
		var m := _tip(sk, "middle", side, 0.3)
		return t * 0.42 + i * 0.38 + m * 0.2
	var tt := _tip(sk, "thumb", side, 0.4)
	var to: String = (GRIP_KINDS.get(kind, GRIP_KINDS["hold"]) as Dictionary)["thumb_to"]
	var tb := sk.find_bone("%s_%s" % [to, side])
	var o := sk.get_bone_global_pose(tb).origin if tb >= 0 else _tip(sk, "index", side)
	if kind == "scoop":
		return (tt + _tip(sk, "middle", side, 0.5) * 2.0) / 3.0
	return (tt + o) * 0.5


## The held thing placed (see `held`).
func _place_held(sk: Skeleton3D) -> void:
	if held == null or not is_instance_valid(held) or held_mode == "":
		return
	var sc := held.scale
	var hb0 := sk.find_bone("hand_r")
	var hand_g := (sk.global_transform * sk.get_bone_global_pose(hb0)).orthonormalized()
	var rt0 := face_fwd.cross(Vector3.UP).normalized()
	if request_keep:                                     # (taken: where it is now, relative to what holds it)
		request_keep = false
		var hg0 := held.global_transform.orthonormalized()
		match held_mode:
			"keep":
				_keep_rel = hand_g.affine_inverse() * hg0
			"upright":
				held_offset = hg0.origin - pinch_world
				held_basis = Basis(rt0, -held_tilt) * hg0.basis
			"both":
				held_offset = hg0.origin - (pinch_world + l_grip_world) * 0.5
				held_basis = Basis(rt0, -held_tilt) * hg0.basis
	match held_mode:
		"keep":
			var t := hand_g * _keep_rel
			held.global_transform = Transform3D(t.basis * Basis.from_scale(sc), t.origin)
		"pinch":
			var hb := sk.find_bone("hand_r")
			var hg := sk.global_transform * sk.get_bone_global_pose(hb)
			var b := hg.basis.orthonormalized() * held_basis
			held.global_transform = Transform3D(b * Basis.from_scale(sc), pinch_world + hg.basis.orthonormalized() * held_offset)
		"upright":
			var rt := face_fwd.cross(Vector3.UP).normalized()
			var b := Basis(rt, held_tilt) * held_basis
			held.global_transform = Transform3D(b * Basis.from_scale(sc), pinch_world + held_offset)
		"both":
			var rt := face_fwd.cross(Vector3.UP).normalized()
			var b := Basis(rt, held_tilt) * held_basis
			held.global_transform = Transform3D(b * Basis.from_scale(sc), (pinch_world + l_grip_world) * 0.5 + held_offset)


func _grip(sk: Skeleton3D, side: String, p: float, kind := "pinch") -> void:
	for fn in ["thumb", "index", "middle", "ring", "pinky"]:   # (from the rig's rest: the clip's own fingers dropped)
		for j in 3:
			var rb := sk.find_bone("%s_%02d_%s" % [fn, j + 1, side])
			if rb >= 0:
				sk.set_bone_pose_rotation(rb, sk.get_bone_rest(rb).basis.get_rotation_quaternion())
	_close_fingers(sk, side, 0.85 + 0.15 * p)            # (together: a little when relaxed, close when holding)
	var gk: Dictionary = GRIP_KINDS.get(kind, {})
	for fn in GRIP:
		var lo: Array = GRIP[fn][0]
		var hi: Array = (gk["curl"][fn] if not gk.is_empty() else GRIP[fn][1])
		for j in 3:
			_bend(sk, side, "%s_%02d_%s" % [fn, j + 1, side], lerpf(float(lo[j]), float(hi[j]), p))
	if p < 0.05:
		_bend(sk, side, "thumb_02_" + side, 0.15)
		return
	_bend(sk, side, "thumb_03_" + side, 0.35 * p)            # (the thumb's tip joint first: the solver then places
	                                                         #  the tip itself, so the gap stays what's held)
	# the thumb: to the index fingertip (opposition), the solver's passes over its first two joints
	var target := _tip(sk, "index", side)
	var hs := hold_size
	if not gk.is_empty():
		var tb2 := sk.find_bone("%s_%s" % [gk["thumb_to"], side])
		if tb2 >= 0:
			target = sk.get_bone_global_pose(tb2).origin
		hs = float(gk["hold"])
	var tb := sk.find_bone("thumb_01_" + side)
	if tb >= 0:                                           # (short of it by what's held, from the thumb's side)
		var from_thumb := (sk.get_bone_global_pose(tb).origin - target).normalized()
		target += from_thumb * hs
	for it in 3:
		for jn in ["thumb_01_", "thumb_02_"]:
			var b := sk.find_bone(jn + side)
			if b < 0:
				continue
			var g := sk.get_bone_global_pose(b)
			var tip := _tip(sk, "thumb", side)
			var v1 := tip - g.origin
			var v2 := tip.lerp(target, p) - g.origin
			if v1.length() < 1e-4 or v2.length() < 1e-4:
				continue
			var ax := v1.cross(v2)
			if ax.length() < 1e-6:
				continue
			var ang := minf(v1.angle_to(v2), 1.2 if jn == "thumb_01_" else 1.0)
			sk.set_bone_global_pose(b, Transform3D(Basis(ax.normalized(), ang * weight) * g.basis, g.origin))
	# (the solver only aims the thumb: longer than its way to the target, its tip runs on to the index fingertip.
	#  So the gap is set last: the thumb opened at its root, away from the index, until it's what's held)
	var want := hs
	for it in 3:
		var b0 := sk.find_bone("thumb_01_" + side)
		if b0 < 0:
			break
		var g0 := sk.get_bone_global_pose(b0)
		var tt := _tip(sk, "thumb", side)
		var it_ := _tip(sk, "index", side)                 # (what the thumb closes on: the index tip, or the grip's joint)
		if not gk.is_empty():
			var tb3 := sk.find_bone("%s_%s" % [gk["thumb_to"], side])
			it_ = sk.get_bone_global_pose(tb3).origin if tb3 >= 0 else _tip(sk, "index", side)
		var gap := tt.distance_to(it_)
		if gap >= want - 0.001 or p < 0.05:
			break
		var arm := tt - g0.origin
		var away := (tt - it_).normalized() if gap > 1e-4 else (tt - g0.origin).cross(_palm_normal(sk, side)).normalized()
		var ax := arm.cross(away)
		if ax.length() < 1e-6 or arm.length() < 1e-4:
			break
		var ang := minf((want - gap) / arm.length(), 0.6)
		sk.set_bone_global_pose(b0, Transform3D(Basis(ax.normalized(), ang * weight) * g0.basis, g0.origin))


## The fingers for eating (the old way, kept for reference: a shared axis and a guessed side; it could bend them
## backward, the spread hand): thumb, index and middle fingertips brought together by `p` (the morsel between them), the
## ring and little fingers tucked a little more than they close.
func _pinch(sk: Skeleton3D, side: String, knuckles: Vector3, p: float) -> void:
	var inv := sk.global_basis.inverse()
	var al := (inv * knuckles).normalized()
	var sgn := _curl_toward_thumb(sk, side, al)
	var curls := {"index": [0.45, 0.6, 0.4], "middle": [0.5, 0.65, 0.42], "ring": [0.8, 1.0, 0.65], "pinky": [0.9, 1.05, 0.7]}
	for fn in curls:
		var c: Array = curls[fn]
		var amt := p if fn in ["index", "middle"] else maxf(p, 0.35) * 1.0
		for j in 3:
			_turn_local(sk, "%s_%02d_%s" % [fn, j + 1, side], al, sgn * float(c[j]) * amt)
	var ts := 1.0 if side == "l" else -1.0
	var bh := sk.find_bone("hand_" + side)
	var bm := sk.find_bone("middle_01_" + side)
	if bh >= 0 and bm >= 0:
		var fdir := (sk.get_bone_global_pose(bm).origin - sk.get_bone_global_pose(bh).origin).normalized()
		_turn_local(sk, "thumb_01_" + side, fdir, ts * 0.6 * p)    # (across to meet the fingertips: opposed)
	_turn_local(sk, "thumb_02_" + side, al, sgn * 0.4 * p)
	_turn_local(sk, "thumb_03_" + side, al, sgn * 0.45 * p)


## Which way about the knuckle line closes the index fingertip toward the thumb tip (+1 or -1).
func _curl_toward_thumb(sk: Skeleton3D, side: String, al: Vector3) -> float:
	var b1 := sk.find_bone("index_01_" + side)
	var b3 := sk.find_bone("index_03_" + side)
	var bt := sk.find_bone("thumb_03_" + side)
	if b1 < 0 or b3 < 0 or bt < 0:
		return 1.0
	var p1 := sk.get_bone_global_pose(b1).origin
	var tip := sk.get_bone_global_pose(b3).origin
	var th := sk.get_bone_global_pose(bt).origin
	var plus := p1 + Basis(al, 0.5) * (tip - p1)
	var minus := p1 + Basis(al, -0.5) * (tip - p1)
	return 1.0 if plus.distance_to(th) <= minus.distance_to(th) else -1.0


## The point between the thumb tip and the index and middle fingertips (where the morsel is held), in the world.
func pinch_point(_sk: Skeleton3D) -> Vector3:
	return pinch_world if pinch_world != Vector3.ZERO else r_at
