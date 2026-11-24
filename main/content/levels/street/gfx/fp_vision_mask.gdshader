shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never,
	blend_mix, fog_disabled, skip_vertex_transform;

// 第一人称视野黑幕（第三人称下按 Tab）。
//
// 不是「屏幕上一个矩形/椭圆」，而是逐像素问一句：**这条视线真正打到的那个世界点，
// 第一人称相机看得见吗？** 看得见 → 透明；看不见 → 纯黑。
//
//   1) 用场景深度把本像素还原成世界坐标（depth → NDC → view → world）；
//   2) 把这个世界点投进第一人称相机的 clip 空间，|x|,|y|,|z| ≤ w 即在视锥内；
//   3) w ≤ 0（点在眼睛后面）、超出近/远平面、出画面，全部涂黑。
//
// 所以黑幕的形状就是「第一人称视锥」在第三人称画面里的逐像素截断，
// 和 Vision 的零余量规则同源：第一人称画面里能看到的东西，黑幕一定不盖它。

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform mat4 fp_proj_view;                              // 第一人称：projection * view
uniform vec4 mask_color : source_color = vec4(0.004, 0.006, 0.011, 1.0);
uniform float edge_soft = 0.008;                        // 视锥边界的柔化（clip 空间比例，0 = 硬边）
uniform float rim_width = 0.0;                          // 边界内侧描边宽度（同上单位，0 = 不画）
uniform vec4 rim_color : source_color = vec4(0.30, 0.86, 1.0, 1.0);
uniform float rim_gain = 0.5;

void vertex() {
	// 全屏四边形：顶点直接写 clip 空间（QuadMesh 2×2 → VERTEX.xy ∈ [-1,1]），
	// 不用管相机 FOV / 窗口宽高比，也不用跟着相机缩放。
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

void fragment() {
	// ---- 1) 本像素真正看到的世界点
	float d = texture(depth_tex, SCREEN_UV).x;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	vec3 wpos = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;

	// ---- 2) 它在第一人称画面里的位置
	//    mxy：0 = 画面中心，1 = 画面左右/上下边缘（可以做柔化 / 描边）
	//    mz ：near..far 深度方向（**总是 ≈1**：越远越贴近 1，只能做硬判定）
	vec4 c = fp_proj_view * vec4(wpos, 1.0);
	float a = 1.0;                                   // 眼睛后面：肯定看不见
	float mxy = 2.0;
	if (c.w > 0.0) {
		mxy = max(abs(c.x), abs(c.y)) / c.w;
		a = smoothstep(1.0 - edge_soft, 1.0, mxy);    // 视锥外纯黑，边界柔化
		if (abs(c.z) / c.w > 1.0) {
			a = 1.0;                                 // 比近裁剪面还近 / 超出远裁剪面
		}
	}

	// ---- 3) 可选：视锥边界内侧一圈描边（看清「画面边缘」在哪）
	vec3 col = mask_color.rgb;
	if (rim_width > 0.0 && a < 1.0) {
		float rim = 1.0 - smoothstep(0.0, rim_width, abs(mxy - 1.0));
		col = mix(col, rim_color.rgb, rim * rim_gain);
		a = max(a, rim * rim_gain * rim_color.a);
	}
	ALBEDO = col;
	ALPHA = a * mask_color.a;
}
