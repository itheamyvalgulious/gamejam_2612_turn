// ============================================================================
//  hologram.gdshader — volumetric-looking projection art / holo-table
// ============================================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

#include "res://shaders/lib/math.gdshaderinc"

uniform vec3 color : source_color = vec3(0.25, 0.8, 1.0);
uniform float energy : hint_range(0.0, 12.0) = 2.2;
uniform float seed = 0.0;
uniform int mode : hint_range(0, 2) = 0;

varying vec3 vseed;

void vertex() {
	vseed = COLOR.rgb;
}

void fragment() {
	vec2 uv = UV;
	float s = seed + vseed.r * 9.0;
	float t = TIME;
	vec3 V = normalize(VIEW);
	float fres = pow(1.0 - m_sat(abs(dot(NORMAL, V))), 2.0);

	// scanlines + jitter
	float scan = 0.55 + 0.45 * sin(uv.y * 260.0 - t * 6.0);
	float jitter = m_hash21(vec2(floor(uv.y * 120.0), floor(t * 14.0))) * 0.06;

	vec3 col = color;
	float alpha = 0.0;

	if (mode == 0) {
		// wireframe sphere-ish lat/long grid (works on any mesh via UV)
		float lon = 1.0 - smoothstep(0.0, 0.03, abs(fract(uv.x * 24.0) - 0.5) * 2.0 - 0.94);
		float lat = 1.0 - smoothstep(0.0, 0.02, abs(fract(uv.y * 12.0 + jitter) - 0.5) * 2.0 - 0.94);
		alpha = (lon + lat) * 0.5 + fres * 0.6;
		alpha *= 0.5 + 0.5 * scan;
	} else if (mode == 1) {
		// scrolling data curtain
		float lines = step(0.55, fract(uv.y * 90.0 + t * 0.8));
		float blocks = step(0.6, m_hash21(vec2(floor(uv.x * 20.0), floor(uv.y * 60.0 - t * 2.0))));
		alpha = (lines * 0.4 + blocks * 0.35) * (0.4 + fres);
	} else {
		// soft core glow with turbulent edges
		float n = m_fbm2(uv * 6.0 + vec2(0.0, -t * 0.3) + s, 4);
		alpha = (0.25 + 0.75 * n) * (0.4 + fres * 1.4);
	}

	ALBEDO = col * energy * alpha * 1.6;
}