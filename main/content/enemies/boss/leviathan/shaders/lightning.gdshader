shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Thin lightning ribbon. UV.x across the ribbon, UV.y = 0 base .. 1 tip.
// Intended for arc_points() ribbons: branch arcs, ground strikes, coil bleed.

uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.80, 1.0);
uniform vec4 arc_color : source_color = vec4(1.0, 0.72, 0.10, 1.0);
uniform float intensity = 4.5;
uniform float seed = 0.0;
uniform float pulse_speed = 26.0;
uniform float fade_in = 0.06;
uniform float fade_out = 0.85;

void fragment() {
	float edge = 1.0 - abs(UV.x - 0.5) * 2.0;
	float core = pow(max(edge, 0.0), 2.2);
	float along = smoothstep(0.0, fade_in, UV.y) * (1.0 - smoothstep(fade_out, 1.0, UV.y));
	float pulse = 0.45 + 0.55 * pow(0.5 + 0.5 * sin(UV.y * 34.0 - TIME * pulse_speed + seed * 17.0), 1.6);
	float gate = smoothstep(0.25, 0.55, 0.5 + 0.5 * sin(TIME * 11.0 + seed * 31.0));
	vec3 col = mix(arc_color.rgb, core_color.rgb, core);
	ALBEDO = col * intensity * (0.6 + 0.6 * pulse);
	ALPHA = clamp(core * along * pulse * (0.55 + 0.45 * gate), 0.0, 1.0);
}