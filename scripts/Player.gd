class_name Player
extends CharacterBody3D

signal squad_updated(new_size: int, fire_rate: float, damage_mult: float)

# 左右移動感度
@export var move_speed: float = 8.0
@export var acceleration: float = 28.0
@export var friction: float = 32.0

# 橋の左右移動範囲
@export var min_x: float = -3.2
@export var max_x: float = 3.2

# 戦闘ステータス
@export var squad_size: int = 1
@export var base_damage: float = 12.0
@export var damage_multiplier: float = 1.0
@export var fire_rate: float = 4.0

var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")

var shoot_cooldown: float = 0.0
var soldier_mesh_instances: Array[Node3D] = []
var is_control_active: bool = true
var walk_anim_timer: float = 0.0

# マテリアルキャッシュ
var camo_armor_mat: StandardMaterial3D
var suit_mat: StandardMaterial3D
var visor_mat: StandardMaterial3D
var gun_mat: StandardMaterial3D
var glow_cyan_mat: StandardMaterial3D

func _ready() -> void:
	# Layer 1 (Player), Mask: Layer 2 (Enemy) | 16 (Gate)
	collision_layer = 1
	collision_mask = 2 | 16
	
	_init_materials()
	_rebuild_squad()

func _init_materials() -> void:
	# プロシージャルミリタリー迷彩テクスチャをコード生成
	var camo_texture = _generate_camo_texture()
	
	camo_armor_mat = StandardMaterial3D.new()
	camo_armor_mat.albedo_texture = camo_texture
	camo_armor_mat.uv1_scale = Vector3(2.5, 2.5, 2.5)
	camo_armor_mat.metallic = 0.25
	camo_armor_mat.roughness = 0.65
	
	suit_mat = StandardMaterial3D.new()
	suit_mat.albedo_color = Color(0.12, 0.16, 0.14) # オリーブドラブ調のダークインナースーツ
	suit_mat.roughness = 0.8
	
	visor_mat = StandardMaterial3D.new()
	visor_mat.albedo_color = Color(0.1, 0.95, 1.0)
	visor_mat.emission_enabled = true
	visor_mat.emission = Color(0.2, 1.0, 1.0)
	visor_mat.emission_energy_multiplier = 3.2
	
	glow_cyan_mat = StandardMaterial3D.new()
	glow_cyan_mat.albedo_color = Color(0.1, 0.8, 1.0)
	glow_cyan_mat.emission_enabled = true
	glow_cyan_mat.emission = Color(0.1, 0.8, 1.0)
	glow_cyan_mat.emission_energy_multiplier = 2.0
	
	gun_mat = StandardMaterial3D.new()
	gun_mat.albedo_color = Color(0.18, 0.20, 0.22) # タクティカルガンメタル
	gun_mat.metallic = 0.75
	gun_mat.roughness = 0.35

