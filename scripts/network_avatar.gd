class_name LocalStrikeNetworkAvatar
extends CharacterBody3D

const VisualActor = preload("res://scripts/enemy.gd")
const Catalog = preload("res://scripts/weapon_catalog.gd")

signal damaged(peer_id: int, amount: float, hit_zone: String)
signal eliminated(peer_id: int)

var peer_id := 0
var team := 0
var health := 100.0
var armor := 35.0
var helmet := true
var weapon_name := "SIDEARM"
var target_position := Vector3.ZERO
var target_rotation_y := 0.0
var _body_root: Node3D
var _weapon: Node3D
var _visual_actor: LocalStrikeEnemy
var _visual_weapon_key := "sidearm"

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
	_visual_actor.velocity = (global_position - previous) / maxf(delta, 0.001)
	_visual_actor.health = health
	_visual_actor._animate_body(delta)

func apply_snapshot(position: Vector3, yaw: float, next_health: float, next_weapon: String) -> void:
	target_position = position
	target_rotation_y = yaw
	health = next_health
	weapon_name = next_weapon
	var next_key := "sidearm"
	for key in Catalog.all():
		if Catalog.get_weapon(key).display_name == next_weapon:
			next_key = key
			break
	if next_key != _visual_weapon_key and _visual_actor != null:
		_visual_weapon_key = next_key
		_visual_actor.equip_arsenal_weapon(next_key)
		_weapon = _visual_actor._held_weapon

func take_damage(amount: float, hit_zone := "torso", _context := {}) -> bool:
	return take_ballistic_damage(amount, hit_zone, 0.0)

func take_ballistic_damage(amount: float, hit_zone: String, armor_penetration: float) -> bool:
	if health <= 0.0:
		return false
	var base_armor_ratio := 0.0 if hit_zone == "limb" else (0.58 if hit_zone != "head" or helmet else 0.0)
	var absorbed := minf(armor, amount * base_armor_ratio * (1.0 - clampf(armor_penetration, 0.0, 1.0)))
	armor -= absorbed
	var health_damage := amount - absorbed
	health = maxf(0.0, health - health_damage)
	damaged.emit(peer_id, health_damage, hit_zone)
	if health <= 0.0:
		eliminated.emit(peer_id)
		return true
	return false

func apply_damage(amount: float, hit_zone := "torso", context := {}) -> void:
	take_damage(amount, hit_zone, context)

func apply_gameplay_impulse(impulse: Vector3, _at_position := Vector3.ZERO) -> void:
	target_position += impulse * 0.035

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
	# Reuse the rigged character and hand attachment without adding another actor.
	_visual_actor = VisualActor.new()
	_visual_actor.configure_spawn(team, "heavy", "sidearm", "passive", Vector3.ZERO)
	_visual_actor.configure_network_replica("visual_only")
	add_child(_visual_actor)
	_visual_actor.set_physics_process(false)
	_visual_actor.remove_from_group("damageable_actor")
	_visual_actor.collision_layer = 0
	_visual_actor.collision_mask = 0
	for area in _visual_actor.find_children("*", "Area3D", true, false):
		area.collision_layer = 0
		area.collision_mask = 0
	_visual_actor.health = health
	_body_root = _visual_actor
	_weapon = _visual_actor._held_weapon