extends RefCounted
## Graphics presets (Low, Medium, High, Ultra) and the window (fullscreen, VSync), for both worlds: city_test.gd and
## drive_game.gd apply the preset to their viewport, environment and sun; F2 steps through them; kept in
## user://settings.cfg [graphics]. With no setting yet, an Apple M1 (or any integrated GPU) starts on Low (measured:
## the only one over 30 fps there, a fixed city-centre view at 1600 × 900 on a Retina screen: Low 32, Medium 22,
## High 12) and anything else on High; Ultra is never chosen for you.
##   scale      the 3D resolution, rebuilt to the window's by "upscaler": FSR 1 on Low and Medium (cheap: on the M1
##              FSR 2's own pass cost a quarter of the frame, 16 → 22 fps), FSR 2 on High (sharper, anti-aliased)
##   shadow     the sun's shadow map (px), its soft-edge filter (0 hard … 5 softest), how far shadows reach (m);
##              on Low and Medium in two splits, not four (the road up: 21 → 27 fps on Low at the elephant crossing;
##              High and Ultra keep the world's own)
##   ssao       ambient occlusion and its quality (0 very low … 4 ultra); ssil: bounce light (rooms only, as before)
##   vfog       volumetric fog (the mountain world's mist banks); rain: share of the raindrops (city_weather.gd)
##   lod        mesh level-of-detail threshold (px of error allowed: higher is coarser, cheaper)
##   activity   people at the bus stops, stalls, shops, and guards (city_activity.gd)
##   walkers    people walking the footpaths round you (city_walkers.gd)
##   traffic    vehicles round you in central Coimbatore (city_traffic.gd: the CPU's largest share of the frame)
##   tiles      the city's view distance: tiles kept loaded each way round you (2: 5 × 5, 1.3 km; 3: 7 × 7, 1.8 km)
## Testing: --graphics=low|medium|high|ultra (not saved).

const ORDER := ["low", "medium", "high", "ultra"]
const PRESETS := {
	"low": {"scale": 0.5, "shadow": 2048, "soft": 1, "shadow_dist": 80.0, "ssao": false, "ssao_q": 0, "ssil": false,
		"vfog": false, "rain": 0.4, "lod": 6.0, "tiles": 2, "upscaler": "fsr", "traffic": 40, "walkers": 16, "activity": 14},
	"medium": {"scale": 0.67, "shadow": 2048, "soft": 2, "shadow_dist": 120.0, "ssao": true, "ssao_q": 1, "ssil": false,
		"vfog": false, "rain": 0.7, "lod": 3.0, "tiles": 2, "upscaler": "fsr", "traffic": 55, "walkers": 24, "activity": 18},
	"high": {"scale": 0.8, "shadow": 4096, "soft": 3, "shadow_dist": 160.0, "ssao": true, "ssao_q": 2, "ssil": true,
		"vfog": true, "rain": 1.0, "lod": 2.0, "tiles": 3, "upscaler": "fsr2", "traffic": 70, "walkers": 36, "activity": 28},
	"ultra": {"scale": 1.0, "shadow": 4096, "soft": 4, "shadow_dist": 220.0, "ssao": true, "ssao_q": 3, "ssil": true,
		"vfog": true, "rain": 1.0, "lod": 1.0, "tiles": 3, "traffic": 70, "walkers": 48, "activity": 36},
}
const CFG := "user://settings.cfg"

static var current := ""


## The preset in force: --graphics=… (a test), else the saved one, else this machine's default.
static func preset() -> String:
	if current != "":
		return current
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--graphics=") and PRESETS.has(a.get_slice("=", 1)):
			current = a.get_slice("=", 1)
			return current
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK and PRESETS.has(str(cf.get_value("graphics", "preset", ""))):
		current = str(cf.get_value("graphics", "preset"))
		return current
	current = default_preset()
	return current


static func default_preset() -> String:
	var weak := RenderingServer.get_video_adapter_name().contains("Apple M1") \
		or RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	return "low" if weak else "high"


static func value(key: String):
	return PRESETS[preset()][key]


## The next preset (F2), saved unless a test chose it.
static func step() -> String:
	current = ORDER[(ORDER.find(preset()) + 1) % ORDER.size()]
	if not " ".join(OS.get_cmdline_user_args()).contains("--graphics="):
		save_value("preset", current)
	return current


## One value into settings.cfg, keeping everything else in it (the steering sensitivity, the window).
static func save_value(key: String, v) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("graphics", key, v)
	cf.save(CFG)


## The preset onto a world: its viewport, its environment (may be null) and its sun (may be null).
static func apply(vp: Viewport, env: Environment, sun: DirectionalLight3D) -> void:
	var p: Dictionary = PRESETS[preset()]
	var up := str(p.get("upscaler", "fsr2"))
	for a in OS.get_cmdline_user_args():                    # (testing: --upscaler=fsr|fsr2|bilinear)
		if a.begins_with("--upscaler="):
			up = a.get_slice("=", 1)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if float(p["scale"]) >= 1.0 or up == "bilinear" else \
		(Viewport.SCALING_3D_MODE_FSR if up == "fsr" else Viewport.SCALING_3D_MODE_FSR2)
	vp.scaling_3d_scale = float(p["scale"])
	vp.msaa_3d = Viewport.MSAA_DISABLED                  # (FSR 2 anti-aliases; at full scale, FXAA)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if float(p["scale"]) >= 1.0 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = float(p["lod"])
	RenderingServer.directional_shadow_atlas_set_size(int(p["shadow"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(p["soft"]) as RenderingServer.ShadowQuality)
	RenderingServer.environment_set_ssao_quality(int(p["ssao_q"]) as RenderingServer.EnvironmentSSAOQuality,
		int(p["ssao_q"]) < 2, 0.5, 2, 50.0, 300.0)
	if env:
		env.ssao_enabled = bool(p["ssao"])
		if not bool(p["vfog"]):
			env.volumetric_fog_enabled = false
	if sun:
		sun.directional_shadow_max_distance = float(p["shadow_dist"])
		if not sun.has_meta("splits"):
			sun.set_meta("splits", sun.directional_shadow_mode)      # (the world's own, for High and Ultra)
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if preset() in ["low", "medium"] \
			and not "--splits4" in OS.get_cmdline_user_args() \
			else sun.get_meta("splits")
	var px := DisplayServer.window_get_size()
	print("GRAPHICS %s (%s, window %d×%d px, screen scale %.1f): scale %.2f, shadows %d px soft %d to %.0f m, ssao %s, lod %.0f" % [preset(),
		up, px.x, px.y, DisplayServer.screen_get_scale(), float(p["scale"]), int(p["shadow"]), int(p["soft"]), float(p["shadow_dist"]),
		p["ssao"], float(p["lod"])])


## The window as saved: fullscreen or not, VSync on or off (on by default).
static func apply_window() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return
	if bool(cf.get_value("graphics", "fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(cf.get_value("graphics", "vsync", true))
		else DisplayServer.VSYNC_DISABLED)
