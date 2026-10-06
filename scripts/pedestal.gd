class_name Pedestal
extends Node2D
## Something to interact with in a non-combat room: a shop item, a repair, an altar, the Crucible.
## Stand next to it to read it, press Interact (E / pad A) to use it. Game.use_pedestal does the work.

const REACH := 1.4 * C.TILE

var game: Node
var kind := "item" # item, repair, reroll, vault_repair, altar, crucible, coinflip
var item_id := ""
var price := 0
var title := ""
var lines: Array[String] = []
var color := Color.WHITE
var active := true
var near := false


func _ready() -> void:
	z_index = 2


func _process(_delta: float) -> void:
	near = active and not game.dead and game.player.global_position.distance_to(global_position) < REACH
	queue_redraw()


func affordable() -> bool:
	return game.scrap >= price


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var a := 1.0 if active else 0.25
	# Plinth
	draw_rect(Rect2(-20, 4, 40, 16), Color(0.2, 0.17, 0.15, a))
	draw_rect(Rect2(-20, 4, 40, 16), Color(color, 0.6 * a), false, 1.5)
	var bob := sin(Time.get_ticks_msec() / 300.0 + position.x) * 3.0 if active else 0.0
	var c := Vector2(0, -12 + bob)
	match kind:
		"item":
			draw_rect(Rect2(c + Vector2(-10, -13), Vector2(20, 26)), Color(0.1, 0.08, 0.07, a))
			draw_rect(Rect2(c + Vector2(-10, -13), Vector2(20, 26)), Color(color, a), false, 2.0)
			draw_circle(c, 4.0, Color(color, a))
		"repair", "vault_repair":
			draw_rect(Rect2(c + Vector2(-11, -4), Vector2(22, 8)), Color(color, a))
			draw_rect(Rect2(c + Vector2(-4, -11), Vector2(8, 22)), Color(color, a))
		"reroll":
			draw_arc(c, 10.0, 0.3, TAU - 0.3, 20, Color(color, a), 3.0)
			draw_line(c + Vector2(10, -4), c + Vector2(13, 3), Color(color, a), 3.0)
		"altar":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14), c + Vector2(9, 8), c + Vector2(-9, 8)]), Color(color, a))
			draw_circle(c + Vector2(0, 2), 4.0, Color(1, 0.9, 0.6, a))
		"crucible", "coinflip":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -9), c + Vector2(14, -9), c + Vector2(9, 12), c + Vector2(-9, 12)]), Color(color, a))
			draw_circle(c + Vector2(0, -12), 6.0 + 1.5 * sin(Time.get_ticks_msec() / 150.0), Color(1, 0.55, 0.2, a))
	if price > 0 and active:
		var pc := Color(1, 0.85, 0.3) if affordable() else Color(0.75, 0.4, 0.35)
		draw_string(font, Vector2(-40, 38), "%d scrap" % price, HORIZONTAL_ALIGNMENT_CENTER, 80, 12, pc)
	if not near:
		draw_string(font, Vector2(-70, -36), title, HORIZONTAL_ALIGNMENT_CENTER, 140, 11, Color(color, 0.8 * a))
		return
	# Detail card above the pedestal while the player stands next to it.
	var w := 300.0
	var h := 48.0 + 17.0 * _line_count(font, w - 24)
	var box := Rect2(-w * 0.5, -40 - h, w, h)
	if global_position.y - 40 - h < C.TILE:
		box.position.y = 44 # no room above: show it below
	draw_rect(box, Color(0.08, 0.07, 0.06, 0.95))
	draw_rect(box, Color(color, 0.9), false, 2.0)
	draw_string(font, box.position + Vector2(12, 22), title, HORIZONTAL_ALIGNMENT_LEFT, w - 24, 15, color)
	var y := box.position.y + 42
	for l in lines:
		var col := Color(1, 0.45, 0.45) if l.begins_with("!") else Color(0.88, 0.86, 0.84)
		var text := l.trim_prefix("!")
		draw_multiline_string(font, Vector2(box.position.x + 12, y), text, HORIZONTAL_ALIGNMENT_LEFT, w - 24, 12, -1, col)
		y += 17.0 * _wrapped(font, text, w - 24)
	var prompt := "E / A: " + ("BUY" if price > 0 else "USE")
	if price > 0 and not affordable():
		prompt = "NOT ENOUGH SCRAP"
	draw_string(font, Vector2(box.position.x, box.end.y - 8), prompt, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(1, 1, 1, 0.75))


func _line_count(font: Font, width: float) -> int:
	var n := 1
	for l in lines:
		n += _wrapped(font, l.trim_prefix("!"), width)
	return n


func _wrapped(font: Font, text: String, width: float) -> int:
	return maxi(1, ceili(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x / (width * 0.92)))
