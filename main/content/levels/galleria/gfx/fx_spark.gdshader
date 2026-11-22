shader_type spatial;
// 加色火花粒子（MultiMesh 实例化）。四边形在顶点着色器里做屏幕空间 billboard，
// 并沿速度方向拉长，形成"拖尾火星"而不是一个白球。
// COLOR          = 实例颜色（rgb 色调，a 生命周期衰减）
// INSTANCE_CUSTOM = (dir*0.5+0.5, stretch)  dir 为速度方向，stretch 0..1 -> 1..6 倍拉伸
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform float glow = 1.6;

void vertex() {
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 fwd = INV_VIEW_MATRIX[2].xyz;

	vec3 vdir = INSTANCE_CUSTOM.xyz * 2.0 - 1.0;
	vec2 d2 = vec2(dot(vdir, right), dot(vdir, up));
	vec2 along = length(d2) > 0.02 ? normalize(d2) : vec2(1.0, 0.0);
	vec2 perp = vec2(-along.y, along.x);

	float stretch = mix(1.0, 6.0, INSTANCE_CUSTOM.w);
	vec3 e1 = (right * along.x + up * along.y) * (size * stretch);
	vec3 e2 = (right * perp.x + up * perp.y) * size;

	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(e1, 0.0), vec4(e2, 0.0), vec4(fwd * size, 0.0),
		vec4(MODEL_MATRIX[3].xyz, 1.0));
}

void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p) * 2.0;
	float core = 1.0 - smoothstep(0.0, 0.42, d);
	float halo = 1.0 - smoothstep(0.0, 1.0, d);
	float a = (core + halo * 0.32) * COLOR.a;
	ALBEDO = COLOR.rgb * glow * (0.55 + 1.25 * core);
	ALPHA = clamp(a, 0.0, 1.0);
}
