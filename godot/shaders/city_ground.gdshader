shader_type spatial;
// Open ground in the city: dry grass, green grass and red soil in large patches (world-space, no UVs needed),
// a little darker under the haze of distance so the plain does not read as one flat colour from above.

uniform sampler2D dry_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D green_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float tile = 6.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz / tile;
	vec3 dry = texture(dry_tex, uv).rgb;
	vec3 green = texture(green_tex, uv * 1.3).rgb * vec3(0.85, 0.95, 0.8);
	vec3 soil = texture(soil_tex, uv * 0.9).rgb;
	float n1 = texture(noise_tex, wpos.xz / 180.0).r;
	float n2 = texture(noise_tex, wpos.xz / 70.0 + 0.37).r;
	float n3 = texture(noise_tex, wpos.xz / 9.0).r;
	vec3 col = mix(dry, green, smoothstep(0.52, 0.68, n1 + (n3 - 0.5) * 0.15));
	col = mix(col, soil, smoothstep(0.55, 0.72, n2 + (n3 - 0.5) * 0.2));
	col *= 0.9 + 0.2 * n3;
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
