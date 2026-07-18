class_name LocalStrikeDroppedWeapon
extends RigidBody3D

var drop_id := ""
var weapon_key := "sidearm"
var ammo := 0
var reserve := 0
var revision := 0

func configure(id: String, key: String, current_ammo: int, reserve_ammo: int) -> void:
	drop_id = id
	weapon_key = key
	ammo = current_ammo
	reserve = reserve_ammo
	add_to_group("dropped_weapon")
	set_meta("surface_type", "metal")

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	mass = 2.8
	continuous_cd = true
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 0.15, 0.72)
	collision.shape = shape
	add_child(collision)
	var model := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.2, 0.15, 0.72)
	model.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("303943")
	material.metallic = 0.55
	material.roughness = 0.34
	model.material_override = material
	add_child(model)

func serialize_state() -> Dictionary:
	return {"id": drop_id, "weapon": weapon_key, "ammo": ammo, "reserve": reserve, "transform": transform, "linear_velocity": linear_velocity, "angular_velocity": angular_velocity, "revision": revision}
