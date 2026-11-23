shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Chest optic: dark coated glass with a glowing iris, aperture rings and a
// scan sweep. UV is planar over the lens cap (0.5,0.5 at center).

uniform vec4 glass_color : source_color = vec4(0.010, 0.012, 0.018, 1.0);
uniform vec4 iris_color : source_color = vec4(1.0, 0.14, 0.06, 1.0);
uniform float intensity = 3.4;
uniform float pupil_radius = 0.24;
uniform float iris_radius = 0.66;
uniform float ring_frequency = 62.0;
uniform float scan_speed = 1.15;
uniform float seed = 0.0;
uniform float alert = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float pupil = smoothstep(pupil_radius, pupil_radius * 0.72, r);
	float iris_band = smoothstep(iris_radius, iris_radius - 0.16, r) * smoothstep(pupil_radius * 0.82, pupil_radius * 1.05, r);
	float rings = pow(0.5 + 0.5 * cos(r * ring_frequency + TIME * 0.35), 20.0)
		* smoothstep(0.97, 0.30, r);
	float blades = pow(0.5 + 0.5 * sin(ang * 14.0 + r * 9.0), 30.0)
		* smoothstep(0.9, 0.22, r) * 0.7;
	float sweep = pow(0.5 + 0.5 * cos(ang - TIME * scan_speed + seed), 26.0)
		* smoothstep(0.92, 0.10, r);
	float vign = smoothstep(1.0, 0.78, r);
	ALBEDO = glass_color.rgb;
	METALLIC = 0.72;
	ROUGHNESS = 0.10;
	EMISSION = iris_color.rgb * intensity * (
		0.55 * pupil
		+ 0.85 * iris_band * (0.6 + 0.4 * sin(TIME * 2.2 + r * 8.0))
		+ rings * 1.1
		+ blades * 0.30
		+ sweep * 1.25
		+ alert * 0.9 * iris_band
	) * vign;
}