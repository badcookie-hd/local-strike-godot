class_name LocalStrikeEnemy
extends CharacterBody3D

const WeaponCatalog = preload("res://scripts/weapon_catalog.gd")
const Ballistics = preload("res://scripts/ballistics_manager.gd")
const MeleeResolver = preload("res://scripts/melee_resolver.gd")
const WeaponModel = preload("res://scripts/weapon_model.gd")

signal died(enemy: LocalStrikeEnemy, position: Vector3, enemy_kind: String)
signal shot_fired(origin: Vector3, end: Vector3, hit: bool)
signal melee_impact(position: Vector3, normal: Vector3, intensity: float, killed: bool)

enum State { PATROL, SEARCH, ENGAGE, OBJECTIVE }

var target_player: Node3D
var opponents: Array[Node3D] = []
var enemy_kind := "assault"
var bot_difficulty := LocalStrikeMatchConfig.Difficulty.VETERAN
var patrol_points: Array[Vector3] = []
var objective_target := Vector3.ZERO
var has_objective := false
var team := 1

var health := 100.0
var max_health := 100.0
var speed := 2.3
var fire_delay := 0.9
var accuracy := 0.62
var reaction_time := 0.34
var damage_scale := 1.0
var preferred_distance := 8.0
var radius := 0.38
var weapon_key := "ranger"
var sandbox_behavior := "aggressive"
var guard_anchor := Vector3.ZERO
var guard_radius := 5.0
var last_hit_context: Dictionary = {}

var _state := State.PATROL
var _shoot_cooldown := 1.0
var _decision_timer := 0.8
var _reaction_timer := 0.0
var _strafe_sign := 1.0
var _patrol_index := 0
var _dead := false
var _hurt_timer := 0.0
var _last_seen_position := Vector3.ZERO
var _search_timer := 0.0
var _body_root: Node3D
var _torso_material: StandardMaterial3D
var _navigation: NavigationAgent3D
var _left_leg: MeshInstance3D
var _right_leg: MeshInstance3D
var _left_arm: MeshInstance3D
var _right_arm: MeshInstance3D
var _muzzle: Marker3D
var _walk_phase := 0.0
var _configured_weapon := ""
var _held_weapon: Node3D
var _attack_anim_timer := 0.0

func configure_spawn(next_team: int, kind: String, next_weapon: String, behavior: String, anchor: Vector3) -> void:
	team = next_team
	enemy_kind = kind if kind in ["scout", "assault", "heavy"] else "assault"
	_configured_weapon = next_weapon if WeaponCatalog.all().has(next_weapon) else "sentinel"
	sandbox_behavior = behavior if behavior in ["aggressive", "guard", "passive"] else "aggressive"
	guard_anchor = anchor

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	add_to_group("damageable_actor")
	_apply_profile()
	if not _configured_weapon.is_empty():
		weapon_key = _configured_weapon
	var spec := WeaponCatalog.get_weapon(weapon_key)
	if spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE:
		preferred_distance = spec.melee_reach * 0.72
		fire_delay = spec.melee_light_recovery
	_build_collision()
	_build_visual()
	_build_navigation()

func _apply_profile() -> void:
	match enemy_kind:
		"scout":
			weapon_key = "whisper"
			health = 74.0
			speed = 3.25
			fire_delay = 0.66
			accuracy = 0.54
			damage_scale = 0.78
			preferred_distance = 6.0
			radius = 0.31
		"heavy":
			weapon_key = "bulwark"
			health = 175.0
			speed = 1.75
			fire_delay = 1.16
			accuracy = 0.70
			damage_scale = 1.35
			preferred_distance = 10.0
			radius = 0.48
		_:
			weapon_key = "sentinel"
			health = 105.0
			speed = 2.35
			fire_delay = 0.9
			accuracy = 0.63
			damage_scale = 1.0
			preferred_distance = 8.0
			radius = 0.38
	match bot_difficulty:
		LocalStrikeMatchConfig.Difficulty.RECRUIT:
			accuracy *= 0.72
			reaction_time = 0.62
		LocalStrikeMatchConfig.Difficulty.ELITE:
			accuracy = minf(0.86, accuracy * 1.2)
			reaction_time = 0.16
		_:
			reaction_time = 0.34
	max_health = health

