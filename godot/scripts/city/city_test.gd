extends Node3D
## Test bed for the Coimbatore streaming world (scenes/city_test.tscn), separate from the drive.
##   --auto            fly north from Gandhipuram at ~90 km/h, logging fps / tiles / memory, then quit
##   --shots=/abs/dir  screenshots at 15 s, 45 s and 80 s (with --auto)
##   (no flags)        drive your car in the city: W/S/A/D, Space handbrake, V camera (chase / cockpit / bonnet),
##                     R back onto the nearest road, L lights, H horn, Tab map (minimap always on),
##                     F get out and walk / back in at the car, F9 free camera (fly)
##   --fly             start with the free camera: WASD move, Q/E down/up, Shift fast, mouse look (click to capture)

const Prof := preload("res://scripts/drive/prof.gd")
const Streamer := preload("res://scripts/city/city_streamer.gd")
const Graphics := preload("res://scripts/graphics.gd")
const Grade := preload("res://scripts/city/grade.gd")
const Settings := preload("res://scripts/settings.gd")
const CityWalkers := preload("res://scripts/city/city_walkers.gd")
const CityActivity := preload("res://scripts/city/city_activity.gd")
const MB := preload("res://scripts/drive/mesh_builder.gd")
const Jeep := preload("res://scripts/drive/jeep.gd")
const CityMap := preload("res://scripts/city/city_map.gd")
const CityTraffic := preload("res://scripts/city/city_traffic.gd")
const CityWater := preload("res://scripts/city/city_water.gd")
const DriveHud := preload("res://scripts/city/drive_hud.gd")
const Fines := preload("res://scripts/city/fines.gd")
const CityPolice := preload("res://scripts/city/city_police.gd")
const CityWeather := preload("res://scripts/city/city_weather.gd")
const Bystanders := preload("res://scripts/city/city_bystanders.gd")
const Dents := preload("res://scripts/drive/dents.gd")
const Goods := preload("res://scripts/city/goods.gd")
const Store := preload("res://scripts/city/store.gd")
const Bag := preload("res://scripts/city/bag.gd")
const Threats := preload("res://scripts/city/city_threats.gd")
const Potholes := preload("res://scripts/city/city_potholes.gd")
const CityDoors := preload("res://scripts/city/city_doors.gd")
const Life := preload("res://scripts/city/life.gd")
const Story := preload("res://scripts/story/story.gd")
const Phone := preload("res://scripts/story/phone.gd")
const Bail := preload("res://scripts/city/bail.gd")
const Money := preload("res://scripts/city/money.gd")
const Hospital := preload("res://scripts/city/hospital.gd")
const Citizens := preload("res://scripts/city/citizens.gd")
const Gang := preload("res://scripts/city/gang.gd")
const RoomSound := preload("res://scripts/city/room_sound.gd")
const Hands := preload("res://scripts/story/hands.gd")
const Walker := preload("res://scripts/player.gd")

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
var path_lane := 1.8                         # how far left of the road's line its lane is (city_traffic.gd _lane)
var landed := false
var used := {}                              # road pieces already driven (by first point)
var car: Jeep                               # your car (play mode)
var spawn := Vector3.ZERO                   # where the car starts (Gandhipuram, or the story's first scene)
var story                                   # the story runner (story.gd), with --story or from the start menu
var env: Environment
var sun: DirectionalLight3D
var _auto_lights := false                   # the headlights went on by themselves at dusk (story mode)
var walker: Walker                          # you on foot (F)
var doors                                   # the doors of every building (city_doors.gd)
var indoors := false                        # a story scene in a room under the street: no sun, room light
var dark_room := false                      # a story room whose power has failed: only a torch and the street's glow
var driving := false
var placed := false                         # the car waits, frozen, until the road under it has loaded
var cam_mode := 0                           # CAM_MODES: 0 chase, 1 driver's eyes, 2 driver's head, 3 bonnet, 4 cinematic
## The driving cameras (V steps through them; Q / E look left / right, C behind, held; the mouse looks round):
##   Chase       behind and above, the heading lagging into a bend, further back with speed, never through a wall
##   Driver      his eyes, steady: only the faintest give to braking, pulling away, a corner, a bump
##   Driver head his head as it moves: a soft spring against the car's accelerations (back as it pulls away, on as
##               it brakes, out in a corner, a little lift over a bump), looking into the turn
##   Bonnet      over the bonnet, looking ahead
##   Cinematic   a slow orbit round the car, kept off walls
## Their settings (field of view, follow distance and height, smoothing, head movement, shake, invert) are the
## settings screen's "Camera" ones (settings.gd: camera/*).
const CAM_MODES := ["Chase", "Driver", "Driver (head)", "Bonnet", "Cinematic"]
var _cam_cfg := {}
var _cam_cfg_t := 0.0
var _head := Vector3.ZERO                   # the head's give, in the car's frame (m): right, up, forward
var _head_v := Vector3.ZERO
var _look_yaw := 0.0                        # Q / E / C: looking aside or behind (radians), eased
var _cine := 0.0                            # the cinematic camera's angle round the car
var _cam_prev_vy := 0.0
var _look_force := 0.0                      # (testing: a look held)
var _cam_prev_speed := 0.0
var _cam_acc := 0.0
var _cam_heading := Vector3.ZERO           # the chase camera follows a lagging heading: it swings out in corners
var _orbit := Vector2.ZERO                 # mouse look round the car (yaw, pitch), eases back when left alone
var _orbit_idle := 0.0
var _shake := 0.0
var hud: Control
var fines                                   # wallet and e-challans (fines.gd)
var life                                    # Karthik's stress and his outings (life.gd)
var _taught_foot := false
var bail                                    # his bail: signing, strikes, the district border (city/bail.gd)
var hospital                                # the 108 and the hospital (hospital.gd)
var citizens                                # the citizens with a day (citizens.gd)
var gang                                    # Suresh's people as the case closes in (gang.gd)
var money                                   # his money after the arrest: the frozen account, bills (city/money.gd)
var phone                                   # Karthik's phone, P (story/phone.gd)
var hands                                   # what he holds and carries, I (story/hands.gd)
var _prof_frames := 0
var _r_down := false
var _jolt := 0.0
var _vy_prev := 0.0
var map
var traffic
var police                                  # the police checking points (city_police.gd)
var weather                                 # rain and wet roads (city_weather.gd)
var bystanders                              # the people on the street, and a vehicle coming at them (city_bystanders.gd)
var store                                   # a shop's counter (store.gd), opened by city_doors.gd
var bag                                     # what he carries (bag.gd), B
var _b_down := false
var _l_down := false
var _torch: SpotLight3D                     # his torch, on foot (L), if he has one in the bag
var _hit_seen := {}                         # what you hit → when (a crash is one complaint, not one per contact)


## (testing) --profsweep (with --testdrive): where the frame goes. After 40 s, each script whose nodes work every
## frame or every physics step is switched off for a few seconds, in turn, and the drop in the frame's process and
## physics time is printed, largest first: what each costs, without timers in every script.
func _profsweep() -> void:
	var tree := get_tree()
	await tree.create_timer(40.0).timeout
	var by := {}
	for n in tree.root.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc == null or n == self or not (n.is_processing() or n.is_physics_processing()):
			continue
		var k := sc.resource_path.get_file() if sc.resource_path != "" else "(built in code: %s)" % n.get_class()
		if not by.has(k):
			by[k] = []
		by[k].append(n)
	var measure := func(secs: float) -> Vector2:          # (the median frame: one hitch doesn't count)
		var pr: Array = []
		var ph: Array = []
		var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
		await tree.process_frame
		while Time.get_ticks_msec() < t_end:
			await tree.process_frame
			pr.append(Performance.get_monitor(Performance.TIME_PROCESS))
			ph.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		pr.sort()
		ph.sort()
		return Vector2(pr[pr.size() / 2], ph[ph.size() / 2]) * 1000.0 if not pr.is_empty() else Vector2.ZERO
	var out: Array = []
	for k in by:
		var d: Array = []                                   # three times off and on: the median difference
		for rep in 3:
			var base: Vector2 = await measure.call(2.0)
			var was := {}
			for n in by[k]:
				if is_instance_valid(n):
					was[n] = [n.is_processing(), n.is_physics_processing()]
					n.set_process(false)
					n.set_physics_process(false)
			await tree.create_timer(0.3).timeout
			var off: Vector2 = await measure.call(2.0)
			for n in was:
				if is_instance_valid(n):
					n.set_process(was[n][0])
					n.set_physics_process(was[n][1])
			await tree.create_timer(0.3).timeout
			d.append(base - off)
		d.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
		var med: Vector2 = d[1]
		out.append([k, by[k].size(), med.x, med.y])
		print("PROFSWEEP %-26s ×%-4d process −%5.1f ms  physics −%5.1f ms  (fps %d)" % [k, by[k].size(), med.x, med.y, Engine.get_frames_per_second()])
	out.sort_custom(func(a, b): return a[2] + a[3] > b[2] + b[3])
	print("PROFSWEEP ---- largest first ----")
	for o in out:
		print("PROFSWEEP %-26s ×%-4d process %5.1f ms  physics %5.1f ms" % [o[0], o[1], o[2], o[3]])
	tree.quit()


## (testing) --jointest: where road pieces meet end to end without a junction surface (city_streamer.gd _joins),
## rays down at points in every patch and at both outer corners of every mitred join, in the tiles round the start:
## a ray that falls more than 5 cm below the road there found a hole (the ground). With --nojoins: the old roads.
func _jointest() -> void:
	var tree := get_tree()
	while not placed or streamer.loaded.size() < 20 or not streamer.pending.is_empty():
		await tree.process_frame
	await tree.create_timer(2.0).timeout
	var space := get_world_3d().direct_space_state
	var n := 0
	var holes := 0
	var worst := []
	for k in streamer.loaded:
		var roads: Array = (streamer.loaded[k] as Node3D).get_meta("roads", [])
		var j := _joins_for_test(roads)                       # (the same places either way: where the fix finds joins)
		var probes: Array = []                                # [point xz, road y]
		for pt in j["patches"]:
			var hull: PackedVector2Array = pt[1]
			var cen := Vector2.ZERO
			for q in hull:
				cen += q
			cen /= hull.size()
			for q in hull:
				probes.append([cen.lerp(q, 0.85), float(pt[0]) - 0.01])
		for ri in j["miter"]:
			var r: Dictionary = roads[ri]
			var pp: PackedFloat32Array = r["p"]
			for vq in j["miter"][ri]:
				var tdir: Vector3 = j["miter"][ri][vq][0]
				var sc: float = j["miter"][ri][vq][1]
				var c := Vector3(pp[vq * 3], pp[vq * 3 + 1], pp[vq * 3 + 2])
				var l := Vector3(tdir.z, 0, -tdir.x).normalized() * float(r["w"]) * 0.5 * sc * 0.9
				for side in [1.0, -1.0]:
					probes.append([Vector2(c.x + l.x * side, c.z + l.z * side), c.y + RANK_LIFT])
		for pr in probes:
			var at: Vector2 = pr[0]
			var y: float = pr[1]
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, y + 4.0, at.y), Vector3(at.x, y - 4.0, at.y)))
			n += 1
			if hit.is_empty() or float(hit["position"].y) < y - 0.05:
				holes += 1
				if worst.size() < 8:
					worst.append([roundi(at.x), roundi(at.y), snappedf(y - (float(hit["position"].y) if not hit.is_empty() else y - 9.0), 0.01)])
	print("JOINTEST %s: %d probes, %d over a hole %s" % ["old roads" if "--nojoins" in OS.get_cmdline_user_args() else "joins fixed", n, holes, str(worst)])
	tree.quit()


const RANK_LIFT := 0.09                                  # (= city_streamer.gd RANK + 0.06: a ribbon over its points)


## The joins the fix would find, without the --nojoins switch (for the before run's probes).
func _joins_for_test(roads: Array) -> Dictionary:
	return Streamer._joins_core(roads)


## (testing) --ride=KIND: you on that vehicle once the street's loaded (with --ridetest: the riding test on it).
func _ride_on(kind: String) -> void:
	while not placed or streamer.loaded.size() < 20 or not streamer.pending.is_empty():
		await get_tree().process_frame
	car.configure(kind)


## (testing) --surfacetest[=scooter]: the car (or Karthik's scooter) set down on the asphalt street 25 m before it
## becomes an earth road (x 463, z −1715, near home), driven straight on through the change and along the earth,
## at about 30 km/h; every half second: the surface its wheels feel, its speed, its height over the road, the
## wheels touching, and the hardest jolt (change of vertical speed) since the last line.
func _surfacetest() -> void:
	var tree := get_tree()
	while not placed or streamer.loaded.size() < 20 or not streamer.pending.is_empty():
		await tree.process_frame
	var scooter := "--surfacetest=scooter" in OS.get_cmdline_user_args()
	if scooter:
		car.configure("karthik_scooter")
	var j := Vector3(463.4, 423.7, -1714.8)
	var d := Vector3(1.79, 0, 5.72).normalized()
	var start := j - d * 25.0 + Vector3.UP * 0.8
	car.global_transform = Transform3D(Basis.looking_at(-d, Vector3.UP), start)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.autopilot = true
	await tree.create_timer(1.0).timeout
	var t := 0.0
	var vy := car.linear_velocity.y
	var jolt := 0.0
	var worst := 0.0
	var last := 0.0
	var surfaces := {}
	var airborne := 0
	while t < 14.0:
		var dt := get_physics_process_delta_time()
		await tree.physics_frame
		t += dt
		var ahead := car.global_position + d * 8.0
		var off := (ahead - j)
		var lat := off.dot(Vector3(d.z, 0, -d.x))               # (keep to the line of the street)
		var f: Vector3 = car.forward()
		car.in_steer = clampf(-atan2(f.x * d.z - f.z * d.x, f.x * d.x + f.z * d.z) * 2.0 + lat * 0.15, -1.0, 1.0)
		car.in_throttle = clampf((30.0 / 3.6 - car.speed) * 0.5, 0.0, 1.0)
		var a := absf(car.linear_velocity.y - vy) / maxf(dt, 0.001)
		vy = car.linear_velocity.y
		jolt = maxf(jolt, a)
		var touching := 0
		for w in car.get_children():
			if w is VehicleWheel3D and (w as VehicleWheel3D).is_in_contact():
				touching += 1
		if touching == 0:
			airborne += 1
		surfaces[car.surface] = true
		if t - last >= 0.5:
			last = t
			var along := (car.global_position - j).dot(d)
			print("SURFACETEST %s t=%4.1f along %+6.1f m  %-8s %4.1f km/h  wheels %d  jolt %5.1f m/s²" % ["scooter" if scooter else "car", t, along, car.surface,
				car.speed * 3.6, touching, jolt])
			worst = maxf(worst, jolt)
			jolt = 0.0
	print("SURFACETEST %s done: surfaces %s, hardest jolt %.1f m/s², frames with no wheel down %d" % ["scooter" if scooter else "car", str(surfaces.keys()), worst, airborne])
	tree.quit()


