class_name SpecialRooms
extends RefCounted
## Special-room offers and transactions. The run owns scene lifecycle and rewards.

const REPAIR_PRICE := 40
const REROLL_PRICE := 15
const REROLL_STEP := 10
const ALTAR_CHANCE := 1.0 / 3.0 # Altars sit in 1 of every 3 Cooling Vaults (GDD section 4)

var game: RunGame
var pedestals: Array[Pedestal] = []
var _reroll_price := REROLL_PRICE


func _init(run: RunGame) -> void:
	game = run


func setup(kind: String) -> void:
	var t := C.TILE
	match kind:
		"shop":
			var stock: Array[String] = []
			var conductors := func(id: String) -> bool: return ItemDB.ITEMS[id].keyword == "conductor"
			stock.append_array(game.inventory.offer(1, conductors))
			var others := func(id: String) -> bool: return ItemDB.ITEMS[id].keyword != "conductor"
			stock.append_array(game.inventory.offer(3, others, stock))
			for i in stock.size():
				_item_pedestal(stock[i], Vector2((6 + i * 4) * t, 6 * t))
			var rep := _pedestal("repair", Vector2(8 * t, 9 * t), "Patch Plating", ["Repair 1 Plating pip."], Color(0.8, 0.85, 0.9))
			rep.price = REPAIR_PRICE
			_reroll_price = REROLL_PRICE
			var rr := _pedestal("reroll", Vector2(16 * t, 9 * t), "Reroll stock", ["Replace every unsold item.", "Each reroll costs 10 more."], Color(1, 0.85, 0.3))
			rr.price = _reroll_price
		"vault":
			# Choose one: the Bath or the Anvil (GDD section 6). Altars are a separate, optional offer.
			_pedestal("vault_repair", Vector2(8 * t, 6.5 * t), "Cooling Bath", ["Repair 2 Plating pips.", "Choose the Bath or the Anvil: the other goes cold."], Color(0.45, 0.8, 1.0))
			_pedestal("anvil", Vector2(12 * t, 6.5 * t), "The Anvil", ["Temper an item for 1 Core: upgrades how it works.", "Forced Fusion for 3 Cores: stands in for the one ingredient you're missing.", "Choose the Bath or the Anvil: the other goes cold."], Color(0.55, 0.95, 1.0))
			if randf() < ALTAR_CHANCE and not game.inventory.stoked:
				_pedestal("altar", Vector2(16 * t, 6.5 * t), "Stoke Altar", ["Heat cap rises to 120: 20 more Heat of Overdrive.", "!Costs 1 max Plating pip. Overheat lasts 1 s longer."], Color(1.0, 0.45, 0.2))
		"wager":
			_pedestal("crucible", Vector2(9 * t, 6.5 * t), "The Crucible", ["Feed in one owned item:", "50%: it upgrades to a higher rarity", "35%: it transmutes to a same-keyword item", "!15%: it becomes Slagged"], Color(0.8, 0.45, 1.0))
			_pedestal("coinflip", Vector2(15 * t, 6.5 * t), "Ember Coin", ["Stake 1 max Plating pip on a 60% flip.", "Win: choose a Rare item you don't own.", "!Lose: the pip is gone."], Color(1.0, 0.55, 0.25))


func _pedestal(kind: String, pos: Vector2, title: String, lines: Array[String], color: Color) -> Pedestal:
	var p := Pedestal.new()
	p.game = game
	p.kind = kind
	p.position = pos
	p.title = title
	p.lines = lines
	p.color = color
	game.world.add_child(p)
	pedestals.append(p)
	return p


func _item_pedestal(id: String, pos: Vector2) -> Pedestal:
	var item: Dictionary = ItemDB.get_item(id)
	var tag := "%s · %s" % [item.keyword.to_upper(), item.rarity]
	var p := _pedestal("item", pos, item.name, [tag, item.desc], ItemDB.keyword_color(item.keyword))
	p.item_id = id
	p.price = ItemDB.price(id) if id != "patch_kit" else REPAIR_PRICE
	return p


