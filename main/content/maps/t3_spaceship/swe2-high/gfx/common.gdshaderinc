// common.gdshaderinc — hash / noise / pattern helpers shared by every shader.
// UVs are metres, so all frequencies below are in 1/m.

float h11(float p) {
	return fract(sin(p * 127.1) * 43758.5453123);
}
float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
float h31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}
vec2 h22(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

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
	for (int i = 0; i < 8; i++) {
		if (i >= oct) { break; }
		v += a * vnoise(p);
		p = p * 2.03 + vec2(19.7, 7.3);
		a *= 0.5;
	}
	return v;
}

float fbm3(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 8; i++) {
		if (i >= oct) { break; }
		v += a * (h31(floor(p)) * 0.0 + vnoise(p.xz + p.y * 3.1));
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Voronoi: returns (F1, F2, cell-hash). domain in metres * density.
vec3 voro(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = h22(ip + g);
		vec2 r = g + o - fp;
		float d = dot(r, r);
		if (d < f1) { f2 = f1; f1 = d; id = h21(ip + g); }
		else if (d < f2) { f2 = d; }
	}
	return vec3(sqrt(f1), sqrt(f2), id);
}

// Rect panel field. Returns seam mask (0 = flat panel, 1 = deep seam).
// Distance-based groove ~18mm wide; AA-safe at any fwidth.
float panels(vec2 uv, vec2 size, float jitter, float seed,
		out vec2 cid, out vec2 frac, out float rnd) {
	vec2 q = uv / size;
	vec2 i = floor(q);
	frac = fract(q);
	cid = i;
	rnd = h21(i + seed * 13.7);
	// distance to cell border in metres -> soft groove, fades out at range so
	// far walls read as a tint lattice instead of dashed noise
	vec2 d = min(frac, 1.0 - frac) * size;
	float dm = min(d.x, d.y);
	float px = max(fwidth(uv.x), fwidth(uv.y));
	float fade = 1.0 - smoothstep(0.03, 0.12, px);
	float aa = px * 1.6 + 0.006;
	float seam = (1.0 - smoothstep(0.004, 0.016 + aa, dm)) * fade;
	return clamp(seam, 0.0, 1.0);
}

// Anti-aliased stripe: d is distance in metres, w is half-width.
float stripe(float d, float w, float aa) {
	return 1.0 - smoothstep(w - aa, w + aa, d);
}

// Grid lines mask, pitch metres.
float gridm(vec2 uv, float pitch, float w) {
	vec2 g = abs(fract(uv / pitch) - 0.5) * pitch;
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.004, min(g.x, g.y));
}

// Fine brushed-metal anisotropy signal. Fades to 0.5 when the pattern
// frequency exceeds the pixel footprint (kills distant shimmer).
float brushed(vec2 uv, float scale, float dir) {
	float px = max(fwidth(uv.x), fwidth(uv.y));
	float fade = 1.0 - smoothstep(0.10, 0.35, px * scale);
	float v = vnoise(vec2(uv.x * dir + uv.y * (1.0 - dir),
		uv.y * dir + uv.x * (1.0 - dir)) * scale);
	return mix(0.5, v, fade);
}

// Rivet/bolt dots on a regular grid. Returns height-ish mask 0..1.
// Fades out when a pixel covers more than ~1/8 of the pitch so distant
// surfaces stop speckling.
float rivets(vec2 uv, float pitch, float r) {
	vec2 g = fract(uv / pitch) - 0.5;
	float d = length(g * pitch);
	float px = max(fwidth(uv.x), fwidth(uv.y));
	float fade = 1.0 - smoothstep(pitch * 0.06, pitch * 0.2, px);
	return (1.0 - smoothstep(r * 0.6, r, d)) * fade;
}

// surface-gradient bump: perturb view-space normal from height field h.
vec3 bumpn(vec3 N, vec3 P, float h, float strength) {
	vec3 dpdx = dFdx(P);
	vec3 dpdy = dFdy(P);
	float dhdx = dFdx(h) * strength;
	float dhdy = dFdy(h) * strength;
	vec3 r1 = cross(dpdy, N);
	vec3 r2 = cross(N, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * N - grad);
}