func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = 1.55
	collision.shape = shape
	collision.position.y = 0.82
	add_child(collision)
	_add_hitbox("head", Vector3(0, 1.55, 0), Vector3(0.44, 0.38, 0.42), true)
	_add_hitbox("torso", Vector3(0, 1.02, 0), Vector3(radius * 1.7, 0.72, radius * 1.15))
	_add_hitbox("limb", Vector3(0, 0.42, 0), Vector3(radius * 1.5, 0.78, radius))

func _add_hitbox(zone: String, position: Vector3, size: Vector3, sphere := false) -> void:
	var area := Area3D.new()
	area.name = "%s_hitbox" % zone
	area.collision_layer = 4
	area.collision_mask = 0
	area.position = position
	area.set_meta("hit_zone", zone)
	var collision := CollisionShape3D.new()
	if sphere:
		var shape := SphereShape3D.new()
		shape.radius = size.x / 2.0
		collision.shape = shape
	else:
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
	area.add_child(collision)
	add_child(area)

func _build_visual() -> void:
	_body_root = Node3D.new()
	add_child(_body_root)
	_torso_material = _material(_kind_color(), 0.58, 0.08)
	var armor_material := _material(_kind_color().darkened(0.38), 0.42, 0.32)
	var fabric_material := _material(Color("252d33"), 0.86, 0.0)
	var visor_material := _material(Color("101a20"), 0.2, 0.72)

	_add_box(_body_root, Vector3(radius * 1.55, 0.58, radius * 0.92), Vector3(0, 1.04, 0), _torso_material)
	_add_box(_body_root, Vector3(radius * 1.72, 0.34, radius * 1.02), Vector3(0, 1.12, -0.015), armor_material)
	_add_box(_body_root, Vector3(radius * 1.5, 0.14, radius * 0.98), Vector3(0, 0.78, 0.02), armor_material)
	var head := _add_sphere(_body_root, radius * 0.62, Vector3(0, 1.53, 0), _material(Color("a98a72"), 0.72, 0.0))
	head.scale.y = 1.08
	_add_box(_body_root, Vector3(radius * 1.2, 0.13, 0.075), Vector3(0, 1.56, -radius * 0.62), visor_material)
	var helmet := _add_sphere(_body_root, radius * 0.67, Vector3(0, 1.68, 0.02), armor_material)
	helmet.scale.y = 0.55
	_add_box(_body_root, Vector3(radius * 0.92, 0.48, radius * 0.32), Vector3(0, 1.04, radius * 0.63), armor_material)

	_left_leg = _add_capsule(_body_root, radius * 0.29, 0.82, Vector3(-radius * 0.38, 0.42, 0), fabric_material)
	_right_leg = _add_capsule(_body_root, radius * 0.29, 0.82, Vector3(radius * 0.38, 0.42, 0), fabric_material)
	_left_arm = _add_capsule(_body_root, radius * 0.23, 0.7, Vector3(-radius * 1.02, 1.04, -0.05), fabric_material)
	_right_arm = _add_capsule(_body_root, radius * 0.23, 0.7, Vector3(radius * 1.02, 1.04, -0.05), fabric_material)
	_add_box(_body_root, Vector3(radius * 0.5, 0.16, radius * 0.56), Vector3(-radius * 0.96, 1.29, 0), armor_material)
	_add_box(_body_root, Vector3(radius * 0.5, 0.16, radius * 0.56), Vector3(radius * 0.96, 1.29, 0), armor_material)
	_left_arm.rotation_degrees.x = -18.0
	_right_arm.rotation_degrees.x = -34.0

	_held_weapon = WeaponModel.create(weapon_key)
	_held_weapon.position = Vector3(radius * 0.58, 1.03, -radius * 0.92)
	_held_weapon.scale = Vector3.ONE * (0.76 if WeaponCatalog.get_weapon(weapon_key).slot == LocalStrikeWeaponDefinition.Slot.MELEE else 0.72)
	_held_weapon.rotation_degrees = Vector3(4.0, 0.0, 0.0)
	_body_root.add_child(_held_weapon)
	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(radius * 0.58, 1.04, -radius * 1.95)
	_body_root.add_child(_muzzle)
	for x in [-0.22, 0.0, 0.22]:
		_add_box(_body_root, Vector3(0.16, 0.22, 0.09), Vector3(x, 0.92, -radius * 0.58), _material(_kind_color().lightened(0.16), 0.62, 0.08))

