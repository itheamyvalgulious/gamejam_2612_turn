shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0, 0.21, 0.052, 1.0);
uniform float strength = 1.0;
uniform float length_world = 24.0;
uniform float phase = 0.0;

void fragment() {
	float cross_lane = abs(UV.x * 2.0 - 1.0);
	float edge = smoothstep(0.78, 0.89, cross_lane) * (1.0 - smoothstep(0.92, 1.0, cross_lane));
	float wave = smoothstep(0.73, 0.95, fract(UV.y * length_world * 0.51 - TIME * 0.9 - cross_lane * 0.40));
	float distance_along = UV.y * length_world;
	float start_fade = min(length_world * 0.035, 1.5);
	float tail_fade = min(length_world * 0.03, 1.5);
	float end_fade = smoothstep(0.0, max(start_fade, 0.001), distance_along)
		* smoothstep(0.0, max(tail_fade, 0.001), length_world - distance_along);
	ALBEDO = color.rgb * (0.68 + phase * 0.40);
	ALPHA = (0.04 + edge * 0.51 + wave * 0.19) * strength * end_fade;
}
