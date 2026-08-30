class_name Gate
extends Area3D

enum GateType {
	SOLDIER_ADD,
	FIRE_RATE_MUL,
	DAMAGE_MUL
}

@export var gate_type: GateType = GateType.SOLDIER_ADD
@export var value: float = 3.0
@export var move_speed: float = 4.2

var is_collected: bool = false
var is_active: bool = false
var base_color: Color = Color(0.1, 0.8, 1.0)

# ペアゲートの相互参照（片方を取るともう片方が即座に消滅）
var linked_pair_gate: Gate = null

@onready var label_3d: Label3D = $Label3D
@onready var frame_mesh_inst: MeshInstance3D = $FrameMesh

static var shared_box_mesh: BoxMesh
static var mat_soldier: StandardMaterial3D
static var mat_fire_rate: StandardMaterial3D
static var mat_damage: StandardMaterial3D

static func init_cache() -> void:
	if shared_box_mesh == null:
		shared_box_mesh = BoxMesh.new()
		shared_box_mesh.size = Vector3(2.6, 2.8, 0.25)
		
		mat_soldier = StandardMaterial3D.new()
		mat_soldier.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_soldier.albedo_color = Color(0.1, 0.7, 1.0, 0.45)
		mat_soldier.emission_enabled = true
		mat_soldier.emission = Color(0.1, 0.7, 1.0)
		mat_soldier.emission_energy_multiplier = 2.2
		
		mat_fire_rate = StandardMaterial3D.new()
		mat_fire_rate.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_fire_rate.albedo_color = Color(1.0, 0.85, 0.1, 0.45)
		mat_fire_rate.emission_enabled = true
		mat_fire_rate.emission = Color(1.0, 0.85, 0.1)
		mat_fire_rate.emission_energy_multiplier = 2.2
		
		mat_damage = StandardMaterial3D.new()
		mat_damage.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_damage.albedo_color = Color(1.0, 0.2, 0.4, 0.45)
		mat_damage.emission_enabled = true
		mat_damage.emission = Color(1.0, 0.2, 0.4)
		mat_damage.emission_energy_multiplier = 2.2

func _ready() -> void:
	collision_layer = 16
	collision_mask = 1
	process_mode = Node.PROCESS_MODE_PAUSABLE
	
	init_cache()
	body_entered.connect(_on_body_entered)
	_setup_visuals()
	_update_label()

func activate(type: GateType, val: float, spawn_pos: Vector3, pair_gate: Gate = null) -> void:
	gate_type = type
	value = val
	global_position = spawn_pos
	scale = Vector3.ONE
	is_collected = false
	is_active = true
	visible = true
	monitoring = true
	monitorable = true
	linked_pair_gate = pair_gate
	set_physics_process(true)
	
	_setup_visuals()
	_update_label()

func deactivate() -> void:
	is_active = false
	visible = false
	monitoring = false
	monitorable = false
	linked_pair_gate = null
	set_physics_process(false)
	global_position = Vector3(0, -100, 0)

func set_gate_data(type: GateType, val: float) -> void:
	gate_type = type
	value = val
	_setup_visuals()
	_update_label()

func _setup_visuals() -> void:
	init_cache()
	
	if not frame_mesh_inst:
		frame_mesh_inst = get_node_or_null("FrameMesh")
		if not frame_mesh_inst:
			frame_mesh_inst = MeshInstance3D.new()
			frame_mesh_inst.name = "FrameMesh"
			add_child(frame_mesh_inst)
			frame_mesh_inst.position = Vector3(0, 1.4, 0)
			
	frame_mesh_inst.mesh = shared_box_mesh
	
	match gate_type:
		GateType.SOLDIER_ADD:
			base_color = Color(0.1, 0.7, 1.0)
			frame_mesh_inst.material_override = mat_soldier
		GateType.FIRE_RATE_MUL:
			base_color = Color(1.0, 0.85, 0.1)
			frame_mesh_inst.material_override = mat_fire_rate
		GateType.DAMAGE_MUL:
			base_color = Color(1.0, 0.2, 0.4)
			frame_mesh_inst.material_override = mat_damage

func _update_label() -> void:
	if not label_3d:
		label_3d = get_node_or_null("Label3D")
		if not label_3d:
			label_3d = Label3D.new()
			label_3d.name = "Label3D"
			add_child(label_3d)
			label_3d.position = Vector3(0, 1.5, 0.18)
			label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label_3d.font_size = 44
			label_3d.outline_size = 12
			label_3d.modulate = Color.WHITE
			label_3d.outline_modulate = Color.BLACK
	
	match gate_type:
		GateType.SOLDIER_ADD:
			label_3d.text = "+%d\nSOLDIERS" % int(value)
		GateType.FIRE_RATE_MUL:
			label_3d.text = "x%.2f\nFIRE RATE" % value
		GateType.DAMAGE_MUL:
			label_3d.text = "+%d%%\nDMG UP" % int((value - 1.0) * 100.0)

func _physics_process(delta: float) -> void:
	if not is_active or is_collected:
		return
		
	global_position.z += move_speed * delta
	position.y = sin(Time.get_ticks_msec() * 0.005) * 0.08
	
	if global_position.z > 14.0:
		deactivate()

func _on_body_entered(body: Node3D) -> void:
	if not is_active or is_collected:
		return
	
	if body.has_method("apply_gate_buff"):
		is_collected = true
		body.apply_gate_buff(gate_type, value)
		
		# もう片方のペアゲートを即時消滅（二者択一）
		if is_instance_valid(linked_pair_gate) and linked_pair_gate.is_active:
			linked_pair_gate.deactivate()
			
		ParticleHelper.spawn_shatter_blocks(get_tree(), global_position + Vector3(0, 1.4, 0), base_color, 14, 0.35)
		
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector3(1.3, 0.05, 1.3), 0.15)
		tween.tween_callback(deactivate)
