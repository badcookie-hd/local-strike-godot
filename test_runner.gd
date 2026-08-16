extends SceneTree

const Ballistics = preload("res://scripts/ballistics_manager.gd")
const SurfaceProfile = preload("res://scripts/surface_profile.gd")
const PhysicsProp = preload("res://scripts/physics_prop.gd")
const SandboxCatalog = preload("res://scripts/sandbox_catalog.gd")
const SandboxItemDefinition = preload("res://scripts/sandbox_item_definition.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")

var _failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
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
	_check(game.levels.size() == 6, "five competitive maps and the Foundry sandbox are available")
	_check(game.current_level is LocalStrikeMapDefinition, "maps use typed definitions")
	_check(game.current_level.sites.size() == 2, "map keeps two bomb sites")
	_check(game.interactables.size() == 4, "map spawns door, glass, lamp and fuel")
	_check(game.physics_props.size() >= 2, "map spawns gameplay physics props")
	_check((game.player.collision_mask & 2) != 0 and (game.enemies[0].collision_mask & 1) != 0, "players and bots physically collide instead of passing through each other")
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
	_check(game.current_level.map_name == "ABANDONED FOUNDRY", "sandbox always opens the dedicated Foundry scene")
	_check(game.enemies.is_empty() and game.allies.is_empty(), "sandbox starts as an empty build space")
	_check(game.player.invulnerable and game.player.unlimited_ammo, "sandbox enables god mode and unlimited ammunition")
	game._update_hud()
	_check(game.sandbox_browser._tool_button.visible and not game.sandbox_browser.is_open(), "sandbox exposes the persistent spawn-browser button")
	game.sandbox_browser._tool_button.pressed.emit()
	await process_frame
	_check(game.sandbox_browser.is_open(), "visible toolbox button opens the spawn browser")
	_check(game.player.combat_input_blocked and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "open browser releases the mouse and blocks combat input")
	var ui_click := InputEventMouseButton.new()
	ui_click.button_index = MOUSE_BUTTON_LEFT
	ui_click.pressed = true
	game.player._input(ui_click)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "player input does not recapture clicks intended for browser controls")
	await _click_control(game.sandbox_browser._category_buttons["Melee"])
	_check(game.sandbox_browser._selected_category == "Melee" and game.sandbox_browser._selected.category == "Melee", "category buttons select their own bound browser category")
	var close_key := InputEventKey.new()
	close_key.keycode = KEY_B
	close_key.pressed = true
	game.sandbox_browser._input(close_key)
	_check(not game.sandbox_browser.is_open(), "B closes the browser even while the search field owns focus")
	var open_key := InputEventKey.new()
	open_key.physical_keycode = KEY_B
	open_key.pressed = true
	game.sandbox_browser._input(open_key)
	_check(game.sandbox_browser.is_open() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "B opens the browser from the captured FPS view")
	_check(game.sandbox_browser.get_weapon_card_count() == 22, "spawn browser exposes all 22 equipment items")
	_check(game.sandbox_browser.get_item_count() == 39, "spawn browser catalog includes bots, equipment, props and world tools")
	_check(game.sandbox_browser._card_buttons.has(&"weapon_fire_axe"), "specific melee card is rendered")
	await _click_control(game.sandbox_browser._card_buttons[&"weapon_fire_axe"])
	_check(game.sandbox_browser._selected.id == &"weapon_fire_axe", "clicking a weapon card selects that exact weapon")
	_check(game.sandbox_browser._primary_action.is_visible_in_tree() and game.sandbox_browser._secondary_action.is_visible_in_tree() and game.sandbox_browser._primary_action.get_global_rect().end.y <= root.size.y and game.sandbox_browser._secondary_action.get_global_rect().end.y <= root.size.y, "browser action buttons remain visible at 1280x720")
	_check(not game.hud._score_label.visible and not game.hud._money_label.visible, "sandbox HUD removes duplicate score and money labels")
	await _click_control(game.sandbox_browser._secondary_action)
	_check(game.player.weapon_key == "fire_axe" and game.player.melee_key == "fire_axe", "browser equips the exact selected melee weapon")
	_check(game.sandbox_browser._quickbar_panel.visible and game.sandbox_browser._overlay.is_ancestor_of(game.sandbox_browser._quickbar_panel), "recent items stay clickable inside the open browser")
	_check(game.sandbox_browser._quickbar_panel.get_global_rect().end.y <= root.size.y, "recent item bar remains inside the 720p viewport")
	_check(game.sandbox_browser._primary_action.get_global_rect().end.y <= root.size.y and game.sandbox_browser._secondary_action.get_global_rect().end.y <= root.size.y, "recent items never push browser actions below the 720p viewport")
	game.sandbox_browser._select_category("Weapons")
	game.sandbox_browser._search.text = "ranger"
	game.sandbox_browser._rebuild_cards()
	await process_frame
	_check(game.sandbox_browser._grid.get_child_count() == 1, "browser search filters equipment cards")
	game.sandbox_browser._search.text = ""
	game.sandbox_browser._rebuild_cards()
	game.player.grant_weapon("flash")
	game.player.shoot()
	_check(game.player.grenade_key == "flash" and game.player.ammo == 1, "sandbox grenades are reusable")
	var base_prop_count: int = game.physics_props.size()
	game.sandbox_browser.select_item_by_id(&"prop_wood_crate")
	game.sandbox_spawn_controller.begin_placement(game.sandbox_browser._selected, {"count": 1})
	_check(game.sandbox_spawn_controller._validate_placement(Vector3(-5, 0.575, 5)), "physics props validate on clear Foundry floor")
	game.sandbox_spawn_controller.cancel_placement(false)
	game.sandbox_browser.select_item_by_id(&"weapon_ranger")
	game.sandbox_spawn_controller.begin_placement(game.sandbox_browser._selected, {"count": 1})
	_check(game.sandbox_spawn_controller._validate_placement(Vector3(-5, 0.28, 5)), "dropped weapons validate on clear Foundry floor")
	game.sandbox_spawn_controller.cancel_placement(false)
	game.sandbox_browser.select_item_by_id(&"bot_heavy")
	game.sandbox_browser._team_select.select(0)
	_select_option_metadata(game.sandbox_browser._weapon_select, "fire_axe")
	game.sandbox_browser._behavior_select.select(1)
	game.sandbox_browser._bot_count.value = 2
	await _click_control(game.sandbox_browser._primary_action)
	await physics_frame
	game.sandbox_spawn_controller.update_preview()
	_check(game.sandbox_spawn_controller.is_placing(), "browser action enters world placement mode")
	_check(game.sandbox_spawn_controller.placement_valid, "world placement preview is valid on the Foundry floor")
	await _world_click()
	await physics_frame
	game.sandbox_browser.open_browser()
	game.sandbox_browser.select_item_by_id(&"bot_scout")
	game.sandbox_browser._team_select.select(1)
	_select_option_metadata(game.sandbox_browser._weapon_select, "baseball_bat")
	game.sandbox_browser._behavior_select.select(2)
	game.sandbox_browser._bot_count.value = 1
	game.sandbox_browser._activate_primary()
	_confirm_placement(game.sandbox_spawn_controller, Transform3D(Basis.IDENTITY, Vector3(-4, 0.05, 7)))
	_check(game.enemies.size() == 2 and game.allies.size() == 1, "browser placement spawns the requested bot count and teams")
	var configured_enemy = game.enemies.back() if game.enemies.size() >= 2 else null
	var second_configured_enemy = game.enemies[game.enemies.size() - 2] if game.enemies.size() >= 2 else null
	var configured_ally = game.allies.back() if not game.allies.is_empty() else null
	_check(configured_enemy != null and configured_enemy.enemy_kind == "heavy" and configured_enemy.weapon_key == "fire_axe" and configured_enemy.sandbox_behavior == "guard", "enemy bot preserves exact type weapon and guard behavior")
	_check(configured_enemy != null and second_configured_enemy != null and configured_enemy.global_position.distance_to(second_configured_enemy.global_position) > 0.3, "multi-spawn uses separated collision-safe positions")
	_check(configured_ally != null and configured_ally.enemy_kind == "scout" and configured_ally.weapon_key == "baseball_bat" and configured_ally.sandbox_behavior == "passive", "ally bot preserves exact type weapon and passive behavior")
	game.sandbox_browser.open_browser()
	game.sandbox_browser.select_item_by_id(&"prop_wood_crate")
	game.sandbox_browser._amount_spin.value = 1
	game.sandbox_browser._activate_primary()
	_confirm_placement(game.sandbox_spawn_controller, Transform3D(Basis.IDENTITY, Vector3(8, 0.575, 5)))
	_check(game.physics_props.size() == base_prop_count + 1, "browser placement creates a registered physics prop")
	game.sandbox_browser.open_browser()
	game.sandbox_browser.select_item_by_id(&"weapon_machete")
	game.sandbox_browser._amount_spin.value = 2
	game.sandbox_browser._activate_primary()
	_confirm_placement(game.sandbox_spawn_controller, Transform3D(Basis.IDENTITY, Vector3(2, 0.28, 5)))
	_check(game.dropped_weapons.size() == 2, "browser placement drops the requested exact weapon count")
	for drop in game.dropped_weapons.values():
		_check(drop.weapon_key == "machete" and drop.get_child_count() >= 2, "dropped weapon keeps its exact key and procedural worldmodel")
	game._on_sandbox_action("equip_weapon", {"weapon": "fire_axe"})
	_check(game.player.weapon_key == "fire_axe" and game.player.melee_key == "fire_axe", "sandbox keeps the exact equipped melee weapon")
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
	game.player.grant_weapon("sentinel")
	var replaced_ammo: int = game.player.ammo
	var pickup = game._spawn_dropped_weapon("ranger", 17, 44, game.player.global_position + Vector3(0.6, 0.3, 0), Vector3.ZERO)
	pickup.freeze = true
	game._handle_authoritative_weapon_action(game.player.global_position, game.player.weapon_key, game.player.ammo, game.player.reserve_ammo, 1)
	_check(game.player.weapon_key == "ranger", "picking up a nearby world weapon equips it")
	_check(game.dropped_weapons.size() == 1 and game.dropped_weapons.values()[0].weapon_key == "sentinel" and game.dropped_weapons.values()[0].ammo == replaced_ammo, "weapon pickup drops the replaced gun with its magazine state")
	game._on_sandbox_action("clear_weapons", {})
	game.player.grant_weapon("sidearm")
	var sidearm_drop: Dictionary = game.player.remove_current_weapon_for_drop()
	_check(sidearm_drop.get("key", "") == "sidearm" and not game.player.inventory.has("sidearm"), "dropping the sidearm does not duplicate a fresh replacement")
	game.player.grant_weapon("sidearm")
	game.player.equip_weapon("knife", false)
	_check(game.player.remove_current_weapon_for_drop().is_empty(), "the default knife cannot be duplicated by dropping it")
	game._spawn_sandbox_prop_at("barrel", Transform3D(Basis.IDENTITY, Vector3(-5, 0.56, 5)), 1)
	game._spawn_sandbox_prop_at("wood", Transform3D(Basis.IDENTITY, Vector3(-2.5, 0.575, 5)), 1)
	await physics_frame
	var explosive_barrel: LocalStrikePhysicsProp
	var blast_crate: LocalStrikePhysicsProp
	for prop in game.physics_props.values():
		if not str(prop.prop_id).begins_with("sandbox_prop_"):
			continue
		if prop.visual_variant == "barrel":
			explosive_barrel = prop
		elif prop.visual_variant == "wood":
			blast_crate = prop
	var crate_health_before := blast_crate.health if blast_crate != null else 0.0
	if explosive_barrel != null:
		explosive_barrel.take_damage(999.0)
	await physics_frame
	_check(explosive_barrel != null and explosive_barrel.destroyed_state, "sandbox fuel barrel enters its destroyed state")
	_check(blast_crate != null and blast_crate.health < crate_health_before, "fuel barrel explosion damages and pushes nearby props")
	game._on_sandbox_action("clear_props", {})
	for batch in range(4):
		game._spawn_sandbox_bot_at({"team": "enemy", "kind": "scout", "weapon": "knife", "behavior": "passive", "count": 10}, Transform3D(Basis.IDENTITY, Vector3(-12 + batch * 7, 0.05, -8 + batch * 2)))
	_check(game.enemies.size() == 40, "sandbox accepts the complete 40-bot limit")
	_check(game._spawn_sandbox_bot_at({"team": "enemy", "count": 1}, Transform3D(Basis.IDENTITY, Vector3.ZERO)) == 0 and game.enemies.size() == 40, "sandbox rejects bot spawns beyond the limit")
	game._on_sandbox_action("clear_npcs", {})
	_check(game.enemies.is_empty(), "forty-bot world can be cleared without stuck actors")
	for batch in range(8):
		game._spawn_sandbox_prop_at("wood", Transform3D(Basis.IDENTITY, Vector3(-14 + batch * 3.5, 0.575, 0)), 8)
	_check(game._sandbox_prop_count() == 64, "sandbox reserves all 64 slots for user-spawned physics props")
	_check(game._spawn_sandbox_prop_at("metal", Transform3D(Basis.IDENTITY, Vector3.ZERO), 1) == 0, "sandbox rejects physics props beyond the limit")
	game._on_sandbox_action("clear_props", {})
	_check(game.physics_props.size() == base_prop_count, "prop cleanup preserves only the built Foundry props")
	for batch in range(4):
		game._spawn_sandbox_weapon_at({"weapon": "sidearm", "count": 10}, Transform3D(Basis.IDENTITY, Vector3(-8 + batch * 4, 0.28, 6)))
	_check(game.dropped_weapons.size() == 32, "sandbox truncates dropped weapons at the 32-item limit")
	_check(game._spawn_sandbox_weapon_at({"weapon": "ranger", "count": 1}, Transform3D.IDENTITY) == 0, "sandbox rejects weapon drops beyond the limit")
	game._on_sandbox_action("clear_weapons", {})
	game._on_sandbox_action("reset", {})
	await physics_frame
	_check(game.enemies.is_empty() and game.allies.is_empty() and game.physics_props.size() == base_prop_count, "sandbox reset restores the empty Foundry world")
	_check(is_equal_approx(Engine.time_scale, 1.0), "sandbox reset restores normal time")
	print("TEST_STAGE map_matrix")
	for map_index in range(5):
		game._start_solo(LocalStrikeMatchConfig.Mode.DEATHMATCH, map_index, LocalStrikeMatchConfig.Difficulty.RECRUIT)
		await physics_frame
		await physics_frame
		_check(game.level_index == map_index and game.current_level.map_name == game.levels[map_index].map_name, "map %d loads the requested definition" % (map_index + 1))
		_check(game.enemies.size() == 5 and game.allies.size() == 4, "map %d supports a complete 5v5 lineup" % (map_index + 1))
		_check(game.current_level.sites.size() == 2 and game.interactables.size() == 4 and game.physics_props.size() >= 2, "map %d builds objectives, interactions and physics props" % (map_index + 1))
		_check(game.player.global_position.y > -0.2 and game.player.global_position.distance_to(game.current_level.player_spawn) < 1.5, "map %d keeps the player at a valid spawn" % (map_index + 1))
	game._start_solo(LocalStrikeMatchConfig.Mode.DEFUSAL, 0, LocalStrikeMatchConfig.Difficulty.RECRUIT)
	await physics_frame
	_check(game.player.melee_key == "knife" and not game.player.inventory.has("fire_axe"), "defusal removes extended sandbox melee inventory")
	game.queue_free()
	for _frame in range(8):
		await process_frame
	print("TEST_STAGE complete")
	if _failed:
		quit(1)
	else:
		print("GAMEPLAY_TESTS_OK")
		quit(0)

