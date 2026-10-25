extends Node
## Public shop, vault, and wager transactions with controlled random outcomes.

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	var strength: float = Juice.hitstop_strength
	Juice.hitstop_strength = 0.0
	await _special_room_transaction_contracts()
	await _coin_outcomes()
	await _crucible_outcomes()
	Juice.hitstop_strength = strength
	Juice.reset()
	print("special rooms test: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _special_room_transaction_contracts() -> void:
	var shop_game: RunGame = load("res://main.tscn").instantiate()
	add_child(shop_game)
	shop_game.set_process(false)
	shop_game.player.set_physics_process(false)
	shop_game.director.set_physics_process(false)
	shop_game.scrap = 1000
	var shop_start := shop_game.special_rooms.pedestals.size()
	shop_game.special_rooms.setup("shop")
	var shop_stock: Array[Pedestal] = shop_game.special_rooms.pedestals.slice(shop_start)
	var purchased: Pedestal = shop_stock.filter(func(p: Pedestal) -> bool: return p.kind == "item")[0]
	shop_game.special_rooms.use_pedestal(purchased)
	var purchase_id := purchased.item_id
	var reroll: Pedestal = shop_stock.filter(func(p: Pedestal) -> bool: return p.kind == "reroll")[0]
	var scrap_before_reroll := shop_game.scrap
	shop_game.special_rooms.use_pedestal(reroll)
	check(not purchased.active and shop_game.inventory.has(purchase_id), "Reroll keeps purchased stock sold and retains the purchased item")
	check(shop_game.scrap == scrap_before_reroll - SpecialRooms.REROLL_PRICE and reroll.price == SpecialRooms.REROLL_PRICE + SpecialRooms.REROLL_STEP, "First shop reroll charges its posted price and raises the next price")
	scrap_before_reroll = shop_game.scrap
	shop_game.special_rooms.use_pedestal(reroll)
	check(shop_game.scrap == scrap_before_reroll - (SpecialRooms.REROLL_PRICE + SpecialRooms.REROLL_STEP) and reroll.price == SpecialRooms.REROLL_PRICE + 2 * SpecialRooms.REROLL_STEP, "Each later reroll charges the updated price exactly once")
	var wager_start := shop_game.special_rooms.pedestals.size()
	shop_game.special_rooms.setup("wager")
	var wager_stock: Array[Pedestal] = shop_game.special_rooms.pedestals.slice(wager_start)
	var coin: Pedestal = wager_stock.filter(func(p: Pedestal) -> bool: return p.kind == "coinflip")[0]
	shop_game.player.max_pips = 1
	shop_game.player.pips = 1
	shop_game.special_rooms.use_pedestal(coin, 0.9)
	check(shop_game.player.max_pips == 1 and shop_game.player.pips == 1 and coin.active, "Coin refusal at minimum plating preserves both plating values and the wager")
	shop_game.player.max_pips = 6
	shop_game.player.pips = 4
	shop_game.special_rooms.use_pedestal(coin, 0.9)
	check(shop_game.player.max_pips == 5 and shop_game.player.pips == 4 and not coin.active, "A valid coin wager costs one maximum plating pip and resolves once")
	shop_game.special_rooms.use_pedestal(coin, 0.9)
	check(shop_game.player.max_pips == 5 and shop_game.player.pips == 4, "Reusing a resolved coin wager cannot charge plating again")
	if shop_game.picker.is_open:
		shop_game.picker.cancel()
	var crucible_start := shop_game.special_rooms.pedestals.size()
	shop_game.special_rooms.setup("wager")
	var crucible: Pedestal = shop_game.special_rooms.pedestals.slice(crucible_start).filter(func(p: Pedestal) -> bool: return p.kind == "crucible")[0]
	for id: String in ItemDB.ITEMS:
		if ItemDB.is_slagged(id):
			shop_game.inventory.add(id)
	shop_game.inventory.add("tinder_rounds")
	shop_game.special_rooms.use_pedestal(crucible)
	check(shop_game.picker.is_open and shop_game.picker.options.has("tinder_rounds"), "Crucible interaction offers owned feedable items")
	shop_game.picker.cancel()
	shop_game.special_rooms.feed_crucible("tinder_rounds", 0.9)
	check(shop_game.inventory.has("tinder_rounds"), "Crucible refusal preserves the fed item when the rolled outcome has no available result")
	shop_game.queue_free()
	await get_tree().process_frame

	var bath_game: RunGame = load("res://main.tscn").instantiate()
	add_child(bath_game)
	bath_game.set_process(false)
	bath_game.player.set_physics_process(false)
	bath_game.director.set_physics_process(false)
	bath_game.player.pips = 2
	var vault_start := bath_game.special_rooms.pedestals.size()
	bath_game.special_rooms.setup("vault")
	var vault: Array[Pedestal] = bath_game.special_rooms.pedestals.slice(vault_start)
	var bath: Pedestal = vault.filter(func(p: Pedestal) -> bool: return p.kind == "vault_repair")[0]
	var anvil: Pedestal = vault.filter(func(p: Pedestal) -> bool: return p.kind == "anvil")[0]
	bath_game.special_rooms.use_pedestal(bath)
	check(bath_game.player.pips == 4 and not bath.active and not anvil.active, "Choosing the Bath repairs plating and deactivates the competing Anvil")
	bath_game.queue_free()
	await get_tree().process_frame

	var anvil_game: RunGame = load("res://main.tscn").instantiate()
	add_child(anvil_game)
	anvil_game.set_process(false)
	anvil_game.player.set_physics_process(false)
	anvil_game.director.set_physics_process(false)
	anvil_game.inventory.add("tinder_rounds")
	anvil_game.cores = 1
	vault_start = anvil_game.special_rooms.pedestals.size()
	anvil_game.special_rooms.setup("vault")
	vault = anvil_game.special_rooms.pedestals.slice(vault_start)
	bath = vault.filter(func(p: Pedestal) -> bool: return p.kind == "vault_repair")[0]
	anvil = vault.filter(func(p: Pedestal) -> bool: return p.kind == "anvil")[0]
	anvil_game.special_rooms.use_pedestal(anvil)
	anvil_game.special_rooms.use_anvil("temper:tinder_rounds")
	check(anvil_game.cores == 0 and anvil_game.inventory.is_tempered("tinder_rounds") and not bath.active, "Choosing a valid Anvil temper spends its Core and deactivates the competing Bath")
	if anvil_game.picker.is_open:
		anvil_game.picker.cancel()
	anvil_game.queue_free()
	await get_tree().process_frame


func _wager_game() -> RunGame:
	var game: RunGame = load("res://main.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	game.player.set_physics_process(false)
	game.director.set_physics_process(false)
	game.special_rooms.setup("wager")
	return game


func _coin_outcomes() -> void:
	for roll: float in [0.0, 0.9]:
		var game := _wager_game()
		var coin: Pedestal = game.special_rooms.pedestals.filter(func(p: Pedestal) -> bool: return p.kind == "coinflip")[0]
		game.player.max_pips = 6
		game.player.pips = 6
		game.special_rooms.use_pedestal(coin, roll)
		check(game.player.max_pips == 5 and game.player.pips == 5 and not coin.active, "Either coin outcome charges one maximum plating pip and clamps current plating")
		if roll < 0.6:
			var choices := game.picker.options.duplicate()
			check(game.picker.is_open and not choices.is_empty() and choices.all(func(id: String) -> bool: return ItemDB.ITEMS[id].rarity == "Rare" and not game.inventory.has(id)), "A winning coin offers only unowned Rare rewards")
			game.picker.cancel()
			check(game.picker.is_open and game.inventory.owned.is_empty(), "A winning coin cannot be cancelled after paying its stake")
			if not choices.is_empty():
				game.picker.choose(0)
				check(game.inventory.has(choices[0]) and not game.picker.is_open and not get_tree().paused, "Choosing a coin reward grants the selected item and resumes gameplay")
		else:
			check(not game.picker.is_open and game.inventory.owned.is_empty(), "A losing coin grants no reward and opens no picker")
		var after_wager := game.inventory.owned.duplicate()
		game.special_rooms.use_pedestal(coin, roll)
		check(game.player.max_pips == 5 and game.player.pips == 5 and game.inventory.owned == after_wager and not game.picker.is_open, "A resolved coin cannot charge or grant a reward a second time")
		get_tree().paused = false
		game.queue_free()
		await get_tree().process_frame

	var exhausted := _wager_game()
	for id: String in ItemDB.ITEMS:
		if ItemDB.ITEMS[id].rarity == "Rare":
			exhausted.inventory.add(id)
	var coin: Pedestal = exhausted.special_rooms.pedestals.filter(func(p: Pedestal) -> bool: return p.kind == "coinflip")[0]
	exhausted.special_rooms.use_pedestal(coin, 0.0)
	check(coin.active and exhausted.player.max_pips == 6 and not exhausted.picker.is_open, "A coin refuses an exhausted Rare pool without charging plating")
	exhausted.queue_free()
	await get_tree().process_frame


func _crucible_outcomes() -> void:
	for outcome: Dictionary in [{"roll": 0.0, "kind": "upgrade"}, {"roll": 0.6, "kind": "transmute"}, {"roll": 0.9, "kind": "slagged"}]:
		var game := _wager_game()
		game.inventory.add("tinder_rounds")
		var crucible: Pedestal = game.special_rooms.pedestals.filter(func(p: Pedestal) -> bool: return p.kind == "crucible")[0]
		game.special_rooms.use_pedestal(crucible)
		game.picker.cancel()
		check(game.inventory.owned == ["tinder_rounds"] and crucible.active and not get_tree().paused, "Cancelling the Crucible preserves its item and leaves the offer usable")
		game.special_rooms.feed_crucible("tinder_rounds", outcome.roll)
		check(not game.inventory.owned.has("tinder_rounds") and game.inventory.owned.size() == 1 and not crucible.active, "A successful Crucible outcome consumes the fed item and produces one replacement")
		if game.inventory.owned.size() == 1:
			var replacement: Dictionary = ItemDB.ITEMS[game.inventory.owned[0]]
			match outcome.kind:
				"upgrade":
					check(ItemDB.RARITY_RANK[replacement.rarity] > ItemDB.RARITY_RANK["Uncommon"], "Crucible upgrade returns an item of higher rarity")
				"transmute":
					check(replacement.keyword == "ignite", "Crucible transmutation preserves the fed item's keyword")
				"slagged":
					check(replacement.rarity == "Slagged", "Crucible Slagged outcome produces a Slagged item")
		var result := game.inventory.owned.duplicate()
		game.special_rooms.use_pedestal(crucible)
		check(game.inventory.owned == result and not game.picker.is_open and game.player.max_pips == 6, "A resolved Crucible cannot consume or grant another item through repeat interaction")
		game.queue_free()
		await get_tree().process_frame
