shader_type spatial;
render_mode unshaded;

uniform float blade_length = 1.83;
uniform float baseline = 3.2;
uniform float leading_edge = -0.18;
uniform float charged_power = 0.0;
uniform float white_heat = 0.0;
uniform float moving_wave = 0.0;
uniform float attack_glow = 0.0;
varying float position_on_blade;

void vertex() {
	position_on_blade = VERTEX.y / blade_length;
}

void fragment() {
	vec3 cold = mix(vec3(0.23, 1.0, 0.72), vec3(1.0, 0.035, 0.02), attack_glow);
	vec3 hot = mix(vec3(0.88, 1.0, 0.96), vec3(1.0, 0.19, 0.10), attack_glow);
	vec3 charged = mix(cold, hot, white_heat);
	float fed = 1.0 - smoothstep(leading_edge - 0.09, leading_edge + 0.012, position_on_blade);
	float wave = moving_wave * (1.0 - smoothstep(0.014, 0.075, abs(position_on_blade - leading_edge)));
	ALBEDO = cold * baseline + charged * fed * charged_power + hot * wave * 2.4;
}
