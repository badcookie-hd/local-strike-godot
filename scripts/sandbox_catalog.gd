class_name LocalStrikeSandboxCatalog
extends RefCounted

const ItemDefinition = preload("res://scripts/sandbox_item_definition.gd")
const WeaponCatalog = preload("res://scripts/weapon_catalog.gd")
const WeaponModel = preload("res://scripts/weapon_model.gd")

const BOT_SCENES := {
	"scout": "res://assets/models/quaternius/modular_men/Punk.gltf",
	"assault": "res://assets/models/quaternius/modular_men/Worker.gltf",
	"heavy": "res://assets/models/quaternius/modular_men/Swat.gltf"
}

static func build() -> Array[LocalStrikeSandboxItemDefinition]:
	var items: Array[LocalStrikeSandboxItemDefinition] = []
	items.append(_bot_item("scout", "SCOUT", "Fast flanker", Vector3(0.62, 1.72, 0.62)))
	items.append(_bot_item("assault", "ASSAULT", "Balanced fighter", Vector3(0.76, 1.82, 0.7)))
	items.append(_bot_item("heavy", "HEAVY", "Armored enforcer", Vector3(0.96, 1.96, 0.82)))

	for key in WeaponCatalog.sandbox_weapon_keys():
		var spec := WeaponCatalog.get_weapon(key)
		var category := "Weapons"
		if spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE:
			category = "Melee"
		elif spec.slot == LocalStrikeWeaponDefinition.Slot.GRENADE:
			category = "Grenades"
		items.append(_item("weapon_%s" % key, spec.display_name, _weapon_description(spec), category, ItemDefinition.Kind.WEAPON, {
			"weapon_key": key,
			"scene_path": str(WeaponModel.EXTERNAL_MODELS.get(key, "")),
			"preview_size": _weapon_preview_size(spec),
			"placement_height": 0.28,
			"max_per_action": 10,
			"placement_rules": {"requires_floor": true, "pickup": true},
			"default_options": {"count": 1}
		}))

	items.append(_item("prop_wood_crate", "WOOD CRATE", "Breakable cover", "Props", ItemDefinition.Kind.PROP, {"surface_type": "wood", "preview_size": Vector3(1.15, 1.15, 1.15), "placement_height": 0.575, "max_per_action": 8}))
	items.append(_item("prop_metal_case", "METAL CASE", "Heavy movable cover", "Props", ItemDefinition.Kind.PROP, {"surface_type": "metal", "preview_size": Vector3(1.5, 0.82, 0.9), "placement_height": 0.41, "max_per_action": 8}))
	items.append(_item("prop_barrel", "FUEL BARREL", "Explosive physics barrel", "Props", ItemDefinition.Kind.PROP, {"surface_type": "barrel", "preview_size": Vector3(0.72, 1.12, 0.72), "placement_height": 0.56, "max_per_action": 8}))
	items.append(_item("prop_tool_cart", "TOOL CART", "Mobile workshop cover", "Props", ItemDefinition.Kind.PROP, {"surface_type": "tool_cart", "preview_size": Vector3(1.4, 1.05, 0.72), "placement_height": 0.525, "max_per_action": 4}))

	for action in [
		["god_mode", "GOD MODE", "Toggle invulnerability"],
		["slow_motion", "SLOW MOTION", "Toggle cinematic time"],
		["explosion", "FORCE BLAST", "Create a physical explosion"],
		["remove_target", "REMOVE TARGET", "Delete the aimed sandbox object"],
		["clear_npcs", "CLEAR BOTS", "Remove all spawned bots"],
		["clear_weapons", "CLEAR WEAPONS", "Remove all dropped weapons"],
		["clear_props", "CLEAR PROPS", "Remove all spawned props"],
		["clear_blood", "CLEAR BLOOD + BODIES", "Clean persistent effects"],
		["clear", "CLEAR ALL", "Remove every sandbox spawn"],
		["reset", "RESET FOUNDRY", "Restore the complete sandbox"]
	]:
		items.append(_item("world_%s" % action[0], action[1], action[2], "World", ItemDefinition.Kind.WORLD, {"world_action": action[0]}))
	return items

static func _item(id: String, display_name: String, description: String, category: String, kind: int, extra: Dictionary) -> LocalStrikeSandboxItemDefinition:
	var data := extra.duplicate(true)
	data.merge({"id": id, "display_name": display_name, "description": description, "category": category, "kind": kind})
	return ItemDefinition.create(data)

static func _bot_item(kind: String, display_name: String, description: String, size: Vector3) -> LocalStrikeSandboxItemDefinition:
	return _item("bot_%s" % kind, display_name, description, "Bots", ItemDefinition.Kind.BOT, {
		"bot_kind": kind,
		"scene_path": BOT_SCENES[kind],
		"preview_size": size,
		"max_per_action": 10,
		"placement_rules": {"requires_floor": true, "requires_navigation": true, "formation_spacing": 1.15},
		"default_options": {"team": "enemy", "kind": kind, "weapon": "sentinel", "behavior": "aggressive", "count": 1}
	})

static func _weapon_description(spec: LocalStrikeWeaponDefinition) -> String:
	if spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE:
		return "%d light / %d heavy damage" % [roundi(spec.melee_light_damage), roundi(spec.melee_heavy_damage)]
	if spec.slot == LocalStrikeWeaponDefinition.Slot.GRENADE:
		return "Throwable tactical equipment"
	return "%d damage  |  %d round magazine" % [roundi(spec.damage), spec.magazine]

static func _weapon_preview_size(spec: LocalStrikeWeaponDefinition) -> Vector3:
	if spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE:
		return Vector3(0.35, 0.25, 1.25)
	if spec.slot == LocalStrikeWeaponDefinition.Slot.GRENADE:
		return Vector3(0.34, 0.34, 0.34)
	return Vector3(0.45, 0.34, 1.45) if spec.slot == LocalStrikeWeaponDefinition.Slot.PRIMARY else Vector3(0.36, 0.28, 0.72)
