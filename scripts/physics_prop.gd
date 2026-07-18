class_name LocalStrikePhysicsProp
extends RigidBody3D

signal state_changed(prop_id: String, state: Dictionary)
signal destroyed(prop: LocalStrikePhysicsProp, position: Vector3, surface_type: String)

const SurfaceProfile = preload("res://scripts/surface_profile.gd")
const Materials = preload("res://scripts/material_library.gd")

var prop_id := ""
var surface_type := "wood"
var size := Vector3.ONE
var tint := Color("806044")
var max_health := 60.0
var health := 60.0
var revision := 0
var destroyed_state := false
var visual_variant := ""
var _initial_transform := Transform3D.IDENTITY
var _collision: CollisionShape3D
var _mesh: MeshInstance3D

func configure(data: Dictionary) -> void:
	prop_id = str(data.get("id", "prop"))
	surface_type = str(data.get("surface", "wood"))
	size = data.get("size", Vector3.ONE)
	tint = data.get("color", Color("806044"))
	max_health = float(data.get("health", 60.0))
	health = max_health
	mass = float(data.get("mass", 18.0))
	visual_variant = str(data.get("variant", surface_type))
	set_meta("surface_type", surface_type)
	add_to_group("physics_prop")

func _ready() -> void:
	_initial_transform = transform
	collision_layer = 1
	collision_mask = 1
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	var profile: Dictionary = SurfaceProfile.get_profile(surface_type)
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = profile.friction
	physics_material.bounce = profile.bounce
	physics_material_override = physics_material
	_build_visual()

func take_damage(amount: float, _zone := "object", _context := {}) -> bool:
	if destroyed_state:
		return false
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		destroyed_state = true
		visible = false
		_collision.set_deferred("disabled", true)
		freeze = true
		revision += 1
		destroyed.emit(self, global_position, surface_type)
		state_changed.emit(prop_id, serialize_state())
	return false

func apply_gameplay_impulse(impulse: Vector3, at_position := Vector3.ZERO) -> void:
	if destroyed_state:
		return
	freeze = false
	apply_impulse(impulse, at_position)
	revision += 1
	state_changed.emit(prop_id, serialize_state())

func reset_state() -> void:
	transform = _initial_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	health = max_health
	destroyed_state = false
	visible = true
	freeze = false
	_collision.set_deferred("disabled", false)
	revision += 1
	state_changed.emit(prop_id, serialize_state())

func serialize_state() -> Dictionary:
	return {"id": prop_id, "transform": transform, "linear_velocity": linear_velocity, "angular_velocity": angular_velocity, "sleeping": sleeping, "health": health, "destroyed": destroyed_state, "revision": revision}

func apply_state(state: Dictionary) -> void:
	var next_revision := int(state.get("revision", 0))
	if next_revision < revision:
		return
	revision = next_revision
	transform = state.get("transform", transform)
	linear_velocity = state.get("linear_velocity", linear_velocity)
	angular_velocity = state.get("angular_velocity", angular_velocity)
	sleeping = bool(state.get("sleeping", sleeping))
	health = float(state.get("health", health))
	destroyed_state = bool(state.get("destroyed", destroyed_state))
	visible = not destroyed_state
	if _collision != null:
		_collision.set_deferred("disabled", destroyed_state)

func _build_visual() -> void:
	_collision = CollisionShape3D.new()
	if visual_variant == "barrel":
		_build_barrel()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = size.x * 0.5
		cylinder.height = size.y
		_collision.shape = cylinder
	elif visual_variant == "tool_cart":
		_build_tool_cart()
		var cart_shape := BoxShape3D.new()
		cart_shape.size = size
		_collision.shape = cart_shape
	else:
		_build_case()
		var shape := BoxShape3D.new()
		shape.size = size
		_collision.shape = shape
	add_child(_collision)

func _build_case() -> void:
	_mesh = _add_box(size, Vector3.ZERO, "wood" if surface_type == "wood" else "steel_plate", tint)
	var trim_material := "wood" if surface_type == "wood" else "rust"
	var trim_color := tint.darkened(0.38)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_add_box(Vector3(0.075, size.y + 0.04, 0.075), Vector3(x * (size.x * 0.5 - 0.04), 0, z * (size.z * 0.5 - 0.04)), trim_material, trim_color)
	for y in [-1.0, 1.0]:
		_add_box(Vector3(size.x + 0.05, 0.065, size.z + 0.05), Vector3(0, y * (size.y * 0.5 - 0.035), 0), trim_material, trim_color)

func _build_barrel() -> void:
	_mesh = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = size.x * 0.48
	mesh.bottom_radius = size.x * 0.48
	mesh.height = size.y
	mesh.radial_segments = 28
	_mesh.mesh = mesh
	_mesh.material_override = Materials.create("rust", Color("9e4b32"), 1.3)
	add_child(_mesh)
	for y in [-0.38, 0.0, 0.38]:
		var band := MeshInstance3D.new()
		var band_mesh := TorusMesh.new()
		band_mesh.inner_radius = size.x * 0.475
		band_mesh.outer_radius = size.x * 0.52
		band_mesh.rings = 24
		band_mesh.ring_segments = 8
		band.mesh = band_mesh
		band.position.y = y * size.y
		band.material_override = Materials.create("steel_plate", Color("495054"), 1.8)
		add_child(band)

func _build_tool_cart() -> void:
	_mesh = _add_box(Vector3(size.x, size.y * 0.78, size.z), Vector3(0, size.y * 0.08, 0), "painted_concrete", Color("6f3432"))
	for y in [-0.22, 0.06, 0.34]:
		_add_box(Vector3(size.x * 0.86, 0.04, size.z + 0.02), Vector3(0, y, -0.02), "steel_plate", Color("313a3d"))
	for x in [-size.x * 0.38, size.x * 0.38]:
		for z in [-size.z * 0.38, size.z * 0.38]:
			var wheel := MeshInstance3D.new()
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.1
			wheel_mesh.bottom_radius = 0.1
			wheel_mesh.height = 0.08
			wheel.mesh = wheel_mesh
			wheel.position = Vector3(x, -size.y * 0.48, z)
			wheel.rotation_degrees.z = 90
			wheel.material_override = Materials.create("rubber", Color("343738"), 1.8)
			add_child(wheel)

func _add_box(box_size: Vector3, position: Vector3, material_name: String, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = Materials.create(material_name, color, 1.25)
	add_child(instance)
	return instance
