extends Node3D
## Test bed for the Coimbatore streaming world (scenes/city_test.tscn), separate from the drive.
##   --auto            fly north from Gandhipuram at ~90 km/h, logging fps / tiles / memory, then quit
##   --shots=/abs/dir  screenshots at 15 s, 45 s and 80 s (with --auto)
##   (no flags)        drive your car in the city: W/S/A/D, Space handbrake, V camera (chase / cockpit / bonnet),
##                     R back onto the nearest road, L lights, H horn, Tab map (minimap always on), F free camera (fly)
##   --fly             start with the free camera: WASD move, Q/E down/up, Shift fast, mouse look (click to capture)

const Prof := preload("res://scripts/drive/prof.gd")
const Streamer := preload("res://scripts/city/city_streamer.gd")
const MB := preload("res://scripts/drive/mesh_builder.gd")
const Jeep := preload("res://scripts/drive/jeep.gd")
const CityMap := preload("res://scripts/city/city_map.gd")
const CityTraffic := preload("res://scripts/city/city_traffic.gd")
const CityWater := preload("res://scripts/city/city_water.gd")
const DriveHud := preload("res://scripts/city/drive_hud.gd")
const Fines := preload("res://scripts/city/fines.gd")
const CityPolice := preload("res://scripts/city/city_police.gd")

