extends Node3D
## The movement lab: a test ground where a scripted walker (player.gd's auto_input) moves Karthik through measured
## runs, through the real character physics, and prints one line per run ("MOVE {json}"):
##   start/stop    walking and running: seconds to 90% of the pace, metres to a stop after letting go
##   reverse       running, then the way back: seconds until going the other way at a walk, the slowest moment
##   slope10/20    up and down a 10° and a 20° ramp: the pace kept, whether he got up
##   stairs        up and down a flight (16 cm risers): whether he got to the top, the biggest rise in one frame
##                 (a "teleport" if over 20 cm), the time
##   kerb          a 15 cm kerb at a walk
##   corridor      a 0.9 m passage: through, or stuck
##   slide         the foot-slide ratio held while walking and running (1.0: feet planted; above: gliding)
## Run: Godot --headless --fixed-fps 60 --path godot scenes/movement_lab.tscn

const Walker := preload("res://scripts/player.gd")

var w: CharacterBody3D


func _ready() -> void:
	for act in ["move_forward", "move_back", "move_left", "move_right", "jump", "run", "release_mouse"]:
		if not InputMap.has_action(act):                         # (the game's actions, with no keys: the walker is scripted)
			InputMap.add_action(act)
	_box(Vector3(0, -1, 0), Vector3(400, 2, 400))                   # the ground
	_ramp(Vector3(-60, 0, 0), 10.0)
	_ramp(Vector3(-90, 0, 0), 20.0)
	for i in 10:                                                   # a flight of ten steps, 16 cm × 30 cm, then a landing
		var top := 0.16 * (i + 1)
		_box(Vector3(60, top * 0.5, -2.0 - i * 0.3 - 0.15), Vector3(2.0, top, 0.3))
	_box(Vector3(60, 0.8, -2.0 - 3.0 - 2.0 + 0.0), Vector3(2.0, 1.6, 4.0))
	_box(Vector3(90, 0.075, -6.0), Vector3(4.0, 0.15, 6.0))          # a kerb onto a pavement
	_box(Vector3(119.0 - 0.45 - 0.1, 1.2, -8.0), Vector3(0.2, 2.4, 12.0))   # a 0.9 m passage
	_box(Vector3(119.0 + 0.45 + 0.1, 1.2, -8.0), Vector3(0.2, 2.4, 12.0))
	Walker.avatar = "res://assets/people/story_karthik.glb"
	w = Walker.new()
	add_child(w)
	w.active = true
	_run()


