extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const HUDScript = preload("res://scripts/hud.gd")
const WeaponCatalog = preload("res://scripts/weapon_catalog.gd")
const GrenadeScript = preload("res://scripts/grenade.gd")
const SmokeScript = preload("res://scripts/smoke_cloud.gd")
const NetworkAvatarScript = preload("res://scripts/network_avatar.gd")
const MapDefinition = preload("res://scripts/map_definition.gd")
const InteractableScript = preload("res://scripts/interactable.gd")
const EffectsManagerScript = preload("res://scripts/effects_manager.gd")
const QualityManager = preload("res://scripts/quality_manager.gd")
const Ballistics = preload("res://scripts/ballistics_manager.gd")
const MeleeResolver = preload("res://scripts/melee_resolver.gd")
const PhysicsPropScript = preload("res://scripts/physics_prop.gd")
const DroppedWeaponScript = preload("res://scripts/dropped_weapon.gd")
const FireZoneScript = preload("res://scripts/fire_zone.gd")
const RagdollScript = preload("res://scripts/ragdoll.gd")
const SandboxBrowserScene = preload("res://scenes/ui/sandbox_browser.tscn")
const SandboxSpawnControllerScript = preload("res://scripts/sandbox_spawn_controller.gd")
const SandboxItemDefinition = preload("res://scripts/sandbox_item_definition.gd")
const FoundryScene = preload("res://scenes/maps/foundry_sandbox.tscn")
const ConcreteDiffuse = preload("res://assets/textures/concrete_floor_worn_001_diff_1k.jpg")
const ConcreteNormal = preload("res://assets/textures/concrete_floor_worn_001_normal_1k.jpg")
const ConcreteArm = preload("res://assets/textures/concrete_floor_worn_001_arm_1k.jpg")
const MetalDiffuse = preload("res://assets/textures/metal_plate_diff_1k.jpg")
const MetalNormal = preload("res://assets/textures/metal_plate_normal_1k.jpg")
const MetalArm = preload("res://assets/textures/metal_plate_arm_1k.jpg")

enum Phase { BUY, LIVE, ENDED }

var levels: Array[LocalStrikeMapDefinition] = []
var level_index := 0
var current_level: LocalStrikeMapDefinition
var sites: Array[Dictionary] = []
var interactables: Dictionary = {}
var physics_props: Dictionary = {}
var dropped_weapons: Dictionary = {}
var enemies: Array[LocalStrikeEnemy] = []
var allies: Array[LocalStrikeEnemy] = []
var replicated_bots: Dictionary = {}
var remote_avatars: Dictionary = {}
var pending_respawns: Array[Dictionary] = []
var sandbox_ragdolls: Array[Node3D] = []

var player: LocalStrikePlayer
var hud: LocalStrikeHUD
var level_root: Node3D
var effect_root: Node3D
var effects: LocalStrikeEffectsManager
var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var charge_mesh: Node3D
var spectator_camera: Camera3D
var spectator_target: Node3D

var started := false
var paused := false
var phase := Phase.BUY
var show_buy := true
var round_no := 0
var attack_score := 0
var defense_score := 0
var phase_timer := 105.0
var freeze_timer := 8.0
var round_end_timer := 0.0
var plant_progress := 0.0
var defuse_progress := 0.0
var bomb_timer := 0.0
var charge_planted := false
var charge_position := Vector3.ZERO
var material_cache: Dictionary = {}
var normal_texture_cache: Dictionary = {}
var game_mode := LocalStrikeMatchConfig.Mode.DEFUSAL
var bot_difficulty := LocalStrikeMatchConfig.Difficulty.VETERAN
var player_dead := false
var player_respawn_timer := 0.0
var deathmatch_timer := 480.0
var network_sync_timer := 0.0
var bot_sync_timer := 0.0
var current_quality := 0
var player_team := 0
var network_spawn_slot := 0
var match_over := false
var peer_shot_state: Dictionary = {}
var peer_melee_state: Dictionary = {}
var prop_sync_timer := 0.0
var next_drop_id := 1
var next_network_bot_id := 1
var sandbox_god_mode := true
var sandbox_slow_motion := false
var sandbox_spawn_serial := 0
var sandbox_browser: LocalStrikeSandboxBrowser
var sandbox_spawn_controller: LocalStrikeSandboxSpawnController

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	_ensure_input_actions()
	levels = _create_levels()
	_build_environment()

	level_root = Node3D.new()
	level_root.name = "Level"
	add_child(level_root)
	effect_root = Node3D.new()
	effect_root.name = "Effects"
	add_child(effect_root)
	effects = EffectsManagerScript.new()
	effects.name = "ImpactEffects"
	effect_root.add_child(effects)

	player = PlayerScript.new()
	player.name = "Player"
	player.enabled = false
	player.shot_fired.connect(_on_shot_fired)
	player.shot_requested.connect(_on_player_shot_requested)
	player.melee_attack_requested.connect(_on_player_melee_requested)
	player.hit_confirmed.connect(_on_hit_confirmed)
	player.player_died.connect(_on_player_died)
	player.grenade_thrown.connect(_on_grenade_thrown)
	player.reload_requested.connect(_on_player_reload_requested)
	player.damage_taken.connect(func(_amount: float): hud.show_damage() if hud != null else null)
	player.footstep.connect(AudioManager.play_footstep)
	add_child(player)
	spectator_camera = Camera3D.new()
	spectator_camera.current = false
	add_child(spectator_camera)

	hud = HUDScript.new()
	hud.solo_requested.connect(_start_solo)
	hud.host_requested.connect(_start_host)
	hud.join_requested.connect(_join_lan)
	hud.refresh_servers_requested.connect(_refresh_servers)
	hud.buy_requested.connect(_buy_weapon)
	hud.quality_changed.connect(_apply_quality)
	hud.sandbox_action_requested.connect(_on_sandbox_action)
	add_child(hud)
	sandbox_spawn_controller = SandboxSpawnControllerScript.new()
	sandbox_spawn_controller.name = "SandboxSpawnController"
	sandbox_spawn_controller.configure(player)
	sandbox_spawn_controller.placement_confirmed.connect(_on_sandbox_placement_confirmed)
	sandbox_spawn_controller.placement_state_changed.connect(_on_sandbox_placement_state_changed)
	add_child(sandbox_spawn_controller)
	sandbox_browser = SandboxBrowserScene.instantiate()
	sandbox_browser.placement_requested.connect(_on_sandbox_placement_requested)
	sandbox_browser.equip_requested.connect(func(weapon_id: String): _equip_sandbox_weapon({"weapon": weapon_id}))
	sandbox_browser.world_action_requested.connect(_on_sandbox_action)
	sandbox_browser.browser_visibility_changed.connect(_on_sandbox_browser_visibility_changed)
	add_child(sandbox_browser)
	NetworkManager.server_discovered.connect(hud.show_server)
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)
	NetworkManager.peer_joined.connect(_on_network_peer_joined)
	NetworkManager.peer_left.connect(_on_network_peer_left)

	_load_level(0)
	player.enabled = false
	hud.set_deployed(false)
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("scoreboard"):
		hud.set_scoreboard(true)
	elif event.is_action_released("scoreboard"):
		hud.set_scoreboard(false)
	if event.is_action_pressed("pause") and started:
		_set_paused(not paused)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("restart"):
		_restart_match()
		return
	if not started or paused:
		return
	if event.is_action_pressed("interact"):
		_try_interact()
	if event.is_action_pressed("drop_weapon"):
		_handle_weapon_pickup_or_drop()
	if event.is_action_pressed("toggle_buy"):
		if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX:
			sandbox_browser.toggle_browser()
		else:
			show_buy = not show_buy
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if show_buy else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX:
		if event.is_action_pressed("sandbox_enemy"):
			_on_sandbox_action("spawn_bot", {"team": "enemy", "kind": "assault", "weapon": "sentinel", "behavior": "aggressive", "count": 1})
		elif event.is_action_pressed("sandbox_ally"):
			_on_sandbox_action("spawn_bot", {"team": "ally", "kind": "assault", "weapon": "sentinel", "behavior": "aggressive", "count": 1})
		elif event.is_action_pressed("sandbox_prop"):
			_on_sandbox_action("spawn_wood", {})
		elif event.is_action_pressed("sandbox_blast"):
			_on_sandbox_action("explosion", {})
		elif event.is_action_pressed("sandbox_slow"):
			_on_sandbox_action("slow_motion", {"enabled": not sandbox_slow_motion})
		elif event.is_action_pressed("sandbox_clear"):
			_on_sandbox_action("clear", {})
	if phase == Phase.BUY and game_mode != LocalStrikeMatchConfig.Mode.SANDBOX and event.is_action_pressed("map_next"):
		level_index = (level_index + 1) % levels.size()
		if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX:
			_reset_round(false)
		else:
			_load_level(level_index)
			_spawn_teams()
		hud.show_toast("Map: %s" % current_level.map_name)
	if phase == Phase.BUY and event.is_action_pressed("weapon_1"):
		_buy_weapon("sidearm")
	elif phase == Phase.BUY and event.is_action_pressed("weapon_2"):
		_buy_weapon("ranger")
	elif phase == Phase.BUY and event.is_action_pressed("weapon_3"):
		_buy_weapon("marksman")
	elif phase == Phase.BUY and event.is_action_pressed("weapon_4"):
		_buy_weapon("breacher")

func _physics_process(delta: float) -> void:
	if not started or paused:
		_update_hud()
		return
	_update_network_state(delta)
	_update_spectator()
	if game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH:
		_update_deathmatch(delta)
		_update_hud()
		return
	if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX:
		_update_sandbox(delta)
		_update_hud()
		return

	if phase == Phase.ENDED:
		round_end_timer -= delta
		if round_end_timer <= 0.0:
			if match_over:
				_finish_match()
			else:
				_reset_round(true)
		_update_hud()
		return

	phase_timer -= delta
	if phase_timer <= 0.0:
		_end_round(false, "time")
		return

	if phase == Phase.BUY:
		freeze_timer -= delta
		if freeze_timer <= 0.0:
			phase = Phase.LIVE
			show_buy = false
			hud.show_toast("LIVE")

	_update_objective(delta)
	_update_hud()

func _start_solo(mode: int, map_index: int, difficulty: int) -> void:
	NetworkManager.leave_game()
	network_spawn_slot = 0
	var config := LocalStrikeMatchConfig.new()
	config.mode = mode
	config.map_index = map_index
	config.bot_difficulty = difficulty
	config.fill_with_bots = true
	GameSession.configure(config)
	GameSession.reset_roster()
	GameSession.register_player(1, GameSession.local_player_name, 0)
	_start_configured_match(config)

func _start_host(mode: int, map_index: int, difficulty: int) -> void:
	if mode == LocalStrikeMatchConfig.Mode.SANDBOX:
		hud.show_toast("Sandbox is available in local solo play", 3.5)
		return
	var config := LocalStrikeMatchConfig.new()
	network_spawn_slot = 0
	config.mode = mode
	config.map_index = map_index
	config.bot_difficulty = difficulty
	config.fill_with_bots = true
	GameSession.configure(config)
	var error := NetworkManager.host_game(config.max_players, config.server_name)
	if error != OK:
		hud.show_toast("Could not host LAN game: %s" % error_string(error), 4.0)
		return
	GameSession.reset_roster()
	GameSession.register_player(1, GameSession.local_player_name, 0)
	_start_configured_match(config)
	hud.show_toast("LAN host ready on UDP %d" % NetworkManager.GAME_PORT, 4.0)

func _join_lan(address: String) -> void:
	var error := NetworkManager.join_game(address)
	if error != OK:
		hud.show_toast("Could not join %s" % address, 4.0)
	else:
		hud.show_toast("Connecting to %s..." % address, 4.0)

func _refresh_servers() -> void:
	var error := NetworkManager.discover_lan_games()
	hud.show_toast("Searching local network..." if error == OK else "LAN discovery unavailable", 2.5)

func _start_configured_match(config: LocalStrikeMatchConfig) -> void:
	Engine.time_scale = 1.0
	game_mode = config.mode
	level_index = levels.size() - 1 if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX else clampi(config.map_index, 0, levels.size() - 2)
	bot_difficulty = config.bot_difficulty
	attack_score = 0
	defense_score = 0
	round_no = 0
	deathmatch_timer = 480.0
	player.money = 99999 if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX else 800
	player.authoritative_damage = not _is_network_client()
	player.invulnerable = game_mode == LocalStrikeMatchConfig.Mode.SANDBOX
	player.unlimited_ammo = game_mode == LocalStrikeMatchConfig.Mode.SANDBOX
	player.set_extended_melee_enabled(game_mode in [LocalStrikeMatchConfig.Mode.DEATHMATCH, LocalStrikeMatchConfig.Mode.SANDBOX])
	effects.set_sandbox_persistent(game_mode == LocalStrikeMatchConfig.Mode.SANDBOX)
	sandbox_god_mode = game_mode == LocalStrikeMatchConfig.Mode.SANDBOX
	sandbox_slow_motion = false
	player_dead = false
	match_over = false
	started = true
	hud.set_deployed(true)
	sandbox_browser.set_sandbox_active(game_mode == LocalStrikeMatchConfig.Mode.SANDBOX)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_reset_round(false)
	var mode_name := "DEFUSAL" if game_mode == LocalStrikeMatchConfig.Mode.DEFUSAL else ("TEAM DEATHMATCH" if game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH else "SANDBOX")
	hud.show_toast("%s - %s" % [mode_name, current_level.map_name], 3.2)

func _restart_match() -> void:
	Engine.time_scale = 1.0
	sandbox_slow_motion = false
	attack_score = 0
	defense_score = 0
	round_no = 0
	player.money = 99999 if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX else 800
	player.clear_weapon_blood()
	player.equip_weapon("sidearm", false)
	_set_paused(false)
	started = true
	player.enabled = true
	hud.set_deployed(true)
	sandbox_browser.set_sandbox_active(game_mode == LocalStrikeMatchConfig.Mode.SANDBOX)
	sandbox_spawn_controller.cancel_placement(false)
	_reset_round(false)
	hud.show_toast("Match restarted")

func _set_paused(value: bool) -> void:
	paused = value
	get_tree().paused = value
	hud.set_paused(value)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func _reset_round(show_message: bool) -> void:
	round_no += 1
	player_team = 0 if round_no <= 3 or game_mode != LocalStrikeMatchConfig.Mode.DEFUSAL else 1
	phase = Phase.LIVE if game_mode != LocalStrikeMatchConfig.Mode.DEFUSAL else Phase.BUY
	show_buy = false if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX else true
	phase_timer = 105.0
	freeze_timer = 12.0
	round_end_timer = 0.0
	plant_progress = 0.0
	defuse_progress = 0.0
	bomb_timer = 0.0
	charge_planted = false
	player_dead = false
	effects.set_sandbox_persistent(game_mode == LocalStrikeMatchConfig.Mode.SANDBOX)
	effects.clear_blood()
	player.clear_weapon_blood()
	for ragdoll in sandbox_ragdolls:
		if is_instance_valid(ragdoll):
			ragdoll.queue_free()
	sandbox_ragdolls.clear()
	_load_level(level_index)
	var spawn_position := _player_spawn_for_slot(network_spawn_slot)
	player.reset_for_round(spawn_position)
	var spawn_yaw := 0.4 if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX else (0.0 if player_team == 0 else PI)
	player.reset_view(spawn_yaw)
	player.invulnerable = sandbox_god_mode if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX else false
	player.unlimited_ammo = game_mode == LocalStrikeMatchConfig.Mode.SANDBOX
	player.enabled = started
	player.set_view_active(true)
	spectator_camera.current = false
	_spawn_teams()
	if show_message:
		hud.show_toast("Round %d: %s" % [round_no, current_level.map_name])

func _load_level(index: int) -> void:
	if sandbox_spawn_controller != null:
		sandbox_spawn_controller.cancel_placement(false)
	for child in level_root.get_children():
		level_root.remove_child(child)
		child.queue_free()
	enemies.clear()
	allies.clear()
	remote_avatars.clear()
	replicated_bots.clear()
	sites.clear()
	interactables.clear()
	physics_props.clear()
	dropped_weapons.clear()
	sandbox_ragdolls.clear()
	material_cache.clear()

	current_level = levels[index]
	_update_environment(current_level.palette)
	if current_level.environment_profile == "foundry_night":
		var foundry := FoundryScene.instantiate()
		foundry.name = "AbandonedFoundry"
		level_root.add_child(foundry)
	else:
		_create_floor(current_level.palette)
		for wall_data in current_level.walls:
			_create_wall(wall_data, current_level.palette)
		for prop_data in current_level.props:
			_create_prop(prop_data)
		for site_data in current_level.sites:
			_create_site(site_data)
		_create_map_beacons(current_level.palette)
		_create_map_identity_props()
	_create_interactables()
	_create_physics_props()
	_create_reflection_probes()
	player.reset_for_round(_player_spawn_for_slot(network_spawn_slot))

