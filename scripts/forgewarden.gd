class_name Forgewarden
extends Enemy
## High-threat Elite (GDD section 7, profile 3). 600 HP, 12 TP.
## Armour: 3 front plates block 75% of damage from the front 120 degrees; each breaks after 80 damage.
## The back takes +50%. It turns slowly, so flanking is the answer.
## Hammerfall: 0.9 s raise while a red 2.5-tile circle grows at the player, then a leap and a slam that
## sends a ground ring out to 5 tiles over 0.5 s (2 pips; the ring can be dashed through).
## Bellows Breath: 1.0 s glow and rising hiss, then a 60 degree, 5-tile flame cone for 1.2 s (2 pips)
## that leaves Molten floor for 3 s. Attacks alternate, with a 2.0 s recovery after each.

enum S { STALK, RAISE, LEAP, SHOCK, INHALE, BREATH, RECOVER }

const SPEED := 1.6 * C.TILE
const TURN_RATE := 1.4 # rad/s outside attacks
const PLATES := 3
const PLATE_HP := 80.0
const FRONT_COS := 0.5 # cos 60: front arc is 120 degrees wide
const BACK_COS := -0.5

const RAISE := 0.9
const AIM_LOCK := 0.6 # both attacks stop tracking the player this long before they land, so walking out works
const SLAM_RADIUS := 2.5 * C.TILE
const LEAP_TIME := 0.3
const RING_REACH := 5.0 * C.TILE
const RING_TIME := 0.5
const RING_WIDTH := 16.0

const INHALE := 1.0
const BREATH := 1.2
const CONE_HALF := deg_to_rad(30.0)
const CONE_REACH := 5.0 * C.TILE

const RECOVER := 2.0
const STALK_TIME := 1.1
const ATTACK_RANGE := 7.0 * C.TILE

var state: int = S.STALK
var t := STALK_TIME
var facing := Vector2.DOWN
var plates := PLATES
var plate_hp := PLATE_HP
var next_attack := "hammer"
var target := Vector2.ZERO
var leap_from := Vector2.ZERO
var ring_hit := false
var breath_hit := false
var _molten_t := 0.0


func _init() -> void:
	max_hp = 600.0
	radius = 26.0
	tp = 12
	elite = true
	source_name = "Forgewarden"


func _ready() -> void:
	super._ready()
	facing = (game.player.global_position - global_position).normalized()


func _ai(delta: float) -> void:
	var p: Player = game.player
	var to_p := p.global_position - global_position
	t -= delta
	match state:
		S.STALK:
			_turn_toward(to_p, TURN_RATE * delta)
			var want := Vector2.ZERO
			if to_p.length() > 3.0 * C.TILE:
				want = nav_dir(p.global_position, delta) * SPEED
			velocity = velocity.lerp(want, 0.1)
			if t <= 0.0 and to_p.length() < ATTACK_RANGE and not game.dead:
				_start_attack()
		S.RAISE:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			_turn_toward(to_p, TURN_RATE * 2.0 * delta)
			if t > AIM_LOCK:
				target = _landing(p.global_position) # the circle always shows where it will really land
			if t <= 0.0:
				leap_from = global_position
				state = S.LEAP
				t = LEAP_TIME
				collision_mask = 0 # _landing already checked the flight path is clear of walls
		S.LEAP:
			var k := 1.0 - maxf(t, 0.0) / LEAP_TIME
			var dest := leap_from.lerp(target, k)
			velocity = (dest - global_position) / maxf(delta, 0.001)
			if t <= 0.0:
				velocity = Vector2.ZERO
				collision_mask = C.LAYER_WALL
				_slam()
		S.SHOCK:
			velocity = Vector2.ZERO
			var r := RING_REACH * (1.0 - maxf(t, 0.0) / RING_TIME)
			var d := p.global_position.distance_to(global_position)
			if not ring_hit and absf(d - r) < RING_WIDTH + Player.RADIUS and not p.is_invulnerable():
				ring_hit = true
				p.take_hit(2, "Forgewarden · Hammerfall")
			if t <= 0.0:
				_recover()
		S.INHALE:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			if t > AIM_LOCK:
				_turn_toward(to_p, TURN_RATE * 1.5 * delta)
			if t <= 0.0:
				state = S.BREATH
				t = BREATH
				_molten_t = 0.0
				breath_hit = false
				Sfx.play("vent", -10.0, -2.0)
		S.BREATH:
			velocity = Vector2.ZERO
			if not breath_hit and _in_cone(p.global_position, CONE_REACH) and not game.dead and not p.is_invulnerable():
				breath_hit = true # one hit per breath
				p.take_hit(2, "Forgewarden · Bellows Breath")
			if randf() < 0.9:
				var a := randf_range(-CONE_HALF, CONE_HALF)
				var dir := facing.rotated(a)
				game.fx.flame(global_position + facing * radius, dir * randf_range(260.0, 420.0))
			_molten_t -= delta
			if _molten_t <= 0.0:
				_molten_t = 0.2
				_drop_molten()
			if t <= 0.0:
				_recover()
		S.RECOVER:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			if t <= 0.0:
				state = S.STALK
				t = STALK_TIME


