shader_type spatial;
render_mode unshaded, cull_disabled, specular_disabled, blend_add;

// Hologram: fresnel shell + latitude/longitude wire + scanning bands.

uniform vec3 u_color = vec3(0.35, 0.9, 1.0);
uniform float u_gain = 0.85;
uniform float u_scan_speed = 1.4;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 nrm = normalize(NORMAL);
	float fres = pow(1.0 - abs(dot(nrm, normalize(VIEW))), 1.6);
	float lat = 1.0 - smoothstep(0.02, 0.045, abs(fract(wpos.y * 9.0 - TIME * u_scan_speed * 0.25) - 0.5) - 0.44);
	float lon = 1.0 - smoothstep(0.02, 0.05, abs(fract(atan(wpos.z, wpos.x) * 2.6) - 0.5) - 0.45);
	float scan = exp(-pow(fract(wpos.y * 1.4 - TIME * u_scan_speed) * 6.0, 2.0)) * 0.8;
	float flick = 0.85 + 0.15 * sin(TIME * 33.0) * sin(TIME * 7.3);
	float i = (fres * 0.9 + lat * 0.22 + lon * 0.16 + scan * 0.3) * flick;
	ALBEDO = vec3(0.0);
	EMISSION = u_color * i * u_gain;
}
