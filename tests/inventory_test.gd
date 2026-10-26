extends Node

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	_fusion_ownership()
	_tempered_modifiers()
	_picker_card_presentation()
	print("inventory test: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _fusion_ownership() -> void:
	var inventory := Inventory.new()
	inventory.add("tinder_rounds")
	inventory.force_fusion("cluster_embers")
	check(inventory.has("frag_lattice"), "Forced Cluster Embers supplies the missing Frag Lattice ingredient")
	check(inventory.missing_ingredients("firestorm_lattice") == ["feedback_coil"], "Forced ownership leaves only Feedback Coil missing for Firestorm Lattice")
	check(inventory.fusion_completed_by("feedback_coil") == "firestorm_lattice", "The completion query identifies the fusion unlocked by Feedback Coil")
	inventory.add("feedback_coil")
	check(inventory.has("firestorm_lattice"), "Acquiring Feedback Coil unlocks Firestorm Lattice")
	inventory.free()


func _picker_card_presentation() -> void:
	var inventory := Inventory.new()
	inventory.add("tinder_rounds")
	var offer := Picker.items(["frag_lattice", "patch_kit"], inventory, "SALVAGE", Callable())
	check(offer.cards["frag_lattice"].hint == "COMPLETES FUSION: " + ItemDB.FUSIONS.cluster_embers.name, "Item offers resolve fusion hints before the picker draws")
	check(offer.cards["patch_kit"].hint == "" and not ItemDB.ITEMS.frag_lattice.has("hint"), "Offer presentation preserves Patch Kit behavior and does not mutate the shared item catalog")
	inventory.add("frag_lattice")
	offer = Picker.items(["splinter_heads"], inventory, "SALVAGE", Callable())
	check(offer.cards["splinter_heads"].hint == "UNLOCKS RESONANCE: SHRAPNEL", "Item offers resolve resonance hints from the current inventory snapshot")
	inventory.free()


func _tempered_modifiers() -> void:
	# Expected values describe the player-facing item and Anvil upgrade promises.
	var contracts := [
		["bellows_valve", "fire_interval_mult", [], 1.0, 1.0 / 1.2, 1.0 / 1.35],
		["cinder_lens", "crit_chance", [], Player.CRIT_CHANCE, Player.CRIT_CHANCE + 0.1, Player.CRIT_CHANCE + 0.2],
		["long_barrel", "projectile_mult", [], 1.0, 1.3, 1.5],
		["heat_exchanger", "heat_decay_mult", [], 1.0, 1.3, 1.6],
		["heat_exchanger", "dash_recharge_mult", [], 1.0, 0.8, 0.65],
		["coolant_line", "vent_cooldown", [], Player.VENT_COOLDOWN, Player.VENT_COOLDOWN - 1.5, Player.VENT_COOLDOWN - 2.5],
		["bank_shot", "ricochets", [false], 0, 1, 2],
		["bank_shot", "ricochets", [true], 1, 2, 3],
	]
	for contract: Array in contracts:
		var inventory := Inventory.new()
		var id: String = contract[0]
		var getter: String = contract[1]
		var args: Array = contract[2]
		check(is_equal_approx(float(inventory.callv(getter, args)), contract[3]), "%s has its baseline without %s" % [getter, id])
		inventory.add(id)
		check(is_equal_approx(float(inventory.callv(getter, args)), contract[4]), "%s grants its ordinary %s modifier" % [id, getter])
		inventory.temper(id)
		check(is_equal_approx(float(inventory.callv(getter, args)), contract[5]), "Tempering %s strengthens %s" % [id, getter])
		inventory.remove(id)
		check(not inventory.is_tempered(id) and is_equal_approx(float(inventory.callv(getter, args)), contract[3]), "Removing %s clears the upgrade and restores %s" % [id, getter])
		inventory.add(id)
		check(is_equal_approx(float(inventory.callv(getter, args)), contract[4]), "Reacquiring %s does not retain its consumed upgrade" % id)
		inventory.free()
