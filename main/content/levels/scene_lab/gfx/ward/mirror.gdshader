shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;

// 平面镜：把「镜像相机」渲染出的画面按投影纹理贴回镜面。
// mirror_matrix = 镜像相机的 projection * view，顶点处换算成裁剪坐标再除以 w。
uniform sampler2D mirror_tex : source_color, filter_linear;
uniform mat4 mirror_matrix;
uniform vec3 tint : source_color = vec3(0.94, 0.99, 0.96);
uniform float dim = 0.88;

varying vec4 clip_pos;

void vertex() {
    clip_pos = mirror_matrix * (MODEL_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
    vec2 uv = clip_pos.xy / max(abs(clip_pos.w), 0.0001) * 0.5 + 0.5;
    uv.y = 1.0 - uv.y;   // 视口纹理的 V 轴与裁剪空间 Y 相反，不翻会上下颠倒
    if (clip_pos.w <= 0.0 || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        ALBEDO = vec3(0.020, 0.024, 0.023);
    } else {
        // 镜像画面在主视口里会被再 tonemap 一次，直接贴会发灰发白：这里先提对比再压暗
        vec3 c = clamp(texture(mirror_tex, uv).rgb, 0.0, 1.0);
        c = pow(c, vec3(1.75));
        ALBEDO = c * tint * dim;
    }
}
