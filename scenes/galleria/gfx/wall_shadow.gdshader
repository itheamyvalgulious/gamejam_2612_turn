shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// 墙面影子：把一块墙当成「投影幕」——影子遮罩由一条正交/透视相机从墙外把场上角色
// 渲染进 SubViewport，这里按相机投影把遮罩贴回墙面。没有三角形并集、没有缝合缝。

uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform mat4 proj_mat;                       // 投影相机 view*projection
uniform vec4 shadow_color : source_color = vec4(0.004, 0.005, 0.010, 1.0);
uniform float intensity = 0.66;
uniform vec2 texel = vec2(0.0011111, 0.0033333);
uniform float soft_radius = 2.0;             // 柔化半径（texel）
uniform float shell_alpha = 0.34;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float mask_at(vec2 uv) {
	// 固定取 0 级 mip：墙面是掠射角，自动 mip 会把剪影糊掉一大圈
	return textureLod(mask_tex, uv, 0.0).a;
}

void fragment() {
	vec4 clip = proj_mat * vec4(wpos, 1.0);
	vec2 uv = (clip.xy / clip.w) * vec2(0.5, -0.5) + 0.5;
	float core = mask_at(uv);
	float halo = 0.0;
	if (soft_radius > 0.0) {
		vec2 o = texel * soft_radius;
		halo = max(halo, mask_at(uv + vec2(o.x, 0.0)));
		halo = max(halo, mask_at(uv - vec2(o.x, 0.0)));
		halo = max(halo, mask_at(uv + vec2(0.0, o.y)));
		halo = max(halo, mask_at(uv - vec2(0.0, o.y)));
		halo = max(halo, mask_at(uv + o));
		halo = max(halo, mask_at(uv - o));
	}
	float a = max(core, halo * shell_alpha);
	ALBEDO = shadow_color.rgb;
	ALPHA = clamp(a, 0.0, 1.0) * intensity;
}
