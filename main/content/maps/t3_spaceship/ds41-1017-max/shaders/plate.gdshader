// ============================================================================
//  plate.gdshader — deck plating / grating
// ============================================================================
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 base_col : source_color = vec3(0.29, 0.30, 0.315);
uniform vec3 deep_col : source_color = vec3(0.055, 0.058, 0.065);
uniform vec3 rust_col : source_color = vec3(0.20, 0.11, 0.06);
uniform float seed = 0.0;
uniform float grate : hint_range(0.0, 1.0) = 0.0;
uniform float wear_amount : hint_range(0.0, 2.0) = 1.0;
uniform float tile_m : hint_range(0.4, 4.0) = 1.22;
uniform float metal_scale : hint_range(0.0, 1.0) = 1.0;
uniform float rough_bias : hint_range(-0.2, 0.4) = 0.0;

varying vec3 vseed;
varying float vwear;

void vertex() {
	vseed = COLOR.rgb;
	vwear = COLOR.a;
}

void fragment() {
	vec2 uv = UV;
	float s = seed + vseed.r * 53.0;
	float local_h = vseed.g;   // 0 at floor ... 1 at ceiling (for walls)
	float px = max(length(fwidth(uv)), 0.0004);
	float detail = 1.0 - smoothstep(0.02, 0.10, px);

	// staggered deck plates
	vec2 cell; vec2 f; float rnd;
	float seam = m_panels(uv, vec2(tile_m, tile_m * 0.5), 0.5, s, cell, f, rnd);

	// micro plate seams (quarter panels)
	vec2 c2; vec2 f2; float r2;
	float seam2 = m_panels(uv + vec2(0.7, 0.31), vec2(tile_m * 0.5, tile_m * 0.25), 0.3, s + 2.0, c2, f2, r2) * 0.5;

	// diamond tread pattern
	vec2 tp = m_rot(f * vec2(tile_m, tile_m * 0.5) * 6.2831, 0.785);
	float tread = m_grid_line(tp.x * 2.4, 0.22) * m_grid_line(tp.y * 2.4, 0.22) * detail;
	tread *= step(0.35, rnd) * (1.0 - grate);

	// grating variant: rectangular apertures + structural ribs
	vec2 gp = fract(uv / vec2(0.16, 0.055));
	float hole = step(0.18, gp.x) * step(gp.x, 0.82) * step(0.16, gp.y) * step(gp.y, 0.84);
	float grate_mask = grate;
	float grate_rib = (1.0 - hole) * grate_mask;

	// scuffs: directional smears, polished traffic lanes
	float scuff = m_turb2(uv * vec2(0.7, 2.4) + s, 3) * mix(0.5, 1.0, detail);
	float lane = m_noise2(vec2(uv.x * 0.20, uv.y * 0.045) + s) ;
	lane = smoothstep(0.55, 0.8, lane) * wear_amount;

	// grime in seams and corners
	float wear = clamp(vwear, 0.0, 1.6);
	float grime = m_sat(m_fbm2(uv * 0.33 + s * 1.7, 4) * 1.2 - 0.25) * (0.5 + 0.6 * wear);
	grime = m_sat(grime * 0.7 + seam * 0.55 + seam2 * 0.3);

	vec3 col = base_col * (1.0 + (rnd - 0.5) * 0.16);
	col = mix(col, deep_col, seam * 0.75);
	col = mix(col, rust_col, m_sat(grime - 0.42) * 0.33);
	col *= mix(1.0, 0.70, grime * 0.8);
	col = mix(col, col * vec3(1.35), tread * 0.35 + lane * 0.25);
	col = mix(col, deep_col * 0.45, grate_rib * 0.55);

	// height field
	float h = -seam * 0.008 - seam2 * 0.002 + tread * 0.002 + grate_rib * 0.010
		+ (grime - 0.5) * 0.0015;

	ALBEDO = col;
	METALLIC = mix(0.40, 0.72, tread) * (1.0 - grime * 0.35) * metal_scale;
	ROUGHNESS = clamp(0.36 + rough_bias + grime * 0.32 + scuff * 0.12 - lane * 0.08 + grate_rib * 0.15, 0.16, 0.98);
	SPECULAR = 0.5;
	AO = clamp(1.0 - seam * 0.55 - seam2 * 0.18 - grime * 0.25 - grate_rib * 0.55, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.2;
	NORMAL = m_bump(NORMAL, VERTEX, h, 1.0);
}