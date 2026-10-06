class_name Inventory
extends Node
## Owned items, Resonance and Fusions, plus the trigger hooks that give items their behaviour.
## Player, Rivet, Shard and Enemy call the on_* hooks; stat getters feed back into their numbers.

signal changed
signal fusion_unlocked(id: String)
signal absolved(id: String)

const SHARD_DEPTH_CAP := 2 # shards spawned by shard kills stop cascading after this

var game: Node
var owned: Array[String] = []
var fusions: Array[String] = []
var proc_bonus := 0.0
var stoked := false # Stoke Altar: Heat cap 120, Overheat +1 s
var absolution := {} # slagged id -> progress toward its Absolution goal
var absolved_ids: Array[String] = []
var _static_hits := 0


func has(id: String) -> bool:
	return owned.has(id) or fusions.has(id)


func count_keyword(kw: String) -> int:
	var n := 0
	for id in owned:
		if ItemDB.ITEMS[id].keyword == kw and kw != "slagged":
			n += 1
	return n


func resonance(kw: String) -> bool:
	return count_keyword(kw) >= 2


func add(id: String) -> void:
	if id == "patch_kit":
		game.player.pips = mini(game.player.pips + 1, game.player.max_pips)
		changed.emit()
		return
	if owned.has(id):
		return
	owned.append(id)
	if ItemDB.is_slagged(id):
		absolution[id] = 0.0
	for f: String in ItemDB.FUSIONS:
		if fusions.has(f):
			continue
		var ok := true
		for part: String in ItemDB.FUSIONS[f].recipe:
			if not owned.has(part):
				ok = false
		if ok:
			fusions.append(f)
			fusion_unlocked.emit(f)
	changed.emit()


## Drops an item (fed to the Crucible). Fusions that lose an ingredient go with it.
func remove(id: String) -> void:
	owned.erase(id)
	absolution.erase(id)
	absolved_ids.erase(id)
	for f in fusions.duplicate():
		if ItemDB.FUSIONS[f].recipe.has(id):
			fusions.erase(f)
	changed.emit()


## Pick n distinct offers. Each slot rolls 40% from keywords you already own, 60% from the open pool.
## Slagged items never appear here; filter narrows the pool and exclude skips ids already on show.
## An unfiltered offer pads empty slots with Patch Kits; a filtered one returns only matching items,
## so it can come back short or empty.
func offer(n := 3, filter := Callable(), exclude: Array[String] = []) -> Array[String]:
	var pool: Array[String] = []
	for id: String in ItemDB.ITEMS:
		if owned.has(id) or exclude.has(id) or ItemDB.is_slagged(id):
			continue
		if filter.is_valid() and not filter.call(id):
			continue
		pool.append(id)
	var result: Array[String] = []
	for i in n:
		if pool.is_empty():
			break
		var themed: Array[String] = []
		for id in pool:
			var kw: String = ItemDB.ITEMS[id].keyword
			if kw != "conductor" and count_keyword(kw) > 0:
				themed.append(id)
		var pick: String = themed.pick_random() if not themed.is_empty() and randf() < 0.4 else pool.pick_random()
		pool.erase(pick)
		result.append(pick)
	while result.size() < n and not filter.is_valid():
		result.append("patch_kit")
	return result


## Fusion this item would complete if picked now ("" if none).
func completes_fusion(id: String) -> String:
	for f: String in ItemDB.FUSIONS:
		if fusions.has(f):
			continue
		var recipe: Array = ItemDB.FUSIONS[f].recipe
		if not recipe.has(id):
			continue
		var missing := 0
		for part: String in recipe:
			if part != id and not owned.has(part):
				missing += 1
		if missing == 0:
			return f
	return ""


func is_fusion_ingredient(id: String) -> bool:
	for f: String in ItemDB.FUSIONS:
		if ItemDB.FUSIONS[f].recipe.has(id):
			return true
	return false


# ---------------------------------------------------------------- stats

func fire_interval_mult() -> float:
	return 1.0 / 1.2 if has("bellows_valve") else 1.0


func crit_chance() -> float:
	return Player.CRIT_CHANCE + (0.1 if has("cinder_lens") else 0.0)


func projectile_mult() -> float:
	return 1.3 if has("long_barrel") else 1.0


