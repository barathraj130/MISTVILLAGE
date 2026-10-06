extends Node3D
## Builds THE MIST VILLAGE at runtime from res://assets/scene.json,
## which export_godot.py writes next to the glTF models.
##
## Keys: WASD move · Shift run · Space jump · N golden hour ↔ night · C replay intro · Esc main menu · Alt free mouse

const SCENE_JSON := "res://assets/scene.json"
const Player := preload("res://scripts/player.gd")
const Cinematic := preload("res://scripts/cinematic.gd")
const SKY_SHADER := preload("res://shaders/sky.gdshader")
const MIST_SHADER := preload("res://shaders/mist_sheet.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
const GLOW_SHADER := preload("res://shaders/particle_glow.gdshader")

## Blender watts → Godot light energy (physical light units are off in this project).
const WATT_TO_ENERGY := 1.0 / 40.0
const SUN_SCALE := 0.4
const EMISSION_SCALE := 0.08
## Vegetation is split into MultiMesh chunks so culling and LOD work per area.
const CHUNK_NEAR := 48.0          # within CHUNK_NEAR_RADIUS: where you can walk
const CHUNK_FAR := 256.0
const CHUNK_NEAR_RADIUS := 900.0
## Trees and shrubs swap to their ~200-triangle LOD beyond this distance (chunk centre).
const LOD_DISTANCE := 90.0
const TREE_COLLISION_RADIUS := 900.0
## Draw distance per vegetation asset (prefix match; missing = always drawn).
const VIS_RANGE := {"grass": 60.0, "fern": 90.0, "wild_flowers": 90.0, "hydrangea": 110.0,
	"shrub": 220.0, "hedgerow": 400.0, "boulder": 250.0}
## Wind sway strength per asset (prefix match; missing = gentle tree sway).
const WIND := {"grass": 0.12, "fern": 0.08, "wild_flowers": 0.1, "hydrangea": 0.05,
	"shrub": 0.04, "hedgerow": 0.03}
const MIST_PUFF_COLOR := Color(0.9, 0.92, 0.95, 0.07)

@export var play_intro := true
## Embedded in the drive world: build only the resort grounds (site, detailed ground, plants
## within the grounds, lamps, campfire, mist puffs), no sky, sun, mountains, player or UI.
@export var embedded := false
const EMBED_HALF := 158.0          # the resort's detailed ground covers ±160 m around its centre
var road_south := Vector3.ZERO     # resort road where it leaves the grounds (for the drive to join)
var road_dir := Vector3.FORWARD    # direction along the resort road, heading north into the grounds
var _hgrid := {}                   # resort ground heights on a 4 m grid (local coords)

var data: Dictionary
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var fire_light: OmniLight3D
var fire_energy := 0.0
var fire_noise := FastNoiseLite.new()
var lamps: Array = []        # [Light3D, golden-hour energy]
var emissive: Array = []     # [BaseMaterial3D, golden-hour emission energy]
var mist_mats: Array = []    # mist sheet ShaderMaterials + mist puff StandardMaterial3Ds
var night := 0.0             # 0 = golden hour, 1 = night
var night_target := 0.0
var player: Player
var cinematic: Cinematic
var blob: GradientTexture2D
var fade: ColorRect
var hud: Label
var quality := ""                 # "low" or "high"
var _t := 0.0
var _bench_frames := 0
var _bench_cpu := 0.0
var _bench_gpu := 0.0


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SCENE_JSON))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Could not read %s. Run export_godot.py in Blender first." % SCENE_JSON)
		return
	data = parsed
	blob = _blob_texture()
	if embedded:
		_build_lights()
		_load_models()
		_build_vegetation()
		_build_fog_and_mist()
		_build_campfire()
		_build_mist_puffs()
		_index_ground()
		_find_road()
		return
	_setup_input()
	_build_environment()
	_build_lights()
	# profiling switches: godot --path . -- --no-intro --no-veg --no-vfog --no-shadow --no-mist --no-ssao
	var args := OS.get_cmdline_user_args()
	_load_models()
	if not "--no-veg" in args:
		_build_vegetation()
	if not "--no-mist" in args:
		_build_fog_and_mist()
	_build_campfire()
	_build_mist_puffs()
	env.volumetric_fog_enabled = not "--no-vfog" in args
	env.ssao_enabled = not "--no-ssao" in args
	if "--no-shadow" in args and sun:
		sun.shadow_enabled = false
	if "--no-intro" in args or Engine.has_meta("arrived_by_jeep"):
		play_intro = false            # you've just driven up; start at the gate
	if "--no-lights" in args:
		for l in lamps:
			(l[0] as Light3D).visible = false
	if "--no-glow" in args:
		env.glow_enabled = false
	if "--no-msaa" in args:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	if "--no-fireshadow" in args and fire_light:
		fire_light.shadow_enabled = false
	if "--bench" in args:
		print("viewport=%s screen_scale=%.1f" % [get_viewport().get_visible_rect().size, DisplayServer.screen_get_scale()])
	for a in args:
		if a.begins_with("--scale="):
			get_viewport().scaling_3d_scale = float(a.get_slice("=", 1))
		if a.begins_with("--lodbias="):
			for n in get_node("Vegetation").get_children():
				(n as GeometryInstance3D).lod_bias = float(a.get_slice("=", 1))
	_spawn_player()
	_build_ui()
	# integrated / Apple M1-class GPUs start on Low; override with -- --quality=high
	var q := "low" if RenderingServer.get_video_adapter_name().contains("Apple M1") \
		or RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU else "high"
	for a in args:
		if a.begins_with("--quality="):
			q = a.get_slice("=", 1)
	_apply_quality(q)
	_apply_time_of_day()
	if play_intro and data.has("cinematic"):
		_start_intro()
	else:
		_on_intro_finished()


