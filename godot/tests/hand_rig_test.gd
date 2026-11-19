extends SceneTree
## (testing) The hand rig on its own, with a small ball rather than food (the rig brief's isolated test): Karthik's
## right hand held before him through eat_ik.gd's hand-pose system, (1) open, (2) the thumb and index closing,
## (3) the ball held between the fingertips, (4) held while the wrist turns one way and the other, (5) released.
## One camera close on the hand: --cam=front|side|top. Stage pictures (with the thumb-index gap) and every frame:
##   godot --path . --audio-driver Dummy --script tests/hand_rig_test.gd -- --out=DIR --cam=front

const EatIK := preload("res://scripts/story/eat_ik.gd")

var out := ""
var view := "front"
var model: Node3D
var skel: Skeleton3D
var ik
var cam: Camera3D
var ball: MeshInstance3D
var t := -1.0
var n := 0
var stages := {0.8: "1_open", 1.6: "2_closing", 2.5: "3_holding", 3.4: "4a_wrist_turned", 4.2: "4b_wrist_back", 5.4: "5_released"}
var taken := {}
var fwd := Vector3(0, 0, 1)
var right := Vector3(-1, 0, 0)
var released_at := Vector3.ZERO


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		if a.begins_with("--cam="):
			view = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.33, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(150), 0)
	sun.light_energy = 1.5
	world.add_child(sun)
	model = (load("res://assets/people/story_karthik.glb") as PackedScene).instantiate()
	world.add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	(model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).play("Idle")
	ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.008
	sm.height = 0.016
	ball.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.9, 0.2, 0.15)
	ball.material_override = bm
	ball.visible = false
	world.add_child(ball)
	ik = EatIK.new()
	ik.face_fwd = fwd
	ik.active = true
	skel.add_child(ik)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.01
	world.add_child(cam)
	cam.make_current()
	root.size = Vector2i(1200, 800)


func _process(dt: float) -> bool:
	t += dt
	if t < 0.0:
		return false
	var hold := Vector3(-0.16, 1.18, 0.36)                  # (before his chest, a little to his right)
	var fingers := (fwd * 0.85 + Vector3.DOWN * 0.3 - right * 0.2).normalized()
	var grip := smoothstep(0.9, 1.7, t) * (1.0 - smoothstep(4.6, 5.2, t))
	# the wrist: turned one way (palm up) and back, the fingers a little up and down with it
	var turn := 0.8 * sin(clampf((t - 2.6) / 1.6, 0.0, 1.0) * PI) if t > 2.6 and t < 4.2 else 0.0
	var knuckles: Vector3 = Basis(fingers, turn) * right
	ik.r_at = hold
	ik.r_fingers = (Basis(right, 0.25 * turn) * fingers).normalized()
	ik.r_knuckles = knuckles
	ik.r_palm = Basis(fingers, turn) * (Vector3.DOWN * 0.6 - right * 0.8).normalized()
	ik.pinch = grip
	ik.l_at = Vector3(0.25, 0.95, 0.25)
	ik.l_fingers = Vector3.DOWN
	ik.l_knuckles = fwd
	ik.l_thumb = fwd
	ik.look_at_pt = hold
	ik.lean_in = 0.0
	# the ball: put between the fingertips as they close, held, then left where they let it go
	if grip > 0.85 and not taken.has("ball"):
		taken["ball"] = true
		ball.visible = true
	if ball.visible and grip > 0.4:
		ball.global_position = ik.pinch_world
		released_at = ball.global_position
	elif ball.visible:
		ball.global_position = released_at + Vector3.DOWN * 0.03 * smoothstep(5.0, 5.4, t)   # (let go: it drops a little)
	var focus: Vector3 = ik.pinch_world if ik.pinch_world != Vector3.ZERO else hold
	match view:
		"side":
			cam.global_position = focus - right * 0.26 + fwd * 0.06 + Vector3.UP * 0.03   # (from the thumb side: the pinch in view)
		"top":
			cam.global_position = focus + Vector3.UP * 0.26 + fwd * 0.04
		_:
			cam.global_position = focus + fwd * 0.26 + Vector3.UP * 0.04 + right * 0.04
	cam.look_at(focus, Vector3.UP if view != "top" else fwd)
	_capture.call_deferred()
	return t > 5.8


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_jpg("%s/f_%04d.jpg" % [out, n], 0.85)
	n += 1
	for st in stages:
		if t >= float(st) and not taken.has(st):
			taken[st] = true
			img.save_jpg("%s/stage_%s.jpg" % [out, stages[st]], 0.9)
			var held: bool = ball.visible and ik.pinch > 0.4
			print("RIGTEST %s %s at %.2f s: grip %.2f, thumb-index gap %.1f cm, ball %s" % [view, stages[st], t, ik.pinch,
				ik.pinch_gap * 100.0, "between the fingertips (%.1f cm from the pinch point)" % (ball.global_position.distance_to(ik.pinch_world) * 100.0) if held else ("released" if ball.visible else "not yet")])
