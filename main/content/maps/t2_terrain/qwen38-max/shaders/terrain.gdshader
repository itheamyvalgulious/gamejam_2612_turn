shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// ------------------------------------------------------------------ helpers
varying vec3 v_world;
varying vec3 v_nworld;

// Exact integer hash: no float precision loss at large world coordinates
// (the old fract-dot hash degenerated into axis-aligned stripes at high octaves).
uint _ih(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}
float hash13(vec3 p) {
	ivec3 i = ivec3(floor(p + 0.5));
	uint u = _ih(uint(i.x) + _ih(uint(i.y) + _ih(uint(i.z))));
	return float(u) * (1.0 / 4294967295.0);
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0,0,0));
	float n100 = hash13(i + vec3(1,0,0));
	float n010 = hash13(i + vec3(0,1,0));
	float n110 = hash13(i + vec3(1,1,0));
	float n001 = hash13(i + vec3(0,0,1));
	float n101 = hash13(i + vec3(1,0,1));
	float n011 = hash13(i + vec3(0,1,1));
	float n111 = hash13(i + vec3(1,1,1));
	return mix(
		mix(mix(n000,n100,f.x), mix(n010,n110,f.x), f.y),
		mix(mix(n001,n101,f.x), mix(n011,n111,f.x), f.y), f.z);
}
float fbm(vec3 p, int oct) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= oct) break;
		s += a * vnoise(p);
		p = p * 2.03 + vec3(11.7);
		a *= 0.5;
	}
	return s;
}
float ridge(vec3 p, int oct) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 5; i++) {
		if (i >= oct) break;
		float n = 1.0 - abs(vnoise(p) * 2.0 - 1.0);
		s += a * n * n;
		p = p * 2.11 + vec3(5.3);
		a *= 0.5;
	}
	return s;
}
vec3 gdir(vec3 i) {
	vec3 h = vec3(hash13(i + vec3(7, 0, 0)), hash13(i + vec3(0, 13, 0)), hash13(i + vec3(0, 0, 29))) * 2.0 - 1.0;
	return normalize(h + vec3(1e-5));
}
float gnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = dot(gdir(i), f);
	float n100 = dot(gdir(i + vec3(1, 0, 0)), f - vec3(1, 0, 0));
	float n010 = dot(gdir(i + vec3(0, 1, 0)), f - vec3(0, 1, 0));
	float n110 = dot(gdir(i + vec3(1, 1, 0)), f - vec3(1, 1, 0));
	float n001 = dot(gdir(i + vec3(0, 0, 1)), f - vec3(0, 0, 1));
	float n101 = dot(gdir(i + vec3(1, 0, 1)), f - vec3(1, 0, 1));
	float n011 = dot(gdir(i + vec3(0, 1, 1)), f - vec3(0, 1, 1));
	float n111 = dot(gdir(i + vec3(1, 1, 1)), f - vec3(1, 1, 1));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

// ------------------------------------------------------------------ vertex
void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nworld = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

float _detail_h(vec3 W) {
	float h = fbm(W * 0.35, 4) * 1.0;
	h += ridge(W * 0.9, 3) * 0.35;
	h += fbm(W * 2.2, 2) * 0.12;
	return h;
}

float _snow_h(vec3 W) {
	vec3 wdir = vec3(0.86, 0.0, 0.5);
	float along = dot(W, wdir);
	float across = dot(W, vec3(-wdir.z, 0.0, wdir.x));
	float g = gnoise(vec3(across * 0.22, along * 0.03, W.y * 0.15));
	float h = pow(1.0 - abs(g), 1.6);
	h += gnoise(W * 0.12) * 0.5;
	h += gnoise(W * 3.0) * 0.10;
	return h;
}

// Scale-invariant fractal height: gradient noise (no lattice streaks), octaves
// continue only down to the pixel footprint e, so close-ups stay crisp, never alias.
float _micro_h(vec3 W, float e) {
	float h = 0.0;
	float a = 1.0;
	float f = 0.30;
	for (int i = 0; i < 9; i++) {
		// stop above pixel footprint (x4 margin) and cap frequency: kills moiré
		if (1.0 / f < e * 4.0 || f > 10.0) break;
		h += a * gnoise(W * f + vec3(float(i) * 17.7));
		a *= 0.52;
		f *= (i % 2 == 0) ? 2.13 : 1.79;   // de-tuned octave ratios break periodicity
	}
	return h;
}

