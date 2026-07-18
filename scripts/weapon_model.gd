class_name LocalStrikeWeaponModel
extends RefCounted

const Catalog = preload("res://scripts/weapon_catalog.gd")

static func create(weapon_key: String, bloodiness := 0.0) -> Node3D:
	var spec := Catalog.get_weapon(weapon_key)
	var root := Node3D.new()
	root.name = "%sModel" % spec.display_name.to_pascal_case()
	var steel := _material(Color("8d999f").lerp(Color("58141a"), bloodiness * 0.68), 0.34, 0.72)
	var dark := _material(Color("242d33").lerp(Color("4d1116"), bloodiness * 0.42), 0.62, 0.28)
	var wood := _material(Color("71442b").lerp(Color("55151a"), bloodiness * 0.5), 0.8, 0.02)
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
	return root

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
