shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Energy shield skin. UV is planar (0.5,0.5 at the dome center).
// Concentric rings + fresnel rim + slow interference sweep + impact ripple.

uniform vec4 tint : source_color = vec4(0.62, 0.52, 0.98, 1.0);
uniform vec4 rim_color : source_color = vec4(0.88, 0.82, 1.0, 1.0);
uniform float intensity = 1.45;
uniform float ring_count = 7.0;
uniform float ring_sharp = 16.0;
uniform float opacity = 0.55;
uniform float fresnel_power = 2.4;
uniform float impact = 0.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float rings = pow(0.5 + 0.5 * cos((r * ring_count - TIME * 0.22) * 6.28318), ring_sharp);
	float micro = pow(0.5 + 0.5 * cos(r * ring_count * 9.0 + TIME * 0.9), 24.0)
		* smoothstep(0.95, 0.25, r);
	float shim = 0.5 + 0.5 * sin(ang * 16.0 + TIME * 1.1 + r * 22.0 + seed);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float ripple = impact * (0.5 + 0.5 * cos((r * 9.0 - TIME * 7.0) * 6.28318))
		* smoothstep(1.0, 0.15, r);
	float border = smoothstep(0.88, 0.985, r) * (1.0 - smoothstep(0.985, 1.0, r));
	float a = opacity * (0.055 + 0.20 * rings + 0.10 * micro + 0.06 * shim
		+ 0.55 * fres + 0.85 * border + 0.55 * ripple);
	ALBEDO = mix(tint.rgb, rim_color.rgb, clamp(fres * 1.2 + border + ripple * 0.5, 0.0, 1.0))
		* intensity * (1.0 + impact * 0.8);
	ALPHA = clamp(a, 0.0, 1.0);
}