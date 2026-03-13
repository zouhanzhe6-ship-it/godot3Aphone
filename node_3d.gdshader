shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform vec4 cloud_color : source_color = vec4(0.9, 0.9, 0.9, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.4;

void vertex() {
    // 关键：广告牌模式，让每一片云始终面向摄像机，营造体积感
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
    // 创建柔软的边缘
    float dist = length(UV - 0.5);
    float mask = smoothstep(0.5, 0.2, dist);

    // 基础颜色渲染
    ALBEDO = cloud_color.rgb;
    ALPHA = mask * density * COLOR.a; // 结合粒子生命周期透明度
}