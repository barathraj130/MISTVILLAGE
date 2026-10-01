extends Node3D
## "The Road Up": the playable prologue. Drive a jeep from Coimbatore across the plains,
## through Mettupalayam and the forest check post, up nine hairpins into the clouds and on
## through the tea gardens of Kotagiri to The Mist Village gate. Built at load from route.gd.
##
## Keys: W/S accelerate / brake-reverse · A/D steer · Space handbrake · H horn · L headlights
##       V camera · R back onto the road · E interact · F1 help · F2 quality · F8 skip to the resort · F5 save
## Test flags (after --): --autodrive  --timescale=3  --shots=/abs/dir  --quit-at-end  --start=<metres>

const Route := preload("res://scripts/drive/route.gd")
const Terrain := preload("res://scripts/drive/terrain.gd")
const Road := preload("res://scripts/drive/road.gd")
const Props := preload("res://scripts/drive/props.gd")
const Traffic := preload("res://scripts/drive/traffic.gd")
const Elephants := preload("res://scripts/drive/elephants.gd")
const Jeep := preload("res://scripts/drive/jeep.gd")
const Prof := preload("res://scripts/drive/prof.gd")
const Details := preload("res://scripts/drive/details.gd")
const Towns := preload("res://scripts/drive/towns.gd")
const MapUI := preload("res://scripts/drive/map_ui.gd")
const Sim := preload("res://scripts/drive/sim.gd")
const RoadGraph := preload("res://scripts/drive/road_graph.gd")
const TownTraffic := preload("res://scripts/drive/town_traffic.gd")
const Pedestrians := preload("res://scripts/drive/pedestrians.gd")
const SKY_SHADER := preload("res://shaders/sky.gdshader")
const MIST_SHADER := preload("res://shaders/mist_sheet.gdshader")
const TERRAIN_SHADER := preload("res://shaders/terrain_drive.gdshader")
const RESORT_SCENE := "res://scenes/main.tscn"
const WorldBuilder := preload("res://scripts/world_builder.gd")
const Walker := preload("res://scripts/player.gd")
const RESORT_RING := 70.0

const MORNING_SKY := [[0.40, [0.52, 0.50, 0.49]], [0.50, [1.0, 0.70, 0.46]], [0.56, [0.92, 0.76, 0.60]],
	[0.70, [0.50, 0.62, 0.80]], [1.0, [0.17, 0.33, 0.66]]]
const NOON_SKY := [[0.40, [0.55, 0.58, 0.60]], [0.50, [0.80, 0.84, 0.88]], [0.60, [0.62, 0.74, 0.90]],
	[1.0, [0.20, 0.40, 0.78]]]
const NIGHT_SKY := [[0.40, [0.010, 0.012, 0.020]], [0.52, [0.030, 0.040, 0.070]], [1.0, [0.004, 0.008, 0.025]]]
const AUTOSAVE_SECS := 180.0
const STAGE_SPEED := {"coimbatore": 12.0, "plains": 20.0, "mettupalayam": 10.0, "foothills": 12.0,
	"ghat": 9.0, "mist": 9.0, "kotagiri": 8.0, "arrival": 5.0}

var route: Route
var terrain: Terrain
var road: Road
var props: Props
var traffic: Traffic
var elephants: Elephants
var jeep: Jeep
var resort: WorldBuilder          # your resort, embedded at the end of the road (real map)
var walker: Walker                # you, on foot (F to get out / back in)
var towns: Towns                  # open-world Coimbatore, Mettupalayam and Kotagiri
var map_ui: MapUI
var town_traffic: TownTraffic
var pedestrians: Pedestrians
var graph := RoadGraph.new()      # the one road network: meshes, GPS, minimap, grip, validator
var sim := Sim.new()               # clock, weather, wallet, fuel, save file
var sky_mat: ShaderMaterial
var rain: GPUParticles3D
var _rain_audio: AudioStreamPlayer
var _rain_pb: AudioStreamGeneratorPlayback
var _rain_lp := 0.0
var _sky_t := 0.0
var _autosave_t := 0.0
var _prompt := ""                  # the [E] action on offer right now
var _near_vehicle := ""
var _fuel_warned := false
var _dark_hint_t := -100.0
var debug_mode := false            # F3: developer overlay (fps, surface, road graph, validator)
var ui_debug: Label
var _debug_lines: MeshInstance3D
var _debug_t := 0.0
var _debug_report := ""
var _surface_t := 0.0
var _cam_prev_speed := 0.0
var _cam_acc := 0.0
var env: Environment
var sun: DirectionalLight3D
var cam: Camera3D
var cam_mode := 0
var args := PackedStringArray()

var idx := 0                       # nearest road sample
var d := 0.0                       # distance along the road
var lateral := 0.0                 # + = left of centre
var stage_id := ""
var ready_to_drive := false
var checkpost := "closed"          # closed → open | skipped
var stop_time := 0.0
var elephant_warn_at := -10.0
var too_close := 0
var tea_break := false
var arrived := false
var shots: Array = []
var _t := 0.0

var ui_loading: Control
var ui_progress: Label
var ui_speed: Label
var ui_meta: Label
var ui_objective: Label
var ui_status: Label               # top right: clock, weather, wallet, diesel
var ui_title: Label
var ui_subtitle: Label
var ui_message: Label
var ui_help: Label
var ui_fade: ColorRect
var _msg_tween: Tween
var _title_tween: Tween


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--timescale="):
			Engine.time_scale = float(a.get_slice("=", 1))
	_setup_input()
	_build_ui()
	await _build_world()
	_start()


# ----------------------------------------------------------------------------- input
func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	_add_action("accelerate", [KEY_W, KEY_UP])
	_add_action("brake", [KEY_S, KEY_DOWN])
	_add_action("steer_left", [KEY_A, KEY_LEFT])
	_add_action("steer_right", [KEY_D, KEY_RIGHT])
	_add_action("handbrake", [KEY_SPACE])
	_add_action("horn", [KEY_H])
	_add_action("headlights", [KEY_L])
	_add_action("camera_view", [KEY_V])
	_add_action("reset_vehicle", [KEY_R])
	_add_action("interact", [KEY_E])
	_add_action("toggle_help", [KEY_F1])
	_add_action("toggle_quality", [KEY_F2])
	_add_action("skip_drive", [KEY_F8])
	_add_action("toggle_manual", [KEY_M])
	_add_action("shift_up", [KEY_X])
	_add_action("shift_down", [KEY_Z])
	_add_action("back_to_menu", [KEY_F10])
	_add_action("quick_save", [KEY_F5])
	_add_action("debug_mode", [KEY_F3])
	_add_action("indicate_left", [KEY_COMMA])
	_add_action("indicate_right", [KEY_PERIOD])
	_add_action("hazards", [KEY_SLASH])
	_add_action("debug_time", [KEY_F6])
	_add_action("debug_weather", [KEY_F7])
	# on foot (same keys as the resort)
	_add_action("enter_exit", [KEY_F])
	_add_action("open_map", [KEY_TAB])
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE])
	_add_action("run", [KEY_SHIFT])
	_add_action("release_mouse", [KEY_ESCAPE])


# ----------------------------------------------------------------------------- world
var _load_t0 := 0
var _load_step := ""


func _progress(text: String, f: float) -> void:
	ui_progress.text = "%s…  %d%%" % [text, int(f * 100.0)]
	# --trace / --bench: how long each loading step takes
	if text != _load_step:
		var now := Time.get_ticks_msec()
		if _load_step != "" and ("--trace" in args or "--bench" in args):
			print("LOAD %-40s %6d ms" % [_load_step, now - _load_t0])
		_load_step = text
		_load_t0 = now


