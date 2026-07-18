class_name LocalStrikeSandboxItemPreview
extends SubViewportContainer

const ItemDefinition = preload("res://scripts/sandbox_item_definition.gd")
const WeaponModel = preload("res://scripts/weapon_model.gd")
const Materials = preload("res://scripts/material_library.gd")

var _viewport: SubViewport
var _turntable: Node3D


func configure(definition: LocalStrikeSandboxItemDefinition) -> void:
	custom_minimum_size = Vector2(160, 76)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(320, 152)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.world_3d = World3D.new()
	add_child(_viewport)

	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("10191d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b4c6c9")
	settings.ambient_light_energy = 0.72
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	_viewport.add_child(environment)

	_turntable = Node3D.new()
	_viewport.add_child(_turntable)
	var visual := _create_visual(definition)
	_turntable.add_child(visual)
	_fit_visual(visual, definition)
	if definition.kind == ItemDefinition.Kind.WEAPON:
		_turntable.rotation_degrees = Vector3(-12, -32, 8)
	elif definition.kind == ItemDefinition.Kind.BOT:
		_turntable.rotation_degrees.y = 18.0

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -32, 0)
	key.light_color = Color("d7edf0")
	key.light_energy = 1.7
	key.shadow_enabled = false
	_viewport.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 1.6, 1.2)
	rim.light_color = Color("f2a85e")
	rim.light_energy = 2.1
	rim.omni_range = 5.0
	_viewport.add_child(rim)

	var camera := Camera3D.new()
	if definition.kind == ItemDefinition.Kind.BOT:
		camera.position = Vector3(2.15, 1.35, 3.0)
		camera.look_at_from_position(camera.position, Vector3(0, 0.9, 0))
	elif definition.kind == ItemDefinition.Kind.WEAPON:
		camera.position = Vector3(1.6, 0.75, 2.25)
		camera.look_at_from_position(camera.position, Vector3.ZERO)
	else:
		camera.position = Vector3(2.15, 1.45, 2.65)
		camera.look_at_from_position(camera.position, Vector3(0, 0.45, 0))
	camera.fov = 39.0
	camera.current = true
	_viewport.add_child(camera)


func _process(delta: float) -> void:
	if _turntable != null and is_visible_in_tree():
		_turntable.rotate_y(delta * 0.32)


func _create_visual(definition: LocalStrikeSandboxItemDefinition) -> Node3D:
	if definition.kind == ItemDefinition.Kind.WEAPON:
		return WeaponModel.create(definition.weapon_key)
	if definition.kind == ItemDefinition.Kind.BOT and not definition.scene_path.is_empty():
		var packed := load(definition.scene_path) as PackedScene
		if packed != null:
			return packed.instantiate()
	var root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var mesh: PrimitiveMesh
	if definition.surface_type == "barrel":
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.42
		cylinder.bottom_radius = 0.42
		cylinder.height = 1.05
		cylinder.radial_segments = 20
		mesh = cylinder
	elif definition.kind == ItemDefinition.Kind.WORLD:
		var sphere := SphereMesh.new()
		sphere.radius = 0.58
		sphere.height = 1.16
		mesh = sphere
	else:
		var box := BoxMesh.new()
		box.size = definition.preview_size
		mesh = box
	mesh_instance.mesh = mesh
	mesh_instance.position.y = definition.preview_size.y * 0.5 if definition.kind == ItemDefinition.Kind.PROP else 0.5
	mesh_instance.material_override = Materials.create("rust" if definition.surface_type in ["metal", "barrel", "tool_cart"] else "wood") if definition.kind == ItemDefinition.Kind.PROP else Materials.emissive(Color("56d8c5"), 1.25)
	root.add_child(mesh_instance)
	return root


func _fit_visual(visual: Node3D, definition: LocalStrikeSandboxItemDefinition) -> void:
	var state := {"has_bounds": false, "bounds": AABB()}
	_collect_bounds(visual, visual, Transform3D.IDENTITY, state)
	if not bool(state.has_bounds):
		return
	var bounds: AABB = state.bounds
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if longest <= 0.001:
		return
	var target_extent := 1.62
	var target_center := Vector3(0, 0.74, 0)
	if definition.kind == ItemDefinition.Kind.WEAPON:
		target_extent = 1.72
		target_center = Vector3(0, 0.06, 0)
	elif definition.kind == ItemDefinition.Kind.PROP:
		target_extent = 1.25
		target_center = Vector3(0, 0.5, 0)
	elif definition.kind == ItemDefinition.Kind.WORLD:
		target_extent = 1.05
		target_center = Vector3(0, 0.45, 0)
	var factor := target_extent / longest
	visual.scale *= factor
	visual.position = -bounds.get_center() * factor
	_turntable.position = target_center


func _collect_bounds(root: Node3D, node: Node, parent_transform: Transform3D, state: Dictionary) -> void:
	var relative := parent_transform
	if node is Node3D and node != root:
		relative = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var mesh_bounds: AABB = relative * mesh_instance.get_aabb()
			state.bounds = state.bounds.merge(mesh_bounds) if bool(state.has_bounds) else mesh_bounds
			state.has_bounds = true
	for child in node.get_children():
		_collect_bounds(root, child, relative, state)
