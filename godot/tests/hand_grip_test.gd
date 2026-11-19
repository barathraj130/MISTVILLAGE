extends SceneTree
## (testing) The eating grip on its own, close up, before it goes into the breakfast (the grip brief's isolated
## test): Karthik at a counter, a plate of poori masala; through eat_ik.gd (the same IK the meals use) his right hand
## does the five stages once: (1) the open hand comes to the poori, (2) the thumb and fingers pinch its edge, (3) a
## small piece torn off, held in the fingertips (the poori on the plate smaller), (4) brought to his mouth, (5) the
## bite (the mouth open, closed on it, the piece gone), chewing, the hand back to the plate. Pictures of each stage
## and a frame every 0.1 s:
##   godot --path . --audio-driver Dummy --script tests/hand_grip_test.gd -- --out=DIR

const EatIK := preload("res://scripts/story/eat_ik.gd")
const Kit := preload("res://scripts/story/food_kit.gd")
const Face := preload("res://scripts/story/face.gd")
const Dine := preload("res://scripts/story/eater.gd")

var out := ""
var world: Node3D
var model: Node3D
var skel: Skeleton3D
var ik
var face
var cam: Camera3D
var plate: Node3D
var poori: Dictionary
var piece: MeshInstance3D
var t := -1.0
var n := 0
var shot_at := {1.0: "1_open_approach", 1.75: "2_pinch", 2.35: "3_piece_held", 3.35: "4_to_mouth", 3.9: "5_bite", 5.2: "6_back_chewing"}
var taken := {}
var fwd := Vector3(0, 0, 1)
var right := Vector3(-1, 0, 0)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	world = Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.36, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(160), 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	world.add_child(sun)
	model = (load("res://assets/people/story_karthik.glb") as PackedScene).instantiate()
	world.add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ap := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	ap.play("Idle")
	# the counter and the plate (the poori dish as the meals build it)
	var top := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.04, 0.5)
	top.mesh = bm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.36, 0.22, 0.13)
	top.material_override = tm
	world.add_child(top)
	top.position = Vector3(0.0, 0.93, 0.47)
	plate = Kit.build("poori")
	world.add_child(plate)
	plate.global_transform = Transform3D(Basis(right, Vector3.UP, -fwd), Vector3(-0.1, 0.952, 0.42))
	for p in plate.get_meta("parts"):
		if str(p["label"]).to_lower().contains("poori"):
			poori = p
			break
	piece = MeshInstance3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	piece.mesh = Dine.torn_piece(rng)                  # (the meals' own torn piece)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = poori.get("colour", Color(0.86, 0.6, 0.28))
	piece.material_override = mm
	piece.visible = false
	world.add_child(piece)
	ik = EatIK.new()
	ik.face_fwd = fwd
	ik.active = true
	skel.add_child(ik)
	ik.wrist_floor = 0.952 + 0.06
	face = Face.new(model)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.02
	world.add_child(cam)
	cam.make_current()
	root.size = Vector2i(1280, 800)


func _mouth() -> Vector3:
	var h: Vector3 = skel.global_transform * skel.get_bone_global_pose(skel.find_bone("head")).origin
	return h + fwd * 0.1 - Vector3.UP * 0.09


