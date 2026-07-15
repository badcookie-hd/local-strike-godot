class_name LocalStrikeInteractable
extends StaticBody3D

signal state_changed(interactable_id: String, state: Dictionary)
signal exploded(interactable: LocalStrikeInteractable, position: Vector3, damage: float, radius: float)
signal effect_requested(position: Vector3, normal: Vector3, surface_type: String, effect_kind: String)

enum Kind { DOOR, GLASS, LAMP, FUEL }

var interactable_id := ""
var kind := Kind.DOOR
var size := Vector3(1.6, 2.5, 0.18)
var tint := Color("52616b")
var health := 100.0
var max_health := 100.0
var revision := 0
var opened := false
var destroyed := false
var armed := false
var _armed_timer := 0.0
var _closed_position := Vector3.ZERO
var _open_position := Vector3.ZERO
var _mesh: MeshInstance3D
var _collision: CollisionShape3D
var _light: OmniLight3D
var _blocking_area: Area3D
var _emissive_material: StandardMaterial3D

func configure(data: Dictionary) -> void:
	interactable_id = str(data.get("id", "interactive"))
	kind = int(data.get("kind", Kind.DOOR))
	size = data.get("size", _default_size(kind))
	tint = data.get("color", _default_color(kind))
	max_health = _default_health(kind)
	health = max_health
	set_meta("surface_type", _surface_type())
	add_to_group("interactable")

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	_closed_position = position
	_open_position = _closed_position + transform.basis.x * (size.x + 0.18)
	_build_visual()
	set_process(true)

func _process(delta: float) -> void:
	if kind == Kind.DOOR:
		var desired := _open_position if opened else _closed_position
		if not opened and _is_blocked():
			desired = _open_position
		position = position.lerp(desired, minf(1.0, delta * 8.0))
	if armed and not destroyed:
		_armed_timer -= delta
		if _light != null:
			_light.light_energy = 4.0 if fmod(_armed_timer, 0.22) > 0.11 else 0.2
		if _armed_timer <= 0.0:
			_explode()

func interact() -> bool:
	if kind != Kind.DOOR or destroyed:
		return false
	if opened and _is_blocked():
		return false
	opened = not opened
	_bump_revision()
	return true

func take_damage(amount: float, _hit_zone := "object") -> bool:
	if destroyed or kind == Kind.DOOR:
		return false
	health = maxf(0.0, health - amount)
	if health > 0.0:
		return false
	match kind:
		Kind.GLASS:
			_destroy_glass()
		Kind.LAMP:
			_destroy_lamp()
		Kind.FUEL:
			_arm_fuel()
	_bump_revision()
	return false

func reset_state() -> void:
	health = max_health
	opened = false
	destroyed = false
	armed = false
	_armed_timer = 0.0
	revision += 1
	position = _closed_position
	visible = true
	if _collision != null:
		_collision.set_deferred("disabled", false)
	if _light != null:
		_light.light_energy = 1.8 if kind == Kind.LAMP else 0.6
	if _emissive_material != null:
		_emissive_material.emission_enabled = true
	state_changed.emit(interactable_id, serialize_state())

func serialize_state() -> Dictionary:
	return {
		"id": interactable_id,
		"kind": kind,
		"health": health,
		"opened": opened,
		"destroyed": destroyed,
		"armed": armed,
		"armed_timer": _armed_timer,
		"revision": revision
	}

func apply_state(state: Dictionary) -> void:
	var next_revision := int(state.get("revision", 0))
	if next_revision < revision:
		return
	revision = next_revision
	health = float(state.get("health", health))
	opened = bool(state.get("opened", opened))
	destroyed = bool(state.get("destroyed", destroyed))
	armed = bool(state.get("armed", armed))
	_armed_timer = float(state.get("armed_timer", _armed_timer))
	if destroyed:
		visible = false if kind in [Kind.GLASS, Kind.FUEL] else true
		if _collision != null:
			_collision.set_deferred("disabled", true)
		if kind == Kind.LAMP and _light != null:
			_light.light_energy = 0.0
		if kind == Kind.LAMP and _emissive_material != null:
			_emissive_material.emission_enabled = false

