shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

varying vec3 wpos;
varying vec3 wnrm;

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
		p = p * 2.03 + vec2(7.1, 3.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float ph = INSTANCE_CUSTOM.g * 6.2831;
	float sway = sin(TIME * 1.15 + wpos.x * 0.09 + wpos.z * 0.07 + ph) * 0.10;
	sway += sin(TIME * 2.3 + wpos.y * 0.4 + ph * 2.0) * 0.035;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
}

void fragment() {
	float seed = COLOR.r;
	vec2 uv = UV;
	// clustered tropical leaves: each cell carries one leaf
	float alpha = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		vec2 q = uv * vec2(3.3, 3.3) + vec2(float(layer) * 0.37, float(layer) * 0.61) + seed * 3.7;
		vec2 id = floor(q);
		vec2 f = fract(q) - 0.5;
		float rnd = hash12(id + seed * 13.0 + float(layer) * 3.1);
		vec2 off = vec2(hash12(id + 4.0), hash12(id + 9.0)) - 0.5;
		off *= 0.28;
		float d = length((f - off) * vec2(1.0, 0.72));
		float r = 0.30 + 0.12 * rnd;
		float leaf = smoothstep(r, r - 0.055, d);
		leaf *= step(0.12, rnd);
		alpha = max(alpha, leaf * (1.0 - float(layer) * 0.25));
	}
	alpha = max(alpha, smoothstep(0.75, 0.94, fbm3(uv * 4.5 + seed)) * 0.85);
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.42;
	if (alpha < 0.42) {
		discard;
	}

	vec3 n = normalize(wnrm);
	if (!FRONT_FACING) {
		n = -n;
	}
	float varn = fbm3(uv * 3.0 + seed * 7.0);
	vec3 leaf_a = vec3(0.040, 0.125, 0.022);
	vec3 leaf_b = vec3(0.095, 0.225, 0.040);
	vec3 col = mix(leaf_a, leaf_b, varn * 0.7 + seed * 0.3);
	col = mix(col, vec3(0.20, 0.235, 0.045), smoothstep(0.72, 0.95, fbm3(uv * 1.7 + 5.0)) * 0.35);
	float vein = 1.0 - smoothstep(0.0, 0.06, abs(fract(uv.x * 3.3 + seed) - 0.5));
	col *= 0.92 + 0.10 * vnoise(vec2(uv.x * 20.0, uv.y * 6.0));
	ALBEDO = col;
	ROUGHNESS = 0.62;
	SPECULAR = 0.28;
	BACKLIGHT = vec3(0.06, 0.12, 0.02);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
