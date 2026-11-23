shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Inner optic ball: dark red machined metal with glowing latitude bands and
// seam lines. The ball is the part that rotates toward the viewer; the fixed
// outer shell is separate geometry. UV comes from MeshKit.arc_shell:
// UV.x = azimuth, UV.y = polar angle (0 at +Y pole, 1 at -Y pole).

uniform vec4 base_color : source_color = vec4(0.045, 0.006, 0.008, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.10, 0.03, 1.0);
uniform float intensity = 2.6;
uniform float band_count = 7.0;
uniform float seed = 0.0;

void fragment() {
	float lat = UV.y * PI;
	float bands = pow(0.5 + 0.5 * cos(lat * band_count + seed), 10.0);
	float thin = pow(0.5 + 0.5 * cos(lat * band_count * 2.0 + 0.7), 26.0);
	float seam = pow(0.5 + 0.5 * cos(UV.x * TAU * 8.0 + seed * 0.3), 30.0);
	float pulse = 0.82 + 0.18 * sin(TIME * 2.3 + seed);
	ALBEDO = base_color.rgb * (0.7 + 0.3 * bands);
	METALLIC = 0.72;
	ROUGHNESS = 0.30;
	SPECULAR = 0.45;
	EMISSION = glow_color.rgb * intensity * pulse * (0.30 + 0.70 * bands + 0.22 * thin + 0.16 * seam * bands);
}