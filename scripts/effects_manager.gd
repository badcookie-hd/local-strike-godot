class_name LocalStrikeEffectsManager
extends Node3D

const BULLET_CAPS := [80, 45, 18]
const BLOOD_CAPS := [96, 56, 24]
const BLOOD_POOL_CAPS := [24, 14, 6]

var quality := 0
var compatibility := false
var bullet_decals: Array[Node3D] = []
var blood_decals: Array[Node3D] = []
var blood_pools: Array[Node3D] = []
var _bullet_texture: Texture2D
var _blood_texture: Texture2D
var sandbox_persistent := false

func _ready() -> void:
	compatibility = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	_bullet_texture = _radial_texture(Color("1c1712"), 0.82, 64)
	_blood_texture = _radial_texture(Color("641219"), 0.9, 64)

func set_quality(next_quality: int, is_compatibility: bool) -> void:
	quality = clampi(next_quality, 0, 2)
	compatibility = is_compatibility
	_trim_pool(bullet_decals, BULLET_CAPS[quality])
	_trim_pool(blood_decals, BLOOD_CAPS[quality])
	_trim_pool(blood_pools, BLOOD_POOL_CAPS[quality])

func set_sandbox_persistent(value: bool) -> void:
	sandbox_persistent = value

func spawn_impact(position: Vector3, normal: Vector3, surface_type: String, actor_hit := false) -> void:
	var safe_normal := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	if actor_hit or surface_type in ["flesh", "fabric"]:
		spawn_blood_hit(position, safe_normal, -safe_normal, 0.65, false)
		return
	match surface_type:
		"metal":
			spawn_burst(position, Color("ffd37a"), 9 if quality == 0 else 5, 1.8)
		"glass":
			spawn_burst(position, Color("b8f1ff"), 16 if quality == 0 else 9, 1.55)
		_:
			spawn_burst(position, Color("a59c8b"), 8 if quality == 0 else 4, 0.9)
	_add_mark(position, safe_normal, false)

func spawn_blood_hit(position: Vector3, normal: Vector3, direction: Vector3, intensity := 1.0, killed := false) -> void:
	var safe_normal := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	var safe_direction := direction.normalized() if direction.length_squared() > 0.01 else -safe_normal
	var scaled := clampf(intensity, 0.35, 2.8)
	spawn_burst(position, Color("9d1721"), roundi(18.0 + scaled * 15.0), 1.05 + scaled * 0.55)
	_add_mark(position, safe_normal, true, clampf(0.8 + scaled * 0.24, 0.8, 1.55))
	var splatter_count := clampi(roundi(1.0 + scaled * 1.65), 2, 5)
	for index in range(splatter_count):
		var scatter := Vector3(randf_range(-0.65, 0.65), randf_range(-0.3, 0.72), randf_range(-0.65, 0.65))
		var ray_direction := (safe_direction + scatter).normalized()
		var ray := PhysicsRayQueryParameters3D.create(position + safe_normal * 0.05, position + ray_direction * randf_range(1.2, 3.1))
		ray.collision_mask = 1
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			_add_mark(hit.position, hit.normal, true, randf_range(0.7, 1.3) * scaled)
	if killed:
		spawn_blood_pool(position, scaled)

func spawn_blood_pool(position: Vector3, intensity := 1.0) -> void:
	var ray := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 0.7, position + Vector3.DOWN * 3.0)
	ray.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return
	var mark := _create_mark(hit.position, hit.normal, true, clampf(2.4 + intensity, 2.7, 4.6))
	blood_pools.append(mark)
	while blood_pools.size() > BLOOD_POOL_CAPS[quality]:
		var oldest: Node3D = blood_pools.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	mark.scale = Vector3.ONE * 0.08
	var tween := mark.create_tween()
	tween.tween_property(mark, "scale", Vector3.ONE, 1.8).set_trans(Tween.TRANS_SINE)
	if not sandbox_persistent:
		tween.tween_interval(42.0)
		tween.tween_property(mark, "scale", Vector3.ONE * 0.001, 0.8)
		tween.tween_callback(func():
			blood_pools.erase(mark)
			if is_instance_valid(mark): mark.queue_free()
		)