func _ready() -> void:
	if " --surfacetest" in " " + " ".join(OS.get_cmdline_user_args()):
		_surfacetest.call_deferred()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ride="):
			_ride_on.call_deferred(a.substr(7))
	if "--profsweep" in OS.get_cmdline_user_args():
		_profsweep.call_deferred()
	if "--jointest" in OS.get_cmdline_user_args():
		_jointest.call_deferred()
	for a in OS.get_cmdline_user_args():            # --upscale=fsr2|metalfx|metalfx_spatial|fsr,SCALE: render fewer pixels, rebuild
		if a.begins_with("--upscale="):
			var v := a.get_slice("=", 1).split(",")
			var modes := {"fsr": Viewport.SCALING_3D_MODE_FSR, "fsr2": Viewport.SCALING_3D_MODE_FSR2,
				"metalfx_spatial": Viewport.SCALING_3D_MODE_METALFX_SPATIAL, "metalfx": Viewport.SCALING_3D_MODE_METALFX_TEMPORAL}
			get_viewport().scaling_3d_mode = modes.get(v[0], Viewport.SCALING_3D_MODE_BILINEAR)
			get_viewport().scaling_3d_scale = float(v[1]) if v.size() > 1 else 0.67
			print("UPSCALE %s at %.2f" % [v[0], get_viewport().scaling_3d_scale])
	var args := OS.get_cmdline_user_args()
	auto = "--auto" in args
	for a in args:
		if a.begins_with("--shots="):
			shots_dir = a.get_slice("=", 1)
	_environment()
	streamer = Streamer.new()
	streamer.radius = int(Graphics.value("tiles"))             # (the view distance: the preset's tiles each way)
	streamer.name = "City"
	add_child(streamer)
	if not "--nowalkers" in args:                         # people walking the footpaths (city_walkers.gd)
		var cw := CityWalkers.new()
		cw.name = "Walkers"
		cw.city = self
		cw.count = int(Graphics.value("walkers"))
		add_child(cw)
		var ca := CityActivity.new()                      # people at bus stops, stalls, shops, guards (city_activity.gd)
		ca.name = "Activity"
		ca.city = self
		ca.count = int(Graphics.value("activity"))
		add_child(ca)
	doors = CityDoors.new()                            # every building can be walked into (city_doors.gd)
	doors.name = "Doors"
	doors.city = self
	add_child(doors)
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
		if a.begins_with("--survey=") or a.begins_with("--view=") or a.begins_with("--flyover="):
			play = false
	if play:
		for pair in [["accelerate", [KEY_W, KEY_UP]], ["brake", [KEY_S, KEY_DOWN]], ["steer_left", [KEY_A, KEY_LEFT]],
				["steer_right", [KEY_D, KEY_RIGHT]], ["handbrake", [KEY_SPACE]], ["horn", [KEY_H]], ["headlights", [KEY_L]],
				["toggle_manual", [KEY_M]], ["shift_up", [KEY_X]], ["shift_down", [KEY_Z]], ["indicate_left", [KEY_COMMA]],
				["indicate_right", [KEY_PERIOD]], ["hazards", [KEY_SLASH]], ["steer_less", [KEY_BRACKETLEFT]],
				["steer_more", [KEY_BRACKETRIGHT]],
				# on foot (player.gd: the house walk, eateries, meeting people)
				["move_forward", [KEY_W, KEY_UP]], ["move_back", [KEY_S, KEY_DOWN]], ["move_left", [KEY_A, KEY_LEFT]],
				["move_right", [KEY_D, KEY_RIGHT]], ["jump", [KEY_SPACE]], ["run", [KEY_SHIFT]],
				["release_mouse", [KEY_ALT]]]:
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
		traffic.busy = int(Graphics.value("traffic"))           # (the preset's: fewer on Low, the CPU's biggest share)
		traffic.count = mini(traffic.count, traffic.busy)
		traffic.name = "Traffic"
		traffic.streamer = streamer
		traffic.player = car
		if not "--notraffic" in args:
			add_child(traffic)
		fines = Fines.new()
		fines.load_wallet()
		var self_test := false                      # (a self-test never writes your saved game: wallet, challans, weather)
		for flag in ["--testdrive", "--carshot", "--trafficshot", "--crashtest", "--peopletest", "--parkedtest",
				"--potholetest", "--flyover", "--clock=", "--weather=", "--nohud", "--doortest", "--threattest", "--surfacetest", "--jointest", "--walkertest", "--activitytest",
				"--hospitaltest", "--citizentest", "--interviewtest", "--unsticktest", "--livingtest", "--livingbench", "--hospitalat", "--shotview", "--interacttest", "--falltest", "--stairtest", "--gaittest", "--standtest", "--gangtest", "--gangstage", "--pursuittest", "--socialtest", "--streetaudit", "--sittest"]:
			self_test = self_test or " ".join(args).contains(flag)
		fines.persist = not self_test
		hud = DriveHud.new()
		hud.car = car
		hud.fines = fines
		life = Life.new()
		life.name = "Life"
		life.city = self
		add_child(life)
		hud.life = life
		police = CityPolice.new()
		police.name = "Police"
		police.car = car
		police.streamer = streamer
		police.hud = hud
		police.fines = fines
		add_child(police)
		var hl := CanvasLayer.new()
		hl.add_child(hud)
		add_child(hl)
		var pl := CanvasLayer.new()                   # (over the story's subtitles: the phone and his hands are his)
		pl.layer = 25
		add_child(pl)
		hands = Hands.new()
		hands.name = "Hands"
		hands.city = self
		pl.add_child(hands)
		store = Store.new()
		store.name = "Store"
		store.finished.connect(_bought)
		pl.add_child(store)
		bag = Bag.new()
		bag.name = "Bag"
		bag.city = self
		pl.add_child(bag)
		var th := Threats.new()
		th.name = "Threats"
		th.city = self
		add_child(th)
		phone = Phone.new()
		phone.name = "Phone"
		phone.city = self
		pl.add_child(phone)
		police.phone = phone
		car.impacted.connect(_on_impact)
		bail = Bail.new()
		bail.name = "Bail"
		bail.city = self
		add_child(bail)
		var ph := Potholes.new()
		ph.name = "Potholes"
		ph.city = self
		add_child(ph)
		bystanders = Bystanders.new()
		bystanders.name = "Bystanders"
		bystanders.city = self
		add_child(bystanders)
		var living := preload("res://scripts/city/city_living.gd").new()   # the standing figures alive near him on foot
		living.name = "Living"
		living.city = self
		add_child(living)
		weather = CityWeather.new()
		weather.name = "Weather"
		weather.city = self
		add_child(weather)
		money = Money.new()
		money.name = "Money"
		money.city = self
		add_child(money)
		citizens = Citizens.new()                    # people with a home, a job and a day (citizens.gd)
		citizens.name = "Citizens"
		citizens.city = self
		add_child(citizens)
		if "--streetaudit" in args:                  # (development: the streets' connectivity, street_audit.gd)
			var au = load("res://scripts/city/street_audit.gd").new()
			au.city = self
			add_child(au)
		gang = Gang.new()                            # the watcher, the pursuit (gang.gd)
		gang.name = "Gang"
		gang.city = self
		add_child(gang)
		hospital = Hospital.new()                    # the 108 and the hospital: hunger, a bad crash (hospital.gd)
		hospital.name = "Hospital"
		hospital.city = self
		add_child(hospital)
		traffic.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		map = CityMap.new()
		map.name = "Map"
		map.target = car
		if not "--nomap" in args:
			add_child(map)
		_nohud = "--nohud" in args                  # (trailers: the picture only; the story's own subtitles stay)
		if "--story" in args or Engine.has_meta("story"):
			story = Story.new()
			story.name = "Story"
			if story.load_chapter():
				story.city = self
				story.car = car
				story.map = map
				story.hud = hud
				story.fines = fines
				fines.persist = false                   # (the slice doesn't touch your saved game)
				spawn = story.spawn_point()
				car.global_position = Vector3(spawn.x, 600, spawn.z)
				add_child(story)
	for a in args:
		if a.begins_with("--view="):
			for v in a.get_slice("=", 1).split(","):
				view.append(float(v))
		if a.begins_with("--clock="):
			if fines == null:                          # (a flyover has no car or wallet: only the clock is wanted)
				fines = Fines.new()
			var hm := a.get_slice("=", 1).split(":")
			fines.sim.minute = float(hm[0]) * 60.0 + (float(hm[1]) if hm.size() > 1 else 0.0)
			_free_clock = true
		if a.begins_with("--flyover="):
			for v in a.get_slice("=", 1).split(","):
				flyover.append(float(v))
		if a.begins_with("--survey="):
			_survey_setup(int(a.get_slice("=", 1)))
		if a.begins_with("--policeat="):                    # x,y,z,dx,dz: a police checkpoint there (views)
			var v: PackedStringArray = a.get_slice("=", 1).split(",")
			var pc := CityPolice.new()
			add_child(pc)
			pc.place(Vector3(float(v[0]), float(v[1]), float(v[2])), Vector3(float(v[3]), 0, float(v[4])).normalized())
	Graphics.apply_window()
	Graphics.apply(get_viewport(), env, sun)                  # the graphics preset (graphics.gd: F2 steps through them)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _environment() -> void:
	env = Environment.new()
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
	env.fog_sky_affect = 0.3                     # (haze lies over the city, not across the whole sky)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-35), 0)
	sun.light_energy = 2.6
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.shadow_enabled = not "--noshadow" in OS.get_cmdline_user_args()
	sun.directional_shadow_max_distance = 160.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)


## The city after dark (0 day → 1 night): lit rooms in some windows and the shop signs glowing (building.gdshader,
## building_kit.gdshader `night`), the street lamps' heads bright, and a soft bloom so lit things glow.
func _city_lights(n: float) -> void:
	env.glow_enabled = n > 0.05                  # (every frame: a room's own glow settings may have been left)
	env.glow_intensity = lerpf(0.3, 0.9, n)
	env.glow_bloom = 0.05 * n
	env.glow_hdr_threshold = 1.1
	if absf(n - _lights_n) < 0.01:
		return
	_lights_n = n
	if streamer.building_mat is ShaderMaterial:
		(streamer.building_mat as ShaderMaterial).set_shader_parameter("night", n)
	if streamer.kit:
		streamer.kit.set_night(n)
	if streamer.pool_mat:
		streamer.pool_mat.set_shader_parameter("night", n)
	if streamer.lamp_mesh and streamer.lamp_mesh.get_surface_count() > 1:
		var glow := streamer.lamp_mesh.surface_get_material(1) as StandardMaterial3D
		if glow:
			glow.emission_energy_multiplier = lerpf(0.4, 9.0, n)


## Story mode: the sun follows the game clock (the same sky as the mountain drive, drive_game.gd): low and warm at
## dawn and dusk, a faint blue moon at night, the sky and ambient light dimming with it; the headlights come on
## by themselves after dusk (L still switches them).
func _daylight() -> void:
	if fines == null or (story == null and not _free_clock):
		return
	if indoors:                                 # in a room: lit by its own lights, the sun can't reach it
		sun.light_energy = 0.0
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.86, 0.82, 0.75)    # light bounced off distemper walls is warm
		env.ambient_light_energy = 0.03 if dark_room else 0.32
		env.background_energy_multiplier = 0.0
		env.fog_light_color = Color(0.05, 0.05, 0.05)
		env.ssil_enabled = Graphics.value("ssil")   # the walls and floor light each other (cheap bounce light)
		env.ssil_intensity = 1.4
		env.ssao_intensity = 2.4
		env.glow_enabled = true                  # tube lights and screens glow a little
		env.glow_intensity = 0.5
		env.glow_hdr_threshold = 1.2
		return
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ssil_enabled = false
	env.ssao_intensity = 2.0
	var sim = fines.sim
	var sd: Vector3 = sim.sun_dir()
	var day: float = sim.daylight()
	_city_lights(clampf((0.55 - day) / 0.45, 0.0, 1.0))
	env.background_energy_multiplier = lerpf(0.1, 1.0, day)
	env.ambient_light_energy = lerpf(0.16, 0.45, day)          # a city's night: street lights and shops keep it grey, not black
	env.fog_light_color = Color(0.74, 0.76, 0.8) * lerpf(0.05, 1.0, day)
	# the sky with the sun: blue by day; at sunset the horizon goes orange and the haze warm; then deep blue night
	# (cloud greys it: the weather's share, city_weather.gd)
	var dusk := (1.0 - smoothstep(0.04, 0.4, sd.y)) * smoothstep(-0.14, 0.0, sd.y)
	var night := 1.0 - smoothstep(-0.14, 0.04, sd.y)
	var cloud: float = float(fines.sim.wx.get("cloud", 0.0))
	var sm := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
	if sm:
		var top := Color(0.32, 0.5, 0.78).lerp(Color(0.27, 0.34, 0.56), dusk).lerp(Color(0.02, 0.035, 0.08), night)
		var hor := Color(0.72, 0.78, 0.85).lerp(Color(0.98, 0.58, 0.32), dusk).lerp(Color(0.12, 0.095, 0.085), night)   # (night: the city's own glow on the haze)
		var grey := Color(0.5, 0.52, 0.55) * lerpf(1.0, 0.15, night)
		sm.sky_top_color = top.lerp(grey * 0.9, cloud * 0.85)
		sm.sky_horizon_color = hor.lerp(grey, cloud * 0.85)
		sm.ground_horizon_color = sm.sky_horizon_color * 0.8
		env.fog_light_color = env.fog_light_color.lerp(Color(0.95, 0.66, 0.45), dusk * (1.0 - cloud) * 0.7)
	var up := sd.y > -0.04
	var light_dir: Vector3 = sd if up else Vector3(-sd.x, maxf(-sd.y, 0.25), sd.z).normalized()
	if absf(light_dir.dot(Vector3.UP)) < 0.999:
		sun.basis = Basis.looking_at(-light_dir, Vector3.UP)
	if up:
		sun.light_color = Color(1.0, 0.72, 0.5).lerp(Color(1.0, 0.94, 0.85), smoothstep(0.08, 0.45, sd.y))
		sun.light_energy = 2.6 * smoothstep(-0.04, 0.15, sd.y)
	else:
		sun.light_color = Color(0.55, 0.65, 1.0)
		sun.light_energy = 0.07                      # (a city's moon: the street lamps light the street, not it)
	if "--grade" in OS.get_cmdline_user_args():      # the look by the hour (grade.gd; on trial, waiting for approval)
		Grade.apply(env, sun, sd, day, dusk, night, cloud, fmod(sim.minute / 60.0, 24.0))
	sun.shadow_enabled = sun.light_energy > 0.2 and not "--noshadow" in OS.get_cmdline_user_args()
	if car:
		car.night = 1.0 - day
		if day < 0.35 and not car.lights_on and not _auto_lights:
			car.set_lights(true)
			_auto_lights = true
		elif day > 0.5 and _auto_lights:
			if car.lights_on:
				car.set_lights(false)
			_auto_lights = false


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
## --flyover=x,y,z,yaw,pitch, x2,y2,z2,yaw2,pitch2, secs: a camera flight for trailers (tools/trailer). It waits at
## the start until the city round it has loaded, prints "TRAILER_MARK frame=N" as it sets off (the clip is cut
## from there), eases to the end over secs and quits a second after.
var flyover := PackedFloat32Array()
var _nohud := false                         # --nohud: no minimap or speedometer, ever (the story turns them on again)
var _free_clock := false
var _lights_n := -1.0                       # the city lights' last night level (_city_lights)                    # --clock=HH:MM outside the story: the sun at that hour, held there (trailers)
var _fly_t := -1.0


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


