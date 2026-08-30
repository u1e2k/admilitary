class_name Gate
extends Area3D

enum GateType {
	SOLDIER_ADD,
	FIRE_RATE_MUL,
	DAMAGE_MUL
}

@export var gate_type: GateType = GateType.SOLDIER_ADD
@export var value: float = 3.0
@export var move_speed: float = 3.8

var is_collected: bool = false
var base_color: Color = Color(0.1, 0.8, 1.0)

@onready var label_3d: Label3D = $Label3D
@onready var frame_mesh_inst: MeshInstance3D = $FrameMesh

# マテリアルとメッシュの静的キャッシュ（毎回のシェーダーコンパイルとメモリ確保を防止）
static var shared_box_mesh: BoxMesh
static var mat_soldier: StandardMaterial3D
static var mat_fire_rate: StandardMaterial3D
static var mat_damage: StandardMaterial3D

static func init_cache() -> void:
	if shared_box_mesh == null:
		shared_box_mesh = BoxMesh.new()
		shared_box_mesh.size = Vector3(3.2, 3.0, 0.25)
		
		# 1. Soldier用マテリアル (シアン)
		mat_soldier = StandardMaterial3D.new()
		mat_soldier.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_soldier.albedo_color = Color(0.1, 0.7, 1.0, 0.45)
		mat_soldier.emission_enabled = true
		mat_soldier.emission = Color(0.1, 0.7, 1.0)
		mat_soldier.emission_energy_multiplier = 2.2
		
		# 2. FireRate用マテリアル (ゴールド)
		mat_fire_rate = StandardMaterial3D.new()
		mat_fire_rate.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_fire_rate.albedo_color = Color(1.0, 0.85, 0.1, 0.45)
		mat_fire_rate.emission_enabled = true
		mat_fire_rate.emission = Color(1.0, 0.85, 0.1)
		mat_fire_rate.emission_energy_multiplier = 2.2
		
		# 3. Damage用マテリアル (レッド)
		mat_damage = StandardMaterial3D.new()
		mat_damage.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_damage.albedo_color = Color(1.0, 0.2, 0.4, 0.45)
		mat_damage.emission_enabled = true
		mat_damage.emission = Color(1.0, 0.2, 0.4)
		mat_damage.emission_energy_multiplier = 2.2

func _ready() -> void:
	# Layer 16 (Gate), Mask 1 (Player)
	collision_layer = 16
	collision_mask = 1
	
	init_cache()
	body_entered.connect(_on_body_entered)
	_setup_visuals()
	_update_label()

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
			frame_mesh_inst.position = Vector3(0, 1.5, 0)
			
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
			label_3d.position = Vector3(0, 1.6, 0.18)
			label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label_3d.font_size = 46
			label_3d.outline_size = 12
			label_3d.modulate = Color.WHITE
			label_3d.outline_modulate = Color.BLACK
	
	match gate_type:
		GateType.SOLDIER_ADD:
			label_3d.text = "+%d\nSOLDIERS" % int(value)
		GateType.FIRE_RATE_MUL:
			label_3d.text = "x%.1f\nFIRE RATE" % value
		GateType.DAMAGE_MUL:
			label_3d.text = "+%d%%\nDMG UP" % int((value - 1.0) * 100.0)

func _physics_process(delta: float) -> void:
	if is_collected:
		return
		
	global_position.z += move_speed * delta
	position.y = sin(Time.get_ticks_msec() * 0.005) * 0.1
	
	if global_position.z > 14.0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if is_collected:
		return
	
	if body.has_method("apply_gate_buff"):
		is_collected = true
		body.apply_gate_buff(gate_type, value)
		
		ParticleHelper.spawn_shatter_blocks(get_tree(), global_position + Vector3(0, 1.5, 0), base_color, 14, 0.35)
		
		var tween = create_tween().set_parallel(true)
		tween.tween_property(self, "scale", Vector3(1.4, 0.05, 1.4), 0.2)
		tween.tween_property(self, "modulate:a", 0.0, 0.2)
		tween.chain().tween_callback(queue_free)
