shader_type spatial;
// Flat additive shock ring / slash arc.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0, 0.38, 0.08, 1.0);
uniform float energy = 1.6;
uniform float inner_softness = 0.55;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = smoothstep(1.0, 0.55, d) * smoothstep(inner_softness, 0.85, d);
	// radial streaks make it read as a pressure wave, not a flat disc
	float ang = atan(p.y, p.x);
	a *= 0.72 + 0.28 * sin(ang * 21.0 + TIME * 5.0);
	ALBEDO = color.rgb * energy * (0.4 + a);
	ALPHA = a;
}