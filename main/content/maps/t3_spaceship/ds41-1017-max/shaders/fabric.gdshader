// ============================================================================
//  fabric.gdshader — upholstery, rugs, curtains, EVA suit cloth
// ============================================================================
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 base_col : source_color = vec3(0.22, 0.24, 0.28);
uniform vec3 thread_col : source_color = vec3(0.32, 0.33, 0.36);
uniform float seed = 0.0;
uniform float weave_m : hint_range(0.002, 0.05) = 0.006;
uniform float grime : hint_range(0.0, 2.0) = 0.8;

varying vec3 vseed;
varying float vwear;

void vertex() {
	vseed = COLOR.rgb;
	vwear = COLOR.a;
}

void fragment() {
	vec2 uv = UV;
	float s = seed + vseed.r * 13.0;
	vec2 w = uv / weave_m;
	float warp = sin(w.x * 6.2831) * 0.5 + 0.5;
	float weft = sin(w.y * 6.2831) * 0.5 + 0.5;
	float weave = warp * 0.55 + weft * 0.55;
	vec3 col = mix(base_col, thread_col, weave * 0.55);
	// large fabric slubs + fading
	float slub = m_noise2(vec2(uv.x * 6.0, uv.y * 38.0) + s);
	col *= 0.86 + 0.28 * slub;
	float fade = m_fbm2(uv * 0.8 + s, 3);
	col = mix(col, col * 1.25, m_sat(fade - 0.35));
	// stains and wear
	float stain = m_sat(m_turb2(uv * 1.7 + s * 2.0, 4) * 1.5 - 0.6) * grime * (0.3 + 0.7 * vwear);
	col = mix(col, col * 0.45, stain * 0.7);
	float piling = smoothstep(0.62, 0.8, m_noise2(uv * 28.0 + s));
	col = mix(col, thread_col * 0.85, piling * 0.25);
	float fuzz = m_sat(m_fbm2(uv * 60.0, 2) - 0.4);
	ALBEDO = col;
	ROUGHNESS = clamp(0.82 + fuzz * 0.12 - stain * 0.1, 0.55, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.25;
	NORMAL = m_bump(NORMAL, VERTEX, (weave * 0.0008 + slub * 0.0015 - stain * 0.0004), 1.0);
}