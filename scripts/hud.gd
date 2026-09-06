class_name LocalStrikeHUD
extends CanvasLayer

signal solo_requested(mode: int, map_index: int, difficulty: int)
signal host_requested(mode: int, map_index: int, difficulty: int)
signal join_requested(address: String)
signal refresh_servers_requested
signal buy_requested(key: String)
signal quality_changed(index: int)
signal resume_requested
signal restart_requested
signal main_menu_requested
signal sandbox_action_requested(action: String, payload: Dictionary)

const RadarScript = preload("res://scripts/radar.gd")
const WeaponCatalog = preload("res://scripts/weapon_catalog.gd")

var _root: Control
var _map_label: Label
var _phase_label: Label
var _timer_label: Label
var _score_label: Label
var _money_label: Label
var _health_label: Label
var _ammo_label: Label
var _weapon_label: Label
var _charge_label: Label
var _stamina_bar: ProgressBar
var _buy_panel: PanelContainer
var _toast_label: Label
var _toast_timer := 0.0
var _hit_marker: Control
var _hit_timer := 0.0
var _pause_panel: PanelContainer
var _pause_overlay: ColorRect
var _resume_button: Button
var _restart_button: Button
var _main_menu_button: Button
var _menu_overlay: ColorRect
var _mode_select: OptionButton
var _mode_description: Label
var _map_select: OptionButton
var _difficulty_select: OptionButton
var _quality_select: OptionButton
var _server_list: ItemList
var _ip_input: LineEdit
var _server_addresses: Array[String] = []
var _radar: LocalStrikeRadar
var _killfeed: VBoxContainer
var _scoreboard: PanelContainer
var _scoreboard_text: Label
var _spectator_label: Label
var _damage_flash: ColorRect
var _flash_overlay: ColorRect
var _weapon_status_label: Label
var _sandbox_panel: PanelContainer
var _sandbox_count_label: Label
var _sandbox_god_toggle: CheckButton
var _sandbox_slow_toggle: CheckButton
var _sandbox_team_select: OptionButton
var _sandbox_kind_select: OptionButton
var _sandbox_bot_weapon_select: OptionButton
var _sandbox_behavior_select: OptionButton
var _sandbox_bot_count: SpinBox
var _sandbox_weapon_category: OptionButton
var _sandbox_weapon_select: OptionButton
var _sandbox_weapon_count: SpinBox
var _host_button: Button
var _buy_buttons: Dictionary = {}
var _free_loadout_state := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		_toast_label.modulate.a = minf(1.0, _toast_timer * 3.0)
	else:
		_toast_label.visible = false
	if _hit_timer > 0.0:
		_hit_timer -= delta
		_hit_marker.modulate.a = clampf(_hit_timer / 0.16, 0.0, 1.0)
	else:
		_hit_marker.visible = false
	_damage_flash.modulate.a = move_toward(_damage_flash.modulate.a, 0.0, delta * 2.8)
	_flash_overlay.modulate.a = move_toward(_flash_overlay.modulate.a, 0.0, delta * 0.55)

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_game_hud()
	_build_buy_menu()
	_build_pause_and_scoreboard()
	_build_main_menu()

