shader_type spatial;
// Procedural cyberpunk facade v3 — material-layered, imperfect, depth-faked.
// UV.x = meters along facade perimeter, UV.y = world height (m).
// UV2 = (seed, floor_h). COLOR.rgb = tint, COLOR.a = (style*16 + ground_h)/255.
// Layers: frame (metal) / glass (dielectric, grime-varied roughness) /
// spandrel panel / wall pier (style material with bump) + storefront & glyphs.

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
float ridged(vec2 p) {
	float n = fbm(p);
	return 1.0 - abs(2.0 * n - 1.0);
}

// CJK-like glyph stroke distance field, p in [0,1]^2
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

// wall micro-height field (meters) for tangent-space bump
float wall_height(vec2 uv, float sd, float style, float bay, float fh) {
	float h = fbm(uv * 1.6 + sd) * 0.010;
	vec2 g = vec2(uv.x / bay, uv.y / fh);
	vec2 f = fract(g);
	float j = min(min(f.x, 1.0 - f.x) * bay, min(f.y, 1.0 - f.y) * fh);
	h -= 0.012 * (1.0 - smoothstep(0.0, 0.05, j));
	if (style > 2.5 && style < 3.5) {
		vec2 bp = vec2(uv.x / 0.55, uv.y / 0.22);
		bp.x += floor(mod(bp.y, 2.0)) * 0.5;
		vec2 bf = fract(bp);
		float m = min(min(bf.x, 1.0 - bf.x), min(bf.y, 1.0 - bf.y));
		h -= 0.010 * (1.0 - smoothstep(0.0, 0.12, m));
	}
	if (style > 3.5 && style < 4.5)
		h += 0.012 * sin(uv.x * 4.5);
	h -= 0.008 * smoothstep(0.86, 0.97, ridged(uv * 0.22 + sd * 3.0));
	return h;
}

