class_name Main
extends Node3D

enum GameState {
	PLAYING,
	GAME_OVER,
	VICTORY
}

@export var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")
@export var boss_scene: PackedScene = preload("res://scenes/Boss.tscn")
@export var gate_scene: PackedScene = preload("res://scenes/Gate.tscn")

var current_state: GameState = GameState.PLAYING
var score: int = 0
var current_wave: int = 1
var max_waves: int = 4

var enemies_to_spawn: int = 0
var enemies_alive: int = 0
var spawn_timer: float = 0.0

@onready var camera_3d: Camera3D = $Camera3D
@onready var player: Player = $Player
@onready var score_label: Label = $UI/HUD/ScoreLabel
@onready var squad_label: Label = $UI/HUD/SquadLabel
@onready var wave_label: Label = $UI/HUD/WaveLabel
@onready var stats_label: Label = $UI/HUD/StatsLabel
@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var victory_panel: Control = $UI/VictoryPanel
@onready var final_score_label: Label = $UI/GameOverPanel/VBox/FinalScore
@onready var victory_score_label: Label = $UI/VictoryPanel/VBox/FinalScore

func _ready() -> void:
	randomize()
	_setup_environment_and_bridge()
	_setup_ui()
	
	if player:
		player.squad_updated.connect(_on_player_squad_updated)
		_update_player_stats_ui(player.squad_size, player.fire_rate, player.damage_multiplier)
		
	_start_wave(1)

func _setup_environment_and_bridge() -> void:
	var bridge_root = Node3D.new()
	bridge_root.name = "BridgeRoot"
	add_child(bridge_root)
	
	# 床 (奥へと伸びる縦長ハイウェイ)
	var floor_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(8.4, 1.0, 95.0)
	floor_mesh.mesh = box
	floor_mesh.position = Vector3(0.0, -0.5, -25.0)
	
	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.10, 0.12, 0.16)
	floor_mat.roughness = 0.8
	floor_mesh.material_override = floor_mat
	bridge_root.add_child(floor_mesh)
	
	# サイドレール（左右の手すり）
	for x_pos in [-4.2, 4.2]:
		var rail = MeshInstance3D.new()
		var rail_box = BoxMesh.new()
		rail_box.size = Vector3(0.3, 0.45, 95.0)
		rail.mesh = rail_box
		rail.position = Vector3(x_pos, 0.22, -25.0)
		var rail_mat = StandardMaterial3D.new()
		rail_mat.albedo_color = Color(0.2, 0.3, 0.45)
		rail_mat.emission_enabled = true
		rail_mat.emission = Color(0.0, 0.5, 1.0) * 0.6
		rail.material_override = rail_mat
		bridge_root.add_child(rail)
	
	# 道路の中央白破線
	for z_i in range(-65, 10, 6):
		var stripe = MeshInstance3D.new()
		var stripe_box = BoxMesh.new()
		stripe_box.size = Vector3(0.25, 0.02, 3.0)
		stripe.mesh = stripe_box
		stripe.position = Vector3(0.0, 0.01, float(z_i))
		var stripe_mat = StandardMaterial3D.new()
		stripe_mat.albedo_color = Color(0.6, 0.7, 0.9, 0.4)
		stripe_mat.emission_enabled = true
		stripe_mat.emission = Color(0.1, 0.3, 0.6)
		stripe.material_override = stripe_mat
		bridge_root.add_child(stripe)
	
	# 防衛ライン (手前 Z = 10.0 に赤色ネオンライン)
	var line_mesh = MeshInstance3D.new()
	var line_box = BoxMesh.new()
	line_box.size = Vector3(8.2, 0.05, 0.4)
	line_mesh.mesh = line_box
	line_mesh.position = Vector3(0.0, 0.03, 10.0)
	var line_mat = StandardMaterial3D.new()
	line_mat.albedo_color = Color(1.0, 0.1, 0.1)
	line_mat.emission_enabled = true
	line_mat.emission = Color(1.0, 0.1, 0.1) * 3.5
	line_mesh.material_override = line_mat
	bridge_root.add_child(line_mesh)
	
	# 防衛ラインの警告テキスト
	var defense_label = Label3D.new()
	defense_label.text = "[ DEFENSE LINE ]"
	defense_label.font_size = 32
	defense_label.modulate = Color(1.0, 0.3, 0.3)
	defense_label.outline_size = 8
	defense_label.position = Vector3(0.0, 0.1, 10.0)
	defense_label.rotation_degrees = Vector3(-90, 0, 0)
	bridge_root.add_child(defense_label)

func _setup_ui() -> void:
	game_over_panel.visible = false
	victory_panel.visible = false
	_update_score_ui()