func _confirm_placement(controller: LocalStrikeSandboxSpawnController, placement: Transform3D) -> void:
	controller.set_process(false)
	controller._preview_root.global_transform = placement
	controller.placement_valid = true
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	controller._unhandled_input(click)

func _click_control(control: Control) -> void:
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

func _world_click() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT
	click.pressed = true
	click.position = root.size * 0.5
	click.global_position = click.position
	Input.parse_input_event(click)
	await process_frame
	click = click.duplicate()
	click.pressed = false
	click.button_mask = 0
	Input.parse_input_event(click)
	await process_frame

func _select_option_metadata(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return
	_check(false, "option metadata %s is available" % value)

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
	var sandbox_items := SandboxCatalog.build()
	var sandbox_weapon_ids: Dictionary = {}
	var bot_scene_count := 0
	var firearm_scene_count := 0
	for definition in sandbox_items:
		if definition.kind == SandboxItemDefinition.Kind.WEAPON:
			sandbox_weapon_ids[definition.weapon_key] = true
			if not definition.scene_path.is_empty():
				firearm_scene_count += 1
				_check(FileAccess.file_exists(definition.scene_path), "%s preview scene is local" % definition.weapon_key)
		elif definition.kind == SandboxItemDefinition.Kind.BOT:
			bot_scene_count += 1
			_check(FileAccess.file_exists(definition.scene_path), "%s bot preview scene is local" % definition.bot_kind)
			_check(bool(definition.placement_rules.get("requires_navigation", false)), "%s bot placement requires navigation" % definition.bot_kind)
	_check(sandbox_weapon_ids.size() == 22, "sandbox catalog contains 22 unique equipment cards")
	_check(firearm_scene_count == 16, "twelve firearms and four melee items use distinct local CC0 model scenes")
	_check(bot_scene_count == 3, "three rigged local character variants are available")
	_check(MaterialLibrary.MATERIALS.size() == 12, "Foundry material library contains twelve PBR sets")
	for material_name in MaterialLibrary.MATERIALS:
		var material_data: Dictionary = MaterialLibrary.MATERIALS[material_name]
		_check(FileAccess.file_exists(str(material_data.diff)) and FileAccess.file_exists(str(material_data.normal)) and FileAccess.file_exists(str(material_data.arm)), "%s has local albedo, normal and ARM textures" % material_name)

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
