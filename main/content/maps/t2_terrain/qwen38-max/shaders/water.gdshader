shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

// Flowing water. UV.x = metres along the flow, UV.y = across (0..1).
// COLOR.r = speed factor, COLOR.g = rapids factor (0..1).
// Waves advect ALONG the channel tangent; vertex shader adds real geometric
// wave displacement; foam forms in rapids, at shores and over shallow depth.

uniform vec3 u_deep : source_color = vec3(0.010, 0.075, 0.150);
uniform vec3 u_shallow : source_color = vec3(0.05, 0.34, 0.36);
uniform sampler2D u_depth : hint_depth_texture;

varying vec3 v_world;
varying vec2 v_uv;
varying vec3 v_col;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1,0,0)), f.x),
			mix(hash13(i + vec3(0,1,0)), hash13(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0,0,1)), hash13(i + vec3(1,0,1)), f.x),
			mix(hash13(i + vec3(0,1,1)), hash13(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p, int oct) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 5; i++) {
		if (i >= oct) break;
		s += a * vnoise(p);
		p = p * 2.03 + vec3(7.7);
		a *= 0.5;
	}
	return s;
}

// advected wave height field in flow-space (u = along, v = across)
// anisotropic: features elongated along the flow direction
float wave_h(vec2 uv, float sp, float rap) {
	float u = uv.x * 0.22 - TIME * 1.9 * sp;
	float h = fbm(vec3(u, uv.y * 7.0, 0.7), 3) * 0.6;
	h += fbm(vec3(u * 2.7 + 3.1, uv.y * 13.0, 1.3), 2) * (0.25 + 0.35 * rap);
	h += sin(uv.x * 0.30 - TIME * 1.7 * sp + uv.y * 4.0) * 0.15;
	return h;
}

void vertex() {
	float sp = COLOR.r;
	float rap = COLOR.g;
	float ph = UV.x * 0.30 - TIME * 1.7 * sp;
	float w = sin(ph + UV.y * 4.0) * 0.5
		+ sin(ph * 1.9 - UV.y * 7.0 + 1.7) * 0.3
		+ sin(ph * 0.53 + UV.y * 2.0) * 0.2;
	VERTEX.y += w * (0.06 + 0.22 * rap);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;
	v_col = COLOR.rgb;
}

void fragment() {
	float sp = v_col.r;
	float rap = v_col.g;

	// wave normal from finite differences of the advected field
	float e = 0.06;
	float h0 = wave_h(v_uv, sp, rap);
	float hu = wave_h(v_uv + vec2(e, 0.0), sp, rap);
	float hv = wave_h(v_uv + vec2(0.0, e), sp, rap);
	// flow ~ +Z, across ~ +X in world (ribbon built axis-aligned)
	vec3 Nw = normalize(vec3(-(hv - h0) / e * 1.0, 1.0, -(hu - h0) / e * 0.9));
	NORMAL = normalize(mat3(VIEW_MATRIX) * Nw);

	// screen-space depth -> shallow/deep + shore foam
	float dpt = texture(u_depth, SCREEN_UV).x;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, dpt * 2.0 - 1.0, 1.0);
	vec3 sc = up.xyz / up.w;
	float d = max(-sc.z - (-VERTEX.z), 0.0);

	vec3 base = mix(u_shallow, u_deep, 1.0 - exp(-d * 0.10));

	// rapids white-water streaks along the flow
	float streak = fbm(vec3(v_uv.x * 1.5 - TIME * 3.2 * sp, v_uv.y * 2.5, 5.0), 3);
	float rap_foam = smoothstep(0.52, 0.80, streak) * rap;
	// churning foam in rapids
	float churn = fbm(vec3(v_uv.x * 0.9 - TIME * 2.6 * sp, v_uv.y * 7.0, 2.2), 3);
	rap_foam = max(rap_foam, smoothstep(0.48, 0.78, churn) * rap * 0.9);
	// shore ripples + foam at both banks
	float edge = smoothstep(0.14, 0.0, v_uv.y) + smoothstep(0.86, 1.0, v_uv.y);
	float ripple = sin(v_uv.x * 2.2 - TIME * 2.4 + sin(v_uv.y * 24.0) * 1.5) * 0.5 + 0.5;
	float shore = clamp(edge, 0.0, 1.0) * (0.25 + 0.55 * ripple * (0.4 + 0.6 * fbm(vec3(v_uv.x * 0.7 - TIME * 1.2, v_uv.y * 9.0, 8.0), 2)));
	// depth foam
	float dfoam = smoothstep(1.2, 0.1, d) * (0.3 + 0.7 * fbm(vec3(v_world.xz * 0.6, TIME * 0.6), 3));

	float foam = clamp(max(max(rap_foam, shore), dfoam), 0.0, 1.0);
	base = mix(base, vec3(0.92, 0.96, 0.98), foam * 0.9);

	ALBEDO = base;
	ROUGHNESS = mix(0.30, 0.08, 1.0 - foam);
	METALLIC = 0.0;
	SPECULAR = 0.45;
	ALPHA = clamp(0.55 + d * 0.10 + foam * 0.45, 0.0, 1.0);
}
