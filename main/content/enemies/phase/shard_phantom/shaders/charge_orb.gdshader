shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Palm charge orb: a small additive sphere, no billboard and no square edge.
uniform vec4 hot_color : source_color = vec4(1.0, 0.92, 0.72, 1.0);
uniform vec4 energy_color : source_color = vec4(1.0, 0.22, 0.035, 1.0);
uniform float intensity = 2.6;

void fragment() {
	float f = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float ball = pow(f, 1.35);
	float rim = pow(1.0 - f, 2.2) * 0.22;
	float pulse = 0.82 + 0.18 * sin(TIME * 24.0);
	ALBEDO = mix(energy_color.rgb, hot_color.rgb, pow(f, 2.4)) * intensity * pulse;
	ALPHA = clamp((ball + rim) * 0.92, 0.0, 1.0);
}
