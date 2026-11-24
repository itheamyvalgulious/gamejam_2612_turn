shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 tint : source_color = vec4(0.21,0.86,0.92,1.0);
uniform float radiance = 3.2;
void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL),normalize(VIEW))),0.0,1.0);
	// Cross-sectional diffusion gives the cylinder depth. No axial modulation,
	// time-driven hotspots, dashes or moving bright beads anywhere along it.
	vec3 phosphor = mix(tint.rgb,vec3(1.0),0.10+0.10*pow(facing,2.0));
	ALBEDO = tint.rgb*0.22;
	ROUGHNESS = 0.42;
	METALLIC = 0.0;
	SPECULAR = 0.18;
	EMISSION = phosphor*radiance*(0.88+0.12*facing);
}
