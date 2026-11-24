// ============================================================================
//  math.gdshaderinc — shared procedural-texture math library
//  All textures in this project are generated from analytic formulas: hashes,
//  value noise, fbm, Voronoi cells, panel grids and derivative-based bump.
// ============================================================================

float m_sat(float x) { return clamp(x, 0.0, 1.0); }
float m_sat01(float x) { return clamp(x, 0.0, 1.0); }
vec2 m_sat2(vec2 x) { return clamp(x, vec2(0.0), vec2(1.0)); }

// --- integer-ish hashes -----------------------------------------------------
float m_hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}
float m_hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 m_hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}
float m_hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
vec3 m_hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yzz) * p.zyx);
}

// --- value noise ------------------------------------------------------------
float m_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = m_hash21(i);
	float b = m_hash21(i + vec2(1.0, 0.0));
	float c = m_hash21(i + vec2(0.0, 1.0));
	float d = m_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float m_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = m_hash31(i);
	float n100 = m_hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = m_hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = m_hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = m_hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = m_hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = m_hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = m_hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z);
}

// --- fbm --------------------------------------------------------------------
float m_fbm2(vec2 p, int oct) {
	float a = 0.5, s = 0.0, n = 0.0;
	for (int i = 0; i < oct; i++) {
		s += a * m_noise2(p);
		n += a;
		p = p * 2.03 + vec2(11.7, 5.1);
		a *= 0.5;
	}
	return s / max(n, 0.0001);
}

float m_fbm3(vec3 p, int oct) {
	float a = 0.5, s = 0.0, n = 0.0;
	for (int i = 0; i < oct; i++) {
		s += a * m_noise3(p);
		n += a;
		p = p * 2.02 + vec3(3.1, 7.7, 1.3);
		a *= 0.5;
	}
	return s / max(n, 0.0001);
}

// turbulence: abs-noise gives that streaky industrial grime look
float m_turb2(vec2 p, int oct) {
	float a = 0.5, s = 0.0, n = 0.0;
	for (int i = 0; i < oct; i++) {
		s += a * abs(m_noise2(p) * 2.0 - 1.0);
		n += a;
		p = p * 2.05 + vec2(4.3, 9.1);
		a *= 0.5;
	}
	return s / max(n, 0.0001);
}

// --- voronoi ----------------------------------------------------------------
float m_voronoi(vec2 p, out vec2 cell_id, out float edge, out float cell_rand) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	cell_id = ip;
	cell_rand = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = m_hash22(ip + g);
			vec2 r = g + o - fp;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				cell_id = ip + g;
				cell_rand = m_hash21(ip + g + 17.3);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	edge = sqrt(d2) - sqrt(d1);
	return sqrt(d1);
}

// --- panel grid -------------------------------------------------------------
// Returns seam mask (1 = seam), per-cell random, and inside-cell coords.
float m_panels(vec2 uv, vec2 size, float stagger, float seed,
		out vec2 cell, out vec2 f, out float rnd) {
	vec2 s = uv / size;
	float row = floor(s.y);
	s.x += m_hash21(vec2(row, 3.7) + seed) * stagger;
	cell = floor(s);
	f = fract(s);
	vec2 d = min(f, 1.0 - f) * size;      // meters to nearest seam
	float dist = min(d.x, d.y);
	rnd = m_hash21(cell + seed * 17.0);
	float footprint = max(length(fwidth(uv)), 0.0001);
	float coverage = 1.0 - smoothstep(0.003, 0.016 + footprint * 0.65, dist);
	return coverage * min(1.0, 0.016 / footprint);
}

// thin bright bevel line on the top/left edge of a panel (catches light)
float m_bevel_line(vec2 f, float width) {
	float d = min(f.x, f.y);
	float d2 = min(abs(f.x - 1.0), abs(f.y - 1.0));
	return 1.0 - smoothstep(0.0, width, min(d, d2));
}

// --- derivative bump --------------------------------------------------------
// Godot's screen-space derivative bump, wrapped with a strength multiplier.
vec3 m_bump(vec3 N, vec3 P, float h, float strength) {
	vec3 dpdx = dFdx(P);
	vec3 dpdy = dFdy(P);
	float dhdx = dFdx(h) * strength;
	float dhdy = dFdy(h) * strength;
	vec3 r1 = cross(dpdy, N);
	vec3 r2 = cross(N, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	// Cap grazing-angle gradients instead of flipping the entire lit surface.
	vec3 slope = grad / max(abs(det), 1e-8);
	slope /= max(1.0, length(slope) / 1.2);
	return normalize(N - slope);
}

// --- misc -------------------------------------------------------------------
vec2 m_rot(vec2 p, float a) {
	float c = cos(a), s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// anti-aliased line on a coordinate (returns 1 near x=integer)
float m_grid_line(float x, float width) {
	float f = abs(fract(x) - 0.5) * 2.0;
	return smoothstep(1.0 - width, 1.0, f);
}

float m_streaks(vec2 uv, float scale, float seed) {
	// vertically-stretched turbulence for grime running down surfaces
	vec2 p = vec2(uv.x * scale, uv.y * scale * 0.08) + seed;
	return m_turb2(p, 4);
}

float m_scratches(vec2 uv, float scale, float seed) {
	vec2 p = vec2(uv.x * scale * 0.06, uv.y * scale * 1.9) + seed;
	float n = m_noise2(p);
	return smoothstep(0.72, 0.9, n);
}

// distance to a rounded rectangle (for hatches / inset details)
float m_sd_round_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}