func _build_game_hud() -> void:
	var top_band := ColorRect.new()
	top_band.color = Color(0.025, 0.035, 0.045, 0.88)
	top_band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_band.offset_bottom = 72
	top_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top_band)
	_map_label = _anchored_label(Vector2(18, 8), Vector2(300, 58), 17, HORIZONTAL_ALIGNMENT_LEFT)
	_phase_label = _anchored_label(Vector2(-120, 7), Vector2(240, 22), 12, HORIZONTAL_ALIGNMENT_CENTER, 0.5)
	_timer_label = _anchored_label(Vector2(-120, 27), Vector2(240, 40), 27, HORIZONTAL_ALIGNMENT_CENTER, 0.5)
	_score_label = _anchored_label(Vector2(-255, 14), Vector2(120, 48), 23, HORIZONTAL_ALIGNMENT_CENTER, 0.5)
	_money_label = _anchored_label(Vector2(135, 14), Vector2(120, 48), 20, HORIZONTAL_ALIGNMENT_CENTER, 0.5)

	_radar = RadarScript.new()
	_radar.position = Vector2(18, 88)
	_radar.size = Vector2(170, 170)
	_root.add_child(_radar)

	_killfeed = VBoxContainer.new()
	_killfeed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_killfeed.position = Vector2(-340, 86)
	_killfeed.size = Vector2(320, 180)
	_killfeed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_killfeed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_killfeed)

	var bottom_band := ColorRect.new()
	bottom_band.color = Color(0.025, 0.035, 0.045, 0.9)
	bottom_band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_band.offset_top = -90
	bottom_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bottom_band)
	_health_label = _bottom_label(Vector2(22, -78), Vector2(165, 62), 20, HORIZONTAL_ALIGNMENT_LEFT)
	_weapon_label = _bottom_label(Vector2(-190, -78), Vector2(180, 24), 12, HORIZONTAL_ALIGNMENT_RIGHT, 1.0)
	_ammo_label = _bottom_label(Vector2(-230, -54), Vector2(220, 42), 25, HORIZONTAL_ALIGNMENT_RIGHT, 1.0)
	_weapon_status_label = _bottom_label(Vector2(210, -78), Vector2(180, 24), 12, HORIZONTAL_ALIGNMENT_LEFT)
	_charge_label = _bottom_label(Vector2(-110, -78), Vector2(220, 62), 17, HORIZONTAL_ALIGNMENT_CENTER, 0.5)
	_stamina_bar = ProgressBar.new()
	_stamina_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_stamina_bar.offset_left = 210
	_stamina_bar.offset_top = -13
	_stamina_bar.offset_right = -210
	_stamina_bar.offset_bottom = -7
	_stamina_bar.show_percentage = false
	_stamina_bar.max_value = 100
	_stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stamina_bar)

	_build_crosshair()
	_spectator_label = _anchored_label(Vector2(-220, 90), Vector2(440, 34), 16, HORIZONTAL_ALIGNMENT_CENTER, 0.5)
	_spectator_label.visible = false
	_toast_label = _anchored_label(Vector2(-270, 132), Vector2(540, 44), 17, HORIZONTAL_ALIGNMENT_CENTER, 0.5)
	_toast_label.visible = false
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.8, 0.05, 0.04, 0.28)
	_damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash.modulate.a = 0.0
	_root.add_child(_damage_flash)
	_flash_overlay = ColorRect.new()
	_flash_overlay.color = Color.WHITE
	_flash_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.modulate.a = 0.0
	_root.add_child(_flash_overlay)

func _build_crosshair() -> void:
	var crosshair := Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-18, -18)
	crosshair.size = Vector2(36, 36)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(crosshair)
	for rect in [Rect2(17, 3, 2, 9), Rect2(17, 24, 2, 9), Rect2(3, 17, 9, 2), Rect2(24, 17, 9, 2)]:
		var line := ColorRect.new()
		line.color = Color(0.94, 0.96, 0.94, 0.95)
		line.position = rect.position
		line.size = rect.size
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair.add_child(line)
	_hit_marker = Control.new()
	_hit_marker.set_anchors_preset(Control.PRESET_CENTER)
	_hit_marker.position = Vector2(-18, -18)
	_hit_marker.size = Vector2(36, 36)
	_hit_marker.visible = false
	_hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hit_marker)
	for rect in [Rect2(5, 5, 8, 2), Rect2(23, 5, 8, 2), Rect2(5, 29, 8, 2), Rect2(23, 29, 8, 2)]:
		var line := ColorRect.new()
		line.color = Color.WHITE
		line.position = rect.position
		line.size = rect.size
		_hit_marker.add_child(line)

