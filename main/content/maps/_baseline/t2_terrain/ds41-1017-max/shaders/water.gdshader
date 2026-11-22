shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 wpos;
varying float pool;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.06 + vec2(9.3, 4.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	pool = COLOR.r;
}

void fragment() {
	vec3 p = wpos;
	// ----------------------------------------------------------- depth
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float scene_z = -vpos.z;
	float thick = clamp(scene_z - (-VERTEX.z), 0.0, 80.0);

	// ----------------------------------------------------------- waves
	vec2 q = vec2(p.x * 0.22, p.z * 0.07 - TIME * 0.55);
	float n0 = fbm3(q);
	float nx = fbm3(q + vec2(0.28, 0.0));
	float nz = fbm3(q + vec2(0.0, 0.28));
	vec2 flow = vec2(p.x * 0.9, p.z * 0.45 - TIME * 1.9);
	float s0 = fbm3(flow);
	float sx = fbm3(flow + vec2(0.18, 0.0));
	float sz = fbm3(flow + vec2(0.0, 0.18));
	float hx = (nx - n0) * 0.55 + (sx - s0) * 0.16;
	float hz = (nz - n0) * 0.55 + (sz - s0) * 0.16;
	vec3 nw = normalize(vec3(-hx * 1.6, 1.0, -hz * 1.6));

	// ----------------------------------------------------------- colour
	vec3 deep = vec3(0.012, 0.052, 0.052);
	vec3 shal = vec3(0.055, 0.185, 0.160);
	vec3 col = mix(shal, deep, smoothstep(0.4, 6.0, thick));
	col = mix(col, vec3(0.085, 0.22, 0.19), pool * 0.30);

	// ----------------------------------------------------------- fresnel / reflection
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - p);
	float fres = pow(1.0 - clamp(dot(nw, vdir), 0.0, 1.0), 5.0);
	vec3 rd = reflect(-vdir, nw);
	vec3 sky_refl = mix(vec3(0.52, 0.62, 0.74), vec3(0.20, 0.34, 0.55), clamp(rd.y, 0.0, 1.0));
	vec2 roff = nw.xz * (0.018 + 0.02 * fres);
	vec3 refl = texture(screen_tex, clamp(SCREEN_UV + roff, vec2(0.001), vec2(0.999))).rgb;
	refl = mix(refl, sky_refl, 0.42);
	col = mix(col, refl, clamp(0.10 + fres * 0.32, 0.0, 0.45));

	// ----------------------------------------------------------- foam
	float foam_n = fbm3(vec2(p.x * 0.95 + p.z * 0.25, p.z * 0.35 - TIME * 1.6));
	float foam_s = fbm3(vec2(p.x * 2.8, p.z * 1.0 - TIME * 3.4));
	float shore = smoothstep(0.42, 0.0, thick);
	float foam = smoothstep(0.62, 0.82, foam_n * 0.65 + foam_s * 0.35 + shore * 0.30);
	foam += smoothstep(0.78, 0.95, foam_s) * 0.10;
	foam *= smoothstep(0.0, 0.2, thick + pool * 0.25);
	foam += pool * smoothstep(0.4, 0.75, foam_n) * 0.35;
	col = mix(col, vec3(0.78, 0.84, 0.85), clamp(foam, 0.0, 0.28));

	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = mix(0.14, 0.28, foam);
	SPECULAR = 0.32;
	METALLIC = 0.0;
	ALPHA = clamp(0.58 + thick * 0.12 + foam * 0.25, 0.50, 0.97);
}
