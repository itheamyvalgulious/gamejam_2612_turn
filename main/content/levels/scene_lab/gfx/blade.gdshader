shader_type spatial;
// Laser blade core: white-hot at the guard, incandescent amber through the arc,
// a hot needle at the tip.  Additive HDR values feed the environment glow pass.
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec4 hot_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.46, 0.10, 1.0);
uniform vec4 tip_color : source_color = vec4(1.0, 0.16, 0.03, 1.0);
uniform float energy = 5.0;
uniform float flicker = 0.10;

void fragment() {
	float t = UV.y;
	vec3 col = mix(hot_color.rgb, mid_color.rgb, smoothstep(0.0, 0.42, t));
	col = mix(col, tip_color.rgb, smoothstep(0.62, 1.0, t));
	// travelling plasma pulses along the blade
	float pulse = 0.92 + 0.08 * sin(t * 38.0 - TIME * 26.0);
	float jitter = 1.0 + flicker * sin(TIME * 61.0 + t * 9.0);
	ALBEDO = col * energy * pulse * jitter;
	// flat faces read white-hot; grazing edges fall off to plasma orange
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	col = mix(mid_color.rgb, col, 0.35 + 0.65 * pow(facing, 1.4));
	ALBEDO = col * energy * pulse * jitter;
}