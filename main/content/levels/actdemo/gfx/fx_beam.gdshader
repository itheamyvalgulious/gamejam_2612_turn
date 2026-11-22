shader_type spatial;
// 一次性光束 / 激光。网格沿 -Z 长度 1，UV.x = 0 起点 -> 1 终点，UV.y 横向 0..1。
// 效果：亮核 + 外辉光 + 两端收束 + 沿轴向流动的能量。
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0, 0.25, 0.6, 1.0);
uniform float energy = 2.2;
uniform float progress = 0.0;   // 0..1 单次光束用它衰减；持续光束保持 0
uniform float scroll = 1.0;
uniform float core = 3.0;
uniform float taper = 0.06;

void fragment() {
	float along = UV.x;
	float across = UV.y * 2.0 - 1.0;
	float ends = smoothstep(0.0, taper, along) * (1.0 - smoothstep(1.0 - taper, 1.0, along));
	float c = exp(-pow(abs(across) * core, 1.7));
	float g = exp(-pow(abs(across) * 1.15, 2.0));
	float flow = 0.78 + 0.22 * sin(along * 42.0 - TIME * 26.0 * scroll);
	float a = (g * 0.42 + c * 1.1) * ends * flow * energy * (1.0 - progress);
	ALBEDO = color.rgb * (1.0 + 1.9 * c) * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
