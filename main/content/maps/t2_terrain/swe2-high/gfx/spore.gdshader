shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

// Floating glow-spore points in the jungle basin. Additive, dim — not neon.

uniform vec3 glow : source_color = vec3(0.45, 0.75, 0.55);
uniform float intensity = 0.55;
uniform float pulse_speed = 1.6;

void fragment() {
	float s = 0.5 + 0.5 * sin(TIME * pulse_speed + FRAGCOORD.x * 0.02 + FRAGCOORD.y * 0.03);
	ALBEDO = glow * intensity * (0.55 + 0.45 * s);
	ALPHA = 0.6;
}
