shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform float phase_amount : hint_range(0.0, 1.0) = 0.0;
uniform float phase_time = 0.0;
uniform vec3 phase_origin;
uniform vec3 phase_axis = vec3(0.0, 0.0, 1.0);
varying vec3 world_point;

float narrow_band(float coord, float width) {
	float dist = abs(fract(coord + 0.5) - 0.5);
	float aa = min(0.12, fwidth(coord));
	return 1.0 - smoothstep(width, width + aa + 0.004, dist);
}

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 pos = world_point - phase_origin;
	float long_axis = dot(pos, phase_axis);
	float width_axis = dot(pos, vec3(phase_axis.z, 0.0, -phase_axis.x));
	float front = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - front, 3.4);
	float contour = narrow_band(pos.y * 3.35 + 0.06 * sin(long_axis * 0.94), 0.042);
	float lower_trace = narrow_band(pos.y * 1.48 - width_axis * 0.19 + long_axis * 0.105, 0.028);
	float scan = long_axis * 0.071 - phase_time * 0.72 + 0.037 * sin(pos.y * 1.7 + width_axis);
	float front_line = narrow_band(scan, 0.025);
	float afterglow = exp(-fract(scan + 0.055) * 10.0);
	float current = front_line * 0.82 + 0.26 * afterglow;
	float light = 0.014 + rim * 0.24 + contour * (0.12 + current * 0.31) + lower_trace * 0.05 + current * 0.23;
	vec3 color = mix(vec3(0.06, 0.60, 1.26), vec3(0.67, 1.26, 1.48), clamp(current + rim * 0.34, 0.0, 1.0));
	ALBEDO = color;
	ALPHA = phase_amount * light;
}
