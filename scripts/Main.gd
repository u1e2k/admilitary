class_name Main
extends Node3D

enum GameState {
	TITLE_SCREEN,
	PLAYING,
	LEVEL_UP_SELECT,
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
var exp_to_next_level: int = 60

var enemies_to_spawn: Array[Dictionary] = []
var spawn_timer: float = 0.0
var gate_spawn_timer: float = 0.0
var is_wave_transitioning: bool = false

# レベルアップ選択肢用
var current_upgrade_options: Array[Dictionary] = []
var selected_card_index: int = 0

@onready var camera_3d: Camera3D = $Camera3D
@onready var game_world: Node3D = $GameWorld
@onready var player: Player = $GameWorld/Player

# UI Nodes
@onready var ui_layer: CanvasLayer = $UI
@onready var hud: Control = $UI/HUD
@onready var title_panel: Control = $UI/TitlePanel
@onready var level_up_panel: Control = $UI/LevelUpPanel
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

@onready var cards_container: HBoxContainer = $UI/LevelUpPanel/VBox/CardsContainer

func _ready() -> void:
	# MainとUIはポーズ中も入力を処理
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ui_layer:
		ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	if game_world:
		game_world.process_mode = Node.PROCESS_MODE_PAUSABLE # ポーズ時に完全に静止
		
	randomize()
	_setup_environment_and_bridge()
	_setup_ui()
	
	if player:
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		player.is_control_active = false
		player.squad_updated.connect(_on_player_squad_updated)
		_update_player_stats_ui(player.squad_size, player.fire_rate, player.damage_multiplier)
		
	_show_title_screen()

func _setup_environment_and_bridge() -> void:
	var bridge_root = Node3D.new()
	bridge_root.name = "BridgeRoot"
	bridge_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	game_world.add_child(bridge_root)
	
	# 床
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
	
	# サイドレール
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
	
	# 道路白破線
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
	
	# 防衛ライン
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
	level_up_panel.visible = false
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
			
		GameState.LEVEL_UP_SELECT:
			_handle_level_up_input()
			return
			
		GameState.GAME_OVER, GameState.VICTORY:
			if Input.is_action_just_pressed("restart") or Input.is_action_just_pressed("ui_accept"):
				_restart_game()
			return

	if not get_tree().paused and current_state == GameState.PLAYING:
		# カメラ追従
		if is_instance_valid(player) and camera_3d:
			camera_3d.global_position.x = lerp(camera_3d.global_position.x, player.global_position.x * 0.45, delta * 6.0)
			
		# 敵スポーン
		if enemies_to_spawn.size() > 0:
			spawn_timer -= delta
			if spawn_timer <= 0.0:
				_spawn_next_enemy()
				spawn_timer = randf_range(0.25, 0.55)
				
		# ゲートスポーン
		gate_spawn_timer -= delta
		if gate_spawn_timer <= 0.0:
			_spawn_pair_gates()
			gate_spawn_timer = randf_range(8.0, 12.0)
			
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
	gate_spawn_timer = 2.0
	
	if current_wave < max_waves:
		wave_label.text = "WAVE %d / %d" % [current_wave, max_waves]
		wave_label.modulate = Color(1.0, 0.85, 0.2)
		_build_wave_queue(current_wave)
		spawn_timer = 0.5
	else:
		wave_label.text = "FINAL WAVE - BOSS"
		wave_label.modulate = Color(1.0, 0.2, 0.2)
		enemies_to_spawn.clear()
		_spawn_pair_gates(true)
		
		var timer = get_tree().create_timer(2.0, false)
		timer.timeout.connect(_spawn_boss)

func _build_wave_queue(wave: int) -> void:
	enemies_to_spawn.clear()
	var mult = 1.0 + (wave * 0.2)
	
