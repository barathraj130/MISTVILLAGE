extends RefCounted
## Sits one of the Quaternius people (assets/drive/people) on a two-wheeler: thighs forward
## along the seat, shins down to the footrests, back leaning a little, arms out to the bars.
## The rig keeps its feet on separate root bones (IK in Blender), so after aiming the legs the
## feet are moved to the ends of the shins. Directions are in the character's space (+Z ahead).

const DIR := "res://assets/drive/people/"
const MODELS := ["man_casual", "man_farmer", "man_worker", "man_hoodie", "man_business", "woman_a", "woman_b"]
const SKIN := [Color(0.42, 0.27, 0.17), Color(0.36, 0.22, 0.13), Color(0.48, 0.32, 0.2), Color(0.3, 0.18, 0.11)]


## A posed rider, feet at y = 0 of the returned node's space before you place it; `seat_h` is
## the seat height above the footpegs (metres), `reach` how far forward the grips are.
static func make(seed_i: int, seat_h := 0.62, reach := 0.55) -> Node3D:
	var model: String = MODELS[seed_i % MODELS.size()]
	var node := (load(DIR + model + ".glb") as PackedScene).instantiate() as Node3D
	var sk := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var tall := 1.62 if model.begins_with("woman") else 1.72
	# the skeleton sits inside a rotated, ×100 armature (Blender's Z-up centimetres): work in the
	# character's own space through A, skeleton → character
	var A := _rel(sk, node)
	var hi := 0.0
	for i in sk.get_bone_count():
		hi = maxf(hi, (A * sk.get_bone_global_rest(i).origin).y)
	node.scale = Vector3.ONE * (tall / (hi * 1.07))
	# the imported AnimationPlayer would put the rest pose back: switch it off, and pose once the
	# rider is in the scene (and again next frame, after any skeleton reset on entering the tree)
	for ap in node.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).active = false
	var sc := node.scale.x
	var apply := func() -> void:
		_pose(sk, A, seat_h / sc, reach / sc)
	node.ready.connect(func() -> void:
		apply.call()
		node.get_tree().process_frame.connect(apply, CONNECT_ONE_SHOT))
	# Indian skin tone and dark hair, like the pedestrians
	var skin: Color = SKIN[seed_i % SKIN.size()]
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			if mat.resource_name.begins_with("Skin") or mat.resource_name.begins_with("Hair"):
				var v := mat.duplicate() as BaseMaterial3D
				v.albedo_color = skin if mat.resource_name.begins_with("Skin") else Color(0.05, 0.04, 0.035)
				mi.set_surface_override_material(s, v)
	return node


static func _rel(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _pose(sk: Skeleton3D, A: Transform3D, seat_h: float, _reach: float) -> void:
	var to_sk := A.basis.inverse()
	var hips := sk.find_bone("Hips")
	var body := sk.find_bone("Body")
	# raise the body so the pelvis sits at seat height above the footpegs (y = 0)
	var hip_y: float = (A * sk.get_bone_global_rest(hips).origin).y
	var lift_sk: Vector3 = to_sk * Vector3(0, seat_h - hip_y, 0)
	if body >= 0:
		var parent_g := sk.get_bone_global_rest(sk.get_bone_parent(body))
		sk.set_bone_pose_position(body, sk.get_bone_rest(body).origin + parent_g.basis.inverse() * lift_sk)
	var aim := func(bone: String, dir_char: Vector3) -> void:
		_aim(sk, bone, (to_sk * dir_char).normalized())
	aim.call("Abdomen", Vector3(0, 1, 0.18))
	aim.call("Chest", Vector3(0, 1, 0.25))
	for side in ["L", "R"]:
		var sx := 1.0 if side == "L" else -1.0
		aim.call("UpperLeg." + side, Vector3(0.12 * sx, -0.3, 1.0))       # thighs along the seat
		aim.call("LowerLeg." + side, Vector3(0.05 * sx, -1.0, -0.12))      # shins down to the pegs
		aim.call("UpperArm." + side, Vector3(0.3 * sx, -0.6, 1.0))         # arms out and forward
		aim.call("LowerArm." + side, Vector3(0.08 * sx, -0.15, 1.0))       # hands on the grips
		# feet: to the end of the shin, flat
		var shin := sk.find_bone("LowerLeg." + side)
		var foot := sk.find_bone("Foot." + side)
		if shin >= 0 and foot >= 0:
			var g := sk.get_bone_global_pose(shin)
			var shin_len := sk.get_bone_global_rest(shin).origin.distance_to(sk.get_bone_global_rest(foot).origin)
			var tip := g.origin + g.basis.y.normalized() * shin_len
			var parent_g := sk.get_bone_global_pose(sk.get_bone_parent(foot))
			sk.set_bone_pose_position(foot, parent_g.affine_inverse() * tip)


## Turn a bone so its length axis (+Y) points along `dir` in skeleton space.
static func _aim(sk: Skeleton3D, bone_name: String, dir: Vector3) -> void:
	var b := sk.find_bone(bone_name)
	if b < 0:
		return
	var g := sk.get_bone_global_pose(b)
	var cur := g.basis.y.normalized()
	var want := dir.normalized()
	var axis := cur.cross(want)
	if axis.length() < 1e-5:
		return
	var turn := Basis(axis.normalized(), cur.angle_to(want))
	var new_global := turn * g.basis
	var parent := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var local := pg.basis.inverse() * new_global
	sk.set_bone_pose_rotation(b, local.get_rotation_quaternion())
