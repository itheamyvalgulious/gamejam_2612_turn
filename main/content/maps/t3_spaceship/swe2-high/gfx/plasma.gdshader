// plasma.gdshader — animated reactor core / conduit plasma (unit UV cylinder).
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

#include "res://gfx/common.gdshaderinc"

uniform vec3 col : source_color = vec3(0.45, 0.75, 1.0);
uniform vec3 hot : source_color = vec3(0.9, 0.98, 1.0);
uniform float energy = 3.0;

void fragment() {
	vec2 uv = UV;
	// uv.x around, uv.y along height
	float flow = fbm(vec2(uv.x * 6.0, uv.y * 3.0 - TIME * 0.8), 4);
	float flow2 = fbm(vec2(uv.x * 10.0 + 7.0, uv.y * 5.0 - TIME * 1.6), 3);
	float m = flow * 0.65 + flow2 * 0.5;
	m = smoothstep(0.25, 0.85, m);
	vec3 c = mix(col, hot, m * m);
	float core = smoothstep(0.0, 0.35, uv.y) * smoothstep(1.0, 0.65, uv.y);
	ALBEDO = c * energy * (0.4 + m);
	EMISSION = c * energy * (0.4 + m) * (0.6 + 0.6 * core);
	ALPHA = 1.0;
}
