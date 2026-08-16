class_name LocalStrikeSandboxBrowser
extends CanvasLayer

const Catalog = preload("res://scripts/sandbox_catalog.gd")
const BotConfig = preload("res://scripts/sandbox_bot_config.gd")
const WeaponCatalog = preload("res://scripts/weapon_catalog.gd")
const ItemDefinition = preload("res://scripts/sandbox_item_definition.gd")
const ItemPreview = preload("res://scripts/sandbox_item_preview.gd")

signal item_selected(definition: LocalStrikeSandboxItemDefinition)
signal placement_requested(definition: LocalStrikeSandboxItemDefinition, options: Dictionary)
signal equip_requested(weapon_id: String)
signal world_action_requested(action: String, payload: Dictionary)
signal browser_visibility_changed(visible: bool)

const CATEGORIES := ["Bots", "Weapons", "Melee", "Grenades", "Props", "World"]

var _items: Array[LocalStrikeSandboxItemDefinition] = []
var _active := false
var _selected_category := "Bots"
var _selected: LocalStrikeSandboxItemDefinition
var _recent: Array[StringName] = []

var _root: Control
var _tool_button: Button
var _overlay: ColorRect
var _search: LineEdit
var _category_buttons: Dictionary = {}
var _card_buttons: Dictionary = {}
var _grid: GridContainer
var _detail_title: Label
var _detail_description: Label
var _bot_options: VBoxContainer
var _team_select: OptionButton
var _kind_select: OptionButton
var _weapon_select: OptionButton
var _behavior_select: OptionButton
var _bot_count: SpinBox
var _amount_row: HBoxContainer
var _amount_spin: SpinBox
var _primary_action: Button
var _secondary_action: Button
var _quickbar: HBoxContainer
var _quickbar_panel: PanelContainer
var _count_label: Label
var _placement_banner: PanelContainer
var _placement_label: Label

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_items = Catalog.build()
	_build_ui()
	get_viewport().size_changed.connect(_on_viewport_resized)
	set_sandbox_active(false)

func _input(event: InputEvent) -> void:
	if not _active or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var pressed_key := key_event.keycode if key_event.keycode != KEY_NONE else key_event.physical_keycode
	if pressed_key == KEY_B:
		toggle_browser()
		get_viewport().set_input_as_handled()
	elif pressed_key == KEY_ESCAPE and is_open():
		close_browser()
		get_viewport().set_input_as_handled()

func set_sandbox_active(value: bool) -> void:
	_active = value
	_tool_button.visible = value
	_quickbar_panel.visible = value and not _recent.is_empty()
	if not value:
		close_browser()
		set_placement_state(false, false, "")

func is_open() -> bool:
	return _overlay.visible

func toggle_browser() -> void:
	if not _active:
		return
	if is_open():
		close_browser()
	else:
		open_browser()

func open_browser() -> void:
	if not _active:
		return
	_overlay.visible = true
	_tool_button.visible = false
	_quickbar_panel.visible = not _recent.is_empty()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_search.grab_focus()
	_rebuild_cards()
	browser_visibility_changed.emit(true)

func close_browser() -> void:
	if _overlay == null:
		return
	_overlay.visible = false
	_tool_button.visible = _active
	_quickbar_panel.visible = false
	if _active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	browser_visibility_changed.emit(false)

func set_counts(npcs: int, props: int, weapons: int, bodies: int) -> void:
	if _count_label != null:
		_count_label.text = "%d / 40 BOTS    %d / 64 PROPS    %d / 32 WEAPONS    %d / 24 BODIES" % [npcs, props, weapons, bodies]

func set_placement_state(active: bool, valid: bool, item_name: String) -> void:
	if _placement_banner == null:
		return
	_placement_banner.visible = active and _active
	if active:
		_placement_label.text = "%s    %s\nLEFT CLICK PLACE    RIGHT CLICK CANCEL    WHEEL ROTATE" % [item_name, "VALID" if valid else "BLOCKED"]
		_placement_label.add_theme_color_override("font_color", Color("70e9a6") if valid else Color("ff625d"))

func select_item_by_id(item_id: StringName) -> bool:
	for definition in _items:
		if definition.id == item_id:
			_selected_category = definition.category
			_select_definition(definition)
			return true
	return false

func get_item_count() -> int:
	return _items.size()

