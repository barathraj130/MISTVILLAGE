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
var forward := Vector3.FORWARD       # the vehicle's forward, in the world (the knees and elbows bend toward it)
var up := Vector3.UP


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or weight < 0.005:
		return
	# the body first: a little more lean into the turn, the head toward level and the way he's going
	_turn_bone(sk, "spine_02", forward, -lean * 0.25)
	_turn_bone(sk, "neck_01", forward, lean * 0.55)
	_turn_bone(sk, "head", up, look * 0.6)
	if grip_l and grip_r:
		_limb(sk, "upperarm_l", "lowerarm_l", "hand_l", grip_l.global_position, -forward * 0.6 + Vector3.DOWN - _side(sk) * 0.6)
		_limb(sk, "upperarm_r", "lowerarm_r", "hand_r", grip_r.global_position, -forward * 0.6 + Vector3.DOWN + _side(sk) * 0.6)
	if foot_l and foot_r:
		var fl := foot_l.global_position.lerp(ground_l, foot_down)
		_limb(sk, "thigh_l", "calf_l", "foot_l", fl, forward + Vector3.UP * 0.3)
		_limb(sk, "thigh_r", "calf_r", "foot_r", foot_r.global_position, forward + Vector3.UP * 0.3)
		_flat_foot(sk, "foot_l", "ball_l")
		_flat_foot(sk, "foot_r", "ball_r")


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
