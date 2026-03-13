shader_type spatial;

// --- 关键修正 ---
// blend_add: 强制为“光照叠加”模式。即使代码出错，也只会不显示效果，绝不会覆盖成黑屏。
// skip_vertex_transform: 确保全屏覆盖。
render_mode unshaded, cull_disabled, depth_test_disabled, skip_vertex_transform, blend_add;

// 手机端专用接口 (Mali GPU 友好)
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// 参数调节
uniform float gi_intensity : hint_range(0.0, 3.0) = 0.8; // 强度：太大就会太白，建议 0.5 - 1.0
uniform float blur_level : hint_range(0.0, 5.0) = 3.0;   // 模糊度：3.0 模拟大气散射

void vertex() {
	// 强制拉伸网格覆盖全屏，不需要手动调整网格大小
	POSITION = vec4(VERTEX, 1.0);
}

void fragment() {
	// --- 极速 GI 算法 ---
	// 原理：不进行 8 次循环采样，而是直接读取显卡自动生成的“模糊层级”(Mipmap)
	// 这相当于 0 消耗获得了一个模糊的、平均的环境光颜色
	
	vec3 ambient_color = textureLod(screen_texture, SCREEN_UV, blur_level).rgb;
	
	// 增加一点对比度，让阴影处不要泛白
	ambient_color = pow(ambient_color, vec3(1.2));

	// 输出
	// 因为是 blend_add 模式，这个颜色会像光一样“加”在你的画面上
	ALBEDO = ambient_color * gi_intensity;
}