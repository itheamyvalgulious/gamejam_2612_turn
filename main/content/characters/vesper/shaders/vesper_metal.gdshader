shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// =============================================================================
// VESPER // hard-surface metal
// Fully procedural PBR metal for cold-white / navy-blue armour.
// No textures, no screen texture, no SSR-only features: safe under the
// gl_compatibility renderer.
//
// Layers
//   * broad machined panel mottling (triplanar 3-octave fbm)
//   * directional brushed micro-grooves (anisotropic object-space 3D fbm)
//   * fine cast grain / pitting (dulls + darkens the surface)
//   * sparse straight scratches: dark polished groove + bright burr lip
//   * fresnel edge wear revealing bright bare steel, broken up by chip noise
//   * a faint cool environment sheen (fakes sky reflection where the
//     compatibility renderer has no SSR)
//
// Everything is sampled in object space so merged parts keep a consistent
// grain scale independent of UVs and transforms.
// =============================================================================

uniform vec4 albedo_color : source_color = vec4(0.62, 0.67, 0.75, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.90;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.34;
uniform float roughness_variation : hint_range(0.0, 1.0) = 0.10;
uniform float brush_strength : hint_range(0.0, 1.0) = 0.55;
uniform vec3 brush_dir = vec3(0.0, 1.0, 0.0);
uniform float grain_scale = 26.0;
uniform float scratch_density : hint_range(0.0, 1.0) = 0.30;
uniform float scratch_scale = 1.0;
uniform vec4 edge_color : source_color = vec4(0.88, 0.92, 1.0, 1.0);
uniform float edge_wear : hint_range(0.0, 1.0) = 0.55;
uniform float edge_power = 2.6;
uniform float panel_scale = 2.6;
uniform float panel_variation : hint_range(0.0, 1.0) = 0.10;
uniform vec4 tint_blue : source_color = vec4(0.62, 0.78, 1.0, 1.0);
uniform float env_sheen : hint_range(0.0, 0.5) = 0.10;

varying vec3 opos;
varying vec3 onrm;
varying vec3 wnrm;

// ---------------------------------------------------------------------------
// Noise
// ---------------------------------------------------------------------------
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

// One random straight scratch segment per 2D cell.
// Returns (dark groove core, bright one-sided burr lip).
vec2 scratch_cell(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float r0 = hash21(cell + vec2(1.7, 9.3));
	float r1 = hash21(cell + vec2(7.9, 2.3));
	float ang = hash21(cell + vec2(3.1, 6.7)) * 6.2831853;
	vec2 dir = vec2(cos(ang), sin(ang));
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 center = vec2(0.5) + (vec2(r0, r1) - 0.5) * 0.55;
	float active = step(0.82, hash21(cell + vec2(21.3, 17.9)));
	vec2 rel = f - center;
	float dist = abs(dot(rel, perp));
	float core = (1.0 - smoothstep(0.006, 0.016, dist)) * active;
	float halo = (1.0 - smoothstep(0.016, 0.040, dist)) * active;
	float side = smoothstep(0.0, 0.016, dot(rel, perp));
	return vec2(core, (halo - core) * side);
}

void vertex() {
	opos = VERTEX;
	onrm = normalize(NORMAL);
	wnrm = normalize((MODEL_NORMAL_MATRIX * NORMAL));
}

void fragment() {
	// triplanar weights from the object-space normal
	vec3 tw = pow(abs(onrm), vec3(4.0));
	tw /= max(tw.x + tw.y + tw.z, 0.0001);

	// --- broad panel / machining variation ---------------------------------
	float panel = tw.x * fbm2(opos.yz * panel_scale + vec2(4.1, 2.7))
			+ tw.y * fbm2(opos.xz * panel_scale + vec2(9.3, 1.1))
			+ tw.z * fbm2(opos.xy * panel_scale + vec2(6.4, 8.8));

	// --- directional brushed micro-surface --------------------------------
	vec3 bd = normalize(brush_dir + vec3(0.0001, 0.0, 0.0));
	vec3 q = opos * (grain_scale * 1.4);
	q -= bd * dot(q, bd) * 0.94; // stretch noise along the brush direction
	float brush = fbm3d(q);

	// --- fine cast grain / pitting ----------------------------------------
	vec3 r = opos * (grain_scale * 4.0);
	float pit = vnoise3(r);
	pit = smoothstep(0.84, 0.985, pit);

	// --- sparse straight scratches ----------------------------------------
	vec3 sw = pow(abs(onrm), vec3(8.0));
	sw /= max(sw.x + sw.y + sw.z, 0.0001);
	vec2 a0 = scratch_cell(opos.yz * (3.5 * scratch_scale) + vec2(4.1, 2.7));
	vec2 a1 = scratch_cell(opos.xz * (3.5 * scratch_scale) + vec2(9.3, 1.1));
	vec2 a2 = scratch_cell(opos.xy * (3.5 * scratch_scale) + vec2(6.4, 8.8));
	vec2 b0 = scratch_cell(opos.yz * (7.0 * scratch_scale) + vec2(12.7, 5.2));
	vec2 b1 = scratch_cell(opos.xz * (7.0 * scratch_scale) + vec2(3.6, 14.1));
	vec2 b2 = scratch_cell(opos.xy * (7.0 * scratch_scale) + vec2(8.2, 7.5));
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
	rough = mix(rough, 0.68, pit * 0.28);
	rough = mix(rough, 0.10, sc_core * 0.90); // freshly cut groove is shiny
	rough = mix(rough, 0.18, sc_lip * 0.55);

	// --- edge wear: fresnel reveals brighter bare steel --------------------
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), edge_power);
	float edge_bias = 0.55 + 0.90 * smoothstep(0.35, 0.75, panel);
	float chip = smoothstep(0.30, 0.62,
			vnoise3(opos * 11.0 + vec3(1.7, 5.3, 9.1)));
	float edge = clamp(fres * edge_bias * edge_wear * 2.0, 0.0, 1.0);
	edge *= mix(0.55, 1.0, chip);
	rough = mix(rough, 0.16, edge * 0.45);

	// --- albedo (F0 for a metal) ------------------------------------------
	vec3 base = albedo_color.rgb;
	base *= 1.0 + (panel - 0.5) * panel_variation * 3.6;
	base *= 1.0 + (brush - 0.5) * brush_strength * 0.45;
	base *= 1.0 - pit * 0.10;
	base *= 1.0 - sc_core * 0.80;                  // dark scratch groove
	base = mix(base, edge_color.rgb, edge * 0.60); // worn bright edge
	base += edge_color.rgb * sc_lip * 0.10;        // bright burr lip

	ALBEDO = base;
	METALLIC = clamp(metallic, 0.0, 1.0);
	ROUGHNESS = clamp(rough, 0.05, 0.95);
	SPECULAR = 0.5;
	AO = clamp(1.0 - pit * 0.10 - sc_core * 0.28, 0.0, 1.0);

	// Cool sky sheen: keeps the metal readable under gl_compatibility, where
	// there is no SSR. A world-up gradient + fresnel stand in for a reflected
	// environment; the worn edge term doubles as a rim light on silhouettes.
	float sky = smoothstep(-0.55, 0.95, dot(wnrm, vec3(0.15, 1.0, 0.25)));
	float sheen = env_sheen * (0.30 + 0.70 * fres) * (0.40 + 0.60 * sky);
	EMISSION = tint_blue.rgb * sheen + edge_color.rgb * edge * env_sheen * 1.4;
}