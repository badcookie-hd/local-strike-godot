class_name LocalStrikeWeaponCatalog
extends RefCounted

const Definition = preload("res://scripts/weapon_definition.gd")

static var _weapons: Dictionary = {}

static func all() -> Dictionary:
	if _weapons.is_empty():
		_build()
	return _weapons

static func get_weapon(key: String) -> LocalStrikeWeaponDefinition:
	return all().get(key, all()["sidearm"])

static func primary_keys() -> Array[String]:
	return ["smg", "ranger", "breacher", "marksman", "heavy_sniper"]

static func _build() -> void:
	_weapons = {
		"knife": Definition.create({"key": "knife", "display_name": "KNIFE", "slot": Definition.Slot.MELEE, "damage": 48.0, "range": 2.2, "magazine": 1, "reserve": 0, "fire_delay": 0.48, "reload_time": 0.0, "automatic": false, "recoil_pitch": 0.0, "recoil_yaw": 0.0, "category": "melee"}),
		"sidearm": Definition.create({"key": "sidearm", "display_name": "SIDEARM", "slot": Definition.Slot.SECONDARY, "damage": 34.0, "head_multiplier": 3.8, "spread": 0.011, "move_spread": 0.022, "range": 38.0, "magazine": 12, "reserve": 36, "fire_delay": 0.28, "reload_time": 1.05, "automatic": false, "recoil_pitch": 0.024, "recoil_yaw": 0.012, "category": "pistol"}),
		"smg": Definition.create({"key": "smg", "display_name": "COMPACT SMG", "price": 1250, "damage": 22.0, "head_multiplier": 3.0, "spread": 0.024, "move_spread": 0.035, "range": 32.0, "magazine": 30, "reserve": 90, "fire_delay": 0.075, "reload_time": 1.35, "recoil_pitch": 0.012, "recoil_yaw": 0.011, "category": "smg"}),
		"ranger": Definition.create({"key": "ranger", "display_name": "RANGER RIFLE", "price": 2700, "damage": 31.0, "head_multiplier": 3.6, "spread": 0.017, "move_spread": 0.038, "range": 48.0, "magazine": 30, "reserve": 90, "fire_delay": 0.095, "reload_time": 1.55, "recoil_pitch": 0.019, "recoil_yaw": 0.012, "category": "rifle"}),
		"breacher": Definition.create({"key": "breacher", "display_name": "BREACHER", "price": 2100, "damage": 16.0, "head_multiplier": 1.45, "spread": 0.095, "move_spread": 0.045, "range": 18.0, "magazine": 6, "reserve": 30, "fire_delay": 0.68, "reload_time": 1.65, "pellets": 7, "automatic": false, "recoil_pitch": 0.07, "recoil_yaw": 0.018, "category": "shotgun"}),
		"marksman": Definition.create({"key": "marksman", "display_name": "MARKSMAN", "price": 3300, "damage": 82.0, "head_multiplier": 2.2, "spread": 0.004, "move_spread": 0.055, "range": 72.0, "magazine": 10, "reserve": 30, "fire_delay": 0.72, "reload_time": 1.8, "automatic": false, "recoil_pitch": 0.055, "recoil_yaw": 0.014, "category": "dmr"}),
		"heavy_sniper": Definition.create({"key": "heavy_sniper", "display_name": "HEAVY SNIPER", "price": 4700, "damage": 118.0, "head_multiplier": 2.0, "spread": 0.0015, "move_spread": 0.085, "range": 100.0, "magazine": 5, "reserve": 15, "fire_delay": 1.25, "reload_time": 2.25, "automatic": false, "recoil_pitch": 0.095, "recoil_yaw": 0.01, "category": "sniper"}),
		"frag": Definition.create({"key": "frag", "display_name": "FRAG", "slot": Definition.Slot.GRENADE, "price": 300, "damage": 88.0, "range": 7.0, "magazine": 1, "reserve": 0, "fire_delay": 1.0, "reload_time": 0.0, "automatic": false, "category": "frag"}),
		"smoke": Definition.create({"key": "smoke", "display_name": "SMOKE", "slot": Definition.Slot.GRENADE, "price": 300, "damage": 0.0, "range": 6.5, "magazine": 1, "reserve": 0, "fire_delay": 1.0, "reload_time": 0.0, "automatic": false, "category": "smoke"})
	}
