shader_type spatial;
// Facades for thousands of town buildings in one material.
// COLOR.rgb = wall paint; COLOR.a = 1 on walls, 0 on roofs (no windows).
// UV  = (metres along the wall, metres above the building's base).
// UV2 = (random 0..1 per building, 1 if the ground floor is a shop).

uniform float floor_h = 3.2;
uniform float bay = 2.6;
uniform float night = 0.0;                 // 0 day → 1 night: some windows light up

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec3 paint = COLOR.rgb;
	vec3 c = paint;
	float rough = 0.9;
	vec3 glow = vec3(0.0);
	if (COLOR.a > 0.5) {
		float u = UV.x;
		float v = UV.y;
		float rnd = UV2.x;
		float shop = UV2.y;
		float fl = floor(v / floor_h);
		float fv = fract(v / floor_h);
		float cell = floor(u / bay);
		float fu = fract(u / bay);
		if (fl > 0.5 || shop < 0.5) {
			// a window per bay: frame, glass, and sometimes a lit room at night
			float win = step(0.26, fu) * step(fu, 0.74) * step(0.34, fv) * step(fv, 0.8);
			float frame = step(0.22, fu) * step(fu, 0.78) * step(0.3, fv) * step(fv, 0.84) - win;
			float h = hash(rnd * 97.0 + fl * 13.1 + cell * 7.7);
			vec3 glass = mix(vec3(0.04, 0.05, 0.07), vec3(0.22, 0.27, 0.32), step(0.65, h));
			c = mix(c, paint * 0.5, frame);
			c = mix(c, glass, win);
			rough = mix(rough, 0.12, win);
			glow = win * step(0.55, h) * night * vec3(1.0, 0.72, 0.4) * 1.6;
		} else {
			// shop front: rolling shutter with slats under a coloured sign band
			float sh = step(0.06, fu) * step(fu, 0.94) * step(fv, 0.7);
			float slat = 0.5 + 0.5 * sin(v * 90.0);
			vec3 shutter = vec3(0.4, 0.41, 0.42) * (0.82 + 0.18 * slat);
			c = mix(c, shutter, sh);
			float band = step(0.74, fv) * step(fv, 0.94);
			vec3 sign_col = 0.5 + 0.5 * cos(6.2831 * (rnd * 3.0 + cell * 0.21 + vec3(0.0, 0.33, 0.67)));
			c = mix(c, sign_col * 0.75, band);
			glow = band * night * sign_col * 0.8;
		}
		c *= 0.8 + 0.2 * smoothstep(0.0, 1.4, v);            // grime near the ground
		c *= 1.0 - 0.1 * step(fv, 0.035);                    // floor lines
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	EMISSION = glow;
}
