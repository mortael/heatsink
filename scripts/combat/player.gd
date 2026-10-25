class_name Player
extends CharacterBody2D
signal damaged(source: String, band_name: String)
signal died
signal vented(amount: float)
signal gauge_pulsed

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
const VENT_READY_FLASH := 0.4
const VENT_RING := RADIUS + 5.0 # cooldown / ready ring around the Sink
const RIVET_BURST_DAMAGE := 10.0
const TENSION_PER_RIVET := 0.05

const MAX_PIPS := 6
const HIT_INVULN := 1.0

var game: RunGame
var inventory: Inventory
var effects: CombatEffects
var heat := Heat.new()
var max_pips := MAX_PIPS # Altars and Wager stakes spend these
var pips := MAX_PIPS
var aim_dir := Vector2.RIGHT
var fire_cd := 0.0
var dash_charges := DASH_MAX
var dash_recharge := 0.0
var dash_time := 0.0
var dash_dir := Vector2.RIGHT
var vent_cd := 0.0
var vent_cd_total := VENT_COOLDOWN # the cooldown the last Vent started with, for the progress rings
var invuln := 0.0
var muzzle := 0.0
var shots_fired := 0
var vents := 0
var vent_ready_flash := 0.0 # 1 -> 0 over VENT_READY_FLASH s once the Vent comes off cooldown
var _vent_was_ready := true
var lamp: PointLight2D # the Sink's own light: walls cast moving shadows around you

# Bot hooks used by the automated playtest.
var bot := false
var bot_move := Vector2.ZERO
var bot_aim := Vector2.RIGHT
var _input_aim := Vector2.ZERO
var _input_aim_active := false
var bot_fire := false
var bot_dash := false
var bot_vent := false
var bot_interact := false


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
	lamp = PointLight2D.new()
	lamp.texture = Glow.light()
	lamp.texture_scale = 5.0 * C.TILE * 2.0 / Glow.TEX_SIZE
	lamp.shadow_enabled = true
	lamp.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	lamp.shadow_filter_smooth = 3.0
	lamp.shadow_color = Color(0, 0, 0, 0.75)
	add_child(lamp)
	# The Sink always reads at full brightness: it carries the lamp, so it shouldn't be lit by it.
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	add_to_group("dynamic_lights")
	apply_lights()


## Called when the Lights & shadows setting changes.
func apply_lights() -> void:
	lamp.enabled = Settings.lights


func is_invulnerable() -> bool:
	return invuln > 0.0 or dash_time > DASH_TIME - DASH_IFRAMES


func _physics_process(delta: float) -> void:
	if game.dead:
		velocity = Vector2.ZERO
		return
	var inv: Inventory = inventory
	heat.decay_rate = 12.0 * inv.heat_decay_mult()
	heat.hot_at = inv.hot_at()
	heat.overheat_time = inv.overheat_time()
	heat.tick(delta)
	fire_cd -= delta
	vent_cd = maxf(0.0, vent_cd - delta)
	# Checked by state, not by the timer's last step: a Heat Engine refund can also finish the cooldown.
	if vent_cd <= 0.0 and not _vent_was_ready:
		_on_vent_ready()
	_vent_was_ready = vent_cd <= 0.0
	vent_ready_flash = maxf(0.0, vent_ready_flash - delta / VENT_READY_FLASH)
	invuln = maxf(0.0, invuln - delta)
	muzzle = maxf(0.0, muzzle - delta)
	if dash_charges < DASH_MAX:
		dash_recharge -= delta
		if dash_recharge <= 0.0:
			dash_charges += 1
			dash_recharge = DASH_RECHARGE * inv.dash_recharge_mult() if dash_charges < DASH_MAX else 0.0

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
	_update_lamp()
	queue_redraw()


## The lamp warms with Heat, brightens in Overdrive and flickers red while overheated.
func _update_lamp() -> void:
	if not lamp.enabled:
		return
	var k := clampf(heat.value / maxf(heat.hot_at, 1.0), 0.0, 1.0)
	var col := Color(0.75, 0.82, 0.95).lerp(Color(1.0, 0.72, 0.4), k)
	var energy := 1.3 + 0.5 * k
	if heat.is_overheated():
		col = C.HEAT_OVER
		energy = 0.9 + 0.8 * randf()
	elif heat.band == Heat.Band.HOT:
		energy = 2.0
	lamp.color = col
	lamp.energy = energy + (0.5 if muzzle > 0.0 else 0.0)