func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.34 if kind != Kind.GLASS else 0.08
	material.metallic = 0.58 if kind in [Kind.DOOR, Kind.LAMP, Kind.FUEL] else 0.0
	if kind == Kind.GLASS:
		material.albedo_color = Color(tint, 0.34)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var mesh: PrimitiveMesh
	if kind == Kind.FUEL:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = size.x * 0.5
		cylinder.bottom_radius = size.x * 0.5
		cylinder.height = size.y
		cylinder.radial_segments = 20
		mesh = cylinder
	else:
		var box := BoxMesh.new()
		box.size = size
		mesh = box
	_mesh.mesh = mesh
	_mesh.material_override = material
	add_child(_mesh)

	_collision = CollisionShape3D.new()
	if kind == Kind.FUEL:
		var cylinder_shape := CylinderShape3D.new()
		cylinder_shape.radius = size.x * 0.5
		cylinder_shape.height = size.y
		_collision.shape = cylinder_shape
	else:
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		_collision.shape = box_shape
	add_child(_collision)

	if kind == Kind.DOOR:
		_build_door_sensor()
		_add_trim()
	elif kind == Kind.LAMP:
		_build_lamp()
	elif kind == Kind.FUEL:
		_build_fuel_light()

func _build_door_sensor() -> void:
	_blocking_area = Area3D.new()
	_blocking_area.collision_layer = 0
	_blocking_area.collision_mask = 3
	_blocking_area.monitoring = true
	var sensor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size + Vector3(0.35, 0.1, 0.65)
	sensor_shape.shape = box
	_blocking_area.add_child(sensor_shape)
	add_child(_blocking_area)

func _add_trim() -> void:
	for x in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(0.07, size.y + 0.08, size.z + 0.04)
		rail.mesh = rail_mesh
		rail.position.x = x * (size.x * 0.5 - 0.04)
		rail.material_override = _plain_material(Color("1d252b"), 0.38, 0.72)
		add_child(rail)

func _build_lamp() -> void:
	_emissive_material = _plain_material(Color("d9fff7"), 0.18, 0.0)
	_emissive_material.emission_enabled = true
	_emissive_material.emission = Color("8fffe8") * 2.6
	_mesh.material_override = _emissive_material
	_light = OmniLight3D.new()
	_light.light_color = Color("9ce8dc")
	_light.light_energy = 1.8
	_light.omni_range = 6.0
	_light.shadow_enabled = false
	add_child(_light)

func _build_fuel_light() -> void:
	_light = OmniLight3D.new()
	_light.position.y = size.y * 0.42
	_light.light_color = Color("ff5a35")
	_light.light_energy = 0.6
	_light.omni_range = 2.5
	_light.shadow_enabled = false
	add_child(_light)

func _destroy_glass() -> void:
	destroyed = true
	visible = false
	_collision.set_deferred("disabled", true)
	effect_requested.emit(global_position, Vector3.UP, "glass", "shatter")

func _destroy_lamp() -> void:
	destroyed = true
	_light.light_energy = 0.0
	_emissive_material.emission_enabled = false
	effect_requested.emit(global_position, Vector3.DOWN, "metal", "sparks")

func _arm_fuel() -> void:
	armed = true
	_armed_timer = 1.2
	effect_requested.emit(global_position + Vector3.UP * 0.4, Vector3.UP, "metal", "sparks")

func _explode() -> void:
	armed = false
	destroyed = true
	visible = false
	_collision.set_deferred("disabled", true)
	exploded.emit(self, global_position, 70.0, 4.5)
	_bump_revision()

func _is_blocked() -> bool:
	if _blocking_area == null:
		return false
	for body in _blocking_area.get_overlapping_bodies():
		if body is CharacterBody3D:
			return true
	return false

func _bump_revision() -> void:
	revision += 1
	state_changed.emit(interactable_id, serialize_state())

func _surface_type() -> String:
	match kind:
		Kind.GLASS: return "glass"
		Kind.LAMP, Kind.FUEL, Kind.DOOR: return "metal"
	return "concrete"

func _default_health(value: int) -> float:
	match value:
		Kind.GLASS: return 35.0
		Kind.LAMP: return 20.0
		Kind.FUEL: return 65.0
	return 9999.0

func _default_size(value: int) -> Vector3:
	match value:
		Kind.GLASS: return Vector3(2.4, 1.45, 0.06)
		Kind.LAMP: return Vector3(0.38, 0.14, 0.24)
		Kind.FUEL: return Vector3(0.58, 0.95, 0.58)
	return Vector3(1.6, 2.5, 0.18)

func _default_color(value: int) -> Color:
	match value:
		Kind.GLASS: return Color("8ed5e3")
		Kind.LAMP: return Color("d9fff7")
		Kind.FUEL: return Color("bd4a32")
	return Color("52616b")

func _plain_material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
