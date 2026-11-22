shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 foam_color : source_color = vec4(0.88, 0.92, 0.94, 1.0);
uniform float strength = 0.8;

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
		p = p * 2.1 + vec2(3.7, 8.1);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float r = length(uv - 0.5) * 2.0;
	float n = fbm3(vec2(uv.x * 128.0, uv.y * 92.0 - TIME * 1.8));
	float n2 = fbm3(vec2(uv.x * 300.0 + 3.0, uv.y * 220.0 - TIME * 3.0));
	float mask = smoothstep(0.30, 0.66, n * 0.55 + n2 * 0.55);
	mask *= 0.55 + 0.45 * smoothstep(0.15, 0.55, n2);
	float edge = smoothstep(1.02, 0.55, r);
	ALBEDO = mix(foam_color.rgb, vec3(0.90, 0.95, 0.99), n2 * 0.4);
	ALPHA = clamp(mask * edge * strength, 0.0, 0.55);
	ROUGHNESS = 0.7;
	SPECULAR = 0.2;
}