	match wave:
		1: # Walker 10体
			for i in range(10):
				enemies_to_spawn.append({"type": Enemy.EnemyType.WALKER, "mult": mult})
		2: # Walker 8 + Runner 6
			for i in range(8):
				enemies_to_spawn.append({"type": Enemy.EnemyType.WALKER, "mult": mult})
			for i in range(6):
				enemies_to_spawn.append({"type": Enemy.EnemyType.RUNNER, "mult": mult})
		3: # Runnerラッシュ 16体
			for i in range(16):
				enemies_to_spawn.append({"type": Enemy.EnemyType.RUNNER, "mult": mult})
		4: # Walker 10 + Tank 3
			for i in range(10):
				enemies_to_spawn.append({"type": Enemy.EnemyType.WALKER, "mult": mult})
			for i in range(3):
				enemies_to_spawn.append({"type": Enemy.EnemyType.TANK, "mult": mult})
		5: # 複合部隊
			for i in range(12):
				enemies_to_spawn.append({"type": Enemy.EnemyType.WALKER, "mult": mult})
			for i in range(10):
				enemies_to_spawn.append({"type": Enemy.EnemyType.RUNNER, "mult": mult})
			for i in range(4):
				enemies_to_spawn.append({"type": Enemy.EnemyType.TANK, "mult": mult})
		6: # 高速大群
			for i in range(22):
				enemies_to_spawn.append({"type": Enemy.EnemyType.RUNNER, "mult": mult})
			for i in range(5):
				enemies_to_spawn.append({"type": Enemy.EnemyType.TANK, "mult": mult})
		7: # 重装軍団
			for i in range(15):
				enemies_to_spawn.append({"type": Enemy.EnemyType.WALKER, "mult": mult})
			for i in range(15):
				enemies_to_spawn.append({"type": Enemy.EnemyType.RUNNER, "mult": mult})
			for i in range(8):
				enemies_to_spawn.append({"type": Enemy.EnemyType.TANK, "mult": mult})
				
	enemies_to_spawn.shuffle()

func _spawn_pair_gates(is_boss: bool = false) -> void:
	if not gate_scene:
		return
		
	var gate_types = [Gate.GateType.SOLDIER_ADD, Gate.GateType.FIRE_RATE_MUL, Gate.GateType.DAMAGE_MUL]
	gate_types.shuffle()
	
	var gate_left = gate_scene.instantiate() as Gate
	gate_left.process_mode = Node.PROCESS_MODE_PAUSABLE
	game_world.add_child(gate_left)
	gate_left.global_position = Vector3(-2.0, 0, -32.0)
	_configure_gate(gate_left, gate_types[0], is_boss)
	
	var gate_right = gate_scene.instantiate() as Gate
	gate_right.process_mode = Node.PROCESS_MODE_PAUSABLE
	game_world.add_child(gate_right)
	gate_right.global_position = Vector3(2.0, 0, -32.0)
	_configure_gate(gate_right, gate_types[1], is_boss)

func _configure_gate(gate: Gate, type: Gate.GateType, is_boss: bool) -> void:
	match type:
		Gate.GateType.SOLDIER_ADD:
			gate.set_gate_data(type, 3 if not is_boss else 5)
		Gate.GateType.FIRE_RATE_MUL:
			gate.set_gate_data(type, 1.35 if not is_boss else 1.8)
		Gate.GateType.DAMAGE_MUL:
			gate.set_gate_data(type, 1.4 if not is_boss else 2.0)

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
	current_state = GameState.LEVEL_UP_SELECT
	get_tree().paused = true # GameWorld配下の全オブジェクトが確実に完全停止！
	
	if player:
		player.is_control_active = false
		
	_generate_level_up_options()
	_display_level_up_cards()
	
	level_up_panel.visible = true
	level_up_panel.modulate.a = 1.0

func _generate_level_up_options() -> void:
	current_upgrade_options.clear()
	selected_card_index = 0
	
