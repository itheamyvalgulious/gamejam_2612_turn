shader_type spatial;
render_mode unshaded, cull_back;
void fragment() {
	ALBEDO = NORMAL * 0.5 + 0.5;
}
