extends SceneTree

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var map_index := int(args[0]) if args.size() > 0 else 0
	var profile := int(args[1]) if args.size() > 1 else 0
	var width := int(args[2]) if args.size() > 2 else 1920
	var height := int(args[3]) if args.size() > 3 else 1080
	var output_path := args[4] if args.size() > 4 else "user://visual_capture.png"
	var clean_hud := args.size() > 5 and args[5] == "clean"
	var requested_mode := int(args[6]) if args.size() > 6 else LocalStrikeMatchConfig.Mode.DEATHMATCH
	root.size = Vector2i(width, height)
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	game._start_solo(requested_mode, map_index, LocalStrikeMatchConfig.Difficulty.RECRUIT)
	game._apply_quality(profile)
	if clean_hud:
		game.show_buy = false
	elif requested_mode == LocalStrikeMatchConfig.Mode.SANDBOX:
		game.show_buy = true
	for frame in range(24):
		await process_frame
	game.hud._toast_label.visible = false
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Unable to save visual capture: %s" % error_string(error))
		quit(1)
		return
	print("VISUAL_CAPTURE_OK %s" % output_path)
	quit(0)
