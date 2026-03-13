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

# ⏱️ 冷却系统
var can_build: bool = true
var build_timer: Timer

func _ready():
	# 1. 初始化射线
	raycast = RayCast3D.new()
	raycast.target_position = Vector3(0, 0, -paint_range)
	raycast.enabled = true
	add_child(raycast)
	
	# 2. 找到根节点 (适配 DataManager 所在的 node_3d)
	parent_node = get_tree().root.get_child(0)
	
	# 3. 初始化冷却计时器
	build_timer = Timer.new()
	build_timer.wait_time = 0.15 
	build_timer.one_shot = true
	build_timer.timeout.connect(func(): can_build = true)
	add_child(build_timer)
	
	# 4. 生成优化材质
	_generate_concrete_material()
	
	# 5. 创建界面与预览
	_create_preview()
	_create_ui()

# --- 🧪 性能优化版材质生成 (去除所有外部依赖) ---
func _generate_concrete_material():
	if custom_material:
		concrete_material = custom_material
		return

	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.2 
	
	var tex_albedo = NoiseTexture2D.new()
	tex_albedo.width = 64 
	tex_albedo.height = 64
	tex_albedo.noise = noise
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.62, 0.65)
	mat.albedo_texture = tex_albedo 
	mat.roughness = 1.0
	concrete_material = mat

# --- 🖥️ UI (修复字体报错与层级) ---
func _create_ui():
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10 # 确保建造 UI 在联机 UI (layer 100) 的下面
	add_child(ui_layer)
	
	var control = Control.new()
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_PASS 
	ui_layer.add_child(control)
	
	# 🧱 建造按钮
	var btn_build = Button.new()
	btn_build.text = "建造" # 删除了特殊字符，确保兼容性
	btn_build.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# 适配手机屏幕位置
	btn_build.position = Vector2(-300, -150)
	btn_build.size = Vector2(120, 100)
	btn_build.button_down.connect(func(): _set_preview_visible(true))
	btn_build.button_up.connect(func(): _on_build_pressed(); _set_preview_visible(false))
	control.add_child(btn_build)
	
	# 🔨 拆除按钮
	var btn_break = Button.new()
	btn_break.text = "拆除"
	btn_break.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn_break.position = Vector2(-150, -150)
	btn_break.size = Vector2(120, 100)
	btn_break.button_down.connect(func(): _set_preview_visible(true))
	btn_break.button_up.connect(func(): _on_break_pressed(); _set_preview_visible(false))
	control.add_child(btn_break)

# --- 🏗️ 逻辑 ---
func _create_preview():
	preview_mesh = MeshInstance3D.new()
	preview_mesh.mesh = BoxMesh.new()
	preview_mesh.mesh.size = Vector3(block_size, block_size, block_size)
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.0, 1.0, 0.0, 0.4)
	preview_mesh.material_override = mat
	preview_mesh.visible = false
	add_child(preview_mesh)

func _set_preview_visible(v: bool):
	preview_mesh.visible = v

func _physics_process(_delta):
	if preview_mesh.visible:
		raycast.force_raycast_update()
		if raycast.is_colliding():
			var point = raycast.get_collision_point()
			var normal = raycast.get_collision_normal()
			var target_pos = point + normal * (block_size * 0.5)
			var snapped_pos = target_pos.snapped(Vector3(block_size, block_size, block_size))
			preview_mesh.global_position = snapped_pos
		else:
			preview_mesh.global_position = Vector3(0,-999,0) 

# --- 🎮 联机适配响应 ---

func _on_build_pressed():
	if not can_build or not raycast.is_colliding(): return
	
	var point = raycast.get_collision_point()
	var normal = raycast.get_collision_normal()
	var pos = (point + normal * (block_size * 0.5)).snapped(Vector3(block_size, block_size, block_size))
	
	if _check_overlap(pos): return
	
	# 关键：通过 RPC 同步给所有联机玩家
	var dm = get_tree().root.find_child("DataManager", true, false)
	if dm:
		dm.rpc("sync_block_change", pos, 1, true)
	else:
		_spawn_block(pos) # 没联网时单机运行
	
	can_build = false
	build_timer.start()

func _on_break_pressed():
	if not can_build or not raycast.is_colliding(): return
	
	var object = raycast.get_collider()
	if object.is_in_group("Voxel"):
		var pos = object.get_parent().global_position
		# 关键：通过 RPC 同步拆除
		var dm = get_tree().root.find_child("DataManager", true, false)
		if dm:
			dm.rpc("sync_block_change", pos, 0, false)
		else:
			object.get_parent().queue_free()
			
		can_build = false
		build_timer.start()

func _spawn_block(pos: Vector3):
	var block = MeshInstance3D.new()
	block.mesh = BoxMesh.new()
	block.mesh.size = Vector3(block_size, block_size, block_size)
	if concrete_material: block.material_override = concrete_material
		
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
	var result = get_world_3d().direct_space_state.intersect_point(params)
	return result.size() > 0
