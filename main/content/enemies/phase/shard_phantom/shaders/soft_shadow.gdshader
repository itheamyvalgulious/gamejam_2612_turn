shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Soft elliptical contact shadow.  No texture: a radial falloff in UV space so
// the quad edge is guaranteed invisible.

uniform float strength = 0.75;
uniform float softness = 2.6;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = pow(max(0.0, 1.0 - r), softness);
	ALBEDO = tint.rgb;
	ALPHA = clamp(a * strength, 0.0, 1.0);
}
