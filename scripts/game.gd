extends Node2D
## Root of a run: owns the room, player, camera, FX, HUD, director and the Stratum route.
## Rooms are rebuilt in place when you walk through a door (GDD section 6).

const TRANSITION_TIME := 0.25
const REWARD_DELAY := 1.2
const CLEAR_SCRAP := Vector2i(8, 15)
const CACHE_BONUS := 25
const DROP_CHANCE := 0.25
const REPAIR_PRICE := 40
const REROLL_PRICE := 15
const REROLL_STEP := 10
const ALTAR_CHANCE := 1.0 / 3.0 # Altars sit in 1 of every 3 Cooling Vaults (GDD section 4)
const SLAGGED_SLOT := 0.2 # elite rewards: chance per card to be a Slagged item
const TEMPLATE_CHANCE := 0.25 # combat rooms: chance of a hand-authored layout instead of a generated one
const ELITE_DENSITY := 0.7 # generated Elite rooms get less cover so the Forgewarden can turn

var world: Node2D
var room: Room
var fx: Fx
var player: Player
var camera: Camera2D
var hud: Hud
var director: Director
var inventory: Inventory
var picker: Picker
var pause_menu: PauseMenu
var touch: TouchControls
var run: RunMap

var dead := false
var victory := false
var kills := 0
var run_time := 0.0
var last_hit_source := ""
var last_hit_band := ""
var rooms_cleared := 0
var scrap := 0
var cores := 0
var elites_killed := 0
var room_kind := ""
var took_damage_this_room := false
var doors: Array[Door] = []
var pedestals: Array[Pedestal] = []

var _transition := 0.0 # counts down while the screen is dark between rooms
var _next_kind := ""
var _reward_timer := 0.0
var _picker_context := ""
var _reroll_price := REROLL_PRICE


func _ready() -> void:
	_setup_input()
	Juice.reset()
	get_tree().paused = false
	inventory = Inventory.new()
	inventory.game = self
	add_child(inventory)
	inventory.fusion_unlocked.connect(_on_fusion)
	inventory.absolved.connect(_on_absolved)
	world = Node2D.new()
	add_child(world)
	add_child(Ambience.new())
	fx = Fx.new()
	fx.z_index = 6
	world.add_child(fx)
	player = Player.new()
	player.game = self
	world.add_child(player)
	camera = Camera2D.new()
	camera.ignore_rotation = false
	camera.position = Vector2(C.ROOM_W, C.ROOM_H) * C.TILE * 0.5 + Vector2(0, 10)
	add_child(camera)
	camera.make_current()
	Juice.camera = camera
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	director = Director.new()
	director.game = self
	add_child(director)
	picker = Picker.new()
	picker.game = self
	add_child(picker)
	picker.chosen.connect(_on_picked)
	pause_menu = PauseMenu.new()
	pause_menu.game = self
	add_child(pause_menu)
	touch = TouchControls.new()
	touch.game = self
	add_child(touch)
	run = RunMap.new(randi())
	_build_room("combat_item")


func in_transition() -> bool:
	return _transition > 0.0


## The pause menu opens mid-run, never over the reward cards or the Death Ledger.
func can_pause() -> bool:
	return not dead and not victory and not picker.is_open


# ---------------------------------------------------------------- rooms

func take_door(door: Door) -> void:
	if in_transition() or not door.open:
		return
	_next_kind = door.kind
	_transition = TRANSITION_TIME
	hud.fade(TRANSITION_TIME)
	Sfx.play("portal", 4.0, -6.0)