func _box(at: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = at
	add_child(b)


func _ramp(at: Vector3, deg: float) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(3.0, 0.4, 30.0)
	cs.shape = sh
	b.add_child(cs)
	b.position = at + Vector3(0, sin(deg_to_rad(deg)) * 15.0 - 0.2, -15.0 * cos(deg_to_rad(deg)))
	b.rotation.x = deg_to_rad(deg)
	add_child(b)


func _report(test: String, d: Dictionary) -> void:
	d["test"] = test
	print("MOVE " + JSON.stringify(d))


func _place(at: Vector3) -> void:
	w.auto_input = Vector2.ZERO
	w.auto_run = false
	w.spawn_at(at, at + Vector3(0, 0, -5))                          # facing -Z, the way the runs go
	for i in 40:
		await get_tree().physics_frame


func _hsp() -> float:
	return Vector2(w.velocity.x, w.velocity.z).length()


func _run() -> void:
	await _start_stop(false)
	await _start_stop(true)
	await _reverse()
	await _slope(-60.0, 10)
	await _slope(-90.0, 20)
	await _stairs()
	await _kerb()
	await _corridor()
	print("MOVE done")
	get_tree().quit()


func _start_stop(run: bool) -> void:
	await _place(Vector3(0, 0, 100))
	w.auto_run = run
	w.auto_input = Vector2(0, -1)
	var pace: float = w.run_speed if run else w.walk_speed
	var t := 0.0
	var t90 := -1.0
	var slides: Array = []
	while t < 6.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t90 < 0.0 and _hsp() >= pace * 0.9:
			t90 = t
		if t > 3.0 and w.anim and w.anim.speed_scale > 0.0:
			var stride: float = (1.18 if w.avatar_run_stride else 1.5) if not run else (3.9 if w.avatar_run_stride else 5.5)
			slides.append(_hsp() / (stride * w.anim.speed_scale))
	var from: Vector3 = w.global_position
	w.auto_input = Vector2.ZERO
	var ts := 0.0
	while _hsp() > 0.05 and ts < 5.0:
		await get_tree().physics_frame
		ts += 1.0 / 60.0
	var avg := 0.0
	for x in slides:
		avg += x / slides.size()
	_report("run" if run else "walk", {"pace": pace, "t_to_90": snappedf(t90, 0.01), "stop_m": snappedf(from.distance_to(w.global_position), 0.01),
		"stop_s": snappedf(ts, 0.01), "slide": snappedf(avg, 0.02), "clip": w.anim.current_animation if w.anim else ""})


func _reverse() -> void:
	await _place(Vector3(20, 0, 100))
	w.auto_run = true
	w.auto_input = Vector2(0, -1)
	for i in 180:
		await get_tree().physics_frame
	w.auto_input = Vector2(0, 1)
	var t := 0.0
	var slowest := 99.0
	while t < 6.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		slowest = minf(slowest, _hsp())
		if w.velocity.z > w.walk_speed * 0.9:
			break
	_report("reverse", {"t_to_walk_back": snappedf(t, 0.01), "slowest": snappedf(slowest, 0.02)})


func _slope(x: float, deg: int) -> void:
	await _place(Vector3(x, 0, 3.0))
	w.auto_input = Vector2(0, -1)
	var t := 0.0
	var paces: Array = []
	while t < 30.0 and w.global_position.z > -27.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t > 2.0:
			paces.append(_hsp())
	var avg := 0.0
	for p in paces:
		avg += p / maxf(paces.size(), 1)
	_report("slope%d" % deg, {"up": w.global_position.z <= -27.0, "pace_up": snappedf(avg, 0.02), "height": snappedf(w.global_position.y, 0.01), "t": snappedf(t, 0.1)})


func _stairs() -> void:
	await _place(Vector3(60, 0, 0.0))
	w.auto_input = Vector2(0, -1)
	var t := 0.0
	var jump := 0.0                                                # the body you see (the capsule hops a step; the body
	var y0: float = w.global_position.y                              #  catches up with it over a fifth of a second)
	while t < 15.0 and w.global_position.z > -6.0:
		var y: float = w.model.global_position.y if w.model else w.global_position.y
		await get_tree().physics_frame
		t += 1.0 / 60.0
		jump = maxf(jump, (w.model.global_position.y if w.model else w.global_position.y) - y)
		if "--movetrace" in OS.get_cmdline_user_args() and (w.model.global_position.y - y) > 0.05:
			print("POP t=%.2f z=%.2f capsule=%.3f body=%.3f drop=%.3f" % [t, w.global_position.z, w.global_position.y, w.model.global_position.y, w._step_drop])
		if "--movetrace" in OS.get_cmdline_user_args() and int(t * 60.0) % 10 == 0 and t < 4.0:
			print("TRACE t=%.2f z=%.2f y=%.2f floor=%s wall=%s v=%.2f" % [t, w.global_position.z, w.global_position.y, w.is_on_floor(), w.is_on_wall(), Vector2(w.velocity.x, w.velocity.z).length()])
	var top: bool = w.global_position.y > 1.5
	_report("stairs_up", {"top": top, "rise_m": snappedf(w.global_position.y - y0, 0.02), "body_max_rise_per_frame": snappedf(jump, 0.03),
		"teleport": jump > 0.1, "t": snappedf(t, 0.1)})
	w.auto_input = Vector2(0, 1)
	t = 0.0
	while t < 15.0 and w.global_position.z < 0.5:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_report("stairs_down", {"bottom": w.global_position.y < 0.2, "t": snappedf(t, 0.1)})


func _kerb() -> void:
	await _place(Vector3(90, 0, 0.0))
	w.auto_input = Vector2(0, -1)
	var t := 0.0
	var minsp := 99.0
	while t < 6.0 and w.global_position.z > -5.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t > 1.0:
			minsp = minf(minsp, _hsp())
	_report("kerb", {"onto": w.global_position.y > 0.12, "slowest": snappedf(minsp, 0.02), "t": snappedf(t, 0.1)})


func _corridor() -> void:
	await _place(Vector3(119, 0, 0.0))
	w.auto_input = Vector2(0, -1)
	var t := 0.0
	while t < 15.0 and w.global_position.z > -14.5:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_report("corridor", {"through": w.global_position.z <= -14.5, "t": snappedf(t, 0.1)})
