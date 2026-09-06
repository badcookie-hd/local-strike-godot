class_name LocalStrikeArsenalRules
extends RefCounted

const WEAPONS: Array[String] = ["kestrel", "smg", "ranger", "bulwark", "doublebarrel", "longbow", "vanguard", "knife"]
const KILLS_PER_STAGE := 3
const SCORE_LIMIT := 24

static func stage_for_score(score: int) -> int:
	return clampi(floori(float(score) / KILLS_PER_STAGE), 0, WEAPONS.size() - 1)

static func weapon_for_score(score: int) -> String:
	return WEAPONS[stage_for_score(score)]

static func progress_text(score: int) -> String:
	if score >= SCORE_LIMIT:
		return "ALL 8 STAGES COMPLETE"
	return "STAGE %d/%d  -  %d/%d" % [stage_for_score(score) + 1, WEAPONS.size(), mini(score % KILLS_PER_STAGE, KILLS_PER_STAGE), KILLS_PER_STAGE]