func _start_attack() -> void:
	if next_attack == "hammer":
		state = S.RAISE
		t = RAISE
		target = _landing(game.player.global_position)
		next_attack = "breath"
		Sfx.play("windup", -7.0, -6.0)
	else:
		state = S.INHALE
		t = INHALE
		next_attack = "hammer"
		Sfx.play("hiss", 0.0, -6.0)


## Where the leap lands: the target, pulled back toward us until the body fits there
## and the flight path is clear of walls. A player behind cover gets a slam in front of it.
func _landing(at: Vector2) -> Vector2:
	var room: Room = game.room
	for i in 12:
		var cand := at.lerp(global_position, i / 11.0)
		if room.is_open(cand, radius + 2.0) and room.has_los(global_position, cand, radius):
			return cand
	return global_position


func _slam() -> void:
	var p: Player = game.player
	if p.global_position.distance_to(global_position) < SLAM_RADIUS + Player.RADIUS and not game.dead:
		p.take_hit(2, "Forgewarden · Hammerfall")
		ring_hit = true
	else:
		ring_hit = false
	state = S.SHOCK
	t = RING_TIME
	Juice.add_trauma(0.45)
	Sfx.play("slam", 0.0, 0.0)
	game.fx.ring(global_position, SLAM_RADIUS, C.TELE_GROUND, 0.25)
	game.fx.explosion(global_position, SLAM_RADIUS, Color(1, 0.35, 0.15), 0.5)
	game.fx.sparks(global_position, Vector2.UP, 14, Color(1, 0.5, 0.2))


func _recover() -> void:
	state = S.RECOVER
	t = RECOVER


func _turn_toward(dir: Vector2, max_step: float) -> void:
	if dir.length() < 1.0:
		return
	var want := dir.angle()
	var cur := facing.angle()
	var diff := wrapf(want - cur, -PI, PI)
	facing = Vector2.from_angle(cur + clampf(diff, -max_step, max_step))


func _in_cone(pos: Vector2, reach: float) -> bool:
	var to := pos - global_position
	if to.length() > reach + Player.RADIUS:
		return false
	if to.length() < radius + Player.RADIUS:
		return true
	return absf(facing.angle_to(to)) < CONE_HALF + 0.08 and game.room.has_los(global_position, pos)


func _drop_molten() -> void:
	var d := randf_range(1.2, 4.6) * C.TILE
	var pos := global_position + facing.rotated(randf_range(-CONE_HALF, CONE_HALF) * 0.8) * d
	if not game.room.is_open(pos, 10.0) or not game.room.has_los(global_position, pos):
		return
	var m := MoltenPatch.new()
	m.game = game
	m.position = pos
	game.world.add_child(m)


## Armour: plates soak 75% from the front; the back takes +50%. Damage over time is not armoured.
func take_damage(amount: float, crit: bool, push: Vector2, kind: String, depth := 0) -> void:
	if dead:
		return
	var from: Vector2 = -push.normalized() if push.length() > 0.01 else (game.player.global_position - global_position).normalized()
	if kind != "ignite" and from != Vector2.ZERO:
		var dot := facing.dot(from)
		if dot >= FRONT_COS and plates > 0:
			plate_hp -= amount
			amount *= 0.25
			game.fx.sparks(global_position + from * radius, from, 3, Color(0.8, 0.82, 0.86))
			if plate_hp <= 0.0:
				_break_plate(from)
		elif dot <= BACK_COS:
			amount *= 1.5
	push *= 0.15 # it barely flinches
	super.take_damage(amount, crit, push, kind, depth)


func _break_plate(from: Vector2) -> void:
	plates -= 1
	plate_hp = PLATE_HP
	Juice.hitstop(6, true)
	Juice.add_trauma(0.2)
	Sfx.play("crit", -5.0, -2.0)
	game.fx.debris(global_position + from * radius, from)
	if plates == 0:
		game.hud.banner("ARMOUR BROKEN", "The Forgewarden's front is open")


func _die() -> void:
	dead = true
	remove_from_group("enemies")
	game.fx.pop(global_position, Color(0.9, 0.45, 0.2))
	game.fx.ring(global_position, 3.0 * C.TILE, Color(1, 0.6, 0.25), 0.5)
	game.fx.explosion(global_position, 3.0 * C.TILE, Color(1, 0.6, 0.25), 0.8)
	Sfx.play("slam", -3.0, 0.0)
	Sfx.play_ramp("kill", 0.0)
	Juice.hitstop(10, true)
	Juice.slowmo(0.3, 0.25)
	Juice.punch(0.04)
	Juice.add_trauma(0.5)
	game.inventory.on_kill(self)
	game.on_enemy_killed(self)
	game.on_elite_killed(self)
	queue_free()


