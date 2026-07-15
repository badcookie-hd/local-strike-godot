class_name LocalStrikeMatchConfig
extends Resource

enum Mode { DEFUSAL, DEATHMATCH }
enum Difficulty { RECRUIT, VETERAN, ELITE }

@export var mode := Mode.DEFUSAL
@export var map_index := 0
@export_range(2, 10) var max_players := 10
@export var fill_with_bots := true
@export var bot_difficulty := Difficulty.VETERAN
@export var server_name := "Local Strike LAN"

func duplicate_config() -> LocalStrikeMatchConfig:
	var copy := LocalStrikeMatchConfig.new()
	copy.mode = mode
	copy.map_index = map_index
	copy.max_players = max_players
	copy.fill_with_bots = fill_with_bots
	copy.bot_difficulty = bot_difficulty
	copy.server_name = server_name
	return copy
