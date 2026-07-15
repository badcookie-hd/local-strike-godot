extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var duration := float(args[0]) if args.size() > 0 else 120.0
	var output_path := args[1] if args.size() > 1 else "user://benchmark.json"
	root.size = Vector2i(1920, 1080)
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	game._start_solo(LocalStrikeMatchConfig.Mode.DEATHMATCH, 0, LocalStrikeMatchConfig.Difficulty.VETERAN)
	game._apply_quality(LocalStrikeQualityManager.Profile.HIGH)
	game.show_buy = false
	var actor_count: int = 1 + game.enemies.size() + game.allies.size()
	await create_timer(5.0).timeout
	var samples: Array[float] = []
	var below_target := 0
	var started_at := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - started_at) / 1000.0 < duration:
		await create_timer(0.25).timeout
		var fps := float(Engine.get_frames_per_second())
		samples.append(fps)
		if fps < 55.0:
			below_target += 1
	var average := 0.0
	for sample in samples:
		average += sample
	average /= maxf(1.0, samples.size())
	var result := {
		"duration_seconds": duration,
		"resolution": "1920x1080",
		"profile": "HIGH",
		"actors": actor_count,
		"average_fps": snappedf(average, 0.1),
		"minimum_sample_fps": samples.min() if not samples.is_empty() else 0.0,
		"samples_below_55": below_target,
		"sample_count": samples.size()
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write benchmark result")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("BENCHMARK_OK %s" % JSON.stringify(result))
	quit(0)
