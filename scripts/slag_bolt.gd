class_name SlagBolt
extends Node2D
## A slow glob of slag spat by a Slagspitter. Flies straight, dies on walls, costs 1 pip on contact.
## Dash i-frames pass through it, like every other hit.

const RADIUS := 7.0
const LIFE := 4.0

var game: Node
var vel := Vector2.ZERO
var life := LIFE
var source := "Slagspitter · Slag bolt"


func _ready() -> void:
	z_index = 3
	add_to_group("enemy_bolts")


func _physics_process(delta: float) -> void:
	if game.dead:
		return
	life -= delta
	position += vel * delta
	if life <= 0.0 or not game.room.is_open(global_position, 2.0):
		game.fx.sparks(global_position, -vel.normalized(), 4, Color(1, 0.6, 0.25))
		queue_free()
		return
	var p: Player = game.player
	if p.global_position.distance_to(global_position) < RADIUS + Player.RADIUS - 2.0 and not p.is_invulnerable():
		p.take_hit(1, source)
		game.fx.sparks(global_position, -vel.normalized(), 8, Color(1, 0.6, 0.25))
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS + 5.0, Color(C.TELE_LINE, 0.18))
	draw_line(Vector2.ZERO, -vel.normalized() * 16.0, Color(1, 0.55, 0.2, 0.45), RADIUS)
	draw_circle(Vector2.ZERO, RADIUS, Color(1.0, 0.55, 0.18))
	draw_circle(Vector2.ZERO, RADIUS * 0.55, Color(1.0, 0.92, 0.7))
	draw_arc(Vector2.ZERO, RADIUS + 1.0, 0, TAU, 14, C.TELE_LINE, 1.5)
