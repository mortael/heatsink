class_name StaticPylon
extends Node2D
## Arclight's Vent leaves one of these where the Sink stood: for 4 s it zaps the nearest enemy
## it can see for 12 damage every 0.5 s.

const LIFE := 4.0
const EVERY := 0.5
const DAMAGE := 12.0
const REACH := 6.0 * C.TILE

var game: Node
var life := LIFE
var zaps := 0
var _cd := 0.15


func _ready() -> void:
	z_index = 3
	material = Glow.additive()


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		game.fx.sparks(global_position, Vector2.UP, 6, Color(0.5, 0.9, 1.0))
		queue_free()
		return
	_cd -= delta
	if _cd <= 0.0:
		_cd += EVERY
		var best: Enemy = null
		var bd := REACH
		for o in get_tree().get_nodes_in_group("enemies"):
			var e: Enemy = o
			var d := e.global_position.distance_to(global_position)
			if not e.dead and d < bd + e.radius and game.room.has_los(global_position, e.global_position):
				bd = d
				best = e
		if best != null:
			zaps += 1
			game.fx.arc(global_position + Vector2(0, -18), best.global_position, 0.15)
			best.take_damage(DAMAGE, false, Vector2.ZERO, "arc")
			Sfx.play("zap", 5.0, -10.0)
	queue_redraw()


func _draw() -> void:
	var k := clampf(life / LIFE * 4.0, 0.0, 1.0)
	var pulse := 0.7 + 0.3 * sin(life * 18.0)
	Glow.halo(self, Vector2(0, -18), 26.0 * pulse, Color(0.45, 0.95, 1.0, 0.7 * k))
	draw_line(Vector2(-9, 6), Vector2(0, -18), Color(0.55, 0.6, 0.66, k), 3.0)
	draw_line(Vector2(9, 6), Vector2(0, -18), Color(0.55, 0.6, 0.66, k), 3.0)
	draw_line(Vector2(0, 6), Vector2(0, -18), Color(0.7, 0.75, 0.8, k), 2.0)
	draw_circle(Vector2(0, -18), 5.0, Color(0.85, 1.0, 1.0, k))
	# Fuse ring: shrinks as the pylon runs down.
	draw_arc(Vector2(0, -18), 10.0, -PI / 2, -PI / 2 + TAU * life / LIFE, 16, Color(0.45, 0.95, 1.0, 0.8 * k), 1.5)
