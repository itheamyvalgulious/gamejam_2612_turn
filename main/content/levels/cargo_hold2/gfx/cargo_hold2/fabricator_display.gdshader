shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float printed = 0.833333;
uniform float received = 0.0;
uniform float pending = 0.0;
uniform float carrier = 0.0;
uniform float fault = 0.0;
uniform float interrupted = 0.0;

const vec3 IDENTITY = vec3(0.77, 0.18, 0.91);
const vec3 BUILD = vec3(0.078, 0.78, 0.84);
const vec3 LINK = vec3(0.57, 0.31, 1.0);
const vec3 LOSS = vec3(1.0, 0.29, 0.19);

float chamfer(vec2 p, vec2 center, vec2 size, float cut) {
	vec2 d = abs(p - center) - size * 0.5;
	return max(max(d.x, d.y), (d.x + d.y + cut) * 0.7071);
}

float fill(float distance_to_edge) {
	return 1.0 - smoothstep(-0.0018, 0.0018, distance_to_edge);
}

float stroke(float distance_to_edge, float thickness) {
	return fill(distance_to_edge) - fill(distance_to_edge + thickness);
}

vec3 meter(vec2 p, float height, float confirmed, float retry, vec3 tint) {
	float cell = (p.x - 0.105) * (12.0 / 0.79);
	float index = floor(cell);
	float slot = chamfer(vec2(fract(cell), p.y), vec2(0.5, height), vec2(0.827, 0.062), 0.019);
	float outline = stroke(slot, 0.0035);
	float in_bounds = step(0.0, cell) * (1.0 - step(12.0, cell));
	float active_cell = 1.0 - step(floor(confirmed * 12.0 + 0.5), index);
	float progress = 0.37 + 0.22 * smoothstep(-0.026, 0.027, p.y - height);
	float lit = fill(slot) * active_cell * progress + outline * active_cell * 0.27;
	float breathing = 0.32 + 0.32 * (0.5 + 0.5 * sin(TIME * 17.0));
	float next_cell = (1.0 - step(0.5, abs(index - floor(confirmed * 12.0 + 0.5))))
		* retry * breathing;
	return in_bounds * (tint * (lit + next_cell * (0.16 * fill(slot) + 0.95 * outline))
		+ vec3(0.010, 0.011, 0.021) * fill(slot) + tint * 0.14 * outline);
}

void fragment() {
	vec2 p = vec2(UV.x, 1.0 - UV.y);
	vec3 link_tint = mix(LINK, LOSS, interrupted);
	float glass_edge = chamfer(p, vec2(0.5), vec2(0.990, 0.982), 0.044);
	float header = chamfer(p, vec2(0.5, 0.881), vec2(0.921, 0.140), 0.028);
	float id_tab = chamfer(p, vec2(0.141, 0.881), vec2(0.202, 0.140), 0.028);
	float build_card = chamfer(p, vec2(0.5, 0.618), vec2(0.921, 0.313), 0.020);
	float link_card = chamfer(p, vec2(0.5, 0.240), vec2(0.921, 0.370), 0.020);
	float build_status = chamfer(p, vec2(0.797, 0.685), vec2(0.232, 0.121), 0.015);
	float link_status = chamfer(p, vec2(0.797, 0.344), vec2(0.232, 0.121), 0.015);
	float trace_box = chamfer(p, vec2(0.5, 0.122), vec2(0.790, 0.102), 0.011);

	vec3 ink = mix(vec3(0.0036, 0.0030, 0.010), vec3(0.0099, 0.0052, 0.018), p.y);
	ink += stroke(glass_edge, 0.003) * vec3(0.083, 0.045, 0.17);
	ink += fill(header) * vec3(0.023, 0.010, 0.045);
	ink += fill(id_tab) * IDENTITY * 0.18 + stroke(id_tab, 0.005) * IDENTITY * 0.46;
	ink += fill(build_card) * vec3(0.004, 0.012, 0.016) + stroke(build_card, 0.0028) * BUILD * 0.20;
	ink += fill(link_card) * vec3(0.010, 0.007, 0.021) + stroke(link_card, 0.0028) * link_tint * 0.20;
	ink += fill(build_status) * BUILD * (0.062 + 0.043 * step(0.99, printed))
		+ stroke(build_status, 0.0035) * BUILD * 0.30;
	ink += fill(link_status) * link_tint * (0.050 + 0.056 * interrupted)
		+ stroke(link_status, 0.0035) * link_tint * (0.30 + 0.23 * interrupted);

	ink += meter(p, 0.532, printed, 0.0, BUILD);
	ink += meter(p, 0.223, received, pending, LINK);

	vec2 grid = abs(fract(p * vec2(34.0, 32.0) + 0.5) - 0.5);
	float pattern = max(1.0 - smoothstep(0.018, 0.060, grid.x), 1.0 - smoothstep(0.018, 0.060, grid.y));
	float noise_bar = pow(max(sin(p.y * 112.0 + TIME * 45.0), 0.0), 18.0);
	float scan = sin(p.y * 435.0) * 0.009;
	float pulse = 0.45 + 0.55 * sin(p.x * 63.0 + TIME * 3.8);
	float wave_y = 0.122 + carrier * sin(p.x * 123.0 - TIME * 10.4) * 0.024 * pulse;
	float wave = 1.0 - smoothstep(0.0024, 0.0065, abs(p.y - wave_y));
	float drop_gap = 1.0 - interrupted * (step(0.54, p.x) - step(0.65, p.x));
	ink += fill(trace_box) * (link_tint * pattern * 0.10
		+ link_tint * (wave * drop_gap * (0.30 + 0.55 * carrier) + noise_bar * fault * 0.32));

	ALBEDO = mix(vec3(0.011, 0.010, 0.018), vec3(0.004, 0.004, 0.008), fill(glass_edge));
	METALLIC = 0.27;
	ROUGHNESS = 0.27;
	SPECULAR = 0.31;
	EMISSION = ink * (1.0 + scan);
}
