extends Node

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	var room := Room.new(Layouts.COMBAT[0])
	add_child(room)
	for i in 500:
		var point := room.random_open_point(30.0, room.entry_point(), 3.0 * C.TILE)
		check(point.is_finite(), "The room supplies a finite spawn point when one is available")
		check(room.is_open(point, 30.0), "Spawn points retain the requested wall clearance")
		check(point.distance_to(room.entry_point()) >= 3.0 * C.TILE, "Spawn points retain the requested distance from the entry")
	check(room.random_open_point(10000.0) == Vector2.INF, "Impossible body clearance reports placement exhaustion")
	check(room.random_open_point(30.0, room.center(), 10000.0) == Vector2.INF, "Impossible entry separation reports placement exhaustion")
	print("room spawn test: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
