shader_type spatial;
// Open ground in the city: dry grass, green grass and red soil in large patches (world-space, no UVs needed),
// a little darker under the haze of distance so the plain does not read as one flat colour from above.

uniform sampler2D dry_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D green_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float tile = 6.0;
uniform float wet = 0.0;                    // after rain: darker soil and grass, a little sheen

varying vec3 wpos;
varying float forest;                       // 1 inside a forest pocket (the ground's vertex colour red 0, city_streamer.gd)

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	forest = 1.0 - COLOR.r;
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
	// the forest floor: leaf litter over dark soil, mottled, a little moss in the damp patches
	vec3 litter = mix(soil * vec3(0.55, 0.42, 0.3), vec3(0.2, 0.15, 0.08), n3 * 0.6);
	litter = mix(litter, green * vec3(0.45, 0.6, 0.35), smoothstep(0.6, 0.8, n2) * 0.5);
	col = mix(col, litter, smoothstep(0.1, 0.9, forest));
	ALBEDO = col * mix(1.0, 0.62, wet);
	ROUGHNESS = mix(0.95, 0.6, wet);
}
