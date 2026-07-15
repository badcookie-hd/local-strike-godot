class_name LocalStrikeGrenade
extends RigidBody3D

signal detonated(position: Vector3, grenade_kind: String, damage: float, radius: float)

var grenade_kind := "frag"
var fuse := 2.4
var damage := 88.0
var radius := 7.0
var _armed := true

func configure(kind: String, impulse: Vector3) -> void:
	grenade_kind = kind
	damage = 0.0 if kind == "smoke" else 88.0
	radius = 6.5 if kind == "smoke" else 7.0
	linear_velocity = impulse

func _ready() -> void:
	collision_layer = 8
	collision_mask = 1
	mass = 0.42
	gravity_scale = 1.25
	continuous_cd = true
	_build_visual()

func _physics_process(delta: float) -> void:
	if not _armed:
		return
	fuse -= delta
	if fuse <= 0.0:
		_armed = false
		detonated.emit(global_position, grenade_kind, damage, radius)
		queue_free()

func _build_visual() -> void:
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.11
	collision.shape = shape
	add_child(collision)
	var body := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.11
	mesh.height = 0.22
	mesh.radial_segments = 12
	body.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("71816c") if grenade_kind == "smoke" else Color("3e4b38")
	material.metallic = 0.42
	material.roughness = 0.48
	body.material_override = material
	add_child(body)
	var band := MeshInstance3D.new()
	var band_mesh := TorusMesh.new()
	band_mesh.inner_radius = 0.075
	band_mesh.outer_radius = 0.095
	band_mesh.rings = 12
	band_mesh.ring_segments = 6
	band.mesh = band_mesh
	var band_material := StandardMaterial3D.new()
	band_material.albedo_color = Color("a9d8ff") if grenade_kind == "smoke" else Color("f3b447")
	band_material.emission_enabled = true
	band_material.emission = band_material.albedo_color * 0.35
	band.material_override = band_material
	add_child(band)
