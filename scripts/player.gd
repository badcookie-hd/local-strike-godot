class_name LocalStrikePlayer
extends CharacterBody3D

signal shot_fired(origin: Vector3, end: Vector3, hit: bool, normal: Vector3, surface_type: String, actor_hit: bool)
signal shot_requested(sequence: int, origin: Vector3, direction: Vector3, weapon_key: String, fire_mode: String)
signal melee_attack_requested(sequence: int, origin: Vector3, direction: Vector3, weapon_key: String, heavy: bool)
signal stats_changed
signal hit_confirmed(killed: bool)
signal player_died
signal grenade_thrown(origin: Vector3, impulse: Vector3, grenade_kind: String)
signal reload_requested(weapon_key: String)
signal damage_taken(amount: float)
signal footstep(position: Vector3)

const WeaponCatalog = preload("res://scripts/weapon_catalog.gd")
const WeaponModel = preload("res://scripts/weapon_model.gd")
const Ballistics = preload("res://scripts/ballistics_manager.gd")
const SurfaceProfile = preload("res://scripts/surface_profile.gd")

const GRAVITY := 22.0
const JUMP_VELOCITY := 7.6
const COYOTE_TIME := 0.12
const JUMP_BUFFER_TIME := 0.14
const CAMERA_HEIGHT := 1.62

var health := 100.0
var armor := 35.0
var money := 800
var stamina := 100.0
var weapon_key := "sidearm"
var primary_key := ""
var secondary_key := "sidearm"
var melee_key := "knife"
var grenade_key := ""
var inventory := {"knife": true, "sidearm": true}
var ammo_state: Dictionary = {}
var ammo := 12
var reserve_ammo := 36
var enabled := true
var authoritative_damage := true
var invulnerable := false
var unlimited_ammo := false
var allow_melee_drop := false
var helmet := true
var crouching := false
var aiming := false
var fire_mode := "auto"
var combat_input_blocked := false

var _yaw := 0.0
var _pitch := 0.0
var _fire_cooldown := 0.0
var _reload_timer := 0.0
var _reloading := false
var _camera: Camera3D
var _weapon_root: Node3D
var _weapon_body: MeshInstance3D
var _barrel: MeshInstance3D
var _grip: MeshInstance3D
var _sight: MeshInstance3D
var _accent: MeshInstance3D
var _left_hand: MeshInstance3D
var _right_hand: MeshInstance3D
var _left_forearm: MeshInstance3D
var _right_forearm: MeshInstance3D
var _muzzle: Marker3D
var _muzzle_flash: MeshInstance3D
var _muzzle_light: OmniLight3D
var _muzzle_flash_timer := 0.0
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _landing_kick := 0.0
var _move_time := 0.0
var _weapon_sway := Vector2.ZERO
var _footstep_timer := 0.0
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _shot_sequence := 0
var _floor_surface := "concrete"
var _equip_timer := 0.0
var _melee_anim_timer := 0.0
var _melee_anim_duration := 0.0
var _melee_heavy := false
var _melee_swing_sign := 1.0
var _base_weapon_color := Color("303943")
var _imported_weapon_model: Node3D
var weapon_blood: Dictionary = {}

