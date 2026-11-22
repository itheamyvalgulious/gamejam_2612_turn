shader_type spatial;
// Blade ribbon trail. Vertex color carries age: rgb = plasma tint, alpha = fade.
// The theme tint pulls any legacy warm vertex colour into the blue-white palette.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float energy = 2.1;
uniform vec4 color : source_color = vec4(0.16, 0.44, 1.0, 1.0);
uniform float tint_mix : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float a = COLOR.a;
	float lum = clamp(max(COLOR.r, max(COLOR.g, COLOR.b)), 0.0, 1.0);
	vec3 theme = color.rgb * (0.35 + 0.90 * lum);
	vec3 c = mix(COLOR.rgb, theme, tint_mix);
	ALBEDO = c * a * energy;
	ALPHA = a;
}