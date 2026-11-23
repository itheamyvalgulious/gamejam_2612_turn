shader_type spatial;
// 实验室地面：一套 shader 支持三种铺装
//   wet     湿水泥（积水 + 反光）
//   epoxy   环氧自流平（大块浅色地坪 + 化学污渍，微反光）
//   grating 金属格栅（条状钢板 + 缝隙）
uniform vec3 base_col : source_color = vec3(0.10, 0.11, 0.12);
uniform vec3 grout_col : source_color = vec3(0.03, 0.035, 0.04);
uniform vec3 stain_col : source_color = vec3(0.08, 0.12, 0.09);
uniform float tile = 1.6;
uniform float grout = 0.012;
uniform float stain = 0.35;
uniform float wet = 0.10;
uniform float grating = 0.0;
uniform float rough = 0.35;
uniform float metal = 0.05;

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
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(7.1, 3.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wp.xz;
	vec2 cell = uv / tile;
	vec2 g = fract(cell);
	vec2 id = floor(cell);

	float edge = min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y));
	float grout_mask = 1.0 - smoothstep(0.0, max(grout / tile, 0.0001), edge);

	float tint = 0.86 + 0.26 * hash21(id + 1.7);
	vec3 col = base_col * tint;

	// 化学污渍（偏绿/偏黄的不规则斑块）
	float st = fbm(uv * 0.45 + vec2(3.3, 8.1));
	col = mix(col, stain_col, smoothstep(0.52, 0.80, st) * stain);

	col = mix(col, grout_col, grout_mask);

	// 积水 / 反光
	float pud = smoothstep(0.60, 0.74, fbm(uv * 0.50 + 11.0));
	col = mix(col, col * 0.55, pud * wet);

	// 金属格栅：横向条板 + 缝隙
	if (grating > 0.5) {
		float gx = fract(uv.x / 0.14);
		float bar = smoothstep(0.08, 0.16, gx) * (1.0 - smoothstep(0.72, 0.80, gx));
		col = mix(col * 0.12, col, bar);
	}

	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.06, pud * wet);
	METALLIC = metal;
	SPECULAR = 0.5;
}