func _spawn_teams() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			if enemy.get_parent() != null:
				enemy.get_parent().remove_child(enemy)
			enemy.queue_free()
	enemies.clear()
	for ally in allies:
		if is_instance_valid(ally):
			if ally.get_parent() != null:
				ally.get_parent().remove_child(ally)
			ally.queue_free()
	allies.clear()
	replicated_bots.clear()
	if _is_network_client():
		return
	if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX:
		_refresh_bot_opponents()
		return
	var human_players := 1 + multiplayer.get_peers().size() if NetworkManager.peer != null else 1
	var team_zero_spawns: Array[Vector3] = [current_level.player_spawn]
	for offset in [Vector3(-1.2, 0, 0.5), Vector3(1.2, 0, 0.5), Vector3(-2.1, 0, 1.3), Vector3(2.1, 0, 1.3)]:
		team_zero_spawns.append(current_level.player_spawn + offset)
	var team_one_spawns: Array[Vector3] = current_level.bot_spawns.duplicate()
	var own_team_spawns: Array[Vector3] = team_zero_spawns if player_team == 0 else team_one_spawns
	var opposing_team_spawns: Array[Vector3] = team_one_spawns if player_team == 0 else team_zero_spawns
	var ally_count := maxi(0, mini(5, own_team_spawns.size()) - human_players)
	for i in range(ally_count):
		var own_spawn: Vector3 = own_team_spawns[(human_players + i) % own_team_spawns.size()]
		allies.append(_spawn_bot(player_team, i, own_spawn))
	var defender_count: int = mini(5, opposing_team_spawns.size())
	for i in range(defender_count):
		var opposing_spawn: Vector3 = opposing_team_spawns[i]
		enemies.append(_spawn_bot(1 - player_team, i, opposing_spawn))
	_refresh_bot_opponents()

func _player_spawn_for_slot(slot: int) -> Vector3:
	if player_team == 1 and not current_level.bot_spawns.is_empty():
		return current_level.bot_spawns[posmod(slot, mini(5, current_level.bot_spawns.size()))]
	var offsets := [Vector3.ZERO, Vector3(-1.2, 0, 0.5), Vector3(1.2, 0, 0.5), Vector3(-2.1, 0, 1.3), Vector3(2.1, 0, 1.3)]
	return current_level.player_spawn + offsets[posmod(slot, offsets.size())]

func _spawn_bot(team: int, index: int, position: Vector3, spawn_config := {}) -> LocalStrikeEnemy:
	var bot: LocalStrikeEnemy = EnemyScript.new()
	if NetworkManager.peer != null and multiplayer.is_server():
		bot.network_bot_id = "bot_%d" % next_network_bot_id
		next_network_bot_id += 1
	bot.bot_difficulty = bot_difficulty
	var default_kind := "heavy" if index == 4 else ("scout" if index % 3 == 1 else "assault")
	var kind := str(spawn_config.get("kind", default_kind))
	var default_weapon := "bulwark" if kind == "heavy" else ("whisper" if kind == "scout" else "sentinel")
	var weapon := str(spawn_config.get("weapon", default_weapon))
	var behavior := str(spawn_config.get("behavior", "aggressive"))
	bot.configure_spawn(team, kind, weapon, behavior, position)
	var typed_patrols: Array[Vector3] = []
	for patrol in current_level.patrols:
		typed_patrols.append(patrol)
	bot.patrol_points = typed_patrols
	bot.died.connect(_on_enemy_died)
	bot.shot_fired.connect(_on_enemy_shot)
	bot.melee_impact.connect(_on_enemy_melee_impact)
	level_root.add_child(bot)
	bot.global_position = position
	return bot

func _refresh_bot_opponents() -> void:
	var own_team: Array[Node3D] = [player]
	for ally in allies:
		if is_instance_valid(ally): own_team.append(ally)
	for avatar in remote_avatars.values():
		if is_instance_valid(avatar) and avatar.team == player_team: own_team.append(avatar)
	var opposing_team: Array[Node3D] = []
	for enemy in enemies:
		if is_instance_valid(enemy): opposing_team.append(enemy)
	for ally in allies:
		if is_instance_valid(ally): ally.set_opponents(opposing_team)
	for enemy in enemies:
		if is_instance_valid(enemy): enemy.set_opponents(own_team)

func _update_objective(delta: float) -> void:
	var site: Dictionary = _current_site()
	if player_team == 0:
		if not charge_planted and not site.is_empty() and Input.is_action_pressed("interact"):
			plant_progress += delta
			if plant_progress >= 3.2:
				_plant_charge(site)
		elif not charge_planted:
			plant_progress = maxf(0.0, plant_progress - delta * 1.5)
	else:
		var attack_site: Dictionary = sites[(round_no + 1) % sites.size()]
		var planters := 0
		if not charge_planted:
			for attacker in enemies:
				if is_instance_valid(attacker):
					attacker.set_objective(attack_site.position, true)
					if attacker.global_position.distance_to(attack_site.position) < 1.7:
						planters += 1
			if planters > 0:
				plant_progress += delta
				if plant_progress >= 3.2:
					_plant_charge(attack_site)
			else:
				plant_progress = maxf(0.0, plant_progress - delta)

	if not charge_planted:
		return

	bomb_timer -= delta
	var defusers := 0
	var defending_bots: Array[LocalStrikeEnemy] = enemies if player_team == 0 else allies
	for defender in defending_bots:
		if is_instance_valid(defender):
			defender.set_objective(charge_position, true)
			if defender.global_position.distance_to(charge_position) < 1.55:
				defusers += 1
	if player_team == 1 and player.global_position.distance_to(charge_position) < 1.75 and Input.is_action_pressed("interact"):
		defusers += 1
	if defusers > 0:
		defuse_progress += delta * defusers
		if defuse_progress >= 5.5:
			_end_round(false, "defused")
	else:
		defuse_progress = maxf(0.0, defuse_progress - delta)
	if bomb_timer <= 0.0:
		_create_burst(charge_position + Vector3.UP * 0.7, Color("f3b447"), 24)
		_end_round(true, "charge detonated")

func _current_site() -> Dictionary:
	for site in sites:
		var flat_player := Vector2(player.global_position.x, player.global_position.z)
		var flat_site := Vector2(site.position.x, site.position.z)
		if flat_player.distance_to(flat_site) <= site.radius:
			return site
	return {}

func _plant_charge(site: Dictionary) -> void:
	charge_planted = true
	charge_position = site.position
	bomb_timer = 35.0
	defuse_progress = 0.0
	phase_timer = maxf(phase_timer, bomb_timer)
	charge_mesh = _create_charge(charge_position)
	hud.show_toast("Charge planted at Site %s" % site.name)

func _end_round(attack_wins: bool, reason: String) -> void:
	if phase == Phase.ENDED:
		return
	phase = Phase.ENDED
	round_end_timer = 3.5
	player.enabled = false
	if attack_wins:
		attack_score += 1
		player.add_reward(1200)
	else:
		defense_score += 1
		player.add_reward(500)
	match_over = attack_score >= 4 or defense_score >= 4
	hud.show_toast("%s wins: %s" % ["ATTACK" if attack_wins else "DEFENSE", reason], 3.2)

