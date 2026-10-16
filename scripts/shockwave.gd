class_name Shockwave
extends Node2D
## Furnace Overdrive: a crest of slag that rolls along the floor from a swing, hitting each enemy once.
## It breaks on walls (Splinter Heads sprays shards from where it breaks).

const SPEED := 13.0 * C.TILE
const WIDTH := 0.55 * C.TILE # half-width of the crest

var game: Node
var dir := Vector2.RIGHT
var max_dist := 4.0 * C.TILE
var damage := 15.0
var hot := true
var _dist := 0.0
var _hit := {}


func _ready() -> void:
	z_index = 4
	material = Glow.additive()


func _physics_process(delta: float) -> void:
	var step := SPEED * delta
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + dir * (step + 6.0), C.LAYER_WALL)
	var wall := space.intersect_ray(q)
	if not wall.is_empty():
		global_position = wall.position
		game.fx.impact(global_position, wall.normal, Color(1, 0.6, 0.25))
		game.inventory.on_wall_stop(global_position, wall.normal)
		queue_free()
		return
	global_position += dir * step
	_dist += step
	var side := dir.orthogonal()
	for o in get_tree().get_nodes_in_group("enemies"):
		var e: Enemy = o
		if e.dead or _hit.has(e):
			continue
		var to := e.global_position - global_position
		if absf(to.dot(dir)) < e.radius + 10.0 and absf(to.dot(side)) < WIDTH + e.radius:
			_hit[e] = true
			game.inventory.on_weapon_hit(e, hot, false)
			e.take_damage(damage, false, dir * 160.0, "shockwave")
	if randf() < 0.6:
		game.fx.sparks(global_position + side * randf_range(-WIDTH, WIDTH), -dir, 1, Color(1, 0.6, 0.2))
	if _dist >= max_dist:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := 1.0 - _dist / max_dist
	var side := dir.orthogonal()
	var col := Color(1.0, 0.7, 0.3)
	Glow.strip(self, side * WIDTH, -side * WIDTH, 34.0, Color(col, k))
	Glow.halo(self, Vector2.ZERO, WIDTH * 1.3, Color(col, 0.35 * k))
	var pts := PackedVector2Array([side * WIDTH, dir * 14.0, -side * WIDTH, -dir * 8.0])
	draw_colored_polygon(pts, Color(1, 0.85, 0.55, 0.85 * k))
