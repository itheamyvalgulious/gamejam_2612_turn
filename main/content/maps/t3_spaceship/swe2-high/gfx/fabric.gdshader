// fabric.gdshader — bunks, seats, soft panels.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://gfx/common.gdshaderinc"

uniform vec3 base : source_color = vec3(0.32, 0.34, 0.40);
uniform vec3 seam_col : source_color = vec3(0.2, 0.21, 0.25);
uniform float weave = 90.0;

varying vec4 vcol;

void vertex() { vcol = COLOR; }

void fragment() {
	vec2 uv = UV;
	float s = vcol.r * 31.0;
	// woven threads — fade to flat at range or the 90/cm pattern aliases
	// into white speckle noise on every seat and bunk
	float px = max(fwidth(uv.x), fwidth(uv.y));
	float wfade = 1.0 - smoothstep(0.02, 0.15, px);
	float wx = vnoise(vec2(uv.x * weave, uv.y * weave) + s) * wfade + 0.5 * (1.0 - wfade);
	float wy = vnoise(vec2(uv.x * weave * 1.7 + 9.0, uv.y * weave) + s) * wfade + 0.5 * (1.0 - wfade);
	float weave_m = (wx + wy) * 0.5;
	// cushion quilting: soft diamond bulges
	vec2 q = abs(fract(mat2(vec2(1, 1), vec2(-1, 1)) * uv * 1.6) - 0.5);
	float quilt = 1.0 - smoothstep(0.0, 0.5, min(q.x, q.y) + 0.35);
	vec3 col = base * (0.85 + weave_m * 0.22 + quilt * 0.12);
	float seam = panels(uv, vec2(0.5, 0.7), 0.0, s, q, q, weave_m) * 0.6;
	col = mix(col, seam_col, seam * 0.5);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	NORMAL = bumpn(NORMAL, VERTEX, weave_m + quilt * 0.4, 0.6);
}
