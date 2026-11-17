extends SkeletonModifier3D
## The rider on a two-wheeler (docs/PHYSICS_AND_BIKE_PLAN_2026-11-16.md B1, B2): his hands on the grips, his feet on
## the floorboard (or the left one down on the road when he stops), solved over the "Ride" clip each frame, under
## his skeleton, after the animation. Two bones a limb, analytically (as arm_ik.gd): the elbow or the knee where the
## two bones' lengths meet between the shoulder (hip) and the target, bent toward the pole.
##   targets   grip_l / grip_r / foot_l / foot_r: Node3Ds on the vehicle (the grips ride on the turning handlebar:
##             jeep.gd _make_bars), read in the world each frame
##   foot_down 0..1: the left foot from the floorboard to `ground_l` (a point on the road beside him) and back
##   lean      the bike's roll (radians, + to his right): his chest leans a little more into the turn, his head
##             comes back toward level (a rider looks level, not along the bike)
##   look      where the bike's going, radians of yaw: his head turns a little toward it
##   weight    0..1 over the clip (mounting blends it in)
var grip_l: Node3D
var grip_r: Node3D
var foot_l: Node3D
var foot_r: Node3D
var ground_l := Vector3.ZERO
var foot_down := 0.0
var lean := 0.0
var look := 0.0
var weight := 1.0
##   limbs     each limb's own weight (getting on and off: a hand to the bar first, the right leg over the seat)
##   over      a limb's target overridden (in the world), blended by its own weight: the right foot's path over the
##             seat, the feet on the ground beside the scooter
var limbs := {"arm_l": 1.0, "arm_r": 1.0, "leg_l": 1.0, "leg_r": 1.0, "body": 1.0}
var over := {}                       # limb → [world point, weight 0..1]
var forward := Vector3.FORWARD       # the vehicle's forward, in the world (the knees and elbows bend toward it)
var hide_head := false
var recline := 0.0                   # (in a car's seat: leaning back against its back, radians)               # (the camera at his eyes, in a car: his head shrunk away, his arms on the wheel seen)
var up := Vector3.UP
##   wheel     a car's steering wheel (its pivot; the column along its own X): the hands are set on its rim, the
##             knuckles along the rim's curve there, the fingers toward the dash, curled round it. Without one (a
##             handlebar), along the bar (his side), the fingers forward and down over it.
##   grip      0..1, how closed the fingers are round the rim or the grip
var wheel: Node3D
var grip := 1.0
var wheel_turn := 0.0                # the wheel's turn now (radians about its column): the hands go round with it to
const HAND_TURN := 1.05              # ±60°, then hold where they are while it turns on through them (as hands shuffle)
const PALM := 0.075                  # (from the wrist to the middle of the palm: the palm, not the wrist, on the rim)
const FINGERS := ["index", "middle", "ring", "pinky"]
const CURL := [0.95, 1.2, 0.75]      # (each finger's three joints, radians when fully closed)


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or weight < 0.005:
		return
	# the body first: a little more lean into the turn, the head toward level and the way he's going
	var w0 := weight
	weight = w0 * float(limbs["body"])
	if absf(recline) > 0.001:                            # (back against the seat: about his side-to-side axis)
		_turn_bone(sk, "spine_01", forward.cross(up).normalized(), -recline)
	_turn_bone(sk, "spine_02", forward, -lean * 0.25)
	_turn_bone(sk, "neck_01", forward, lean * 0.55)
	_turn_bone(sk, "head", up, look * 0.6)
	if grip_l and grip_r:
		for hs in [["l", grip_l, -1.0], ["r", grip_r, 1.0]]:
			var side: String = hs[0]
			var gp: Vector3 = (hs[1] as Node3D).global_position
			if wheel and is_instance_valid(wheel) and absf(wheel_turn) > HAND_TURN:
				var held := clampf(wheel_turn, -HAND_TURN, HAND_TURN)
				var loc: Vector3 = wheel.global_transform.affine_inverse() * gp
				gp = wheel.global_transform * (Basis(Vector3.RIGHT, held - wheel_turn) * loc)
			var frame := _grip_frame(gp)                 # [along the rim or bar, the fingers' way]
			weight = w0 * float(limbs["arm_" + side])
			var target := _aim("arm_" + side, gp - (frame[1] as Vector3) * PALM)
			_limb(sk, "upperarm_" + side, "lowerarm_" + side, "hand_" + side, target,
				-forward * 0.6 + Vector3.DOWN + _side(sk) * 0.6 * float(hs[2]))
			if not over.has("arm_" + side) or float(over["arm_" + side][1]) < 0.5:
				_hand(sk, side, frame[0], frame[1], gp)
	if foot_l and foot_r:
		var fl := foot_l.global_position.lerp(ground_l, foot_down)
		weight = w0 * float(limbs["leg_l"])
		_limb(sk, "thigh_l", "calf_l", "foot_l", _aim("leg_l", fl), forward + Vector3.UP * 0.3)
		_flat_foot(sk, "foot_l", "ball_l")
		weight = w0 * float(limbs["leg_r"])
		_limb(sk, "thigh_r", "calf_r", "foot_r", _aim("leg_r", foot_r.global_position), forward + Vector3.UP * 0.3)
		_flat_foot(sk, "foot_r", "ball_r")
	weight = w0
	if hide_head:
		for bn in ["neck_01", "head"]:
			var hb := sk.find_bone(bn)
			if hb >= 0:
				var hg := sk.get_bone_global_pose(hb)
				sk.set_bone_global_pose(hb, Transform3D(hg.basis.scaled(Vector3.ONE * 0.001), hg.origin))