func _move_input() -> Vector2:
	if bot:
		return bot_move.limit_length(1.0)
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func set_aim_input(direction: Vector2, active: bool) -> void:
	_input_aim = direction
	_input_aim_active = active


func _update_aim() -> void:
	if bot:
		if bot_aim.length() > 0.01:
			aim_dir = bot_aim.normalized()
		return
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.35:
		aim_dir = stick.normalized()
		return
	if _input_aim_active:
		if _input_aim != Vector2.ZERO:
			aim_dir = _input_aim
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


func interact_pressed() -> bool:
	if bot:
		var i := bot_interact
		bot_interact = false
		return i
	return Input.is_action_just_pressed("interact")


func _fire() -> void:
	var inv: Inventory = inventory
	fire_cd = FIRE_INTERVAL * inv.fire_interval_mult()
	var hot := heat.band == Heat.Band.HOT
	var primary_dir := aim_dir.rotated(randf_range(-0.025, 0.025))
	var shot_count := 1 + inv.extra_projectiles()
	for i in shot_count:
		var direction := primary_dir
		if i > 0:
			var side_index := i - 1
			var side := (side_index / 2 + 1) * (1 if side_index % 2 == 0 else -1)
			direction = primary_dir.rotated(0.12 * side)
		var rivet := Rivet.new()
		rivet.inventory = inventory
		rivet.effects = effects
		rivet.fx = game.fx
		rivet.position = global_position + aim_dir * (RADIUS + 6.0)
		rivet.dir = direction
		rivet.overdrive = hot
		rivet.pierce = 1 if hot else 0
		rivet.ricochet = inv.ricochets(hot)
		rivet.speed_mult = inv.projectile_speed_mult()
		game.world.add_child(rivet)
	heat.add(HEAT_PER_SHOT)
	game.fx.muzzle(global_position + aim_dir * (RADIUS + 6.0), Rivet.color_for(hot))
	muzzle = 0.05
	shots_fired += 1
	Sfx.play("shot", 3.0 if hot else 0.0, -6.0)
	Juice.add_trauma(0.015)


func _dash(move: Vector2) -> void:
	dash_dir = move.normalized() if move != Vector2.ZERO else aim_dir
	dash_time = DASH_TIME
	dash_charges -= 1
	if dash_recharge <= 0.0:
		dash_recharge = DASH_RECHARGE * inventory.dash_recharge_mult()
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
	vent_cd = inventory.vent_cooldown()
	vent_cd_total = vent_cd
	vents += 1
	var radius := (2.5 + amount / 25.0) * C.TILE
	var dmg: float = amount * 0.6 * mult * inventory.vent_damage_mult()

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
			e.take_damage(dmg * tension, false, push, Enemy.DamageKind.VENT)

	for b in bursts:
		var pos: Vector2 = b[0]
		var n: int = b[1]
		game.fx.rivet_burst(pos, n)
		Sfx.play_ramp("burst", -3.0)
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.dead:
				continue
			if e.global_position.distance_to(pos) <= C.TILE + e.radius:
				e.take_damage(RIVET_BURST_DAMAGE * n, false, Vector2.ZERO, Enemy.DamageKind.RIVET)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.clear_rivets()

	var col := C.HEAT_COLD.lerp(C.HEAT_WARM, clampf(amount / 80.0, 0.0, 1.0))
	if amount >= 80.0:
		col = C.HEAT_HOT
	game.fx.ring(global_position, radius, col, 0.32)
	# The blast burns orange even when the ring reads cold; a hot Vent burns yellow-white.
	game.fx.explosion(global_position, radius, Color(1, 0.5, 0.18).lerp(Color(1, 0.8, 0.5), clampf((amount - 40.0) / 60.0, 0.0, 1.0)), amount / 100.0)
	game.fx.vent_embers(global_position, radius, amount)
	Juice.hitstop(6 if amount >= 80.0 else 3)
	Juice.add_trauma(0.2 + 0.25 * amount / 100.0)
	Sfx.play("vent", -6.0 + amount / 20.0)
	vented.emit(amount)
	effects.on_vent(amount)


