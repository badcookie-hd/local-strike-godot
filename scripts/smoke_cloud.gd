class_name LocalStrikeSmokeCloud
extends Node3D

const RADIUS := 3.25
const LIFETIME := 16.0

var _life := LIFETIME
var _puffs: Array[MeshInstance3D] = []

func _ready() -> void:
	add_to_group("smoke_cloud")
	for i in range(18):
		var puff := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = randf_range(0.72, 1.12)
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 12
		mesh.rings = 7
		puff.mesh = mesh
		puff.position = Vector3(randf_range(-2.0, 2.0), randf_range(0.35, 1.55), randf_range(-2.0, 2.0))
		puff.scale = Vector3.ZERO
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.31, 0.35, 0.37, 0.76)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff.material_override = material
		add_child(puff)
		_puffs.append(puff)
		var tween := puff.create_tween()
		tween.tween_property(puff, "scale", Vector3.ONE, randf_range(0.35, 0.75))

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 2.0:
		var fade := clampf(_life / 2.0, 0.0, 1.0)
		for puff in _puffs:
			puff.modulate.a = fade
	if _life <= 0.0:
		queue_free()

func blocks_segment(from: Vector3, to: Vector3) -> bool:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return false
	var t := clampf((global_position - from).dot(segment) / length_squared, 0.0, 1.0)
	return (from + segment * t).distance_to(global_position + Vector3.UP) < RADIUS