## Where a hand holds: [the line it closes round (the rim's tangent there, or the bar along his side), the way the
## fingers point (toward the dash over a wheel's rim; forward and down over a bar)], in the world.
func _grip_frame(gp: Vector3) -> Array:
	if wheel and is_instance_valid(wheel):
		var axis := (wheel.global_basis.x).normalized()   # (the column, from him toward the dash)
		var radial := gp - wheel.global_position
		radial = (radial - axis * radial.dot(axis)).normalized()
		var tangent := axis.cross(radial).normalized()
		var fingers := (axis * 0.8 - radial * 0.6).normalized()   # (over the rim toward the dash, a little inward)
		return [tangent, fingers]
	return [_side(null), (forward * 0.75 + Vector3.DOWN * 0.65).normalized()]


## The hand turned to hold: its knuckles along `along`, its fingers toward `fingers`; then the fingers and the thumb
## closed round the rim or the bar at `at` (each finger curling the way that brings its tip round it).
func _hand(sk: Skeleton3D, side: String, along: Vector3, fingers: Vector3, at: Vector3) -> void:
	var bh := sk.find_bone("hand_" + side)
	var bi := sk.find_bone("index_01_" + side)
	var bp := sk.find_bone("pinky_01_" + side)
	var bm := sk.find_bone("middle_01_" + side)
	if bh < 0 or bi < 0 or bp < 0 or bm < 0:
		return
	var inv := sk.global_basis.inverse()
	var al := (inv * along).normalized()
	var fi := (inv * fingers).normalized()
	var at_l := sk.global_transform.affine_inverse() * at
	var g := sk.get_bone_global_pose(bh)
	# the knuckles along the line (whichever way round they already lie), then the fingers round it toward `fingers`
	var k := sk.get_bone_global_pose(bi).origin - sk.get_bone_global_pose(bp).origin
	var al2 := al if k.dot(al) >= 0.0 else -al
	var r1 := _turn(k, k.lerp(al2 * k.length(), weight))
	g = Transform3D(r1 * g.basis, g.origin)
	sk.set_bone_global_pose(bh, g)
	var f := sk.get_bone_global_pose(bm).origin - g.origin
	var f_flat := f - al2 * f.dot(al2)
	var want := fi - al2 * fi.dot(al2)
	if f_flat.length() > 1e-4 and want.length() > 1e-4:
		var ang := f_flat.normalized().signed_angle_to(want.normalized(), al2) * weight
		g = Transform3D(Basis(al2, ang) * g.basis, g.origin)
		sk.set_bone_global_pose(bh, g)
	# the fingers: the curl's sign from the middle finger (whichever way takes its tip nearer the line it holds)
	var c := clampf(grip * weight, 0.0, 1.0)
	if c < 0.01:
		return
	var sgn := _curl_sign(sk, side, al2, at_l)
	for fn in FINGERS:
		for j in 3:
			_turn_local(sk, "%s_%02d_%s" % [fn, j + 1, side], al2, sgn * CURL[j] * c)
	var ts := 1.0 if side == "l" else -1.0                # (the thumb across, under the rim)
	_turn_local(sk, "thumb_01_" + side, fi, ts * 0.35 * c)
	_turn_local(sk, "thumb_02_" + side, al2, sgn * 0.4 * c)
	_turn_local(sk, "thumb_03_" + side, al2, sgn * 0.5 * c)


func _curl_sign(sk: Skeleton3D, side: String, axis: Vector3, at_l: Vector3) -> float:
	var b1 := sk.find_bone("middle_01_" + side)
	var b3 := sk.find_bone("middle_03_" + side)
	if b1 < 0 or b3 < 0:
		return 1.0
	var p1 := sk.get_bone_global_pose(b1).origin
	var tip := sk.get_bone_global_pose(b3).origin
	var dist := func(p: Vector3) -> float:                 # (from the line through `at` along the axis)
		var d := p - at_l
		return (d - axis * d.dot(axis)).length()
	var plus := p1 + Basis(axis, 0.6) * (tip - p1)
	var minus := p1 + Basis(axis, -0.6) * (tip - p1)
	return 1.0 if dist.call(plus) <= dist.call(minus) else -1.0