func take_hit(amount: int, source: String) -> void:
	if game.dead or is_invulnerable():
		return
	if heat.is_overheated():
		amount += 1
	amount = inventory.hit_cost(amount, heat.band == Heat.Band.HOT)
	pips -= amount
	invuln = HIT_INVULN
	damaged.emit(source, heat.band_name())
	Juice.hitstop(8)
	Juice.add_trauma(0.35)
	Sfx.play("player_hit")
	game.fx.sparks(global_position, Vector2.UP, 10, Color(1, 0.35, 0.3))
	if pips <= 0:
		pips = 0
		died.emit()


## The Vent is back: a bright ring snaps out from the Sink with a soft chime.
func _on_vent_ready() -> void:
	vent_ready_flash = 1.0
	if not bot:
		Sfx.play("band", 12.0, -16.0)


func _on_band_changed(new_band: Heat.Band, old_band: Heat.Band) -> void:
	if new_band == Heat.Band.OVERHEAT:
		return
	gauge_pulsed.emit()
	if new_band > old_band:
		var semitones := 0.0
		match new_band:
			Heat.Band.HOT:
				semitones = 4.0
			Heat.Band.OVERHEAT:
				semitones = 7.0
		Sfx.play("band", semitones, -4.0)


func _on_overheated() -> void:
	Sfx.play("overheat")
	effects.on_overheat()
	Juice.add_trauma(0.3)
	game.fx.sparks(global_position, Vector2.UP, 16, C.HEAT_OVER)
	gauge_pulsed.emit()


func repair(amount: int) -> void:
	pips = mini(pips + amount, max_pips)


func spend_max_plating(amount: int) -> bool:
	if amount <= 0 or max_pips - amount < 1:
		return false
	max_pips -= amount
	pips = mini(pips, max_pips)
	return true


func stoke() -> bool:
	if inventory.stoked or not spend_max_plating(1):
		return false
	heat.cap = 120.0
	inventory.stoked = true
	return true


func refund_vent_cooldown(seconds: float) -> void:
	vent_cd = maxf(0.0, vent_cd - seconds)


func _draw() -> void:
	var flicker := invuln > 0.0 and int(invuln * 20.0) % 2 == 0
	var a := 0.35 if flicker else 1.0
	var core := C.HEAT_COLD
	if heat.is_overheated():
		core = C.HEAT_OVER if int(Time.get_ticks_msec() / 80) % 2 == 0 else Color(0.3, 0.05, 0.05)
	elif heat.value < heat.hot_at:
		core = C.HEAT_COLD.lerp(C.HEAT_WARM, heat.value / heat.hot_at)
	else:
		core = C.HEAT_WARM.lerp(C.HEAT_HOT, clampf((heat.value - heat.hot_at) / 20.0, 0.0, 1.0))
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
	_draw_vent_ring(a)


## Vent readiness on the Sink itself, so you never have to look at the HUD:
## cooling down, a dim ring fills clockwise from the top; ready, a full orange ring breathes slowly.
func _draw_vent_ring(a: float) -> void:
	if game.dead:
		return
	if vent_cd > 0.0:
		var k := clampf(1.0 - vent_cd / vent_cd_total, 0.0, 1.0)
		draw_arc(Vector2.ZERO, VENT_RING, 0, TAU, 32, Color(0, 0, 0, 0.35 * a), 3.0)
		if k > 0.0:
			draw_arc(Vector2.ZERO, VENT_RING, -PI / 2, -PI / 2 + TAU * k, 32, Color(0.8, 0.52, 0.3, 0.85 * a), 2.5)
		return
	var breathe := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
	draw_arc(Vector2.ZERO, VENT_RING, 0, TAU, 32, Color(1, 0.6, 0.2, (0.18 + 0.12 * breathe) * a), 6.0)
	draw_arc(Vector2.ZERO, VENT_RING, 0, TAU, 32, Color(1, 0.75, 0.35, (0.75 + 0.25 * breathe) * a), 2.5)
	if vent_ready_flash > 0.0:
		var f := vent_ready_flash
		draw_arc(Vector2.ZERO, VENT_RING + 22.0 * (1.0 - f), 0, TAU, 32, Color(1, 0.85, 0.55, f * a), 2.0 + 3.0 * f)
