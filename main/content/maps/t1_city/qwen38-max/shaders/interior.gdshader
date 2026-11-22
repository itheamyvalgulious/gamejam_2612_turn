shader_type spatial;
render_mode cull_disabled;
// Interior surfaces: COLOR.rgb = albedo tint, CUSTOM0.x = emissive factor.

void fragment() {
	ALBEDO = COLOR.rgb * 0.7;
	ROUGHNESS = 0.8;
	METALLIC = 0.0;
	EMISSION = COLOR.rgb * UV2.x * 1.1;
}
