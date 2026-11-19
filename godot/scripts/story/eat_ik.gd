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
	# the right hand: the wrist where the fingers reach the target from, then turned, then the fingers
	var rf := r_fingers.normalized()
	var wrist := r_at - rf * FINGER_LEN - _corr
	if wrist.y < wrist_floor:                          # (never the hand into the plate: the wrist held above it)
		wrist.y = wrist_floor
	_limb(sk, "upperarm_r", "lowerarm_r", "hand_r", wrist,
		Vector3.DOWN * 1.0 + right * 0.3 - face_fwd * 0.1)     # (the elbow low and relaxed, a little out)
	grip = 0.0
	_hand(sk, "r", r_knuckles, rf, r_at)
	_thumb_toward(sk, "r", r_thumb)
	_grip(sk, "r", pinch)
	var tt := _tip(sk, "thumb", "r")
	var it := _tip(sk, "index", "r")
	pinch_world = sk.global_transform * ((tt + it) * 0.5)
	pinch_gap = tt.distance_to(it)
	var err := pinch_world - r_at
	_corr = (_corr + err * 0.5).limit_length(0.08) if pinch > 0.5 else _corr * 0.85
	# the left: flat by the plate, fingers forward, the elbow out to his left and down
	var lf := l_fingers.normalized()
	_limb(sk, "upperarm_l", "lowerarm_l", "hand_l", l_at - lf * 0.07, Vector3.DOWN * 1.0 - right * 0.3 - face_fwd * 0.1)
	_hand(sk, "l", l_knuckles, lf, l_at)
	_thumb_toward(sk, "l", l_thumb)
	_grip(sk, "l", 0.0)                                   # (relaxed: the fingers a little curled, the thumb loose)


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
const GRIP := {"index": [[0.15, 0.2, 0.12], [0.55, 0.75, 0.55]], "middle": [[0.2, 0.25, 0.15], [0.7, 0.85, 0.6]],
	"ring": [[0.3, 0.35, 0.2], [1.1, 1.25, 0.85]], "pinky": [[0.35, 0.4, 0.25], [1.2, 1.3, 0.9]]}
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


func _tip(sk: Skeleton3D, finger: String, side: String) -> Vector3:
	var b2 := sk.find_bone("%s_02_%s" % [finger, side])
	var b3 := sk.find_bone("%s_03_%s" % [finger, side])
	if b2 < 0 or b3 < 0:
		return Vector3.ZERO
	var a := sk.get_bone_global_pose(b2).origin
	var c := sk.get_bone_global_pose(b3).origin
	return c + (c - a) * 0.85                             # (the last joint's length again, about: the fingertip)


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


func _grip(sk: Skeleton3D, side: String, p: float) -> void:
	for fn in ["thumb", "index", "middle", "ring", "pinky"]:   # (from the rig's rest: the clip's own fingers dropped)
		for j in 3:
			var rb := sk.find_bone("%s_%02d_%s" % [fn, j + 1, side])
			if rb >= 0:
				sk.set_bone_pose_rotation(rb, sk.get_bone_rest(rb).basis.get_rotation_quaternion())
	_close_fingers(sk, side, 0.55 + 0.45 * p)            # (together: a little when relaxed, close when holding)
	for fn in GRIP:
		var lo: Array = GRIP[fn][0]
		var hi: Array = GRIP[fn][1]
		for j in 3:
			_bend(sk, side, "%s_%02d_%s" % [fn, j + 1, side], lerpf(float(lo[j]), float(hi[j]), p))
	if p < 0.05:
		_bend(sk, side, "thumb_02_" + side, 0.15)
		return
	_bend(sk, side, "thumb_03_" + side, 0.35 * p)            # (the thumb's tip joint first: the solver then places
	                                                         #  the tip itself, so the gap stays what's held)
	# the thumb: to the index fingertip (opposition), the solver's passes over its first two joints
	var target := _tip(sk, "index", side)
	var tb := sk.find_bone("thumb_01_" + side)
	if tb >= 0:                                           # (short of it by what's held, from the thumb's side)
		var from_thumb := (sk.get_bone_global_pose(tb).origin - target).normalized()
		target += from_thumb * hold_size
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
	var want := hold_size
	for it in 3:
		var b0 := sk.find_bone("thumb_01_" + side)
		if b0 < 0:
			break
		var g0 := sk.get_bone_global_pose(b0)
		var tt := _tip(sk, "thumb", side)
		var it_ := _tip(sk, "index", side)
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
