shader_type spatial;
uniform vec4 haze_col : source_color = vec4(0.055, 0.04, 0.105, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.5;
varying float vdist;
// Park grass: layered noise greens with worn patches.

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
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.17 + 9.3; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 p = UV * 8.0;
	float n = fbm(p * 0.4);
	float fine = fbm(p * 4.0);
	vec3 g1 = vec3(0.045, 0.10, 0.035);
	vec3 g2 = vec3(0.075, 0.13, 0.05);
	vec3 dry = vec3(0.11, 0.10, 0.05);
	vec3 c = mix(g1, g2, n);
	c = mix(c, dry, smoothstep(0.6, 0.85, fbm(p * 0.15 + 31.0)) * 0.7);
	c *= 0.8 + 0.4 * fine;
	ALBEDO = c;
	ROUGHNESS = 0.95;
	// aerial perspective haze (Environment fog replacement)
	float hz = 1.0 - exp(-vdist * haze_den);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis, hz);
}

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

