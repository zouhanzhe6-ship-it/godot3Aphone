extends Node

# --- ⚙️ 配置区 ---
const BMOB_APP_ID = "ba18f8f564cb290a71e656c0d018f956"
const BMOB_REST_KEY = "3b875f86c7de5f84a73c8612c0f5d0b0"
const PORT = 7000

# 修复点：使用安全的加载方式，防止因文件找不到而直接崩溃
var player_scene

# --- 变量区 ---
var enet_peer = ENetMultiplayerPeer.new()
var name_input: LineEdit
var ip_input: LineEdit
var network_ui: CanvasLayer
var main_vbox: VBoxContainer   
var mini_rect: ColorRect      
var count_label: Label        
var block_data: Dictionary = {}

func _ready():
	# 强行尝试加载玩家场景，失败也不会让程序卡死
	player_scene = load("res://player.tscn") 
	if player_scene == null:
		print("警告：未找到 player.tscn，请检查文件名大小写！")
	
	# 无论如何先画出 UI
	_create_network_ui()
	
	# 监听网络
	multiplayer.peer_connected.connect(_on_network_changed)
	multiplayer.peer_disconnected.connect(_on_network_changed)

# --- 🖥️ UI 界面逻辑 (最高优先级) ---
func _create_network_ui():
	# 如果已经有 UI 了就先销毁，防止重复创建
	if has_node("NetUI"): 
		get_node("NetUI").queue_free()

	network_ui = CanvasLayer.new()
	network_ui.name = "NetUI"
	network_ui.layer = 120 # 调高层级，确保在最前面
	add_child(network_ui)
	
	# 1. 灰色小方块 (初始隐藏)
	mini_rect = ColorRect.new()
	mini_rect.color = Color(0.2, 0.2, 0.2, 0.7)
	mini_rect.custom_minimum_size = Vector2(100, 50)
	mini_rect.position = Vector2(30, 30)
	mini_rect.visible = false
	mini_rect.gui_input.connect(_on_mini_rect_clicked)
	network_ui.add_child(mini_rect)
	
	count_label = Label.new()
	count_label.text = "联机中..."
	count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	mini_rect.add_child(count_label)

	# 2. 主菜单
	main_vbox = VBoxContainer.new()
	main_vbox.position = Vector2(100, 100) # 往中间挪一点，避开刘海屏
	network_ui.add_child(main_vbox)
	
	name_input = LineEdit.new()
	name_input.placeholder_text = "输入名字"
	name_input.custom_minimum_size = Vector2(300, 60)
	main_vbox.add_child(name_input)
	
	ip_input = LineEdit.new()
	ip_input.text = "127.0.0.1"
	ip_input.custom_minimum_size = Vector2(300, 60)
	main_vbox.add_child(ip_input)
	
	var btn_h = Button.new()
	btn_h.text = "创建世界 (房主)"
	btn_h.custom_minimum_size = Vector2(200, 100)
	btn_h.pressed.connect(start_hosting)
	main_vbox.add_child(btn_h)
	
	var btn_j = Button.new()
	btn_j.text = "搜索加入 (队员)"
	btn_j.custom_minimum_size = Vector2(200, 100)
	btn_j.pressed.connect(join_world)
	main_vbox.add_child(btn_j)

# --- 🌐 联机核心逻辑 ---
func start_hosting():
	if enet_peer.create_server(PORT) != OK: return
	multiplayer.multiplayer_peer = enet_peer
	add_player(1) 
	_show_mini_mode()

func join_world():
	enet_peer.create_client(ip_input.text, PORT)
	multiplayer.multiplayer_peer = enet_peer
	_show_mini_mode()

func add_player(peer_id):
	if player_scene == null: return
	var p = player_scene.instantiate()
	p.name = str(peer_id)
	p.global_position = Vector3(0, 15, 0)
	add_child(p)

func _show_mini_mode():
	main_vbox.visible = false
	mini_rect.visible = true

func _on_mini_rect_clicked(event):
	if event is InputEventScreenTouch and event.pressed:
		main_vbox.visible = !main_vbox.visible

func _on_network_changed(_id):
	if count_label:
		count_label.text = "人数:%d" % (multiplayer.get_peers().size() + 1)