## ミリタリー迷彩（カモフラージュパターン）テクスチャの動的生成
func _generate_camo_texture() -> ImageTexture:
	var width = 128
	var height = 128
	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)
	
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.04
	noise.cellular_distance_function = FastNoiseLite.DISTANCE_HYBRID
	noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	
	# ミリタリーアーミー・ネイビー迷彩パレット
	var col_dark_green = Color(0.15, 0.28, 0.18)
	var col_olive = Color(0.28, 0.42, 0.24)
	var col_tan = Color(0.48, 0.45, 0.32)
	var col_navy_blue = Color(0.14, 0.25, 0.45)
	
	for y in range(height):
		for x in range(width):
			var val = (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5 # 0.0 ~ 1.0
			var pixel_color: Color
			if val < 0.28:
				pixel_color = col_dark_green
			elif val < 0.55:
				pixel_color = col_olive
			elif val < 0.78:
				pixel_color = col_tan
			else:
				pixel_color = col_navy_blue
			img.set_pixel(x, y, pixel_color)
			
	return ImageTexture.create_from_image(img)

func _physics_process(delta: float) -> void:
	if not is_control_active:
		return
		
	var input_x = Input.get_axis("move_left", "move_right")
	
	if input_x != 0.0:
		velocity.x = move_toward(velocity.x, input_x * move_speed, acceleration * delta)
		walk_anim_timer += delta * 12.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		walk_anim_timer += delta * 3.0
	
	velocity.y = 0.0
	velocity.z = 0.0
	
	move_and_slide()
	
	global_position.x = clampf(global_position.x, min_x, max_x)
	global_position.y = 0.0
	global_position.z = 8.0
	
	_animate_squad(input_x)
	
	# オート射撃
	shoot_cooldown -= delta
	if shoot_cooldown <= 0.0:
		_shoot_barrage()
		shoot_cooldown = 1.0 / maxf(fire_rate, 0.5)

func _animate_squad(input_x: float) -> void:
	var tilt = -input_x * 0.15
	for i in range(soldier_mesh_instances.size()):
		var soldier = soldier_mesh_instances[i]
		if is_instance_valid(soldier):
			var bounce = sin(walk_anim_timer + (i * 0.5)) * 0.04
			soldier.position.y = bounce
			soldier.rotation.z = lerp_angle(soldier.rotation.z, tilt, 0.2)

func _shoot_barrage() -> void:
	if not bullet_scene or not is_control_active:
		return
		
	var tree = get_tree()
	if not tree or not tree.current_scene:
		return
		
	var scene_root = tree.current_scene
	var world_node = scene_root.get_node_or_null("GameWorld")
	var parent_node = world_node if world_node else scene_root
	
	for soldier in soldier_mesh_instances:
		if is_instance_valid(soldier):
			var bullet = bullet_scene.instantiate() as Bullet
			if bullet:
				bullet.process_mode = Node.PROCESS_MODE_PAUSABLE
				parent_node.add_child(bullet)
				bullet.global_position = soldier.global_position + Vector3(0.18, 0.85, -0.7)
				bullet.damage = base_damage * damage_multiplier
				bullet.direction = Vector3.FORWARD
				
				var gun = soldier.get_node_or_null("Gun")
				if gun:
					gun.position.z = -0.15
					var tween = gun.create_tween()
					tween.tween_property(gun, "position:z", -0.28, 0.08)

func apply_gate_buff(type: Gate.GateType, value: float) -> void:
	match type:
		Gate.GateType.SOLDIER_ADD:
			squad_size = clampi(squad_size + int(value), 1, 24)
			_rebuild_squad()
		Gate.GateType.FIRE_RATE_MUL:
			fire_rate = clampf(fire_rate * value, 1.0, 25.0)
		Gate.GateType.DAMAGE_MUL:
			damage_multiplier = clampf(damage_multiplier * value, 1.0, 15.0)
			
	squad_updated.emit(squad_size, fire_rate, damage_multiplier)

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
	
	# 1. インナースーツ
	var suit_body = MeshInstance3D.new()
	var suit_cap = CapsuleMesh.new()
	suit_cap.radius = 0.2
	suit_cap.height = 1.2
	suit_body.mesh = suit_cap
	suit_body.position = Vector3(0, 0.6, 0)
	suit_body.material_override = suit_mat
	soldier_root.add_child(suit_body)
	
	# 2. タクティカル迷彩チェストアーマー (胸部装甲)
	var armor_chest = MeshInstance3D.new()
	var chest_box = BoxMesh.new()
	chest_box.size = Vector3(0.46, 0.45, 0.36)
	armor_chest.mesh = chest_box
	armor_chest.position = Vector3(0, 0.75, -0.02)
	armor_chest.material_override = camo_armor_mat
	soldier_root.add_child(armor_chest)
	
	# 3. 迷彩ショルダーパッド (肩部装甲)
	for side in [-1, 1]:
		var shoulder = MeshInstance3D.new()
		var s_box = BoxMesh.new()
		s_box.size = Vector3(0.14, 0.16, 0.24)
		shoulder.mesh = s_box
		shoulder.position = Vector3(side * 0.28, 0.85, 0.0)
		shoulder.material_override = camo_armor_mat
		soldier_root.add_child(shoulder)
	
	# 4. 迷彩ヘルメット
	var helmet = MeshInstance3D.new()
	var helm_mesh = SphereMesh.new()
	helm_mesh.radius = 0.24
	helm_mesh.height = 0.44
	helmet.mesh = helm_mesh
	helmet.position = Vector3(0, 1.15, 0)
	helmet.material_override = camo_armor_mat
	soldier_root.add_child(helmet)
	
	# 5. サイバー発光バイザー
	var visor = MeshInstance3D.new()
	var visor_box = BoxMesh.new()
	visor_box.size = Vector3(0.32, 0.10, 0.14)
	visor.mesh = visor_box
	visor.position = Vector3(0, 1.16, -0.16)
	visor.material_override = visor_mat
	soldier_root.add_child(visor)
	
	# 6. バックパック
	var backpack = MeshInstance3D.new()
	var pack_box = BoxMesh.new()
	pack_box.size = Vector3(0.32, 0.4, 0.16)
	backpack.mesh = pack_box
	backpack.position = Vector3(0, 0.75, 0.22)
	backpack.material_override = camo_armor_mat
	soldier_root.add_child(backpack)
	
	var energy_bar = MeshInstance3D.new()
	var e_box = BoxMesh.new()
	e_box.size = Vector3(0.2, 0.06, 0.04)
	energy_bar.mesh = e_box
	energy_bar.position = Vector3(0, 0.82, 0.31)
	energy_bar.material_override = glow_cyan_mat
	soldier_root.add_child(energy_bar)
	
	# 7. アサルトライフル
	var gun_root = Node3D.new()
	gun_root.name = "Gun"
	gun_root.position = Vector3(0.18, 0.75, -0.28)
	soldier_root.add_child(gun_root)
	
	var gun_body = MeshInstance3D.new()
	var gun_b_box = BoxMesh.new()
	gun_b_box.size = Vector3(0.1, 0.14, 0.55)
	gun_body.mesh = gun_b_box
	gun_body.material_override = gun_mat
	gun_root.add_child(gun_body)
	
	var muzzle = MeshInstance3D.new()
	var m_box = BoxMesh.new()
	m_box.size = Vector3(0.06, 0.06, 0.12)
	muzzle.mesh = m_box
	muzzle.position = Vector3(0, 0.02, -0.32)
	muzzle.material_override = glow_cyan_mat
	gun_root.add_child(muzzle)
	
	var mag = MeshInstance3D.new()
	var mag_box = BoxMesh.new()
	mag_box.size = Vector3(0.08, 0.16, 0.1)
	mag.mesh = mag_box
	mag.position = Vector3(0, -0.12, 0.05)
	mag.material_override = gun_mat
	gun_root.add_child(mag)
	
	return soldier_root
