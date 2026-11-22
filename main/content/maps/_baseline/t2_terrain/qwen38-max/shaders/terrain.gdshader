shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// ------------------------------------------------------------------ helpers
varying vec3 v_world;
varying vec3 v_nworld;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
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
	float h = pow(ridge(vec3(across * 0.22, along * 0.03, W.y * 0.15), 3), 1.6);
	h += fbm(W * 0.12, 2) * 0.5;
	h += fbm(W * 3.0, 2) * 0.10;
	return h;
}

// ------------------------------------------------------------------ fragment
void fragment() {
	vec3 W = v_world;
	vec3 N = normalize(v_nworld);
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

	// ================= GRASS / jungle floor =================
	float g_n = fbm(W * 0.06, 4);
	float g_fine = fbm(W * 0.5, 3);
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
	// leaf-litter / dead patches in jungle
	grass_col = mix(grass_col, vec3(0.16, 0.11, 0.05), jungle_mix * smoothstep(0.55, 0.8, fbm(W * 0.15 + 7.0, 3)) * 0.6);
	float grass_rough = 0.92;

	// ================= ROCK =================
	// bedding planes with spatially varying dip direction
	vec3 dip = normalize(vec3(0.35 * sin(W.x * 0.0012 + 1.3), 1.0, 0.30 * cos(W.z * 0.0011)));
	float sd = dot(W, dip);
	float r_strata = sin(sd * 0.22 + fbm(W * 0.05, 3) * 8.0);
	float r_strata2 = sin(sd * 1.15 + fbm(W * 0.11 + 5.0, 2) * 5.0);
	vec3 rock_a = vec3(0.045, 0.044, 0.046);
	vec3 rock_b = vec3(0.17, 0.16, 0.16);
	vec3 rock_c = vec3(0.10, 0.10, 0.11);
	vec3 rock_col = mix(rock_a, rock_b, 0.5 + 0.45 * r_strata);
	rock_col = mix(rock_col, rock_c, 0.25 + 0.25 * r_strata2);
	// large-scale lithology patches (basalt vs granite)
	float lith = fbm(W * 0.012 + 21.0, 3);
	rock_col = mix(rock_col, rock_col * vec3(0.70, 0.74, 0.82), smoothstep(0.60, 0.85, lith) * 0.5);
	float r_n = fbm(W * 0.12, 4);
	rock_col *= 0.65 + 0.60 * r_n;
	// dark crevices / moisture
	rock_col = mix(rock_col, rock_col * 0.40, smoothstep(0.6, 0.3, r_n) * 0.6);
	// vertical seepage stains on cliff faces
	float streak = fbm(vec3(W.x * 0.18, W.y * 0.015, W.z * 0.18), 3);
	float face = 1.0 - up;
	rock_col = mix(rock_col, rock_col * vec3(0.35, 0.38, 0.42), smoothstep(0.50, 0.78, streak) * face * 0.8);
	// talus / scree aprons at cliff bases: granular grey
	float scree_band = smoothstep(0.55, 0.35, up) * smoothstep(0.12, 0.28, up);
	float gran = fbm(W * 1.6, 2);
	vec3 scree_col = mix(vec3(0.26, 0.24, 0.21), vec3(0.46, 0.43, 0.39), gran);
	rock_col = mix(rock_col, scree_col, scree_band * 0.5);
	// lichen / moss on lower, wetter rock
	float moss = smoothstep(0.5, 0.8, fbm(W * 0.2 + 3.0, 3)) * smoothstep(200.0, 90.0, W.y) * up;
	rock_col = mix(rock_col, vec3(0.12, 0.20, 0.09), moss * 0.5);
	// macro mottling so big faces are never uniform
	rock_col *= 0.8 + 0.5 * fbm(W * 0.03 + 41.0, 3);
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
	snow_col *= 0.95 + 0.10 * fbm(W * 6.0, 2);
	// blue shadow tint in hollows (soft, desaturated)
	snow_col = mix(snow_col * vec3(0.80, 0.86, 0.97), snow_col, smoothstep(0.05, 0.75, up));
	// exposed rock ribs poking through the snowpack
	float rib = ridge(W * 0.045 + 9.1, 3);
	float rock_out = smoothstep(0.55, 0.78, rib) * smoothstep(0.35, 0.75, up) * smoothstep(0.2, 0.5, fbm(W * 0.02, 2));
	snow_col = mix(snow_col, rock_col, clamp(rock_out, 0.0, 1.0) * 0.85);
	// old/dirty snow near rock
	snow_col = mix(snow_col, vec3(0.62, 0.65, 0.70), smoothstep(0.6, 0.9, rock) * 0.4);
	float snow_rough = 0.40 + 0.18 * fbm(W * 4.0, 2);

	// ================= SAND =================
	float sa_n = fbm(W * 0.3, 3);
	vec3 sand_col = mix(vec3(0.55, 0.47, 0.33), vec3(0.72, 0.63, 0.46), sa_n);
	// ripples
	float rip = sin((W.x + W.z) * 1.7 + fbm(W * 0.2, 2) * 5.0);
	sand_col *= 0.92 + 0.08 * rip;
	float sand_rough = 0.8;

	// ================= blend =================
	vec3 albedo = grass_col * grass + rock_col * rock + snow_col * snow + sand_col * sand;
	float rough = grass_rough * grass + rock_rough * rock + snow_rough * snow + sand_rough * sand;

	// subsurface-scatter warm glow softening the light/shadow terminator on snow
	vec3 camW = (INV_VIEW_MATRIX * vec4(0, 0, 0, 1)).xyz;
	vec3 Vv = normalize(camW - W);
	vec3 Ls = normalize(vec3(-0.696, 0.530, 0.370));   // toward sun (matches main.gd)
	float back = clamp(dot(Vv, -Ls) * 0.5 + 0.5, 0.0, 1.0);
	float sss = pow(back, 4.0) * snow * (0.5 + 0.5 * fbm(W * 5.0, 2));
	albedo += vec3(1.0, 0.72, 0.45) * sss * 0.22;

	// ================= procedural bump normal =================
	float camd = length(W - (INV_VIEW_MATRIX * vec4(0,0,0,1)).xyz);
	float fade = 1.0 / (1.0 + camd * 0.0006);
	float e = 0.6;
	float h0 = _detail_h(W);
	float hx = _detail_h(W + vec3(e,0,0));
	float hz = _detail_h(W + vec3(0,0,e));
	float sg0 = _snow_h(W);
	float sgx = _snow_h(W + vec3(e, 0, 0));
	float sgz = _snow_h(W + vec3(0, 0, e));
	float strength = (rock * 2.2 + grass * 1.0 + sand * 0.6 + snow * 0.3) * fade;
	vec3 grad = vec3((hx - h0) / e, 0.0, (hz - h0) / e);
	grad += vec3((sgx - sg0) / e, 0.0, (sgz - sg0) / e) * (snow * 3.0);
	vec3 Np = normalize(N - grad * strength + vec3(0.0, 0.0001, 0.0));
	// keep normal from inverting on steep slopes
	Np = normalize(mix(Np, N, smoothstep(0.35, 0.05, up) * 0.5));
	NORMAL = normalize(mat3(VIEW_MATRIX) * Np);

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.35, snow);
}