func _build_room(kind: String) -> void:
	# Bank any Scrap still flying toward the player so leaving early never loses it.
	for b in get_tree().get_nodes_in_group("scrap"):
		if not b.is_queued_for_deletion():
			add_scrap(b.value, false)
			b.remove_from_group("scrap")
	for c in world.get_children():
		if c != player and c != fx:
			c.queue_free()
	fx.clear()
	doors.clear()
	pedestals.clear()
	room_kind = kind
	run.enter(kind)
	took_damage_this_room = false
	room = Room.new(_pick_layout(kind))
	room.accent = RunMap.KINDS[kind].color if not RunMap.is_combat(kind) or kind == "elite" else Color(0.9, 0.4, 0.1)
	world.add_child(room)
	world.move_child(room, 0)
	player.position = room.entry_point()
	player.velocity = Vector2.ZERO
	player.invuln = maxf(player.invuln, 0.5)
	for i in run.exits.size():
		var d := Door.new()
		d.game = self
		d.kind = run.exits[i]
		d.slot = _door_slot(i, run.exits.size())
		world.add_child(d)
		doors.append(d)
	var info: Dictionary = RunMap.KINDS[kind]
	var label := "ROOM %d / %d" % [run.index, RunMap.GATE] if kind != "gate" else "THE GATE"
	label += "  ·  " + Difficulty.level_name()
	hud.banner(info.name, label)
	if RunMap.is_combat(kind):
		director.start_room(run.index, kind if kind == "gate" or kind == "elite" else "combat")
	else:
		_setup_special(kind)
		_open_doors()


func _pick_layout(kind: String) -> Array:
	if not RunMap.is_combat(kind):
		return Layouts.HALL
	if kind == "gate" or run.index == 1:
		return Layouts.COMBAT[0]
	if randf() >= TEMPLATE_CHANCE:
		var rng := RandomNumberGenerator.new()
		rng.seed = randi()
		return RoomGen.generate(rng, ELITE_DENSITY if kind == "elite" else 1.0)
	for attempt in 8:
		var lines := Layouts.variant(Layouts.COMBAT.pick_random(), randf() < 0.5, randf() < 0.5)
		var probe := Room.new(lines)
		var ok := probe.is_valid()
		probe.free()
		if ok:
			return lines
	return Layouts.COMBAT[0]


func _door_slot(i: int, count: int) -> int:
	if count == 1:
		return 1
	if count == 2:
		return [0, 2][i]
	return i


func _open_doors() -> void:
	for d in doors:
		d.open = true
	if not doors.is_empty():
		Sfx.play("band", 5.0, -8.0)


func _process(delta: float) -> void:
	if not dead and not victory:
		run_time += delta
	elif Input.is_action_just_pressed("restart"):
		Juice.reset()
		get_tree().reload_current_scene()
		return
	elif Input.is_action_just_pressed("pause") and not Input.is_action_just_pressed("restart"):
		pause_menu.to_menu()
		return
	if _transition > 0.0:
		_transition -= delta
		if _transition <= 0.0:
			_build_room(_next_kind)
		return
	if _reward_timer > 0.0:
		_reward_timer -= delta
		if _reward_timer <= 0.0:
			_give_reward()
	if not dead and player.interact_pressed():
		for p in pedestals:
			if p.near:
				use_pedestal(p)
				break


func on_enemy_killed(e: Enemy) -> void:
	kills += 1
	if randf() < DROP_CHANCE:
		var b := ScrapBit.new()
		b.game = self
		b.value = randi_range(1, 2)
		b.position = e.global_position
		world.add_child.call_deferred(b)


## Elites drop 1 Core (GDD section 9): the only steady Core source.
func on_elite_killed(e: Enemy) -> void:
	elites_killed += 1
	cores += 1
	fx.number(e.global_position + Vector2(0, -40), 1, false, Color(0.55, 0.95, 1.0), 26)
	fx.ring(e.global_position, 1.5 * C.TILE, Color(0.55, 0.95, 1.0), 0.5)
	hud.banner("+1 CORE", "Spend Cores at the Anvil in a Cooling Vault")
	Sfx.play("core", 0.0, -2.0)


