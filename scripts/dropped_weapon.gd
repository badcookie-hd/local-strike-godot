class_name LocalStrikeDroppedWeapon
extends RigidBody3D

const WeaponModel = preload("res://scripts/weapon_model.gd")

var drop_id := ""
var weapon_key := "sidearm"
var ammo := 0
var reserve := 0
var revision := 0
var bloodiness := 0.0
var _model: Node3D

func configure(id: String, key: String, current_ammo: int, reserve_ammo: int, next_bloodiness := 0.0) -> void:
	drop_id = id
	weapon_key = key
	ammo = current_ammo
	reserve = reserve_ammo
	bloodiness = clampf(next_bloodiness, 0.0, 1.0)
	add_to_group("dropped_weapon")
	set_meta("surface_type", "metal")

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	mass = 2.8
	continuous_cd = true
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = WeaponModel.collision_size(weapon_key)
	collision.shape = shape
	add_child(collision)
	_model = WeaponModel.create(weapon_key, bloodiness)
	add_child(_model)

func clear_blood() -> void:
	bloodiness = 0.0
	if is_instance_valid(_model):
		_model.queue_free()
	_model = WeaponModel.create(weapon_key, 0.0)
	add_child(_model)

func serialize_state() -> Dictionary:
	return {"id": drop_id, "weapon": weapon_key, "ammo": ammo, "reserve": reserve, "bloodiness": bloodiness, "transform": transform, "linear_velocity": linear_velocity, "angular_velocity": angular_velocity, "revision": revision}