func _build_navigation() -> void:
	_navigation = NavigationAgent3D.new()
	_navigation.path_height_offset = 0.0
	_navigation.radius = radius
	_navigation.path_desired_distance = 0.55
	_navigation.target_desired_distance = 0.8
	_navigation.avoidance_enabled = true
	_navigation.neighbor_distance = 3.0
	add_child(_navigation)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_shoot_cooldown -= delta
	_attack_anim_timer = maxf(0.0, _attack_anim_timer - delta)
	_decision_timer -= delta
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	_search_timer = maxf(0.0, _search_timer - delta)
	if _hurt_timer <= 0.0:
		_torso_material.emission_enabled = false
	if sandbox_behavior == "passive":
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		velocity.y = velocity.y - 22.0 * delta if not is_on_floor() else -0.5
		move_and_slide()
		_animate_body(delta)
		return
	if not is_instance_valid(target_player):
		return
	if _decision_timer <= 0.0:
		_decision_timer = randf_range(0.55, 1.25)
		_select_target()
		if randf() < 0.48:
			_strafe_sign *= -1.0

	var player_position := target_player.global_position
	var distance := global_position.distance_to(player_position)
	var sees_player := _can_see_player()
	if sees_player:
		_last_seen_position = player_position
		_search_timer = 4.0
		_state = State.OBJECTIVE if has_objective else State.ENGAGE
		_reaction_timer += delta
	elif has_objective:
		_state = State.OBJECTIVE
	elif _search_timer > 0.0:
		_state = State.SEARCH
	else:
		_state = State.PATROL
		_reaction_timer = 0.0

	var target := _choose_target()
	var direction := _direction_to_target(target)
	var spec := WeaponCatalog.get_weapon(weapon_key)
	var uses_melee := spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE
	if sandbox_behavior == "guard" and global_position.distance_to(guard_anchor) > guard_radius:
		direction = _direction_to_target(guard_anchor)
	elif _state == State.ENGAGE and uses_melee:
		var melee_direction := Vector3(player_position.x - global_position.x, 0, player_position.z - global_position.z).normalized()
		direction = melee_direction if distance > spec.melee_reach * 0.72 else Vector3.ZERO
	elif _state == State.ENGAGE and distance < preferred_distance + 2.5:
		var player_direction := Vector3(player_position.x - global_position.x, 0, player_position.z - global_position.z).normalized()
		var strafe := Vector3(-player_direction.z, 0, player_direction.x) * _strafe_sign
		var retreat := -player_direction if distance < preferred_distance - 1.2 else Vector3.ZERO
		direction = (strafe * 0.85 + retreat * 0.72 + player_direction * 0.08).normalized()

	velocity.x = move_toward(velocity.x, direction.x * speed, 10.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 10.0 * delta)
	velocity.y = velocity.y - 22.0 * delta if not is_on_floor() else -0.5
	move_and_slide()
	if is_on_wall():
		_strafe_sign *= -1.0

	var look_target := player_position if sees_player else target
	if global_position.distance_squared_to(look_target) > 0.1:
		look_at(Vector3(look_target.x, global_position.y, look_target.z), Vector3.UP)
	_animate_body(delta)
	if sees_player and _reaction_timer >= reaction_time and _shoot_cooldown <= 0.0:
		if uses_melee and distance <= spec.melee_reach + 0.4:
			_melee_attack(distance)
		elif not uses_melee and distance < 28.0:
			_shoot(distance)

func _choose_target() -> Vector3:
	match _state:
		State.OBJECTIVE: return objective_target
		State.SEARCH: return _last_seen_position
		State.ENGAGE: return target_player.global_position
		_: return _patrol_target()

func _direction_to_target(target: Vector3) -> Vector3:
	var flat_target := Vector3(target.x, global_position.y, target.z)
	_navigation.target_position = flat_target
	var next := _navigation.get_next_path_position()
	if next == Vector3.ZERO or next.distance_to(global_position) < 0.05 or next.distance_to(global_position) > 30.0:
		next = flat_target
	var delta := Vector3(next.x - global_position.x, 0, next.z - global_position.z)
	return delta.normalized() if delta.length_squared() > 0.02 else Vector3.ZERO