func _build_world() -> void:
	_progress("Laying out the road", 0.02)
	await get_tree().process_frame
	Props.preload_models()                  # engine threads decode the prop GLBs while the road and resort build
	route = Route.new()
	if "--fictional" in args or not route.load_map():
		route.build()                       # the original made-up road
	else:
		_progress("Loading the real Coimbatore–Kotagiri map", 0.04)
	_environment()

	var noise := FastNoiseLite.new()
	noise.frequency = 0.01
	noise.fractal_octaves = 5
	var ntex := NoiseTexture2D.new()
	ntex.width = 512
	ntex.height = 512
	ntex.seamless = true
	ntex.noise = noise
	var tmat := ShaderMaterial.new()
	tmat.shader = TERRAIN_SHADER
	tmat.set_shader_parameter("noise_tex", ntex)
	tmat.set_shader_parameter("plains_end", route.face_x0 - 700.0)
	tmat.set_shader_parameter("hills_start", route.face_x0 - 150.0)
	tmat.set_shader_parameter("by_height", route.is_real)
	var tex_dir := "res://assets/drive/tex/"
	if ResourceLoader.exists(tex_dir + "grass_color.jpg"):
		for pair in [["grass_tex", "grass"], ["dry_tex", "dry_grass"], ["soil_tex", "red_soil"], ["rock_tex", "rock"],
				["forest_tex", "forest_floor"]]:
			tmat.set_shader_parameter(pair[0], load(tex_dir + pair[1] + "_color.jpg"))
		tmat.set_shader_parameter("has_textures", true)

	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(route, tmat)
	_progress("Shaping the hills", 0.06)
	await get_tree().process_frame
	if route.is_real:
		terrain.load_real()
	else:
		terrain.build_heights()
	if route.is_real and ResourceLoader.exists(WorldBuilder.SCENE_JSON) and not "--no-resort" in args:
		_progress("Bringing in The Mist Village", 0.12)
		await get_tree().process_frame
		_attach_resort()
	await terrain.build_chunks(func(f: float): _progress("Building the ground", 0.2 + 0.3 * f))
	if route.is_real:
		terrain.build_far_real()
	else:
		terrain.build_far()

	_progress("Paving the ghat road", 0.52)
	await get_tree().process_frame
	road = Road.new()
	road.name = "Road"
	add_child(road)
	road.build(route, terrain)

	props = Props.new()
	props.name = "Roadside"
	add_child(props)
	await props.build(route, terrain, func(f: float): _progress("Planting palms, forest and tea", 0.6 + 0.3 * f))
	_progress("Adding the small things", 0.92)
	await get_tree().process_frame
	var details := Details.new()
	details.name = "Details"
	add_child(details)
	details.build(route, terrain, road.bumps)
	if route.is_real and FileAccess.file_exists("res://assets/drive/towns.json"):
		towns = Towns.new()
		towns.name = "Towns"
		graph.route = route
		towns.graph = graph
		towns.highway_gap = func(q: Vector3) -> float:
			var i: int = route.nearest_global(q)
			return Vector2(route.pts[i].x - q.x, route.pts[i].z - q.z).length()
		add_child(towns)
		await towns.build("res://assets/drive/towns.json", road.mat_asphalt,
			func(what: String, f: float): _progress(what, 0.93 + 0.05 * f))
		if "--trace" in args or "--bench" in args:
			print("TOWNS parked vehicles %d, fuel bunks %d" % [towns.parked, towns.bunks.size()])
	_mist_layers(ntex)

	jeep = Jeep.new()
	jeep.name = "Jeep"
	add_child(jeep)
	traffic = Traffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.build(route)
	if graph.has_graph() and not "--notowntraffic" in args:
		town_traffic = TownTraffic.new()
		town_traffic.name = "TownTraffic"
		add_child(town_traffic)
		town_traffic.build(graph, jeep)
	if graph.has_graph() and not "--nopeople" in args:
		pedestrians = Pedestrians.new()
		pedestrians.name = "Pedestrians"
		add_child(pedestrians)
		pedestrians.build(graph, jeep)
	elephants = Elephants.new()
	elephants.name = "Elephants"
	add_child(elephants)
	elephants.build(route, terrain)

	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 12000.0
	cam.fov = 68.0
	add_child(cam)
	_build_rain()
	_progress("Ready", 1.0)


func _environment() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("day_gradient", _gradient(MORNING_SKY))
	sky_mat.set_shader_parameter("noon_gradient", _gradient(NOON_SKY))
	sky_mat.set_shader_parameter("night_gradient", _gradient(NIGHT_SKY))
	var sun_dir := Vector3(0.75, 0.2, -0.45).normalized()
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("day_strength", 1.5)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.74, 0.76)
	env.fog_density = 0.00015
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.2
	env.fog_sun_scatter = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