## A nonnegative coin_roll selects a deterministic wager outcome for simulations.
func use_pedestal(p: Pedestal, coin_roll := -1.0) -> void:
	if not p.active:
		return
	if p.price > 0 and game.scrap < p.price:
		Sfx.play("player_hit", 6.0, -12.0)
		return
	match p.kind:
		"item":
			game.spend_scrap(p.price)
			game.inventory.add(p.item_id)
			p.active = false
			_buy_fx(p)
		"repair":
			if game.player.pips >= game.player.max_pips:
				game.hud.banner("PLATING IS FULL")
				return
			game.spend_scrap(p.price)
			game.player.repair(1)
			_buy_fx(p)
		"reroll":
			if not pedestals.any(func(q: Pedestal) -> bool: return q.kind == "item" and q.active and q.item_id != "patch_kit"):
				game.hud.banner("NOTHING TO REROLL")
				return
			game.spend_scrap(p.price)
			_reroll_price += REROLL_STEP
			p.price = _reroll_price
			_reroll_shop()
			_buy_fx(p)
		"vault_repair":
			game.player.repair(2)
			_vault_choice(p, ["vault_repair", "anvil"])
		"anvil":
			_open_anvil()
		"altar":
			if game.inventory.stoked:
				game.hud.banner("ALREADY STOKED", "The Altar has nothing more to give")
				return
			if game.player.max_pips <= 1:
				game.hud.banner("NOT ENOUGH PLATING")
				return
			game.player.stoke()
			game.hud.banner("STOKED", "Heat cap 120 · Overheat lasts 1 s longer")
			_vault_choice(p, ["altar"])
		"crucible":
			var feedable: Array[String] = []
			for id in game.inventory.owned:
				if not ItemDB.is_slagged(id):
					feedable.append(id)
			if feedable.is_empty():
				game.hud.banner("NOTHING TO FEED", "Own an item first")
				return
			var offer := Picker.items(feedable, game.inventory, "FEED THE CRUCIBLE", _complete_crucible)
			offer.subtitle = "50% upgrade  ·  35% transmute  ·  15% Slagged"
			offer.cancellable = true
			game.picker.open(offer)
		"coinflip":
			_flip_coin(p, coin_roll)


func _open_anvil() -> void:
	var cards := anvil_cards()
	var opts: Array[String] = []
	opts.assign(cards.keys())
	if opts.is_empty():
		if game.cores < ItemDB.TEMPER_COST:
			game.hud.banner("THE ANVIL NEEDS A CORE", "Elites drop Cores")
		else:
			game.hud.banner("NOTHING TO TEMPER", "Own an untempered item first")
		Sfx.play("player_hit", 6.0, -12.0)
		return
	var offer := Picker.Offer.new()
	offer.options = opts
	offer.cards = cards
	offer.title = "THE ANVIL"
	offer.subtitle = "%d Core%s  ·  Temper 1  ·  Forced Fusion 3" % [game.cores, "" if game.cores == 1 else "s"]
	offer.cancellable = true
	offer.complete = use_anvil
	game.picker.open(offer)


func anvil_cards() -> Dictionary:
	var cards := {}
	if game.cores >= ItemDB.TEMPER_COST:
		for id in game.inventory.temperable():
			var item: Dictionary = ItemDB.ITEMS[id]
			cards["temper:" + id] = {
				"name": "Temper " + item.name, "keyword": item.keyword, "tier": item.tier,
				"rarity": "1 Core", "desc": ItemDB.TEMPER[id], "hint": "Lasts the rest of the run",
			}
	if game.cores >= ItemDB.FORGE_COST:
		for id in game.inventory.forgeable():
			var fusion: Dictionary = ItemDB.FUSIONS[id]
			var missing := game.inventory.missing_ingredients(id)
			cards["forge:" + id] = {
				"name": "Force " + fusion.name, "keyword": "fusion", "tier": "C", "rarity": "3 Cores",
				"desc": fusion.desc, "hint": "Stands in for " + ItemDB.ITEMS[missing[0]].name,
			}
	return cards


func _flip_coin(p: Pedestal, roll: float) -> void:
	if game.player.max_pips <= 1:
		game.hud.banner("NOT ENOUGH PLATING")
		return
	var rare := func(id: String) -> bool: return ItemDB.ITEMS[id].rarity == "Rare"
	if game.inventory.offer(1, rare).is_empty():
		game.hud.banner("THE COIN WON'T FLIP", "You already own every Rare")
		return
	p.active = false
	game.player.spend_max_plating(1)
	Juice.add_trauma(0.25)
	if roll < 0.0:
		roll = randf()
	if roll < 0.6:
		Sfx.play("fusion", 2.0, -4.0)
		var opts := game.inventory.offer(3, rare)
		var offer := Picker.items(opts, game.inventory, "THE COIN LANDS EMBER-SIDE", _complete_coin)
		offer.subtitle = "Choose a Rare"
		game.picker.open(offer)
	else:
		Sfx.play("player_hit")
		game.hud.damage_flash()
		game.hud.banner("THE COIN LANDS ASH-SIDE", "You lost 1 max Plating pip")


func _complete_crucible(id: String) -> void:
	if id != "":
		feed_crucible(id)


func _complete_coin(id: String) -> void:
	if id != "":
		game.inventory.add(id)


func _vault_choice(chosen: Pedestal, kinds: Array[String]) -> void:
	for p in pedestals:
		if kinds.has(p.kind):
			p.active = false
	Sfx.play("vent", 6.0, -6.0)
	game.fx.ring(chosen.global_position, 2.0 * C.TILE, chosen.color, 0.4)


