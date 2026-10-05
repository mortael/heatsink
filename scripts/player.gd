class_name Player
extends CharacterBody2D
## The Sink, Riveter Frame. Verbs: move, attack, dash, vent (GDD sections 2-3).

const SPEED := 6.0 * C.TILE
const ACCEL_TIME := 0.08
const DECEL_TIME := 0.05
const RADIUS := 14.0

const FIRE_INTERVAL := 0.2 # 5 shots/s
const HEAT_PER_SHOT := 6.0
const CRIT_CHANCE := 0.1

const DASH_DIST := 4.5 * C.TILE
const DASH_TIME := 0.18
const DASH_IFRAMES := 0.12
const DASH_RECHARGE := 1.2
const DASH_MAX := 2
const DASH_QUENCH := 10.0

const VENT_COOLDOWN := 6.0
const VENT_MULT := 1.0 # Riveter
const RIVET_BURST_DAMAGE := 10.0
const TENSION_PER_RIVET := 0.05

const MAX_PIPS := 6
const HIT_INVULN := 1.0

var game: Node
var heat := Heat.new()
var pips := MAX_PIPS
var aim_dir := Vector2.RIGHT
var fire_cd := 0.0
var dash_charges := DASH_MAX
var dash_recharge := 0.0
var dash_time := 0.0
var dash_dir := Vector2.RIGHT
var vent_cd := 0.0
var invuln := 0.0
var muzzle := 0.0
var shots_fired := 0
var vents := 0

# Bot hooks used by the automated playtest.
var bot := false
var bot_move := Vector2.ZERO
var bot_aim := Vector2.RIGHT
var bot_fire := false
var bot_dash := false
var bot_vent := false


func _ready() -> void:
	collision_layer = C.LAYER_PLAYER
	collision_mask = C.LAYER_WALL
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = RADIUS
	cs.shape = sh
	add_child(cs)
	add_child(heat)
	heat.band_changed.connect(_on_band_changed)
	heat.overheated.connect(_on_overheated)
	z_index = 3


func is_invulnerable() -> bool:
	return invuln > 0.0 or dash_time > DASH_TIME - DASH_IFRAMES


func _physics_process(delta: float) -> void:
	if game.dead:
		velocity = Vector2.ZERO
		return
	heat.tick(delta)
	fire_cd -= delta
	vent_cd = maxf(0.0, vent_cd - delta)
	invuln = maxf(0.0, invuln - delta)
	muzzle = maxf(0.0, muzzle - delta)
	if dash_charges < DASH_MAX:
		dash_recharge -= delta
		if dash_recharge <= 0.0:
			dash_charges += 1
			dash_recharge = DASH_RECHARGE if dash_charges < DASH_MAX else 0.0

	var move := _move_input()
	_update_aim()

	if dash_time > 0.0:
		dash_time -= delta
		velocity = dash_dir * (DASH_DIST / DASH_TIME)
		game.fx.trail(global_position, C.HEAT_COLD.lerp(C.HEAT_WARM, heat.value / 100.0))
	else:
		var speed := SPEED * (0.8 if heat.is_overheated() else 1.0)
		var rate := SPEED / (ACCEL_TIME if move != Vector2.ZERO else DECEL_TIME)
		velocity = velocity.move_toward(move * speed, rate * delta)
		if _dash_pressed() and dash_charges > 0:
			_dash(move)
	move_and_slide()

	if _fire_held() and fire_cd <= 0.0 and not heat.is_overheated():
		_fire()
	if _vent_pressed() and vent_cd <= 0.0:
		_vent()
	queue_redraw()


func _move_input() -> Vector2:
	if bot:
		return bot_move.limit_length(1.0)
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _update_aim() -> void:
	if bot:
		if bot_aim.length() > 0.01:
			aim_dir = bot_aim.normalized()
		return
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.35:
		aim_dir = stick.normalized()
		return
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 4.0:
		aim_dir = to_mouse.normalized()


func _fire_held() -> bool:
	return bot_fire if bot else Input.is_action_pressed("fire")


func _dash_pressed() -> bool:
	if bot:
		var d := bot_dash
		bot_dash = false
		return d
	return Input.is_action_just_pressed("dash")


func _vent_pressed() -> bool:
	if bot:
		var v := bot_vent
		bot_vent = false
		return v
	return Input.is_action_just_pressed("vent")


func _fire() -> void:
	fire_cd = FIRE_INTERVAL
	var hot := heat.band == Heat.Band.HOT
	var r := Rivet.new()
	r.game = game
	r.position = global_position + aim_dir * (RADIUS + 6.0)
	r.dir = aim_dir.rotated(randf_range(-0.025, 0.025))
	r.overdrive = hot
	r.pierce = 1 if hot else 0
	r.ricochet = 1 if hot else 0
	game.world.add_child(r)
	heat.add(HEAT_PER_SHOT)
	muzzle = 0.05
	shots_fired += 1
	Sfx.play("shot", 3.0 if hot else 0.0, -6.0)
	Juice.add_trauma(0.015)