func _build_buy_menu() -> void:
	_buy_panel = PanelContainer.new()
	_buy_panel.anchor_bottom = 1.0
	_buy_panel.offset_left = 18
	_buy_panel.offset_top = 278
	_buy_panel.offset_right = 318
	_buy_panel.offset_bottom = -102
	_root.add_child(_buy_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_buy_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 280
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "EQUIPMENT"
	title.add_theme_font_size_override("font_size", 17)
	title.custom_minimum_size.y = 30
	box.add_child(title)
	for key in LocalStrikeWeaponCatalog.sandbox_weapon_keys():
		var spec := LocalStrikeWeaponCatalog.get_weapon(key)
		var button := Button.new()
		button.text = "%s    $%d" % [spec.display_name, spec.price]
		button.tooltip_text = "%s | MAG %d | RELOAD %.2fs" % [spec.display_name, spec.magazine, spec.reload_time]
		button.custom_minimum_size = Vector2(280, 36)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_emit_buy.bind(key))
		box.add_child(button)
		_buy_buttons[key] = {"button": button, "name": spec.display_name, "price": spec.price}

func _emit_buy(key: String) -> void:
	buy_requested.emit(key)

func _build_sandbox_tools() -> void:
	_sandbox_panel = PanelContainer.new()
	_sandbox_panel.anchor_left = 1.0
	_sandbox_panel.anchor_right = 1.0
	_sandbox_panel.anchor_bottom = 1.0
	_sandbox_panel.offset_left = -350
	_sandbox_panel.offset_top = 278
	_sandbox_panel.offset_right = -18
	_sandbox_panel.offset_bottom = -102
	_root.add_child(_sandbox_panel)
	var margin := MarginContainer.new()
	margin.custom_minimum_size.x = 310
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_sandbox_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var title := Label.new()
	title.text = "SANDBOX TOOLS"
	title.add_theme_font_size_override("font_size", 17)
	box.add_child(title)
	_sandbox_count_label = Label.new()
	_sandbox_count_label.add_theme_font_size_override("font_size", 12)
	_sandbox_count_label.add_theme_color_override("font_color", Color("9fb0b9"))
	box.add_child(_sandbox_count_label)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size.y = 270
	box.add_child(tabs)
	var bots := _sandbox_tab(tabs, "BOTS")
	_sandbox_team_select = _sandbox_option([["ENEMY", "enemy"], ["ALLY", "ally"]])
	_sandbox_kind_select = _sandbox_option([["ASSAULT", "assault"], ["SCOUT", "scout"], ["HEAVY", "heavy"]])
	_sandbox_bot_weapon_select = _sandbox_option(_weapon_entries(WeaponCatalog.bot_weapon_keys()))
	_sandbox_behavior_select = _sandbox_option([["AGGRESSIVE", "aggressive"], ["GUARD", "guard"], ["PASSIVE", "passive"]])
	_sandbox_bot_count = _sandbox_spin(1, 10, 1)
	_add_sandbox_field(bots, "TEAM", _sandbox_team_select)
	_add_sandbox_field(bots, "TYPE", _sandbox_kind_select)
	_add_sandbox_field(bots, "WEAPON", _sandbox_bot_weapon_select)
	_add_sandbox_field(bots, "BEHAVIOR", _sandbox_behavior_select)
	_add_sandbox_field(bots, "COUNT", _sandbox_bot_count)
	var spawn_bot := _sandbox_tool_button("SPAWN AT CURSOR", "")
	spawn_bot.pressed.connect(func(): sandbox_action_requested.emit("spawn_bot", get_sandbox_bot_config()))
	bots.add_child(spawn_bot)
	bots.add_child(_sandbox_tool_button("SPAWN BRAWL WAVE", "spawn_wave"))

	var weapons := _sandbox_tab(tabs, "WEAPONS")
	_sandbox_weapon_category = _sandbox_option([["ALL", "all"], ["MELEE", "melee"], ["FIREARMS", "firearms"], ["GRENADES", "grenades"]])
	_sandbox_weapon_category.item_selected.connect(func(_index: int): _populate_sandbox_weapons())
	_sandbox_weapon_select = OptionButton.new()
	_sandbox_weapon_select.custom_minimum_size.y = 34
	_sandbox_weapon_count = _sandbox_spin(1, 10, 1)
	_add_sandbox_field(weapons, "CATEGORY", _sandbox_weapon_category)
	_add_sandbox_field(weapons, "ITEM", _sandbox_weapon_select)
	_add_sandbox_field(weapons, "COUNT", _sandbox_weapon_count)
	_populate_sandbox_weapons()
	var drop_weapon := _sandbox_tool_button("DROP AT CURSOR", "")
	drop_weapon.pressed.connect(func(): sandbox_action_requested.emit("spawn_weapon", get_sandbox_weapon_config()))
	weapons.add_child(drop_weapon)
	var equip_weapon := _sandbox_tool_button("EQUIP NOW", "")
	equip_weapon.pressed.connect(func():
		var payload := get_sandbox_weapon_config()
		payload["count"] = 1
		sandbox_action_requested.emit("equip_weapon", payload)
	)
	weapons.add_child(equip_weapon)

	var world := _sandbox_tab(tabs, "WORLD")
	world.add_child(_sandbox_tool_row([["WOOD CRATE", "spawn_wood"], ["METAL PROP", "spawn_metal"]]))
	world.add_child(_sandbox_tool_button("FORCE BLAST", "explosion"))
	_sandbox_god_toggle = CheckButton.new()
	_sandbox_god_toggle.text = "GOD MODE"
	_sandbox_god_toggle.toggled.connect(func(value: bool): sandbox_action_requested.emit("god_mode", {"enabled": value}))
	world.add_child(_sandbox_god_toggle)
	_sandbox_slow_toggle = CheckButton.new()
	_sandbox_slow_toggle.text = "SLOW MOTION"
	_sandbox_slow_toggle.toggled.connect(func(value: bool): sandbox_action_requested.emit("slow_motion", {"enabled": value}))
	world.add_child(_sandbox_slow_toggle)
	world.add_child(_sandbox_tool_button("REMOVE AIMED OBJECT", "remove_target"))
	world.add_child(_sandbox_tool_row([["CLEAR NPCS", "clear_npcs"], ["CLEAR WEAPONS", "clear_weapons"]]))
	world.add_child(_sandbox_tool_button("CLEAR BLOOD + BODIES", "clear_blood"))
	world.add_child(_sandbox_tool_button("CLEAR ALL SPAWNS", "clear"))
	world.add_child(_sandbox_tool_button("RESET WORLD", "reset"))
	_sandbox_panel.visible = false

