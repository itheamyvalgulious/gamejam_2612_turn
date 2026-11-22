shader_type spatial;
uniform vec4 haze_col : source_color = vec4(0.085, 0.055, 0.15, 1.0);
uniform float haze_den = 0.00022;
uniform float haze_emis = 0.6;
varying float vdist;
varying float vhy;
// Procedural cyberpunk facade v2 — pure math, no textures.
// UV.x = meters along facade perimeter, UV.y = world height.
// CUSTOM0 = (seed, floor_h, perimeter, style*16 + ground_h). COLOR.rgb = tint.

varying vec4 vmeta;
varying vec3 vtint;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
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
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.03 + 17.7; a *= 0.5; }
	return v;
}

// random CJK-like glyph stroke distance field, p in [0,1]^2
float glyph(vec2 p, float hs) {
	float d = 1.0;
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float hk = hash21(vec2(hs * 7.13 + fk * 13.7, hs * 3.31 - fk * 5.1));
		float ang = floor(hash21(vec2(hk * 31.7, fk * 3.3)) * 4.0);
		vec2 a = vec2(0.15 + 0.5 * hash21(vec2(hk * 17.3, fk * 3.1)),
				0.15 + 0.5 * hash21(vec2(hk * 23.9, fk * 5.7)));
		vec2 dv = ang < 0.5 ? vec2(1, 0) : ang < 1.5 ? vec2(0, 1) :
				ang < 2.5 ? vec2(0.707, 0.707) : vec2(0.707, -0.707);
		float len = 0.3 + 0.55 * hash21(vec2(hk * 41.1, fk * 7.7));
		vec2 pa = p - a;
		float t = clamp(dot(pa, dv), 0.0, len);
		d = min(d, length(pa - dv * t));
	}
	return d;
}

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vhy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	vmeta = vec4(UV2.x, UV2.y, 0.0, COLOR.a * 255.0);
	vtint = COLOR.rgb;
}