void vertex() {
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vhy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float sd = floor(UV2.x + 0.5);
	float fh = max(UV2.y, 2.6);
	float style = floor(COLOR.a * 255.0 / 16.0);
	float gh = COLOR.a * 255.0 - style * 16.0;
	float u = UV.x;
	float v = UV.y;
	vec3 vtint = COLOR.rgb;

	// ---------- style parameters
	float bay = 3.8, wy0 = 0.30, wy1 = 0.82, win_cov = 0.42, lit_prob = 0.26;
	if (style < 0.5)      { bay = 3.2; wy0 = 0.06; wy1 = 0.94; win_cov = 0.82; lit_prob = 0.30; }
	else if (style < 1.5) { bay = 4.0; wy0 = 0.28; wy1 = 0.80; win_cov = 0.40; lit_prob = 0.28; }
	else if (style < 2.5) { bay = 3.6; wy0 = 0.32; wy1 = 0.78; win_cov = 0.36; lit_prob = 0.34; }
	else if (style < 3.5) { bay = 3.0; wy0 = 0.30; wy1 = 0.72; win_cov = 0.30; lit_prob = 0.30; }
	else if (style < 4.5) { bay = 1.4; wy0 = 0.72; wy1 = 0.92; win_cov = 0.16; lit_prob = 0.16; }
	else if (style < 5.5) { bay = 2.2; wy0 = 0.26; wy1 = 0.80; win_cov = 0.52; lit_prob = 0.26; }
	else if (style < 6.5) { bay = 3.4; wy0 = 0.12; wy1 = 0.90; win_cov = 0.66; lit_prob = 0.28; }
	else                  { bay = 4.5; wy0 = 0.08; wy1 = 0.92; win_cov = 0.78; lit_prob = 0.24; }

	// ---------- window grid
	float vv = max(v - gh, 0.0);
	vec2 g = vec2(u / bay, vv / fh);
	vec2 id = floor(g);
	vec2 f = fract(g);
	float detail = 1.0 - smoothstep(140.0, 420.0, vdist);

	// aperture mask (frame border = 1 - win)
	float wx = smoothstep(0.10, 0.13, f.x) * (1.0 - smoothstep(0.87, 0.90, f.x));
	if (style > 4.5 && style < 5.5) wx = 1.0;
	float wy = smoothstep(wy0 - 0.025, wy0 + 0.025, f.y) * (1.0 - smoothstep(wy1 - 0.025, wy1 + 0.025, f.y));
	float win = wx * wy;
	if (style > 5.5 && style < 6.5) win *= step(0.5, fract(id.y * 0.5 + sd));
	float frame = 0.0;  // set after jdist below (thin cell borders only)

	// per-cell type: 0 glass, 1 curtain, 2 ac unit, 3 plant, 4 open dark
	float hs = hash21(id + sd * 31.7);
	float ctype = 0.0;
	if (hs > 0.86) ctype = 1.0;
	else if (hs > 0.80 && style > 1.5 && style < 3.5) ctype = 2.0;
	else if (hs > 0.76 && style > 1.5 && style < 3.5) ctype = 3.0;
	else if (hs < 0.05) ctype = 4.0;

	// ---------- wall base material per style
	float grain = fbm(vec2(u, v) * 0.7 + sd);
	vec3 wall = vtint * (0.30 + 0.30 * grain);
	float wall_rough = 0.82;
	float wall_metal = 0.0;
	if (style > 2.5 && style < 3.5) {
		vec2 bp = vec2(u / 0.55, v / 0.22);
		bp.x += floor(mod(bp.y, 2.0)) * 0.5;
		vec2 bf = fract(bp);
		float mortar = smoothstep(0.06, 0.10, bf.x) * smoothstep(0.06, 0.10, bf.y)
				* smoothstep(0.06, 0.10, 1.0 - bf.x) * smoothstep(0.06, 0.10, 1.0 - bf.y);
		wall = vtint * (0.5 + 0.55 * hash21(floor(bp))) * mix(0.35, 1.0, mortar);
		wall_rough = 0.9;
	}
	if (style > 3.5 && style < 4.5) {
		float rib = 0.5 + 0.5 * sin(u * 4.5);
		wall = vtint * (0.4 + 0.35 * rib) * (0.7 + 0.5 * grain);
		wall_rough = 0.5; wall_metal = 0.6;
	}
	// street grime + rain streaks + cracks + posters
	wall *= 1.0 - 0.45 * (1.0 - smoothstep(0.0, 14.0, v));
	// panel joint albedo lines + sill shadow under apertures + downpipes
	vec2 gj = vec2(fract(u / bay), fract(vv / fh));
	float jdist = min(min(gj.x, 1.0 - gj.x) * bay, min(gj.y, 1.0 - gj.y) * fh);
	float jline = smoothstep(0.12, 0.0, jdist);
	wall *= 1.0 - jline * 0.75 * detail;
	frame = (1.0 - smoothstep(0.04, 0.11, jdist)) * step(0.02, vv);  // mullion/transom caps
	// per-panel tone variation + fine speckle so 1-2 m reads as material
	wall *= 0.86 + 0.28 * hash21(floor(g) + sd * 3.3);
	wall *= 0.88 + 0.24 * vnoise(vec2(u, v) * 7.0 + sd);
	wall *= 1.0 - (1.0 - smoothstep(0.0, 0.35, (vv / fh) - wy1 + 0.0)) * 0.0;
	float sill = (1.0 - smoothstep(0.0, 0.18, abs((vv / fh) - wy0 + 0.06))) * wx;
	wall *= 1.0 - sill * 0.4;
	float pipe = step(0.86, hash21(vec2(floor(u / bay), sd * 2.2))) * (1.0 - smoothstep(0.05, 0.10, abs(fract(u / bay) - 0.08)));
	wall *= 1.0 - pipe * 0.45;
	float streak = smoothstep(0.72, 0.95, hash21(vec2(floor(u / bay), sd))) *
			smoothstep(2.0, 26.0, v) * (0.15 + 0.25 * (1.0 - smoothstep(0.0, 3.0, fract(vv / fh))));
	wall *= 1.0 - streak;
	wall *= 1.0 - 0.35 * smoothstep(0.86, 0.97, ridged(vec2(u, v) * 0.22 + sd * 3.0));
	if (v < 3.5) {
		vec2 pid = vec2(floor(u / 1.3), floor(v / 1.7));
		float ph = hash21(pid + sd * 5.1);
		if (ph > 0.78) {
			vec2 pf = fract(vec2(u / 1.3, v / 1.7));
			float pm = smoothstep(0.06, 0.12, pf.x) * smoothstep(0.06, 0.12, pf.y)
					* smoothstep(0.06, 0.12, 1.0 - pf.x) * smoothstep(0.06, 0.12, 1.0 - pf.y);
			vec3 pcol = mix(vec3(0.5, 0.2, 0.15), vec3(0.15, 0.3, 0.45), step(0.5, hash21(pid * 3.3)));
			pcol = mix(pcol, vec3(0.6, 0.55, 0.2), step(0.8, hash21(pid * 7.7)));
			wall = mix(wall, pcol * (0.6 + 0.5 * vnoise(pf * 6.0)), pm * 0.85);
			wall_rough = mix(wall_rough, 0.95, pm);
		}
	}

	// ---------- glass / interior per cell
	float lit = step(1.0 - lit_prob, hs);
	if (style < 0.5 || (style > 5.5 && style < 6.5))
		lit = step(1.0 - lit_prob, hash21(vec2(id.y, sd * 3.1)));
	vec3 warm = vec3(1.0, 0.70, 0.38);
	vec3 cool = vec3(0.55, 0.78, 1.0);
	vec3 neon = mix(vec3(1.0, 0.22, 0.6), vec3(0.15, 0.95, 0.85), step(0.5, hash11(hs * 91.7)));
	vec3 litcol = mix(warm, cool, step(0.62, hs));
	litcol = mix(litcol, neon, step(0.93, hs));
	float bright = 0.55 + 1.15 * hash21(id * 5.11 + sd);

	// interior depth: view-parallax shifted silhouette layers
	float px = VIEW.x;
	float sil_u = f.x + px * 0.12;
	float furn = step(f.y, wy0 + 0.26 * hash21(id * 2.3 + sd)) * 0.75
			+ step(0.82, hash21(id * 4.9 + sd)) * (1.0 - smoothstep(0.15, 0.42, sil_u)) * step(wy0 + 0.06, f.y) * 0.6;
	furn = clamp(furn, 0.0, 0.92);
	float ceil_band = smoothstep(wy1 - 0.10, wy1, f.y - VIEW.y * 0.04) * 0.5;
	float blinds = 0.80 + 0.20 * step(0.45, fract(f.y * 11.0 + hash21(id * 1.7 + sd) * 7.0));
	float distc = length((f - vec2(0.5, (wy0 + wy1) * 0.5)) * vec2(1.0, 1.5));
	float fall = 0.7 + 0.5 * (1.0 - smoothstep(0.0, 0.55, distc));
	// jamb occlusion (side walls of the recess catch less light)
	float side = step(0.0, px);
	float occ = mix(smoothstep(0.0, 0.20, f.x), 1.0 - smoothstep(0.80, 1.0, f.x), side);
	occ = 0.45 + 0.55 * occ;
	// recess edge AO inside aperture
	vec2 dinv = min(f - vec2(0.10, wy0), vec2(0.90, wy1) - f);
	float recess = smoothstep(0.0, 0.09, min(dinv.x, dinv.y));
	float topshade = 1.0 - 0.4 * smoothstep(wy1 - 0.3, wy1, f.y);

	vec3 emis_win = lit * litcol * bright * blinds * (1.0 - furn) * (1.0 - ceil_band) *
			fall * occ * (0.25 + 0.75 * recess) * topshade * 0.22;
	// a few fully-bright showcase windows keep the sparkle
	emis_win *= 1.0 + 3.5 * step(0.93, hash21(id * 9.7 + sd));
	// curtain type: soft diffuse glow instead of clear interior
	if (ctype > 0.5 && ctype < 1.5) {
		emis_win = lit * litcol * 0.5 * (0.7 + 0.3 * vnoise(f * 8.0 + id));
	}

	// glass surface props: grime, streaks, roughness separation
	float ggrime = 0.25 * smoothstep(0.5, 0.9, fbm(vec2(u * 0.9, v * 0.35) + sd * 2.0))
			+ 0.35 * smoothstep(0.75, 0.95, hash21(vec2(id.x, sd))) * (1.0 - smoothstep(wy0, wy1, f.y));
	float glass_rough = 0.05 + ggrime * 0.35;
	vec3 glass_alb = vec3(0.012, 0.020, 0.034);

	// ---------- compose zones
	vec3 alb = wall;
	float rough = wall_rough;
	float metal = wall_metal;
	vec3 emis = vec3(0.0);

	// spandrel band (floor slab edge between windows): painted metal panel
	float spandrel = (1.0 - wy) * step(0.02, vv) * wx;
	alb = mix(alb, vtint * 0.35 * (0.8 + 0.4 * grain) * (1.0 - jline * 0.5) * (0.92 + 0.16 * vnoise(vec2(u, v) * 7.0 + sd)), spandrel);
	rough = mix(rough, 0.55, spandrel);
	metal = mix(metal, 0.45, spandrel);

	// glass zone
	alb = mix(alb, glass_alb, win);
	rough = mix(rough, glass_rough, win);
	metal = mix(metal, 0.0, win);
	emis += win * emis_win * detail;

	// ctype overlays inside aperture
	float acmask = win * (ctype > 1.5 && ctype < 2.5 ? (1.0 - smoothstep(wy0 + 0.30, wy0 + 0.36, f.y)) : 0.0);
	alb = mix(alb, vec3(0.28, 0.29, 0.31), acmask);
	rough = mix(rough, 0.4, acmask);
	metal = mix(metal, 0.8, acmask);
	emis *= 1.0 - acmask;
	float plantmask = win * (ctype > 2.5 && ctype < 3.5 ? (1.0 - smoothstep(wy0 + 0.18, wy0 + 0.30, f.y)) : 0.0);
	alb = mix(alb, vec3(0.05, 0.12, 0.04) * (0.7 + 0.6 * vnoise(f * 20.0)), plantmask);
	rough = mix(rough, 0.85, plantmask);
	emis *= 1.0 - plantmask * 0.7;
	float openmask = win * (ctype > 3.5 ? 1.0 : 0.0);
	alb = mix(alb, vec3(0.01), openmask);
	rough = mix(rough, 0.9, openmask);
	emis *= 1.0 - openmask;
	// curtain diffuse albedo when unlit
	float curmask = win * (ctype > 0.5 && ctype < 1.5 ? 1.0 : 0.0) * (1.0 - lit);
	alb = mix(alb, vec3(0.30, 0.26, 0.22) * (0.7 + 0.4 * vnoise(f * 6.0 + id)), curmask);
	rough = mix(rough, 0.9, curmask);

	// frame zone: dark metal mullions
	alb = mix(alb, vec3(0.030, 0.032, 0.036), frame);
	rough = mix(rough, 0.35, frame);
	metal = mix(metal, 0.9, frame);

	// light landing: lit windows wash their own wall margins + sill below
	vec2 doutv = max(vec2(0.10, wy0) - f, f - vec2(0.90, wy1));
	float halo = exp(-max(max(doutv.x, doutv.y), 0.0) * 9.0) * (1.0 - win);
	emis += halo * lit * litcol * 0.14 * detail;
	float sill_spill = (1.0 - smoothstep(0.0, 0.35, (wy0 - f.y) * fh)) * step(f.y, wy0) * wx;
	emis += sill_spill * lit * litcol * 0.10 * detail;

	// ---------- distance blend (sparkle average)
	vec2 cg = floor(vec2(u, v * 0.5) / 5.0);
	float sp = step(0.87, hash21(cg + sd * 1.7));
	vec3 emis_a = (0.015 + sp * 1.5) * mix(warm, cool, step(0.6, hash21(cg * 3.3 + sd))) * win_cov;
	emis = mix(emis_a, emis, detail);
	alb = mix(mix(alb, glass_alb, win_cov * 0.7), alb, detail);
	// street-level light landing: storefront/sign spill washing wall piers
	float spill_h = exp(-max(v, 0.0) * 0.22);
	vec3 spill_col = mix(vec3(1.0, 0.45, 0.6), vec3(0.35, 0.85, 1.0), step(0.5, hash21(vec2(floor(u / 7.0), 2.2 + sd))));
	spill_col = mix(spill_col, vec3(1.0, 0.72, 0.3), step(0.8, hash21(vec2(floor(u / 7.0), 6.6 + sd))));
	emis += spill_col * spill_h * 0.12 * (0.6 + 0.8 * hash21(vec2(floor(u / 7.0), sd))) * detail;
	// faint sky/ambient lift so volumes read against the night sky
	emis += vec3(0.022, 0.024, 0.040) * (0.5 + 0.5 * grain) * (0.35 + 0.65 * smoothstep(0.0, 60.0, v));
	// street bounce: warm light trapped in the canyon washes lower walls
	emis += vec3(0.055, 0.040, 0.030) * exp(-max(v, 0.0) * 0.055) * (0.6 + 0.6 * grain);

	// ---------- ground floor: storefront, doors, shutters, glyph sign band
	if (v < gh) {
		float bayg = 3.0;
		vec2 gg = vec2(u / bayg, v / gh);
		vec2 gid = floor(gg);
		vec2 gf = fract(gg);
		float mullg = smoothstep(0.05, 0.02, min(gf.x, 1.0 - gf.x));
		float shop_lit = step(0.42, hash21(gid + sd * 7.7));
		vec3 shop_col = mix(warm, neon, step(0.6, hash21(gid * 3.3 + sd)));
		float door = smoothstep(0.32, 0.36, gf.x) * (1.0 - smoothstep(0.64, 0.68, gf.x)) * (1.0 - smoothstep(0.72, 0.78, gf.y));
		// recessed entrance: darker + warm interior gradient
		vec3 shop_emis = shop_lit * shop_col * (0.28 + 0.26 * hash21(gid * 9.1 + sd)) *
				(1.0 - door * 0.55) * (0.6 + 0.4 * (1.0 - gf.y));
		float closed = step(hash21(gid + sd * 13.1), 0.3);
		float ribs = 0.5 + 0.5 * sin(v * 40.0);
		alb = mix(alb, vec3(0.02, 0.025, 0.035), (1.0 - mullg));
		alb = mix(alb, vtint * 0.35 * (0.6 + 0.4 * ribs), closed);
		emis = mix(emis, shop_emis * (1.0 - closed), 1.0 - closed);
		rough = mix(rough, mix(0.10, 0.5, closed), 1.0 - mullg);
		metal = mix(metal, mix(0.1, 0.7, closed), 1.0 - mullg);
		alb = mix(alb, vec3(0.02), mullg);
		// awning shadow band
		emis *= 1.0 - 0.5 * (1.0 - smoothstep(gh - 0.5, gh - 0.15, v)) * step(gh - 1.5, v);
		// sign band with procedural glyphs on backing panel
		float band = smoothstep(gh - 1.25, gh - 1.15, v) * (1.0 - smoothstep(gh - 0.25, gh - 0.15, v));
		if (band > 0.0) {
			vec2 sp2 = vec2(u / 1.15, (v - (gh - 1.2)) / 1.0);
			vec2 sid2 = vec2(floor(sp2.x), 0.0);
			vec2 sf = fract(sp2);
			float gd = glyph(sf, hash21(sid2 + sd * 5.5) * 50.0);
			float gm = 1.0 - smoothstep(0.06, 0.11, gd);
			vec2 grp = vec2(floor(sp2.x / 7.0), 0.0);
			vec3 sign_col = mix(vec3(1.0, 0.25, 0.55), vec3(0.2, 0.95, 1.0), step(0.5, hash21(grp + sd * 2.2)));
			sign_col = mix(sign_col, vec3(1.0, 0.75, 0.2), step(0.8, hash21(grp * 7.7 + sd)));
			float flick = 0.75 + 0.25 * step(0.97, hash21(grp + floor(TIME * 3.0) * 0.37));
			float dead_seg = step(0.93, hash21(vec2(floor(sf.x * 3.0) + sid2.x, sd)));
			emis = mix(emis, sign_col * (0.3 + 1.6 * gm) * flick * (1.0 - dead_seg * 0.8), band);
			alb = mix(alb, vec3(0.03), band);
			rough = mix(rough, 0.4, band);
		}
	}

	// ---------- bump normal on wall zones
	if (detail > 0.05) {
		vec2 bw = fwidth(UV);
		float h0 = wall_height(UV, sd, style, bay, fh);
		float hx = wall_height(UV + vec2(bw.x, 0.0), sd, style, bay, fh) - h0;
		float hy = wall_height(UV + vec2(0.0, bw.y), sd, style, bay, fh) - h0;
		float wmask = (1.0 - win) * (1.0 - frame * 0.5);
		NORMAL = normalize(NORMAL - (TANGENT * (hx / max(bw.x, 1e-6)) + BINORMAL * (hy / max(bw.y, 1e-6))) * 0.15 * wmask);
	}

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	EMISSION = emis;

	// aerial perspective + height fog
	float hfac = 1.0 + 1.8 * exp(-max(vhy, 0.0) * 0.025);
	float hz = 1.0 - exp(-vdist * haze_den * hfac - vdist * vdist * 3.5e-8);
	ALBEDO = mix(ALBEDO, haze_col.rgb, hz);
	EMISSION = mix(EMISSION, haze_col.rgb * haze_emis * (0.4 + 0.8 * exp(-max(vhy, 0.0) * 0.02)), hz);
}
