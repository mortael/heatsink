class_name CombatEffects
extends Node
## Live item triggers and projectile spawning: reads Inventory for ownership and stat queries,
## and acts on the player, fx and projectile parent it's given. Inventory keeps ownership,
## offers, tempering and fusion rules; this is where owning an item does something mid-fight.

signal flares_detonated

const SHARD_DEPTH_CAP := 2 # shards spawned by shard kills stop cascading after this

var inventory: Inventory
var player: Player
var fx: Fx
var projectile_parent: Node2D
var _static_hits := 0


func _process(delta: float) -> void:
	if inventory.cursed("feral_valve") and player.heat.band == Heat.Band.HOT and inventory.run_active:
		inventory.progress_absolution("feral_valve", delta)


func on_rivet_hit(e: Enemy, overdrive: bool, crit: bool) -> void:
	on_weapon_hit(e, overdrive, crit)


## Every Frame's weapon calls this once per hit: a rivet, a maul swing or shockwave, or a beam pulse.
func on_weapon_hit(e: Enemy, hot: bool, crit: bool) -> void:
	var inv := inventory
	if inv.has("bellows_valve") and player.heat.band >= Heat.Band.WARM:
		inv.proc_bonus = minf(0.2, inv.proc_bonus + 0.02)
	var times := 2 if crit and inv.has("cinder_lens") else 1
	for i in times:
		_apply_on_hit(e, hot)
	if inv.has("static_rivets"):
		_static_hits += 1
		if _static_hits % (3 if inv.is_tempered("static_rivets") else 5) == 0:
			radial_arcs(e.global_position, inv.arc_targets(2), 3.0 * C.TILE, 8.0, e)


func on_shard_hit(e: Enemy) -> void:
	if inventory.has("cluster_embers"):
		e.add_ignite(1, inventory.ignite_cap())
	if randf() < inventory.proc_chance():
		_apply_on_hit(e, false)


func _apply_on_hit(e: Enemy, hot: bool) -> void:
	var inv := inventory
	if inv.has("tinder_rounds"):
		e.add_ignite(1, inv.ignite_cap())
	if inv.has("pyre_coating") and hot:
		e.add_ignite(3 if inv.is_tempered("pyre_coating") else 2, inv.ignite_cap())


## A Molten pool the player made burns an enemy. Cinder Spill pools also set it on fire.
func on_molten_tick(e: Enemy) -> void:
	if inventory.has("cinder_spill"):
		e.add_ignite(1, inventory.ignite_cap())


## Slag Trail: a Molten pool where a dash starts and where it ends.
func on_dash(from: Vector2) -> void:
	if inventory.has("slag_trail"):
		spawn_pool(from, 0.7)


func on_dash_end(at: Vector2) -> void:
	if inventory.has("slag_trail"):
		spawn_pool(at, 0.7)


func spawn_pool(pos: Vector2, scale := 1.0) -> void:
	var pool := SlagPool.new()
	pool.game = player.game
	pool.position = pos
	pool.radius = SlagPool.RADIUS * scale
	pool.dps = inventory.molten_dps()
	projectile_parent.add_child.call_deferred(pool)


func on_kill(e: Enemy) -> void:
	var inv := inventory
	var pos := e.global_position
	if inv.has("cinder_spill"):
		var at := Heat.Band.WARM if inv.is_tempered("cinder_spill") else Heat.Band.HOT
		if player.heat.band >= at and player.heat.band != Heat.Band.OVERHEAT:
			spawn_pool(pos, 0.6)
	if e.last_kind == Enemy.DamageKind.ARC and inv.has("heat_engine"):
		player.refund_vent_cooldown(0.5)
	if e.last_kind == Enemy.DamageKind.VENT and inv.cursed("hungry_coal"):
		inv.progress_absolution("hungry_coal", 1.0)
	if inv.has("tinder_rounds") and e.ignite_stacks > 1:
		var share := e.ignite_stacks / 2
		var reach := (2.5 if inv.is_tempered("tinder_rounds") else 1.5) * C.TILE
		fx.ring(pos, reach, Color(1, 0.5, 0.15, 0.8), 0.2)
		for o in _enemies_near(pos, reach):
			o.add_ignite(share, inv.ignite_cap())
	if inv.has("frag_lattice") and e.last_depth < SHARD_DEPTH_CAP:
		var n := inv.shard_count(6 if inv.is_tempered("frag_lattice") else 4)
		for i in n:
			var ang := PI / 4.0 + i * PI / 2.0 if i < 4 else randf() * TAU
			spawn_shard(pos, Vector2.from_angle(ang), e.last_depth + 1)
		Sfx.play_ramp("burst", -8.0)


