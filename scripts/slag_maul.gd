class_name SlagMaul
extends Node2D
## The Furnace Frame's weapon (GDD section 3): a 3-hit combo in a wide arc in front of the Sink.
## Hold fire to keep swinging. The third hit leaves a Molten pool; in Overdrive every swing also throws
## a shockwave along the floor. Momentum: chained hits hold the Heat up longer.
## A child of the Player, so it draws the swing around the Sink.

const TIMES := [0.35, 0.35, 0.55] # recovery after each hit of the combo
const DAMAGE := [22.0, 22.0, 40.0]
const PUSH := [150.0, 150.0, 330.0]
const REACH := 1.6 * C.TILE # from the Sink's centre to the edge of the arc
const ARC := deg_to_rad(150.0) # full width of the swing
const HEAT_PER_SWING := 12.0
const COMBO_GRACE := 0.45 # the combo resets if the next swing waits longer than this
const STEP := 0.4 * C.TILE # each swing carries the Sink forward a little
const SHOCK_DAMAGE := 15.0
const SHOCK_RANGE := 4.0 * C.TILE
const CHAIN_WINDOW := 0.6 # Momentum: a hit this soon after the last one keeps the chain going
const CHAIN_STEP := 0.3 # each chained hit delays cooling this much more
const MAX_DELAY := 2.0 # cap on the Heat decay delay
const SWING_SHOW := 0.16 # how long a swing's arc stays on screen

var player: Player
var combo := 0 # index of the next swing
var cd := 0.0
var grace := 0.0
var since_hit := 99.0
var delay_bonus := 0.0
var swings := 0
var _show := 0.0
var _show_idx := 0
var _show_dir := Vector2.RIGHT
var _show_hot := false


func _ready() -> void:
	material = Glow.additive()
	z_index = 1


## Called by the Player every physics step.
func tick(delta: float, held: bool) -> void:
	var heat := player.heat
	cd -= delta
	if cd <= 0.0:
		grace -= delta
		if grace <= 0.0:
			combo = 0
	since_hit += delta
	if since_hit > CHAIN_WINDOW:
		delay_bonus = 0.0
	heat.decay_delay = minf(Heat.DECAY_DELAY + delay_bonus, MAX_DELAY)
	_show = maxf(0.0, _show - delta)
	if held and cd <= 0.0 and not heat.is_overheated():
		_swing()
	queue_redraw()


func is_busy() -> bool:
	return cd > 0.0


func _swing() -> void:
	var game: Node = player.game
	var inv: Inventory = game.inventory
	var idx := combo
	combo = (combo + 1) % TIMES.size()
	cd = TIMES[idx] * inv.fire_interval_mult()
	grace = COMBO_GRACE
	swings += 1
	var hot := player.heat.band == Heat.Band.HOT
	var dir := player.aim_dir
	var origin := player.global_position
	player.velocity += dir * STEP / 0.08
	var reach := REACH * inv.projectile_mult()
	var hits := 0
	for o in get_tree().get_nodes_in_group("enemies"):
		var e: Enemy = o
		if e.dead:
			continue
		var to := e.global_position - origin
		var d := to.length()
		if d > reach + e.radius:
			continue
		# Anything touching the Sink is hit whatever the angle; otherwise it must be inside the arc.
		if d > Player.RADIUS + e.radius + 6.0 and absf(dir.angle_to(to)) > ARC * 0.5 + atan2(e.radius, d):
			continue
		if not game.room.has_los(origin, e.global_position):
			continue
		var crit := randf() < inv.crit_chance()
		var dmg: float = DAMAGE[idx] * (2.0 if crit else 1.0)
		inv.on_weapon_hit(e, hot, crit)
		e.take_damage(dmg, crit, to.normalized() * PUSH[idx], "maul")
		game.fx.impact(e.global_position - to.normalized() * e.radius, -to.normalized(), Color(1, 0.6, 0.25))
		hits += 1
	if hits > 0:
		delay_bonus = delay_bonus + CHAIN_STEP if since_hit <= CHAIN_WINDOW else 0.0
		since_hit = 0.0
		Juice.hitstop(4 if idx == 2 else 2)
		Juice.add_trauma(0.12 if idx == 2 else 0.05)
		Sfx.play("hit", -3.0 if idx == 2 else 0.0, -4.0)
	player.heat.add(HEAT_PER_SWING)
	if idx == 2:
		inv.spawn_pool(origin + dir * reach * 0.6)
		Sfx.play("slam", 4.0, -10.0)
	var waves := inv.extra_shockwaves()
	if hot:
		waves += 1
	for k in waves:
		var side := 0.0 if k == 0 else (0.2 * ((k + 1) / 2)) * (1.0 if k % 2 == 1 else -1.0)
		var w := Shockwave.new()
		w.game = game
		w.position = origin # rolls out from the Sink's centre, so a pillar it stands against stops it
		w.dir = dir.rotated(side)
		w.max_dist = SHOCK_RANGE * inv.projectile_mult()
		w.damage = SHOCK_DAMAGE
		w.hot = hot
		game.world.add_child(w)
	Sfx.play("dash", 5.0 + idx * 2.0, -2.0)
	_show = SWING_SHOW
	_show_idx = idx
	_show_dir = dir
	_show_hot = hot
	player.muzzle = 0.08


func _draw() -> void:
	if _show <= 0.0:
		return
	var k := _show / SWING_SHOW
	var reach: float = REACH * player.game.inventory.projectile_mult()
	var col := C.HEAT_HOT if _show_hot else Color(1.0, 0.55, 0.2)
	var a0 := _show_dir.angle() - ARC * 0.5
	# Sweep direction alternates so the combo reads as left, right, overhead.
	var from := a0 if _show_idx != 1 else a0 + ARC
	var to := a0 + ARC if _show_idx != 1 else a0
	var prog := 1.0 - k
	var steps := 14
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in steps + 1:
		var t := float(i) / steps * prog
		var ang := lerpf(from, to, t)
		pts.append(Vector2.from_angle(ang) * reach)
		cols.append(Color(col, 0.95 * k * t / maxf(prog, 0.01)))
	for i in range(steps, -1, -1):
		var t := float(i) / steps * prog
		var ang := lerpf(from, to, t)
		pts.append(Vector2.from_angle(ang) * reach * 0.55)
		cols.append(Color(col, 0.0))
	draw_polygon(pts, cols)
	var tip: Vector2 = Vector2.from_angle(lerpf(from, to, prog)) * reach
	Glow.halo(self, tip, 26.0 if _show_idx == 2 else 18.0, Color(col, 0.8 * k))
	var edge := PackedVector2Array()
	for i in steps + 1:
		edge.append(Vector2.from_angle(lerpf(from, to, float(i) / steps * prog)) * reach)
	draw_polyline(edge, Color(1, 0.95, 0.8, k), 3.0 if _show_idx == 2 else 2.0)
