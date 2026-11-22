shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.22, 0.03, 1.0);
uniform float intensity = 1.0;

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float core = smoothstep(0.55, 0.0, across);
	float edge = smoothstep(1.0, 0.15, across);
	float along = clamp(UV.y, 0.0, 1.0);
	float life = smoothstep(0.0, 0.18, along) * (0.35 + 0.65 * along);
	float flick = 0.82 + 0.18 * sin(TIME * 31.0 + UV.y * 12.0);
	ALBEDO = tint.rgb * (core * 2.2 + edge * 0.8) * intensity * life * flick;
	ALPHA = clamp((core * 0.9 + edge * 0.25) * life, 0.0, 1.0);
}