## F: step out of the car (driver's door, on the right) or back in when you're next to it.
var _switching := false                    # (getting on or off a two-wheeler: the sequence is playing)


func toggle_on_foot() -> bool:
	if _switching:
		return false
	var bike: bool = car.get("two_wheeler") == true and car.get("_rik") != null
	if walker == null:
		if absf(car.speed) > 1.0:                               # (moving: nothing happens until he stops)
			return false
		if bike:                                                # (off a two-wheeler: he gets off it, then walks)
			_get_off_bike()
			return true
		Walker.avatar = "res://assets/people/story_karthik.glb"     # you on foot are Karthik, the story's own man
		walker = Walker.new()
		walker.name = "OnFoot"
		walker.collision_mask |= 4                             # (the street's furniture: solid to him on foot, city_streamer.gd)
		walker.walk_speed = 1.4                                # (a person's walking pace; the clips play to it)
		walker.run_speed = 4.2
		add_child(walker)
		Walker.avatar = ""
		var door: Vector3 = car.global_position - car.global_basis.x * 1.6
		var top: float = streamer.height_at(door.x, door.z)    # (on top of what's there: a footpath can stand 0.55 m
		if not is_nan(top) and top < door.y + 1.5:             #  above the road, and its collision is one-sided)
			door.y = maxf(door.y, top)
		walker.spawn_at(door + Vector3(0, 0.4, 0), car.global_position + car.forward() * 12.0)
		walker.activate()
		_park_t = 3.0                                          # (the car is held where it stands once it's down on its
		_settle_parked()                                       #  four tyres: never in the air it was still dropping through)
		streamer.target = walker
		map.target = walker
		traffic.player = walker
		if not _taught_foot:                                    # (taught once: GAME_DESIGN.md §8 rule 10)
			_taught_foot = true
			hud.warn("WASD walk · Shift run · F at the car", 4.0)
		return true
	if walker.global_position.distance_to(car.global_position) > 4.5:
		if not _take_parked():
			return false
		bike = false
	if bike:                                                    # (onto a two-wheeler: to its side, then on)
		_get_on_bike()
		return true
	walker.deactivate()
	walker.queue_free()
	walker = null
	ask_shift()
	cam.make_current()
	car.freeze = false
	streamer.target = car
	map.target = car
	traffic.player = car
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true


## (testing) --pedcheck (with --citizentest=HH:MM, on foot at Gandhipuram): every second for 100 s, every person
## walking or standing about (city_walkers.gd, citizens.gd, city_activity.gd) checked: on a vehicle (a parked one's
## or a moving one's body under the feet), inside one (in its box at the knees), above the ground (more than 0.3 m
## over the ground under them, the vehicles not counted) or below it; the counts printed, and pictures of the first
## few found (user://ped_<n>.jpg) from 6 m off.
func _ped_check() -> void:
	await get_tree().create_timer(16.0).timeout
	var space := get_world_3d().direct_space_state
	var counts := {"checked": 0, "on_vehicle": 0, "in_vehicle": 0, "in_furniture": 0, "above": 0, "below": 0,
		"walked_through": 0}
	var last_at := {}                                    # (each person a second ago: walked through anything since?)
	var shots := 0
	var seen_bad := {}
	for t in 100:
		await get_tree().create_timer(1.0).timeout
		var nodes: Array = []
		for holder in [get_node_or_null("Walkers"), get_node_or_null("Activity"), citizens]:
			if holder == null or not "people" in holder:
				continue
			for q in holder.people:
				var n = q.get("node") if q is Dictionary else null
				if n is Node3D and is_instance_valid(n) and (n as Node3D).is_visible_in_tree():
					nodes.append([n, "%s %s" % [holder.name, str(q.get("state", q.get("act", "")))]])
		for e in nodes:
			var n: Node3D = e[0]
			var p := n.global_position
			counts["checked"] += 1
			var was: Vector3 = last_at.get(n.get_instance_id(), Vector3.INF)
			last_at[n.get_instance_id()] = p
			if was != Vector3.INF and was.distance_to(p) < 4.0 and was.distance_to(p) > 0.05:
				var tq := PhysicsRayQueryParameters3D.create(was + Vector3.UP * 0.8, p + Vector3.UP * 0.8)
				var th := space.intersect_ray(tq)          # (a tree, a pole, a stall, a car, a wall between: through it)
				if not th.is_empty() and absf((th["normal"] as Vector3).y) < 0.6:
					counts["walked_through"] += 1
					if counts["walked_through"] <= 6:
						print("PEDCHECK walked through %s: %s (%s) from %s to %s" % [str(th["collider"]), n.name, e[1], str(was.snapped(Vector3.ONE * 0.1)), str(p.snapped(Vector3.ONE * 0.1))])
			var bad := ""
			var hq := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.3, p + Vector3.DOWN * 1.2)
			var hit := space.intersect_ray(hq)
			if not hit.is_empty() and _is_vehicle(hit["collider"]):
				bad = "on_vehicle"
			if bad == "":
				var pq := PhysicsPointQueryParameters3D.new()
				pq.position = p + Vector3.UP * 0.6
				pq.collision_mask = 0xFFFFFFFF
				for r in space.intersect_point(pq, 4):
					if _is_vehicle(r["collider"]):
						bad = "in_vehicle"
						hit = {"collider": r["collider"]}
					elif r["collider"] == streamer.street_body:
						bad = "in_furniture"
						hit = {"collider": r["collider"]}
			if bad == "":
				# (the surface under the feet, from a metre above them: an awning or a stall's roof overhead isn't ground)
				var gq := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 3.0)
				var gx: Array[RID] = []
				var g := NAN
				for k in 4:
					var gh := space.intersect_ray(gq)
					if gh.is_empty():
						break
					if _is_vehicle(gh["collider"]) or gh["collider"] is CharacterBody3D:
						gx.append(gh["rid"])
						gq.exclude = gx
						continue
					g = gh["position"].y
					break
				if not is_nan(g) and p.y - g > 0.3:
					bad = "above"
				elif not is_nan(g) and g - p.y > 0.3:
					bad = "below"
			if bad == "":
				continue
			counts[bad] += 1
			var id := n.get_instance_id()
			if seen_bad.has(id):
				continue
			seen_bad[id] = true
			if bad == "in_vehicle" and citizens and String(e[1]).begins_with("Citizens"):
				for cq in citizens.people:
					if cq["node"] == n:
						print("PEDCHECK   covered %s, path %d/%d, cover_t %s" % [str(citizens._covered(p)), int(cq["pi"]), (cq["path"] as Array).size(), str(cq.get("cover_t", "-"))])
			var g2: float = streamer.height_at(p.x, p.z)
			print("PEDCHECK %s: %s (%s) at %s, gap %+.2f, %s" % [bad, n.name, e[1], str(p), p.y - g2, str(hit.get("collider")) if not hit.is_empty() else "-"])
			if shots < 4:
				shots += 1
				var c := Camera3D.new()
				add_child(c)
				var off := Vector3(5.0, 2.5, 3.0)
				c.global_position = p + off
				c.look_at(p + Vector3.UP * 0.9, Vector3.UP)
				c.make_current()
				for f in 3:
					await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://ped_%d.jpg" % shots), 0.85)
				c.queue_free()
				if walker:
					walker.activate()
	print("PEDCHECK done: %s" % str(counts))
	# (the places the first pictures had people on cars, in them, in the ground: the same views now)
	var views := [Vector3(-258.79, 430.63, 76.13), Vector3(-214.66, 431.23, 151.01), Vector3(-268.02, 431.89, 74.59),
		Vector3(-219.18, 430.34, 39.40)]
	for vi in views.size():
		var c2 := Camera3D.new()
		add_child(c2)
		var look_at_p: Vector3 = views[vi] + Vector3.UP * 0.9
		var from: Vector3 = views[vi] + Vector3(5.0, 2.5, 3.0)
		for k in 12:                                      # (from where nothing's in the way: not inside a wall)
			var a := TAU * float(k) / 12.0
			var cand := look_at_p + Vector3(cos(a) * 5.5, 1.8, sin(a) * 5.5)
			if get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(look_at_p, cand)).is_empty():
				from = cand
				break
		c2.global_position = from
		c2.look_at(look_at_p, Vector3.UP)
		c2.make_current()
		await get_tree().create_timer(0.5).timeout
		for f in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://ped_after_%d.jpg" % (vi + 1)), 0.85)
		c2.queue_free()
	get_tree().quit()


func _is_vehicle(o) -> bool:
	return o is VehicleBody3D or o is RigidBody3D or o is AnimatableBody3D or (streamer and o == streamer.parked_body)


## (testing) --traffictest: a minute of ordinary traffic round the car (stopped by the road): its drivers, the
## nearest any follows another (seconds), any through a red, any two in each other without a crash counted; then
## two crashes staged (a driver who doesn't look into one stopped ahead: at a walking pace, then at 50 km/h), the
## street watched: user://traffic_<n>.jpg.
func _traffic_test() -> void:
	await get_tree().create_timer(14.0).timeout
	car.freeze = true
	var kinds := {}
	var worst_head := 99.0
	var red_runs := 0
	var inside := 0
	var t := 0.0
	var seen_drivers := {}
	var lamp_counts := {"sf": 0, "indicating": 0, "braking": 0, "samples": 0}
	var ind_shot := false
	while t < 60.0:
		if int(t * 60.0) % 30 == 0:                         # (twice a second: who's a pack model, indicating, braking)
			for v in traffic.vehicles:
				if (v.get("lamps", {}) as Dictionary).is_empty() or (v["pos"] as Vector3).distance_to(car.global_position) > 200.0:
					continue
				lamp_counts["sf"] += 1
				if absf(float(v.get("turn", 0.0))) > 0.3:
					lamp_counts["indicating"] += 1
					if not ind_shot and float(v["speed"]) > 1.0:
						ind_shot = true
						var c3 := Camera3D.new()
						add_child(c3)
						var fw3: Vector3 = v["fwd"]
						c3.global_position = (v["pos"] as Vector3) - fw3 * (float(v["half"]) + 5.0) + Vector3.UP * 2.2
						c3.look_at(v["pos"] + Vector3.UP * 0.9, Vector3.UP)
						c3.make_current()
						for f in 3:
							await RenderingServer.frame_post_draw
						get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://traffic_indicator.jpg"), 0.85)
						await get_tree().create_timer(0.4).timeout
						await RenderingServer.frame_post_draw
						get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://traffic_indicator2.jpg"), 0.85)
						c3.queue_free()
						cam.make_current()
				if bool(v.get("braking", false)):
					lamp_counts["braking"] += 1
				lamp_counts["samples"] += 1
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		for v in traffic.vehicles:
			seen_drivers[str(v["driver"])] = int(seen_drivers.get(str(v["driver"]), 0)) + 1
			var fwd: Vector3 = v["fwd"]
			var sp: float = v["speed"]
			for o in traffic.vehicles:
				if o == v:
					continue
				var rel: Vector3 = o["pos"] - v["pos"]
				var along := rel.dot(fwd)
				if along > 0.0 and along < 30.0 and absf(rel.dot(Vector3(fwd.z, 0, -fwd.x))) < 1.5 and sp > 3.0 and (o["fwd"] as Vector3).dot(fwd) > 0.8:
					worst_head = minf(worst_head, (along - float(o["half"]) - float(v["half"])) / sp)
				if o["body"].get_instance_id() > v["body"].get_instance_id() and traffic._overlap(v, o) != Vector3.ZERO:
					inside += 1
					var okey := "%d,%d" % [v["body"].get_instance_id(), o["body"].get_instance_id()]
					if not seen_drivers.has("ov" + okey) and inside < 4000:
						seen_drivers["ov" + okey] = 0
						print("TRAFFICTEST overlap %s %.1f m/s / %s %.1f m/s, headings %.2f, same road %s, i %d/%d t %.2f/%.2f, stunned %.1f/%.1f, pass %.1f/%.1f at %s" % [
							v["kind"], v["speed"], o["kind"], o["speed"], (v["fwd"] as Vector3).dot(o["fwd"]), str(v["road"] == o["road"]),
							int(v["i"]), int(o["i"]), float(v["t"]), float(o["t"]), float(v["stunned"]), float(o["stunned"]),
							float(v.get("pass", 0.0)), float(o.get("pass", 0.0)), str((v["pos"] as Vector3).snapped(Vector3.ONE * 0.1))])
			for sg in traffic.signals:                      # (past a red head facing it, moving)
				var rel2: Vector3 = (sg[0] as Vector3) - (v["pos"] as Vector3)
				var face := Vector3(sin(float(sg[1])), 0, cos(float(sg[1])))
				if face.dot(fwd) < -0.7 and absf(rel2.dot(fwd)) < 0.3 and absf(rel2.dot(Vector3(fwd.z, 0, -fwd.x))) < 10.0 \
						and sp > 3.0 and Streamer.signal_state(float(sg[2])) == 2:
					red_runs += 1
	var share := {}
	var tot := 0
	for k in seen_drivers:
		if not str(k).begins_with("ov"):
			tot += int(seen_drivers[k])
	for k in seen_drivers:
		if not str(k).begins_with("ov"):
			share[k] = snappedf(float(seen_drivers[k]) / maxf(tot, 1), 0.01)
	print("TRAFFICTEST lamps: %s" % str(lamp_counts))
	print("TRAFFICTEST a minute: %d vehicles now, drivers %s, nearest following %.2f s, through a red %d, in each other %d (physics steps), crashes %d" % [
		traffic.vehicles.size(), str(share), worst_head, red_runs, inside, traffic.crashes.size()])
	var shot := 0
	for test in [["low", 2.5], ["high", 14.0]]:
		var pair := _crash_pair()
		if pair.is_empty():
			print("TRAFFICTEST no pair for the %s crash" % test[0])
			continue
		var a: Dictionary = pair[0]
		var b: Dictionary = pair[1]
		b["blind"] = 0.0
		b["speed"] = 0.0
		a["blind"] = float(test[1])
		a["speed"] = float(test[1])
		var before: int = traffic.crashes.size()
		var cam2 := Camera3D.new()
		add_child(cam2)
		cam2.make_current()
		var tt := 0.0
		while tt < 9.0 and traffic.crashes.size() == before:
			await get_tree().physics_frame
			tt += get_physics_process_delta_time()
			var mid: Vector3 = ((a["pos"] as Vector3) + (b["pos"] as Vector3)) * 0.5
			var fw: Vector3 = b["fwd"]
			cam2.global_position = mid + fw.cross(Vector3.UP) * 11.0 + Vector3.UP * 5.0 - fw * 2.0
			cam2.look_at(mid + Vector3.UP * 0.8, Vector3.UP)
		a.erase("blind")
		b.erase("blind")
		for k in 3:                                        # (the moment, and after)
			await get_tree().create_timer(0.05 if k == 0 else 1.2).timeout
			await RenderingServer.frame_post_draw
			shot += 1
			get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://traffic_%d.jpg" % shot), 0.85)
		var cr: Array = traffic.crashes[traffic.crashes.size() - 1] if traffic.crashes.size() > before else []
		print("TRAFFICTEST staged %s at %.0f km/h: %s; stunned %.1f s / %.1f s, driver out %s / %s, dents %d / %d" % [test[0], float(test[1]) * 3.6,
			str(cr), float(a["stunned"]), float(b["stunned"]), str(a.has("out")), str(b.has("out")), (a["dents"] as Dictionary).size(), (b["dents"] as Dictionary).size()])
		await get_tree().create_timer(3.0).timeout          # (no second crash while they stay touching)
		print("TRAFFICTEST after 3 s: crashes %d (one counted for that pair: %s)" % [traffic.crashes.size(), str(traffic.crashes.size() == before + 1)])
		cam2.queue_free()
		cam.make_current()
	get_tree().quit()


