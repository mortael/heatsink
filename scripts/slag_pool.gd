class_name SlagPool
extends Node2D
## Molten pool the Sink leaves behind (Furnace's third hit, Molten items). It only burns enemies:
## 6 damage per second to everything standing in it. Molten Resonance makes pools bigger and longer.

const LIFE := 2.0
const RADIUS := 1.5 * C.TILE
const DPS := 6.0
const TICK := 0.25

var game: Node
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
				e.take_damage(dps * TICK, false, Vector2.ZERO, "molten")
				game.inventory.on_molten_tick(e)
	queue_redraw()


func _draw() -> void:
	var fade := clampf(life / _max_life * 3.0, 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0 + _seed
	draw_circle(Vector2.ZERO, radius, Color(0.75, 0.28, 0.05, 0.22 * fade))
	draw_circle(Vector2.ZERO, radius * 0.7, Color(1.0, 0.55, 0.15, 0.16 * fade))
	# Glossy blobs with a highlight, bubbling (GDD section 8: Molten = round blobs).
	for i in 5:
		var ang := i * TAU / 5.0 + t * 0.4
		var r := radius * (0.3 + 0.25 * sin(t * 2.0 + i))
		var p := Vector2.from_angle(ang) * r
		var s := radius * 0.18 * (0.8 + 0.2 * sin(t * 5.0 + i * 1.7))
		draw_circle(p, s, Color(1.0, 0.75, 0.3, 0.5 * fade))
		draw_circle(p + Vector2(-s * 0.3, -s * 0.3), s * 0.3, Color(1, 1, 0.85, 0.7 * fade))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 28, Color(1.0, 0.7, 0.3, 0.45 * fade), 2.0)
