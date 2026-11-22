shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled;

// Procedural cloud deck: fBm coverage on a high plane, soft edges, sun-lit tops,
// grey undersides, horizon fade. Pure math - no textures.

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
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1,0,0)), f.x),
			mix(hash13(i + vec3(0,1,0)), hash13(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0,0,1)), hash13(i + vec3(1,0,1)), f.x),
			mix(hash13(i + vec3(0,1,1)), hash13(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p, int oct) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= oct) break;
		s += a * vnoise(p);
		p = p * 2.07 + vec3(9.2);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_world.xz * 0.00042;
	float t = TIME * 0.006;
	float base = fbm(vec3(uv * 2.6 + vec2(t, t * 0.35), t * 0.4), 5);
	float detail = fbm(vec3(uv * 8.0 - vec2(t * 1.6, t * 0.4), 3.1), 4);
	float cov = base * 0.72 + detail * 0.38;
	float d = smoothstep(0.44, 0.72, cov);
	// billowy top lighting vs grey underside
	vec3 col = mix(vec3(0.66, 0.70, 0.78), vec3(1.0, 0.99, 0.97), smoothstep(0.40, 0.75, base));
	col = mix(col, vec3(0.50, 0.54, 0.63), smoothstep(0.60, 0.92, detail) * 0.40);
	// fade at deck rim so the plane edge never shows
	float r = length(v_world.xz - vec2(2000.0, 1250.0));
	float rim = 1.0 - smoothstep(6200.0, 7800.0, r);
	ALBEDO = col;
	ALPHA = d * 0.92 * rim;
}
