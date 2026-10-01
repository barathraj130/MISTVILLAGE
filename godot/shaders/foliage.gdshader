shader_type spatial;
render_mode cull_disabled;
// Leaves, grass, ferns and flowers: baked albedo tile, per-instance tint (MultiMesh colour),
// light passing through the leaves, and wind that bends the crown more than the trunk.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness = 0.65;
uniform float translucency = 0.35;
uniform float wind_strength = 0.02;     // sway per metre of height
uniform float wind_speed = 1.1;
uniform vec2 wind_dir = vec2(0.8, 0.6);

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 root = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0);
	float phase = dot(root.xz, vec2(0.37, 0.21));
	float gust = sin(TIME * 0.35 + dot(root.xz, wind_dir) * 0.03) * 0.5 + 0.5;
	float sway = (sin(TIME * wind_speed + phase) * 0.6
		+ sin(TIME * wind_speed * 2.3 + phase * 1.7 + world.y) * 0.25) * (0.4 + gust);
	vec2 offset = wind_dir * sway * wind_strength * h * h / (h + 1.0);
	offset += vec2(sin(TIME * 4.0 + world.x * 3.0), cos(TIME * 3.3 + world.z * 3.0))
		* 0.15 * min(h, 2.0) * wind_strength;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(offset.x, 0.0, offset.y);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * albedo_color.rgb * COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	BACKLIGHT = c * translucency;
}
