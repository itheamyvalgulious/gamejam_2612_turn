shader_type spatial;
// 实验罐里的液体：上下渐变 + 缓慢流动的浑浊噪声 + 液面附近的亮带。
render_mode blend_mix, cull_disabled;

uniform vec3 top_col : source_color = vec3(0.16, 0.62, 0.52);
uniform vec3 deep_col : source_color = vec3(0.02, 0.12, 0.13);
uniform float alpha : hint_range(0.0, 1.0) = 0.52;
uniform float glow : hint_range(0.0, 4.0) = 0.50;
uniform float base_y = 0.6;
uniform float span = 5.8;

varying vec3 wp;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.13 + vec2(3.7, 9.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = clamp((wp.y - base_y) / span, 0.0, 1.0);
	vec2 q = wp.xz * 0.40 + vec2(TIME * 0.04, -TIME * 0.025);
	float n = fbm(q + vec2(fbm(q * 1.7), fbm(q * 1.7 + 4.0)) * 0.7);

	vec3 col = mix(deep_col, top_col, h * 0.65 + n * 0.35);
	float surf = smoothstep(0.90, 1.0, h) * (0.55 + 0.45 * n);
	col += top_col * surf * 0.7;

	ALBEDO = col;
	EMISSION = col * glow * (0.20 + 0.55 * n + surf * 0.9);
	ALPHA = alpha * mix(0.80, 1.0, h);
	ROUGHNESS = 0.16;
	METALLIC = 0.0;
}
