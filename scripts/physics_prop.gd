class_name LocalStrikePhysicsProp
extends RigidBody3D

signal state_changed(prop_id: String, state: Dictionary)
signal destroyed(prop: LocalStrikePhysicsProp, position: Vector3, surface_type: String)

const SurfaceProfile = preload("res://scripts/surface_profile.gd")

var prop_id := ""
var surface_type := "wood"
var size := Vector3.ONE
var tint := Color("806044")
var max_health := 60.0
var health := 60.0
var revision := 0
var destroyed_state := false
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
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	_mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.74 if surface_type == "wood" else 0.42
	material.metallic = 0.48 if surface_type == "metal" else 0.0
	_mesh.material_override = material
	add_child(_mesh)
	_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	_collision.shape = shape
	add_child(_collision)
