extends CharacterBody3D

# --- 🎮 基础参数 ---
const WALK_SPEED = 5.0
const SPRINT_SPEED = 12.0
const CLIMB_SPEED = 4.0 # 爬墙速度
const FLY_SPEED = 20.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8

# --- 📱 触屏 UI 分区参数 ---
const ZOOM_ZONE_SIZE = 250.0 
const FLY_BTN_SIZE = 250.0   
const TOUCH_SENSITIVITY_LOOK = 0.05 
const TOUCH_SENSITIVITY_MOVE = 0.02

# --- 内部变量 ---
@onready var head = $Head
@onready var camera = $Head/Camera3D

var is_flying = false 

# 触摸索引
var move_finger_index = -1
var look_finger_index = -1
var zoom_finger_index = -1

# 触摸起始点
var move_start_pos = Vector2.ZERO
var zoom_start_pos = Vector2.ZERO
var last_look_pos = Vector2.ZERO
var current_move_vector = Vector2.ZERO

# --- 🌐 联机锁死逻辑 (新增) ---
func _ready():
	# 1. 自动设置同步权限 (锁死 UID)
	if has_node("MultiplayerSynchronizer"):
		var sync_node = $MultiplayerSynchronizer
		sync_node.set_multiplayer_authority(name.to_int())
		
		# 2. 强制绑定同步属性 (防止编辑器搜不到)
		var config = sync_node.replication_config
		if config:
			if not config.has_property(".:global_position"):
				config.add_property(".:global_position")
			if not config.has_property(".:rotation"):
				config.add_property(".:rotation")
	
	# 3. 只有本人才能控制相机
	if not is_multiplayer_authority():
		if camera: camera.current = false
		return # 非本人不执行后续初始化

	if camera:
		camera.fov = 75.0
		camera.far = 1000.0

func _input(event):
	# 只有本人操作自己的手机才会触发输入
	if not is_multiplayer_authority(): return 
	
	var vp_w = get_viewport().get_visible_rect().size.x
	var half_w = vp_w / 2.0
	
	if event is InputEventScreenTouch:
		if event.pressed:
			# 1. 缩放区 (左上)
			if event.position.x < ZOOM_ZONE_SIZE and event.position.y < ZOOM_ZONE_SIZE:
				if zoom_finger_index == -1:
					zoom_finger_index = event.index
					zoom_start_pos = event.position
			
			# 2. 飞行开关 (右上)
			elif event.position.x > (vp_w - FLY_BTN_SIZE) and event.position.y < FLY_BTN_SIZE:
				is_flying = not is_flying
				velocity = Vector3.ZERO
				print("飞行模式: ", is_flying)
			
			# 3. 移动区 (左半屏)
			elif event.position.x < half_w:
				if move_finger_index == -1:
					move_finger_index = event.index
					move_start_pos = event.position
			
			# 4. 视角区 (右半屏)
			else:
				if look_finger_index == -1:
					look_finger_index = event.index
					last_look_pos = event.position

		else: # 抬起
			if event.index == move_finger_index:
				move_finger_index = -1
				current_move_vector = Vector2.ZERO
			elif event.index == look_finger_index:
				look_finger_index = -1
			elif event.index == zoom_finger_index:
				zoom_finger_index = -1

	elif event is InputEventScreenDrag:
		# 缩放
		if event.index == zoom_finger_index:
			var dy = event.position.y - zoom_start_pos.y
			if abs(dy) > 1.0:
				camera.fov += dy * 0.05
				camera.fov = clamp(camera.fov, 30.0, 110.0)
				zoom_start_pos = event.position 
		
		# 旋转
		elif event.index == look_finger_index:
			var diff = event.position - last_look_pos
			last_look_pos = event.position
			rotate_y(-diff.x * TOUCH_SENSITIVITY_LOOK * 0.1)
			head.rotate_x(-diff.y * TOUCH_SENSITIVITY_LOOK * 0.1)
			head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		
		# 移动
		elif event.index == move_finger_index:
			var diff = event.position - move_start_pos
			if diff.length() > 100: diff = diff.normalized() * 100
			current_move_vector = diff * TOUCH_SENSITIVITY_MOVE

func _physics_process(delta):
	# 只有本人的手机负责计算自己的物理位移
	# 其他玩家的坐标由同步器自动强制拉过去
	if not is_multiplayer_authority(): return

	# --- 飞行模式 ---
	if is_flying:
		var aim = camera.global_transform.basis
		if current_move_vector.length() > 0.1:
			var dir = (aim.z * current_move_vector.y + aim.x * current_move_vector.x).normalized()
			velocity = velocity.lerp(dir * FLY_SPEED, delta * 5.0)
		else:
			velocity = velocity.lerp(Vector3.ZERO, delta * 5.0)
		move_and_slide()
		return

	# --- 爬墙逻辑 (在此处) ---
	var is_climbing = false
	# 如果贴着墙 且 摇杆向前推 (y < -0.5)
	if is_on_wall() and current_move_vector.y < -0.5: 
		is_climbing = true
		velocity.y = CLIMB_SPEED
	
	if not is_on_floor() and not is_climbing:
		velocity.y -= GRAVITY * delta

	# --- 地面/空中移动 ---
	var dir = Vector3.ZERO
	var aim_flat = global_transform.basis
	
	if current_move_vector.length() > 0.1:
		dir += aim_flat.z * current_move_vector.y
		dir += aim_flat.x * current_move_vector.x
		dir = dir.normalized()
		var spd = WALK_SPEED
		if is_climbing: spd = CLIMB_SPEED # 爬墙时稍微慢一点
		
		velocity.x = lerp(velocity.x, dir.x * spd, delta * 10.0)
		velocity.z = lerp(velocity.z, dir.z * spd, delta * 10.0)
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 10.0)

	move_and_slide()
