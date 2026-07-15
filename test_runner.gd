extends SceneTree

var _failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("TEST_STAGE weapon_data")
	_test_weapon_data()
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await physics_frame
	print("TEST_STAGE defusal_start")
	game._start_solo(LocalStrikeMatchConfig.Mode.DEFUSAL, 0, LocalStrikeMatchConfig.Difficulty.VETERAN)
	await physics_frame
	_check(game.enemies.size() == 5, "defusal spawns five opponents")
	_check(game.allies.size() == 4, "solo defusal spawns four allies")
	_check(game.phase == game.Phase.BUY, "defusal starts in buy phase")
	game.player.grant_weapon("smoke")
	game.player.shoot()
	print("TEST_STAGE movement")
	_check(game.effect_root.get_child_count() > 0, "smoke grenade spawns")
	var start_y: float = game.player.global_position.y
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	for i in range(10):
		await physics_frame
	_check(game.player.global_position.y > start_y + 0.05, "player jump physics")
	var victim = game.enemies[0]
	_check(victim.take_damage(999.0, "head"), "headshot eliminates bot")
	await process_frame
	print("TEST_STAGE deathmatch_start")
	game._start_solo(LocalStrikeMatchConfig.Mode.DEATHMATCH, 1, LocalStrikeMatchConfig.Difficulty.RECRUIT)
	await physics_frame
	_check(game.phase == game.Phase.LIVE, "deathmatch starts live")
	_check(game.enemies.size() == 5 and game.allies.size() == 4, "deathmatch uses 5v5 teams")
	print("TEST_STAGE complete")
	if _failed:
		quit(1)
	else:
		print("GAMEPLAY_TESTS_OK")
		quit(0)

func _test_weapon_data() -> void:
	var catalog := LocalStrikeWeaponCatalog.all()
	_check(catalog.size() == 9, "complete weapon catalog")
	for key in catalog:
		var weapon: LocalStrikeWeaponDefinition = catalog[key]
		_check(not weapon.display_name.is_empty(), "%s has display name" % key)
		_check(weapon.magazine > 0, "%s has valid magazine" % key)
		_check(weapon.range > 0.0, "%s has valid range" % key)

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		push_error("TEST FAILED: %s" % label)
