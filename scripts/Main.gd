class_name Main
extends Node3D

enum GameState {
	TITLE_SCREEN,
	PLAYING,
	PAUSED,
	GAME_OVER,
	VICTORY
}

@export var enemy_scene: PackedScene = preload("res://scenes/Enemy.tscn")
@export var boss_scene: PackedScene = preload("res://scenes/Boss.tscn")
@export var gate_scene: PackedScene = preload("res://scenes/Gate.tscn")

var current_state: GameState = GameState.TITLE_SCREEN
var score: int = 0
var current_wave: int = 1
var max_waves: int = 8

# レベル＆経験値システム
var current_level: int = 1
var current_exp: int = 0
var exp_to_next_level: int = 50

var enemies_to_spawn: Array[Dictionary] = []
var spawn_timer: float = 0.0
var is_wave_transitioning: bool = false

# ゲート用オブジェクトプール
var gate_pool: Array[Gate] = []

@onready var camera_3d: Camera3D = $Camera3D
@onready var game_world: Node3D = $GameWorld
@onready var player: Player = $GameWorld/Player

# UI Nodes
@onready var ui_layer: CanvasLayer = $UI
@onready var hud: Control = $UI/HUD
@onready var title_panel: Control = $UI/TitlePanel
@onready var level_up_banner: Control = $UI/LevelUpBanner
@onready var level_up_label: Label = $UI/LevelUpBanner/VBox/Title
@onready var pause_panel: Control = $UI/PausePanel
@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var victory_panel: Control = $UI/VictoryPanel

@onready var score_label: Label = $UI/HUD/ScoreLabel
@onready var squad_label: Label = $UI/HUD/SquadLabel
@onready var wave_label: Label = $UI/HUD/WaveLabel
@onready var stats_label: Label = $UI/HUD/StatsLabel
@onready var level_label: Label = $UI/HUD/LevelLabel
@onready var exp_bar: ProgressBar = $UI/HUD/ExpBar

@onready var final_score_label: Label = $UI/GameOverPanel/VBox/FinalScore
@onready var victory_score_label: Label = $UI/VictoryPanel/VBox/FinalScore

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ui_layer:
		ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	if game_world:
		game_world.process_mode = Node.PROCESS_MODE_PAUSABLE
		
	randomize()
	Gate.init_cache()
	_setup_environment_and_bridge()
	_setup_ui()
	_init_gate_pool()
	_warmup_assets()
	
	if player:
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		player.is_control_active = false
		player.squad_updated.connect(_on_player_squad_updated)
		_update_player_stats_ui(player.squad_size, player.fire_rate, player.damage_multiplier)
		
	_show_title_screen()

func _init_gate_pool() -> void:
	if not gate_scene or not game_world:
		return
		
	for i in range(8):
		var gate = gate_scene.instantiate() as Gate
		game_world.add_child(gate)
		gate.set_gate_data(i % 3 as Gate.GateType, 3.0)
		gate.deactivate()
		gate_pool.append(gate)

func _get_free_gate_from_pool() -> Gate:
	for gate in gate_pool:
		if is_instance_valid(gate) and not gate.is_active:
			return gate
			
	var new_gate = gate_scene.instantiate() as Gate
	game_world.add_child(new_gate)
	new_gate.deactivate()
	gate_pool.append(new_gate)
	return new_gate

func _warmup_assets() -> void:
	if not game_world:
		return
		
	var warmup_root = Node3D.new()
	warmup_root.position = Vector3(0, -200, 0)
	game_world.add_child(warmup_root)
	
	if enemy_scene:
		var dummy_enemy = enemy_scene.instantiate() as Enemy
		warmup_root.add_child(dummy_enemy)
	if boss_scene:
		var dummy_boss = boss_scene.instantiate() as Boss
		warmup_root.add_child(dummy_boss)
		
	var timer = get_tree().create_timer(0.1, false)
	timer.timeout.connect(func():
		if is_instance_valid(warmup_root):
			warmup_root.queue_free()
	)

