class_name LocalStrikeEffectsManager
extends Node3D

const BULLET_CAPS := [80, 45, 18]
const BLOOD_CAPS := [32, 18, 8]

var quality := 0
var compatibility := false
var bullet_decals: Array[Node3D] = []
var blood_decals: Array[Node3D] = []
var _bullet_texture: Texture2D
var _blood_texture: Texture2D

func _ready() -> void:
	compatibility = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	_bullet_texture = _radial_texture(Color("1c1712"), 0.82, 64)
	_blood_texture = _radial_texture(Color("641219"), 0.9, 64)

func set_quality(next_quality: int, is_compatibility: bool) -> void:
	quality = clampi(next_quality, 0, 2)
	compatibility = is_compatibility
	_trim_pool(bullet_decals, BULLET_CAPS[quality])
	_trim_pool(blood_decals, BLOOD_CAPS[quality])

func spawn_impact(position: Vector3, normal: Vector3, surface_type: String, actor_hit := false) -> void:
	var safe_normal := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	if actor_hit or surface_type in ["flesh", "fabric"]:
		spawn_burst(position, Color("9d1721"), 14 if quality == 0 else 9, 1.35)
		_add_mark(position, safe_normal, true)
		return
	match surface_type:
		"metal":
			spawn_burst(position, Color("ffd37a"), 9 if quality == 0 else 5, 1.8)
		"glass":
			spawn_burst(position, Color("b8f1ff"), 16 if quality == 0 else 9, 1.55)
		_:
			spawn_burst(position, Color("a59c8b"), 8 if quality == 0 else 4, 0.9)
	_add_mark(position, safe_normal, false)

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
	var amount := mini(count, 34 if quality == 0 else (20 if quality == 1 else 10))
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
	return {"bullet": bullet_decals.size(), "blood": blood_decals.size()}

func _add_mark(position: Vector3, normal: Vector3, blood: bool) -> void:
	var pool: Array[Node3D] = blood_decals if blood else bullet_decals
	var cap: int = int(BLOOD_CAPS[quality] if blood else BULLET_CAPS[quality])
	var mark: Node3D
	if compatibility:
		var mesh_instance := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.3, 0.3) if blood else Vector2(0.12, 0.12)
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
		decal.size = Vector3(0.38, 0.38, 0.38) if blood else Vector3(0.16, 0.16, 0.16)
		decal.texture_albedo = _blood_texture if blood else _bullet_texture
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = 28.0
		decal.distance_fade_length = 12.0
		mark = decal
	mark.position = position + normal * 0.012
	mark.quaternion = Quaternion(Vector3.FORWARD, normal)
	add_child(mark)
	pool.append(mark)
	while pool.size() > cap:
		var oldest: Node3D = pool.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var lifetime: float = 25.0 if blood else 35.0
	var tween := mark.create_tween()
	tween.tween_interval(lifetime)
	tween.tween_property(mark, "scale", Vector3.ONE * 0.001, 0.5)
	tween.tween_callback(func():
		pool.erase(mark)
		if is_instance_valid(mark): mark.queue_free()
	)

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
