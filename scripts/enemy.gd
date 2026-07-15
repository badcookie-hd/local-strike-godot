class_name LocalStrikeEnemy
extends CharacterBody3D

signal died(enemy: LocalStrikeEnemy, position: Vector3, enemy_kind: String)
signal shot_fired(origin: Vector3, end: Vector3, hit: bool)

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

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_apply_profile()
	_build_collision()
	_build_visual()
	_build_navigation()

func _apply_profile() -> void:
	match enemy_kind:
		"scout":
			health = 74.0
			speed = 3.25
			fire_delay = 0.66
			accuracy = 0.54
			damage_scale = 0.78
			preferred_distance = 6.0
			radius = 0.31
		"heavy":
			health = 175.0
			speed = 1.75
			fire_delay = 1.16
			accuracy = 0.70
			damage_scale = 1.35
			preferred_distance = 10.0
			radius = 0.48
		_:
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
	var head := _add_sphere(_body_root, radius * 0.62, Vector3(0, 1.53, 0), _material(Color("a98a72"), 0.72, 0.0))
	head.scale.y = 1.08
	_add_box(_body_root, Vector3(radius * 1.2, 0.13, 0.075), Vector3(0, 1.56, -radius * 0.62), visor_material)
	_add_box(_body_root, Vector3(radius * 1.3, 0.12, radius * 1.15), Vector3(0, 1.72, 0), armor_material)

	_left_leg = _add_box(_body_root, Vector3(radius * 0.52, 0.78, radius * 0.58), Vector3(-radius * 0.38, 0.42, 0), fabric_material)
	_right_leg = _add_box(_body_root, Vector3(radius * 0.52, 0.78, radius * 0.58), Vector3(radius * 0.38, 0.42, 0), fabric_material)
	_left_arm = _add_box(_body_root, Vector3(radius * 0.42, 0.66, radius * 0.44), Vector3(-radius * 1.02, 1.04, -0.05), fabric_material)
	_right_arm = _add_box(_body_root, Vector3(radius * 0.42, 0.66, radius * 0.44), Vector3(radius * 1.02, 1.04, -0.05), fabric_material)
	_left_arm.rotation_degrees.x = -18.0
	_right_arm.rotation_degrees.x = -34.0

	var gun := _add_box(_body_root, Vector3(0.13, 0.14, 0.72), Vector3(radius * 0.58, 1.03, -radius * 0.92), visor_material)
	gun.rotation_degrees.x = 4.0
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.025
	barrel_mesh.bottom_radius = 0.034
	barrel_mesh.height = 0.48
	barrel_mesh.radial_segments = 10
	barrel.mesh = barrel_mesh
	barrel.rotation_degrees.x = 90.0
	barrel.position = Vector3(radius * 0.58, 1.04, -radius * 1.7)
	barrel.material_override = visor_material
	_body_root.add_child(barrel)
	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(radius * 0.58, 1.04, -radius * 1.95)
	_body_root.add_child(_muzzle)

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
	if _dead or not is_instance_valid(target_player):
		return
	_shoot_cooldown -= delta
	_decision_timer -= delta
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	_search_timer = maxf(0.0, _search_timer - delta)
	if _hurt_timer <= 0.0:
		_torso_material.emission_enabled = false
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
	if _state == State.ENGAGE and distance < preferred_distance + 2.5:
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
	if sees_player and distance < 28.0 and _reaction_timer >= reaction_time and _shoot_cooldown <= 0.0:
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
	_shoot_cooldown = fire_delay + randf_range(0.0, 0.24)
	var origin := _muzzle.global_position
	var end := target_player.global_position + Vector3.UP * 1.15
	var chance := clampf(accuracy - distance / 70.0, 0.12, 0.9)
	var hit := randf() <= chance
	if hit:
		var zone := "head" if randf() < 0.09 * accuracy else ("limb" if randf() < 0.24 else "torso")
		var zone_scale := 1.8 if zone == "head" else (0.72 if zone == "limb" else 1.0)
		if target_player.has_method("apply_damage"):
			target_player.apply_damage(randf_range(8.0, 15.0) * damage_scale * zone_scale, zone)
		elif target_player.has_method("take_damage"):
			target_player.take_damage(randf_range(8.0, 15.0) * damage_scale * zone_scale, zone)
	else:
		end += Vector3(randf_range(-2.2, 2.2), randf_range(-1.1, 1.1), randf_range(-2.2, 2.2))
	shot_fired.emit(origin, end, hit)

func take_damage(amount: float, hit_zone := "torso") -> bool:
	if _dead:
		return false
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
		tween.tween_property(self, "scale", Vector3.ZERO, 0.25)
		tween.tween_callback(queue_free)
		return true
	return false

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
