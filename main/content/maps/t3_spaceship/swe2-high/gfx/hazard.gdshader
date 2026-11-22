// hazard.gdshader — yellow/black chevron markings, deck edge warnings.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://gfx/common.gdshaderinc"

uniform vec3 col_a : source_color = vec3(0.85, 0.62, 0.06);
uniform vec3 col_b : source_color = vec3(0.09, 0.09, 0.10);
uniform float pitch = 0.5;   // chevron repeat in metres (diagonal)

void fragment() {
	vec2 uv = UV;
	float d = fract((uv.x + uv.y) / pitch);
	float ch = step(0.5, d);
	vec3 col = mix(col_a, col_b, ch);
	// worn paint
	float wear = fbm(uv * 12.0, 3);
	col *= 0.85 + wear * 0.25;
	col = mix(col, vec3(0.25, 0.25, 0.26), smoothstep(0.75, 0.9, wear) * 0.5);
	ALBEDO = col;
	ROUGHNESS = 0.75;
	METALLIC = 0.3;
}
