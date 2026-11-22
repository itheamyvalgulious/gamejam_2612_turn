shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// =============================================================================
// VESPER // engine iris blade — brushed steel
// -----------------------------------------------------------------------------
// One plate of the 8-blade iris aperture that seals the main vector nozzle.
// Real metal: F0 is bright steel, METALLIC = 1, roughness varies with the
// brushing direction, and the beveled rim catches a cool blue Fresnel edge so
// the blades read as machined titanium even against the dark backpack.
//
// UV: UV.x runs hinge (0) -> tip (1); UV.y runs across the width (0..1).
// =============================================================================

uniform vec4 edge_color : source_color = vec4(0.30, 0.62, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
uniform float open_glow : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
	float s = vnoise2(p) * 0.55;
	s += vnoise2(p * 2.07 + vec2(11.3, 7.1)) * 0.30;
	s += vnoise2(p * 4.11 + vec2(3.7, 17.9)) * 0.15;
	return s;
}

void fragment() {
	// --- clean brushed titanium: no UV-repeating pattern (the slab's per-face
	// UVs turned any texture into concentric rings on the closed iris).
	float across = abs(UV.y - 0.5) * 2.0;
	float bevel = smoothstep(0.72, 1.0, across) * 0.55 + smoothstep(0.86, 1.0, UV.x) * 0.35;
	float wear = fbm2(vec2(UV.x * 9.0, UV.y * 5.0)) * 0.12;

	vec3 base = vec3(0.56, 0.58, 0.61);
	base *= 1.0 - wear;
	base = mix(base, vec3(0.86, 0.88, 0.90), bevel);
	ALBEDO = base;
	METALLIC = 0.94;
	ROUGHNESS = clamp(0.28 - bevel * 0.12 + wear * 0.18, 0.10, 0.48);
	SPECULAR = 0.55;

	float face = FRONT_FACING ? 1.0 : -1.0;
	vec3 nrm = normalize(NORMAL) * face;
	float fres = pow(1.0 - clamp(dot(nrm, normalize(VIEW)), 0.0, 1.0), 3.0);
	float seam_x = smoothstep(0.90, 1.0, UV.x);
	float seam_line = 1.0 - smoothstep(0.05, 0.22, abs(UV.y - 0.5));
	float pulse = 0.85 + 0.15 * sin(TIME * 2.2);
	EMISSION = edge_color.rgb * (fres * 0.28 + seam_x * seam_line * 0.65) * intensity * pulse * open_glow;
}