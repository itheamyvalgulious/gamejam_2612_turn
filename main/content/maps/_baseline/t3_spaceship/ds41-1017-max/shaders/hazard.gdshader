// ============================================================================
//  hazard.gdshader — warning stripes, blast-door trim, deck edges
// ============================================================================
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 col_a : source_color = vec3(0.78, 0.54, 0.05);
uniform vec3 col_b : source_color = vec3(0.055, 0.05, 0.045);
uniform float seed = 0.0;
uniform float stripe_m = 0.10;
uniform float wear : hint_range(0.0, 1.0) = 0.55;

varying vec3 vseed;

void vertex() {
	vseed = COLOR.rgb;
}

void fragment() {
	float s = seed + vseed.r * 11.0;
	float stripe = step(0.5, fract((UV.x + UV.y) / (stripe_m * 2.0)));
	vec3 col = mix(col_b, col_a, stripe);
	float chip = m_sat(m_turb2(UV * 14.0 + s, 3) * 1.6 - 0.45) * wear;
	col = mix(col, vec3(0.30, 0.30, 0.32), chip);
	col *= 0.8 + 0.3 * m_fbm2(UV * 2.0 + s, 3);
	float grime = m_sat(m_fbm2(UV * 1.2 + s, 4) * 1.3 - 0.4);
	col *= 1.0 - grime * 0.35;
	ALBEDO = col;
	METALLIC = mix(0.2, 0.7, chip);
	ROUGHNESS = clamp(0.55 + grime * 0.25 - chip * 0.3, 0.08, 1.0);
	AO = 1.0 - grime * 0.2;
	NORMAL = m_bump(NORMAL, VERTEX, -chip * 0.002 + grime * 0.001, 1.0);
}