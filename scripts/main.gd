extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const HUDScript = preload("res://scripts/hud.gd")
const WeaponCatalog = preload("res://scripts/weapon_catalog.gd")
const GrenadeScript = preload("res://scripts/grenade.gd")
const SmokeScript = preload("res://scripts/smoke_cloud.gd")
const NetworkAvatarScript = preload("res://scripts/network_avatar.gd")
const ConcreteDiffuse = preload("res://assets/textures/concrete_floor_worn_001_diff_1k.jpg")
const ConcreteNormal = preload("res://assets/textures/concrete_floor_worn_001_normal_1k.jpg")
const MetalDiffuse = preload("res://assets/textures/metal_plate_diff_1k.jpg")
const MetalNormal = preload("res://assets/textures/metal_plate_normal_1k.jpg")

enum Phase { BUY, LIVE, ENDED }

var levels: Array[Dictionary] = []
var level_index := 0
var current_level: Dictionary
var sites: Array[Dictionary] = []
var enemies: Array[LocalStrikeEnemy] = []
var allies: Array[LocalStrikeEnemy] = []
var remote_avatars: Dictionary = {}
var pending_respawns: Array[Dictionary] = []

var player: LocalStrikePlayer
var hud: LocalStrikeHUD
var level_root: Node3D
var effect_root: Node3D
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
var current_quality := 0
var player_team := 0
var match_over := false

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

	player = PlayerScript.new()
	player.name = "Player"
	player.enabled = false
	player.shot_fired.connect(_on_shot_fired)
	player.hit_confirmed.connect(_on_hit_confirmed)
	player.player_died.connect(_on_player_died)
	player.grenade_thrown.connect(_on_grenade_thrown)
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
	add_child(hud)
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
	if event.is_action_pressed("toggle_buy"):
		show_buy = not show_buy
	if phase == Phase.BUY and event.is_action_pressed("map_next"):
		level_index = (level_index + 1) % levels.size()
		_load_level(level_index)
		_spawn_teams()
		hud.show_toast("Map: %s" % current_level.name)
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
	var config := LocalStrikeMatchConfig.new()
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
	game_mode = config.mode
	level_index = clampi(config.map_index, 0, levels.size() - 1)
	bot_difficulty = config.bot_difficulty
	attack_score = 0
	defense_score = 0
	round_no = 0
	deathmatch_timer = 480.0
	player.money = 800
	player.authoritative_damage = not _is_network_client()
	player_dead = false
	match_over = false
	started = true
	hud.set_deployed(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_reset_round(false)
	hud.show_toast("%s - %s" % ["DEFUSAL" if game_mode == LocalStrikeMatchConfig.Mode.DEFUSAL else "TEAM DEATHMATCH", current_level.name], 3.2)

func _restart_match() -> void:
	attack_score = 0
	defense_score = 0
	round_no = 0
	player.money = 800
	player.equip_weapon("sidearm", false)
	_set_paused(false)
	started = true
	player.enabled = true
	hud.set_deployed(true)
	_reset_round(false)
	hud.show_toast("Match restarted")

func _set_paused(value: bool) -> void:
	paused = value
	get_tree().paused = value
	hud.set_paused(value)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func _reset_round(show_message: bool) -> void:
	round_no += 1
	player_team = 0 if round_no <= 3 or game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH else 1
	phase = Phase.LIVE if game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH else Phase.BUY
	show_buy = true
	phase_timer = 105.0
	freeze_timer = 12.0
	round_end_timer = 0.0
	plant_progress = 0.0
	defuse_progress = 0.0
	bomb_timer = 0.0
	charge_planted = false
	player_dead = false
	_load_level(level_index)
	var spawn_position: Vector3 = current_level.player_spawn if player_team == 0 else current_level.bot_spawns[0]
	player.reset_for_round(spawn_position)
	player.enabled = started
	player.set_view_active(true)
	spectator_camera.current = false
	_spawn_teams()
	if show_message:
		hud.show_toast("Round %d: %s" % [round_no, current_level.name])

func _load_level(index: int) -> void:
	for child in level_root.get_children():
		child.queue_free()
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	for ally in allies:
		if is_instance_valid(ally):
			ally.queue_free()
	allies.clear()
	remote_avatars.clear()
	sites.clear()
	material_cache.clear()

	current_level = levels[index]
	_update_environment(current_level.palette)
	_create_floor(current_level.palette)
	for wall_data in current_level.walls:
		_create_wall(wall_data, current_level.palette)
	for prop_data in current_level.props:
		_create_prop(prop_data)
	for site_data in current_level.sites:
		_create_site(site_data)
	_create_map_beacons(current_level.palette)
	_create_map_identity_props()
	player.reset_for_round(current_level.player_spawn)

func _spawn_teams() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	for ally in allies:
		if is_instance_valid(ally):
			ally.queue_free()
	allies.clear()
	if _is_network_client():
		return
	var human_players := 1 + multiplayer.get_peers().size() if NetworkManager.peer != null else 1
	var ally_count := maxi(0, 5 - human_players)
	var ally_spawns: Array[Vector3] = []
	for offset in [Vector3(-1.2, 0, 0.5), Vector3(1.2, 0, 0.5), Vector3(-2.1, 0, 1.3), Vector3(2.1, 0, 1.3)]:
		ally_spawns.append(current_level.player_spawn + offset)
	for i in range(ally_count):
		var own_spawn: Vector3 = ally_spawns[i % ally_spawns.size()] if player_team == 0 else current_level.bot_spawns[(i + 1) % current_level.bot_spawns.size()]
		allies.append(_spawn_bot(player_team, i, own_spawn))
	var defender_count: int = mini(5, current_level.bot_spawns.size())
	for i in range(defender_count):
		var opposing_spawn: Vector3 = current_level.bot_spawns[i] if player_team == 0 else ally_spawns[i % ally_spawns.size()]
		enemies.append(_spawn_bot(1 - player_team, i, opposing_spawn))
	_refresh_bot_opponents()

func _spawn_bot(team: int, index: int, position: Vector3) -> LocalStrikeEnemy:
	var bot: LocalStrikeEnemy = EnemyScript.new()
	bot.team = team
	bot.bot_difficulty = bot_difficulty
	bot.enemy_kind = "heavy" if index == 4 else ("scout" if index % 3 == 1 else "assault")
	var typed_patrols: Array[Vector3] = []
	for patrol in current_level.patrols:
		typed_patrols.append(patrol)
	bot.patrol_points = typed_patrols
	bot.died.connect(_on_enemy_died)
	bot.shot_fired.connect(_on_enemy_shot)
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
	started = false
	player.enabled = false
	hud.set_deployed(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_toast("MATCH COMPLETE  %d : %d" % [attack_score, defense_score], 5.0)

func _buy_weapon(key: String) -> void:
	var message := player.grant_weapon(key) if game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH else player.try_buy(key, phase == Phase.BUY)
	hud.show_toast(message)

func _on_enemy_died(enemy: LocalStrikeEnemy, position: Vector3, enemy_kind: String) -> void:
	var was_opponent := enemies.has(enemy)
	enemies.erase(enemy)
	allies.erase(enemy)
	if was_opponent:
		var reward := 450 if enemy_kind == "heavy" else (350 if enemy_kind == "scout" else 300)
		player.add_reward(reward)
	_create_burst(position + Vector3.UP, Color("f3b447"), 12)
	hud.add_kill("OPERATOR" if was_opponent else "DEFENDER", "DEFENDER" if was_opponent else "ALLY", player.get_weapon_name())
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

func _on_player_died() -> void:
	player_dead = true
	player.enabled = false
	if game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH:
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

func _on_shot_fired(origin: Vector3, end: Vector3, hit: bool) -> void:
	AudioManager.play_shot(origin, WeaponCatalog.get_weapon(player.weapon_key).category)
	for bot in enemies:
		if is_instance_valid(bot): bot.hear_noise(origin, 1.0)
	if _is_network_client():
		_request_network_shot.rpc_id(1, origin, end, player.weapon_key)
		return
	_create_tracer(origin, end, Color("ffd08a"))
	if hit:
		_create_burst(end, Color("ef5b5b"), 4)

func _on_enemy_shot(origin: Vector3, end: Vector3, hit: bool) -> void:
	AudioManager.play_shot(origin, "rifle")
	_create_tracer(origin, end, Color("ef5b5b"))

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

func _respawn_player() -> void:
	player_dead = false
	var spawn_position: Vector3 = current_level.player_spawn if player_team == 0 else current_level.bot_spawns[0]
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
	_create_burst(position + Vector3.UP * 0.5, Color("ff9a3d"), 34)
	AudioManager.play_explosion(position)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, position)
	query.collision_mask = 3
	var damaged_targets: Dictionary = {}
	for result in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var target: Object = result.collider
		if target == null or damaged_targets.has(target.get_instance_id()):
			continue
		damaged_targets[target.get_instance_id()] = true
		if target.has_method("apply_damage") or target.has_method("take_damage"):
			var distance := position.distance_to(target.global_position)
			var applied_damage := damage * clampf(1.0 - distance / radius, 0.15, 1.0)
			if target.has_method("apply_damage"):
				target.apply_damage(applied_damage, "torso")
			else:
				target.take_damage(applied_damage, "torso")

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
	if multiplayer.is_server() and started:
		_spawn_teams()

func _on_network_peer_left(peer_id: int) -> void:
	GameSession.remove_player(peer_id)
	if remote_avatars.has(peer_id):
		remote_avatars[peer_id].queue_free()
		remote_avatars.erase(peer_id)
	_refresh_bot_opponents()
	_sync_roster.rpc(GameSession.roster)

@rpc("any_peer", "call_remote", "reliable")
func _register_client(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	GameSession.register_player(sender, player_name, 0)
	_receive_match_config.rpc_id(sender, game_mode, level_index, bot_difficulty)
	_sync_roster.rpc(GameSession.roster)
	_spawn_teams()

@rpc("authority", "call_remote", "reliable")
func _receive_match_config(mode: int, map_index: int, difficulty: int) -> void:
	var config := LocalStrikeMatchConfig.new()
	config.mode = mode
	config.map_index = map_index
	config.bot_difficulty = difficulty
	GameSession.configure(config)
	_start_configured_match(config)
	player.authoritative_damage = false

@rpc("authority", "call_remote", "reliable")
func _sync_roster(next_roster: Dictionary) -> void:
	GameSession.roster = next_roster.duplicate(true)
	GameSession.roster_changed.emit(GameSession.roster)

func _update_network_state(delta: float) -> void:
	if NetworkManager.peer == null:
		return
	network_sync_timer -= delta
	if network_sync_timer > 0.0:
		return
	network_sync_timer = 0.05
	if multiplayer.is_server():
		_receive_player_snapshot.rpc(1, player.global_position, player.rotation.y, player.health, player.get_weapon_name())
	else:
		_submit_player_snapshot.rpc_id(1, player.global_position, player.rotation.y, player.get_weapon_name())

@rpc("any_peer", "call_remote", "unreliable", 1)
func _submit_player_snapshot(position: Vector3, yaw: float, weapon: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var avatar := _get_or_create_avatar(sender, 0)
	avatar.apply_snapshot(position, yaw, avatar.health, weapon)
	_receive_player_snapshot.rpc(sender, position, yaw, avatar.health, weapon)

@rpc("authority", "call_remote", "unreliable", 1)
func _receive_player_snapshot(peer_id: int, position: Vector3, yaw: float, health: float, weapon: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var team: int = int(GameSession.roster.get(peer_id, {}).get("team", 0))
	var avatar := _get_or_create_avatar(peer_id, team)
	avatar.apply_snapshot(position, yaw, health, weapon)

func _get_or_create_avatar(peer_id: int, team: int) -> LocalStrikeNetworkAvatar:
	if remote_avatars.has(peer_id) and is_instance_valid(remote_avatars[peer_id]):
		return remote_avatars[peer_id]
	var avatar: LocalStrikeNetworkAvatar = NetworkAvatarScript.new()
	avatar.configure(peer_id, team)
	avatar.damaged.connect(_on_network_avatar_damaged)
	level_root.add_child(avatar)
	avatar.global_position = current_level.player_spawn
	remote_avatars[peer_id] = avatar
	_refresh_bot_opponents()
	return avatar

func _on_network_avatar_damaged(peer_id: int, amount: float, hit_zone: String) -> void:
	if multiplayer.is_server():
		_receive_network_damage.rpc_id(peer_id, amount, hit_zone)

@rpc("authority", "call_remote", "reliable")
func _receive_network_damage(amount: float, hit_zone: String) -> void:
	player.apply_damage(amount, hit_zone)

@rpc("any_peer", "call_remote", "reliable")
func _request_network_shot(origin: Vector3, requested_end: Vector3, weapon_key: String) -> void:
	if not multiplayer.is_server():
		return
	var spec := WeaponCatalog.get_weapon(weapon_key)
	var direction := (requested_end - origin).normalized()
	var end := origin + direction * minf(spec.range, origin.distance_to(requested_end))
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = 5
	query.collide_with_areas = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var hit_position: Vector3 = result.position if not result.is_empty() else end
	if not result.is_empty():
		var collider: Object = result.collider
		var target: Object = collider.get_parent() if collider is Area3D else collider
		if target != null and target.has_method("take_damage"):
			var zone := str(collider.get_meta("hit_zone", "torso"))
			var applied_damage := spec.damage * (spec.head_multiplier if zone == "head" else (spec.limb_multiplier if zone == "limb" else 1.0))
			target.take_damage(applied_damage, zone)
	_network_shot_effect.rpc(origin, hit_position, not result.is_empty())
	_network_shot_effect(origin, hit_position, not result.is_empty())

@rpc("authority", "call_remote", "unreliable", 2)
func _network_shot_effect(origin: Vector3, end: Vector3, hit: bool) -> void:
	_create_tracer(origin, end, Color("ffd08a"))
	if hit:
		_create_burst(end, Color("ef5b5b"), 4)

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
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
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

func _apply_quality(index: int) -> void:
	current_quality = clampi(index, 0, 2)
	var viewport := get_viewport()
	match current_quality:
		0:
			viewport.msaa_3d = Viewport.MSAA_4X
			viewport.scaling_3d_scale = 1.0
			viewport.positional_shadow_atlas_size = 4096
			sun.shadow_enabled = true
			world_environment.environment.ssao_enabled = true
			world_environment.environment.glow_enabled = true
			world_environment.environment.fog_enabled = true
		1:
			viewport.msaa_3d = Viewport.MSAA_2X
			viewport.scaling_3d_scale = 0.9
			viewport.positional_shadow_atlas_size = 2048
			sun.shadow_enabled = true
			world_environment.environment.ssao_enabled = true
			world_environment.environment.glow_enabled = false
			world_environment.environment.fog_enabled = true
		_:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.scaling_3d_scale = 0.78
			viewport.positional_shadow_atlas_size = 1024
			sun.shadow_enabled = false
			world_environment.environment.ssao_enabled = false
			world_environment.environment.glow_enabled = false
			world_environment.environment.fog_enabled = false
	hud.show_toast("Graphics quality: %s" % ["HIGH", "MEDIUM", "LOW"][current_quality])

func _create_floor(palette: Dictionary) -> void:
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	floor.collision_layer = 1
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
			for position in [Vector3(-14.1, 0.45, 8.2), Vector3(-13.2, 0.45, 8.5), Vector3(13.6, 0.45, -9.2)]:
				_create_barrel(position, Color("d89b3c"))
		1:
			_create_train_car(Vector3(-11.0, 1.15, 1.5), Color("6d3f31"))
			_create_train_car(Vector3(10.8, 1.15, -2.2), Color("415968"))
			for z in [-13.0, -7.0, -1.0, 5.0, 11.0]:
				_add_rail_sleeper(z)
		2:
			_create_lab_core(Vector3.ZERO)
			for position in [Vector3(-11.8, 0.65, -5.0), Vector3(-11.8, 0.65, 5.0), Vector3(11.8, 0.65, -5.0), Vector3(11.8, 0.65, 5.0)]:
				_create_solar_panel(position)

func _create_identity_box(position: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
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
	var distance := origin.distance_to(end)
	if distance <= 0.05:
		return
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.018, distance)
	tracer.mesh = mesh
	var material := _plain_material(color, 0.1, 0.0)
	material.emission_enabled = true
	material.emission = color
	tracer.material_override = material
	effect_root.add_child(tracer)
	tracer.look_at_from_position((origin + end) / 2.0, end, Vector3.UP)
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "scale", Vector3(0.2, 0.2, 1.0), 0.065)
	tween.tween_callback(tracer.queue_free)

func _create_burst(position: Vector3, color: Color, count: int) -> void:
	for i in range(count):
		var particle := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = randf_range(0.025, 0.055)
		mesh.height = mesh.radius * 2.0
		particle.mesh = mesh
		particle.position = position
		var material := _plain_material(color, 0.2, 0.0)
		material.emission_enabled = true
		material.emission = color * 0.7
		particle.material_override = material
		effect_root.add_child(particle)
		var target := position + Vector3(randf_range(-1.2, 1.2), randf_range(0.2, 1.6), randf_range(-1.2, 1.2))
		var tween := particle.create_tween()
		tween.tween_property(particle, "position", target, randf_range(0.22, 0.48))
		tween.parallel().tween_property(particle, "scale", Vector3.ZERO, 0.48)
		tween.tween_callback(particle.queue_free)

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
	if hud == null or player == null or current_level.is_empty():
		return
	var phase_text := "DEATHMATCH" if game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH else ("BUY" if phase == Phase.BUY else ("ROUND END" if phase == Phase.ENDED else ("PLANTED" if charge_planted else "LIVE")))
	var charge_text := "FREE LOADOUT" if game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH else ("DEFEND" if player_team == 1 else "CARRIED")
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
	hud.update_state({
		"map_index": level_index,
		"map_count": levels.size(),
		"map_name": current_level.name,
		"phase": phase_text,
		"time": _format_time(bomb_timer if charge_planted else phase_timer),
		"attack_score": attack_score,
		"defense_score": defense_score,
		"money": player.money,
		"health": player.health,
		"armor": player.armor,
		"weapon": weapon_spec.display_name,
		"ammo": "RELOAD" if player.is_reloading() else "%d / %d" % [player.ammo, player.reserve_ammo],
		"charge": charge_text,
		"stamina": player.stamina,
		"buy_visible": show_buy and started and (phase == Phase.BUY or game_mode == LocalStrikeMatchConfig.Mode.DEATHMATCH),
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
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mouse)

func _add_key_action(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)

func _create_levels() -> Array[Dictionary]:
	return [
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
			"props": [_prop(-13, -12, 4.2, 0.4, Color("f3b447")), _prop(12, 10.8, 3.5, 0.4, Color("56d8c5"))]
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
			"props": [_prop(-10.8, -2.2, 0.36, 23, Color("d88842")), _prop(10.8, 2.2, 0.36, 23, Color("d88842"))]
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
			"props": [_prop(0, 0, 7, 0.35, Color("9777ff")), _prop(0, 0, 0.35, 7, Color("56d8c5"))]
		}
	]

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

func _palette(background: Color, floor: Color, wall: Color, crate: Color, ambient: Color) -> Dictionary:
	return {"background": background, "floor": floor, "wall": wall, "crate": crate, "ambient": ambient, "sun": Color("ffe0b0")}