func _setup_environment_and_bridge() -> void:
	var bridge_root = Node3D.new()
	bridge_root.name = "BridgeRoot"
	bridge_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	game_world.add_child(bridge_root)
	
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
	
	var defense_label = Label3D.new()
	defense_label.text = "[ DEFENSE LINE ]"
	defense_label.font_size = 32
	defense_label.modulate = Color(1.0, 0.3, 0.3)
	defense_label.outline_size = 8
	defense_label.position = Vector3(0.0, 0.1, 10.0)
	defense_label.rotation_degrees = Vector3(-90, 0, 0)
	bridge_root.add_child(defense_label)

func _setup_ui() -> void:
	hud.visible = false
	title_panel.visible = false
	level_up_banner.visible = false
	pause_panel.visible = false
	game_over_panel.visible = false
	victory_panel.visible = false
	_update_score_ui()
	_update_exp_ui()

func _show_title_screen() -> void:
	current_state = GameState.TITLE_SCREEN
	get_tree().paused = false
	hud.visible = false
	title_panel.visible = true
	title_panel.modulate.a = 1.0

func _start_game() -> void:
	current_state = GameState.PLAYING
	get_tree().paused = false
	title_panel.visible = false
	hud.visible = true
	if player:
		player.is_control_active = true
	_start_wave(1)

func _process(delta: float) -> void:
	match current_state:
		GameState.TITLE_SCREEN:
			if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("restart") or Input.is_action_just_pressed("pause"):
				_start_game()
			return
			
		GameState.PLAYING:
			if Input.is_action_just_pressed("pause"):
				_toggle_pause()
				return
				
		GameState.PAUSED:
			if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("ui_accept"):
				_toggle_pause()
			elif Input.is_action_just_pressed("restart"):
				_restart_game()
			return
			
		GameState.GAME_OVER, GameState.VICTORY:
			if Input.is_action_just_pressed("restart") or Input.is_action_just_pressed("ui_accept"):
				_restart_game()
			return

	if not get_tree().paused and current_state == GameState.PLAYING:
		if is_instance_valid(player) and camera_3d:
			camera_3d.global_position.x = lerp(camera_3d.global_position.x, player.global_position.x * 0.45, delta * 6.0)
			
		if enemies_to_spawn.size() > 0:
			spawn_timer -= delta
			if spawn_timer <= 0.0:
				_spawn_next_enemy()
				spawn_timer = randf_range(0.25, 0.55)
				
		_check_wave_cleared()

func _toggle_pause() -> void:
	if current_state == GameState.PLAYING:
		current_state = GameState.PAUSED
		get_tree().paused = true
		pause_panel.visible = true
		if player:
			player.is_control_active = false
	elif current_state == GameState.PAUSED:
		current_state = GameState.PLAYING
		get_tree().paused = false
		pause_panel.visible = false
		if player:
			player.is_control_active = true

func _start_wave(wave_num: int) -> void:
	current_wave = wave_num
	is_wave_transitioning = false
	
	if current_wave < max_waves:
		wave_label.text = "WAVE %d / %d" % [current_wave, max_waves]
		wave_label.modulate = Color(1.0, 0.85, 0.2)
		_build_wave_queue(current_wave)
		spawn_timer = 0.5
	else:
		wave_label.text = "FINAL WAVE - BOSS"
		wave_label.modulate = Color(1.0, 0.2, 0.2)
		enemies_to_spawn.clear()
		_spawn_pair_gates(true) # ボス前ボーナスゲート
		
		var timer = get_tree().create_timer(2.0, false)
		timer.timeout.connect(_spawn_boss)

