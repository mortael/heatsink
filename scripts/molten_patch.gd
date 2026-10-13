class_name MoltenPatch
extends Node2D
## Molten floor left by Bellows Breath: lasts 3 s and costs 1 pip to stand in.

const LIFE := 3.0
const RADIUS := 0.7 * C.TILE

var game: Node
var life := LIFE
var burned := false # each patch costs at most 1 pip


func _ready() -> void:
	z_index = 1


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var p: Player = game.player
	if not burned and not game.dead and not p.is_invulnerable() and p.global_position.distance_to(global_position) < RADIUS + Player.RADIUS * 0.5 and p.dash_time <= 0.0:
		burned = true
		p.take_hit(1, "Forgewarden · Molten floor")
	queue_redraw()


func _draw() -> void:
	var k := life / LIFE
	var fade := clampf(k * 3.0, 0.0, 1.0)
	draw_circle(Vector2.ZERO, RADIUS, Color(0.95, 0.3, 0.08, 0.45 * fade))
	draw_circle(Vector2.ZERO, RADIUS * 0.6, Color(1.0, 0.65, 0.2, 0.5 * fade))
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 20, Color(C.TELE_GROUND, 0.8 * fade), 2.0)
