@tool
extends MeshInstance3D

var shader_mat: ShaderMaterial

func _ready():
	_setup_sky_box()
	_apply_shader()

func _setup_sky_box():
	# 如果没有网格，创建一个新的 BoxMesh
	if not mesh:
		mesh = BoxMesh.new()
	
	# 设置一个巨大的尺寸，包围整个世界
	if mesh is BoxMesh:
		mesh.size = Vector3(10000, 5000, 10000)
		
	# 关闭阴影投射，只负责渲染天空
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 确保位置在头顶
	position.y = 1000.0 

func _apply_shader():
	# 尝试从 Material Override 获取材质
	if material_override is ShaderMaterial:
		shader_mat = material_override
	# 尝试从 Surface 获取材质
	elif get_surface_override_material(0) is ShaderMaterial:
		shader_mat = get_surface_override_material(0)
	
	if not shader_mat:
		print("未找到材质，请在右侧检查器 Material Override 中设置！")

func _process(delta):
	if not shader_mat: return
	
	# 简单的太阳旋转
	var time = Time.get_ticks_msec() / 5000.0
	var sun_pos = Vector3(sin(time), 0.6, cos(time)).normalized()
	shader_mat.set_shader_parameter("sun_dir", sun_pos)
