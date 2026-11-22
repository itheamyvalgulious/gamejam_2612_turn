shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, blend_mix;

// Lake disc, local origin at lake centre. VERTEX.xz is the offset from centre.
// Gentle broad swells (vertex) + shore foam ring + slight specular.

uniform float u_radius = 285.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(11.7, 3.1);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	vec3 p = VERTEX;
	// broad gentle swells: two long-wavelength, slow-moving waves
	float s1 = sin(p.x * 0.03 + TIME * 0.5) * cos(p.z * 0.035 + TIME * 0.4);
	float s2 = sin(p.x * 0.08 - TIME * 0.8 + p.z * 0.05) * 0.4;
	float s3 = sin(p.x * 0.05 + p.z * 0.04 + TIME * 0.6) * 0.3;
	VERTEX.y += s1 * 0.35 + s2 * 0.15 + s3 * 0.10;
}

void fragment() {
	vec3 p = VERTEX;
	float r = length(p.xz);
	// narrow foam hug at the very shore line
	float edge = smoothstep(u_radius * 0.96, u_radius, r);
	float foamnoise = fbm(p.xz * 0.12 + vec2(TIME * 0.5, -TIME * 0.4));
	float foam = edge * (0.25 + 0.45 * foamnoise);
	// darker teal body — reads as deep jungle water, not sky reflection
	vec3 deep = vec3(0.02, 0.10, 0.12);
	vec3 shallow = vec3(0.05, 0.20, 0.18);
	vec3 col = mix(deep, shallow, smoothstep(0.0, 0.85, r / u_radius));
	float d = fbm(p.xz * 0.25 + vec2(TIME * 0.2, TIME * 0.15));
	col += vec3(0.015, 0.025, 0.02) * d;
	col = mix(col, vec3(0.80, 0.88, 0.86), clamp(foam * 0.7, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(0.88 + foam * 0.12, 0.0, 1.0);
	ROUGHNESS = 0.7;    // rough water, not a mirror
	METALLIC = 0.0;
	SPECULAR = 0.15;
	// gentle normal from the swell field
	vec2 e = vec2(0.5, 0.0);
	float nx = fbm(p.xz * 0.25 + e) - fbm(p.xz * 0.25 - e);
	float ny = fbm(p.xz * 0.25 + e.yx) - fbm(p.xz * 0.25 - e.yx);
	NORMAL = normalize(vec3(-nx * 0.4, 1.0, -ny * 0.4));
}
