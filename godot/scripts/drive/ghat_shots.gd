extends Node
## (testing) --ghatshots[=view,view]: the ghat road's first three hairpins seen from fixed cameras placed along the
## route (route.gd frame_at: +Z forward, +X left, +Y up), the same every run, at each hour of
## --ghathours=07:15,13:00,18:10,21:30: a picture each (user://ghat/<view>_<hhmm>.jpg) and three seconds measured
## (fps, the median frame's CPU time, draw calls, objects, primitives, memory), one "GHAT ..." line each.
## With --noghatforest: the ghat as it was (before and after). docs/FOREST_AND_GHAT_PLAN_2026-11-18.md.

# d: metres along the route; side: metres to the left (+) or right (-) of the centreline; up: metres up;
# look: metres ahead along the road to look at (and how far to its side, "lside"), "lup" up there
const VIEWS := {
	"hp1_road": {"d": 11560.0, "side": 1.2, "up": 1.6, "look": 40.0, "lside": 0.0, "lup": 1.4},     # driving up to hairpin 1
	"hp1_above": {"d": 11656.0, "side": -30.0, "up": 26.0, "look": 0.0, "lside": 0.0, "lup": 0.0},  # hairpin 1 from above
	"forest_edge": {"d": 12200.0, "side": 4.5, "up": 1.7, "look": 6.0, "lside": 40.0, "lup": 4.0},  # into the forest uphill
	"hp2_road": {"d": 12330.0, "side": 1.2, "up": 1.6, "look": 45.0, "lside": 0.0, "lup": 1.4},     # into hairpin 2
	"hp3_valley": {"d": 13081.0, "side": 6.0, "up": 1.7, "look": 10.0, "lside": 120.0, "lup": -30.0, "valley": true},  # the valley from hairpin 3
	# driving at night as the player sees it: the jeep on its lane, headlights on, the camera where the chase camera
	# sits (behind and above it), looking along the road: into the bend before hairpin 1, and a straight in the forest
	"drive_bend": {"d": 11600.0, "jeep": true},
	"drive_forest": {"d": 12150.0, "jeep": true},
	"drive_bend_off": {"d": 11600.0, "jeep": true, "lights": false},     # (the same, headlights off: moonlight alone)
}