func _ready() -> void:
	collision_layer = 1
	collision_mask = 3
	add_to_group("damageable_actor")
	_build_body()
	_initialize_inventory()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_body() -> void:
	_collision = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.36
	_capsule.height = 1.55
	_collision.shape = _capsule
	_collision.position.y = 0.82
	add_child(_collision)

	_camera = Camera3D.new()
	_camera.position = Vector3(0, CAMERA_HEIGHT, 0)
	_camera.current = true
	_camera.fov = 74.0
	add_child(_camera)
	var viewmodel_light := OmniLight3D.new()
	viewmodel_light.position = Vector3(0.35, -0.05, -0.28)
	viewmodel_light.light_color = Color("c7e2e4")
	viewmodel_light.light_energy = 1.35
	viewmodel_light.omni_range = 2.4
	viewmodel_light.shadow_enabled = false
	viewmodel_light.light_cull_mask = 2
	_camera.add_child(viewmodel_light)

	_weapon_root = Node3D.new()
	_weapon_root.position = Vector3(0.23, -0.27, -0.48)
	_camera.add_child(_weapon_root)

	_weapon_body = MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.18, 0.16, 0.68)
	_weapon_body.mesh = body_mesh
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color("303943")
	body_material.metallic = 0.55
	body_material.roughness = 0.34
	_weapon_body.material_override = body_material
	_weapon_root.add_child(_weapon_body)

	_barrel = MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.038
	barrel_mesh.bottom_radius = 0.048
	barrel_mesh.height = 0.52
	barrel_mesh.radial_segments = 12
	_barrel.mesh = barrel_mesh
	_barrel.position = Vector3(0, 0.01, -0.48)
	_barrel.rotation_degrees.x = 90.0
	_barrel.material_override = body_material
	_weapon_root.add_child(_barrel)

	_grip = MeshInstance3D.new()
	var grip_mesh := BoxMesh.new()
	grip_mesh.size = Vector3(0.12, 0.28, 0.16)
	_grip.mesh = grip_mesh
	_grip.position = Vector3(0, -0.17, 0.12)
	_grip.rotation_degrees.x = -12.0
	_grip.material_override = body_material
	_weapon_root.add_child(_grip)

	_sight = MeshInstance3D.new()
	var sight_mesh := BoxMesh.new()
	sight_mesh.size = Vector3(0.065, 0.055, 0.16)
	_sight.mesh = sight_mesh
	_sight.position = Vector3(0, 0.105, -0.12)
	_sight.material_override = body_material
	_weapon_root.add_child(_sight)

	_accent = MeshInstance3D.new()
	var accent_mesh := BoxMesh.new()
	accent_mesh.size = Vector3(0.08, 0.05, 0.24)
	_accent.mesh = accent_mesh
	_accent.position = Vector3(0.11, 0.08, -0.08)
	var accent_material := StandardMaterial3D.new()
	accent_material.albedo_color = Color("f3b447")
	accent_material.emission_enabled = true
	accent_material.emission = Color("6b3b0c")
	_accent.material_override = accent_material
	_weapon_root.add_child(_accent)

	_left_hand = _create_gloved_arm(Vector3(-0.2, -0.19, -0.18), -18.0)
	_right_hand = _create_gloved_arm(Vector3(0.12, -0.22, 0.11), -8.0)
	_left_forearm = _create_forearm()
	_right_forearm = _create_forearm()

	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(0, 0, -0.76)
	_weapon_root.add_child(_muzzle)

	_muzzle_flash = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.085
	flash_mesh.height = 0.28
	flash_mesh.radial_segments = 8
	flash_mesh.rings = 4
	_muzzle_flash.mesh = flash_mesh
	_muzzle_flash.scale = Vector3(1.0, 0.55, 1.8)
	var flash_material := StandardMaterial3D.new()
	flash_material.albedo_color = Color("ffe2a3")
	flash_material.emission_enabled = true
	flash_material.emission = Color("ff9a3d") * 4.0
	_muzzle_flash.material_override = flash_material
	_muzzle_flash.visible = false
	_muzzle.add_child(_muzzle_flash)

	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color("ffb65c")
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 4.5
	_muzzle_light.shadow_enabled = false
	_muzzle.add_child(_muzzle_light)
	_set_viewmodel_layers(_weapon_root)

func _create_gloved_arm(position: Vector3, rotation_z: float) -> MeshInstance3D:
	var arm := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.09, 0.115, 0.105)
	arm.mesh = mesh
	arm.position = position
	arm.rotation_degrees = Vector3(10, 0, rotation_z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("20282e")
	material.roughness = 0.84
	arm.material_override = material
	_weapon_root.add_child(arm)
	return arm

func _create_forearm() -> MeshInstance3D:
	var arm := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.052
	mesh.height = 0.4
	mesh.radial_segments = 12
	mesh.rings = 4
	arm.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("35423a")
	material.roughness = 0.95
	arm.material_override = material
	_weapon_root.add_child(arm)
	return arm

func _pose_viewmodel_hands(spec: LocalStrikeWeaponDefinition) -> void:
	_right_hand.position = Vector3(0, -0.012, 0.015)
	_right_hand.rotation_degrees = Vector3(10, 0, -5)
	_left_hand.position = Vector3(_imported_weapon_model.get_meta("support")) * 0.82 + Vector3(-0.02, -0.025, 0)
	_left_hand.rotation_degrees = Vector3(-8, 0, 15)
	_left_hand.visible = spec.slot in [LocalStrikeWeaponDefinition.Slot.PRIMARY, LocalStrikeWeaponDefinition.Slot.SECONDARY]
	_left_forearm.visible = _left_hand.visible
	_pose_forearm(_right_forearm, Vector3(0.23, -0.32, 0.4), _right_hand.position)
	_pose_forearm(_left_forearm, Vector3(-0.38, -0.30, 0.32), _left_hand.position)
	_muzzle.position = Vector3(_imported_weapon_model.get_meta("muzzle")) * 0.82

func _pose_forearm(arm: MeshInstance3D, elbow: Vector3, wrist: Vector3) -> void:
	var direction := wrist - elbow
	(arm.mesh as CapsuleMesh).height = direction.length()
	arm.position = (elbow + wrist) * 0.5
	arm.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))

