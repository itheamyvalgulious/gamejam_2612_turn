shader_type spatial;
// Blade ribbon trail.  Vertex color carries age: rgb = plasma tint, alpha = fade.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform float energy = 2.2;

uniform bool silver_refraction = false;

void fragment() {
	float a = COLOR.a;
	if (silver_refraction) {
		// Close passes stay readable even when several parts of the arc overlap.
		a *= mix(0.10, 1.0, smoothstep(0.75, 2.65, -VERTEX.z));
		if (UV2.x < 0.5) {
			float radial = UV.x;
			float body = smoothstep(0.17, 0.89, radial);
			float refraction = clamp(UV2.y, 0.0, 1.0);
			float sliver = 1.0 - smoothstep(0.009, 0.036, abs(radial - mix(0.81, 0.68, refraction)));
			float echo = 1.0 - smoothstep(0.004, 0.029, abs(radial - mix(0.68, 0.56, refraction)));
			float facet = sliver + echo * 0.34;
			float bevel = smoothstep(0.956, 1.0, radial);
			vec3 glass = mix(vec3(0.15, 0.28, 0.78), vec3(0.24, 0.77, 1.0), body);
			ALBEDO = mix(glass, vec3(0.88, 0.98, 1.0), bevel * 0.92 + facet * 0.24) * energy;
			ALPHA = a * (0.08 + body * 0.22 + facet * 0.22 + bevel * 0.24);
		} else {
			// The edge band has two halves so the crest reads from either side.
			float across = UV2.x < 1.5 ? UV.y : 1.0 - UV.y;
			float silver = 1.0 - smoothstep(0.01, 0.20, across);
			ALBEDO = mix(vec3(0.27, 0.68, 1.0), vec3(0.95, 0.99, 1.0), silver) * energy;
			ALPHA = a * (0.14 + silver * 0.67);
		}
		ALBEDO *= COLOR.rgb;
	} else {
		ALBEDO = COLOR.rgb * a * energy;
		ALPHA = a;
	}
}