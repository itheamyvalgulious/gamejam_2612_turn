shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Ground-plane shock ring / sweep ring. UV radial.

uniform vec4 tint : source_color = vec4(1.0, 0.65, 0.25, 1.0);
uniform float intensity = 2.4;
uniform float progress = 0.0;   // 0..1 expansion
uniform float thickness = 0.06;
uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float radius = 0.08 + progress * 0.9;
	float ring = smoothstep(thickness, 0.0, abs(r - radius));
	float trail = smoothstep(radius, radius - 0.35, r) * step(r, radius) * 0.22;
	float spoke = pow(0.5 + 0.5 * sin(atan(p.y, p.x) * 24.0 + seed * 9.0), 18.0)
		* smoothstep(radius, radius - 0.2, r) * step(r, radius);
	float fade = 1.0 - smoothstep(0.55, 1.0, progress);
	ALBEDO = tint.rgb * intensity * (1.0 + ring);
	ALPHA = clamp((ring * 0.95 + trail + spoke * 0.55) * fade, 0.0, 1.0);
}