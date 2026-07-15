class_name LocalStrikePlayer
extends CharacterBody3D

signal shot_fired(origin: Vector3, end: Vector3, hit: bool, normal: Vector3, surface_type: String, actor_hit: bool)
signal stats_changed
signal hit_confirmed(killed: bool)
signal player_died
signal grenade_thrown(origin: Vector3, impulse: Vector3, grenade_kind: String)
signal damage_taken(amount: float)
signal footstep(position: Vector3)

const WeaponCatalog = preload("res://scripts/weapon_catalog.gd")

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
var grenade_key := ""
var inventory := {"knife": true, "sidearm": true}
var ammo_state: Dictionary = {}
var ammo := 12
var reserve_ammo := 36
var enabled := true
var authoritative_damage := true
var helmet := true
var crouching := false

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

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
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

	_weapon_root = Node3D.new()
	_weapon_root.position = Vector3(0.34, -0.28, -0.72)
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

func _create_gloved_arm(position: Vector3, rotation_z: float) -> MeshInstance3D:
	var arm := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.075
	mesh.height = 0.58
	mesh.radial_segments = 12
	mesh.rings = 4
	arm.mesh = mesh
	arm.position = position
	arm.rotation_degrees = Vector3(72, 0, rotation_z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("20282e")
	material.roughness = 0.84
	arm.material_override = material
	_weapon_root.add_child(arm)
	return arm

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
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
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
	_muzzle_flash_timer = maxf(0.0, _muzzle_flash_timer - delta)
	if _muzzle_flash_timer <= 0.0:
		_muzzle_flash.visible = false
		_muzzle_light.light_energy = 0.0
	if _reloading:
		_reload_timer -= delta
		_weapon_root.rotation.z = sin(_reload_timer * 13.0) * 0.16
		if _reload_timer <= 0.0:
			_finish_reload()

	if Input.is_action_just_pressed("reload"):
		begin_reload()
	if Input.is_action_just_pressed("select_primary") and not primary_key.is_empty():
		equip_weapon(primary_key)
	elif Input.is_action_just_pressed("select_secondary"):
		equip_weapon(secondary_key)
	elif Input.is_action_just_pressed("select_melee"):
		equip_weapon("knife")
	elif Input.is_action_just_pressed("select_grenade") and not grenade_key.is_empty():
		equip_weapon(grenade_key)
	var current_spec := WeaponCatalog.get_weapon(weapon_key)
	if (current_spec.automatic and Input.is_action_pressed("fire")) or (not current_spec.automatic and Input.is_action_just_pressed("fire")):
		shoot()
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	crouching = Input.is_action_pressed("crouch") and is_on_floor()
	_capsule.height = 1.08 if crouching else 1.55
	_collision.position.y = 0.58 if crouching else 0.82
	var sprinting := Input.is_action_pressed("sprint") and not crouching and stamina > 2.0 and input.length() > 0.1
	var speed := 2.8 if crouching else (7.0 if sprinting else 4.5)
	if sprinting:
		stamina = maxf(0.0, stamina - 30.0 * delta)
	else:
		stamina = minf(100.0, stamina + 24.0 * delta)

	velocity.x = move_toward(velocity.x, direction.x * speed, 24.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 24.0 * delta)
	var was_on_floor := is_on_floor()
	if was_on_floor:
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
		velocity.y -= GRAVITY * delta
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
	var fall_speed := velocity.y
	move_and_slide()
	if is_on_floor() and not was_on_floor and fall_speed < -3.0:
		_landing_kick = minf(0.12, absf(fall_speed) * 0.009)

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
	_camera.fov = lerpf(_camera.fov, 78.0 if sprinting else 74.0, 7.0 * delta)
	_weapon_sway = _weapon_sway.lerp(Vector2.ZERO, minf(1.0, 10.0 * delta))
	_weapon_root.position.x = lerpf(_weapon_root.position.x, 0.34 - _weapon_sway.x, 14.0 * delta)
	_weapon_root.position.y = lerpf(_weapon_root.position.y, -0.28 + bob, 12.0 * delta)
	_weapon_root.position.z = lerpf(_weapon_root.position.z, -0.72 + absf(_weapon_sway.y) * 0.5, 14.0 * delta)
	_weapon_root.rotation.z = lerpf(_weapon_root.rotation.z, -input.x * 0.035, 10.0 * delta)
	stats_changed.emit()

func shoot() -> void:
	if _fire_cooldown > 0.0 or _reloading:
		return
	if ammo <= 0:
		begin_reload()
		return

	var spec := WeaponCatalog.get_weapon(weapon_key)
	ammo -= 1
	_fire_cooldown = spec.fire_delay
	ammo_state[weapon_key] = {"ammo": ammo, "reserve": reserve_ammo}
	if spec.slot == LocalStrikeWeaponDefinition.Slot.GRENADE:
		var throw_direction := (-_camera.global_transform.basis.z + Vector3.UP * 0.24).normalized()
		grenade_thrown.emit(_muzzle.global_position, throw_direction * 12.5, spec.category)
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
	var total_spread := spec.spread + movement_penalty
	for pellet in range(spec.pellets):
		var spread := Vector3(
			randf_range(-total_spread, total_spread),
			randf_range(-total_spread, total_spread),
			randf_range(-total_spread * 0.2, total_spread * 0.2)
		)
		var direction: Vector3 = (forward + _camera.global_transform.basis.x * spread.x + _camera.global_transform.basis.y * spread.y).normalized()
		var end: Vector3 = origin + direction * float(spec.range)
		var query := PhysicsRayQueryParameters3D.create(origin, end)
		query.exclude = [get_rid()]
		query.collision_mask = 5
		query.collide_with_areas = true
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		var hit := not result.is_empty()
		var hit_position: Vector3 = result.position if hit else end
		var hit_normal: Vector3 = result.normal if hit else -direction
		var surface_type := "air"
		var actor_hit := false
		if hit:
			var collider: Object = result.collider
			var damage_target: Object = collider.get_parent() if collider is Area3D else collider
			actor_hit = damage_target is Node and damage_target.is_in_group("damageable_actor")
			if actor_hit:
				surface_type = "flesh"
			elif collider != null:
				surface_type = str(collider.get_meta("surface_type", "concrete"))
				if surface_type == "concrete" and damage_target != null:
					surface_type = str(damage_target.get_meta("surface_type", "concrete"))
			if authoritative_damage and damage_target != null and damage_target.has_method("take_damage"):
				var hit_zone := str(collider.get_meta("hit_zone", "torso")) if collider != null else "torso"
				var damage := spec.damage
				if hit_zone == "head":
					damage *= spec.head_multiplier
				elif hit_zone == "limb":
					damage *= spec.limb_multiplier
				var killed: bool = damage_target.take_damage(damage, hit_zone)
				hit_confirmed.emit(killed)
		shot_fired.emit(origin, hit_position, hit, hit_normal, surface_type, actor_hit)
	_pitch = clampf(_pitch - spec.recoil_pitch, -1.35, 1.35)
	_yaw += randf_range(-spec.recoil_yaw, spec.recoil_yaw)
	rotation.y = _yaw
	_camera.rotation.x = _pitch

	stats_changed.emit()
	if ammo <= 0:
		begin_reload()

func begin_reload() -> void:
	var spec := WeaponCatalog.get_weapon(weapon_key)
	if _reloading or spec.reload_time <= 0.0 or ammo >= spec.magazine or reserve_ammo <= 0:
		return
	_reloading = true
	_reload_timer = spec.reload_time

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
	elif spec.slot == LocalStrikeWeaponDefinition.Slot.GRENADE:
		grenade_key = key
	equip_weapon(key, false)
	return "%s equipped" % spec.display_name

func apply_damage(amount: float, hit_zone := "torso") -> void:
	if health <= 0.0:
		return
	var armor_ratio := 0.0 if hit_zone == "limb" else (0.58 if hit_zone != "head" or helmet else 0.0)
	var absorbed := minf(armor, amount * armor_ratio)
	armor -= absorbed
	health = maxf(0.0, health - (amount - absorbed))
	damage_taken.emit(amount - absorbed)
	stats_changed.emit()
	if health <= 0.0:
		player_died.emit()

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

func get_weapon_name() -> String:
	return WeaponCatalog.get_weapon(weapon_key).display_name

func is_reloading() -> bool:
	return _reloading

func set_view_active(value: bool) -> void:
	if _camera != null:
		_camera.current = value

func equip_weapon(key: String, store_current := true) -> void:
	if not inventory.has(key):
		return
	if store_current and not weapon_key.is_empty():
		ammo_state[weapon_key] = {"ammo": ammo, "reserve": reserve_ammo}
	weapon_key = key
	var spec := WeaponCatalog.get_weapon(key)
	var state: Dictionary = ammo_state.get(key, {"ammo": spec.magazine, "reserve": spec.reserve})
	ammo = state.ammo
	reserve_ammo = state.reserve
	_reloading = false
	_update_weapon_visual(spec)
	stats_changed.emit()

func _update_weapon_visual(spec: LocalStrikeWeaponDefinition) -> void:
	if _weapon_body == null:
		return
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
	_barrel.visible = true
	_grip.visible = true
	_sight.visible = true
	_accent.visible = true
	_left_hand.visible = true
	_right_hand.visible = true
	body_material.albedo_color = Color("303943")
	match spec.category:
		"melee":
			body_mesh.size = Vector3(0.055, 0.055, 0.82)
			_weapon_body.position = Vector3(0, 0.02, -0.22)
			body_material.albedo_color = Color("9eabb2")
			_barrel.visible = false
			_sight.visible = false
			_accent.visible = false
		"pistol":
			body_mesh.size = Vector3(0.16, 0.14, 0.42)
			barrel_mesh.height = 0.3
			_weapon_body.position = Vector3.ZERO
			_barrel.position.z = -0.34
			grip_mesh.size = Vector3(0.11, 0.29, 0.13)
			_sight.visible = false
			_accent.position = Vector3(0.09, 0.075, -0.08)
		"shotgun":
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
		"frag", "smoke":
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
