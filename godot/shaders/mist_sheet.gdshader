shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Drifting mist layers in the valley and between the ridges (mat_mist_sheet in mist_village.py).

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 mist_color : source_color = vec3(0.85, 0.88, 0.92);
uniform float density = 0.5;
uniform float noise_scale = 0.006;       // Blender noise Scale: features ≈ 1 / scale metres
uniform vec2 drift = vec2(3.1, -1.3);    // metres per second
uniform float light = 1.0;               // dimmed at night
uniform float fade_distance = 40.0;      // soft edge where the sheet cuts terrain

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// the noise texture holds ~4 features per tile
	vec2 p = (world_pos.xz + drift * TIME) * noise_scale * 0.25;
	float n = texture(noise_tex, p).r * 0.65 + texture(noise_tex, p * 3.1 + 0.37).r * 0.35;
	float a = smoothstep(0.48, 0.78, n);
	vec2 e = UV * (1.0 - UV) * 4.0;
	float edge = pow(e.x * e.y, 0.8);

	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	scene.xyz /= scene.w;
	float soft = clamp((VERTEX.z - scene.z) / fade_distance, 0.0, 1.0);

	ALBEDO = mist_color * light;
	ALPHA = a * edge * density * soft;
}
