class_name Shard
extends Node2D
## Shrapnel shard. Normal: short-range triangle. Cluster Embers: homes on Ignited enemies.
## Firestorm Lattice: drifts briefly, then hangs as a burning flare until a Vent detonates it.

const SPEED := 9.0 * C.TILE
const DAMAGE := 6.0
const RANGE_TIME := 0.45
const FLARE_DRIFT := 0.18
const FLARE_LIFE := 1.5
const HOMING_TURN := PI # rad/s
const HOMING_REACH := 6.0 * C.TILE

var game: Node
var dir := Vector2.RIGHT
var depth := 1
var homing := false
var flare := false
var speed_mult := 1.0
var age := 0.0
var _burn_cd := 0.0
var _trail: Array[Vector2] = []


func _ready() -> void:
	z_index = 4
	if flare:
		add_to_group("flares")


func _physics_process(delta: float) -> void:
	age += delta
	var life := FLARE_LIFE if flare else RANGE_TIME * speed_mult
	if age >= life:
		queue_free()
		return
	if flare:
		if age < FLARE_DRIFT:
			_move(SPEED * 0.6 * delta, false)
		else:
			_burn(delta)
		queue_redraw()
		return
	if homing:
		var target := _nearest_ignited()
		if target != null:
			var want := (target.global_position - global_position).angle()
			var cur := dir.angle()
			var diff := wrapf(want - cur, -PI, PI)
			dir = Vector2.from_angle(cur + clampf(diff, -HOMING_TURN * delta, HOMING_TURN * delta))
		_trail.push_front(global_position)
		if _trail.size() > 6:
			_trail.pop_back()
	_move(SPEED * speed_mult * delta, true)
	queue_redraw()


func _move(dist: float, can_hit: bool) -> void:
	var space := get_world_2d().direct_space_state
	var mask := C.LAYER_WALL | (C.LAYER_ENEMY if can_hit else 0)
	var exclude: Array[RID] = []
	for i in 3:
		var q := PhysicsRayQueryParameters2D.create(global_position, global_position + dir * dist, mask, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			global_position += dir * dist
			return
		var col: Object = hit.collider
		if col is Enemy:
			var e := col as Enemy
			if e.dead:
				exclude.append(hit.rid)
				continue
			game.inventory.on_shard_hit(e)
			e.take_damage(DAMAGE, false, dir * 60.0, "shard", depth)
			queue_free()
			return
		# Wall
		if flare:
			global_position = hit.position
			age = FLARE_DRIFT
		else:
			queue_free()
		return


func _burn(delta: float) -> void:
	_burn_cd -= delta
	if _burn_cd > 0.0:
		return
	_burn_cd = 0.3
	for o in get_tree().get_nodes_in_group("enemies"):
		var e: Enemy = o
		if not e.dead and e.global_position.distance_to(global_position) <= e.radius + 10.0:
			e.add_ignite(1, game.inventory.ignite_cap())


func _nearest_ignited() -> Enemy:
	var best: Enemy = null
	var bd := HOMING_REACH
	for o in get_tree().get_nodes_in_group("enemies"):
		var e: Enemy = o
		if e.dead or e.ignite_stacks <= 0:
			continue
		var d := e.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _draw() -> void:
	if flare:
		var pulse := 0.75 + 0.25 * sin(age * 30.0)
		draw_circle(Vector2.ZERO, 9.0 * pulse, Color(1, 0.5, 0.1, 0.25))
		draw_circle(Vector2.ZERO, 4.0, Color(1, 0.95, 0.75))
		return
	if homing:
		for i in _trail.size():
			var k := 1.0 - float(i) / _trail.size()
			draw_circle(to_local(_trail[i]), 3.5 * k, Color(1, 0.55, 0.15, 0.6 * k))
		draw_circle(Vector2.ZERO, 4.0, Color(1, 0.8, 0.4))
		return
	var r := dir.angle()
	var pts := PackedVector2Array([
		Vector2.from_angle(r) * 6.0,
		Vector2.from_angle(r + 2.5) * 4.0,
		Vector2.from_angle(r - 2.5) * 4.0,
	])
	draw_colored_polygon(pts, Color(0.85, 0.88, 0.94))
