shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Small attitude-jet plume for the shoulders, spine, calves and soles.
// UV.x across, UV.y = 0 nozzle .. 1 tail.  Instance seed gives each vent a
// different flicker; fx_boost raises output when the swarm is dispersed.

uniform vec4 hot_color : source_color = vec4(1.0, 0.88, 0.66, 1.0);
uniform vec4 flame_color : source_color = vec4(1.0, 0.20, 0.03, 1.0);
uniform float intensity = 3.4;
uniform float flicker_speed = 26.0;
uniform float length_power = 1.7;
instance uniform float fx_seed = 0.0;
instance uniform float fx_boost = 0.0;

void fragment() {
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = clamp(UV.y, 0.0, 1.0);
	float plume = pow(max(across, 0.0), 1.4) * pow(max(1.0 - along, 0.0), length_power);
	float core = pow(max(across, 0.0), 3.0) * pow(max(1.0 - along, 0.0), 4.0);
	float fl = 0.70 + 0.30 * sin(TIME * flicker_speed + fx_seed * 37.0)
		* sin(TIME * flicker_speed * 0.33 + fx_seed * 11.0);
	ALBEDO = mix(flame_color.rgb, hot_color.rgb, clamp(core * 2.0, 0.0, 1.0))
		* intensity * (1.0 + fx_boost) * fl;
	ALPHA = clamp(plume * (1.1 + fx_boost * 0.6) * fl, 0.0, 1.0);
}
