// ============================================================================
//  container.gdshader — corrugated cargo containers
// ============================================================================
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 paint : source_color = vec3(0.16, 0.30, 0.36);
uniform vec3 stencil : source_color = vec3(0.78, 0.76, 0.70);
uniform float seed = 0.0;
uniform float rust : hint_range(0.0, 1.5) = 0.8;
uniform float rib_m = 0.28;

varying vec3 vseed;

void vertex() {
	vseed = COLOR.rgb;
}

void fragment() {
	vec2 uv = UV;
	float s = seed + vseed.r * 29.0;
	// vertical corrugation ribs
	float rib = sin(uv.x / rib_m * 6.2831);
	float rib2 = sin(uv.x / rib_m * 6.2831 + 1.2) * 0.5;
	float h = rib * 0.006;

	vec3 col = paint * (0.86 + 0.18 * (rib * 0.5 + 0.5));
	// door end frames
	float frame = step(abs(uv.x / 12.0 - 0.0), 0.02);
	// stencil markings
	float band = step(0.62, uv.y / 2.6) * step(uv.y / 2.6, 0.78) * step(0.06, fract(uv.x / 3.0)) * step(fract(uv.x / 3.0), 0.28);
	col = mix(col, stencil, band * 0.6 * step(0.4, m_hash21(vec2(floor(uv.x / 3.0), s))));

	// rust bleeding from the bottom and from ribs
	float bottom = 1.0 - smoothstep(0.0, 0.7, uv.y);
	float rust_mask = m_sat(m_turb2(uv * 1.1 + s, 4) * 1.7 - 0.55 + bottom * 0.6) * rust;
	col = mix(col, vec3(0.24, 0.10, 0.05) * (0.7 + 0.7 * rib * 0.5 + 0.5), rust_mask * 0.8);
	col *= 1.0 - 0.25 * m_noise2(uv * 0.5 + s);
	// scratches
	float scr = m_scratches(uv * vec2(1.0, 2.0), 1.2, s);
	col = mix(col, vec3(0.5), scr * 0.4);

	ALBEDO = col;
	METALLIC = mix(0.55, 0.15, rust_mask);
	ROUGHNESS = clamp(0.48 + rust_mask * 0.3 + scr * 0.1, 0.1, 1.0);
	AO = 1.0 - rust_mask * 0.15;
	NORMAL = m_bump(NORMAL, VERTEX, h - rust_mask * 0.001, 1.0);
}