shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	ALBEDO = vcol.rgb * vcol.a * 4.0;
	ALPHA = 1.0;
}
