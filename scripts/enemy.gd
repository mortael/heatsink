class_name Enemy
extends CharacterBody2D
## Shared enemy plumbing: HP, damage flash, knockback, embedded rivets, separation.

const MAX_RIVETS := 8
const RIVET_LIFE := 6.0

var game: Node
var max_hp := 10.0
var hp := 10.0
var radius := 13.0
var dead := false
var source_name := "Enemy"
var flash_frames := 0
var flash_crit := false
var knock := Vector2.ZERO
var rivets: Array = [] # each: [time_left, angle]


func _ready() -> void:
	hp = max_hp
	collision_layer = C.LAYER_ENEMY
	collision_mask = C.LAYER_WALL
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = radius
	cs.shape = sh
	add_child(cs)
	add_to_group("enemies")
	z_index = 2


func _physics_process(delta: float) -> void:
	if dead:
		return
	if flash_frames > 0:
		flash_frames -= 1
	for i in range(rivets.size() - 1, -1, -1):
		rivets[i][0] -= delta
		if rivets[i][0] <= 0.0:
			rivets.remove_at(i)
	_ai(delta)
	var k := knock
	velocity += k
	knock = knock.move_toward(Vector2.ZERO, 1800.0 * delta)
	move_and_slide()
	velocity -= k
	queue_redraw()


func _ai(_delta: float) -> void:
	pass


func rivet_count() -> int:
	return rivets.size()


func embed_rivet() -> void:
	if rivets.size() >= MAX_RIVETS:
		rivets.remove_at(0)
	rivets.append([RIVET_LIFE, randf() * TAU])


func clear_rivets() -> void:
	rivets.clear()


func take_damage(amount: float, crit: bool, push: Vector2, kind: String) -> void:
	if dead:
		return
	hp -= amount
	flash_frames = 3
	flash_crit = crit
	knock += push
	game.fx.number(global_position + Vector2(0, -radius - 6), amount, crit)
	if kind == "rivet":
		Sfx.play("hit", 0.0, -8.0)
	if crit:
		Sfx.play("crit", 0.0, -4.0)
		Juice.hitstop(5)
		Juice.add_trauma(0.12)
	elif kind == "rivet":
		Juice.hitstop(2)
		Juice.add_trauma(0.04)
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	remove_from_group("enemies")
	game.fx.pop(global_position, Color(0.55, 0.38, 0.28))
	Sfx.play_ramp("kill", -4.0)
	Juice.hitstop(2)
	game.on_enemy_killed(self)
	queue_free()


## Push away from neighbours so packs spread into a readable crowd.
func _separation() -> Vector2:
	var push := Vector2.ZERO
	var reach := radius * 2.0 + 0.6 * C.TILE
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == self:
			continue
		var d: Vector2 = global_position - o.global_position
		var l := d.length()
		if l < reach and l > 0.01:
			push += d / l * (1.0 - l / reach)
	return push


## White flash: full for 1 frame, 50% for the next 2.
func flash_color(base: Color) -> Color:
	if flash_frames <= 0:
		return base
	var tint := Color(1, 0.95, 0.6) if flash_crit else Color.WHITE
	return tint if flash_frames == 3 else base.lerp(tint, 0.5)


func draw_rivets(r: float) -> void:
	for rv in rivets:
		var p := Vector2.from_angle(rv[1]) * (r - 3.0)
		draw_circle(p, 3.2, Color(0.25, 0.25, 0.27))
		draw_circle(p, 2.0, Color(0.85, 0.87, 0.9))
