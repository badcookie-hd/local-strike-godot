extends SceneTree

var _failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("TEST_STAGE weapon_data")
	_test_weapon_data()
	print("TEST_STAGE interactions")
	await _test_interactables()
	print("TEST_STAGE effect_limits")
	await _test_effect_limits()
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
	_check(game.levels.size() == 3, "three map definitions are available")
	_check(game.current_level is LocalStrikeMapDefinition, "maps use typed definitions")
	_check(game.current_level.sites.size() == 2, "map keeps two bomb sites")
	_check(game.interactables.size() == 4, "map spawns door, glass, lamp and fuel")
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

func _test_interactables() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var door := LocalStrikeInteractable.new()
	door.configure({"id": "test-door", "kind": LocalStrikeInteractable.Kind.DOOR})
	holder.add_child(door)
	var glass := LocalStrikeInteractable.new()
	glass.configure({"id": "test-glass", "kind": LocalStrikeInteractable.Kind.GLASS})
	holder.add_child(glass)
	var lamp := LocalStrikeInteractable.new()
	lamp.configure({"id": "test-lamp", "kind": LocalStrikeInteractable.Kind.LAMP})
	holder.add_child(lamp)
	var fuel := LocalStrikeInteractable.new()
	fuel.configure({"id": "test-fuel", "kind": LocalStrikeInteractable.Kind.FUEL})
	holder.add_child(fuel)
	await physics_frame
	_check(door.interact() and door.opened, "door opens through stable interaction API")
	var open_state := door.serialize_state()
	_check(open_state.revision == 1 and open_state.opened, "door state is revisioned")
	var stale_state := open_state.duplicate(true)
	stale_state.revision = 0
	stale_state.opened = false
	door.apply_state(stale_state)
	_check(door.opened, "stale replicated state is rejected")
	glass.take_damage(34.0)
	_check(not glass.destroyed and is_equal_approx(glass.health, 1.0), "glass uses 35 HP threshold")
	glass.take_damage(1.0)
	_check(glass.destroyed, "glass shatters at threshold")
	glass.reset_state()
	await physics_frame
	_check(not glass.destroyed and is_equal_approx(glass.health, 35.0), "glass resets for a new round")
	lamp.take_damage(20.0)
	_check(lamp.destroyed, "lamp breaks at 20 damage")
	fuel.take_damage(65.0)
	_check(fuel.armed and not fuel.destroyed, "fuel starts 1.2 second warning phase")
	fuel.reset_state()
	holder.queue_free()
	await process_frame

func _test_effect_limits() -> void:
	var manager := LocalStrikeEffectsManager.new()
	root.add_child(manager)
	await process_frame
	manager.set_quality(LocalStrikeQualityManager.Profile.LOW, true)
	for index in range(22):
		manager.spawn_impact(Vector3(index * 0.02, 0, 0), Vector3.UP, "concrete")
	for index in range(11):
		manager.spawn_impact(Vector3(index * 0.02, 0, 1), Vector3.UP, "flesh", true)
	var counts := manager.get_pool_counts()
	_check(counts.bullet <= 18, "low quality bullet decal pool is capped")
	_check(counts.blood <= 8, "low quality blood decal pool is capped")
	manager.queue_free()
	await process_frame

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		push_error("TEST FAILED: %s" % label)