func _set_viewmodel_layers(node: Node) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		geometry.layers = 2
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_set_viewmodel_layers(child)

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0022
		_pitch = clamp(_pitch - event.relative.y * 0.0018, -1.35, 1.35)
		_weapon_sway += Vector2(event.relative.x, event.relative.y) * 0.00022
		_weapon_sway = _weapon_sway.limit_length(0.025)
		rotation.y = _yaw
		_camera.rotation.x = _pitch
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not combat_input_blocked and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _initialize_inventory() -> void:
	for key in inventory:
		var spec := WeaponCatalog.get_weapon(key)
		ammo_state[key] = {"ammo": spec.magazine, "reserve": spec.reserve}
	equip_weapon("sidearm", false)

func _physics_process(delta: float) -> void:
	if not enabled:
		velocity = Vector3.ZERO
		return

	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_equip_timer = maxf(0.0, _equip_timer - delta)
	_melee_anim_timer = maxf(0.0, _melee_anim_timer - delta)
	_muzzle_flash_timer = maxf(0.0, _muzzle_flash_timer - delta)
	if _muzzle_flash_timer <= 0.0:
		_muzzle_flash.visible = false
		_muzzle_light.light_energy = 0.0
	if _reloading:
		_reload_timer -= delta
		_weapon_root.rotation.z = sin(_reload_timer * 13.0) * 0.16
		if _reload_timer <= 0.0:
			_finish_reload()

	if not combat_input_blocked and Input.is_action_just_pressed("reload"):
		begin_reload()
	if not combat_input_blocked and Input.is_action_just_pressed("fire_mode"):
		cycle_fire_mode()
	if not combat_input_blocked and Input.is_action_just_pressed("select_primary") and not primary_key.is_empty():
		equip_weapon(primary_key)
	elif not combat_input_blocked and Input.is_action_just_pressed("select_secondary"):
		equip_weapon(secondary_key)
	elif not combat_input_blocked and Input.is_action_just_pressed("select_melee"):
		equip_weapon(melee_key)
	elif not combat_input_blocked and Input.is_action_just_pressed("select_grenade") and not grenade_key.is_empty():
		equip_weapon(grenade_key)
	var current_spec := WeaponCatalog.get_weapon(weapon_key)
	var mouse_captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	aiming = not combat_input_blocked and mouse_captured and Input.is_action_pressed("aim") and current_spec.slot not in [LocalStrikeWeaponDefinition.Slot.MELEE, LocalStrikeWeaponDefinition.Slot.GRENADE]
	if current_spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE:
		if not combat_input_blocked and mouse_captured and Input.is_action_just_pressed("fire"):
			melee_attack(false)
		elif not combat_input_blocked and mouse_captured and Input.is_action_just_pressed("aim"):
			melee_attack(true)
	else:
		var automatic_fire := fire_mode == "auto" or fire_mode == "pump"
		if not combat_input_blocked and mouse_captured and ((automatic_fire and Input.is_action_pressed("fire")) or (not automatic_fire and Input.is_action_just_pressed("fire"))):
			shoot()
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var wants_crouch := Input.is_action_pressed("crouch") and is_on_floor()
	if wants_crouch:
		crouching = true
	elif crouching and _can_stand():
		crouching = false
	_capsule.height = 1.08 if crouching else 1.55
	_collision.position.y = 0.58 if crouching else 0.82
	var sprinting := Input.is_action_pressed("sprint") and not crouching and stamina > 2.0 and input.length() > 0.1
	var speed := (2.8 if crouching else (7.0 if sprinting else 4.5)) / maxf(1.0, current_spec.weight * 0.92)
	if sprinting:
		stamina = maxf(0.0, stamina - 30.0 * delta)
	else:
		stamina = minf(100.0, stamina + 24.0 * delta)

	var surface: Dictionary = SurfaceProfile.get_profile(_floor_surface)
	var acceleration: float = 24.0 * float(surface.friction) if is_on_floor() else 7.5
	var target_x := direction.x * speed
	var target_z := direction.z * speed
	velocity.x = move_toward(velocity.x, target_x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_z, acceleration * delta)
	var was_on_floor := is_on_floor()
	if was_on_floor:
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
		velocity.y -= GRAVITY * delta
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		if direction.length_squared() > 0.1 and _try_vault(direction):
			velocity.y = 2.4
		else:
			velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
	var fall_speed := velocity.y
	move_and_slide()
	_update_floor_surface()
	if is_on_floor() and not was_on_floor and fall_speed < -3.0:
		_landing_kick = minf(0.12, absf(fall_speed) * 0.009)
		if fall_speed < -10.0:
			apply_damage(minf(60.0, (absf(fall_speed) - 9.0) * 4.0), "limb")

	if input.length() > 0.1 and is_on_floor():
		_move_time += delta * (11.5 if sprinting else 8.5)
		_footstep_timer -= delta
		if _footstep_timer <= 0.0:
			_footstep_timer = 0.28 if sprinting else (0.52 if crouching else 0.4)
			footstep.emit(global_position)
	var bob := sin(_move_time) * 0.012 if input.length() > 0.1 and is_on_floor() else 0.0
	_landing_kick = move_toward(_landing_kick, 0.0, 0.75 * delta)
	var target_camera_height := 1.12 if crouching else CAMERA_HEIGHT
	_camera.position.y = lerpf(_camera.position.y, target_camera_height + bob * 0.65 - _landing_kick, 13.0 * delta)
	var target_fov := current_spec.ads_fov if aiming else (78.0 if sprinting else 74.0)
	_camera.fov = lerpf(_camera.fov, target_fov, 10.0 * delta)
	_weapon_sway = _weapon_sway.lerp(Vector2.ZERO, minf(1.0, 10.0 * delta))
	_weapon_root.position.x = lerpf(_weapon_root.position.x, (0.0 if aiming else 0.23) - _weapon_sway.x, 14.0 * delta)
	var sight_height := -0.255 if current_spec.category in ["sniper", "dmr"] else -0.19
	_weapon_root.position.y = lerpf(_weapon_root.position.y, (sight_height if aiming else -0.27) + bob, 12.0 * delta)
	_weapon_root.position.z = lerpf(_weapon_root.position.z, -0.48 + absf(_weapon_sway.y) * 0.5, 14.0 * delta)
	var target_rotation := Vector3(0.0, 0.0, -input.x * 0.035)
	if _melee_anim_timer > 0.0 and _melee_anim_duration > 0.0:
		var progress := 1.0 - _melee_anim_timer / _melee_anim_duration
		var swing := sin(progress * PI)
		target_rotation.x = (-1.05 if _melee_heavy else -0.42) * swing
		target_rotation.y = _melee_swing_sign * (0.28 if _melee_heavy else 0.52) * swing
		target_rotation.z = _melee_swing_sign * (0.82 if _melee_heavy else 1.15) * swing
	_weapon_root.rotation = _weapon_root.rotation.lerp(target_rotation, minf(1.0, 18.0 * delta))
	stats_changed.emit()

