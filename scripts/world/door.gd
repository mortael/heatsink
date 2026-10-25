class_name Door
extends Node2D
## A door in the top wall that previews the next room (GDD section 4, "Route risk").
## Sealed while enemies remain; once open, walking into it takes you through.
## Drawn as neon: glowing tubes in the room's colour that flicker on when the door opens, and
## a glow that spills onto the floor in front of it (drawn, not a Light2D: lights that stay on all
## the time are the expensive kind on phones).

signal traversal_requested(door: Door)

var player: Player
var kind := "combat_item"
var open := false
var _glow := 0.0
var _neon: Node2D
var _was_open := false
var _flicker := 0.0 # seconds of start-up flicker left


func _init() -> void:
	_neon = Node2D.new()
	_neon.material = Glow.additive()
	_neon.draw.connect(_draw_neon)
	add_child(_neon)


func _ready() -> void:
	z_index = 1


func _process(delta: float) -> void:
	_glow = minf(1.0, _glow + delta * 2.0) if open else 0.0
	if open and not _was_open:
		_flicker = 0.6
	_was_open = open
	_flicker = maxf(0.0, _flicker - delta)
	if open and absf(player.global_position.x - global_position.x) < C.TILE * 0.9 and player.global_position.y < global_position.y + Player.RADIUS + 4.0:
		traversal_requested.emit(self)
	queue_redraw()
	_neon.queue_redraw()


## 0..1 brightness of the tubes: a neon sign stutters on, then holds with a faint hum.
func _neon_level() -> float:
	if not open:
		return 0.5
	if _flicker > 0.0:
		return 1.0 if randf() < 0.55 else 0.15
	return 0.92 + 0.08 * sin(Time.get_ticks_msec() / 90.0)


func _draw_neon() -> void:
	var t := C.TILE
	var col: Color = RunMap.KINDS[kind].color
	var k := _neon_level()
	var frame := Rect2(-t, -t, 2 * t, t).grow(3)
	var a := (0.9 if open else 0.3) * k
	var pts := [frame.position, Vector2(frame.end.x, frame.position.y), frame.end, Vector2(frame.position.x, frame.end.y)]
	for i in 4:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % 4]
		Glow.strip(_neon, p0, p1, 44.0, Color(col, 0.4 * a))
		_neon.draw_line(p0, p1, Color(col, 0.5 * a), 1.5)
	if kind == "elite":
		var outer := frame.grow(5)
		Glow.strip(_neon, outer.position, Vector2(outer.end.x, outer.position.y), 18.0, Color(col, 0.5 * a))
	if open:
		# Light pouring through the doorway and over the threshold.
		Glow.halo(_neon, Vector2(0, -t * 0.4), t * 1.1, Color(col, 0.35 * k))
		Glow.halo(_neon, Vector2(0, t * 0.2), t * 1.4, Color(col, 0.18 * k))
		Glow.halo(_neon, Vector2(0, t * 1.2), t * 2.6, Color(col, 0.25 * k)) # spill on the floor
	var c := Vector2(0, t * 0.62)
	Glow.halo(_neon, c, 30.0, Color(col, 0.5 * a))
	_icon(_neon, c, Color(col, 0.8 * a))


func _draw() -> void:
	var t := C.TILE
	var info: Dictionary = RunMap.KINDS[kind]
	var col: Color = info.color
	var frame := Rect2(-t, -t * 1.0, 2 * t, t)
	# Opening in the wall
	draw_rect(frame, Color(0.05, 0.04, 0.04) if open else Color(0.13, 0.11, 0.1))
	draw_rect(frame.grow(3), Color(col, 0.9 if open else 0.45), false, 3.0)
	if kind == "elite":
		draw_rect(frame.grow(8), Color(col, 0.7 if open else 0.35), false, 3.0) # red-framed Elite door
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
	_icon(self, c, Color(col, 1.0 if open else 0.55))
	var font := ThemeDB.fallback_font
	var a := 1.0 if open else 0.6
	draw_string(font, Vector2(-80, t * 0.62 + 34), info.name, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color(col, a))
	draw_string(font, Vector2(-90, t * 0.62 + 49), info.sub, HORIZONTAL_ALIGNMENT_CENTER, 180, 10, Color(1, 1, 1, 0.55 * a))


func _icon(ci: CanvasItem, c: Vector2, col: Color) -> void:
	match kind:
		"combat_item":
			ci.draw_rect(Rect2(c + Vector2(-7, -10), Vector2(14, 20)), col, false, 2.0)
			ci.draw_circle(c, 3.5, col)
		"combat_conductor":
			var bolt := PackedVector2Array([c + Vector2(3, -11), c + Vector2(-5, 1), c + Vector2(1, 1), c + Vector2(-3, 11), c + Vector2(6, -2), c + Vector2(0, -2)])
			ci.draw_colored_polygon(bolt, col)
		"combat_scrap":
			_gear(ci, c, 8.0, col)
		"shop":
			ci.draw_circle(c, 9.0, col)
			ci.draw_string(ThemeDB.fallback_font, c + Vector2(-5, 6), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.1, 0.08, 0.05))
		"vault":
			for i in 3:
				var d := Vector2.from_angle(i * PI / 3.0) * 10.0
				ci.draw_line(c - d, c + d, col, 2.0)
		"wager":
			var cup := PackedVector2Array([c + Vector2(-10, -7), c + Vector2(10, -7), c + Vector2(6, 9), c + Vector2(-6, 9)])
			ci.draw_colored_polygon(cup, col)
			ci.draw_circle(c + Vector2(0, -9), 4.0, Color(1, 0.55, 0.2))
		"elite":
			# A raised hammer: a Forgewarden waits behind this door.
			ci.draw_line(c + Vector2(-8, 9), c + Vector2(5, -4), col, 3.0)
			ci.draw_rect(Rect2(c + Vector2(0, -12), Vector2(13, 9)), col)
		"gate":
			ci.draw_line(c + Vector2(-9, -9), c + Vector2(9, 9), col, 3.0)
			ci.draw_line(c + Vector2(9, -9), c + Vector2(-9, 9), col, 3.0)
			ci.draw_rect(Rect2(c + Vector2(-12, -12), Vector2(6, 6)), col)
			ci.draw_rect(Rect2(c + Vector2(6, -12), Vector2(6, 6)), col)


func _gear(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	for i in 8:
		var d := Vector2.from_angle(i * TAU / 8.0)
		ci.draw_line(c + d * r, c + d * (r + 4.0), col, 3.0)
	ci.draw_arc(c, r, 0, TAU, 20, col, 3.0)
	ci.draw_circle(c, 2.5, col)
