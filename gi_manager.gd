extends Node

# 脚本功能：自动创建一个全屏方片，把 GI 材质贴上去
func _ready():
	_setup_effect()

func _setup_effect():
	# 1. 等待一帧，确保相机加载完成
	await get_tree().process_frame
	
	# 2. 寻找当前激活的 3D 相机
	var camera = get_viewport().get_camera_3d()
	if not camera:
		print("❌ 错误：场景里没有相机！")
		return

	# 3. 创建一个全屏方片网格
	var mesh_instance = MeshInstance3D.new()
	var mesh = QuadMesh.new()
	mesh.size = Vector2(2, 2) # 2x2 刚好覆盖全屏坐标系 (-1 到 1)
	mesh.flip_faces = true    # 翻转面，防止看不见
	mesh_instance.mesh = mesh
	
	# 4. 创建材质并加载上面的 Shader
	var mat = ShaderMaterial.new()
	# 【注意】这里的文件名必须和你第一步创建的文件名一致！
	mat.shader = load("res://safe_mobile_gi.gdshader")
	mesh_instance.material_override = mat
	
	# 5. 关闭阴影（防止自己挡光）
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# 6. 挂载到相机上
	camera.add_child(mesh_instance)
	# 放在相机前方 1 米处，确保能被看见
	mesh_instance.position = Vector3(0, 0, -1.0)
	
	print("✅ 极致 GI 挂载成功！")