func _process(delta: float) -> void:
	_t += delta
	if embedded:
		if fire_light:
			fire_light.light_energy = fire_energy * (1.0 + 0.25 * fire_noise.get_noise_1d(_t * 40.0))
		return
	# godot --path . -- --bench --no-intro  → average FPS over 10–25 s, then quit
	if "--bench" in OS.get_cmdline_user_args():
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		if _t > 10.0:
			_bench_frames += 1
			_bench_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
			_bench_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		if _t > 25.0:
			print("BENCH avg_fps=%.1f draws=%d render_cpu=%.1fms gpu=%.1fms process=%.1fms physics=%.1fms prims=%.1fM" % [
				_bench_frames / (_t - 10.0),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				_bench_cpu / _bench_frames, _bench_gpu / _bench_frames,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6])
			get_tree().quit()
	# godot --path . -- --fps-log  → one line per second: time, FPS, draw calls, shot
	if int(_t) != int(_t - delta) and "--fps-log" in OS.get_cmdline_user_args():
		print("t=%3ds  fps=%3d  draws=%5d  %s" % [int(_t), Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"shot %d" % (cinematic.frames[mini(int(cinematic.time * cinematic.fps), cinematic.frames.size() - 1)][0])
				if cinematic and cinematic.playing else "player"])
	if Input.is_action_just_pressed("back_to_menu") and not (cinematic and cinematic.playing):   # Esc during the intro only skips it
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/start_menu.tscn")
	if Input.is_action_just_pressed("toggle_quality"):
		_apply_quality("high" if quality == "low" else "low")
	if Input.is_action_just_pressed("toggle_night"):
		night_target = 1.0 - night_target
	if Input.is_action_just_pressed("replay_intro") and cinematic and not cinematic.playing:
		_start_intro()
	if night != night_target:
		night = move_toward(night, night_target, delta / 3.0)
		_apply_time_of_day()
	if fire_light:
		var n := fire_noise.get_noise_1d(_t * 40.0)
		fire_light.light_energy = fire_energy * lerpf(1.0, 1.6, night) * (1.0 + 0.25 * n)


# ----------------------------------------------------------------------------- helpers
static func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func col(a: Array) -> Color:
	return Color(a[0], a[1], a[2])


static func quat(a: Array) -> Quaternion:
	return Quaternion(a[0], a[1], a[2], a[3]).normalized()


static func lookup(key: String, table: Dictionary, fallback: float) -> float:
	for k in table:
		if key.begins_with(k):
			return table[k]
	return fallback


