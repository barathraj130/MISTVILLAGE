shader_type spatial;
// Retroreflective road furniture (cat's-eye studs, delineator posts): they bounce light straight back to
// its source, so at night they blaze when your own headlights point at them and stay dull otherwise.
// head_* are updated every frame from the player's car.
render_mode cull_disabled;

uniform vec3 head_pos = vec3(0.0);
uniform vec3 head_dir = vec3(0.0, 0.0, 1.0);
uniform float head_on = 0.0;
uniform float night = 0.0;
uniform float strength = 16.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = COLOR.rgb * 0.6;
	ROUGHNESS = 0.35;
	vec3 v = wpos - head_pos;
	float d = max(length(v), 0.001);
	float cone = smoothstep(0.84, 0.97, dot(v / d, normalize(head_dir)));
	float reach = 1.0 - smoothstep(30.0, 170.0, d);
	EMISSION = COLOR.rgb * (strength * head_on * night * cone * reach + 0.06 * night);
}
