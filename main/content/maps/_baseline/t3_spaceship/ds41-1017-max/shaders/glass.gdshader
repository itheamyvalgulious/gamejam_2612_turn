// ============================================================================
//  glass.gdshader — viewports / canopies
// ============================================================================
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.62, 0.78, 0.86);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.10;
uniform float seed = 0.0;
uniform float dirt : hint_range(0.0, 1.0) = 0.4;

varying vec3 vseed;

void vertex() {
	vseed = COLOR.rgb;
}

void fragment() {
	vec2 uv = UV;
	float s = seed + vseed.r * 7.0;
	vec3 V = normalize(VIEW);
	float fres = pow(1.0 - m_sat(dot(NORMAL, V)), 3.0);

	float smear = m_streaks(uv * vec2(1.0, 0.35), 0.8, s) * dirt;
	float specks = smoothstep(0.72, 0.9, m_noise2(uv * 41.0 + s)) * dirt;
	float edge = 1.0 - smoothstep(0.0, 0.035, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
	edge *= 0.0; // handled by frame geometry

	ALBEDO = tint * (0.9 + 0.1 * m_noise2(uv * 6.0));
	METALLIC = 0.0;
	ROUGHNESS = clamp(0.035 + smear * 0.22 + specks * 0.30, 0.02, 0.45);
	SPECULAR = 0.7;
	ALPHA = clamp(base_alpha + fres * 0.17 + smear * 0.07 + specks * 0.08, 0.0, 0.7);
}