## (testing) --camtest[=kind]: in that vehicle on the road, each camera in turn: pulling away (a picture), braking
## (a picture), the head's give printed; from the driver's seat a look left, right and behind (pictures):
## user://cam_<mode>_<moment>.jpg.
func _cam_test(kind: String) -> void:
	await get_tree().create_timer(10.0).timeout
	if car.vehicle != kind and car.SPECS.has(kind):
		var at: Vector3 = car.global_position
		car.configure(kind)
		car.global_position = at + Vector3.UP * 0.4
		await get_tree().create_timer(2.0).timeout
	car.autopilot = true
	for m in CAM_MODES.size():
		cam_mode = m
		car.set_cockpit(m == 1 or m == 2)
		car.in_brake = 0.0
		car.in_throttle = 0.7
		car.in_steer = 0.0
		var peak := Vector3.ZERO
		var t := 0.0
		while t < 2.2:
			await get_tree().process_frame
			t += get_process_delta_time()
			if _head.length() > peak.length():
				peak = _head
		await _cam_snap("cam_%d_accel" % m)
		car.in_throttle = 0.0
		car.in_brake = 1.0
		var peak_b := Vector3.ZERO
		t = 0.0
		while t < 0.7:
			await get_tree().process_frame
			t += get_process_delta_time()
			if _head.z > peak_b.z:
				peak_b = _head
		await _cam_snap("cam_%d_brake" % m)
		print("CAMTEST %s: %.1f km/h; head pulling away %s, braking %s; fov %.0f" % [CAM_MODES[m], absf(car.speed) * 3.6,
			str(peak.snapped(Vector3.ONE * 0.001)), str(peak_b.snapped(Vector3.ONE * 0.001)), cam.fov])
		t = 0.0
		while t < 1.5:
			await get_tree().process_frame
			t += get_process_delta_time()
		if m == 1:
			for lk in [["left", 1.35], ["right", -1.35], ["behind", PI]]:
				_look_force = lk[1]
				await get_tree().create_timer(0.8).timeout
				await _cam_snap("cam_1_look_%s" % lk[0])
			_look_force = 0.0
			await get_tree().create_timer(0.8).timeout
	car.in_brake = 0.0
	car.autopilot = false
	get_tree().quit()


func _cam_snap(nm: String) -> void:
	for f in 2:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://%s.jpg" % nm), 0.85)


## (testing) --lamptest: the camera behind one of the pack's vehicles in the traffic for 40 s: how long it indicated
## (and which way, and whether it then turned that way), braked; a picture the first time each (user://lamp_*.jpg).
func _lamp_test() -> void:
	await get_tree().create_timer(14.0).timeout
	car.freeze = true
	var c := Camera3D.new()
	add_child(c)
	c.make_current()
	traffic.player = c                                   # (the traffic round the camera: its lamps lit there)
	var v: Dictionary = {}
	var head0 := Vector3.ZERO
	var t := 0.0
	var stats := {"indicating_s": 0.0, "braking_s": 0.0, "turns": 0, "turns_signalled": 0}
	var shots := {}
	var last_road = null
	var was_turn := 0.0
	while t < 40.0:
		var want := "turn" if t < 20.0 else "slow"         # (first one about to turn, then one slowing down)
		var fits := not v.is_empty() and (absf(float(v.get("turn", 0.0))) > 0.3 or float(v.get("turn_after", 0.0)) > 0.0 if want == "turn" \
			else bool(v.get("braking", false)) or float(v.get("brake_hold", 0.0)) > 0.0)
		if v.is_empty() or not traffic.vehicles.has(v) or str(v.get("_lt", "")) != want or (not fits and int(t) != int(t - get_process_delta_time())):
			var bd := 1e9
			var found: Dictionary = {}
			for o in traffic.vehicles:
				if (o.get("lamps", {}) as Dictionary).is_empty():
					continue
				var ok: bool = absf(float(o.get("turn", 0.0))) > 0.3 if want == "turn" else bool(o.get("braking", false))
				var dd := (o["pos"] as Vector3).distance_to(car.global_position) + (0.0 if ok else 1e6)
				if dd < bd:
					bd = dd
					found = o
			if not found.is_empty() and (v.is_empty() or found != v):
				v = found
				v["_lt"] = want
				head0 = Vector3.ZERO
				last_road = v["road"]
			elif not found.is_empty():
				v["_lt"] = want
			if v.is_empty():
				break
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		var fw: Vector3 = v["fwd"]
		c.global_position = (v["pos"] as Vector3) - fw * (float(v["half"]) + 4.5) + Vector3.UP * 2.0
		c.look_at((v["pos"] as Vector3) + Vector3.UP * 0.8, Vector3.UP)
		var turn := float(v.get("turn", 0.0))
		if int(t / 5.0) != int((t - dt) / 5.0):
			print("LAMPTEST t %.0f: speed %.1f target %.1f braking %s turn %s stunned %.1f lamps %s dist %.0f" % [t, float(v["speed"]), float(v.get("target", -1)),
				str(v.get("braking", "-")), str(v.get("turn", "-")), float(v["stunned"]), str((v["lamps"] as Dictionary).keys()), (v["pos"] as Vector3).distance_to(c.global_position)])
		if absf(turn) > 0.3:
			stats["indicating_s"] += dt
			was_turn = turn
		if bool(v.get("braking", false)):
			stats["braking_s"] += dt
		if v["road"] != last_road:                       # (onto another road: did it turn (>30°), had it said so?)
			last_road = v["road"]
			if head0 != Vector3.ZERO and head0.dot(fw) < 0.87:
				stats["turns"] += 1
				if absf(was_turn) > 0.3:
					stats["turns_signalled"] += 1
			was_turn = 0.0
		if absf(turn) < 0.3:
			head0 = fw
		for what in ["indicating", "braking"]:
			var now: bool = absf(turn) > 0.3 if what == "indicating" else bool(v.get("braking", false))
			if now and not shots.has(what) and float(v.get("blink", 0.0)) < 0.3:
				shots[what] = true
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://lamp_%s.jpg" % what), 0.85)
	print("LAMPTEST %s: %s, pictures %s" % [str(v.get("kind", "-")), str(stats), str(shots.keys())])
	traffic.player = car
	get_tree().quit()


## Two vehicles in one lane, one behind the other (20–45 m), on a straight bit, near the car: for a staged crash.
func _crash_pair() -> Array:
	for a in traffic.vehicles:
		if a["stunned"] > 0.0 or (a["pos"] as Vector3).distance_to(car.global_position) > 300.0:
			continue
		var fwd: Vector3 = a["fwd"]
		for b in traffic.vehicles:
			if b == a or b["stunned"] > 0.0:
				continue
			var rel: Vector3 = (b["pos"] as Vector3) - (a["pos"] as Vector3)
			var along := rel.dot(fwd)
			if along > 12.0 and along < 45.0 and absf(rel.dot(Vector3(fwd.z, 0, -fwd.x))) < 1.6 and (b["fwd"] as Vector3).dot(fwd) > 0.9 \
					and a["road"] == b["road"]:
				return [a, b]
	return []


## (testing) --taketest: out of the car, beside the nearest parked vehicle you can take, F: into it; a picture beside
## it, one from his seat, one driving away (user://take_*.jpg); then back on foot, to his own car left behind, F.
func _take_test() -> void:
	await get_tree().create_timer(10.0).timeout
	toggle_on_foot()
	await get_tree().create_timer(2.0).timeout
	var at: Vector3 = walker.global_position
	var best := {}
	var bd := 1e9
	for t in streamer.takeable:
		var o: Vector3 = (t["xf"] as Transform3D).origin
		if o.distance_to(at) < bd:
			bd = o.distance_to(at)
			best = t
	print("TAKETEST %d takeable, nearest %s at %.1f m" % [streamer.takeable.size(), best.get("key", "-"), bd])
	if best.is_empty():
		get_tree().quit()
		return
	var px: Transform3D = best["xf"]
	var side := px.basis.z.normalized() * 1.6
	var stand := px.origin + side
	var top: float = streamer.height_at(stand.x, stand.z)
	walker.global_position = Vector3(stand.x, (px.origin.y if is_nan(top) else maxf(top, px.origin.y)) + 0.3, stand.z)
	await get_tree().create_timer(1.5).timeout
	var c := Camera3D.new()
	add_child(c)
	c.global_position = px.origin + side * 3.5 + px.basis.x.normalized() * 4.0 + Vector3.UP * 3.0
	c.look_at(px.origin + Vector3.UP, Vector3.UP)
	c.make_current()
	for f in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://take_1_beside.jpg"), 0.85)
	var ok := toggle_on_foot()
	print("TAKETEST F: %s, now %s, walker %s" % [str(ok), car.vehicle, str(walker != null)])
	await get_tree().create_timer(1.5).timeout
	c.global_position = car.global_position + car.global_basis.x * 4.0 + car.global_basis.z * 3.0 + Vector3.UP * 3.0
	c.look_at(car.global_position + Vector3.UP, Vector3.UP)
	for f in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://take_2_in.jpg"), 0.85)
	c.queue_free()
	cam.make_current()
	cam_mode = 1
	car.set_cockpit(true)
	await get_tree().create_timer(1.0).timeout
	for f in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://take_3_seat.jpg"), 0.85)
	cam_mode = 0
	car.set_cockpit(false)
	car.autopilot = true
	car.in_throttle = 0.5
	car.in_steer = 0.0
	await get_tree().create_timer(3.0).timeout
	car.in_throttle = 0.0
	car.in_brake = 1.0
	await get_tree().create_timer(2.0).timeout
	car.in_brake = 0.0
	car.autopilot = false
	print("TAKETEST drove to %.1f km/h, moved %.1f m" % [absf(car.speed) * 3.6, car.global_position.distance_to(px.origin)])
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://take_4_away.jpg"), 0.85)
	# back to his own, left behind
	for i in 40:
		if absf(car.speed) < 0.5:
			break
		await get_tree().create_timer(0.25).timeout
	toggle_on_foot()
	await get_tree().create_timer(1.5).timeout
	var lb: Node3D = _left_behind[0][0] if not _left_behind.is_empty() else null
	if lb:
		walker.global_position = lb.global_position - lb.global_basis.x * 1.8 + Vector3.UP * 0.5
		await get_tree().create_timer(1.0).timeout
		toggle_on_foot()
		print("TAKETEST back in own: now %s, left behind %d" % [car.vehicle, _left_behind.size()])
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://take_5_own.jpg"), 0.85)
	get_tree().quit()


## The view shaken a moment (a crash near him: city_traffic.gd).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


var _left_behind: Array = []        # your own vehicles left parked when you took another: [Node3D, its kind]


## On foot, F beside a parked car, auto or lorry (the street's own: city_streamer.gd take_parked): you
## get into it. The vehicle you had stays parked where you left it (solid, as it was), and is yours again if you
## come back to it: F beside it.
func _take_parked() -> bool:
	if walker == null or streamer == null:
		return false
	var at: Vector3 = walker.global_position
	for i in range(_left_behind.size() - 1, -1, -1):          # (one of your own, left here before)
		var lb: Node3D = _left_behind[i][0]
		if is_instance_valid(lb) and Vector2(lb.global_position.x - at.x, lb.global_position.z - at.z).length() < 3.5:
			_swap_into(String(_left_behind[i][1]), lb.global_transform)
			lb.queue_free()
			_left_behind.remove_at(i)
			return true
	if not streamer.has_method("take_parked"):
		return false
	var t: Dictionary = streamer.take_parked(at, 3.2)
	if t.is_empty() or not car.SPECS.has(t["key"]):
		return false
	var px: Transform3D = t["xf"]
	var nose := Vector3(px.basis.x.x, 0.0, px.basis.x.z).normalized()   # (the model's nose: +X, the car's: +Z)
	var bz := Basis(Vector3.UP.cross(nose), Vector3.UP, nose)
	_swap_into(String(t["key"]), Transform3D(bz, px.origin))
	return true


## Your car made `key` and put at `xf` (its floor there); what it was left standing where it stood.
func _swap_into(key: String, xf: Transform3D) -> void:
	var was := car.vehicle
	var stays := car.duplicate(0) as Node3D                    # (no script: what it looks like, solid, standing)
	for n in stays.find_children("*", "", true, false):
		if n is Camera3D or n is AudioStreamPlayer3D or n is AudioStreamPlayer or n is SubViewport or n is Light3D \
				or n is Control or n is CanvasLayer or n.name == "Cabin":
			n.queue_free()
	if stays is RigidBody3D:
		(stays as RigidBody3D).freeze = true
	add_child(stays)
	stays.global_transform = car.global_transform
	_left_behind.append([stays, was])
	if _left_behind.size() > 3:                                # (the oldest goes: a city doesn't keep them all)
		var old: Node3D = _left_behind.pop_front()[0]
		if is_instance_valid(old):
			old.queue_free()
	car.configure(key)
	car.global_transform = Transform3D(xf.basis, xf.origin + Vector3.UP * 0.35)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	print("TAKE %s → %s at %s" % [was, key, str(xf.origin)])


var _mt_started := false
var _sfv_started := false


