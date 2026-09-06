class_name LocalStrikeWeaponModel
extends RefCounted

const Catalog = preload("res://scripts/weapon_catalog.gd")
const Materials = preload("res://scripts/material_library.gd")
const CUSTOM_MODELS: Array[String] = ["kestrel", "doublebarrel", "longbow"]

const EXTERNAL_MODELS := {
	"knife": "res://assets/models/quaternius/modular_weapons/Dagger.fbx",
	"machete": "res://assets/models/quaternius/modular_weapons/Sword_Big.fbx",
	"fire_axe": "res://assets/models/quaternius/modular_weapons/Axe.fbx",
	"sledgehammer": "res://assets/models/quaternius/modular_weapons/Hammer_Double.fbx",
	"sidearm": "res://assets/models/quaternius/ultimate_guns/Pistol_1.fbx",
	"vanguard": "res://assets/models/quaternius/ultimate_guns/Bullpup_1.fbx",
	"smg": "res://assets/models/quaternius/ultimate_guns/AssaultRifle2_1.fbx",
	"whisper": "res://assets/models/quaternius/ultimate_guns/AssaultRifle2_2.fbx",
	"ranger": "res://assets/models/quaternius/ultimate_guns/AssaultRifle_1.fbx",
	"sentinel": "res://assets/models/quaternius/ultimate_guns/AssaultRifle_2.fbx",
	"hammer": "res://assets/models/quaternius/ultimate_guns/AssaultRifle_3.fbx",
	"breacher": "res://assets/models/quaternius/ultimate_guns/Bullpup_2.fbx",
	"cyclone": "res://assets/models/quaternius/ultimate_guns/Bullpup_3.fbx",
	"marksman": "res://assets/models/quaternius/ultimate_guns/AssaultRifle_4.fbx",
	"heavy_sniper": "res://assets/models/quaternius/ultimate_guns/AssaultRifle2_3.fbx",
	"bulwark": "res://assets/models/quaternius/ultimate_guns/AssaultRifle2_4.fbx"
}

static func create(weapon_key: String, bloodiness := 0.0) -> Node3D:
	var spec := Catalog.get_weapon(weapon_key)
	var root := Node3D.new()
	root.name = "%sModel" % spec.display_name.to_pascal_case()
	var steel := _material(Color("8d999f").lerp(Color("58141a"), bloodiness * 0.68), 0.34, 0.72)
	var dark := _material(Color("242d33").lerp(Color("4d1116"), bloodiness * 0.42), 0.62, 0.28)
	var wood := _material(Color("71442b").lerp(Color("55151a"), bloodiness * 0.5), 0.8, 0.02)
	if EXTERNAL_MODELS.has(weapon_key):
		var packed := load(str(EXTERNAL_MODELS[weapon_key])) as PackedScene
		if packed != null:
			var pivot := Node3D.new()
			pivot.name = "ImportedCC0Model"
			# Imported firearms run along +X; melee blades/handles run along +Y.
			# Normalize every held model to muzzle/blade forward (-Z), top (+Y).
			pivot.basis = Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5) if spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE else Basis(Vector3.UP, PI * 0.5)
			root.add_child(pivot)
			var imported := packed.instantiate()
			imported.name = "SourceModel"
			pivot.add_child(imported)
			var extent := 0.58 if spec.slot == LocalStrikeWeaponDefinition.Slot.SECONDARY else 1.08
			if weapon_key == "knife": extent = 0.5
			elif weapon_key == "machete": extent = 0.85
			_fit_imported_model(imported, extent)
			_apply_external_material(imported, weapon_key, bloodiness)
			root.set_meta("external_model", true)
			root.set_meta("weapon_key", weapon_key)
			root.set_meta("bloodiness", bloodiness)
			return _finish_model(root, weapon_key)
	if weapon_key in CUSTOM_MODELS:
		_build_custom_firearm(root, weapon_key, steel, dark, wood)
		root.set_meta("weapon_key", weapon_key)
		root.set_meta("bloodiness", bloodiness)
		return _finish_model(root, weapon_key)
	match spec.category:
		"knife":
			_box(root, Vector3(0.06, 0.06, 0.58), Vector3(0, 0, -0.13), steel)
			_box(root, Vector3(0.12, 0.08, 0.26), Vector3(0, 0, 0.29), dark)
		"machete":
			_box(root, Vector3(0.09, 0.055, 0.82), Vector3(0, 0, -0.23), steel)
			_box(root, Vector3(0.14, 0.1, 0.3), Vector3(0, 0, 0.34), dark)
		"baseball_bat":
			_cylinder(root, 0.105, 0.065, 1.02, Vector3(0, 0, -0.08), Vector3(90, 0, 0), wood)
		"crowbar":
			_cylinder(root, 0.045, 0.045, 0.98, Vector3(0, 0, -0.04), Vector3(90, 0, 0), _material(Color("a52b31").lerp(Color("551015"), bloodiness * 0.5), 0.42, 0.68))
			_box(root, Vector3(0.26, 0.06, 0.07), Vector3(0.09, 0, -0.52), steel)
		"fire_axe":
			_cylinder(root, 0.045, 0.05, 0.96, Vector3(0, 0, 0.02), Vector3(90, 0, 0), wood)
			_box(root, Vector3(0.42, 0.1, 0.24), Vector3(0, 0, -0.48), steel)
		"sledgehammer":
			_cylinder(root, 0.052, 0.058, 1.04, Vector3(0, 0, 0.04), Vector3(90, 0, 0), wood)
			_box(root, Vector3(0.48, 0.24, 0.24), Vector3(0, 0, -0.52), steel)
		"frag", "smoke", "flash", "incendiary":
			_cylinder(root, 0.13, 0.13, 0.32, Vector3.ZERO, Vector3.ZERO, dark)
			_box(root, Vector3(0.08, 0.08, 0.18), Vector3(0, 0.23, 0), steel)
		_:
			var body_length := 0.46 if spec.slot == LocalStrikeWeaponDefinition.Slot.SECONDARY else (0.94 if spec.category in ["sniper", "dmr", "shotgun", "auto_shotgun"] else clampf(0.62 + spec.weight * 0.1, 0.68, 0.82))
			var body_width := 0.2 if spec.category in ["lmg", "battle_rifle"] else 0.18
			_box(root, Vector3(body_width, 0.16, body_length), Vector3.ZERO, dark)
			_cylinder(root, 0.032, 0.044, body_length * 0.72, Vector3(0, 0, -body_length * 0.68), Vector3(90, 0, 0), steel)
			_box(root, Vector3(0.12, 0.28, 0.15), Vector3(0, -0.18, body_length * 0.18), dark)
			var accent_colors := [Color("d7a33f"), Color("4fa6a0"), Color("a84b4d"), Color("6687ad"), Color("9b7bb5")]
			var accent_index := absi(weapon_key.hash()) % accent_colors.size()
			var accent := _material(accent_colors[accent_index], 0.46, 0.38)
			_box(root, Vector3(0.035, 0.07, body_length * 0.46), Vector3(body_width * 0.56, 0.035, -0.04), accent)
			if spec.category in ["sniper", "dmr"]:
				_cylinder(root, 0.055, 0.055, 0.34, Vector3(0, 0.14, -0.08), Vector3(90, 0, 0), steel)
	root.set_meta("weapon_key", weapon_key)
	root.set_meta("bloodiness", bloodiness)
	return _finish_model(root, weapon_key)