func shoot() -> void:
	if _fire_cooldown > 0.0 or _reloading or _equip_timer > 0.0:
		return
	var spec := WeaponCatalog.get_weapon(weapon_key)
	if spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE:
		melee_attack(false)
		return
	if ammo <= 0 and not unlimited_ammo:
		begin_reload()
		return

	_shot_sequence += 1
	if not unlimited_ammo:
		ammo -= 1
	_fire_cooldown = spec.fire_delay
	ammo_state[weapon_key] = {"ammo": ammo, "reserve": reserve_ammo}
	if spec.slot == LocalStrikeWeaponDefinition.Slot.GRENADE:
		var throw_direction := (-_camera.global_transform.basis.z + Vector3.UP * 0.24).normalized()
		grenade_thrown.emit(_muzzle.global_position, throw_direction * 12.5, spec.category)
		if not unlimited_ammo:
			inventory.erase(weapon_key)
			grenade_key = ""
			equip_weapon(primary_key if not primary_key.is_empty() else secondary_key, false)
		stats_changed.emit()
		return
	_weapon_root.position.z += 0.08 if spec.pellets > 1 else 0.045
	_muzzle_flash_timer = 0.045
	_muzzle_flash.visible = true
	_muzzle_flash.rotation.z = randf_range(0.0, TAU)
	_muzzle_light.light_energy = 3.6

	var origin: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_transform.basis.z
	var movement_penalty := clampf(Vector2(velocity.x, velocity.z).length() / 7.0, 0.0, 1.0) * spec.move_spread
	if not is_on_floor():
		movement_penalty += spec.move_spread * 1.8
	elif crouching:
		movement_penalty *= 0.45
	if aiming:
		movement_penalty *= spec.ads_spread_multiplier
	var total_spread := spec.spread * (spec.ads_spread_multiplier if aiming else 1.0) + movement_penalty
	shot_requested.emit(_shot_sequence, origin, forward, weapon_key, fire_mode)
	if authoritative_damage:
		for pellet in range(spec.pellets):
			var spread := Ballistics.deterministic_spread(spec, _shot_sequence, pellet, total_spread)
			var direction: Vector3 = (forward + _camera.global_transform.basis.x * spread.x + _camera.global_transform.basis.y * spread.y).normalized()
			var result := Ballistics.resolve_shot(get_world_3d().direct_space_state, origin, direction, spec, [get_rid()], _shot_sequence)
			for hit_data in result.hits:
				var target: Object = hit_data.target
				if target != null and target.has_method("take_ballistic_damage"):
					var killed: bool = target.take_ballistic_damage(float(hit_data.damage), str(hit_data.zone), spec.armor_penetration)
					hit_confirmed.emit(killed)
				elif target != null and target.has_method("take_damage"):
					var killed: bool = target.take_damage(float(hit_data.damage), str(hit_data.zone))
					hit_confirmed.emit(killed)
				if target != null and target.has_method("apply_gameplay_impulse"):
					target.apply_gameplay_impulse(direction * spec.shot_impulse, hit_data.position - target.global_position)
			for segment in result.segments:
				var segment_surface := str(segment.get("surface", "air"))
				var segment_hit := segment_surface != "air"
				shot_fired.emit(segment.from, segment.to, segment_hit, segment.get("normal", -direction), segment_surface, segment_surface == "flesh")
	var recoil := Ballistics.recoil_for(spec, _shot_sequence - 1) * (0.72 if aiming else 1.0)
	_pitch = clampf(_pitch - recoil.y, -1.35, 1.35)
	_yaw += recoil.x
	rotation.y = _yaw
	_camera.rotation.x = _pitch

	stats_changed.emit()
	if ammo <= 0 and not unlimited_ammo:
		begin_reload()