## (testing) --sfvehicletest=sf_hatchback_01,sf_bus_01,...: each made the car in turn where it stands, a picture from
## outside and one from the driver's seat (user://sfv_<key>_out.jpg, _in.jpg), its cabin's fit printed.
func _sfv_test(keys: PackedStringArray) -> void:
	await get_tree().create_timer(6.0).timeout
	for key in keys:
		if not car.SPECS.has(key):
			print("SFV no such vehicle " + key)
			continue
		var at: Vector3 = car.global_position
		car.configure(key)
		car.global_position = at + Vector3.UP * 0.5
		car.linear_velocity = Vector3.ZERO
		await get_tree().create_timer(2.0).timeout
		cam_mode = 0
		car.set_cockpit(false)
		var c := Camera3D.new()
		c.fov = 50.0
		add_child(c)
		var L := float(car.SPECS[key].get("len", 4.5))
		var mdl := car.get_node_or_null("Model") as Node3D       # (its real length, where the spec doesn't say)
		if mdl:
			var lo := INF
			var hi := -INF
			for mi in mdl.find_children("*", "MeshInstance3D", true, false):
				var ab: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
				for corner in 8:
					var z: float = car.to_local(ab.get_endpoint(corner)).z
					lo = minf(lo, z)
					hi = maxf(hi, z)
			if hi > lo:
				L = maxf(L, hi - lo)
		c.global_position = car.global_position + car.global_basis.x * (L * 0.45 + 1.2) + car.global_basis.z * (L * 0.5) + Vector3.UP * (1.6 + L * 0.35)
		c.look_at(car.global_position + Vector3.UP * 0.8, Vector3.UP)
		c.make_current()
		for f in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://sfv_%s_out.jpg" % key), 0.85)
		c.global_position = car.global_position - car.global_basis.x * (L * 0.45 + 1.2) - car.global_basis.z * (L * 0.5) + Vector3.UP * (1.6 + L * 0.35)
		c.look_at(car.global_position + Vector3.UP * 0.8, Vector3.UP)
		for f in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://sfv_%s_out2.jpg" % key), 0.85)
		if car.SPECS[key].get("own_cabin", false):        # (the driver, close, through his window)
			var st: Vector3 = car.to_global(car.seat)
			c.global_position = st - car.global_basis.x * 1.25 + car.global_basis.z * 0.25 + Vector3.UP * 0.05
			c.look_at(st + Vector3.DOWN * 0.25 + car.global_basis.z * 0.25, Vector3.UP)
			for f in 3:
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://sfv_%s_driver.jpg" % key), 0.85)
		for end in [["front", 1.0], ["back", -1.0]]:      # (close, nose and tail: its badges, plates)
			c.global_position = car.global_position + car.global_basis.z * float(end[1]) * (L * 0.5 + 2.6) + Vector3.UP * 1.1
			c.look_at(car.global_position + car.global_basis.z * float(end[1]) * L * 0.5 + Vector3.UP * 0.7, Vector3.UP)
			for f in 3:
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://sfv_%s_%s.jpg" % [key, end[0]]), 0.85)
		c.queue_free()
		cam.make_current()
		cam_mode = 1
		car.set_cockpit(true)
		await get_tree().create_timer(1.0).timeout
		for f in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://sfv_%s_in.jpg" % key), 0.85)
		print("SFV %s: seat %s, cabin %s, wheels %d, mass %.0f" % [key, str(car.seat), str(car.find_child("Cabin", false, false) != null), car._wheels.size(), car.mass])
		for wv in car._wheels:
			var vw := wv as VehicleWheel3D
			var parts := vw.get_child(0) as Node3D if vw.get_child_count() > 0 else null
			print("SFV   wheel %s at %s r %.2f parts %s scale %s" % [vw.name, str(car.to_local(vw.global_position)), vw.wheel_radius, str(car.to_local(parts.global_position)) if parts else "none", str(parts.global_basis.get_scale()) if parts else ""])
		cam_mode = 0
		car.set_cockpit(false)
	get_tree().quit()


## (testing) --mounttest: off the scooter, a few steps away, back on; pictures from beside it partway through each
## (user://mount_<n>.jpg).
func _mount_test() -> void:
	await get_tree().create_timer(4.0).timeout
	var shot := func(n: String) -> void:
		var c := Camera3D.new()
		c.fov = 45.0
		add_child(c)
		var side: Vector3 = car.global_basis.x.normalized()
		c.global_position = car.global_position + side * 2.6 + car.global_basis.z * 0.3 + Vector3.UP * 1.2
		c.look_at(car.global_position + Vector3.UP * 0.8, Vector3.UP)
		var was := get_viewport().get_camera_3d()
		c.make_current()
		for f in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://mount_%s.jpg" % n), 0.85)
		if was:
			was.make_current()
		c.queue_free()
	toggle_on_foot()
	for i in 4:
		await get_tree().create_timer(0.3).timeout
		await shot.call("off_%d" % i)
	await get_tree().create_timer(1.0).timeout
	print("MOUNT off: walker %s at %s, the scooter's rider shown %s" % [str(walker != null), str(walker.global_position) if walker else "-", str(car._rider.visible)])
	await shot.call("off_done")
	walker.global_position += car.global_basis.x.normalized() * 1.5   # (a step or two away, to walk back to it)
	await get_tree().create_timer(1.0).timeout
	toggle_on_foot()
	for i in 6:
		await get_tree().create_timer(0.4).timeout
		await shot.call("on_%d" % i)
	await get_tree().create_timer(1.5).timeout
	print("MOUNT on: walker %s, the rider shown %s, mounting %s" % [str(walker != null), str(car._rider.visible), str(car.mounting)])
	await shot.call("on_done")
	get_tree().quit()


## Off the scooter: the getting-off (jeep.gd dismount), then he's on his feet where he stood up.
func _get_off_bike() -> void:
	_switching = true
	car.freeze = false
	await car.dismount()
	var at: Vector3 = car.beside_point()
	Walker.avatar = "res://assets/people/story_karthik.glb"
	walker = Walker.new()
	walker.name = "OnFoot"
	walker.walk_speed = 1.4
	walker.run_speed = 4.2
	add_child(walker)
	Walker.avatar = ""
	walker.spawn_at(at + Vector3(0, 0.1, 0), at + car.forward() * 12.0)
	walker.activate()
	_park_t = 3.0
	_settle_parked()
	streamer.target = walker
	map.target = walker
	traffic.player = walker
	if not _taught_foot:
		_taught_foot = true
		hud.warn("WASD walk · Shift run · F at the scooter", 4.0)
	_switching = false


## Onto the scooter: he walks to its left side by the seat (a few steps at most), then gets on (jeep.gd mount); the
## controls are his once he's sitting.
func _get_on_bike() -> void:
	_switching = true
	var to: Vector3 = car.beside_point()
	var t := 0.0
	walker.active = false
	while t < 2.5 and Vector2(walker.global_position.x - to.x, walker.global_position.z - to.z).length() > 0.25:
		var d: Vector3 = to - walker.global_position
		walker.rotation.y = atan2(-d.x, -d.z)               # (the keys' forward: toward his place by the seat)
		walker.active = true
		walker.auto_input = Vector2(0, -1)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	walker.auto_input = Vector2.INF
	walker.deactivate()
	walker.queue_free()
	walker = null
	cam.make_current()
	car.freeze = false
	streamer.target = car
	map.target = car
	traffic.player = car
	await car.mount()
	ask_shift()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_switching = false


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
			_sms("E-challan %s: red light jumped, signal camera, %s." % [Fines.rupees(Fines.RED_LIGHT), _now12()])
		else:                                               # (no camera: the horns around him say it)
			var hp := AudioStreamPlayer.new()
			hp.stream = RoomSound.sound("horn")
			hp.volume_db = -6.0
			add_child(hp)
			hp.play()
			hp.finished.connect(hp.queue_free)
	elif fines and kmh > Fines.CITY_LIMIT_KMH + 5.0 and Fines.has_speed_camera(sp):
		fines.challan("Overspeeding %d km/h" % roundi(kmh), Fines.OVERSPEED)
		_sms("E-challan %s: %d km/h in a 50 zone, speed camera, %s." % [Fines.rupees(Fines.OVERSPEED), roundi(kmh), _now12()])


## Stuck: the car up on a kerb, a step, a ledge, wedged or on its side, going nowhere (under 1 km/h for 4 s with
## the throttle or reverse on, or tipped over 25°). The HUD says so once; holding G for a second and a half has the
## people about push it back: it's set down on the nearest street, upright, along it, still.
var _stuck_t := 0.0
var _g_held := 0.0
var _stuck_said := false


