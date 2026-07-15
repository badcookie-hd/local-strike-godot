extends Node

const KENNEY_ROOT := "res://assets/audio/kenney_impact/"

var _cache: Dictionary = {}

func play_shot(position: Vector3, category := "rifle") -> void:
	var key := "shot_%s" % category
	if not _cache.has(key):
		var tone := 150.0 if category in ["sniper", "shotgun"] else (230.0 if category == "pistol" else 190.0)
		_cache[key] = _make_noise_burst(0.16 if category == "sniper" else 0.1, tone, 0.92)
	_play_3d(_cache[key], position, -3.0, 48.0)

func play_explosion(position: Vector3) -> void:
	if not _cache.has("explosion"):
		_cache.explosion = _make_noise_burst(0.62, 54.0, 1.0)
	_play_3d(_cache.explosion, position, 1.0, 70.0)

func play_footstep(position: Vector3) -> void:
	if not _cache.has("footstep"):
		_cache.footstep = _load_stream("footstep_concrete_000.ogg")
		if _cache.footstep == null:
			_cache.footstep = _make_noise_burst(0.075, 88.0, 0.34)
	_play_3d(_cache.footstep, position, -12.0, 18.0)

func play_impact(position: Vector3, surface_type: String, heavy := false) -> void:
	var filename := "impactGeneric_light_000.ogg"
	if surface_type == "metal":
		filename = "impactMetal_medium_000.ogg"
	elif surface_type == "glass":
		filename = "impactGlass_heavy_000.ogg" if heavy else "impactGlass_light_000.ogg"
	var key := "impact_%s_%s" % [surface_type, heavy]
	if not _cache.has(key):
		_cache[key] = _load_stream(filename)
		if _cache[key] == null:
			_cache[key] = _make_noise_burst(0.09, 420.0 if surface_type == "glass" else 180.0, 0.55)
	_play_3d(_cache[key], position, -8.0 if heavy else -13.0, 24.0)

func play_ui() -> void:
	if not _cache.has("ui"):
		_cache.ui = _make_tone(0.055, 760.0, 0.22)
	var player := AudioStreamPlayer.new()
	player.stream = _cache.ui
	player.volume_db = -10.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _play_3d(stream: AudioStream, position: Vector3, volume_db: float, max_distance: float) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.position = position
	player.volume_db = volume_db
	player.max_distance = max_distance
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _load_stream(filename: String) -> AudioStream:
	var path := KENNEY_ROOT + filename
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream

func _make_noise_burst(duration: float, frequency: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var seed := 13579
	for i in range(count):
		seed = int((seed * 1103515245 + 12345) & 0x7fffffff)
		var noise := float(seed % 65536) / 32768.0 - 1.0
		var time := float(i) / rate
		var envelope := exp(-time * (7.0 / duration))
		var body := sin(TAU * frequency * time) * 0.62 + noise * 0.38
		bytes.encode_s16(i * 2, int(clampf(body * envelope * volume, -1.0, 1.0) * 32767.0))
	return _wav(bytes, rate)

func _make_tone(duration: float, frequency: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		var time := float(i) / rate
		var sample := sin(TAU * frequency * time) * (1.0 - float(i) / count) * volume
		bytes.encode_s16(i * 2, int(sample * 32767.0))
	return _wav(bytes, rate)

func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
