shader_type canvas_item;
// 屏幕闪白 / 受击红晕。径向渐隐 + 轻微扫描线，避免整屏死板平涂。
render_mode blend_mix;

uniform vec4 color : source_color = vec4(1.0, 0.4, 0.25, 1.0);
uniform float strength = 0.0;

void fragment() {
	vec2 p = SCREEN_UV * 2.0 - 1.0;
	float vig = clamp(1.0 - 0.62 * dot(p, p), 0.0, 1.0);
	float scan = 0.94 + 0.06 * sin(SCREEN_UV.y * 900.0);
	float a = clamp(strength, 0.0, 1.0) * vig * scan;
	COLOR = vec4(color.rgb, a);
}