func on_room_cleared(time: float) -> void:
	rooms_cleared += 1
	inventory.on_room_clear(not took_damage_this_room)
	for b in get_tree().get_nodes_in_group("scrap"):
		b.sweep = true
	var gain := randi_range(CLEAR_SCRAP.x, CLEAR_SCRAP.y)
	if room_kind == "combat_scrap":
		gain += CACHE_BONUS
	add_scrap(gain, true)
	Sfx.play("clear")
	if room_kind == "gate":
		victory = true
		hud.banner("STRATUM CLEARED", "%.1f s" % time)
		Sfx.play("fusion", 3.0)
		return
	hud.banner("ROOM CLEAR", "%.1f s  ·  +%d scrap" % [time, gain])
	_reward_timer = REWARD_DELAY


func _give_reward() -> void:
	match room_kind:
		"combat_item":
			_open_picker("reward", inventory.offer(3), "CHOOSE A SALVAGE")
		"combat_conductor":
			var conductors := func(id: String) -> bool: return ItemDB.ITEMS[id].keyword == "conductor"
			var opts := inventory.offer(3, conductors)
			if opts.is_empty():
				opts.append("patch_kit") # every Conductor is owned
			_open_picker("reward", opts, "CHOOSE A CONDUCTOR")
		"elite":
			var opts := _elite_offer()
			if opts.is_empty():
				add_scrap(40, true) # every Rare and Slagged item is owned
				_open_doors()
				return
			_open_picker("reward", opts, "ELITE SALVAGE", "Rare or better · Slagged items carry a drawback until absolved")
		_:
			_open_doors()


## Elite reward: 3 cards at Rare or better. Each card has a 20% chance to be a Slagged item;
## when the Rares run out, Slagged items fill the remaining cards.
func _elite_offer() -> Array[String]:
	var rares: Array[String] = inventory.offer(3, func(id: String) -> bool: return ItemDB.ITEMS[id].rarity == "Rare")
	var slag: Array[String] = []
	for id: String in ItemDB.ITEMS:
		if ItemDB.is_slagged(id) and not inventory.owned.has(id):
			slag.append(id)
	slag.shuffle()
	var out: Array[String] = []
	for i in 3:
		if not slag.is_empty() and (rares.is_empty() or randf() < SLAGGED_SLOT):
			out.append(slag.pop_back())
		elif not rares.is_empty():
			out.append(rares.pop_front())
	return out


func add_scrap(amount: int, show: bool) -> void:
	scrap += amount
	if show:
		fx.number(player.global_position + Vector2(0, -30), amount, false, Color(1, 0.85, 0.35), 16)


# ---------------------------------------------------------------- picker

func _open_picker(context: String, opts: Array[String], title: String, sub := "", cancellable := false) -> void:
	_picker_context = context
	picker.open(opts, title, sub, cancellable)


func _on_picked(id: String) -> void:
	match _picker_context:
		"reward":
			if id != "":
				inventory.add(id)
			_open_doors()
		"crucible":
			if id == "":
				return
			_feed_crucible(id)
		"coinflip":
			if id != "":
				inventory.add(id)
		"anvil":
			if id != "":
				_use_anvil(id)


# ---------------------------------------------------------------- non-combat rooms

func _setup_special(kind: String) -> void:
	var t := C.TILE
	match kind:
		"shop":
			var stock: Array[String] = []
			var conductors := func(id: String) -> bool: return ItemDB.ITEMS[id].keyword == "conductor"
			stock.append_array(inventory.offer(1, conductors))
			var others := func(id: String) -> bool: return ItemDB.ITEMS[id].keyword != "conductor"
			stock.append_array(inventory.offer(3, others, stock))
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
			if randf() < ALTAR_CHANCE and not inventory.stoked:
				_pedestal("altar", Vector2(16 * t, 6.5 * t), "Stoke Altar", ["Heat cap rises to 120: 20 more Heat of Overdrive.", "!Costs 1 max Plating pip. Overheat lasts 1 s longer."], Color(1.0, 0.45, 0.2))
		"wager":
			_pedestal("crucible", Vector2(9 * t, 6.5 * t), "The Crucible", ["Feed in one owned item:", "50%: it upgrades to a higher rarity", "35%: it transmutes to a same-keyword item", "!15%: it becomes Slagged"], Color(0.8, 0.45, 1.0))
			_pedestal("coinflip", Vector2(15 * t, 6.5 * t), "Ember Coin", ["Stake 1 max Plating pip on a 60% flip.", "Win: choose a Rare item you don't own.", "!Lose: the pip is gone."], Color(1.0, 0.55, 0.25))


