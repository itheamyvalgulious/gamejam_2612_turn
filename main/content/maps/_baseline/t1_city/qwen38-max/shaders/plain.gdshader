shader_type spatial;
uniform vec4 haze_col : source_color = vec4(0.055, 0.04, 0.105, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.5;
// Generic tinted procedural surface (sidewalk / roof / ground).
uniform vec4 tint : source_color = vec4(0.5);
uniform float grain = 0.5;
uniform float uv_scale = 0.2;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.11 + vec2(11.7, 5.3);
		a *= 0.5;
	}
	return v;
}

varying float vdist;
varying float vhy;
varying vec2 vxz;

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vhy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	vxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = UV * (1.0 / max(uv_scale, 0.001));
	float n = fbm(p * 0.35);
	float fine = fbm(p * 3.0);
	float macro = fbm(p * 0.12 + 7.7);
	vec3 c = tint.rgb * (1.0 - grain * 0.5 + grain * n);
	c *= 0.55 + 0.9 * macro;
	c *= 0.85 + 0.3 * fine;
	// aerial perspective + height fog
	float hfac = 1.0 + 1.8 * exp(-max(vhy, 0.0) * 0.025);
	float hz = 1.0 - exp(-vdist * 0.00022 * hfac);
	ALBEDO = mix(c, vec3(0.085, 0.055, 0.15), hz);
	ROUGHNESS = 0.75 + 0.2 * fine;
	METALLIC = 0.0;
	float cityprox = 1.0 - smoothstep(1200.0, 2400.0, length(vxz));
	float groundness = 1.0 - smoothstep(6.0, 35.0, vhy);
	SPECULAR = 0.0;
	float hbreak = 0.55 + 0.9 * fbm(vxz * 0.00045 + 3.3);
	EMISSION = mix(vec3(0.020, 0.016, 0.032) * max(NORMAL.y, 0.0) * (0.35 + 0.9 * n) * (0.3 + 1.1 * macro) * (0.2 + 0.8 * cityprox) * (0.25 + 0.75 * groundness),
			vec3(0.085, 0.055, 0.15) * haze_emis * (0.4 + 0.8 * exp(-max(vhy, 0.0) * 0.02)) * hbreak, hz);
}


