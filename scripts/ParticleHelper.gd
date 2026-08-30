class_name ParticleHelper
extends Node

## 敵撃破時やゲート通過時のローポリブロック飛散エフェクトを動的生成するヘルパー

static func spawn_shatter_blocks(tree: SceneTree, spawn_pos: Vector3, color: Color, count: int = 6, scale_size: float = 0.25) -> void:
	if not tree or not tree.current_scene:
		return
		
	var parent_node = tree.current_scene
	var shared_mesh = BoxMesh.new()
	shared_mesh.size = Vector3(scale_size, scale_size, scale_size)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.7
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	
	for i in range(count):
		var block = MeshInstance3D.new()
		block.mesh = shared_mesh
		block.material_override = mat
		block.global_position = spawn_pos + Vector3(
			randf_range(-0.3, 0.3),
			randf_range(0.0, 0.5),
			randf_range(-0.3, 0.3)
		)
		parent_node.add_child(block)
		
		# ランダムな飛散方向と回転
		var fly_velocity = Vector3(
			randf_range(-4.0, 6.0),
			randf_range(3.0, 8.0),
			randf_range(-4.0, 4.0)
		)
		var rot_velocity = Vector3(
			randf_range(-10.0, 10.0),
			randf_range(-10.0, 10.0),
			randf_range(-10.0, 10.0)
		)
		
		# Tweenで放物線運動＆縮小フェードアウト
		var tween = block.create_tween().set_parallel(true)
		tween.tween_property(block, "scale", Vector3.ZERO, 0.6).set_delay(0.2)
		
		# 簡易物理シミュレーション (Tween step)
		var duration = 0.8
		var elapsed_time = 0.0
		var initial_pos = block.global_position
		
		var gravity = Vector3(0, -18.0, 0)
		var mover = func(t: float):
			if is_instance_valid(block):
				block.global_position = initial_pos + (fly_velocity * t) + (0.5 * gravity * t * t)
				block.rotation += rot_velocity * 0.016
		
		var timer_tween = block.create_tween()
		timer_tween.tween_method(mover, 0.0, duration, duration)
		timer_tween.tween_callback(block.queue_free)