var streamer
var water                                   # tanks, ponds and lakes (city_water.gd)
var cam: Camera3D
var t := 0.0
var auto := false
var shots_dir := ""
var shot_times := [15.0, 45.0, 80.0]
var yaw := PI                               # looking north (−z)
var pitch := -0.05
var cam_y := 420.0
var path := PackedVector3Array()            # the road being driven (auto mode)
var path_i := 0
var landed := false
var used := {}                              # road pieces already driven (by first point)
var car: Jeep                               # your car (play mode)
var driving := false
var placed := false                         # the car waits, frozen, until the road under it has loaded
var cam_mode := 0                           # 0 chase, 1 cockpit, 2 bonnet
var _cam_prev_speed := 0.0
var _cam_acc := 0.0
var _cam_heading := Vector3.ZERO           # the chase camera follows a lagging heading: it swings out in corners
var _orbit := Vector2.ZERO                 # mouse look round the car (yaw, pitch), eases back when left alone
var _orbit_idle := 0.0
var _shake := 0.0
var hud: Control
var fines                                   # wallet and e-challans (fines.gd)
var _prof_frames := 0
var _r_down := false
var _jolt := 0.0
var _vy_prev := 0.0
var map
var traffic


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	auto = "--auto" in args
	for a in args:
		if a.begins_with("--shots="):
			shots_dir = a.get_slice("=", 1)
	_environment()
	streamer = Streamer.new()
	streamer.name = "City"
	add_child(streamer)
	water = CityWater.new()
	water.name = "Water"
	water.streamer = streamer
	add_child(water)
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://shaders/building.gdshader")
	var walk := StandardMaterial3D.new()
	walk.albedo_texture = load("res://assets/models/textures/parking_pavers_base.jpg")
	walk.normal_enabled = true
	walk.normal_texture = load("res://assets/models/textures/parking_pavers_normal.png")
	walk.roughness_texture = load("res://assets/models/textures/parking_pavers_rough.jpg")
	walk.albedo_color = Color(0.92, 0.88, 0.84)
	walk.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var kerb: StandardMaterial3D = MB.cc0_material("concrete", 3.0, 0.85)
	kerb.vertex_color_use_as_albedo = true
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://shaders/city_ground.gdshader")
	gm.set_shader_parameter("dry_tex", load("res://assets/drive/tex/dry_grass_color.jpg"))
	gm.set_shader_parameter("green_tex", load("res://assets/drive/tex/grass_color.jpg"))
	gm.set_shader_parameter("soil_tex", load("res://assets/drive/tex/red_soil_color.jpg"))
	var gn := NoiseTexture2D.new()
	gn.seamless = true
	gn.width = 256
	gn.height = 256
	gn.noise = FastNoiseLite.new()
	gn.noise.frequency = 0.02
	gm.set_shader_parameter("noise_tex", gn)
	streamer.set_materials(_road_material(), gm, bm, walk, kerb)
	var yard: StandardMaterial3D = MB.cc0_material("concrete", 2.5, 0.9, false)
	yard.albedo_color = Color(0.86, 0.84, 0.8)
	var wall: StandardMaterial3D = MB.cc0_material("plaster", 2.5, 0.9)
	wall.vertex_color_use_as_albedo = true
	streamer.set_yard_materials(yard, wall)
	cam = Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # moved every frame from the car's smoothed pose
	cam.fov = 70.0
	cam.far = 4000.0
	cam.position = Vector3(0, cam_y, 0)
	add_child(cam)
	cam.make_current()
	streamer.target = cam
	var play := not auto and not "--fly" in args and not "--top" in args
	for a in args:
		if a.begins_with("--survey=") or a.begins_with("--view="):
			play = false
	if play:
		for pair in [["accelerate", [KEY_W, KEY_UP]], ["brake", [KEY_S, KEY_DOWN]], ["steer_left", [KEY_A, KEY_LEFT]],
				["steer_right", [KEY_D, KEY_RIGHT]], ["handbrake", [KEY_SPACE]], ["horn", [KEY_H]], ["headlights", [KEY_L]],
				["toggle_manual", [KEY_M]], ["shift_up", [KEY_X]], ["shift_down", [KEY_Z]], ["indicate_left", [KEY_COMMA]],
				["indicate_right", [KEY_PERIOD]], ["hazards", [KEY_SLASH]], ["steer_less", [KEY_BRACKETLEFT]],
				["steer_more", [KEY_BRACKETRIGHT]]]:
			if not InputMap.has_action(pair[0]):          # the drive game's keys (drive_game.gd _setup_input)
				InputMap.add_action(pair[0], 0.08)
				for kc in pair[1]:
					var ev := InputEventKey.new()
					ev.physical_keycode = kc
					InputMap.action_add_event(pair[0], ev)
		# a gamepad or wheel: left stick steers, right trigger accelerates, left trigger brakes
		for jb in [["accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["brake", JOY_AXIS_TRIGGER_LEFT, 1.0],
				["steer_left", JOY_AXIS_LEFT_X, -1.0], ["steer_right", JOY_AXIS_LEFT_X, 1.0]]:
			var je := InputEventJoypadMotion.new()
			je.axis = jb[1]
			je.axis_value = jb[2]
			InputMap.action_add_event(jb[0], je)
		for jb in [["handbrake", JOY_BUTTON_B], ["horn", JOY_BUTTON_LEFT_STICK], ["headlights", JOY_BUTTON_DPAD_UP],
				["shift_up", JOY_BUTTON_RIGHT_SHOULDER], ["shift_down", JOY_BUTTON_LEFT_SHOULDER]]:
			var jbe := InputEventJoypadButton.new()
			jbe.button_index = jb[1]
			InputMap.action_add_event(jb[0], jbe)
		car = Jeep.new()
		car.name = "Car"
		car.freeze = true
		add_child(car)
		car.global_position = Vector3(0, 600, 0)
		driving = true
		streamer.target = car
		traffic = CityTraffic.new()
		traffic.name = "Traffic"
		traffic.streamer = streamer
		traffic.player = car
		if not "--notraffic" in args:
			add_child(traffic)
		fines = Fines.new()
		fines.load_wallet()
		fines.persist = not ("--testdrive" in args or "--carshot" in args or "--trafficshot" in args)
		hud = DriveHud.new()
		hud.car = car
		hud.fines = fines
		var police := CityPolice.new()
		police.name = "Police"
		police.car = car
		police.streamer = streamer
		police.hud = hud
		police.fines = fines
		add_child(police)
		var hl := CanvasLayer.new()
		hl.add_child(hud)
		add_child(hl)
		traffic.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		map = CityMap.new()
		map.name = "Map"
		map.target = car
		if not "--nomap" in args:
			add_child(map)
	for a in args:
		if a.begins_with("--view="):
			for v in a.get_slice("=", 1).split(","):
				view.append(float(v))
		if a.begins_with("--survey="):
			_survey_setup(int(a.get_slice("=", 1)))
		if a.begins_with("--policeat="):                    # x,y,z,dx,dz: a police checkpoint there (views)
			var v: PackedStringArray = a.get_slice("=", 1).split(",")
			var pc := CityPolice.new()
			add_child(pc)
			pc.place(Vector3(float(v[0]), float(v[1]), float(v[2])), Vector3(float(v[3]), 0, float(v[4])).normalized())
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	get_viewport().scaling_3d_scale = 0.67
	get_viewport().mesh_lod_threshold = 8.0 if "--lod8" in OS.get_cmdline_user_args() else 3.0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.5, 0.78)
	sm.sky_horizon_color = Color(0.72, 0.78, 0.85)
	sm.ground_horizon_color = Color(0.6, 0.6, 0.6)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.0003
	env.fog_aerial_perspective = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-35), 0)
	sun.light_energy = 2.6
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.shadow_enabled = not "--noshadow" in OS.get_cmdline_user_args()
	sun.directional_shadow_max_distance = 160.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)