func get_weapon_card_count() -> int:
	var count := 0
	for definition in _items:
		if definition.kind == ItemDefinition.Kind.WEAPON:
			count += 1
	return count

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_tool_button = Button.new()
	_tool_button.text = "SPAWN BROWSER  [B]"
	_tool_button.tooltip_text = "Open the sandbox spawn browser"
	_tool_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_tool_button.position = Vector2(22, -148)
	_tool_button.size = Vector2(206, 44)
	_tool_button.add_theme_font_size_override("font_size", 15)
	_tool_button.add_theme_stylebox_override("normal", _style(Color("18242a"), Color("56d8c5"), 2, 6))
	_tool_button.add_theme_stylebox_override("hover", _style(Color("22353a"), Color("7ff1de"), 2, 6))
	_tool_button.pressed.connect(open_browser)
	_root.add_child(_tool_button)

	_build_placement_banner()

	_overlay = ColorRect.new()
	_overlay.color = Color(0.015, 0.021, 0.024, 0.96)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_overlay)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 24)
	outer.add_theme_constant_override("margin_right", 24)
	outer.add_theme_constant_override("margin_top", 18)
	outer.add_theme_constant_override("margin_bottom", 18)
	_overlay.add_child(outer)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 10)
	outer.add_child(shell)
	shell.add_child(_build_header())
	shell.add_child(_build_category_bar())
	_build_quickbar()
	shell.add_child(_quickbar_panel)

	var content := HSplitContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.split_offset = 350
	content.add_theme_constant_override("separation", 14)
	shell.add_child(content)

	var browser_panel := PanelContainer.new()
	browser_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser_panel.add_theme_stylebox_override("panel", _style(Color("0f171b"), Color("293a40"), 1, 6))
	content.add_child(browser_panel)
	var browser_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		browser_margin.add_theme_constant_override("margin_%s" % side, 12)
	browser_panel.add_child(browser_margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	browser_margin.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)

	content.add_child(_build_detail_panel())
	_overlay.visible = false

func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 52
	row.add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = "FOUNDRY SANDBOX"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_count_label = Label.new()
	_count_label.text = "0 / 40 BOTS    0 / 64 PROPS    0 / 32 WEAPONS    0 / 24 BODIES"
	_count_label.add_theme_color_override("font_color", Color("9eb0b5"))
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_count_label)
	var close := Button.new()
	close.text = "CLOSE  [B]"
	close.custom_minimum_size = Vector2(126, 40)
	close.tooltip_text = "Close the spawn browser"
	close.pressed.connect(close_browser)
	row.add_child(close)
	return row

func _build_category_bar() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for category in CATEGORIES:
		var button := Button.new()
		button.text = category.to_upper()
		button.toggle_mode = true
		button.button_pressed = category == _selected_category
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 38
		button.pressed.connect(_select_category.bind(category))
		row.add_child(button)
		_category_buttons[category] = button
	column.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "Search weapons, bots and props"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.y = 40
	_search.text_changed.connect(func(_text: String): _rebuild_cards())
	column.add_child(_search)
	return column

