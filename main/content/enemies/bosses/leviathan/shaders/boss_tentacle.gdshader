shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// =============================================================================
// LEVIATHAN - uniform mechanical chain limb
// UV: u = around the tube (0..1), v = arc length in METRES from the socket.
// Each 0.62 m link is nearly the same diameter: no octopus taper, no suckers.
// Link necks, joint bolts, a longitudinal light channel and sparse scratches
// carry the mechanical read. Shader pattern is locked to the base.
// =============================================================================

uniform vec4 albedo_color : source_color = vec4(0.031, 0.032, 0.039, 1.0);
uniform vec4 link_color : source_color = vec4(0.055, 0.056, 0.066, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.18, 0.030, 1.0);
uniform vec4 trim_color : source_color = vec4(0.48, 0.49, 0.54, 1.0);
uniform float glow_energy = 1.6;
uniform float role = 0.0;       // 0 idle, 1 support, 2 attack, 3 retract
uniform float charge = 0.0;
uniform float length_m = 6.0;
uniform float metallic : hint_range(0.0, 1.0) = 1.0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.40;
uniform float seed = 0.0;
uniform float wave_energy = 1.0;

varying vec3 opos;
varying vec3 onrm;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + vec2(7.1, 3.3)) * 0.30
		+ vnoise(p * 4.11 + vec2(1.7, 9.2)) * 0.15;
}

void vertex() {
	opos = VERTEX;
	onrm = normalize(NORMAL);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float period = 0.62;
	float seg = fract(v / period);
	float lid = floor(v / period);
	float link_tone = mod(lid, 2.0);

	// --- joint geometry -----------------------------------------------------
	float neck = smoothstep(0.0, 0.020, seg) * smoothstep(0.105, 0.060, seg);
	float seam = smoothstep(0.0, 0.008, seg) * smoothstep(0.026, 0.012, seg);
	float mid_band = smoothstep(0.455, 0.475, seg) * smoothstep(0.545, 0.525, seg);
	// four joint bolts per link
	float bolt = 0.0;
	for (int b = 0; b < 4; b++) {
		float uk = 0.125 + 0.25 * float(b);
		float du = abs(fract(u - uk + 0.5) - 0.5);
		float r = length(vec2(du / 0.020, (seg - 0.035) / 0.016));
		bolt = max(bolt, smoothstep(0.95, 0.55, r));
	}

	// --- longitudinal grooves / light channel -------------------------------
	float du0 = abs(fract(u + 0.5) - 0.5);
	float spine = smoothstep(0.014, 0.004, du0);
	float side1 = abs(fract(u - 0.25 + 0.5) - 0.5);
	float side2 = abs(fract(u - 0.75 + 0.5) - 0.5);
	float side_groove = smoothstep(0.012, 0.004, min(side1, side2));

	// --- surface noise ------------------------------------------------------
	float pn = fbm(vec2(v * 1.4 + seed, u * 6.0));
	float pn2 = fbm(vec2(v * 5.3 - seed, u * 17.0));
	float scr = smoothstep(0.88, 0.99, fbm(vec2(v * 23.0 + u * 2.5, u * 8.0 + seed)));
	scr *= smoothstep(0.35, 0.65, pn2);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float edge = clamp(fres * 0.5, 0.0, 1.0);

	// --- albedo / roughness -------------------------------------------------
	vec3 base = mix(albedo_color.rgb, link_color.rgb, link_tone * 0.55);
	base = mix(base, trim_color.rgb, seam * 0.30 + neck * 0.10 + bolt * 0.45);
	base *= 1.0 + (pn - 0.5) * 0.55;
	base *= 1.0 - spine * 0.45 - side_groove * 0.25 - mid_band * 0.22;
	base *= 1.0 - scr * 0.25;
	base = mix(base, trim_color.rgb * 0.5, edge * 0.28);

	float rough = roughness_base + (pn - 0.5) * 0.20 + (pn2 - 0.5) * 0.08;
	rough = mix(rough, 0.14, neck * 0.30 + bolt * 0.45 + scr * 0.35);
	rough = mix(rough, 0.66, mid_band * 0.30);

	// --- emission -----------------------------------------------------------
	float pulse = 0.55 + 0.45 * sin(v * 0.75 - TIME * (2.0 + role * 1.5) + seed * 6.0);
	float strip = spine * (0.45 + 0.55 * pulse);
	float side_strip = side_groove * 0.10;
	float tip_t = smoothstep(0.955, 1.0, v / max(length_m, 0.01));
	float tip_ring = smoothstep(0.030, 0.008, abs((v / max(length_m, 0.01)) - 0.945));
	float role_boost = mix(1.0, 1.8, step(1.5, role));
	vec3 em = glow_color.rgb * (
		neck * 0.06 * role_boost
		+ seam * 0.10
		+ bolt * 0.28
		+ strip * 1.10
		+ side_strip
		+ tip_ring * 0.35
		+ tip_t * (0.03 + charge * 6.0)
	) * glow_energy;
	em += vec3(1.0, 0.72, 0.46) * charge * 2.5 * tip_t * tip_t;

	ALBEDO = base;
	METALLIC = metallic;
	ROUGHNESS = clamp(rough, 0.06, 0.94);
	SPECULAR = 0.5;
	AO = clamp(1.0 - spine * 0.30 - seam * 0.25 - mid_band * 0.15, 0.0, 1.0);
	EMISSION = em;
}