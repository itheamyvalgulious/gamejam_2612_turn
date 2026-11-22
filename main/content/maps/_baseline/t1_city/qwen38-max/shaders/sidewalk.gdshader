shader_type spatial;
// Sidewalk: concrete + storefront neon spill band at the building edge.
// UV.x = meters along, UV.y = meters across (0 = curb, UV2.x = width).
uniform vec4 haze_col : source_color = vec4(0.085, 0.055, 0.15, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.6;
varying float vdist;
varying float vhy;

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
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.11 + 9.3; a *= 0.5; }
	return v;
}

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vhy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec2 p = UV * 6.0;
	float n = fbm(p * 0.35);
	float fine = fbm(p * 3.0);
	vec3 c = vec3(0.16, 0.16, 0.18) * (0.75 + 0.5 * n) * (0.85 + 0.3 * fine);
	// paving joints
	float joint = smoothstep(0.04, 0.0, min(fract(UV.x / 2.0), fract(UV.y / 2.0))) * 0.3;
	c *= 1.0 - joint;
	float sw = max(UV2.x, 2.0);
	float band = smoothstep(max(sw - 1.8, 0.0), sw - 0.3, UV.y);
	vec3 shopcol = mix(vec3(1.0, 0.3, 0.55), vec3(0.25, 0.9, 1.0), step(0.5, hash21(vec2(floor(UV.x / 7.0), 1.7))));
	shopcol = mix(shopcol, vec3(1.0, 0.7, 0.25), step(0.8, hash21(vec2(floor(UV.x / 7.0), 4.2))));
	float flick = (0.45 + 0.55 * vnoise(vec2(UV.x * 1.3, 2.2))) * (0.7 + 0.3 * vnoise(vec2(UV.x * 0.5, 7.7)));
	vec3 spill = band * shopcol * 0.09 * flick;
	// aerial perspective + height fog
	float hfac = 1.0 + 1.8 * exp(-max(vhy, 0.0) * 0.025);
	float hz = 1.0 - exp(-vdist * haze_den * hfac);
	ALBEDO = mix(c, haze_col.rgb, hz);
	SPECULAR = 0.06;
	ROUGHNESS = mix(0.85, 0.4, band * 0.6);
	METALLIC = 0.0;
	EMISSION = mix(spill + vec3(0.014, 0.012, 0.024) * (0.5 + 0.8 * n),
			haze_col.rgb * haze_emis * (0.4 + 0.8 * exp(-max(vhy, 0.0) * 0.02)), hz);
}
