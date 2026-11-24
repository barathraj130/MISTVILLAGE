extends SceneTree
## (testing) The editable man in a shirt (assets/people/person_man_shirt_custom.tscn, its "custom" clips), checked
## by measurement and pictures:
##   per clip: the loop's seam (each bone's turn from the last frame to the first, degrees), the biggest turn of any
##   bone between two frames 1/60 s apart (snapping), the hips' sideways travel (root motion: should be 0), and for the
##   idle the feet: how far each moves over the clip (planted: ~0)
##   pictures: the idle from the front, the side and the back; walk, run, talk, sit from the side; the shoulders close
##   transitions: walk → stop (to the idle, 0.35 s blend, as player.gd) and back, the feet and the hips through them
##   the scene: two players (the imported one with its five clips, the custom one with five), the original .glb's
##   clips unchanged
##   godot --path . --audio-driver Dummy --script tests/person_custom_test.gd -- --out=DIR

const SCENE := "res://assets/people/person_man_shirt_custom.tscn"

var out := ""
var model: Node3D
var ap: AnimationPlayer
var sk: Skeleton3D
var cam: Camera3D


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.6, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.88)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(210), 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	world.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	fl.mesh = pm
	world.add_child(fl)
	model = (load(SCENE) as PackedScene).instantiate() as Node3D
	world.add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	print("PCTEST players: %s" % ", ".join(PackedStringArray(players.map(func(p): return "%s %s" % [p.name, (p as AnimationPlayer).get_animation_list()]))))
	ap = players[0] as AnimationPlayer
	var cap := model.get_node("CustomAnimationPlayer") as AnimationPlayer
	ap.add_animation_library("custom", cap.get_animation_library("custom"))   # (as player.gd does)
	cap.active = false
	sk = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	cam = Camera3D.new()
	cam.fov = 35.0
	world.add_child(cam)
	cam.make_current()
	root.size = Vector2i(900, 1100)
	_run.call_deferred()


func _pose_at(clip: String, t: float) -> Array:
	ap.play(clip)
	ap.seek(t, true)
	ap.advance(0.0)
	var out_p: Array = []
	for b in sk.get_bone_count():
		out_p.append(sk.get_bone_global_pose(b))
	return out_p


func _measure(clip: String) -> void:
	var an := ap.get_animation(clip)
	var L := an.length
	var a0 := _pose_at(clip, 0.0)
	var a1 := _pose_at(clip, L - 0.0001)
	var seam := 0.0
	for b in a0.size():
		seam = maxf(seam, rad_to_deg((a0[b] as Transform3D).basis.get_rotation_quaternion().angle_to((a1[b] as Transform3D).basis.get_rotation_quaternion())))
	var step := 0.0
	var step_bone := ""
	var prev := a0
	var hips := sk.find_bone("Hips")
	var hx := 0.0
	var feet := {"Foot.L": [], "Foot.R": []}
	var t := 1.0 / 60.0
	while t < L:
		var p := _pose_at(clip, t)
		for b in p.size():
			var d := rad_to_deg((prev[b] as Transform3D).basis.get_rotation_quaternion().angle_to((p[b] as Transform3D).basis.get_rotation_quaternion()))
			if d > step:
				step = d
				step_bone = sk.get_bone_name(b)
		var ho: Vector3 = (p[hips] as Transform3D).origin - (a0[hips] as Transform3D).origin
		hx = maxf(hx, Vector2(ho.x, ho.z).length())
		for f in feet:
			(feet[f] as Array).append(sk.global_transform * (p[sk.find_bone(f)] as Transform3D).origin)
		prev = p
		t += 1.0 / 60.0
	var foot_move := 0.0
	for f in feet:
		var pts: Array = feet[f]
		for q in pts:
			foot_move = maxf(foot_move, (q as Vector3).distance_to(pts[0]))
	print("PCTEST %-18s length %.2f s, loop %s | seam %.2f deg | biggest turn in 1/60 s: %.2f deg (%s) | hips sideways %.1f mm | feet move %.1f mm" % [
		clip, L, "yes" if an.loop_mode == Animation.LOOP_LINEAR else "NO", seam, step, step_bone, hx * 1000.0, foot_move * 1000.0])


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	for f in 3:
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg("%s/%s.jpg" % [out, name], 0.9)