func _unstick(dt: float) -> void:
	if "--unsticktest" in OS.get_cmdline_user_args():   # (testing: tipped onto a kerb off the road, then G)
		_unstick_test(dt)
	if ("--falltest" in OS.get_cmdline_user_args() or "--gaittest" in OS.get_cmdline_user_args() or "--sittest" in OS.get_cmdline_user_args() or "--gangtest" in OS.get_cmdline_user_args() or " ".join(OS.get_cmdline_user_args()).contains("--standtest")) and walker == null and not has_meta("falltest") and Time.get_ticks_msec() > 9000 \
			and not car.freeze and car.global_position.y < 590.0 and absf(car.speed) < 0.5 and Time.get_ticks_msec() > 12000:
		set_meta("falltest", true)                      # (testing: out of the car; player.gd does the rest)
		print("FALLTEST car at %s, ground %.1f" % [str(car.global_position), streamer.height_at(car.global_position.x, car.global_position.z)])
		print("CARPROBE sleeping %s, freeze %s, lin %s, chassis contacts %d" % [car.sleeping, car.freeze, str(car.linear_velocity), car.get_contact_count()])
		for wh in car.find_children("*", "VehicleWheel3D", true, false):   # (each tyre: touching, and the gap under it)
			var w3 := wh as VehicleWheel3D
			var q := PhysicsRayQueryParameters3D.create(w3.global_position + Vector3.UP * 6.0, w3.global_position + Vector3.DOWN * 6.0)
			q.exclude = [car.get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			var gap: float = (w3.global_position.y - w3.wheel_radius - float(hit["position"].y)) if not hit.is_empty() else -99.0
			print("CARPROBE %s at y %.2f, susp %.2f/%.2f" % [w3.name, w3.global_position.y, w3.wheel_rest_length, w3.suspension_travel])
			print("CARPROBE %s contact %s, tyre bottom %.2f m over what's under it (%s)" % [w3.name, w3.is_in_contact(), gap,
				str(hit["collider"].name) if not hit.is_empty() else "nothing"])
		toggle_on_foot()
		print("FALLTEST out at %s" % str(walker.global_position) if walker else "FALLTEST not out")
	if walker != null or car == null or (story and story.room != null):
		_stuck_t = 0.0
		_g_held = 0.0
		return
	var tilt: float = rad_to_deg(acos(clampf(car.global_basis.y.dot(Vector3.UP), -1.0, 1.0)))
	var pushing := InputMap.has_action("accelerate") and (Input.is_action_pressed("accelerate") or Input.is_action_pressed("brake"))
	if absf(car.speed) < 0.3 and (pushing or tilt > 25.0):
		_stuck_t += dt
	elif absf(car.speed) > 1.5:
		_stuck_t = 0.0
		_stuck_said = false
	if _stuck_t > 4.0 and not _stuck_said:
		_stuck_said = true
		hud.warn("Stuck? Hold G: the people around help push it back onto the road.", 6.0)
	if Input.is_key_pressed(KEY_G):
		_g_held += dt
		if _g_held >= 1.5:
			_g_held = -99.0                                 # (once a press)
			_back_on_road()
	else:
		_g_held = 0.0


var _ut := 0.0


func _unstick_test(dt: float) -> void:
	_ut += dt
	if _ut > 14.0 and not has_meta("tipped") and car.global_position.y < 550.0:
		set_meta("tipped", true)
		var side := car.global_basis.x
		car.global_transform = Transform3D(car.global_basis.rotated(car.global_basis.z, deg_to_rad(40.0)),
			car.global_position + side * 7.0 + Vector3.UP * 1.2)
		print("UNSTICKTEST tipped 40° at %s" % car.global_position)
	if _ut > 22.0 and not has_meta("pushed"):
		set_meta("pushed", true)
		var tilt: float = rad_to_deg(acos(clampf(car.global_basis.y.dot(Vector3.UP), -1.0, 1.0)))
		print("UNSTICKTEST before: at %s tilt %.0f°, stuck for %.1f s, hint %s" % [car.global_position, tilt, _stuck_t, _stuck_said])
		_back_on_road()
	if _ut > 28.0 and not has_meta("after"):
		set_meta("after", true)
		var tilt2: float = rad_to_deg(acos(clampf(car.global_basis.y.dot(Vector3.UP), -1.0, 1.0)))
		print("UNSTICKTEST after: at %s tilt %.0f°, speed %.1f" % [car.global_position, tilt2, car.speed])


func _back_on_road() -> void:
	var at: Vector3 = car.global_position
	var best := INF
	var bp := at
	var bd := Vector3.FORWARD
	for k in streamer.loaded:
		var node: Node3D = streamer.loaded[k]
		if node == null or not is_instance_valid(node):
			continue
		for r in node.get_meta("roads", []):
			if not str(r["c"]) in ["trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street"] \
					or r.get("fly", false):
				continue
			var p: PackedFloat32Array = r["p"]
			for i in p.size() / 3 - 1:
				var a := Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
				var b := Vector3(p[i * 3 + 3], p[i * 3 + 4], p[i * 3 + 5])
				var q := Geometry3D.get_closest_point_to_segment(at, a, b)
				var dd := Vector2(q.x - at.x, q.z - at.z).length_squared()
				if dd < best:
					best = dd
					bp = q
					bd = (b - a).normalized()
	if best > 80.0 * 80.0:
		bp = at
		bd = -car.global_basis.z
	var fwd := -car.global_basis.z                      # (facing along the street the way it pointed)
	if Vector2(fwd.x, fwd.z).dot(Vector2(bd.x, bd.z)) < 0.0:
		bd = -bd
	var y: float = streamer.height_at(bp.x, bp.z)
	if is_nan(y):
		y = bp.y
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.global_transform = Transform3D(Basis.looking_at(Vector3(bd.x, 0.0, bd.z).normalized(), Vector3.UP), Vector3(bp.x, y + 0.6, bp.z))
	_stuck_t = 0.0
	_stuck_said = false
	hud.say("", "A few men from the shops lean on it with him. It rolls back onto the road.", 4.0)
	print("UNSTUCK to %.1f,%.1f (%.1f m)" % [bp.x, bp.z, sqrt(best)])


## An e-challan arrives as it does in Coimbatore: an SMS from the police, on his phone.
## A crash. Another vehicle: it is shoved (city_traffic.gd), its driver has words, and a hard hit is a rash-driving
## complaint (an e-challan) and, while he is on bail, one more thing the inspector hears of. A police checking
## point's barricades: fined on the spot. A parked vehicle: its owner wants the dent paid for, there and then
## (a light knock, only words). Walls and kerbs only cost the car.
func _on_impact(_zone: String, severity: float, other: Object) -> void:
	if life and severity >= 0.15:                       # (he feels it: on two wheels, far more)
		life.add_hurt(severity * (45.0 if car.two_wheeler else 16.0))
	if hospital:                                        # (a bad one: the 108, the hospital)
		hospital.crash(severity, car.two_wheeler)
	var now := Time.get_ticks_msec() / 1000.0
	var key := other.get_instance_id() if other else 0
	var again := now - float(_hit_seen.get(key, -99.0)) < 6.0
	_hit_seen[key] = now
	if traffic and traffic.is_vehicle(other):
		var keep: float = traffic.struck(other, car.hit_velocity, car.hit_normal, car.mass)
		if keep >= 0.0:
			car.share_momentum(-Vector3(car.hit_normal.x, 0, car.hit_normal.z).normalized(), keep)
			if car.hit_point != Vector3.ZERO and other is Node3D:          # (its panels give as yours do)
				var hp: Vector3 = car.hit_point
				hp.y = maxf(hp.y, (other as Node3D).global_position.y + 0.6)
				Dents.dent(other, hp, -car.hit_normal, 0.45 + severity * 0.75, 0.04 + severity * 0.26, traffic.dents_of(other))
		if again:
			return
		var lines := [["Oi! Eyes open, saar!", "ஏய்! கண்ணைத் திறந்து ஓட்டு, சார்!"],
			["What is this driving? Look at my vehicle!", "என்ன ஓட்டுறீங்க? என் வண்டியைப் பாருங்க!"],
			["Are you mad? Stop, stop!", "பைத்தியமா? நில்லுங்க, நில்லுங்க!"]]
		var l: Array = lines[randi() % lines.size()]
		hud.say(_t({"en": "Other driver", "ta": "மற்ற ஓட்டுநர்"}), _t({"en": l[0], "ta": l[1]}), 3.5)
		if severity >= 0.25 and fines:
			fines.challan("Rash driving (collision)", Fines.RASH)
			phone.message({"en": "Coimbatore City Police", "ta": "கோவை மாநகர காவல்"},
				{"en": "E-challan %s: rash driving, a collision reported, %s." % [Fines.rupees(Fines.RASH), _now12()],
				"ta": "இ-சலான் %s: அலட்சியமாக ஓட்டியது, மோதல் புகார், %s." % [Fines.rupees(Fines.RASH), _now12()]})
			if bail and bail.active:
				bail.suspicion = clampf(bail.suspicion + 4.0, 0.0, 100.0)
			print("IMPACT rash-driving challan (severity %.2f), suspicion %.0f" % [severity, bail.suspicion if bail else 0.0])
	elif streamer and other == streamer.parked_body:      # a parked vehicle: its owner comes out
		if again or severity < 0.12:
			return
		var who := _t({"en": "The owner", "ta": "வண்டி உரிமையாளர்"})
		if severity < 0.3 or fines == null:
			hud.say(who, _t({"en": "Hey! My vehicle! ...Look where you're going.", "ta": "ஏய்! என் வண்டி! ...பார்த்து ஓட்டுங்க."}), 4.0)
			return
		var asked := int(round((1500.0 + 4000.0 * severity) / 500.0)) * 500       # (the dent, settled there and then)
		var paid: int = fines.pay(asked)
		hud.say(who, _t({"en": "Look at this dent! %s for the repair, now. Or we go to the station." % Fines.rupees(asked),
			"ta": "இந்த நசுங்கலைப் பாருங்க! ரிப்பேருக்கு %s, இப்பவே. இல்லைனா ஸ்டேஷனுக்குப் போவோம்." % Fines.rupees(asked)}), 5.0)
		print("IMPACT parked vehicle (severity %.2f): paid %d of %d" % [severity, paid, asked])
	elif police and other is Node and police.is_ancestor_of(other) and not again and fines:
		var paid: int = fines.pay(Fines.BARRICADE)
		hud.say(_t({"en": "Traffic police", "ta": "போக்குவரத்து காவல்"}),
			_t({"en": "Our barricade! Get out. Pay for it, now.", "ta": "எங்க தடுப்பு! இறங்குங்க. இப்பவே கட்டுங்க."}), 5.0)
		phone.message({"en": "Coimbatore City Police", "ta": "கோவை மாநகர காவல்"},
			{"en": "Fined %s on the spot: damaged a police barricade." % Fines.rupees(paid),
			"ta": "அந்த இடத்திலேயே %s அபராதம்: காவல் தடுப்பைச் சேதப்படுத்தியது." % Fines.rupees(paid)})
		if bail and bail.active:
			bail.suspicion = clampf(bail.suspicion + 6.0, 0.0, 100.0)
		print("IMPACT police barricade: paid %d" % paid)


var _ct := {"t": 0.0, "kinds": ["hatchback", "auto", "bus"], "v": {}, "log": [], "hits": []}


## --crashtest: behind a traffic vehicle of each kind in turn (one with clear road ahead of it), 22 m back at its
## speed, then full throttle into it; reports the speed of the hit, the shove, the spin, the damage and the
## challans, then checks a police barricade's fine. Shots of each crash with --shots=DIR.
func _crashtest(dt: float) -> void:
	_ct["t"] = float(_ct["t"]) + dt
	car.autopilot = true
	if t < 10.0:
		return
	if not _ct.has("wired"):
		_ct["wired"] = true
		_ct["challans0"] = fines.challans.size()
		car.impacted.connect(func(zone: String, sev: float, o: Object) -> void:
			if traffic.is_vehicle(o):
				_ct["hits"].append({"zone": zone, "sev": snappedf(sev, 0.01), "kmh": snappedf(car.hit_velocity.length() * 3.6, 0.1), "body": o}))
	var kinds: Array = _ct["kinds"]
	if kinds.is_empty():
		var before: int = fines.sim.money
		police._body = StaticBody3D.new()
		police.add_child(police._body)
		_on_impact("front", 0.3, police._body)
		_ct["log"].append({"barricade_paid": before - fines.sim.money})
		print("CRASHTEST " + JSON.stringify({"runs": _ct["log"], "new_challans": fines.challans.size() - int(_ct["challans0"]),
			"suspicion": bail.suspicion, "bail_active": bail.active}))
		get_tree().quit()
		return
	var v: Dictionary = _ct["v"]
	if v.is_empty():
		for o in traffic.vehicles:
			if o["kind"] != kinds[0] or float(o["stunned"]) > 0.0 or float(o["speed"]) < 2.0:
				continue
			var clear := true
			for o2 in traffic.vehicles:
				var rel: Vector3 = o2["pos"] - o["pos"]
				if o2 != o and rel.length() < 45.0:
					clear = false
			if clear:
				v = o
				break
		if v.is_empty():
			if float(_ct["t"]) > 40.0:                      # (none of that kind about: the next)
				_ct["log"].append({"kind": kinds[0], "skipped": true})
				kinds.pop_front()
				_ct["t"] = 0.0
			return
		_ct["v"] = v
		_ct["t"] = 0.0
		_ct["hits"] = []
		v["speed0"] = v["speed"]
		car.repair()
		var f: Vector3 = v["fwd"]
		var at: Vector3 = v["pos"] - f * (float(v["half"]) + 22.0)
		car.global_transform = Transform3D(Basis.looking_at(-f, Vector3.UP), at + Vector3.UP * 0.6)
		car.linear_velocity = f * float(v["speed"])
		car.angular_velocity = Vector3.ZERO
		car._v_prev = car.linear_velocity
		return
	var hits: Array = _ct["hits"]
	var to: Vector3 = v["pos"] - car.global_position
	var f2: Vector3 = car.forward()
	var ang := atan2(f2.x * to.z - f2.z * to.x, f2.x * to.x + f2.z * to.z)
	car.in_steer = clampf(-ang * 2.0, -1.0, 1.0)
	car.in_throttle = 1.0 if hits.is_empty() else 0.0
	car.in_brake = 0.0 if hits.is_empty() or car.speed < 0.5 else 1.0
	car.in_handbrake = not hits.is_empty() and car.speed < 0.5
	if not hits.is_empty() and not _ct.has("hit_t"):
		_ct["hit_t"] = _ct["t"]
	var since: float = float(_ct["t"]) - float(_ct.get("hit_t", INF))
	if since > 0.25 and not _ct.has("after"):
		_ct["after"] = snappedf(car.speed * 3.6, 0.1)
	if since > 0.8 and not _ct.has("shot"):
		_ct["shot"] = true
		if shots_dir != "":
			get_viewport().get_texture().get_image().save_jpg(shots_dir + "/crash_%s.jpg" % kinds[0], 0.85)
	if float(_ct["t"]) > 14.0 or since > 4.0:
		var struck: Dictionary = {}
		for o in traffic.vehicles:
			if not hits.is_empty() and o["body"] == hits[0]["body"]:
				struck = o
		var first: Dictionary = hits[0].duplicate() if not hits.is_empty() else {}
		first.erase("body")
		_ct["log"].append({"kind": kinds[0], "first_hit": first, "contacts": hits.size(), "struck": struck.get("kind", ""),
			"shoved_m": snappedf((struck.get("off", Vector3.ZERO) as Vector3).length(), 0.01),
			"yaw_deg": snappedf(rad_to_deg(float(struck.get("yaw", 0.0))), 0.1), "my_kmh_after": _ct.get("after", 0.0), "their_kmh_before": snappedf(float(v.get("speed0", 0.0)) * 3.6, 0.1),
			"damage_front": snappedf(car.damage["front"], 0.01), "challans": fines.challans.size() - int(_ct["challans0"])})
		for k in ["hit_t", "shot", "after"]:
			_ct.erase(k)
		_ct["v"] = {}
		_ct["t"] = 0.0
		kinds.pop_front()


var _ph := {"t": 0.0}


## --potholetest: the nearest pothole with a clear 30 m run-up, the car lined up so its left wheels run through it
## at 40 km/h; a close look at it first (shots: pothole.jpg), then reports the hits, the jolt and the speed lost.
func _potholetest(dt: float) -> void:
	car.autopilot = true
	if t < 12.0:
		return
	_ph["t"] = float(_ph["t"]) + dt
	if not _ph.has("hole"):
		var space := get_world_3d().direct_space_state
		var best := {}
		var bd := INF
		for cell in streamer.potholes:
			for h in streamer.potholes[cell]:
				var c: Vector3 = h[0]
				if c.distance_to(car.global_position) > bd:
					continue
				var rd: Vector3 = h[2]
				for d in [Vector3(rd.x, 0, rd.z).normalized(), -Vector3(rd.x, 0, rd.z).normalized()]:   # (along its road)
					var from: Vector3 = c - d * 30.0
					var g := space.intersect_ray(PhysicsRayQueryParameters3D.create(from + Vector3.UP * 4.0, from + Vector3.DOWN * 8.0))
					var sd := Vector3(-d.z, 0, d.x)
					var blocked := g.is_empty() or absf(g["position"].y - c.y) > 0.8
					for lat in [-1.7, -0.78, 0.15]:                  # (the car's whole width, along its track)
						var q := PhysicsRayQueryParameters3D.create(c + sd * lat + d * 3.0 + Vector3.UP * 0.7, from + sd * lat + Vector3.UP * 0.7)
						blocked = blocked or not space.intersect_ray(q).is_empty()
					if blocked:
						continue
					bd = c.distance_to(car.global_position)
					best = {"c": c, "r": h[1], "d": d, "ground": float(g["position"].y)}
					break
		if best.is_empty():
			print("POTHOLETEST none found (%d cells)" % streamer.potholes.size())
			get_tree().quit()
			return
		_ph["hole"] = best
		var c: Vector3 = best["c"]
		var gh := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 3.0, c + Vector3.DOWN * 3.0))
		print("POTHOLETEST surface at the hole %.3f, the hole %.3f (%s)" % [float(gh["position"].y) if gh else NAN, c.y,
			str(gh.get("collider")) if gh else "nothing"])
		cam.global_position = c + Vector3(2.2, 1.6, 2.2)
		cam.look_at(c)
		_ph["look"] = true
		return
	var hole: Dictionary = _ph["hole"]
	var c2: Vector3 = hole["c"]
	var d2: Vector3 = hole["d"]
	if _ph.has("look"):                                       # (a still look at it, before the drive)
		cam.global_position = c2 + Vector3(2.2, 1.6, 2.2)
		cam.look_at(c2)
		if float(_ph["t"]) > 3.0:
			if shots_dir != "":
				get_viewport().get_texture().get_image().save_jpg(shots_dir + "/pothole.jpg", 0.85)
			_ph.erase("look")
			_ph["t"] = 0.0
			var side := Vector3(-d2.z, 0, d2.x)                  # (the car's left, so its left wheels meet the hole)
			var start := c2 - d2 * 30.0 - side * 0.78
			start.y = float(hole["ground"]) + 0.8
			car.repair()
			car.global_transform = Transform3D(Basis.looking_at(-d2, Vector3.UP), start)
			_ph["start"] = start
			car.linear_velocity = d2 * (40.0 / 3.6)
			car._v_prev = car.linear_velocity
			_ph["v0"] = 0.0
		return
	car.in_steer = 0.0
	car.in_throttle = clampf((40.0 / 3.6 - car.speed) * 0.5, 0.0, 1.0) if float(_ph["t"]) < 2.2 else 0.0
	car.in_brake = 0.0
	var ph = get_node("Potholes")
	if float(_ph["t"]) > 4.0:
		print("POTHOLETEST " + JSON.stringify({"radius": snappedf(float(hole["r"]), 0.01), "wheel_hits": ph._hits,
			"moved_m": snappedf(car.global_position.distance_to(_ph["start"]), 0.1),
			"speed_now_kmh": snappedf(car.speed * 3.6, 0.1), "front_damage": snappedf(car.damage["front"], 0.01)}))
		get_tree().quit()


var _pk := {"t": 0.0}