static func _finish_model(root: Node3D, key: String) -> Node3D:
	var spec := Catalog.get_weapon(key)
	var grip := Vector3(0, -0.085, 0.35)
	var muzzle := Vector3(0, 0.12, -0.54)
	if spec.slot == LocalStrikeWeaponDefinition.Slot.SECONDARY:
		grip = Vector3(0, -0.055, 0.18)
		muzzle = Vector3(0, 0.1, -0.29)
	elif spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE:
		grip = Vector3(0, 0, 0.35)
		muzzle = Vector3(0, 0, -0.54)
	elif spec.slot == LocalStrikeWeaponDefinition.Slot.GRENADE:
		grip = Vector3.ZERO
		muzzle = Vector3(0, 0.2, 0)
	match key:
		"knife":
			grip = Vector3(0, 0, 0.17)
			muzzle = Vector3(0, 0, -0.25)
		"kestrel":
			grip = Vector3(0, -0.14, 0.055)
			muzzle = Vector3(0, 0.02, -0.37)
		"doublebarrel":
			grip = Vector3(0, -0.08, 0.21)
			muzzle = Vector3(0, 0, -0.71)
		"longbow":
			grip = Vector3(0, -0.14, 0.12)
			muzzle = Vector3(0, 0.015, -0.83)
	for child in root.get_children():
		if child is Node3D:
			child.position -= grip
	root.set_meta("grip", Vector3.ZERO)
	root.set_meta("support", Vector3(-0.025, -0.005, -0.20) if spec.slot == LocalStrikeWeaponDefinition.Slot.PRIMARY else Vector3(-0.055, -0.035, 0.01))
	root.set_meta("muzzle", muzzle - grip)
	return root

static func has_external_model(weapon_key: String) -> bool:
	return EXTERNAL_MODELS.has(weapon_key)

static func has_detailed_model(weapon_key: String) -> bool:
	return has_external_model(weapon_key) or weapon_key in CUSTOM_MODELS

