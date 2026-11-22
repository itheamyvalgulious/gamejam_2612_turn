shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Shuriken energy skin.  Planar UV over the star; additive, blade lobes rotate
// in the shader on top of the node spin so the energy never looks frozen.

uniform vec4 hot_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform vec4 energy_color : source_color = vec4(1.0, 0.24, 0.035, 1.0);
uniform float intensity = 3.4;
uniform float spin = 7.0;
uniform float seed = 0.0;
uniform float blades = 4.0;
uniform float charge = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float lobe = pow(0.5 + 0.5 * cos(ang * blades - TIME * spin + seed * 11.0), 2.2);
	float str = pow(0.5 + 0.5 * cos(ang * 23.0 + r * 17.0 - TIME * 21.0), 24.0)
		* smoothstep(1.0, 0.2, r);
	float core = smoothstep(0.38, 0.0, r);
	float rim = smoothstep(0.62, 1.0, r) * (1.0 - smoothstep(1.0, 1.06, r));
	float pulse = 0.78 + 0.22 * sin(TIME * 15.0 + seed * 30.0);
	vec3 col = mix(energy_color.rgb, hot_color.rgb, clamp(core * 1.2 + lobe * 0.32, 0.0, 1.0));
	ALBEDO = col * intensity * (1.0 + charge) * (0.62 + lobe * 0.65 + core * 1.15 + rim * 0.5) * pulse;
	ALPHA = clamp(core * 1.6 + lobe * 0.70 + str * 0.5 + rim * 0.22, 0.0, 1.0);
}