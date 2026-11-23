extends Node
## (testing) --gfxaudit[=low|medium|high|ultra via --graphics=]: the graphics audit's evidence, from the game itself.
## At each test location (the car set down on its road, the chase camera, the city loaded round it) and each hour
## (morning, evening, night, and night in rain) a screenshot (user://gfx/<place>_<hour>.jpg) and three seconds
## measured: frames a second, the median frame's CPU time (process) and the GPU's render time, draw calls, objects
## and primitives in the frame, video memory and static memory. One line each, "GFX ...", and a summary at the end.
## --gfxonly=place,place: just those; --gfxhours=09:00,18:00: just those hours.

const PLACES := [
	{"id": "gandhipuram", "en": "Commercial road, Gandhipuram", "x": -560.0, "z": 250.0},
	{"id": "ganapathy", "en": "Residential street, Ganapathy", "x": 700.0, "z": -1990.0},
	{"id": "bunk", "en": "Kongu Fuels, Sathy Road", "x": 1197.0, "z": -2045.0},
	{"id": "police", "en": "Nagar police station", "x": 262.0, "z": -101.0},
	{"id": "hospital", "en": "Government hospital", "x": 236.0, "z": 2400.0},
	{"id": "race_course", "en": "Race Course: trees", "x": 962.0, "z": 1987.0},
	# fixed cameras on the baked-AO test landmarks (tools/bake/bake_ao.py): the camera 8 m up over a road spot, looking
	# at the landmark ("at"), the same every run (only with --gfxonly naming them)
	# "lm": in front of that landmark (its door side, local -Z), "dist" m off; "bld": the generated building nearest
	# (x, z), seen from the street side
	{"id": "lm_hospital", "en": "Government hospital (baked AO test)", "x": 236.0, "z": 2470.0, "lm": "hospital", "dist": 60.0, "cam": true},
	{"id": "lm_hotel", "en": "The Siruvani Grand (baked AO test)", "x": 2920.0, "z": -440.0, "lm": "hotel_grand", "dist": 45.0, "up": 15.0, "cam": true},
	{"id": "lm_bunk", "en": "Kongu Fuels, Ganapathy (baked AO test)", "x": 1197.0, "z": -2040.0, "lm": "bunk_ganapathy", "dist": 26.0, "up": 9.0, "cam": true},
	{"id": "lm_police", "en": "Nagar police station (shader AO test)", "x": 261.7, "z": -101.3, "bld": true, "dist": 26.0, "up": 14.0, "cam": true},
]
const HOURS := ["07:15", "13:00", "18:10", "21:30", "21:30r"]

