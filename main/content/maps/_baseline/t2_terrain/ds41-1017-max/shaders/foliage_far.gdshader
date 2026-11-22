shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 inst;

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
		p = p * 2.05 + vec2(3.1, 8.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	inst = INSTANCE_CUSTOM;
	float ph = INSTANCE_CUSTOM.g * 6.2831;
	VERTEX.x += sin(TIME * 0.7 + ph + wpos.z * 0.02) * 0.12;
}

void fragment() {
	vec3 n = normalize(wnrm);
	float v = fbm3(wpos.xz * 0.55 + wpos.y * 0.35 + inst.r * 9.0);
	float v2 = fbm3(wpos.xz * 2.2 + wpos.y * 0.9);
	vec3 col = mix(vec3(0.022, 0.070, 0.018), vec3(0.065, 0.160, 0.032), v);
	col = mix(col, vec3(0.135, 0.190, 0.040), smoothstep(0.62, 0.9, v2) * 0.5);
	col *= 0.8 + 0.4 * fbm3(wpos.xz * 5.0);
	col *= 0.78 + 0.44 * inst.r;
	col = mix(col, col * vec3(1.15, 1.05, 0.72), smoothstep(0.6, 0.95, inst.b) * 0.5);
	// dark underside / inner canopy
	col *= mix(0.45, 1.0, smoothstep(-0.6, 0.6, n.y));
	ALBEDO = col;
	ROUGHNESS = 0.78;
	SPECULAR = 0.22;
	BACKLIGHT = vec3(0.04, 0.09, 0.015);
	// leaf-clump normal perturbation
	vec3 bump = vec3(fbm3(wpos.zy * 1.3), 0.0, fbm3(wpos.xy * 1.3)) - 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n + bump * 0.8), 0.0)).xyz);
}
