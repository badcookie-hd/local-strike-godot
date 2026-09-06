extends SceneTree

const TEST_PORT := 27908

var _failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var host_root := SubViewport.new()
	host_root.name = "Host"
	host_root.size = Vector2i(1280, 720)
	host_root.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host_root.world_3d = World3D.new()
	root.add_child(host_root)
	var client_root := SubViewport.new()
	client_root.name = "Client"
	client_root.size = Vector2i(1280, 720)
	client_root.render_target_update_mode = SubViewport.UPDATE_DISABLED
	client_root.world_3d = World3D.new()
	root.add_child(client_root)

	var host_peer := ENetMultiplayerPeer.new()
	var client_peer := ENetMultiplayerPeer.new()
	_check(host_peer.create_server(TEST_PORT, 1) == OK, "host ENet peer starts")
	_check(client_peer.create_client("127.0.0.1", TEST_PORT) == OK, "client ENet peer starts")
	var host_api := SceneMultiplayer.new()
	var client_api := SceneMultiplayer.new()
	host_api.multiplayer_peer = host_peer
	client_api.multiplayer_peer = client_peer
	set_multiplayer(host_api, host_root.get_path())
	set_multiplayer(client_api, client_root.get_path())

	var connected := false
	for _frame in range(300):
		await process_frame
		OS.delay_msec(2)
		if host_api.get_peers().size() == 1 and client_api.get_unique_id() != 1:
			connected = true
			break
	_check(connected, "custom host and client connect through ENet")
	if not connected:
		_finish(host_peer, client_peer, host_root, client_root)
		return

	var network_manager = root.get_node("/root/NetworkManager")
	var game_session = root.get_node("/root/GameSession")
	network_manager.peer = host_peer
	var scene: PackedScene = load("res://main.tscn")
	var host_game = scene.instantiate()
	host_root.add_child(host_game)
	var client_game = scene.instantiate()
	client_root.add_child(client_game)
	await physics_frame

	var config := LocalStrikeMatchConfig.new()
	config.mode = LocalStrikeMatchConfig.Mode.DEATHMATCH
	config.map_index = 0
	config.bot_difficulty = LocalStrikeMatchConfig.Difficulty.RECRUIT
	game_session.configure(config)
	game_session.reset_roster()
	game_session.register_player(1, "Host", 0)
	host_game._start_configured_match(config)
	client_game._register_client.rpc_id(1, "Client")

	var synchronized := false
	for _frame in range(600):
		await process_frame
		OS.delay_msec(2)
		if client_game.started and client_game.replicated_bots.size() == 8 and client_game.remote_avatars.has(1) and host_game.remote_avatars.size() == 1:
			synchronized = true
			break

	var replica_count := 0
	for bot in client_game.replicated_bots.values():
		if is_instance_valid(bot) and bot.network_replica:
			replica_count += 1
	var host_bot_count: int = host_game.allies.size() + host_game.enemies.size()
	var client_bot_count: int = client_game.allies.size() + client_game.enemies.size()
	print("LAN_GAMEPLAY_DIAGNOSTIC synchronized=%s host_bots=%d client_bots=%d replicas=%d host_avatars=%d client_avatars=%d" % [synchronized, host_bot_count, client_bot_count, replica_count, host_game.remote_avatars.size(), client_game.remote_avatars.size()])
	_check(synchronized, "client receives authoritative gameplay state")
	_check(host_bot_count == 8, "host refills the two-player match to 5v5")
	_check(client_bot_count == 8 and replica_count == 8, "client creates every bot replica exactly once")
	_check(host_game._serialize_bot_state().size() == 8, "host serializes stable bot identities")
	var client_id := client_api.get_unique_id()
	client_game.player.invulnerable = true
	for bot in host_game.allies + host_game.enemies:
		bot.sandbox_behavior = "passive"
	for _frame in range(300):
		await process_frame
		OS.delay_msec(2)
		if host_game.remote_avatars[client_id].global_position.distance_to(client_game.player.get_aim_origin()) < 2.2:
			break
	client_game.player.grant_weapon("sentinel")
	client_game.player.ammo = 2
	client_game.player.reserve_ammo = 30
	for _frame in range(100):
		await process_frame
		OS.delay_msec(2)
		if host_game.remote_avatars[client_id].weapon_name == LocalStrikeWeaponCatalog.get_weapon("sentinel").display_name:
			break
	host_game.peer_shot_state[client_id] = {"sequence": 0, "time": -10.0, "weapon": "sentinel", "ammo": 2, "reload_ready": -1.0}
	client_game.player.begin_reload()
	for _frame in range(1400):
		await process_frame
		OS.delay_msec(2)
		if not client_game.player.is_reloading():
			break
	for _frame in range(600):
		var ready_time := float(host_game.peer_shot_state.get(client_id, {}).get("reload_ready", INF))
		if Time.get_ticks_msec() / 1000.0 >= ready_time:
			break
		await process_frame
		OS.delay_msec(2)
	client_game.player.shoot()
	for _frame in range(100):
		await process_frame
		OS.delay_msec(2)
		if int(host_game.peer_shot_state.get(client_id, {}).get("ammo", -1)) == LocalStrikeWeaponCatalog.get_weapon("sentinel").magazine - 1:
			break
	var test_origin: Vector3 = client_game.player.get_aim_origin()
	var test_direction: Vector3 = client_game.player.get_aim_direction()
	var test_avatar = host_game.remote_avatars[client_id]
	_check(test_avatar._weapon.get_meta("weapon_key") == "sentinel", "remote avatar displays the actual synchronized weapon")
	_check(test_avatar._visual_actor._weapon_attachment.bone_name == "Wrist.R", "remote avatar weapon follows animated hand")
	_check(test_avatar._visual_actor.collision_layer == 0 and not test_avatar._visual_actor.is_in_group("damageable_actor"), "remote visual does not introduce duplicate damage targets")
	var view_dot := Vector3(test_direction.x, 0.0, test_direction.z).normalized().dot(-test_avatar.global_transform.basis.z)
	print("LAN_RELOAD_DIAGNOSTIC weapon=%s client_ammo=%d unlimited=%s sequence=%d origin=%s avatar=%s target=%s origin_distance=%.3f view_dot=%.3f reloading=%s equip_timer=%.3f fire_timer=%.3f avatar_weapon=%s host_state=%s" % [client_game.player.weapon_key, client_game.player.ammo, client_game.player.unlimited_ammo, client_game.player._shot_sequence, test_origin, test_avatar.global_position, test_avatar.target_position, test_avatar.global_position.distance_to(test_origin), view_dot, client_game.player.is_reloading(), client_game.player._equip_timer, client_game.player._fire_cooldown, test_avatar.weapon_name, host_game.peer_shot_state.get(client_id, {})])
	_check(int(host_game.peer_shot_state.get(client_id, {}).get("ammo", -1)) == LocalStrikeWeaponCatalog.get_weapon("sentinel").magazine - 1, "host accepts the first shot after a validated partial reload")
	if not _failed:
		print("NETWORK_GAMEPLAY_TEST_OK")
	_finish(host_peer, client_peer, host_root, client_root)

func _finish(host_peer: ENetMultiplayerPeer, client_peer: ENetMultiplayerPeer, host_root: Node, client_root: Node) -> void:
	root.get_node("/root/AudioManager").stop_all(true)
	host_peer.close()
	client_peer.close()
	root.get_node("/root/NetworkManager").peer = null
	set_multiplayer(null, host_root.get_path())
	set_multiplayer(null, client_root.get_path())
	for child in host_root.get_children():
		host_root.remove_child(child)
		child.queue_free()
	for child in client_root.get_children():
		client_root.remove_child(child)
		child.queue_free()
	root.remove_child(host_root)
	root.remove_child(client_root)
	host_root.queue_free()
	client_root.queue_free()
	for _frame in range(16):
		await process_frame
	quit(1 if _failed else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("NETWORK_GAMEPLAY_TEST_FAILED: %s" % label)