## A bone turned about an axis given in the skeleton's frame, at its own place (its children follow).
func _turn_local(sk: Skeleton3D, bone: String, axis: Vector3, ang: float) -> void:
	var b := sk.find_bone(bone)
	if b < 0 or absf(ang) < 0.0005:
		return
	var g := sk.get_bone_global_pose(b)
	sk.set_bone_global_pose(b, Transform3D(Basis(axis.normalized(), ang) * g.basis, g.origin))


## A limb's target: its own, or overridden (blended by the override's weight).
func _aim(limb: String, own: Vector3) -> Vector3:
	if not over.has(limb):
		return own
	var o: Array = over[limb]
	return own.lerp(o[0], clampf(float(o[1]), 0.0, 1.0))


## His right, in the world (from the vehicle's forward and up).
func _side(_sk: Skeleton3D) -> Vector3:
	return forward.cross(up).normalized()


func _turn_bone(sk: Skeleton3D, bone: String, axis: Vector3, ang: float) -> void:
	var b := sk.find_bone(bone)
	if b < 0 or absf(ang) < 0.0005:
		return
	var inv := sk.global_basis.inverse()
	var ax := (inv * axis).normalized()
	var g := sk.get_bone_global_pose(b)
	sk.set_bone_global_pose(b, Transform3D(Basis(ax, ang * weight) * g.basis, g.origin))


## One limb to a point in the world (two bones: upper, lower, the end bone's place the target), toward a pole
## direction (in the world).
func _limb(sk: Skeleton3D, upper: String, lower: String, end: String, target: Vector3, pole_dir: Vector3) -> void:
	var b_up := sk.find_bone(upper)
	var b_lo := sk.find_bone(lower)
	var b_en := sk.find_bone(end)
	if b_up < 0 or b_lo < 0 or b_en < 0:
		return
	var inv := sk.global_transform.affine_inverse()
	var t := inv * target
	var pd := (sk.global_basis.inverse() * pole_dir).normalized()
	var up_pose := sk.get_bone_global_pose(b_up)
	var s := up_pose.origin
	var e := sk.get_bone_global_pose(b_lo).origin
	var w := sk.get_bone_global_pose(b_en).origin
	var a := s.distance_to(e)
	var b := e.distance_to(w)
	var to := t - s
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.002)
	var dir := to.normalized()
	var cos_s := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var bend := pd - dir * pd.dot(dir)
	if bend.length() < 0.001:
		bend = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	bend = bend.normalized()
	var mid := s + dir * (a * cos_s) + bend * (a * sqrt(maxf(1.0 - cos_s * cos_s, 0.0)))
	var want_e := e.lerp(mid, weight)
	var r1 := _turn(e - s, want_e - s)
	sk.set_bone_global_pose(b_up, Transform3D(r1 * up_pose.basis, s))
	var lo2 := sk.get_bone_global_pose(b_lo)
	var w2 := sk.get_bone_global_pose(b_en).origin
	var want_w := w2.lerp(s + dir * d, weight)
	var r2 := _turn(w2 - lo2.origin, want_w - lo2.origin)
	sk.set_bone_global_pose(b_lo, Transform3D(r2 * lo2.basis, lo2.origin))


## The foot laid flat and pointing the way the vehicle goes (its ball level with its heel, ahead of it).
func _flat_foot(sk: Skeleton3D, foot: String, ball: String) -> void:
	var bf := sk.find_bone(foot)
	var bb := sk.find_bone(ball)
	if bf < 0 or bb < 0:
		return
	var g := sk.get_bone_global_pose(bf)
	var have := sk.get_bone_global_pose(bb).origin - g.origin
	var fw := (sk.global_basis.inverse() * forward).normalized()
	var upl := (sk.global_basis.inverse() * up).normalized()
	var want := (fw - upl * 0.45).normalized() * have.length()   # (toes a little down, as a foot rests)
	var r := _turn(have, have.lerp(want, weight))
	sk.set_bone_global_pose(bf, Transform3D(r * g.basis, g.origin))


static func _turn(a: Vector3, b: Vector3) -> Basis:
	if a.length() < 1e-5 or b.length() < 1e-5:
		return Basis()
	var an := a.normalized()
	var bn := b.normalized()
	var ax := an.cross(bn)
	if ax.length() < 1e-6:
		return Basis()
	return Basis(ax.normalized(), acos(clampf(an.dot(bn), -1.0, 1.0)))