func _pedestal(kind: String, pos: Vector2, title: String, lines: Array[String], color: Color) -> Pedestal:
	var p := Pedestal.new()
	p.game = self
	p.kind = kind
	p.position = pos
	p.title = title
	p.lines = lines
	p.color = color
	world.add_child(p)
	pedestals.append(p)
	return p


func _item_pedestal(id: String, pos: Vector2) -> Pedestal:
	var item: Dictionary = ItemDB.get_item(id)
	var tag := "%s · %s" % [item.keyword.to_upper(), item.rarity]
	var p := _pedestal("item", pos, item.name, [tag, item.desc], ItemDB.keyword_color(item.keyword))
	p.item_id = id
	p.price = ItemDB.price(id) if id != "patch_kit" else REPAIR_PRICE
	return p


func use_pedestal(p: Pedestal) -> void:
	if not p.active:
		return
	if p.price > 0 and scrap < p.price:
		Sfx.play("player_hit", 6.0, -12.0)
		return
	match p.kind:
		"item":
			scrap -= p.price
			inventory.add(p.item_id)
			p.active = false
			_buy_fx(p)
		"repair":
			if player.pips >= player.max_pips:
				hud.banner("PLATING IS FULL")
				return
			scrap -= p.price
			player.pips += 1
			_buy_fx(p)
		"reroll":
			if not pedestals.any(func(q: Pedestal) -> bool: return q.kind == "item" and q.active and q.item_id != "patch_kit"):
				hud.banner("NOTHING TO REROLL")
				return
			scrap -= p.price
			_reroll_price += REROLL_STEP
			p.price = _reroll_price
			_reroll_shop()
			_buy_fx(p)
		"vault_repair":
			player.pips = mini(player.pips + 2, player.max_pips)
			_vault_choice(p, ["vault_repair", "anvil"])
		"anvil":
			var opts: Array[String] = []
			if cores >= ItemDB.TEMPER_COST:
				for id in inventory.temperable():
					opts.append("temper:" + id)
			if cores >= ItemDB.FORGE_COST:
				for f in inventory.forgeable():
					opts.append("forge:" + f)
			if opts.is_empty():
				if cores < ItemDB.TEMPER_COST:
					hud.banner("THE ANVIL NEEDS A CORE", "Elites drop Cores")
				else:
					hud.banner("NOTHING TO TEMPER", "Own an untempered item first")
				Sfx.play("player_hit", 6.0, -12.0)
				return
			_open_picker("anvil", opts, "THE ANVIL", "%d Core%s  ·  Temper 1  ·  Forced Fusion 3" % [cores, "" if cores == 1 else "s"], true)
		"altar":
			if inventory.stoked:
				hud.banner("ALREADY STOKED", "The Altar has nothing more to give")
				return
			if player.max_pips <= 1:
				hud.banner("NOT ENOUGH PLATING")
				return
			player.max_pips -= 1
			player.pips = mini(player.pips, player.max_pips)
			player.heat.cap = 120.0
			inventory.stoked = true
			hud.banner("STOKED", "Heat cap 120 · Overheat lasts 1 s longer")
			_vault_choice(p, ["altar"])
		"crucible":
			var feedable: Array[String] = []
			for id in inventory.owned:
				if not ItemDB.is_slagged(id):
					feedable.append(id)
			if feedable.is_empty():
				hud.banner("NOTHING TO FEED", "Own an item first")
				return
			_open_picker("crucible", feedable, "FEED THE CRUCIBLE", "50% upgrade  ·  35% transmute  ·  15% Slagged", true)
		"coinflip":
			if player.max_pips <= 1:
				hud.banner("NOT ENOUGH PLATING")
				return
			var rare := func(id: String) -> bool: return ItemDB.ITEMS[id].rarity == "Rare"
			if inventory.offer(1, rare).is_empty():
				hud.banner("THE COIN WON'T FLIP", "You already own every Rare")
				return
			p.active = false
			player.max_pips -= 1
			player.pips = mini(player.pips, player.max_pips)
			Juice.add_trauma(0.25)
			if randf() < 0.6:
				Sfx.play("fusion", 2.0, -4.0)
				var opts := inventory.offer(3, rare)
				_open_picker("coinflip", opts, "THE COIN LANDS EMBER-SIDE", "Choose a Rare")
			else:
				Sfx.play("player_hit")
				hud.damage_flash()
				hud.banner("THE COIN LANDS ASH-SIDE", "You lost 1 max Plating pip")