// ---- Voronoi joint blocks (5-20 cm): flat facets per cell + dark seam grooves
float _block_h(vec3 W, float freq, out float edge, out float tint) {
	vec3 p = W * freq + vec3(gnoise(W * freq * 0.16)) * (freq * 0.6)
		+ vec3(0.0, gnoise(W * freq * 0.11 + 5.0), 0.0) * (freq * 0.4);
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float f1 = 9.0;
	float f2 = 9.0;
	vec3 best = ip;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 cid = ip + g;
				vec3 o = vec3(hash13(cid), hash13(cid + vec3(31, 0, 0)), hash13(cid + vec3(0, 47, 0)));
				vec3 r = g + o - fp;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					best = cid;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	edge = sqrt(f2) - sqrt(f1);
	vec3 cr = vec3(hash13(best + vec3(3, 5, 7)), hash13(best + vec3(11, 0, 2)), hash13(best + vec3(0, 9, 13)));
	float tilt = dot(fp - (cr - 0.5), (cr - 0.5) * 1.6);
	float groove = smoothstep(0.0, 0.15, edge);
	tint = cr.y;
	return (cr.x - 0.5) * 0.6 + tilt + groove * 0.35;
}

// ---- hierarchical blocks: two voronoi scales blended by a subdivision mask,
// seams with variable width / open-closed state / stress placement / debris fill
float _blocks_h(vec3 W, out float seam, out float tint) {
	float e1;
	float t1;
	float h1 = _block_h(W, 1.1, e1, t1);
	float e2;
	float t2;
	float h2 = _block_h(W, 2.6, e2, t2);
	float sub = smoothstep(0.42, 0.68, fbm(W * 0.5 + 7.0, 3));
	float h = mix(h1, h2 * 0.6, sub);
	float edge = mix(e1, e2, sub);
	float open = smoothstep(0.30, 0.62, fbm(W * 0.35 + 31.0, 3));
	float stress = 0.35 + 0.65 * smoothstep(0.25, 0.70, abs(gnoise(W * 0.3)) + 0.3 * fbm(W * 0.4, 2));
	float intact = smoothstep(0.55, 0.78, fbm(W * 0.25 + 3.0, 2));
	float seamv = open * stress * (1.0 - intact * 0.85);
	float sw = 0.02 + 0.09 * fbm(W * 0.8 + 11.0, 2);
	seam = (1.0 - smoothstep(0.0, sw, edge)) * seamv;
	tint = mix(t1, t2, sub);
	return h * (0.3 + 0.7 * seamv);
}

// ---- large form (2-8 m): undulation + bedding terraces; drives hierarchy masks
float _large_h(vec3 W) {
	vec3 dip = normalize(vec3(0.35 * sin(W.x * 0.0012 + 1.3), 1.0, 0.30 * cos(W.z * 0.0011)));
	float sd = dot(W, dip);
	float bed = sin(sd * 0.30) * 0.5 + sin(sd * 0.8 + 2.0) * 0.25;
	return gnoise(W * 0.15) + 0.4 * gnoise(W * 0.4) + bed * 0.7;
}

// ---- bedding bands + decimetre hollows (0.5-2 m)
float _bed_h(vec3 W) {
	vec3 dip = normalize(vec3(0.35 * sin(W.x * 0.0012 + 1.3), 1.0, 0.30 * cos(W.z * 0.0011)));
	float sd = dot(W, dip);
	float bed = sin(sd * 0.35) * 0.5 + sin(sd * 0.9 + 2.0) * 0.25;
	return bed * 0.25 + gnoise(W * 0.5) * 0.35 + gnoise(W * 1.4) * 0.12;
}