static func node_name(s: String) -> String:
	return s.validate_node_name()


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE])
	_add_action("run", [KEY_SHIFT])
	_add_action("toggle_night", [KEY_N])
	_add_action("replay_intro", [KEY_C])
	_add_action("skip_intro", [KEY_SPACE, KEY_ENTER, KEY_ESCAPE])
	_add_action("release_mouse", [KEY_ALT])
	_add_action("toggle_quality", [KEY_F2])
	_add_action("back_to_menu", [KEY_F10, KEY_ESCAPE])


func _gradient_texture(stops: Array) -> GradientTexture1D:
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(s[0])
		var c: Array = s[1]
		colors.append(Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0))
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	t.width = 256
	return t


func _curve_texture(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


func _blob_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0, 0, 0, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


# ----------------------------------------------------------------------------- sky + environment
func _build_environment() -> void:
	var sky_data: Dictionary = data.get("sky", {})
	var presets: Dictionary = data.get("presets", {})
	var golden: Dictionary = presets.get("golden", {})
	var night_p: Dictionary = presets.get("night", {})
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("day_gradient", _gradient_texture(
		sky_data.get("gradient", [[0.0, [0.55, 0.52, 0.52]], [1.0, [0.16, 0.3, 0.62]]])))
	sky_mat.set_shader_parameter("night_gradient", _gradient_texture(
		night_p.get("sky_gradient", [[0.0, [0.0, 0.0, 0.0]], [1.0, [0.002, 0.004, 0.012]]])))
	sky_mat.set_shader_parameter("sun_dir", v3(sky_data.get("sun_direction_to_sun", [0.0, 0.12, 1.0])).normalized())
	sky_mat.set_shader_parameter("day_strength", float(golden.get("sky_strength", 1.6)))
	sky_mat.set_shader_parameter("night_strength", float(night_p.get("sky_strength", 1.0)))

	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	# distance haze: ridges at 17 km stay faintly visible, the site stays clear
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.74, 0.78)
	env.fog_density = 0.00008
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.25
	env.fog_sun_scatter = 0.25
	# volumetric fog: only the FogVolumes add density
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 140.0

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# ----------------------------------------------------------------------------- lights
func _build_lights() -> void:
	var root := Node3D.new()
	root.name = "Lights"
	add_child(root)
	for l in data.get("lights", []):
		var w: float = l["energy_w"]
		var nm := node_name(l["name"])
		if embedded and l["type"] == "SUN":
			continue                       # the drive world has its own sun
		match l["type"]:
			"SUN":
				var d := DirectionalLight3D.new()
				d.name = nm
				d.quaternion = quat(l["rot"])
				d.light_color = col(l["color"])
				d.light_energy = w * SUN_SCALE
				d.light_angular_distance = float(l.get("angle_deg", 0.5))
				if nm.contains("Fill"):
					d.shadow_enabled = false
					fill = d
				else:
					d.shadow_enabled = true
					d.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
					d.directional_shadow_max_distance = 150.0
					sun = d
				d.set_meta("golden_energy", d.light_energy)
				d.set_meta("golden_color", d.light_color)
				root.add_child(d)
			"POINT":
				var o := OmniLight3D.new()
				o.name = nm
				o.position = v3(l["pos"])
				o.light_color = col(l["color"])
				o.light_energy = w * WATT_TO_ENERGY
				o.omni_range = clampf(sqrt(w) * 1.6, 3.0, 30.0)
				o.light_size = float(l.get("radius", 0.05))
				o.shadow_enabled = w >= 100.0 and not embedded   # only the fire, and not inside the drive world
				root.add_child(o)
				if l.has("flicker"):
					fire_light = o
					fire_energy = o.light_energy
				else:
					lamps.append([o, o.light_energy])
			"AREA", "SPOT":
				var s := SpotLight3D.new()
				s.name = nm
				s.position = v3(l["pos"])
				s.quaternion = quat(l["rot"])
				s.light_color = col(l["color"])
				s.light_energy = w * WATT_TO_ENERGY
				s.spot_range = clampf(sqrt(w) * 2.0, 3.0, 25.0)
				s.spot_angle = 70.0
				s.light_size = float(l.get("size", 0.2)) * 0.5
				root.add_child(s)
				lamps.append([s, s.light_energy])
	if sun == null and not embedded:
		sun = DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-10, 50, 0)
		sun.shadow_enabled = true
		sun.set_meta("golden_energy", 1.5)
		sun.set_meta("golden_color", Color(1.0, 0.6, 0.33))
		root.add_child(sun)
	fire_noise.frequency = 0.3
	fire_noise.fractal_octaves = 2


