shader_type spatial;
// Alpha 混合烟尘/碎屑粒子。同样屏幕空间 billboard，用噪声做出絮状边缘。
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform float softness = 0.85;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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

void vertex() {
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 fwd = INV_VIEW_MATRIX[2].xyz;
	vec3 e1 = right * size;
	vec3 e2 = up * size;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(e1, 0.0), vec4(e2, 0.0), vec4(fwd * size, 0.0),
		vec4(MODEL_MATRIX[3].xyz, 1.0));
}

void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p) * 2.0;
	float n = vnoise(UV * 3.2 + vec2(TIME * 0.07, 0.0));
	float edge = 1.0 - smoothstep(softness * 0.1, 1.0, d);
	float a = edge * (0.55 + 0.45 * n) * COLOR.a;
	ALBEDO = COLOR.rgb * (0.75 + 0.4 * n);
	ALPHA = clamp(a, 0.0, 0.92);
}
