shader_type spatial;
// 室内瓷砖 / 水泥地面：世界坐标切砖，砖缝、污渍、湿地。

uniform vec3 base_col : source_color = vec3(0.13, 0.14, 0.145);
uniform vec3 grout_col : source_color = vec3(0.035, 0.037, 0.04);
uniform float tile = 0.6;
uniform float grout = 0.035;
uniform float stain = 0.55;
uniform float wet = 0.30;

varying vec3 wp;
varying vec3 wn;

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
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p = p * 2.07 + vec2(7.1, 3.7);
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wn);
	bool is_floor = abs(n.y) > 0.5;

	vec2 uv = is_floor
		? wp.xz
		: (abs(n.x) > abs(n.z) ? vec2(wp.z, wp.y) : vec2(wp.x, wp.y));

	vec2 cell = uv / tile;
	vec2 g = fract(cell);
	vec2 id = floor(cell);

	float edge = min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y));
	float grout_mask = 1.0 - smoothstep(0.0, grout / tile, edge);

	float tint = 0.82 + 0.30 * hash21(id + 3.7);
	vec3 col = base_col * tint;

	// 污渍：越靠地面/墙角越脏
	float grime = fbm(uv * 0.9 + 5.0);
	float low = is_floor ? 1.0 : clamp(1.0 - wp.y / 2.6, 0.0, 1.0);
	col *= mix(1.0, 0.62, low * smoothstep(0.45, 0.85, grime) * stain);

	col = mix(col, grout_col, grout_mask);

	// 湿地面：低粗糙度水膜 + 积水
	float puddle = is_floor ? smoothstep(0.62, 0.74, fbm(uv * 0.55 + 11.0)) : 0.0;
	col = mix(col, col * 0.55, puddle * wet);

	ALBEDO = col;
	ROUGHNESS = is_floor ? mix(0.55, 0.06, puddle) : 0.68;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
