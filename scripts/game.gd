class_name RunGame
extends Node2D
## Root of a run: owns the room, player, camera, FX, HUD, director and the Stratum route.
## Rooms are rebuilt in place when you walk through a door (GDD section 6).

const TRANSITION_TIME := 0.25
const REWARD_DELAY := 1.2
const CLEAR_SCRAP := Vector2i(8, 15)
const CACHE_BONUS := 25
const DROP_CHANCE := 0.25
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
var effects: CombatEffects
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

var _transition := 0.0 # counts down while the screen is dark between rooms
var _next_kind := ""
var _reward_timer := 0.0
var special_rooms: SpecialRooms


func _ready() -> void:
	special_rooms = SpecialRooms.new(self)
	_setup_input()
	Juice.reset()
	get_tree().paused = false
	inventory = Inventory.new()
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
	player.inventory = inventory
	inventory.player = player
	effects = CombatEffects.new()
	effects.inventory = inventory
	effects.player = player
	effects.fx = fx
	effects.projectile_parent = world
	add_child(effects)
	player.effects = effects
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
	player.damaged.connect(_on_player_damaged)
	player.died.connect(on_player_died)
	player.vented.connect(hud.chromatic)
	player.gauge_pulsed.connect(hud.pulse_gauge)
	effects.flares_detonated.connect(func() -> void: hud.dim(0.15))
	director = Director.new()
	director.game = self
	director.player = player
	director.fx = fx
	director.spawn_parent = world
	director.enemy_defeated.connect(_on_enemy_defeated)
	director.armour_broken.connect(_on_armour_broken)
	director.room_cleared.connect(on_room_cleared)
	add_child(director)
	picker = Picker.new()
	add_child(picker)
	pause_menu = PauseMenu.new()
	pause_menu.game = self
	add_child(pause_menu)
	touch = TouchControls.new()
	touch.game = self
	touch.aim_changed.connect(player.set_aim_input)
	picker.opened.connect(touch.suspend)
	pause_menu.opened.connect(touch.suspend)
	add_child(touch)
	run = RunMap.new(randi())
	_build_room("combat_item")


func in_transition() -> bool:
	return _transition > 0.0


func _on_player_damaged(source: String, band_name: String) -> void:
	took_damage_this_room = true
	last_hit_source = source
	last_hit_band = band_name
	hud.damage_flash()


## The pause menu opens mid-run, never over the reward cards or the Death Ledger.
func can_pause() -> bool:
	return not dead and not victory and not picker.is_open


# ---------------------------------------------------------------- rooms

func take_door(door: Door) -> void:
	if dead or in_transition() or not door.open:
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
	special_rooms.pedestals.clear()
	room_kind = kind
	run.enter(kind)
	took_damage_this_room = false
	room = Room.new(_pick_layout(kind))
	director.room = room
	room.accent = RunMap.KINDS[kind].color if not RunMap.is_combat(kind) or kind == "elite" else Color(0.9, 0.4, 0.1)
	world.add_child(room)
	world.move_child(room, 0)
	player.position = room.entry_point()
	player.velocity = Vector2.ZERO
	player.invuln = maxf(player.invuln, 0.5)
	for i in run.exits.size():
		var d := Door.new()
		d.player = player
		d.kind = run.exits[i]
		d.position = room.door_point(_door_slot(i, run.exits.size()))
		d.traversal_requested.connect(take_door)
		world.add_child(d)
		doors.append(d)
	var info: Dictionary = RunMap.KINDS[kind]
	var label := "ROOM %d / %d" % [run.index, RunMap.GATE] if kind != "gate" else "THE GATE"
	hud.banner(info.name, label)
	if RunMap.is_combat(kind):
		director.start_room(run.index, kind if kind == "gate" or kind == "elite" else "combat")
	else:
		special_rooms.setup(kind)
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
	if dead or victory:
		if Input.is_action_just_pressed("restart"):
			Juice.reset()
			var err := get_tree().reload_current_scene()
			if err != OK:
				push_error("RunGame: failed to reload current scene (Error %d)" % err)
		elif Input.is_action_just_pressed("pause"):
			pause_menu.to_menu()
		return
	run_time += delta
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
		for p in special_rooms.pedestals:
			if p.near:
				use_pedestal(p)
				break


func _on_enemy_defeated(e: Enemy) -> void:
	effects.on_kill(e)
	on_enemy_killed(e)
	if e.elite:
		on_elite_killed(e)


func on_enemy_killed(e: Enemy) -> void:
	kills += 1
	if randf() < DROP_CHANCE:
		_spawn_scrap.call_deferred(randi_range(1, 2), e.global_position)


func _spawn_scrap(value: int, pos: Vector2) -> void:
	var pickup := ScrapBit.new()
	pickup.game = self
	pickup.value = value
	pickup.position = pos
	# Evaluate on insertion: the final kill may have cleared the room this frame.
	pickup.sweep = not director.active
	world.add_child(pickup)


func _on_armour_broken() -> void:
	hud.banner("ARMOUR BROKEN", "The Forgewarden's front is open")


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
		inventory.run_active = false
		hud.banner("STRATUM CLEARED", "%.1f s" % time)
		Sfx.play("fusion", 3.0)
		return
	hud.banner("ROOM CLEAR", "%.1f s  ·  +%d scrap" % [time, gain])
	_reward_timer = REWARD_DELAY


func _give_reward() -> void:
	match room_kind:
		"combat_item":
			picker.open(Picker.items(inventory.offer(3), inventory, "CHOOSE A SALVAGE", _claim_reward))
		"combat_conductor":
			var opts := inventory.offer(3, ItemDB.is_conductor)
			if opts.is_empty():
				opts.append("patch_kit") # every Conductor is owned
			picker.open(Picker.items(opts, inventory, "CHOOSE A CONDUCTOR", _claim_reward))
		"elite":
			var opts := _elite_offer()
			if opts.is_empty():
				add_scrap(40, true) # every Rare and Slagged item is owned
				_open_doors()
				return
			var offer := Picker.items(opts, inventory, "ELITE SALVAGE", _claim_reward)
			offer.subtitle = "Rare or better · Slagged items carry a drawback until absolved"
			picker.open(offer)
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


func spend_scrap(amount: int) -> void:
	scrap -= amount


func spend_cores(amount: int) -> void:
	cores -= amount


# ---------------------------------------------------------------- picker

func _claim_reward(id: String) -> void:
	if id != "":
		inventory.add(id)
	_open_doors()


# ---------------------------------------------------------------- non-combat rooms

func use_pedestal(p: Pedestal) -> void:
	special_rooms.use_pedestal(p)


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
	inventory.run_active = false
	Juice.reset()
	Juice.add_trauma(0.5)


func ledger_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("Killed by %s" % last_hit_source)
	lines.append("Heat band at death: %s" % last_hit_band)
	if last_hit_band == "OVERHEAT":
		lines.append("Risk taken: overheated, so every hit cost +1 pip")
	for r in inventory.active_risks():
		lines.append("Risk taken: " + r)
	lines.append("Room %d of %d (%s)  ·  %d kills  ·  %d:%02d" % [run.index, RunMap.GATE, RunMap.KINDS[room_kind].name.capitalize(), kills, int(run_time) / 60, int(run_time) % 60])
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
