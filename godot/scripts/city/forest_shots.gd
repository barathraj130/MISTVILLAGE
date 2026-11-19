extends Node
## (testing) --forestshots[=view,view]: the forest pockets seen from fixed cameras (docs/FOREST_AND_GHAT_PLAN_2026-11-18.md),
## the same every run, at each hour of --foresthours=07:15,13:00,18:10,21:30 (default those four): a picture each
## (user://forest/<view>_<hhmm>.jpg) and three seconds measured (fps, the median frame's CPU time, draw calls,
## objects, primitives, video and static memory), one "FOREST ..." line each. With --noforest: the same without the
## pockets (before and after). Needs --clock= so the hours change the light.

const VIEWS := {
	# the TNAU Botanical Garden: from its east side at a person's eye height, and from above its middle
	"tnau_eye": {"at": Vector2(-3900.0, 126.0), "look": Vector2(-3990.0, 180.0), "up": 1.7},
	"tnau_high": {"at": Vector2(-3790.0, 210.0), "look": Vector2(-3935.0, 300.0), "up": 32.0},
	"tnau_path": {"at": Vector2(-3905.0, 120.0), "look": Vector2(-3925.0, 260.0), "up": 1.7},
	# the world's edge (the void beyond the streamed tiles): from high over the west of the city looking out west,
	# and at a person's height on an open road looking along it to the horizon
	"edge_high": {"at": Vector2(-3700.0, 600.0), "look": Vector2(-7000.0, 600.0), "up": 140.0},
	"edge_ground": {"at": Vector2(-3790.0, 160.0), "look": Vector2(-3790.0, -2000.0), "up": 1.7},
}

var city


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://forest"))
	var only: Array = VIEWS.keys()
	var hours: Array = ["07:15", "13:00", "18:10", "21:30"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--forestshots="):
			only = Array(a.get_slice("=", 1).split(","))
		if a.begins_with("--foresthours="):
			hours = Array(a.get_slice("=", 1).split(","))
	await tree.create_timer(6.0).timeout
	var cam := Camera3D.new()
	cam.fov = 62.0
	add_child(cam)
	for v in only:
		var p: Dictionary = VIEWS[v]
		var car = city.car
		car.freeze = true
		car.global_position = Vector3(p["at"].x + 6.0, 500.0, p["at"].y + 6.0)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 30000:
			if city.streamer.loaded.size() >= 9 and city.streamer.pending.is_empty():
				break
			await tree.create_timer(0.5).timeout
		var g: float = NAN
		var t1 := Time.get_ticks_msec()
		while is_nan(g) and Time.get_ticks_msec() - t1 < 15000:   # (the ground's collision in: a real height)
			g = city.streamer.height_at(p["at"].x, p["at"].y)
			if is_nan(g):
				await tree.create_timer(0.5).timeout
		var gl: float = city.streamer.height_at(p["look"].x, p["look"].y)
		print("FOREST %s: ground %.1f at the camera (%s)" % [v, g, "found" if not is_nan(g) else "NOT FOUND"])
		g = g if not is_nan(g) else 420.0
		gl = gl if not is_nan(gl) else g
		car.global_position = Vector3(p["at"].x + 6.0, g + 0.6, p["at"].y + 6.0)
		cam.global_position = Vector3(p["at"].x, g + float(p["up"]), p["at"].y)
		cam.look_at(Vector3(p["look"].x, gl + (1.8 if float(p["up"]) < 5.0 else 0.0), p["look"].y), Vector3.UP)
		cam.make_current()
		await tree.create_timer(3.0).timeout
		for h in hours:
			var hm: PackedStringArray = str(h).split(":")
			city.fines.sim.minute = float(hm[0]) * 60.0 + float(hm[1])
			await tree.create_timer(2.5).timeout
			cam.make_current()
			var m := await _measure(3.0)
			for f in 2:
				await RenderingServer.frame_post_draw
			var nm := "%s_%s" % [v, str(h).replace(":", "")]
			get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://forest/%s.jpg" % nm), 0.85)
			print("FOREST %-18s %5.1f fps · CPU %5.1f ms · %5d draws · %5d objects · %6.0f k prims · VRAM %4.0f MB · RAM %4.0f MB" % [nm,
				m["fps"], m["cpu"], m["draws"], m["objects"], m["prims"] / 1000.0, m["vram"], m["ram"]])
	print("FOREST done")
	tree.quit()


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
