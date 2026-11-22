shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled, shadows_disabled, specular_disabled;

// Thin plasma sheet that fills the arc volume. It is deliberately faint in
// the middle and bright at the two long edges, so the sword silhouette is
// legible even when the stochastic leaders happen to be sparse.

uniform float fade : hint_range(0.0, 1.5) = 1.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
uniform float charge : hint_range(0.0, 1.5) = 0.0;
uniform float time = 0.0;

varying vec2 v_uv;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_uv = UV;
}

void fragment() {
	float u = abs(v_uv.x * 2.0 - 1.0);
	float v = v_uv.y;

	// Edge channel: slightly wider at the base, razor thin at the point.
	float edge_w = mix(0.115, 0.030, pow(v, 0.7));
	float edge = smoothstep(1.0 - edge_w, 1.0, u);

	// Interior: slow upward flow plus fine scan bands, never a flat fill.
	float flow = 0.5 + 0.5 * sin(v * 21.0 - time * 2.1 + sin(v_uv.x * 7.0) * 0.8);
	float bands = 0.5 + 0.5 * sin(v * 130.0 - time * 9.0 + hash(vec2(v_uv.x * 9.0, 3.0)) * 2.0);
	float sheet = (0.30 + 0.70 * flow * bands) * (0.30 + 0.70 * (1.0 - u));

	// Hot central spine.
	float spine = smoothstep(0.055, 0.0, u) * (0.55 + 0.45 * flow);

	float root = smoothstep(0.0, 0.045, v);
	float tip = smoothstep(1.0, 0.975, v);
	float envelope = root * tip;

	float a = (edge * 0.46 + sheet * 0.045 + spine * 0.055) * envelope * fade * intensity;
	a *= 1.0 + charge * 0.55;

	vec3 amber = vec3(1.00, 0.20, 0.008);
	vec3 hot = vec3(2.30, 1.45, 0.46);
	ALBEDO = mix(amber, hot, clamp(edge * 0.75 + spine * 0.4 + sheet * 0.10, 0.0, 1.0));
	ALPHA = clamp(a, 0.0, 0.82);
}