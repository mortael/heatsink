class_name Rivet
extends Node2D
## Rivet Gun projectile. Embeds in enemies; in Overdrive it pierces 1 and ricochets once.
## Drawn additively: a hot white head, a small halo and a tracer that fades out behind it.

const SPEED := 14.0 * C.TILE
const DAMAGE := 8.0

var game: Node
var dir := Vector2.RIGHT
var overdrive := false
var pierce := 0
var ricochet := 0
var life := 1.4
var speed_mult := 1.0
var ricocheted := false
var _travel := 0.0 # px since leaving the gun or the last bounce; the tracer never reaches further back
var _exclude: Array[RID] = []


func _ready() -> void:
	z_index = 4
	material = Glow.additive()


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var remaining := SPEED * speed_mult * delta
	_travel += remaining
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
			_travel = 0.0
			global_position += normal * 2.0
			if not ricocheted and game.inventory.has("rebound_charge"):
				pierce += 2 if game.inventory.is_tempered("rebound_charge") else 1
			ricocheted = true
			game.fx.sparks(global_position, normal, 5, C.RIVET_GOLD)
			Sfx.play("ricochet", 0.0, -8.0)
			continue
		game.fx.sparks(global_position, normal, 3, C.STEEL)
		game.inventory.on_wall_stop(global_position, normal)
		queue_free()
		return
	queue_redraw()


func _hit_enemy(e: Enemy) -> void:
	var inv: Inventory = game.inventory
	var crit := randf() < inv.crit_chance()
	var dmg := DAMAGE * (2.0 if crit else 1.0)
	if ricocheted and inv.has("rebound_charge"):
		dmg *= 2.0 if inv.is_tempered("rebound_charge") else 1.5
	e.embed_rivet()
	inv.on_rivet_hit(e, self, crit) # on-hit effects land before damage, so a killing hit still ignites
	e.take_damage(dmg, crit, dir * 110.0, "rivet")


func _draw() -> void:
	var hot := overdrive or ricocheted
	var col := C.RIVET_GOLD if hot else Color(0.75, 0.85, 1.0)
	var length := minf(_travel, 70.0 if hot else 46.0)
	var side := dir.orthogonal() * (3.0 if hot else 2.2)
	var tail := -dir * length
	# Tracer: a tapered streak, bright at the head and gone at the tail.
	draw_polygon(PackedVector2Array([side, tail + side * 0.2, tail - side * 0.2, -side]),
		PackedColorArray([Color(col, 0.85), Color(col, 0.0), Color(col, 0.0), Color(col, 0.85)]))
	Glow.halo(self, Vector2.ZERO, 16.0 if hot else 12.0, Color(col, 0.55))
	draw_circle(Vector2.ZERO, 2.5, Color.WHITE)