func _finish_match() -> void:
	Engine.time_scale = 1.0
	started = false
	player.enabled = false
	hud.set_deployed(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_toast("MATCH COMPLETE  %d : %d" % [attack_score, defense_score], 5.0)

func _buy_weapon(key: String) -> void:
	var spec := WeaponCatalog.get_weapon(key)
	if game_mode == LocalStrikeMatchConfig.Mode.DEFUSAL and spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE and key != "knife":
		hud.show_toast("Sandbox melee weapons are unavailable in Defusal", 1.8)
		return
	var message := player.grant_weapon(key) if game_mode in [LocalStrikeMatchConfig.Mode.DEATHMATCH, LocalStrikeMatchConfig.Mode.SANDBOX] else player.try_buy(key, phase == Phase.BUY)
	hud.show_toast(message)

func _on_enemy_died(enemy: LocalStrikeEnemy, position: Vector3, enemy_kind: String) -> void:
	var was_opponent := enemies.has(enemy)
	var hit_context: Dictionary = enemy.last_hit_context
	var hit_direction: Vector3 = hit_context.get("direction", (position - player.global_position).normalized())
	var impulse_strength := float(hit_context.get("impulse", 6.0))
	var impulse := hit_direction.normalized() * impulse_strength * 0.72 + Vector3.UP * 2.0
	var ragdoll = RagdollScript.new()
	effect_root.add_child(ragdoll)
	ragdoll.global_position = position
	var persistent := game_mode == LocalStrikeMatchConfig.Mode.SANDBOX
	ragdoll.configure(Color("8f3f43") if enemy.team == 1 else Color("365f70"), impulse, persistent)
	if persistent:
		_track_sandbox_ragdoll(ragdoll)
	if str(hit_context.get("source", "ballistic")) != "melee":
		effects.spawn_blood_pool(position, 0.9)
	enemies.erase(enemy)
	allies.erase(enemy)
	if was_opponent:
		var reward := 450 if enemy_kind == "heavy" else (350 if enemy_kind == "scout" else 300)
		player.add_reward(reward)
	_create_burst(position + Vector3.UP, Color("f3b447"), 12)
	hud.add_kill("OPERATOR" if was_opponent else "DEFENDER", "DEFENDER" if was_opponent else "ALLY", player.get_weapon_name())
	if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX:
		if was_opponent:
			attack_score += 1
		else:
			defense_score += 1
		_refresh_bot_opponents()
		return
	if game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH:
		if enemy.team == 1:
			attack_score += 1
		else:
			defense_score += 1
		pending_respawns.append({"time": 3.0, "team": enemy.team, "kind": enemy_kind, "position": position})
		_refresh_bot_opponents()
		return
	if not _team_alive(1):
		_end_round(true, "team eliminated")
	elif not _team_alive(0):
		_end_round(false, "team eliminated")
	else:
		_refresh_bot_opponents()

func _track_sandbox_ragdoll(ragdoll: Node3D) -> void:
	sandbox_ragdolls.append(ragdoll)
	while sandbox_ragdolls.size() > 24:
		var oldest: Node3D = sandbox_ragdolls.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

func _on_player_died() -> void:
	player_dead = true
	player.enabled = false
	if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX:
		player_respawn_timer = 1.5
	elif game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH:
		player_respawn_timer = 3.0
		if player_team == 0:
			defense_score += 1
		else:
			attack_score += 1
	else:
		_start_spectating()
		if not _team_alive(player_team):
			_end_round(player_team == 1, "team eliminated")

func _on_hit_confirmed(killed: bool) -> void:
	hud.show_hit(killed)

func _on_shot_fired(origin: Vector3, end: Vector3, hit: bool, normal: Vector3, surface_type: String, actor_hit: bool) -> void:
	AudioManager.play_shot(origin, WeaponCatalog.get_weapon(player.weapon_key).category)
	for bot in enemies:
		if is_instance_valid(bot): bot.hear_noise(origin, 1.0)
	_create_tracer(origin, end, Color("ffd08a"))
	if hit:
		effects.spawn_impact(end, normal, surface_type, actor_hit)
		if not actor_hit:
			AudioManager.play_impact(end, surface_type)
	if NetworkManager.peer != null and multiplayer.is_server():
		_network_shot_effect.rpc(origin, end, normal, surface_type, actor_hit)

func _on_player_shot_requested(sequence: int, origin: Vector3, direction: Vector3, weapon_key: String, mode: String) -> void:
	if _is_network_client():
		_request_network_shot.rpc_id(1, sequence, origin, direction, weapon_key, mode)

func _on_player_reload_requested(weapon_key: String) -> void:
	if _is_network_client():
		_request_network_reload.rpc_id(1, weapon_key)

func _on_player_melee_requested(sequence: int, origin: Vector3, direction: Vector3, weapon_key: String, heavy: bool) -> void:
	if _is_network_client():
		_request_network_melee.rpc_id(1, sequence, origin, direction, weapon_key, heavy)
	else:
		_execute_melee(player, sequence, origin, direction, weapon_key, heavy, multiplayer.get_unique_id())

func _on_enemy_shot(origin: Vector3, end: Vector3, hit: bool) -> void:
	AudioManager.play_shot(origin, "rifle")
	_create_tracer(origin, end, Color("ef5b5b"))
	if hit:
		effects.spawn_impact(end, (origin - end).normalized(), "flesh", true)

func _on_enemy_melee_impact(position: Vector3, normal: Vector3, intensity: float, killed: bool) -> void:
	effects.spawn_blood_hit(position, normal, -normal, intensity, killed)

func _execute_melee(attacker: Node3D, sequence: int, origin: Vector3, direction: Vector3, weapon_key: String, heavy: bool, attacker_peer: int) -> void:
	if not WeaponCatalog.all().has(weapon_key):
		return
	var spec := WeaponCatalog.get_weapon(weapon_key)
	if spec.slot != LocalStrikeWeaponDefinition.Slot.MELEE:
		return
	var result := MeleeResolver.resolve_attack(get_world_3d().direct_space_state, origin, direction, spec, [attacker.get_rid()], heavy)
	for hit in result.hits:
		var target: Object = hit.target
		var target_node := target as Node3D
		var target_base := target as Node
		var actor_hit := target_base != null and target_base.is_in_group("damageable_actor")
		var surface := "flesh" if actor_hit else str(target.get_meta("surface_type", "concrete"))
		var context := {"source": "melee", "weapon": weapon_key, "heavy": heavy, "direction": direction.normalized(), "impulse": hit.impulse, "blood_intensity": hit.blood_intensity}
		var killed := false
		if target.has_method("take_damage"):
			killed = bool(target.take_damage(float(hit.damage), str(hit.zone), context))
		elif target.has_method("apply_damage"):
			target.apply_damage(float(hit.damage), str(hit.zone), context)
			var target_health = target.get("health")
			killed = target_health != null and float(target_health) <= 0.0
		if target.has_method("apply_gameplay_impulse") and target_node != null:
			target.apply_gameplay_impulse(direction.normalized() * float(hit.impulse), hit.position - target_node.global_position)
		hit["killed"] = killed
		hit["actor_hit"] = actor_hit
		hit["surface"] = surface
	var clean := MeleeResolver.network_result(result)
	clean["sequence"] = sequence
	clean["attacker_peer"] = attacker_peer
	if NetworkManager.peer != null and multiplayer.is_server():
		_confirm_melee.rpc(clean)
	_confirm_melee(clean)

func _team_alive(team: int) -> bool:
	if player_team == team and player.health > 0.0:
		return true
	for bot in allies + enemies:
		if is_instance_valid(bot) and bot.team == team and bot.health > 0.0:
			return true
	for avatar in remote_avatars.values():
		if is_instance_valid(avatar) and avatar.team == team and avatar.health > 0.0:
			return true
	return false

func _start_spectating() -> void:
	spectator_target = null
	for ally in allies:
		if is_instance_valid(ally) and ally.health > 0.0:
			spectator_target = ally
			break
	if is_instance_valid(spectator_target):
		spectator_camera.current = true
		player.set_view_active(false)

func _update_spectator() -> void:
	if not player_dead or not is_instance_valid(spectator_target):
		return
	var target_position := spectator_target.global_position + Vector3.UP * 1.2
	var desired := target_position + spectator_target.global_transform.basis.z * 3.8 + Vector3.UP * 1.5
	spectator_camera.global_position = spectator_camera.global_position.lerp(desired, 0.12)
	spectator_camera.look_at(target_position, Vector3.UP)

func _update_deathmatch(delta: float) -> void:
	if match_over:
		round_end_timer -= delta
		if round_end_timer <= 0.0:
			_finish_match()
		return
	deathmatch_timer -= delta
	phase_timer = deathmatch_timer
	if deathmatch_timer <= 0.0 or attack_score >= 40 or defense_score >= 40:
		match_over = true
		round_end_timer = 3.0
		player.enabled = false
		hud.show_toast("DEATHMATCH COMPLETE  %d : %d" % [attack_score, defense_score], 3.0)
		return
	if player_dead:
		player_respawn_timer -= delta
		if player_respawn_timer <= 0.0:
			_respawn_player()
	for i in range(pending_respawns.size() - 1, -1, -1):
		pending_respawns[i].time -= delta
		if pending_respawns[i].time <= 0.0:
			_respawn_bot(pending_respawns[i])
			pending_respawns.remove_at(i)

func _update_sandbox(delta: float) -> void:
	phase = Phase.LIVE
	phase_timer = 0.0
	if player_dead:
		player_respawn_timer -= delta
		if player_respawn_timer <= 0.0:
			_respawn_player()
			player.invulnerable = sandbox_god_mode
			player.unlimited_ammo = true

func _on_sandbox_browser_visibility_changed(visible: bool) -> void:
	if game_mode != LocalStrikeMatchConfig.Mode.SANDBOX:
		return
	if visible and sandbox_spawn_controller.is_placing():
		sandbox_spawn_controller.cancel_placement()
	player.combat_input_blocked = visible or sandbox_spawn_controller.is_placing()

func _on_sandbox_placement_requested(definition: LocalStrikeSandboxItemDefinition, options: Dictionary) -> void:
	if game_mode != LocalStrikeMatchConfig.Mode.SANDBOX or not started:
		return
	sandbox_spawn_controller.begin_placement(definition, options)
	player.combat_input_blocked = true

func _on_sandbox_placement_state_changed(active: bool, valid: bool, item_name: String) -> void:
	sandbox_browser.set_placement_state(active, valid, item_name)
	if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX:
		player.combat_input_blocked = active or sandbox_browser.is_open()

func _on_sandbox_placement_confirmed(definition: LocalStrikeSandboxItemDefinition, placement: Transform3D, options: Dictionary) -> void:
	match definition.kind:
		SandboxItemDefinition.Kind.BOT:
			if not definition.bot_kind.is_empty():
				options["kind"] = definition.bot_kind
			_spawn_sandbox_bot_at(options, placement)
		SandboxItemDefinition.Kind.WEAPON:
			options["weapon"] = definition.weapon_key
			_spawn_sandbox_weapon_at(options, placement)
		SandboxItemDefinition.Kind.PROP:
			_spawn_sandbox_prop_at(definition.surface_type, placement, int(options.get("count", 1)))
	player.combat_input_blocked = false

func _spawn_sandbox_bot_at(config: Dictionary, placement: Transform3D) -> int:
	var available := mini(clampi(int(config.get("count", 1)), 1, 10), 40 - enemies.size() - allies.size())
	if available <= 0:
		hud.show_toast("Bot limit reached", 1.4)
		return 0
	var team := player_team if str(config.get("team", "enemy")) == "ally" else 1 - player_team
	var kind := str(config.get("kind", "assault"))
	if kind not in ["scout", "assault", "heavy"]:
		kind = "assault"
	var weapon := str(config.get("weapon", "sentinel"))
	if weapon not in WeaponCatalog.bot_weapon_keys():
		weapon = "sentinel"
	var behavior := str(config.get("behavior", "aggressive"))
	if behavior not in ["aggressive", "guard", "passive"]:
		behavior = "aggressive"
	var columns := mini(4, ceili(sqrt(float(available))))
	var rows := ceili(float(available) / float(columns))
	for index in range(available):
		var column := index % columns
		var row := int(index / columns)
		var local_offset := Vector3((float(column) - float(columns - 1) * 0.5) * 1.15, 0.05, (float(row) - float(rows - 1) * 0.5) * 1.15)
		var position := placement.origin + placement.basis * local_offset
		sandbox_spawn_serial += 1
		var bot := _spawn_bot(team, sandbox_spawn_serial % 5, position, {"kind": kind, "weapon": weapon, "behavior": behavior})
		bot.guard_anchor = position
		if team == player_team:
			allies.append(bot)
		else:
			enemies.append(bot)
	_refresh_bot_opponents()
	hud.show_toast("%d %s %s placed" % [available, kind.capitalize(), "allies" if team == player_team else "enemies"], 1.4)
	return available

func _spawn_sandbox_weapon_at(config: Dictionary, placement: Transform3D) -> int:
	var key := str(config.get("weapon", "ranger"))
	if key not in WeaponCatalog.sandbox_weapon_keys():
		key = "ranger"
	var available := mini(clampi(int(config.get("count", 1)), 1, 10), 32 - dropped_weapons.size())
	if available <= 0:
		hud.show_toast("Weapon limit reached", 1.4)
		return 0
	var spec := WeaponCatalog.get_weapon(key)
	for index in range(available):
		var column := index % 4
		var row := int(index / 4)
		var local_offset := Vector3((float(column) - minf(1.5, float(available - 1) * 0.5)) * 0.58, row * 0.18, row * 0.48)
		var position := placement.origin + placement.basis * local_offset
		var drop: LocalStrikeDroppedWeapon = _spawn_dropped_weapon(key, spec.magazine, spec.reserve, position, Vector3.UP * 0.4, "", 0.0)
		drop.global_basis = placement.basis
	hud.show_toast("%d x %s placed" % [available, spec.display_name], 1.3)
	return available

func _spawn_sandbox_prop_at(surface_type: String, placement: Transform3D, requested_count: int) -> int:
	var available := mini(clampi(requested_count, 1, 8), 64 - _sandbox_prop_count())
	if available <= 0:
		hud.show_toast("Physics prop limit reached", 1.4)
		return 0
	var size := Vector3(1.15, 1.15, 1.15)
	var mass := 18.0
	var health := 55.0
	var resolved_surface := surface_type
	match surface_type:
		"metal":
			size = Vector3(1.5, 0.82, 0.9)
			mass = 38.0
			health = 95.0
		"barrel":
			size = Vector3(0.72, 1.12, 0.72)
			mass = 24.0
			health = 65.0
			resolved_surface = "metal"
		"tool_cart":
			size = Vector3(1.4, 1.05, 0.72)
			mass = 31.0
			health = 88.0
			resolved_surface = "metal"
	for index in range(available):
		sandbox_spawn_serial += 1
		var prop_id := "sandbox_prop_%d" % sandbox_spawn_serial
		var local_offset := Vector3(float(index % 4) * (size.x + 0.18), float(int(index / 4)) * 0.12, float(int(index / 4)) * (size.z + 0.18))
		var transform := placement.translated_local(local_offset)
		var data := _physics_prop(prop_id, transform.origin, size, resolved_surface, mass, health)
		data["variant"] = surface_type
		var prop: LocalStrikePhysicsProp = PhysicsPropScript.new()
		prop.configure(data)
		prop.transform = transform
		prop.state_changed.connect(_on_physics_prop_state_changed)
		prop.destroyed.connect(_on_physics_prop_destroyed)
		level_root.add_child(prop)
		physics_props[prop_id] = prop
	hud.show_toast("%d %s props placed" % [available, surface_type.replace("_", " ").capitalize()], 1.3)
	return available

func _on_sandbox_action(action: String, payload: Dictionary) -> void:
	if game_mode != LocalStrikeMatchConfig.Mode.SANDBOX or not started:
		return
	match action:
		"god_mode":
			sandbox_god_mode = bool(payload.get("enabled", not sandbox_god_mode))
			player.invulnerable = sandbox_god_mode
			if sandbox_god_mode:
				player.health = 100.0
				player.armor = 100.0
			hud.show_toast("God mode %s" % ["enabled" if sandbox_god_mode else "disabled"], 1.4)
		"slow_motion":
			sandbox_slow_motion = bool(payload.get("enabled", not sandbox_slow_motion))
			Engine.time_scale = 0.32 if sandbox_slow_motion else 1.0
			hud.show_toast("Slow motion %s" % ["enabled" if sandbox_slow_motion else "disabled"], 1.4)
		"spawn_bot":
			_spawn_sandbox_bot(payload)
		"spawn_wave":
			_spawn_sandbox_wave()
		"spawn_wood":
			_spawn_sandbox_prop("wood")
		"spawn_metal":
			_spawn_sandbox_prop("metal")
		"spawn_weapon":
			_spawn_sandbox_weapon(payload)
		"equip_weapon":
			_equip_sandbox_weapon(payload)
		"explosion":
			var blast_position := _sandbox_target_position(0.2)
			_create_burst(blast_position + Vector3.UP * 0.3, Color("ff8a38"), 38)
			if DisplayServer.get_name() != "headless":
				AudioManager.play_explosion(blast_position)
			_apply_radial_damage(blast_position, 82.0, 6.0)
		"clear":
			_clear_sandbox_spawns()
		"clear_npcs":
			_clear_sandbox_npcs(true)
		"clear_weapons":
			_clear_sandbox_weapons(true)
		"clear_props":
			_clear_sandbox_props(true)
		"clear_blood":
			_clear_sandbox_blood(true)
		"remove_target":
			_remove_sandbox_target()
		"reset":
			_restart_match()

func _spawn_sandbox_bot(config: Dictionary) -> int:
	var available := mini(clampi(int(config.get("count", 1)), 1, 10), 40 - enemies.size() - allies.size())
	if available <= 0:
		hud.show_toast("NPC limit reached", 1.3)
		return 0
	var team := player_team if str(config.get("team", "enemy")) == "ally" else 1 - player_team
	var kind := str(config.get("kind", "assault"))
	if kind not in ["scout", "assault", "heavy"]:
		kind = "assault"
	var weapon := str(config.get("weapon", "sentinel"))
	if weapon not in WeaponCatalog.bot_weapon_keys():
		weapon = "sentinel"
	var behavior := str(config.get("behavior", "aggressive"))
	if behavior not in ["aggressive", "guard", "passive"]:
		behavior = "aggressive"
	var center := _sandbox_target_position(0.05)
	for index in range(available):
		sandbox_spawn_serial += 1
		var position := _safe_sandbox_spawn_position(center, index)
		var bot := _spawn_bot(team, sandbox_spawn_serial % 5, position, {"kind": kind, "weapon": weapon, "behavior": behavior})
		bot.guard_anchor = position
		if team == player_team:
			allies.append(bot)
		else:
			enemies.append(bot)
	_refresh_bot_opponents()
	hud.show_toast("%d %s %s spawned" % [available, kind.capitalize(), "allies" if team == player_team else "enemies"], 1.3)
	return available

func _spawn_sandbox_wave() -> void:
	var enemy_count := _spawn_sandbox_bot({"team": "enemy", "kind": "assault", "weapon": "crowbar", "behavior": "aggressive", "count": 6})
	var ally_count := _spawn_sandbox_bot({"team": "ally", "kind": "assault", "weapon": "baseball_bat", "behavior": "aggressive", "count": 2})
	if enemy_count + ally_count > 0:
		hud.show_toast("Brawl wave: %d vs %d" % [enemy_count, ally_count], 1.4)

func _spawn_sandbox_prop(surface_type: String) -> void:
	if _sandbox_prop_count() >= 64:
		hud.show_toast("Physics prop limit reached", 1.3)
		return
	sandbox_spawn_serial += 1
	var prop_id := "sandbox_prop_%d" % sandbox_spawn_serial
	var size := Vector3(1.15, 1.15, 1.15) if surface_type == "wood" else Vector3(1.5, 0.8, 0.85)
	var data := _physics_prop(prop_id, _sandbox_target_position(size.y * 0.5), size, surface_type, 18.0 if surface_type == "wood" else 38.0, 55.0 if surface_type == "wood" else 95.0)
	var prop = PhysicsPropScript.new()
	prop.configure(data)
	prop.position = data.position
	prop.state_changed.connect(_on_physics_prop_state_changed)
	prop.destroyed.connect(_on_physics_prop_destroyed)
	level_root.add_child(prop)
	physics_props[prop_id] = prop
	hud.show_toast("%s prop spawned" % surface_type.capitalize(), 1.1)

func _spawn_sandbox_weapon(config: Dictionary) -> int:
	var key := str(config.get("weapon", "ranger"))
	if key not in WeaponCatalog.sandbox_weapon_keys():
		key = "ranger"
	var available := mini(clampi(int(config.get("count", 1)), 1, 10), 32 - dropped_weapons.size())
	if available <= 0:
		hud.show_toast("Weapon drop limit reached", 1.3)
		return 0
	var spec := WeaponCatalog.get_weapon(key)
	var center := _sandbox_target_position(0.35)
	for index in range(available):
		var column := index % 4
		var row := int(index / 4)
		var position := center + Vector3((column - 1.5) * 0.48, row * 0.16, row * 0.42)
		_spawn_dropped_weapon(key, spec.magazine, spec.reserve, position, Vector3.UP * 0.5, "", 0.0)
	hud.show_toast("%d x %s dropped" % [available, spec.display_name], 1.2)
	return available

func _equip_sandbox_weapon(config: Dictionary) -> void:
	var key := str(config.get("weapon", "ranger"))
	if key not in WeaponCatalog.sandbox_weapon_keys():
		hud.show_toast("Unknown sandbox weapon", 1.2)
		return
	hud.show_toast(player.grant_weapon(key), 1.2)

func _safe_sandbox_spawn_position(center: Vector3, index: int) -> Vector3:
	for attempt in range(12):
		var slot := index + attempt
		var angle := float(slot) * 2.39996
		var radius := 0.85 * sqrt(float(slot))
		var candidate := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var floor_ray := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 4.0, candidate + Vector3.DOWN * 7.0)
		floor_ray.exclude = [player.get_rid()]
		floor_ray.collision_mask = 1
		var floor_hit := get_world_3d().direct_space_state.intersect_ray(floor_ray)
		if not floor_hit.is_empty():
			candidate.y = floor_hit.position.y
		var occupied := Vector2(candidate.x - player.global_position.x, candidate.z - player.global_position.z).length() < 1.0
		for bot in allies + enemies:
			if is_instance_valid(bot) and Vector2(candidate.x - bot.global_position.x, candidate.z - bot.global_position.z).length() < 1.0:
				occupied = true
				break
		if occupied:
			continue
		var point_query := PhysicsPointQueryParameters3D.new()
		point_query.position = candidate + Vector3.UP * 1.0
		point_query.exclude = [player.get_rid()]
		point_query.collision_mask = 1
		if get_world_3d().direct_space_state.intersect_point(point_query, 1).is_empty():
			return candidate
	var fallback_angle := float(index) * 2.39996
	return center + Vector3(cos(fallback_angle), 0.05, sin(fallback_angle)) * (0.9 + index * 0.35)

func _sandbox_target_position(height_offset: float) -> Vector3:
	var origin := player.get_aim_origin()
	var direction := player.get_aim_direction().normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 14.0)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit.position + hit.normal * 0.35 if not hit.is_empty() else origin + direction * 7.0
	var floor_query := PhysicsRayQueryParameters3D.create(target + Vector3.UP * 5.0, target + Vector3.DOWN * 10.0)
	floor_query.exclude = [player.get_rid()]
	floor_query.collision_mask = 1
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(floor_query)
	if not floor_hit.is_empty():
		target.y = floor_hit.position.y + height_offset
	target.x = clampf(target.x, -15.2, 15.2)
	target.z = clampf(target.z, -15.2, 15.2)
	return target

func _clear_sandbox_spawns() -> void:
	_clear_sandbox_npcs(false)
	_clear_sandbox_weapons(false)
	_clear_sandbox_props(false)
	_clear_sandbox_blood(false)
	_refresh_bot_opponents()
	hud.show_toast("Spawned objects cleared", 1.3)

func _clear_sandbox_props(show_message: bool) -> void:
	var prop_ids: Array[String] = []
	for prop_id in physics_props:
		if str(prop_id).begins_with("sandbox_prop_"):
			prop_ids.append(str(prop_id))
	for prop_id in prop_ids:
		if is_instance_valid(physics_props[prop_id]):
			physics_props[prop_id].queue_free()
		physics_props.erase(prop_id)
	if show_message:
		hud.show_toast("Spawned props removed", 1.2)

func _sandbox_prop_count() -> int:
	var count := 0
	for prop_id in physics_props:
		if str(prop_id).begins_with("sandbox_prop_"):
			count += 1
	return count

func _clear_sandbox_npcs(show_message: bool) -> void:
	for bot in allies + enemies:
		if is_instance_valid(bot):
			bot.queue_free()
	allies.clear()
	enemies.clear()
	_refresh_bot_opponents()
	if show_message:
		hud.show_toast("All sandbox NPCs removed", 1.2)

func _clear_sandbox_weapons(show_message: bool) -> void:
	for drop in dropped_weapons.values():
		if is_instance_valid(drop):
			drop.queue_free()
	dropped_weapons.clear()
	if show_message:
		hud.show_toast("Dropped weapons removed", 1.2)

