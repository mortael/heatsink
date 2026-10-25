class_name Rivet
extends Node2D
## Rivet Gun projectile. Embeds in enemies; in Overdrive it pierces 1 and ricochets once.
## Drawn as an energy bolt (additive): a white-hot core, a pulsing coloured glow, a long tracer,
## fizzing motes along the path and a flash of light where it lands.

const SPEED := 14.0 * C.TILE
const DAMAGE := 8.0

var inventory: Inventory
var effects: CombatEffects
var fx: Fx
var dir := Vector2.RIGHT
var overdrive := false
var pierce := 0
var ricochet := 0
var life := 1.4
var speed_mult := 1.0
var ricocheted := false
var _age := randf() * 10.0
var _travel := 0.0 # px since leaving the gun or the last bounce; the tracer never reaches further back
var _exclude: Array[RID] = []


func _ready() -> void:
	z_index = 4
	material = Glow.additive()
	add_to_group("bolts") # Lights hangs a small light on each bolt in flight


## Normal bolts burn electric blue-white; Overdrive and ricochets burn gold.
static func color_for(hot: bool) -> Color:
	return C.RIVET_GOLD if hot else Color(0.5, 0.8, 1.0)


func _physics_process(delta: float) -> void:
	life -= delta
	_age += delta
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
			if randf() < 0.5:
				fx.mote(global_position - dir * randf_range(8.0, 30.0), _color())
			break
		var hit_pos: Vector2 = hit.position
		remaining -= global_position.distance_to(hit_pos)
		global_position = hit_pos
		var col: Object = hit.collider
		if col is Enemy:
			if col.dead:
				_exclude.append(hit.rid)
				continue
			fx.impact(hit_pos, -dir, _color())
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
			if not ricocheted and inventory.has("rebound_charge"):
				pierce += 2 if inventory.is_tempered("rebound_charge") else 1
			ricocheted = true
			fx.impact(global_position, normal, C.RIVET_GOLD)
			Sfx.play("ricochet", 0.0, -8.0)
			continue
		fx.impact(global_position, normal, _color())
		effects.on_wall_stop(global_position, normal)
		queue_free()
		return
	queue_redraw()


func _hit_enemy(e: Enemy) -> void:
	var inv: Inventory = inventory
	var crit := randf() < inv.crit_chance()
	var dmg := DAMAGE * (2.0 if crit else 1.0)
	if ricocheted and inv.has("rebound_charge"):
		dmg *= 2.0 if inv.is_tempered("rebound_charge") else 1.5
	e.embed_rivet()
	effects.on_rivet_hit(e, overdrive, crit) # on-hit effects land before damage, so a killing hit still ignites
	e.take_damage(dmg, crit, dir * 110.0, Enemy.DamageKind.RIVET)


func _color() -> Color:
	return color_for(overdrive or ricocheted)


func _draw() -> void:
	var hot := overdrive or ricocheted
	var col := _color()
	var length := minf(_travel, 90.0 if hot else 64.0)
	var side := dir.orthogonal()
	var tail := -dir * length
	var pulse := 0.85 + 0.15 * sin(_age * 40.0)
	# Tracer: a wide faint streak and a narrow bright one, both gone at the tail.
	var w := 7.0 if hot else 5.5
	draw_polygon(PackedVector2Array([side * w, tail, -side * w]),
		PackedColorArray([Color(col, 0.35), Color(col, 0.0), Color(col, 0.35)]))
	draw_polygon(PackedVector2Array([side * 2.4, tail * 0.7 + side * 0.4, tail * 0.7 - side * 0.4, -side * 2.4]),
		PackedColorArray([Color(col, 1.0), Color(col, 0.0), Color(col, 0.0), Color(col, 1.0)]))
	Glow.halo(self, Vector2.ZERO, 64.0, Color(col, 0.07)) # faint wash on the floor, even beyond the light cap
	Glow.halo(self, Vector2.ZERO, (26.0 if hot else 20.0) * pulse, Color(col, 0.6))
	Glow.halo(self, -dir * 4.0, 9.0, Color(1, 1, 1, 0.9))
	# White-hot core, stretched along the flight line.
	draw_line(-dir * 7.0, dir * 3.0, Color(1, 1, 1), 3.5)
