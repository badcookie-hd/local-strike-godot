class_name LocalStrikeMapDefinition
extends Resource

@export var map_name := ""
@export var player_spawn := Vector3.ZERO
@export var palette: Dictionary = {}
@export var walls: Array = []
@export var sites: Array = []
@export var bot_spawns: Array[Vector3] = []
@export var patrols: Array[Vector3] = []
@export var props: Array = []
@export var interactables: Array = []
@export var reflection_zones: Array = []
@export var physics_props: Array = []
@export var destructibles: Array = []
@export var environment_profile := "outdoor"

static func create(data: Dictionary) -> LocalStrikeMapDefinition:
	var definition := LocalStrikeMapDefinition.new()
	definition.map_name = str(data.get("name", "UNNAMED"))
	definition.player_spawn = data.get("player_spawn", Vector3.ZERO)
	definition.palette = data.get("palette", {}).duplicate(true)
	definition.walls = data.get("walls", []).duplicate(true)
	definition.sites = data.get("sites", []).duplicate(true)
	definition.props = data.get("props", []).duplicate(true)
	definition.interactables = data.get("interactables", []).duplicate(true)
	definition.reflection_zones = data.get("reflection_zones", []).duplicate(true)
	definition.physics_props = data.get("physics_props", []).duplicate(true)
	definition.destructibles = data.get("destructibles", []).duplicate(true)
	definition.environment_profile = str(data.get("environment_profile", "outdoor"))
	for spawn in data.get("bot_spawns", []):
		definition.bot_spawns.append(spawn)
	for patrol in data.get("patrols", []):
		definition.patrols.append(patrol)
	return definition