static func _build_custom_firearm(root: Node3D, key: String, steel: Material, dark: Material, wood: Material) -> void:
	if key == "kestrel":
		_box(root, Vector3(0.12, 0.12, 0.38), Vector3(0, 0.015, -0.08), steel)
		_box(root, Vector3(0.105, 0.22, 0.14), Vector3(0, -0.14, 0.055), dark)
		_box(root, Vector3(0.08, 0.2, 0.1), Vector3(0, -0.32, 0.045), steel)
		_cylinder(root, 0.025, 0.03, 0.18, Vector3(0, 0.02, -0.28), Vector3(90, 0, 0), dark)
		_box(root, Vector3(0.04, 0.055, 0.035), Vector3(0, 0.095, -0.22), dark)
		_box(root, Vector3(0.1, 0.04, 0.045), Vector3(0, 0.09, 0.08), dark)
		_box(root, Vector3(0.115, 0.05, 0.16), Vector3(0, -0.14, -0.08), dark)
	elif key == "doublebarrel":
		for side in [-1.0, 1.0]:
			_cylinder(root, 0.038, 0.042, 0.72, Vector3(side * 0.045, 0, -0.34), Vector3(90, 0, 0), steel)
			_cylinder(root, 0.03, 0.03, 0.008, Vector3(side * 0.045, 0, -0.706), Vector3(90, 0, 0), dark)
		_box(root, Vector3(0.16, 0.12, 0.18), Vector3(0, -0.015, 0.09), steel)
		_box(root, Vector3(0.13, 0.085, 0.36), Vector3(0, -0.075, -0.25), wood)
		_box(root, Vector3(0.12, 0.14, 0.35), Vector3(0, -0.08, 0.35), wood)
		_box(root, Vector3(0.13, 0.18, 0.045), Vector3(0, -0.08, 0.55), dark)
		_box(root, Vector3(0.025, 0.035, 0.035), Vector3(0, 0.05, -0.65), steel)
	else:
		var olive := _material(Color("57674c"), 0.75, 0.1)
		_box(root, Vector3(0.13, 0.14, 0.55), Vector3(0, -0.02, -0.02), olive)
		_cylinder(root, 0.025, 0.04, 0.64, Vector3(0, 0.015, -0.51), Vector3(90, 0, 0), steel)
		_box(root, Vector3(0.105, 0.2, 0.12), Vector3(0, -0.14, 0.12), dark)
		_box(root, Vector3(0.12, 0.17, 0.28), Vector3(0, -0.035, 0.38), olive)
		_box(root, Vector3(0.14, 0.2, 0.04), Vector3(0, -0.035, 0.54), dark)
		for z in [-0.15, 0.08]:
			_box(root, Vector3(0.06, 0.07, 0.04), Vector3(0, 0.1, z), steel)
		_cylinder(root, 0.047, 0.047, 0.35, Vector3(0, 0.17, -0.04), Vector3(90, 0, 0), dark)
		_cylinder(root, 0.061, 0.061, 0.08, Vector3(0, 0.17, -0.21), Vector3(90, 0, 0), steel)
		_box(root, Vector3(0.13, 0.035, 0.035), Vector3(0.1, 0.035, 0.05), steel)

static func _apply_external_material(node: Node, weapon_key: String, bloodiness: float) -> void:
	if node is MeshInstance3D:
		var accent_colors := [Color("7f8e92"), Color("485c62"), Color("8a6540"), Color("566c83"), Color("765d74")]
		var tint: Color = accent_colors[absi(weapon_key.hash()) % accent_colors.size()]
		tint = tint.lerp(Color("541117"), bloodiness * 0.62)
		var material := Materials.create("steel_plate", tint, 1.35).duplicate() as StandardMaterial3D
		material.roughness = 0.48
		node.material_override = material
	for child in node.get_children():
		_apply_external_material(child, weapon_key, bloodiness)

static func _fit_imported_model(imported: Node3D, target_extent: float) -> void:
	var state := {"has_bounds": false, "bounds": AABB()}
	_collect_bounds(imported, imported, Transform3D.IDENTITY, state)
	if not bool(state.has_bounds):
		return
	var bounds: AABB = state.bounds
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if longest <= 0.001:
		return
	var factor := target_extent / longest
	imported.scale *= factor
	imported.position = -bounds.get_center() * factor

static func _collect_bounds(root: Node3D, node: Node, parent_transform: Transform3D, state: Dictionary) -> void:
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

static func collision_size(weapon_key: String) -> Vector3:
	var spec := Catalog.get_weapon(weapon_key)
	if spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE:
		return Vector3(0.34 if spec.category in ["fire_axe", "sledgehammer"] else 0.16, 0.18, 1.08)
	if spec.slot == LocalStrikeWeaponDefinition.Slot.GRENADE:
		return Vector3(0.28, 0.36, 0.28)
	return Vector3(0.2, 0.15, 0.48 if spec.slot == LocalStrikeWeaponDefinition.Slot.SECONDARY else 0.82)

static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

static func _box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)
	return instance

static func _cylinder(parent: Node3D, top_radius: float, bottom_radius: float, height: float, position: Vector3, rotation: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 12
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation
	instance.material_override = material
	parent.add_child(instance)
	return instance