# ----------------------------------------------------------------------------- site, terrain, valley, mountains
func _load_models() -> void:
	var models: Dictionary = data.get("models", {})
	var hints: Dictionary = data.get("materials", {})
	var vertex_colored := StandardMaterial3D.new()
	vertex_colored.vertex_color_use_as_albedo = true
	vertex_colored.roughness = 0.92
	var seen := {}
	for key in (["terrain", "site"] if embedded else ["terrain", "site", "valley", "mountains"]):
		if not models.has(key):
			continue
		var ps := load("res://assets/" + models[key]) as PackedScene
		if ps == null:
			push_warning("Missing model: %s" % models[key])
			continue
		var inst := ps.instantiate()
		inst.name = key.capitalize()
		if embedded and key == "terrain":
			# keep only the detailed ground around the resort; the drive map supplies the rest
			for child in inst.get_children():
				if not String(child.name).begins_with("terrain_near"):
					child.free()
		add_child(inst)
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if key == "terrain" or key == "mountains":
				# shading was baked to vertex colours by the exporter
				mi.material_override = vertex_colored
				if embedded:
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if key == "mountains" or mi.name.begins_with("terrain_far"):
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				continue
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s) as BaseMaterial3D
				if mat == null or seen.has(mat):
					continue
				seen[mat] = true
				if mat.emission_enabled:
					mat.emission_energy_multiplier *= EMISSION_SCALE
					emissive.append([mat, mat.emission_energy_multiplier])
				if hints.get(mat.resource_name, {}).get("kind", "") == "glass":
					mat.roughness = 0.03


# ----------------------------------------------------------------------------- embedding in the drive world
## Heights of the resort's detailed ground on a 4 m grid, for blending the drive map into it.
func _index_ground() -> void:
	# the ground mesh is 0.2 m apart in the middle and ~15 m at the edges: thin it to one point
	# per 2 m, then bucket the points in 16 m cells for an inverse-distance lookup
	var seen := {}
	for mi in find_children("terrain_near*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := global_transform.affine_inverse() * m.global_transform
		for s in m.mesh.get_surface_count():
			var verts: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := xf * v
				var k2 := Vector2i(roundi(p.x / 2.0), roundi(p.z / 2.0))
				if seen.has(k2):
					continue
				seen[k2] = true
				var c := Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))
				if not _hgrid.has(c):
					_hgrid[c] = PackedVector3Array()
				_hgrid[c].append(p)


## Resort ground height at a local point (NAN outside the grounds): inverse-distance over nearby mesh points.
func ground_local(x: float, z: float) -> float:
	var cx := floori(x / 16.0)
	var cz := floori(z / 16.0)
	var num := 0.0
	var den := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := Vector2i(cx + dx, cz + dz)
			if not _hgrid.has(c):
				continue
			for p in _hgrid[c]:
				var d2: float = (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z)
				if d2 < 0.01:
					return p.y
				if d2 > 900.0:
					continue
				var w := 1.0 / (d2 * d2)
				num += w * p.y
				den += w
	return num / den if den > 0.0 else NAN


