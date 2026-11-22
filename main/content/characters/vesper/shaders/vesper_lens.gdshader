shader_type spatial;
// =============================================================================
// VESPER // blue boss optic
// -----------------------------------------------------------------------------
// Port of the ARC SENTINEL boss eye (arc_lens.gdshader) in the VESPER palette:
// a coated near-black glass dome with a polygonal 7-blade aperture that
// breathes, a thin bright iris annulus, a white-hot core, machine-turned
// rings on the inner barrel, and a scan wedge sweeping around the optic.
//
// Radial coordinates come from the dome's OBJECT-space XZ plane (the dome's
// pole faces the viewer), so the iris is a clean disc on the eye, not a UV
// wrap around the hemisphere.
// =============================================================================
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 glass_color : source_color = vec4(0.004, 0.008, 0.018, 1.0);
uniform vec4 iris_color  : source_color = vec4(0.08, 0.32, 1.0, 1.0);
uniform vec4 core_color  : source_color = vec4(0.48, 0.76, 1.0, 1.0);
uniform vec4 hot_color   : source_color = vec4(0.85, 0.96, 1.0, 1.0);
uniform vec4 rim_color   : source_color = vec4(0.02, 0.08, 0.30, 1.0);

uniform float intensity = 3.2;
uniform float lens_radius = 0.062;
uniform float pupil_radius = 0.30;
uniform float iris_radius = 0.58;
uniform float blade_count = 7.0;
uniform float iris_speed = 0.55;
uniform float pulse_speed = 1.7;
uniform float scan_speed = 0.85;
uniform float ring_frequency = 46.0;
uniform float aperture = 0.62;
uniform float alert = 0.0;
uniform float seed = 0.0;
uniform float phase = 0.0;

varying vec3 opos;

void vertex() {
	opos = VERTEX;
}

void fragment() {
	float t = TIME;
	float inv_r = 1.0 / max(lens_radius, 0.001);
	float r = clamp(length(opos.xz) * inv_r, 0.0, 1.0);
	float ang = atan(opos.z, opos.x);

	// ---- breathing aperture: 7 blades, slowly rotating -------------------
	float open = clamp(aperture + 0.22 * sin(t * pulse_speed + phase + seed * 2.7), 0.0, 1.0);
	float poly_scale = mix(0.38, 1.18, open);
	float ang_t = ang + t * iris_speed;
	float poly = pupil_radius * (1.0 + 0.075 * cos(ang_t * blade_count + seed));
	poly *= poly_scale;

	// ---- pupil: dark aperture with a faint blue floor -------------------
	float pupil = smoothstep(poly * 1.03, poly * 0.90, r);
	float pupil_edge = smoothstep(poly * 0.78, poly * 1.0, r) * smoothstep(poly * 1.34, poly * 1.02, r);

	// ---- blade seams on the aperture ring -------------------------------
	float seam = pow(0.5 + 0.5 * cos(ang_t * blade_count + seed * 0.7), 24.0);
	float blades = seam * smoothstep(poly * 1.70, poly * 1.02, r) * 0.30;

	// ---- iris annulus + hot core ----------------------------------------
	float iris = smoothstep(poly * 1.62, poly * 1.24, r) * smoothstep(poly * 1.00, poly * 1.30, r);
	float outer = smoothstep(0.95, 0.70, r) * smoothstep(0.52, 0.86, r);

	// ---- machine-turned rings on the inner barrel -----------------------
	float rings = pow(0.5 + 0.5 * cos(r * ring_frequency), 22.0) * smoothstep(0.98, 0.45, r) * 0.22;

	// ---- scan wedge ------------------------------------------------------
	float sweep = pow(0.5 + 0.5 * cos(ang - t * scan_speed + seed), 30.0) * smoothstep(0.95, 0.16, r);
	float sweep_soft = pow(0.5 + 0.5 * cos(ang - t * scan_speed + seed), 6.0) * smoothstep(0.95, 0.20, r) * 0.10;

	float breathe = 0.86 + 0.14 * sin(t * 1.9 + seed * 3.0);
	float hot = pupil * (0.10 + 0.20 * breathe) + pupil_edge * 0.50
		+ iris * (1.10 + 0.25 * breathe) + blades * 0.30 + rings
		+ sweep * 1.30 + sweep_soft;

	// ---- optical glass body ---------------------------------------------
	vec3 glass = glass_color.rgb * (0.55 + 0.45 * (1.0 - r * r));
	ALBEDO = glass;
	METALLIC = 0.0;
	ROUGHNESS = 0.14;
	SPECULAR = 0.55;

	vec3 glow = iris_color.rgb * intensity * hot * smoothstep(1.0, 0.86, r);
	glow += core_color.rgb * intensity * 0.55 * pow(pupil, 2.0) * breathe;
	glow += hot_color.rgb * intensity * 0.35 * pupil_edge;
	glow += rim_color.rgb * 0.45 * outer;
	glow += iris_color.rgb * alert * 1.4 * (iris + outer) * smoothstep(0.96, 0.55, r);
	EMISSION = glow;

	// glass is opaque: only the iris/core genuinely emit
	ALPHA = 1.0;
}