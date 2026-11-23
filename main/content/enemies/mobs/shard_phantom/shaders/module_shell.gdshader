shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Procedural machined-metal skin (modules style 0, frame style 1).
// No textures.  Surface-only detail:
//  - low-frequency albedo mottling + per-panel tint variation + corner darkening
//  - desaturated grime/patina in crevices and low areas (no orange rust)
//  - roughness base 0.52-0.65 with 2-3 octave noise (+-0.08)
//  - high-frequency pitting + sparse long anisotropic scratches (roughness/specular)
//  - micro-normal perturbation so speculars break into irregular patches
//  - slight metal edge wear (lightening), not an emissive rim
//  - module style keeps the thin orange-red seam/signal/phase emission

uniform vec4 base_color : source_color = vec4(0.010, 0.010, 0.012, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.19, 0.045, 1.0);
uniform float metallic_value = 0.90;
uniform float roughness_value = 0.58;
uniform float edge_width = 0.030;
uniform float edge_gain = 0.12;
uniform float style = 0.0;
uniform float bump_strength = 0.030;

instance uniform vec4 fx_tint : source_color = vec4(0.018, 0.018, 0.022, 1.0);
instance uniform float fx_seed = 0.0;
instance uniform float fx_edge = 0.55;
instance uniform float fx_phase = 0.0;
instance uniform float fx_signal = 0.0;

varying vec3 l_nrm;
varying vec3 l_pos;
varying vec3 w_pos;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
		mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
		mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

// 3 octaves, normalised to 0..1
float fbm3(vec3 p) {
	return vnoise(p) * 0.53 + vnoise(p * 2.11 + 17.3) * 0.31 + vnoise(p * 4.27 + 41.7) * 0.16;
}

float fbm2(vec3 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.07 + 17.3) * 0.35;
}

// long thin anisotropic streak field, angle a, across-frequency f
float streaks(vec3 p, float a, float f, float w) {
	float c = cos(a);
	float s = sin(a);
	float u = (c * p.x + s * p.y) * f;
	float v = (-s * p.x + c * p.y) * (f * 0.045);
	return smoothstep(0.90 - w, 0.995, vnoise(vec3(u, v, p.z * 7.0 + 3.0)));
}