void fragment() {
	float sd = floor(vmeta.x + 0.5);
	float fh = max(vmeta.y, 2.6);
	float style = floor(vmeta.w / 16.0);
	float gh = vmeta.w - style * 16.0;
	float u = UV.x;
	float v = UV.y;

	// ---------- style parameters
	float bay = 3.8;
	float wy0 = 0.30, wy1 = 0.82;
	float win_cov = 0.42;
	float lit_prob = 0.26;
	if (style < 0.5) { bay = 3.2; wy0 = 0.06; wy1 = 0.94; win_cov = 0.82; lit_prob = 0.30; }
	else if (style < 1.5) { bay = 4.0; wy0 = 0.28; wy1 = 0.80; win_cov = 0.40; lit_prob = 0.28; }
	else if (style < 2.5) { bay = 3.6; wy0 = 0.32; wy1 = 0.78; win_cov = 0.36; lit_prob = 0.34; }
	else if (style < 3.5) { bay = 3.0; wy0 = 0.30; wy1 = 0.72; win_cov = 0.30; lit_prob = 0.30; }
	else if (style < 4.5) { bay = 1.4; wy0 = 0.72; wy1 = 0.92; win_cov = 0.16; lit_prob = 0.16; }
	else if (style < 5.5) { bay = 2.2; wy0 = 0.26; wy1 = 0.80; win_cov = 0.52; lit_prob = 0.26; }
	else if (style < 6.5) { bay = 3.4; wy0 = 0.12; wy1 = 0.90; win_cov = 0.66; lit_prob = 0.28; }
	else { bay = 4.5; wy0 = 0.08; wy1 = 0.92; win_cov = 0.78; lit_prob = 0.24; }

	// ---------- wall base
	float grain = fbm(vec2(u, v) * 0.7 + sd);
	vec3 wall = vtint * (0.30 + 0.30 * grain);
	if (style > 2.5 && style < 3.5) {
		// brick pattern
		vec2 bp = vec2(u / 0.55, v / 0.22);
		bp.x += floor(mod(bp.y, 2.0)) * 0.5;
		vec2 bf = fract(bp);
		float mortar = smoothstep(0.06, 0.1, bf.x) * smoothstep(0.06, 0.1, bf.y)
				* smoothstep(0.06, 0.1, 1.0 - bf.x) * smoothstep(0.06, 0.1, 1.0 - bf.y);
		wall = vtint * (0.5 + 0.55 * hash21(floor(bp))) * mix(0.35, 1.0, mortar);
	}
	if (style > 3.5 && style < 4.5) {
		// ribbed metal
		float rib = 0.5 + 0.5 * sin(u * 4.5);
		wall = vtint * (0.4 + 0.35 * rib) * (0.7 + 0.5 * grain);
	}
	wall *= 1.0 - 0.4 * (1.0 - smoothstep(0.0, 14.0, v));  // street grime
	// water streaks
	float streak = smoothstep(0.75, 0.95, hash21(vec2(floor(u / bay), sd))) *
			smoothstep(0.0, 30.0, v) * 0.25;
	wall *= 1.0 - streak;

	// ---------- window grid
	float vv = max(v - gh, 0.0);
	vec2 g = vec2(u / bay, vv / fh);
	vec2 id = floor(g);
	vec2 f = fract(g);
	float detail = 1.0 - smoothstep(140.0, 420.0, vdist);

	float wx = smoothstep(0.10, 0.14, f.x) * (1.0 - smoothstep(0.86, 0.90, f.x));
	if (style > 4.5 && style < 5.5) wx = 1.0;  // ribbon windows
	float wy = smoothstep(wy0 - 0.03, wy0 + 0.03, f.y) * (1.0 - smoothstep(wy1 - 0.03, wy1 + 0.03, f.y));
	float win = wx * wy;
	if (style > 5.5 && style < 6.5) win *= step(0.5, fract(id.y * 0.5 + sd));  // mega: alternating bands

	float hs = hash21(id + sd * 31.7);
	float lit = step(1.0 - lit_prob, hs);
	// whole-floor lighting for offices
	if (style < 0.5 || (style > 5.5 && style < 6.5)) lit = step(1.0 - lit_prob, hash21(vec2(id.y, sd * 3.1)));

	vec3 warm = vec3(1.0, 0.70, 0.38);
	vec3 cool = vec3(0.55, 0.78, 1.0);
	vec3 neon = mix(vec3(1.0, 0.22, 0.6), vec3(0.15, 0.95, 0.85), step(0.5, hash11(hs * 91.7)));
	vec3 litcol = mix(warm, cool, step(0.62, hs));
	litcol = mix(litcol, neon, step(0.93, hs));
	float bright = 0.55 + 1.15 * hash21(id * 5.11 + sd);
	// fake interior: blinds slats, furniture silhouettes, radial falloff
	float blinds = 0.80 + 0.20 * step(0.45, fract(f.y * 11.0 + hash21(id * 1.7 + sd) * 7.0));
	float furn = step(f.y, wy0 + 0.24 * hash21(id * 2.3 + sd)) * 0.7
			+ step(0.84, hash21(id * 4.9 + sd)) * (1.0 - step(0.32, f.x)) * step(wy0 + 0.08, f.y) * 0.55;
	furn = clamp(furn, 0.0, 0.9);
	float distc = length((f - vec2(0.5, (wy0 + wy1) * 0.5)) * vec2(1.0, 1.5));
	float fall = 0.7 + 0.5 * (1.0 - smoothstep(0.0, 0.55, distc));
	// window recess: edge AO + overhang shadow at top
	vec2 dinv = min(f - vec2(0.10, wy0), vec2(0.90, wy1) - f);
	float recess = smoothstep(0.0, 0.09, min(dinv.x, dinv.y));
	float topshade = 1.0 - 0.4 * smoothstep(wy1 - 0.3, wy1, f.y);
	vec3 emis_win = lit * litcol * bright * blinds * (1.0 - furn) * fall *
			(0.3 + 0.7 * recess) * topshade;

	// distance-blended averages: sparse bright window dots instead of flat glow
	vec3 glass_col = vec3(0.015, 0.024, 0.042);
	float win_a = win_cov;
	vec2 cg = floor(vec2(u, v * 0.5) / 5.0);
	float sp = step(0.87, hash21(cg + sd * 1.7));
	vec3 emis_a = (0.015 + sp * 1.5) *
			mix(warm, cool, step(0.6, hash21(cg * 3.3 + sd))) * win_a;
	vec3 alb = mix(mix(wall, glass_col, win_a), mix(wall, glass_col, win), detail);
	vec3 emis = mix(emis_a, win * emis_win, detail);
	// light spill halo: lit windows wash their own wall margins
	vec2 doutv = max(vec2(0.10, wy0) - f, f - vec2(0.90, wy1));
	float halo = exp(-max(max(doutv.x, doutv.y), 0.0) * 9.0) * (1.0 - win);
	emis += halo * lit * litcol * 0.14 * detail;
	float rough = mix(mix(0.85, 0.15, win_a), mix(0.85, 0.12, win), detail);
	float metal = mix(mix(0.05, 0.5, win_a), mix(0.05, 0.55, win), detail);

	// mullions
	float mull = smoothstep(0.03, 0.0, min(f.x, 1.0 - f.x)) * win;
	alb = mix(alb, vec3(0.02), mull * detail);
	rough = mix(rough, 0.4, mull * detail);

	// ---------- ground floor: storefront + sign glyphs
	if (v < gh) {
		float bayg = 3.0;
		vec2 gg = vec2(u / bayg, v / gh);
		vec2 gid = floor(gg);
		vec2 gf = fract(gg);
		float mullg = smoothstep(0.05, 0.02, min(gf.x, 1.0 - gf.x));
		float shop_lit = step(0.42, hash21(gid + sd * 7.7));
		vec3 shop_col = mix(warm, neon, step(0.6, hash21(gid * 3.3 + sd)));
		float door = step(0.35, gf.x) * (1.0 - step(0.65, gf.x)) * (1.0 - step(0.75, gf.y));
		vec3 shop_emis = shop_lit * shop_col * (0.55 + 0.5 * hash21(gid * 9.1 + sd)) * (1.0 - door * 0.7);
		// shutter (closed shops): horizontal ribs, dim
		float closed = step(hash21(gid + sd * 13.1), 0.3);
		float ribs = 0.5 + 0.5 * sin(v * 40.0);
		alb = mix(alb, mix(vec3(0.02, 0.025, 0.035), vtint * 0.35 * (0.6 + 0.4 * ribs), closed), 1.0);
		emis = mix(emis, shop_emis * (1.0 - closed), 1.0);
		rough = mix(rough, 0.15, 1.0 - closed);
		metal = mix(metal, 0.6, 1.0 - closed);
		alb = mix(alb, vec3(0.02), mullg);
		// sign band with procedural glyphs
		float band = smoothstep(gh - 1.25, gh - 1.15, v) * (1.0 - smoothstep(gh - 0.25, gh - 0.15, v));
		if (band > 0.0) {
			vec2 sp = vec2(u / 1.15, (v - (gh - 1.2)) / 1.0);
			vec2 sid2 = vec2(floor(sp.x), 0.0);
			vec2 sf = fract(sp);
			float gd = glyph(sf, hash21(sid2 + sd * 5.5) * 50.0);
			float gm = 1.0 - smoothstep(0.06, 0.11, gd);
			vec2 grp = vec2(floor(sp.x / 7.0), 0.0);
			vec3 sign_col = mix(vec3(1.0, 0.25, 0.55), vec3(0.2, 0.95, 1.0), step(0.5, hash21(grp + sd * 2.2)));
			sign_col = mix(sign_col, vec3(1.0, 0.75, 0.2), step(0.8, hash21(grp * 7.7 + sd)));
			float flick = 0.75 + 0.25 * step(0.97, hash21(grp + floor(TIME * 3.0) * 0.37));
			emis = mix(emis, sign_col * (0.6 + 2.6 * gm) * flick, band);
			alb = mix(alb, vec3(0.03), band);
		}
	}

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emis;
	// aerial perspective + height fog (Environment fog replacement)
	float hfac = 1.0 + 1.8 * exp(-max(vhy, 0.0) * 0.025);
	float hz = 1.0 - exp(-vdist * haze_den * hfac);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis * (0.4 + 0.8 * exp(-max(vhy, 0.0) * 0.02)), hz);
}

