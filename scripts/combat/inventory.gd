class_name Inventory
extends Node
## Owned items, Resonance and Fusions: ownership, offers, tempering and fusion eligibility,
## plus the stat getters combat code queries. Live item triggers and projectile spawning
## live in CombatEffects, which reads this inventory to decide what owning an item does.

signal changed
signal fusion_unlocked(id: String)
signal absolved(id: String)

var player: Player # heals on a Patch Kit pickup and tells offers/stats which Frame is active
var run_active := true
var owned: Array[String] = []
var fusions: Array[String] = []
var proc_bonus := 0.0
var stoked := false # Stoke Altar: Heat cap 120, Overheat +1 s
var absolution := {} # slagged id -> progress toward its Absolution goal
var absolved_ids: Array[String] = []
var tempered: Array[String] = [] # items upgraded at the Anvil
var forged := {} # fusion id -> the ingredient a Forced Fusion stood in for


## A Forced Fusion's stand-in counts as owning the missing ingredient's behaviour too.
func has(id: String) -> bool:
	return owned.has(id) or fusions.has(id) or forged.values().has(id)


## The Frame being played; items that only make sense for some Frames are left out of offers.
func frame() -> String:
	return player.frame if player != null else Frames.DEFAULT


func fits(id: String) -> bool:
	return ItemDB.fits(id, frame())


func count_keyword(kw: String) -> int:
	var n := 0
	for id in owned:
		if ItemDB.ITEMS[id].keyword == kw and kw != "slagged":
			n += 1
	for id: String in forged.values():
		if not owned.has(id) and ItemDB.ITEMS[id].keyword == kw:
			n += 1 # a Forced Fusion's stand-in counts toward Resonance
	return n


func resonance(kw: String) -> bool:
	return count_keyword(kw) >= 2


func add(id: String) -> void:
	if id == "patch_kit":
		player.repair(1)
		changed.emit()
		return
	if owned.has(id):
		return
	owned.append(id)
	if ItemDB.is_slagged(id):
		absolution[id] = 0.0
	_unlock_completed_fusions()
	changed.emit()


func _unlock_completed_fusions() -> void:
	for f: String in ItemDB.FUSIONS:
		if fusions.has(f):
			continue
		if missing_ingredients(f).is_empty():
			fusions.append(f)
			fusion_unlocked.emit(f)


## Drops an item (fed to the Crucible). Fusions that lose an ingredient go with it.
func remove(id: String) -> void:
	owned.erase(id)
	tempered.erase(id)
	absolution.erase(id)
	absolved_ids.erase(id)
	var invalidated_fusion := true
	while invalidated_fusion:
		invalidated_fusion = false
		for f: String in fusions.duplicate():
			var loses_real_ingredient: bool = ItemDB.FUSIONS[f].recipe.has(id) and forged.get(f, "") != id
			if loses_real_ingredient or not missing_ingredients(f).is_empty():
				fusions.erase(f)
				forged.erase(f) # a Forced Fusion keeps its own paid-for stand-in
				invalidated_fusion = true
	changed.emit()


func temper(id: String) -> void:
	if not tempered.has(id):
		tempered.append(id)
	changed.emit()


func is_tempered(id: String) -> bool:
	return tempered.has(id)


## Items the Anvil can still temper.
func temperable() -> Array[String]:
	var out: Array[String] = []
	for id in owned:
		if ItemDB.TEMPER.has(id) and not tempered.has(id):
			out.append(id)
	return out


## Fusions one ingredient short: a Forced Fusion (3 Cores) stands in for the missing piece.
func forgeable() -> Array[String]:
	var out: Array[String] = []
	for f: String in ItemDB.FUSIONS:
		if fusions.has(f):
			continue
		if missing_ingredients(f).size() == 1:
			out.append(f)
	return out


func missing_ingredients(f: String) -> Array[String]:
	var out: Array[String] = []
	for part: String in ItemDB.FUSIONS[f].recipe:
		if not has(part):
			out.append(part)
	return out


func force_fusion(f: String) -> void:
	var miss := missing_ingredients(f)
	if miss.size() != 1 or fusions.has(f):
		return
	forged[f] = miss[0]
	_unlock_completed_fusions()
	changed.emit()