void vertex() {
	l_nrm = NORMAL;
	l_pos = VERTEX;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float panel = fract(sin(fx_seed * 91.73 + 1.7) * 43758.5453);
	float panel2 = fract(sin(fx_seed * 43.17 + 9.1) * 21374.918);
	// low-frequency only: panel-scale blotches, no per-pixel grain
	float n_low = vnoise(w_pos * 2.4 + 7.0);
	float n_med = vnoise(l_pos * 18.0 + vec3(fx_seed * 19.0, 3.0, 7.0)) * 0.6
		+ vnoise(l_pos * 55.0 + 11.0) * 0.4;
	float n_world = vnoise(w_pos * 3.1 + 3.1);
	float border = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float facing = smoothstep(0.35, 0.92, abs(l_nrm.z));
	float corner = (1.0 - smoothstep(0.0, 0.11, border)) * (1.0 - style);
	// per-panel rounding: module faces sit at slightly different depths/edges
	float panel_edge = (1.0 - smoothstep(0.0, 0.035, border)) * (1.0 - style);

	// sparse long scratches: ~1 plate in 3, concentrated near edges/protrusions
	float a1 = fract(sin(fx_seed * 12.9898) * 43758.5453) * 6.2831;
	float a2 = fract(sin(fx_seed * 78.233 + 1.7) * 24634.6345) * 6.2831;
	float a3 = fract(sin(fx_seed * 39.425 + 7.3) * 39175.1273) * 6.2831;
	float sc1 = streaks(l_pos, a1, 250.0, 0.050);
	float sc2 = streaks(l_pos, a2, 175.0, 0.058);
	float sc3 = streaks(l_pos, a3, 95.0, 0.060);
	float has_scratch = step(0.58, fract(sin(fx_seed * 47.31) * 43758.5453));
	float edge_bias = 0.90 + 0.95 * corner + 0.35 * panel_edge;
	float sc = (sc1 * 1.0 + sc2 * 0.70 + sc3 * 0.50) * has_scratch * edge_bias;
	sc = clamp(sc, 0.0, 1.4);

	float redness = clamp((fx_tint.r / max(max(fx_tint.g, fx_tint.b), 1e-5) - 1.0) * 2.0, 0.0, 1.0);
	// micro-normal perturbation (procedural, world tangent frame)
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 t1 = normalize(cross(wn, vec3(0.0, 1.0, 0.0)) + vec3(0.001));
	vec3 t2 = normalize(cross(wn, t1));
	float nb1 = vnoise(l_pos * 55.0 + 5.0) - 0.5;
	float nb2 = vnoise(l_pos * 55.0 + 61.0) - 0.5;
	float nb3 = vnoise(l_pos * 21.0 + 23.0) - 0.5;
	vec3 bn = normalize(wn + (t1 * (nb1 + nb3 * 0.5) + t2 * (nb2 - nb3 * 0.35)) * bump_strength * (1.0 - 0.5 * redness));
	NORMAL = normalize((VIEW_MATRIX * vec4(bn, 0.0)).xyz);

	float low = clamp(0.5 - wn.y * 0.5, 0.0, 1.0);
	// very desaturated grime in crevices / low areas; no orange
	float grime = clamp(corner * 0.60 + low * 0.16 + (n_world - 0.5) * 0.12, 0.0, 1.0);
	float wear = panel_edge * 0.75 + pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * 0.12;

	// albedo: per-panel tint (desaturated), low-freq mottling +-4%
	vec3 tint = mix(fx_tint.rgb, vec3(dot(fx_tint.rgb, vec3(0.299, 0.587, 0.114))), 0.28 + 0.34 * redness);
	vec3 col = mix(base_color.rgb, tint, 0.86 * (1.0 - style));
	col *= (0.98 + n_low * 0.04 * (1.0 - 0.5 * redness)) * (0.94 + panel * 0.12);
	col *= 1.0 - (0.04 + 0.02 * redness) * panel2;
	col *= 1.0 - 0.12 * redness;
	// corner / edge darkening
	col = mix(col, col * vec3(0.66, 0.66, 0.64), corner * 0.60);
	// subtle dark oxidation on red plates: kill saturation, no orange rust
	vec3 ox = vec3(0.017, 0.016, 0.016);
	col = mix(col, ox, clamp(grime * (0.14 + 0.22 * redness), 0.0, 0.34));
	// exposed metal on the very edge: slightly lighter and warmer
	col += vec3(0.034, 0.032, 0.029) * wear;
	col += vec3(0.0036, 0.0034, 0.0031) * min(sc, 1.2);

	ALBEDO = col;
	METALLIC = clamp(metallic_value, 0.0, 1.0);
	// low-frequency roughness +-0.05; scratches polish the surface
	float rough = roughness_value + (n_med - 0.5) * 0.10 * (1.0 - 0.4 * redness)
		- wear * 0.05 - min(sc, 1.1) * 0.30;
	ROUGHNESS = clamp(rough, 0.30, 0.70);
	SPECULAR = clamp(0.35 + min(sc, 1.1) * 0.40 - grime * 0.06 - wear * 0.04, 0.16, 0.72);

	// module-only thin orange-red seam / signal / dispersal phase
	float line = 1.0 - smoothstep(edge_width * 0.30, edge_width, border);
	float signal = pow(0.5 + 0.5 * sin(TIME * (0.55 + fract(fx_seed * 7.13) * 1.9) + fx_seed * 41.0), 30.0);
	float sig = step(0.52, fx_signal) * signal;
	float bar = smoothstep(0.045, 0.0, abs(UV.y - 0.17))
		* smoothstep(0.30, 0.22, abs(UV.x - 0.5)) * facing;
	float edge = line * facing;
	float phase = clamp(fx_phase, 0.0, 1.0);
	vec3 em = edge_color.rgb * (edge * fx_edge * edge_gain + sig * bar * 4.2);
	em += edge_color.rgb * phase * (edge * 1.45 + 0.012);
	em *= (1.0 - style);
	EMISSION = em;
}