func _vault_choice(chosen: Pedestal, kinds: Array) -> void:
	for p in pedestals:
		if kinds.has(p.kind):
			p.active = false
	Sfx.play("vent", 6.0, -6.0)
	fx.ring(chosen.global_position, 2.0 * C.TILE, chosen.color, 0.4)


func _use_anvil(choice: String) -> void:
	var anvil: Pedestal = null
	for p in pedestals:
		if p.kind == "anvil":
			anvil = p
	var parts := choice.split(":")
	if parts[0] == "temper" and cores >= ItemDB.TEMPER_COST:
		cores -= ItemDB.TEMPER_COST
		inventory.temper(parts[1])
		hud.banner("TEMPERED: " + ItemDB.ITEMS[parts[1]].name.to_upper(), ItemDB.TEMPER[parts[1]])
	elif parts[0] == "forge" and cores >= ItemDB.FORGE_COST:
		cores -= ItemDB.FORGE_COST
		inventory.force_fusion(parts[1])
	else:
		return
	Sfx.play("slam", 6.0, -6.0)
	Sfx.play("fusion", 7.0, -8.0)
	Juice.add_trauma(0.25)
	if anvil != null:
		fx.sparks(anvil.global_position + Vector2(0, -12), Vector2.UP, 16, Color(1, 0.8, 0.4))
		# Using the Anvil sends the Bath cold; the Anvil stays hot while you have Cores to spend.
		for p in pedestals:
			if p.kind == "vault_repair":
				p.active = false


func _buy_fx(p: Pedestal) -> void:
	Sfx.play("clear", 7.0, -6.0)
	fx.ring(p.global_position, 1.2 * C.TILE, p.color, 0.3)


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
		var pick: Array[String] = inventory.offer(1, f, shown)
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
func _feed_crucible(id: String) -> void:
	var fed: Dictionary = ItemDB.ITEMS[id]
	var rank: int = ItemDB.RARITY_RANK[fed.rarity]
	var roll := randf()
	var outcome := "UPGRADED" if roll < 0.5 else ("TRANSMUTED" if roll < 0.85 else "SLAGGED")
	var skip: Array[String] = [id]
	var picks: Array[String] = []
	match outcome:
		"UPGRADED":
			# Prefer the same keyword; any higher rarity still counts as an upgrade.
			var same_higher := func(o: String) -> bool: return ItemDB.ITEMS[o].keyword == fed.keyword and ItemDB.RARITY_RANK[ItemDB.ITEMS[o].rarity] > rank
			var higher := func(o: String) -> bool: return ItemDB.RARITY_RANK[ItemDB.ITEMS[o].rarity] > rank
			picks = inventory.offer(1, same_higher, skip)
			if picks.is_empty():
				picks = inventory.offer(1, higher, skip)
		"TRANSMUTED":
			var same_kw := func(o: String) -> bool: return ItemDB.ITEMS[o].keyword == fed.keyword
			picks = inventory.offer(1, same_kw, skip)
		"SLAGGED":
			for o: String in ItemDB.ITEMS:
				if ItemDB.is_slagged(o) and not inventory.owned.has(o):
					picks.append(o)
			picks.shuffle()
	for p in pedestals:
		if p.kind == "crucible":
			p.active = false
	if picks.is_empty():
		hud.banner("THE CRUCIBLE REFUSES", "It rolled %s but had nothing to give. You keep %s." % [outcome.to_lower(), fed.name])
		Sfx.play("player_hit", 4.0, -8.0)
		return
	var result: String = picks[0]
	inventory.remove(id)
	inventory.add(result)
	var into: Dictionary = ItemDB.ITEMS[result]
	hud.banner("%s: %s" % [outcome, into.name.to_upper()], "%s went into the fire" % fed.name)
	Sfx.play("fusion" if outcome != "SLAGGED" else "overheat", 0.0, -2.0)
	Juice.add_trauma(0.3)
	fx.ring(player.global_position, 3.0 * C.TILE, ItemDB.keyword_color(into.keyword), 0.4)