## Clip the 780 m resort road to the grounds and find where it leaves them (south end).
func _find_road() -> void:
	var south := []
	var north := []
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var nm := String(mi.name).to_lower()
		if not (nm.begins_with("mountain road") or nm.begins_with("road kerbs")):
			continue
		var mesh := ArrayMesh.new()
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var keep := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var ok := true
				for q in 3:
					var v := verts[idx[t + q]]
					if maxf(absf(v.x), absf(v.z)) > EMBED_HALF - 2.0:
						ok = false
						break
				if ok:
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			if keep.is_empty():
				continue
			arr[Mesh.ARRAY_INDEX] = keep
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mi.mesh.surface_get_material(s))
			if nm.begins_with("mountain road"):
				for i in keep:
					var v := verts[i]
					if v.z > EMBED_HALF - 14.0:
						south.append(v)
					elif v.z > EMBED_HALF - 60.0 and v.z < EMBED_HALF - 40.0:
						north.append(v)
		mi.mesh = mesh
		for body in mi.find_children("*", "CollisionShape3D", true, false):
			(body as CollisionShape3D).shape = mesh.create_trimesh_shape()
	if south.is_empty() or north.is_empty():
		var sp: Array = data.get("spawn", {}).get("pos", [0.0, 0.0, 0.0])
		road_south = Vector3(sp[0], sp[1], EMBED_HALF - 8.0)
		road_dir = Vector3(0, 0, -1)
		return
	var a := Vector3.ZERO
	for v in south:
		a += v
	a /= south.size()
	var b := Vector3.ZERO
	for v in north:
		b += v
	b /= north.size()
	road_south = a
	road_dir = Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()


# ----------------------------------------------------------------------------- vegetation (44k instances)
func _prepare_asset_mesh(key: String, mesh: Mesh, hints: Dictionary) -> void:
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s) as BaseMaterial3D
		if src == null or hints.get(src.resource_name, {}).get("kind", "") != "leaf":
			continue
		var m := ShaderMaterial.new()
		m.shader = FOLIAGE_SHADER
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
		m.set_shader_parameter("albedo_color", src.albedo_color)
		m.set_shader_parameter("wind_strength", lookup(key, WIND, 0.02))
		mesh.surface_set_material(s, m)


func _load_asset_mesh(path: String, key: String, hints: Dictionary) -> Mesh:
	var ps := load("res://assets/" + path) as PackedScene
	if ps == null:
		push_warning("Missing vegetation model: %s" % path)
		return null
	var node := ps.instantiate()
	var found := node.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = null
	if not found.is_empty():
		mesh = (found[0] as MeshInstance3D).mesh
		_prepare_asset_mesh(key, mesh, hints)
	node.free()
	return mesh


