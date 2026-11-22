shader_type spatial;
// River / harbor water v2: 4-octave analytic waves, bank foam, moon glint
// path, ripple-distorted neon city reflection columns.
uniform vec4 haze_col : source_color = vec4(0.085, 0.055, 0.15, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.6;
uniform float emis_scale = 1.0;
varying float vdist;
varying float vhy;
varying vec3 vworld;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vhy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	vworld = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vworld.xz;
	float t = TIME * 0.6;
	// wave height field: 4 directional sines, analytic gradient
	vec2 grad = vec2(0.0);
	float h = 0.0;
	vec2 k1 = vec2(0.08, 0.05); vec2 k2 = vec2(-0.06, 0.09);
	vec2 k3 = vec2(0.13, -0.11); vec2 k4 = vec2(0.21, 0.17);
	h += sin(dot(k1, p) * 3.0 + t * 1.7);
	grad += k1 * 3.0 * cos(dot(k1, p) * 3.0 + t * 1.7);
	h += 0.6 * sin(dot(k2, p) * 4.0 - t * 1.3);
	grad += k2 * 2.4 * cos(dot(k2, p) * 4.0 - t * 1.3);
	h += 0.35 * sin(dot(k3, p) * 7.0 + t * 2.3);
	grad += k3 * 2.45 * cos(dot(k3, p) * 7.0 + t * 2.3);
	h += 0.18 * sin(dot(k4, p) * 11.0 - t * 3.1);
	grad += k4 * 1.98 * cos(dot(k4, p) * 11.0 - t * 3.1);
	vec3 n = normalize(vec3(-grad.x * 0.06, 1.0, -grad.y * 0.06));
	NORMAL = n;

	float across = clamp(UV.y / 0.02, -1.0, 1.0);   // -1..1 bank to bank
	vec3 deep = vec3(0.006, 0.016, 0.024);
	ALBEDO = deep;
	ROUGHNESS = 0.06;
	METALLIC = 0.2;
	SPECULAR = 0.8;

	float fr = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	float fres = clamp(0.25 + 0.75 * fr, 0.0, 1.0);
	vec3 skyref = mix(vec3(0.05, 0.03, 0.09), vec3(0.14, 0.08, 0.24), fres);

	// neon city reflection columns, distorted by ripples
	float dist_u = UV.x * 50.0 + h * 0.35;
	float colid = floor(dist_u / 2.2 + hash11(floor(p.y / 90.0)) * 3.0);
	vec3 neon = mix(vec3(1.0, 0.3, 0.55), vec3(0.25, 0.85, 1.0), hash11(colid));
	neon = mix(neon, vec3(1.0, 0.7, 0.2), step(0.75, hash11(colid * 3.7)));
	float streak = smoothstep(0.55, 0.95, sin(dist_u * 1.6 + hash11(colid) * 9.0)) *
			(0.4 + 0.6 * sin(p.y * 0.8 + t * 2.0 + h * 2.0));
	streak = max(streak, 0.0);
	// moon glint path: specular lobe toward view azimuth
	float glint = pow(max(0.0, 1.0 - abs(fract(dist_u * 0.31) - 0.5) * 2.4), 3.0) *
			smoothstep(0.6, 1.0, fr) * 0.5;

	float ripple = 0.55 + 0.45 * sin(p.y * 1.7 + t * 1.4 + h * 1.5);
	EMISSION = (skyref * (0.10 + 0.5 * fres) * ripple
			+ neon * streak * 1.2 * (0.3 + 0.7 * fres)
			+ vec3(0.8, 0.85, 1.0) * glint) * emis_scale;

	// bank foam + quay darkening
	float bank = smoothstep(0.86, 1.0, abs(across));
	float foam = bank * (0.35 + 0.65 * vnoise(p * 1.7 + t * 0.4));
	ALBEDO = mix(ALBEDO, vec3(0.10, 0.12, 0.13), foam * 0.7);
	ROUGHNESS = mix(ROUGHNESS, 0.5, foam);
	EMISSION += vec3(0.05, 0.06, 0.07) * foam * 0.5;

	// aerial perspective + height fog
	float hfac = 1.0 + 1.8 * exp(-max(vhy, 0.0) * 0.025);
	float hz = 1.0 - exp(-vdist * haze_den * hfac - vdist * vdist * 3.5e-8);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis * (0.4 + 0.8 * exp(-max(vhy, 0.0) * 0.02)), hz);
}
