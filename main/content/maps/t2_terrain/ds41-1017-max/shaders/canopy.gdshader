shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

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
		p = p * 2.03 + vec2(7.7, 3.1);
		a *= 0.5;
	}
	return v;
}
float worley(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d = 1.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j)) + vec2(hash12(ip + vec2(float(i), float(j))), hash12(ip + vec2(float(i), float(j)) + 11.0)) - fp;
			d = min(d, dot(g, g));
		}
	}
	return sqrt(d);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR.rgb;
}

void fragment() {
	vec3 p = wpos;
	vec3 n = normalize(wnrm);
	float age = vcol.g;
	// ragged canopy gaps: dark understorey / trunks show through
	float holes = fbm3(p.xz * 0.10 + 9.0);
	if (holes < 0.12 && vcol.r < 0.90) {
		discard;
	}
	float crown = worley(p.xz * 0.045 + age * 3.7);
	float crown2 = worley(p.xz * 0.125 + 3.0);
	float leaf = fbm3(p.xz * 0.75 + 5.0);
	float leaf2 = fbm3(p.xz * 2.7 + vcol.b * 5.0);
	float shade = smoothstep(0.0, 0.55, crown * 0.65 + crown2 * 0.35);
	shade *= 0.58 + 0.55 * leaf;
	vec3 dark = vec3(0.020, 0.055, 0.014);
	vec3 mid = vec3(0.055, 0.130, 0.028);
	vec3 light = vec3(0.115, 0.215, 0.045);
	vec3 col = mix(dark, mid, smoothstep(0.1, 0.8, shade));
	col = mix(col, light, smoothstep(0.55, 0.95, leaf) * smoothstep(0.35, 0.9, shade) * 0.7);
	col = mix(col, vec3(0.135, 0.200, 0.042), smoothstep(0.72, 0.95, leaf2) * 0.45);
	// shadow pockets between crowns
	float gap = smoothstep(0.02, 0.16, crown);
	col *= mix(0.55, 1.0, gap);
	col *= 0.85 + 0.3 * vcol.r;
	// age variation: young yellow-green crowns vs mature dark crowns
	vec3 young = vec3(0.175, 0.265, 0.060);
	vec3 mature = vec3(0.018, 0.052, 0.010);
	col = mix(col, mix(mature, young, smoothstep(0.48, 0.92, age)), 0.72);
	col = mix(col, vec3(0.155, 0.235, 0.052), smoothstep(0.0, 0.55, crown) * 0.28);
	// edge / back-light translucency
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - p);
	float rim = pow(1.0 - abs(dot(n, vdir)), 2.2);
	col += vec3(0.15, 0.24, 0.055) * rim * 0.9;
	ALBEDO = col;
	ROUGHNESS = 0.82;
	SPECULAR = 0.18;
	BACKLIGHT = vec3(0.12, 0.20, 0.030) * (0.40 + 0.60 * rim);
	// leafy normal texture
	float e = 0.6;
	float h0 = fbm3(p.xz * 0.55) + 0.4 * fbm3(p.xz * 2.1);
	float hx = fbm3((p.xz + vec2(e, 0.0)) * 0.55) + 0.4 * fbm3((p.xz + vec2(e, 0.0)) * 2.1);
	float hz = fbm3((p.xz + vec2(0.0, e)) * 0.55) + 0.4 * fbm3((p.xz + vec2(0.0, e)) * 2.1);
	vec3 n2 = normalize(n + vec3(-(hx - h0) / e, 0.0, -(hz - h0) / e) * 0.9);
	NORMAL = normalize((VIEW_MATRIX * vec4(n2, 0.0)).xyz);
}