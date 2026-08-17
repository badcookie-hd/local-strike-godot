class_name LocalStrikeSandboxSpawnController
extends Node3D

const ItemDefinition = preload("res://scripts/sandbox_item_definition.gd")
const WeaponModel = preload("res://scripts/weapon_model.gd")

signal placement_confirmed(definition: LocalStrikeSandboxItemDefinition, placement: Transform3D, options: Dictionary)
signal placement_cancelled
signal placement_state_changed(active: bool, valid: bool, item_name: String)

var player: LocalStrikePlayer
var active_definition: LocalStrikeSandboxItemDefinition
var active_options: Dictionary = {}
var placement_rotation := 0.0
var placement_valid := false
var _preview_root: Node3D
var _preview_material: StandardMaterial3D

func _ready() -> void:
	_preview_root = Node3D.new()
	_preview_root.name = "PlacementPreview"
	_preview_root.visible = false
	add_child(_preview_root)
	_preview_material = StandardMaterial3D.new()
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_material.albedo_color = Color(0.24, 0.95, 0.58, 0.42)
	_preview_material.emission_enabled = true
	_preview_material.emission = Color(0.08, 0.7, 0.35)
	_preview_material.no_depth_test = false

func configure(next_player: LocalStrikePlayer) -> void:
	player = next_player

func is_placing() -> bool:
	return active_definition != null

func begin_placement(definition: LocalStrikeSandboxItemDefinition, options := {}) -> void:
	if definition == null or definition.kind == ItemDefinition.Kind.WORLD:
		return
	active_definition = definition
	active_options = options.duplicate(true)
	placement_rotation = 0.0
	_rebuild_preview()
	_preview_root.visible = true
	set_process(true)
	placement_state_changed.emit(true, placement_valid, definition.display_name)

func update_preview() -> void:
	if active_definition == null or not is_instance_valid(player):
		return
	var target := _target_position(active_definition.placement_height)
	_preview_root.global_transform = Transform3D(Basis(Vector3.UP, placement_rotation), target)
	placement_valid = _validate_placement(target)
	var color := Color(0.24, 0.95, 0.58, 0.42) if placement_valid else Color(1.0, 0.22, 0.18, 0.45)
	_preview_material.albedo_color = color
	_preview_material.emission = Color(color.r, color.g, color.b) * 0.72
	placement_state_changed.emit(true, placement_valid, active_definition.display_name)

func confirm_placement() -> bool:
	if active_definition == null or not placement_valid:
		return false
	var definition := active_definition
	var options := active_options.duplicate(true)
	var placement := _preview_root.global_transform
	cancel_placement(false)
	placement_confirmed.emit(definition, placement, options)
	return true

func cancel_placement(emit_signal := true) -> void:
	active_definition = null
	active_options.clear()
	_preview_root.visible = false
	_clear_preview()
	placement_valid = false
	if emit_signal:
		placement_cancelled.emit()
	placement_state_changed.emit(false, false, "")

func rotate_preview(step_degrees: float) -> void:
	placement_rotation = wrapf(placement_rotation + deg_to_rad(step_degrees), -PI, PI)
	update_preview()

func equip_weapon(weapon_id: String) -> void:
	# Das Inventar selbst wird von GameSession verwaltet.
	active_options = {"weapon": weapon_id}

func clear_category(_category: String) -> void:
	# Das Leeren übernimmt die aktive Sandbox-Sitzung.
	pass

func _process(_delta: float) -> void:
	if active_definition != null:
		update_preview()

func _unhandled_input(event: InputEvent) -> void:
	if active_definition == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			confirm_placement()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			rotate_preview(15.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			rotate_preview(-15.0)
			get_viewport().set_input_as_handled()

func _target_position(height_offset: float) -> Vector3:
	var origin := player.get_aim_origin()
	var direction := player.get_aim_direction().normalized()
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + direction * 22.0)
	ray.exclude = [player.get_rid()]
	ray.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var target: Vector3 = hit.position if not hit.is_empty() else origin + direction * 8.0
	var floor_ray := PhysicsRayQueryParameters3D.create(target + Vector3.UP * 5.0, target + Vector3.DOWN * 12.0)
	floor_ray.exclude = [player.get_rid()]
	floor_ray.collision_mask = 1
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(floor_ray)
	if not floor_hit.is_empty():
		target = floor_hit.position
	target.y += height_offset
	return target

func _validate_placement(origin: Vector3) -> bool:
	var count := clampi(int(active_options.get("count", 1)), 1, active_definition.max_per_action)
	for index in range(count):
		var local_offset := _formation_offset(index, count)
		var rotated_offset := Basis(Vector3.UP, placement_rotation) * local_offset
		var placement_point := origin + rotated_offset
		if bool(active_definition.placement_rules.get("requires_floor", true)) and not _has_floor_support(placement_point):
			return false
		if bool(active_definition.placement_rules.get("requires_navigation", false)) and not _is_on_navigation(placement_point):
			return false
		var shape := BoxShape3D.new()
		shape.size = active_definition.preview_size * Vector3(0.82, 0.86, 0.82)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, placement_point + Vector3.UP * maxf(0.0, active_definition.preview_size.y * 0.5 - active_definition.placement_height))
		query.exclude = [player.get_rid()]
		query.collision_mask = 3
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true

func _has_floor_support(point: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.35, point + Vector3.DOWN * 0.8)
	ray.exclude = [player.get_rid()]
	ray.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.get("normal", Vector3.UP).dot(Vector3.UP) >= 0.66

func _is_on_navigation(point: Vector3) -> bool:
	var navigation_map := get_world_3d().navigation_map
	if not navigation_map.is_valid():
		return false
	var closest := NavigationServer3D.map_get_closest_point(navigation_map, point)
	var horizontal_distance := Vector2(closest.x, closest.z).distance_to(Vector2(point.x, point.z))
	return horizontal_distance <= 0.72 and absf(closest.y - point.y) <= 1.0

func _rebuild_preview() -> void:
	_clear_preview()
	var count := clampi(int(active_options.get("count", 1)), 1, active_definition.max_per_action)
	for index in range(count):
		var visual: Node3D
		if active_definition.kind == ItemDefinition.Kind.WEAPON and not active_definition.weapon_key.is_empty():
			visual = WeaponModel.create(active_definition.weapon_key)
			visual.scale = Vector3.ONE * 0.82
		else:
			visual = MeshInstance3D.new()
			var mesh: PrimitiveMesh
			if active_definition.kind == ItemDefinition.Kind.BOT or active_definition.surface_type == "barrel":
				var capsule := CapsuleMesh.new()
				capsule.radius = active_definition.preview_size.x * 0.5
				capsule.height = active_definition.preview_size.y
				mesh = capsule
			else:
				var box := BoxMesh.new()
				box.size = active_definition.preview_size
				mesh = box
			visual.mesh = mesh
		visual.position = _formation_offset(index, count)
		_apply_preview_material(visual)
		_preview_root.add_child(visual)

func _apply_preview_material(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = _preview_material
	for child in node.get_children():
		_apply_preview_material(child)

func _clear_preview() -> void:
	if _preview_root == null:
		return
	for child in _preview_root.get_children():
		child.queue_free()

func _formation_offset(index: int, count: int) -> Vector3:
	if count <= 1:
		return Vector3.ZERO
	var columns := mini(4, ceili(sqrt(float(count))))
	var rows := ceili(float(count) / float(columns))
	var column := index % columns
	var row := int(index / columns)
	return Vector3((float(column) - float(columns - 1) * 0.5) * 1.15, 0.0, (float(row) - float(rows - 1) * 0.5) * 1.15)
