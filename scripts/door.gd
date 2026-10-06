class_name Door
extends Node2D
## A door in the top wall that previews the next room (GDD section 4, "Route risk").
## Sealed while enemies remain; once open, walking into it takes you through.

var game: Node
var kind := "combat_item"
var slot := 0
var open := false
var _glow := 0.0


func _ready() -> void:
	z_index = 1
	position = game.room.door_point(slot)


func _process(delta: float) -> void:
	_glow = minf(1.0, _glow + delta * 2.0) if open else 0.0
	if open and not game.dead and not game.in_transition():
		var p: Player = game.player
		if absf(p.global_position.x - global_position.x) < C.TILE * 0.9 and p.global_position.y < global_position.y + Player.RADIUS + 4.0:
			game.take_door(self)
	queue_redraw()


func _draw() -> void:
	var t := C.TILE
	var info: Dictionary = RunMap.KINDS[kind]
	var col: Color = info.color
	var frame := Rect2(-t, -t * 1.0, 2 * t, t)
	# Opening in the wall
	draw_rect(frame, Color(0.05, 0.04, 0.04) if open else Color(0.13, 0.11, 0.1))
	draw_rect(frame.grow(3), Color(col, 0.9 if open else 0.45), false, 3.0)
	if not open:
		for i in 5:
			var x := -t + 8 + i * (2 * t - 16) / 4.0
			draw_line(Vector2(x, -t + 2), Vector2(x, -2), Color(0.45, 0.4, 0.38), 3.0)
	else:
		draw_rect(frame.grow(-4), Color(col, 0.12 + 0.1 * _glow * (0.6 + 0.4 * sin(Time.get_ticks_msec() / 200.0))))
	# Icon plate below the door
	var c := Vector2(0, t * 0.62)
	draw_circle(c, 17.0, Color(0.06, 0.05, 0.05, 0.9))
	draw_arc(c, 17.0, 0, TAU, 28, Color(col, 0.95 if open else 0.5), 2.0)
	_icon(c, Color(col, 1.0 if open else 0.55))
	var font := ThemeDB.fallback_font
	var a := 1.0 if open else 0.6
	draw_string(font, Vector2(-80, t * 0.62 + 34), info.name, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color(col, a))
	draw_string(font, Vector2(-90, t * 0.62 + 49), info.sub, HORIZONTAL_ALIGNMENT_CENTER, 180, 10, Color(1, 1, 1, 0.55 * a))


func _icon(c: Vector2, col: Color) -> void:
	match kind:
		"combat_item":
			draw_rect(Rect2(c + Vector2(-7, -10), Vector2(14, 20)), col, false, 2.0)
			draw_circle(c, 3.5, col)
		"combat_conductor":
			var bolt := PackedVector2Array([c + Vector2(3, -11), c + Vector2(-5, 1), c + Vector2(1, 1), c + Vector2(-3, 11), c + Vector2(6, -2), c + Vector2(0, -2)])
			draw_colored_polygon(bolt, col)
		"combat_scrap":
			_gear(c, 8.0, col)
		"shop":
			draw_circle(c, 9.0, col)
			draw_string(ThemeDB.fallback_font, c + Vector2(-5, 6), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.1, 0.08, 0.05))
		"vault":
			for i in 3:
				var d := Vector2.from_angle(i * PI / 3.0) * 10.0
				draw_line(c - d, c + d, col, 2.0)
		"wager":
			var cup := PackedVector2Array([c + Vector2(-10, -7), c + Vector2(10, -7), c + Vector2(6, 9), c + Vector2(-6, 9)])
			draw_colored_polygon(cup, col)
			draw_circle(c + Vector2(0, -9), 4.0, Color(1, 0.55, 0.2))
		"gate":
			draw_line(c + Vector2(-9, -9), c + Vector2(9, 9), col, 3.0)
			draw_line(c + Vector2(9, -9), c + Vector2(-9, 9), col, 3.0)
			draw_rect(Rect2(c + Vector2(-12, -12), Vector2(6, 6)), col)
			draw_rect(Rect2(c + Vector2(6, -12), Vector2(6, 6)), col)


func _gear(c: Vector2, r: float, col: Color) -> void:
	for i in 8:
		var d := Vector2.from_angle(i * TAU / 8.0)
		draw_line(c + d * r, c + d * (r + 4.0), col, 3.0)
	draw_arc(c, r, 0, TAU, 20, col, 3.0)
	draw_circle(c, 2.5, col)
