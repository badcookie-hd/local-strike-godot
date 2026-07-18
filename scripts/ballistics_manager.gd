class_name LocalStrikeBallisticsManager
extends RefCounted

const SurfaceProfile = preload("res://scripts/surface_profile.gd")
const MAX_PENETRATIONS := 3
const MAX_RICOCHETS := 1

static func damage_at_distance(spec: LocalStrikeWeaponDefinition, distance: float) -> float:
	if distance <= spec.falloff_start:
		return spec.damage
	var span := maxf(0.01, spec.falloff_end - spec.falloff_start)
	var factor := clampf((distance - spec.falloff_start) / span, 0.0, 1.0)
	return spec.damage * lerpf(1.0, spec.minimum_damage_multiplier, factor)

static func deterministic_spread(spec: LocalStrikeWeaponDefinition, sequence: int, pellet: int, amount: float) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sequence * 104729 + pellet * 7919 + abs(hash(spec.key)))
	return Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount))

static func recoil_for(spec: LocalStrikeWeaponDefinition, sequence: int) -> Vector2:
	if spec.recoil_pattern.is_empty():
		return Vector2(spec.recoil_yaw, spec.recoil_pitch)
	return spec.recoil_pattern[sequence % spec.recoil_pattern.size()]

static func resolve_shot(
	space_state: PhysicsDirectSpaceState3D,
	origin: Vector3,
	direction: Vector3,
	spec: LocalStrikeWeaponDefinition,
	excluded_rids: Array[RID],
	sequence: int
) -> Dictionary:
	var result := {"sequence": sequence, "segments": [], "hits": [], "penetrations": 0, "ricochets": 0}
	var ray_origin := origin
	var ray_direction := direction.normalized()
	var remaining_range := spec.range
	var penetration_power := spec.penetration_power
	var damage_scale := 1.0
	var traveled := 0.0
	var exclusions := excluded_rids.duplicate()
	for step in range(MAX_PENETRATIONS + MAX_RICOCHETS + 2):
		if remaining_range <= 0.05:
			break
		var ray_end := ray_origin + ray_direction * remaining_range
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		query.exclude = exclusions
		query.collision_mask = 5
		query.collide_with_areas = true
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			result.segments.append({"from": ray_origin, "to": ray_end, "surface": "air"})
			break
		var hit_position: Vector3 = hit.position
		var hit_normal: Vector3 = hit.normal
		var collider: Object = hit.collider
		var target: Object = collider.get_parent() if collider is Area3D else collider
		var actor_hit: bool = target is Node and target.is_in_group("damageable_actor")
		var surface: String = "flesh" if actor_hit else str(collider.get_meta("surface_type", "concrete"))
		if not actor_hit and target != null:
			surface = str(target.get_meta("surface_type", surface))
		var segment_distance := ray_origin.distance_to(hit_position)
		traveled += segment_distance
		remaining_range -= segment_distance
		result.segments.append({"from": ray_origin, "to": hit_position, "surface": surface, "normal": hit_normal})
		var zone := str(collider.get_meta("hit_zone", "torso"))
		var damage := damage_at_distance(spec, traveled) * damage_scale
		if zone == "head":
			damage *= spec.head_multiplier
		elif zone == "limb":
			damage *= spec.limb_multiplier
		result.hits.append({"target": target, "position": hit_position, "normal": hit_normal, "surface": surface, "zone": zone, "damage": damage, "armor_penetration": spec.armor_penetration, "actor": actor_hit})
		if actor_hit:
			break
		var profile: Dictionary = SurfaceProfile.get_profile(surface)
		var incidence := absf(ray_direction.dot(hit_normal.normalized()))
		if profile.ricochet_threshold > 0.0 and incidence < profile.ricochet_threshold and int(result.ricochets) < MAX_RICOCHETS:
			result.ricochets = int(result.ricochets) + 1
			ray_direction = ray_direction.bounce(hit_normal).normalized()
			damage_scale *= 0.52
			ray_origin = hit_position + hit_normal * 0.035
			continue
		if penetration_power <= profile.penetration_resistance or int(result.penetrations) >= MAX_PENETRATIONS:
			break
		penetration_power -= profile.penetration_resistance
		damage_scale *= profile.damage_retention
		result.penetrations = int(result.penetrations) + 1
		if collider is CollisionObject3D:
			exclusions.append(collider.get_rid())
		ray_origin = hit_position + ray_direction * profile.exit_offset
		remaining_range -= profile.exit_offset
	return result

static func network_result(result: Dictionary) -> Dictionary:
	var clean_hits := []
	for hit in result.get("hits", []):
		clean_hits.append({
			"position": hit.position,
			"normal": hit.normal,
			"surface": hit.surface,
			"zone": hit.zone,
			"damage": hit.damage,
			"actor": hit.actor
		})
	return {
		"sequence": result.get("sequence", 0),
		"segments": result.get("segments", []),
		"hits": clean_hits,
		"penetrations": result.get("penetrations", 0),
		"ricochets": result.get("ricochets", 0)
	}