func _road_material() -> Material:
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/road_surface.gdshader")
	sm.set_shader_parameter("albedo_tex", load("res://assets/drive/tex/asphalt_color.jpg"))
	sm.set_shader_parameter("normal_tex", load("res://assets/drive/tex/asphalt_normal.jpg"))
	sm.set_shader_parameter("rough_tex", load("res://assets/drive/tex/asphalt_rough.jpg"))
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	nz.fractal_octaves = 4
	nz.frequency = 0.012
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.generate_mipmaps = true
	nt.noise = nz
	sm.set_shader_parameter("noise_tex", nt)
	sm.set_shader_parameter("city_marks", true)
	sm.set_shader_parameter("tint", Color(0.44, 0.44, 0.46))          # darker, like the Blender reference
	return sm


## --survey=N: visit N spread-out tiles; at each, a street-level shot along a road and a 45° view from above.
var survey: Array = []
var survey_i := -1
var survey_wait := 0.0
var survey_stage := 0


func _survey_setup(n: int) -> void:
	var keys: Array = []
	for k in streamer.index["tiles"]:
		var c: Array = streamer.index["tiles"][k]
		if c[0] > 2 and c[1] > 8:
			keys.append(k)
	keys.sort()
	var step := maxi(1, keys.size() / n)
	for i in range(0, keys.size(), step):
		var parts: PackedStringArray = keys[i].split(",")
		survey.append(Vector2i(int(parts[0]), int(parts[1])))
	survey = survey.slice(0, n)


func _survey(dt: float) -> void:
	survey_wait += dt
	if survey_i < 0 or survey_stage >= 2:
		survey_i += 1
		survey_stage = 0
		survey_wait = 0.0
		if survey_i >= survey.size():
			get_tree().quit()
			return
		var k: Vector2i = survey[survey_i]
		cam.position = Vector3((k.x + 0.5) * streamer.tile, 600.0, (k.y + 0.5) * streamer.tile)
		return
	var k: Vector2i = survey[survey_i]
	if not streamer.loaded.has(k) or survey_wait < 6.0:
		if survey_wait > 40.0:                       # never loaded: note it and move on
			print("SURVEY %d tile %s SKIPPED pending=%d ready=%d loaded=%d cam=%s" % [survey_i, str(k), streamer.pending.size(),
				streamer.ready_q.size(), streamer.loaded.size(), str(cam.position)])
			survey_stage = 2
		return
	if survey_stage == 0 and survey_wait < 6.5:
		var roads: Array = (streamer.loaded[k] as Node3D).get_meta("roads", [])
		var best = null
		for r in roads:
			if best == null or float(r["w"]) * (r["p"].size()) > float(best["w"]) * (best["p"].size()):
				best = r
		var p = best["p"]
		var n: int = p.size() / 3
		var i := maxi(0, n / 2 - 1)
		var a := Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
		var b := Vector3(p[(i + 1) * 3], p[(i + 1) * 3 + 1], p[(i + 1) * 3 + 2])
		var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var left := Vector3(dir.z, 0, -dir.x)
		cam.position = a + left * float(best["w"]) * 0.25 + Vector3(0, 1.5, 0)
		yaw = atan2(-dir.x, -dir.z)
		pitch = -0.04
		cam.basis = Basis.from_euler(Vector3(pitch, yaw, 0))
		set_meta("aim", a)
		set_meta("dir", dir)
		return
	if survey_wait >= 8.0 and survey_stage == 0:
		get_viewport().get_texture().get_image().save_jpg("%s/s%02d_street.jpg" % [shots_dir, survey_i], 0.8)
		var a: Vector3 = get_meta("aim")
		var dir: Vector3 = get_meta("dir")
		cam.position = a - dir * 30.0 + Vector3(0, 32.0, 0)
		cam.look_at(a + dir * 20.0, Vector3.UP)
		survey_stage = 1
		survey_wait = 8.0
		return
	if survey_stage == 1 and survey_wait >= 10.0:
		get_viewport().get_texture().get_image().save_jpg("%s/s%02d_above.jpg" % [shots_dir, survey_i], 0.8)
		print("SURVEY %d tile %s" % [survey_i, str(k)])
		survey_stage = 2