func _clear_sandbox_blood(show_message: bool) -> void:
	effects.clear_blood()
	player.clear_weapon_blood()
	for drop in dropped_weapons.values():
		if is_instance_valid(drop):
			drop.clear_blood()
	for bot in allies + enemies:
		if is_instance_valid(bot):
			bot.clear_weapon_blood()
	for ragdoll in sandbox_ragdolls:
		if is_instance_valid(ragdoll):
			ragdoll.queue_free()
	sandbox_ragdolls.clear()
	if show_message:
		hud.show_toast("Blood and bodies cleared", 1.2)

func _remove_sandbox_target() -> void:
	var origin := player.get_aim_origin()
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + player.get_aim_direction() * 18.0)
	ray.exclude = [player.get_rid()]
	ray.collision_mask = 15
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		hud.show_toast("No sandbox object targeted", 1.1)
		return
	var node := hit.collider as Node
	while node != null:
		if allies.has(node) or enemies.has(node):
			allies.erase(node)
			enemies.erase(node)
			node.queue_free()
			_refresh_bot_opponents()
			hud.show_toast("NPC removed", 1.1)
			return
		if node is LocalStrikeDroppedWeapon:
			dropped_weapons.erase(node.drop_id)
			node.queue_free()
			hud.show_toast("Weapon removed", 1.1)
			return
		if node is LocalStrikePhysicsProp and str(node.prop_id).begins_with("sandbox_prop_"):
			physics_props.erase(node.prop_id)
			node.queue_free()
			hud.show_toast("Prop removed", 1.1)
			return
		if node.is_in_group("sandbox_ragdoll"):
			sandbox_ragdolls.erase(node)
			node.queue_free()
			hud.show_toast("Body removed", 1.1)
			return
		node = node.get_parent()
	hud.show_toast("Map geometry cannot be removed", 1.2)

func _respawn_player() -> void:
	player_dead = false
	var spawn_position := _player_spawn_for_slot(network_spawn_slot)
	player.reset_for_round(spawn_position)
	player.enabled = true
	player.set_view_active(true)
	spectator_camera.current = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _respawn_bot(data: Dictionary) -> void:
	var team: int = data.team
	var spawn_position: Vector3 = current_level.player_spawn + Vector3(randf_range(-2.0, 2.0), 0, randf_range(-1.0, 1.5)) if team == 0 else current_level.bot_spawns[randi() % current_level.bot_spawns.size()]
	var profile_index := 4 if data.kind == "heavy" else (1 if data.kind == "scout" else 0)
	var bot := _spawn_bot(team, profile_index, spawn_position)
	if team == player_team:
		allies.append(bot)
	else:
		enemies.append(bot)
	_refresh_bot_opponents()

func _on_grenade_thrown(origin: Vector3, impulse: Vector3, grenade_kind: String) -> void:
	var grenade: LocalStrikeGrenade = GrenadeScript.new()
	grenade.configure(grenade_kind, impulse)
	grenade.detonated.connect(_on_grenade_detonated)
	effect_root.add_child(grenade)
	grenade.global_position = origin

func _on_grenade_detonated(position: Vector3, grenade_kind: String, damage: float, radius: float) -> void:
	if grenade_kind == "smoke":
		var smoke: LocalStrikeSmokeCloud = SmokeScript.new()
		effect_root.add_child(smoke)
		smoke.global_position = position
		_create_burst(position + Vector3.UP * 0.4, Color("a9d8ff"), 10)
		return
	if grenade_kind == "flash":
		_create_burst(position + Vector3.UP * 0.4, Color.WHITE, 28)
		AudioManager.play_explosion(position)
		_apply_flash(position, radius)
		return
	if grenade_kind == "incendiary":
		_create_burst(position + Vector3.UP * 0.4, Color("ff6a2e"), 24)
		AudioManager.play_explosion(position)
		var fire_zone = FireZoneScript.new()
		fire_zone.damage_tick.connect(_on_fire_zone_tick)
		effect_root.add_child(fire_zone)
		fire_zone.global_position = position
		return
	_create_burst(position + Vector3.UP * 0.5, Color("ff9a3d"), 34)
	AudioManager.play_explosion(position)
	if not _is_network_client():
		_apply_radial_damage(position, damage, radius)

func _apply_flash(position: Vector3, radius: float) -> void:
	var eye := player.global_position + Vector3.UP * 1.55
	var to_flash := position - eye
	if to_flash.length() > radius or not _has_explosion_line_of_sight(position, eye, null):
		return
	var view_forward := -player.global_transform.basis.z
	var facing := clampf((view_forward.dot(to_flash.normalized()) + 1.0) * 0.5, 0.0, 1.0)
	var distance_scale := 1.0 - to_flash.length() / radius
	hud.show_flash(clampf(distance_scale * (0.35 + facing * 0.9), 0.0, 1.0))

func _on_fire_zone_tick(position: Vector3, radius: float, damage: float) -> void:
	if _is_network_client():
		return
	_apply_radial_damage(position, damage, radius)

func _is_network_client() -> bool:
	return NetworkManager.peer != null and not multiplayer.is_server()

func _on_connection_state_changed(state: String) -> void:
	if hud == null:
		return
	match state:
		"connected":
			hud.show_toast("Connected. Synchronizing match...", 3.0)
			_register_client.rpc_id(1, GameSession.local_player_name)
		"failed", "join_failed": hud.show_toast("LAN connection failed", 4.0)
		"disconnected":
			hud.show_toast("Host disconnected", 4.0)
			_finish_match()

func _on_network_peer_joined(_peer_id: int) -> void:
	# Bots werden nach der Spielerregistrierung aufgefüllt.
	pass

func _on_network_peer_left(peer_id: int) -> void:
	GameSession.remove_player(peer_id)
	if remote_avatars.has(peer_id):
		remote_avatars[peer_id].queue_free()
		remote_avatars.erase(peer_id)
	_refresh_bot_opponents()
	if multiplayer.is_server() and started:
		_spawn_teams()
	_sync_roster.rpc(GameSession.roster)

@rpc("any_peer", "call_remote", "reliable")
func _register_client(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	GameSession.register_player(sender, player_name, 0)
	var spawn_slot := clampi(GameSession.roster.size() - 1, 0, 4)
	_spawn_teams()
	_receive_match_config.rpc_id(sender, game_mode, level_index, bot_difficulty, spawn_slot)
	_receive_interactable_snapshot.rpc_id(sender, _serialize_interactables())
	_receive_physics_snapshot.rpc_id(sender, _serialize_physics_state())
	_receive_bot_snapshot.rpc_id(sender, _serialize_bot_state())
	_sync_roster.rpc(GameSession.roster)

@rpc("authority", "call_remote", "reliable")
func _receive_match_config(mode: int, map_index: int, difficulty: int, spawn_slot := 0) -> void:
	var config := LocalStrikeMatchConfig.new()
	config.mode = mode
	config.map_index = map_index
	config.bot_difficulty = difficulty
	network_spawn_slot = clampi(spawn_slot, 0, 4)
	GameSession.configure(config)
	_start_configured_match(config)
	player.authoritative_damage = false

@rpc("authority", "call_remote", "reliable")
func _sync_roster(next_roster: Dictionary) -> void:
	GameSession.roster = next_roster.duplicate(true)
	GameSession.roster_changed.emit(GameSession.roster)

func _try_interact() -> void:
	var nearest: LocalStrikeInteractable
	var nearest_distance := 2.2
	for candidate in interactables.values():
		if not is_instance_valid(candidate) or candidate.kind != LocalStrikeInteractable.Kind.DOOR:
			continue
		var distance := player.global_position.distance_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	if nearest == null:
		return
	if _is_network_client():
		_request_interaction.rpc_id(1, nearest.interactable_id)
	elif nearest.interact():
		hud.show_toast("Door opened" if nearest.opened else "Door closed", 1.2)

func _handle_weapon_pickup_or_drop() -> void:
	if _is_network_client():
		_request_weapon_pickup_drop.rpc_id(1, player.weapon_key, player.ammo, player.reserve_ammo)
		return
	_handle_authoritative_weapon_action(player.global_position, player.weapon_key, player.ammo, player.reserve_ammo, 1)

func _handle_authoritative_weapon_action(actor_position: Vector3, weapon_key: String, current_ammo: int, reserve: int, peer_id: int) -> void:
	var nearest: RigidBody3D
	var nearest_distance := 2.0
	for candidate in dropped_weapons.values():
		if not is_instance_valid(candidate):
			continue
		var distance := actor_position.distance_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	if nearest != null:
		var picked_position := nearest.global_position
		var replaced := {}
		var incoming_spec := WeaponCatalog.get_weapon(nearest.weapon_key)
		var current_spec := WeaponCatalog.get_weapon(weapon_key)
		var replaces_current: bool = nearest.weapon_key != weapon_key and incoming_spec.slot == current_spec.slot and incoming_spec.slot != LocalStrikeWeaponDefinition.Slot.GRENADE
		if peer_id == 1:
			if replaces_current and not (weapon_key == "knife" and current_spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE):
				replaced = player.remove_current_weapon_for_drop()
			player.pickup_weapon(nearest.weapon_key, nearest.ammo, nearest.reserve, nearest.bloodiness)
			hud.show_toast("Picked up %s" % player.get_weapon_name(), 1.4)
		else:
			if replaces_current:
				replaced = {"key": weapon_key, "ammo": current_ammo, "reserve": reserve, "bloodiness": 0.0}
			_confirm_network_pickup.rpc_id(peer_id, nearest.weapon_key, nearest.ammo, nearest.reserve, nearest.bloodiness)
		dropped_weapons.erase(nearest.drop_id)
		if NetworkManager.peer != null:
			_remove_network_drop.rpc(nearest.drop_id)
		nearest.queue_free()
		if not replaced.is_empty():
			_spawn_dropped_weapon(replaced.key, int(replaced.ammo), int(replaced.reserve), picked_position + Vector3.UP * 0.18, Vector3.UP * 0.8, "", float(replaced.get("bloodiness", 0.0)))
		return
	var data := player.remove_current_weapon_for_drop() if peer_id == 1 else {"key": weapon_key, "ammo": current_ammo, "reserve": reserve, "bloodiness": 0.0}
	if data.is_empty():
		if peer_id == 1:
			hud.show_toast("No weapon to drop", 1.2)
		return
	var forward: Vector3 = -player.global_transform.basis.z if peer_id == 1 else -remote_avatars[peer_id].global_transform.basis.z
	_spawn_dropped_weapon(data.key, int(data.ammo), int(data.reserve), actor_position + Vector3.UP * 1.0 + forward * 0.7, forward * 4.0 + Vector3.UP * 1.2, "", float(data.get("bloodiness", 0.0)))
	if peer_id != 1:
		_confirm_network_drop.rpc_id(peer_id, weapon_key)

@rpc("any_peer", "call_remote", "reliable")
func _request_weapon_pickup_drop(weapon_key: String, current_ammo: int, reserve: int) -> void:
	if not multiplayer.is_server() or not WeaponCatalog.all().has(weapon_key):
		return
	var sender := multiplayer.get_remote_sender_id()
	var avatar: Node3D = remote_avatars.get(sender)
	var spec := WeaponCatalog.get_weapon(weapon_key)
	var slot_allowed := spec.slot in [LocalStrikeWeaponDefinition.Slot.PRIMARY, LocalStrikeWeaponDefinition.Slot.SECONDARY] or (game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH and spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE)
	if not is_instance_valid(avatar) or not slot_allowed:
		return
	if current_ammo < 0 or current_ammo > spec.magazine or reserve < 0 or reserve > spec.reserve:
		return
	_handle_authoritative_weapon_action(avatar.global_position, weapon_key, current_ammo, reserve, sender)

@rpc("authority", "call_remote", "reliable")
func _confirm_network_pickup(weapon_key: String, current_ammo: int, reserve: int, bloodiness: float) -> void:
	player.pickup_weapon(weapon_key, current_ammo, reserve, bloodiness)
	hud.show_toast("Picked up %s" % player.get_weapon_name(), 1.4)

@rpc("authority", "call_remote", "reliable")
func _confirm_network_drop(weapon_key: String) -> void:
	if player.weapon_key == weapon_key:
		player.remove_current_weapon_for_drop()

@rpc("authority", "call_remote", "reliable")
func _remove_network_drop(drop_id: String) -> void:
	if dropped_weapons.has(drop_id) and is_instance_valid(dropped_weapons[drop_id]):
		dropped_weapons[drop_id].queue_free()
		dropped_weapons.erase(drop_id)

func _spawn_dropped_weapon(key: String, current_ammo: int, reserve: int, position: Vector3, impulse: Vector3, forced_id := "", bloodiness := 0.0):
	var drop_id := forced_id if not forced_id.is_empty() else "drop_%d" % next_drop_id
	next_drop_id += 1
	var drop = DroppedWeaponScript.new()
	drop.configure(drop_id, key, current_ammo, reserve, bloodiness)
	level_root.add_child(drop)
	drop.global_position = position
	drop.linear_velocity = impulse
	dropped_weapons[drop_id] = drop
	return drop

@rpc("any_peer", "call_remote", "reliable")
func _request_interaction(interactable_id: String) -> void:
	if not multiplayer.is_server() or not interactables.has(interactable_id):
		return
	var sender := multiplayer.get_remote_sender_id()
	var avatar: Node3D = remote_avatars.get(sender)
	var interactive: LocalStrikeInteractable = interactables[interactable_id]
	if not is_instance_valid(avatar) or avatar.global_position.distance_to(interactive.global_position) > 2.4:
		return
	interactive.interact()

@rpc("authority", "call_remote", "reliable")
func _sync_interactable_state(interactable_id: String, state: Dictionary) -> void:
	if interactables.has(interactable_id) and is_instance_valid(interactables[interactable_id]):
		interactables[interactable_id].apply_state(state)

@rpc("authority", "call_remote", "reliable")
func _receive_interactable_snapshot(snapshot: Dictionary) -> void:
	for interactable_id in snapshot:
		if interactables.has(interactable_id) and is_instance_valid(interactables[interactable_id]):
			interactables[interactable_id].apply_state(snapshot[interactable_id])

func _serialize_interactables() -> Dictionary:
	var snapshot := {}
	for interactable_id in interactables:
		var interactive: LocalStrikeInteractable = interactables[interactable_id]
		if is_instance_valid(interactive):
			snapshot[interactable_id] = interactive.serialize_state()
	return snapshot

func _on_interactable_state_changed(interactable_id: String, state: Dictionary) -> void:
	if NetworkManager.peer != null and multiplayer.is_server():
		_sync_interactable_state.rpc(interactable_id, state)

func _on_interactable_effect(position: Vector3, normal: Vector3, surface_type: String, _effect_kind: String) -> void:
	effects.spawn_impact(position, normal, surface_type, false)
	AudioManager.play_impact(position, surface_type, _effect_kind == "shatter")

func _on_interactable_exploded(interactive: LocalStrikeInteractable, position: Vector3, damage: float, radius: float) -> void:
	_create_burst(position + Vector3.UP * 0.45, Color("ff8a38"), 34)
	AudioManager.play_explosion(position)
	if _is_network_client():
		return
	_apply_radial_damage(position, damage, radius, interactive)

func _apply_radial_damage(position: Vector3, damage: float, radius: float, excluded: Object = null) -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, position)
	query.collision_mask = 3
	var damaged_targets: Dictionary = {}
	for result in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var target: Object = result.collider
		if target == null or target == excluded or damaged_targets.has(target.get_instance_id()):
			continue
		damaged_targets[target.get_instance_id()] = true
		var target_position: Vector3 = target.global_position
		if not _has_explosion_line_of_sight(position, target_position + Vector3.UP * 0.4, target, excluded):
			continue
		var falloff := clampf(1.0 - position.distance_to(target_position) / radius, 0.15, 1.0)
		if target.has_method("apply_damage") or target.has_method("take_damage"):
			var applied_damage := damage * falloff
			if target.has_method("apply_damage"):
				target.apply_damage(applied_damage, "torso")
			else:
				target.take_damage(applied_damage, "torso")
		if target.has_method("apply_gameplay_impulse"):
			var direction := (target_position - position).normalized()
			target.apply_gameplay_impulse((direction + Vector3.UP * 0.25) * 18.0 * falloff, Vector3.ZERO)