func melee_attack(heavy: bool) -> void:
	if _fire_cooldown > 0.0 or _reloading or _equip_timer > 0.0:
		return
	var spec := WeaponCatalog.get_weapon(weapon_key)
	if spec.slot != LocalStrikeWeaponDefinition.Slot.MELEE:
		return
	_shot_sequence += 1
	_fire_cooldown = spec.melee_heavy_recovery if heavy else spec.melee_light_recovery
	_melee_anim_duration = _fire_cooldown
	_melee_anim_timer = _melee_anim_duration
	_melee_heavy = heavy
	_melee_swing_sign *= -1.0
	melee_attack_requested.emit(_shot_sequence, get_aim_origin(), get_aim_direction(), weapon_key, heavy)
	stats_changed.emit()

func confirm_melee_hit(killed: bool, blood_amount: float) -> void:
	weapon_blood[weapon_key] = clampf(float(weapon_blood.get(weapon_key, 0.0)) + blood_amount, 0.0, 1.0)
	_apply_weapon_blood()
	hit_confirmed.emit(killed)

func cycle_fire_mode() -> void:
	var spec := WeaponCatalog.get_weapon(weapon_key)
	if spec.fire_modes.size() < 2:
		return
	var index := spec.fire_modes.find(fire_mode)
	fire_mode = spec.fire_modes[(index + 1) % spec.fire_modes.size()]
	stats_changed.emit()

func get_fire_mode() -> String:
	return fire_mode.to_upper()

func pickup_weapon(key: String, current_ammo: int, reserve: int, bloodiness := 0.0) -> void:
	grant_weapon(key)
	ammo = current_ammo
	reserve_ammo = reserve
	weapon_blood[key] = clampf(bloodiness, 0.0, 1.0)
	ammo_state[key] = {"ammo": ammo, "reserve": reserve_ammo}
	_apply_weapon_blood()
	stats_changed.emit()

func remove_current_weapon_for_drop() -> Dictionary:
	var spec := WeaponCatalog.get_weapon(weapon_key)
	if spec.slot not in [LocalStrikeWeaponDefinition.Slot.PRIMARY, LocalStrikeWeaponDefinition.Slot.SECONDARY] and not (allow_melee_drop and spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE):
		return {}
	if weapon_key == "knife":
		return {}
	var dropped := {"key": weapon_key, "ammo": ammo, "reserve": reserve_ammo, "bloodiness": float(weapon_blood.get(weapon_key, 0.0))}
	inventory.erase(weapon_key)
	if spec.slot == LocalStrikeWeaponDefinition.Slot.PRIMARY:
		primary_key = ""
	elif spec.slot == LocalStrikeWeaponDefinition.Slot.SECONDARY:
		secondary_key = ""
	else:
		melee_key = "knife"
		inventory["knife"] = true
		ammo_state["knife"] = {"ammo": 1, "reserve": 0}
		equip_weapon("knife", false)
		return dropped
	var fallback := primary_key if not primary_key.is_empty() else (secondary_key if not secondary_key.is_empty() else melee_key)
	equip_weapon(fallback, false)
	return dropped

