shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Assembly guide projected on the floor: a broken segmented ring, fine inward
// ticks and a faint dotted inner circle.  progress 0..1 drives the radius,
// alpha fades at both ends.  Deliberately quiet.

uniform vec4 tint : source_color = vec4(1.0, 0.22, 0.05, 1.0);
uniform float intensity = 1.0;
uniform float progress = 0.0;
uniform float alpha = 0.0;
uniform float thickness = 0.012;
uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float radius = mix(0.86, 0.20, clamp(progress, 0.0, 1.0));
	float ring = smoothstep(thickness, 0.0, abs(r - radius));
	float dashes = step(0.30, fract(ang / 6.28318 * 34.0 + seed));
	float ring2 = smoothstep(thickness * 0.55, 0.0, abs(r - radius * 0.86)) * 0.35;
	float ticks = smoothstep(0.0035, 0.0, abs(r - radius * 0.94))
		* step(0.62, fract(ang / 6.28318 * 72.0)) * 0.55;
	float dots = smoothstep(0.006, 0.0, abs(r - radius * 0.80))
		* step(0.86, fract(ang / 6.28318 * 24.0 + 0.5)) * 0.5;
	float inner = smoothstep(0.003, 0.0, abs(r - radius * 0.52)) * 0.22;
	float spokes = pow(0.5 + 0.5 * cos(ang * 6.0), 40.0) * smoothstep(radius, radius * 0.45, r) * 0.10;
	float fade = smoothstep(0.0, 0.10, alpha) * (1.0 - smoothstep(0.75, 1.0, alpha));
	float a = (ring * dashes + ring2 + ticks * dashes + dots + inner + spokes) * fade;
	ALBEDO = tint.rgb * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}