func heat_decay_mult() -> float:
	if cursed("hungry_coal"):
		return 0.0
	return 1.3 if has("heat_exchanger") else 1.0


## True while a Slagged item's drawback is still in force.
func cursed(id: String) -> bool:
	return owned.has(id) and ItemDB.is_slagged(id) and not absolved_ids.has(id)


func extra_projectiles() -> int:
	return 2 if has("brittle_crown") else 0


func vent_damage_mult() -> float:
	return 3.0 if has("hungry_coal") else 1.0


func hot_at() -> float:
	return 60.0 if has("feral_valve") else Heat.HOT_AT


func overheat_time() -> float:
	var t := 4.0 if cursed("feral_valve") else Heat.OVERHEAT_TIME
	return t + (1.0 if stoked else 0.0)


func hit_cost(amount: int, hot: bool) -> int:
	return 3 if hot and cursed("brittle_crown") else amount


## Lines for the Death Ledger: every risk the player accepted that is still live.
func active_risks() -> Array[String]:
	var out: Array[String] = []
	for id in owned:
		if cursed(id):
			out.append("%s: %s" % [ItemDB.ITEMS[id].name, ItemDB.ITEMS[id].drawback])
	if stoked:
		out.append("Stoke Altar: Overheat lasts 1 s longer")
	return out


func _process(delta: float) -> void:
	if cursed("feral_valve") and game.player != null and game.player.heat.band == Heat.Band.HOT and not game.dead:
		_progress("feral_valve", delta)


func on_room_clear(clean: bool) -> void:
	if cursed("brittle_crown"):
		if clean:
			_progress("brittle_crown", 1.0)
		else:
			absolution["brittle_crown"] = 0.0


func _progress(id: String, amount: float) -> void:
	absolution[id] = absolution.get(id, 0.0) + amount
	if absolution[id] >= ItemDB.ITEMS[id].goal:
		absolved_ids.append(id)
		absolved.emit(id)


func dash_recharge_mult() -> float:
	return 0.8 if has("heat_exchanger") else 1.0


func vent_cooldown() -> float:
	return Player.VENT_COOLDOWN - (1.5 if has("coolant_line") else 0.0)


func ricochets(hot: bool) -> int:
	var n := 1 if hot else 0
	if has("bank_shot"):
		n += 1
	if resonance("ricochet"):
		n += 1
	return n


func ignite_cap() -> int:
	return 15 if resonance("ignite") else 10


func proc_chance() -> float:
	return 0.5 + proc_bonus


func arc_targets(base: int) -> int:
	return base + (1 if resonance("arc") else 0)


func shard_count(base: int) -> int:
	return base + (2 if resonance("shrapnel") else 0)


# ---------------------------------------------------------------- hooks

func on_rivet_hit(e: Enemy, rivet: Rivet, crit: bool) -> void:
	if has("bellows_valve") and game.player.heat.band >= Heat.Band.WARM:
		proc_bonus = minf(0.2, proc_bonus + 0.02)
	var times := 2 if crit and has("cinder_lens") else 1
	for i in times:
		_apply_on_hit(e, rivet.overdrive)
	if has("static_rivets"):
		_static_hits += 1
		if _static_hits % 5 == 0:
			chain_arcs(e.global_position, arc_targets(2), 3.0 * C.TILE, 8.0, e)


func on_shard_hit(e: Enemy) -> void:
	if has("cluster_embers"):
		e.add_ignite(1, ignite_cap())
	if randf() < proc_chance():
		_apply_on_hit(e, false)


func _apply_on_hit(e: Enemy, hot: bool) -> void:
	if has("tinder_rounds"):
		e.add_ignite(1, ignite_cap())
	if has("pyre_coating") and hot:
		e.add_ignite(2, ignite_cap())


func on_kill(e: Enemy) -> void:
	var pos := e.global_position
	if e.last_kind == "vent" and cursed("hungry_coal"):
		_progress("hungry_coal", 1.0)
	if has("tinder_rounds") and e.ignite_stacks > 1:
		var share := e.ignite_stacks / 2
		game.fx.ring(pos, 1.5 * C.TILE, Color(1, 0.5, 0.15, 0.8), 0.2)
		for o in _enemies_near(pos, 1.5 * C.TILE):
			o.add_ignite(share, ignite_cap())
	if has("frag_lattice") and e.last_depth < SHARD_DEPTH_CAP:
		var n := shard_count(4)
		for i in n:
			var ang := PI / 4.0 + i * PI / 2.0 if i < 4 else randf() * TAU
			spawn_shard(pos, Vector2.from_angle(ang), e.last_depth + 1)
		Sfx.play_ramp("burst", -8.0)


