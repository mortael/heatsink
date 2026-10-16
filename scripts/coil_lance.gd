class_name CoilLance
extends Node2D
## The Arclight Frame's weapon (GDD section 3): hold fire to channel a beam that burns the first enemy
## in its path and chains on to more, one extra link per Heat band above Cold. In Overdrive the beam
## forks into three. Heat climbs fast while channelling; Grounded doubles cooling once you let go.
## A child of the Player; the beam is drawn in the Player's space (the Sink never rotates).

const RANGE := 7.0 * C.TILE
const DPS := 40.0
const TICK := 0.1
const HEAT_PER_SEC := 20.0
const CHAIN_REACH := 3.0 * C.TILE
const CHAIN_DAMAGE := 0.35 # chained enemies take this share of the beam's damage
const MAX_CHAIN := 3
const FORK_SPREAD := deg_to_rad(15.0) # each side fork, so 30° across
const PROC_EVERY := 3 # on-hit item effects fire on every 3rd tick against the same enemy
const GROUNDED_AFTER := 1.0
const GROUNDED_MULT := 2.0
const HUM_EVERY := 0.42

var player: Player
var channeling := false
var idle := 99.0 # seconds since the beam was last on
var beams: Array = [] # each: [end (local), hit (bool)]
var links: Array = [] # each: [from (local), to (local)]
var ticks := 0
var _tick := 0.0
var _hum := 0.0
var _procs := {} # enemy -> ticks taken from the main beam
var _t := 0.0


func _ready() -> void:
	material = Glow.additive()
	z_index = 1


func grounded() -> bool:
	return idle >= GROUNDED_AFTER


## Called by the Player every physics step.
func tick(delta: float, held: bool) -> void:
	_t += delta
	var heat := player.heat
	channeling = held and not heat.is_overheated()
	if not channeling:
		idle += delta
		beams.clear()
		links.clear()
		_tick = 0.0
		_hum = 0.0
		queue_redraw()
		return
	idle = 0.0
	heat.add(HEAT_PER_SEC * delta)
	_hum -= delta
	if _hum <= 0.0:
		_hum = HUM_EVERY
		Sfx.play("beam", 7.0 if heat.band == Heat.Band.HOT else 4.0, -14.0)
	var targets := _trace()
	_tick -= delta / player.game.inventory.fire_interval_mult()
	while _tick <= 0.0:
		_tick += TICK
		_zap(targets)
	player.muzzle = 0.05
	queue_redraw()


## Number of beams: one, three in Overdrive, two more with Brittle Crown.
func fork_count() -> int:
	var n := 3 if player.heat.band == Heat.Band.HOT else 1
	return n + player.game.inventory.extra_forks()


## Chain links per beam: 1 more enemy, +1 per Heat band above Cold (max 3), +1 with Arc Resonance.
func chain_count() -> int:
	var band := mini(player.heat.band, Heat.Band.HOT)
	return player.game.inventory.arc_targets(mini(1 + band, MAX_CHAIN))


## Works out where every beam ends and who it chains to. Returns [enemy, push dir, main beam?] per hit.
func _trace() -> Array:
	var game: Node = player.game
	beams.clear()
	links.clear()
	var out: Array = []
	var chained: Array = []
	var origin := player.global_position
	var space := get_world_2d().direct_space_state
	var reach: float = RANGE * game.inventory.projectile_mult()
	var n := fork_count()
	for i in n:
		var side := 0.0
		if n > 1:
			side = lerpf(-FORK_SPREAD, FORK_SPREAD, float(i) / (n - 1)) if n <= 3 else lerpf(-FORK_SPREAD * 1.6, FORK_SPREAD * 1.6, float(i) / (n - 1))
		var dir := player.aim_dir.rotated(side)
		# Traced from the Sink's centre, so flush against a pillar the beam stops on it instead of starting behind it.
		var q := PhysicsRayQueryParameters2D.create(origin, origin + dir * reach, C.LAYER_WALL | C.LAYER_ENEMY)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			beams.append([dir * reach, false])
			continue
		var end: Vector2 = hit.position
		if not hit.collider is Enemy:
			beams.append([end - origin, false])
			continue
		var e: Enemy = hit.collider
		beams.append([end - origin, true])
		out.append([e, dir, true])
		var seen := {e: true}
		var from: Enemy = e
		for c in chain_count():
			var best: Enemy = null
			var bd := CHAIN_REACH
			for o in get_tree().get_nodes_in_group("enemies"):
				var en: Enemy = o
				if en.dead or seen.has(en):
					continue
				var d := en.global_position.distance_to(from.global_position)
				if d < bd + en.radius and game.room.has_los(from.global_position, en.global_position):
					bd = d
					best = en
			if best == null:
				break
			seen[best] = true
			links.append([from.global_position - origin, best.global_position - origin])
			chained.append([best, (best.global_position - from.global_position).normalized(), false])
			from = best
	return out + chained # main beams first, so an enemy both hit and chained to takes the full tick


func _zap(targets: Array) -> void:
	var inv: Inventory = player.game.inventory
	var hot := player.heat.band == Heat.Band.HOT
	ticks += 1
	var done := {} # forks that converge on one enemy burn it once per tick
	for t in targets:
		var e: Enemy = t[0]
		if not is_instance_valid(e) or e.dead or done.has(e):
			continue
		done[e] = true
		var crit := randf() < inv.crit_chance()
		if t[2]:
			var n: int = _procs.get(e, 0) + 1
			_procs[e] = n
			if n % PROC_EVERY == 0 or crit:
				inv.on_weapon_hit(e, hot, crit)
		if e.dead:
			continue
		var dir: Vector2 = t[1]
		var share := 1.0 if t[2] else CHAIN_DAMAGE
		e.take_damage(DPS * TICK * share * (2.0 if crit else 1.0), crit, dir * 6.0, "beam")
	if _procs.size() > 32:
		_procs.clear()


func _draw() -> void:
	if beams.is_empty():
		return
	var hot := player.heat.band == Heat.Band.HOT
	var col := Color(0.45, 0.95, 1.0) if not hot else Color(0.85, 1.0, 1.0)
	var flick := 0.85 + 0.15 * sin(_t * 70.0)
	var start := player.aim_dir * (Player.RADIUS + 4.0)
	Glow.halo(self, start, 22.0 * flick, Color(col, 0.8))
	for b in beams:
		var end: Vector2 = b[0]
		var from := start if end.length() > start.length() else Vector2.ZERO # a wall right at the emitter
		Glow.strip(self, from, end, 26.0 * flick, Color(col, 0.55))
		Glow.strip(self, from, end, 9.0, Color(1, 1, 1, 0.9))
		_jag(from, end, Color(col, 0.9), 2.0)
		if b[1]:
			Glow.halo(self, end, 30.0 * flick, Color(col, 0.7))
	for l in links:
		var a: Vector2 = l[0]
		var b2: Vector2 = l[1]
		Glow.strip(self, a, b2, 16.0, Color(col, 0.45))
		_jag(a, b2, Color(0.85, 0.97, 1.0, 0.95), 2.0)
		Glow.halo(self, b2, 20.0, Color(col, 0.6))


## Jagged lightning line, new jitter every frame.
func _jag(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var segs := maxi(3, int(a.distance_to(b) / 24.0))
	var normal := (b - a).normalized().orthogonal()
	var pts := PackedVector2Array([a])
	for i in range(1, segs):
		pts.append(a.lerp(b, float(i) / segs) + normal * randf_range(-6.0, 6.0))
	pts.append(b)
	draw_polyline(pts, col, width)
