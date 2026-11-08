extends Node3D
## Weather in the city (the mountain drive's own, scripts/drive/sim.gd WEATHER, on the same save):
##   rain       streaks round the camera (none indoors), its hiss, a grey sky, less sun, more haze
##   wet roads  the roads soak in a minute or so of rain and dry slowly after: the asphalt darkens and shines
##              (road_surface.gdshader `wet`), the pavements and open ground darken, tyres hold less (grip
##              × 0.72 soaked, as on the ghat), the wipers run, and the traffic drives a little slower
## In the story the day is the story's: clear unless a step says "weather": "rain" (or "cloudy", "clear"), so a
## scene never meets rain it wasn't written for. In free play it changes by itself as on the plains.
## --weather=rain (or cloudy) for tests: the roads already soaked.

const Sim := preload("res://scripts/drive/sim.gd")
const SOAKED_GRIP := 0.72                    # (sim.gd WEATHER "rain": the same tyres on the same wet asphalt)

var city
var story_weather := "clear"
var _rain: GPUParticles3D
var _audio: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _lp := 0.0
var _free_left := 0.0                        # free play: real seconds until the weather may change
var _base := {}                              # the materials' dry values


func _ready() -> void:
	_build_rain()
	_free_left = randf_range(240.0, 600.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):
			var w := a.substr(10)
			if Sim.WEATHER.has(w):
				story_weather = w
				_sim().weather = w
				_sim().wx = Sim.WEATHER[w].duplicate()
				_sim().wet = 1.0 if w == "rain" else 0.0


func _sim():
	return city.fines.sim


## A story step's "weather".
func set_weather(w: String) -> void:
	if Sim.WEATHER.has(w):
		story_weather = w
		print("WEATHER %s" % w)


func _physics_process(delta: float) -> void:
	if city == null or city.fines == null:
		return
	var sim = _sim()
	if city.story:
		sim.weather = story_weather                  # (the story's clock blends towards it: sim.advance)
		sim._wx_left = 1.0e9
	else:
		_free_left -= delta
		if _free_left <= 0.0:
			_free_left = randf_range(240.0, 600.0)
			sim.weather = sim._pick(Sim.NEXT_PLAINS[sim.weather])
		_blend(sim, delta)
	var wet: float = sim.wet
	var car = city.car
	if car:
		car.set_grip(lerpf(1.0, SOAKED_GRIP, wet))
		car.wiping = float(sim.wx["rain"]) > 0.25 and city.driving
	if city.traffic:
		city.traffic.wet = wet


## Free play has no story clock: the same blend sim.advance does, in real seconds.
func _blend(sim, delta: float) -> void:
	var gm: float = delta * Sim.MINUTES_PER_SECOND
	sim.wet = minf(sim.wet + gm / 40.0, 1.0) if float(sim.wx.get("rain", 0.0)) > 0.3 else maxf(sim.wet - gm / 300.0, 0.0)
	var target: Dictionary = Sim.WEATHER[sim.weather]
	var k := 1.0 - exp(-delta / 40.0)
	for key in ["cloud", "rain", "fog", "grip"]:
		sim.wx[key] = lerpf(sim.wx[key], target[key], k)


## After the day's light is set (city_test._daylight): the weather's share of it, and the wet look.
func apply(env: Environment, sun: DirectionalLight3D, cam: Camera3D) -> void:
	if city == null or city.fines == null:
		return
	var sim = _sim()
	var cloud: float = sim.wx["cloud"]
	var r: float = sim.wx["rain"]
	var wet: float = sim.wet
	if city.story == null:                          # (free play: the light isn't reset each frame by the clock)
		sun.light_energy = 2.6
		sun.shadow_enabled = not "--noshadow" in OS.get_cmdline_user_args()
		env.background_energy_multiplier = 1.0
	if not city.indoors:
		sun.light_energy *= lerpf(1.0, 0.25, smoothstep(0.3, 1.0, cloud))
		sun.shadow_enabled = sun.shadow_enabled and sun.light_energy > 0.4
		env.fog_density = 0.0003 + float(sim.wx["fog"]) * 0.0012 + r * 0.0018
		env.background_energy_multiplier *= lerpf(1.0, 0.55, cloud)
		if city.story == null and not city._free_clock:       # (otherwise the sky is the clock's: city_test._daylight)
			var sm := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
			if sm:
				sm.sky_top_color = Color(0.32, 0.5, 0.78).lerp(Color(0.46, 0.49, 0.53), cloud)
				sm.sky_horizon_color = Color(0.72, 0.78, 0.85).lerp(Color(0.62, 0.64, 0.66), cloud)
	_wet_look(wet)
	_rain.emitting = r > 0.05 and not city.indoors
	if _rain.emitting and cam:
		_rain.amount_ratio = r
		var mv: Vector3 = city.car.linear_velocity if city.car and city.driving else Vector3.ZERO
		_rain.global_position = cam.global_position + Vector3(0, 14.0, 0) + mv * 0.6
	_audio.volume_db = linear_to_db(maxf(r * (0.12 if city.indoors else 0.35), 0.0001))
	if _pb:
		for i in _pb.get_frames_available():
			_lp = lerpf(_lp, randf_range(-1.0, 1.0), 0.35)       # low-passed noise: a hiss, not static
			_pb.push_frame(Vector2(_lp, _lp) * 0.5)


func _wet_look(wet: float) -> void:
	var st = city.streamer
	if st == null:
		return
	if st.road_mat is ShaderMaterial:
		(st.road_mat as ShaderMaterial).set_shader_parameter("wet", wet)     # darker, glossy, pools in the wheel tracks
	if st.ground_mat is ShaderMaterial:
		(st.ground_mat as ShaderMaterial).set_shader_parameter("wet", wet)
	for m in [st.walk_mat, st.kerb_mat]:
		if m is StandardMaterial3D:
			var sm := m as StandardMaterial3D
			if not _base.has(sm):
				_base[sm] = [sm.roughness, sm.albedo_color]
			sm.roughness = lerpf(float(_base[sm][0]), 0.35, wet)
			sm.albedo_color = (_base[sm][1] as Color) * lerpf(1.0, 0.7, wet)


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 7000
	_rain.lifetime = 1.1
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24.0, 0.5, 24.0)
	pm.direction = Vector3(0.08, -1.0, 0.0)
	pm.spread = 3.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 19.0
	pm.gravity = Vector3(0, -9.8, 0)
	_rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.78, 0.82, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	_rain.draw_pass_1 = q
	_rain.emitting = false
	add_child(_rain)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.2
	_audio = AudioStreamPlayer.new()
	_audio.stream = gen
	_audio.volume_db = -80.0
	add_child(_audio)
	_audio.play()
	_pb = _audio.get_stream_playback()