func _build_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 330
	panel.add_theme_stylebox_override("panel", _style(Color("111b20"), Color("385058"), 1, 6))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_detail_title = Label.new()
	_detail_title.text = "SELECT AN ITEM"
	_detail_title.add_theme_font_size_override("font_size", 22)
	column.add_child(_detail_title)
	_detail_description = Label.new()
	_detail_description.text = "Choose a card from the browser."
	_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_description.add_theme_color_override("font_color", Color("a8b7bb"))
	_detail_description.custom_minimum_size.y = 42
	column.add_child(_detail_description)
	var divider := HSeparator.new()
	column.add_child(divider)

	_bot_options = VBoxContainer.new()
	_bot_options.add_theme_constant_override("separation", 4)
	_team_select = _option(["ENEMY", "ALLY"])
	_kind_select = _option(["SCOUT", "ASSAULT", "HEAVY"])
	_weapon_select = OptionButton.new()
	_weapon_select.custom_minimum_size.y = 32
	for key in WeaponCatalog.bot_weapon_keys():
		_weapon_select.add_item(WeaponCatalog.get_weapon(key).display_name)
		_weapon_select.set_item_metadata(_weapon_select.item_count - 1, key)
	_behavior_select = _option(["AGGRESSIVE", "GUARD", "PASSIVE"])
	_bot_count = SpinBox.new()
	_bot_count.min_value = 1
	_bot_count.max_value = 10
	_bot_count.value = 1
	_bot_count.custom_minimum_size.y = 32
	_add_field(_bot_options, "TEAM", _team_select)
	_add_field(_bot_options, "ARCHETYPE", _kind_select)
	_add_field(_bot_options, "WEAPON", _weapon_select)
	_add_field(_bot_options, "BEHAVIOR", _behavior_select)
	_add_field(_bot_options, "FORMATION COUNT", _bot_count)
	column.add_child(_bot_options)

	_amount_row = HBoxContainer.new()
	var amount_label := Label.new()
	amount_label.text = "COUNT"
	amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount_row.add_child(amount_label)
	_amount_spin = SpinBox.new()
	_amount_spin.min_value = 1
	_amount_spin.max_value = 10
	_amount_spin.value = 1
	_amount_spin.custom_minimum_size = Vector2(104, 38)
	_amount_row.add_child(_amount_spin)
	column.add_child(_amount_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	_primary_action = Button.new()
	_primary_action.text = "PLACE"
	_primary_action.custom_minimum_size.y = 44
	_primary_action.add_theme_font_size_override("font_size", 16)
	_primary_action.add_theme_stylebox_override("normal", _style(Color("17443c"), Color("56d8c5"), 2, 6))
	_primary_action.pressed.connect(_activate_primary)
	column.add_child(_primary_action)
	_secondary_action = Button.new()
	_secondary_action.text = "EQUIP NOW"
	_secondary_action.custom_minimum_size.y = 40
	_secondary_action.pressed.connect(_activate_secondary)
	column.add_child(_secondary_action)
	return panel

func _build_quickbar() -> void:
	_quickbar_panel = PanelContainer.new()
	_quickbar_panel.custom_minimum_size.y = 52
	_quickbar_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quickbar_panel.add_theme_stylebox_override("panel", _style(Color(0.035, 0.055, 0.062, 0.92), Color("2c4148"), 1, 5))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_quickbar_panel.add_child(margin)
	_quickbar = HBoxContainer.new()
	_quickbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_quickbar.add_theme_constant_override("separation", 5)
	margin.add_child(_quickbar)

func _build_placement_banner() -> void:
	_placement_banner = PanelContainer.new()
	_placement_banner.anchor_left = 0.5
	_placement_banner.anchor_right = 0.5
	_placement_banner.anchor_top = 1.0
	_placement_banner.anchor_bottom = 1.0
	_placement_banner.offset_left = -315
	_placement_banner.offset_right = 315
	_placement_banner.offset_top = -172
	_placement_banner.offset_bottom = -108
	_placement_banner.add_theme_stylebox_override("panel", _style(Color(0.025, 0.042, 0.047, 0.96), Color("56d8c5"), 1, 5))
	_root.add_child(_placement_banner)
	_placement_label = Label.new()
	_placement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placement_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placement_label.add_theme_font_size_override("font_size", 13)
	_placement_banner.add_child(_placement_label)
	_placement_banner.visible = false

func _select_category(category: String) -> void:
	_selected_category = category
	for name in _category_buttons:
		_category_buttons[name].set_pressed_no_signal(name == category)
	_rebuild_cards()

func _rebuild_cards() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_card_buttons.clear()
	var viewport_width := get_viewport().get_visible_rect().size.x
	_grid.columns = 4 if viewport_width >= 1700 else (3 if viewport_width >= 1080 else 2)
	var needle := _search.text.strip_edges().to_lower() if _search != null else ""
	var first: LocalStrikeSandboxItemDefinition
	for definition in _items:
		if definition.category != _selected_category:
			continue
		if not needle.is_empty() and needle not in (definition.display_name + " " + definition.description).to_lower():
			continue
		if first == null:
			first = definition
		var card := Button.new()
		card.text = ""
		card.custom_minimum_size = Vector2(174, 142)
		card.tooltip_text = definition.description
		card.add_theme_stylebox_override("normal", _style(Color("182228"), Color("2b3c43"), 1, 5))
		card.add_theme_stylebox_override("hover", _style(Color("23343a"), Color("56d8c5"), 2, 5))
		card.add_theme_stylebox_override("pressed", _style(Color("17443c"), Color("7ff1de"), 2, 5))
		card.pressed.connect(_select_definition.bind(definition))
		_card_buttons[definition.id] = card
		var card_margin := MarginContainer.new()
		card_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_margin.add_theme_constant_override("margin_left", 7)
		card_margin.add_theme_constant_override("margin_right", 7)
		card_margin.add_theme_constant_override("margin_top", 6)
		card_margin.add_theme_constant_override("margin_bottom", 7)
		card.add_child(card_margin)
		var card_column := VBoxContainer.new()
		card_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_column.add_theme_constant_override("separation", 4)
		card_margin.add_child(card_column)
		var preview := ItemPreview.new()
		preview.configure(definition)
		card_column.add_child(preview)
		var name_label := Label.new()
		name_label.text = definition.display_name
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card_column.add_child(name_label)
		var description_label := Label.new()
		description_label.text = definition.description
		description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		description_label.add_theme_font_size_override("font_size", 10)
		description_label.add_theme_color_override("font_color", Color("91a5aa"))
		description_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card_column.add_child(description_label)
		_grid.add_child(card)
	if first != null and (_selected == null or _selected.category != _selected_category):
		_select_definition(first)

func _select_definition(definition: LocalStrikeSandboxItemDefinition) -> void:
	_selected = definition
	_detail_title.text = definition.display_name
	_detail_description.text = definition.description
	_bot_options.visible = definition.kind == ItemDefinition.Kind.BOT
	_amount_row.visible = definition.kind in [ItemDefinition.Kind.WEAPON, ItemDefinition.Kind.PROP]
	_secondary_action.visible = definition.kind == ItemDefinition.Kind.WEAPON
	match definition.kind:
		ItemDefinition.Kind.BOT:
			_primary_action.text = "PLACE FORMATION"
			_kind_select.select(["scout", "assault", "heavy"].find(definition.bot_kind))
		ItemDefinition.Kind.WEAPON:
			_primary_action.text = "PLACE WEAPON"
			_secondary_action.text = "EQUIP NOW"
		ItemDefinition.Kind.PROP:
			_primary_action.text = "PLACE PROP"
		ItemDefinition.Kind.WORLD:
			_primary_action.text = "RUN ACTION"
	item_selected.emit(definition)

func _activate_primary() -> void:
	if _selected == null:
		return
	_add_recent(_selected.id)
	if _selected.kind == ItemDefinition.Kind.WORLD:
		world_action_requested.emit(_selected.world_action, {})
		return
	var options := _selection_options()
	placement_requested.emit(_selected, options)
	close_browser()

func _activate_secondary() -> void:
	if _selected == null or _selected.kind != ItemDefinition.Kind.WEAPON:
		return
	_add_recent(_selected.id)
	equip_requested.emit(_selected.weapon_key)

func _selection_options() -> Dictionary:
	if _selected.kind == ItemDefinition.Kind.BOT:
		var config := BotConfig.new()
		config.team = _team_select.selected
		config.archetype = _kind_select.selected
		config.weapon_key = str(_weapon_select.get_item_metadata(_weapon_select.selected))
		config.behavior = _behavior_select.selected
		config.count = roundi(_bot_count.value)
		return config.to_dictionary()
	return {"count": clampi(roundi(_amount_spin.value), 1, _selected.max_per_action)}

func _add_recent(item_id: StringName) -> void:
	_recent.erase(item_id)
	_recent.push_front(item_id)
	if _recent.size() > 8:
		_recent.resize(8)
	for child in _quickbar.get_children():
		_quickbar.remove_child(child)
		child.queue_free()
	for recent_id in _recent:
		var definition := _find_item(recent_id)
		if definition == null:
			continue
		var button := Button.new()
		button.text = definition.display_name
		button.tooltip_text = definition.description
		button.custom_minimum_size = Vector2(76, 40)
		button.add_theme_font_size_override("font_size", 10)
		button.pressed.connect(_quick_activate.bind(definition))
		_quickbar.add_child(button)
	_quickbar_panel.visible = _active and is_open() and not _recent.is_empty()

func _quick_activate(definition: LocalStrikeSandboxItemDefinition) -> void:
	_select_definition(definition)
	if definition.kind == ItemDefinition.Kind.WORLD:
		world_action_requested.emit(definition.world_action, {})
	elif definition.kind == ItemDefinition.Kind.WEAPON:
		placement_requested.emit(definition, {"count": 1})
	elif definition.kind == ItemDefinition.Kind.BOT:
		placement_requested.emit(definition, {"team": "enemy", "kind": definition.bot_kind, "weapon": "sentinel", "behavior": "aggressive", "count": 1})
	else:
		placement_requested.emit(definition, {"count": 1})

func _find_item(item_id: StringName) -> LocalStrikeSandboxItemDefinition:
	for definition in _items:
		if definition.id == item_id:
			return definition
	return null

func _on_viewport_resized() -> void:
	_rebuild_cards()

func _option(items: Array[String]) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.y = 32
	for item in items:
		option.add_item(item)
	return option

func _add_field(parent: VBoxContainer, label_text: String, control: Control) -> void:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("93a7ad"))
	parent.add_child(label)
	parent.add_child(control)

func _style(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style