func _sandbox_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 286
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	return content

func _sandbox_option(entries: Array) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.y = 34
	for entry in entries:
		option.add_item(str(entry[0]))
		option.set_item_metadata(option.item_count - 1, str(entry[1]))
	return option

func _sandbox_spin(minimum: float, maximum: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = value
	spin.custom_minimum_size.y = 34
	return spin

func _add_sandbox_field(parent: VBoxContainer, label_text: String, control: Control) -> void:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("9fb0b9"))
	parent.add_child(label)
	parent.add_child(control)

func _weapon_entries(keys: Array) -> Array:
	var entries: Array = []
	for key in keys:
		entries.append([WeaponCatalog.get_weapon(key).display_name, key])
	return entries

func _selected_metadata(option: OptionButton) -> String:
	return str(option.get_item_metadata(option.selected)) if option != null and option.item_count > 0 else ""

func get_sandbox_bot_config(force_team := "") -> Dictionary:
	return {
		"team": force_team if not force_team.is_empty() else _selected_metadata(_sandbox_team_select),
		"kind": _selected_metadata(_sandbox_kind_select),
		"weapon": _selected_metadata(_sandbox_bot_weapon_select),
		"behavior": _selected_metadata(_sandbox_behavior_select),
		"count": clampi(roundi(_sandbox_bot_count.value), 1, 10)
	}

func get_sandbox_weapon_config() -> Dictionary:
	return {"weapon": _selected_metadata(_sandbox_weapon_select), "count": clampi(roundi(_sandbox_weapon_count.value), 1, 10)}