func _draw() -> void:
	# Telegraphs on the ground first.
	match state:
		S.RAISE, S.LEAP:
			var k := 1.0 - maxf(t, 0.0) / RAISE if state == S.RAISE else 1.0
			var c := target - global_position
			draw_circle(c, SLAM_RADIUS * (0.35 + 0.65 * k), Color(C.TELE_GROUND, 0.18 + 0.12 * k))
			draw_arc(c, SLAM_RADIUS, 0, TAU, 40, Color(C.TELE_GROUND, 0.85), 2.5)
		S.SHOCK:
			var r := RING_REACH * (1.0 - maxf(t, 0.0) / RING_TIME)
			draw_arc(Vector2.ZERO, r, 0, TAU, 56, Color(1, 0.55, 0.25, 0.9), RING_WIDTH * 0.8)
			draw_arc(Vector2.ZERO, r, 0, TAU, 56, Color(1, 0.9, 0.6, 0.9), 3.0)
		S.INHALE:
			var k := 1.0 - maxf(t, 0.0) / INHALE
			var pts := PackedVector2Array([Vector2.ZERO])
			for i in 9:
				pts.append(facing.rotated(-CONE_HALF + i * CONE_HALF / 4.0) * CONE_REACH)
			draw_colored_polygon(pts, Color(C.TELE_GROUND, 0.08 + 0.14 * k))
			draw_polyline(pts + PackedVector2Array([Vector2.ZERO]), Color(C.TELE_GROUND, 0.7), 2.0)
		S.BREATH:
			var pts := PackedVector2Array([Vector2.ZERO])
			for i in 9:
				pts.append(facing.rotated(-CONE_HALF + i * CONE_HALF / 4.0) * CONE_REACH)
			draw_colored_polygon(pts, Color(1, 0.45, 0.1, 0.22 + 0.06 * sin(Time.get_ticks_msec() / 40.0)))
	var lift := -14.0 * sin(PI * (1.0 - maxf(t, 0.0) / LEAP_TIME)) if state == S.LEAP else 0.0
	Upright.body(self, radius, radius * 0.9, Color(0.3, 0.27, 0.27))
	Upright.xf(self, Vector2(0, lift), facing.angle(), Vector2.ONE)
	var r := radius
	# Bellows on the back
	var swell := 0.0
	if state == S.INHALE:
		swell = (1.0 - t / INHALE) * 6.0
	draw_rect(Rect2(-r - 8 - swell, -12 - swell * 0.5, 14 + swell, 24 + swell), flash_color(Color(0.42, 0.3, 0.22)))
	draw_circle(Vector2.ZERO, r, flash_color(Color(0.3, 0.27, 0.27)))
	draw_arc(Vector2.ZERO, r, 0, TAU, 32, flash_color(Color(0.55, 0.5, 0.48)), 3.0)
	# Furnace mouth on the chest
	var glow := 0.4
	if state == S.INHALE:
		glow = 0.4 + 0.6 * (1.0 - t / INHALE)
	elif state == S.BREATH:
		glow = 1.0
	draw_circle(Vector2(r * 0.35, 0), 7.0, Color(1, 0.45 + 0.4 * glow, 0.15, 0.5 + 0.5 * glow))
	# Front plates: three arcs across the front 120 degrees
	for i in PLATES:
		var a0 := -PI / 3.0 + i * (2.0 * PI / 9.0)
		var col := Color(0.78, 0.8, 0.84) if i < plates else Color(0.25, 0.2, 0.2, 0.6)
		draw_arc(Vector2.ZERO, r + 4.0, a0 + 0.04, a0 + 2.0 * PI / 9.0 - 0.04, 6, flash_color(col), 6.0 if i < plates else 2.0)
	# Hammer: raised overhead during Hammerfall
	var hammer := Vector2(r * 0.2, r + 8.0)
	if state == S.RAISE:
		hammer = Vector2(-r * 0.2 - 10.0 * (1.0 - t / RAISE), r * 0.4)
	draw_line(Vector2(0, r * 0.6), hammer, Color(0.5, 0.4, 0.3), 4.0)
	draw_rect(Rect2(hammer - Vector2(9, 7), Vector2(18, 14)), flash_color(Color(0.6, 0.6, 0.65)))
	Upright.xf(self)
	draw_rivets(r)
	draw_status(r)
	# Health bar
	var w := 64.0
	draw_rect(Rect2(-w * 0.5, -r - 16, w, 5), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-w * 0.5, -r - 16, w * maxf(hp, 0.0) / max_hp, 5), Color(1, 0.35, 0.25))