## One MultiMesh chunk, drawn between begin and end metres from the camera (0 = no limit).
func _multimesh(id: String, mesh: Mesh, xfs: Array, colors: PackedColorArray, begin: float, end: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = id
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if begin > 0.0:
		mmi.visibility_range_begin = begin
		mmi.visibility_range_begin_margin = 10.0
	if end > 0.0:
		mmi.visibility_range_end = end
		mmi.visibility_range_end_margin = 10.0 if begin == 0.0 and end == LOD_DISTANCE else end * 0.15
	return mmi


func _build_vegetation() -> void:
	var veg: Dictionary = data.get("vegetation", {})
	var assets: Dictionary = veg.get("assets", {})
	var hints: Dictionary = data.get("materials", {})
	var meshes := {}
	var lod_meshes := {}
	for key in assets:
		var mesh := _load_asset_mesh(assets[key]["model"], key, hints)
		if mesh:
			meshes[key] = mesh
		if assets[key].has("lod_model"):
			var lod := _load_asset_mesh(assets[key]["lod_model"], key, hints)
			if lod:
				lod_meshes[key] = lod

	# bucket instances by asset + grid cell
	var buckets := {}
	var colliders: Array = []
	for layer in veg.get("layers", []):
		var inst: Dictionary = layer["instances"]
		for key in inst:
			if not meshes.has(key):
				continue
			var collide: bool = assets[key].get("collide", false)
			for it in inst[key]:
				var p := Vector3(it[0], it[1], it[2])
				if embedded and maxf(absf(p.x), absf(p.z)) > EMBED_HALF:
					continue                       # outside the resort grounds: the drive map plants those
				var cs := (96.0 if embedded else CHUNK_NEAR) if Vector2(p.x, p.z).length() < CHUNK_NEAR_RADIUS else CHUNK_FAR
				var id := "%s_%d_%d_%d" % [key, int(cs), floori(p.x / cs), floori(p.z / cs)]
				var xf := Transform3D(Basis(Vector3.UP, it[3]).scaled(Vector3.ONE * float(it[4])), p)
				if not buckets.has(id):
					buckets[id] = [key, []]
				buckets[id][1].append(xf)
				if collide and p.length() < TREE_COLLISION_RADIUS:
					colliders.append([key, p, float(it[4])])

	var root := Node3D.new()
	root.name = "Vegetation"
	add_child(root)
	var rng := RandomNumberGenerator.new()
	var is_tree := func(k: String) -> bool: return assets[k].get("collide", false) and not k.begins_with("boulder")
	for id in buckets:
		var key: String = buckets[id][0]
		var xfs: Array = buckets[id][1]
		var colors := PackedColorArray()
		for xf in xfs:
			# per-plant tint replaces Blender's Object Info ▸ Random
			rng.seed = hash(xf.origin)
			var v := rng.randf_range(0.8, 1.12)
			colors.append(Color(v * rng.randf_range(0.92, 1.06), v, v * rng.randf_range(0.9, 1.04)))
		var vr := lookup(key, VIS_RANGE, 0.0)
		var tree: bool = is_tree.call(key)
		if lod_meshes.has(key):
			# full detail near, ~200 triangles beyond LOD_DISTANCE
			var near := _multimesh(id, meshes[key], xfs, colors, 0.0, LOD_DISTANCE)
			near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tree else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(near)
			if vr == 0.0 or vr > LOD_DISTANCE:
				root.add_child(_multimesh(id + "_lod", lod_meshes[key], xfs, colors, LOD_DISTANCE, vr))
		else:
			var mmi := _multimesh(id, meshes[key], xfs, colors, 0.0, vr)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tree and not key.begins_with("far_") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)

	# trunks and boulders you can't walk through
	var body := StaticBody3D.new()
	body.name = "VegetationColliders"
	add_child(body)
	for c in colliders:
		var key: String = c[0]
		var p: Vector3 = c[1]
		var s: float = c[2]
		var r: float = float(assets[key].get("trunk_radius", 0.3)) * s
		if r <= 0.0:
			continue
		var shape := CollisionShape3D.new()
		if key.begins_with("boulder"):
			var sph := SphereShape3D.new()
			sph.radius = r
			shape.shape = sph
			shape.position = p
		else:
			var cyl := CylinderShape3D.new()
			cyl.radius = r
			cyl.height = 4.0 * s
			shape.shape = cyl
			shape.position = p + Vector3.UP * cyl.height * 0.5
		body.add_child(shape)
	print("Vegetation: %d chunks, %d colliders" % [buckets.size(), colliders.size()])


# ----------------------------------------------------------------------------- fog volumes + mist sheets
func _build_fog_and_mist() -> void:
	var root := Node3D.new()
	root.name = "Mist"
	add_child(root)
	if embedded:
		return                             # the drive world handles fog and cloud layers
	for f in data.get("fog_volumes", []):
		var fv := FogVolume.new()
		fv.name = node_name(f["name"])
		fv.size = v3(f["size"])
		fv.position = v3(f["center"])
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		var small := fv.size.y < 10.0
		var fm := FogMaterial.new()
		fm.density = float(f["density"]) * (4.0 if small else 2.0)
		fm.albedo = col(f["color"])
		fm.height_falloff = 0.9 if small else 0.08
		fm.edge_fade = 0.35
		var noise := FastNoiseLite.new()
		noise.frequency = 0.08
		noise.fractal_octaves = 3
		var nt := NoiseTexture3D.new()
		nt.width = 64
		nt.height = 16 if small else 32
		nt.depth = 64
		nt.seamless = true
		nt.noise = noise
		fm.density_texture = nt
		fv.material = fm
		root.add_child(fv)

	var tex_noise := FastNoiseLite.new()
	tex_noise.frequency = 0.01
	tex_noise.fractal_octaves = 5
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.seamless = true
	noise_tex.noise = tex_noise
	for m in data.get("mist_sheets", []):
		var sz: Array = m["size_xz"]
		var drift: Array = m.get("drift_per_s", [3.1, 0.0, -1.3])
		var plane := PlaneMesh.new()
		plane.size = Vector2(sz[0], sz[1])
		var mat := ShaderMaterial.new()
		mat.shader = MIST_SHADER
		mat.set_shader_parameter("noise_tex", noise_tex)
		mat.set_shader_parameter("mist_color", col(m["color"]))
		mat.set_shader_parameter("density", float(m["density"]))
		mat.set_shader_parameter("noise_scale", float(m["noise_scale"]))
		mat.set_shader_parameter("drift", Vector2(drift[0], drift[2]))
		var mi := MeshInstance3D.new()
		mi.name = node_name(m["name"])
		mi.mesh = plane
		mi.material_override = mat
		mi.position = v3(m["center"])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mist_mats.append(mat)


