shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv) * 2.0;
	float a = smoothstep(1.0, 0.1, d);
	ALBEDO = vec3(0.92, 0.96, 0.98);
	ALPHA = a * 0.75 * COLOR.a;
	ROUGHNESS = 0.4;
}