func _can_stand() -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = _capsule.radius
	shape.height = 1.55
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(global_transform.basis, global_position + Vector3.UP * 0.82)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _try_vault(direction: Vector3) -> bool:
	if not is_on_floor():
		return false
	var low_origin := global_position + Vector3.UP * 0.45
	var high_origin := global_position + Vector3.UP * 1.35
	var low_query := PhysicsRayQueryParameters3D.create(low_origin, low_origin + direction * 0.8)
	var high_query := PhysicsRayQueryParameters3D.create(high_origin, high_origin + direction * 0.8)
	low_query.exclude = [get_rid()]
	high_query.exclude = [get_rid()]
	low_query.collision_mask = 1
	high_query.collision_mask = 1
	if get_world_3d().direct_space_state.intersect_ray(low_query).is_empty():
		return false
	if not get_world_3d().direct_space_state.intersect_ray(high_query).is_empty():
		return false
	global_position += direction * 0.58 + Vector3.UP * 0.42
	return true

func _update_floor_surface() -> void:
	if not is_on_floor():
		return
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		if collision.get_normal().y < 0.45:
			continue
		var collider := collision.get_collider()
		if collider != null:
			_floor_surface = str(collider.get_meta("surface_type", "concrete"))
			return

func begin_reload() -> void:
	var spec := WeaponCatalog.get_weapon(weapon_key)
	if _reloading or spec.reload_time <= 0.0 or ammo >= spec.magazine or reserve_ammo <= 0:
		return
	_reloading = true
	_reload_timer = spec.reload_time
	reload_requested.emit(weapon_key)

func _finish_reload() -> void:
	var spec := WeaponCatalog.get_weapon(weapon_key)
	var needed: int = spec.magazine - ammo
	var taken: int = mini(needed, reserve_ammo)
	ammo += taken
	reserve_ammo -= taken
	_reloading = false
	ammo_state[weapon_key] = {"ammo": ammo, "reserve": reserve_ammo}
	_weapon_root.rotation.z = 0.0
	stats_changed.emit()

func try_buy(key: String, buy_open: bool) -> String:
	if not buy_open:
		return "Buy phase is closed"
	if not WeaponCatalog.all().has(key):
		return "Unknown weapon"
	var spec := WeaponCatalog.get_weapon(key)
	if money < spec.price:
		return "Not enough money"
	money -= spec.price
	inventory[key] = true
	ammo_state[key] = {"ammo": spec.magazine, "reserve": spec.reserve}
	if spec.slot == LocalStrikeWeaponDefinition.Slot.PRIMARY:
		if not primary_key.is_empty():
			inventory.erase(primary_key)
		primary_key = key
	elif spec.slot == LocalStrikeWeaponDefinition.Slot.SECONDARY:
		secondary_key = key
	elif spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE:
		melee_key = key
	elif spec.slot == LocalStrikeWeaponDefinition.Slot.GRENADE:
		grenade_key = key
	equip_weapon(key, false)
	_reloading = false
	stats_changed.emit()
	return "%s ready" % spec.display_name

func grant_weapon(key: String) -> String:
	if not WeaponCatalog.all().has(key):
		return "Unknown weapon"
	var spec := WeaponCatalog.get_weapon(key)
	inventory[key] = true
	ammo_state[key] = {"ammo": spec.magazine, "reserve": spec.reserve}
	if spec.slot == LocalStrikeWeaponDefinition.Slot.PRIMARY:
		if not primary_key.is_empty(): inventory.erase(primary_key)
		primary_key = key
	elif spec.slot == LocalStrikeWeaponDefinition.Slot.SECONDARY:
		secondary_key = key
	elif spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE:
		melee_key = key
	elif spec.slot == LocalStrikeWeaponDefinition.Slot.GRENADE:
		grenade_key = key
	equip_weapon(key, false)
	return "%s equipped" % spec.display_name

func apply_damage(amount: float, hit_zone := "torso", _context := {}) -> void:
	if health <= 0.0 or invulnerable:
		return
	var armor_ratio := 0.0 if hit_zone == "limb" else (0.58 if hit_zone != "head" or helmet else 0.0)
	var absorbed := minf(armor, amount * armor_ratio)
	armor -= absorbed
	health = maxf(0.0, health - (amount - absorbed))
	damage_taken.emit(amount - absorbed)
	stats_changed.emit()
	if health <= 0.0:
		player_died.emit()

func apply_confirmed_damage(amount: float) -> void:
	if health <= 0.0 or invulnerable:
		return
	health = maxf(0.0, health - amount)
	damage_taken.emit(amount)
	stats_changed.emit()
	if health <= 0.0:
		player_died.emit()

func apply_gameplay_impulse(impulse: Vector3, _at_position := Vector3.ZERO) -> void:
	velocity += impulse * 0.18
	velocity.y = maxf(velocity.y, impulse.y * 0.12)

func add_reward(amount: int) -> void:
	money += amount
	stats_changed.emit()

