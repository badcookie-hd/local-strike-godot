extends Node

signal config_changed(config: LocalStrikeMatchConfig)
signal roster_changed(roster: Dictionary)

var config := LocalStrikeMatchConfig.new()
var roster: Dictionary = {}
var local_player_name := "Operator"

func configure(next_config: LocalStrikeMatchConfig) -> void:
	config = next_config.duplicate_config()
	config_changed.emit(config)

func reset_roster() -> void:
	roster.clear()
	roster_changed.emit(roster)

func register_player(peer_id: int, player_name: String, team: int = -1) -> void:
	if team < 0:
		team = _least_populated_team()
	roster[peer_id] = {"name": player_name.left(20), "team": team, "kills": 0, "deaths": 0, "ping": 0}
	roster_changed.emit(roster)

func remove_player(peer_id: int) -> void:
	roster.erase(peer_id)
	roster_changed.emit(roster)

func record_kill(killer_id: int, victim_id: int) -> void:
	if roster.has(killer_id):
		roster[killer_id].kills += 1
	if roster.has(victim_id):
		roster[victim_id].deaths += 1
	roster_changed.emit(roster)

func _least_populated_team() -> int:
	var attackers := 0
	var defenders := 0
	for entry in roster.values():
		if entry.team == 0:
			attackers += 1
		else:
			defenders += 1
	return 0 if attackers <= defenders else 1
