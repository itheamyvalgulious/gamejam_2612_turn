shader_type canvas_item;
render_mode unshaded;

// Screen finish: vignette, fine scanlines, grain and a hint of lens
// aberration. Applied on a full-rect ColorRect above the 3D view.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float vignette = 0.55;
uniform float vignette_width = 1.35;
uniform float scan_amount = 0.022;
uniform float grain = 0.016;
uniform float aberration = 0.6;
uniform float tint_shift = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - 0.5;
	vec2 off = dir * aberration * 0.0016;
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;
	float d = length(dir) * vignette_width;
	float vig = smoothstep(1.0, 0.30, d);
	col *= mix(1.0 - vignette, 1.0, vig);
	col *= 1.0 - scan_amount * (0.5 + 0.5 * sin(FRAGCOORD.y * 1.7 + TIME * 1.6));
	float n = hash(FRAGCOORD.xy + floor(TIME * 24.0) * 13.7);
	col += (n - 0.5) * grain;
	col = mix(col, col * vec3(0.96, 1.0, 1.04), tint_shift);
	COLOR = vec4(col, 1.0);
}