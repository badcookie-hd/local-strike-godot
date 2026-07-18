class_name LocalStrikeFoundryMap
extends Node3D

const Materials = preload("res://scripts/material_library.gd")

var _geometry_root: Node3D
var _detail_root: Node3D
var _compatibility := false

func _ready() -> void:
	_compatibility = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	_geometry_root = Node3D.new()
	_geometry_root.name = "StaticGeometry"
	add_child(_geometry_root)
	_detail_root = Node3D.new()
	_detail_root.name = "FoundryDetails"
	add_child(_detail_root)
	_build_shell()
	_build_furnace_hall()
	_build_workshop()
	_build_control_room()
	_build_loading_yard()
	_build_catwalks()
	_build_lighting()
	_build_navigation()
	_build_reflections()

func _build_shell() -> void:
	_add_static_box("MainFloor", Vector3(46, 0.24, 38), Vector3(0, -0.12, 0), "hangar_floor", "concrete")
	_add_static_box("NorthWall", Vector3(46, 7.5, 0.5), Vector3(0, 3.75, -19), "factory_wall", "concrete")
	_add_static_box("SouthWallLeft", Vector3(17, 7.5, 0.5), Vector3(-14.5, 3.75, 19), "brick", "concrete")
	_add_static_box("SouthWallRight", Vector3(17, 7.5, 0.5), Vector3(14.5, 3.75, 19), "brick", "concrete")
	_add_static_box("WestWall", Vector3(0.5, 7.5, 38), Vector3(-23, 3.75, 0), "brick", "concrete")
	_add_static_box("EastWallNorth", Vector3(0.5, 7.5, 17), Vector3(23, 3.75, -10.5), "corrugated", "metal")
	_add_static_box("EastWallSouth", Vector3(0.5, 7.5, 13), Vector3(23, 3.75, 12.5), "corrugated", "metal")
	_add_static_box("FoundryRoof", Vector3(46, 0.3, 38), Vector3(0, 7.45, 0), "corrugated", "metal")
	for x in [-20.0, -12.0, -4.0, 4.0, 12.0, 20.0]:
		_add_detail_box(Vector3(x, 7.1, 0), Vector3(0.22, 0.22, 38.0), "steel_plate", Color("879097"), 90.0)
	for z in [-18.2, 18.2]:
		_add_detail_box(Vector3(0, 7.05, z), Vector3(46.0, 0.2, 0.2), "rust", Color("8b6a54"))
	_add_label("FOUNDRY 07", Vector3(-22.68, 4.9, -6.0), Vector3(0, 90, 0), Color("e8b15f"), 110)
	_add_label("LOADING BAY", Vector3(0, 4.8, 18.68), Vector3(0, 180, 0), Color("c7d4d4"), 76)

func _build_furnace_hall() -> void:
	_add_static_box("FurnaceBase", Vector3(7.6, 0.8, 7.6), Vector3(3, 0.4, -1), "dirty_concrete", "concrete")
	_add_cylinder("BlastFurnace", Vector3(3, 3.0, -1), 2.45, 5.2, "rust", "metal")
	for y in [0.85, 2.2, 3.55, 4.9]:
		_add_torus(Vector3(3, y, -1), 2.5, 2.7, "steel_plate")
	var glow := _add_cylinder("FurnaceGlow", Vector3(3, 1.12, -3.36), 0.78, 0.12, "steel_plate", "metal", Vector3(90, 0, 0))
	var glow_mesh := glow.get_node("Mesh") as MeshInstance3D
	glow_mesh.material_override = Materials.emissive(Color("ff6b24"), 4.8)
	for x in [0.0, 6.0]:
		_add_pipe_run(Vector3(x, 4.8, -1), 0.28, 8.5, Vector3(90, 0, 0))
	for z in [-8.5, 6.5]:
		_add_static_box("HeatShield", Vector3(8.4, 2.2, 0.32), Vector3(3, 1.1, z), "corrugated", "metal")
	_add_oil_patch(Vector3(-1.4, 0.012, 4.6), Vector2(5.4, 2.6))
	_add_oil_patch(Vector3(9.8, 0.012, -7.8), Vector2(3.2, 1.7))

func _build_workshop() -> void:
	_add_static_box("WorkshopBack", Vector3(0.35, 4.2, 13.5), Vector3(-9.2, 2.1, -9.5), "painted_concrete", "concrete")
	_add_static_box("WorkshopSide", Vector3(10.5, 4.2, 0.35), Vector3(-14.25, 2.1, -3.0), "brick", "concrete")
	_add_static_box("WorkshopCounter", Vector3(5.8, 1.0, 1.2), Vector3(-16.4, 0.5, -8.2), "steel_plate", "metal")
	for x in [-19.5, -16.4, -13.3]:
		_add_detail_box(Vector3(x, 1.6, -18.45), Vector3(2.3, 2.8, 0.34), "rust", Color("756052"))
	for z in [-16.2, -12.0, -7.8]:
		_add_pipe_run(Vector3(-21.9, 2.2, z), 0.12, 3.5, Vector3(0, 0, 0))
	_add_label("MACHINE SHOP", Vector3(-9.0, 3.4, -9.1), Vector3(0, 90, 0), Color("d7c8a8"), 58)

