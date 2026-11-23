shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// ARC // SENTINEL — hard-light shield.
// The field is alive: ring pulses are BORN at the centre and travel outward to
// the rim, energy rises with radius, and the rim blooms. UV is planar radial.

uniform vec4 tint : source_color = vec4(0.66, 0.55, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.90, 0.84, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float opacity = 0.42;
uniform float ring_count = 6.0;
uniform float ring_bright = 0.55;
uniform float travel_speed = 0.20;
uniform float fresnel_power = 2.2;
uniform float impact = 0.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);

	// rings that travel outward: phase = r*N - time, so crests move to the rim
	float travel = TIME * travel_speed * ring_count;
	float ph1 = fract(r * ring_count - travel);
	float band1 = pow(1.0 - abs(ph1 - 0.5) * 2.0, 14.0);
	float ph2 = fract(r * ring_count * 2.0 - travel * 1.6 + 0.37);
	float band2 = pow(1.0 - abs(ph2 - 0.5) * 2.0, 30.0) * 0.55;
	// faint fine structure between the main pulses
	float micro = pow(0.5 + 0.5 * cos(r * ring_count * 7.0 - TIME * 0.9), 24.0)
		* smoothstep(0.98, 0.30, r) * 0.25;

	// energy rises toward the rim, plus an outer bloom
	float radial = 0.22 + 0.95 * r;
	float rim = smoothstep(0.88, 1.0, r);
	float rim_bloom = smoothstep(1.02, 0.93, r) * rim * 1.6;

	// slow rotational shimmer
	float shim = 0.5 + 0.5 * sin(ang * 9.0 + TIME * 0.45 + r * 14.0);
	float cells = pow(0.5 + 0.5 * cos(ang * 26.0 + seed), 18.0) * smoothstep(0.98, 0.15, r) * 0.10;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);

	// impact: an expanding, brightening wave from the centre
	float wave = fract(TIME * 0.9);
	float ripple = impact * pow(0.5 + 0.5 * cos((r * 4.0 - wave * 4.0) * 6.28318), 7.0)
		* smoothstep(1.0, 0.05, r) * (1.0 - wave);

	float energy = (band1 * ring_bright + band2 * ring_bright + micro) * radial
		+ rim_bloom * 0.5 + fres * 0.16 + shim * cells + ripple * 1.5;

	vec3 col = mix(tint.rgb, rim_color.rgb,
		clamp(band1 * 0.35 * radial + rim_bloom * 0.55 + ripple * 0.8, 0.0, 1.0));
	ALBEDO = col * (0.50 + 0.55 * energy) * (1.0 + impact * 0.5);
	ALPHA = clamp(opacity * 0.52 + energy * 0.42, 0.0, 0.90);
}
