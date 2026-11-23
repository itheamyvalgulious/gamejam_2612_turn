shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// =============================================================================
// LEVIATHAN - boss_metal
// Procedural PBR metal for a black + orange-red hard-surface kraken boss.
// No textures, no screen texture, no includes. Broad panel variation uses
// object-space triplanar weights; micro-brush, grain and scratches use
// seamless object-space cell/3D detail, so arbitrary merged meshes keep a
// consistent grain/brush scale regardless of UVs or transforms.
//
// Layers:
//   * broad machined panel mottling (3-octave triplanar fbm)
//   * brushed directional micro-grooves (anisotropic 3D fbm + normal)
//   * fine pitting / cast grain (high frequency, dulls + dents the surface)
//   * sparse straight scratches: dark polished groove + bright one-sided burr
//   * fresnel edge wear revealing lighter bare steel, broken by chip noise
//   * very subtle warm oxide in low panel-noise areas
//
// Uniforms:
//   albedo_color         base F0 tint, near-black graphite
//   metallic             metal mask (default 1.0)
//   roughness_base       base roughness (0.38)
//   roughness_variation  broad roughness swing (0.10)
//   brush_strength       depth of the brushed micro-surface (0.35)
//   brush_dir            object-space brushing direction (normalized in shader)
//   grain_scale          object-space grain/pitting frequency (28.0)
//   scratch_density      how much of the surface carries scratches (0.35)
//   scratch_scale        overall scratch cell frequency multiplier (1.0)
//   edge_color           bare metal revealed by wear (light steel)
//   edge_wear            edge wear strength (0.5)
//   edge_power           fresnel falloff exponent for edge wear (3.0)
//   oxide_amount         subtle warm oxidation blend (0.05)
//   oxide_color          dark warm oxide color
//   panel_scale          broad panel / machining frequency (3.0)
//   panel_variation      broad panel roughness/albedo swing (0.06)
//
// Forward+ recommended: sky / SSR / SDFGI supply the environment reflections
// that make a metallic=1 surface read as metal. Lit PBR only.
// =============================================================================

uniform vec4 albedo_color : source_color = vec4(0.042, 0.043, 0.050, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 1.0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.38;
uniform float roughness_variation : hint_range(0.0, 1.0) = 0.10;
uniform float brush_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec3 brush_dir = vec3(0.0, 1.0, 0.0);
uniform float grain_scale = 28.0;
uniform float scratch_density : hint_range(0.0, 1.0) = 0.35;
uniform float scratch_scale = 1.0;
uniform vec4 edge_color : source_color = vec4(0.40, 0.41, 0.44, 1.0);
uniform float edge_wear : hint_range(0.0, 1.0) = 0.5;
uniform float edge_power = 3.0;
uniform float oxide_amount : hint_range(0.0, 1.0) = 0.05;
uniform vec4 oxide_color : source_color = vec4(0.16, 0.055, 0.025, 1.0);
uniform float panel_scale = 3.0;
uniform float panel_variation : hint_range(0.0, 1.0) = 0.06;

varying vec3 opos;   // object-space position
varying vec3 onrm;   // object-space normal
varying vec3 wpos;   // world position (available for world-space effects)
varying vec3 ax_x;   // object X axis in world space
varying vec3 ax_y;   // object Y axis in world space
varying vec3 ax_z;   // object Z axis in world space

// ---------------------------------------------------------------------------
// Noise
// ---------------------------------------------------------------------------

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm3(vec2 p) {
	float s = vnoise(p) * 0.55;
	s += vnoise(p * 2.07 + vec2(11.3, 7.1)) * 0.30;
	s += vnoise(p * 4.11 + vec2(3.7, 17.9)) * 0.15;
	return s;
}

// --- 3D value noise: seamless object-space micro detail -------------------
float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = hash31(i);
	float b = hash31(i + vec3(1.0, 0.0, 0.0));
	float c = hash31(i + vec3(0.0, 1.0, 0.0));
	float d = hash31(i + vec3(1.0, 1.0, 0.0));
	float e = hash31(i + vec3(0.0, 0.0, 1.0));
	float f1 = hash31(i + vec3(1.0, 0.0, 1.0));
	float g = hash31(i + vec3(0.0, 1.0, 1.0));
	float h = hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
		mix(mix(e, f1, u.x), mix(g, h, u.x), u.y),
		u.z);
}