# ---------------------------------------------------------------- events

func _on_fusion(id: String) -> void:
	var f: Dictionary = ItemDB.FUSIONS[id]
	hud.banner("FUSION: " + f.name.to_upper(), f.desc)
	Sfx.play("fusion")
	Juice.add_trauma(0.3)


func _on_absolved(id: String) -> void:
	hud.banner("ABSOLVED: " + ItemDB.ITEMS[id].name.to_upper(), "The drawback is gone; the power stays")
	Sfx.play("fusion", 5.0)


func on_player_died() -> void:
	dead = true
	Juice.reset()
	Juice.add_trauma(0.5)


func ledger_lines() -> Array:
	var lines := []
	lines.append("Killed by %s" % last_hit_source)
	lines.append("Heat band at death: %s" % last_hit_band)
	if last_hit_band == "OVERHEAT":
		lines.append("Risk taken: overheated, so every hit cost +1 pip")
	for r in inventory.active_risks():
		lines.append("Risk taken: " + r)
	lines.append("Room %d of %d (%s)  ·  %s  ·  %d kills  ·  %d:%02d" % [run.index, RunMap.GATE, RunMap.KINDS[room_kind].name.capitalize(), Difficulty.level_name(), kills, int(run_time) / 60, int(run_time) % 60])
	lines.append("Overheats this run: %d  ·  Vents: %d  ·  Scrap: %d" % [player.heat.overheat_count, player.vents, scrap])
	return lines


func _setup_input() -> void:
	_key_action("move_left", [KEY_A, KEY_LEFT])
	_key_action("move_right", [KEY_D, KEY_RIGHT])
	_key_action("move_up", [KEY_W, KEY_UP])
	_key_action("move_down", [KEY_S, KEY_DOWN])
	_key_action("dash", [KEY_SPACE, KEY_SHIFT])
	_key_action("restart", [KEY_R])
	_key_action("pause", [KEY_ESCAPE, KEY_P])
	_key_action("fire", [])
	_key_action("vent", [KEY_Q])
	_mouse_action("fire", MOUSE_BUTTON_LEFT)
	_mouse_action("vent", MOUSE_BUTTON_RIGHT)
	_axis_action("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis_action("move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis_action("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_axis_action("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_axis_action("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_axis_action("vent", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_button_action("dash", JOY_BUTTON_LEFT_SHOULDER)
	_button_action("restart", JOY_BUTTON_START)
	_button_action("pause", JOY_BUTTON_START)
	_key_action("interact", [KEY_E, KEY_F])
	_button_action("interact", JOY_BUTTON_A)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)


## Each binding is added on its own, so a reload or a partly predefined InputMap never duplicates or skips one.
func _bind(action: String, ev: InputEvent) -> void:
	_ensure(action)
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


func _key_action(action: String, keys: Array) -> void:
	for k: Key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		_bind(action, ev)


func _mouse_action(action: String, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	_bind(action, ev)


func _axis_action(action: String, axis: JoyAxis, dir: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = dir
	_bind(action, ev)


func _button_action(action: String, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	_bind(action, ev)
