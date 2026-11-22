shader_type sky;
// Night sky: gradient + city light dome + drifting cloud layer + stars.
uniform vec4 zenith : source_color = vec4(0.004, 0.005, 0.014, 1.0);
uniform vec4 horizon : source_color = vec4(0.10, 0.06, 0.16, 1.0);
uniform vec4 dome : source_color = vec4(0.30, 0.12, 0.20, 1.0);
uniform float dome_strength = 0.55;
uniform float star_scale = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.17 + 9.1; a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon.rgb, zenith.rgb, smoothstep(-0.02, 0.42, h));
	// city light dome hugging the horizon
	col += dome.rgb * pow(max(0.0, 1.0 - abs(h) * 2.2), 4.0) * dome_strength;
	// cloud layer (projected plane fbm), lit from below by the city
	float cl = fbm(d.xz / max(abs(h) + 0.12, 0.12) * 0.55 + vec2(TIME * 0.004, TIME * 0.0015));
	float cm = smoothstep(0.48, 0.86, cl) * smoothstep(-0.02, 0.14, h);
	col = mix(col, vec3(0.050, 0.038, 0.080) + dome.rgb * 0.30, cm * 0.85);
	// stars
	vec2 sp = d.xz / (abs(h) + 0.35) * 140.0 + vec2(d.y * 40.0);
	vec2 cell = floor(sp);
	float st = step(0.9975, hash21(cell));
	col += vec3(0.8, 0.85, 1.0) * st * smoothstep(0.08, 0.35, h) *
			(0.35 + 0.65 * hash21(cell + 1.0)) * (1.0 - cm) * star_scale;
	COLOR = col;
}
