shader_type spatial;
render_mode depth_draw_opaque;
// The roads that aren't asphalt (tools/citygen/surfaces.py, city_streamer.gd): drawn here, no image files, on the
// same mesh as the asphalt (road_surface.gdshader's contract: UV.x * 6 = metres across from the left edge, UV.y * 6
// = metres along, COLOR.r = half-width / 10).
//   kind 0  compacted earth, a Tamil Nadu village road: red-brown laterite soil going sandy beige in places, two
//           wheel paths packed darker and smoother, the hump between them lighter and on a track grassy, loose sand
//           towards the edges, small stones, grass at the shoulders, and the edge itself ragged into the ground
//   kind 1  gravel: grey-brown stones in soil, the wheel paths cleared down to the soil
//   kind 2  concrete: light grey slabs with a joint across every 4 m, a little stained, dust at the edges
// Rain (wet, city_weather.gd): earth goes dark mud with water standing in the wheel paths' low places, concrete and
// gravel darken and shine a little; nothing goes mirror-like.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;      // seamless value noise, 0..1
uniform int kind = 0;
uniform float wet = 0.0;
uniform vec3 soil : source_color = vec3(0.60, 0.42, 0.29);              // laterite
uniform vec3 sand : source_color = vec3(0.74, 0.64, 0.5);
uniform vec3 grass : source_color = vec3(0.36, 0.38, 0.2);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float n2(vec2 p) {
	return texture(noise_tex, p).r;
}

// a little fbm: three octaves of the noise
float fbm(vec2 p) {
	return 0.55 * n2(p) + 0.3 * n2(p * 2.07 + 0.31) + 0.15 * n2(p * 4.13 + 0.77);
}

void fragment() {
	float half_w = COLOR.r * 10.0;
	bool lot = COLOR.r >= 0.95;                         // (a junction or a joint patch: no wheel paths)
	float across = UV.x * 6.0 - half_w;                 // metres from the centreline
	float edge = lot ? 9.0 : half_w - abs(across);      // metres to the nearest edge
	vec2 w = wpos.xz;
	float big = fbm(w / 23.0);
	float fine = n2(w / 0.9);
	float grit = n2(w / 0.23);
	vec3 col;
	float rough = 0.95;
	float bump = 0.0;
	float paths = 0.0;
	if (!lot) {                                         // two wheel paths: one lane if narrow, two if wide
		float a = abs(across);
		float lane = half_w > 3.2 ? half_w * 0.5 : 0.0;
		float d1 = abs(a - abs(lane - 0.82));
		float d2 = abs(a - (lane + 0.82));
		paths = exp(-d1 * d1 / 0.16) + exp(-d2 * d2 / 0.16);
		paths *= 0.7 + 0.3 * n2(vec2(UV.y * 1.3, across * 0.4));
		paths = clamp(paths, 0.0, 1.0);
	}
	if (kind == 0) {
		col = mix(soil, sand, smoothstep(0.35, 0.75, big));             // laterite here, sandier there
		col *= mix(0.88, 1.08, fine);
		float loose = 1.0 - smoothstep(0.2, 1.1, edge);                 // loose sand drifted to the edges
		col = mix(col, sand * 1.04, loose * 0.55);
		col = mix(col, col * 0.86, paths * 0.6);                        // the packed wheel paths
		rough = mix(0.97, 0.86, paths);
		float hump = (1.0 - paths) * smoothstep(0.6, 1.4, edge);       // between the paths, and on a track: grass
		float tuft = smoothstep(0.55, 0.8, n2(w / 0.7)) * (1.0 - smoothstep(0.0, 0.9, edge));
		col = mix(col, grass * mix(0.8, 1.15, fine), clamp(tuft * 0.85 + hump * 0.12 * step(half_w, 2.2), 0.0, 1.0));
		float stone = smoothstep(0.78, 0.86, grit) * (1.0 - paths * 0.7);
		col = mix(col, vec3(0.55, 0.5, 0.45) * mix(0.8, 1.2, fine), stone * 0.7);
		bump = grit * 0.6 + stone * 0.5 - paths * 0.3;
		// the edge, ragged into the field: dissolved a little way in, with the soil's noise
		if (!lot) {
			float ragged = edge - 0.35 * fbm(w / 1.7);
			if (ragged < 0.05) discard;
		}
	} else if (kind == 1) {
		vec3 stones = mix(vec3(0.46, 0.43, 0.4), vec3(0.62, 0.58, 0.52), grit);
		col = mix(stones, soil * 1.1, paths * 0.55 + 0.25 * fine);
		col *= mix(0.9, 1.06, big);
		float s = smoothstep(0.6, 0.75, grit);
		col *= 1.0 - 0.2 * s;
		rough = 0.93;
		bump = grit * 0.9;
		if (!lot) {
			float ragged = edge - 0.25 * fbm(w / 1.3);
			if (ragged < 0.05) discard;
		}
	} else {
		col = vec3(0.68, 0.67, 0.64) * mix(0.9, 1.05, big) * mix(0.95, 1.03, fine);
		float along = UV.y * 6.0;
		float joint = 1.0 - smoothstep(0.0, 0.03, abs(fract(along / 4.0) - 0.5) * 4.0 - 1.94);   // a cut every 4 m
		col *= 1.0 - 0.35 * joint * (lot ? 0.0 : 1.0);
		col = mix(col, col * 0.86, smoothstep(0.62, 0.8, n2(w / 3.1)) * 0.6);                   // stains
		col = mix(col, sand * 0.95, (1.0 - smoothstep(0.1, 0.7, edge)) * 0.5);                   // dust at the edges
		col = mix(col, col * 0.9, paths * 0.4);
		rough = 0.88;
		bump = fine * 0.2 - joint * 0.4;
	}
	// rain
	float puddle = 0.0;
	if (kind == 0) {
		float low = smoothstep(0.52, 0.68, fbm(w / 3.3 + 7.1)) * (0.4 + paths * 0.9);
		puddle = clamp(wet * low * 1.4, 0.0, 1.0);
		col *= mix(1.0, 0.58, wet);                                     // mud
		rough = mix(rough, 0.55, wet);
		col = mix(col, vec3(0.16, 0.12, 0.09), puddle * 0.75);           // brown water standing in the low places
		rough = mix(rough, 0.08, puddle);
	} else {
		col *= mix(1.0, 0.7, wet);
		rough = mix(rough, 0.45, wet);
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = mix(0.25, 0.5, wet);
	// small relief from the noise's slope (the stones, the ruts), flattened where water stands
	float e = 0.02;
	float hx = n2((w + vec2(e, 0.0)) / 0.23) - grit;
	float hz = n2((w + vec2(0.0, e)) / 0.23) - grit;
	NORMAL_MAP = normalize(vec3(-hx * 6.0 * bump, -hz * 6.0 * bump, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0 - puddle;
}
