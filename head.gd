extends Node

# 挂载后自动运行
func _ready():
	_create_post_process_layer()

func _create_post_process_layer():
	# 1. 寻找相机
	var camera = get_viewport().get_camera_3d()
	if not camera:
		print("未找到相机，GI 挂载失败")
		return
		
	# 2. 创建一个四边形网格来承载 Shader
	var mesh_instance = MeshInstance3D.new()
	var mesh = QuadMesh.new()
	mesh.size = Vector2(2, 2) # 全屏覆盖
	mesh.flip_faces = true    # 翻转面，确保相机能看到
	mesh_instance.mesh = mesh
	
	# 3. 创建材质并加载上面的 Shader
	var mat = ShaderMaterial.new()
	mat.shader = load("res://fake_gi.gdshader") # 确保路径正确！
	
	# 重要：设置混合模式为“叠加(Add)”，这样 GI 是亮光叠加，而不是覆盖
	# 注意：为了让 Shader 生效，我们需要将其作为几何体渲染，但要画在最后
	mesh_instance.material_override = mat
	
	# 4. 将网格放到相机面前
	# 这一步很关键：通过 cast_shadow 关闭阴影，防止自己挡光
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# 5. 为了让它始终糊在相机脸上
	# 我们通常把它作为相机的子节点
	camera.add_child(mesh_instance)
	mesh_instance.position = Vector3(0, 0, -0.5) # 放在相机前方 0.5 米处
	
	# 6. 配置材质参数（可以在这里微调）
	mat.set_shader_parameter("gi_intensity", 3.0) # 强度
	mat.set_shader_parameter("quality_steps", 8)  # 手机设8，太高会卡
	
	print("极致 GI 纯代码挂载成功！")