func _build_wave_queue(wave: int) -> void:
	enemies_to_spawn.clear()
	var mult = 1.0 + (wave * 0.2)
	
	match wave:
		1:
			for i in range(10):
				enemies_to_spawn.append({"type": Enemy.EnemyType.WALKER, "mult": mult})
		2:
			for i in range(8):
				enemies_to_spawn.append({"type": Enemy.EnemyType.WALKER, "mult": mult})
			for i in range(6):
				enemies_to_spawn.append({"type": Enemy.EnemyType.RUNNER, "mult": mult})
		3:
			for i in range(16):
				enemies_to_spawn.append({"type": Enemy.EnemyType.RUNNER, "mult": mult})
		4:
			for i in range(10):
				enemies_to_spawn.append({"type": Enemy.EnemyType.WALKER, "mult": mult})
			for i in range(3):
				enemies_to_spawn.append({"type": Enemy.EnemyType.TANK, "mult": mult})
		5:
			for i in range(12):
				enemies_to_spawn.append({"type": Enemy.EnemyType.WALKER, "mult": mult})
			for i in range(10):
				enemies_to_spawn.append({"type": Enemy.EnemyType.RUNNER, "mult": mult})
			for i in range(4):
				enemies_to_spawn.append({"type": Enemy.EnemyType.TANK, "mult": mult})
		6:
			for i in range(22):
				enemies_to_spawn.append({"type": Enemy.EnemyType.RUNNER, "mult": mult})
			for i in range(5):
				enemies_to_spawn.append({"type": Enemy.EnemyType.TANK, "mult": mult})
		7:
			for i in range(15):
				enemies_to_spawn.append({"type": Enemy.EnemyType.WALKER, "mult": mult})
			for i in range(15):
				enemies_to_spawn.append({"type": Enemy.EnemyType.RUNNER, "mult": mult})
			for i in range(8):
				enemies_to_spawn.append({"type": Enemy.EnemyType.TANK, "mult": mult})
				
	enemies_to_spawn.shuffle()

## 二者択一排他ペアゲートのスポーン（レベルアップ時＆ボス前のみ）
func _spawn_pair_gates(is_boss: bool = false, is_level_up: bool = false) -> void:
	var gate_types = [Gate.GateType.SOLDIER_ADD, Gate.GateType.FIRE_RATE_MUL, Gate.GateType.DAMAGE_MUL]
	gate_types.shuffle()
	
	var gate_left = _get_free_gate_from_pool()
	var gate_right = _get_free_gate_from_pool()
	
	var val_left = (2.0 if is_level_up else 1.0) if not is_boss else 3.0
	if gate_types[0] == Gate.GateType.FIRE_RATE_MUL:
		val_left = (1.25 if is_level_up else 1.15) if not is_boss else 1.35
	elif gate_types[0] == Gate.GateType.DAMAGE_MUL:
		val_left = (1.5 if is_level_up else 1.35) if not is_boss else 1.8
		
	var val_right = (2.0 if is_level_up else 1.0) if not is_boss else 3.0
	if gate_types[1] == Gate.GateType.FIRE_RATE_MUL:
		val_right = (1.25 if is_level_up else 1.15) if not is_boss else 1.35
	elif gate_types[1] == Gate.GateType.DAMAGE_MUL:
		val_right = (1.5 if is_level_up else 1.35) if not is_boss else 1.8
	
	# 幅を適正化し、相互リンクを設定（片方を取るともう片方が即消滅）
	gate_left.activate(gate_types[0], val_left, Vector3(-2.2, 0, -35.0), gate_right)
	gate_right.activate(gate_types[1], val_right, Vector3(2.2, 0, -35.0), gate_left)

func _spawn_next_enemy() -> void:
	if not enemy_scene or enemies_to_spawn.is_empty():
		return
		
	var data = enemies_to_spawn.pop_back()
	var enemy = enemy_scene.instantiate() as Enemy
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	game_world.add_child(enemy)
	
	var spawn_x = randf_range(-3.0, 3.0)
	var spawn_z = randf_range(-42.0, -35.0)
	enemy.global_position = Vector3(spawn_x, 0, spawn_z)
	
	enemy.set_enemy_type(data["type"], data["mult"])
	enemy.enemy_defeated.connect(_on_enemy_defeated)
	enemy.breached_defense.connect(_on_defense_breached)