func _build_control_room() -> void:
	_add_static_box("ControlPlatform", Vector3(9.0, 0.35, 7.0), Vector3(-14.2, 2.7, 10.7), "metal_grate", "metal")
	_add_static_box("ControlBack", Vector3(9.0, 3.3, 0.3), Vector3(-14.2, 4.35, 14.1), "painted_concrete", "concrete")
	_add_static_box("ControlLeft", Vector3(0.3, 3.3, 7.0), Vector3(-18.55, 4.35, 10.7), "painted_concrete", "concrete")
	_add_static_box("ControlRight", Vector3(0.3, 3.3, 7.0), Vector3(-9.85, 4.35, 10.7), "painted_concrete", "concrete")
	_add_glass_panel(Vector3(-14.2, 4.15, 7.28), Vector3(7.8, 2.1, 0.08))
	for x in [-16.4, -14.2, -12.0]:
		var console := _add_detail_box(Vector3(x, 3.15, 12.9), Vector3(1.7, 0.75, 0.72), "rubber", Color("5c676b"))
		var screen := MeshInstance3D.new()
		var screen_mesh := BoxMesh.new()
		screen_mesh.size = Vector3(1.2, 0.04, 0.34)
		screen.mesh = screen_mesh
		screen.position = Vector3(0, 0.4, -0.08)
		screen.rotation_degrees.x = -22
		screen.material_override = Materials.emissive(Color("4fcfc4" if x != -14.2 else "e8a550"), 1.9)
		console.add_child(screen)
	_add_ramp(Vector3(-7.5, 1.35, 10.7), Vector3(5.0, 0.28, 1.7), -29.0, "metal_grate")

func _build_loading_yard() -> void:
	_add_static_box("LoadingDivider", Vector3(0.35, 3.2, 13.0), Vector3(12.5, 1.6, 11.5), "corrugated", "metal")
	_add_static_box("LoadingDock", Vector3(9.5, 0.9, 5.4), Vector3(17.5, 0.45, 14.5), "dirty_concrete", "concrete")
	for z in [8.0, 12.0, 16.0]:
		_add_detail_box(Vector3(20.9, 1.3, z), Vector3(3.2, 2.5, 0.25), "corrugated", Color("6a7272"))
	for position in [Vector3(15.0, 0.55, 3.8), Vector3(17.2, 0.55, 4.6), Vector3(19.2, 0.55, 6.0)]:
		_add_detail_box(position, Vector3(1.2, 1.1, 1.2), "wood", Color("b29b7a"))
	_add_label("BAY 2", Vector3(12.68, 2.25, 10.5), Vector3(0, -90, 0), Color("f0b45a"), 82)

func _build_catwalks() -> void:
	_add_static_box("NorthCatwalk", Vector3(27.0, 0.24, 1.45), Vector3(6.5, 3.55, -12.4), "metal_grate", "metal")
	_add_static_box("EastCatwalk", Vector3(1.45, 0.24, 18.0), Vector3(19.25, 3.55, -4.1), "metal_grate", "metal")
	for x in [-7.0, -1.0, 5.0, 11.0, 17.0, 20.0]:
		_add_railing(Vector3(x, 4.05, -13.08), Vector3(0.12, 1.0, 0.12), 2)
	for z in [-11.5, -6.5, -1.5, 3.5]:
		_add_railing(Vector3(19.93, 4.05, z), Vector3(0.12, 1.0, 0.12), 2)
	_add_ramp(Vector3(-9.5, 1.76, -12.4), Vector3(8.0, 0.28, 1.45), 24.0, "metal_grate")
	_add_ramp(Vector3(19.25, 1.76, 7.0), Vector3(1.45, 0.28, 8.0), -24.0, "metal_grate", true)

func _build_lighting() -> void:
	for data in [
		[Vector3(-15, 5.8, -13), Color("b9d8df"), 3.6, 13.0],
		[Vector3(-4, 5.8, -10), Color("b9d8df"), 3.2, 12.0],
		[Vector3(8, 5.8, -10), Color("ffc580"), 4.1, 14.0],
		[Vector3(17, 5.8, -4), Color("b9d8df"), 3.3, 12.0],
		[Vector3(-14, 5.7, 10), Color("5ed5cc"), 2.6, 10.0],
		[Vector3(16, 5.7, 13), Color("ffc066"), 3.8, 13.0]
	]:
		_add_fixture(data[0], data[1], data[2], data[3])
	var furnace_light := OmniLight3D.new()
	furnace_light.position = Vector3(3, 1.3, -3.2)
	furnace_light.light_color = Color("ff652b")
	furnace_light.light_energy = 7.0
	furnace_light.omni_range = 11.0
	furnace_light.shadow_enabled = not _compatibility
	_detail_root.add_child(furnace_light)

