shader_type spatial;
// 地面 / 命中冲击环。UV 以中心为 (0.5,0.5)，r = |UV*2-1| = 1 在外缘。
// 效果：外缘环带 + 径向条纹（压力波）+ 中心余晖，随时间衰减。
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0, 0.62, 0.22, 1.0);
uniform float energy = 1.6;
uniform float progress = 0.0;
uniform float thickness = 0.24;
uniform float streaks = 18.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float inner = smoothstep(1.0 - thickness - 0.16, 1.0 - thickness, r);
	float outer = 1.0 - smoothstep(1.0 - 0.10, 1.0, r);
	float ring = inner * outer;

	float ang = atan(p.y, p.x);
	float streak = 0.55 + 0.45 * sin(ang * streaks + r * 5.0 - progress * 5.0);

	float fill = (1.0 - smoothstep(0.0, 0.92, r)) * 0.22 * (1.0 - progress);
	float a = (ring * streak + fill) * energy;
	ALBEDO = color.rgb * (0.55 + 1.5 * ring) * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
