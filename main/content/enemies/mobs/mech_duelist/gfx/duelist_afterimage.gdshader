shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform float opacity = 0.0;

void fragment() {
	float rim = pow(1.0 - max(0.0, dot(normalize(NORMAL), normalize(VIEW))), 1.7);
	ALBEDO = mix(vec3(0.56, 0.035, 0.022), vec3(1.0, 0.28, 0.15), rim);
	ALPHA = opacity * (0.25 + 0.68 * rim);
}
