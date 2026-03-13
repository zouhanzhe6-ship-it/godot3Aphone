extends Node

## 强制太阳角度脚本：独立运行，不依赖主脚本变量
## 中午12点对应的角度通常是垂直向下 (Vector3(-90, 0, 0))

@export var force_noon: bool = true

func _process(_delta: float) -> void:
	if not force_noon:
		return
		
	# 技巧：遍历场景寻找所有的太阳（DirectionalLight3D）
	var lights = get_tree().get_nodes_in_group("sun_group")
	
	# 如果没有设置分组，就直接找类型
	if lights.is_empty():
		for child in get_parent().get_children():
			if child is DirectionalLight3D:
				_apply_noon_rotation(child)
	else:
		for sun in lights:
			_apply_noon_rotation(sun)

func _apply_noon_rotation(sun_node: DirectionalLight3D):
	# 3A 技巧：中午12点的太阳。X轴 -90度表示阳光垂直从头顶射向地面。
	# 使用 global_rotation 确保即使太阳在复杂的层级下，光照方向也是准确的。
	sun_node.global_rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	
	# 顶级渲染修正：中午12点的光照能量通常最强，确保 3A 质感不发灰
	sun_node.light_energy = 1.8
	sun_node.light_indirect_energy = 1.0
	
	# 强制开启高质量阴影
	sun_node.shadow_enabled = true
	sun_node.shadow_normal_bias = 2.0
