class_name LocalStrikeNetworkAvatar
extends CharacterBody3D

signal damaged(peer_id: int, amount: float, hit_zone: String)
signal eliminated(peer_id: int)

var peer_id := 0
var team := 0
var health := 100.0
var weapon_name := "SIDEARM"
var target_position := Vector3.ZERO
var target_rotation_y := 0.0
var _body_root: Node3D
var _weapon: MeshInstance3D
var _left_leg: MeshInstance3D
var _right_leg: MeshInstance3D
var _left_arm: MeshInstance3D
var _right_arm: MeshInstance3D
var _walk_phase := 0.0

func configure(id: int, next_team: int) -> void:
	peer_id = id
	team = next_team
	name = "NetworkPlayer_%d" % id

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	add_to_group("damageable_actor")
	target_position = global_position
	_build_collision()
	_build_visual()

func _physics_process(delta: float) -> void:
	var previous := global_position
	global_position = global_position.lerp(target_position, minf(1.0, delta * 14.0))
	rotation.y = lerp_angle(rotation.y, target_rotation_y, minf(1.0, delta * 16.0))
	var speed := previous.distance_to(global_position) / maxf(delta, 0.001)
	_walk_phase += delta * speed * 4.0
	var swing := sin(_walk_phase) * minf(26.0, speed * 8.0)
	_left_leg.rotation_degrees.x = swing
	_right_leg.rotation_degrees.x = -swing
	_left_arm.rotation_degrees.x = -16.0 - swing * 0.32
	_right_arm.rotation_degrees.x = -31.0 + swing * 0.2

func apply_snapshot(position: Vector3, yaw: float, next_health: float, next_weapon: String) -> void:
	target_position = position
	target_rotation_y = yaw
	health = next_health
	weapon_name = next_weapon

func take_damage(amount: float, hit_zone := "torso") -> bool:
	if health <= 0.0:
		return false
	health = maxf(0.0, health - amount)
	damaged.emit(peer_id, amount, hit_zone)
	if health <= 0.0:
		eliminated.emit(peer_id)
		return true
	return false

func apply_damage(amount: float, hit_zone := "torso") -> void:
	take_damage(amount, hit_zone)

func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.55
	collision.shape = capsule
	collision.position.y = 0.82
	add_child(collision)
	_add_hitbox("head", Vector3(0, 1.55, 0), Vector3(0.42, 0.42, 0.42), true)
	_add_hitbox("torso", Vector3(0, 1.0, 0), Vector3(0.64, 0.7, 0.38))
	_add_hitbox("limb", Vector3(0, 0.42, 0), Vector3(0.55, 0.78, 0.34))

func _add_hitbox(zone: String, position: Vector3, size: Vector3, sphere := false) -> void:
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.position = position
	area.set_meta("hit_zone", zone)
	var collision := CollisionShape3D.new()
	if sphere:
		var shape := SphereShape3D.new()
		shape.radius = size.x / 2.0
		collision.shape = shape
	else:
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
	area.add_child(collision)
	add_child(area)

func _build_visual() -> void:
	_body_root = Node3D.new()
	add_child(_body_root)
	var team_color := Color("397080") if team == 0 else Color("8d4547")
	var uniform := _material(team_color, 0.62, 0.05)
	var armor := _material(team_color.darkened(0.38), 0.4, 0.35)
	var dark := _material(Color("182127"), 0.45, 0.42)
	_add_box(Vector3(0.58, 0.62, 0.36), Vector3(0, 1.02, 0), uniform)
	_add_box(Vector3(0.66, 0.3, 0.42), Vector3(0, 1.12, 0), armor)
	_left_leg = _add_capsule(0.11, 0.78, Vector3(-0.18, 0.4, 0), dark)
	_right_leg = _add_capsule(0.11, 0.78, Vector3(0.18, 0.4, 0), dark)
	_left_arm = _add_capsule(0.095, 0.68, Vector3(-0.4, 1.02, -0.04), uniform)
	_right_arm = _add_capsule(0.095, 0.68, Vector3(0.4, 1.02, -0.04), uniform)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	head_mesh.radial_segments = 14
	head_mesh.rings = 7
	head.mesh = head_mesh
	head.position = Vector3(0, 1.55, 0)
	head.material_override = _material(Color("a98a72"), 0.75, 0.0)
	_body_root.add_child(head)
	_add_box(Vector3(0.42, 0.1, 0.08), Vector3(0, 1.58, -0.2), dark)
	var helmet := MeshInstance3D.new()
	var helmet_mesh := SphereMesh.new()
	helmet_mesh.radius = 0.235
	helmet_mesh.height = 0.3
	helmet_mesh.radial_segments = 16
	helmet_mesh.rings = 6
	helmet.mesh = helmet_mesh
	helmet.position = Vector3(0, 1.69, 0.01)
	helmet.scale.y = 0.58
	helmet.material_override = armor
	_body_root.add_child(helmet)
	_add_box(Vector3(0.42, 0.44, 0.14), Vector3(0, 1.03, 0.25), armor)
	_weapon = _add_box(Vector3(0.12, 0.13, 0.68), Vector3(0.28, 1.02, -0.42), dark)

func _add_box(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	_body_root.add_child(instance)
	return instance

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _add_capsule(radius: float, height: float, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	_body_root.add_child(instance)
	return instance
