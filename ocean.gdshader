shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled, depth_draw_always;

// --- 🎨 3A 基础参数 ---
uniform vec3 deep_color : source_color = vec3(0.002, 0.01, 0.03);
uniform vec3 shallow_color : source_color = vec3(0.05, 0.25, 0.3);
uniform vec3 foam_color : source_color = vec3(0.98, 0.98, 1.0);
uniform vec3 sss_color : source_color = vec3(0.0, 0.8, 0.6);

// --- ☀️ 环境参数 ---
uniform float sun_altitude = 1.0;
uniform float wave_speed = 0.2;
uniform float wave_height = 0.5;

// --- 🌊 物理交互参数 ---
uniform vec3 player_pos = vec3(0.0);
uniform float interact_strength = 0.5;
uniform float interact_radius = 2.0;

// --- 🗺️ 纹理 ---
uniform sampler2D normal_noise : hint_normal;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// --- 🌊 基础波浪函数 ---
vec3 gerstner_wave(vec2 uv, float time, vec2 dir, float steepness, float wavelength, inout vec3 tangent, inout vec3 binormal) {
    float k = 2.0 * 3.14159 / wavelength;
    float c = sqrt(9.8 / k);
    vec2 d = normalize(dir);
    float f = k * (dot(d, uv) - c * time);
    float a = clamp(steepness, 0.0, 0.3 / k) / k;
    float sin_f = sin(f);
    float cos_f = cos(f);
    vec3 p = vec3(d.x * (a * cos_f), a * sin_f, d.y * (a * cos_f));
    float wa_cos = k * a * cos_f;
    float wa_sin = k * a * sin_f;
    tangent += vec3(-d.x * d.x * wa_sin, d.x * wa_cos, -d.x * d.y * wa_sin);
    binormal += vec3(-d.x * d.y * wa_sin, d.y * wa_cos, -d.y * d.y * wa_sin);
    return p;
}

// 传递给 fragment 的变量
varying float v_wave_height;
varying vec3 v_world_pos;
varying float v_interaction_mask; // 传递交互区域强度

void vertex() {
    float time = TIME * wave_speed;
    vec3 tangent = vec3(1.0, 0.0, 0.0);
    vec3 binormal = vec3(0.0, 0.0, 1.0);
    vec2 world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    vec3 p = VERTEX;
    
    // 1. 基础海浪
    p += gerstner_wave(world_xz, time, vec2(1.0, 0.1), 0.12, 60.0, tangent, binormal) * wave_height;
    p += gerstner_wave(world_xz, time, vec2(0.4, 0.7), 0.08, 25.0, tangent, binormal) * wave_height;
    
    // --- 💥 物理溅射核心逻辑 ---
    float dist = distance(v_world_pos.xz, player_pos.xz);
    float interaction = 0.0;
    
    // 计算交互范围
    if (dist < interact_radius) {
        // 创建向外扩散的波
        float ripple = sin(dist * 8.0 - TIME * 15.0);
        float decay = smoothstep(interact_radius, 0.0, dist);
        
        // 【关键】修复错误：在顶点着色器中使用 textureLod 读取噪声
        // 这里的噪声用来模拟水花炸开的随机尖刺
        float splash_noise = textureLod(normal_noise, world_xz * 0.5 + TIME * 2.0, 0.0).r;
        
        // 溅射高度：结合正弦波和高频噪声
        // 当 ripple 处于波峰时，叠加尖刺，看起来像水炸开了
        float splash_spike = max(0.0, ripple) * splash_noise * 1.5;
        
        interaction = (ripple + splash_spike) * decay * interact_strength;
    }
    
    p.y += interaction;
    v_interaction_mask = smoothstep(0.0, 0.5, abs(interaction)); // 记录哪里发生了激烈碰撞

    // 重新计算法线
    vec3 normal = normalize(cross(binormal, tangent));
    // 交互区域法线扰动
    if (interaction != 0.0) {
        vec3 push_dir = normalize(v_world_pos - player_pos);
        normal = mix(normal, vec3(0.0, 1.0, 0.0) + push_dir * interaction, 0.6);
    }

    VERTEX = p;
    NORMAL = normal;
    v_wave_height = p.y;
}

void fragment() {
    float night_factor = clamp(sun_altitude, 0.1, 1.0);

    // 1. 深度计算
    float depth_raw = texture(depth_texture, SCREEN_UV).r;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
    vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view_pos.xyz /= view_pos.w;
    float linear_depth = -view_pos.z;
    float water_depth = clamp((linear_depth - VERTEX.z) * 0.5, 0.0, 1.0);

    // 2. 润湿张力法线 (Wetting Tension)
    vec2 uv_world = v_world_pos.xz * 0.05;
    // 采样两次噪声做流动
    vec3 n1 = texture(normal_noise, uv_world + vec2(TIME * 0.03, TIME * 0.01)).rgb;
    vec3 n2 = texture(normal_noise, uv_world * 0.5 - vec2(TIME * 0.02, TIME * 0.02)).rgb;
    
    // 【关键】溅射区域使用更剧烈的法线扰动，模拟水珠乱飞的视觉错觉
    vec3 splash_normal = texture(normal_noise, uv_world * 5.0 + vec2(0.0, TIME)).rgb; // 高速流动
    vec3 base_normal = normalize(vec3(n1.xy + n2.xy - 1.0, n1.z * n2.z * 1.5));
    
    // 如果有交互，混合高速溅射法线
    vec3 final_normal = mix(base_normal, splash_normal, v_interaction_mask * 0.8);
    
    NORMAL_MAP = final_normal;
    NORMAL_MAP_DEPTH = mix(0.8, 0.1, water_depth) * 0.5;

    // 3. 次表面散射
    float sss_intensity = max(0.0, dot(normalize(VIEW), -NORMAL)) * 2.0;
    vec3 scatter = sss_color * pow(sss_intensity, 4.0) * sun_altitude * 0.5;

    // 4. 颜色与泡沫
    vec3 water_col = mix(shallow_color, deep_color, water_depth);
    
    // 【关键】修复错误：sampler2D 采样修正
    // 泡沫生成逻辑
    float noise_val = texture(normal_noise, uv_world * 3.0).r; // 👈 修复了这里
    float foam_mask = smoothstep(0.4, 0.6, v_wave_height - 0.2);
    foam_mask += smoothstep(0.85, 0.95, 1.0 - noise_val);
    
    // 交互区域强制产生大量白沫 (Splash Foam)
    float splash_foam = v_interaction_mask * texture(normal_noise, uv_world * 10.0 + TIME * 5.0).r;
    
    float final_foam = clamp(foam_mask * 0.5 + splash_foam * 2.0, 0.0, 1.0);

    // 合成
    vec3 final_albedo = mix(water_col, foam_color, final_foam);
    final_albedo += scatter;
    
    ALBEDO = final_albedo * night_factor;
    METALLIC = 0.0;
    SPECULAR = 0.5;
    
    // 5. 润湿感粗糙度
    // 溅射区域极其光滑（模拟水珠），普通波浪有质感
    float wet_roughness = mix(0.2, 0.02, v_interaction_mask); // 交互处像镜子一样
    ROUGHNESS = mix(wet_roughness, 0.8, final_foam * 0.5);
    
    ALPHA = clamp(water_depth + 0.2 + final_foam + v_interaction_mask, 0.0, 1.0);
    
    // 折射
    vec2 screen_uv_offset = final_normal.xy * 0.02 * (1.0 - water_depth);
    EMISSION = texture(screen_texture, SCREEN_UV + screen_uv_offset).rgb * 0.1;
}