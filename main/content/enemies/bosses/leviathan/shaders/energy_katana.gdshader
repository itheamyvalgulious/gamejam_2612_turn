shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Electric katana volume. UV.x = across blade width, UV.y = base..tip.
// Layered value-noise strands scroll along the blade; each strand flickers on
// its own phase so the sword reads as contained plasma, not a neon stick.

uniform vec4 core_color : source_color = vec4(1.0, 0.97, 0.70, 1.0);
uniform vec4 arc_color : source_color = vec4(1.0, 0.70, 0.06, 1.0);
uniform float intensity = 2.6;
uniform float arc_density = 7.0;
uniform float arc_speed = 1.7;
uniform float arc_width = 0.036;
uniform float charge = 0.0;
uniform float seed = 0.0;
uniform float body_power = 1.35;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float body = pow(max(0.0, 1.0 - abs(u - 0.5) * 2.0), body_power);
	float plasma = fbm(vec2(v * arc_density * 1.7 - TIME * arc_speed, u * 2.6 + seed));
	float strands = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float ph = fi * 1.618 + seed * 3.7;
		float wob = fbm(vec2(v * arc_density * (0.85 + fi * 0.06) + ph * 1.7,
			TIME * arc_speed * (0.55 + fi * 0.14) + ph)) - 0.5;
		float center = 0.5 + wob * 0.62;
		float w = arc_width * (0.7 + 0.14 * fi);
		float d = abs(u - center);
		float line = exp(-(d * d) / (w * w));
		float pulse = smoothstep(0.2, 0.85, 0.5 + 0.5 * sin(TIME * (7.0 + fi * 2.9) + ph * 9.0));
		strands += line * pulse;
	}
	float tipfade = smoothstep(0.0, 0.035, v) * (1.0 - smoothstep(0.84, 1.0, v));
	float spark = smoothstep(0.82, 1.0, fbm(vec2(v * 90.0, TIME * 6.0 + seed + u * 20.0)));
	float lum = (body * (0.30 + 0.55 * plasma) + strands * 0.85 + spark * body * 0.35) * tipfade;
	vec3 col = mix(arc_color.rgb, core_color.rgb, clamp(strands * 0.55 + body * 0.35, 0.0, 1.0));
	ALBEDO = col * intensity * (1.0 + charge * 1.1);
	ALPHA = clamp(lum * (1.0 + charge * 0.45), 0.0, 1.0);
}