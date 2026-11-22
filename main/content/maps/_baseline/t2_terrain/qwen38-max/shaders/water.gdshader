shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

uniform vec3 u_deep : source_color = vec3(0.010, 0.075, 0.150);
uniform vec3 u_shallow : source_color = vec3(0.05, 0.34, 0.36);
uniform float u_wave_amp : hint_range(0.0, 2.0) = 0.6;
uniform sampler2D u_depth : hint_depth_texture;

varying vec3 v_world;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1,0,0));
	float n010 = hash13(i + vec3(0,1,0));
	float n110 = hash13(i + vec3(1,1,0));
	float n001 = hash13(i + vec3(0,0,1));
	float n101 = hash13(i + vec3(1,0,1));
	float n011 = hash13(i + vec3(0,1,1));
	float n111 = hash13(i + vec3(1,1,1));
	return mix(mix(mix(n000,n100,f.x), mix(n010,n110,f.x), f.y),
		mix(mix(n001,n101,f.x), mix(n011,n111,f.x), f.y), f.z);
}
float fbm(vec3 p, int oct) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 5; i++) {
		if (i >= oct) break;
		s += a * vnoise(p);
		p = p * 2.03 + vec3(7.7);
		a *= 0.5;
	}
	return s;
}
float wave_h(vec2 uv, float t) {
	float h = fbm(vec3(uv * 0.10, t * 0.5), 3) * 0.7;
	h += fbm(vec3(uv * 0.45 + vec2(t * 0.9, -t * 0.6), t * 0.4), 2) * 0.3;
	return h;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_world.xz;
	float t = TIME * 0.5;
	float e = 0.4;
	float h0 = wave_h(uv, t);
	float hx = wave_h(uv + vec2(e, 0.0), t);
	float hz = wave_h(uv + vec2(0.0, e), t);
	vec3 Nw = normalize(vec3(-(hx - h0) / e * u_wave_amp, 1.0, -(hz - h0) / e * u_wave_amp));
	NORMAL = normalize(mat3(VIEW_MATRIX) * Nw);

	// scene depth for shallow/deep + foam
	float dpt = texture(u_depth, SCREEN_UV).x;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, dpt * 2.0 - 1.0, 1.0);
	vec3 sc = up.xyz / up.w;
	float sceneDepth = -sc.z;
	float fragDepth = -VERTEX.z;
	float d = max(sceneDepth - fragDepth, 0.0);

	vec3 base = mix(u_shallow, u_deep, 1.0 - exp(-d * 0.10));
	float foam_n = fbm(vec3(uv * 0.6, t * 0.6), 3);
	float foam = smoothstep(1.2, 0.1, d) * (0.3 + 0.7 * foam_n);
	base = mix(base, vec3(0.92, 0.95, 0.97), clamp(foam, 0.0, 1.0) * 0.85);

	ALBEDO = base;
	ROUGHNESS = mix(0.30, 0.05, 1.0 - clamp(foam, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = clamp(0.5 + d * 0.10 + foam * 0.5, 0.0, 1.0);
}
