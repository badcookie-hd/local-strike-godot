class_name LocalStrikeFireZone
extends Node3D

signal damage_tick(position: Vector3, radius: float, damage: float)

var duration := 6.0
var radius := 3.5
var tick_damage := 8.0
var _tick_timer := 0.1

func _ready() -> void:
	add_to_group("fire_zone")
	for index in range(12):
		var flame := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.04
		mesh.bottom_radius = randf_range(0.12, 0.25)
		mesh.height = randf_range(0.25, 0.65)
		mesh.radial_segments = 6
		flame.mesh = mesh
		var angle := TAU * float(index) / 12.0
		var distance := radius * randf_range(0.2, 0.9)
		flame.position = Vector3(cos(angle) * distance, mesh.height * 0.5, sin(angle) * distance)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("ff7435")
		material.emission_enabled = true
		material.emission = Color("ff4a18") * 2.2
		flame.material_override = material
		add_child(flame)

func _process(delta: float) -> void:
	duration -= delta
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = 0.5
		damage_tick.emit(global_position, radius, tick_damage)
	if duration <= 0.0:
		queue_free()