## --parkedtest: the nearest parked vehicle with a clear 25 m run-up on its road side, driven into at 35 km/h:
## reports the shapes loaded, whether the car stopped against it (not through it), the damage and what was paid.
func _parkedtest(dt: float) -> void:
	car.autopilot = true
	if t < 12.0:
		return
	_pk["t"] = float(_pk["t"]) + dt
	if not _pk.has("target"):
		var space := get_world_3d().direct_space_state
		var best := {}
		var bd := INF
		var shape_count := 0
		for prid in streamer.parked_rids:
			shape_count += PhysicsServer3D.body_get_shape_count(prid)
		for prid in streamer.parked_rids:
			for si in PhysicsServer3D.body_get_shape_count(prid):
				var sxf := PhysicsServer3D.body_get_shape_transform(prid, si)
				var c: Vector3 = sxf.origin
				var fwd: Vector3 = sxf.basis.z.normalized()
				for d in [fwd, -fwd]:
					var from: Vector3 = c + d * 25.0
					var g := space.intersect_ray(PhysicsRayQueryParameters3D.create(from + Vector3.UP * 4.0, from + Vector3.DOWN * 8.0))
					var q := PhysicsRayQueryParameters3D.create(c + d * 3.0 + Vector3.UP * 0.8, from + Vector3.UP * 0.8)
					q.exclude = streamer.parked_rids.keys()
					if g.is_empty() or absf(g["position"].y - c.y) > 1.5 or not space.intersect_ray(q).is_empty():
						continue
					var dd := c.distance_to(car.global_position)
					if dd < bd:
						bd = dd
						best = {"c": c, "start": Vector3(from.x, g["position"].y + 0.6, from.z), "d": -d}
		if best.is_empty():
			print("PARKEDTEST none found among %d shapes" % shape_count)
			get_tree().quit()
			return
		_pk["target"] = best
		_pk["t"] = 0.0
		_pk["money0"] = fines.sim.money
		_pk["shapes"] = shape_count
		car.repair()
		car.global_transform = Transform3D(Basis.looking_at(-best["d"], Vector3.UP), best["start"])
		car.linear_velocity = Vector3.ZERO
		car._v_prev = Vector3.ZERO
		return
	var tg: Dictionary = _pk["target"]
	var to: Vector3 = tg["c"] - car.global_position
	var f2: Vector3 = car.forward()
	car.in_steer = clampf(-atan2(f2.x * to.z - f2.z * to.x, f2.x * to.x + f2.z * to.z) * 2.0, -1.0, 1.0)
	car.in_throttle = clampf((35.0 / 3.6 - car.speed) * 0.5, 0.0, 1.0) if float(_pk["t"]) < 5.0 else 0.0
	car.in_brake = 0.0 if float(_pk["t"]) < 5.0 else 1.0
	if float(_pk["t"]) > 8.0:
		var past: float = (car.global_position - (tg["c"] as Vector3)).dot(tg["d"])     # > 0: drove through it
		print("PARKEDTEST " + JSON.stringify({"shapes_loaded": _pk["shapes"], "stopped_short": past < 0.5,
			"past_its_centre_m": snappedf(past, 0.01), "front_damage": snappedf(car.damage["front"], 0.01),
			"paid": int(_pk["money0"]) - fines.sim.money}))
		if shots_dir != "":
			get_viewport().get_texture().get_image().save_jpg(shots_dir + "/parked.jpg", 0.85)
		get_tree().quit()


var _pt := {"t": 0.0, "runs": [8.0, 30.0, 50.0, 60.0], "log": [], "p": {}}


## --peopletest: the car 30 m from a person on the street (a clear line to them), driven straight at them at 8 then
## 45 km/h; reports what they did (hopped clear / knocked down), the car's speed, the money and challans.
func _peopletest(dt: float) -> void:
	_pt["t"] = float(_pt["t"]) + dt
	car.autopilot = true
	if t < 12.0:
		return
	var runs: Array = _pt["runs"]
	if _pt.has("seen") and float(_pt["t"]) - float(_pt["seen"]) > 1.0 and not _pt.has("down_seen"):
		var c0: Dictionary = (_pt["p"] as Dictionary).get("c", {})
		if not c0.is_empty():
			var m0 := c0["mms"][0] as MultiMeshInstance3D
			_pt["down_seen"] = (m0.global_transform * m0.multimesh.get_instance_transform(c0["i"])).basis.y.dot(Vector3.UP) < 0.5
	if runs.is_empty():
		print("PEOPLETEST " + JSON.stringify(_pt["log"]))
		get_tree().quit()
		return
	var p: Dictionary = _pt["p"]
	if p.is_empty():
		bystanders._scan(400.0)
		var space := get_world_3d().direct_space_state
		var best := {}
		var bd := INF
		for c in bystanders._near:
			var xf: Transform3D = c["xf"]
			for k in 12:
				var d := Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0))
				var from: Vector3 = xf.origin + d * clampf(float(runs[0]) / 3.6 * 3.0, 9.0, 32.0) + Vector3.UP * 1.0
				var q := PhysicsRayQueryParameters3D.create(xf.origin + Vector3.UP * 1.0, from)
				var q2 := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 3.0, from + Vector3.DOWN * 6.0)
				var g := space.intersect_ray(q2)
				if space.intersect_ray(q).is_empty() and not g.is_empty() and absf(g["position"].y - xf.origin.y) < 0.6:
					var dd: float = xf.origin.distance_to(car.global_position) + (0.0 if not _pt.has("used") or _pt["used"] != c["xf"].origin else 1e6)
					if dd < bd:
						bd = dd
						best = {"c": c, "start": Vector3(from.x, g["position"].y + 0.5, from.z), "d": -d}
		if best.is_empty():
			print("PEOPLETEST none found")
			get_tree().quit()
			return
		_pt["p"] = best
		_pt["t"] = 0.0
		_pt["money0"] = fines.sim.money
		_pt["ch0"] = fines.challans.size()
		car.repair()
		car.global_transform = Transform3D(Basis.looking_at(-best["d"], Vector3.UP), best["start"])
		car.linear_velocity = (best["d"] as Vector3) * runs[0] / 3.6
		car._v_prev = car.linear_velocity
		_pt["key"] = bystanders._key(best["c"])
		_pt["xf0"] = (best["c"]["xf"] as Transform3D)
		return
	var want: float = runs[0] / 3.6
	car.in_steer = 0.0
	car.in_throttle = clampf((want - car.speed) * 0.5, 0.0, 1.0) if float(_pt["t"]) < 6.0 else 0.0
	car.in_brake = 0.0 if float(_pt["t"]) < 6.0 else 1.0
	if bystanders._busy.has(_pt["key"]) and not _pt.has("seen"):
		_pt["seen"] = _pt["t"]
		_pt["kmh_at"] = snappedf(car.speed * 3.6, 0.1)
	var since: float = float(_pt["t"]) - float(_pt.get("seen", INF))
	if since > 0.6 and not _pt.has("shot"):
		_pt["shot"] = true
		if shots_dir != "":
			get_viewport().get_texture().get_image().save_jpg(shots_dir + "/people_%d.jpg" % int(runs[0]), 0.85)
	if float(_pt["t"]) > 9.0:
		var c: Dictionary = p["c"]
		var mmi := c["mms"][0] as MultiMeshInstance3D
		var now_xf := mmi.global_transform * mmi.multimesh.get_instance_transform(c["i"])
		var moved: Vector3 = now_xf.origin - (_pt["xf0"] as Transform3D).origin
		_pt["log"].append({"kmh": runs[0], "reacted": _pt.has("seen"), "attention": snappedf(bystanders._attention(c), 0.01),
			"down_now": now_xf.basis.y.dot(Vector3.UP) < 0.5, "car_kmh_then": _pt.get("kmh_at", 0.0),
			"moved_m": snappedf(Vector3(moved.x, 0, moved.z).length(), 0.01), "paid": int(_pt["money0"]) - fines.sim.money,
			"challans": fines.challans.size() - int(_pt["ch0"]), "fell": _pt.get("down_seen", false)})
		_pt["used"] = (_pt["xf0"] as Transform3D).origin
		for k in ["seen", "kmh_at", "shot", "key", "xf0", "down_seen"]:
			_pt.erase(k)
		_pt["p"] = {}
		_pt["t"] = 0.0
		runs.pop_front()


var _shift_t := 0.0                         # the "delivery or not?" question is open (seconds left)


## Getting on the scooter: a delivery shift (the bag on his back) or something else (no bag)? A story delivery
## answers it itself; otherwise 1 / 2 for a few seconds, and no answer means no shift.
## On foot, L: the torch from his bag, a warm-white beam where he looks (nothing without one).
func _toggle_torch() -> void:
	if _torch and is_instance_valid(_torch):
		_torch.queue_free()
		_torch = null
		return
	if not Goods.has(fines._save_data, "torch"):
		hud.warn(_t({"en": "No torch. A kirana or a hardware shop sells one.", "ta": "டார்ச் இல்ல. மளிகை, ஹார்டுவேர் கடையில கிடைக்கும்."}), 3.0)
		return
	var holder: Node3D = walker.camera if "camera" in walker and walker.camera else walker
	_torch = SpotLight3D.new()
	_torch.light_color = Color(1.0, 0.94, 0.85)
	_torch.light_energy = 6.0
	_torch.spot_range = 28.0
	_torch.spot_angle = 22.0
	_torch.spot_attenuation = 0.8
	_torch.shadow_enabled = true
	_torch.position = Vector3(0.18, -0.25, -0.2)
	holder.add_child(_torch)


## Paid at a counter: out of the wallet, into the bag.
func _bought(items: Dictionary) -> void:
	if items.is_empty():
		return
	var cost := 0
	for id in items:
		cost += int(Goods.GOODS[id]["price"]) * int(items[id])
		Goods.add(fines._save_data, id, int(items[id]))
	fines.sim.money -= cost
	fines.save()
	hud.warn(_t({"en": "Paid ₹%d. In your bag (B)." % cost, "ta": "₹%d கட்டியாச்சு. உங்க பையில (B)." % cost}), 3.0)
	print("STORE bought %s for %d" % [str(items), cost])


func ask_shift() -> void:
	if car == null or not car.two_wheeler:
		return
	if story and story.cur.get("delivery", false):
		car.set_delivery_bag(true)
		return
	_shift_t = 8.0
	hud.warn(_t({"en": "1: delivery shift   2: other", "ta": "1: டெலிவரி   2: வேற வேலை"}), 8.0)


func _shift_keys(dt: float) -> void:
	if _shift_t <= 0.0:
		return
	_shift_t -= dt
	var pick := 0
	if Input.is_key_pressed(KEY_1) or Input.is_key_pressed(KEY_KP_1):
		pick = 1
	elif Input.is_key_pressed(KEY_2) or Input.is_key_pressed(KEY_KP_2) or _shift_t <= 0.0:
		pick = 2
	if pick == 0:
		return
	_shift_t = 0.0
	car.set_delivery_bag(pick == 1)
	hud.warn(_t({"en": "Delivery shift: the bag's on." if pick == 1 else "No deliveries now.",
		"ta": "டெலிவரி வேலை: பை போட்டாச்சு." if pick == 1 else "இப்போ டெலிவரி இல்ல."}), 2.5)
	print("SHIFT %s" % ("delivery" if pick == 1 else "other"))


func _t(d: Dictionary) -> String:
	var lang: String = story.lang if story else "en"
	return str(d.get(lang, d.get("en", "")))


func _sms(text: String) -> void:
	if phone:
		phone.message({"en": "Coimbatore City Police", "ta": "கோவை மாநகர காவல்"}, {"en": text, "ta": text})


func _now12() -> String:
	if fines == null:
		return ""
	var m: float = fines.sim.minute
	var h := floori(m / 60.0) % 24
	return "%d:%02d %s" % [12 if h % 12 == 0 else h % 12, floori(fmod(m, 60.0)), "AM" if h < 12 else "PM"]


## The camera settings (settings.gd "camera"), re-read twice a second (the settings screen changes them).
func _camera_cfg(dt: float) -> Dictionary:
	_cam_cfg_t -= dt
	if _cam_cfg.is_empty() or _cam_cfg_t <= 0.0:
		_cam_cfg_t = 0.5
		_cam_cfg = {"fov": float(Settings.get_value("camera", "fov", 72.0)), "fov_chase": float(Settings.get_value("camera", "fov_chase", 64.0)),
			"follow": float(Settings.get_value("camera", "follow", 1.0)), "height": float(Settings.get_value("camera", "height", 1.0)),
			"smooth": maxf(float(Settings.get_value("camera", "smooth", 1.0)), 0.3), "head": float(Settings.get_value("camera", "head", 1.0)),
			"shake": float(Settings.get_value("camera", "shake", 1.0)), "invert": bool(Settings.get_value("camera", "invert", false))}
	return _cam_cfg


## The camera kept off walls, poles, trees and other vehicles between the car and it: a ball's sweep from the pivot
## (a ray alone slipped past a pole's edge), then a little short of what it met.
func _clear_view(pivot: Vector3, at: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.25
	q.shape = ball
	q.transform = Transform3D(Basis(), pivot)
	q.motion = at - pivot
	q.exclude = [car.get_rid()]
	q.collision_mask = 0xFFFFFFFF
	var r := space.cast_motion(q)
	if r.size() == 2 and r[0] < 1.0:
		return pivot + (at - pivot) * maxf(r[0] - 0.02, 0.05)
	return at


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
	var cfg := _camera_cfg(dt)
	# what the car is doing (its frame): pulling away or braking, cornering, over a bump: the camera answers these
	var acc: float = (car.speed - _cam_prev_speed) / maxf(dt, 0.001)
	_cam_prev_speed = car.speed
	_cam_acc = lerpf(_cam_acc, clampf(acc, -9.0, 5.0), 1.0 - exp(-dt * 4.0 / float(cfg["smooth"])))
	var lat: float = clampf(car.speed * car.angular_velocity.dot(jt.basis.y), -9.0, 9.0)   # (m/s², to its left +)
	var vy: float = car.linear_velocity.dot(jt.basis.y)
	var bump: float = clampf((vy - _cam_prev_vy) / maxf(dt, 0.001), -30.0, 30.0)
	_cam_prev_vy = vy
	# looking aside or behind (held), eased out and back
	var want_look := _look_force
	if driving and walker == null and _look_force == 0.0:
		if Input.is_key_pressed(KEY_Q):
			want_look = 1.35
		elif Input.is_key_pressed(KEY_E):
			want_look = -1.35
		elif Input.is_key_pressed(KEY_C):
			want_look = PI
	_look_yaw = lerp_angle(_look_yaw, want_look, 1.0 - exp(-dt * 7.0))
	var inv := -1.0 if bool(cfg["invert"]) else 1.0
	match cam_mode:
		0, 4:
			# the heading lags the car's: in a bend the camera swings out and shows the corner
			if _cam_heading == Vector3.ZERO:
				_cam_heading = flat
			_cam_heading = _cam_heading.slerp(flat, 1.0 - exp(-dt * lerpf(2.2, 4.0, clampf(absf(car.speed) / 25.0, 0.0, 1.0)) / float(cfg["smooth"]))).normalized()
			var h := _cam_heading.rotated(Vector3.UP, _orbit.x + _look_yaw)
			var back: float = (car.chase_back + _cam_acc * 0.14 + clampf(absf(car.speed) / 30.0, 0.0, 1.0) * 1.2) * float(cfg["follow"])
			var up: float = car.chase_up * float(cfg["height"]) + _orbit.y * back * inv
			if cam_mode == 4:                                 # cinematic: round it slowly, a little lower, nearer
				_cine += dt * 0.22
				h = flat.rotated(Vector3.UP, _cine + _orbit.x)
				back = car.chase_back * 0.85 * float(cfg["follow"])
				up = car.chase_up * 0.55 * float(cfg["height"]) + _orbit.y * back * inv
			var want := jt.origin - h * back + Vector3.UP * up
			cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-dt * 6.0 / float(cfg["smooth"])))
			var pivot := jt.origin + Vector3.UP * 1.6
			cam.global_position = _clear_view(pivot, cam.global_position)
			cam.look_at(jt.origin + Vector3.UP * (car.chase_up * 0.48) + h * (4.0 if cam_mode == 0 else 0.0))
			cam.fov = lerpf(cam.fov, float(cfg["fov_chase"]) + clampf(absf(car.speed) / 30.0, 0.0, 1.0) * 10.0, 1.0 - exp(-dt * 1.5))
		1, 2:
			cam.fov = float(cfg["fov"])
			var k: float = float(cfg["head"])
			var give := Vector3.ZERO
			if cam_mode == 1:                                 # his eyes: steady, the faintest give
				give = Vector3(-lat * 0.0016, -clampf(bump * 0.0006, -0.01, 0.01), -_cam_acc * 0.0022) * k
				_head = give
				_head_v = Vector3.ZERO
			else:                                             # his head: a soft spring against what the car does
				var force := Vector3(-lat * 0.006, -bump * 0.0012, -_cam_acc * 0.0065) * k
				_head_v += (force * 60.0 - _head * 60.0 - _head_v * 11.0) * dt
				_head += _head_v * dt
				_head = Vector3(clampf(_head.x, -0.06, 0.06), clampf(_head.y, -0.035, 0.035), clampf(_head.z, -0.06, 0.06))
				give = _head
			var roll := -lat * 0.0035 * k if cam_mode == 2 else 0.0
			var into_turn: float = car.steering * (0.35 if cam_mode == 2 else 0.12)
			var look := face * Basis(Vector3.UP, _orbit.x * 1.6 + _look_yaw + into_turn) * Basis(Vector3.RIGHT, deg_to_rad(-5.0) + _orbit.y * inv) \
				* Basis(Vector3.BACK, roll)
			# (the car's frame: x left, y up, z ahead; give's x is to his right)
			var off := Vector3(-give.x, give.y, give.z)
			cam.global_transform = Transform3D(look, jt * (car.eye_point() + off))
		3:
			cam.fov = float(cfg["fov"]) - 2.0
			cam.global_transform = Transform3D(face * Basis(Vector3.UP, _orbit.x + _look_yaw), jt * car.bonnet)
	if _shake > 0.001:
		cam.global_position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * _shake * 0.12 * float(_cam_cfg.get("shake", 1.0))