	var pool = [
		{"type": "SOLDIER_1", "title": "+1 SOLDIER", "desc": "部隊に兵士を1体増員\n弾幕の幅が広がる", "color": Color(0.2, 0.8, 1.0)},
		{"type": "FIRE_RATE", "title": "+25% FIRE RATE", "desc": "マシンガン連射速度UP\n制圧力アップ", "color": Color(1.0, 0.85, 0.2)},
		{"type": "DAMAGE", "title": "+30% DAMAGE", "desc": "弾丸の単発威力を強化\n敵を素早く撃破", "color": Color(1.0, 0.3, 0.3)},
		{"type": "SOLDIER_2", "title": "+2 SOLDIERS", "desc": "部隊に兵士を2体一括増員\n一気に火力を増強", "color": Color(0.4, 1.0, 0.6)},
		{"type": "OVERDRIVE", "title": "OVERDRIVE", "desc": "連射速度 +15%\n攻撃力 +15%", "color": Color(0.9, 0.4, 1.0)}
	]
	pool.shuffle()
	current_upgrade_options.append(pool[0])
	current_upgrade_options.append(pool[1])
	current_upgrade_options.append(pool[2])

func _display_level_up_cards() -> void:
	for child in cards_container.get_children():
		child.queue_free()
		
	for i in range(current_upgrade_options.size()):
		var opt = current_upgrade_options[i]
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(200, 260)
		
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.theme_override_constants.separation = 12
		card.add_child(vbox)
		
		var key_label = Label.new()
		key_label.text = "[ %d / %s ]" % [i + 1, "A" if i == 0 else ("B" if i == 1 else "X")]
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		vbox.add_child(key_label)
		
		var title = Label.new()
		title.text = opt["title"]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_color_override("font_color", opt["color"])
		title.add_theme_font_size_override("font_size", 18)
		vbox.add_child(title)
		
		var desc = Label.new()
		desc.text = opt["desc"]
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.add_theme_font_size_override("font_size", 13)
		vbox.add_child(desc)
		
		cards_container.add_child(card)
	
	_highlight_selected_card()

func _highlight_selected_card() -> void:
	var children = cards_container.get_children()
	for i in range(children.size()):
		var card = children[i] as PanelContainer
		if i == selected_card_index:
			card.modulate = Color(1.2, 1.2, 1.2, 1.0)
		else:
			card.modulate = Color(0.65, 0.65, 0.65, 0.85)

func _handle_level_up_input() -> void:
	if Input.is_action_just_pressed("move_left"):
		selected_card_index = posmod(selected_card_index - 1, 3)
		_highlight_selected_card()
	elif Input.is_action_just_pressed("move_right"):
		selected_card_index = posmod(selected_card_index + 1, 3)
		_highlight_selected_card()
	elif Input.is_action_just_pressed("ui_accept"):
		_apply_upgrade_choice(selected_card_index)
	elif Input.is_action_just_pressed("ui_select_1"):
		_apply_upgrade_choice(0)
	elif Input.is_action_just_pressed("ui_select_2"):
		_apply_upgrade_choice(1)
	elif Input.is_action_just_pressed("ui_select_3"):
		_apply_upgrade_choice(2)

func _apply_upgrade_choice(idx: int) -> void:
	if idx < 0 or idx >= current_upgrade_options.size():
		return
		
	var opt = current_upgrade_options[idx]
	match opt["type"]:
		"SOLDIER_1":
			player.add_soldiers(1)
		"SOLDIER_2":
			player.add_soldiers(2)
		"FIRE_RATE":
			player.upgrade_fire_rate(1.25)
		"DAMAGE":
			player.upgrade_damage(1.30)
		"OVERDRIVE":
			player.upgrade_fire_rate(1.15)
			player.upgrade_damage(1.15)
			
	level_up_panel.visible = false
	current_state = GameState.PLAYING
	get_tree().paused = false # ゲーム再開！
	
	if player:
		player.is_control_active = true
		
	_check_wave_cleared()

func _on_defense_breached(_target: Node3D) -> void:
	if current_state != GameState.PLAYING and current_state != GameState.LEVEL_UP_SELECT:
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
