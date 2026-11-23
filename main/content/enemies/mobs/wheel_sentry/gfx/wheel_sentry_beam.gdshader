shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0, 0.24, 0.052, 1.0);
uniform float strength = 1.0;
uniform float detail = 1.0;

void fragment() {
	float wall = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float flow = 0.77 + 0.23 * sin(UV.y * 108.0 - TIME * 36.0 + UV.x * 6.283);
	float spiral = pow(0.5 + 0.5 * sin(UV.x * 18.85 + UV.y * 78.0 - TIME * 29.0), 7.0);
	float filaments = pow(0.5 + 0.5 * sin(UV.x * 37.70 - UV.y * 43.0 + TIME * 22.0), 9.0);
	float ribs = pow(0.5 + 0.5 * sin(UV.y * 244.0 - TIME * 54.0), 12.0);
	float brightness = mix(1.1, 0.43 + 0.72 * spiral + 0.40 * filaments + 0.25 * ribs, detail) * flow;
	vec3 hot_strand = mix(color.rgb, vec3(1.0, 0.70, 0.31), detail * spiral * 0.64);
	ALBEDO = hot_strand * 1.95 * brightness;
	ALPHA = clamp(strength * (0.23 + 0.77 * wall) * brightness, 0.0, 1.0);
}
