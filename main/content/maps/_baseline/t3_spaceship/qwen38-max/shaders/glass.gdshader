shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;

// Viewport glass: faint hex etch, fresnel sheen, edge grime. Reflections come
// from ReflectionProbes / sky. Kept mostly transparent to read space outside.

uniform vec3 u_tint = vec3(0.6, 0.78, 1.0);
uniform float u_alpha_scale = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hexlines(vec2 p) {
	// cheap triangular-grid approximation of a hex etch
	vec2 q = p * vec2(1.0, 1.1547);
	vec2 g = abs(fract(q) - 0.5);
	vec2 g2 = abs(fract(q + vec2(0.5, 0.5)) - 0.5);
	float d = min(min(g.x, g.y), min(g2.x, g2.y) * 0.6 + min(g.x, g.y) * 0.6);
	return 1.0 - smoothstep(0.02, 0.055, d);
}

void fragment() {
	vec3 nrm = normalize(NORMAL);
	float fres = pow(1.0 - clamp(abs(dot(nrm, normalize(VIEW))), 0.0, 1.0), 3.0);
	float hex = hexlines(wpos.xz + wpos.yz) * 0.5;
	float grime = smoothstep(0.75, 1.0, fract(sin(dot(floor(wpos.xz * 0.3), vec2(12.99, 78.23))) * 43758.5)) * 0.015;
	ALBEDO = u_tint * 0.12;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	ALPHA = clamp((0.03 + fres * 0.34 + hex * 0.035 + grime) * u_alpha_scale, 0.0, 0.85);
	EMISSION = u_tint * hex * 0.02;
}
