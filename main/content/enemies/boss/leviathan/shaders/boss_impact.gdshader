shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.30, 0.06, 1.0);
uniform float intensity = 1.0;
uniform float progress = 0.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float ring = smoothstep(0.92, 0.70, r) * smoothstep(0.42, 0.64, r);
	float rays = pow(0.5 + 0.5 * cos(ang * 18.0 + seed), 12.0) * smoothstep(1.0, 0.2, r);
	float fade = 1.0 - progress;
	ALBEDO = vec3(0.0);
	EMISSION = tint.rgb * (ring * 2.2 + rays * 1.2) * intensity * fade;
	ALPHA = clamp((ring * 0.8 + rays * 0.4) * fade, 0.0, 1.0);
}
