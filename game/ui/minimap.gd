extends Control
## North-up village compass. Drawn from game locations, with no external map art.
const Catalog = preload("res://game/core/catalog.gd")
var player_position := Vector3.ZERO
var yaw := 0.0

func set_player(pos: Vector3, facing: float) -> void:
	player_position = pos
	yaw = facing
	queue_redraw()

func _draw() -> void:
	var middle := Vector2(106, 106)
	var radius := 96.0
	draw_circle(middle, radius, Color(0.035, 0.085, 0.077, 0.92))
	draw_arc(middle, radius, 0, TAU, 64, Color("bb9e69"), 2.0, true)
	draw_arc(middle, radius - 7, 0, TAU, 64, Color(0.72, 0.65, 0.47, 0.3), 1.0, true)
	# A small map that follows the player's location. North is always up.
	for station in ["market", "vault", "forge", "apothecary", "board", "trainer"]:
		var point: Vector3 = Catalog.STATIONS[station]
		var delta := Vector2(point.x - player_position.x, point.z - player_position.z) * 3.0
		if delta.length() > radius - 17: continue
		var tint := Color("c5a66c") if station == "board" else Color("9aaea0")
		draw_circle(middle + delta, 4.0 if station == "board" else 2.8, tint)
	var gate_delta := Vector2(-player_position.x, -22 - player_position.z) * 3.0
	if gate_delta.length() < radius - 15: draw_circle(middle + gate_delta, 3, Color("b87d5a"))
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-forward.y, forward.x)
	draw_colored_polygon(PackedVector2Array([
		middle + forward * 10,
		middle - forward * 6 + side * 5,
		middle - forward * 6 - side * 5,
	]), Color("f3e5ba"))
	draw_string(get_theme_default_font(), Vector2(101, 24), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("e2c285"))
	draw_string(get_theme_default_font(), Vector2(190, 110), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("8fa396"))
