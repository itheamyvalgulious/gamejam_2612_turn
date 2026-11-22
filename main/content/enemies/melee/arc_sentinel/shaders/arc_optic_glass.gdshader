shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Fixed outer lens glass of the socket optic. Only a thin curved shell, so the
// rotating red ball behind it stays readable. The shell never rotates.

uniform vec4 tint : source_color = vec4(1.0, 0.22, 0.05, 1.0);
uniform float alpha = 0.16;
uniform float intensity = 0.45;
uniform float scan = 0.6;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float rim = smoothstep(0.80, 1.0, r);
	float sweep = pow(0.5 + 0.5 * cos(r * 30.0 - TIME * scan * 3.0), 28.0)
		* smoothstep(1.0, 0.55, r);
	ALBEDO = tint.rgb * 0.03;
	METALLIC = 0.0;
	ROUGHNESS = 0.38;
	SPECULAR = 0.06;
	ALPHA = clamp(alpha + rim * 0.10 + sweep * 0.05, 0.0, 0.85);
	EMISSION = tint.rgb * intensity * (0.10 + rim * 0.65 + sweep * 1.1);
}