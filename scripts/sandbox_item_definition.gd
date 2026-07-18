class_name LocalStrikeSandboxItemDefinition
extends Resource

enum Kind { BOT, WEAPON, PROP, WORLD }

@export var id: StringName = &""
@export var display_name := ""
@export var description := ""
@export var category := ""
@export var kind := Kind.PROP
@export var preview_image: Texture2D
@export_file("*.tscn", "*.fbx", "*.gltf", "*.glb") var scene_path := ""
@export var placement_rules: Dictionary = {}
@export var default_options: Dictionary = {}
@export var weapon_key := ""
@export var bot_kind := ""
@export var surface_type := ""
@export var world_action := ""
@export var preview_size := Vector3.ONE
@export var placement_height := 0.0
@export var max_per_action := 1

static func create(data: Dictionary) -> LocalStrikeSandboxItemDefinition:
	var definition := LocalStrikeSandboxItemDefinition.new()
	definition.id = StringName(data.get("id", ""))
	definition.display_name = str(data.get("display_name", definition.id))
	definition.description = str(data.get("description", ""))
	definition.category = str(data.get("category", "Props"))
	definition.kind = int(data.get("kind", Kind.PROP))
	definition.preview_image = data.get("preview_image")
	definition.scene_path = str(data.get("scene_path", ""))
	definition.placement_rules = data.get("placement_rules", {}).duplicate(true)
	definition.default_options = data.get("default_options", {}).duplicate(true)
	definition.weapon_key = str(data.get("weapon_key", ""))
	definition.bot_kind = str(data.get("bot_kind", ""))
	definition.surface_type = str(data.get("surface_type", ""))
	definition.world_action = str(data.get("world_action", ""))
	definition.preview_size = data.get("preview_size", Vector3.ONE)
	definition.placement_height = float(data.get("placement_height", 0.0))
	definition.max_per_action = maxi(1, int(data.get("max_per_action", 1)))
	return definition
