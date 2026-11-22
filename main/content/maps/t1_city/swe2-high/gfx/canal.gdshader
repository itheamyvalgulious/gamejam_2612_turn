shader_type spatial;
render_mode cull_back, blend_mix;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(i);
	float b = h21(i + vec2(1, 0));
	float c = h21(i + vec2(0, 1));
	float d = h21(i + vec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 p = wpos.xz;
	float n = vnoise(p * 0.15 + vec2(TIME * 0.5, 0.0)) * 0.6
		+ vnoise(p * 0.5 - vec2(0.0, TIME * 0.8)) * 0.4;
	vec3 deep = vec3(0.02, 0.07, 0.10);
	vec3 sheen = vec3(0.10, 0.20, 0.26);
	vec3 col = mix(deep, sheen, n);
	// city-glow streaks reflected in the canal
	float gl = vnoise(vec2(p.x * 0.8, p.y * 0.06 + TIME * 0.3));
	col += vec3(0.30, 0.22, 0.10) * smoothstep(0.7, 0.9, gl);
	ALBEDO = col;
	ALPHA = 0.92;
	ROUGHNESS = 0.25;
	METALLIC = 0.1;
}
