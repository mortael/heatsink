class_name Rivet
extends Node2D
## Rivet Gun projectile. Embeds in enemies; in Overdrive it pierces 1 and ricochets once.

const SPEED := 14.0 * C.TILE
const DAMAGE := 8.0

var game: Node
var dir := Vector2.RIGHT
var overdrive := false
var pierce := 0
var ricochet := 0
var life := 1.4
var _exclude: Array[RID] = []


func _ready() -> void:
	z_index = 4


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var remaining := SPEED * delta
	var space := get_world_2d().direct_space_state
	var guard := 0
	while remaining > 0.0 and guard < 4:
		guard += 1
		var to := global_position + dir * remaining
		var q := PhysicsRayQueryParameters2D.create(global_position, to, C.LAYER_WALL | C.LAYER_ENEMY, _exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			global_position = to
			break
		var hit_pos: Vector2 = hit.position
		remaining -= global_position.distance_to(hit_pos)
		global_position = hit_pos
		var col: Object = hit.collider
		if col is Enemy:
			_hit_enemy(col as Enemy)
			if pierce > 0:
				pierce -= 1
				_exclude.append(hit.rid)
				continue
			queue_free()
			return
		var normal: Vector2 = hit.normal
		if ricochet > 0:
			ricochet -= 1
			dir = dir.bounce(normal)
			global_position += normal * 2.0
			game.fx.sparks(global_position, normal, 5, C.RIVET_GOLD)
			Sfx.play("ricochet", 0.0, -8.0)
			continue
		game.fx.sparks(global_position, normal, 3, C.STEEL)
		queue_free()
		return
	queue_redraw()


func _hit_enemy(e: Enemy) -> void:
	var crit := randf() < Player.CRIT_CHANCE
	var dmg := DAMAGE * (2.0 if crit else 1.0)
	e.embed_rivet()
	e.take_damage(dmg, crit, dir * 110.0, "rivet")


func _draw() -> void:
	var col := C.RIVET_GOLD if overdrive else Color(0.85, 0.88, 0.92)
	var back := -dir * (22.0 if overdrive else 14.0)
	draw_line(back, Vector2.ZERO, Color(col, 0.35), 5.0)
	draw_line(back * 0.5, Vector2.ZERO, col, 3.0)
	draw_circle(Vector2.ZERO, 2.5, Color.WHITE)