func _gradient(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(Color(s[1][0], s[1][1], s[1][2]))
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	return t


## Your resort, placed where the real road ends in Kotagiri: its road picks up exactly where the
## drive's road stops, the map's ground sinks under the resort's own detailed ground, and a 70 m
## ring blends the two. Map trees, poles and tea stay out of the grounds.
func _attach_resort() -> void:
	resort = WorldBuilder.new()
	resort.embedded = true
	resort.name = "TheMistVillage"
	add_child(resort)
	var end_f: Transform3D = route.frame_at(route.length)
	var t_end: Vector3 = end_f.basis.z
	var yaw := atan2(t_end.x, t_end.z) - atan2(resort.road_dir.x, resort.road_dir.z)
	var b := Basis(Vector3.UP, yaw)
	resort.transform = Transform3D(b, end_f.origin - b * resort.road_south)
	route.resort_attached = true
	# same photo-textured ground as the map, so grass, soil and rock carry straight across
	for mi in resort.find_children("terrain_near*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = terrain.material
	var inv: Transform3D = resort.transform.affine_inverse()
	var half: float = WorldBuilder.EMBED_HALF
	var ring := RESORT_RING
	var centre: Vector3 = resort.transform.origin
	var near_fn := func(x: float, z: float, hh: float, pr: float) -> Vector2:
		var l: Vector3 = inv * Vector3(x, 0.0, z)
		var ax := maxf(absf(l.x), absf(l.z))
		if ax < half - 2.0:
			var g: float = resort.ground_local(l.x, l.z)
			var gy: float = (resort.transform * Vector3(l.x, g, l.z)).y if not is_nan(g) else hh
			return Vector2(minf(hh, gy - 4.0), 1.0)          # hide the map ground under the resort's
		if ax < half + ring:
			var t := smoothstep(0.0, ring, ax - half + 2.0)
			if pr > 0.5 and t > 0.3:
				return Vector2(hh, pr)                       # keep the drive's own road bed
			var e: float = resort.ground_local(clampf(l.x, -half + 4.0, half - 4.0), clampf(l.z, -half + 4.0, half - 4.0))
			if is_nan(e):
				return Vector2(hh, pr)
			var ey: float = (resort.transform * Vector3(l.x, e, l.z)).y
			return Vector2(lerpf(ey, hh, t), maxf(pr, 1.0 - t))
		return Vector2(hh, pr)
	terrain.blend_region(centre, (half + ring) * 1.45, near_fn)
	if "--trace" in args:
		var probe := []
		for lz in [-240.0, -200.0, -170.0, -150.0, 0.0, 150.0, 170.0, 200.0, 240.0]:
			var wp: Vector3 = resort.transform * Vector3(0.0, 0.0, lz)
			var g: float = resort.ground_local(0.0, clampf(lz, -154.0, 154.0))
			probe.append("z%+d: map %.1f resort %.1f" % [int(lz), terrain.height_at(wp.x, wp.z), (resort.transform * Vector3(0, g, 0)).y])
		print("RESORT origin=%s road_south=%s dir=%s hgrid=%d\n  %s" % [resort.transform.origin, resort.road_south, resort.road_dir,
			resort._hgrid.size(), "\n  ".join(probe)])
	var far_fn := func(x: float, z: float, hh: float) -> float:
		var l: Vector3 = inv * Vector3(x, 0.0, z)
		var ax := maxf(absf(l.x), absf(l.z))
		var e: float = resort.ground_local(clampf(l.x, -half + 4.0, half - 4.0), clampf(l.z, -half + 4.0, half - 4.0))
		if is_nan(e):
			return hh
		var ey: float = (resort.transform * Vector3(l.x, e, l.z)).y
		if ax < half:
			return minf(hh, ey - 6.0)
		return lerpf(ey - 1.0, hh, smoothstep(0.0, ring, ax - half)) if ax < half + ring else hh
	route.blend_far(centre, (half + ring) * 1.45, far_fn)


## Cloud layers clinging to the Nilgiri slopes: you drive up through them.
func _mist_layers(ntex: NoiseTexture2D) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var i0: int = route.index_at(route.marks["ghat_start"] - 1500.0)
	var i1: int = route.index_at(route.stages[-2]["start"])
	for i in range(i0, i1, 20):
		var p: Vector3 = route.pts[i]
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var centre := (lo + hi) * 0.5
	var size := (hi - lo) + Vector2(2500.0, 2500.0)
	var heights: Array = [118.0, 150.0, 178.0]
	if route.is_real:
		# cloud base ~1,150–1,450 m real altitude
		heights = [(1150.0 - route.alt[0]) * 0.5, (1300.0 - route.alt[0]) * 0.5, (1450.0 - route.alt[0]) * 0.5]
	var dens := [0.5, 0.65, 0.45]
	var scales := [0.004, 0.003, 0.0025]
	for k in 3:
		var plane := PlaneMesh.new()
		plane.size = size
		var mat := ShaderMaterial.new()
		mat.shader = MIST_SHADER
		mat.set_shader_parameter("noise_tex", ntex)
		mat.set_shader_parameter("mist_color", Color(0.86, 0.88, 0.9))
		mat.set_shader_parameter("density", dens[k])
		mat.set_shader_parameter("noise_scale", scales[k])
		mat.set_shader_parameter("drift", Vector2(2.0, -1.0))
		mat.set_shader_parameter("fade_distance", 25.0)
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = mat
		mi.position = Vector3(centre.x, heights[k], centre.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# ----------------------------------------------------------------------------- start
func _start() -> void:
	var start_d := 12.0
	sim.distance_scale = route.real_length / route.length if route.is_real else 1.0
	var saved := -1.0
	if Engine.has_meta("continue_game") or "--continue" in args:
		Engine.remove_meta("continue_game")
		saved = _load_game()
	for a in args:
		if a.begins_with("--start="):
			start_d = float(a.get_slice("=", 1))
		elif a.begins_with("--time="):
			sim.minute = float(a.get_slice("=", 1)) * 60.0
		elif a.begins_with("--weather="):
			sim.weather = a.get_slice("=", 1)
			sim.wx = Sim.WEATHER[sim.weather].duplicate()
			if sim.weather == "rain":
				sim.wet = 1.0
		elif a.begins_with("--fuel="):
			sim.fuel = float(a.get_slice("=", 1)) * Sim.TANK_L
	if saved >= 0.0:
		start_d = saved
	_place_jeep(start_d)
	for a in args:
		if a.begins_with("--at="):                                    # debug teleport: --at=x,z[,yaw°]
			var v := a.get_slice("=", 1).split(",")
			var tx := float(v[0])
			var tz := float(v[1])
			var yaw := deg_to_rad(float(v[2])) if v.size() > 2 else 0.0
			jeep.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(tx, terrain.height_at(tx, tz) + 1.0, tz))
			idx = route.nearest_global(jeep.global_position)
		if a.begins_with("--bunk=") and towns and not towns.bunks.is_empty():   # testing: park on a forecourt
			var bk: Dictionary = towns.bunks[int(a.get_slice("=", 1)) % towns.bunks.size()]
			var bp: Vector3 = bk["pos"]
			jeep.global_transform = Transform3D(Basis(Vector3.UP, 0.6), bp + Vector3(5.0, 0.8, 9.0))
			idx = route.nearest_global(bp)
	if _saved_pose.has("pos"):                  # exactly where you parked, even on a town street
		var sp: Array = _saved_pose["pos"]
		jeep.global_transform = Transform3D(Basis(Vector3.UP, float(_saved_pose.get("yaw", 0.0))),
			Vector3(sp[0], sp[1] + 0.4, sp[2]))
		var vk := String(_saved_pose.get("vehicle", jeep.vehicle))
		if vk != jeep.vehicle and Jeep._available(vk):
			jeep.configure(vk)
			jeep.global_transform = Transform3D(Basis(Vector3.UP, float(_saved_pose.get("yaw", 0.0))),
				Vector3(sp[0], sp[1] + 0.4, sp[2]))
		jeep.set_lights(bool(_saved_pose.get("lights", false)))
		_message("Welcome back · Day %d, %s" % [sim.day, Sim.clock_text(sim.minute)], 4.0)
	# your second car waits on the shoulder just behind you: get out (F), walk over, F again
	var spare := "coupe" if jeep.vehicle != "coupe" else "luxury_suv"
	if Jeep._available(spare) and not "--nospare" in args:
		var jf: Transform3D = jeep.global_transform
		_park_left_behind(spare, Transform3D(jf.basis, jf.origin - jf.basis.z * 9.0 + jf.basis.x * 2.6 + Vector3(0, -0.3, 0)))
	if route.is_real and not "--nomap" in args:
		var _tm := Time.get_ticks_msec()
		_setup_map()
		if "--trace" in args:
			print("LOAD %-40s %6d ms" % ["Map + GPS", Time.get_ticks_msec() - _tm])
	if "--checkcol" in args:
		_check_collision()
	for a in args:
		if a.begins_with("--cam="):
			cam_mode = int(a.get_slice("=", 1))
			jeep.set_cockpit(cam_mode == 1)
	# starting further up the road (--start, or a future save point): skip events already behind us
	if start_d > route.marks["checkpost"] - 30.0 and checkpost == "closed":
		checkpost = "open"
	if checkpost != "closed":
		props.open_barrier()
	if start_d > route.marks["elephants"] - 180.0:
		elephants.state = "done"
	cam.global_transform = jeep.global_transform.translated_local(Vector3(0, 3, -8))
	cam.look_at(jeep.global_position + Vector3.UP)
	cam.make_current()
	_apply_quality("low" if RenderingServer.get_video_adapter_name().contains("Apple M1")
		or RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU else "high")
	if "--autodrive" in args:
		jeep.autopilot = true
		for s in route.stages:
			shots.append([s["start"] + 140.0, s["id"]])
		for k in [0, route.hairpin_idx.size() / 2, route.hairpin_idx.size() - 1]:
			shots.append([route.dist[route.hairpin_idx[k]] - 35.0, "hairpin_%d" % (k + 1)])
		shots.append([route.marks["checkpost"] - 40.0, "checkpost"])
		shots.append([route.marks["elephants"] - 70.0, "elephants"])
		shots.append([route.length - 95.0, "gate"])
		shots.sort_custom(func(a, b): return a[0] < b[0])
	var tw := create_tween()
	tw.tween_property(ui_loading, "modulate:a", 0.0, 1.0)
	tw.tween_callback(func(): ui_loading.visible = false)
	ui_help.visible = true
	get_tree().create_timer(12.0).timeout.connect(func(): ui_help.modulate.a = 0.0)
	if "--validate-roads" in args or "--debug" in args:
		_validate_roads()
	if "--debug" in args:
		_set_debug(true)
	ready_to_drive = true


## --checkcol : compare heightmap collision with the visible ground at off-road points.
func _check_collision() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var worst := 0.0
	var n := 0
	for k in 40:
		var dd := route.length * (k + 0.5) / 40.0
		for off in [-30.0, 45.0, 120.0]:
			var p: Vector3 = route.frame_at(dd, off).origin
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 400.0, p.z), Vector3(p.x, p.y - 400.0, p.z))
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var g: float = terrain.height_at(p.x, p.z)
			var err: float = hit["position"].y - g
			if absf(err) < 3.0:                 # ignore hits on buildings, walls, trees
				worst = maxf(worst, absf(err))
				n += 1
	print("COLLISION checked %d points, worst ground mismatch %.2f m" % [n, worst])


## GTA-style minimap + full map (Tab) with GPS over the highway and every town street.
func _setup_map() -> void:
	map_ui = MapUI.new()
	map_ui.name = "Map"
	ui_help.get_parent().add_child(map_ui)
	map_ui.get_parent().move_child(map_ui, ui_fade.get_index())
	var extra: Array = []
	if resort:
		extra.append({"name": "The Mist Village", "kind": "Resort", "pos": route.frame_at(route.length).origin})
	extra.append({"name": "Viewpoint tea stall", "kind": "Viewpoint", "pos": props.tea_stall_pos})
	extra.append({"name": "Forest check post", "kind": "Check post", "pos": route.frame_at(route.marks["checkpost"]).origin})
	extra.append({"name": "Bhavani bridge", "kind": "Bridge",
		"pos": route.frame_at((route.marks["bridge_start"] + route.marks["bridge_end"]) * 0.5).origin})
	var tdata: Dictionary = towns.data if towns else {}
	var pois: Array = towns.pois if towns else []
	map_ui.setup(route, tdata, pois, extra, func() -> Array:
		if walker:
			return [walker.global_position, -walker.global_basis.z]
		return [jeep.global_position, jeep.forward()]
	, graph)


func _place_jeep(at_d: float) -> void:
	var f: Transform3D = route.frame_at(at_d, Route.LANE)
	jeep.linear_velocity = Vector3.ZERO
	jeep.angular_velocity = Vector3.ZERO
	var b: Basis = f.basis if Jeep.FWD > 0.0 else f.basis.rotated(Vector3.UP, PI)
	jeep.global_transform = Transform3D(b, f.origin + Vector3(0, 0.6, 0))
	idx = route.index_at(at_d)


func _apply_quality(level: String) -> void:
	var low := level == "low"
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if low else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 0.6 if low else 1.0
	vp.msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if low else Viewport.SCREEN_SPACE_AA_DISABLED
	set_meta("quality", level)


# ----------------------------------------------------------------------------- per frame
func _physics_process(delta: float) -> void:
	if not ready_to_drive:
		return
	var _p0 := Time.get_ticks_usec()
	_track()
	Prof.add("game_track", _p0)
	if jeep.autopilot and walker == null:
		_autopilot()
	_events(delta)
	_fuel(delta)
	_surface_t -= delta
	if _surface_t <= 0.0 and walker == null:
		_surface_t = 0.1
		jeep.set_surface(_surface_under(jeep.global_position))


## Tarmac, shoulder or open ground under the car, from the same road graph the GPS uses.
func _surface_under(p: Vector3) -> String:
	if resort and resort.visible and p.distance_to(resort.global_position) < WorldBuilder.EMBED_HALF + 10.0:
		return "asphalt"                    # the resort's own drives and paths
	if towns:
		for b in towns.bunks:
			if p.distance_to(b["pos"]) < 12.0:
				return "asphalt"
	if not graph.has_graph():
		return "asphalt" if absf(lateral) < Route.ROAD_HALF + 0.5 else "ground"
	return graph.surface_at(p, idx)


