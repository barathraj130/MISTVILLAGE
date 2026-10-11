shader_type spatial;
// Indian city asphalt: the base photo texture plus everything a real road collects — darker, polished wheel tracks
// in each lane, patched repairs, oil drips down the lane centres, red dust drifting in from the edges, large-scale
// colour variation (no visible tiling), and rain that pools in the tracks.
//
// Mesh contract: UV.x * 6 = metres across from the left edge, UV.y * 6 = metres along (road.gd / towns.gd).
// COLOR.r = half-width / 10 (COLOR.r ≥ 0.95 = junction / lot: no lanes, just wear).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;      // seamless value noise, 0..1
uniform vec3 tint : source_color = vec3(0.62, 0.62, 0.64);
uniform vec3 dust : source_color = vec3(0.55, 0.43, 0.33);
uniform float tile = 1.5;                  // texture repeats per 6 m UV unit (4 m tiles)
uniform float wear = 1.0;                  // 0 new road … 1 well used
uniform float wet = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float n2(vec2 p) {
	return texture(noise_tex, p).r;
}

void fragment() {
	vec2 uv = UV * tile;
	// two rotated samples of the photo texture, blended by large noise: hides the 4 m repeat
	vec2 uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * uv * 0.71 + vec2(0.37, 0.11);
	float m = smoothstep(0.35, 0.65, n2(wpos.xz / 55.0));
	vec3 base = mix(texture(albedo_tex, uv).rgb, texture(albedo_tex, uv2).rgb, m);
	vec3 nrm = mix(texture(normal_tex, uv).rgb, texture(normal_tex, uv2).rgb, m);
	float rough = mix(texture(rough_tex, uv).r, texture(rough_tex, uv2).r, m);
	vec3 col = base * tint;
	// broad patchy variation (resurfaced stretches, sun-bleached areas)
	float macro = n2(wpos.xz / 140.0);
	col *= mix(0.86, 1.1, macro);

	float half_w = COLOR.r * 10.0;
	bool lanes = COLOR.r < 0.95;
	float across = UV.x * 6.0 - half_w;              // metres from the centreline
	float edge = half_w - abs(across);                // metres to the nearest edge
	float tracks = 0.0;
	if (lanes) {
		float lane_c = half_w > 4.2 ? half_w * 0.5 : half_w * 0.5;      // two lanes, keep left
		float a = abs(across);
		float d1 = abs(a - (lane_c - 0.78));
		float d2 = abs(a - (lane_c + 0.78));
		tracks = exp(-d1 * d1 / 0.09) + exp(-d2 * d2 / 0.09);
		tracks *= 0.75 + 0.25 * n2(vec2(UV.y * 0.7, across * 0.2));
		// oil drips down the middle of each lane
		float lc = abs(a - lane_c);
		float oil = smoothstep(0.62, 0.8, n2(wpos.xz / 2.3)) * exp(-lc * lc / 0.12);
		col *= 1.0 - 0.32 * oil * wear;
		rough -= 0.25 * oil * wear;
	}
	col *= 1.0 - 0.13 * tracks * wear;                // darker where tyres run
	rough -= 0.12 * tracks * wear;                    // and polished
	// patched repairs: cut rectangles of newer, darker asphalt
	vec2 cell = floor(wpos.xz / vec2(3.1, 2.3));
	float pick = n2(cell * 0.137);
	vec2 inner = fract(wpos.xz / vec2(3.1, 2.3));
	float box = step(0.12, inner.x) * step(inner.x, 0.86) * step(0.18, inner.y) * step(inner.y, 0.8);
	float patch = step(0.78, pick) * box * wear;
	col = mix(col, col * 0.72, patch);
	rough = mix(rough, rough + 0.08, patch);
	// red dust blown in from the verges, thicker in the gutters
	float dust_amt = lanes ? (1.0 - smoothstep(0.0, 0.9, edge)) * (0.55 + 0.45 * n2(wpos.xz / 4.0)) : 0.0;
	dust_amt += 0.12 * smoothstep(0.55, 0.8, n2(wpos.xz / 9.0));
	col = mix(col, dust * (0.8 + 0.4 * n2(wpos.xz / 1.3)), clamp(dust_amt * wear, 0.0, 0.85));
	rough = mix(rough, 1.0, dust_amt * 0.6);
	// rain: darker, glossy, water collects in the wheel tracks first
	float pool = wet * clamp(0.4 + tracks * 0.8 + (1.0 - dust_amt) * 0.2, 0.0, 1.0);
	col *= mix(1.0, 0.5, wet);
	rough = mix(rough, 0.08, pool);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	NORMAL_MAP = mix(nrm, vec3(0.5, 0.5, 1.0), pool * 0.85);
	SPECULAR = mix(0.4, 0.7, wet);
}
