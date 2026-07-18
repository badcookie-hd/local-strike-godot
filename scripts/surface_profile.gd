class_name LocalStrikeSurfaceProfile
extends Resource

@export var key := "concrete"
@export var penetration_resistance := 1.2
@export var damage_retention := 0.58
@export var ricochet_threshold := 0.18
@export var friction := 0.75
@export var bounce := 0.08
@export var exit_offset := 0.18
@export var impact_effect := "dust"
@export var footstep_volume := 1.0

static var _profiles: Dictionary = {}

static func get_profile(surface_key: String):
	if _profiles.is_empty():
		_build_profiles()
	return _profiles.get(surface_key, _profiles["concrete"])

static func all() -> Dictionary:
	if _profiles.is_empty():
		_build_profiles()
	return _profiles

static func _build_profiles() -> void:
	_profiles = {
		"glass": _make("glass", 0.12, 0.88, 0.0, 0.42, 0.18, 0.08, "shards", 0.9),
		"wood": _make("wood", 0.38, 0.76, 0.04, 0.72, 0.08, 0.16, "splinters", 0.92),
		"drywall": _make("drywall", 0.24, 0.81, 0.0, 0.7, 0.04, 0.14, "dust", 0.85),
		"metal": _make("metal", 1.05, 0.5, 0.3, 0.52, 0.28, 0.12, "sparks", 1.15),
		"concrete": _make("concrete", 1.35, 0.42, 0.2, 0.82, 0.05, 0.12, "dust", 1.0),
		"snow": _make("snow", 0.08, 0.94, 0.0, 0.94, 0.0, 0.1, "snow", 0.55),
		"ice": _make("ice", 0.22, 0.86, 0.24, 0.08, 0.34, 0.1, "ice", 0.82),
		"flesh": _make("flesh", 0.0, 1.0, 0.0, 0.8, 0.0, 0.05, "blood", 1.0)
	}

static func _make(
	profile_key: String,
	resistance: float,
	retention: float,
	ricochet: float,
	friction_value: float,
	bounce_value: float,
	exit_distance: float,
	effect: String,
	step_volume: float
):
	return {
		"key": profile_key,
		"penetration_resistance": resistance,
		"damage_retention": retention,
		"ricochet_threshold": ricochet,
		"friction": friction_value,
		"bounce": bounce_value,
		"exit_offset": exit_distance,
		"impact_effect": effect,
		"footstep_volume": step_volume
	}