func clear_blood() -> void:
	for mark in blood_decals + blood_pools:
		if is_instance_valid(mark):
			mark.queue_free()
	blood_decals.clear()
	blood_pools.clear()

func spawn_tracer(origin: Vector3, end: Vector3, color: Color) -> void:
	var distance := origin.distance_to(end)
	if distance < 0.05:
		return
	var tracer := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.009
	mesh.bottom_radius = 0.018
	mesh.height = distance
	mesh.radial_segments = 6
	tracer.mesh = mesh
	tracer.position = origin.lerp(end, 0.5)
	add_child(tracer)
	tracer.look_at(end, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 3.0
	tracer.material_override = material
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "scale", Vector3(0.08, 1.0, 0.08), 0.085)
	tween.tween_callback(tracer.queue_free)

func spawn_burst(position: Vector3, color: Color, count: int, spread := 1.0) -> void:
	var amount := mini(count, 56 if quality == 0 else (32 if quality == 1 else 16))
	for i in range(amount):
		var particle := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = randf_range(0.018, 0.045)
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		particle.mesh = mesh
		particle.position = position
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color * 0.65
		particle.material_override = material
		add_child(particle)
		var direction := Vector3(randf_range(-1.0, 1.0), randf_range(0.15, 1.25), randf_range(-1.0, 1.0)).normalized()
		var tween := particle.create_tween()
		tween.tween_property(particle, "position", position + direction * randf_range(0.3, spread), randf_range(0.22, 0.48))
		tween.parallel().tween_property(particle, "scale", Vector3.ONE * 0.001, 0.45)
		tween.tween_callback(particle.queue_free)

func get_pool_counts() -> Dictionary:
	return {"bullet": bullet_decals.size(), "blood": blood_decals.size(), "pools": blood_pools.size()}

func _add_mark(position: Vector3, normal: Vector3, blood: bool, size_scale := 1.0) -> void:
	var pool: Array[Node3D] = blood_decals if blood else bullet_decals
	var cap: int = int(BLOOD_CAPS[quality] if blood else BULLET_CAPS[quality])
	var mark := _create_mark(position, normal, blood, size_scale)
	pool.append(mark)
	while pool.size() > cap:
		var oldest: Node3D = pool.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	if blood and sandbox_persistent:
		return
	var lifetime: float = 45.0 if blood else 35.0
	var tween := mark.create_tween()
	tween.tween_interval(lifetime)
	tween.tween_property(mark, "scale", Vector3.ONE * 0.001, 0.5)
	tween.tween_callback(func():
		pool.erase(mark)
		if is_instance_valid(mark): mark.queue_free()
	)

func _create_mark(position: Vector3, normal: Vector3, blood: bool, size_scale: float) -> Node3D:
	var mark: Node3D
	if compatibility:
		var mesh_instance := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = (Vector2(0.3, 0.3) if blood else Vector2(0.12, 0.12)) * size_scale
		var material := StandardMaterial3D.new()
		material.albedo_texture = _blood_texture if blood else _bullet_texture
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad.material = material
		mesh_instance.mesh = quad
		mark = mesh_instance
	else:
		var decal := Decal.new()
		decal.size = (Vector3(0.38, 0.38, 0.38) if blood else Vector3(0.16, 0.16, 0.16)) * size_scale
		decal.texture_albedo = _blood_texture if blood else _bullet_texture
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = 28.0
		decal.distance_fade_length = 12.0
		mark = decal
	mark.position = position + normal * 0.012
	mark.quaternion = Quaternion(Vector3.FORWARD, normal)
	add_child(mark)
	return mark

func _trim_pool(pool: Array[Node3D], cap: int) -> void:
	while pool.size() > cap:
		var oldest: Node3D = pool.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

func _radial_texture(color: Color, alpha: float, resolution: int) -> Texture2D:
	var image := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	var center := Vector2(resolution - 1, resolution - 1) * 0.5
	for y in range(resolution):
		for x in range(resolution):
			var distance := Vector2(x, y).distance_to(center) / center.x
			var noise := randf_range(0.74, 1.0)
			var edge := clampf((1.0 - distance) * 5.0, 0.0, 1.0)
			image.set_pixel(x, y, Color(color, alpha * edge * noise))
	return ImageTexture.create_from_image(image)
