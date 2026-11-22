shader_type spatial;
// 斩击弧 / 刀气。UV.x 沿弧长（0 -> 1 为挥砍方向），UV.y 为径向（内 -> 外）。
// 效果：月牙形渐细两端 + 外侧亮刃线 + 沿弧长前进的"刃口"亮带 + 后方拖尾 + 撕裂边缘。
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0, 0.45, 0.14, 1.0);
uniform float energy = 1.8;
uniform float progress = 0.0;   // 生命周期 0..1
uniform float tear = 0.55;      // 撕裂强度 0..1
uniform float trail_len = 0.85; // 拖尾长度（弧长比例）

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		s += amp * vnoise(p);
		p *= 2.07;
		amp *= 0.5;
	}
	return s;
}

void fragment() {
	vec2 uv = UV;
	// 两端渐细 -> 月牙
	float taper = smoothstep(0.0, 0.24, uv.x) * (1.0 - smoothstep(0.76, 1.0, uv.x));
	// 径向包络：外侧厚、内侧收成薄刃
	float body = smoothstep(0.0, 0.34, uv.y) * (1.0 - smoothstep(0.80, 1.02, uv.y));

	// 刃口沿挥砍方向前进
	float head = progress * 1.28;
	float lead = 1.0 - smoothstep(head, head + 0.10, uv.x);
	float behind = smoothstep(head - trail_len, head, uv.x);

	// 沿弧长的能量细纹（保持连续，不做成虚线）
	float streak = 0.74 + 0.32 * vnoise(vec2(uv.x * 12.0, uv.y * 3.0 + progress * 8.0));
	// 撕裂：只削外缘，做出能量刃的毛边
	float torn = 1.0 - tear * smoothstep(0.45, 1.0, fbm(vec2(uv.x * 20.0, uv.y * 6.0)))
		* smoothstep(0.30, 1.0, uv.y);
	// 外缘亮刃线
	float edge_line = (1.0 - smoothstep(0.0, 0.20, abs(uv.y - 0.78))) * behind;

	float band = lead * 1.55 + behind * 0.30;
	float a = taper * (body * band * streak + edge_line * 1.1) * torn * energy;
	ALBEDO = color.rgb * (0.7 + 1.7 * lead) * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