func _populate_sandbox_weapons() -> void:
	if _sandbox_weapon_select == null:
		return
	_sandbox_weapon_select.clear()
	var category := _selected_metadata(_sandbox_weapon_category)
	for key in WeaponCatalog.sandbox_weapon_keys():
		var spec := WeaponCatalog.get_weapon(key)
		var include := category == "all"
		include = include or (category == "melee" and spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE)
		include = include or (category == "firearms" and spec.slot in [LocalStrikeWeaponDefinition.Slot.PRIMARY, LocalStrikeWeaponDefinition.Slot.SECONDARY])
		include = include or (category == "grenades" and spec.slot == LocalStrikeWeaponDefinition.Slot.GRENADE)
		if include:
			_sandbox_weapon_select.add_item(spec.display_name)
			_sandbox_weapon_select.set_item_metadata(_sandbox_weapon_select.item_count - 1, key)

func _sandbox_tool_row(entries: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for entry in entries:
		var button := _sandbox_tool_button(str(entry[0]), str(entry[1]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
	return row

func _sandbox_tool_button(label: String, action: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 36
	if not action.is_empty():
		button.pressed.connect(func(): sandbox_action_requested.emit(action, {}))
	return button

func _build_pause_and_scoreboard() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.color = Color(0.015, 0.025, 0.035, 0.8)
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_pause_overlay)
	_pause_panel = _center_panel(Vector2(430, 326))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_pause_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var title := Label.new()
	title.text = "PAUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	_resume_button = _menu_button("WEITERSPIELEN  [ESC]", func(): resume_requested.emit())
	_restart_button = _menu_button("MATCH NEU STARTEN  [F2]", func(): restart_requested.emit())
	_main_menu_button = _menu_button("ZURÜCK ZUM HAUPTMENÜ", func(): main_menu_requested.emit())
	for button in [_resume_button, _restart_button, _main_menu_button]:
		button.custom_minimum_size.y = 48
		box.add_child(button)
	var hint := Label.new()
	hint.text = "Hauptmenü beendet das laufende Match."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	box.add_child(hint)
	_pause_overlay.visible = false
	_pause_panel.visible = false
	_scoreboard = _center_panel(Vector2(680, 460))
	_scoreboard_text = Label.new()
	_scoreboard_text.text = "SCOREBOARD"
	_scoreboard_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scoreboard_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_scoreboard_text.add_theme_font_size_override("font_size", 17)
	_scoreboard.add_child(_scoreboard_text)
	_scoreboard.visible = false

func _build_main_menu() -> void:
	_menu_overlay = ColorRect.new()
	_menu_overlay.color = Color("0b1218")
	_menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_menu_overlay)
	var menu := PanelContainer.new()
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.position = Vector2(-270, -310)
	menu.size = Vector2(540, 620)
	_menu_overlay.add_child(menu)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	menu.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)
	var title := Label.new()
	title.text = "LOCAL STRIKE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.custom_minimum_size.y = 52
	box.add_child(title)
	var subtitle := Label.new()
	_mode_description = subtitle
	subtitle.text = "Choose a mode and deploy"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("56d8c5"))
	box.add_child(subtitle)
	_mode_select = _option(["DEFUSAL - BEST OF 7", "TEAM DEATHMATCH", "SANDBOX - ABANDONED FOUNDRY", "ARSENAL - TEAM WEAPON RACE"])
	_mode_select.item_selected.connect(_on_mode_selected)
	_map_select = _option(["HARBOR YARD", "TRAIN DEPOT", "SOLAR LAB", "OLD QUARTER", "FROSTLINE STATION", "ABANDONED FOUNDRY"])
	_difficulty_select = _option(["RECRUIT BOTS", "VETERAN BOTS", "ELITE BOTS"])
	_difficulty_select.select(1)
	_quality_select = _option(["QUALITY: HIGH", "QUALITY: MEDIUM", "QUALITY: LOW"])
	_quality_select.item_selected.connect(func(index: int): quality_changed.emit(index))
	for control in [_mode_select, _map_select, _difficulty_select, _quality_select]:
		box.add_child(control)
	_mode_select.select(LocalStrikeMatchConfig.Mode.ARSENAL)
	_map_select.select(0)
	box.add_child(_menu_button("PLAY SOLO", _emit_solo))
	_host_button = _menu_button("HOST LAN - 5v5", _emit_host)
	_host_button.disabled = true
	box.add_child(_host_button)
	_on_mode_selected(_mode_select.selected)
	var server_row := HBoxContainer.new()
	server_row.add_theme_constant_override("separation", 8)
	box.add_child(server_row)
	var refresh := _menu_button("REFRESH LAN", func(): refresh_servers_requested.emit())
	refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_row.add_child(refresh)
	_server_list = ItemList.new()
	_server_list.custom_minimum_size = Vector2(470, 82)
	_server_list.item_activated.connect(_join_server_index)
	box.add_child(_server_list)
	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	box.add_child(ip_row)
	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "Direct IP, e.g. 192.168.1.25"
	_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_row.add_child(_ip_input)
	ip_row.add_child(_menu_button("JOIN", _emit_join))

