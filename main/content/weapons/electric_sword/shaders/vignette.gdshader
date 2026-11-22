shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec2 uv = UV;
	vec2 v = (uv - 0.5) * vec2(1.03, 0.95);
	float vig = smoothstep(0.30, 0.82, length(v));
	float grain = fract(sin(dot(FRAGCOORD.xy + TIME, vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(vec3(0.0), vig * 0.52 + (grain - 0.5) * 0.012 * (1.0 - vig));
}