func use_anvil(choice: String) -> void:
	var anvil: Pedestal = null
	for p in pedestals:
		if p.kind == "anvil":
			anvil = p
	var parts := choice.split(":")
	if parts.size() != 2:
		return
	if parts[0] == "temper" and game.cores >= ItemDB.TEMPER_COST and game.inventory.temperable().has(parts[1]):
		game.spend_cores(ItemDB.TEMPER_COST)
		game.inventory.temper(parts[1])
		game.hud.banner("TEMPERED: " + ItemDB.ITEMS[parts[1]].name.to_upper(), ItemDB.TEMPER[parts[1]])
	elif parts[0] == "forge" and game.cores >= ItemDB.FORGE_COST and game.inventory.forgeable().has(parts[1]):
		game.spend_cores(ItemDB.FORGE_COST)
		game.inventory.force_fusion(parts[1])
	else:
		return
	Sfx.play("slam", 6.0, -6.0)
	Sfx.play("fusion", 7.0, -8.0)
	Juice.add_trauma(0.25)
	if anvil != null:
		game.fx.sparks(anvil.global_position + Vector2(0, -12), Vector2.UP, 16, Color(1, 0.8, 0.4))
		# Using the Anvil sends the Bath cold; the Anvil stays hot while you have Cores to spend.
		for p in pedestals:
			if p.kind == "vault_repair":
				p.active = false


func _buy_fx(p: Pedestal) -> void:
	Sfx.play("clear", 7.0, -6.0)
	game.fx.ring(p.global_position, 1.2 * C.TILE, p.color, 0.3)


func _reroll_shop() -> void:
	var shown: Array[String] = []
	for p in pedestals:
		if p.kind == "item" and p.active:
			shown.append(p.item_id)
	for p in pedestals.duplicate():
		if p.kind != "item" or not p.active:
			continue
		var want_conductor: bool = p.item_id != "patch_kit" and ItemDB.ITEMS[p.item_id].keyword == "conductor"
		var f := func(id: String) -> bool: return (ItemDB.ITEMS[id].keyword == "conductor") == want_conductor
		var pick: Array[String] = game.inventory.offer(1, f, shown)
		if pick.is_empty():
			continue # nothing new of this kind left: keep what is on show
		shown.append(pick[0])
		var pos: Vector2 = p.position
		pedestals.erase(p)
		p.queue_free()
		_item_pedestal(pick[0], pos)


## Crucible odds (GDD section 6): 50% upgrade a rarity, 35% transmute within the keyword, 15% Slagged.
## Each roll only ever produces its own outcome; if that outcome has nothing left to give,
## the Crucible refuses and you keep the item.
func feed_crucible(id: String, roll := randf()) -> void:
	var fed: Dictionary = ItemDB.ITEMS[id]
	var rank: int = ItemDB.RARITY_RANK[fed.rarity]
	var outcome := "UPGRADED" if roll < 0.5 else ("TRANSMUTED" if roll < 0.85 else "SLAGGED")
	var skip: Array[String] = [id]
	var picks: Array[String] = []
	match outcome:
		"UPGRADED":
			# Prefer the same keyword; any higher rarity still counts as an upgrade.
			var same_higher := func(o: String) -> bool: return ItemDB.ITEMS[o].keyword == fed.keyword and ItemDB.RARITY_RANK[ItemDB.ITEMS[o].rarity] > rank
			var higher := func(o: String) -> bool: return ItemDB.RARITY_RANK[ItemDB.ITEMS[o].rarity] > rank
			picks = game.inventory.offer(1, same_higher, skip)
			if picks.is_empty():
				picks = game.inventory.offer(1, higher, skip)
		"TRANSMUTED":
			var same_kw := func(o: String) -> bool: return ItemDB.ITEMS[o].keyword == fed.keyword
			picks = game.inventory.offer(1, same_kw, skip)
		"SLAGGED":
			for o: String in ItemDB.ITEMS:
				if ItemDB.is_slagged(o) and not game.inventory.owned.has(o):
					picks.append(o)
			picks.shuffle()
	for p in pedestals:
		if p.kind == "crucible":
			p.active = false
	if picks.is_empty():
		game.hud.banner("THE CRUCIBLE REFUSES", "It rolled %s but had nothing to give. You keep %s." % [outcome.to_lower(), fed.name])
		Sfx.play("player_hit", 4.0, -8.0)
		return
	var result: String = picks[0]
	game.inventory.remove(id)
	game.inventory.add(result)
	var into: Dictionary = ItemDB.ITEMS[result]
	game.hud.banner("%s: %s" % [outcome, into.name.to_upper()], "%s went into the fire" % fed.name)
	Sfx.play("fusion" if outcome != "SLAGGED" else "overheat", 0.0, -2.0)
	Juice.add_trauma(0.3)
	game.fx.ring(game.player.global_position, 3.0 * C.TILE, ItemDB.keyword_color(into.keyword), 0.4)


