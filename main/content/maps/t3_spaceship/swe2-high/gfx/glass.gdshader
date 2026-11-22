// glass.gdshader — windows / canopy / case glass.
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, specular_schlick_ggx;

#include "res://gfx/common.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.5, 0.62, 0.72, 0.22);
uniform float rough = 0.06;

void fragment() {
	vec3 col = tint.rgb;
	// edge haze + faint interior reflection sheen
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	ALBEDO = col * (0.4 + fres * 1.4);
	ALPHA = tint.a + fres * 0.30;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
