extends RefCounted
## The city's look out of doors, by the hour (city_test.gd _daylight calls it after the sun and sky are set; --nograde
## leaves it out, for comparing): what a camera in Coimbatore sees rather than a flat render.
##   morning    a warm low sun through the haze of the city waking (smoke, dust): the haze thick at 6–7, gone by 10
##   noon       a hard white sun, the colour a little bleached, deep short shadows
##   evening    the sun low and orange, the haze warm, colour richer
##   night      exposure lifted a little so the street can be read; blue in the shadows, the lamps warm
## Throughout: shadows a touch cool and highlights a touch warm (a split tone, as curves), a little more contrast,
## the sun's glare in the haze when you look toward it, a faint bloom on sunlit chrome and glass by day, and on High
## and Ultra the light bounced off sunlit walls into the shade (SSIL, screen space: no cost that grows with the map).
## Costs on Low: none measurable (curves, haze and day bloom are full-screen passes the frame already had or cheap).

const Graphics := preload("res://scripts/graphics.gd")

static var _curves := {}                         # (a key per time band → its gradient texture, made once)


## sd: the sun's direction (sim.sun_dir), day: daylight 0–1, dusk and night: 0–1 bands (as _daylight works them out),
## cloud 0–1, hour: the clock (0–24).
static func apply(env: Environment, sun: DirectionalLight3D, sd: Vector3, day: float, dusk: float, night: float,
		cloud: float, hour: float) -> void:
	var low := 1.0 - smoothstep(0.1, 0.5, sd.y)              # the sun low in the sky (morning or evening)
	var morning := low * (1.0 - smoothstep(9.0, 11.0, hour)) * smoothstep(5.0, 6.0, hour)
	var clear := 1.0 - cloud
	# the sun: warmer and stronger when low, white at noon; the sky's fill a little less, so the shade has depth
	if sd.y > -0.04:
		sun.light_color = Color(1.0, 0.66, 0.4).lerp(Color(1.0, 0.95, 0.88), smoothstep(0.1, 0.55, sd.y))
		sun.light_energy = lerpf(2.6, 3.0, clear) * smoothstep(-0.04, 0.15, sd.y)
	env.ambient_light_energy = lerpf(0.16, lerpf(0.45, 0.36, clear), day)
	# haze: thick in the early morning, warm when the sun is low; the sun's glare in it
	env.fog_density = 0.0003 + 0.0009 * morning * clear + 0.0003 * dusk + 0.0004 * cloud
	env.fog_sun_scatter = 0.35 * clear * day
	env.fog_light_color = env.fog_light_color.lerp(Color(0.93, 0.78, 0.62), morning * 0.6)
	# exposure and colour
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = lerpf(1.15, 1.0, day)
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = lerpf(1.0, 1.08, day)
	env.adjustment_saturation = lerpf(0.9, lerpf(1.06, 1.15, maxf(dusk, morning)), day) * lerpf(1.0, 0.92, cloud)
	var band := "night" if night > 0.5 else ("warm" if maxf(dusk, morning) > 0.35 else "day")
	env.adjustment_color_correction = _curve(band)
	# by day a faint bloom on what the sun catches (at night the city's own glow settings stand: _city_lights)
	if night < 0.05 and day > 0.5:
		env.glow_enabled = true
		env.glow_intensity = 0.25
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 0.95
	# bounced light on High and Ultra
	env.ssil_enabled = bool(Graphics.value("ssil")) and day > 0.3
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8


## Curves per band: what dark becomes (shadows), the middle, what white becomes (highlights), as R, G and B each.
static func _curve(band: String) -> Texture2D:
	if _curves.has(band):
		return _curves[band]
	var stops: Array = {
		"day": [Color(0.0, 0.006, 0.02), Color(0.25, 0.25, 0.255), Color(0.5, 0.5, 0.49), Color(1.0, 0.985, 0.95)],
		"warm": [Color(0.01, 0.005, 0.025), Color(0.26, 0.245, 0.24), Color(0.52, 0.49, 0.46), Color(1.0, 0.96, 0.88)],
		"night": [Color(0.0, 0.01, 0.035), Color(0.24, 0.25, 0.28), Color(0.5, 0.5, 0.52), Color(1.0, 0.97, 0.92)],
	}[band]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 1.0])
	g.colors = PackedColorArray(stops)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	_curves[band] = t
	return t