float fbm3d(vec3 p) {
	return vnoise3(p) * 0.68 + vnoise3(p * 2.03 + vec3(17.1, 9.3, 5.7)) * 0.32;
}

// Straight scratch segment per 2D cell: one random line per cell, clipped by
// the cell so scratches stay sparse, straight and naturally short-to-long.
// Returns (dark groove core, bright one-sided burr lip).
vec2 scratch_cell2(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float r0 = hash21(cell + vec2(1.7, 9.3));
	float r1 = hash21(cell + vec2(7.9, 2.3));
	float ang = hash21(cell + vec2(3.1, 6.7)) * 6.2831853;
	vec2 dir = vec2(cos(ang), sin(ang));
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 center = vec2(0.5) + (vec2(r0, r1) - 0.5) * 0.55;
	float active = step(0.80, hash21(cell + vec2(21.3, 17.9)));
	vec2 rel = f - center;
	float dist = abs(dot(rel, perp));
	float core = (1.0 - smoothstep(0.007, 0.018, dist)) * active;
	float halo = (1.0 - smoothstep(0.018, 0.042, dist)) * active;
	float side = smoothstep(0.0, 0.018, dot(rel, perp));
	return vec2(core, (halo - core) * side);
}

// Micro height used for the procedural detail normal: brushed grooves plus
// fine cast grain. Sampled in 3D object space so merged meshes have no UV or
// triplanar-projection seams at grazing angles.
float micro_h(vec3 p) {
	vec3 bd = normalize(brush_dir + vec3(0.0001, 0.0, 0.0));
	vec3 q = p * (grain_scale * 2.0);
	q -= bd * dot(q, bd) * 0.94;
	float brush = fbm3d(q);
	vec3 r = p * (grain_scale * 4.0);
	float grain = vnoise3(r);
	return brush * 0.92 + grain * 0.08;
}

void vertex() {
	opos = VERTEX;
	onrm = normalize(NORMAL);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ax_x = normalize(MODEL_NORMAL_MATRIX * vec3(1.0, 0.0, 0.0));
	ax_y = normalize(MODEL_NORMAL_MATRIX * vec3(0.0, 1.0, 0.0));
	ax_z = normalize(MODEL_NORMAL_MATRIX * vec3(0.0, 0.0, 1.0));
}