func _process(dt: float) -> bool:
	t += dt
	if t < 0.0:
		return false
	var nd: Node3D = poori["node"]
	var pc := nd.global_position
	var rest := plate.global_position + right * 0.2 - fwd * 0.04 + Vector3.UP * 0.04
	var edge := pc - fwd * 0.04 + Vector3.UP * 0.018
	var mouth := _mouth()
	var level := (Vector3.DOWN * 0.45 + fwd * 0.85).normalized()
	var to_mouth := (-fwd * 0.6 + Vector3.UP * 0.55 - right * 0.35).normalized()
	# the keys: [time, fingertip point, fingers' way, grip]
	var keys := [[0.0, rest, level, 0.0], [1.0, edge + Vector3.UP * 0.03, level, 0.0], [1.5, edge, level, 0.0],
		[1.75, edge, level, 1.0], [2.2, edge - fwd * 0.03 + Vector3.UP * 0.015, level, 1.0],
		[3.35, mouth + fwd * 0.09 - Vector3.UP * 0.03, to_mouth, 1.0], [3.75, mouth + fwd * 0.01, to_mouth, 1.0],
		[4.3, mouth + fwd * 0.12 - Vector3.UP * 0.07, to_mouth.lerp(level, 0.5).normalized(), 0.3], [5.4, rest, level, 0.0], [6.2, rest, level, 0.0]]
	var at: Array = keys[-1]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= float(b[0]):
			var u := clampf((t - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			at = [0.0, (a[1] as Vector3).lerp(b[1], u), (a[2] as Vector3).lerp(b[2], u).normalized(), lerpf(a[3], b[3], u)]
			break
	ik.r_at = at[1]
	ik.r_fingers = at[2]
	ik.r_knuckles = right
	ik.pinch = at[3]
	var to_face := smoothstep(3.0, 3.35, t) * (1.0 - smoothstep(3.9, 4.4, t))
	ik.r_palm = (Vector3.DOWN - right * 0.35).normalized().slerp((-right * 0.85 + Vector3.UP * 0.35).normalized(), to_face)
	ik.l_at = plate.global_position - right * 0.22 + Vector3.UP * 0.022
	ik.l_fingers = (fwd * 0.9 + Vector3.DOWN * 0.12 + right * 0.2).normalized()
	ik.l_knuckles = right
	ik.l_thumb = right
	ik.look_at_pt = at[1] if t < 3.0 else mouth + fwd * 1.0 + Vector3.DOWN * 0.3
	ik.lean_in = 0.05
	# the piece: torn at 1.85 s (the poori smaller), in the fingertips, gone as the lips close at 3.8 s
	if t >= 1.85 and not taken.has("tear"):
		taken["tear"] = true
		Kit.bite(poori)
		piece.visible = true
	if piece.visible:
		piece.global_position = ik.pinch_point(skel)
	if t >= 3.8 and piece.visible:
		piece.visible = false
	var open := 0.3 * smoothstep(3.4, 3.7, t) * (1.0 - smoothstep(3.78, 3.9, t))
	var chew := 0.0
	if t > 3.9 and t < 5.6:
		chew = 0.05 + 0.05 * (0.5 + 0.5 * sin(t * TAU * 1.7))
	face.pose({"mouth-open": open + chew, "mouth-pursing": 0.25 * smoothstep(3.78, 3.9, t) * (1.0 - smoothstep(4.1, 4.4, t)),
		"mouth-compression": 0.15 if chew > 0.0 else 0.0})
	face.update(dt)
	# the camera close on his face and right hand
	var hand: Vector3 = at[1]
	var focus := hand.lerp(mouth, smoothstep(2.4, 3.3, t) * (1.0 - smoothstep(4.4, 5.2, t)))   # (the hand, then the mouth)
	cam.global_position = focus + right * 0.2 + fwd * 0.2 + Vector3.UP * 0.1   # (close on the fingers)
	cam.look_at(focus, Vector3.UP)
	_capture.call_deferred()
	return t > 6.2


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_jpg("%s/f_%04d.jpg" % [out, n], 0.85)
	n += 1
	for st in shot_at:
		if t >= float(st) and not taken.has(st):
			taken[st] = true
			img.save_jpg("%s/stage_%s.jpg" % [out, shot_at[st]], 0.9)
			var gap: float = ik.pinch_gap                    # (measured inside the IK, after the grip)
			print("GRIPTEST %s at %.2f s: grip %.2f, thumb-index gap %.1f cm, piece %s" % [shot_at[st], t, ik.pinch, gap * 100.0,
				"held at the fingertips" if piece.visible else "not shown"])
