shader_type spatial;
render_mode cull_back;

// Procedural boulder rock: macro mottle + strata + scale-invariant micro bump.

varying vec3 v_world;
varying vec3 v_nworld;

uint _ih(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}
float hash13(vec3 p) {
	ivec3 i = ivec3(floor(p + 0.5));
	uint u = _ih(uint(i.x) + _ih(uint(i.y) + _ih(uint(i.z))));
	return float(u) * (1.0 / 4294967295.0);
}
vec3 gdir(vec3 i) {
	vec3 h = vec3(hash13(i + vec3(7, 0, 0)), hash13(i + vec3(0, 13, 0)), hash13(i + vec3(0, 0, 29))) * 2.0 - 1.0;
	return normalize(h + vec3(1e-5));
}
float gnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = dot(gdir(i), f);
	float n100 = dot(gdir(i + vec3(1, 0, 0)), f - vec3(1, 0, 0));
	float n010 = dot(gdir(i + vec3(0, 1, 0)), f - vec3(0, 1, 0));
	float n110 = dot(gdir(i + vec3(1, 1, 0)), f - vec3(1, 1, 0));
	float n001 = dot(gdir(i + vec3(0, 0, 1)), f - vec3(0, 0, 1));
	float n101 = dot(gdir(i + vec3(1, 0, 1)), f - vec3(1, 0, 1));
	float n011 = dot(gdir(i + vec3(0, 1, 1)), f - vec3(0, 1, 1));
	float n111 = dot(gdir(i + vec3(1, 1, 1)), f - vec3(1, 1, 1));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}
float fbm(vec3 p, int oct) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 5; i++) {
		if (i >= oct) break;
		s += a * (gnoise(p) * 0.5 + 0.5);
		p = p * 2.17 + vec3(9.1);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nworld = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 W = v_world;
	vec3 N = normalize(v_nworld);
	float n1 = fbm(W * 2.5, 4);
	vec3 col = mix(vec3(0.18, 0.16, 0.13), vec3(0.28, 0.25, 0.21), n1);
	col *= 0.92 + 0.16 * (gnoise(W * 8.0) * 0.5 + 0.5);
	// faint strata bands
	float band = sin(W.y * 3.5 + fbm(W * 1.2, 3) * 4.0) * 0.5 + 0.5;
	col = mix(col, col * 0.72, smoothstep(0.6, 0.9, band) * 0.5);
	// lichen patches
	col = mix(col, vec3(0.14, 0.18, 0.10), smoothstep(0.62, 0.8, fbm(W * 0.9 + 3.0, 3)) * 0.4);
	// scale-invariant micro bump
	vec3 camW = (INV_VIEW_MATRIX * vec4(0, 0, 0, 1)).xyz;
	float e = clamp(length(camW - W) * 0.0012, 0.02, 0.5);
	float h0 = gnoise(W * 6.0) + 0.4 * gnoise(W * 16.0 + 11.0) + 0.25 * gnoise(W * 60.0);
	float hx = gnoise((W + vec3(e, 0, 0)) * 6.0) + 0.4 * gnoise((W + vec3(e, 0, 0)) * 16.0 + 11.0) + 0.25 * gnoise((W + vec3(e, 0, 0)) * 60.0);
	float hz = gnoise((W + vec3(0, 0, e)) * 6.0) + 0.4 * gnoise((W + vec3(0, 0, e)) * 16.0 + 11.0) + 0.25 * gnoise((W + vec3(0, 0, e)) * 60.0);
	vec3 grad = vec3((hx - h0) / e, 0.0, (hz - h0) / e);
	vec3 gT = grad - N * dot(N, grad);
	NORMAL = normalize(mat3(VIEW_MATRIX) * normalize(N - gT * 1.1));
	ALBEDO = col;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
}