## --view=x,y,z,yaw_deg,pitch_deg: hold the camera there, save view.jpg after 25 s and quit (comparisons)
var view := PackedFloat32Array()


## Put the car on the nearest main road to `near`, keeping left, facing along the road.
func _place_car(near: Vector3) -> bool:
	var best = null
	var bd := INF
	var bi := 0
	for k in streamer.loaded:
		for r in (streamer.loaded[k] as Node3D).get_meta("roads", []):
			if r.get("fly", false) or not r["c"] in ["trunk", "primary", "secondary", "tertiary", "residential", "unclassified"]:
				continue
			var p = r["p"]
			for i in p.size() / 3 - 1:
				var d := Vector2(p[i * 3] - near.x, p[i * 3 + 2] - near.z).length()
				var bonus := 0.0 if r["c"] in ["trunk", "primary", "secondary"] else (5000.0 if "--testdrive" in OS.get_cmdline_user_args() else 25.0)
				if d + bonus < bd:
					bd = d + bonus
					best = r
					bi = i
	if best == null:
		return false
	var p = best["p"]
	var a := Vector3(p[bi * 3], p[bi * 3 + 1], p[bi * 3 + 2])
	var b := Vector3(p[bi * 3 + 3], p[bi * 3 + 4], p[bi * 3 + 5])
	var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var left := Vector3(dir.z, 0, -dir.x)
	var spot := a + left * float(best["w"]) * 0.25
	var g: float = streamer.height_at(spot.x, spot.z)
	if is_nan(g):
		return false
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	var basis := Basis.looking_at(-dir if Jeep.FWD > 0.0 else dir, Vector3.UP)
	car.global_transform = Transform3D(basis, Vector3(spot.x, g + 0.8, spot.z))
	car.freeze = false
	car.reset_physics_interpolation()
	_cam_heading = Vector3.ZERO
	_cam_prev_speed = 0.0
	cam.global_position = car.global_position - dir * 9.0 + Vector3.UP * 3.0
	return true


## Jumping a red: crossing the line of a signal that faces you while it shows red. Signals come from the loaded
## tiles ([position, yaw (the way the lights face), phase]), as the traffic reads them.
var _sig_prev := {}


