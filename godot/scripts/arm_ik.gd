extends SkeletonModifier3D
## One arm to a point, solved here (two bones, analytically): the elbow where an upper arm and a forearm of their
## lengths meet between the shoulder and the target, in the plane toward the pole (down and out, as an arm goes);
## the upper arm turned to point at that elbow, the forearm at the target. `weight` blends it over the clip's arm.
## (Godot's TwoBoneIK3D serves the legs, which hang near straight; the arms rest in the rig's A-pose and it didn't
## settle them, so this one is ours.) reach.gd drives it.

var side := "r"
var target := Vector3.ZERO           # in the world
var pole := Vector3.ZERO             # in the world
var weight := 0.0
var error := 0.0                     # (testing: after the last solve, how far the wrist is from the target, m)


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or weight < 0.005:
		return
	var b_up := sk.find_bone("upperarm_" + side)
	var b_lo := sk.find_bone("lowerarm_" + side)
	var b_hd := sk.find_bone("hand_" + side)
	if b_up < 0 or b_lo < 0 or b_hd < 0:
		return
	var inv := sk.global_transform.affine_inverse()
	var t := inv * target                                # (all in the skeleton's space)
	var pl := inv * pole
	var up_pose := sk.get_bone_global_pose(b_up)
	var lo_pose := sk.get_bone_global_pose(b_lo)
	var hd_pose := sk.get_bone_global_pose(b_hd)
	var s := up_pose.origin
	var e := lo_pose.origin
	var w := hd_pose.origin
	var a := s.distance_to(e)
	var b := e.distance_to(w)
	var to := t - s
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.001)
	var dir := to.normalized()
	var cos_s := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)   # (the angle at the shoulder)
	var bend := (pl - s) - dir * (pl - s).dot(dir)       # (toward the pole, square to the reach)
	if bend.length() < 0.001:
		bend = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	bend = bend.normalized()
	var elbow := s + dir * (a * cos_s) + bend * (a * sqrt(maxf(1.0 - cos_s * cos_s, 0.0)))
	var wrist := s + dir * d
	# the upper arm: from where its child is to the new elbow, blended by weight
	var want_e := e.lerp(elbow, weight)
	var r1 := _turn(e - s, want_e - s)
	sk.set_bone_global_pose(b_up, Transform3D(r1 * up_pose.basis, s))
	var lo2 := sk.get_bone_global_pose(b_lo)
	var w2 := sk.get_bone_global_pose(b_hd).origin
	var want_w := w2.lerp(wrist, weight)
	var r2 := _turn(w2 - lo2.origin, want_w - lo2.origin)
	sk.set_bone_global_pose(b_lo, Transform3D(r2 * lo2.basis, lo2.origin))
	error = sk.get_bone_global_pose(b_hd).origin.distance_to(t)


## The rotation that takes direction a onto direction b (shortest way).
static func _turn(a: Vector3, b: Vector3) -> Basis:
	if a.length() < 1e-5 or b.length() < 1e-5:
		return Basis()
	var an := a.normalized()
	var bn := b.normalized()
	var ax := an.cross(bn)
	var dt := clampf(an.dot(bn), -1.0, 1.0)
	if ax.length() < 1e-6:
		return Basis()
	return Basis(ax.normalized(), acos(dt))
