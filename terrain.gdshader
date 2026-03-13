shader_type spatial;

uniform sampler2D noise_tex; // 细节噪声
uniform float sea_level = 0.0;

varying float v_height;
varying vec3 v_normal;

void vertex() {
	v_height = VERTEX.y;
	v_normal = NORMAL;
}

void fragment() {
	// --- 3A级地形颜色混合逻辑 ---
	vec3 color;
	float roughness = 0.8;
	
	// 采样宏观细节噪声
	float detail = texture(noise_tex, UV * 20.0).r * 0.2;
	
	if (v_height < -50.0) { // 深海 (马里亚纳海沟带)
		float deep_factor = clamp((v_height + 20000.0) / 15000.0, 0.0, 1.0);
		color = mix(vec3(0.02, 0.03, 0.08), vec3(0.1, 0.15, 0.2), deep_factor);
		roughness = 0.4; // 水底淤泥较平滑
	} else if (v_height < 2.0) { // 沙滩
		color = vec3(0.7, 0.6, 0.4) + detail;
	} else if (v_height < 3000.0) { // 草原/森林
		color = mix(vec3(0.15, 0.3, 0.1), vec3(0.2, 0.25, 0.15), detail * 5.0);
	} else if (v_height < 6000.0) { // 高山岩石 (珠峰基座)
		color = vec3(0.3, 0.3, 0.3) + detail;
		if (v_normal.y < 0.6) color *= 0.7; // 陡峭处变暗
	} else { // 巅峰积雪
		color = vec3(0.95, 0.98, 1.0);
		roughness = 0.2; // 冰晶反光
	}

	ALBEDO = color;
	ROUGHNESS = roughness;
	NORMAL = normalize(v_normal + vec3(detail * 0.1));
}