func _red_light_check() -> void:
	if hud == null or absf(car.speed) < 2.0:
		return
	var cp: Vector3 = car.global_position
	var fwd: Vector3 = car.forward()
	var seen := {}
	var key := Vector2i(floori(cp.x / 256.0), floori(cp.z / 256.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var tile = streamer.loaded.get(Vector2i(key.x + dx, key.y + dz))
			if tile == null:
				continue
			for s_ in (tile as Node3D).get_meta("signals", []):
				var sp: Vector3 = s_[0]
				if sp.distance_to(cp) > 30.0:
					continue
				var f := Vector3(sin(float(s_[1])), 0, cos(float(s_[1])))
				if fwd.dot(f) > -0.7:                     # not facing me
					continue
				var x := Vector3.UP.cross(f)
				var lateral := (cp - sp).dot(x)
				if lateral < -2.0 or lateral > 14.0:      # not on this approach's lanes (they reach right of the pole)
					continue
				var past := (cp - sp).dot(-f)             # > 0 once past the signal
				var id := "%d,%d" % [roundi(sp.x * 10), roundi(sp.z * 10)]
				seen[id] = past
				if _sig_prev.has(id) and _sig_prev[id] < 0.0 and past >= 0.0:
					_crossed_signal(sp, Streamer.signal_state(float(s_[2])))
	_sig_prev = seen


## Crossing a junction's signal line: the red-light camera and the speed camera (where the junction has them).
func _crossed_signal(sp: Vector3, state: int) -> void:
	var kmh := absf(car.speed) * 3.6
	if state == 2:
		if fines and Fines.has_red_camera(sp):
			fines.challan("Red light jumped", Fines.RED_LIGHT)
			hud.warn("E-CHALLAN %s · red light jumped (camera)" % Fines.rupees(Fines.RED_LIGHT))
		else:
			hud.warn("RED LIGHT — you jumped the signal")
	elif fines and kmh > Fines.CITY_LIMIT_KMH + 5.0 and Fines.has_speed_camera(sp):
		fines.challan("Overspeeding %d km/h" % roundi(kmh), Fines.OVERSPEED)
		hud.warn("E-CHALLAN %s · %d km/h in a 50 zone (camera)" % [Fines.rupees(Fines.OVERSPEED), roundi(kmh)])


func _drive_camera(dt: float) -> void:
	# the car's pose between physics steps (physics interpolation): smooth at any frame rate
	var jt: Transform3D = car.get_global_transform_interpolated()
	var fwd: Vector3 = (jt.basis * Vector3(0, 0, 1)).normalized()
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var face := Basis.looking_at(fwd, Vector3.UP)
	_shake = maxf(_shake * exp(-dt * 7.0), clampf((car.jolt - 12.0) / 60.0, 0.0, 0.35))
	_orbit_idle += dt
	if _orbit_idle > 1.6:
		_orbit = _orbit.lerp(Vector2.ZERO, 1.0 - exp(-dt * 2.5))
	match cam_mode:
		0:
			var acc: float = (car.speed - _cam_prev_speed) / maxf(dt, 0.001)
			_cam_prev_speed = car.speed
			_cam_acc = lerpf(_cam_acc, clampf(acc, -8.0, 4.0), 1.0 - exp(-dt * 3.0))
			# the heading lags the car's: in a bend the camera swings out and shows the corner
			if _cam_heading == Vector3.ZERO:
				_cam_heading = flat
			_cam_heading = _cam_heading.slerp(flat, 1.0 - exp(-dt * lerpf(2.2, 4.0, clampf(absf(car.speed) / 25.0, 0.0, 1.0)))).normalized()
			var h := _cam_heading.rotated(Vector3.UP, _orbit.x)
			var back: float = car.chase_back + _cam_acc * 0.14 + clampf(absf(car.speed) / 30.0, 0.0, 1.0) * 1.2
			var up: float = car.chase_up + _orbit.y * back
			var want := jt.origin - h * back + Vector3.UP * up
			cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-dt * 6.0))
			var pivot := jt.origin + Vector3.UP * 1.6
			var q := PhysicsRayQueryParameters3D.create(pivot, cam.global_position)
			q.exclude = [car.get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				cam.global_position = hit["position"] + (pivot - hit["position"]).normalized() * 0.4
			cam.look_at(jt.origin + Vector3.UP * (car.chase_up * 0.48) + h * 4.0)
			cam.fov = lerpf(cam.fov, 64.0 + clampf(absf(car.speed) / 30.0, 0.0, 1.0) * 10.0, 1.0 - exp(-dt * 1.5))
		1:
			cam.fov = 74.0
			# head turns with the mouse; a little head movement from the road and the g-forces
			var look := face * Basis(Vector3.UP, _orbit.x * 1.6) * Basis(Vector3.RIGHT, deg_to_rad(-5.0) + _orbit.y)
			var bob := Vector3(0, -clampf(car.jolt / 400.0, 0.0, 0.03), -clampf(_cam_acc * 0.006, -0.04, 0.04))
			cam.global_transform = Transform3D(look, jt * (car.seat + bob))
		2:
			cam.fov = 70.0
			cam.global_transform = Transform3D(face * Basis(Vector3.UP, _orbit.x), jt * car.bonnet)
	if _shake > 0.001:
		cam.global_position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * _shake * 0.12


func _process(dt: float) -> void:
	t += dt
	if water:
		water.target = streamer.target
	if driving:
		if not placed:
			placed = _place_car(Vector3.ZERO) if t > 1.0 else false
			cam.global_position = Vector3(0, 80, 40)
			cam.look_at(Vector3.ZERO)
			return
		if Input.is_key_pressed(KEY_R) and not _r_down:
			_place_car(car.global_position)
		_r_down = Input.is_key_pressed(KEY_R)
		_drive_camera(dt)
		_red_light_check()
		if "--trafficshot" in OS.get_cmdline_user_args():
			if int(t) != int(t - dt) and int(t) % 5 == 0:
				var moving: int = traffic.vehicles.filter(func(v): return v["speed"] > 1.0).size()
				var sp := 0.0
				for v in traffic.vehicles:
					sp += v["speed"]
				print("TRAFFIC t=%d vehicles=%d moving=%d mean=%.1f km/h fps=%d" % [int(t), traffic.vehicles.size(), moving,
					sp / maxf(1, traffic.vehicles.size()) * 3.6, Engine.get_frames_per_second()])
			if t > 30.0 and shots_dir != "":
				var near = null
				for v in traffic.vehicles:
					if near == null or v["pos"].distance_to(car.global_position) < near["pos"].distance_to(car.global_position):
						near = v
				if near != null:
					cam.global_position = near["pos"] - near["fwd"] * 12.0 + Vector3.UP * 4.0 + Vector3(near["fwd"].z, 0, -near["fwd"].x) * 4.0
					cam.look_at(near["pos"] + near["fwd"] * 6.0)
				if t > 30.5:
					get_viewport().get_texture().get_image().save_jpg(shots_dir + "/traffic.jpg", 0.85)
					get_tree().quit()
				return
		if "--carshot" in OS.get_cmdline_user_args() and t > 5.0:      # side view of the car (checking the model)
			var ct := car.global_transform
			cam.global_position = ct.origin + ct.basis.x * 5.0 + Vector3.UP * 1.0
			cam.look_at(ct.origin + Vector3.UP * 0.6)
			if t > 6.0 and shots_dir != "":
				get_viewport().get_texture().get_image().save_jpg(shots_dir + "/car.jpg", 0.85)
				print("WHEELS %d %s" % [car._wheels.size(), str(car._wheels.map(func(w): return w.get_child_count()))])
				get_tree().quit()
			return
		if "--testdrive" in OS.get_cmdline_user_args():          # self-test: accelerate, report, screenshot, quit
			# a test driver: follows the main roads at ~50 km/h, keeping left (pure pursuit 12 m ahead)
			car.autopilot = true
			if path.is_empty() or path_i >= path.size() - 1:
				var nxt := _next_piece(car.global_position if path.is_empty() else path[path.size() - 1])
				if not nxt.is_empty():
					path = nxt
					path_i = 0
			var steer := 0.0
			if path.size() > 1:
				while path_i < path.size() - 1 and Vector2(path[path_i].x - car.global_position.x, path[path_i].z - car.global_position.z).length() < 12.0:
					path_i += 1
				var a2 := path[maxi(path_i - 1, 0)]
				var b2 := path[path_i]
				var d2 := Vector3(b2.x - a2.x, 0, b2.z - a2.z).normalized()
				var aim := b2 + Vector3(d2.z, 0, -d2.x) * 1.8
				var to := (aim - car.global_position)
				var f2: Vector3 = car.forward()
				var ang := atan2(f2.x * to.z - f2.z * to.x, f2.x * to.x + f2.z * to.z)
				steer = clampf(-ang * 1.6, -1.0, 1.0)
			var want := 14.0 if t > 4.0 and t < (40.0 if "--long" in OS.get_cmdline_user_args() else 12.0) else 0.0
			car.in_steer = steer
			car.in_throttle = clampf((want - car.speed) * 0.4, 0.0, 1.0)
			car.in_brake = clampf((car.speed - want - 1.0) * 0.3, 0.0, 1.0)
			# bumpiness: the car's vertical jolts (change of vertical speed per second), worst in each second
			var vy: float = car.linear_velocity.y
			_jolt = maxf(_jolt, absf(vy - _vy_prev) / maxf(dt, 0.001))
			_vy_prev = vy
			if int(t) != int(t - dt):
				print("DRIVE t=%d speed=%.1f km/h jolt=%.1f m/s2 pos=%s fps=%d" % [int(t), car.speed * 3.6, _jolt,
					str(car.global_position.round()), Engine.get_frames_per_second()])
				_jolt = 0.0
			if t > (42.0 if "--long" in OS.get_cmdline_user_args() else 13.0) and shots_dir != "" and not map.full_open:
				get_viewport().get_texture().get_image().save_jpg(shots_dir + "/drive.jpg", 0.85)
				map.pin = Vector2(car.global_position.x + 1500.0, car.global_position.z - 900.0)
				map.toggle()
			elif t > (43.5 if "--long" in OS.get_cmdline_user_args() else 14.5) and shots_dir != "" and map.full_open:
				get_viewport().get_texture().get_image().save_jpg(shots_dir + "/map.jpg", 0.85)
				get_tree().quit()
		_log_and_shots(dt)
		return
	if not view.is_empty():
		cam.position = Vector3(view[0], view[1], view[2])
		cam.basis = Basis.from_euler(Vector3(deg_to_rad(view[4]), deg_to_rad(view[3]), 0))
		if t > 25.0 and streamer.pending.is_empty() and streamer.ready_q.is_empty() and streamer.loaded.size() > 20:
			get_viewport().get_texture().get_image().save_jpg(shots_dir + "/view.jpg", 0.85)
			get_tree().quit()
		return
	if not survey.is_empty():
		_survey(dt)
		return
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	if auto:
		_drive(dt)
		cam.basis = Basis.from_euler(Vector3(pitch, yaw, 0))
		_log_and_shots(dt)
		return
	else:
		var mv := Vector3.ZERO
		var right := Vector3(-fwd.z, 0, fwd.x)
		if Input.is_key_pressed(KEY_W): mv += fwd
		if Input.is_key_pressed(KEY_S): mv -= fwd
		if Input.is_key_pressed(KEY_D): mv += right
		if Input.is_key_pressed(KEY_A): mv -= right
		var sp := 60.0 if Input.is_key_pressed(KEY_SHIFT) else 15.0
		cam.position += mv * sp * dt
		if Input.is_key_pressed(KEY_E): cam_y += 10.0 * dt
		if Input.is_key_pressed(KEY_Q): cam_y -= 10.0 * dt
	# ride 2.2 m above the ground once the tile under us is loaded
	var g: float = streamer.height_at(cam.position.x, cam.position.z)
	if not is_nan(g):
		if not auto and not landed:                   # free camera: start at eye height on the street
			cam_y = g + 1.8
			landed = true
		cam_y = lerpf(cam_y, g + 2.2, minf(1.0, dt * 4.0)) if auto else maxf(cam_y, g + 1.0)
	cam.position.y = cam_y
	cam.basis = Basis.from_euler(Vector3(pitch, yaw, 0))
	if "--top" in OS.get_cmdline_user_args():          # debugging view: straight down from 350 m
		cam.position = Vector3(0, 780, -200)
		cam.basis = Basis.from_euler(Vector3(-PI / 2, 0, 0))
	_log_and_shots(dt)


## Auto mode: drive along real main roads at ~80 km/h, keeping left, carrying on to the next piece of road.
func _drive(dt: float) -> void:
	if path.is_empty() or path_i >= path.size() - 1:
		var from := cam.position if path.is_empty() else path[path.size() - 1]
		var nxt := _next_piece(from)
		if nxt.is_empty():
			return
		path = nxt
		path_i = 0
		if Vector2(nxt[0].x - cam.position.x, nxt[0].z - cam.position.z).length() > 25.0:
			cam.position = nxt[0] + Vector3(0, 1.45, 0)          # a jump to another road: don't fly through hills
	var a := path[path_i]
	var b := path[path_i + 1]
	var seg := b - a
	var dir := Vector3(seg.x, 0, seg.z).normalized()
	var left := Vector3(dir.z, 0, -dir.x)
	var target := b + left * 1.7
	var to := target - Vector3(cam.position.x, target.y, cam.position.z)
	var step := 22.0 * dt
	if to.length() <= step:
		path_i += 1
	cam.position.x += to.normalized().x * minf(step, to.length())
	cam.position.z += to.normalized().z * minf(step, to.length())
	cam.position.y = lerpf(cam.position.y, a.y + 1.45, minf(1.0, dt * 3.0))
	yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z), minf(1.0, dt * 2.5))
	pitch = -0.04