func _process(dt: float) -> void:
	if car and car.get("_rider") != null and is_instance_valid(car._rider) and not car.mounting:
		var own: bool = car.SPECS.get(car.vehicle, {}).get("own_cabin", false)
		car._rider.visible = walker == null and (own or not car.cockpit)   # (on foot, he isn't also sitting in it)
		if own and car.get("_rik") != null and is_instance_valid(car._rik):
			car._rik.hide_head = car.cockpit                 # (from his eyes: his arms and hands, not inside his head)
	if not _sfv_started and car:
		for a in OS.get_cmdline_user_args():
			if a == "--pedcheck" and not _sfv_started:
				_sfv_started = true
				_ped_check.call_deferred()
			if a.begins_with("--camtest") and not _sfv_started:
				_sfv_started = true
				_cam_test.call_deferred(a.get_slice("=", 1) if a.contains("=") else "sedan")
			if a == "--lamptest" and not _sfv_started:
				_sfv_started = true
				_lamp_test.call_deferred()
			if a == "--traffictest" and not _sfv_started:
				_sfv_started = true
				_traffic_test.call_deferred()
			if a == "--taketest" and not _sfv_started:
				_sfv_started = true
				_take_test.call_deferred()
			if a.begins_with("--sfvehicletest="):
				_sfv_started = true
				_sfv_test.call_deferred(a.get_slice("=", 1).split(","))
	if not _mt_started and "--mounttest" in OS.get_cmdline_user_args() and car and car.get("_rik") != null:
		_mt_started = true
		_mount_test.call_deferred()
	var _p0 := Time.get_ticks_usec()
	_process_timed(dt)
	if _park_t > 0.0:
		_park_t -= dt
		_settle_parked()
	Prof.add("city", _p0)


## Out of the car: it's frozen where it stands, but only once all its tyres are on the ground (or after 3 s, if
## something holds a wheel up: a kerb); until then it settles under its own weight.
var _park_t := 0.0


func _settle_parked() -> void:
	if walker == null or car == null:
		_park_t = 0.0
		return
	var down := true
	for w in car._wheels:
		down = down and (w as VehicleWheel3D).is_in_contact()
	if (down and car.linear_velocity.length() < 0.2) or _park_t <= 0.0:
		car.freeze = true
		_park_t = 0.0
	else:
		car.freeze = false


var _f2_down := false
var _bench_t := 0.0
var _bench_frames := 0


func _process_timed(dt: float) -> void:
	t += dt
	_shift_keys(dt)
	var gk := Input.is_key_pressed(KEY_F2)
	if gk and not _f2_down:                                   # the next graphics preset
		var g := Graphics.step()
		Graphics.apply(get_viewport(), env, sun)
		if hud:
			hud.warn("Graphics: %s" % g.capitalize(), 2.5)
	_f2_down = gk
	var lk := Input.is_key_pressed(KEY_L)
	if lk and not _l_down and walker:
		_toggle_torch()
	_l_down = lk
	if _torch and (walker == null or not is_instance_valid(_torch)):
		_torch = null
	_unstick(get_process_delta_time())
	var bk := Input.is_key_pressed(KEY_B)
	if bk and not _b_down and bag and not (store and store.visible):
		bag.toggle()
	_b_down = bk
	if _nohud:
		hud.visible = false
		map.visible = false
	if water:
		water.target = streamer.target
	if driving:
		if not placed:
			placed = _place_car(spawn) if t > 1.0 else false
			cam.global_position = spawn + Vector3(0, 80, 40)
			cam.look_at(spawn)
			return
		if Input.is_key_pressed(KEY_R) and not _r_down:
			_place_car(car.global_position)
		_r_down = Input.is_key_pressed(KEY_R)
		if walker == null:
			_drive_camera(dt)
		_daylight()
		if weather:
			weather.apply(env, sun, get_viewport().get_camera_3d())
		_red_light_check()
		if " ".join(OS.get_cmdline_user_args()).contains("--trafficshot"):
			if int(t) != int(t - dt) and int(t) % 5 == 0:
				var moving: int = traffic.vehicles.filter(func(v): return v["speed"] > 1.0).size()
				var sp := 0.0
				for v in traffic.vehicles:
					sp += v["speed"]
				print("TRAFFIC t=%d vehicles=%d moving=%d mean=%.1f km/h fps=%d" % [int(t), traffic.vehicles.size(), moving,
					sp / maxf(1, traffic.vehicles.size()) * 3.6, Engine.get_frames_per_second()])
			if t > 30.0 and shots_dir != "":
				var near = null
				var want := ""                          # --trafficshot=auto: the nearest of that kind
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--trafficshot="):
						want = a.get_slice("=", 1)
				for v in traffic.vehicles:
					if want != "" and v["kind"] != want:
						continue
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
			var two: bool = car.SPECS[car.vehicle].get("rider", false)          # a two-wheeler: closer, at the rider
			cam.global_position = ct.origin + ct.basis.x * (2.6 if two else 5.0) + ct.basis.z * (0.8 if two else 0.0) + Vector3.UP * (1.2 if two else 1.0)
			cam.look_at(ct.origin + Vector3.UP * (0.95 if two else 0.6))
			if t > 6.0 and shots_dir != "":
				get_viewport().get_texture().get_image().save_jpg(shots_dir + "/car.jpg", 0.85)
				print("WHEELS %d %s" % [car._wheels.size(), str(car._wheels.map(func(w): return w.get_child_count()))])
				for w in car._wheels:                    # (touching the road, and the tyre's bottom over it)
					var w3 := w as VehicleWheel3D
					print("WHEEL contact %s  local y %.2f  global y %.2f  car y %.2f  rpm %.0f" % [w3.is_in_contact(), w3.position.y,
						w3.global_position.y, car.global_position.y, w3.get_rpm()])
				if car._rider:
					for ap in car._rider.find_children("*", "AnimationPlayer", true, false):
						print("RIDER anim=%s playing=%s pos=%s" % [ap.current_animation, ap.is_playing(), str(car._rider.position)])
					for sk in car._rider.find_children("*", "Skeleton3D", true, false):
						var s3 := sk as Skeleton3D
						for bn in ["thigh_l", "hand_l", "foot_l", "head"]:
							var gp: Vector3 = car.global_transform.affine_inverse() * (s3.global_transform * s3.get_bone_global_pose(s3.find_bone(bn)).origin)
							print("RIDER %s in scooter frame %s" % [bn, str(gp.snapped(Vector3.ONE * 0.01))])
				get_tree().quit()
			return
		if "--potholetest" in OS.get_cmdline_user_args():        # self-test: a wheel through a pothole at 40 km/h
			_potholetest(dt)
			return
		if "--parkedtest" in OS.get_cmdline_user_args():         # self-test: into a parked car at 35 km/h
			_parkedtest(dt)
			return
		if "--peopletest" in OS.get_cmdline_user_args():         # self-test: at a person on the street, slow then fast
			_peopletest(dt)
			return
		if "--crashtest" in OS.get_cmdline_user_args():          # self-test: drive into traffic (a car, an auto, a bus)
			_crashtest(dt)
			return
		if "--testdrive" in OS.get_cmdline_user_args():          # self-test: accelerate, report, screenshot, quit
			# a test driver: follows the main roads at ~50 km/h, keeping left (pure pursuit 12 m ahead)
			car.autopilot = true
			if path.is_empty() or path_i >= path.size() - 1:
				var nxt := _next_piece(car.global_position if path.is_empty() else path[path.size() - 1])
				if not nxt.is_empty():
					path = nxt
					path_i = 0
					if t < 4.0 and nxt.size() > 1:             # (the first road: set off along it, not into a U-turn)
						var d0 := Vector3(nxt[1].x - nxt[0].x, 0, nxt[1].z - nxt[0].z).normalized()
						car.global_transform = Transform3D(Basis.looking_at(-d0, Vector3.UP), car.global_position)
						car.linear_velocity = Vector3.ZERO
			var steer := 0.0
			if path.size() > 1:
				while path_i < path.size() - 1 and Vector2(path[path_i].x - car.global_position.x, path[path_i].z - car.global_position.z).length() < 12.0:
					path_i += 1
				var a2 := path[maxi(path_i - 1, 0)]
				var b2 := path[path_i]
				var d2 := Vector3(b2.x - a2.x, 0, b2.z - a2.z).normalized()
				var aim := b2 + Vector3(d2.z, 0, -d2.x) * path_lane   # (keep left, India: the traffic's own lane)
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
	if _free_clock and story == null:
		_daylight()
	if flyover.size() >= 11:
		var f := clampf(_fly_t / flyover[10], 0.0, 1.0) if _fly_t >= 0.0 else 0.0
		var e := f * f * (3.0 - 2.0 * f)
		cam.position = Vector3(flyover[0], flyover[1], flyover[2]).lerp(Vector3(flyover[5], flyover[6], flyover[7]), e)
		cam.basis = Basis.from_euler(Vector3(deg_to_rad(lerpf(flyover[4], flyover[9], e)), deg_to_rad(lerpf(flyover[3], flyover[8], e)), 0))
		if _fly_t < 0.0:
			if Engine.get_frames_drawn() > 90 and streamer.pending.is_empty() and streamer.ready_q.is_empty() and streamer.loaded.size() > 20:
				_fly_t = 0.0
				print("TRAILER_MARK frame=%d" % Engine.get_frames_drawn())
		else:
			_fly_t += 1.0 / 30.0                    # (by frames, as the movie is recorded: a slow frame can't skip the flight)
			if _fly_t > flyover[10] + 1.0:
				get_tree().quit()
		return
	if not view.is_empty():
		cam.position = Vector3(view[0], view[1], view[2])
		cam.basis = Basis.from_euler(Vector3(deg_to_rad(view[4]), deg_to_rad(view[3]), 0))
		if t > 25.0 and streamer.pending.is_empty() and streamer.ready_q.is_empty() and streamer.loaded.size() > 20:
			if "--viewbench" in OS.get_cmdline_user_args():   # (testing: a fixed view's frame rate, 20 s of it)
				_bench_t += dt
				_bench_frames += 1
				if _bench_t >= 20.0:
					print("VIEWBENCH %s: %.1f fps, %.1f ms a frame (%d frames), draws %d" % [Graphics.preset(), _bench_frames / _bench_t,
						_bench_t * 1000.0 / _bench_frames, _bench_frames,
						RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
					print("VIEWBENCH tiles: %d set up, %.1f ms each on average, worst %.1f ms" % [int(streamer.stats.get("inst_n", 0)),
						float(streamer.stats.get("inst_ms", 0.0)) / maxi(int(streamer.stats.get("inst_n", 0)), 1), float(streamer.stats.get("inst_max", 0.0))])
					if shots_dir != "":                   # (and the picture of it)
						get_viewport().get_texture().get_image().save_jpg(shots_dir + "/view.jpg", 0.85)
					get_tree().quit()
				return
			if shots_dir != "":
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
				if flip and int(r.get("o", 0)) == 1:     # (a one-way only the way it goes)
					continue
				var e := last if flip else first
				var dd := Vector2(e.x - from.x, e.z - from.z).length()
				if dd < bd:
					bd = dd
					path_lane = CityTraffic._lane(r)
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
						path_lane = CityTraffic._lane(r)
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
	if int(t) != int(t - dt) and int(t) % 5 == 0 and int(streamer.stats.get("inst_n", 0)) > 0:
		print("TILES instanced %d, %.1f ms each on average, worst %.1f ms" % [int(streamer.stats["inst_n"]),
			float(streamer.stats["inst_ms"]) / int(streamer.stats["inst_n"]), float(streamer.stats["inst_max"])])
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
		_orbit.x = clampf(_orbit.x - e.relative.x * 0.004 * Settings.look(), -PI, PI)
		_orbit.y = clampf(_orbit.y - e.relative.y * 0.003 * Settings.look(), -0.25, 0.5)
		_orbit_idle = 0.0
		return
	if car and driving and e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_Y:
		cam_mode = (cam_mode + 1) % CAM_MODES.size()
		car.set_cockpit(cam_mode == 1 or cam_mode == 2)
		return
	if car and e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_V and driving:
			cam_mode = (cam_mode + 1) % CAM_MODES.size()
			car.set_cockpit(cam_mode == 1 or cam_mode == 2)
			if hud:
				hud.warn("Camera: " + CAM_MODES[cam_mode], 1.5)
			return
		if e.keycode == KEY_F and driving:
			toggle_on_foot()
			return
		if e.keycode == KEY_F9:
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
		yaw -= e.relative.x * 0.003 * Settings.look()
		pitch = clampf(pitch - e.relative.y * 0.003 * Settings.look(), -1.3, 1.3)
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
