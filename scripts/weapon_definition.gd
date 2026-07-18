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
@export var fire_modes: Array[String] = ["auto"]
@export var recoil_pattern: Array[Vector2] = []
@export var falloff_start := 18.0
@export var falloff_end := 55.0
@export var minimum_damage_multiplier := 0.62
@export var penetration_power := 0.7
@export var armor_penetration := 0.55
@export var ads_fov := 62.0
@export var ads_spread_multiplier := 0.42
@export var equip_time := 0.42
@export var weight := 1.0
@export var shot_impulse := 3.0
@export var sound_profile := "rifle"
@export var view_model_path := ""
@export var world_model_path := ""
@export var animation_profile := "rifle"
@export var surface_profile := "metal"
@export var muzzle_offset := Vector3(0, 0, -0.78)
@export var view_scale := Vector3.ONE
@export var melee_type := ""
@export var melee_reach := 0.0
@export var melee_arc_degrees := 0.0
@export var melee_light_damage := 0.0
@export var melee_heavy_damage := 0.0
@export var melee_light_recovery := 0.0
@export var melee_heavy_recovery := 0.0
@export var melee_max_targets := 1
@export var melee_impulse := 0.0
@export var blood_multiplier := 1.0

static func create(data: Dictionary) -> LocalStrikeWeaponDefinition:
	var weapon := LocalStrikeWeaponDefinition.new()
	for property in data:
		if property == "fire_modes":
			weapon.fire_modes.assign(data[property])
		elif property == "recoil_pattern":
			weapon.recoil_pattern.assign(data[property])
		else:
			weapon.set(property, data[property])
	return weapon
