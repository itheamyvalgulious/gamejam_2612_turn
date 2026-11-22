// plant.gdshader — hydroponics foliage: procedurally shaded leaves.
// geometry is quad cards / clusters; UV unit per card.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://gfx/common.gdshaderinc"

uniform vec3 leaf_a : source_color = vec3(0.05, 0.16, 0.05);
uniform vec3 leaf_b : source_color = vec3(0.18, 0.34, 0.08);
uniform float seed = 0.0;

varying vec4 vcol;

void vertex() { vcol = COLOR; }

void fragment() {
	vec2 uv = UV;
	float s = seed + vcol.r * 47.0;
	// leaf silhouette: taper + midrib + veins, alpha-clipped
	vec2 p = uv - vec2(0.5, 0.0);
	float taper = 1.0 - abs(p.x) / (0.5 * (0.25 + 0.75 * sin(uv.y * 3.14159)));
	float shape = step(0.0, taper);
	// serration
	shape *= step(0.0, taper + sin(uv.y * 60.0 + s) * 0.02 - 0.0);
	float rib = stripe(abs(p.x), 0.012, 0.012);
	float vein = stripe(abs(fract(atan(p.y + 0.02, p.x) * 4.0) - 0.5) * 0.5, 0.06, 0.06);
	vec3 col = mix(leaf_a, leaf_b, vnoise(uv * 6.0 + s) * 0.8 + uv.y * 0.2);
	col = mix(col, col * 1.25, rib * 0.5 + vein * 0.2);
	float transl = pow(max(dot(NORMAL, -VIEW), 0.0), 1.0);

	ALBEDO = col;
	ALPHA = shape;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	BACKLIGHT = col * transl * 0.9;
}
