shader_type spatial;
// =============================================================================
// VESPER hair — Multi-stratum Hair Cards + Dual-Lobe Kajiya-Kay Shading
// -----------------------------------------------------------------------------
// Eliminates the "octopus tentacle" card silhouette via three overlapping
// procedural fiber strata inside wide arched cards + alpha-to-coverage MSAA.
// * Stratum C (12 body fibers): opaque root/mid coverage (t < ~0.68).
// * Stratum A (24 primary strands): tapered strands ending in staggered tufts.
// * Stratum B (40 ultra-fine wispy hairs): feathery micro-strands up to t = 1.0.
// * Kajiya-Kay dual-lobe anisotropic specular (silvery R + azure TRT) + backlit TT.
// =============================================================================
render_mode cull_disabled, depth_draw_opaque, alpha_to_coverage;

uniform bool is_scalp = false;
uniform float energy = 0.015;
uniform vec3 root_col : source_color = vec3(0.210, 0.440, 0.720);
uniform vec3 mid_col  : source_color = vec3(0.280, 0.540, 0.800);
uniform vec3 tip_col  : source_color = vec3(0.360, 0.610, 0.840);
uniform vec3 sheen_primary : source_color = vec3(0.72, 0.86, 0.98);
uniform vec3 sheen_secondary : source_color = vec3(0.36, 0.62, 0.90);
uniform vec3 shade_col : source_color = vec3(0.140, 0.300, 0.560);

varying vec3 v_tangent;
varying vec3 v_normal;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	v_tangent = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
	v_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float u = clamp(UV.x, 0.0, 1.0);
	float t = clamp(UV.y, 0.0, 1.0);
	float phase = UV2.x;
	float bias = clamp(UV2.y, 0.0, 1.0);
	vec3 vcol = COLOR.rgb;

	float fiber_ridge = 1.0;
	float fseed = 0.5;
	float alpha_out = 1.0;
	float color_t = t;

	if (is_scalp) {
		float fx = u * 160.0;
		float fi = floor(fx);
		float ff = fract(fx);
		fseed = hash11(fi * 1.73 + 3.1);
		fiber_ridge = 1.0 - smoothstep(0.26, 0.60, abs(ff - 0.5));
		// Scalp spans crown (0.0) to hairline (1.0) in the deep->mid range
		color_t = 0.06 + 0.36 * t;
		alpha_out = 1.0;
	} else {
		// Gentle natural hair wave along strand length
		float wave = sin(t * 7.5 + phase * 3.1) * 0.018 + sin(t * 15.0 - phase * 1.7) * 0.008;
		float uw = clamp(u + wave * smoothstep(0.04, 0.75, t), 0.0, 1.0);
		float edge_dist = abs(uw - 0.5) * 2.0;
		float edge_cut = pow(edge_dist, 2.2) * 0.30;

		// Stratum C: broad inner body fibers (0.0 -> 0.56..0.74)
		float fx_c = uw * 12.0;
		float ic = floor(fx_c);
		float fc = fract(fx_c);
		float sc = hash11(ic * 2.13 + phase * 5.71);
		float end_c = clamp((0.56 + 0.18 * sc) * (1.0 - edge_cut * 0.85), 0.20, 0.80);
		float w_c = 0.46 * smoothstep(end_c, end_c - 0.12, t);
		float cov_c = smoothstep(w_c + 0.07, w_c - 0.04, abs(fc - 0.5)) * smoothstep(end_c + 0.02, end_c - 0.04, t);

		// Stratum A: 24 primary fine strands
		float fx_a = uw * 24.0 + 0.31;
		float ia = floor(fx_a);
		float fa = fract(fx_a);
		float sa = hash11(ia * 3.71 + phase * 9.17);
		float end_a = clamp(0.66 + 0.28 * sa - edge_cut * 0.75, 0.30, 0.96);
		float taper_a = smoothstep(end_a, end_a - 0.22, t);
		float hw_a = mix(0.20, 0.44, taper_a);
		float cov_a = smoothstep(hw_a + 0.05, hw_a - 0.04, abs(fa - 0.5)) * smoothstep(end_a + 0.02, end_a - 0.03, t);

		// Stratum B: 40 ultra-fine feathery flyaway strands extending to tip
		float fx_b = uw * 40.0 + 0.67;
		float ib = floor(fx_b);
		float fb = fract(fx_b);
		float sb = hash11(ib * 5.19 + phase * 11.43);
		float end_b = clamp((0.54 + 0.46 * pow(sb, 0.78)) - edge_cut * 0.55, 0.26, 1.00);
		float taper_b = smoothstep(end_b, end_b - 0.26, t);
		float hw_b = mix(0.16, 0.42, taper_b);
		float cov_b = smoothstep(hw_b + 0.04, hw_b - 0.04, abs(fb - 0.5)) * smoothstep(end_b + 0.015, end_b - 0.025, t);

		// Solid root seal so scalp roots never expose gaps
		float root_seal = smoothstep(0.16, 0.02, t) * 0.95;
		float combined = max(root_seal, max(cov_c, max(cov_a, cov_b)));
		combined *= smoothstep(1.0, 0.88, edge_dist * smoothstep(0.12, 0.50, t));
		alpha_out = clamp(combined, 0.0, 1.0);

		fseed = mix(sa, sb, smoothstep(0.52, 0.85, t));
		float ridge_a = (1.0 - smoothstep(0.14, 0.44, abs(fa - 0.5))) * cov_a;
		float ridge_b = (1.0 - smoothstep(0.10, 0.38, abs(fb - 0.5))) * cov_b;
		fiber_ridge = clamp(max(ridge_a, ridge_b * 0.92) + cov_c * 0.35, 0.0, 1.0);
	}

	float tt = clamp(color_t + (fseed - 0.5) * 0.04, 0.0, 1.0);
	vec3 col = mix(root_col, mid_col, smoothstep(0.05, 0.58, tt));
	col = mix(col, tip_col, smoothstep(0.50, 0.98, tt));

	float lock_lift = mix(-0.06, 0.06, bias);
	col *= 1.0 + lock_lift;
	col *= 0.94 + 0.10 * fseed;

	// Subtle fiber grooves for silky separation without harsh dark striping
	col = mix(shade_col, col, mix(0.62, 1.0, fiber_ridge));

	vec3 base = col * vcol;
	base *= mix(0.95, 1.03, smoothstep(0.0, 0.45, color_t));

	ALBEDO = base * 0.56;
	METALLIC = 0.02;
	ROUGHNESS = mix(0.48, 0.38, smoothstep(0.0, 0.8, color_t));
	SPECULAR = 0.16;
	EMISSION = base * energy;

	ALPHA = alpha_out;
	ALPHA_SCISSOR_THRESHOLD = 0.30;
	ALPHA_ANTIALIASING_EDGE = 0.22;
}

