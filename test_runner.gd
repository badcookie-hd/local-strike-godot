extends SceneTree

const Ballistics = preload("res://scripts/ballistics_manager.gd")
const SurfaceProfile = preload("res://scripts/surface_profile.gd")
const PhysicsProp = preload("res://scripts/physics_prop.gd")

var _failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("TEST_STAGE weapon_data")
	_test_weapon_data()
	_test_ballistics_data()
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
	_check(game.levels.size() == 5, "five map definitions are available")
	_check(game.current_level is LocalStrikeMapDefinition, "maps use typed definitions")
	_check(game.current_level.sites.size() == 2, "map keeps two bomb sites")
	_check(game.interactables.size() == 4, "map spawns door, glass, lamp and fuel")
	_check(game.physics_props.size() >= 2, "map spawns gameplay physics props")
	game.player.grant_weapon("sentinel")
	var first_mode: String = game.player.fire_mode
	game.player.cycle_fire_mode()
	_check(game.player.fire_mode != first_mode, "player can switch supported fire mode")
	var dropped: Dictionary = game.player.remove_current_weapon_for_drop()
	_check(dropped.key == "sentinel" and dropped.ammo > 0, "weapon drop preserves magazine state")
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
	print("TEST_STAGE sandbox_start")
	game._start_solo(LocalStrikeMatchConfig.Mode.SANDBOX, 2, LocalStrikeMatchConfig.Difficulty.RECRUIT)
	await physics_frame
	_check(game.phase == game.Phase.LIVE, "sandbox starts without a buy phase")
	_check(game.enemies.size() == 3 and game.allies.is_empty(), "sandbox starts with three hostile actors")
	_check(game.player.invulnerable and game.player.unlimited_ammo, "sandbox enables god mode and unlimited ammunition")
	game.show_buy = true
	game._update_hud()
	_check(game.hud._sandbox_panel.visible and game.hud._buy_buttons["ranger"].button.text.contains("FREE"), "sandbox toolbox and free loadout are visible")
	_check(game.hud._sandbox_team_select != null and game.hud._sandbox_weapon_select.item_count == 22, "sandbox toolbox exposes configurable bot and weapon selectors")
	game.show_buy = false
	game.player.grant_weapon("flash")
	game.player.shoot()
	_check(game.player.grenade_key == "flash" and game.player.ammo == 1, "sandbox grenades are reusable")
	var base_prop_count: int = game.physics_props.size()
	game._on_sandbox_action("spawn_bot", {"team": "enemy", "kind": "heavy", "weapon": "fire_axe", "behavior": "guard", "count": 2})
	game._on_sandbox_action("spawn_bot", {"team": "ally", "kind": "scout", "weapon": "baseball_bat", "behavior": "passive", "count": 1})
	_check(game.enemies.size() == 5 and game.allies.size() == 1, "sandbox spawns the requested bot count and teams")
	var configured_enemy = game.enemies.back()
	var second_configured_enemy = game.enemies[game.enemies.size() - 2]
	var configured_ally = game.allies.back()
	_check(configured_enemy.enemy_kind == "heavy" and configured_enemy.weapon_key == "fire_axe" and configured_enemy.sandbox_behavior == "guard", "enemy bot preserves exact type weapon and guard behavior")
	_check(configured_enemy.global_position.distance_to(second_configured_enemy.global_position) > 0.3, "multi-spawn uses separated collision-safe positions")
	_check(configured_ally.enemy_kind == "scout" and configured_ally.weapon_key == "baseball_bat" and configured_ally.sandbox_behavior == "passive", "ally bot preserves exact type weapon and passive behavior")
	game._on_sandbox_action("spawn_wave", {})
	_check(game.enemies.size() == 11 and game.allies.size() == 3, "sandbox brawl wave creates opposing melee groups")
	game._on_sandbox_action("spawn_wood", {})
	_check(game.physics_props.size() == base_prop_count + 1, "sandbox creates a registered physics prop")
	game._on_sandbox_action("spawn_weapon", {"weapon": "machete", "count": 2})
	_check(game.dropped_weapons.size() == 2, "sandbox drops the requested exact weapon count")
	for drop in game.dropped_weapons.values():
		_check(drop.weapon_key == "machete" and drop.get_child_count() >= 2, "dropped weapon keeps its exact key and procedural worldmodel")
	game._on_sandbox_action("equip_weapon", {"weapon": "fire_axe"})
	_check(game.player.weapon_key == "fire_axe" and game.player.melee_key == "fire_axe", "sandbox equips an exact melee weapon")
	configured_ally.global_position = game.player.global_position - game.player.global_transform.basis.z * 1.35
	configured_ally.sandbox_behavior = "passive"
	await physics_frame
	var target_health: float = configured_ally.health
	var melee_ammo: int = game.player.ammo
	game.player._fire_cooldown = 0.0
	game.player._equip_timer = 0.0
	game.player.melee_attack(false)
	_check(configured_ally.health < target_health, "spatial melee arc damages a target in front of the player")
	_check(game.player.ammo == melee_ammo, "melee attacks never consume ammunition")
	game.player.confirm_melee_hit(false, 0.7)
	var melee_drop: Dictionary = game.player.remove_current_weapon_for_drop()
	_check(melee_drop.key == "fire_axe" and float(melee_drop.bloodiness) > 0.0 and game.player.melee_key == "knife", "melee drops preserve blood state and restore the default knife")
	var sandbox_health: float = game.player.health
	game._on_sandbox_action("explosion", {})
	_check(is_equal_approx(game.player.health, sandbox_health), "sandbox god mode protects against force blasts")
	game._on_sandbox_action("god_mode", {"enabled": false})
	_check(not game.player.invulnerable, "sandbox god mode can be disabled")
	game._on_sandbox_action("slow_motion", {"enabled": true})
	_check(is_equal_approx(Engine.time_scale, 0.32), "sandbox slow motion changes simulation speed")
	game._on_sandbox_action("slow_motion", {"enabled": false})
	game.effects.spawn_blood_hit(game.player.global_position, Vector3.UP, Vector3.FORWARD, 1.8, true)
	_check(game.effects.get_pool_counts().blood > 0 and game.effects.get_pool_counts().pools > 0, "sandbox melee blood creates splatters and a pool")
	for index in range(26):
		var persistent_body := Node3D.new()
		persistent_body.add_to_group("sandbox_ragdoll")
		game.effect_root.add_child(persistent_body)
		game._track_sandbox_ragdoll(persistent_body)
	_check(game.sandbox_ragdolls.size() == 24, "sandbox ragdoll pool keeps at most 24 persistent bodies")
	var stained_drop = game.dropped_weapons.values()[0]
	stained_drop.bloodiness = 0.8
	game._on_sandbox_action("clear_blood", {})
	_check(game.effects.get_pool_counts().blood == 0 and game.effects.get_pool_counts().pools == 0 and game.sandbox_ragdolls.is_empty(), "sandbox cleanup clears blood pools and persistent bodies")
	_check(is_zero_approx(stained_drop.bloodiness), "sandbox cleanup removes blood from dropped weapons")
	game._on_sandbox_action("clear", {})
	_check(game.enemies.is_empty() and game.allies.is_empty(), "sandbox clear removes spawned actors")
	_check(game.physics_props.size() == base_prop_count and game.dropped_weapons.is_empty(), "sandbox clear preserves map props and removes spawned items")
	game._on_sandbox_action("reset", {})
	await physics_frame
	_check(game.enemies.size() == 3 and game.physics_props.size() == base_prop_count, "sandbox reset restores the initial world")
	_check(is_equal_approx(Engine.time_scale, 1.0), "sandbox reset restores normal time")
	game._start_solo(LocalStrikeMatchConfig.Mode.DEFUSAL, 0, LocalStrikeMatchConfig.Difficulty.RECRUIT)
	await physics_frame
	_check(game.player.melee_key == "knife" and not game.player.inventory.has("fire_axe"), "defusal removes extended sandbox melee inventory")
	game.queue_free()
	await process_frame
	await process_frame
	print("TEST_STAGE complete")
	if _failed:
		quit(1)
	else:
		print("GAMEPLAY_TESTS_OK")
		quit(0)