func on_wall_stop(pos: Vector2, normal: Vector2) -> void:
	if not has("splinter_heads"):
		return
	for a in [-0.5, 0.0, 0.5]:
		spawn_shard(pos + normal * 4.0, normal.rotated(a), 1)


func on_overheat() -> void:
	if not has("pyre_coating"):
		return
	var p: Player = game.player
	for o in _enemies_near(p.global_position, 4.0 * C.TILE):
		o.add_ignite(3, ignite_cap())
	game.fx.ring(p.global_position, 4.0 * C.TILE, Color(1, 0.45, 0.1), 0.3)


## Called after the nova and rivet bursts have resolved.
func on_vent(_amount: float) -> void:
	proc_bonus = 0.0
	var p: Player = game.player
	if has("firestorm_lattice"):
		_detonate_flares()
	if has("feedback_coil"):
		var cands: Array = _enemies_near(p.global_position, 8.0 * C.TILE)
		cands.sort_custom(func(a: Enemy, b: Enemy) -> bool:
			if a.ignite_stacks != b.ignite_stacks:
				return a.ignite_stacks > b.ignite_stacks
			return a.global_position.distance_to(p.global_position) < b.global_position.distance_to(p.global_position))
		var n := mini(arc_targets(3), cands.size())
		for i in n:
			var e: Enemy = cands[i]
			if e.dead:
				continue
			var dmg := 10.0 + 5.0 * e.ignite_stacks
			e.clear_ignite()
			game.fx.arc(p.global_position, e.global_position)
			e.take_damage(dmg, false, Vector2.ZERO, "arc")
			if e.dead and has("heat_engine"):
				p.vent_cd = maxf(0.0, p.vent_cd - 0.5)
		if n > 0:
			Sfx.play("zap", 0.0, -4.0)
	if has("heat_engine"):
		p.heat.set_value(40.0)


func chain_arcs(from: Vector2, count: int, reach: float, dmg: float, skip: Enemy) -> void:
	var cands: Array = _enemies_near(from, reach)
	cands.erase(skip)
	cands.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	for i in mini(count, cands.size()):
		var e: Enemy = cands[i]
		game.fx.arc(from, e.global_position)
		e.take_damage(dmg, false, Vector2.ZERO, "arc")
	if not cands.is_empty():
		Sfx.play("zap", 3.0, -8.0)


func spawn_shard(pos: Vector2, dir: Vector2, depth: int) -> void:
	var s := Shard.new()
	s.game = game
	s.position = pos
	s.dir = dir.normalized()
	s.depth = depth
	s.homing = has("cluster_embers")
	s.flare = has("firestorm_lattice")
	s.speed_mult = projectile_mult()
	game.world.add_child(s)


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
		game.fx.rivet_burst(pt, 1)
		for o in _enemies_near(pt, C.TILE):
			o.take_damage(12.0, false, Vector2.ZERO, "flare")
	# Lightning web between flares within 4 tiles: damages everything it crosses.
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var a := pts[i]
			var b := pts[j]
			if a.distance_to(b) > 4.0 * C.TILE:
				continue
			game.fx.arc(a, b, 0.35)
			for o in get_tree().get_nodes_in_group("enemies"):
				var en: Enemy = o
				if en.dead or hit.has(en):
					continue
				var closest := Geometry2D.get_closest_point_to_segment(en.global_position, a, b)
				if closest.distance_to(en.global_position) <= en.radius + 10.0:
					hit[en] = true
					en.take_damage(12.0, false, Vector2.ZERO, "arc")
	game.hud.dim(0.15)
	Juice.hitstop(8)
	Juice.add_trauma(0.4)
	Sfx.play("zap", -5.0, 0.0)
	Sfx.play("fusion", 5.0, -6.0)


func _enemies_near(pos: Vector2, reach: float) -> Array:
	var out := []
	for o in get_tree().get_nodes_in_group("enemies"):
		var e: Enemy = o
		if not e.dead and e.global_position.distance_to(pos) <= reach + e.radius:
			out.append(e)
	return out
