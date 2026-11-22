shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 tint : source_color = vec4(0.21,0.86,0.92,1.0);
uniform float speed = 0.65;
void fragment() {
	// Frosted diffuser: bright core, cylindrical surface shading and gentle flow.
	float wave = pow(0.5+0.5*sin(UV.y*6.283185-TIME*speed),6.0);
	float face = pow(abs(dot(normalize(NORMAL),normalize(VIEW))),0.6);
	vec3 phosphor = mix(tint.rgb,vec3(0.92,0.97,1.0),0.38);
	ALBEDO = mix(tint.rgb,vec3(0.65),0.4)*0.35;
	ROUGHNESS = 0.28;
	METALLIC = 0.05;
	EMISSION = phosphor*(1.1+1.2*face)*(0.96+0.04*wave);
}
