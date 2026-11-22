shader_type spatial;
render_mode blend_add, unshaded, cull_disabled;
// Fake light pool decal on the ground. UV 0..1 across quad.
uniform vec4 pool_color : source_color = vec4(1.0, 0.75, 0.45, 1.0);
uniform float strength = 0.85;

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = (1.0 - smoothstep(0.15, 1.0, d));
	a *= a;
	ALBEDO = pool_color.rgb * a * strength;
	ALPHA = 1.0;
}