void fragment() {
	// --- triplanar weights from the object-space normal ---------------------
	vec3 tw = pow(abs(onrm), vec3(4.0));
	tw /= max(tw.x + tw.y + tw.z, 0.0001);

	// --- broad panel / machining variation ---------------------------------
	float panel = tw.x * fbm3(opos.yz * panel_scale + vec2(4.1, 2.7))
			+ tw.y * fbm3(opos.xz * panel_scale + vec2(9.3, 1.1))
			+ tw.z * fbm3(opos.xy * panel_scale + vec2(6.4, 8.8));

	// --- directional brushed micro-surface --------------------------------
	vec3 bd = normalize(brush_dir + vec3(0.0001, 0.0, 0.0));
	vec3 q = opos * (grain_scale * 1.4);
	q -= bd * dot(q, bd) * 0.94; // stretch the noise along the brush direction
	float brush = fbm3d(q);

	// --- fine pitting / cast grain ----------------------------------------
	vec3 r = opos * (grain_scale * 4.0);
	float pit = vnoise3(r);
	pit = smoothstep(0.84, 0.985, pit);

	// --- sparse long scratches --------------------------------------------
	// Straight cell-clipped scratches in the dominant triplanar plane, at two
	// scales. No crack networks: one line segment per cell.
	vec3 sw = pow(abs(onrm), vec3(8.0));
	sw /= max(sw.x + sw.y + sw.z, 0.0001);
	vec2 a0 = scratch_cell2(opos.yz * (3.5 * scratch_scale) + vec2(4.1, 2.7));
	vec2 a1 = scratch_cell2(opos.xz * (3.5 * scratch_scale) + vec2(9.3, 1.1));
	vec2 a2 = scratch_cell2(opos.xy * (3.5 * scratch_scale) + vec2(6.4, 8.8));
	vec2 b0 = scratch_cell2(opos.yz * (7.0 * scratch_scale) + vec2(12.7, 5.2));
	vec2 b1 = scratch_cell2(opos.xz * (7.0 * scratch_scale) + vec2(3.6, 14.1));
	vec2 b2 = scratch_cell2(opos.xy * (7.0 * scratch_scale) + vec2(8.2, 7.5));
	float sc_amt = clamp(scratch_density * 2.0, 0.0, 1.0);
	float sc_core = (sw.x * a0.x + sw.y * a1.x + sw.z * a2.x)
			+ (sw.x * b0.x + sw.y * b1.x + sw.z * b2.x) * 0.45;
	float sc_lip = (sw.x * a0.y + sw.y * a1.y + sw.z * a2.y)
			+ (sw.x * b0.y + sw.y * b1.y + sw.z * b2.y) * 0.45;
	sc_core = clamp(sc_core, 0.0, 1.0) * sc_amt;
	sc_lip = clamp(sc_lip, 0.0, 1.0) * sc_amt;

	// --- roughness ---------------------------------------------------------
	float rough = roughness_base;
	rough += (panel - 0.5) * roughness_variation * 1.6;
	rough += (brush - 0.5) * brush_strength * 0.30;
	rough = mix(rough, 0.65, pit * 0.25);          // pits scatter, metal dulls
	rough = mix(rough, 0.10, sc_core * 0.90);       // groove is freshly cut/shiny
	rough = mix(rough, 0.18, sc_lip * 0.55);         // burr lip is polished too

	// --- subtle warm oxide in low panel-noise areas ------------------------
	float ox = (1.0 - smoothstep(0.16, 0.42, panel)) * oxide_amount;
	rough += ox * 0.55;

	// --- edge wear: fresnel reveals lighter bare steel ---------------------
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), edge_power);
	float edge_bias = 0.55 + 0.90 * smoothstep(0.35, 0.75, panel);
	float chip = smoothstep(0.30, 0.62,
			vnoise3(opos * 11.0 + vec3(1.7, 5.3, 9.1)));
	float edge = clamp(fres * edge_bias * edge_wear * 2.0, 0.0, 1.0);
	edge *= mix(0.55, 1.0, chip);
	rough = mix(rough, 0.16, edge * 0.45);

	// --- albedo (F0 for a metal) ------------------------------------------
	vec3 base = albedo_color.rgb;
	base *= 1.0 + (panel - 0.5) * panel_variation * 4.0;
	base *= 1.0 + (brush - 0.5) * brush_strength * 0.50;
	base *= 1.0 - pit * 0.08;
	base = mix(base, oxide_color.rgb, clamp(ox * 0.8, 0.0, 1.0));
	base *= 1.0 - sc_core * 0.82;                    // dark scratch groove
	base = mix(base, edge_color.rgb, edge * 0.55);   // worn bright edge
	base += edge_color.rgb * sc_lip * 0.12;          // bright burr lip

	ALBEDO = base;
	METALLIC = clamp(metallic, 0.0, 1.0);
	ROUGHNESS = clamp(rough, 0.05, 0.95);
	SPECULAR = 0.5;
	AO = clamp(1.0 - pit * 0.10 - sc_core * 0.30 - ox * 0.25, 0.0, 1.0);
	EMISSION = vec3(0.0);

	// Surface detail is carried by albedo/roughness (brushed streaks, pitting,
	// scratches, edge wear). The normal stays smooth: metal reads as metal,
	// not as rough stone. A tiny procedural bump is not worth the noise.

}