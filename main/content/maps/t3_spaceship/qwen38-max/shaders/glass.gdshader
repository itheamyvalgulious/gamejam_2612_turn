shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;

// Viewport glass v2 — reflection/roughness separation: clean glass is a mirror,
// smudges & wipe arcs & edge dust raise roughness and add faint haze.

uniform vec3 u_tint = vec3(0.6, 0.78, 1.0);
uniform float u_alpha_scale = 1.0;
uniform float u_smudge : hint_range(0.0, 1.5) = 0.7;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 34.27);
	return fract(p.x * p.y * 95.43);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.7, 7.3);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 nrm = normalize(NORMAL);
	vec3 V = normalize(VIEW);
	float fres = pow(1.0 - clamp(abs(dot(nrm, V)), 0.0, 1.0), 3.0);
	vec2 uv = wpos.xz + wpos.yz + wpos.xy * 0.5;

	// smudge field: hand-wipe arcs + blotches + bottom dust line
	float arcs = abs(sin(uv.x * 1.7 + fbm(uv * 0.5) * 4.0)) * 0.5 + 0.5;
	float blotch = smoothstep(0.5, 0.8, fbm(uv * 1.6 + 9.0));
	float dustline = smoothstep(0.5, 0.0, fract(wpos.y * 0.35)) * 0.4;
	float sm = clamp((blotch * 0.7 + arcs * 0.25 * blotch + dustline) * u_smudge, 0.0, 1.0);

	float hex = 0.0;  // faint maintenance etch grid
	vec2 hg = fract(uv * 0.8);
	hex = (1.0 - smoothstep(0.01, 0.03, min(min(hg.x, 1.0 - hg.x), min(hg.y, 1.0 - hg.y)))) * 0.06;

	ALBEDO = u_tint * 0.12;
	ROUGHNESS = mix(0.02, 0.28, sm);       // clean mirror vs smeared
	METALLIC = 0.0;
	SPECULAR = 1.0;
	ALPHA = clamp((0.028 + fres * 0.34 + sm * 0.05 + hex) * u_alpha_scale, 0.0, 0.85);
	EMISSION = u_tint * hex * 0.5;
}