# ----------------------------------------------------------------------------- debug mode (F3)
func _set_debug(on: bool) -> void:
	debug_mode = on
	ui_debug.visible = on
	if _debug_lines:
		_debug_lines.visible = on
	if on and _debug_report == "":
		_validate_roads()
	_debug_t = 0.0


func _validate_roads() -> void:
	if not graph.has_graph():
		_debug_report = "No road graph (old map data)."
		return
	var res := graph.validate(func(x: float, z: float) -> float: return terrain.height_at(x, z))
	_debug_report = res["report"]
	print(_debug_report)
	var probs: Array = res["problems"]
	for k in mini(probs.size(), 12):
		print("  ! %s at (%.0f, %.0f)" % [probs[k]["what"], probs[k]["pos"].x, probs[k]["pos"].z])
	if probs.size() > 12:
		print("  … %d more" % (probs.size() - 12))
	set_meta("road_problems", probs)


func _debug_update(delta: float) -> void:
	var p: Vector3 = walker.global_position if walker else jeep.global_position
	ui_debug.text = "DEBUG   F3 close · F6 +1 h · F7 weather · F8 skip to resort\nfps %d   pos %.0f, %.0f, %.0f   d %.0f m   surface %s\n%s" % [
		Engine.get_frames_per_second(), p.x, p.y, p.z, d, jeep.surface, _debug_report]
	_debug_t -= delta
	if _debug_t > 0.0:
		return
	_debug_t = 1.0
	# road graph near you: streets (cyan), highway (yellow), junctions (white), dead ends (orange),
	# validator problems (red posts)
	if _debug_lines == null:
		_debug_lines = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.no_depth_test = true
		_debug_lines.material_override = m
		_debug_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_lines)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var up := Vector3(0, 0.6, 0)
	var r2 := 350.0 * 350.0
	for st in graph.streets:
		var pts: PackedVector3Array = st["pts"]
		if Vector2(pts[0].x - p.x, pts[0].z - p.z).length_squared() > r2:
			continue
		for k in pts.size() - 1:
			im.surface_set_color(Color(0.2, 0.9, 1.0))
			im.surface_add_vertex(pts[k] + up)
			im.surface_add_vertex(pts[k + 1] + up)
	var i0: int = maxi(idx - 200, 0)
	for i in range(i0, mini(idx + 200, route.pts.size() - 1)):
		im.surface_set_color(Color(1.0, 0.85, 0.2))
		im.surface_add_vertex(route.pts[i] + up)
		im.surface_add_vertex(route.pts[i + 1] + up)
	for id in graph.nodes:
		var nd: Dictionary = graph.nodes[id]
		var q: Vector3 = nd["pos"]
		if Vector2(q.x - p.x, q.z - p.z).length_squared() > r2:
			continue
		var col := Color.WHITE
		match nd["kind"]:
			"highway": col = Color(1.0, 0.85, 0.2)
			"end": col = Color(1.0, 0.5, 0.1)
			"edge": col = Color(0.7, 0.4, 1.0)
		im.surface_set_color(col)
		im.surface_add_vertex(q)
		im.surface_add_vertex(q + Vector3(0, 3.0, 0))
	for pr in get_meta("road_problems", []):
		var q: Vector3 = pr["pos"]
		if Vector2(q.x - p.x, q.z - p.z).length_squared() > r2:
			continue
		im.surface_set_color(Color(1, 0.1, 0.1))
		im.surface_add_vertex(q)
		im.surface_add_vertex(q + Vector3(0, 8.0, 0))
	im.surface_end()
	_debug_lines.mesh = im


## Diesel: burns with throttle and revs while you're in the car. Low tank → GPS to the nearest bunk.
func _fuel(delta: float) -> void:
	if walker == null:
		sim.burn(delta, jeep.pedal(), jeep.rpm)
	var empty: bool = sim.fuel <= 0.0
	if empty and not jeep.out_of_fuel:
		_message("Out of diesel! Coast to the side. (F8 / R still work; a fuel bunk is marked on the map.)", 7.0)
	jeep.out_of_fuel = empty
	if sim.fuel_frac() < Sim.LOW_FUEL and not _fuel_warned and towns and not towns.bunks.is_empty():
		_fuel_warned = true
		var b := _nearest_bunk()
		_message("Fuel low. GPS set to %s." % b["name"], 6.0)
		if map_ui:
			map_ui.set_destination(b["pos"], b["name"])
	elif sim.fuel_frac() > Sim.LOW_FUEL + 0.05:
		_fuel_warned = false


func _nearest_bunk() -> Dictionary:
	var best := {}
	var bd := INF
	for b in towns.bunks:
		var dd: float = jeep.global_position.distance_to(b["pos"])
		if dd < bd:
			bd = dd
			best = b
	return best


## [E] actions near you: fill up at a fuel bunk, chai at the viewpoint stall. Shown as the objective.
func _interactions() -> void:
	_prompt = ""
	var p: Vector3 = walker.global_position if walker else jeep.global_position
	if walker and Engine.get_process_frames() % 10 == 0:
		var near := _vehicle_near(p)
		_near_vehicle = "" if near.is_empty() else ("your " if near["type"] in ["current", "left"] else "the ") + Jeep.SPECS[near["kind"]]["name"]
	if walker and _near_vehicle != "":
		_prompt = "Press F: drive %s" % _near_vehicle
	var still := walker != null or absf(jeep.speed) < 1.0
	var action := Callable()
	if towns:
		for b in towns.bunks:
			if p.distance_to(b["pos"]) > 15.0:
				continue
			if not sim.is_open("Petrol bunk"):
				_prompt = "%s is closed (%s)" % [b["name"], sim.hours_text("Petrol bunk")]
			elif jeep.global_position.distance_to(b["pos"]) > 15.0:
				_prompt = "Bring the car onto the forecourt to fill up"
			elif sim.fuel_frac() > 0.97:
				_prompt = "Tank's full"
			elif not still:
				_prompt = "Stop at the pump to fill up"
			else:
				var litres := minf(Sim.TANK_L - sim.fuel, sim.money / Sim.DIESEL_RS)
				_prompt = "Press E: fill up, %.0f L diesel for ₹%s" % [litres, _rupees(int(ceil(litres * Sim.DIESEL_RS)))]
				action = func():
					var paid := sim.money
					var got := sim.refuel()
					_message("Filled %.1f L at ₹%.0f/L · paid ₹%s · wallet ₹%s" % [got, Sim.DIESEL_RS,
						_rupees(paid - sim.money), _rupees(sim.money)], 5.0)
			break
	if _prompt == "" and not tea_break and p.distance_to(props.tea_stall_pos) < 14.0 and still:
		if not sim.is_open("Viewpoint"):
			_prompt = "The tea stall is shut (%s)" % sim.hours_text("Viewpoint")
		else:
			_prompt = "Press E for a chai break (₹20)"
			action = func():
				tea_break = true
				sim.money -= 20
				_message("Chai break, ₹20. Below you, the plains have vanished under a sea of clouds.", 6.0)
	if action.is_valid() and (Input.is_action_just_pressed("interact") or (jeep.autopilot and _prompt.contains("chai"))):
		action.call()
		_prompt = ""


static func _rupees(n: int) -> String:
	# Indian grouping: 1,23,456
	var neg := n < 0
	var s := str(absi(n))
	if s.length() > 3:
		var head := s.substr(0, s.length() - 3)
		var out := s.substr(s.length() - 3)
		while head.length() > 2:
			out = head.substr(head.length() - 2) + "," + out
			head = head.substr(0, head.length() - 2)
		s = head + "," + out
	return ("-" if neg else "") + s


# ----------------------------------------------------------------------------- save / load
func _save_game(announce: bool) -> void:
	if jeep == null or not ready_to_drive:
		return
	var y := jeep.global_basis.get_euler().y
	sim.save({"d": d, "pos": [jeep.global_position.x, jeep.global_position.y, jeep.global_position.z], "yaw": y,
		"checkpost": checkpost, "tea_break": tea_break, "elephants_done": elephants.state == "done" or d > route.marks["elephants"],
		"lights": jeep.lights_on, "vehicle": jeep.vehicle})
	if announce:
		_message("Game saved · Day %d, %s" % [sim.day, Sim.clock_text(sim.minute)], 3.0)


var _saved_pose := {}
var left_behind: Array = []        # cars you got out of and left parked: {kind, body}


