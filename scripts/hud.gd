class_name LocalStrikeHUD
extends CanvasLayer

signal solo_requested(mode: int, map_index: int, difficulty: int)
signal host_requested(mode: int, map_index: int, difficulty: int)
signal join_requested(address: String)
signal refresh_servers_requested
signal buy_requested(key: String)
signal quality_changed(index: int)

const RadarScript = preload("res://scripts/radar.gd")

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
var _menu_overlay: ColorRect
var _mode_select: OptionButton
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
	for entry in [
		["sidearm", "SIDEARM", 0], ["smg", "COMPACT SMG", 1250], ["ranger", "RANGER RIFLE", 2700],
		["breacher", "BREACHER", 2100], ["marksman", "MARKSMAN", 3300], ["heavy_sniper", "HEAVY SNIPER", 4700],
		["frag", "FRAG", 300], ["smoke", "SMOKE", 300]
	]:
		var button := Button.new()
		button.text = "%s    $%d" % [entry[1], entry[2]]
		button.custom_minimum_size = Vector2(280, 36)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var key: String = entry[0]
		button.pressed.connect(func(): buy_requested.emit(key))
		box.add_child(button)

func _build_pause_and_scoreboard() -> void:
	_pause_panel = _center_panel(Vector2(420, 180))
	var pause_label := Label.new()
	pause_label.text = "PAUSED\n\nESC / P  resume       F2  restart"
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_label.add_theme_font_size_override("font_size", 21)
	_pause_panel.add_child(pause_label)
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
	subtitle.text = "TACTICAL OPERATIONS"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("56d8c5"))
	box.add_child(subtitle)
	_mode_select = _option(["DEFUSAL - BEST OF 7", "TEAM DEATHMATCH"])
	_map_select = _option(["HARBOR YARD", "TRAIN DEPOT", "SOLAR LAB"])
	_difficulty_select = _option(["RECRUIT BOTS", "VETERAN BOTS", "ELITE BOTS"])
	_difficulty_select.select(1)
	_quality_select = _option(["QUALITY: HIGH", "QUALITY: MEDIUM", "QUALITY: LOW"])
	_quality_select.item_selected.connect(func(index: int): quality_changed.emit(index))
	for control in [_mode_select, _map_select, _difficulty_select, _quality_select]:
		box.add_child(control)
	box.add_child(_menu_button("PLAY SOLO", _emit_solo))
	box.add_child(_menu_button("HOST LAN - 5v5", _emit_host))
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
	_map_label.text = "MAP %d/3\n%s" % [data.map_index + 1, data.map_name]
	_phase_label.text = data.phase
	_timer_label.text = data.time
	_score_label.text = "%d : %d" % [data.attack_score, data.defense_score]
	_money_label.text = "$%d" % data.money
	_health_label.text = "HP %d    ARMOR %d" % [ceili(data.health), ceili(data.armor)]
	_weapon_label.text = data.weapon
	_ammo_label.text = data.ammo
	_charge_label.text = data.charge
	_stamina_bar.value = data.stamina
	_buy_panel.visible = data.buy_visible
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

func set_paused(value: bool) -> void:
	_pause_panel.visible = value

func set_scoreboard(value: bool) -> void:
	_scoreboard.visible = value

func set_deployed(value: bool) -> void:
	_menu_overlay.visible = not value

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
