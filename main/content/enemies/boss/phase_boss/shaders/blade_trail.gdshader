shader_type spatial;
// Blade ribbon trail.  Vertex color carries age: rgb = plasma tint, alpha = fade.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform float energy = 2.2;

void fragment() {
	float a = COLOR.a;
	ALBEDO = COLOR.rgb * a * energy;
	ALPHA = a;
}