func _next_piece(from: Vector3) -> PackedVector3Array:
	var best := PackedVector3Array()
	var bd := 30.0
	for k in streamer.loaded:
		for r in (streamer.loaded[k] as Node3D).get_meta("roads", []):
			if not r["c"] in ["trunk", "primary", "secondary"]:
				continue
			var a = r["p"]
			var n: int = a.size() / 3
			var first := Vector3(a[0], a[1], a[2])
			var last := Vector3(a[(n - 1) * 3], a[(n - 1) * 3 + 1], a[(n - 1) * 3 + 2])
			var key := "%.1f,%.1f" % [first.x, first.z]
			if used.has(key):
				continue
			for flip in [false, true]:
				var e := last if flip else first
				var dd := Vector2(e.x - from.x, e.z - from.z).length()
				if dd < bd:
					bd = dd
					best = PackedVector3Array()
					for i in n:
						var j := n - 1 - i if flip else i
						best.append(Vector3(a[j * 3], a[j * 3 + 1], a[j * 3 + 2]))
					used[key] = true
	if best.is_empty():                       # dead end: jump on the nearest main road not yet driven
		bd = INF
		for k in streamer.loaded:
			for r in (streamer.loaded[k] as Node3D).get_meta("roads", []):
				if r["c"] in ["trunk", "primary", "secondary"]:
					var a = r["p"]
					if used.has("%.1f,%.1f" % [a[0], a[2]]):
						continue
					var dd := Vector2(a[0] - from.x, a[2] - from.z).length()
					if dd < bd:
						bd = dd
						best = PackedVector3Array()
						for i in a.size() / 3:
							best.append(Vector3(a[i * 3], a[i * 3 + 1], a[i * 3 + 2]))
	return best


