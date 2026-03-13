extends Node3D

# --- 🔧 参数设置 ---
@export var block_size: float = 1.0        
@export var paint_range: float = 8.0       
@export var custom_material: StandardMaterial3D 

# --- ⚙️ 内部变量 ---
var raycast: RayCast3D
var parent_node: Node 
var preview_mesh: MeshInstance3D
var ui_layer: CanvasLayer

# 材质缓存
var concrete_material: StandardMaterial3D

# ⏱️ 冷却系统 (防卡死核心)
var can_build: bool = true
var build_timer: Timer

func _ready():
	# 1. 初始化射线
	raycast = RayCast3D.new()
	raycast.target_position = Vector3(0, 0, -paint_range)
	raycast.enabled = true
	add_child(raycast)
	
	# 2. 找到根节点
	parent_node = get_tree().root.get_child(0)
	
	# 3. 初始化冷却计时器
	build_timer = Timer.new()
	build_timer.wait_time = 0.15 # 0.15秒冷却，既流畅又不卡
	build_timer.one_shot = true
	build_timer.timeout.connect(func(): can_build = true)
	add_child(build_timer)
	
	# 4. 生成低配版高清材质
	_generate_concrete_material()
	
	# 5. 创建界面
	_create_preview()
	_create_ui()

# --- 🧪 性能优化版材质生成 ---
func _generate_concrete_material():
	if custom_material:
		concrete_material = custom_material
		return

	print("正在生成优化版混凝土纹理...")
	
	# 1. 噪点
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.2 
	
	# 2. 颜色纹理 (大幅降低分辨率到 64x64)
	var tex_albedo = NoiseTexture2D.new()
	tex_albedo.width = 64  # [性能关键] 手机端 64 足够了
	tex_albedo.height = 64
	tex_albedo.noise = noise
	tex_albedo.seamless = true 
	
	# 3. 法线贴图 (最耗性能的部分，同样降分辨率)
	var tex_normal = NoiseTexture2D.new()
	tex_normal.width = 64 # [性能关键]
	tex_normal.height = 64
	tex_normal.noise = noise
	tex_normal.seamless = true
	tex_normal.as_normal_map = true 
	tex_normal.bump_strength = 2.0  
	
	# 4. 材质
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.62, 0.65)
	mat.albedo_texture = tex_albedo 
	mat.normal_enabled = true
	mat.normal_texture = tex_normal
	mat.roughness = 1.0 # 完全粗糙，减少反光计算
	mat.uv1_scale = Vector3(1.0, 1.0, 1.0) 
	
	concrete_material = mat

# --- 🖥️ UI (保持不变) ---
func _create_ui():
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	var control = Control.new()
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_PASS 
	ui_layer.add_child(control)
	
	var btn_build = Button.new()
	btn_build.text = "🧱 建造"
	btn_build.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn_build.position = Vector2(-240, -120)
	btn_build.size = Vector2(100, 80)
	btn_build.pressed.connect(_on_build_pressed)
	control.add_child(btn_build)
	
	var btn_break = Button.new()
	btn_break.text = "🔨 拆除"
	btn_break.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn_break.position = Vector2(-120, -120)
	btn_break.size = Vector2(100, 80)
	btn_break.pressed.connect(_on_break_pressed)
	control.add_child(btn_break)

# --- 🏗️ 逻辑 ---
func _create_preview():
	preview_mesh = MeshInstance3D.new()
	preview_mesh.mesh = BoxMesh.new()
	preview_mesh.mesh.size = Vector3(block_size, block_size, block_size)
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.0, 1.0, 0.0, 0.4)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_mesh.material_override = mat
	preview_mesh.visible = false
	add_child(preview_mesh)

func _physics_process(delta):
	raycast.force_raycast_update()
	if raycast.is_colliding():
		preview_mesh.visible = true
		var point = raycast.get_collision_point()
		var normal = raycast.get_collision_normal()
		var target_pos = point + normal * (block_size * 0.5)
		var snapped_pos = target_pos.snapped(Vector3(block_size, block_size, block_size))
		preview_mesh.global_position = snapped_pos
		preview_mesh.global_rotation = Vector3.ZERO
	else:
		preview_mesh.visible = false

# --- 🎮 按钮响应 ---

func _on_build_pressed():
	# 检查冷却
	if not can_build: return
	if not raycast.is_colliding(): return
	
	if preview_mesh.visible:
		var pos = preview_mesh.global_position
		if _check_overlap(pos): return
		
		_spawn_block(pos)
		
		# 触发冷却
		can_build = false
		build_timer.start()

func _on_break_pressed():
	if not can_build: return # 拆除也加冷却
	if not raycast.is_colliding(): return
	
	var object = raycast.get_collider()
	if object.is_in_group("Voxel"):
		object.get_parent().queue_free()
		
		can_build = false
		build_timer.start()

func _spawn_block(pos: Vector3):
	var block = MeshInstance3D.new()
	block.mesh = BoxMesh.new()
	block.mesh.size = Vector3(block_size, block_size, block_size)
	
	# [性能优化] 关闭阴影投射
	block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	if concrete_material:
		block.material_override = concrete_material
		
	var body = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(block_size, block_size, block_size)
	shape.shape = box
	
	block.add_child(body)
	body.add_child(shape)
	body.add_to_group("Voxel")
	
	parent_node.add_child(block)
	block.global_position = pos

func _check_overlap(pos: Vector3) -> bool:
	var params = PhysicsPointQueryParameters3D.new()
	params.position = pos
	# [性能优化] 缩小检测掩码，只检测必须的层
	params.collision_mask = 1 
	var result = get_world_3d().direct_space_state.intersect_point(params)
	return result.size() > 0
