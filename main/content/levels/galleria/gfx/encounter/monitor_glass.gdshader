shader_type spatial;
render_mode shadows_disabled, specular_schlick_ggx;

uniform sampler2D instrument : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 primary : source_color = vec4(0.35, 0.78, 0.81, 1.0);
uniform vec4 secondary : source_color = vec4(0.55, 0.51, 0.89, 1.0);
uniform int channel = 0;
uniform float scan_offset = 0.0;
uniform float travel = -1.0;
uniform int signal_state = -1;

float band(float offset, float half_width) {
	float edge = clamp(fwidth(offset), 0.5, 5.0);
	return 1.0 - smoothstep(max(0.0, half_width - edge), half_width + edge, abs(offset));
}

float box_mask(vec2 p, vec2 lo, vec2 hi) {
	vec2 mask = smoothstep(lo - 1.0, lo + 1.0, p) * (1.0 - smoothstep(hi - 1.0, hi + 1.0, p));
	return mask.x * mask.y;
}

float signal_dot(vec2 p, vec2 center, float radius) {
	float d = length(p - center);
	return (1.0 - smoothstep(radius - 1.5, radius + 2.0, d)) + exp(-d * 0.086) * 0.58;
}

float packet(float x, float t, float spacing) {
	float line = fract((x - t) / spacing);
	return smoothstep(0.40, 0.86, line) * (1.0 - smoothstep(0.91, 1.0, line));
}

vec3 manifest_signal(vec2 p, float t) {
	float scan_x = mix(517.0, 965.0, fract(t * 0.31));
	float bar = band(p.x - scan_x, 2.2) + exp(-abs(p.x - scan_x) * 0.055) * 0.40;
	float marks = 0.48 + 0.34 * sin(t * 2.1 + p.y * 0.031);
	float badge = box_mask(p, vec2(940.0, 246.0), vec2(957.0, 263.0))
		+ box_mask(p, vec2(940.0, 320.0), vec2(957.0, 337.0));
	return primary.rgb * bar * box_mask(p, vec2(514.0, 396.0), vec2(969.0, 457.0))
		+ secondary.rgb * badge * marks;
}

vec3 conveyor_signal(vec2 p, float t) {
	float center = mix(124.0, 883.0, fract(t * 0.17));
	float gate = smoothstep(140.0, 240.0, center) * (1.0 - smoothstep(787.0, 865.0, center));
	vec2 cargo = p - vec2(center, 271.0);
	float block = box_mask(cargo, vec2(-46.0, -27.0), vec2(46.0, 28.0));
	float inset = box_mask(cargo, vec2(-40.0, -21.0), vec2(40.0, 22.0));
	float tick = band(p.y - 337.0, 5.5) * packet(p.x, t * 108.0, 87.0);
	return primary.rgb * (block * 0.63 - inset * 0.47) * gate
		+ secondary.rgb * tick * box_mask(p, vec2(94.0, 318.0), vec2(910.0, 353.0)) * 0.82;
}

vec2 service_position(float distance_along) {
	if (distance_along < 176.0) {
		return vec2(182.0 + distance_along, 356.0);
	}
	if (distance_along < 207.0) {
		return vec2(358.0, 356.0 - (distance_along - 176.0));
	}
	if (distance_along < 628.0) {
		return vec2(358.0 + (distance_along - 207.0), 325.0);
	}
	if (distance_along < 686.0) {
		return vec2(779.0, 325.0 - (distance_along - 628.0));
	}
	return vec2(779.0 + (distance_along - 686.0), 267.0);
}

vec3 service_signal(vec2 p, float t) {
	float distance_along = mod(t * 121.0, 734.0);
	float flash = 0.36 + 0.18 * sin(t * 2.0);
	return primary.rgb * signal_dot(p, service_position(distance_along), 6.5)
		+ secondary.rgb * (signal_dot(p, service_position(mod(distance_along + 367.0, 734.0)), 5.0) * 0.85
		+ signal_dot(p, vec2(510.0, 325.0), 8.5) * flash);
}

vec3 pressure_signal(vec2 p, float t) {
	float x = clamp((p.x - 58.0) / 651.0, 0.0, 1.0);
	float history = smoothstep(0.26, 0.57, x);
	float line_a = 214.0 + 113.0 * history;
	float line_b = 353.0 - 26.0 * history;
	float sweep_x = fract(t * 0.27);
	float readout = exp(-abs(x - sweep_x) * 9.0);
	float left = band(p.y - line_a, 2.5) * (0.44 + readout * 0.67);
	float right = band(p.y - line_b, 2.5) * (0.43 + readout * 0.67);
	float sample = band((x - sweep_x) * 651.0, 1.8) * 0.27;
	return (primary.rgb * left + secondary.rgb * right + secondary.rgb * sample)
		* box_mask(p, vec2(57.0, 165.0), vec2(711.0, 399.0));
}

vec3 habitat_signal(vec2 p, float t) {
	float channel_x = p.x / 53.0 + t * 1.76;
	float wave_a = sin(channel_x) * 12.0 + sin(channel_x * 1.86) * 4.0 + sin(channel_x * 0.54) * 15.0;
	float wave_b = sin(channel_x * 0.74 + 1.26) * 9.0 + sin(channel_x * 2.28) * 5.0;
	float low = step(p.y, 377.0 + wave_a + 1.0);
	vec3 signal = primary.rgb * band(p.y - 377.0 - wave_a, 3.1)
		+ secondary.rgb * band(p.y - 416.0 - wave_b, 2.2) * 0.82;
	signal += primary.rgb * low * exp(-abs(p.y - 377.0 - wave_a) * 0.034) * 0.17;
	return signal * box_mask(p, vec2(48.0, 299.0), vec2(977.0, 454.0));
}

