class_name Enemy
extends CharacterBody2D
## Shared enemy plumbing: HP, damage flash, knockback, embedded rivets, separation.

signal defeated(enemy: Enemy)

## OTHER covers test/debug hits that don't need to match a specific source.
enum DamageKind { OTHER, RIVET, SHARD, ARC, VENT, IGNITE, FLARE, BEAM, MAUL, MOLTEN, SHOCKWAVE }

const MAX_RIVETS := 8
const RIVET_LIFE := 6.0

var game: RunGame
var max_hp := 10.0
var hp := 10.0
var radius := 13.0
var dead := false
var source_name := "Enemy"
var tp := 1 # Threat Points this unit costs the director (GDD section 6)
var elite := false
var flash_frames := 0
var flash_crit := false
var knock := Vector2.ZERO
var rivets: Array = [] # each: [time_left, angle]
var last_kind := DamageKind.OTHER # damage kind of the last hit (Hungry Coal counts Vent kills)
var last_depth := 0 # shard generation that last hit us (limits shard cascades)
var ignite_stacks := 0
var ignite_time := 0.0
var _ignite_tick := 0.0
var _beam_sum := 0.0 # Coil Lance ticks are shown as one merged number every BEAM_NUMBER s
var _beam_t := 0.0
var _nav_wp := Vector2.ZERO
var _nav_t := 0.0

const IGNITE_DURATION := 3.0
const IGNITE_TICK := 0.5
const IGNITE_DPS_PER_STACK := 4.0
const BEAM_NUMBER := 0.4


func _ready() -> void:
	max_hp *= Difficulty.value("hp")
	hp = max_hp
	collision_layer = C.LAYER_ENEMY
	collision_mask = C.LAYER_WALL
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = radius
	cs.shape = sh
	add_child(cs)
	add_to_group("enemies")
	z_index = 3 if Upright.on else 2 # 2.5D: same layer as the Sink, so the world's y-sort decides who stands in front


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
	if _beam_sum > 0.0:
		_beam_t -= delta
		if _beam_t <= 0.0:
			_show_beam_number()
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
		take_damage(IGNITE_DPS_PER_STACK * IGNITE_TICK * ignite_stacks, false, Vector2.ZERO, DamageKind.IGNITE, last_depth) # keep the shard generation so Ignite kills respect the cascade cap
	if ignite_time <= 0.0:
		clear_ignite()


func take_damage(amount: float, crit: bool, push: Vector2, kind: DamageKind, depth := 0) -> void:
	if dead:
		return
	hp -= amount
	last_depth = depth
	last_kind = kind
	knock += push
	if kind == DamageKind.IGNITE:
		game.fx.number(global_position + Vector2(0, -radius - 6), amount, false, Color(1, 0.6, 0.25), 14)
	elif kind == DamageKind.BEAM and not crit:
		if _beam_sum <= 0.0:
			_beam_t = BEAM_NUMBER
		_beam_sum += amount
		if flash_frames <= 0 and randf() < 0.35:
			flash_frames = 2
			flash_crit = false
	else:
		flash_frames = 3
		flash_crit = crit
		game.fx.number(global_position + Vector2(0, -radius - 6), amount, crit)
	if kind == DamageKind.RIVET:
		Sfx.play("hit", 0.0, -8.0)
	if crit:
		Sfx.play("crit", 0.0, -4.0)
		Juice.hitstop(5)
		Juice.add_trauma(0.12)
	elif kind == DamageKind.RIVET:
		Juice.hitstop(2)
		Juice.add_trauma(0.04)
	if hp <= 0.0:
		_die()


func _show_beam_number() -> void:
	game.fx.number(global_position + Vector2(0, -radius - 6), _beam_sum, false, Color(0.6, 0.95, 1.0), 16)
	_beam_sum = 0.0


func _die() -> void:
	if _beam_sum > 0.0:
		_show_beam_number()
	dead = true
	remove_from_group("enemies")
	_death_feedback()
	defeated.emit(self)
	queue_free()


func _death_feedback() -> void:
	game.fx.pop(global_position, Color(0.55, 0.38, 0.28))
	Sfx.play_ramp("kill", -4.0)
	Juice.hitstop(2)


## Direction toward target: straight when the way is clear, otherwise along the room's tile path.
## The path is refreshed a few times a second so packs don't all search every frame.
func nav_dir(target: Vector2, delta: float) -> Vector2:
	var room: Room = game.room
	if room.has_los(global_position, target, radius * 0.8):
		_nav_t = 0.0
		return (target - global_position).normalized()
	_nav_t -= delta
	if _nav_t <= 0.0 or global_position.distance_to(_nav_wp) < 8.0:
		_nav_t = 0.35
		var route := room.path(global_position, target)
		_nav_wp = route[0] if not route.is_empty() else target
		# Skip ahead to the furthest waypoint we can already see.
		for wp in route:
			if room.has_los(global_position, wp, radius * 0.8):
				_nav_wp = wp
			else:
				break
	return (_nav_wp - global_position).normalized()


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


## Rainside: the enemy as a standing sprite with its hit flash and Ignite glow at its feet.
## Returns false in flat rooms, where the caller draws its own art.
func draw_figure(fig: String, face: Vector2, pose := 0, lift := 0.0) -> bool:
	if not Upright.on:
		return false
	Upright.figure(self, fig, radius, face, velocity.length() > 20.0, pose, Upright.flash(flash_frames, flash_crit), lift)
	if ignite_stacks > 0:
		var k := clampf(ignite_stacks / 10.0, 0.2, 1.0)
		draw_set_transform(Upright.feet(radius), 0.0, Vector2(1.0, 0.45))
		draw_arc(Vector2.ZERO, radius + 3.0, 0, TAU, 20, Color(1, 0.5, 0.12, 0.5 + 0.4 * k), 2.0 + 2.0 * k)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


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
