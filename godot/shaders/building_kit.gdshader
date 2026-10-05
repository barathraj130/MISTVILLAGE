shader_type spatial;
// Designed buildings (tools/buildings.py --export). One material for the whole building: the vertex
// colour carries RGB = tint and A = layer / 255. Layers 0..14 pick a texture from the arrays (world
// triplanar, real metres, the same tile sizes as the Blender designs); 100 = a lit room seen through
// a window, 101 = a wall lamp — both glow warmer and brighter after dusk.
render_mode cull_back;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : filter_linear_mipmap, repeat_enable;
uniform float tiles[15];
uniform float roughs[15];
uniform float metals[15];
uniform float night = 0.0;
uniform float wet = 0.0;

varying vec3 wpos;
varying vec3 wnrm;
varying flat float layer;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	layer = floor(COLOR.a * 255.0 + 0.5);
}

vec3 unpack_n(vec4 t) {
	vec2 xy = t.xy * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

void fragment() {
	if (layer >= 99.5) {
		bool room = layer < 100.5;
		vec3 warm = room ? vec3(1.0, 0.72, 0.42) : vec3(1.0, 0.8, 0.55);
		ALBEDO = COLOR.rgb * 0.6;
		ROUGHNESS = 0.6;
		EMISSION = warm * (room ? mix(0.35, 2.4, night) : mix(0.3, 7.0, night));
	} else {
		int li = int(layer);
		float t = tiles[li];
		vec3 n = normalize(wnrm);
		vec3 bw = pow(abs(n), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		vec3 p = wpos / t;
		vec3 ax = texture(albedo_tex, vec3(p.zy, float(li))).rgb;
		vec3 ay = texture(albedo_tex, vec3(p.xz, float(li))).rgb;
		vec3 az = texture(albedo_tex, vec3(p.xy, float(li))).rgb;
		ALBEDO = (ax * bw.x + ay * bw.y + az * bw.z) * COLOR.rgb * mix(1.0, 0.7, wet);
		vec3 tx = unpack_n(texture(normal_tex, vec3(p.zy, float(li))));
		vec3 ty = unpack_n(texture(normal_tex, vec3(p.xz, float(li))));
		vec3 tz = unpack_n(texture(normal_tex, vec3(p.xy, float(li))));
		// whiteout-blended triplanar normal in world space
		vec3 nx = vec3(tx.xy + n.zy, abs(tx.z) * n.x).zyx;
		vec3 ny = vec3(ty.xy + n.xz, abs(ty.z) * n.y).xzy;
		vec3 nz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
		vec3 wn = normalize(nx * bw.x + ny * bw.y + nz * bw.z);
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		ROUGHNESS = mix(roughs[li], 0.25, wet * 0.6);
		METALLIC = metals[li];
	}
}
