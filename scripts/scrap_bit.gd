class_name ScrapBit
extends Node2D
## A Scrap pickup. Pulled in when you get close, and swept to you when the room is cleared.

const MAGNET := 2.5 * C.TILE

var game: Node
var value := 1
var vel := Vector2.ZERO
var sweep := false


func _ready() -> void:
	z_index = 2
	add_to_group("scrap")
	sweep = not game.director.active # dropped by the room's last kill, after the clear sweep
	vel = Vector2.from_angle(randf() * TAU) * randf_range(60.0, 160.0)


func _process(delta: float) -> void:
	if game.dead:
		return
	var p: Player = game.player
	var to := p.global_position - global_position
	if sweep or to.length() < MAGNET:
		vel = vel.lerp(to.normalized() * 700.0, minf(1.0, 8.0 * delta))
	else:
		vel *= pow(0.02, delta)
	position += vel * delta
	if to.length() < Player.RADIUS + 6.0 and is_in_group("scrap"):
		remove_from_group("scrap")
		game.add_scrap(value, false)
		Sfx.play("band", 12.0, -14.0)
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var r := 4.0 + value
	draw_colored_polygon(PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)]), Color(0.95, 0.8, 0.4))
	draw_circle(Vector2.ZERO, 1.5, Color(0.4, 0.3, 0.15))
