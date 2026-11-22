// ============================================================================
//  hull.gdshader — exterior armour plating
//  Multi-scale panel fields, rivets, inset hatches, oxidation streaks.
//  UV is in meters: x = circumference, y = along the hull.
// ============================================================================
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 paint : source_color = vec3(0.415, 0.44, 0.475);
uniform vec3 paint_dark : source_color = vec3(0.115, 0.125, 0.145);
uniform vec3 accent : source_color = vec3(0.78, 0.30, 0.055);
uniform vec3 rust_col : source_color = vec3(0.20, 0.095, 0.045);
uniform float seed = 0.0;
uniform float grime = 0.85;
uniform float panel_scale = 1.0;

varying vec3 vseed;
varying vec3 vobjn;
varying vec3 vobjp;

void vertex() {
	vseed = COLOR.rgb;
	vobjn = NORMAL;
	vobjp = VERTEX;
}

void fragment() {
	vec2 uv = UV * panel_scale;
	float s = seed + vseed.r * 31.0;
	float px = max(length(fwidth(uv)), 0.0005);       // metres per pixel
	float detail = 1.0 - smoothstep(0.025, 0.16, px); // fade sub-pixel detail

	// ---------- primary plating ----------
	vec2 cell; vec2 f; float rnd;
	m_panels(uv, vec2(3.3, 1.35), 0.5, s, cell, f, rnd);
	vec2 dp = min(f, 1.0 - f) * vec2(3.3, 1.35);
	float seam = (1.0 - smoothstep(0.008 + px * 0.4, 0.024 + px * 1.4, min(dp.x, dp.y)))
		* mix(0.35, 1.0, detail);

	// ---------- secondary sub-plate seams ----------
	vec2 cell2; vec2 f2; float rnd2;
	float seam2 = m_panels(uv + vec2(0.13, 0.07), vec2(2.6, 2.0), 0.4, s + 4.0, cell2, f2, rnd2);
	seam2 *= 0.08 * detail;

	// ---------- panel tone ----------
	float tone = (rnd - 0.5) * 0.10;
	vec3 base = paint * (1.0 + tone);
	// broad tonal drift across the whole hull
	base *= 0.90 + 0.20 * m_fbm2(uv * 0.018 + s, 3);
	// structural panels (darker) and rare accent panels
	float dark_panel = step(rnd, 0.014);
	float acc_panel = step(0.014, rnd) * step(rnd, 0.023);
	base = mix(base, paint * 0.42 * (1.0 + tone), dark_panel);
	base = mix(base, accent * (0.9 + 0.2 * m_hash21(cell * 3.1)), acc_panel);

	// ---------- inset hatch on a few panels ----------
	vec2 pc = (f - 0.5) * vec2(3.3, 1.35);
	float hatch_on = step(0.982, rnd) * step(rnd, 0.990) * step(0.35, detail);
	float hd = m_sd_round_rect(pc, vec2(0.78, 0.30), 0.06);
	float hatch = hatch_on * (1.0 - smoothstep(-0.012, 0.012, hd));
	float hatch_rim = hatch_on * (1.0 - smoothstep(0.0, 0.03, abs(hd + 0.02)));
	base = mix(base, paint_dark * 1.7, hatch * 0.35);

	// ---------- rivets / bolt rings ----------
	vec2 bq = abs(pc) - vec2(0.66, 0.24);
	float bolts = 0.0;
	if (hatch_on > 0.5) {
		vec2 bp = pc - sign(pc) * vec2(0.66, 0.24);
		bolts = 1.0 - smoothstep(0.018, 0.032, length(bp));
	}
	// corner bolts on the main panel
	vec2 cp = (abs(f - 0.5) - vec2(0.5, 0.5)) * vec2(3.3, 1.35);
	float cbolt = 1.0 - smoothstep(0.014 + px * 0.3, 0.028 + px * 0.8, length(cp + vec2(0.09, 0.09)));
	cbolt *= step(0.35, rnd) * detail;

	// ---------- wear / grime ----------
	vec3 on = normalize(vobjn);
	float up = m_sat(on.y);
	float down = m_sat(-on.y);
	float streak = m_streaks(uv, 3.0, s) * grime;
	float broad = m_fbm2(uv * vec2(0.30, 0.16) + s, 4);
	float micro = m_noise2(uv * 9.0 + s * 3.0);
	float edge_grime = seam * (0.55 + 0.45 * broad);
	float dust = m_sat(up * 0.55 + broad * 0.55 - 0.25);

	base *= mix(1.0, 0.86, dust * grime);
	base = mix(base, rust_col, m_sat(streak * 0.30 + edge_grime * 0.12) * 0.32 * (1.0 - down * 0.4));
	base *= 1.0 - 0.14 * m_sat(streak - 0.35) * grime;
	// long painted identification stripe along the flanks
	float band = 1.0 - smoothstep(0.30, 0.34, abs(vobjp.y - 7.4));
	base = mix(base, accent * 0.9, band * 0.75 * step(0.25, vseed.r + 0.5));

	// scorch / heat tint near engine (v large)
	float heat = smoothstep(95.0, 145.0, UV.y) * 0.6;

	// ---------- scratches (bare metal) ----------
	float scr = m_scratches(uv + s, 2.0, s) * step(0.35, micro) * detail;
	float metal_wear = m_sat(hatch_rim * 1.2 + cbolt + scr * 0.7);

	// ---------- height field for bump ----------
	float h = -seam * 0.012 - seam2 * 0.004 + hatch * 0.004 - bolts * 0.006
		- cbolt * 0.005 + (broad - 0.5) * 0.004 + micro * 0.0012;

	// ---------- outputs ----------
	vec3 albedo = base;
	albedo = mix(albedo, vec3(0.34, 0.35, 0.37), metal_wear * 0.55);
	albedo *= 1.0 - 0.35 * seam;
	albedo *= 1.0 - 0.25 * seam2 * (1.0 - seam);
	albedo = mix(albedo, albedo * vec3(1.15, 0.9, 0.75), heat * (0.5 + broad * 0.5));

	ALBEDO = albedo;
	METALLIC = mix(0.26, 0.9, metal_wear);
	ROUGHNESS = clamp(0.50 + (1.0 - rnd) * 0.08 + seam * 0.14 + dust * 0.08
		- metal_wear * 0.12 - heat * 0.08, 0.22, 0.95);
	SPECULAR = 0.45;
	AO = 1.0 - 0.45 * seam - 0.18 * seam2 - 0.5 * bolts - 0.35 * cbolt - 0.25 * hatch;
	AO = clamp(AO, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.25;
	NORMAL = m_bump(NORMAL, VERTEX, h, 1.0 / (1.0 + px * 6.0));
}