func _patrol_target() -> Vector3:
	if patrol_points.is_empty():
		return global_position
	var point := patrol_points[_patrol_index % patrol_points.size()]
	if global_position.distance_to(point) < 1.1:
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		point = patrol_points[_patrol_index]
	return point

func _can_see_player() -> bool:
	if not is_instance_valid(target_player):
		return false
	var origin := global_position + Vector3.UP * 1.35
	var end := target_player.global_position + Vector3.UP * 1.2
	for smoke in get_tree().get_nodes_in_group("smoke_cloud"):
		if smoke.has_method("blocks_segment") and smoke.blocks_segment(origin, end):
			return false
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [get_rid()]
	query.collision_mask = 3
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return not result.is_empty() and result.collider == target_player

func _shoot(distance: float) -> void:
	var spec := WeaponCatalog.get_weapon(weapon_key)
	var uses_ads := distance > preferred_distance * 0.8
	_shoot_cooldown = maxf(fire_delay * 0.45, spec.fire_delay * (1.08 if uses_ads else 1.25)) + randf_range(0.0, 0.12)
	var origin := _muzzle.global_position
	var end := target_player.global_position + Vector3.UP * 1.15
	var chance := clampf(accuracy - distance / 85.0 + (0.12 if uses_ads else 0.0), 0.12, 0.92)
	var hit := randf() <= chance
	if hit:
		var zone := "head" if randf() < 0.09 * accuracy else ("limb" if randf() < 0.24 else "torso")
		var zone_scale := minf(2.0, spec.head_multiplier) if zone == "head" else (spec.limb_multiplier if zone == "limb" else 1.0)
		var shot_damage: float = Ballistics.damage_at_distance(spec, distance) * 0.42 * damage_scale * zone_scale
		if target_player.has_method("apply_damage"):
			target_player.apply_damage(shot_damage, zone)
		elif target_player.has_method("take_damage"):
			target_player.take_damage(shot_damage, zone)
	else:
		end += Vector3(randf_range(-2.2, 2.2), randf_range(-1.1, 1.1), randf_range(-2.2, 2.2))
	shot_fired.emit(origin, end, hit)

func _melee_attack(distance: float) -> void:
	var spec := WeaponCatalog.get_weapon(weapon_key)
	var heavy := distance < spec.melee_reach * 0.58 and randf() < 0.32
	_shoot_cooldown = spec.melee_heavy_recovery if heavy else spec.melee_light_recovery
	_attack_anim_timer = _shoot_cooldown
	var origin := global_position + Vector3.UP * 1.12
	var direction := (target_player.global_position + Vector3.UP - origin).normalized()
	var result := MeleeResolver.resolve_attack(get_world_3d().direct_space_state, origin, direction, spec, [get_rid()], heavy)
	for hit in result.hits:
		var target: Object = hit.target
		if not opponents.has(target):
			continue
		var context := {"source": "melee", "weapon": weapon_key, "heavy": heavy, "direction": direction, "impulse": hit.impulse, "blood_intensity": hit.blood_intensity}
		var killed := false
		if target.has_method("take_damage"):
			killed = bool(target.take_damage(float(hit.damage) * damage_scale, str(hit.zone), context))
		elif target.has_method("apply_damage"):
			target.apply_damage(float(hit.damage) * damage_scale, str(hit.zone), context)
			killed = float(target.get("health")) <= 0.0
		if target.has_method("apply_gameplay_impulse"):
			target.apply_gameplay_impulse(direction * float(hit.impulse), hit.position - target.global_position)
		_stain_held_weapon(float(hit.blood_intensity) * 0.16)
		melee_impact.emit(hit.position, hit.normal, float(hit.blood_intensity), killed)

func clear_weapon_blood() -> void:
	if not is_instance_valid(_held_weapon):
		return
	var old_position := _held_weapon.position
	var old_rotation := _held_weapon.rotation
	var old_scale := _held_weapon.scale
	_held_weapon.queue_free()
	_held_weapon = WeaponModel.create(weapon_key, 0.0)
	_held_weapon.position = old_position
	_held_weapon.rotation = old_rotation
	_held_weapon.scale = old_scale
	_body_root.add_child(_held_weapon)