func reset_for_round(spawn_position: Vector3) -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	health = 100.0
	armor = 35.0
	helmet = true
	stamina = 100.0
	for key in inventory:
		var inventory_spec := WeaponCatalog.get_weapon(key)
		ammo_state[key] = {"ammo": inventory_spec.magazine, "reserve": inventory_spec.reserve}
	equip_weapon(weapon_key, false)
	_reloading = false
	_fire_cooldown = 0.0
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_landing_kick = 0.0
	stats_changed.emit()

func reset_view(yaw := 0.0, pitch := 0.0) -> void:
	_yaw = yaw
	_pitch = clampf(pitch, -1.35, 1.35)
	rotation.y = _yaw
	if _camera != null:
		_camera.rotation.x = _pitch
	_weapon_sway = Vector2.ZERO

func get_weapon_name() -> String:
	return WeaponCatalog.get_weapon(weapon_key).display_name

func is_reloading() -> bool:
	return _reloading

func set_view_active(value: bool) -> void:
	if _camera != null:
		_camera.current = value

func get_aim_origin() -> Vector3:
	return _camera.global_position if _camera != null else global_position + Vector3.UP * CAMERA_HEIGHT

func get_aim_direction() -> Vector3:
	return -_camera.global_transform.basis.z if _camera != null else -global_transform.basis.z

func equip_weapon(key: String, store_current := true) -> void:
	if not inventory.has(key):
		return
	if store_current and not weapon_key.is_empty():
		ammo_state[weapon_key] = {"ammo": ammo, "reserve": reserve_ammo}
	weapon_key = key
	var spec := WeaponCatalog.get_weapon(key)
	fire_mode = spec.fire_modes[0] if not spec.fire_modes.is_empty() else ("auto" if spec.automatic else "semi")
	_equip_timer = spec.equip_time
	var state: Dictionary = ammo_state.get(key, {"ammo": spec.magazine, "reserve": spec.reserve})
	ammo = state.ammo
	reserve_ammo = state.reserve
	_reloading = false
	_update_weapon_visual(spec)
	_apply_weapon_blood()
	stats_changed.emit()

func clear_weapon_blood() -> void:
	weapon_blood.clear()
	_apply_weapon_blood()

func set_extended_melee_enabled(value: bool) -> void:
	allow_melee_drop = value
	if value:
		return
	for key in WeaponCatalog.melee_keys():
		if key != "knife":
			inventory.erase(key)
			ammo_state.erase(key)
			weapon_blood.erase(key)
	melee_key = "knife"
	inventory["knife"] = true
	if not ammo_state.has("knife"):
		ammo_state["knife"] = {"ammo": 1, "reserve": 0}
	if WeaponCatalog.get_weapon(weapon_key).slot == LocalStrikeWeaponDefinition.Slot.MELEE:
		equip_weapon("knife", false)