func _option(items: Array[String]) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(470, 38)
	for item in items:
		option.add_item(item)
	return option

func _menu_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(150, 40)
	button.pressed.connect(callback)
	return button

func _emit_solo() -> void:
	solo_requested.emit(_mode_select.selected, _map_select.selected, _difficulty_select.selected)

func _emit_host() -> void:
	host_requested.emit(_mode_select.selected, _map_select.selected, _difficulty_select.selected)

func _on_mode_selected(index: int) -> void:
	_map_select.set_item_disabled(5, index != LocalStrikeMatchConfig.Mode.SANDBOX)
	_host_button.disabled = index in [LocalStrikeMatchConfig.Mode.SANDBOX, LocalStrikeMatchConfig.Mode.ARSENAL]
	_host_button.tooltip_text = "Local solo with bots" if _host_button.disabled else "Host a game on your local network"
	_mode_description.text = ["Plant or defuse. First team to 4 rounds wins.", "Free loadouts. First to 40 kills, or 8 minutes.", "Build, spawn and experiment in the Foundry.", "8 weapon stages. 3 team kills each. Local 5v5 bots."][index]
	if index == LocalStrikeMatchConfig.Mode.SANDBOX:
		_map_select.select(5)
		_map_select.disabled = true
	elif _map_select.selected == 5:
		_map_select.disabled = false
		_map_select.select(0)
	else:
		_map_select.disabled = false

func _emit_join() -> void:
	if not _ip_input.text.strip_edges().is_empty():
		join_requested.emit(_ip_input.text.strip_edges())

func _join_server_index(index: int) -> void:
	if index >= 0 and index < _server_addresses.size():
		join_requested.emit(_server_addresses[index])

func show_server(server: Dictionary) -> void:
	var address := str(server.get("address", ""))
	if address.is_empty():
		return
	var existing := _server_addresses.find(address)
	var label := "%s   %d/10   %s" % [server.get("name", "LAN Server"), server.get("players", 1), address]
	if existing < 0:
		_server_addresses.append(address)
		_server_list.add_item(label)
	else:
		_server_list.set_item_text(existing, label)

