// Detailed building glass: dark reflective panes with sparse interior lighting.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float night : hint_range(0.0, 1.0) = 1.0;
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.22;
uniform float wetness : hint_range(0.0, 1.0) = 0.9;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 par;
varying vec3 vtint;

float h13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	par = CUSTOM0 * 255.0;
	par.z /= 255.0;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vtint = COLOR.rgb;
}

void fragment() {
	vec3 n_w = normalize(wnrm);
	// one visible pane = ~1.6 x 3.9 m
	vec2 q = floor(vec2(wpos.x + wpos.z, wpos.y) * vec2(0.55, 0.24));
	float r = h13(vec3(q, par.z * 31.0));
	float r2 = h13(vec3(q.yx, par.z * 7.0 + 3.0));
	float gstyle = par.y;   // 0 upper/opaque, 1 detail see-through, 2 shopfront
	float lit_thr = lit_ratio * (0.4 + 1.2 * fract(par.z * 5.3));
	if (gstyle > 0.5) { lit_thr *= 0.35; }
	float lit = step(1.0 - lit_thr, r);
	lit *= 1.0 - step(0.988, fract(TIME * 0.27 + r2 * 8.0));
	vec3 warm = vec3(1.0, 0.70, 0.38);
	vec3 cool = vec3(0.42, 0.68, 1.0);
	vec3 c = mix(warm, cool, step(0.66, r2));
	vec3 emis = c * lit * (0.35 + 1.05 * r2) * 1.15 * night;
	if (gstyle > 0.5) { emis *= 0.22; }
	// rain droplets / dirty glass
	vec2 dp = wpos.xz * 9.0 + wpos.y * 7.0;
	float drop = smoothstep(0.78, 0.97, vnoise(dp)) * wetness;
	vec3 alb = vec3(0.035, 0.045, 0.055) * (0.8 + 0.4 * vnoise(wpos.xz * 2.0));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = alb * (1.0 - 0.35 * (1.0 - night));
	METALLIC = mix(0.92, 0.55, 1.0 - night);
	ROUGHNESS = clamp(mix(0.10, 0.045, night) + 0.12 * drop + 0.05 * vnoise(wpos.xz * 1.5), 0.03, 0.6);
	// daylight sky sheen on the outer face
	emis += vec3(0.035, 0.045, 0.06) * (1.0 - night) * (0.25 + 0.75 * fres);
	EMISSION = emis;
	float base_a = 0.94;
	if (gstyle > 1.5) { base_a = 0.70; }
	else if (gstyle > 0.5) { base_a = 0.90; }
	ALPHA = clamp(base_a + 0.10 * lit + 0.06 * fres, 0.0, 0.985);
	SPECULAR = 0.75;
}