func _update_weapon_visual(spec: LocalStrikeWeaponDefinition) -> void:
	if _weapon_body == null:
		return
	if is_instance_valid(_imported_weapon_model):
		_imported_weapon_model.queue_free()
		_imported_weapon_model = null
	var body_mesh := _weapon_body.mesh as BoxMesh
	var barrel_mesh := _barrel.mesh as CylinderMesh
	var grip_mesh := _grip.mesh as BoxMesh
	var sight_mesh := _sight.mesh as BoxMesh
	var body_material := _weapon_body.material_override as StandardMaterial3D
	_weapon_root.scale = spec.view_scale
	body_mesh.size = Vector3(0.19, 0.17, 0.64)
	barrel_mesh.height = 0.52
	grip_mesh.size = Vector3(0.12, 0.3, 0.16)
	sight_mesh.size = Vector3(0.1, 0.08, 0.2)
	_weapon_body.position = Vector3.ZERO
	_barrel.position = Vector3(0, 0.01, -0.48)
	_grip.position = Vector3(0, -0.16, -0.05)
	_sight.position = Vector3(0, 0.115, -0.16)
	_accent.position = Vector3(0.11, 0.045, -0.22)
	_weapon_body.visible = true
	_barrel.visible = true
	_grip.visible = true
	_sight.visible = true
	_accent.visible = true
	_left_hand.visible = true
	_right_hand.visible = true
	barrel_mesh.top_radius = 0.038
	barrel_mesh.bottom_radius = 0.048
	body_material.albedo_color = Color("303943")
	match spec.category:
		"knife", "machete":
			body_mesh.size = Vector3(0.065 if spec.category == "knife" else 0.12, 0.045, 0.68 if spec.category == "knife" else 0.92)
			_weapon_body.position = Vector3(0, 0.02, -0.28)
			grip_mesh.size = Vector3(0.13, 0.1, 0.3)
			_grip.position = Vector3(0, -0.01, 0.28)
			body_material.albedo_color = Color("9eabb2")
			_barrel.visible = false
			_sight.visible = false
			_accent.visible = false
		"baseball_bat", "crowbar":
			_weapon_body.visible = false
			barrel_mesh.height = 1.08
			barrel_mesh.top_radius = 0.09 if spec.category == "baseball_bat" else 0.045
			barrel_mesh.bottom_radius = 0.055 if spec.category == "baseball_bat" else 0.045
			_barrel.position = Vector3(0, 0, -0.28)
			body_material.albedo_color = Color("7a4a2d") if spec.category == "baseball_bat" else Color("a52b31")
			_grip.visible = false
			_sight.visible = false
			_accent.visible = spec.category == "crowbar"
			_accent.position = Vector3(0.11, 0, -0.78)
		"fire_axe", "sledgehammer":
			body_mesh.size = Vector3(0.46, 0.13 if spec.category == "fire_axe" else 0.25, 0.24)
			_weapon_body.position = Vector3(0, 0, -0.78)
			barrel_mesh.height = 1.05
			barrel_mesh.top_radius = 0.048
			barrel_mesh.bottom_radius = 0.055
			_barrel.position = Vector3(0, 0, -0.28)
			body_material.albedo_color = Color("8f999e")
			_grip.visible = false
			_sight.visible = false
			_accent.visible = false
		"pistol", "revolver":
			body_mesh.size = Vector3(0.16, 0.14, 0.42)
			barrel_mesh.height = 0.3
			_weapon_body.position = Vector3.ZERO
			_barrel.position.z = -0.34
			grip_mesh.size = Vector3(0.11, 0.29, 0.13)
			_sight.visible = false
			_accent.position = Vector3(0.09, 0.075, -0.08)
		"shotgun", "auto_shotgun":
			body_mesh.size = Vector3(0.2, 0.18, 0.92)
			barrel_mesh.height = 0.72
			_barrel.position.z = -0.78
			grip_mesh.size = Vector3(0.13, 0.34, 0.18)
			_accent.position = Vector3(0.12, 0.06, -0.38)
		"sniper", "dmr":
			body_mesh.size = Vector3(0.19, 0.17, 0.94)
			barrel_mesh.height = 0.78
			_barrel.position.z = -0.82
			sight_mesh.size = Vector3(0.11, 0.1, 0.34)
			_sight.position = Vector3(0, 0.14, -0.18)
			body_material.albedo_color = Color("28333c")
		"frag", "smoke", "flash", "incendiary":
			body_mesh.size = Vector3(0.24, 0.34, 0.24)
			_weapon_body.position = Vector3(0, -0.03, -0.08)
			_barrel.visible = false
			_grip.visible = false
			_sight.visible = false
			_accent.position = Vector3(0.13, 0.04, -0.08)
		_:
			body_mesh.size = Vector3(0.19, 0.17, 0.78 if spec.category == "rifle" else 0.64)
			barrel_mesh.height = 0.58
			_barrel.position.z = -0.58
			grip_mesh.size = Vector3(0.12, 0.3, 0.16)
			_sight.position = Vector3(0, 0.115, -0.16)
	_muzzle.position = spec.muzzle_offset
	_base_weapon_color = body_material.albedo_color
	if WeaponCatalog.all().has(spec.key):
		_imported_weapon_model = WeaponModel.create(spec.key, float(weapon_blood.get(spec.key, 0.0)))
		_imported_weapon_model.position = Vector3.ZERO
		_imported_weapon_model.scale = Vector3.ONE * 0.82
		_weapon_root.add_child(_imported_weapon_model)
		_set_viewmodel_layers(_imported_weapon_model)
		for primitive in [_weapon_body, _barrel, _grip, _sight, _accent]:
			primitive.visible = false
		_pose_viewmodel_hands(spec)
	_apply_weapon_blood()

func _apply_weapon_blood() -> void:
	if _weapon_body == null:
		return
	var material := _weapon_body.material_override as StandardMaterial3D
	if material == null:
		return
	var bloodiness := clampf(float(weapon_blood.get(weapon_key, 0.0)), 0.0, 1.0)
	material.albedo_color = _base_weapon_color.lerp(Color("5a1118"), bloodiness * 0.68)
	if is_instance_valid(_imported_weapon_model):
		var position := _imported_weapon_model.position
		var rotation := _imported_weapon_model.rotation
		var scale_value := _imported_weapon_model.scale
		_imported_weapon_model.queue_free()
		_imported_weapon_model = WeaponModel.create(weapon_key, bloodiness)
		_imported_weapon_model.position = position
		_imported_weapon_model.rotation = rotation
		_imported_weapon_model.scale = scale_value
		_weapon_root.add_child(_imported_weapon_model)
		_set_viewmodel_layers(_imported_weapon_model)
