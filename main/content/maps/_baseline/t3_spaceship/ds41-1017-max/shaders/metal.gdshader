// ============================================================================
//  metal.gdshader — machinery, pipes, beams, crates
// ============================================================================
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.30, 0.31, 0.33);
uniform vec3 rust_col : source_color = vec3(0.24, 0.10, 0.045);
uniform float seed = 0.0;
uniform float rust_amount : hint_range(0.0, 1.5) = 0.45;
uniform float oil_grime : hint_range(0.0, 1.5) = 0.6;
uniform float rough_base : hint_range(0.0, 1.0) = 0.45;
uniform float metal_amount : hint_range(0.0, 1.0) = 0.8;
uniform int pattern : hint_range(0, 2) = 0;

varying vec3 vseed;

void vertex() {
	vseed = COLOR.rgb;
}

void fragment() {
	vec2 uv = UV;
	float s = seed + vseed.r * 19.0;
	float brushed = m_noise2(vec2(uv.x * 0.35, uv.y * 26.0) + s);
	float broad = m_fbm2(uv * 0.55 + s, 4);
	float fine = m_noise2(uv * 7.0 + s);
	float px = max(length(fwidth(uv)), 0.0004);
	float detail = 1.0 - smoothstep(0.02, 0.12, px);

	vec3 col = tint;
	float h = 0.0;
	float ao = 1.0;
	float rough = rough_base;
	float metal = metal_amount;

	if (pattern == 0) {
		// machined / cast surface with faint tooling rings
		col *= 0.9 + 0.22 * brushed + 0.10 * fine;
		// weld bead stripes
		float weld = 1.0 - smoothstep(0.0, 0.05, abs(fract(uv.y / 1.7) - 0.5) * 1.7 - 0.80);
		weld *= step(0.75, m_noise2(vec2(uv.x * 0.8, uv.y * 0.2) + s));
		col = mix(col, tint * 0.72, weld * 0.8);
		h += weld * 0.004 + (fine - 0.5) * 0.0015;
		rough += weld * 0.12;
	} else if (pattern == 1) {
		// painted sheet metal: panel seams, chips, rust blooms
		vec2 cell; vec2 f; float rnd;
		float seam = m_panels(uv, vec2(1.6, 0.95), 0.5, s, cell, f, rnd);
		col *= 1.0 + (rnd - 0.5) * 0.10;
		col = mix(col, tint * 0.45, seam * 0.6);
		float chips = smoothstep(0.58, 0.72, m_turb2(uv * 2.4 + s, 3)) * mix(0.35, 1.0, detail);
		metal = mix(metal, 0.95, chips);
		rough = mix(rough, 0.24, chips);
		h += -seam * 0.006 - chips * 0.002;
		ao *= 1.0 - seam * 0.45;
	} else {
		// heavy cast iron / dirty machinery
		col *= 0.8 + 0.35 * broad;
		h += (broad - 0.5) * 0.01 + (fine - 0.5) * 0.003;
	}

	// rust patches and oil drips
	float rust_mask = m_sat(m_turb2(uv * 1.3 + s * 0.7, 4) * 1.5 - 0.55) * rust_amount;
	float drip = m_sat(m_streaks(uv, 1.6, s * 2.0) - 0.4) * oil_grime;
	col = mix(col, rust_col * (0.7 + 0.6 * broad), rust_mask * 0.8);
	col *= 1.0 - drip * 0.45;
	col = mix(col, col * 0.4, m_sat((fine - 0.7) * 2.0) * oil_grime * 0.3 * detail);
	h += rust_mask * 0.002;

	ALBEDO = col;
	METALLIC = clamp(metal * (1.0 - rust_mask * 0.55) * (1.0 - drip * 0.25), 0.0, 1.0);
	ROUGHNESS = clamp(rough + rust_mask * 0.38 + drip * 0.15, 0.05, 1.0);
	SPECULAR = 0.5;
	AO = clamp(ao * (1.0 - rust_mask * 0.15) * (1.0 - drip * 0.2), 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.25;
	NORMAL = m_bump(NORMAL, VERTEX, h, 1.0);
}