class_name Bullet
extends Area3D

@export var speed: float = 45.0
@export var damage: float = 38.0 # 重厚な高威力
@export var knockback_force: float = 6.5 # 重い衝撃力
@export var max_distance_z: float = -60.0

var direction: Vector3 = Vector3.FORWARD
var is_active: bool = true

func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	process_mode = Node.PROCESS_MODE_PAUSABLE
	
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	_setup_visuals()

func _setup_visuals() -> void:
	var mesh_inst = get_node_or_null("MeshInstance3D")
	if not mesh_inst:
		mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "MeshInstance3D"
		add_child(mesh_inst)
		
	# 太めで迫力のあるシアンヘビープラズマ弾
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.13
	capsule.height = 0.65
	mesh_inst.mesh = capsule
	mesh_inst.rotation_degrees = Vector3(90, 0, 0)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 1.0)
	mat.emission_energy_multiplier = 3.5
	mesh_inst.material_override = mat

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	
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
	ParticleHelper.spawn_shatter_blocks(get_tree(), global_position, Color(0.2, 0.95, 1.0), 4, 0.16)
	queue_free()
