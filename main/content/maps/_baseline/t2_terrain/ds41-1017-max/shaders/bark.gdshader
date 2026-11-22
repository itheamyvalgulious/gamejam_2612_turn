shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

varying vec3 wpos;

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
		p = p * 2.02 + vec2(5.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ridge = fbm3(vec2(UV.x * 26.0, UV.y * 1.3));
	float ridge2 = fbm3(vec2(UV.x * 6.0, UV.y * 0.5));
	vec3 col = mix(vec3(0.095, 0.080, 0.062), vec3(0.235, 0.205, 0.165), ridge * 0.7 + ridge2 * 0.3);
	float moss = smoothstep(0.50, 0.78, fbm3(vec2(wpos.x, wpos.z) * 0.35 + 4.0 + wpos.y * 0.02));
	moss *= smoothstep(0.38, 0.62, fbm3(vec2(UV.x * 3.0, UV.y * 0.7)));
	col = mix(col, vec3(0.105, 0.185, 0.065), moss * 0.55);
	float lichen = smoothstep(0.72, 0.86, fbm3(vec2(UV.x * 9.0, UV.y * 2.2) + 11.0));
	col = mix(col, vec3(0.42, 0.45, 0.33), lichen * 0.35);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
