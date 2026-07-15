class_name LocalStrikeRadar
extends Control

var player_position := Vector3.ZERO
var player_yaw := 0.0
var allies: Array = []
var enemies: Array = []
var sites: Array = []
var world_half_size := 16.5

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(170, 170)

func update_radar(data: Dictionary) -> void:
	player_position = data.get("player_position", Vector3.ZERO)
	player_yaw = data.get("player_yaw", 0.0)
	allies = data.get("allies", [])
	enemies = data.get("enemies", [])
	sites = data.get("sites", [])
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.025, 0.035, 0.045, 0.88), true)
	draw_rect(rect, Color(0.45, 0.65, 0.68, 0.45), false, 2.0)
	for i in range(1, 4):
		var offset := size.x * float(i) / 4.0
		draw_line(Vector2(offset, 0), Vector2(offset, size.y), Color(0.35, 0.48, 0.5, 0.18), 1.0)
		draw_line(Vector2(0, offset), Vector2(size.x, offset), Color(0.35, 0.48, 0.5, 0.18), 1.0)
	for site in sites:
		var site_position: Vector3 = site.get("position", Vector3.ZERO)
		draw_circle(_to_radar(site_position), 6.0, site.get("color", Color.WHITE), false, 2.0)
	for ally in allies:
		draw_circle(_to_radar(ally), 3.5, Color("56d8c5"))
	for enemy in enemies:
		draw_circle(_to_radar(enemy), 3.5, Color("ef5b5b"))
	var center := _to_radar(player_position)
	var forward := Vector2(-sin(player_yaw), -cos(player_yaw))
	var right := Vector2(forward.y, -forward.x)
	var points := PackedVector2Array([center + forward * 8.0, center - forward * 5.0 + right * 4.0, center - forward * 5.0 - right * 4.0])
	draw_colored_polygon(points, Color("f3b447"))

func _to_radar(position: Vector3) -> Vector2:
	var normalized := Vector2(position.x, position.z) / (world_half_size * 2.0) + Vector2(0.5, 0.5)
	return Vector2(normalized.x * size.x, normalized.y * size.y)
