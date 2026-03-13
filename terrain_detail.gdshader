shader_type spatial;

// 顶级 3A 参数
uniform sampler2D detail_texture : source_color; // 细节贴图
uniform sampler2D detail_normal : hint_normal;  // 细节法线
uniform float detail_uv_scale = 20.0;           // 细节密集度
uniform float normal_intensity = 0.5;           // 法线强度

void fragment() {
    // 1. 获取世界坐标 UV（解决任何物体上的贴图对齐问题）
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec2 world_uv = world_pos.xz * detail_uv_scale * 0.05;

    // 2. 采样 3A 细节纹理
    vec3 alb = texture(detail_texture, world_uv).rgb;
    vec3 nrm = texture(detail_normal, world_uv).rgb;

    // 3. 动态光影与混合
    ALBEDO = alb;
    NORMAL_MAP = nrm;
    NORMAL_MAP_DEPTH = normal_intensity;

    // 4. 增加微小高光，模拟潮湿或岩石晶体感
    ROUGHNESS = 0.7;
    SPECULAR = 0.2;
}