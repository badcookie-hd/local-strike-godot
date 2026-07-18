class_name LocalStrikeSandboxBotConfig
extends Resource

enum Team { ENEMY, ALLY }
enum Archetype { SCOUT, ASSAULT, HEAVY }
enum Behavior { AGGRESSIVE, GUARD, PASSIVE }

@export var team := Team.ENEMY
@export var archetype := Archetype.ASSAULT
@export var weapon_key := "sentinel"
@export var behavior := Behavior.AGGRESSIVE
@export_range(1, 10) var count := 1

func to_dictionary() -> Dictionary:
	return {
		"team": ["enemy", "ally"][clampi(team, 0, 1)],
		"kind": ["scout", "assault", "heavy"][clampi(archetype, 0, 2)],
		"weapon": weapon_key,
		"behavior": ["aggressive", "guard", "passive"][clampi(behavior, 0, 2)],
		"count": clampi(count, 1, 10)
	}

static func from_dictionary(data: Dictionary) -> LocalStrikeSandboxBotConfig:
	var config := LocalStrikeSandboxBotConfig.new()
	config.team = Team.ALLY if str(data.get("team", "enemy")) == "ally" else Team.ENEMY
	config.archetype = ["scout", "assault", "heavy"].find(str(data.get("kind", "assault")))
	if config.archetype < 0:
		config.archetype = Archetype.ASSAULT
	config.weapon_key = str(data.get("weapon", "sentinel"))
	config.behavior = ["aggressive", "guard", "passive"].find(str(data.get("behavior", "aggressive")))
	if config.behavior < 0:
		config.behavior = Behavior.AGGRESSIVE
	config.count = clampi(int(data.get("count", 1)), 1, 10)
	return config
