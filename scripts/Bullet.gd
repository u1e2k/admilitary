class_name Bullet
extends Area3D

@export var speed: float = 42.0
@export var damage: float = 10.0
@export var knockback_force: float = 4.0
@export var max_distance_z: float = -60.0

# 手前から奥（-Z方向）へ直進
var direction: Vector3 = Vector3.FORWARD
var is_active: bool = true

func _ready() -> void:
	# 衝突レイヤー設定: Layer 4 (PlayerBullet), Mask: Layer 2 (Enemy)
	collision_layer = 8
	collision_mask = 2
	
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	_setup_visuals()

func _setup_visuals() -> void:
	var mesh_inst = get_node_or_null("MeshInstance3D")
	if not mesh_inst:
		mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "MeshInstance3D"
		add_child(mesh_inst)
		
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.08
	capsule.height = 0.55
	mesh_inst.mesh = capsule
	mesh_inst.rotation_degrees = Vector3(90, 0, 0) # Z軸奥方向に寝かせる
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 1.0)
	mat.emission_energy_multiplier = 3.0
	mesh_inst.material_override = mat

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	
	# 奥または手前に行き過ぎたら自動削除
	if global_position.z < max_distance_z or global_position.z > 20.0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if not is_active:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage, knockback_force)
		_hit_and_destroy()

func _on_area_entered(area: Area3D) -> void:
	if not is_active:
		return
	var target = area.get_parent() if not area.has_method("take_damage") else area
	if target and target.has_method("take_damage"):
		target.take_damage(damage, knockback_force)
		_hit_and_destroy()

func _hit_and_destroy() -> void:
	is_active = false
	ParticleHelper.spawn_shatter_blocks(get_tree(), global_position, Color(0.2, 0.9, 1.0), 3, 0.12)
	queue_free()