## --census: what the loaded city is made of — triangles (× instances) by node type and visibility range
func _census() -> void:
	var by := {}
	var stack: Array = [streamer]
	if water:
		stack.append(water)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var tris := 0
		var key := ""
		if n is MeshInstance3D and n.mesh:
			for si in n.mesh.get_surface_count():
				var a: Array = n.mesh.surface_get_arrays(si)
				tris += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
			key = "Mesh %s %.0f-%.0f shadow=%d" % [n.get_parent().name.left(8), n.visibility_range_begin, n.visibility_range_end, n.cast_shadow]
		elif n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh:
			var m: Mesh = n.multimesh.mesh
			var per := 0
			for si in m.get_surface_count():
				var a: Array = m.surface_get_arrays(si)
				per += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
			tris = per * n.multimesh.instance_count
			key = "MM %d-tri %.0f-%.0f shadow=%d" % [per, n.visibility_range_begin, n.visibility_range_end, n.cast_shadow]
		else:
			continue
		if not by.has(key):
			by[key] = [0, 0]
		by[key][0] += tris
		by[key][1] += 1
	var keys := by.keys()
	keys.sort_custom(func(x, y): return by[x][0] > by[y][0])
	for k in keys.slice(0, 40):
		print("CENSUS %8dk tris  %5d nodes  %s" % [by[k][0] / 1000, by[k][1], k])


