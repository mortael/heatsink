extends Node
## Deterministic contracts for the three printed Slagged-item Absolution goals.

const InventoryScript = preload("res://scripts/combat/inventory.gd")
const PlayerScript = preload("res://scripts/combat/player.gd")
const EnemyScript = preload("res://scripts/combat/enemies/enemy.gd")
const CombatEffectsScript = preload("res://scripts/combat/combat_effects.gd")

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	_brittle_crown()
	_hungry_coal()
	_feral_valve()
	print("absolution test: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _brittle_crown() -> void:
	var inventory := InventoryScript.new()
	var events: Array[String] = []
	inventory.absolved.connect(func(id: String) -> void: events.append(id))
	inventory.add("brittle_crown")
	inventory.on_room_clear(true)
	inventory.on_room_clear(false)
	check(inventory.absolution["brittle_crown"] == 0.0, "Taking damage resets the clean-room streak")
	inventory.on_room_clear(true)
	inventory.on_room_clear(true)
	check(events.is_empty() and inventory.cursed("brittle_crown"), "Two clean rooms do not absolve Brittle Crown")
	check(inventory.hit_cost(1, true) == 3 and inventory.hit_cost(1, false) == 1, "Brittle Crown's drawback applies only while Hot")
	inventory.on_room_clear(true)
	check(events == ["brittle_crown"] and not inventory.cursed("brittle_crown"), "The third consecutive clean room absolves Brittle Crown once")
	check(inventory.hit_cost(1, true) == 1 and inventory.extra_projectiles() == 2, "Absolution removes the Hot damage penalty and retains the extra Rivets")
	inventory.on_room_clear(true)
	inventory.on_room_clear(false)
	check(events.size() == 1 and inventory.absolution["brittle_crown"] == 3.0, "Later rooms cannot reset completed Absolution or emit it again")
	inventory.free()


func _hungry_coal() -> void:
	var inventory := InventoryScript.new()
	var effects := CombatEffectsScript.new()
	effects.inventory = inventory
	var events: Array[String] = []
	inventory.absolved.connect(func(id: String) -> void: events.append(id))
	inventory.add("hungry_coal")
	var victim := EnemyScript.new()
	victim.last_kind = Enemy.DamageKind.RIVET
	effects.on_kill(victim)
	check(inventory.absolution["hungry_coal"] == 0.0, "Non-Vent kills do not advance Hungry Coal")
	victim.last_kind = Enemy.DamageKind.VENT
	for i in 39:
		effects.on_kill(victim)
	check(events.is_empty() and inventory.cursed("hungry_coal") and inventory.heat_decay_mult() == 0.0, "Thirty-nine Vent kills leave Hungry Coal's decay drawback active")
	effects.on_kill(victim)
	check(events == ["hungry_coal"] and not inventory.cursed("hungry_coal"), "The fortieth Vent kill absolves Hungry Coal once")
	check(inventory.heat_decay_mult() == 1.0 and inventory.vent_damage_mult() == 3.0, "Hungry Coal restores heat decay while retaining triple Vent damage")
	effects.on_kill(victim)
	check(events.size() == 1 and inventory.absolution["hungry_coal"] == 40.0, "Later Vent kills do not emit completed Absolution again")
	victim.free()
	inventory.free()
	effects.free()


func _feral_valve() -> void:
	var inventory := InventoryScript.new()
	var player := PlayerScript.new()
	# Keep Heat owned without entering Player's scene-dependent _ready callback.
	player.add_child(player.heat)
	var effects := CombatEffectsScript.new()
	effects.inventory = inventory
	effects.player = player
	var events: Array[String] = []
	inventory.absolved.connect(func(id: String) -> void: events.append(id))
	inventory.add("feral_valve")
	effects._process(10.0)
	check(inventory.absolution["feral_valve"] == 0.0, "Cold time does not advance Feral Valve")
	player.heat.set_value(80.0)
	inventory.run_active = false
	effects._process(10.0)
	check(inventory.absolution["feral_valve"] == 0.0, "Hot time outside an active run does not advance Feral Valve")
	inventory.run_active = true
	effects._process(89.0)
	check(events.is_empty() and inventory.cursed("feral_valve") and inventory.overheat_time() == 4.0, "Eighty-nine Hot seconds leave Feral Valve's longer Overheat active")
	effects._process(1.0)
	check(events == ["feral_valve"] and not inventory.cursed("feral_valve"), "The ninetieth Hot second absolves Feral Valve once")
	check(inventory.overheat_time() == Heat.OVERHEAT_TIME and inventory.hot_at() == 60.0, "Feral Valve restores Overheat duration and retains the lower Overdrive threshold")
	effects._process(10.0)
	check(events.size() == 1 and inventory.absolution["feral_valve"] == 90.0, "Later Hot time does not emit completed Absolution again")
	inventory.free()
	player.free()
	effects.free()
