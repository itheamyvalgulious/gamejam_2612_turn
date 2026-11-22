shader_type canvas_item;
// Vignette + very light scanline / grain pass for the HUD layer.
render_mode unshaded;

uniform float vignette = 0.55;
uniform float scanline = 0.020;
uniform float grain = 0.012;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float v = 1.0 - smoothstep(0.42, 1.38, length(p * vec2(1.0, 0.92)));
	float a = (1.0 - v) * vignette;
	a += scanline * (0.5 + 0.5 * sin(UV.y * 1500.0));
	a += grain * hash(UV * vec2(1920.0, 1080.0) + TIME);
	a += smoothstep(0.26, 0.0, UV.y) * 0.22;
	a += smoothstep(0.80, 1.0, UV.y) * 0.10;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(a, 0.0, 1.0));
}