func _process(delta: float) -> void:
	# カメラ追従 (プレイヤーの左右X移動に合わせて少しシフト)
	if is_instance_valid(player) and camera_3d:
		camera_3d.global_position.x = lerp(camera_3d.global_position.x, player.global_position.x * 0.4, delta * 6.0)
		
	if current_state != GameState.PLAYING:
		if Input.is_action_just_pressed("restart"):
			_restart_game()
		return
		
	# 敵スポーンタイマー
	if enemies_to_spawn > 0:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			_spawn_enemy()
			spawn_timer = randf_range(0.35, 0.8) / float(current_wave)

func _start_wave(wave_num: int) -> void:
	current_wave = wave_num
	wave_label.text = "WAVE %d / %d" % [current_wave, max_waves]
	
	if current_wave < max_waves:
		enemies_to_spawn = 8 + (current_wave * 8)
		enemies_alive = enemies_to_spawn
		spawn_timer = 0.8
		_spawn_wave_gates()
	else:
		wave_label.text = "FINAL WAVE - BOSS"
		wave_label.modulate = Color(1.0, 0.2, 0.2)
		enemies_to_spawn = 0
		enemies_alive = 1
		_spawn_wave_gates(true)
		
		var tween = create_tween()
		tween.tween_interval(1.8)
		tween.tween_callback(_spawn_boss)

func _spawn_wave_gates(is_boss_wave: bool = false) -> void:
	if not gate_scene:
		return
		
	if not is_boss_wave:
		# プレイヤーの前方奥（Z = -6.0 〜 -18.0）にゲート配置
		var gate = gate_scene.instantiate() as Gate
		add_child(gate)
		gate.global_position = Vector3(0, 0, -2.0 - (current_wave * 5.0))
		
		var rand_type = randi() % 3
		match rand_type:
			0:
				gate.set_gate_data(Gate.GateType.SOLDIER_ADD, randi_range(2, 4))
			1:
				gate.set_gate_data(Gate.GateType.FIRE_RATE_MUL, 1.4)
			2:
				gate.set_gate_data(Gate.GateType.DAMAGE_MUL, 1.5)
	else:
		# ボス戦前は強力なゲートを配置
		var gate = gate_scene.instantiate() as Gate
		add_child(gate)
		gate.global_position = Vector3(0, 0, -4.0)
		gate.set_gate_data(Gate.GateType.SOLDIER_ADD, 5)

func _spawn_enemy() -> void:
	if not enemy_scene or enemies_to_spawn <= 0:
		return
		
	enemies_to_spawn -= 1
	var enemy = enemy_scene.instantiate() as Enemy
	add_child(enemy)
	
	# スポーン座標 (奥 -Z のランダムなX位置)
	var spawn_x = randf_range(-3.0, 3.0)
	var spawn_z = randf_range(-42.0, -34.0)
	enemy.global_position = Vector3(spawn_x, 0, spawn_z)
	
	enemy.max_hp = 20.0 + (current_wave * 12.0)
	enemy.current_hp = enemy.max_hp
	enemy.move_speed = 2.4 + (current_wave * 0.35)
	
	enemy.enemy_defeated.connect(_on_enemy_defeated)
	enemy.breached_defense.connect(_on_defense_breached)

func _spawn_boss() -> void:
	if not boss_scene:
		return
		
	var boss = boss_scene.instantiate() as Boss
	add_child(boss)
	boss.global_position = Vector3(0.0, 0, -42.0)
	
	boss.boss_defeated.connect(_on_boss_defeated)
	boss.breached_defense.connect(_on_defense_breached)

func _on_enemy_defeated(reward: int) -> void:
	score += reward
	enemies_alive -= 1
	_update_score_ui()
	
	if enemies_alive <= 0 and current_wave < max_waves:
		var tween = create_tween()
		tween.tween_interval(2.0)
		tween.tween_callback(func(): _start_wave(current_wave + 1))

func _on_boss_defeated(reward: int) -> void:
	score += reward
	_update_score_ui()
	_trigger_victory()

func _on_defense_breached(_target: Node3D) -> void:
	if current_state != GameState.PLAYING:
		return
	_trigger_game_over()

func _trigger_game_over() -> void:
	current_state = GameState.GAME_OVER
	final_score_label.text = "FINAL SCORE: %d" % score
	game_over_panel.visible = true
	game_over_panel.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.4)

func _trigger_victory() -> void:
	current_state = GameState.VICTORY
	victory_score_label.text = "CLEAR SCORE: %d" % score
	victory_panel.visible = true
	victory_panel.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(victory_panel, "modulate:a", 1.0, 0.4)

func _on_player_squad_updated(size: int, fire_r: float, dmg_mult: float) -> void:
	_update_player_stats_ui(size, fire_r, dmg_mult)

func _update_score_ui() -> void:
	score_label.text = "SCORE: %d" % score

func _update_player_stats_ui(size: int, fire_r: float, dmg_mult: float) -> void:
	squad_label.text = "SQUAD: %d SOLDIERS" % size
	stats_label.text = "ROF: %.1f/s | DMG: x%.1f" % [fire_r, dmg_mult]

func _restart_game() -> void:
	get_tree().reload_current_scene()
