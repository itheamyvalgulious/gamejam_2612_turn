shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
uniform vec4 tint : source_color = vec4(0.21,0.86,0.92,1.0);
void fragment() {
	float grazing = pow(1.0-clamp(abs(dot(normalize(NORMAL),normalize(VIEW))),0.0,1.0),3.0);
	ALBEDO = mix(vec3(0.78,0.85,0.90),tint.rgb,0.12);
	METALLIC = 0.0;
	ROUGHNESS = 0.13;
	SPECULAR = 0.5;
	ALPHA = 0.055+0.27*grazing;
	// A thin dielectric envelope catches grazing reflections. The light is
	// supplied by the continuous opaque phosphor tube inside this shell.
}
