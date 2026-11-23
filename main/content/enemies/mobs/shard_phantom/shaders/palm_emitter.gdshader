shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// Palm launcher aperture.  Radial UV (0.5,0.5 at the centre): a machined
// housing, a bright containment ring, twelve iris blades and a hot core.
// Deliberately low specular so stage lights cannot turn it into a white mirror.

uniform vec4 housing : source_color = vec4(0.012, 0.012, 0.014, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.20, 0.04, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.62, 0.26, 1.0);
uniform float intensity = 2.2;
uniform float charge = 0.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float ring = smoothstep(0.10, 0.0, abs(r - 0.74));
	float ring2 = smoothstep(0.04, 0.0, abs(r - 0.56)) * 0.35;
	float iris = smoothstep(0.52, 0.34, r) * smoothstep(0.20, 0.28, r);
	float blades = pow(0.5 + 0.5 * cos(a * 12.0 + TIME * 1.6 + seed), 9.0)
		* smoothstep(0.60, 0.18, r);
	float core = smoothstep(0.20, 0.02, r);
	float pulse = 0.86 + 0.14 * sin(TIME * 2.4 + seed);
	ALBEDO = housing.rgb;
	METALLIC = 0.45;
	ROUGHNESS = 0.40;
	SPECULAR = 0.28;
	EMISSION = rim_color.rgb * intensity * (ring * 1.1 + ring2 + iris * 0.75 + blades * 0.45) * pulse
		+ core_color.rgb * core * (1.5 + charge * 5.0)
		+ rim_color.rgb * charge * (ring * 1.4 + blades * 0.8);
}
