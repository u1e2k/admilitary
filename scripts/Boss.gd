class_name Boss
extends CharacterBody3D

signal boss_defeated(score_val: int, exp_val: int)
signal breached_defense(boss: Node3D)

@export var max_hp: float = 650.0
@export var current_hp: float = 650.0
@export var move_speed: float = 1.3
@export var score_reward: int = 2500
@export var exp_reward: int = 200
@export var breach_z_threshold: float = 10.5

var knockback_velocity: Vector3 = Vector3.ZERO
var is_dead: bool = false

var visual_root: Node3D
var hp_bar_mesh: MeshInstance3D
var base_mat: StandardMaterial3D
var emissive_mat: StandardMaterial3D
var flash_mat: StandardMaterial3D

func _ready() -> void:
	# Layer 2 (Enemy), Mask 1 (Player) | 8 (PlayerBullet)
	collision_layer = 2
	collision_mask = 1 | 8
	
	current_hp = max_hp
	_setup_visuals()
	_setup_hp_bar()

func _setup_visuals() -> void:
	visual_root = Node3D.new()
	visual_root.name = "VisualRoot"
	add_child(visual_root)
	
	base_mat = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.12, 0.12, 0.14)
	base_mat.metallic = 0.5
	base_mat.roughness = 0.4
	
	emissive_mat = StandardMaterial3D.new()
	emissive_mat.albedo_color = Color(1.0, 0.1, 0.1)
	emissive_mat.emission_enabled = true
	emissive_mat.emission = Color(1.0, 0.1, 0.2)
	emissive_mat.emission_energy_multiplier = 3.5
	
	flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 1.0, 1.0)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 1.0, 1.0)
	flash_mat.emission_energy_multiplier = 5.0
	
	# 胴体
	var body = MeshInstance3D.new()
	var body_box = BoxMesh.new()
	body_box.size = Vector3(2.8, 3.2, 2.4)
	body.mesh = body_box
	body.position = Vector3(0, 1.8, 0)
	body.material_override = base_mat
	visual_root.add_child(body)
	
	# 発光コア/アイ (手前 +Z 側を向く)
	var core = MeshInstance3D.new()
	var core_box = BoxMesh.new()
	core_box.size = Vector3(2.5, 0.8, 1.2)
	core.mesh = core_box
	core.position = Vector3(0, 2.2, 0.8)
	core.material_override = emissive_mat
	visual_root.add_child(core)
	
	# 角 / スパイク (手前・上方に突き出す)
	for x_offset in [-1.0, 1.0]:
		var horn = MeshInstance3D.new()
		var horn_mesh = CylinderMesh.new()
		horn_mesh.top_radius = 0.05
		horn_mesh.bottom_radius = 0.3
		horn_mesh.height = 1.6
		horn.mesh = horn_mesh
		horn.position = Vector3(x_offset, 3.8, 0.6)
		horn.rotation_degrees = Vector3(-35, 0, 0)
		horn.material_override = emissive_mat
		visual_root.add_child(horn)

func _setup_hp_bar() -> void:
	var hp_root = Node3D.new()
	hp_root.position = Vector3(0, 4.6, 0)
	add_child(hp_root)
	
	var label = Label3D.new()
	label.text = "BOSS: GIGA KAIJU"
	label.font_size = 36
	label.outline_size = 8
	label.modulate = Color(1.0, 0.3, 0.3)
	label.position = Vector3(0, 0.6, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_root.add_child(label)
	
	var hp_bg = MeshInstance3D.new()
	var bg_box = BoxMesh.new()
	bg_box.size = Vector3(3.2, 0.25, 0.15)
	hp_bg.mesh = bg_box
	var bg_mat = StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.9)
	hp_bg.material_override = bg_mat
	hp_root.add_child(hp_bg)
	
	hp_bar_mesh = MeshInstance3D.new()
	var bar_box = BoxMesh.new()
	bar_box.size = Vector3(3.1, 0.22, 0.18)
	hp_bar_mesh.mesh = bar_box
	var bar_mat = StandardMaterial3D.new()
	bar_mat.albedo_color = Color(1.0, 0.2, 0.2)
	bar_mat.emission_enabled = true
	bar_mat.emission = Color(1.0, 0.2, 0.2) * 1.5
	hp_bar_mesh.material_override = bar_mat
	hp_root.add_child(hp_bar_mesh)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
		
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, delta * 30.0)
	
	# 手前 (+Z) 方向へ前進
	var forward_velocity = Vector3.BACK * move_speed
	velocity = forward_velocity + knockback_velocity
	
	move_and_slide()
	
	if visual_root:
		visual_root.position.y = abs(sin(Time.get_ticks_msec() * 0.005)) * 0.2
	
	# 防衛ライン突破チェック
	if global_position.z >= breach_z_threshold:
		breached_defense.emit(self)
		is_dead = true
		queue_free()

func take_damage(amount: float, knockback: float = 3.0) -> void:
	if is_dead:
		return
		
	current_hp -= amount
	# 奥（-Z方向）へノックバック
	knockback_velocity += Vector3.FORWARD * (knockback * 0.18)
	
	_update_hp_bar()
	_flash_effect()
	
	if current_hp <= 0.0:
		die()

func _update_hp_bar() -> void:
	if hp_bar_mesh:
		var ratio = clampf(current_hp / max_hp, 0.0, 1.0)
		hp_bar_mesh.scale.x = ratio

func _flash_effect() -> void:
	if visual_root:
		for child in visual_root.get_children():
			if child is MeshInstance3D:
				child.material_override = flash_mat
		
		var tween = create_tween()
		tween.tween_interval(0.05)
		tween.tween_callback(func():
			if is_instance_valid(self) and not is_dead:
				_restore_materials()
		)

func _restore_materials() -> void:
	if not visual_root:
		return
	var children = visual_root.get_children()
	if children.size() > 0:
		children[0].material_override = base_mat
	for i in range(1, children.size()):
		children[i].material_override = emissive_mat

func die() -> void:
	is_dead = true
	boss_defeated.emit(score_reward, exp_reward)
	
	for i in range(4):
		var offset = Vector3(randf_range(-1, 1), randf_range(0.5, 3.0), randf_range(-1, 1))
		ParticleHelper.spawn_shatter_blocks(get_tree(), global_position + offset, Color(1.0, 0.2, 0.1), 12, 0.45)
		
	queue_free()