func _stain_held_weapon(amount: float) -> void:
	if not is_instance_valid(_held_weapon):
		return
	for child in _held_weapon.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null:
			continue
		var material := mesh_instance.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = material.albedo_color.lerp(Color("5a1118"), clampf(amount, 0.0, 0.5))

func take_damage(amount: float, hit_zone := "torso", context := {}) -> bool:
	if _dead:
		return false
	last_hit_context = context.duplicate(true) if context is Dictionary else {}
	health -= amount
	_hurt_timer = 0.14
	_search_timer = 4.0
	_last_seen_position = target_player.global_position if is_instance_valid(target_player) else global_position
	_torso_material.emission_enabled = true
	_torso_material.emission = Color("ff3f3f") * (1.5 if hit_zone == "head" else 0.8)
	if health <= 0.0:
		_dead = true
		collision_layer = 0
		died.emit(self, global_position, enemy_kind)
		var tween := create_tween()
		tween.tween_property(_body_root, "rotation_degrees", Vector3(82, randf_range(-20, 20), randf_range(-18, 18)), 0.24)
		tween.parallel().tween_property(_body_root, "position:y", 0.2, 0.24)
		tween.tween_interval(1.4)
		tween.tween_property(self, "scale", Vector3.ONE * 0.001, 0.25)
		tween.tween_callback(queue_free)
		return true
	return false

func apply_gameplay_impulse(impulse: Vector3, _at_position := Vector3.ZERO) -> void:
	velocity += impulse * (0.12 if enemy_kind == "heavy" else 0.2)
	velocity.y = maxf(velocity.y, impulse.y * 0.12)

func hear_noise(position: Vector3, loudness := 1.0) -> void:
	if global_position.distance_to(position) <= 15.0 * loudness and _state != State.ENGAGE:
		_last_seen_position = position
		_search_timer = 3.5
		_state = State.SEARCH

func set_opponents(next_opponents: Array[Node3D]) -> void:
	opponents = next_opponents
	_select_target()

func _select_target() -> void:
	var best: Node3D
	var best_distance := INF
	for candidate in opponents:
		if not is_instance_valid(candidate) or candidate == self:
			continue
		var candidate_health = candidate.get("health")
		if candidate_health != null and float(candidate_health) <= 0.0:
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	if is_instance_valid(best):
		target_player = best

func set_objective(position: Vector3, active: bool) -> void:
	objective_target = position
	has_objective = active

func _animate_body(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	_walk_phase += delta * horizontal_speed * 4.2
	var swing := sin(_walk_phase) * minf(28.0, horizontal_speed * 9.0)
	_left_leg.rotation_degrees.x = swing
	_right_leg.rotation_degrees.x = -swing
	_left_arm.rotation_degrees.x = -18.0 - swing * 0.38
	_right_arm.rotation_degrees.x = -34.0 + swing * 0.22
	if _attack_anim_timer > 0.0:
		var attack_swing := sin((_attack_anim_timer / maxf(0.01, fire_delay)) * PI) * 72.0
		_right_arm.rotation_degrees.x -= attack_swing
		if is_instance_valid(_held_weapon):
			_held_weapon.rotation_degrees.z = attack_swing * 0.8
	elif is_instance_valid(_held_weapon):
		_held_weapon.rotation_degrees.z = lerpf(_held_weapon.rotation_degrees.z, 0.0, minf(1.0, delta * 12.0))
	_body_root.position.y = absf(sin(_walk_phase * 2.0)) * 0.018 if horizontal_speed > 0.15 else 0.0

func _kind_color() -> Color:
	if team == 0:
		match enemy_kind:
			"scout": return Color("3f7f86")
			"heavy": return Color("405a78")
			_: return Color("365f70")
	match enemy_kind:
		"scout": return Color("c98242")
		"heavy": return Color("7e546f")
		_: return Color("8f3f43")

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _add_box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

func _add_sphere(parent: Node3D, radius_value: float, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius_value
	mesh.height = radius_value * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance

func _add_capsule(parent: Node3D, radius_value: float, height: float, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius_value
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
	return mesh_instance
