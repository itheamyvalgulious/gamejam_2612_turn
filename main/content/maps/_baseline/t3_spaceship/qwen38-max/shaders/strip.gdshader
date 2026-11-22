shader_type spatial;
render_mode unshaded, cull_disabled, specular_disabled;

// Emissive strips: lighting coves, door headers, route line with scrolling
// chevrons, hazard pulses. UV.x = along strip, UV.y = across (0..1).

uniform vec3 u_color = vec3(0.62, 0.85, 1.0);
uniform float u_gain = 2.4;
uniform float u_speed = 0.0;
uniform float u_arrow = 0.0;
uniform float u_phase = 0.0;
uniform float u_edge_fade = 1.0;
uniform float u_flicker = 0.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	float across = 1.0;
	if (u_edge_fade > 0.5) {
		across = smoothstep(0.0, 0.22, UV.y) * smoothstep(1.0, 0.78, UV.y);
	}
	float pulse = 0.92 + 0.08 * sin(TIME * 1.6 + u_phase);
	float pat = 1.0;
	if (u_arrow > 0.5) {
		float chev = abs(UV.y - 0.5) * 2.0;
		float ph = fract(UV.x * 1.6 - TIME * u_speed);
		float target = 0.5 - 0.22 * chev;
		pat = smoothstep(0.11, 0.035, abs(ph - target));
		pat = max(pat, 0.3);
		across = smoothstep(0.0, 0.12, UV.y) * smoothstep(1.0, 0.88, UV.y);
	}
	float fl = 1.0;
	if (u_flicker > 0.01) {
		float t = floor(TIME * 13.0);
		fl = 1.0 - u_flicker * step(0.86, hash11(t + u_phase * 9.0)) * hash11(t * 1.7);
	}
	ALBEDO = vec3(0.0);
	EMISSION = u_color * pat * across * pulse * fl * u_gain;
}
