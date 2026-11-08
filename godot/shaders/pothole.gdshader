shader_type spatial;
// A pothole on the asphalt (city_potholes.gd): a ragged hole, its own shape from the instance's seed. Its walls
// face in (a bowl, from the normal map: the light catches the far wall, the near one is in shade), a thin lighter
// broken edge, loose dark grit at the bottom; after rain it holds water, a still dark mirror.

uniform float wet = 0.0;

varying float seed;

void vertex() {
	seed = INSTANCE_CUSTOM.r;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {                                   // smooth value noise (no blocks)
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float d = length(c);
	float a = atan(c.y, c.x);
	float s = seed * 6.2831;
	float edge = 0.78 + 0.08 * sin(a * 3.0 + s) + 0.05 * sin(a * 5.0 + s * 2.3) + 0.03 * sin(a * 11.0 + s * 3.1);
	edge += (noise(c * 9.0 + seed * 31.0) - 0.5) * 0.12;
	if (d > edge) {
		discard;
	}
	float depth = smoothstep(edge, edge * 0.55, d);            // 0 at the edge, 1 on the floor of the hole
	float lip = 1.0 - smoothstep(0.0, 0.07, edge - d);           // the broken edge itself
	float grit = noise(UV * 60.0 + seed * 7.0);
	vec3 floor_col = vec3(0.022, 0.021, 0.02) * (0.7 + 0.6 * grit);
	vec3 wall_col = vec3(0.045, 0.043, 0.04) * (0.8 + 0.4 * grit);
	vec3 lip_col = vec3(0.13, 0.125, 0.115) * (0.8 + 0.4 * grit);
	vec3 col = mix(wall_col, floor_col, depth);
	col = mix(col, lip_col, lip * 0.8);
	float pool = wet * smoothstep(0.3, 0.75, depth);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);    // (still water: the grey sky in it, more at a slant)
	col = mix(col, mix(vec3(0.04, 0.045, 0.05), vec3(0.19, 0.2, 0.23), fres), pool);
	ALBEDO = col;
	// the walls slope in towards the middle; flat at the bottom and outside
	float wall = smoothstep(edge, edge * 0.75, d) * (1.0 - smoothstep(edge * 0.75, edge * 0.5, d));
	vec2 slope = (d > 0.001 ? c / d : vec2(0.0)) * wall * 0.9 * (1.0 - pool);
	NORMAL_MAP = normalize(vec3(-slope.x, -slope.y, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = mix(0.95, 0.03, pool);
	SPECULAR = mix(0.25, 0.7, pool);
}
