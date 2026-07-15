class_name LocalStrikeWeaponDefinition
extends Resource

enum Slot { MELEE, PRIMARY, SECONDARY, GRENADE }

@export var key := ""
@export var display_name := ""
@export var slot := Slot.PRIMARY
@export var price := 0
@export var damage := 30.0
@export var head_multiplier := 3.5
@export var limb_multiplier := 0.76
@export var spread := 0.015
@export var move_spread := 0.025
@export var range := 40.0
@export var magazine := 30
@export var reserve := 90
@export var fire_delay := 0.12
@export var reload_time := 1.5
@export var pellets := 1
@export var automatic := true
@export var recoil_pitch := 0.018
@export var recoil_yaw := 0.008
@export var category := "rifle"
@export var view_model_path := ""
@export var world_model_path := ""
@export var animation_profile := "rifle"
@export var surface_profile := "metal"
@export var muzzle_offset := Vector3(0, 0, -0.78)
@export var view_scale := Vector3.ONE

static func create(data: Dictionary) -> LocalStrikeWeaponDefinition:
	var weapon := LocalStrikeWeaponDefinition.new()
	for property in data:
		weapon.set(property, data[property])
	return weapon
