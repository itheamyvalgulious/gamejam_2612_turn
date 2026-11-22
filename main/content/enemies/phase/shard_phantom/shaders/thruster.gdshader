shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Thruster plume for a cone/quad mesh pointing along -Y of its node.
// UV.x around the plume, UV.y = 0 nozzle .. 1 tail. Per-instance tint via
// `instance uniform` so hundreds of modules keep individual flicker.

uniform vec4 hot_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform vec4 flame_color : source_color = vec4(1.0, 0.30, 0.05, 1.0);
uniform float intensity = 3.2;
uniform float flicker_speed = 17.0;
uniform float length_power = 1.7;
uniform float seed = 0.0;
instance uniform float fx_seed = 0.0;
instance uniform vec4 fx_tint : source_color = vec4(1.0, 0.34, 0.06, 1.0);

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = 1.0 - UV.y;
	float plume = pow(max(across, 0.0), 1.35) * pow(max(along, 0.0), length_power);
	float core = pow(max(across, 0.0), 2.6) * pow(max(along, 0.0), 4.0);
	float fl = 0.72 + 0.28 * sin(TIME * flicker_speed + (seed + fx_seed) * 41.0)
		* sin(TIME * flicker_speed * 0.37 + (seed + fx_seed) * 13.0);
	vec3 tint = mix(flame_color.rgb, fx_tint.rgb, 0.65);
	ALBEDO = mix(tint, hot_color.rgb, clamp(core * 1.6, 0.0, 1.0)) * intensity * fl;
	ALPHA = clamp(plume * 1.25 * fl, 0.0, 1.0);
}