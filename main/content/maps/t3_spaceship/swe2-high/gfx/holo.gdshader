// holo.gdshader — volumetric hologram look: fresnel shell + scan lines.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

#include "res://gfx/common.gdshaderinc"

uniform vec3 col : source_color = vec3(0.25, 0.7, 1.0);
uniform float energy = 0.9;
uniform float scan_pitch = 160.0;

void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	float scan = 0.6 + 0.4 * sin(UV.y * scan_pitch - TIME * 6.0);
	float flick = 0.9 + 0.1 * vnoise(vec2(TIME * 8.0, 0.0));
	ALBEDO = col * energy * (0.35 + fres * 1.3) * scan * flick;
	EMISSION = col * energy * (0.35 + fres * 1.3) * scan * flick;
	ALPHA = 1.0;
}
