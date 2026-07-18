class_name LocalStrikeRagdoll
extends Node3D

func configure(team_color: Color, impulse: Vector3, persistent := false) -> void:
	add_to_group("sandbox_ragdoll" if persistent else "temporary_ragdoll")
	var pieces := [
		{"size": Vector3(0.48, 0.58, 0.3), "position": Vector3(0, 1.04, 0)},
		{"size": Vector3(0.34, 0.34, 0.34), "position": Vector3(0, 1.55, 0)},
		{"size": Vector3(0.18, 0.7, 0.18), "position": Vector3(-0.32, 0.42, 0)},
		{"size": Vector3(0.18, 0.7, 0.18), "position": Vector3(0.32, 0.42, 0)},
		{"size": Vector3(0.16, 0.62, 0.16), "position": Vector3(-0.46, 1.05, 0)},
		{"size": Vector3(0.16, 0.62, 0.16), "position": Vector3(0.46, 1.05, 0)}
	]
	for index in range(pieces.size()):
		var data: Dictionary = pieces[index]
		var body := RigidBody3D.new()
		body.position = data.position
		body.mass = 3.0 if index > 1 else 10.0
		body.collision_layer = 8
		body.collision_mask = 1
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = data.size
		collision.shape = shape
		body.add_child(collision)
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = data.size
		visual.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = team_color if index == 0 else Color("252d33")
		material.roughness = 0.76
		visual.material_override = material
		body.add_child(visual)
		add_child(body)
		body.apply_central_impulse(impulse * body.mass * (0.08 if index > 1 else 0.12) + Vector3(randf_range(-1.0, 1.0), randf_range(0.8, 2.2), randf_range(-1.0, 1.0)))
	if not persistent:
		var tween := create_tween()
		tween.tween_interval(9.0)
		tween.tween_callback(queue_free)