func _test_weapon_data() -> void:
	var catalog := LocalStrikeWeaponCatalog.all()
	_check(catalog.size() == 22, "complete 22 item weapon catalog")
	for key in catalog:
		var weapon: LocalStrikeWeaponDefinition = catalog[key]
		_check(not weapon.display_name.is_empty(), "%s has display name" % key)
		_check(weapon.magazine > 0, "%s has valid magazine" % key)
		_check(weapon.range > 0.0, "%s has valid range" % key)
		_check(not weapon.recoil_pattern.is_empty() or weapon.slot in [LocalStrikeWeaponDefinition.Slot.GRENADE, LocalStrikeWeaponDefinition.Slot.MELEE], "%s has recoil data" % key)
	var melee_keys := LocalStrikeWeaponCatalog.melee_keys()
	_check(melee_keys.size() == 6, "six distinct melee weapons are available")
	for key in melee_keys:
		var melee := LocalStrikeWeaponCatalog.get_weapon(key)
		_check(melee.melee_reach > 1.5 and melee.melee_arc_degrees > 45.0, "%s has a spatial melee profile" % key)
		_check(melee.melee_heavy_damage > melee.melee_light_damage and melee.melee_heavy_recovery > melee.melee_light_recovery, "%s heavy attack is stronger and slower" % key)
		_check(melee.melee_impulse > 0.0 and melee.blood_multiplier > 0.0, "%s has impulse and blood tuning" % key)