func update_state(data: Dictionary) -> void:
	var sandbox_mode: bool = data.get("sandbox_mode", false)
	_map_label.text = "MAP %d/%d\n%s" % [data.map_index + 1, data.get("map_count", 5), data.map_name]
	_phase_label.text = data.phase
	_timer_label.text = data.time
	_score_label.text = "%d : %d" % [data.attack_score, data.defense_score]
	_money_label.text = data.get("money_text", "$%d" % data.money)
	_score_label.visible = not sandbox_mode
	_money_label.visible = not sandbox_mode
	_health_label.text = "HP %d    ARMOR %d" % [ceili(data.health), ceili(data.armor)]
	_weapon_label.text = data.weapon
	_ammo_label.text = data.ammo
	_weapon_status_label.text = "%s   %s" % [data.get("fire_mode", "SEMI"), "ADS" if data.get("aiming", false) else "HIP"]
	_charge_label.text = data.charge
	_stamina_bar.value = data.stamina
	_buy_panel.visible = data.buy_visible
	var free_loadout: bool = data.get("free_loadout", false)
	if free_loadout != _free_loadout_state:
		_free_loadout_state = free_loadout
		for key in _buy_buttons:
			var entry: Dictionary = _buy_buttons[key]
			entry.button.text = "%s    %s" % [entry.name, "FREE" if free_loadout else "$%d" % int(entry.price)]
	if _sandbox_panel != null:
		_sandbox_panel.visible = false
		_sandbox_count_label.text = "%d NPCS   %d ITEMS   %d BODIES" % [data.get("sandbox_npcs", 0), data.get("sandbox_props", 0), data.get("sandbox_bodies", 0)]
		_sandbox_god_toggle.set_pressed_no_signal(data.get("sandbox_god", false))
		_sandbox_slow_toggle.set_pressed_no_signal(data.get("sandbox_slow", false))
	_spectator_label.visible = data.get("spectating", false)
	_spectator_label.text = "SPECTATING  %s" % data.get("spectator_name", "ALLY")
	_radar.update_radar(data.get("radar", {}))
	_update_scoreboard(data.get("roster", {}))

func _update_scoreboard(roster: Dictionary) -> void:
	var attackers := "ATTACKERS\n"
	var defenders := "DEFENDERS\n"
	for id in roster:
		var entry: Dictionary = roster[id]
		var line := "%-20s   %2d K   %2d D\n" % [entry.get("name", "Operator"), entry.get("kills", 0), entry.get("deaths", 0)]
		if entry.get("team", 0) == 0:
			attackers += line
		else:
			defenders += line
	_scoreboard_text.text = "MATCH SCOREBOARD\n\n%s\n%s" % [attackers, defenders]

func add_kill(killer: String, victim: String, weapon: String) -> void:
	var label := Label.new()
	label.text = "%s   [%s]   %s" % [killer, weapon, victim]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 13)
	_killfeed.add_child(label)
	if _killfeed.get_child_count() > 5:
		_killfeed.get_child(0).queue_free()
	var tween := label.create_tween()
	tween.tween_interval(4.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)

func show_toast(message: String, duration := 2.2) -> void:
	_toast_label.text = message
	_toast_label.visible = true
	_toast_label.modulate.a = 1.0
	_toast_timer = duration

func show_hit(killed: bool) -> void:
	_hit_marker.visible = true
	_hit_marker.modulate = Color("f3b447") if killed else Color.WHITE
	_hit_timer = 0.22 if killed else 0.16

func show_damage() -> void:
	_damage_flash.modulate.a = 1.0

func show_flash(intensity: float) -> void:
	_flash_overlay.modulate.a = maxf(_flash_overlay.modulate.a, clampf(intensity, 0.0, 1.0))

func set_paused(value: bool) -> void:
	_pause_panel.visible = value
	_pause_overlay.visible = value
	if value:
		_scoreboard.visible = false
		_resume_button.grab_focus()

func set_scoreboard(value: bool) -> void:
	_scoreboard.visible = value

func set_deployed(value: bool) -> void:
	_menu_overlay.visible = not value
	if not value:
		set_paused(false)
		_scoreboard.visible = false
		_buy_panel.visible = false

func _anchored_label(position: Vector2, label_size: Vector2, font_size: int, alignment: int, anchor_x := 0.0) -> Label:
	var label := Label.new()
	label.anchor_left = anchor_x
	label.anchor_right = anchor_x
	label.position = position
	label.size = label_size
	_style_label(label, font_size, alignment)
	_root.add_child(label)
	return label

func _bottom_label(position: Vector2, label_size: Vector2, font_size: int, alignment: int, anchor_x := 0.0) -> Label:
	var label := _anchored_label(position, label_size, font_size, alignment, anchor_x)
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	return label

func _style_label(label: Label, font_size: int, alignment: int) -> void:
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f2efe6"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _center_panel(panel_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -panel_size / 2.0
	panel.size = panel_size
	_root.add_child(panel)
	return panel
