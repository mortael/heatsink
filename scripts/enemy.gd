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
var last_depth := 0 # shard generation that last hit us (limits shard cascades)
var ignite_stacks := 0
var ignite_time := 0.0
var _ignite_tick := 0.0

const IGNITE_DURATION := 3.0
const IGNITE_TICK := 0.5
const IGNITE_DPS_PER_STACK := 4.0


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
	_tick_ignite(delta)
	if dead:
		return
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


func add_ignite(stacks: int, cap: int) -> void:
	if dead or stacks <= 0:
		return
	if ignite_stacks == 0:
		_ignite_tick = IGNITE_TICK
	ignite_stacks = mini(cap, ignite_stacks + stacks)
	ignite_time = IGNITE_DURATION


func clear_ignite() -> void:
	ignite_stacks = 0
	ignite_time = 0.0


func _tick_ignite(delta: float) -> void:
	if ignite_stacks <= 0:
		return
	ignite_time -= delta
	_ignite_tick -= delta
	if randf() < 0.15 + 0.03 * ignite_stacks:
		game.fx.ember(global_position + Vector2(randf_range(-radius, radius), randf_range(-radius, radius) * 0.5))
	if _ignite_tick <= 0.0:
		_ignite_tick += IGNITE_TICK
		take_damage(IGNITE_DPS_PER_STACK * IGNITE_TICK * ignite_stacks, false, Vector2.ZERO, "ignite", last_depth) # keep the shard generation so Ignite kills respect the cascade cap
	if ignite_time <= 0.0:
		clear_ignite()


func take_damage(amount: float, crit: bool, push: Vector2, kind: String, depth := 0) -> void:
	if dead:
		return
	hp -= amount
	last_depth = depth
	knock += push
	if kind == "ignite":
		game.fx.number(global_position + Vector2(0, -radius - 6), amount, false, Color(1, 0.6, 0.25), 14)
	else:
		flash_frames = 3
		flash_crit = crit
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
	game.inventory.on_kill(self)
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


## Status overlay drawn on top of the body: Ignite glow.
func draw_status(r: float) -> void:
	if ignite_stacks > 0:
		var k := clampf(ignite_stacks / 10.0, 0.2, 1.0)
		draw_arc(Vector2.ZERO, r + 3.0, 0, TAU, 20, Color(1, 0.5, 0.12, 0.5 + 0.4 * k), 2.0 + 2.0 * k)


func draw_rivets(r: float) -> void:
	for rv in rivets:
		var p := Vector2.from_angle(rv[1]) * (r - 3.0)
		draw_circle(p, 3.2, Color(0.25, 0.25, 0.27))
		draw_circle(p, 2.0, Color(0.85, 0.87, 0.9))
