shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Micro-thruster plume: two crossed quads hanging off the inner face of every
// module.  UV.x across, UV.y = 0 nozzle .. 1 tail.  Drawn with a MultiMesh;
// INSTANCE_CUSTOM.x = flicker seed, .y = boost while dispersed.

uniform vec4 hot_color : source_color = vec4(1.0, 0.90, 0.72, 1.0);
uniform vec4 flame_color : source_color = vec4(1.0, 0.22, 0.035, 1.0);
uniform float intensity = 1.5;
uniform float flicker_speed = 22.0;
uniform float length_power = 1.9;

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	float seed = v_custom.x;
	float boost = v_custom.y;
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = clamp(UV.y, 0.0, 1.0);
	float plume = pow(max(across, 0.0), 1.5) * pow(max(1.0 - along, 0.0), length_power);
	float core = pow(max(across, 0.0), 3.2) * pow(max(1.0 - along, 0.0), 5.0);
	float fl = 0.70 + 0.30 * sin(TIME * flicker_speed + seed * 41.0)
		* sin(TIME * flicker_speed * 0.31 + seed * 13.0);
	vec3 tint = mix(flame_color.rgb, hot_color.rgb, clamp(core * 0.7, 0.0, 1.0));
	ALBEDO = mix(tint, hot_color.rgb, clamp(core * 1.6, 0.0, 1.0))
		* intensity * (1.0 + boost * 1.6) * fl;
	ALPHA = clamp(plume * (1.15 + boost * 0.9) * fl, 0.0, 1.0);
}