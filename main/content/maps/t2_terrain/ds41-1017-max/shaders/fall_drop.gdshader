shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Individual falling droplets: vertically stretched sprites that wrap inside a
// band, so the fall has real moving speckle instead of static dots.
// Per-vertex COLOR = (brightness, phase, speed, alpha).

uniform sampler2D drop_tex : filter_linear_mipmap, repeat_enable;
uniform float span = 30.0;
uniform float base_y = 292.0;
uniform float drop_speed = 26.0;

varying vec4 vcolv;
varying float vfade;

void vertex() {
	vcolv = COLOR;
	// The whole quad is pushed as one piece - wrapping per vertex would tear
	// the sprite across the whole band and print white petals in front of the
	// curtain.
	float fall = TIME * drop_speed * COLOR.b + COLOR.g * span;
	VERTEX.y -= fall;
	VERTEX.x += sin(TIME * 1.3 + COLOR.g * 31.0) * 0.25;
	vfade = 1.0;
}

void fragment() {
	float a = texture(drop_tex, UV).a;
	ALBEDO = vec3(0.95, 0.975, 0.99) * (0.78 + 0.38 * vcolv.r);
	ALPHA = clamp(a * vcolv.a * vfade, 0.0, 1.0);
	ROUGHNESS = 0.5;
}