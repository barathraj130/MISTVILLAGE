extends Node3D
## Test bed for the Coimbatore streaming world (scenes/city_test.tscn), separate from the drive.
##   --auto            fly north from Gandhipuram at ~90 km/h, logging fps / tiles / memory, then quit
##   --shots=/abs/dir  screenshots at 15 s, 45 s and 80 s (with --auto)
##   (no flags)        free camera: WASD move, Q/E down/up, Shift fast, mouse look (click to capture)

const Streamer := preload("res://scripts/city/city_streamer.gd")
const MB := preload("res://scripts/drive/mesh_builder.gd")

var streamer
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
	streamer.set_materials(_road_material(), MB.cc0_material("dry_grass", 6.0, 0.95, false), bm, walk, kerb)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	cam.position = Vector3(0, cam_y, 0)
	add_child(cam)
	cam.make_current()
	streamer.target = cam
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	get_viewport().scaling_3d_scale = 0.67


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
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
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
	return sm


func _process(dt: float) -> void:
	t += dt
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


func _log_and_shots(dt: float) -> void:
	if int(t) != int(t - dt) and int(t) % 5 == 0:
		print("CITY t=%3ds fps=%3d tiles=%3d built=%4d unloaded=%4d blds=%d designed=%d mem=%dMB vmem=%dMB draws=%d pos=(%.0f,%.0f)" % [
			int(t), Engine.get_frames_per_second(), streamer.stats["loaded"], streamer.stats["built"], streamer.stats["unloaded"],
			streamer.stats["buildings"], streamer.stats["designed"],
			int(OS.get_static_memory_usage() / 1048576), int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), cam.position.x, cam.position.z])
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
	if e is InputEventMouseButton and e.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * 0.003
		pitch = clampf(pitch - e.relative.y * 0.003, -1.3, 1.3)
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
