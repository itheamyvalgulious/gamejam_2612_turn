shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

// =============================================================================
// VESPER // greatsword plasma core
// Smooth quintic-filtered domain-warped blue plasma blade with central bright
// conduit spine, animated internal current veins, icy edges, and surge waves.
// =============================================================================

uniform vec4 hot_color : source_color = vec4(0.88, 0.96, 1.0, 1.0);
uniform vec4 mid_color : source_color = vec4(0.08, 0.42, 1.0, 1.0);
uniform vec4 tip_color : source_color = vec4(0.45, 0.86, 1.0, 1.0);
uniform float energy = 1.50;
uniform float core_boost : hint_range(0.0, 1.0) = 0.45;
uniform float scan_scale = 28.0;
uniform float flow_speed = 14.0;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.18;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// C2 quintic interpolation prevents blocky grid artifacts in close-ups
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = rot * p * 2.04 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float t = UV.y;
	float across = abs(UV.x * 2.0 - 1.0);
	float time_s = TIME;

	// Domain-warped turbulent plasma currents streaming guard -> tip
	vec2 q = vec2(UV.x * 4.5, t * 7.5 - time_s * 2.4);
	float warp = fbm(q + vec2(0.0, time_s * 0.5));
	float plasma = fbm(vec2(UV.x * 6.5 + warp * 1.4, t * 11.0 - time_s * 3.4));
	float plasma_fine = fbm(vec2(UV.x * 12.0 - warp * 1.1, t * 22.0 - time_s * 5.8));

	// Deep cobalt containment pockets vs electric blue plasma body
	vec3 deep_cobalt = vec3(0.02, 0.11, 0.50);
	vec3 col = mix(deep_cobalt, mid_color.rgb, smoothstep(0.22, 0.78, plasma));
	col = mix(col, tip_color.rgb, smoothstep(0.55, 0.92, plasma_fine) * 0.45 + smoothstep(0.75, 1.0, t) * 0.30);

	// 3 sinuous pulsing energy filaments coursing inside the blade
	float veins = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float ph = fi * 2.094;
		float wob = (fbm(vec2(t * 7.5 - time_s * (1.8 + 0.35 * fi), ph)) - 0.5) * 0.56;
		float center = 0.5 + wob;
		float d = abs(UV.x - center);
		float line = exp(-(d * d) / (0.0018 + 0.0006 * fi));
		float v_pulse = 0.40 + 0.60 * sin(t * 9.0 - time_s * (6.2 + fi * 1.9) + ph * 3.0);
		veins += line * v_pulse;
	}

	// Incandescent central spine & razor-bright cyan cutting edges
	float spine = exp(-pow(across * 4.8, 2.0)) * (0.76 + 0.24 * sin(t * 9.0 - time_s * 5.2));
	float edge_cut = smoothstep(0.78, 0.995, across) * (0.78 + 0.22 * sin(t * 14.0 - time_s * 7.5));
	float emitter_root = smoothstep(0.16, 0.0, t) * (1.0 - across * 0.45);

	// Staggered travelling energy surges racing from hilt to tip
	float surge1_d = abs(t - fract(time_s * 0.72));
	float surge2_d = abs(t - fract(time_s * 0.72 + 0.5));
	float surge = smoothstep(0.11, 0.0, surge1_d) * 0.80 + smoothstep(0.09, 0.0, surge2_d) * 0.42;
	float breathe = 0.88 + 0.12 * sin(time_s * 3.6);
	float scan = 1.0 + scan_strength * 0.35 * sin(t * scan_scale - time_s * flow_speed);

	float hot_amt = clamp(spine * 0.74 + veins * 0.52 + edge_cut * 0.38 + emitter_root * 0.65 + surge * (0.35 + 0.30 * spine), 0.0, 1.0);
	col = mix(col, tip_color.rgb, clamp(edge_cut * 0.70, 0.0, 1.0));
	col = mix(col, hot_color.rgb, hot_amt * (0.60 + 0.35 * core_boost));

	float lum = (0.68 + 0.55 * plasma + spine * 0.65 + veins * 0.60 + edge_cut * 0.45 + surge * 0.58 + emitter_root * 0.45) * breathe * scan;
	ALBEDO = col * energy * lum;
	ALPHA = 1.0;
}
