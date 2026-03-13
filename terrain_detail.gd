extends Node3D

# --- 💡 3A 曝光控制 & 环境修复 ---
func _ready():
	_fix_lighting_and_exposure()
	_apply_aaa_snow_material()

func _fix_lighting_and_exposure():
	# 1. 查找或创建 WorldEnvironment
	var env_node = get_node_or_null("WorldEnvironment")
	if not env_node:
		env_node = WorldEnvironment.new()
		add_child(env_node)
	
	var env = env_node.environment
	if not env:
		env = Environment.new()
		env_node.environment = env
	
	# 2. 【关键】解决过曝：使用 ACES 色调映射
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.7  # 压暗曝光，找回细节
	env.tonemap_white = 6.0     # 提高白点，允许更亮的高光存在但不死白
	
	# 3. 增加立体感：开启 SSAO (环境光遮蔽)
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 4.0    # 增强角落阴影
	env.ssao_power = 1.5
	
	# 4. 调整雾效：冷色调氛围雾
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.68, 0.75) # 蓝灰色
	env.fog_density = 0.0015
	env.volumetric_fog_enabled = true # 体积雾（如果性能允许）
	env.volumetric_fog_density = 0.01

	# 5. 修正太阳光：避免过硬的阴影
	var sun = get_node_or_null("DirectionalLight3D") # 假设你的太阳叫这个
	if sun:
		sun.light_energy = 1.2 # 降低强度，之前可能太高了
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_fade_start = 0.8
		sun.light_color = Color(1.0, 0.95, 0.9) # 暖日光，对比冷雾

# --- ❄️ 主机级雪地 Shader (纯代码注入) ---
func _apply_aaa_snow_material():
	# 找到地形节点（假设叫 TerrainDetail 或 chunks 里的网格）
	var terrain = get_node_or_null("TerrainDetail") 
	if not terrain: return # 找不到就跳过
	
	var mat = ShaderMaterial.new()
	mat.shader = _get_snow_shader()
	terrain.material_override = mat

func _get_snow_shader() -> Shader:
	var code = """
	shader_type spatial;
	
	// 主机级细节参数
	uniform float roughness : hint_range(0,1) = 0.3;
	uniform float specular : hint_range(0,1) = 0.5;
	uniform float sparkle_scale = 500.0; // 雪花闪光密度
	
	// 简单的噪声函数
	float hash(vec2 p) {
		return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
	}
	
	void fragment() {
		vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		
		// 1. 基础颜色：微微偏蓝的白雪
		vec3 snow_color = vec3(0.92, 0.94, 0.96);
		
		// 2. 核心细节：雪地闪光 (Sparkle)
		// 利用视线向量产生动态闪烁感
		vec2 sparkle_uv = world_pos.xz * sparkle_scale;
		float sparkle = hash(floor(sparkle_uv));
		// 只有当反光角度合适时才闪烁
		float view_dot = max(0.0, dot(normalize(VIEW), normalize(NORMAL)));
		float sparkle_intensity = pow(sparkle, 15.0) * 2.0 * view_dot;
		
		// 3. 细节纹理混合 (这里用噪声模拟粗糙表面)
		float noise = hash(world_pos.xz * 10.0);
		
		ALBEDO = snow_color + vec3(sparkle_intensity);
		
		// 4. PBR 参数
		ROUGHNESS = roughness + noise * 0.1; // 让表面不那么光滑
		SPECULAR = specular;
		
		// 5. 简单法线扰动 (模拟积雪凹凸)
		vec3 n = normalize(vec3(noise - 0.5, 1.0, noise - 0.5));
		NORMAL_MAP = n;
		NORMAL_MAP_DEPTH = 0.2;
	}
	"""
	var shader = Shader.new()
	shader.code = code
	return shader
