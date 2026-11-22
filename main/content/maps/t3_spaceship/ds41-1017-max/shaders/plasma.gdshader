// ============================================================================
//  plasma.gdshader — engine exhaust, reactor core, energy conduits
// ============================================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 hot : source_color = vec3(1.0, 0.92, 0.72);
uniform vec3 mid : source_color = vec3(1.0, 0.45, 0.12);
uniform vec3 cold : source_color = vec3(0.55, 0.12, 0.05);
uniform float energy : hint_range(0.0, 20.0) = 4.0;
uniform float seed = 0.0;
uniform float flow : hint_range(0.0, 20.0) = 3.0;
uniform int mode : hint_range(0, 2) = 0;

varying vec3 vseed;

void vertex() {
	vseed = COLOR.rgb;
}

void fragment() {
	vec2 uv = UV;
	float s = seed + vseed.r * 23.0;
	float t = TIME;

	if (mode == 0) {
		// exhaust column: UV.y along the plume, UV.x around it
		vec2 p = vec2(uv.x * 6.0, uv.y * 3.0 - t * flow * 0.10);
		float n = m_fbm2(p + s, 4);
		float n2 = m_fbm2(p * 2.7 + vec2(0.0, -t * flow * 0.21) + s, 3);
		float core = smoothstep(0.85, 0.0, abs(uv.x - 0.5) * 2.0);
		float falloff = pow(clamp(1.0 - uv.y, 0.0, 1.0), 1.4);
		float flick = 0.8 + 0.2 * sin(t * 17.0 + s * 40.0) * sin(t * 5.3 + s * 11.0);
		vec3 col = mix(cold, mid, m_sat(n * 1.5));
		col = mix(col, hot, m_sat(core * n2 * 1.8));
		float a = falloff * (0.25 + core * 0.85) * (0.55 + n * 0.7) * flick;
		ALBEDO = col * energy * a;
	} else if (mode == 1) {
		// spherical reactor glow: swirling cells
		vec2 p = (uv - 0.5) * 2.0;
		float r = length(p);
		float ang = atan(p.y, p.x) / 6.2831 + 0.5;
		vec2 q = vec2(ang * 5.0 + s, r * 6.0 - t * flow * 0.06);
		float n = m_fbm2(q, 4);
		float n2 = m_fbm2(q * 3.0 + vec2(t * flow * 0.08, 0.0), 3);
		vec3 col = mix(cold, mid, m_sat(n * 1.6));
		col = mix(col, hot, m_sat(n2 * n * 2.2 + (1.0 - r) * 0.5));
		ALBEDO = col * energy * smoothstep(1.0, 0.35, r) * (0.7 + 0.6 * n);
	} else {
		// energy conduit: bright travelling pulses
		float pulse = pow(0.5 + 0.5 * sin(uv.y * 1.6 - t * flow), 6.0);
		float n = m_noise2(vec2(uv.x * 8.0, uv.y * 3.0 + s) + t * 0.1);
		vec3 col = mix(mid, hot, pulse);
		ALBEDO = col * energy * (0.25 + pulse * 1.1) * (0.7 + 0.4 * n);
	}
}