var city
var lines: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://gfx"))
	var only: Array = []
	var hours: Array = HOURS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gfxonly="):
			only = a.get_slice("=", 1).split(",")
		if a.begins_with("--gfxhours="):
			hours = Array(a.get_slice("=", 1).split(","))
	await tree.create_timer(6.0).timeout
	print("GFX adapter %s · %s · window %s · preset %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(),
		str(DisplayServer.window_get_size()), str(load("res://scripts/graphics.gd").preset())])
	var places: Array = PLACES.duplicate()
	for a in OS.get_cmdline_user_args():               # --gfxlm=name,name: a fixed camera before each landmark named
		if a.begins_with("--gfxlm="):                  #  (landmarks.json), 60 m off its door side, 25 m up
			for entry in a.get_slice("=", 1).split(","):
				var nm := entry.get_slice(":", 0)            # (name:metres for a big one: the camera farther off)
				var dd := float(entry.get_slice(":", 1)) if entry.contains(":") else 60.0
				for lm in city.streamer.landmarks:
					if str(lm.get("name", "")) == nm:
						var fx := float(lm["x"]) + sin(float(lm["yaw"])) * dd
						var fz := float(lm["z"]) + cos(float(lm["yaw"])) * dd
						places.append({"id": "lm_" + nm, "en": nm, "x": fx, "z": fz, "lm": nm, "dist": dd, "up": 25.0 + dd * 0.25, "cam": true})
						only.append("lm_" + nm)
	for p in places:
		if (not only.is_empty() and not str(p["id"]) in only) or (only.is_empty() and p.has("cam")):
			continue
		var car = city.car
		car.freeze = true
		car.global_position = Vector3(float(p["x"]), 500.0, float(p["z"]))
		await tree.create_timer(1.0).timeout
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 25000:            # (the tiles round it in)
			if city.streamer.loaded.size() >= 9 and city.streamer.pending.is_empty():
				break
			await tree.create_timer(0.5).timeout
		var g: float = city.streamer.height_at(float(p["x"]), float(p["z"]))
		car.global_position = Vector3(float(p["x"]), (g if not is_nan(g) else 400.0) + 0.6, float(p["z"]))
		car.linear_velocity = Vector3.ZERO
		await tree.create_timer(3.0).timeout
		var fixed: Camera3D = null
		if p.has("cam"):                                  # (the same pose every run: before and after comparable)
			fixed = Camera3D.new()
			fixed.fov = 60.0
			add_child(fixed)
			var gy: float = g if not is_nan(g) else 400.0
			var ax := float(p["x"])
			var az := float(p["z"])
			var ly := gy
			var away := Vector2(0, 1)
			for lm in city.streamer.landmarks:               # (a landmark: from its door side; its own ground)
				if str(lm.get("name", "")) == str(p.get("lm", "")):
					ax = float(lm["x"])
					az = float(lm["z"])
					ly = float(lm["y"])
					away = Vector2(sin(float(lm["yaw"])), cos(float(lm["yaw"])))   # (its door: Blender -Y, Godot +Z)
			if p.has("bld"):                                 # (a generated building: the nearest one's centre)
				var bd := 30.0
				var here := Vector2(ax, az)
				var best := here
				for node in city.streamer.loaded.values():
					for b in (node as Node3D).get_meta("bldinfo", []):
						var c: Vector2 = b[1]
						if c.distance_to(here) < bd:
							bd = c.distance_to(here)
							best = c
				away = (here - best).normalized() if best != here else Vector2(0, 1)
				ax = best.x
				az = best.y
			away *= float(p.get("dist", 55.0))
			fixed.global_position = Vector3(ax + away.x, ly + float(p.get("up", 30.0)), az + away.y)   # (high: over the
			fixed.look_at(Vector3(ax, ly + 4.0, az), Vector3.UP)                                     #  neighbours)
			fixed.make_current()
		for h in hours:
			var rain := str(h).ends_with("r")
			var hm: PackedStringArray = str(h).trim_suffix("r").split(":")
			city.fines.sim.minute = float(hm[0]) * 60.0 + float(hm[1])
			if city.weather and city.weather.has_method("set_weather"):
				city.weather.set_weather("rain" if rain else "clear")
			await tree.create_timer(2.5).timeout
			var m := await _measure(3.0)
			var name := "%s_%s" % [p["id"], str(h).replace(":", "")]
			for f in 2:
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://gfx/%s.jpg" % name), 0.85)
			if fixed:
				fixed.make_current()
			var line := "GFX %-22s %5.1f fps · CPU %5.1f ms · GPU %5.1f ms · %5d draws · %5d objects · %6.0f k prims · VRAM %4.0f MB · RAM %4.0f MB" % [name,
				m["fps"], m["cpu"], m["gpu"], m["draws"], m["objects"], m["prims"] / 1000.0, m["vram"], m["ram"]]
			print(line)
			lines.append(line)
		if fixed:
			fixed.queue_free()
	print("GFX done: %d captures" % lines.size())
	tree.quit()


func _measure(secs: float) -> Dictionary:
	var tree := get_tree()
	var vp := get_viewport().get_viewport_rid()
	var cpu: Array = []
	var gpu: Array = []
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
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		n += 1
	var fps := float(Engine.get_frames_drawn() - frames0) / (float(Time.get_ticks_usec() - t0) / 1e6)
	cpu.sort()
	gpu.sort()
	return {"fps": fps, "cpu": cpu[cpu.size() / 2] if not cpu.is_empty() else 0.0, "gpu": gpu[gpu.size() / 2] if not gpu.is_empty() else 0.0,
		"draws": int(draws / maxi(n, 1)), "objects": int(objs / maxi(n, 1)), "prims": prims / maxi(n, 1),
		"vram": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"ram": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0}
