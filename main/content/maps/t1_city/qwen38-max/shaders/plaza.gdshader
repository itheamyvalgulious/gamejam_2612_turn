shader_type spatial;
// Plaza paving: radial rings + emissive inlay + slab noise.
uniform vec4 inlay_color : source_color = vec4(0.3, 0.85, 1.0, 1.0);
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
	for (int i = 0; i < 3; i++) { v += a * vnoise(p); p = p * 2.13 + 4.1; a *= 0.5; }
	return v;
}

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vhy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec2 p = UV;   // centered meters
	float r = length(p - vec2(0.0));
	vec3 c = vec3(0.13, 0.13, 0.15) * (0.7 + 0.6 * fbm(p * 0.15));
	// radial ring joints
	float ring = smoothstep(0.06, 0.0, abs(fract(r * 0.12) - 0.5) * 2.0 - 0.94);
	c *= 1.0 - ring * 0.5;
	// emissive inlay rings
	float inlay = smoothstep(0.03, 0.0, abs(fract(r * 0.06 + 0.25) - 0.5) * 2.0 - 0.985);
	vec3 emis = inlay_color.rgb * inlay * 1.4;
	// slab joints
	vec2 sf = fract(p * 0.5);
	float joint = smoothstep(0.04, 0.0, min(min(sf.x, 1.0 - sf.x), min(sf.y, 1.0 - sf.y)));
	c *= 1.0 - joint * 0.4;
	ALBEDO = c;
	ROUGHNESS = 0.7;
	SPECULAR = 0.1;
	EMISSION = emis + vec3(0.014, 0.012, 0.024) * (0.5 + 0.8 * fbm(p * 0.3));
	float hfac = 1.0 + 1.8 * exp(-max(vhy, 0.0) * 0.025);
	float hz = 1.0 - exp(-vdist * haze_den * hfac - vdist * vdist * 3.5e-8);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis * (0.4 + 0.8 * exp(-max(vhy, 0.0) * 0.02)), hz);
}
