shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Soft orange pool on the floor under the hovering body / the swarm.
// Radial UV over a quad; slow breathing plus faint concentric scan.

uniform vec4 tint : source_color = vec4(1.0, 0.20, 0.035, 1.0);
uniform float intensity = 0.5;
uniform float falloff = 5.5;
uniform float progress = 0.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float pool = exp(-r * r * 9.0);
	float hot = exp(-r * r * 26.0);
	float pulse = 0.78 + 0.22 * sin(TIME * 2.1 + seed * 4.0);
	float a = (pool * 0.50 + hot * 0.55) * pulse * (0.35 + progress * 0.75);
	ALBEDO = tint.rgb * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}