func on_wall_stop(pos: Vector2, normal: Vector2) -> void:
	if not inventory.has("splinter_heads"):
		return
	var spread: Array = [-0.6, -0.3, 0.0, 0.3, 0.6] if inventory.is_tempered("splinter_heads") else [-0.5, 0.0, 0.5]
	for a: float in spread:
		spawn_shard(pos + normal * 4.0, normal.rotated(a), 1)


func on_overheat() -> void:
	if not inventory.has("pyre_coating"):
		return
	var big := inventory.is_tempered("pyre_coating")
	var reach := (5.0 if big else 4.0) * C.TILE
	for o in _enemies_near(player.global_position, reach):
		o.add_ignite(5 if big else 3, inventory.ignite_cap())
	fx.ring(player.global_position, reach, Color(1, 0.45, 0.1), 0.3)


## Called after the nova and rivet bursts have resolved.
func on_vent(_amount: float) -> void:
	var inv := inventory
	inv.proc_bonus = 0.0
	if inv.has("firestorm_lattice"):
		_detonate_flares()
	if inv.has("feedback_coil"):
		var cands: Array = _enemies_near(player.global_position, 8.0 * C.TILE)
		cands.sort_custom(func(a: Enemy, b: Enemy) -> bool:
			if a.ignite_stacks != b.ignite_stacks:
				return a.ignite_stacks > b.ignite_stacks
			return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
		var big := inv.is_tempered("feedback_coil")
		var n := mini(inv.arc_targets(5 if big else 3), cands.size())
		for i in n:
			var e: Enemy = cands[i]
			if e.dead:
				continue
			var dmg := (14.0 if big else 10.0) + 5.0 * e.ignite_stacks
			e.clear_ignite()
			fx.arc(player.global_position, e.global_position)
			e.take_damage(dmg, false, Vector2.ZERO, Enemy.DamageKind.ARC)
		if n > 0:
			Sfx.play("zap", 0.0, -4.0)
	if inv.has("heat_engine"):
		player.heat.set_value(40.0)


func radial_arcs(from: Vector2, count: int, reach: float, dmg: float, skip: Enemy) -> void:
	var cands: Array = _enemies_near(from, reach)
	cands.erase(skip)
	cands.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	for i in mini(count, cands.size()):
		var e: Enemy = cands[i]
		fx.arc(from, e.global_position)
		e.take_damage(dmg, false, Vector2.ZERO, Enemy.DamageKind.ARC)
	if not cands.is_empty():
		Sfx.play("zap", 3.0, -8.0)


func spawn_shard(pos: Vector2, dir: Vector2, depth: int) -> void:
	if dir.is_zero_approx() or not dir.is_finite():
		return
	var s := Shard.new()
	s.effects = self
	s.inventory = inventory
	s.position = pos
	s.dir = dir.normalized()
	s.depth = depth
	s.homing = inventory.has("cluster_embers")
	s.flare = inventory.has("firestorm_lattice")
	s.speed_mult = inventory.projectile_mult()
	projectile_parent.add_child(s)


func _detonate_flares() -> void:
	var flares := get_tree().get_nodes_in_group("flares")
	if flares.is_empty():
		return
	var pts: Array[Vector2] = []
	for f in flares:
		pts.append(f.global_position)
		f.remove_from_group("flares")
		f.queue_free()
	var hit := {}
	# Each flare bursts.
	for pt in pts:
		fx.rivet_burst(pt, 1)
		for o in _enemies_near(pt, C.TILE):
			o.take_damage(12.0, false, Vector2.ZERO, Enemy.DamageKind.FLARE)
	# Lightning web between flares within 4 tiles: damages everything it crosses.
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var a := pts[i]
			var b := pts[j]
			if a.distance_to(b) > 4.0 * C.TILE:
				continue
			fx.arc(a, b, 0.35)
			for o in get_tree().get_nodes_in_group("enemies"):
				var en: Enemy = o
				if en.dead or hit.has(en):
					continue
				var closest := Geometry2D.get_closest_point_to_segment(en.global_position, a, b)
				if closest.distance_to(en.global_position) <= en.radius + 10.0:
					hit[en] = true
					en.take_damage(12.0, false, Vector2.ZERO, Enemy.DamageKind.ARC)
	flares_detonated.emit()
	Juice.hitstop(8)
	Juice.add_trauma(0.4)
	Sfx.play("zap", -5.0, 0.0)
	Sfx.play("fusion", 5.0, -6.0)


func _enemies_near(pos: Vector2, reach: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for o in get_tree().get_nodes_in_group("enemies"):
		var e: Enemy = o
		if not e.dead and e.global_position.distance_to(pos) <= reach + e.radius:
			out.append(e)
	return out
