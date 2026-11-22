shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D rock_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_height : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_detail_albedo : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_detail_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_detail_height : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_detail_rough : filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform float detail_mix = 1.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 vcol;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.05 + vec2(7.1, 3.3);
		a *= 0.5;
	}
	return v;
}
vec3 srgb2lin(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }
vec3 tri_color(sampler2D t, sampler2D hmap, vec3 p, vec3 w, float s, vec2 off, vec3 vdir, float depth) {
	vec2 ux = p.zy * s + off;
	vec2 uy = p.xz * s + off;
	vec2 uz = p.xy * s + off;
	if (depth > 0.0) {
		ux -= vdir.zy * (texture(hmap, ux).r - 0.5) * depth * s;
		uy -= vdir.xz * (texture(hmap, uy).r - 0.5) * depth * s;
		uz -= vdir.xy * (texture(hmap, uz).r - 0.5) * depth * s;
	}
	return srgb2lin(texture(t, ux).rgb) * w.x + srgb2lin(texture(t, uy).rgb) * w.y + srgb2lin(texture(t, uz).rgb) * w.z;
}
vec3 tri_normal(sampler2D t, sampler2D hmap, vec3 p, vec3 w, float s, vec2 off, vec3 vdir, float depth) {
	vec2 ux = p.zy * s + off;
	vec2 uy = p.xz * s + off;
	vec2 uz = p.xy * s + off;
	if (depth > 0.0) {
		ux -= vdir.zy * (texture(hmap, ux).r - 0.5) * depth * s;
		uy -= vdir.xz * (texture(hmap, uy).r - 0.5) * depth * s;
		uz -= vdir.xy * (texture(hmap, uz).r - 0.5) * depth * s;
	}
	vec3 nx = texture(t, ux).xyz * 2.0 - 1.0;
	vec3 ny = texture(t, uy).xyz * 2.0 - 1.0;
	vec3 nz = texture(t, uz).xyz * 2.0 - 1.0;
	vec3 wx = vec3(nx.z, nx.y, nx.x);
	vec3 wy = vec3(ny.x, ny.z, ny.y);
	vec3 wz = vec3(nz.x, nz.y, nz.z);
	return normalize(wx * w.x + wy * w.y + wz * w.z);
}
float tri_scalar(sampler2D t, vec3 p, vec3 w, float s, vec2 off) {
	return texture(t, p.zy * s + off).r * w.x + texture(t, p.xz * s + off).r * w.y + texture(t, p.xy * s + off).r * w.z;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR.rgb;
}

void fragment() {
	vec3 p = wpos;
	vec3 n = normalize(wnrm);
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= max(tw.x + tw.y + tw.z, 1e-4);
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - p);
	float dist = distance(p, CAMERA_POSITION_WORLD);
	float depth = dist < 40.0 ? 0.022 : 0.0;
	vec3 a = tri_color(rock_albedo, rock_height, p, tw, 0.25, vec2(0.0), vdir, depth);
	vec3 b = tri_color(rock_albedo, rock_height, p, tw, 1.20, vec2(0.37, 0.71), vdir, depth * 0.5);
	vec3 col = (a * 0.65 + b * 0.35) * tint;
	float macro = fbm3(p.xz * 0.09 + p.y * 0.03);
	col *= 0.82 + 0.30 * macro;
	// moss on up-facing crevices
	float moss = smoothstep(0.55, 0.85, fbm3(p.xz * 0.55 + p.y * 0.2)) * smoothstep(0.5, 0.9, n.y);
	col = mix(col, vec3(0.07, 0.13, 0.030), moss * 0.55);
	// snow caps
	float sn = smoothstep(0.62, 0.85, n.y) * smoothstep(430.0, 520.0, p.y);
	col = mix(col, vec3(0.72, 0.78, 0.86), sn * 0.75);
	vec3 ntex = normalize(tri_normal(rock_normal, rock_height, p, tw, 0.25, vec2(0.0), vdir, depth) +
		tri_normal(rock_normal, rock_height, p, tw, 1.20, vec2(0.37, 0.71), vdir, depth * 0.5) * 0.8);
	float rough = mix(tri_scalar(rock_rough, p, tw, 0.25, vec2(0.0)), tri_scalar(rock_rough, p, tw, 1.20, vec2(0.37, 0.71)), 0.4);
	// 0.32 m / 0.11 m detail layers: mineral grains, crystal faces, pits (1 cm features)
	float dpx = max(max(fwidth(p.x), fwidth(p.y)), fwidth(p.z));
	float df = (1.0 - smoothstep(2.2, 4.8, dist)) * (1.0 - smoothstep(0.006, 0.020, dpx));
	if (df > 0.01) {
		vec3 d1 = tri_color(rock_detail_albedo, rock_detail_height, p, tw, 3.125, vec2(0.17, 0.43), vdir, 0.010);
		vec3 d2 = tri_color(rock_detail_albedo, rock_detail_height, p, tw, 9.10, vec2(0.63, 0.29), vdir, 0.004);
		col = mix(col, (d1 * 0.62 + d2 * 0.38) * 1.05, df * 0.85 * detail_mix);
		vec3 dn = normalize(tri_normal(rock_detail_normal, rock_detail_height, p, tw, 3.125, vec2(0.17, 0.43), vdir, 0.010) +
			tri_normal(rock_detail_normal, rock_detail_height, p, tw, 9.10, vec2(0.63, 0.29), vdir, 0.004) * 0.7);
		ntex = normalize(mix(ntex, dn, df * 0.9 * detail_mix));
		rough = mix(rough, 0.82, df * 0.3 * detail_mix);
	}
	col *= mix(vec3(1.0), vcol, 0.55);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.1, 1.0);
	SPECULAR = 0.18;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(ntex, 0.0)).xyz);
}
