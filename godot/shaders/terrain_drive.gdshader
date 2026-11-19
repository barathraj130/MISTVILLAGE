shader_type spatial;
// Ground along the drive, from photo textures (ambientCG, CC0):
// dry grass on the Coimbatore plains, green grass in the hills, forest floor in patches,
// red Nilgiri soil in steep road cuttings and grey rock on the steepest faces.
// Two scales of each texture plus macro noise break up visible tiling.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D dry_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D soil_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D forest_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool has_textures = false;
uniform float plains_end = 3000.0;     // fictional road: x where the plains stop being dry
uniform float hills_start = 3600.0;
uniform bool by_height = false;        // real map: dry plains below dry_top, green above green_bottom
uniform float dry_top = 20.0;
uniform float green_bottom = 110.0;
// the deep-forest stretches (props.gd _deep_forest): points along their road, xz and a reach (w); the ground within
// reach of them is forest floor (leaf litter under the canopy) except on steep cuttings
uniform vec3 deep_pts[24];
uniform int deep_n = 0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 two_scale(sampler2D t, vec2 p, float tile) {
	vec3 a = texture(t, p / tile).rgb;
	vec3 b = texture(t, p / (tile * 3.7) + 0.31).rgb;
	return mix(a, b, 0.35);
}

vec3 triplanar(sampler2D t, vec3 p, vec3 n, float tile) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy / tile).rgb * w.x + texture(t, p.xz / tile).rgb * w.y + texture(t, p.xy / tile).rgb * w.z;
}

void fragment() {
	float n1 = texture(noise_tex, wpos.xz * 0.004).r;
	float n2 = texture(noise_tex, wpos.xz * 0.05).r;
	float n3 = texture(noise_tex, wpos.xz * 0.4).r;
	float dry = by_height ? 1.0 - smoothstep(dry_top, green_bottom, wpos.y)
		: 1.0 - smoothstep(plains_end, hills_start, wpos.x);
	float slope = 1.0 - wnorm.y;
	float w_dry = dry * smoothstep(0.25, 0.65, n1 + 0.15);
	float w_forest = (1.0 - dry) * smoothstep(0.55, 0.75, n1) * (1.0 - smoothstep(0.2, 0.35, slope));
	float deep = 0.0;
	for (int i = 0; i < deep_n; i++) {
		float dd = distance(wpos.xz, deep_pts[i].xy);
		deep = max(deep, 1.0 - smoothstep(deep_pts[i].z * 0.65, deep_pts[i].z, dd));
	}
	float w_deep = deep * (0.8 + 0.2 * n2) * (1.0 - smoothstep(0.3, 0.5, slope));
	float w_soil = smoothstep(0.25, 0.42, slope);
	float w_rock = smoothstep(0.62, 0.82, slope);
	vec3 c;
	if (has_textures) {
		vec3 grass = two_scale(grass_tex, wpos.xz, 4.0) * vec3(0.85, 0.95, 0.8);
		vec3 dryc = two_scale(dry_tex, wpos.xz, 5.0);
		vec3 forest = two_scale(forest_tex, wpos.xz, 4.0) * 0.8;
		vec3 soil = triplanar(soil_tex, wpos, wnorm, 3.0) * vec3(1.15, 0.8, 0.65);
		vec3 rock = triplanar(rock_tex, wpos, wnorm, 7.0);
		c = mix(grass, dryc, w_dry);
		c = mix(c, forest, w_forest);
		// the deep forest's floor: dark, damp, green-brown leaf litter with moss in the hollows (not dry red earth)
		float lum = dot(forest, vec3(0.333));               // (the texture's detail, not its orange)
		vec3 humus = vec3(0.13, 0.1, 0.065) * (0.55 + 0.9 * lum);
		vec3 moss = vec3(0.08, 0.13, 0.045) * (0.6 + 0.8 * lum);
		vec3 litter = vec3(0.22, 0.15, 0.08) * (0.6 + 0.7 * lum);
		// mixed at three scales so no patch repeats: humus and moss (tens of metres), green ground cover in broad
		// drifts (hundreds), leaf litter and dark root-and-twig streaks (metres)
		float n4 = texture(noise_tex, wpos.xz * 0.013 + 0.61).r;
		float n5 = texture(noise_tex, vec2(wpos.x * 0.9, wpos.z * 0.22) + 0.17).r;
		vec3 cover = grass * vec3(0.42, 0.55, 0.3);
		vec3 damp = mix(humus, moss, smoothstep(0.38, 0.72, n2));
		damp = mix(damp, cover, smoothstep(0.5, 0.78, n4) * 0.7);
		damp = mix(damp, litter, smoothstep(0.6, 0.85, n3) * 0.45);
		damp *= mix(1.0, 0.62, smoothstep(0.72, 0.9, n5) * 0.6);
		c = mix(c, damp, w_deep);
		c = mix(c, soil, w_soil);
		c = mix(c, rock, w_rock);
		c *= 0.8 + 0.4 * n2;
	} else {
		vec3 grass_dry = mix(vec3(0.30, 0.25, 0.11), vec3(0.19, 0.19, 0.07), n2);
		vec3 grass_wet = mix(vec3(0.05, 0.12, 0.03), vec3(0.10, 0.16, 0.04), n2);
		c = mix(grass_wet, grass_dry, w_dry);
		vec3 red = mix(vec3(0.28, 0.09, 0.035), vec3(0.40, 0.15, 0.06), n3);
		c = mix(c, red, w_soil);
		c = mix(c, vec3(0.20, 0.19, 0.17) * (0.8 + 0.4 * n3), w_rock);
		c *= 0.85 + 0.3 * n3;
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