func _build_navigation() -> void:
	var region := NavigationRegion3D.new()
	region.name = "FoundryNavigation"
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-22.2, 0.04, -18.2), Vector3(22.2, 0.04, -18.2), Vector3(22.2, 0.04, 18.2), Vector3(-22.2, 0.04, 18.2)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	add_child(region)

func _build_reflections() -> void:
	if _compatibility:
		return
	for data in [[Vector3(2, 2.8, -2), Vector3(25, 7, 25)], [Vector3(-14, 4.0, 10), Vector3(10, 5, 9)], [Vector3(17, 2.4, 12), Vector3(11, 6, 13)]]:
		var probe := ReflectionProbe.new()
		probe.position = data[0]
		probe.size = data[1]
		probe.box_projection = true
		probe.intensity = 0.72
		probe.max_distance = 32.0
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		add_child(probe)

func _add_static_box(node_name: String, size: Vector3, position: Vector3, material_name: String, surface: String, rotation := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.rotation_degrees = rotation
	body.collision_layer = 1
	body.set_meta("surface_type", surface)
	_geometry_root.add_child(body)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = Materials.create(material_name)
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	if size.y >= 2.0 and (size.x >= 4.0 or size.z >= 4.0):
		var occluder := OccluderInstance3D.new()
		var box_occluder := BoxOccluder3D.new()
		box_occluder.size = size
		occluder.occluder = box_occluder
		body.add_child(occluder)
	return body

func _add_detail_box(position: Vector3, size: Vector3, material_name: String, tint := Color.WHITE, rotation_y := 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = position
	root.rotation_degrees.y = rotation_y
	_detail_root.add_child(root)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = Materials.create(material_name, tint)
	mesh_instance.visibility_range_end = 42.0
	mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(mesh_instance)
	return root

func _add_cylinder(node_name: String, position: Vector3, radius: float, height: float, material_name: String, surface: String, rotation := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.rotation_degrees = rotation
	body.collision_layer = 1
	body.set_meta("surface_type", surface)
	_geometry_root.add_child(body)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 32
	mesh_instance.mesh = mesh
	mesh_instance.material_override = Materials.create(material_name)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	body.add_child(collision)
	return body

func _add_torus(position: Vector3, inner_radius: float, outer_radius: float, material_name: String) -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 40
	mesh.ring_segments = 10
	ring.mesh = mesh
	ring.position = position
	ring.material_override = Materials.create(material_name)
	_detail_root.add_child(ring)

func _add_pipe_run(position: Vector3, radius: float, height: float, rotation: Vector3) -> void:
	_add_cylinder("Pipe", position, radius, height, "rust", "metal", rotation)

func _add_glass_panel(position: Vector3, size: Vector3) -> void:
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	panel.mesh = mesh
	panel.position = position
	panel.material_override = Materials.glass()
	_detail_root.add_child(panel)

func _add_oil_patch(position: Vector3, size: Vector2) -> void:
	var patch := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.012, size.y)
	patch.mesh = mesh
	patch.position = position
	patch.material_override = Materials.oil()
	_detail_root.add_child(patch)

func _add_ramp(position: Vector3, size: Vector3, rotation_degrees_value: float, material_name: String, rotate_z := false) -> void:
	var rotation := Vector3(0, 0, rotation_degrees_value) if rotate_z else Vector3(rotation_degrees_value, 0, 0)
	_add_static_box("Ramp", size, position, material_name, "metal", rotation)

func _add_railing(position: Vector3, post_size: Vector3, count: int) -> void:
	for index in range(count):
		_add_detail_box(position + Vector3(index * 0.75, 0, 0), post_size, "steel_plate", Color("6e777a"))
	_add_detail_box(position + Vector3(0.38, 0.42, 0), Vector3(1.6, 0.09, 0.09), "steel_plate", Color("6e777a"))

func _add_fixture(position: Vector3, color: Color, energy: float, range_value: float) -> void:
	var fixture := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.2, 0.12, 0.28)
	fixture.mesh = mesh
	fixture.position = position
	fixture.material_override = Materials.emissive(color, 2.4)
	_detail_root.add_child(fixture)
	var light := OmniLight3D.new()
	light.position = position + Vector3.DOWN * 0.15
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.shadow_enabled = not _compatibility and energy >= 3.5
	_detail_root.add_child(light)

func _add_label(text: String, position: Vector3, rotation: Vector3, color: Color, font_size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.rotation_degrees = rotation
	label.font_size = font_size
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.78)
	_detail_root.add_child(label)
