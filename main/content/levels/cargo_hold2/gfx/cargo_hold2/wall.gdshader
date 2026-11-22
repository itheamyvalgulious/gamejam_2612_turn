// ============================================================================
//  wall.gdshader — interior surfaces (painted panels / structural / padded / tile)
//  UV is in meters; COLOR.g carries normalised local height (0 = deck, 1 = ceiling)
// ============================================================================
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://gfx/cargo_hold2/lib/math.gdshaderinc"

uniform vec3 base_col : source_color = vec3(0.34, 0.355, 0.375);
uniform vec3 trim_col : source_color = vec3(0.10, 0.11, 0.125);
uniform vec3 accent_col : source_color = vec3(0.80, 0.34, 0.06);
uniform int style : hint_range(0, 4) = 0;
uniform float seed = 0.0;
uniform float grime : hint_range(0.0, 2.0) = 0.8;

varying vec3 vseed;
varying float vwear;

void vertex() {
	vseed = COLOR.rgb;
	vwear = COLOR.a;
}

void fragment() {
	vec2 uv = UV;
	float s = seed + vseed.r * 67.0;
	float lh = clamp(vseed.g, 0.0, 1.0);
	float px = max(length(fwidth(uv)), 0.0004);
	float detail = 1.0 - smoothstep(0.02, 0.12, px);

	vec3 col = base_col;
	float rough = 0.55;
	float metal = 0.25;
	float h = 0.0;
	float ao = 1.0;
	float grime_mask = 0.0;

	if (style == 0) {
		// ---------------- painted modular panels ----------------
		vec2 cell; vec2 f; float rnd;
		float seam = m_panels(uv, vec2(1.24, 0.78), 0.0, s, cell, f, rnd);
		vec2 c2; vec2 f2; float r2;
		float seam2 = m_panels(uv + vec2(0.62, 0.39), vec2(0.62, 0.39), 0.0, s + 3.0, c2, f2, r2) * 0.45;

		col *= 1.0 + (rnd - 0.5) * 0.09;
		// occasional differently painted panel
		float alt = step(rnd, 0.13);
		col = mix(col, base_col * 0.55, alt);
		// vertical stiffener ribs
		float rib = 1.0 - smoothstep(0.0, 0.055, abs(fract(uv.x / 2.48) - 0.5) * 2.48 - 1.18);
		rib *= 0.0;
		// rub rails (two horizontal bands) at local heights 0.18 / 0.80
		float rail = 1.0 - smoothstep(0.0, 0.024, abs(lh - 0.19));
		rail += 1.0 - smoothstep(0.0, 0.020, abs(lh - 0.805));
		rail = clamp(rail, 0.0, 1.0);
		col = mix(col, trim_col, rail * 0.85);

		// screws in panel corners
		vec2 cp = abs(f - 0.5) * vec2(1.24, 0.78) - vec2(0.52, 0.30);
		float screw = (1.0 - smoothstep(0.010 + px, 0.018 + px * 2.0, length(cp))) * step(0.45, rnd) * detail;
		// ventilation slots near top of some panels
		float vent_on = step(0.86, rnd) * step(0.55, lh) * step(lh, 0.72);
		vec2 vp = vec2(f.x * 1.24, (lh - 0.55) * 10.0);
		float vent = vent_on * m_grid_line(vp.y * 14.0, 0.55) * step(0.12, f.x) * step(f.x, 0.88) * detail;
		col = mix(col, trim_col, vent * 0.9);
		// tiny stencil blocks
		float label = step(0.94, m_hash21(cell + s)) * step(0.35, f.y) * step(f.y, 0.44)
			* step(0.12, f.x) * step(f.x, 0.40);
		col = mix(col, accent_col, label * 0.85);

		h = -seam * 0.010 - seam2 * 0.003 - screw * 0.004 + rail * 0.004 - vent * 0.006;
		ao = 1.0 - seam * 0.55 - seam2 * 0.15 - screw * 0.3;
		rough = 0.52 + seam * 0.12 + rnd * 0.05;
		metal = 0.22;
	} else if (style == 1) {
		// ---------------- structural: bare metal + heavy seams ----------------
		vec2 cell; vec2 f; float rnd;
		float seam = m_panels(uv, vec2(2.0, 1.1), 0.5, s, cell, f, rnd);
		float lamp = 0.5 + 0.5 * sin(uv.x * 6.2831 / 0.46);
		float corr = smoothstep(0.15, 0.85, lamp);
		col = mix(base_col * 0.62, base_col * 1.12, corr);
		col *= 0.9 + 0.2 * m_fbm2(uv * 0.7 + s, 4);
		col *= 1.0 + (rnd - 0.5) * 0.24;
		col = mix(col, trim_col, seam * 0.65);
		// vertical ribs every 1.8 m
		float rib = 1.0 - smoothstep(0.02, 0.10, abs(fract(uv.x / 1.8) - 0.5) * 1.8 - 0.83);
		col = mix(col, trim_col * 1.4, rib * 0.65);
		float bolts = (1.0 - smoothstep(0.0, 0.035, abs(fract(uv.y / 0.55) - 0.5) * 0.55 - 0.24))
			* (1.0 - smoothstep(0.006, 0.018, abs(fract(uv.x / 0.9) - 0.5) * 0.9 - 0.40));
		col *= 1.0 - bolts * 0.25;
		h = -seam * 0.014 + corr * 0.006 - rib * 0.010 - bolts * 0.003
			+ (m_fbm2(uv * 2.0 + s, 3) - 0.5) * 0.003;
		ao = 1.0 - seam * 0.55 - rib * 0.45 + corr * 0.06;
		rough = 0.40 + m_noise2(uv * 3.0) * 0.2 + corr * 0.06;
		metal = 0.72;
	} else if (style == 2) {
		// ---------------- padded acoustic panels (quarters) ----------------
		vec2 q = m_rot(uv * 9.0, 0.785);
		vec2 fq = fract(q) - 0.5;
		float pad = smoothstep(0.52, 0.40, length(fq));
		float quilting = 1.0 - smoothstep(0.0, 0.10, length(fq));
		float seams = 1.0 - pad;
		col = base_col * (0.96 + pad * 0.06);
		col = mix(col, trim_col, seams * 0.22);
		float fabric_grain = m_noise2(uv * 95.0 + s);
		float weave = m_noise2(vec2(uv.x * 140.0, uv.y * 12.0) + s * 2.0);
		col *= 0.94 + fabric_grain * 0.09 + weave * 0.03;
		h = pad * 0.003 + quilting * 0.0012 + (fabric_grain - 0.5) * 0.0004;
		ao = 0.82 + pad * 0.18 - quilting * 0.06;
		rough = 0.9 + fabric_grain * 0.06;
		metal = 0.0;
	} else if (style == 3) {
		// ---------------- clean medical tiles ----------------
		vec2 t = uv / 0.30;
		vec2 ti = floor(t);
		vec2 tf = fract(t);
		float grout = 1.0 - smoothstep(0.0, 0.055, min(min(tf.x, 1.0 - tf.x), min(tf.y, 1.0 - tf.y)) * 0.30);
		float rnd = m_hash21(ti + s);
		col = base_col * (1.0 + (rnd - 0.5) * 0.035);
		col = mix(col, trim_col * 1.6, grout * 0.55);
		h = -grout * 0.0025;
		ao = 1.0 - grout * 0.45;
		rough = 0.18 + grout * 0.3 + rnd * 0.03;
		metal = 0.05;
	} else {
		// ---------------- dark industrial panels ----------------
		vec2 cell; vec2 f; float rnd;
		float seam = m_panels(uv, vec2(1.8, 1.4), 0.4, s, cell, f, rnd);
		col = base_col * (1.0 + (rnd - 0.5) * 0.14);
		col = mix(col, trim_col, seam * 0.7);
		col = mix(col, accent_col, step(0.994, rnd) * 0.25);
		h = -seam * 0.012 + (m_fbm2(uv * 1.5 + s, 3) - 0.5) * 0.003;
		ao = 1.0 - seam * 0.6;
		rough = 0.45 + rnd * 0.15;
		metal = 0.6;
	}

	// ---------------- shared weathering ----------------
	float wear = clamp(vwear, 0.0, 1.6);
	float streaks = m_streaks(uv * vec2(1.0, 1.0), 2.0, s) * grime * wear * mix(0.5, 1.0, detail);
	float floor_dirt = (1.0 - smoothstep(0.0, 0.22, lh)) * grime * (0.45 + 0.55 * wear);
	float corner = m_sat(m_fbm2(uv * 0.25 + s, 3) * 1.3 - 0.45);
	grime_mask = m_sat(floor_dirt * 0.9 + streaks * 0.45 + corner * 0.25 * wear);
	col = mix(col, trim_col * 0.8, grime_mask * 0.35);
	col *= 1.0 - grime_mask * 0.18;
	rough = clamp(rough + grime_mask * 0.16, 0.05, 1.0);
	ao *= 1.0 - grime_mask * 0.12;

	ALBEDO = col;
	METALLIC = metal * (1.0 - grime_mask * 0.4);
	ROUGHNESS = rough;
	SPECULAR = 0.45;
	AO = clamp(ao, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.2;
	NORMAL = m_bump(NORMAL, VERTEX, h, 1.0);
}