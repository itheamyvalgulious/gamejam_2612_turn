// emit.gdshader — light strips / indicators / neon trim.
// style 0: plain emissive band, 1: segmented strip, 2: hazard chevrons (animated)
// u_* materials receive unit UVs.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, unshaded;

uniform vec3 col : source_color = vec3(1.0, 0.95, 0.85);
uniform float energy = 3.0;
uniform int style : hint_range(0, 2) = 0;
uniform float segs = 12.0;          // for style 1
uniform vec3 col_b : source_color = vec3(0.9, 0.2, 0.05);
uniform float scroll = 0.0;         // chevron scroll speed

void fragment() {
	vec3 c = col;
	float e = energy;
	if (style == 1) {
		// segmented light bar: lit cells + dark separators
		float f = fract(UV.x * segs);
		float on = step(0.12, f);
		c *= mix(0.12, 1.0, on);
		e *= mix(0.15, 1.0, on);
	} else if (style == 2) {
		// warning chevrons scrolling along U
		float f = fract(UV.x * segs - TIME * scroll + UV.y * 0.5);
		float ch = step(0.5, f);
		c = mix(col, col_b, ch);
		e = energy * (0.6 + 0.4 * sin(TIME * 2.0));
	}
	ALBEDO = c * 0.4;
	EMISSION = c * e;
}