// ------------------------------------------------------------------ fragment
void fragment() {
	vec3 W = v_world;
	vec3 N = normalize(v_nworld);
	float camdE = length(W - (INV_VIEW_MATRIX * vec4(0, 0, 0, 1)).xyz);
	vec4 sp = COLOR;              // grass, rock, snow, sand
	float grass = sp.r, rock = sp.g, snow = sp.b, sand = sp.a;

	float up = clamp(N.y, 0.0, 1.0);
	float lat = clamp(W.z / 2500.0, 0.0, 1.0);      // 0 north .. 1 south

	// ---- shader-side reinforcement of rock on steep faces & snow on highs
	float slope_rock = smoothstep(0.45, 0.80, 1.0 - up);
	rock = clamp(rock + slope_rock * (grass * 0.9 + sand * 0.7), 0.0, 1.0);
	grass *= 1.0 - slope_rock * 0.9;
	sand *= 1.0 - slope_rock * 0.7;
	float tot = grass + rock + snow + sand + 1e-5;
	grass /= tot; rock /= tot; snow /= tot; sand /= tot;
	// snow caps on high peaks
	float cap = smoothstep(200.0, 260.0, W.y) * smoothstep(0.3, 0.6, up);
	snow += cap * rock * 0.85;
	rock *= 1.0 - cap * 0.85;
	// cliffs shed snow: steep faces are bare rock
	float steep = smoothstep(0.45, 0.75, 1.0 - up);
	rock = max(rock, steep * 0.9);
	snow *= 1.0 - steep * 0.85;
	grass *= 1.0 - steep * 0.9;
	tot = grass + rock + snow + sand + 1e-5;
	grass /= tot; rock /= tot; snow /= tot; sand /= tot;
	// shared sub-metre grain for albedo modulation
	float micro = _micro_h(W, 0.03) * 0.5 + 0.5;

	// ================= GRASS / jungle floor =================
	float g_n = fbm(W * 0.06, 4);
	float g_fine = gnoise(W * 0.5) * 0.5 + 0.5;
	vec3 jungle_a = vec3(0.075, 0.185, 0.05);
	vec3 jungle_b = vec3(0.12, 0.28, 0.085);
	vec3 tundra_a = vec3(0.30, 0.34, 0.24);
	vec3 tundra_b = vec3(0.42, 0.44, 0.33);
	vec3 meadow_a = vec3(0.13, 0.26, 0.07);
	vec3 meadow_b = vec3(0.22, 0.36, 0.11);
	float jungle_mix = smoothstep(0.45, 0.75, lat);
	vec3 gA = mix(meadow_a, jungle_a, jungle_mix);
	vec3 gB = mix(meadow_b, jungle_b, jungle_mix);
	gA = mix(gA, tundra_a, smoothstep(0.35, 0.15, lat));
	gB = mix(gB, tundra_b, smoothstep(0.35, 0.15, lat));
	vec3 grass_col = mix(gA, gB, g_n);
	grass_col *= 0.8 + 0.4 * g_fine;
	grass_col *= 0.88 + 0.24 * micro;
	// leaf-litter / dead patches in jungle
	grass_col = mix(grass_col, vec3(0.16, 0.11, 0.05), jungle_mix * smoothstep(0.55, 0.8, fbm(W * 0.15 + 7.0, 3)) * 0.6);
	float grass_rough = 0.92;

	// ================= ROCK =================
	// bedding planes with spatially varying dip direction
	vec3 dip = normalize(vec3(0.35 * sin(W.x * 0.0012 + 1.3), 1.0, 0.30 * cos(W.z * 0.0011)));
	float sd = dot(W, dip);
	float r_strata = sin(sd * 0.22 + fbm(W * 0.05, 3) * 8.0);
	float r_strata2 = sin(sd * 1.15 + fbm(W * 0.11 + 5.0, 2) * 5.0);
	vec3 rock_a = vec3(0.16, 0.135, 0.105);
	vec3 rock_b = vec3(0.34, 0.30, 0.245);
	vec3 rock_c = vec3(0.26, 0.20, 0.155);
	vec3 rock_col = mix(rock_a, rock_b, 0.5 + 0.15 * r_strata);
	rock_col = mix(rock_col, rock_c, 0.15 + 0.10 * r_strata2);
	// large-scale lithology patches (warm granite vs sandstone)
	float lith = fbm(W * 0.012 + 21.0, 3);
	rock_col = mix(rock_col, rock_col * vec3(1.06, 0.98, 0.88), smoothstep(0.60, 0.85, lith) * 0.3);
	float r_n = fbm(W * 0.12, 4);
	rock_col *= 0.85 + 0.30 * r_n;
	rock_col *= 0.94 + 0.12 * micro;
	rock_col *= 0.92 + 0.16 * (gnoise(W * 1.3) * 0.5 + 0.5);
	// dark crevices / moisture (narrow, subtle)
	rock_col = mix(rock_col, rock_col * 0.55, smoothstep(0.55, 0.35, r_n) * 0.35);
	// vertical seepage stains on cliff faces (neutral dark, not blue)
	float streak = fbm(vec3(W.x * 0.18, W.y * 0.015, W.z * 0.18), 3);
	float face = 1.0 - up;
	rock_col = mix(rock_col, rock_col * vec3(0.50, 0.50, 0.52), smoothstep(0.50, 0.78, streak) * face * 0.6);
	// talus / scree aprons at cliff bases: granular warm grey
	float scree_band = smoothstep(0.55, 0.35, up) * smoothstep(0.12, 0.28, up);
	float gran = gnoise(W * 1.1) * 0.5 + 0.5;
	vec3 scree_col = mix(vec3(0.26, 0.24, 0.21), vec3(0.40, 0.37, 0.32), gran);
	rock_col = mix(rock_col, scree_col, scree_band * 0.5);
	// ---- large-scale hierarchy: hue patches, wet recesses, weathering streaks
	float Lh = _large_h(W);
	float Lmask = smoothstep(-0.35, 0.45, Lh);
	float hp1 = fbm(W * 0.22 + 5.0, 3);
	float hp2 = fbm(W * 0.17 + 19.0, 2);
	rock_col = mix(rock_col, rock_col * vec3(1.12, 1.02, 0.86), smoothstep(0.45, 0.75, hp1) * 0.5);
	rock_col = mix(rock_col, rock_col * vec3(0.90, 0.93, 1.00), smoothstep(0.55, 0.80, hp2) * 0.30);
	rock_col = mix(rock_col, rock_col * vec3(1.10, 0.80, 0.58), smoothstep(0.60, 0.85, hp1 * hp2 * 1.7) * 0.45);
	rock_col *= 1.0 - (1.0 - Lmask) * 0.35;                       // wet/dark in big recesses
	float streakA = gnoise(vec3(W.x * 0.5, W.y * 0.06, W.z * 0.5));
	rock_col *= 0.88 + 0.24 * streakA;                            // vertical weathering
	// block seams: variable width, open/closed, stress-placed, filled with debris/dust
	float seamR;
	float tintR;
	_blocks_h(W, seamR, tintR);
	rock_col *= 0.94 + 0.12 * tintR;
	vec3 debris = mix(vec3(0.15, 0.12, 0.09), vec3(0.32, 0.28, 0.22), gnoise(W * 30.0) * 0.5 + 0.5);
	rock_col = mix(rock_col, debris, seamR * 0.75);
	rock_col *= 1.0 - 0.30 * seamR * seamR;
	float jmask = smoothstep(0.35, 0.65, fbm(W * 0.6 + 2.0, 3));
	float bfade = 1.0 / (1.0 + camdE * 0.02);
	// exposure / height / aspect colour variation across the wall
	float expo = smoothstep(0.45, 0.85, up);
	rock_col = mix(rock_col, rock_col * vec3(1.10, 1.05, 0.96), expo * 0.5);
	float basedirt = smoothstep(45.0, 15.0, W.y);
	rock_col = mix(rock_col, rock_col * vec3(0.80, 0.74, 0.62), basedirt * 0.5);
	float eastshade = smoothstep(0.15, 0.6, N.x);
	float lich = smoothstep(0.45, 0.75, fbm(W * 0.35 + 8.0, 3));
	rock_col = mix(rock_col, rock_col * vec3(0.62, 0.72, 0.50), eastshade * lich * 0.55);
	// lichen / moss on lower, wetter rock
	float moss = smoothstep(0.5, 0.8, fbm(W * 0.2 + 3.0, 3)) * smoothstep(200.0, 90.0, W.y) * up;
	rock_col = mix(rock_col, vec3(0.12, 0.20, 0.09), moss * 0.5);
	// macro mottling so big faces are never uniform (low contrast)
	rock_col *= 0.90 + 0.20 * fbm(W * 0.03 + 41.0, 3);
	// slope AO: steep faces get less sky light
	rock_col *= 0.55 + 0.45 * up;
	// snow dusting only on high, upward faces
	float dust = smoothstep(210.0, 330.0, W.y) * smoothstep(0.6, 0.9, up) * smoothstep(0.35, 0.65, fbm(W * 0.3, 3));
	rock_col = mix(rock_col, vec3(0.9), dust * 0.6);
	float rock_rough = 0.85;

	// ================= SNOW =================
	float s_n = fbm(W * 0.08, 3);
	vec3 snow_col = mix(vec3(0.86, 0.90, 0.97), vec3(0.97, 0.98, 1.0), s_n);
	// depth-varying snow layers (fresh / crust / blue firn)
	float layer = fbm(W * 0.02 + 13.7, 2);
	snow_col = mix(snow_col, snow_col * vec3(0.90, 0.94, 1.04), smoothstep(0.35, 0.7, layer));
	snow_col = mix(snow_col, vec3(0.78, 0.82, 0.90), smoothstep(0.62, 0.85, fbm(W * 0.05 + 4.2, 3)) * 0.5);
	// directional sastrugi: wind-carved grooves with leeward lips
	float sas = _snow_h(W);
	snow_col *= 0.80 + 0.35 * sas;
	// snow-grain scale high-frequency detail
	snow_col *= 0.96 + 0.08 * (gnoise(W * 4.0) * 0.5 + 0.5);
	snow_col *= 0.97 + 0.06 * micro;
	// blue shadow tint in hollows (soft, desaturated)
	snow_col = mix(snow_col * vec3(0.80, 0.86, 0.97), snow_col, smoothstep(0.05, 0.75, up));
	// exposed rock ribs poking through the snowpack
	float rib = ridge(W * 0.045 + 9.1, 3);
	float rock_out = smoothstep(0.55, 0.78, rib) * smoothstep(0.35, 0.75, up) * smoothstep(0.2, 0.5, fbm(W * 0.02, 2));
	snow_col = mix(snow_col, rock_col, clamp(rock_out, 0.0, 1.0) * 0.85);
	// old/dirty snow near rock
	snow_col = mix(snow_col, vec3(0.62, 0.65, 0.70), smoothstep(0.6, 0.9, rock) * 0.4);
	float snow_rough = 0.40 + 0.18 * (gnoise(W * 4.0) * 0.5 + 0.5);

	// ================= SAND =================
	float sa_n = fbm(W * 0.3, 3);
	vec3 sand_col = mix(vec3(0.55, 0.47, 0.33), vec3(0.72, 0.63, 0.46), sa_n);
	// ripples
	float rip = sin((W.x + W.z) * 1.7 + fbm(W * 0.2, 2) * 5.0);
	sand_col *= 0.92 + 0.08 * rip;
	sand_col *= 0.92 + 0.16 * micro;
	float sand_rough = 0.8;

	// ================= blend =================
	vec3 albedo = grass_col * grass + rock_col * rock + snow_col * snow + sand_col * sand;
	float rough = grass_rough * grass + rock_rough * rock + snow_rough * snow + sand_rough * sand;

	// subsurface-scatter warm glow softening the light/shadow terminator on snow
	vec3 camW = (INV_VIEW_MATRIX * vec4(0, 0, 0, 1)).xyz;
	vec3 Vv = normalize(camW - W);
	vec3 Ls = normalize(vec3(-0.696, 0.530, 0.370));   // toward sun (matches main.gd)
	float back = clamp(dot(Vv, -Ls) * 0.5 + 0.5, 0.0, 1.0);
	float sss = pow(back, 4.0) * snow * (0.5 + 0.5 * (gnoise(W * 5.0) * 0.5 + 0.5));
	albedo += vec3(1.0, 0.72, 0.45) * sss * 0.22;

	// ============ procedural bump normal (scale-invariant + parallax) ============
	float camd = length(camW - W);
	vec3 Vd = normalize(W - camW);
	// epsilon tracks pixel footprint: crisp at any zoom, never blurry
	float e = clamp(camd * 0.0012, 0.02, 0.6);
	float fade = 1.0 / (1.0 + camd * camd * 0.0000012);
	// parallax relief: height field sampled shifted along the view ray
	vec3 Wp = W;
	float h0 = _micro_h(Wp, e);
	float hx = _micro_h(Wp + vec3(e, 0, 0), e);
	float hz = _micro_h(Wp + vec3(0, 0, e), e);
	float strength = (rock * 0.6 + grass * 0.9 + sand * 0.5 + snow * 0.25) * fade;
	vec3 grad = vec3((hx - h0) / e, 0.0, (hz - h0) / e);
	// snow sastrugi + grain on top
	float sg0 = _snow_h(W);
	float sgx = _snow_h(W + vec3(e, 0, 0));
	float sgz = _snow_h(W + vec3(0, 0, e));
	grad += vec3((sgx - sg0) / e, 0.0, (sgz - sg0) / e) * (snow * 2.0);
	// mineral grains & micro-pits (1-3 mm): faint roughness perturbation only
	float e2 = max(e * 0.25, 0.004);
	float g0 = gnoise(W * 160.0) + 0.5 * gnoise(W * 380.0);
	float gx = gnoise((W + vec3(e2, 0, 0)) * 160.0) + 0.5 * gnoise((W + vec3(e2, 0, 0)) * 380.0);
	float gz = gnoise((W + vec3(0, 0, e2)) * 160.0) + 0.5 * gnoise((W + vec3(0, 0, e2)) * 380.0);
	grad += vec3((gx - g0) / e2, 0.0, (gz - g0) / e2) * ((rock * 0.03 + sand * 0.02) * (0.3 + 0.7 * Lmask));
	// LARGE form (2-8 m): dominant shape shading + bedding terraces
	float eL = 0.25;
	float L0 = _large_h(W);
	float Lx = _large_h(W + vec3(eL, 0, 0));
	float Lz = _large_h(W + vec3(0, 0, eL));
	grad += vec3((Lx - L0) / eL, 0.0, (Lz - L0) / eL) * (rock * 1.3);
	// MID cut blocks (0.6-2 m, hierarchical): broken slabs with seam steps
	float eM = 0.06;
	float sM;
	float tM;
	float M0 = _blocks_h(W, sM, tM);
	float Mx = _blocks_h(W + vec3(eM, 0, 0), sM, tM);
	float Mz = _blocks_h(W + vec3(0, 0, eM), sM, tM);
	grad += vec3((Mx - M0) / eM, 0.0, (Mz - M0) / eM) * (rock * 0.55);
	// joint blocks (5-20 cm): DOMINANT facet layer with seam steps
	float e4 = 0.02;
	float eB;
	float tB;
	float b0 = _block_h(W, 4.5, eB, tB);
	float bxx = _block_h(W + vec3(e4, 0, 0), 4.5, eB, tB);
	float bzz = _block_h(W + vec3(0, 0, e4), 4.5, eB, tB);
	grad += vec3((bxx - b0) / e4, 0.0, (bzz - b0) / e4) * (rock * 0.14 * bfade * (0.35 + 0.65 * jmask) * (0.25 + 0.75 * Lmask) * (1.0 - seamR * 0.6));
	// mid-scale rock relief (0.3-1.2 m undulation) for shape shading
	float e3 = 0.15;
	float m0 = gnoise(W * 0.8) * 0.6 + gnoise(W * 2.2) * 0.3;
	float mx = gnoise((W + vec3(e3, 0, 0)) * 0.8) * 0.6 + gnoise((W + vec3(e3, 0, 0)) * 2.2) * 0.3;
	float mz = gnoise((W + vec3(0, 0, e3)) * 0.8) * 0.6 + gnoise((W + vec3(0, 0, e3)) * 2.2) * 0.3;
	grad += vec3((mx - m0) / e3, 0.0, (mz - m0) / e3) * (rock * 0.5);
	vec3 gT = grad - N * dot(N, grad);
	vec3 Np = normalize(N - gT * strength);
	Np = normalize(mix(Np, N, smoothstep(0.35, 0.05, up) * 0.4));
	NORMAL = normalize(mat3(VIEW_MATRIX) * Np);

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.35, snow);
	// mica glints: rare specular sparkles on rock
	float mica = step(0.996, hash13(floor(W * 260.0))) * rock;
	ALBEDO += vec3(mica) * 0.25;
	SPECULAR = clamp(SPECULAR + mica * 0.7, 0.0, 1.0);
	ROUGHNESS = clamp(ROUGHNESS - mica * 0.3, 0.05, 1.0);
}