# ----------------------------------------------------------------------------- GTA-style: drive anything
## The nearest vehicle you could get into from where you stand: your current car, ones you left
## parked, parked vehicles on the streets, town traffic and highway traffic.
func _vehicle_near(p: Vector3) -> Dictionary:
	var best := {}
	var reach := func(kind: String) -> float:
		return 2.6 + float(Jeep.SPECS[kind].get("len", 4.6)) * 0.5
	var consider := func(kind: String, pos: Vector3, xf: Transform3D, type: String, ref) -> void:
		if not Jeep.SPECS.has(kind):
			return
		var dd := pos.distance_to(p)
		if dd < reach.call(kind) and (best.is_empty() or dd < best["dist"]):
			best.clear()
			best.merge({"kind": kind, "xf": xf, "type": type, "ref": ref, "dist": dd})
	consider.call(jeep.vehicle, jeep.global_position, jeep.global_transform, "current", null)
	for lb in left_behind:
		var b: Node3D = lb["body"]
		consider.call(lb["kind"], b.global_position, b.global_transform, "left", lb)
	if towns:
		for life in towns.lives:
			var e: Dictionary = life.nearest(p, 7.0)
			if not e.is_empty():
				var xf: Transform3D = e["xf"]
				if e["model"] in ["bike", "scooter"]:
					xf = Transform3D(xf.basis, xf.origin)
				consider.call(e["model"], xf.origin, xf, "parked", [life, e])
	if town_traffic:
		for c in town_traffic.cars:
			if c["si"] >= 0:
				var b: Node3D = c["body"]
				consider.call(c["kind"], b.global_position, b.global_transform, "towntraffic", c)
	for v in traffic.vehicles:
		if not v["taken"]:
			var b: Node3D = v["body"]
			var kind: String = v["model"] if Jeep.SPECS.has(v["model"]) else ("lorry" if v["model"] == "lorry" else v["model"])
			consider.call(kind, b.global_position, b.global_transform, "traffic", v)
	return best


## Swap cars: leave the one you were driving parked where it stands, take the new one off the
## street (or out of the traffic) and drive it from exactly where it was.
func _take_vehicle(c: Dictionary) -> void:
	var old_kind: String = jeep.vehicle
	var old_xf: Transform3D = jeep.global_transform
	if c["type"] != "current":
		_park_left_behind(old_kind, old_xf)
		match c["type"]:
			"left":
				left_behind.erase(c["ref"])
				(c["ref"]["body"] as Node).queue_free()
			"parked":
				c["ref"][0].take(c["ref"][1])
			"towntraffic":
				town_traffic.take(c["ref"])
			"traffic":
				traffic.take(c["ref"])
		jeep.configure(c["kind"])
		var xf: Transform3D = c["xf"]
		jeep.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3(0, 0.4, 0))
		jeep.linear_velocity = Vector3.ZERO
		jeep.angular_velocity = Vector3.ZERO
		idx = route.nearest_global(jeep.global_position)
		_message("You're driving the %s." % Jeep.SPECS[c["kind"]]["name"], 3.0)


func _park_left_behind(kind: String, xf: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Parked_%s" % kind
	var sp: Dictionary = Jeep.SPECS[kind]
	var boxes: Array = sp.get("boxes", [])
	if boxes.is_empty():
		var L: float = sp.get("len", 4.6)
		var W: float = sp.get("w", 1.9)
		var H: float = sp.get("h", 1.7)
		boxes = [[Vector3(W, H * 0.75, L), Vector3(0, H * 0.45 + 0.1, 0)]]
	for bx in boxes:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = bx[0]
		cs.shape = shape
		cs.position = bx[1]
		body.add_child(cs)
	body.add_child(jeep.visual_for(kind))
	add_child(body)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin - xf.basis.y.normalized() * 0.02)
	left_behind.append({"kind": kind, "body": body})

## Called from _start when the menu asked to continue. Returns the saved road distance or -1.
func _load_game() -> float:
	var data := sim.load_save()
	if data.is_empty():
		return -1.0
	checkpost = String(data.get("checkpost", "closed"))
	tea_break = bool(data.get("tea_break", false))
	if bool(data.get("elephants_done", false)):
		elephants.state = "done"
	_saved_pose = data
	return float(data.get("d", 12.0))


var _bench_frames := 0
var _bench_proc := 0.0
var _bench_phys := 0.0
var _bench_hidden := false


## The resort keeps particles, lights and animated water running even out of sight, so it only exists
## to the renderer and the scene tree while you are within RESORT_STREAM of it (it's lost in the mist
## from further anyway). Its colliders stay, so nothing can fall through on arrival.
const RESORT_STREAM := 1600.0

func _stream_far() -> void:
	if resort == null or Engine.get_process_frames() % 15 != 0:
		return
	var focus: Vector3 = walker.global_position if walker else jeep.global_position
	var on := focus.distance_to(resort.global_position) < RESORT_STREAM
	if resort.visible != on:
		resort.visible = on
		resort.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## --bench : stand still (or --autodrive), average fps over 6–16 s, print rendering stats, quit.