func _spawn_boss() -> void:
	if not boss_scene:
		return
		
	var boss = boss_scene.instantiate() as Boss
	boss.process_mode = Node.PROCESS_MODE_PAUSABLE
	game_world.add_child(boss)
	boss.global_position = Vector3(0.0, 0, -42.0)
	
	boss.boss_defeated.connect(_on_boss_defeated)
	boss.breached_defense.connect(_on_defense_breached)

func _on_enemy_defeated(reward: int, exp_reward: int) -> void:
	score += reward
	_update_score_ui()
	_add_exp(exp_reward)
	_check_wave_cleared()

func _on_boss_defeated(reward: int, exp_reward: int) -> void:
	score += reward
	_update_score_ui()
	_add_exp(exp_reward)
	_trigger_victory()

func _check_wave_cleared() -> void:
	if is_wave_transitioning or current_wave >= max_waves:
		return
	if current_state != GameState.PLAYING:
		return
		
	if enemies_to_spawn.is_empty():
		var alive_enemies = get_tree().get_nodes_in_group("enemies")
		if alive_enemies.is_empty():
			is_wave_transitioning = true
			var timer = get_tree().create_timer(1.8, false)
			timer.timeout.connect(func():
				if current_state == GameState.PLAYING and current_wave < max_waves:
					_start_wave(current_wave + 1)
			)

# EXP & レベルアップ (敵を倒してレベルアップした時のみ報酬ゲートをポップ！)
func _add_exp(amount: int) -> void:
	current_exp += amount
	if current_exp >= exp_to_next_level:
		current_exp -= exp_to_next_level
		current_level += 1
		exp_to_next_level = int(exp_to_next_level * 1.45)
		_trigger_level_up()
	_update_exp_ui()

func _update_exp_ui() -> void:
	level_label.text = "LV %d" % current_level
	exp_bar.max_value = exp_to_next_level
	exp_bar.value = current_exp

func _trigger_level_up() -> void:
	_spawn_pair_gates(false, true)
	
	level_up_label.text = "★ LEVEL UP! (LV %d) REWARD GATES INCOMING ★" % current_level
	level_up_banner.visible = true
	level_up_banner.modulate.a = 0.0
	level_up_banner.scale = Vector2(0.85, 0.85)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(level_up_banner, "modulate:a", 1.0, 0.2)
	tween.tween_property(level_up_banner, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	var hide_tween = create_tween()
	hide_tween.tween_interval(2.2)
	hide_tween.tween_property(level_up_banner, "modulate:a", 0.0, 0.5)
	hide_tween.tween_callback(func(): level_up_banner.visible = false)

func _on_defense_breached(_target: Node3D) -> void:
	if current_state != GameState.PLAYING:
		return
	_trigger_game_over()

func _trigger_game_over() -> void:
	current_state = GameState.GAME_OVER
	get_tree().paused = true
	if player:
		player.is_control_active = false
	final_score_label.text = "FINAL SCORE: %d" % score
	game_over_panel.visible = true
	game_over_panel.modulate.a = 1.0

func _trigger_victory() -> void:
	current_state = GameState.VICTORY
	get_tree().paused = true
	if player:
		player.is_control_active = false
	victory_score_label.text = "CLEAR SCORE: %d" % score
	victory_panel.visible = true
	victory_panel.modulate.a = 1.0

func _on_player_squad_updated(size: int, fire_r: float, dmg_mult: float) -> void:
	_update_player_stats_ui(size, fire_r, dmg_mult)

func _update_score_ui() -> void:
	score_label.text = "SCORE: %d" % score

func _update_player_stats_ui(size: int, fire_r: float, dmg_mult: float) -> void:
	squad_label.text = "SQUAD: %d SOLDIERS" % size
	stats_label.text = "ROF: %.1f/s | DMG: x%.1f" % [fire_r, dmg_mult]

func _restart_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
