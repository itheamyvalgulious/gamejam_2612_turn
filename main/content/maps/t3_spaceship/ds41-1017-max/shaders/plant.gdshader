// ============================================================================
//  plant.gdshader — hydroponics foliage (two-sided, veins, translucency)
// ============================================================================
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 leaf : source_color = vec3(0.12, 0.30, 0.07);
uniform vec3 leaf_tip : source_color = vec3(0.30, 0.52, 0.10);
uniform float seed = 0.0;

varying vec3 vseed;

void vertex() {
	vseed = COLOR.rgb;
}

void fragment() {
	vec2 uv = UV;
	float s = seed + vseed.r * 5.0;
	float mid = 1.0 - smoothstep(0.0, 0.05, abs(uv.x - 0.5));
	float veins = 1.0 - smoothstep(0.0, 0.012, abs(fract((uv.y - abs(uv.x - 0.5) * 0.6) * 9.0) - 0.5) * 0.11);
	vec3 col = mix(leaf, leaf_tip, uv.y);
	col *= 0.75 + 0.45 * mid;
	col += vec3(0.05, 0.09, 0.02) * veins * 0.6;
	float n = m_noise2(uv * 14.0 + s);
	col *= 0.85 + 0.3 * n;
	ALBEDO = col;
	ROUGHNESS = 0.62 + n * 0.15;
	METALLIC = 0.0;
	SPECULAR = 0.3;
	EMISSION = col * 0.06;
}