var game


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	while not game.ready_to_drive:
		await tree.create_timer(0.5).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ghat"))
	var only: Array = VIEWS.keys()
	var hours: Array = ["07:15", "13:00", "18:10", "21:30"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ghatshots="):
			only = Array(a.get_slice("=", 1).split(","))
		if a.begins_with("--ghathours="):
			hours = Array(a.get_slice("=", 1).split(","))
	var cam := Camera3D.new()
	cam.fov = 64.0
	cam.far = 12000.0
	add_child(cam)
	var route = game.route
	for v in only:
		var p: Dictionary = VIEWS[v]
		if p.has("jeep"):
			await _jeep_view(cam, route, float(p["d"]), v, hours, bool(p.get("lights", true)))
			continue
		var f: Transform3D = route.frame_at(float(p["d"]))
		var sgn := 1.0
		if p.has("valley"):                              # (on the downhill side, looking out over it)
			var l: Vector3 = f.origin + f.basis.x * 60.0
			var r: Vector3 = f.origin - f.basis.x * 60.0
			sgn = 1.0 if game.terrain.height_at(l.x, l.z) < game.terrain.height_at(r.x, r.z) else -1.0
		var at: Vector3 = f.origin + f.basis.x * float(p["side"]) * sgn
		var g: float = game.terrain.height_at(at.x, at.z)
		at.y = maxf(g, f.origin.y) + float(p["up"])
		var lf: Transform3D = route.frame_at(float(p["d"]) + float(p["look"]))
		var look: Vector3 = lf.origin + lf.basis.x * float(p["lside"]) * sgn + Vector3.UP * float(p["lup"])
		if game.jeep:                                    # (the jeep parked out of the picture, near: what's built near it is built)
			game.jeep.freeze = true
			game.jeep.global_position = route.frame_at(float(p["d"]) - 60.0).origin + Vector3.UP * 0.8
		cam.global_position = at
		cam.look_at(look, Vector3.UP)
		cam.make_current()
		await tree.create_timer(4.0).timeout
		for h in hours:
			var hm: PackedStringArray = str(h).split(":")
			game.sim.minute = float(hm[0]) * 60.0 + float(hm[1])
			await tree.create_timer(2.5).timeout
			cam.make_current()
			var m := await _measure(3.0)
			for k in 2:
				await RenderingServer.frame_post_draw
			var nm := "%s_%s" % [v, str(h).replace(":", "")]
			get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://ghat/%s.jpg" % nm), 0.85)
			print("GHAT %-18s %5.1f fps · CPU %5.1f ms · %5d draws · %5d objects · %6.0f k prims · VRAM %4.0f MB · RAM %4.0f MB" % [nm,
				m["fps"], m["cpu"], m["draws"], m["objects"], m["prims"] / 1000.0, m["vram"], m["ram"]])
	print("GHAT done")
	tree.quit()


## The jeep set on its lane (left of the centreline) at d, facing up the road, its headlights on; the camera 6.5 m
## behind and 2.4 m above it, looking 28 m ahead: the chase camera's view. Pictures and measures at each hour.
func _jeep_view(cam: Camera3D, route, d: float, v: String, hours: Array, lights := true) -> void:
	var tree := get_tree()
	var f: Transform3D = route.frame_at(d, 1.8)
	var j = game.jeep
	j.freeze = true
	var y: float = game.terrain.height_at(f.origin.x, f.origin.z)
	j.global_transform = Transform3D(Basis.looking_at(-f.basis.z, Vector3.UP), Vector3(f.origin.x, maxf(y, f.origin.y) + 0.6, f.origin.z))
	if j.has_method("set_lights"):
		j.set_lights(lights)
	var ahead: Transform3D = route.frame_at(d + 28.0, 1.8)
	cam.global_position = j.global_position - f.basis.z * 6.5 + Vector3.UP * 2.4
	cam.look_at(ahead.origin + Vector3.UP * 0.8, Vector3.UP)
	cam.make_current()
	await tree.create_timer(4.0).timeout
	for h in hours:
		var hm: PackedStringArray = str(h).split(":")
		game.sim.minute = float(hm[0]) * 60.0 + float(hm[1])
		await tree.create_timer(2.5).timeout
		if j.has_method("set_lights"):
			j.set_lights(lights)
		cam.make_current()
		var m := await _measure(3.0)
		for k in 2:
			await RenderingServer.frame_post_draw
		var nm := "%s_%s" % [v, str(h).replace(":", "")]
		get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://ghat/%s.jpg" % nm), 0.85)
		print("GHAT %-18s %5.1f fps · CPU %5.1f ms · %5d draws · %5d objects · %6.0f k prims · VRAM %4.0f MB · RAM %4.0f MB" % [nm,
			m["fps"], m["cpu"], m["draws"], m["objects"], m["prims"] / 1000.0, m["vram"], m["ram"]])


func _measure(secs: float) -> Dictionary:
	var tree := get_tree()
	var cpu: Array = []
	var draws := 0.0
	var objs := 0.0
	var prims := 0.0
	var n := 0
	var frames0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < t_end:
		await tree.process_frame
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		n += 1
	cpu.sort()
	return {"fps": float(Engine.get_frames_drawn() - frames0) / (float(Time.get_ticks_usec() - t0) / 1e6),
		"cpu": cpu[cpu.size() / 2] if not cpu.is_empty() else 0.0, "draws": int(draws / maxi(n, 1)),
		"objects": int(objs / maxi(n, 1)), "prims": prims / maxi(n, 1),
		"vram": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"ram": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0}
