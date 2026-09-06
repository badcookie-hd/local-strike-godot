extends SceneTree

const Catalog = preload("res://scripts/weapon_catalog.gd")
const Models = preload("res://scripts/weapon_model.gd")
var failed := false
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)
	else:
		print("PASS ", message)

func _click(control: Control) -> void:
	await process_frame
	var center := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		click.pressed = pressed
		click.position = center
		click.global_position = center
		Input.parse_input_event(click)
		await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await physics_frame
	game._start_solo(LocalStrikeMatchConfig.Mode.ARSENAL, 0, LocalStrikeMatchConfig.Difficulty.RECRUIT)
	await physics_frame
	var pause_key := InputEventAction.new()
	pause_key.action = "pause"
	pause_key.pressed = true
	game._unhandled_input(pause_key)
	check(paused and game.paused and game.hud._pause_panel.visible, "Escape opens pause menu and pauses tree")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "pause releases mouse for menu buttons")
	var bot_position: Vector3 = game.enemies[0].global_position
	var player_position: Vector3 = game.player.global_position
	Input.action_press("move_forward")
	for frame in range(12):
		await physics_frame
	Input.action_release("move_forward")
	check(game.enemies[0].global_position.is_equal_approx(bot_position) and game.player.global_position.is_equal_approx(player_position), "bots and player remain frozen while paused")
	check(game.hud._main_menu_button.get_global_rect().end.y < 720, "all pause actions fit 720p")
	await _click(game.hud._resume_button)
	check(not paused and not game.paused, "resume button restores game")
	# The headless display cannot retain captured mouse mode after GUI events.
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "resume button recaptures mouse in native game window")
	game._set_paused(true)
	await _click(game.hud._restart_button)
	check(game.started and not paused and game.attack_score == 0, "restart button starts a fresh match")
	game._set_paused(true)
	await _click(game.hud._main_menu_button)
	check(not game.started and not paused and game.hud._menu_overlay.visible, "main menu button leaves paused match")
	check(game.enemies.is_empty() and game.allies.is_empty() and game.pending_respawns.is_empty(), "return to menu clears actors and respawns")
	check(not game.player.enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "menu leaves player inactive and pointer visible")
	game.hud._mode_select.select(LocalStrikeMatchConfig.Mode.SANDBOX)
	game.hud._on_mode_selected(LocalStrikeMatchConfig.Mode.SANDBOX)
	game.hud._emit_solo()
	await physics_frame
	check(game.started and game.game_mode == LocalStrikeMatchConfig.Mode.SANDBOX, "new mode can start after returning to menu")
	game.sandbox_browser.open_browser()
	game._set_paused(true)
	check(not game.sandbox_browser.is_open() and not game.sandbox_browser._active, "pause closes sandbox overlay and blocks toolbox shortcuts")
	await _click(game.hud._resume_button)
	check(game.sandbox_browser._active and not game.sandbox_browser.is_open(), "resume restores sandbox tools without overlay")
	game._set_paused(true)
	await _click(game.hud._main_menu_button)
	check(not game.sandbox_browser._active and not game.sandbox_spawn_controller.is_placing(), "sandbox tools and placement are disabled in menu")
	game._start_host(LocalStrikeMatchConfig.Mode.DEATHMATCH, 0, LocalStrikeMatchConfig.Difficulty.RECRUIT)
	check(root.get_node("NetworkManager").peer != null, "LAN host is active before leaving")
	game._set_paused(true)
	await _click(game.hud._main_menu_button)
	check(root.get_node("NetworkManager").peer == null and root.get_node("GameSession").roster.is_empty(), "return to menu closes LAN host and roster")
	game._start_solo(LocalStrikeMatchConfig.Mode.DEATHMATCH, 0, LocalStrikeMatchConfig.Difficulty.RECRUIT)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot in game.allies + game.enemies:
		bot.set_physics_process(false)
	for key in Catalog.primary_keys() + Catalog.secondary_keys():
		var model := Models.create(key)
		root.add_child(model)
		var state := {"has_bounds": false, "bounds": AABB()}
		Models._collect_bounds(model, model, Transform3D.IDENTITY, state)
		var size: Vector3 = state.bounds.size
		check(size.z > size.x * 1.8, "%s barrel points along forward axis" % key)
		check(Vector3(model.get_meta("muzzle")).z < -0.2, "%s muzzle is ahead of grip" % key)
		game.player.grant_weapon(key)
		check(game.player._imported_weapon_model.position.is_zero_approx(), "%s viewmodel sits at hand grip" % key)
		check(game.player._muzzle.position.is_equal_approx(Vector3(model.get_meta("muzzle")) * 0.82), "%s first-person flash follows barrel" % key)
		model.queue_free()
	var pose_errors := {"right": 0.0, "left": 0.0, "samples": 0}
	var bot = game.enemies[0]
	bot._hold_modifier.modification_processed.connect(func():
		if bot.weapon_key == "knife": return
		var skeleton: Skeleton3D = bot._skeleton
		var right := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Wrist.R"))
		var left := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Wrist.L"))
		pose_errors.right = maxf(pose_errors.right, right.origin.distance_to(bot._hold_modifier.right_target_world))
		pose_errors.left = maxf(pose_errors.left, left.origin.distance_to(bot._hold_modifier.left_target_world))
		pose_errors.samples += 1
	)
	for key in ["ranger", "kestrel", "knife", "longbow"]:
		bot.equip_arsenal_weapon(key)
		for animation in ["Idle_Gun_Pointing", "Walk", "Run", "Sword_Slash" if key == "knife" else "Idle_Gun_Shoot"]:
			bot._animation_player.play(animation, 0.0)
			for frame in range(3):
				await process_frame
			check(bot._weapon_mount.get_parent() == bot._weapon_attachment and bot._weapon_attachment.bone_name == "Wrist.R", "%s stays attached during %s" % [key, animation])
			check(bot._held_weapon.global_position.distance_to(bot._weapon_attachment.global_position) < 0.08, "%s grip stays against animated hand" % key)
			check(bot._muzzle.get_parent() == bot._held_weapon, "%s muzzle follows held model" % key)
	check(pose_errors.samples > 0 and pose_errors.right < 0.035, "right hand IK reaches grip across animations")
	check(pose_errors.left < 0.06, "support hand IK reaches weapon across animations")
	print("POSE_ERRORS ", pose_errors)
	game._return_to_main_menu()
	game.queue_free()
	root.get_node("AudioManager").stop_all(true)
	for frame in range(8):
		await process_frame
	print("MENU_HOLDING_TESTS_FAILED" if failed else "MENU_HOLDING_TESTS_OK", " checks=", checks)
	quit(1 if failed else 0)
