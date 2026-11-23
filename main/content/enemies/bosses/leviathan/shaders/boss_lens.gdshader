shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ARC SENTINEL — chest optic.
// Coated optical glass: near-black substrate, controlled specular, an aperture
// iris with blade shadowing, a scan wedge and a hot inner core. UV radial.

uniform vec4 glass_color : source_color = vec4(0.008, 0.009, 0.013, 1.0);
uniform vec4 iris_color : source_color = vec4(1.0, 0.115, 0.045, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.72, 0.42, 1.0);
uniform float intensity = 3.6;
uniform float pupil_radius = 0.30;
uniform float blade_count = 7.0;
uniform float ring_frequency = 46.0;
uniform float scan_speed = 0.85;
uniform float seed = 0.0;
uniform float alert = 0.0;
uniform float aperture = 0.55;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float rc = clamp(r, 0.0, 1.0);

	// aperture polygon: blade_count leaves, closing with `aperture`
	float poly = pupil_radius * (1.0 + 0.075 * cos(ang * blade_count + seed));
	poly *= mix(1.16, 0.34, clamp(aperture, 0.0, 1.0));
	float pupil = smoothstep(poly * 1.03, poly * 0.90, r);
	float pupil_edge = smoothstep(poly * 0.78, poly * 1.0, r) * smoothstep(poly * 1.34, poly * 1.02, r);

	// blade seams inside the aperture ring
	float seam = pow(0.5 + 0.5 * cos(ang * blade_count + seed * 0.7), 24.0);
	float blades = seam * smoothstep(poly * 1.62, poly * 1.02, r) * 0.30;

	// iris: thin bright annulus just outside the pupil plus a hot core
	float iris = smoothstep(poly * 1.62, poly * 1.28, r) * smoothstep(poly * 1.02, poly * 1.30, r);
	float outer = smoothstep(0.94, 0.70, r) * smoothstep(0.55, 0.86, r);

	// fine concentric machining rings on the inner barrel
	float rings = pow(0.5 + 0.5 * cos(r * ring_frequency), 22.0) * smoothstep(0.98, 0.45, r) * 0.22;

	// scan wedge sweeping around the optic
	float sweep = pow(0.5 + 0.5 * cos(ang - TIME * scan_speed + seed), 30.0)
		* smoothstep(0.95, 0.16, rc);
	float sweep_soft = pow(0.5 + 0.5 * cos(ang - TIME * scan_speed + seed), 6.0)
		* smoothstep(0.95, 0.20, rc) * 0.12;

	float breathe = 0.86 + 0.14 * sin(TIME * 1.9 + seed * 3.0);
	float hot = pupil * (0.40 + 0.35 * breathe) + pupil_edge * 0.55
		+ iris * (1.15 + 0.25 * breathe) + blades * 0.30 + rings
		+ sweep * 1.35 + sweep_soft;

	// glass body is nearly black; slight radial falloff so it reads as a dome
	ALBEDO = glass_color.rgb * (0.55 + 0.45 * (1.0 - rc * rc));
	METALLIC = 0.0;
	ROUGHNESS = 0.52;
	SPECULAR = 0.08;
	EMISSION = iris_color.rgb * intensity * hot * smoothstep(1.0, 0.86, r)
		+ iris_color.rgb * alert * 1.4 * (iris + outer) * smoothstep(0.96, 0.55, r);
}