## --hide=Towns,Details,... : hide top-level nodes to find what costs the frames.
func _bench(delta: float) -> void:
	if not _bench_hidden:
		_bench_hidden = true
		for a in args:
			if a.begins_with("--hide="):
				for n in a.get_slice("=", 1).split(","):
					var node := get_node_or_null(n)
					print("HIDE %s -> %s" % [n, node])
					if node:
						node.visible = false
	if _t > 6.0 and Prof.frames == 0:
		Prof.totals.clear()
		Prof.frames = 1
	if _t > 6.0:
		_bench_frames += 1
		_bench_proc += Performance.get_monitor(Performance.TIME_PROCESS)
		_bench_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	if _t > 16.0:
		var vp := get_viewport()
		var info := func(t: int, k: int) -> int: return vp.get_render_info(t, k)
		print("BENCH d=%.0f fps=%.1f process=%.1fms physics=%.1fms draws=%d (shadow %d) objects=%d (shadow %d) prims=%.2fM vram=%.0fMB" % [d,
			_bench_frames / (_t - 6.0), _bench_proc / _bench_frames * 1000.0, _bench_phys / _bench_frames * 1000.0,
			info.call(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			info.call(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			info.call(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
			info.call(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
			info.call(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME) / 1e6,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6])
		print("PROF " + Prof.report(_bench_frames))
		var counts := []
		for c in get_children():
			var n := c.find_children("*", "GeometryInstance3D", true, false).size()
			if n > 0:
				counts.append("%s %d" % [c.name, n])
		print("NODES " + "  ".join(counts))
		get_tree().quit()


func _process(delta: float) -> void:
	if not ready_to_drive:
		return
	_t += delta
	if "--bench" in args:
		_bench(delta)
	if "--trace" in args and int(_t / 5.0) != int((_t - delta) / 5.0):
		print("TRACE t=%4.0f d=%5.0f/%.0f g=%s rpm=%4.0f v=%5.1f lat=%5.1f stage=%s cp=%s ele=%s y=%.1f fps=%d fuel=%.2fL %s surf=%s" % [_t, d, route.length, jeep.gear_name(), jeep.rpm,
			jeep.speed, lateral, stage_id, checkpost, elephants.state, jeep.global_position.y - route.pts[idx].y,
			Engine.get_frames_per_second(), sim.fuel, Sim.clock_text(sim.minute), jeep.surface])
		if town_traffic:
			print("  TOWNTRAFFIC %s" % town_traffic.summary())
		if pedestrians:
			var vis := 0
			for q in pedestrians.people:
				if q["si"] >= 0:
					vis += 1
			print("  PEOPLE active %d / %d" % [vis, pedestrians.people.size()])
			for q in pedestrians.people.slice(0, 3):
				print("    person %s scale %.3f pos %s dist %.0f state %s" % [q["node"].name, q["node"].scale.x, q["pos"], q["pos"].distance_to(jeep.global_position), q["state"]])
	var _p1 := Time.get_ticks_usec()
	if walker == null:
		_update_camera(delta)
	_update_hud()
	_update_mist(delta)
	_stream_far()
	if town_traffic:
		town_traffic.player = walker if walker else jeep
	if pedestrians:
		pedestrians.player = walker if walker else jeep
	_interactions()
	_autosave_t += delta
	if _autosave_t > AUTOSAVE_SECS and not arrived:
		_autosave_t = 0.0
		_save_game(false)
	if Input.is_action_just_pressed("quick_save"):
		_save_game(true)
	Prof.add("game_hud_cam", _p1)
	if Input.is_action_just_pressed("enter_exit"):
		_toggle_on_foot()
	if Input.is_action_just_pressed("open_map") and map_ui:
		map_ui.toggle_full()
		if not map_ui.full_open and walker:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.is_action_just_pressed("camera_view"):
		cam_mode = (cam_mode + 1) % 3
		jeep.set_cockpit(cam_mode == 1)
	if Input.is_action_just_pressed("reset_vehicle"):
		_place_jeep(maxf(d, 5.0))
		_message("Back on the road.")
	if Input.is_action_just_pressed("debug_mode"):
		_set_debug(not debug_mode)
	if debug_mode:
		_debug_update(delta)
		if Input.is_action_just_pressed("debug_time"):
			sim.minute = fmod(sim.minute + 60.0, 1440.0)
			_sky_t = 0.0
		if Input.is_action_just_pressed("debug_weather"):
			var ws: Array = Sim.WEATHER.keys()
			sim.weather = ws[(ws.find(sim.weather) + 1) % ws.size()]
			sim.wx = Sim.WEATHER[sim.weather].duplicate()
			_sky_t = 0.0
	if Input.is_action_just_pressed("toggle_help"):
		ui_help.modulate.a = 1.0 - ui_help.modulate.a
	if Input.is_action_just_pressed("toggle_quality"):
		_apply_quality("high" if get_meta("quality", "low") == "low" else "low")
		_message("Quality: %s" % String(get_meta("quality")).to_upper())
	if Input.is_action_just_pressed("skip_drive") and debug_mode:
		if resort and walker == null:
			_place_jeep(route.length - 90.0)          # jump to the approach, the resort is right ahead
			_message("Skipped to Kotagiri. The Mist Village gate is just ahead.")
		elif resort == null:
			_arrive(true)
	if Input.is_action_just_pressed("back_to_menu"):
		_save_game(false)
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file("res://scenes/start_menu.tscn")
	_screenshots()
	_snap()


func _track() -> void:
	var p: Vector3 = jeep.global_position
	idx = route.nearest(p, idx)
	var off: Vector3 = p - route.pts[idx]
	d = clampf(route.dist[idx] + off.dot(route.tangents[idx]), 0.0, route.length)
	lateral = off.dot(route.left(idx))
	traffic.jeep_d = d
	traffic.jeep_lat = lateral
	traffic.jeep_pos = p
	var st: Dictionary = route.stage_at(d)
	if st["id"] != stage_id:
		stage_id = st["id"]
		_show_title(st["title"], st["subtitle"])


func _update_camera(delta: float) -> void:
	var jt: Transform3D = jeep.global_transform
	var fwd: Vector3 = jeep.forward()
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var face := Basis.looking_at(fwd, Vector3.UP)
	match cam_mode:
		0:
			# Euro Truck-style chase: further back, lower, and lagging smoothly through corners.
			# It drops back a little under acceleration, closes in and dips under braking,
			# widens with speed, and never ends up inside a wall or building.
			var acc: float = (jeep.speed - _cam_prev_speed) / maxf(delta, 0.001)
			_cam_prev_speed = jeep.speed
			_cam_acc = lerpf(_cam_acc, clampf(acc, -8.0, 4.0), 1.0 - exp(-delta * 3.0))
			var back := 8.6 + _cam_acc * 0.12
			var want := jt.origin - flat * back + Vector3.UP * (2.9 - minf(_cam_acc, 0.0) * -0.04)
			cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-delta * 2.4))
			var ground: float = terrain.height_at(cam.global_position.x, cam.global_position.z)
			cam.global_position.y = maxf(cam.global_position.y, ground + 1.2)
			var pivot := jt.origin + Vector3.UP * 1.6
			var q := PhysicsRayQueryParameters3D.create(pivot, cam.global_position)
			q.exclude = [jeep.get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				cam.global_position = hit["position"] + (pivot - hit["position"]).normalized() * 0.4
			cam.look_at(jt.origin + Vector3.UP * 1.4 + flat * 4.0 + Vector3.DOWN * maxf(-_cam_acc, 0.0) * 0.05)
			cam.fov = lerpf(cam.fov, 66.0 + clampf(absf(jeep.speed) / 30.0, 0.0, 1.0) * 8.0, 1.0 - exp(-delta * 1.5))
		1:
			cam.fov = 68.0
			# driver's eyes, tilted slightly down towards the gauges
			cam.global_transform = Transform3D(face * Basis(Vector3.RIGHT, deg_to_rad(-4.0)), jt * jeep.seat)
		2:
			cam.global_transform = Transform3D(face, jt * (Vector3(0, 0.98, 1.25) if jeep.is_coupe else Vector3(0, 1.32, 1.6)))
		4:
			# debug side view (--cam=4): 4.5 m off the left flank, at rider height
			cam.global_position = jt.origin + jt.basis.x.normalized() * 4.5 + Vector3.UP * 1.2
			cam.look_at(jt.origin + Vector3.UP * 0.9)
		3:
			# debug overhead (--cam=3): high above, looking down at the jeep
			cam.global_position = jt.origin - flat * 70.0 + Vector3(0.0, 75.0, 0.0)
			cam.look_at(jt.origin + flat * 120.0)


# ----------------------------------------------------------------------------- events
func _events(delta: float) -> void:
	# forest check post: stop at the boom and the guard lifts it
	var cp: float = route.marks["checkpost"]
	if checkpost == "closed":
		if d > cp - 28.0 and d < cp and absf(jeep.speed) < 0.8:
			stop_time += delta
			if stop_time > 1.2:
				checkpost = "open"
				props.open_barrier()
				_message("Guard: “Good morning! No plastic up the hill, and go slow — elephants about.”", 6.0)
		elif d > cp + 3.0:
			checkpost = "skipped"
			_message("You drove round the check post! The guard is shouting after you.", 5.0)
	# elephants
	var em: float = route.marks["elephants"]
	if elephants.state == "idle" and d > em - 170.0:
		elephants.start()
		_message("Elephants on the road ahead! Stop and wait. Don't honk, don't get close.", 6.0)
	if elephants.state == "crossing":
		var near: float = elephants.nearest_distance(jeep.global_position)
		if near < 22.0 and absf(jeep.speed) > 1.5 and _t - elephant_warn_at > 3.0:
			elephant_warn_at = _t
			too_close += 1
			_message("Too close! Back off and let the herd cross.", 3.0)
		if jeep.honked and near < 70.0:
			_message("The matriarch flaps her ears. They don't like the horn. Stay quiet.", 4.0)
	# arrival
	if not arrived and d > route.length - 50.0:
		_arrive(false)


func _elephants_ok() -> bool:
	return elephants.state != "crossing"


func _arrive(skipped: bool) -> void:
	if arrived:
		return
	arrived = true
	if resort:
		# same world: you drive straight in, and can get out and walk around
		_show_title("The Mist Village", "Where the mist slows you down.")
		_message("Welcome to The Mist Village! Park, then press F to get out and explore.", 8.0)
		print("ARRIVED d=%.0f too_close=%d checkpost=%s tea=%s" % [d, too_close, checkpost, tea_break])
		if "--quit-at-end" in args:
			get_tree().quit()
		return
	jeep.autopilot = true
	jeep.in_throttle = 0.0
	jeep.in_brake = 1.0
	var tw := create_tween()
	tw.tween_property(ui_fade, "color:a", 1.0, 1.2 if not skipped else 0.4)
	tw.tween_callback(func():
		ui_title.text = "THE MIST VILLAGE"
		ui_subtitle.text = "Where the mist slows you down."
		ui_title.modulate.a = 1.0
		ui_subtitle.modulate.a = 1.0
	)
	tw.tween_interval(2.5)
	tw.tween_callback(func():
		print("ARRIVED d=%.0f too_close=%d checkpost=%s tea=%s" % [d, too_close, checkpost, tea_break])
		if "--quit-at-end" in args:
			get_tree().quit()
		else:
			Engine.time_scale = 1.0
			Engine.set_meta("arrived_by_jeep", true)
			get_tree().change_scene_to_file(RESORT_SCENE)
	)


## F: step out of the jeep (driver's door, on the right) or climb back in when close to it.
func _toggle_on_foot() -> void:
	if walker == null:
		if absf(jeep.speed) > 1.0:
			_message("Stop the car first.")
			return
		walker = Walker.new()
		walker.name = "OnFoot"
		add_child(walker)
		var door: Vector3 = jeep.global_position - jeep.global_basis.x * 1.6     # driver's door, on the right
		walker.spawn_at(door + Vector3(0, 0.4, 0), jeep.global_position + jeep.forward() * 12.0)
		walker.activate()
		jeep.autopilot = true                       # parked: no inputs, handbrake on
		jeep.in_throttle = 0.0
		jeep.in_brake = 0.0
		jeep.in_steer = 0.0
		jeep.in_handbrake = true
		jeep.set_cockpit(false)
		_message("On foot. WASD walk · Shift run · Space jump · mouse to look · F by the car to drive again.", 6.0)
	else:
		var near := _vehicle_near(walker.global_position)
		if near.is_empty():
			_message("Walk up to a vehicle (yours, a parked one or one in traffic) and press F.")
			return
		_take_vehicle(near)
		walker.deactivate()
		walker.queue_free()
		walker = null
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		cam.make_current()
		jeep.in_handbrake = false
		jeep.autopilot = "--autodrive" in args
		jeep.set_cockpit(cam_mode == 1)


## Sun, sky, fog and rain from the clock, the weather and the altitude (the ghat's cloud band).
func _update_mist(delta: float) -> void:
	var alt: float = route.real_altitude(d)
	sim.advance(delta, alt)
	var gs: float = route.marks["ghat_start"]
	var ge: float = route.marks["ghat_end"]
	var kot: Dictionary = route.stages[-2]
	var f := smoothstep(gs + (ge - gs) * 0.45, ge + 100.0, d) * (1.0 - 0.55 * smoothstep(kot["start"], kot["start"] + 350.0, d))
	if route.is_real:
		f = smoothstep(1050.0, 1350.0, alt) * (1.0 - 0.6 * smoothstep(1650.0, 1850.0, alt))
	var wx: Dictionary = sim.wx
	f = maxf(f, wx["fog"] * (0.55 if alt < 1000.0 else 0.9))
	var cloud: float = wx["cloud"]
	var sd: Vector3 = sim.sun_dir()
	var day: float = sim.daylight()
	if "--nofog" in args:
		f = 0.0
	env.fog_density = 0.0 if "--nofog" in args else lerpf(0.00015, 0.011, f) + cloud * 0.0004 + wx["rain"] * 0.0015
	var fog_col := Color(0.74, 0.74, 0.76).lerp(Color(0.80, 0.82, 0.85), f).lerp(Color(0.62, 0.64, 0.67), cloud * 0.6)
	env.fog_light_color = fog_col * lerpf(0.06, 1.0, day)
	env.ambient_light_energy = lerpf(0.05, 0.5, day) * (1.0 - 0.25 * cloud)
	# sun by day, a faint blue moon opposite it by night
	var up := sd.y > -0.04
	var light_dir: Vector3 = sd if up else Vector3(-sd.x, maxf(-sd.y, 0.25), sd.z).normalized()
	if absf(light_dir.dot(Vector3.UP)) < 0.999:
		sun.basis = Basis.looking_at(-light_dir, Vector3.UP)
	if up:
		sun.light_color = Color(1.0, 0.72, 0.5).lerp(Color(1.0, 0.96, 0.9), smoothstep(0.08, 0.45, sd.y))
		sun.light_energy = 1.6 * smoothstep(-0.04, 0.15, sd.y) * (1.0 - 0.7 * cloud) * lerpf(1.0, 0.35, f)
	else:
		sun.light_color = Color(0.55, 0.65, 1.0)
		sun.light_energy = 0.07 * (1.0 - 0.8 * cloud)
	sun.shadow_enabled = sun.light_energy > 0.2
	# the sky shader's radiance map is re-baked whenever it changes, so only every couple of seconds
	_sky_t -= delta
	if _sky_t <= 0.0:
		_sky_t = 2.0
		sky_mat.set_shader_parameter("sun_dir", sd)
		sky_mat.set_shader_parameter("night_mix", 1.0 - day)
		sky_mat.set_shader_parameter("noon_mix", smoothstep(0.2, 0.55, sd.y))
		sky_mat.set_shader_parameter("overcast", cloud)
		sky_mat.set_shader_parameter("day_strength", lerpf(1.5, 1.05, cloud))
		if towns:
			towns.set_night(1.0 - day)
			towns.set_wet(sim.wet)
		road.set_wet(sim.wet)
		if resort and resort.visible:
			# same rule as the resort's own day/night: lamps and glowing windows brighten after dark
			for l in resort.lamps:
				(l[0] as Light3D).light_energy = l[1] * lerpf(1.0, 1.8, 1.0 - day)
			for e in resort.emissive:
				(e[0] as BaseMaterial3D).emission_energy_multiplier = e[1] * lerpf(1.0, 2.0, 1.0 - day)
		jeep.set_grip(wx["grip"])
	_update_rain(delta)
	var dark: bool = f > 0.5 or day < 0.35 or wx["rain"] > 0.5
	if dark and not jeep.lights_on and not jeep.autopilot and walker == null and _t - _dark_hint_t > 25.0:
		_dark_hint_t = _t
		_message("It's getting hard to see: press L for headlights.", 4.0)
	if jeep.autopilot and dark and not jeep.lights_on:
		jeep.set_lights(true)


## Rain streaks in a box that follows the camera, plus a soft hiss.
func _build_rain() -> void:
	rain = GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 7000
	rain.lifetime = 1.1
	rain.local_coords = false
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24.0, 0.5, 24.0)
	pm.direction = Vector3(0.08, -1.0, 0.0)
	pm.spread = 3.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 19.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.78, 0.82, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	rain.draw_pass_1 = q
	rain.emitting = false
	add_child(rain)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.2
	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.stream = gen
	_rain_audio.volume_db = -80.0
	add_child(_rain_audio)
	_rain_audio.play()
	_rain_pb = _rain_audio.get_stream_playback()


func _update_rain(_delta: float) -> void:
	var r: float = sim.wx["rain"]
	rain.emitting = r > 0.05
	if rain.emitting:
		rain.amount_ratio = r
		var c: Vector3 = cam.global_position
		rain.global_position = c + Vector3(0, 14.0, 0) + jeep.linear_velocity * 0.6
	_rain_audio.volume_db = linear_to_db(maxf(r * 0.35, 0.0001))
	if _rain_pb:
		for i in _rain_pb.get_frames_available():
			_rain_lp = lerpf(_rain_lp, randf_range(-1.0, 1.0), 0.35)       # low-passed noise: a hiss, not static
			_rain_pb.push_frame(Vector2(_rain_lp, _rain_lp) * 0.5)


# ----------------------------------------------------------------------------- autopilot (testing)
func _autopilot() -> void:
	if arrived:
		return
	var fwd: Vector3 = jeep.forward()
	var leftv := Vector3.UP.cross(fwd).normalized()
	var look := clampf(absf(jeep.speed) * 1.1, 7.0, 20.0)
	var target: Vector3 = route.frame_at(d + look, Route.LANE).origin
	var to := target - jeep.global_position
	var ang := atan2(to.dot(leftv), to.dot(fwd))
	jeep.in_steer = clampf(ang * 2.2, -1.0, 1.0)
	var v: float = STAGE_SPEED.get(stage_id, 10.0)
	var t0: Vector3 = route.frame_at(d).basis.z
	var t1: Vector3 = route.frame_at(d + 35.0).basis.z
	var bend := acos(clampf(t0.dot(t1), -1.0, 1.0))
	if bend > 0.9:
		v = minf(v, 5.0)
	elif bend > 0.4:
		v = minf(v, 8.0)
	var cp: float = route.marks["checkpost"]
	if checkpost == "closed" and d < cp:
		v = minf(v, maxf(0.0, (cp - 10.0 - d) * 0.5))
	if not _elephants_ok() and d < route.marks["elephants"] + 10.0:
		v = minf(v, maxf(0.0, (route.marks["elephants"] - 45.0 - d) * 0.5))
	var tea: Vector3 = props.tea_stall_pos
	if not tea_break and jeep.global_position.distance_to(tea) < 40.0:
		v = minf(v, maxf(0.0, jeep.global_position.distance_to(tea) - 8.0) * 0.4)
	for b in road.bumps:
		if b > d - 2.0 and b < d + 35.0:
			v = minf(v, 3.5)                    # slow for speed breakers
	var gap: float = traffic.gap_ahead(d, lateral)
	v = minf(v, maxf(0.0, (gap - 8.0) * 0.6))
	var err: float = v - jeep.speed
	jeep.in_throttle = clampf(err * 0.35, 0.0, 1.0)
	jeep.in_brake = clampf(-err * 0.3, 0.0, 1.0) if err < -0.5 else 0.0
	if v < 0.1 and absf(jeep.speed) < 0.3:
		jeep.in_brake = 0.0
		jeep.in_handbrake = true
	else:
		jeep.in_handbrake = false


## --snap=/abs/file.jpg : drive (autopilot) for 5 s from --start, save one screenshot, quit.
var _snapped := false
func _snap() -> void:
	# --onfoot : after 2 s stop, get out, and stand at the resort's own spawn looking into the grounds
	if "--onfoot" in args and walker == null and _t > 2.0 and resort:
		jeep.linear_velocity = Vector3.ZERO
		jeep.speed = 0.0
		_toggle_on_foot()
		var sp: Array = resort.data["spawn"]["pos"]
		walker.spawn_at(resort.to_global(Vector3(sp[0], sp[1], sp[2])), resort.to_global(Vector3(0, 8, 0)))
	# --gps : set a GPS route to the resort; --openmap : also open the full map
	if "--gps" in args and map_ui and map_ui.gps_target.is_empty() and _t > 1.0:
		map_ui.set_destination(route.frame_at(route.length).origin, "The Mist Village")
		print("GPS test: %d points, %.1f km to the resort" % [map_ui.gps.size(), map_ui.Nav.length(map_ui.gps) / 1000.0])
		if "--openmap" in args:
			map_ui.toggle_full()
			map_ui.full_scale = 0.02
	# --swaptest : out of the SUV → into the spare coupe → out → into the nearest parked street vehicle
	if "--swaptest" in args:
		var step := int(get_meta("swap_step", 0))
		var plan := [[3.0, "out"], [3.6, "to_spare"], [4.2, "in"], [7.0, "out"], [7.6, "to_parked"], [8.2, "in"]]
		if step < plan.size() and _t > plan[step][0]:
			set_meta("swap_step", step + 1)
			match plan[step][1]:
				"out":
					jeep.linear_velocity = Vector3.ZERO
					jeep.speed = 0.0
					if walker == null:
						_toggle_on_foot()
				"to_spare":
					if walker and not left_behind.is_empty():
						walker.global_position = (left_behind[0]["body"] as Node3D).global_position + Vector3(2.0, 1.0, 0)
				"to_parked":
					var best: Dictionary = {}
					var bd := INF
					for life in towns.lives:
						for e in life.entries:
							var dd: float = (e["xf"].origin as Vector3).distance_to(jeep.global_position)
							if not e["taken"] and dd < bd and not e["model"] in ["bike", "scooter"]:
								bd = dd
								best = e
					if walker and not best.is_empty():
						walker.global_position = best["xf"].origin + Vector3(1.5, 1.0, 0)
				"in":
					if walker:
						_toggle_on_foot()
					print("SWAP now driving %s (left behind: %d)" % [jeep.vehicle, left_behind.size()])
	# --save : write the save file 3 s in (tests the Continue path)
	if "--save" in args and _t > 3.0 and not has_meta("saved_once"):
		set_meta("saved_once", true)
		_save_game(true)
		print("SAVED d=%.0f day=%d %s money=%d fuel=%.1f" % [d, sim.day, Sim.clock_text(sim.minute), sim.money, sim.fuel])
	if _snapped or _t < 5.0:
		return
	for a in args:
		if a.begins_with("--snap="):
			_snapped = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg(a.get_slice("=", 1), 0.85)
			print("SNAP d=%.0f alt=%.0f fps=%d" % [d, route.real_altitude(d), Engine.get_frames_per_second()])
			get_tree().quit()


func _screenshots() -> void:
	if shots.is_empty():
		return
	var dir := ""
	for a in args:
		if a.begins_with("--shots="):
			dir = a.get_slice("=", 1)
	if dir == "":
		return
	if d >= shots[0][0]:
		var s: Array = shots.pop_front()
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_jpg("%s/%02d_%s.jpg" % [dir, 20 - shots.size(), s[1]], 0.85)
		print("SHOT %s d=%.0f fps=%d speed=%.1f" % [s[1], d, Engine.get_frames_per_second(), jeep.speed])


# ----------------------------------------------------------------------------- HUD
func _label(parent: Control, size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	ui_speed = _label(root, 44)
	ui_speed.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 28)
	ui_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui_speed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ui_speed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ui_speed.offset_bottom = -58
	ui_meta = _label(root, 18, Color(0.95, 0.92, 0.85))
	ui_meta.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 28)
	ui_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui_meta.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ui_meta.grow_vertical = Control.GROW_DIRECTION_BEGIN

	ui_objective = _label(root, 18, Color(1.0, 0.9, 0.55))
	ui_objective.position = Vector2(28, 24)

	ui_status = _label(root, 17, Color(0.97, 0.95, 0.9))
	ui_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 24)
	ui_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var title_box := VBoxContainer.new()
	title_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_box.position.y = 70
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_box)
	ui_title = _label(title_box, 46, Color(0.98, 0.93, 0.84))
	ui_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_subtitle = _label(title_box, 20, Color(0.95, 0.9, 0.8))
	ui_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_title.modulate.a = 0.0
	ui_subtitle.modulate.a = 0.0

	ui_message = _label(root, 22)
	ui_message.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ui_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_message.position.y = -150
	ui_message.custom_minimum_size = Vector2(900, 0)
	ui_message.offset_left = -450
	ui_message.offset_right = 450
	ui_message.offset_top = -170
	ui_message.offset_bottom = -120
	ui_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_message.modulate.a = 0.0

	ui_help = _label(root, 15, Color(1, 1, 1, 0.85))
	ui_help.text = "W/S accelerate · brake/reverse   A/D steer   Space handbrake   H horn   L headlights   M manual gears (X up, Z down)   , . indicators   / hazards\nV camera (chase · cockpit · bonnet)   R back on road   E interact   F get out / in   Tab map + GPS   F5 save   F10 save + menu   F1 hide"
	ui_help.position = Vector2(28, 50)
	ui_debug = _label(root, 14, Color(0.6, 1.0, 0.7))
	ui_debug.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 24)
	ui_debug.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui_debug.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ui_debug.position.y = 130
	ui_debug.visible = false
	ui_help.visible = false

	ui_fade = ColorRect.new()
	ui_fade.color = Color(0, 0, 0, 0)
	ui_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ui_fade)
	# title card sits above the fade for the arrival
	title_box.move_to_front()

	ui_loading = ColorRect.new()
	(ui_loading as ColorRect).color = Color(0.03, 0.04, 0.05)
	ui_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui_loading)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	ui_loading.add_child(box)
	var t := _label(box, 52, Color(0.98, 0.93, 0.84))
	t.text = "THE ROAD UP"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := _label(box, 20, Color(0.85, 0.82, 0.75))
	s.text = "Coimbatore → Mettupalayam → Kotagiri"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_progress = _label(box, 16, Color(0.7, 0.7, 0.7))
	ui_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _update_hud() -> void:
	ui_speed.text = "On foot" if walker else "%d km/h   %s%s" % [roundi(absf(jeep.speed) * 3.6), jeep.gear_name(), "  M" if jeep.manual else ""]
	var alt: float = route.real_altitude(d)
	var hp := 0
	for i in route.hairpin_idx:
		if route.dist[i] < d:
			hp += 1
	var extra := ""
	if stage_id == "ghat":
		extra = "   ·   Hairpin %d / %d" % [hp, route.hairpin_idx.size()]
	var left_km: float = (route.real_length - route.real_distance(d)) / 1000.0 if route.is_real else (route.length - d) / route.length * 68.0
	ui_meta.text = "Kotagiri %d km   ·   %s m   ·   %d °C%s" % [ceili(left_km), _thousands(roundi(alt)), roundi(route.temperature(alt)), extra]
	ui_objective.text = _prompt if _prompt != "" else _objective()
	var bars := roundi(sim.fuel_frac() * 10.0)
	ui_status.text = "%s  ·  Day %d\n%s\n₹ %s\nDiesel %s%s %d%%" % [Sim.clock_text(sim.minute), sim.day,
		Sim.WEATHER[sim.weather]["label"], _rupees(sim.money), "▮".repeat(bars), "▯".repeat(10 - bars), roundi(sim.fuel_frac() * 100.0)]
	ui_status.modulate = Color(1, 0.45, 0.35) if sim.fuel_frac() < Sim.LOW_FUEL else Color.WHITE


