extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1440, 900)
	var args := OS.get_cmdline_user_args()
	var kind := args[0] if args.size() > 0 else "bots"
	var output := args[1] if args.size() > 1 else "res://docs/weapon-holding.png"
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("25313b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c6d5e3")
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 1.6
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(2.8, 2.3, -5.2) if kind in ["bots", "lan"] else Vector3(0, 0.7, 5)
	camera.look_at(Vector3(0, 0.95, 0) if kind in ["bots", "lan"] else Vector3(0, 0.7, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.4
	var keys: Array = ["ranger", "kestrel", "knife"] if kind in ["bots", "lan"] else ["ranger", "sidearm", "knife", "fire_axe", "longbow", "doublebarrel"]
	for index in range(keys.size()):
		var key: String = keys[index]
		var x := (index % 3 - 1) * 1.8
		var label := Label3D.new()
		label.text = key.to_upper()
		label.font_size = 42
		label.pixel_size = 0.003
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(label)
		if kind == "lan":
			var avatar = load("res://scripts/network_avatar.gd").new()
			avatar.configure(index + 2, index % 2)
			world.add_child(avatar)
			avatar.position.x = x
			avatar.apply_snapshot(avatar.position, 0.0, 100.0, LocalStrikeWeaponCatalog.get_weapon(key).display_name)
			avatar.set_physics_process(false)
			label.position = Vector3(x, 2.05, 0)
		elif kind == "bots":
			var bot = load("res://scripts/enemy.gd").new()
			bot.configure_spawn(0, ["assault", "heavy", "scout"][index], key, "passive", Vector3.ZERO)
			world.add_child(bot)
			bot.position.x = x
			bot.set_physics_process(false)
			label.position = Vector3(x, 2.05, 0)
		else:
			var model = load("res://scripts/weapon_model.gd").create(key)
			world.add_child(model)
			model.position = Vector3(x, 1.5 - (index / 3) * 1.4, 0)
			model.rotation.y = PI * 0.5
			label.position = model.position + Vector3(0, 0.4, 0)
	for frame in range(30):
		await process_frame
	var error := root.get_texture().get_image().save_png(output)
	print("HOLD_CAPTURE ", error)
	world.queue_free()
	for frame in range(5):
		await process_frame
	quit(error)
