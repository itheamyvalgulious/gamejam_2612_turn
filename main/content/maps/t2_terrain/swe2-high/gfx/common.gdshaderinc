// common.gdshaderinc — hash / noise / voronoi helpers shared by terrain shaders.
// All functions operate in plain float domains; callers scale as they like.

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float h31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Value noise, C1-continuous.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x),
		mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.52;
	}
	return v;
}

// Ridged fbm — sharp crests for rock strata.
float rfbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < oct; i++) {
		v += a * (1.0 - abs(vnoise(p) * 2.0 - 1.0));
		p = p * 2.11 + vec2(4.7, 12.9);
		a *= 0.5;
	}
	return v;
}

// Worley: returns (F1, F2, cell-hash).
vec3 worley(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++)
	for (int i = -1; i <= 1; i++) {
		vec2 g = vec2(float(i), float(j));
		vec2 o = hash22(ip + g);
		vec2 r = g + o - fp;
		float d = dot(r, r);
		if (d < f1) { f2 = f1; f1 = d; id = h21(ip + g); }
		else if (d < f2) { f2 = d; }
	}
	return vec3(sqrt(f1), sqrt(f2), id);
}

// Anti-aliased stripe: d = coordinate, c = centre, w = half-width.
float stripe(float d, float c, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + fwidth(d) * 1.6 + 0.004,
		abs(d - c));
}

// Cheap derivative bump: returns a normal tilt for a scalar height field.
// h = height at this fragment, dhdx/dhdz = screen-space derivative estimate.
vec3 bumpn(vec3 n, vec3 vx, float h, float amp) {
	float dx = dFdx(h);
	float dz = dFdy(h);
	vec3 t = normalize(cross(vec3(0, 0, 1), n));
	vec3 b = normalize(cross(n, t));
	return normalize(n - (t * dx + b * dz) * amp);
}