void light() {
	vec3 T = normalize(v_tangent);
	vec3 N = normalize(NORMAL);
	vec3 L = normalize(LIGHT);
	vec3 V = normalize(VIEW);
	vec3 H = normalize(L + V);

	// Per-fiber tangent jitter breaks flat card specular bands into fine silky glint
	float u_cell = floor(UV.x * (is_scalp ? 160.0 : 32.0));
	float f_jit = hash11(u_cell * 2.71 + UV2.x * 7.13) - 0.5;
	vec3 T1 = normalize(T + N * (-0.07 + f_jit * 0.10));
	vec3 T2 = normalize(T + N * (0.11 + f_jit * 0.14));

	float dotTH1 = dot(T1, H);
	float dotTH2 = dot(T2, H);
	float sinTH1 = sqrt(clamp(1.0 - dotTH1 * dotTH1, 0.0, 1.0));
	float sinTH2 = sqrt(clamp(1.0 - dotTH2 * dotTH2, 0.0, 1.0));

	float NdotL = dot(N, L);
	float spec_mask = smoothstep(-0.22, 0.30, NdotL);
	float spec1 = pow(sinTH1, 110.0) * spec_mask;
	float spec2 = pow(sinTH2, 30.0) * spec_mask;

	// Wrapped fibrous diffuse + subtle translucent tip rim
	float wrapped = clamp((NdotL + 0.56) / 1.62, 0.0, 1.0);
	float backlit = pow(clamp(dot(V, -L), 0.0, 1.0), 3.2) * smoothstep(0.35, 0.95, UV.y) * 0.14;

	float scalp_spec = is_scalp ? 0.28 : 1.0;
	DIFFUSE_LIGHT += ALBEDO * (wrapped * 0.74 + backlit) * LIGHT_COLOR * ATTENUATION;
	SPECULAR_LIGHT += (sheen_primary * spec1 * 0.06 + sheen_secondary * spec2 * 0.06) * scalp_spec * LIGHT_COLOR * ATTENUATION;
}