func _objective() -> String:
	if walker:
		return "Explore on foot · F next to the car to drive"
	if arrived and resort:
		return "You've arrived. Press F to get out and explore The Mist Village"
	if checkpost == "closed" and d > route.marks["checkpost"] - 250.0:
		return "Stop at the forest check post"
	if elephants.state == "crossing":
		return "Wait for the herd to cross"
	match stage_id:
		"coimbatore", "plains":
			return "Drive to Mettupalayam, keeping left"
		"mettupalayam", "foothills":
			return "Head for the Kotagiri ghat road"
		"ghat":
			return "Climb the nine hairpins. Uphill traffic has right of way"
		"mist":
			return "Optional: stop at the tea stall · Drive on to Kotagiri" if not tea_break else "Drive on to Kotagiri"
		_:
			return "Find The Mist Village gate"


func _thousands(n: int) -> String:
	return "%d,%03d" % [n / 1000, n % 1000] if n >= 1000 else str(n)


func _show_title(title: String, subtitle: String) -> void:
	ui_title.text = title.to_upper()
	ui_subtitle.text = subtitle
	if _title_tween:
		_title_tween.kill()
	_title_tween = create_tween()
	_title_tween.tween_property(ui_title, "modulate:a", 1.0, 0.8)
	_title_tween.parallel().tween_property(ui_subtitle, "modulate:a", 1.0, 0.8)
	_title_tween.tween_interval(3.5)
	_title_tween.tween_property(ui_title, "modulate:a", 0.0, 1.2)
	_title_tween.parallel().tween_property(ui_subtitle, "modulate:a", 0.0, 1.2)


func _message(text: String, secs := 4.0) -> void:
	ui_message.text = text
	if _msg_tween:
		_msg_tween.kill()
	_msg_tween = create_tween()
	_msg_tween.tween_property(ui_message, "modulate:a", 1.0, 0.3)
	_msg_tween.tween_interval(secs)
	_msg_tween.tween_property(ui_message, "modulate:a", 0.0, 0.8)
