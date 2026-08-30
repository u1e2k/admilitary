class_name Player
extends CharacterBody3D

signal squad_updated(new_size: int, fire_rate: float, damage_mult: float)

# 左右移動感度調整（マイルドで制御しやすい速度）
@export var move_speed: float = 7.8
@export var acceleration: float = 26.0
@export var friction: float = 30.0

# 橋の左右移動範囲
@export var min_x: float = -3.2
@export var max_x: float = 3.2

# 戦闘ステータス
@export var squad_size: int = 1
@export var base_damage: float = 12.0
@export var damage_multiplier: float = 1.0
@export var fire_rate: float = 4.0 # 1秒あたりの発射数

var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")

var shoot_cooldown: float = 0.0
var soldier_mesh_instances: Array[Node3D] = []
var is_control_active: bool = true

var soldier_base_mat: StandardMaterial3D
var visor_mat: StandardMaterial3D

func _ready() -> void:
	# Layer 1 (Player), Mask: Layer 2 (Enemy) | 16 (Gate)
	collision_layer = 1
	collision_mask = 2 | 16
	
	_init_materials()
	_rebuild_squad()

func _init_materials() -> void:
	soldier_base_mat = StandardMaterial3D.new()
	soldier_base_mat.albedo_color = Color(0.12, 0.45, 0.95)
	soldier_base_mat.metallic = 0.3
	soldier_base_mat.roughness = 0.5
	
	visor_mat = StandardMaterial3D.new()
	visor_mat.albedo_color = Color(0.2, 0.95, 1.0)
	visor_mat.emission_enabled = true
	visor_mat.emission = Color(0.2, 0.95, 1.0)
	visor_mat.emission_energy_multiplier = 2.5

func _physics_process(delta: float) -> void:
	if not is_control_active:
		return
		
	# 入力処理 (左右移動)
	var input_x = Input.get_axis("move_left", "move_right")
	
	if input_x != 0.0:
		velocity.x = move_toward(velocity.x, input_x * move_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	
	velocity.y = 0.0
	velocity.z = 0.0
	
	move_and_slide()
	
	# 移動範囲の制限
	global_position.x = clampf(global_position.x, min_x, max_x)
	global_position.y = 0.0
	global_position.z = 8.0
	
	# オート射撃処理
	shoot_cooldown -= delta
	if shoot_cooldown <= 0.0:
		_shoot_barrage()
		shoot_cooldown = 1.0 / maxf(fire_rate, 0.5)

func _shoot_barrage() -> void:
	if not bullet_scene or not is_control_active:
		return
		
	var tree = get_tree()
	if not tree or not tree.current_scene:
		return
		
	var scene_root = tree.current_scene
	
	for soldier in soldier_mesh_instances:
		if is_instance_valid(soldier):
			var bullet = bullet_scene.instantiate() as Bullet
			if bullet:
				scene_root.add_child(bullet)
				bullet.global_position = soldier.global_position + Vector3(0.0, 0.8, -0.6)
				bullet.damage = base_damage * damage_multiplier
				bullet.direction = Vector3.FORWARD

func apply_gate_buff(type: Gate.GateType, value: float) -> void:
	match type:
		Gate.GateType.SOLDIER_ADD:
			squad_size = clampi(squad_size + int(value), 1, 24)
			_rebuild_squad()
		Gate.GateType.FIRE_RATE_MUL:
			fire_rate = clampf(fire_rate * value, 1.0, 20.0)
		Gate.GateType.DAMAGE_MUL:
			damage_multiplier = clampf(damage_multiplier * value, 1.0, 10.0)
			
	squad_updated.emit(squad_size, fire_rate, damage_multiplier)

# レベルアップ強化用メソッド
func add_soldiers(count: int = 1) -> void:
	squad_size = clampi(squad_size + count, 1, 24)
	_rebuild_squad()
	squad_updated.emit(squad_size, fire_rate, damage_multiplier)

func upgrade_fire_rate(multiplier: float = 1.25) -> void:
	fire_rate = clampf(fire_rate * multiplier, 1.0, 25.0)
	squad_updated.emit(squad_size, fire_rate, damage_multiplier)

func upgrade_damage(multiplier: float = 1.30) -> void:
	damage_multiplier = clampf(damage_multiplier * multiplier, 1.0, 15.0)
	squad_updated.emit(squad_size, fire_rate, damage_multiplier)

func _rebuild_squad() -> void:
	for soldier in soldier_mesh_instances:
		if is_instance_valid(soldier):
			soldier.queue_free()
	soldier_mesh_instances.clear()
	
	var container = get_node_or_null("SquadContainer")
	if not container:
		container = Node3D.new()
		container.name = "SquadContainer"
		add_child(container)
	
	var max_per_row = 5
	for i in range(squad_size):
		var row = i / max_per_row
		var col = i % max_per_row
		var count_in_this_row = min(max_per_row, squad_size - (row * max_per_row))
		
		var x_offset = (col - (count_in_this_row - 1) * 0.5) * 0.75
		var z_offset = row * 0.85
		
		var soldier = _create_soldier_mesh()
		soldier.position = Vector3(x_offset, 0, z_offset)
		container.add_child(soldier)
		soldier_mesh_instances.append(soldier)
		
		soldier.scale = Vector3.ZERO
		var tween = soldier.create_tween()
		tween.tween_property(soldier, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _create_soldier_mesh() -> Node3D:
	var soldier_root = Node3D.new()
	
	var body = MeshInstance3D.new()
	var cap = CapsuleMesh.new()
	cap.radius = 0.25
	cap.height = 1.4
	body.mesh = cap
	body.position = Vector3(0, 0.7, 0)
	body.material_override = soldier_base_mat
	soldier_root.add_child(body)
	
	var visor = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.32, 0.12, 0.15)
	visor.mesh = box
	visor.position = Vector3(0, 1.1, -0.2)
	visor.material_override = visor_mat
	soldier_root.add_child(visor)
	
	var gun = MeshInstance3D.new()
	var gun_box = BoxMesh.new()
	gun_box.size = Vector3(0.12, 0.12, 0.55)
	gun.mesh = gun_box
	gun.position = Vector3(0.22, 0.85, -0.3)
	var gun_mat = StandardMaterial3D.new()
	gun_mat.albedo_color = Color(0.2, 0.2, 0.25)
	gun.material_override = gun_mat
	soldier_root.add_child(gun)
	
	return soldier_root
