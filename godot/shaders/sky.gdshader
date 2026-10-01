shader_type sky;
// Gradient sky from mist_village.py: a colour ramp over elevation plus a warm glow
// around the low golden-hour sun. night_mix blends to the night ramp with stars.

uniform sampler2D day_gradient : repeat_disable, filter_linear;
uniform sampler2D night_gradient : repeat_disable, filter_linear;
uniform sampler2D noon_gradient : repeat_disable, filter_linear;
uniform float noon_mix : hint_range(0.0, 1.0) = 0.0;   // golden-hour ramp → midday blue (drive clock)
uniform float overcast : hint_range(0.0, 1.0) = 0.0;   // weather: flat grey cloud, sun glow hidden
uniform vec3 sun_dir = vec3(0.0, 0.12, 1.0);
uniform vec3 glow_color = vec3(1.0, 0.55, 0.25);
uniform float day_strength = 1.6;
uniform float night_strength = 1.0;
uniform float night_mix : hint_range(0.0, 1.0) = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	float t = clamp(EYEDIR.y * 1.4 + 0.5, 0.0, 1.0);
	vec3 day = texture(day_gradient, vec2(t, 0.5)).rgb;
	if (noon_mix > 0.0) {
		day = mix(day, texture(noon_gradient, vec2(t, 0.5)).rgb, noon_mix);
	}
	float d = max(dot(EYEDIR, normalize(sun_dir)), 0.0);
	day += (pow(d, 28.0) * 6.0 + pow(d, 4.0) * 0.8) * glow_color * (1.0 - overcast * 0.9);
	float grey = dot(day, vec3(0.3, 0.5, 0.2));
	day = mix(day, vec3(grey * 0.85 + 0.08), overcast);

	vec3 night = texture(night_gradient, vec2(t, 0.5)).rgb;
	float star = step(0.9985, hash(floor(EYEDIR * 300.0))) * smoothstep(0.05, 0.3, EYEDIR.y);
	night += vec3(star * 0.6);

	COLOR = mix(day * day_strength, night * night_strength, night_mix);
}
