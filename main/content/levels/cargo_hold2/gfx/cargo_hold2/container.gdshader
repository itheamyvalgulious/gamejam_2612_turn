// ============================================================================
//  container.gdshader — corrugated cargo containers
// ============================================================================
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://gfx/cargo_hold2/lib/math.gdshaderinc"

uniform vec3 paint : source_color = vec3(0.16, 0.30, 0.36);
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float seed = 0.0;
uniform float rust : hint_range(0.0, 1.5) = 0.32;
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
	float px = max(length(fwidth(uv)), 0.0001);
	float detail = 1.0 - smoothstep(0.004, 0.025, px);

	vec3 col = paint * 0.95;
	// rust bleeding from the bottom and from ribs
	float bottom = 1.0 - smoothstep(0.0, 0.7, uv.y);
	float rust_mask = m_sat(m_turb2(uv * 1.1 + s, 4) * 1.7 - 0.55 + bottom * 0.6) * rust;
	col = mix(col, vec3(0.20, 0.14, 0.10) * (1.2 + 0.35 * rib), rust_mask * 0.8);
	col *= 1.0 - 0.25 * m_noise2(uv * 0.5 + s);
	// scratches
	float scr = m_scratches(uv * vec2(1.0, 2.0), 1.2, s) * detail * 0.35;
	float grain = (m_noise2(uv * 210.0 + s) - 0.5) * (1.0 - smoothstep(0.001, 0.006, px));
	col = mix(col, vec3(0.48, 0.49, 0.50), scr * 0.48);

	ALBEDO = col;
	METALLIC = mix(0.48, 0.88, scr) * (1.0 - rust_mask);
	ROUGHNESS = clamp(0.31 + grain * 0.07 + rust_mask * 0.38 - scr * 0.14, 0.18, 0.75);
	SPECULAR = 0.64;
	AO = 1.0 - rust_mask * 0.15;
	NORMAL_MAP = texture(surface_normal, UV / 1.12).rgb;
	NORMAL_MAP_DEPTH = 0.72;
}