vec3 stair_signal(vec2 p, float t) {
	float scan_x = mix(97.0, 905.0, fract(t * 0.21));
	float steps_up = clamp(floor((scan_x - 268.0) / 16.0), 0.0, 28.0);
	float scan_y = 383.0 - steps_up * 8.0;
	float marker = signal_dot(p, vec2(scan_x, scan_y - 2.0), 5.5);
	float axis = band(p.x - scan_x, 1.6) * box_mask(p, vec2(86.0, 160.0), vec2(916.0, 401.0));
	return primary.rgb * marker + secondary.rgb * axis * 0.41;
}

vec3 duct_signal(vec2 p, float t) {
	float supply = packet(p.x, t * 128.0, 147.0) * band(p.y - 242.0, 12.0);
	float exhaust = packet(-p.x, t * 107.0, 131.0) * band(p.y - 362.0, 11.0);
	float fins = packet(p.x, t * 128.0, 148.0) * 0.29
		* box_mask(p, vec2(333.0, 172.0), vec2(563.0, 306.0));
	return (primary.rgb * supply + secondary.rgb * exhaust)
		* box_mask(p, vec2(126.0, 214.0), vec2(862.0, 391.0)) + primary.rgb * fins;
}

vec3 power_signal(vec2 p, float t) {
	float current = packet(p.x, t * 149.0, 178.0) * band(p.y - 218.0, 3.6);
	float width = 72.0 + 48.0 * sin(t * 1.9 + p.x / 230.0);
	float meters = band(p.y - 361.0, 3.9) + band(p.y - 380.0, 3.9) * 0.58;
	float local = p.x - (118.0 + clamp(floor((p.x + 15.0) / 323.0), 0.0, 2.0) * 323.0);
	meters *= smoothstep(0.0, 3.0, local) * (1.0 - smoothstep(width, width + 4.0, local));
	float branch = (band(p.x - 194.0, 3.2) + band(p.x - 518.0, 3.2) + band(p.x - 840.0, 3.2))
		* box_mask(p, vec2(176.0, 220.0), vec2(850.0, 296.0)) * packet(p.y, t * 63.0, 88.0);
	return primary.rgb * (current * box_mask(p, vec2(71.0, 208.0), vec2(948.0, 229.0)) + branch)
		+ secondary.rgb * meters;
}

vec3 lock_signal(vec2 p, float t) {
	float signal_y = 201.0 + float(signal_state) * 33.5;
	float light = box_mask(p, vec2(865.0, signal_y - 7.0), vec2(933.0, signal_y + 7.0));
	float pending_pulse = 0.77 + 0.20 * sin(t * 5.9);
	float strength = signal_state == 1 ? pending_pulse : 0.93;
	return (signal_state == 2 ? secondary.rgb : primary.rgb) * light * strength;
}

vec3 actuator_signal(vec2 p) {
	float position = clamp(travel, 0.0, 1.0);
	float scale_x = (p.x - 96.0) / 832.0;
	float filled = (1.0 - smoothstep(position - 0.003, position + 0.003, scale_x)) * step(0.001, position);
	float segment = smoothstep(0.08, 0.21, fract(scale_x * 32.0));
	float rod_end = mix(378.0, 610.0, position);
	float rod = box_mask(p, vec2(170.0, 232.0), vec2(rod_end, 251.0));
	float carriage = box_mask(p, vec2(rod_end - 13.0, 218.0), vec2(rod_end, 264.0));
	return primary.rgb * filled * segment * box_mask(p, vec2(96.0, 388.0), vec2(928.0, 417.0))
		+ secondary.rgb * (rod * 0.48 + carriage * 0.76);
}

void fragment() {
	vec2 point = UV * vec2(1024.0, 512.0);
	float time = TIME + scan_offset * 4.0;
	vec4 ink = texture(instrument, UV);
	vec3 phosphor = ink.rgb * ink.a;
	float scan_distance = abs(UV.y - fract(time * 0.075));
	float scan = exp(-scan_distance * 42.0);
	float glass_angle = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float reflection_band = smoothstep(0.12, 0.27, UV.y) * (1.0 - smoothstep(0.28, 0.58, UV.y));
	float edge_key = box_mask(point, vec2(47.0, 111.0), vec2(184.0, 117.0));
	vec3 ambient_tint = mix(primary.rgb, secondary.rgb, smoothstep(0.0, 1.0, UV.x));
	vec3 changing;
	if (channel == 0) {
		changing = manifest_signal(point, time);
	} else if (channel == 1) {
		changing = conveyor_signal(point, time);
	} else if (channel == 2) {
		changing = service_signal(point, time);
	} else if (channel == 3) {
		changing = pressure_signal(point, time);
	} else if (channel == 4) {
		changing = habitat_signal(point, time);
	} else if (channel == 5) {
		changing = stair_signal(point, time);
	} else if (channel == 6) {
		changing = duct_signal(point, time);
	} else if (channel == 7) {
		changing = lock_signal(point, time);
	} else if (channel == 8) {
		changing = actuator_signal(point);
	} else {
		changing = power_signal(point, time);
	}
	ALBEDO = vec3(0.014, 0.021, 0.027) + ambient_tint * 0.023
		+ vec3(0.025, 0.037, 0.046) * reflection_band * glass_angle;
	METALLIC = 0.24;
	ROUGHNESS = 0.38;
	SPECULAR = 0.24;
	EMISSION = phosphor * (0.84 + scan * 0.12) + changing * 0.85 + primary.rgb * edge_key * 0.48
		+ ambient_tint * scan * 0.028;
}
