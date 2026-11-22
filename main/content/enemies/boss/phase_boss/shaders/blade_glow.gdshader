shader_type spatial;
// Additive plasma envelope around the blade core.  Fresnel makes the silhouette
// flare, which fakes volumetric bloom even without a screen-space effect.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0, 0.34, 0.05, 1.0);
uniform float strength = 1.0;
uniform float flicker = 0.12;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 2.2);
	float along = smoothstep(0.0, 0.06, UV.y) * (1.0 - smoothstep(0.86, 1.0, UV.y) * 0.5);
	float flutter = 0.88 + flicker * sin(TIME * 34.0 + UV.y * 21.0);
	ALBEDO = color.rgb * strength * (0.22 + 1.1 * rim) * along * flutter * 2.0;
	ALPHA = (0.045 + 0.22 * rim) * along * flutter;
}