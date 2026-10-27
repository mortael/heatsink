class_name SlagPool
extends Node2D
## Molten pool the Sink leaves behind (Furnace's third hit, Molten items). It only burns enemies:
## 6 damage per second to everything standing in it. Molten Resonance makes pools bigger and longer.

const LIFE := 2.0
const RADIUS := 1.5 * C.TILE
const DPS := 6.0
const TICK := 0.25

var game: RunGame
var radius := RADIUS
var life := LIFE
var dps := DPS
var _max_life := LIFE
var _tick := TICK
var _seed := randf() * 10.0


func _ready() -> void:
	z_index = 1
	var inv: Inventory = game.inventory
	radius *= inv.molten_scale()
	life += inv.molten_extra_life()
	_max_life = life
	add_to_group("slag_pools")
	Sfx.play_ramp("glug", -10.0)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick += TICK
		for o in get_tree().get_nodes_in_group("enemies"):
			var e: Enemy = o
			if not e.dead and e.global_position.distance_to(global_position) < radius + e.radius * 0.5:
				e.take_damage(dps * TICK, false, Vector2.ZERO, Enemy.DamageKind.MOLTEN)
				game.effects.on_molten_tick(e)
	queue_redraw()


func _draw() -> void:
	if Upright.on: # a flat puddle on the 2.5D floor, not a top-down disc
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.15, 0.45))
	var fade := clampf(life / _max_life * 3.0, 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0 + _seed
	Lava.pool(self, radius, t, _seed, fade)
