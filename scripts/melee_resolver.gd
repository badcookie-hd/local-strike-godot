class_name LocalStrikeMeleeResolver
extends RefCounted

static func resolve_attack(
	space_state: PhysicsDirectSpaceState3D,
	origin: Vector3,
	direction: Vector3,
	spec: LocalStrikeWeaponDefinition,
	exclude: Array[RID],
	heavy: bool
) -> Dictionary:
	var forward := direction.normalized()
	var reach := maxf(0.6, spec.melee_reach)
	var shape := SphereShape3D.new()
	shape.radius = reach * 0.68
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, origin + forward * reach * 0.56)
	query.collision_mask = 7
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = exclude
	var candidates: Array[Dictionary] = []
	var seen: Dictionary = {}
	var minimum_dot := cos(deg_to_rad(spec.melee_arc_degrees * 0.5))
	for result in space_state.intersect_shape(query, 64):
		var collider: Object = result.get("collider")
		var target := find_damage_target(collider)
		if target == null or seen.has(target.get_instance_id()):
			continue
		var hit_node := collider as Node3D
		var target_node := target as Node3D
		var hit_position := hit_node.global_position if hit_node != null else target_node.global_position + Vector3.UP
		var offset := hit_position - origin
		var distance := offset.length()
		if distance > reach + 0.35 or distance < 0.05 or forward.dot(offset / distance) < minimum_dot:
			continue
		if not _has_line_of_sight(space_state, origin, hit_position, target, exclude):
			continue
		seen[target.get_instance_id()] = true
		candidates.append({
			"target": target,
			"position": hit_position,
			"normal": -forward,
			"zone": str(collider.get_meta("hit_zone", "torso")) if collider is Node else "torso",
			"distance": distance
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.distance) < float(b.distance))
	var hit_count := mini(spec.melee_max_targets, candidates.size())
	var damage := spec.melee_heavy_damage if heavy else spec.melee_light_damage
	var hits: Array[Dictionary] = []
	for index in range(hit_count):
		var candidate: Dictionary = candidates[index]
		var zone_scale := 1.35 if candidate.zone == "head" else (0.78 if candidate.zone == "limb" else 1.0)
		candidate["damage"] = damage * zone_scale
		candidate["impulse"] = spec.melee_impulse * (1.45 if heavy else 1.0)
		candidate["blood_intensity"] = spec.blood_multiplier * (1.45 if heavy else 1.0)
		hits.append(candidate)
	return {"hits": hits, "heavy": heavy, "weapon": spec.key}

static func network_result(result: Dictionary) -> Dictionary:
	var clean_hits: Array[Dictionary] = []
	for hit in result.get("hits", []):
		clean_hits.append({
			"position": hit.position,
			"normal": hit.normal,
			"zone": hit.zone,
			"blood_intensity": hit.blood_intensity,
			"killed": hit.get("killed", false),
			"actor_hit": hit.get("actor_hit", true),
			"surface": hit.get("surface", "flesh")
		})
	return {"hits": clean_hits, "heavy": result.get("heavy", false), "weapon": result.get("weapon", "knife")}

static func find_damage_target(collider: Object) -> Object:
	var node := collider as Node
	while node != null:
		if node.has_method("take_damage") or node.has_method("apply_damage"):
			return node
		node = node.get_parent()
	return null

static func _has_line_of_sight(
	space_state: PhysicsDirectSpaceState3D,
	origin: Vector3,
	target_position: Vector3,
	target: Object,
	exclude: Array[RID]
) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(origin, target_position)
	ray.collision_mask = 1
	ray.exclude = exclude
	var hit := space_state.intersect_ray(ray)
	return hit.is_empty() or hit.get("collider") == target
