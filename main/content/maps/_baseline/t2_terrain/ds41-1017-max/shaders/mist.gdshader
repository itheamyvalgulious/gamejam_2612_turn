shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

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
		p = p * 2.02 + vec2(4.1, 7.3);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv) * 2.0;
	float soft = smoothstep(1.0, 0.0, d);
	soft *= soft;
	float n = fbm3(UV * 3.5 + vec2(TIME * 0.02, -TIME * 0.03));
	float a = soft * (0.30 + 0.45 * n);
	ALBEDO = vec3(0.82, 0.87, 0.92);
	ALPHA = clamp(a * COLOR.a * 1.2, 0.0, 0.25);
	ROUGHNESS = 1.0;
}
