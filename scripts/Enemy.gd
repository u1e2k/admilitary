class_name Enemy
extends CharacterBody3D

signal enemy_defeated(score_val: int)
signal breached_defense(enemy: Node3D)

@export var max_hp: float = 30.0
@export var current_hp: float = 30.0
@export var move_speed: float = 2.6
@export var score_reward: int = 100
@export var breach_z_threshold: float = 10.5

var knockback_velocity: Vector3 = Vector3.ZERO
var is_dead: bool = false

var body_mesh_instance: MeshInstance3D
var hp_bar_mesh: MeshInstance3D
var base_mat: StandardMaterial3D
var flash_mat: StandardMaterial3D

func _ready() -> void:
	# Layer 2 (Enemy), Mask 1 (Player) | 8 (PlayerBullet)
	collision_layer = 2
	collision_mask = 1 | 8
	
	current_hp = max_hp
	_setup_visuals()
	_setup_hp_bar()

func _setup_visuals() -> void:
	body_mesh_instance = get_node_or_null("MeshInstance3D")
	if not body_mesh_instance:
		body_mesh_instance = MeshInstance3D.new()
		body_mesh_instance.name = "MeshInstance3D"
		add_child(body_mesh_instance)
		
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	body_mesh_instance.mesh = capsule
	body_mesh_instance.position = Vector3(0, 0.8, 0)
	
	base_mat = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.85, 0.15, 0.15) # 赤
	base_mat.emission_enabled = true
	base_mat.emission = Color(0.9, 0.1, 0.1) * 0.4
	body_mesh_instance.material_override = base_mat
	
	flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 1.0, 1.0)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 1.0, 1.0)
	flash_mat.emission_energy_multiplier = 4.0

func _setup_hp_bar() -> void:
	var hp_bg = MeshInstance3D.new()
	var bg_box = BoxMesh.new()
	bg_box.size = Vector3(0.8, 0.08, 0.08)
	hp_bg.mesh = bg_box
	hp_bg.position = Vector3(0, 1.8, 0)
	var bg_mat = StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
	hp_bg.material_override = bg_mat
	add_child(hp_bg)
	
	hp_bar_mesh = MeshInstance3D.new()
	var bar_box = BoxMesh.new()
	bar_box.size = Vector3(0.78, 0.07, 0.09)
	hp_bar_mesh.mesh = bar_box
	hp_bar_mesh.position = Vector3(0, 1.8, 0.01)
	var bar_mat = StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.2, 0.9, 0.3)
	bar_mat.emission_enabled = true
	bar_mat.emission = Color(0.2, 0.9, 0.3)
	hp_bar_mesh.material_override = bar_mat
	add_child(hp_bar_mesh)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
		
	# ノックバック減衰
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, delta * 18.0)
	
	# 手前 (+Z) 方向へ前進
	var forward_velocity = Vector3.BACK * move_speed
	velocity = forward_velocity + knockback_velocity
	
	move_and_slide()
	
	# 防衛ライン突破チェック（手前側Zラインを越えたか）
	if global_position.z >= breach_z_threshold:
		breached_defense.emit(self)
		is_dead = true
		queue_free()

func take_damage(amount: float, knockback: float = 3.0) -> void:
	if is_dead:
		return
		
	current_hp -= amount
	# 弾丸ヒットで奥（-Z方向）へノックバック
	knockback_velocity += Vector3.FORWARD * knockback
	
	_update_hp_bar()
	_flash_effect()
	
	if current_hp <= 0.0:
		die()

func _update_hp_bar() -> void:
	if hp_bar_mesh:
		var ratio = clampf(current_hp / max_hp, 0.0, 1.0)
		hp_bar_mesh.scale.x = ratio
		if hp_bar_mesh.material_override is StandardMaterial3D:
			var mat = hp_bar_mesh.material_override as StandardMaterial3D
			mat.albedo_color = Color(1.0 - ratio, ratio, 0.1)
			mat.emission = mat.albedo_color

func _flash_effect() -> void:
	if body_mesh_instance:
		body_mesh_instance.material_override = flash_mat
		var tween = create_tween()
		tween.tween_interval(0.06)
		tween.tween_callback(func():
			if is_instance_valid(body_mesh_instance) and not is_dead:
				body_mesh_instance.material_override = base_mat
		)

func die() -> void:
	is_dead = true
	enemy_defeated.emit(score_reward)
	ParticleHelper.spawn_shatter_blocks(get_tree(), global_position + Vector3(0, 0.8, 0), Color(0.9, 0.2, 0.2), 8, 0.28)
	queue_free()
