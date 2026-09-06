extends SkeletonModifier3D

var actor: Node3D
var weapon_key := "sidearm"
var right_basis := Basis.IDENTITY
var hand_offset := Vector3(0, -0.015, -0.045)
var support_offset := Vector3(-0.025, -0.005, -0.20)
var weapon_scale := 0.82
var body_scale := 1.0
var right_target_world := Vector3.ZERO
var left_target_world := Vector3.ZERO

func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not is_instance_valid(actor) or actor.health <= 0.0:
		return
	var spec := LocalStrikeWeaponCatalog.get_weapon(weapon_key)
	if spec.slot == LocalStrikeWeaponDefinition.Slot.MELEE:
		return # Melee keeps the authored slash and swing animation.
	var right_target := Vector3(0.12, 1.27, -0.12) * body_scale
	right_target_world = actor.to_global(right_target)
	var world_basis := actor.global_basis.orthonormalized() * right_basis
	_solve_arm(skeleton, "R", right_target_world, actor.global_basis * Vector3(0.7, -1, 0.2), world_basis)
	var wrist: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Wrist.R"))
	var grip := wrist.origin + actor.global_basis * hand_offset * body_scale
	left_target_world = grip + actor.global_basis * support_offset * weapon_scale
	_solve_arm(skeleton, "L", left_target_world, actor.global_basis * Vector3(-0.7, -1, 0.2), actor.global_basis * Basis(Vector3.FORWARD, PI) * right_basis)

func _solve_arm(skeleton: Skeleton3D, side: String, target_world: Vector3, pole_world: Vector3, wrist_basis_world: Basis) -> void:
	var upper := skeleton.find_bone("UpperArm." + side)
	var lower := skeleton.find_bone("LowerArm." + side)
	var wrist := skeleton.find_bone("Wrist." + side)
	if mini(upper, mini(lower, wrist)) < 0:
		return
	var inverse := skeleton.global_transform.affine_inverse()
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var elbow := skeleton.get_bone_global_pose(lower).origin
	var hand := skeleton.get_bone_global_pose(wrist).origin
	var a := shoulder.distance_to(elbow)
	var b := elbow.distance_to(hand)
	var reach := inverse * target_world - shoulder
	if reach.length_squared() < 0.000001 or minf(a, b) < 0.001:
		return
	var distance := clampf(reach.length(), absf(a - b) + 0.001, a + b - 0.002)
	var direction := reach.normalized()
	var pole := inverse.basis * pole_world
	pole = (pole - direction * pole.dot(direction)).normalized()
	var along := (a * a + distance * distance - b * b) / (2.0 * distance)
	var bend := sqrt(maxf(0.0, a * a - along * along))
	var desired_elbow := shoulder + direction * along + pole * bend
	_rotate_toward(skeleton, upper, elbow - shoulder, desired_elbow - shoulder)
	elbow = skeleton.get_bone_global_pose(lower).origin
	hand = skeleton.get_bone_global_pose(wrist).origin
	_rotate_toward(skeleton, lower, hand - elbow, shoulder + direction * distance - elbow)
	_set_global_rotation(skeleton, wrist, inverse.basis.orthonormalized() * wrist_basis_world.orthonormalized())

func _rotate_toward(skeleton: Skeleton3D, index: int, from: Vector3, to: Vector3) -> void:
	var rotation := Basis(Quaternion(from.normalized(), to.normalized()))
	_set_global_rotation(skeleton, index, rotation * skeleton.get_bone_global_pose(index).basis.orthonormalized())

func _set_global_rotation(skeleton: Skeleton3D, index: int, basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(index)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(index, (parent_basis.inverse() * basis).get_rotation_quaternion().normalized())