func _log_and_shots(dt: float) -> void:
	if "--census" in OS.get_cmdline_user_args() and int(t) == 14 and int(t - dt) == 13:
		_census()
	if int(t) != int(t - dt) and int(t) % 5 == 0:
		print("CITY t=%3ds fps=%3d tiles=%3d built=%4d unloaded=%4d blds=%d designed=%d mem=%dMB vmem=%dMB draws=%d pos=(%.0f,%.0f)" % [
			int(t), Engine.get_frames_per_second(), streamer.stats["loaded"], streamer.stats["built"], streamer.stats["unloaded"],
			streamer.stats["buildings"], streamer.stats["designed"],
			int(OS.get_static_memory_usage() / 1048576), int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), cam.position.x, cam.position.z])
		var vp := get_viewport().get_viewport_rid()
		print("TIMES process=%.1fms physics=%.1fms nav=%.1fms objects=%d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		print("PROF %s" % Prof.report(maxi(Engine.get_frames_drawn() - _prof_frames, 1)))
		Prof.totals.clear()
		_prof_frames = Engine.get_frames_drawn()
		print("PRIMS %dk gpu=%.1fms cpu=%.1fms" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000),
			RenderingServer.viewport_get_measured_render_time_gpu(vp), RenderingServer.viewport_get_measured_render_time_cpu(vp)
			+ RenderingServer.get_frame_setup_time_cpu()])
	if auto and shots_dir != "" and not shot_times.is_empty() and t >= shot_times[0]:
		shot_times.pop_front()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("%s/city_%02d.jpg" % [shots_dir, int(t)], 0.85)
	if "--top" in OS.get_cmdline_user_args() and t > 12.0 and shots_dir != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(shots_dir + "/city_top.jpg", 0.85)
		get_tree().quit()
	if auto and t > 90.0:
		get_tree().quit()


func _unhandled_input(e: InputEvent) -> void:
	if car and driving and e is InputEventMouseMotion and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
			or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		_orbit.x = clampf(_orbit.x - e.relative.x * 0.004, -PI, PI)
		_orbit.y = clampf(_orbit.y - e.relative.y * 0.003, -0.25, 0.5)
		_orbit_idle = 0.0
		return
	if car and driving and e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_Y:
		cam_mode = (cam_mode + 1) % 3
		car.set_cockpit(cam_mode == 1)
		return
	if car and e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_V and driving:
			cam_mode = (cam_mode + 1) % 3
			car.set_cockpit(cam_mode == 1)
			return
		if e.keycode == KEY_F:
			driving = not driving
			map.target = car if driving else cam
			if driving:
				streamer.target = car
				car.freeze = false
			else:
				streamer.target = cam
				cam_y = cam.global_position.y
				yaw = cam.rotation.y
				pitch = cam.rotation.x
				car.freeze = true
			return
	if driving:
		return
	if e is InputEventMouseButton and e.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.003
		pitch = clampf(pitch - e.relative.y * 0.003, -1.3, 1.3)
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
