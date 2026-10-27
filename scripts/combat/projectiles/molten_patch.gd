class_name MoltenPatch
extends Node2D
## Molten floor left by Bellows Breath: lasts 3 s and costs 1 pip to stand in.

const LIFE := 3.0
const RADIUS := 0.7 * C.TILE

var game: RunGame
var life := LIFE
var burned := false # each patch costs at most 1 pip
var _seed := randf() * 10.0


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
	if Upright.on: # a flat puddle on the 2.5D floor, not a top-down disc
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.15, 0.45))
	var k := life / LIFE
	var fade := clampf(k * 3.0, 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0 + _seed
	Lava.pool(self, RADIUS, t, _seed, fade, C.TELE_GROUND)