func _has_explosion_line_of_sight(origin: Vector3, target: Vector3, target_object: Object, excluded: Object = null) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.12, target)
	query.collision_mask = 7
	if excluded is CollisionObject3D:
		query.exclude = [(excluded as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == target_object

func _update_network_state(delta: float) -> void:
	if NetworkManager.peer == null:
		return
	network_sync_timer -= delta
	prop_sync_timer -= delta
	bot_sync_timer -= delta
	if multiplayer.is_server():
		if network_sync_timer <= 0.0:
			network_sync_timer = 0.05
			_receive_player_snapshot.rpc(1, player.global_position, player.rotation.y, player.health, player.get_weapon_name())
		if prop_sync_timer <= 0.0:
			prop_sync_timer = 0.1
			_sync_physics_state.rpc(_serialize_physics_state())
		if bot_sync_timer <= 0.0:
			bot_sync_timer = 0.1
			_sync_bot_state.rpc(_serialize_bot_state())
	else:
		if network_sync_timer <= 0.0:
			network_sync_timer = 0.05
			_submit_player_snapshot.rpc_id(1, player.global_position, player.rotation.y, player.get_weapon_name())

@rpc("any_peer", "call_remote", "unreliable", 1)
func _submit_player_snapshot(position: Vector3, yaw: float, weapon: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var avatar := _get_or_create_avatar(sender, 0, position)
	avatar.apply_snapshot(position, yaw, avatar.health, weapon)
	_receive_player_snapshot.rpc(sender, position, yaw, avatar.health, weapon)

@rpc("authority", "call_remote", "unreliable", 1)
func _receive_player_snapshot(peer_id: int, position: Vector3, yaw: float, health: float, weapon: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var team: int = int(GameSession.roster.get(peer_id, {}).get("team", 0))
	var avatar := _get_or_create_avatar(peer_id, team, position)
	avatar.apply_snapshot(position, yaw, health, weapon)

func _serialize_physics_state() -> Dictionary:
	var props := {}
	for prop_id in physics_props:
		var prop = physics_props[prop_id]
		if is_instance_valid(prop):
			props[prop_id] = prop.serialize_state()
	var drops := {}
	for drop_id in dropped_weapons:
		var weapon = dropped_weapons[drop_id]
		if is_instance_valid(weapon):
			drops[drop_id] = weapon.serialize_state()
	return {"props": props, "drops": drops}

func _serialize_bot_state() -> Array:
	var snapshot := []
	for bot in allies + enemies:
		if not is_instance_valid(bot) or bot.network_bot_id.is_empty() or bot.health <= 0.0:
			continue
		snapshot.append([bot.network_bot_id, bot.global_position, bot.rotation.y, bot.health, bot.team, bot.enemy_kind, bot.weapon_key, bot.sandbox_behavior])
	return snapshot

@rpc("authority", "call_remote", "unreliable", 4)
func _sync_bot_state(snapshot: Array) -> void:
	_apply_bot_snapshot(snapshot)

@rpc("authority", "call_remote", "reliable")
func _receive_bot_snapshot(snapshot: Array) -> void:
	_apply_bot_snapshot(snapshot)

func _apply_bot_snapshot(snapshot: Array) -> void:
	if not _is_network_client():
		return
	var active_ids := {}
	for state_variant in snapshot:
		var state: Array = state_variant
		if state.size() < 8:
			continue
		var bot_id := str(state[0])
		active_ids[bot_id] = true
		var bot: LocalStrikeEnemy = replicated_bots.get(bot_id)
		if not is_instance_valid(bot):
			bot = EnemyScript.new()
			bot.bot_difficulty = bot_difficulty
			bot.configure_spawn(int(state[4]), str(state[5]), str(state[6]), str(state[7]), state[1])
			bot.configure_network_replica(bot_id)
			bot.position = state[1]
			level_root.add_child(bot)
			replicated_bots[bot_id] = bot
			if bot.team == player_team:
				allies.append(bot)
			else:
				enemies.append(bot)
		bot.apply_network_snapshot(state[1], float(state[2]), float(state[3]))
	for bot_id_variant in replicated_bots.keys():
		var bot_id := str(bot_id_variant)
		if active_ids.has(bot_id):
			continue
		var stale: LocalStrikeEnemy = replicated_bots[bot_id_variant]
		allies.erase(stale)
		enemies.erase(stale)
		if is_instance_valid(stale):
			if stale.get_parent() != null:
				stale.get_parent().remove_child(stale)
			stale.queue_free()
		replicated_bots.erase(bot_id_variant)

@rpc("authority", "call_remote", "unreliable", 3)
func _sync_physics_state(snapshot: Dictionary) -> void:
	_apply_physics_snapshot(snapshot)

@rpc("authority", "call_remote", "reliable")
func _receive_physics_snapshot(snapshot: Dictionary) -> void:
	_apply_physics_snapshot(snapshot)

func _apply_physics_snapshot(snapshot: Dictionary) -> void:
	for prop_id in snapshot.get("props", {}):
		if physics_props.has(prop_id) and is_instance_valid(physics_props[prop_id]):
			physics_props[prop_id].apply_state(snapshot.props[prop_id])
	for drop_id in snapshot.get("drops", {}):
		var state: Dictionary = snapshot.drops[drop_id]
		if not dropped_weapons.has(drop_id):
			_spawn_dropped_weapon(state.weapon, int(state.ammo), int(state.reserve), state.transform.origin, Vector3.ZERO, str(drop_id), float(state.get("bloodiness", 0.0)))
		if dropped_weapons.has(drop_id) and is_instance_valid(dropped_weapons[drop_id]):
			var drop = dropped_weapons[drop_id]
			drop.transform = state.transform
			drop.linear_velocity = state.linear_velocity
			drop.angular_velocity = state.angular_velocity

func _get_or_create_avatar(peer_id: int, team: int, initial_position := Vector3.ZERO) -> LocalStrikeNetworkAvatar:
	if remote_avatars.has(peer_id) and is_instance_valid(remote_avatars[peer_id]):
		return remote_avatars[peer_id]
	var avatar: LocalStrikeNetworkAvatar = NetworkAvatarScript.new()
	avatar.configure(peer_id, team)
	avatar.damaged.connect(_on_network_avatar_damaged)
	level_root.add_child(avatar)
	avatar.global_position = initial_position
	avatar.target_position = initial_position
	remote_avatars[peer_id] = avatar
	_refresh_bot_opponents()
	return avatar

func _on_network_avatar_damaged(peer_id: int, amount: float, hit_zone: String) -> void:
	if multiplayer.is_server():
		_receive_network_damage.rpc_id(peer_id, amount, hit_zone)

@rpc("authority", "call_remote", "reliable")
func _receive_network_damage(amount: float, hit_zone: String) -> void:
	player.apply_confirmed_damage(amount)

@rpc("any_peer", "call_remote", "reliable")
func _request_network_melee(sequence: int, origin: Vector3, direction: Vector3, weapon_key: String, heavy: bool) -> void:
	if not multiplayer.is_server() or not WeaponCatalog.all().has(weapon_key):
		return
	var sender := multiplayer.get_remote_sender_id()
	var avatar: LocalStrikeNetworkAvatar = remote_avatars.get(sender)
	var spec := WeaponCatalog.get_weapon(weapon_key)
	if game_mode == LocalStrikeMatchConfig.Mode.DEFUSAL and weapon_key != "knife":
		return
	if not is_instance_valid(avatar) or spec.slot != LocalStrikeWeaponDefinition.Slot.MELEE or avatar.weapon_name != spec.display_name or avatar.global_position.distance_to(origin) > 2.6:
		return
	var horizontal_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	if horizontal_direction.length_squared() < 0.5 or horizontal_direction.dot(-avatar.global_transform.basis.z) < 0.55:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var previous: Dictionary = peer_melee_state.get(sender, {"sequence": 0, "next_time": -10.0})
	var required_delay := spec.melee_heavy_recovery if heavy else spec.melee_light_recovery
	if sequence <= int(previous.sequence) or now < float(previous.next_time):
		return
	peer_melee_state[sender] = {"sequence": sequence, "next_time": now + required_delay * 0.82, "weapon": weapon_key}
	_execute_melee(avatar, sequence, origin, direction, weapon_key, heavy, sender)

@rpc("authority", "call_remote", "reliable")
func _confirm_melee(result: Dictionary) -> void:
	var connected_hit := false
	var killed_target := false
	var stain_amount := 0.0
	for hit in result.get("hits", []):
		var actor_hit := bool(hit.get("actor_hit", true))
		if actor_hit:
			var intensity := float(hit.get("blood_intensity", 1.0))
			effects.spawn_blood_hit(hit.position, hit.get("normal", Vector3.UP), -hit.get("normal", Vector3.UP), intensity, bool(hit.get("killed", false)))
			connected_hit = true
			killed_target = killed_target or bool(hit.get("killed", false))
			stain_amount = maxf(stain_amount, intensity * 0.18)
		else:
			var surface := str(hit.get("surface", "concrete"))
			effects.spawn_impact(hit.position, hit.get("normal", Vector3.UP), surface, false)
			AudioManager.play_impact(hit.position, surface)
	if connected_hit and int(result.get("attacker_peer", -1)) == multiplayer.get_unique_id():
		player.confirm_melee_hit(killed_target, stain_amount)

@rpc("any_peer", "call_remote", "reliable")
func _request_network_reload(weapon_key: String) -> void:
	if not multiplayer.is_server() or not WeaponCatalog.all().has(weapon_key):
		return
	var sender := multiplayer.get_remote_sender_id()
	var avatar: LocalStrikeNetworkAvatar = remote_avatars.get(sender)
	var spec := WeaponCatalog.get_weapon(weapon_key)
	if not is_instance_valid(avatar) or avatar.weapon_name != spec.display_name or spec.reload_time <= 0.0:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var previous: Dictionary = peer_shot_state.get(sender, {"sequence": 0, "time": -10.0, "weapon": weapon_key, "ammo": spec.magazine, "reload_ready": -1.0})
	if str(previous.get("weapon", "")) != weapon_key:
		return
	previous["reload_ready"] = now + spec.reload_time
	peer_shot_state[sender] = previous

@rpc("any_peer", "call_remote", "reliable")
func _request_network_shot(sequence: int, origin: Vector3, direction: Vector3, weapon_key: String, mode: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var avatar: LocalStrikeNetworkAvatar = remote_avatars.get(sender)
	if not is_instance_valid(avatar) or avatar.global_position.distance_to(origin) > 2.6:
		return
	var spec := WeaponCatalog.get_weapon(weapon_key)
	if mode not in spec.fire_modes:
		return
	var horizontal_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	if horizontal_direction.length_squared() < 0.5 or horizontal_direction.dot(-avatar.global_transform.basis.z) < 0.45:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var previous: Dictionary = peer_shot_state.get(sender, {"sequence": 0, "time": -10.0, "weapon": weapon_key, "ammo": spec.magazine, "reload_ready": -1.0})
	if str(previous.weapon) != weapon_key:
		previous = {"sequence": int(previous.sequence), "time": float(previous.time), "weapon": weapon_key, "ammo": spec.magazine, "reload_ready": -1.0}
	var reload_ready := float(previous.get("reload_ready", -1.0))
	if reload_ready > 0.0:
		if now < reload_ready:
			return
		previous.ammo = spec.magazine
		previous.reload_ready = -1.0
	if int(previous.ammo) <= 0:
		if now - float(previous.time) < spec.reload_time:
			return
		previous.ammo = spec.magazine
	if sequence <= int(previous.sequence) or now - float(previous.time) < spec.fire_delay * 0.82:
		return
	peer_shot_state[sender] = {"sequence": sequence, "time": now, "weapon": weapon_key, "ammo": int(previous.ammo) - 1, "reload_ready": float(previous.get("reload_ready", -1.0))}
	var combined := {"sequence": sequence, "segments": [], "hits": [], "penetrations": 0, "ricochets": 0}
	var forward := direction.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.1:
		right = Vector3.RIGHT
	var up := right.cross(forward).normalized()
	for pellet in range(spec.pellets):
		var spread := Ballistics.deterministic_spread(spec, sequence, pellet, spec.spread)
		var pellet_direction := (forward + right * spread.x + up * spread.y).normalized()
		var result := Ballistics.resolve_shot(get_world_3d().direct_space_state, origin, pellet_direction, spec, [avatar.get_rid()], sequence)
		combined.segments.append_array(result.segments)
		combined.hits.append_array(result.hits)
		combined.penetrations = int(combined.penetrations) + int(result.penetrations)
		combined.ricochets = int(combined.ricochets) + int(result.ricochets)
		for hit_data in result.hits:
			var target: Object = hit_data.target
			if target != null and target.has_method("take_ballistic_damage"):
				target.take_ballistic_damage(float(hit_data.damage), str(hit_data.zone), spec.armor_penetration)
			elif target != null and target.has_method("take_damage"):
				target.take_damage(float(hit_data.damage), str(hit_data.zone))
			if target != null and target.has_method("apply_gameplay_impulse"):
				target.apply_gameplay_impulse(pellet_direction * spec.shot_impulse, hit_data.position - target.global_position)
	var clean := Ballistics.network_result(combined)
	_confirm_shot.rpc(clean)
	_confirm_shot(clean)

@rpc("authority", "call_remote", "unreliable", 2)
func _confirm_shot(result: Dictionary) -> void:
	for segment in result.get("segments", []):
		var surface := str(segment.get("surface", "air"))
		var end: Vector3 = segment.to
		_create_tracer(segment.from, end, Color("ffd08a"))
		if surface != "air":
			var actor_hit := surface == "flesh"
			effects.spawn_impact(end, segment.get("normal", Vector3.UP), surface, actor_hit)
			if not actor_hit:
				AudioManager.play_impact(end, surface)

@rpc("authority", "call_remote", "unreliable", 2)
func _network_shot_effect(origin: Vector3, end: Vector3, normal: Vector3, surface_type: String, actor_hit: bool) -> void:
	_create_tracer(origin, end, Color("ffd08a"))
	if surface_type != "air":
		effects.spawn_impact(end, normal, surface_type, actor_hit)
		if not actor_hit:
			AudioManager.play_impact(end, surface_type)

func _build_environment() -> void:
	world_environment = WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 6.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.ambient_light_energy = 0.68
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.08
	environment.fog_enabled = true
	environment.fog_density = 0.008
	environment.ssao_enabled = true
	environment.ssao_radius = 1.8
	environment.ssao_intensity = 2.1
	environment.ssil_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	environment.ssil_radius = 3.0
	environment.ssil_intensity = 1.25
	environment.ssr_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	environment.ssr_max_steps = 48
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.volumetric_fog_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	environment.volumetric_fog_density = 0.018
	environment.volumetric_fog_length = 48.0
	environment.volumetric_fog_detail_spread = 1.6
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54, -32, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_max_distance = 58.0
	add_child(sun)

func _update_environment(palette: Dictionary) -> void:
	var environment := world_environment.environment
	environment.ambient_light_color = palette.ambient
	environment.fog_light_color = palette.background.lightened(0.12)
	sky_material.sky_top_color = palette.background.darkened(0.34)
	sky_material.sky_horizon_color = palette.background.lightened(0.28)
	sky_material.ground_bottom_color = palette.floor.darkened(0.45)
	sky_material.ground_horizon_color = palette.background.lightened(0.08)
	sun.light_color = palette.sun
	match current_level.environment_profile:
		"harbor_sunset":
			sun.rotation_degrees = Vector3(-38, -54, 0)
			sun.light_energy = 1.42
			environment.ambient_light_energy = 0.58
			environment.fog_density = 0.006
			environment.volumetric_fog_density = 0.012
		"depot_overcast":
			sun.rotation_degrees = Vector3(-61, 22, 0)
			sun.light_energy = 0.92
			sun.light_color = Color("d8e4ee")
			environment.ambient_light_energy = 0.82
			environment.fog_density = 0.011
			environment.volumetric_fog_density = 0.018
		"solar_interior":
			sun.rotation_degrees = Vector3(-72, -18, 0)
			sun.light_energy = 0.48
			sun.light_color = Color("9db9dd")
			environment.ambient_light_energy = 0.46
			environment.fog_density = 0.014
			environment.volumetric_fog_density = 0.026
		"foundry_night":
			var compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"
			sun.rotation_degrees = Vector3(-68, 28, 0)
			sun.light_energy = 0.16
			sun.light_color = Color("78989d")
			environment.ambient_light_color = Color("26363a")
			environment.ambient_light_energy = 0.62 if compatibility else 0.38
			environment.fog_light_color = Color("182629")
			environment.fog_density = 0.009 if compatibility else 0.018
			environment.volumetric_fog_density = 0.032
			environment.tonemap_exposure = 1.32 if compatibility else 1.2

func _apply_quality(index: int) -> void:
	current_quality = clampi(index, 0, 2)
	QualityManager.apply_profile(get_viewport(), world_environment.environment, sun, current_quality, effects)
	hud.show_toast("Graphics quality: %s" % ["HIGH", "MEDIUM", "LOW"][current_quality])

func _create_floor(palette: Dictionary) -> void:
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	floor.collision_layer = 1
	floor.set_meta("surface_type", "concrete")
	level_root.add_child(floor)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(32, 0.2, 32)
	mesh_instance.mesh = mesh
	mesh_instance.position.y = -0.1
	mesh_instance.material_override = _material(palette.floor, 0)
	floor.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(32, 0.2, 32)
	collision.shape = shape
	collision.position.y = -0.1
	floor.add_child(collision)

func _create_wall(data: Dictionary, palette: Dictionary) -> void:
	var height := 1.65 if data.kind == "crate" else 3.1
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.set_meta("surface_type", "metal" if data.kind == "crate" else "concrete")
	body.position = Vector3(data.rect.position.x, height / 2.0, data.rect.position.y)
	level_root.add_child(body)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(data.rect.size.x, height, data.rect.size.y)
	mesh_instance.mesh = mesh
	var tint: Color = palette.crate if data.kind == "crate" else palette.wall
	mesh_instance.material_override = _material(tint, 2 if data.kind == "crate" else 1)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	collision.shape = shape
	body.add_child(collision)
	_add_wall_details(body, mesh.size, data.kind, tint)

func _create_prop(data: Dictionary) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(data.rect.size.x, 0.035, data.rect.size.y)
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(data.rect.position.x, 0.025, data.rect.position.y)
	mesh_instance.material_override = _material(data.color, 3)
	level_root.add_child(mesh_instance)

func _create_site(data: Dictionary) -> void:
	var root := Node3D.new()
	root.position = data.position
	level_root.add_child(root)
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = data.radius
	mesh.bottom_radius = data.radius
	mesh.height = 0.035
	mesh.radial_segments = 48
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(data.color, 0.42)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = data.color * 0.32
	mesh_instance.material_override = material
	root.add_child(mesh_instance)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = data.radius - 0.11
	ring_mesh.outer_radius = data.radius
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	ring.position.y = 0.045
	ring.material_override = _glow_material(data.color, 1.8)
	root.add_child(ring)
	var label := Label3D.new()
	label.text = data.name
	label.font_size = 96
	label.modulate = data.color
	label.position.y = 0.08
	label.rotation_degrees = Vector3(-90, 0, 0)
	root.add_child(label)
	var site := data.duplicate()
	sites.append(site)
	var light := OmniLight3D.new()
	light.light_color = data.color
	light.light_energy = 1.1
	light.omni_range = 5.5
	light.position.y = 1.0
	root.add_child(light)

func _add_wall_details(body: StaticBody3D, size: Vector3, kind: String, tint: Color) -> void:
	var cap_color := tint.lightened(0.1) if kind == "wall" else Color("30363b")
	_add_detail_box(body, Vector3(size.x + 0.04, 0.075, size.z + 0.04), Vector3(0, size.y / 2.0 + 0.035, 0), cap_color, 0.5, 0.18)
	if kind == "crate":
		var rail_color := Color("2b3137")
		for x_side in [-1.0, 1.0]:
			for z_side in [-1.0, 1.0]:
				_add_detail_box(
					body,
					Vector3(0.075, size.y + 0.08, 0.075),
					Vector3(x_side * (size.x / 2.0 - 0.045), 0, z_side * (size.z / 2.0 - 0.045)),
					rail_color,
					0.38,
					0.55
				)
		return
	var hash_value := int(absf(body.position.x * 3.0 + body.position.z * 5.0))
	if hash_value % 3 != 0:
		return
	var lamp_position := Vector3(0, size.y / 2.0 - 0.48, size.z / 2.0 + 0.055)
	if size.z > size.x:
		lamp_position = Vector3(size.x / 2.0 + 0.055, size.y / 2.0 - 0.48, 0)
	_add_detail_box(body, Vector3(0.32, 0.12, 0.08), lamp_position, Color("d9f2ef"), 0.18, 0.05, true)
	var lamp := OmniLight3D.new()
	lamp.position = lamp_position
	lamp.light_color = Color("9ce8dc")
	lamp.light_energy = 0.72
	lamp.omni_range = 4.8
	lamp.shadow_enabled = false
	body.add_child(lamp)

func _add_detail_box(parent: Node3D, size: Vector3, position: Vector3, color: Color, roughness: float, metallic: float, glowing := false) -> void:
	var detail := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	detail.mesh = mesh
	detail.position = position
	detail.material_override = _glow_material(color, 1.3) if glowing else _plain_material(color, roughness, metallic)
	parent.add_child(detail)

func _create_map_beacons(palette: Dictionary) -> void:
	for position in [Vector3(-14.5, 0, -14.5), Vector3(14.5, 0, -14.5), Vector3(-14.5, 0, 14.5), Vector3(14.5, 0, 14.5)]:
		var root := Node3D.new()
		root.position = position
		level_root.add_child(root)
		_add_detail_box(root, Vector3(0.12, 2.4, 0.12), Vector3(0, 1.2, 0), Color("353e46"), 0.42, 0.62)
		_add_detail_box(root, Vector3(0.26, 0.1, 0.26), Vector3(0, 2.42, 0), palette.ambient, 0.18, 0.05, true)
		var light := OmniLight3D.new()
		light.position.y = 2.38
		light.light_color = palette.ambient
		light.light_energy = 0.9
		light.omni_range = 5.2
		light.shadow_enabled = false
		root.add_child(light)

func _create_map_identity_props() -> void:
	match level_index:
		0:
			_create_identity_box(Vector3(-12.5, 1.25, 4.8), Vector3(5.2, 2.5, 2.4), Color("315d6f"))
			_create_identity_box(Vector3(11.8, 1.25, -2.0), Vector3(5.4, 2.5, 2.4), Color("8a4b35"))
			_create_crane(Vector3(-13.8, 0, -2.5))
			_create_puddle(Vector3(-5.2, 0.008, 10.2), Vector2(5.4, 2.2), Color("6d8792"))
			_create_puddle(Vector3(7.8, 0.008, -11.0), Vector2(3.8, 1.4), Color("586e79"))
			_create_floodlight(Vector3(13.8, 0, 12.8), Vector3(-5, 0.8, 3), Color("ffe2ae"))
			_create_floodlight(Vector3(-13.8, 0, -13.2), Vector3(4, 0.5, -2), Color("b8dcff"))
			for position in [Vector3(-14.1, 0.45, 8.2), Vector3(-13.2, 0.45, 8.5), Vector3(13.6, 0.45, -9.2)]:
				_create_barrel(position, Color("d89b3c"))
		1:
			_create_train_car(Vector3(-11.0, 1.15, 1.5), Color("6d3f31"))
			_create_train_car(Vector3(10.8, 1.15, -2.2), Color("415968"))
			_create_station_canopy(Vector3(0, 0, 12.7))
			_create_signal(Vector3(-6.6, 0, -12.6), Color("ef5b5b"))
			_create_signal(Vector3(6.6, 0, 12.6), Color("6de4a5"))
			for z in [-13.0, -7.0, -1.0, 5.0, 11.0]:
				_add_rail_sleeper(z)
		2:
			_create_lab_core(Vector3.ZERO)
			for z in [-12.2, -4.2, 4.2, 12.2]:
				_create_lab_arch(Vector3(0, 0, z))
			_create_display_panel(Vector3(-14.8, 1.35, -3.2), 90.0, Color("56d8c5"))
			_create_display_panel(Vector3(14.8, 1.35, 3.2), -90.0, Color("9777ff"))
			for position in [Vector3(-11.8, 0.65, -5.0), Vector3(-11.8, 0.65, 5.0), Vector3(11.8, 0.65, -5.0), Vector3(11.8, 0.65, 5.0)]:
				_create_solar_panel(position)
		3:
			for position in [Vector3(-12, 0, -1), Vector3(-4, 0, 10), Vector3(8, 0, 4)]:
				_create_market_stall(position)
			_create_stone_arch(Vector3(-1.5, 0, 5.5), 0.0)
			_create_stone_arch(Vector3(9.0, 0, -6.0), 90.0)
			_create_floodlight(Vector3(-14, 0, -14), Vector3(-5, 0, -5), Color("ffc77d"))
		4:
			_create_ice_patch(Vector3(-5.5, 0.018, -3.0), Vector2(6.0, 4.0))
			_create_ice_patch(Vector3(8.0, 0.018, 3.0), Vector2(5.0, 5.0))
			_create_station_canopy(Vector3(0, 0, 13.0))
			_create_floodlight(Vector3(-14, 0, 13), Vector3(-4, 0, 4), Color("b8ecff"))
			_create_floodlight(Vector3(14, 0, -13), Vector3(4, 0, -4), Color("d9f4ff"))

func _create_market_stall(position: Vector3) -> void:
	var root := Node3D.new()
	root.position = position
	level_root.add_child(root)
	for x in [-0.8, 0.8]:
		_add_detail_box(root, Vector3(0.12, 2.2, 0.12), Vector3(x, 1.1, 0), Color("57402f"), 0.82, 0.0)
	_add_detail_box(root, Vector3(1.9, 0.12, 1.2), Vector3(0, 2.15, 0), Color("a8493f"), 0.76, 0.0)
	_add_detail_box(root, Vector3(1.7, 0.16, 0.75), Vector3(0, 0.92, 0), Color("765239"), 0.8, 0.0)

func _create_stone_arch(position: Vector3, rotation_y: float) -> void:
	var root := Node3D.new()
	root.position = position
	root.rotation_degrees.y = rotation_y
	level_root.add_child(root)
	for x in [-1.25, 1.25]:
		_add_detail_box(root, Vector3(0.65, 3.4, 0.8), Vector3(x, 1.7, 0), Color("81776d"), 0.92, 0.0)
	_add_detail_box(root, Vector3(3.1, 0.65, 0.8), Vector3(0, 3.25, 0), Color("81776d"), 0.92, 0.0)

func _create_ice_patch(position: Vector3, size: Vector2) -> void:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	body.set_meta("surface_type", "ice")
	level_root.add_child(body)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.025, size.y)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _plain_material(Color("91c9d9"), 0.08, 0.16)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	collision.shape = shape
	body.add_child(collision)

func _create_puddle(position: Vector3, size: Vector2, color: Color) -> void:
	var puddle := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.012, size.y)
	puddle.mesh = mesh
	puddle.position = position
	var material := _plain_material(Color(color, 0.62), 0.08, 0.18)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puddle.material_override = material
	level_root.add_child(puddle)

func _create_floodlight(position: Vector3, target: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.position = position
	level_root.add_child(root)
	_add_detail_box(root, Vector3(0.16, 4.8, 0.16), Vector3(0, 2.4, 0), Color("303940"), 0.42, 0.72)
	_add_detail_box(root, Vector3(0.72, 0.34, 0.24), Vector3(0, 4.75, 0), Color("d4d9d7"), 0.26, 0.48, true)
	var light := SpotLight3D.new()
	light.position = Vector3(0, 4.7, 0)
	light.light_color = color
	light.light_energy = 4.2
	light.spot_range = 18.0
	light.spot_angle = 34.0
	light.shadow_enabled = current_quality == 0
	root.add_child(light)
	light.look_at(target, Vector3.UP)

func _create_station_canopy(position: Vector3) -> void:
	var root := Node3D.new()
	root.position = position
	level_root.add_child(root)
	_add_detail_box(root, Vector3(18.0, 0.18, 2.4), Vector3(0, 3.0, 0), Color("3c454b"), 0.58, 0.52)
	for x in [-8.0, -4.0, 4.0, 8.0]:
		_add_detail_box(root, Vector3(0.16, 3.0, 0.16), Vector3(x, 1.5, 0), Color("252c31"), 0.42, 0.68)

func _create_signal(position: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.position = position
	level_root.add_child(root)
	_add_detail_box(root, Vector3(0.12, 3.2, 0.12), Vector3(0, 1.6, 0), Color("242a2e"), 0.48, 0.7)
	_add_detail_box(root, Vector3(0.44, 0.58, 0.3), Vector3(0, 3.12, 0), Color("1b2024"), 0.38, 0.65)
	var lens := MeshInstance3D.new()
	var lens_mesh := SphereMesh.new()
	lens_mesh.radius = 0.12
	lens_mesh.height = 0.24
	lens.mesh = lens_mesh
	lens.position = Vector3(0, 3.18, -0.17)
	lens.material_override = _glow_material(color, 3.2)
	root.add_child(lens)

func _create_lab_arch(position: Vector3) -> void:
	var root := Node3D.new()
	root.position = position
	level_root.add_child(root)
	for x in [-6.4, 6.4]:
		_add_detail_box(root, Vector3(0.28, 4.0, 0.3), Vector3(x, 2.0, 0), Color("34445b"), 0.36, 0.62)
	_add_detail_box(root, Vector3(13.1, 0.28, 0.3), Vector3(0, 3.9, 0), Color("34445b"), 0.36, 0.62)
	_add_detail_box(root, Vector3(11.8, 0.08, 0.12), Vector3(0, 3.72, 0), Color("56d8c5"), 0.18, 0.05, true)

func _create_display_panel(position: Vector3, rotation_y: float, color: Color) -> void:
	var root := Node3D.new()
	root.position = position
	root.rotation_degrees.y = rotation_y
	level_root.add_child(root)
	_add_detail_box(root, Vector3(0.08, 1.45, 2.1), Vector3.ZERO, Color("17232d"), 0.38, 0.62)
	for y in [-0.42, 0.0, 0.42]:
		_add_detail_box(root, Vector3(0.045, 0.25, 1.65), Vector3(-0.06, y, 0), color.darkened(absf(y) * 0.5), 0.18, 0.02, true)

func _create_interactables() -> void:
	for data in current_level.interactables:
		var interactive: LocalStrikeInteractable = InteractableScript.new()
		interactive.configure(data)
		interactive.position = data.get("position", Vector3.ZERO)
		interactive.rotation_degrees.y = float(data.get("rotation_y", 0.0))
		interactive.state_changed.connect(_on_interactable_state_changed)
		interactive.exploded.connect(_on_interactable_exploded)
		interactive.effect_requested.connect(_on_interactable_effect)
		level_root.add_child(interactive)
		interactables[interactive.interactable_id] = interactive
		if interactive.kind == LocalStrikeInteractable.Kind.DOOR:
			_create_door_frame(interactive.position, float(data.get("rotation_y", 0.0)), interactive.size, data.get("color", Color("52616b")))

func _create_physics_props() -> void:
	for data in current_level.physics_props:
		var prop = PhysicsPropScript.new()
		prop.configure(data)
		prop.position = data.get("position", Vector3.ZERO)
		prop.rotation_degrees.y = float(data.get("rotation_y", 0.0))
		prop.state_changed.connect(_on_physics_prop_state_changed)
		prop.destroyed.connect(_on_physics_prop_destroyed)
		level_root.add_child(prop)
		physics_props[prop.prop_id] = prop

func _on_physics_prop_state_changed(_prop_id: String, _state: Dictionary) -> void:
	pass

func _on_physics_prop_destroyed(prop: Object, position: Vector3, surface_type: String) -> void:
	var explosive := prop is LocalStrikePhysicsProp and (prop as LocalStrikePhysicsProp).visual_variant == "barrel"
	_create_burst(position, Color("ff7a35") if explosive else (Color("b79872") if surface_type == "wood" else Color("b9d6dc")), 32 if explosive else 18)
	effects.spawn_impact(position, Vector3.UP, surface_type, false)
	if explosive and not _is_network_client():
		_apply_radial_damage(position, 70.0, 4.5, prop)

func _create_door_frame(position: Vector3, rotation_y: float, size: Vector3, color: Color) -> void:
	var frame := Node3D.new()
	frame.position = position
	frame.rotation_degrees.y = rotation_y
	level_root.add_child(frame)
	var dark := color.darkened(0.55)
	_add_detail_box(frame, Vector3(0.14, size.y + 0.28, size.z + 0.18), Vector3(-size.x * 0.56, 0, 0), dark, 0.32, 0.72)
	_add_detail_box(frame, Vector3(0.14, size.y + 0.28, size.z + 0.18), Vector3(size.x * 0.56, 0, 0), dark, 0.32, 0.72)
	_add_detail_box(frame, Vector3(size.x + 0.32, 0.14, size.z + 0.18), Vector3(0, size.y * 0.55, 0), dark, 0.32, 0.72)

func _create_reflection_probes() -> void:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" or current_quality == 2:
		return
	for data in current_level.reflection_zones:
		var probe := ReflectionProbe.new()
		probe.position = data.get("position", Vector3(0, 2.0, 0))
		probe.size = data.get("size", Vector3(12, 5, 12))
		probe.box_projection = true
		probe.intensity = float(data.get("intensity", 0.7))
		probe.max_distance = 36.0
		probe.enable_shadows = false
		level_root.add_child(probe)

func _create_identity_box(position: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.set_meta("surface_type", "metal")
	body.position = position
	level_root.add_child(body)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color, 2)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	for x in [-1.0, 1.0]:
		_add_detail_box(body, Vector3(0.09, size.y + 0.06, size.z + 0.08), Vector3(x * (size.x / 2.0 - 0.05), 0, 0), Color("252e34"), 0.4, 0.55)
	return body

func _create_crane(position: Vector3) -> void:
	var root := Node3D.new()
	root.position = position
	level_root.add_child(root)
	var yellow := Color("c49338")
	_add_detail_box(root, Vector3(0.28, 7.0, 0.28), Vector3(0, 3.5, 0), yellow, 0.48, 0.6)
	_add_detail_box(root, Vector3(7.2, 0.3, 0.3), Vector3(3.4, 6.8, 0), yellow, 0.48, 0.6)
	_add_detail_box(root, Vector3(0.06, 3.2, 0.06), Vector3(6.2, 5.1, 0), Color("20272c"), 0.4, 0.7)

func _create_barrel(position: Vector3, color: Color) -> void:
	var barrel := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.28
	mesh.bottom_radius = 0.28
	mesh.height = 0.86
	mesh.radial_segments = 16
	barrel.mesh = mesh
	barrel.position = position
	barrel.material_override = _plain_material(color, 0.55, 0.38)
	level_root.add_child(barrel)

func _create_train_car(position: Vector3, color: Color) -> void:
	var car := _create_identity_box(position, Vector3(2.5, 2.3, 7.0), color)
	for z in [-2.3, 0.0, 2.3]:
		_add_detail_box(car, Vector3(2.62, 0.12, 0.1), Vector3(0, 0.5, z), Color("252b2e"), 0.36, 0.62)
	for z in [-2.45, 2.45]:
		for x in [-0.8, 0.8]:
			var wheel := MeshInstance3D.new()
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.31
			wheel_mesh.bottom_radius = 0.31
			wheel_mesh.height = 0.16
			wheel.mesh = wheel_mesh
			wheel.rotation_degrees.z = 90.0
			wheel.position = Vector3(x, -1.12, z)
			wheel.material_override = _plain_material(Color("151a1d"), 0.7, 0.4)
			car.add_child(wheel)

func _add_rail_sleeper(z: float) -> void:
	var root := Node3D.new()
	level_root.add_child(root)
	_add_detail_box(root, Vector3(31.0, 0.06, 0.18), Vector3(0, 0.02, z), Color("3c3430"), 0.9, 0.0)
	for x in [-10.8, 10.8]:
		_add_detail_box(root, Vector3(0.09, 0.08, 5.6), Vector3(x, 0.07, z), Color("6f7475"), 0.28, 0.8)

func _create_lab_core(position: Vector3) -> void:
	var root := Node3D.new()
	root.position = position + Vector3.UP * 2.0
	level_root.add_child(root)
	var core := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.72
	mesh.bottom_radius = 0.72
	mesh.height = 4.0
	mesh.radial_segments = 24
	core.mesh = mesh
	core.material_override = _plain_material(Color("34465a"), 0.32, 0.58)
	root.add_child(core)
	for y in [-1.2, 0.0, 1.2]:
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.74
		ring_mesh.outer_radius = 0.86
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 8
		ring.mesh = ring_mesh
		ring.position.y = y
		ring.material_override = _glow_material(Color("56d8c5"), 1.9)
		root.add_child(ring)

func _create_solar_panel(position: Vector3) -> void:
	var root := Node3D.new()
	root.position = position
	root.rotation_degrees.x = -24.0
	level_root.add_child(root)
	_add_detail_box(root, Vector3(2.8, 0.08, 1.65), Vector3.ZERO, Color("203c5a"), 0.22, 0.38)
	for x in [-0.92, 0.0, 0.92]:
		_add_detail_box(root, Vector3(0.035, 0.095, 1.68), Vector3(x, 0.02, 0), Color("9ac5d1"), 0.25, 0.5)

func _create_charge(position: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = position + Vector3.UP * 0.22
	level_root.add_child(root)
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.7, 0.28, 0.48)
	body.mesh = mesh
	body.material_override = _plain_material(Color("1d2228"), 0.55, 0.35)
	root.add_child(body)
	var screen := MeshInstance3D.new()
	var screen_mesh := BoxMesh.new()
	screen_mesh.size = Vector3(0.45, 0.04, 0.26)
	screen.mesh = screen_mesh
	screen.position.y = 0.16
	var screen_material := _plain_material(Color("56d8c5"), 0.4, 0.1)
	screen_material.emission_enabled = true
	screen_material.emission = Color("1b665c")
	screen.material_override = screen_material
	root.add_child(screen)
	var light := OmniLight3D.new()
	light.light_color = Color("f3b447")
	light.light_energy = 2.0
	light.omni_range = 4.0
	root.add_child(light)
	return root

func _create_tracer(origin: Vector3, end: Vector3, color: Color) -> void:
	effects.spawn_tracer(origin, end, color)

func _create_burst(position: Vector3, color: Color, count: int) -> void:
	effects.spawn_burst(position, color, count, 1.35)

func _material(color: Color, pattern: int) -> StandardMaterial3D:
	var key := "%s:%d" % [color.to_html(), pattern]
	if material_cache.has(key):
		return material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE.lerp(color, 0.32) if pattern in [0, 2] else Color.WHITE
	material.albedo_texture = ConcreteDiffuse if pattern == 0 else (MetalDiffuse if pattern == 2 else _procedural_texture(color, pattern))
	material.normal_enabled = true
	material.normal_texture = ConcreteNormal if pattern == 0 else (MetalNormal if pattern == 2 else _procedural_normal_texture(pattern))
	material.normal_scale = 0.52
	material.roughness = 0.82 if pattern != 2 else 0.68
	material.metallic = 0.05 if pattern != 3 else 0.25
	if pattern in [0, 2]:
		var arm_texture: Texture2D = ConcreteArm if pattern == 0 else MetalArm
		material.ao_enabled = true
		material.ao_texture = arm_texture
		material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		material.roughness_texture = arm_texture
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		material.metallic_texture = arm_texture
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_scale = Vector3(3.0, 3.0, 3.0)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material_cache[key] = material
	return material

func _plain_material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := _plain_material(color, 0.22, 0.06)
	material.emission_enabled = true
	material.emission = color * energy
	return material

func _procedural_texture(base: Color, pattern: int) -> ImageTexture:
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var noise := sin(float(x * 17 + y * 31 + pattern * 13)) * 0.045
			noise += sin(float(x * 5 - y * 7 + pattern * 29)) * 0.025
			var color := base.lightened(maxf(0.0, noise)).darkened(maxf(0.0, -noise))
			if pattern == 0 and (x % 32 <= 1 or y % 32 <= 1):
				color = base.lightened(0.11)
			elif pattern == 1 and (x % 32 <= 1 or y % 24 <= 1):
				color = base.darkened(0.16)
			elif pattern == 2 and (x % 24 <= 2 or abs((x % 48) - (y % 48)) <= 2 or abs((47 - x % 48) - (y % 48)) <= 2):
				color = base.darkened(0.24)
			elif pattern == 3:
				color = base if int((x + y) / 18) % 2 == 0 else Color("252a30")
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _procedural_normal_texture(pattern: int) -> ImageTexture:
	if normal_texture_cache.has(pattern):
		return normal_texture_cache[pattern]
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var nx := sin(float(x * 0.42 + pattern * 2.1)) * 0.12
			var ny := cos(float(y * 0.37 - pattern * 1.7)) * 0.12
			if pattern == 0 and (x % 32 <= 1 or y % 32 <= 1):
				nx *= 2.2
				ny *= 2.2
			elif pattern == 2 and x % 24 <= 2:
				nx = 0.34
			image.set_pixel(x, y, Color(0.5 + nx, 0.5 + ny, 1.0, 1.0))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	normal_texture_cache[pattern] = texture
	return texture

func _update_hud() -> void:
	if hud == null or player == null or current_level == null:
		return
	var phase_text := "SANDBOX" if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX else ("DEATHMATCH" if game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH else ("BUY" if phase == Phase.BUY else ("ROUND END" if phase == Phase.ENDED else ("PLANTED" if charge_planted else "LIVE"))))
	var charge_text := "CHAOS MODE" if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX else ("FREE LOADOUT" if game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH else ("DEFEND" if player_team == 1 else "CARRIED"))
	var site: Dictionary = _current_site()
	if charge_planted:
		charge_text = "DEFUSE %.1f" % maxf(0.0, 5.5 - defuse_progress) if defuse_progress > 0.0 else _format_time(bomb_timer)
	elif not site.is_empty() and player_team == 0:
		charge_text = "PLANT %.1f" % maxf(0.0, 3.2 - plant_progress) if plant_progress > 0.0 else "SITE %s" % site.name
	var weapon_spec := WeaponCatalog.get_weapon(player.weapon_key)
	var ally_positions: Array[Vector3] = []
	var enemy_positions: Array[Vector3] = []
	for ally in allies:
		if is_instance_valid(ally): ally_positions.append(ally.global_position)
	for enemy in enemies:
		if is_instance_valid(enemy): enemy_positions.append(enemy.global_position)
	var sandbox_prop_count := _sandbox_prop_count()
	if sandbox_browser != null:
		sandbox_browser.set_counts(enemies.size() + allies.size(), sandbox_prop_count, dropped_weapons.size(), sandbox_ragdolls.size())
	hud.update_state({
		"map_index": level_index,
		"map_count": levels.size(),
		"map_name": current_level.map_name,
		"phase": phase_text,
		"time": "FREE" if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX else _format_time(bomb_timer if charge_planted else phase_timer),
		"attack_score": attack_score,
		"defense_score": defense_score,
		"money": player.money,
		"money_text": "SANDBOX" if game_mode == LocalStrikeMatchConfig.Mode.SANDBOX else "$%d" % player.money,
		"health": player.health,
		"armor": player.armor,
		"weapon": weapon_spec.display_name,
		"ammo": "LIGHT / RMB HEAVY" if weapon_spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE else ("RELOAD" if player.is_reloading() else "%d / %d" % [player.ammo, player.reserve_ammo]),
		"fire_mode": player.get_fire_mode(),
		"aiming": player.aiming,
		"charge": charge_text,
		"stamina": player.stamina,
		"buy_visible": show_buy and started and game_mode != LocalStrikeMatchConfig.Mode.SANDBOX and (phase == Phase.BUY or game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH),
		"sandbox_visible": false,
		"sandbox_mode": game_mode == LocalStrikeMatchConfig.Mode.SANDBOX,
		"sandbox_npcs": enemies.size() + allies.size(),
		"sandbox_props": physics_props.size() + dropped_weapons.size(),
		"sandbox_weapons": dropped_weapons.size(),
		"sandbox_bodies": sandbox_ragdolls.size(),
		"sandbox_god": sandbox_god_mode,
		"sandbox_slow": sandbox_slow_motion,
		"free_loadout": game_mode in [LocalStrikeMatchConfig.Mode.DEATHMATCH, LocalStrikeMatchConfig.Mode.SANDBOX],
		"spectating": player_dead and game_mode == LocalStrikeMatchConfig.Mode.DEFUSAL,
		"spectator_name": "TEAMMATE",
		"roster": _scoreboard_roster(),
		"radar": {"player_position": player.global_position, "player_yaw": player.rotation.y, "allies": ally_positions, "enemies": enemy_positions, "sites": sites}
	})

func _scoreboard_roster() -> Dictionary:
	var roster := GameSession.roster.duplicate(true)
	var index := 0
	for bot in allies + enemies:
		if is_instance_valid(bot):
			roster[-100 - index] = {"name": "%s BOT %d" % ["ATK" if bot.team == 0 else "DEF", index + 1], "team": bot.team, "kills": 0, "deaths": 0}
			index += 1
	return roster

func _format_time(seconds: float) -> String:
	var safe := maxi(0, ceili(seconds))
	return "%d:%02d" % [int(safe / 60), safe % 60]

func _ensure_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("sprint", KEY_SHIFT)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("crouch", KEY_CTRL)
	_add_key_action("reload", KEY_R)
	_add_key_action("fire_mode", KEY_V)
	_add_key_action("drop_weapon", KEY_G)
	_add_key_action("interact", KEY_E)
	_add_key_action("toggle_buy", KEY_B)
	_add_key_action("map_next", KEY_M)
	_add_key_action("weapon_1", KEY_1)
	_add_key_action("weapon_2", KEY_2)
	_add_key_action("weapon_3", KEY_3)
	_add_key_action("weapon_4", KEY_4)
	_add_key_action("select_primary", KEY_1)
	_add_key_action("select_secondary", KEY_2)
	_add_key_action("select_melee", KEY_3)
	_add_key_action("select_grenade", KEY_4)
	_add_key_action("scoreboard", KEY_TAB)
	_add_key_action("restart", KEY_F2)
	_add_key_action("pause", KEY_ESCAPE)
	_add_key_action("pause", KEY_P)
	_add_key_action("sandbox_enemy", KEY_F5)
	_add_key_action("sandbox_ally", KEY_F6)
	_add_key_action("sandbox_prop", KEY_F7)
	_add_key_action("sandbox_blast", KEY_F8)
	_add_key_action("sandbox_slow", KEY_F9)
	_add_key_action("sandbox_clear", KEY_F10)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mouse)
	if not InputMap.has_action("aim"):
		InputMap.add_action("aim")
		var aim_mouse := InputEventMouseButton.new()
		aim_mouse.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("aim", aim_mouse)

func _add_key_action(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)

func _create_levels() -> Array[LocalStrikeMapDefinition]:
	var data := [
		{
			"name": "HARBOR YARD",
			"player_spawn": Vector3(0, 0.05, 12),
			"palette": _palette(Color("101820"), Color("39464f"), Color("596874"), Color("795333"), Color("a9d8ff")),
			"walls": _with_borders([
				_w(-6.5, -5.5, 7.2, 1.0), _w(5.8, -4.0, 1.0, 7.5), _w(-6.0, 5.3, 1.0, 6.8), _w(4.0, 6.0, 7.4, 1.0),
				_w(-11.5, -1.8, 3.0, 2.0, "crate"), _w(9.0, -12.0, 3.8, 2.0, "crate"), _w(-0.2, 1.5, 3.6, 2.2, "crate"), _w(12.2, 12.0, 2.4, 2.6, "crate"),
				_w(-2.7, -11.8, 2.2, 1.4, "crate"), _w(8.2, 3.5, 1.4, 2.6, "crate")
			]),
			"sites": [_site("A", -10, -10, 3.1, Color("56d8c5")), _site("B", 10, 8, 3.1, Color("f3b447"))],
			"bot_spawns": [Vector3(-11, 0.05, -11), Vector3(11, 0.05, -9), Vector3(10, 0.05, 7), Vector3(-9, 0.05, 8), Vector3(0, 0.05, -13)],
			"patrols": [Vector3(-12, 0, -8), Vector3(-4, 0, -3), Vector3(5, 0, -10), Vector3(12, 0, 4), Vector3(-11, 0, 9), Vector3.ZERO],
			"props": [_prop(-13, -12, 4.2, 0.4, Color("f3b447")), _prop(12, 10.8, 3.5, 0.4, Color("56d8c5"))],
			"environment_profile": "harbor_sunset",
			"reflection_zones": [_reflection(Vector3(-8, 2.2, 4), Vector3(13, 5, 11)), _reflection(Vector3(9, 2.2, -5), Vector3(11, 5, 13))],
			"physics_props": [_physics_prop("harbor_crate_1", Vector3(-4.2, 0.55, 8.0), Vector3(1.1, 1.1, 1.1), "wood"), _physics_prop("harbor_barrel_1", Vector3(10.8, 0.55, 4.5), Vector3(0.7, 1.1, 0.7), "metal", 28.0, 75.0)],
			"interactables": [
				_interactive("harbor_door", LocalStrikeInteractable.Kind.DOOR, Vector3(2.8, 1.25, -5.3), Vector3(1.75, 2.5, 0.2), Color("3e6372")),
				_interactive("harbor_glass", LocalStrikeInteractable.Kind.GLASS, Vector3(-10.8, 1.15, 5.8), Vector3(2.8, 1.55, 0.07), Color("83c6d3"), 90.0),
				_interactive("harbor_lamp", LocalStrikeInteractable.Kind.LAMP, Vector3(8.8, 2.65, 5.8)),
				_interactive("harbor_fuel", LocalStrikeInteractable.Kind.FUEL, Vector3(-13.4, 0.5, 8.5))
			]
		},
		{
			"name": "TRAIN DEPOT",
			"player_spawn": Vector3(-12.5, 0.05, 12.2),
			"palette": _palette(Color("211815"), Color("4a3f34"), Color("675447"), Color("6f4d2d"), Color("ffd0a2")),
			"walls": _with_borders([
				_w(-8.5, -8.8, 1.0, 10.4), _w(0, -2.8, 1.0, 12.2), _w(8.5, 4.2, 1.0, 10.4), _w(-4.2, 8.5, 6.0, 1.0), _w(5.0, -10.8, 6.2, 1.0),
				_w(-13, 0.5, 2.6, 4.8, "crate"), _w(-3.9, -11.8, 3.0, 2.3, "crate"), _w(4.1, 0.2, 3.0, 2.3, "crate"), _w(12.8, -5.5, 2.2, 5.6, "crate"),
				_w(-4.4, 3.2, 2.2, 1.4, "crate"), _w(4.3, 10.8, 2.4, 1.4, "crate")
			]),
			"sites": [_site("A", -12, -10, 3.0, Color("ef5b5b")), _site("B", 11.5, 10.2, 3.0, Color("f3b447"))],
			"bot_spawns": [Vector3(12, 0.05, -12), Vector3(12, 0.05, 1), Vector3(4, 0.05, -13), Vector3(-4, 0.05, -12), Vector3(13, 0.05, 10)],
			"patrols": [Vector3(-12, 0, -10), Vector3(-10, 0, 4), Vector3(-2, 0, 12), Vector3(8, 0, 12), Vector3(12, 0, -8), Vector3(2, 0, 0)],
			"props": [_prop(-10.8, -2.2, 0.36, 23, Color("d88842")), _prop(10.8, 2.2, 0.36, 23, Color("d88842"))],
			"environment_profile": "depot_overcast",
			"reflection_zones": [_reflection(Vector3(-10, 2.1, 1), Vector3(8, 5, 18)), _reflection(Vector3(10, 2.1, -2), Vector3(8, 5, 18))],
			"physics_props": [_physics_prop("depot_cart_1", Vector3(-7.0, 0.55, 4.0), Vector3(1.6, 1.0, 0.8), "metal", 42.0, 90.0), _physics_prop("depot_crate_1", Vector3(6.0, 0.55, -7.0), Vector3.ONE, "wood")],
			"interactables": [
				_interactive("depot_door", LocalStrikeInteractable.Kind.DOOR, Vector3(1.3, 1.25, 4.5), Vector3(1.65, 2.5, 0.2), Color("6b4d3d"), 90.0),
				_interactive("depot_glass", LocalStrikeInteractable.Kind.GLASS, Vector3(-5.7, 1.2, 11.2), Vector3(2.6, 1.55, 0.07), Color("b1ced4")),
				_interactive("depot_lamp", LocalStrikeInteractable.Kind.LAMP, Vector3(6.0, 2.7, 8.2)),
				_interactive("depot_fuel", LocalStrikeInteractable.Kind.FUEL, Vector3(13.5, 0.5, -9.0))
			]
		},
		{
			"name": "SOLAR LAB",
			"player_spawn": Vector3(0, 0.05, 13),
			"palette": _palette(Color("0b1020"), Color("2f3b55"), Color("4c5a79"), Color("485764"), Color("b9a8ff")),
			"walls": _with_borders([
				_w(0, -7.5, 8.8, 1.0), _w(0, 7.5, 8.8, 1.0), _w(-7.5, 0, 1.0, 8.8), _w(7.5, 0, 1.0, 8.8), _w(-12, -7.5, 4.0, 1.0), _w(12, 7.5, 4.0, 1.0),
				_w(-10.8, 8.6, 2.8, 2.8, "crate"), _w(10.8, -8.6, 2.8, 2.8, "crate"), _w(0, 0, 3.2, 3.2, "crate"), _w(-13.2, 0, 2.2, 2.2, "crate"), _w(13.2, 0, 2.2, 2.2, "crate"),
				_w(-4.6, -11.4, 2.0, 1.2, "crate"), _w(5.0, 11.2, 2.0, 1.2, "crate")
			]),
			"sites": [_site("A", -11.2, 10.8, 3.05, Color("9777ff")), _site("B", 11.2, -10.8, 3.05, Color("56d8c5"))],
			"bot_spawns": [Vector3(-12, 0.05, -12), Vector3(12, 0.05, 12), Vector3(11, 0.05, 1), Vector3(-11, 0.05, -1), Vector3(0, 0.05, -12.5)],
			"patrols": [Vector3(-11, 0, 10), Vector3(-4, 0, 4), Vector3.ZERO, Vector3(4, 0, -4), Vector3(11, 0, -10), Vector3(12, 0, 8), Vector3(-12, 0, -8)],
			"props": [_prop(0, 0, 7, 0.35, Color("9777ff")), _prop(0, 0, 0.35, 7, Color("56d8c5"))],
			"environment_profile": "solar_interior",
			"reflection_zones": [_reflection(Vector3.ZERO + Vector3.UP * 2.0, Vector3(15, 6, 15)), _reflection(Vector3(10, 2.0, -9), Vector3(9, 5, 9))],
			"physics_props": [_physics_prop("lab_cell_1", Vector3(-8.5, 0.65, 1.0), Vector3(0.8, 1.3, 0.8), "metal", 34.0, 80.0), _physics_prop("lab_glass_cart", Vector3(8.2, 0.5, -2.0), Vector3(1.2, 0.9, 0.7), "glass", 18.0, 35.0)],
			"interactables": [
				_interactive("lab_door", LocalStrikeInteractable.Kind.DOOR, Vector3(-4.2, 1.25, -3.5), Vector3(1.7, 2.5, 0.2), Color("465a77"), 90.0),
				_interactive("lab_glass", LocalStrikeInteractable.Kind.GLASS, Vector3(4.2, 1.2, 4.6), Vector3(3.2, 1.65, 0.07), Color("8fddea"), 90.0),
				_interactive("lab_lamp", LocalStrikeInteractable.Kind.LAMP, Vector3(-9.0, 2.75, 8.0)),
				_interactive("lab_fuel", LocalStrikeInteractable.Kind.FUEL, Vector3(12.8, 0.5, 3.8), Vector3(0.58, 0.95, 0.58), Color("a7445f"))
			]
		},
		{
			"name": "OLD QUARTER",
			"player_spawn": Vector3(-13.0, 0.05, 13.0),
			"palette": _palette(Color("172027"), Color("575552"), Color("81776d"), Color("75513d"), Color("ffc77d")),
			"walls": _with_borders([
				_w(-10.5, -6.0, 1.0, 12.0), _w(0, -9.0, 9.0, 1.0), _w(10.5, -3.5, 1.0, 13.0),
				_w(-5.0, 5.5, 9.0, 1.0), _w(6.0, 8.0, 1.0, 10.0), _w(0, 0, 4.2, 4.2, "crate"),
				_w(-12.5, 8.0, 2.8, 2.0, "crate"), _w(12.0, 10.5, 3.4, 1.6, "crate"), _w(5.0, -13.0, 2.4, 1.5, "crate")
			]),
			"sites": [_site("A", -12.0, -11.0, 3.0, Color("e9a84d")), _site("B", 11.5, 10.5, 3.0, Color("56d8c5"))],
			"bot_spawns": [Vector3(13, 0.05, -13), Vector3(12, 0.05, -7), Vector3(8, 0.05, -13), Vector3(13, 0.05, 2), Vector3(5, 0.05, -8)],
			"patrols": [Vector3(-12, 0, -11), Vector3(-5, 0, -2), Vector3(-10, 0, 10), Vector3.ZERO, Vector3(10, 0, 5), Vector3(12, 0, -10)],
			"props": [_prop(-7.0, 11.5, 6.0, 0.25, Color("d79a4b")), _prop(11.8, -5.0, 0.25, 6.0, Color("56d8c5"))],
			"environment_profile": "quarter_evening",
			"reflection_zones": [_reflection(Vector3(-8, 2.0, 8), Vector3(10, 5, 10))],
			"physics_props": [_physics_prop("quarter_stall_1", Vector3(-4.0, 0.65, 10.0), Vector3(1.8, 1.2, 0.9), "wood", 32.0, 55.0), _physics_prop("quarter_cart_1", Vector3(8.0, 0.55, 4.0), Vector3(1.5, 1.0, 0.8), "wood", 24.0, 45.0)],
			"interactables": [
				_interactive("quarter_door", LocalStrikeInteractable.Kind.DOOR, Vector3(-6.2, 1.25, 5.4), Vector3(1.7, 2.5, 0.2), Color("79543d")),
				_interactive("quarter_glass", LocalStrikeInteractable.Kind.GLASS, Vector3(10.4, 1.2, 3.0), Vector3(2.6, 1.5, 0.07), Color("a9d8d0"), 90.0),
				_interactive("quarter_lamp", LocalStrikeInteractable.Kind.LAMP, Vector3(-11.0, 2.7, -4.0)),
				_interactive("quarter_fuel", LocalStrikeInteractable.Kind.FUEL, Vector3(12.5, 0.5, 9.0))
			]
		},
		{
			"name": "FROSTLINE STATION",
			"player_spawn": Vector3(0, 0.05, 13.5),
			"palette": _palette(Color("a8bfca"), Color("b8c8ce"), Color("596b75"), Color("3f5865"), Color("b8ecff")),
			"walls": _with_borders([
				_w(-9.0, -6.0, 1.0, 12.0), _w(9.0, -6.0, 1.0, 12.0), _w(0, -10.5, 10.0, 1.0),
				_w(-5.5, 5.0, 8.0, 1.0), _w(6.0, 7.5, 1.0, 8.0), _w(0, 0, 4.0, 2.5, "crate"),
				_w(-12.0, 10.0, 3.0, 2.0, "crate"), _w(12.0, 10.0, 3.0, 2.0, "crate"), _w(0, -14.0, 3.5, 1.4, "crate")
			]),
			"sites": [_site("A", -12.0, -10.5, 3.0, Color("70d9ff")), _site("B", 12.0, 10.5, 3.0, Color("ffb15a"))],
			"bot_spawns": [Vector3(-13, 0.05, -13), Vector3(13, 0.05, -13), Vector3(0, 0.05, -13), Vector3(-12, 0.05, -6), Vector3(12, 0.05, -5)],
			"patrols": [Vector3(-12, 0, -10), Vector3(-6, 0, 0), Vector3(0, 0, 7), Vector3(7, 0, 4), Vector3(12, 0, -10), Vector3.ZERO],
			"props": [_prop(-12.5, 0, 0.3, 9.0, Color("70d9ff")), _prop(12.5, 1.0, 0.3, 9.0, Color("ffb15a"))],
			"environment_profile": "frost_day",
			"reflection_zones": [_reflection(Vector3.ZERO + Vector3.UP * 2.0, Vector3(16, 5, 16), 0.82)],
			"physics_props": [_physics_prop("frost_crate_1", Vector3(-5.0, 0.55, 8.5), Vector3(1.1, 1.1, 1.1), "wood"), _physics_prop("frost_case_1", Vector3(7.5, 0.45, -3.0), Vector3(1.4, 0.8, 0.8), "metal", 36.0, 80.0)],
			"interactables": [
				_interactive("frost_door", LocalStrikeInteractable.Kind.DOOR, Vector3(4.2, 1.25, 7.4), Vector3(1.7, 2.5, 0.2), Color("567381"), 90.0),
				_interactive("frost_glass", LocalStrikeInteractable.Kind.GLASS, Vector3(-8.8, 1.2, -1.0), Vector3(3.0, 1.6, 0.07), Color("b6ebf5"), 90.0),
				_interactive("frost_lamp", LocalStrikeInteractable.Kind.LAMP, Vector3(10.5, 2.8, 6.0)),
				_interactive("frost_fuel", LocalStrikeInteractable.Kind.FUEL, Vector3(-12.5, 0.5, 9.0))
			]
		}
	]
	data.append({
		"name": "ABANDONED FOUNDRY",
		"player_spawn": Vector3(0.0, 0.08, 13.5),
		"palette": _palette(Color("080b0d"), Color("353a3b"), Color("4b4f4e"), Color("6e5541"), Color("8db7b4")),
		"walls": [],
		"sites": [],
		"bot_spawns": [Vector3(17, 0.08, -14), Vector3(16, 0.08, 10), Vector3(-15, 0.08, -14), Vector3(7, 0.08, 12), Vector3(-7, 0.08, 2)],
		"patrols": [Vector3(-17, 0.08, -13), Vector3(-6, 0.08, -8), Vector3(3, 0.08, 8), Vector3(17, 0.08, 13), Vector3(18, 0.08, -10), Vector3(-16, 0.08, 12)],
		"props": [],
		"environment_profile": "foundry_night",
		"reflection_zones": [],
		"physics_props": [
			_physics_prop("foundry_crate_1", Vector3(-17.2, 0.58, -5.6), Vector3(1.15, 1.15, 1.15), "wood", 18.0, 55.0),
			_physics_prop("foundry_crate_2", Vector3(-15.8, 0.58, -5.2), Vector3(1.15, 1.15, 1.15), "wood", 18.0, 55.0),
			_physics_prop("foundry_case_1", Vector3(10.2, 0.42, 10.5), Vector3(1.5, 0.82, 0.9), "metal", 38.0, 95.0),
			_physics_prop("foundry_barrel_1", Vector3(8.8, 0.56, -8.7), Vector3(0.72, 1.12, 0.72), "metal", 24.0, 65.0),
			_physics_prop("foundry_barrel_2", Vector3(10.0, 0.56, -8.4), Vector3(0.72, 1.12, 0.72), "metal", 24.0, 65.0)
		],
		"interactables": [
			_interactive("foundry_door", LocalStrikeInteractable.Kind.DOOR, Vector3(-9.1, 1.25, -6.3), Vector3(1.8, 2.5, 0.2), Color("5d493b"), 90.0),
			_interactive("foundry_glass", LocalStrikeInteractable.Kind.GLASS, Vector3(-14.2, 4.15, 7.25), Vector3(7.8, 2.1, 0.08), Color("73979c")),
			_interactive("foundry_lamp", LocalStrikeInteractable.Kind.LAMP, Vector3(-3.5, 5.8, -10.0)),
			_interactive("foundry_fuel", LocalStrikeInteractable.Kind.FUEL, Vector3(11.2, 0.55, -8.2), Vector3(0.65, 1.1, 0.65), Color("a84231"))
		]
	})
	var definitions: Array[LocalStrikeMapDefinition] = []
	for entry in data:
		definitions.append(MapDefinition.create(entry))
	return definitions

func _with_borders(inner: Array) -> Array:
	var walls := [
		_w(0, -16.35, 33, 0.7), _w(0, 16.35, 33, 0.7),
		_w(-16.35, 0, 0.7, 33), _w(16.35, 0, 0.7, 33)
	]
	walls.append_array(inner)
	return walls

func _w(x: float, z: float, width: float, depth: float, kind := "wall") -> Dictionary:
	return {"rect": Rect2(Vector2(x, z), Vector2(width, depth)), "kind": kind}

func _site(name: String, x: float, z: float, radius: float, color: Color) -> Dictionary:
	return {"name": name, "position": Vector3(x, 0.04, z), "radius": radius, "color": color}

func _prop(x: float, z: float, width: float, depth: float, color: Color) -> Dictionary:
	return {"rect": Rect2(Vector2(x, z), Vector2(width, depth)), "color": color}

func _interactive(id: String, kind: int, position: Vector3, size := Vector3.ZERO, color := Color.WHITE, rotation_y := 0.0) -> Dictionary:
	var data := {"id": id, "kind": kind, "position": position, "rotation_y": rotation_y}
	if size != Vector3.ZERO:
		data["size"] = size
	if color != Color.WHITE:
		data["color"] = color
	return data

func _physics_prop(id: String, position: Vector3, size: Vector3, surface := "wood", mass := 22.0, health := 60.0) -> Dictionary:
	var colors := {"wood": Color("806044"), "metal": Color("42515b"), "glass": Color("8ecbd4")}
	return {"id": id, "position": position, "size": size, "surface": surface, "mass": mass, "health": health, "color": colors.get(surface, Color("6b7075"))}

func _reflection(position: Vector3, size: Vector3, intensity := 0.72) -> Dictionary:
	return {"position": position, "size": size, "intensity": intensity}

func _palette(background: Color, floor: Color, wall: Color, crate: Color, ambient: Color) -> Dictionary:
	return {"background": background, "floor": floor, "wall": wall, "crate": crate, "ambient": ambient, "sun": Color("ffe0b0")}
