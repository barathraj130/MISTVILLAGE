extends SkeletonModifier3D
## Where a person's head is turned, after their clip has posed them (Godot's modifier stack: it runs on the pose the
## animation left): toward `target` (a point in the world, the one they're with), plus a feeling's own attitude:
## `pitch` (degrees, + down), `away` (degrees turned off the target, now one side, now the other: glancing away),
## `tilt` (degrees, the head on one side). All eased (nothing snaps), and limited as a neck is (60° each way, 35° up
## or down). `weight` 0 leaves the clip's head as it is. scripts/story/acting.gd drives it.

var target := Vector3.INF
var pitch := 0.0
var away := 0.0
var tilt := 0.0
var weight := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _tilt := 0.0
var _w := 0.0


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var hb := sk.find_bone("head")
	if hb < 0:
		return
	var dt := get_process_delta_time()
	var k := 1.0 - exp(-dt * 5.0)
	_w = lerpf(_w, weight if target != Vector3.INF else 0.0, k)
	if _w < 0.01:
		return
	var head := sk.get_bone_global_pose(hb)
	var want_yaw := 0.0
	var want_pitch := 0.0
	if target != Vector3.INF:                            # (skeleton space: +Z ahead, +Y up)
		var d := (sk.global_transform.affine_inverse() * target) - head.origin
		var flat := Vector2(d.x, d.z)
		want_yaw = clampf(atan2(d.x, d.z), -1.05, 1.05)
		want_pitch = clampf(-atan2(d.y, maxf(flat.length(), 0.01)), -0.6, 0.6)
	want_yaw = clampf(want_yaw + deg_to_rad(away), -1.05, 1.05)
	want_pitch = clampf(want_pitch + deg_to_rad(pitch), -0.6, 0.6)
	_yaw = lerpf(_yaw, want_yaw, k)
	_pitch = lerpf(_pitch, want_pitch, k)
	_tilt = lerpf(_tilt, deg_to_rad(tilt), k)
	var q := Quaternion(Vector3.UP, _yaw * _w) * Quaternion(Vector3.RIGHT, _pitch * _w) * Quaternion(Vector3.FORWARD, _tilt * _w)
	# (the head as the clip has it is roughly ahead: the turn is laid over it, about the neck's top)
	sk.set_bone_global_pose(hb, Transform3D(Basis(q) * head.basis, head.origin))