## Pick n distinct offers. Each slot rolls 40% from keywords you already own or your Frame's native
## keyword, 60% from the open pool. Items that don't fit the Frame are never offered.
## Slagged items never appear here; filter narrows the pool and exclude skips ids already on show.
## An unfiltered offer pads empty slots with Patch Kits; a filtered one returns only matching items,
## so it can come back short or empty.
func offer(n := 3, filter := Callable(), exclude: Array[String] = []) -> Array[String]:
	var pool: Array[String] = []
	for id: String in ItemDB.ITEMS:
		if owned.has(id) or exclude.has(id) or ItemDB.is_slagged(id) or not fits(id):
			continue
		if filter.is_valid() and not filter.call(id):
			continue
		pool.append(id)
	var native: String = Frames.info(frame()).keyword
	var result: Array[String] = []
	for i in n:
		if pool.is_empty():
			break
		var themed: Array[String] = []
		for id in pool:
			var kw: String = ItemDB.ITEMS[id].keyword
			if kw != "conductor" and (count_keyword(kw) > 0 or kw == native):
				themed.append(id)
		var pick: String = themed.pick_random() if not themed.is_empty() and randf() < 0.4 else pool.pick_random()
		pool.erase(pick)
		result.append(pick)
	while result.size() < n and not filter.is_valid():
		result.append("patch_kit")
	return result


## Fusion this item would complete if picked now ("" if none).
func fusion_completed_by(id: String) -> String:
	for f: String in ItemDB.FUSIONS:
		if fusions.has(f):
			continue
		var recipe: Array = ItemDB.FUSIONS[f].recipe
		if not recipe.has(id):
			continue
		var missing := missing_ingredients(f)
		missing.erase(id)
		if missing.is_empty():
			return f
	return ""


func is_fusion_ingredient(id: String) -> bool:
	for f: String in ItemDB.FUSIONS:
		if ItemDB.FUSIONS[f].recipe.has(id):
			return true
	return false


# ---------------------------------------------------------------- stats

func fire_interval_mult() -> float:
	if not has("bellows_valve"):
		return 1.0
	return 1.0 / (1.35 if is_tempered("bellows_valve") else 1.2)


func crit_chance() -> float:
	if not has("cinder_lens"):
		return Player.CRIT_CHANCE
	return Player.CRIT_CHANCE + (0.2 if is_tempered("cinder_lens") else 0.1)


func projectile_mult() -> float:
	if not has("long_barrel"):
		return 1.0
	return 1.5 if is_tempered("long_barrel") else 1.3


func heat_decay_mult() -> float:
	if cursed("hungry_coal"):
		return 0.0
	if not has("heat_exchanger"):
		return 1.0
	return 1.6 if is_tempered("heat_exchanger") else 1.3


## True while a Slagged item's drawback is still in force.
func cursed(id: String) -> bool:
	return owned.has(id) and ItemDB.is_slagged(id) and not absolved_ids.has(id)


## Brittle Crown: +2 rivets (Riveter), a shockwave on every swing (Furnace) or +2 beam forks (Arclight).
func extra_projectiles() -> int:
	return 2 if has("brittle_crown") and frame() == "riveter" else 0


func extra_shockwaves() -> int:
	return 1 if has("brittle_crown") and frame() == "furnace" else 0


func extra_forks() -> int:
	return 2 if has("brittle_crown") and frame() == "arclight" else 0


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


func on_room_clear(clean: bool) -> void:
	if cursed("brittle_crown"):
		if clean:
			progress_absolution("brittle_crown", 1.0)
		else:
			absolution["brittle_crown"] = 0.0


## Advances a Slagged item's Absolution goal; CombatEffects calls this from its own triggers too.
func progress_absolution(id: String, amount: float) -> void:
	absolution[id] = absolution.get(id, 0.0) + amount
	if absolution[id] >= ItemDB.ITEMS[id].goal:
		absolved_ids.append(id)
		absolved.emit(id)


func dash_recharge_mult() -> float:
	if not has("heat_exchanger"):
		return 1.0
	return 0.65 if is_tempered("heat_exchanger") else 0.8


func vent_cooldown() -> float:
	if not has("coolant_line"):
		return Player.VENT_COOLDOWN
	return Player.VENT_COOLDOWN - (2.5 if is_tempered("coolant_line") else 1.5)


func ricochets(hot: bool) -> int:
	var n := 1 if hot else 0
	if has("bank_shot"):
		n += 2 if is_tempered("bank_shot") else 1
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


func molten_scale() -> float:
	return 1.5 if resonance("molten") else 1.0


func molten_extra_life() -> float:
	return 1.0 if resonance("molten") else 0.0


func molten_dps() -> float:
	return SlagPool.DPS * (2.0 if is_tempered("slag_trail") else 1.0)