# ----------------------------------------------------------------------------- campfire
func _glow_particles(amount: int, lifetime: float, intensity: float, size: Vector2) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	var q := QuadMesh.new()
	q.size = size
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("blob", blob)
	m.set_shader_parameter("intensity", intensity)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 8, 4))
	return p


func _build_campfire() -> void:
	var cf = data.get("campfire")
	if cf == null:
		return
	var c := v3(cf["center"])

	var flames := _glow_particles(64, 0.75, 6.0, Vector2(0.42, 0.62))
	flames.name = "CampfireFlames"
	flames.position = c + Vector3(0, 0.05, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.8, 0)
	pm.angle_min = -30.0
	pm.angle_max = 30.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	pm.scale_curve = _curve_texture([Vector2(0.0, 0.5), Vector2(0.25, 1.0), Vector2(1.0, 0.1)])
	pm.color_ramp = _gradient_texture([[0.0, [1.0, 0.65, 0.25, 1.0]], [0.45, [1.0, 0.28, 0.03, 0.9]],
		[1.0, [0.9, 0.05, 0.0, 0.0]]])
	flames.process_material = pm
	add_child(flames)

	var em = null
	for p in data.get("particles", []):
		if p["kind"] == "embers":
			em = p
	var embers := _glow_particles(40, 2.0, 12.0, Vector2(0.035, 0.035))
	embers.name = "CampfireEmbers"
	embers.position = c + Vector3(0, 0.3, 0)
	embers.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 10, 8))
	var epm := ParticleProcessMaterial.new()
	epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	epm.emission_box_extents = Vector3(0.3, 0.1, 0.3)
	epm.direction = Vector3.UP
	epm.spread = 25.0
	epm.initial_velocity_min = 0.6
	epm.initial_velocity_max = float(em["up_velocity"]) + 0.3 if em else 1.5
	epm.gravity = Vector3(0, 0.3, 0)
	epm.turbulence_enabled = true
	epm.turbulence_noise_strength = 1.5
	epm.turbulence_noise_scale = 2.0
	epm.scale_min = 0.5
	epm.scale_max = 1.2
	epm.color_ramp = _gradient_texture([[0.0, [1.0, 0.45, 0.08, 1.0]], [0.7, [1.0, 0.18, 0.02, 1.0]],
		[1.0, [0.6, 0.05, 0.0, 0.0]]])
	embers.process_material = epm
	add_child(embers)


func _build_mist_puffs() -> void:
	for p in data.get("particles", []):
		if p["kind"] != "mist_puffs":
			continue
		var fps := float(data.get("cinematic", {}).get("fps", 24))
		var area: Array = p["emit_size_xz"]
		var g := GPUParticles3D.new()
		g.name = "MistPuffs"
		g.amount = int(p["count"])
		g.lifetime = float(p["lifetime_frames"]) / fps
		g.preprocess = g.lifetime
		g.position = v3(p["center"])
		g.visibility_aabb = AABB(Vector3(-40, -5, -35), Vector3(80, 15, 70))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(float(area[0]) * 0.5, 0.6, float(area[1]) * 0.5)
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = 0.03
		pm.initial_velocity_max = 0.08
		pm.gravity = Vector3.ZERO
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.3
		pm.turbulence_noise_scale = 20.0
		pm.scale_min = 0.6
		pm.scale_max = 1.4
		pm.color_ramp = _gradient_texture([[0.0, [1, 1, 1, 0]], [0.2, [1, 1, 1, 1]], [0.8, [1, 1, 1, 1]], [1.0, [1, 1, 1, 0]]])
		g.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2.ONE * float(p["size"]) * 2.0
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = blob
		m.albedo_color = MIST_PUFF_COLOR
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = 1.5
		q.material = m
		g.draw_pass_1 = q
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		mist_mats.append(m)


