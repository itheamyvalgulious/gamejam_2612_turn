shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Additive laser beam. UV.y runs along the beam.

uniform vec4 core_color : source_color = vec4(1.0, 0.88, 0.76, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.10, 0.015, 1.0);
uniform float intensity = 1.0;
uniform float seed = 0.0;
uniform float flow_speed = 22.0;
uniform float core_power = 1.0;

varying vec2 luv;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	luv = UV;
}

void fragment() {
	float along = luv.y;
	float r = abs(luv.x - 0.5) * 2.0;
	float core = smoothstep(0.42, 0.0, r);
	float glow = smoothstep(1.0, 0.15, r);
	float flow = 0.62 + 0.38 * sin(along * 62.0 - TIME * flow_speed + seed);
	float flow2 = 0.75 + 0.25 * sin(along * 17.0 + TIME * 7.0 + seed * 2.3);
	float spark = smoothstep(0.78, 1.0, hash21(vec2(floor(along * 190.0), floor(TIME * 30.0) + seed)));
	float flick = 0.9 + 0.1 * sin(TIME * 83.0 + seed * 11.0);
	vec3 col = edge_color.rgb * glow * 1.35 + core_color.rgb * core * (2.2 + 1.4 * core_power);
	ALBEDO = col * flow * flow2 * intensity * flick + core_color.rgb * spark * 1.6 * core;
	EMISSION = vec3(0.0);
	ALPHA = clamp(glow * 0.55 + core * 0.8, 0.0, 1.0);
}
