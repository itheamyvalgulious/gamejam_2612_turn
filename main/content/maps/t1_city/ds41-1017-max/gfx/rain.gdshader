// Rain streaks: soft vertical line with a bright head, additive-ish.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.62, 0.72, 0.95);
uniform float alpha = 0.30;

void fragment() {
	vec2 uv = UV;
	float x = abs(uv.x - 0.5) * 2.0;
	float body = smoothstep(1.0, 0.0, x);
	float head = smoothstep(0.35, 0.0, uv.y);
	float tail = smoothstep(0.0, 0.55, uv.y) * 0.7;
	float m = body * mix(0.35, 1.0, head) * (1.0 - tail);
	ALBEDO = tint;
	EMISSION = tint * 0.35 * m;
	ALPHA = m * alpha * COLOR.a;
}