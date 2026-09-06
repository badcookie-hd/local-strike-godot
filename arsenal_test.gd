extends SceneTree

const Rules = preload("res://scripts/arsenal_rules.gd")
const Catalog = preload("res://scripts/weapon_catalog.gd")
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
	else:
		print("PASS ", message)

func freeze_bots(game: Node) -> void:
	for bot in game.allies + game.enemies:
		bot.set_physics_process(false)

func _run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await physics_frame
	game.set_physics_process(false)
	game.hud._mode_select.select(LocalStrikeMatchConfig.Mode.ARSENAL)
	game.hud._on_mode_selected(LocalStrikeMatchConfig.Mode.ARSENAL)
	check(game.hud._host_button.disabled, "Arsenal menu explains local-only mode")
	game.hud._emit_solo()
	freeze_bots(game)
	game.player.set_physics_process(false)
	check(game.game_mode == LocalStrikeMatchConfig.Mode.ARSENAL and game.phase == game.Phase.LIVE, "menu starts live Arsenal match")
	check(game.enemies.size() == 5 and game.allies.size() == 4, "Arsenal starts with two full teams")
	check(game.player.weapon_key == "kestrel" and game.player.inventory.size() == 1, "stage one replaces previous inventory")
	for bot in game.allies + game.enemies:
		check(bot.weapon_key == "kestrel", "both teams start with Kestrel")
	game._buy_weapon("heavy_sniper")
	game.player.equip_weapon("knife")
	game._handle_authoritative_weapon_action(game.player.global_position, "kestrel", 20, 80, 1)
	check(game.player.weapon_key == "kestrel" and game.dropped_weapons.is_empty(), "buy, slot switching and drops cannot bypass progression")
	for kill in range(3):
		game.enemies[0].take_damage(999.0)
		await process_frame
	check(game.attack_score == 3 and game.defense_score == 0, "three eliminations count for the correct team")
	check(game.player.weapon_key == "smg", "third team elimination advances player weapon")
	check(game.allies[0].weapon_key == "smg" and game.enemies[0].weapon_key == "kestrel", "only the scoring team advances")
	game._update_deathmatch(3.1)
	freeze_bots(game)
	check(game.enemies.size() == 5 and game.pending_respawns.is_empty(), "fallen bots respawn once after three seconds")
	for kill in range(3):
		game.allies[0].take_damage(999.0)
		await process_frame
	check(game.defense_score == 3 and game.enemies[0].weapon_key == "smg", "enemy team advances independently")
	game.player.apply_damage(999.0)
	check(game.player_dead and game.defense_score == 4, "player death awards opposing team and starts respawn")
	game._update_deathmatch(3.1)
	freeze_bots(game)
	check(not game.player_dead and game.player.health == 100.0 and game.player.weapon_key == "smg", "player respawns with current stage and full health")
	game._update_hud()
	check(game.hud._charge_label.text.contains("STAGE 2/8") and not game.hud._buy_panel.visible, "HUD shows stage progress and hides shop")
	for score in range(4, Rules.SCORE_LIMIT + 1):
		if game.enemies.is_empty():
			game._update_deathmatch(3.1)
			freeze_bots(game)
		game.enemies[0].take_damage(999.0)
		await process_frame
		if score < Rules.SCORE_LIMIT:
			check(game.player.weapon_key == Rules.weapon_for_score(score), "weapon stage at score %d" % score)
	check(game.match_over and game.attack_score == 24 and not game.player.enabled, "final knife stage ends match at 24")
	check(game.player.weapon_key == "knife", "final stage uses knife")
	game._on_player_died()
	check(game.defense_score == 4, "match result cannot change after victory")
	game._update_deathmatch(3.1)
	check(not game.started and game.hud._menu_overlay.visible, "completed match returns to menu")
	game._restart_match()
	freeze_bots(game)
	check(not game.match_over and game.attack_score == 0 and game.deathmatch_timer == 480.0, "restart resets score, result and timer")
	check(game.pending_respawns.is_empty() and game.player.weapon_key == "kestrel", "restart clears pending spawns and restores first stage")
	game.deathmatch_timer = 0.01
	game._update_deathmatch(0.02)
	check(game.match_over and game.hud._toast_label.text.begins_with("DRAW"), "time limit resolves a tied match")
	game._start_solo(LocalStrikeMatchConfig.Mode.DEATHMATCH, 0, LocalStrikeMatchConfig.Difficulty.RECRUIT)
	freeze_bots(game)
	game.player.set_physics_process(false)
	await physics_frame
	game.player.reset_view(0.0, 1.2)
	for key in ["kestrel", "doublebarrel", "longbow"]:
		game.player.grant_weapon(key)
		var spec := Catalog.get_weapon(key)
		game.player._equip_timer = 0.0
		game.player._fire_cooldown = 0.0
		game.player.shoot()
		check(game.player.ammo == spec.magazine - 1, "%s shot consumes one round" % key)
		check(is_instance_valid(game.player._imported_weapon_model) and game.player._imported_weapon_model.get_meta("weapon_key") == key, "%s uses its own first-person model" % key)
		game.player.begin_reload()
		game.player._finish_reload()
		check(game.player.ammo == spec.magazine and game.player.reserve_ammo == spec.reserve - 1, "%s reload transfers reserve ammo" % key)
		var drop: Dictionary = game.player.remove_current_weapon_for_drop()
		check(drop.key == key and drop.ammo == spec.magazine, "%s drops with correct ammo" % key)
		game.player.pickup_weapon(key, int(drop.ammo), int(drop.reserve), 0.0)
		check(game.player.weapon_key == key and game.player.reserve_ammo == spec.reserve - 1, "%s pickup preserves ammo" % key)
		check(game.hud._buy_buttons.has(key) and game.hud._buy_buttons[key].price == spec.price, "%s shop uses actual catalog price" % key)
	game.player.grant_weapon("doublebarrel")
	game.player.ammo = 1
	game.player._equip_timer = 0.0
	game.player._fire_cooldown = 0.0
	game.player.shoot()
	check(game.player.ammo == 0 and game.player.is_reloading(), "double barrel automatically reloads after last shell")
	game._start_solo(LocalStrikeMatchConfig.Mode.DEFUSAL, 0, LocalStrikeMatchConfig.Difficulty.RECRUIT)
	freeze_bots(game)
	check(game.player.inventory.size() == 2 and game.player.primary_key.is_empty() and game.player.weapon_key == "sidearm", "switching mode clears free weapons")
	game.player.money = 2200
	game._buy_weapon("longbow")
	check(game.player.weapon_key == "longbow" and game.player.money == 0, "Longbow purchase charges displayed price")
	game.pending_respawns.append({"time": 1.0, "team": 1, "kind": "scout"})
	game._start_solo(LocalStrikeMatchConfig.Mode.ARSENAL, 4, LocalStrikeMatchConfig.Difficulty.RECRUIT)
	freeze_bots(game)
	check(game.pending_respawns.is_empty() and game.level_index == 4, "mode switch clears stale respawns and accepts another map")
	game.queue_free()
	root.get_node("AudioManager").stop_all(true)
	for frame in range(8):
		await process_frame
	print("ARSENAL_TESTS_FAILED" if failed else "ARSENAL_TESTS_OK")
	quit(1 if failed else 0)
