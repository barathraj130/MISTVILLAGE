shader_type spatial;
// The footpaths (city_streamer.gd, from the paver material city_test.gd gives it): the same pavers, plus contact
// shading along both long edges (the kerb on one side, the plinth or wall on the other), on ambient light only.
// Mesh contract: UV = (metres across from the strip's centre, metres along) / 2; UV2.x = the strip's half width (m).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.92, 0.88, 0.84);
uniform float ao_k = 1.0;                  // the edges' contact shading (0: off, --noshaderao)

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = texture(rough_tex, UV).r;
	float hw = UV2.x;
	if (hw > 0.05) {
		float to_edge = hw - abs(UV.x * 2.0);
		AO = mix(1.0, mix(0.6, 1.0, smoothstep(0.0, 0.45, to_edge)), ao_k);
		AO_LIGHT_AFFECT = 0.0;
	}
}