func _run() -> void:
	await process_frame
	for c in ["custom/Custom_Idle", "custom/Custom_Walk", "custom/Custom_Run", "custom/Custom_Talk", "custom/Custom_Sit"]:
		_measure(c)
	for c in ["Idle", "Walk", "Run"]:
		_measure(c)                                     # (the originals: for comparison, untouched)
	# the mesh on the skeleton: the body's bounds while idling, against the head and feet bones
	ap.play("custom/Custom_Idle")
	ap.seek(1.0, true)
	await process_frame
	var head: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
	var body := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var bb := body.global_transform * body.get_aabb()
	print("PCTEST mesh %.2f m tall (%.2f to %.2f), head bone at %.2f m: %s" % [bb.size.y, bb.position.y, bb.end.y, head.y, "on the body" if head.y < bb.end.y and head.y > bb.end.y - 0.35 else "OFF"])
	# pictures: the idle from three sides at three moments, the others from the side, the shoulders close
	var mid := Vector3(0, 0.95, 0)
	for k in 3:
		ap.play("custom/Custom_Idle")
		ap.seek(float(k) * 1.33, true)
		await _shot("idle_front_%d" % k, Vector3(0, 1.0, 3.6), mid)
		await _shot("idle_side_%d" % k, Vector3(3.6, 1.0, 0), mid)
		await _shot("idle_back_%d" % k, Vector3(0, 1.0, -3.6), mid)
	for c in ["Walk", "Run", "Talk", "Sit"]:
		ap.play("custom/Custom_" + c)
		var L := ap.get_animation("custom/Custom_" + c).length
		for k in 4:
			ap.seek(L * float(k) / 4.0, true)
			await _shot("%s_side_%d" % [c.to_lower(), k], Vector3(3.6, 0.9, 0.3), Vector3(0, 0.8, 0))
	ap.play("custom/Custom_Idle")
	ap.seek(2.0, true)
	await _shot("shoulders_close", Vector3(0.9, 1.5, 0.9), Vector3(0, 1.38, 0))
	# walk → stop → walk, with player.gd's blends: the left foot each frame, the custom clips and the originals the same
	# way (a swinging foot moves tens of mm a frame in any walk: the originals are the measure)
	for c in ["Walk", "custom/Custom_Walk"]:                 # (a plain cycle: what a foot does a frame anyway)
		var L := ap.get_animation(c).length
		var fb := sk.find_bone("Foot.L")
		var worst := 0.0
		var lastp := Vector3.INF
		var tt := 0.0
		while tt < L:
			var pp: Array = _pose_at(c, tt)
			var q: Vector3 = (pp[fb] as Transform3D).origin
			if lastp != Vector3.INF:
				worst = maxf(worst, q.distance_to(lastp))
			lastp = q
			tt += 1.0 / 60.0
		print("PCTEST cycle %s: the left foot's biggest move in a frame %.1f mm" % [c, worst * 1000.0])
	for set_ in [["custom/Custom_Walk", "custom/Custom_Idle"], ["Walk", "Idle"]]:
		await _transition(set_[0], set_[1])
	print("PCTEST done")
	quit()


func _transition(walk: String, idle: String) -> void:
	ap.play(walk)
	for f in 60:
		await process_frame
	var worst := 0.0
	var last := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Foot.L")).origin
	ap.play(idle, 0.35)
	var settle := 0.0
	for f in 60:
		await process_frame
		var now := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Foot.L")).origin
		worst = maxf(worst, now.distance_to(last))
		if f > 30:
			settle = maxf(settle, now.distance_to(last))
		last = now
	ap.play(walk, 0.25)
	for f in 40:
		await process_frame
		var now2 := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Foot.L")).origin
		worst = maxf(worst, now2.distance_to(last))
		last = now2
	if walk.begins_with("custom"):                       # (the picture after: taking it spans frames, unmeasured)
		ap.play(idle, 0.35)
		for f in 10:
			await process_frame
		await _shot("walk_to_stop", Vector3(3.6, 0.9, 0.3), Vector3(0, 0.8, 0))
	print("PCTEST transitions %s → %s (0.35 s) → back (0.25 s): the left foot's biggest move in a frame %.1f mm; still once stopped (from 0.5 s): %.1f mm" % [walk, idle, worst * 1000.0, settle * 1000.0])