func _dash(move: Vector2) -> void:
	dash_dir = move.normalized() if move != Vector2.ZERO else aim_dir
	dash_time = DASH_TIME
	dash_charges -= 1
	if dash_recharge <= 0.0:
		dash_recharge = DASH_RECHARGE
	heat.quench(DASH_QUENCH)
	Sfx.play("dash")


func _vent() -> void:
	var amount := heat.value
	var mult := VENT_MULT
	if heat.is_overheated():
		amount = 100.0
		mult *= 0.5 # venting during lockout is allowed at half damage
	else:
		heat.vent()
	vent_cd = VENT_COOLDOWN
	vents += 1
	var radius := (2.5 + amount / 25.0) * C.TILE
	var dmg := amount * 0.6 * mult

	var enemies := get_tree().get_nodes_in_group("enemies")
	# Snapshot rivet bursts before anything dies.
	var bursts: Array = []
	for e in enemies:
		var n: int = e.rivet_count()
		if n > 0:
			bursts.append([e.global_position, n])

	for e in enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var d := global_position.distance_to(e.global_position)
		if d <= radius + e.radius and dmg > 0.5:
			var tension: float = 1.0 + TENSION_PER_RIVET * e.rivet_count()
			var push: Vector2 = (e.global_position - global_position).normalized() * 320.0
			e.take_damage(dmg * tension, false, push, "vent")

	var step := 0
	for b in bursts:
		var pos: Vector2 = b[0]
		var n: int = b[1]
		game.fx.rivet_burst(pos, n)
		Sfx.play_ramp("burst", -3.0)
		step += 1
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.dead:
				continue
			if e.global_position.distance_to(pos) <= C.TILE + e.radius:
				e.take_damage(RIVET_BURST_DAMAGE * n, false, Vector2.ZERO, "rivet")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.clear_rivets()

	var col := C.HEAT_COLD.lerp(C.HEAT_WARM, clampf(amount / 80.0, 0.0, 1.0))
	if amount >= 80.0:
		col = C.HEAT_HOT
	game.fx.ring(global_position, radius, col, 0.32)
	game.fx.vent_embers(global_position, radius, amount)
	Juice.hitstop(6 if amount >= 80.0 else 3)
	Juice.add_trauma(0.2 + 0.25 * amount / 100.0)
	Sfx.play("vent", -6.0 + amount / 20.0)
	game.hud.chromatic(amount)


func take_hit(amount: int, source: String) -> void:
	if game.dead or is_invulnerable():
		return
	if heat.is_overheated():
		amount += 1
	pips -= amount
	invuln = HIT_INVULN
	game.last_hit_source = source
	game.last_hit_band = heat.band_name()
	Juice.hitstop(8)
	Juice.add_trauma(0.35)
	Sfx.play("player_hit")
	game.hud.damage_flash()
	game.fx.sparks(global_position, Vector2.UP, 10, Color(1, 0.35, 0.3))
	if pips <= 0:
		pips = 0
		game.on_player_died()


func _on_band_changed(new_band: int, old_band: int) -> void:
	if new_band == Heat.Band.OVERHEAT:
		return
	game.hud.pulse_gauge()
	if new_band > old_band:
		Sfx.play("band", [0.0, 0.0, 4.0, 7.0][new_band], -4.0)


func _on_overheated() -> void:
	Sfx.play("overheat")
	Juice.add_trauma(0.3)
	game.fx.sparks(global_position, Vector2.UP, 16, C.HEAT_OVER)
	game.hud.pulse_gauge()


func _draw() -> void:
	var flicker := invuln > 0.0 and int(invuln * 20.0) % 2 == 0
	var a := 0.35 if flicker else 1.0
	var core := C.HEAT_COLD
	if heat.is_overheated():
		core = C.HEAT_OVER if int(Time.get_ticks_msec() / 80) % 2 == 0 else Color(0.3, 0.05, 0.05)
	elif heat.value < Heat.HOT_AT:
		core = C.HEAT_COLD.lerp(C.HEAT_WARM, heat.value / Heat.HOT_AT)
	else:
		core = C.HEAT_WARM.lerp(C.HEAT_HOT, (heat.value - Heat.HOT_AT) / 20.0)
	# Hot glow
	if heat.band == Heat.Band.HOT:
		draw_circle(Vector2.ZERO, RADIUS + 9.0, Color(1, 0.6, 0.2, 0.18 * a))
	# Barrel
	var tip := aim_dir * (RADIUS + 10.0)
	draw_line(aim_dir * 6.0, tip, Color(0.3, 0.32, 0.35, a), 7.0)
	draw_line(aim_dir * 6.0, tip, Color(0.75, 0.78, 0.8, a), 3.0)
	if muzzle > 0.0:
		draw_circle(tip + aim_dir * 3.0, 7.0, Color(1, 0.9, 0.6, a))
	# Body + core
	draw_circle(Vector2.ZERO, RADIUS, Color(0.2, 0.21, 0.23, a))
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 24, Color(C.STEEL, a), 2.0)
	draw_circle(Vector2.ZERO, 7.0, Color(core, a))