func _test_ballistics_data() -> void:
	var rifle := LocalStrikeWeaponCatalog.get_weapon("sentinel")
	var close_damage: float = Ballistics.damage_at_distance(rifle, rifle.falloff_start)
	var far_damage: float = Ballistics.damage_at_distance(rifle, rifle.falloff_end)
	_check(far_damage < close_damage and far_damage >= rifle.damage * rifle.minimum_damage_multiplier, "distance falloff is bounded")
	var spread_a: Vector2 = Ballistics.deterministic_spread(rifle, 12, 0, rifle.spread)
	var spread_b: Vector2 = Ballistics.deterministic_spread(rifle, 12, 0, rifle.spread)
	_check(spread_a == spread_b, "shot spread is deterministic")
	_check(rifle.fire_modes.has("semi") and rifle.fire_modes.has("auto"), "sentinel supports validated fire selection")
	var metal: Dictionary = SurfaceProfile.get_profile("metal")
	var ice: Dictionary = SurfaceProfile.get_profile("ice")
	_check(float(metal.penetration_resistance) > float(SurfaceProfile.get_profile("wood").penetration_resistance), "metal resists penetration more than wood")
	_check(float(ice.friction) < 0.25, "ice uses low movement friction")

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
	var prop = PhysicsProp.new()
	prop.configure({"id": "test-crate", "surface": "wood", "health": 25.0, "mass": 10.0})
	holder.add_child(prop)
	await physics_frame
	prop.apply_gameplay_impulse(Vector3(4, 1, 0))
	_check(prop.revision == 1 and prop.linear_velocity.length() > 0.0, "physics prop accepts gameplay impulse")
	prop.take_damage(25.0)
	_check(prop.destroyed_state, "destructible physics prop reaches destroyed state")
	prop.reset_state()
	_check(not prop.destroyed_state and is_equal_approx(prop.health, 25.0), "physics prop resets between rounds")
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
	for index in range(38):
		manager.spawn_blood_hit(Vector3(index * 0.02, 0, 1), Vector3.UP, Vector3.FORWARD, 1.2, index % 4 == 0)
	var counts := manager.get_pool_counts()
	_check(counts.bullet <= 18, "low quality bullet decal pool is capped")
	_check(counts.blood <= 24, "low quality blood splatter pool is capped")
	_check(counts.pools <= 6, "low quality blood pool is capped")
	manager.clear_blood()
	_check(manager.get_pool_counts().blood == 0 and manager.get_pool_counts().pools == 0, "blood pools can be cleared explicitly")
	manager.queue_free()
	await process_frame

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		push_error("TEST FAILED: %s" % label)
