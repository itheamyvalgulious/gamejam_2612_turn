shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, blend_mix;

// Waterfall sheet. UV.u = across (0..1), UV.v = down (0 top -> 1 bottom).
// Fast downward scroll + white streaks + faint magic-cyan emission on foam.

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(11.7, 3.1);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	float u = UV.x;
	float v = UV.y;
	// lateral ripple grows toward the base
	float wob = sin(u * 20.0 - TIME * 6.0 + v * 8.0) * 0.06 * (0.5 + v);
	VERTEX.x += wob;
	VERTEX.y += sin(u * 14.0 + TIME * 7.0 + v * 10.0) * 0.04;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	// high-speed downward flow
	vec2 flow = vec2(u * 2.0, v * 4.0 - TIME * 6.0);
	float streak = fbm(flow);
	vec2 flow2 = vec2(u * 5.0 + v, v * 10.0 - TIME * 16.0);
	float streak2 = fbm(flow2);
	// vertical white streaks
	float vert = smoothstep(0.35, 0.8, fbm(vec2(u * 3.0, v * 30.0 - TIME * 24.0)));
	// foam grows toward the base
	float bottom = smoothstep(0.55, 1.0, v);
	float foam = clamp(streak * 0.5 + streak2 * 0.4 + vert * 0.7 + bottom * 0.5, 0.0, 1.0);
	vec3 col = mix(vec3(0.55, 0.75, 0.80), vec3(0.86, 0.93, 0.95), foam);
	ALBEDO = col * 0.85;
	EMISSION = vec3(0.05, 0.18, 0.20) * foam * 0.5;   // faint magic cyan
	ALPHA = clamp(0.45 + streak * 0.25 + foam * 0.30, 0.0, 1.0);
	ROUGHNESS = 0.3;
	METALLIC = 0.0;
}