# ----------------------------------------------------------------------------- player, UI, intro
func _spawn_player() -> void:
	player = Player.new()
	player.name = "Player"
	add_child(player)
	var sp: Dictionary = data.get("spawn", {})
	player.spawn_at(v3(sp.get("pos", [0.0, 5.0, 0.0])), v3(sp.get("look_at", [0.0, 0.0, 0.0])))


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = Label.new()
	hud.text = _hud_text()
	hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hud.add_theme_constant_override("outline_size", 4)
	hud.visible = false
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(fade)


func _start_intro() -> void:
	if cinematic == null:
		cinematic = Cinematic.new()
		cinematic.name = "Cinematic"
		add_child(cinematic)
		cinematic.setup(data["cinematic"], data.get("title", {}))
		cinematic.finished.connect(_on_intro_finished)
	player.deactivate()
	hud.visible = false
	cinematic.play()


func _on_intro_finished() -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.5)
	tw.tween_callback(func():
		player.activate()
		hud.visible = true
		hud.modulate.a = 1.0
	)
	tw.tween_property(fade, "color:a", 0.0, 0.8)
	tw.tween_interval(10.0)
	tw.tween_property(hud, "modulate:a", 0.35, 1.5)


# ----------------------------------------------------------------------------- quality presets
func _hud_text() -> String:
	return "WASD move · Shift run · Space jump · N day / night · C replay intro · F2 quality: %s · Esc / F10 main menu · Alt free mouse" \
		% quality.to_upper()


## Low keeps every feature (mist, fog, shadows, all plants) and cuts resolution-bound extras.
## Measured on an M1 (8 GB) at the spawn point: Low ≈ 35 fps, High ≈ 11 fps.
func _apply_quality(level: String) -> void:
	quality = level
	var low := level == "low"
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if low else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 0.6 if low else 1.0
	vp.msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if low else Viewport.SCREEN_SPACE_AA_DISABLED
	env.ssao_enabled = not low
	var veg := get_node_or_null("Vegetation")
	if veg:
		for n in veg.get_children():
			(n as GeometryInstance3D).lod_bias = 0.2 if low else 1.0
	if hud:
		hud.text = _hud_text()


# ----------------------------------------------------------------------------- golden hour ↔ night
func _apply_time_of_day() -> void:
	if sun:
		sun.light_energy = lerpf(sun.get_meta("golden_energy"), 0.08, night)
		var gc: Color = sun.get_meta("golden_color")
		sun.light_color = gc.lerp(Color(0.55, 0.65, 1.0), night)    # moonlight
	if fill:
		var fe: float = fill.get_meta("golden_energy")
		fill.light_energy = lerpf(fe, fe * 0.24, night)
	sky_mat.set_shader_parameter("night_mix", night)
	env.ambient_light_energy = lerpf(0.4, 0.2, night)
	env.fog_light_color = Color(0.72, 0.74, 0.78).lerp(Color(0.03, 0.04, 0.07), night)
	# mist_village.py doubles lamp emission and raises lamp power at night
	for e in emissive:
		(e[0] as BaseMaterial3D).emission_energy_multiplier = e[1] * lerpf(1.0, 2.0, night)
	for l in lamps:
		(l[0] as Light3D).light_energy = l[1] * lerpf(1.0, 1.8, night)
	var k := lerpf(1.0, 0.06, night)
	for m in mist_mats:
		if m is ShaderMaterial:
			m.set_shader_parameter("light", k)
		elif m is StandardMaterial3D:
			m.albedo_color = Color(MIST_PUFF_COLOR.r * k, MIST_PUFF_COLOR.g * k, MIST_PUFF_COLOR.b * k, MIST_PUFF_COLOR.a)
