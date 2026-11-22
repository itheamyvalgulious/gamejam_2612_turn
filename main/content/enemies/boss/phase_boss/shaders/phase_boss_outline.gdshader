shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform float phase_amount : hint_range(0.0, 1.0) = 0.0;
uniform float phase_time = 0.0;
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float edge = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.1);
	vec3 shifted = world_point * vec3(2.2, 2.45, 1.85) + vec3(0.32, -0.26, 0.15) * phase_time;
	vec3 cell = floor(shifted);
	vec3 inset = abs(fract(shifted) - 0.5);
	float variation = fract(sin(dot(cell, vec3(19.1, 113.7, 61.9))) * 4375.73);
	float blink = smoothstep(0.40, 0.94, sin(phase_time * (3.8 + 3.3 * variation) + variation * 11.0));
	float seam = smoothstep(0.445, 0.495, max(max(inset.x, inset.y), inset.z));
	float prism = smoothstep(0.25, 0.85, variation + 0.28 * blink);
	ALBEDO = mix(vec3(0.35, 0.24, 1.0), vec3(0.18, 0.90, 1.0), prism);
	ALPHA = phase_amount * (edge * (0.31 + 0.30 * blink) + seam * blink * 0.13 + 0.018 + 0.044 * prism);
}
