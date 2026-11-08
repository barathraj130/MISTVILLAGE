shader_type spatial;
// The light a street lamp throws on the road at night (city_streamer.gd, one under each lamp's head): added over
// the road, brightest under the lamp, falling off softly, a little uneven; nothing by day.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform float night = 0.0;
uniform vec3 tint = vec3(1.0, 0.86, 0.66);     // warm-white LED street lighting

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float d = length(c);
	float fall = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	ALBEDO = tint * pow(fall, 1.3) * night * 0.6;
	ALPHA = 1.0;
}
