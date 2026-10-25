extends Node

const DirectorScript = preload("res://scripts/combat/director.gd")
const EnemyScript = preload("res://scripts/combat/enemies/enemy.gd")
const ClinkerScript = preload("res://scripts/combat/enemies/clinker.gd")
const ForgewardenScript = preload("res://scripts/combat/enemies/forgewarden.gd")
const LinesmanScript = preload("res://scripts/combat/enemies/linesman.gd")
const PlayerScript = preload("res://scripts/combat/player.gd")
const RivetScript = preload("res://scripts/combat/projectiles/rivet.gd")
const ShardScript = preload("res://scripts/combat/projectiles/shard.gd")
const MoltenPatchScript = preload("res://scripts/combat/projectiles/molten_patch.gd")
const ItemDBScript = preload("res://scripts/item_db.gd")
const JuiceScript = preload("res://scripts/presentation/juice.gd")
const LightsScript = preload("res://scripts/presentation/lights.gd")
const SfxScript = preload("res://scripts/presentation/sfx.gd")
const FxScript = preload("res://scripts/presentation/fx.gd")
const MainMenuScript = preload("res://scripts/ui/main_menu.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
const PickerScript = preload("res://scripts/ui/picker.gd")
const SettingsPanelScript = preload("res://scripts/ui/settings_panel.gd")
const CodexPanelScript = preload("res://scripts/ui/codex_panel.gd")
const HudScript = preload("res://scripts/ui/hud.gd")
const TouchControlsScript = preload("res://scripts/ui/touch_controls.gd")
const DoorScript = preload("res://scripts/world/door.gd")
const LayoutsScript = preload("res://scripts/world/layouts.gd")
const PedestalScript = preload("res://scripts/world/pedestal.gd")
const ScrapBitScript = preload("res://scripts/world/scrap_bit.gd")
const SIMULATION_STEP := 1.0 / 60.0

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _ready() -> void:
	_data_contracts()
	_presentation_contracts()
	_juice_contracts()
	var hitstop_strength: float = Juice.hitstop_strength
	Juice.hitstop_strength = 0.0
	_settings_contracts()
	_fusion_contracts()
	await _transaction_contracts()
	await _combat_contracts()
	Juice.hitstop_strength = hitstop_strength
	Juice.reset()
	print("contracts test: %d failures" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)


func _data_contracts() -> void:
	check(ItemDBScript.price("patch_kit") == ItemDBScript.PRICE.conductor, "Patch Kit uses its conductor price")
	check(ItemDBScript.get_item("patch_kit").get("name") == "Patch Kit" and ItemDBScript.get_item("patch_kit").get("keyword") == "conductor", "Patch Kit resolves to its special item definition")
	check(ItemDBScript.keyword_color("unknown") == Color.WHITE, "Unknown item keywords use the neutral fallback color")
	var rows: Array[String] = ["abc", "def"]
	check(LayoutsScript.variant(rows, true, true) == ["fed", "cba"], "Layout variants mirror rows and row order independently")
	check(DirectorScript._cost(["forgewarden", "linesman", "clinker"]) == 17, "Director threat costs add elite, support, and fodder values")
	var director: Director = DirectorScript.new()
	director.room_index = 1
	director.budget = 10
	var first_room: Array = director._plan("combat")
	check(first_room.size() == 1 and DirectorScript._cost(first_room[0]) == director.budget, "First combat room spends its full threat budget in one wave")
	director.room_index = 3
	director.budget = 14
	var later_room: Array = director._plan("combat")
	var plans_valid := later_room.size() == 2
	for wave_units: Array in later_room:
		var fodder := wave_units.count("clinker")
		var support := wave_units.count("linesman")
		plans_valid = plans_valid and support <= 1 and float(fodder) / float(wave_units.size()) >= 0.4
	check(plans_valid, "Later combat plans preserve fodder share while limiting support units")
	director.free()


func _presentation_contracts() -> void:
	check(Sfx.streams.has("shot") and Sfx.streams.has("crit") and Sfx.streams["shot"] is AudioStreamWAV, "SFX builds synthesized streams for core combat events")
	var prior_lights := Settings.lights
	Settings.lights = true
	var lights: Lights = LightsScript.new()
	add_child(lights)
	lights.flash(Vector2(20.0, 30.0), Color.WHITE, 80.0, 1.5, 0.1)
	check(lights.active_count() == 1, "Lights activates a pooled flash when lighting is enabled")
	lights._process(0.2)
	check(lights.active_count() == 0, "Lights expires a flash when its lifetime elapses")
	lights.clear()
	lights.queue_free()
	Settings.lights = prior_lights


func _juice_contracts() -> void:
	Juice.reset()
	var before := Juice.total_hitstop_frames
	Juice.hitstop(8, true)
	var after_first := Juice.total_hitstop_frames
	Juice.hitstop(8, true)
	var after_second := Juice.total_hitstop_frames
	Juice.hitstop(2, true)
	check(after_first - before == 8, "Forced hit-stop starts when requested")
	check(after_second - after_first == 4 and Juice.total_hitstop_frames == after_second, "Forced hit-stop bypasses the gap but respects the shared twelve-frame budget")
	Juice.reset()


func _settings_contracts() -> void:
	var settings: Node = load("res://scripts/settings.gd").new()
	var config := ConfigFile.new()
	config.set_value("audio", "volume", "invalid")
	config.set_value("video", "shake", INF)
	config.set_value("video", "fullscreen", 1)
	settings.load_values(config)
	check(settings.volume == 0.8 and settings.shake == 1.0 and not settings.fullscreen, "Malformed settings retain defaults")
	config.set_value("audio", "volume", 5)
	config.set_value("video", "shake", -1)
	config.set_value("video", "fullscreen", true)
	settings.load_values(config)
	check(settings.volume == 1.0 and settings.shake == 0.0 and settings.fullscreen, "Valid settings clamp numeric ranges")
	settings.free()


func _fusion_contracts() -> void:
	var events: Array[String] = []
	var inventory := Inventory.new()
	inventory.fusion_unlocked.connect(func(id: String) -> void: events.append(id))
	inventory.add("tinder_rounds")
	inventory.add("frag_lattice")
	inventory.add("bellows_valve")
	inventory.force_fusion("firestorm_lattice")
	check(events.count("cluster_embers") == 1, "Natural ingredients unlock Cluster Embers once")
	check(events.count("firestorm_lattice") == 1 and events.count("heat_engine") == 1, "Forced stand-in immediately unlocks every completed recipe once")
	inventory.add("feedback_coil")
	check(events.count("firestorm_lattice") == 1 and events.count("heat_engine") == 1, "Later real ingredient does not duplicate forged fusion unlocks")
	inventory.free()

	events.clear()
	inventory = Inventory.new()
	inventory.fusion_unlocked.connect(func(id: String) -> void: events.append(id))
	inventory.add("bellows_valve")
	inventory.force_fusion("heat_engine")
	inventory.add("tinder_rounds")
	inventory.add("frag_lattice")
	check(events.count("heat_engine") == 1 and events.count("cluster_embers") == 1 and events.count("firestorm_lattice") == 1, "Later acquisitions complete recipes against the forced stand-in once")
	inventory.free()

	inventory = Inventory.new()
	inventory.add("bellows_valve")
	inventory.add("tinder_rounds")
	inventory.add("frag_lattice")
	inventory.force_fusion("heat_engine")
	check(inventory.has("heat_engine") and inventory.has("firestorm_lattice") and inventory.has("feedback_coil"), "Heat Engine's paid stand-in can complete Firestorm Lattice")
	inventory.remove("bellows_valve")
	check(not inventory.has("heat_engine") and not inventory.has("firestorm_lattice") and not inventory.has("feedback_coil"), "Removing a forced fusion prerequisite prunes downstream fusions and its stand-in")
	check(inventory.has("cluster_embers") and inventory.has("tinder_rounds") and inventory.has("frag_lattice"), "Fusion pruning preserves still-supported recipes and real ingredients")
	inventory.free()

	var query := Inventory.new()
	query.add("tinder_rounds")
	check(query.fusion_completed_by("frag_lattice") == "cluster_embers", "Fusion query returns the completed fusion identifier")
	query.free()


func _transaction_contracts() -> void:
	var game: RunGame = load("res://main.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	game.player.set_physics_process(false)
	game.director.set_physics_process(false)
	game.inventory.add("tinder_rounds")
	game.cores = 3
	game.special_rooms.use_anvil("forge:cluster_embers")
	check(game.cores == 0 and game.inventory.has("frag_lattice"), "Forced fusion spends exactly three cores")
	game.cores = 3
	game.special_rooms.use_anvil("forge:cluster_embers")
	check(game.cores == 3, "Duplicate fusion does not spend cores")
	game.special_rooms.use_anvil("temper:tinder_rounds")
	check(game.cores == 2 and game.inventory.is_tempered("tinder_rounds"), "Tempering spends one core")
	game.special_rooms.use_anvil("temper:tinder_rounds")
	game.special_rooms.use_anvil("invalid")
	check(game.cores == 2, "Invalid or repeated temper leaves cores intact")
	game.inventory.add("feedback_coil")
	check(game.inventory.has("firestorm_lattice"), "Forged ingredient completes natural fusion")
	game.inventory.remove("tinder_rounds")
	check(not game.inventory.has("cluster_embers") and not game.inventory.has("firestorm_lattice"), "Removing a real ingredient invalidates dependent fusions")
	var offers := game.inventory.offer(3, func(_id: String) -> bool: return false)
	check(offers.is_empty(), "Exhausted filtered offers stay empty")
	_rivet_construction_contracts(game)
	game.queue_free()
	await get_tree().process_frame


func _rivet_construction_contracts(game: RunGame) -> void:
	game.inventory.add("brittle_crown")
	game.player.bot = true
	game.player.bot_aim = Vector2.RIGHT
	game.player.bot_fire = true
	game.player.fire_cd = 0.0
	game.player.heat.set_value(Heat.HOT_AT)
	var bolts_before := game.world.get_children().filter(func(child: Node) -> bool: return child is Rivet).size()
	var shots_before := game.player.shots_fired
	var heat_before := game.player.heat.value
	game.player._physics_process(SIMULATION_STEP)
	var bolts: Array[Rivet] = []
	for child: Node in game.world.get_children():
		if child is Rivet and not child.is_queued_for_deletion():
			bolts.append(child as Rivet)
	bolts = bolts.slice(bolts_before)
	check(bolts.size() == 1 + game.inventory.extra_projectiles(), "One attack creates the primary Rivet and each Crown spread shot (found %d, expected %d)" % [bolts.size(), 1 + game.inventory.extra_projectiles()])
	check(game.player.shots_fired == shots_before + 1 and is_equal_approx(game.player.heat.value, heat_before + Player.HEAT_PER_SHOT), "Spread shots count as one attack and add heat once (shots %d -> %d, heat %.1f -> %.1f)" % [shots_before, game.player.shots_fired, heat_before, game.player.heat.value])
	if bolts.size() == 3:
		var primary := bolts[0]
		check(primary.get_script() == RivetScript, "Player attacks instantiate the directly tested Rivet script")
		check(primary.inventory == game.inventory and primary.fx == game.fx and primary.overdrive and primary.pierce == 1 and primary.ricochet == 1, "Primary Rivet inherits the hot inventory configuration")
		check(bolts[1].inventory == primary.inventory and bolts[1].fx == primary.fx and bolts[1].overdrive == primary.overdrive and bolts[1].pierce == primary.pierce and bolts[1].ricochet == primary.ricochet and is_equal_approx(bolts[1].speed_mult, primary.speed_mult), "Spread Rivets share primary projectile settings")
		check(bolts[2].inventory == primary.inventory and bolts[2].fx == primary.fx and bolts[2].overdrive == primary.overdrive and bolts[2].pierce == primary.pierce and bolts[2].ricochet == primary.ricochet and is_equal_approx(bolts[2].speed_mult, primary.speed_mult), "All spread Rivets share primary projectile settings")
		check(is_equal_approx(primary.dir.angle_to(bolts[1].dir), 0.12) and is_equal_approx(primary.dir.angle_to(bolts[2].dir), -0.12), "Spread Rivets keep their symmetric firing angles")


func _combat_contracts() -> void:
	var game: RunGame = load("res://main.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	game.player.set_physics_process(false)
	game.director.set_physics_process(false)
	var player := game.player
	check(player.get_script() == PlayerScript and game.fx.get_script() == FxScript and game.hud.get_script() == HudScript, "RunGame wires the tested Player, FX, and HUD scripts")
	check(game.touch.get_script() == TouchControlsScript and game.pause_menu.get_script() == PauseMenuScript and game.picker.get_script() == PickerScript, "RunGame wires the tested touch, pause, and picker scripts")
	check(Juice.get_script() == JuiceScript and Sfx.get_script() == SfxScript, "Autoload services use the directly tested Juice and SFX scripts")
	var heat_inventory := Inventory.new()
	heat_inventory.player = player
	heat_inventory.add("bellows_valve")
	heat_inventory.add("feedback_coil")
	var arc_kill := EnemyScript.new()
	arc_kill.last_kind = "arc"
	player.vent_cd = 2.0
	heat_inventory.on_kill(arc_kill)
	check(is_equal_approx(player.vent_cd, 1.5), "Heat Engine refunds vent cooldown for arc kills through the shared kill hook")
	heat_inventory.free()
	player.vent_cd = 0.0
	arc_kill.free()
	_dash_contracts(game)
	await _clinker_contracts(game)
	await _linesman_contracts(game)
	await _touch_controls_contracts(game)
	await _forgewarden_contracts(game)
	await _projectile_and_scrap_contracts(game)
	await _ui_contracts(game)
	await _world_interaction_contracts(game)
	_presentation_output_contracts(game)
	var target: Enemy = EnemyScript.new()
	target.game = game
	target.max_hp = 200.0
	target.position = player.position + Vector2(100.0, 0.0)
	target.set_physics_process(false)
	game.world.add_child(target)
	target.embed_rivet()
	target.embed_rivet()
	var vent_amounts: Array[float] = []
	player.vented.connect(func(amount: float) -> void: vent_amounts.append(amount))
	player.bot = true
	player.bot_aim = Vector2.RIGHT
	player.bot_vent = true
	player.heat.set_value(80.0)
	player._physics_process(SIMULATION_STEP)
	check(vent_amounts.size() == 1 and is_equal_approx(vent_amounts[0], 80.0), "Bot-triggered Vent reports its dumped Heat")
	check(is_equal_approx(target.hp, 127.2) and target.rivet_count() == 0, "Vent damages a nearby target, resolves its two-Rivet burst, and clears embedded Rivets")
	check(player.vents == 1 and player.vent_cd <= Player.VENT_COOLDOWN and player.vent_cd > Player.VENT_COOLDOWN - 0.1 and is_equal_approx(player.heat.value, 0.0), "Vent starts its cooldown and returns Heat to Cold")

	game.inventory.add("feedback_coil")
	game.inventory.add("bellows_valve")
	player.vent_cd = 3.0
	var survivor: Enemy = EnemyScript.new()
	survivor.game = game
	survivor.max_hp = 100.0
	survivor.position = player.position + Vector2(100.0, 0.0)
	survivor.set_physics_process(false)
	game.world.add_child(survivor)
	survivor.add_ignite(2, 10)
	game.inventory.on_vent(0.0)
	check(is_equal_approx(survivor.hp, 80.0) and survivor.ignite_stacks == 0, "Feedback Coil consumes Ignite and deals its deterministic arc damage")
	check(is_equal_approx(player.vent_cd, 3.0) and is_equal_approx(player.heat.value, 40.0), "Heat Engine sets Warm Heat but does not refund cooldown when an arc target survives")
	survivor.remove_from_group("enemies")
	survivor.queue_free()
	var doomed: Enemy = EnemyScript.new()
	doomed.game = game
	doomed.max_hp = 15.0
	doomed.position = player.position + Vector2(120.0, 0.0)
	doomed.set_physics_process(false)
	doomed.defeated.connect(game._on_enemy_defeated)
	game.world.add_child(doomed)
	doomed.add_ignite(1, 10)
	player.vent_cd = 3.0
	game.inventory.on_vent(0.0)
	check(doomed.dead and doomed.ignite_stacks == 0 and is_equal_approx(player.vent_cd, 2.5), "Feedback Coil consumes Ignite and Heat Engine refunds half a second only when an arc kills")

	var damage_sources: Array[String] = []
	var deaths := [0]
	player.damaged.connect(func(source: String, _band: String) -> void: damage_sources.append(source))
	player.died.connect(func() -> void: deaths[0] += 1)
	player.pips = 6
	player.invuln = 0.0
	player.heat.set_value(0.0)
	player.take_hit(1, "contract hit")
	check(player.pips == 5 and damage_sources == ["contract hit"] and player.is_invulnerable(), "Player damage emits its source and activates invulnerability")
	player.take_hit(1, "suppressed hit")
	check(player.pips == 5 and damage_sources.size() == 1, "Invulnerability suppresses repeat damage and its signal")
	player.pips = 1
	player.invuln = 0.0
	game.on_room_cleared(1.0) # queue the ordinary delayed room reward before death
	player.take_hit(1, "fatal hit")
	check(player.pips == 0 and deaths[0] == 1 and game.dead, "Lethal damage clamps Pips and emits death exactly once")
	var ended_at := game.run_time
	game._process(RunGame.REWARD_DELAY + SIMULATION_STEP)
	check(not game.picker.is_open and not get_tree().paused and game.run_time == ended_at, "A pending room reward cannot open or advance a run after death")
	get_tree().paused = false # allow failure reporting even if a regression opened the picker
	game.queue_free()
	await get_tree().process_frame


func _dash_contracts(game: RunGame) -> void:
	var player := game.player
	var original_position := player.position
	var original_pips := player.pips
	player.bot = true
	player.bot_move = Vector2.RIGHT
	player.bot_aim = Vector2.RIGHT
	player.invuln = 0.0
	player.heat.set_value(40.0)
	player.bot_dash = true
	player._physics_process(SIMULATION_STEP)
	check(player.dash_charges == 1 and is_equal_approx(player.dash_time, Player.DASH_TIME), "Dash input consumes one charge and starts its duration")
	check(is_equal_approx(player.heat.value, 40.0 - Player.DASH_QUENCH), "Dash quenches its printed Heat amount once")
	player._physics_process(Player.DASH_IFRAMES - 0.001)
	player.take_hit(1, "inside dash protection")
	check(player.pips == original_pips and player.is_invulnerable(), "Damage is rejected immediately inside the dash protection window")
	player._physics_process(0.002)
	player.take_hit(1, "outside dash protection")
	check(player.pips == original_pips - 1, "Damage applies immediately after dash protection expires")
	player.invuln = 0.0
	player._physics_process(Player.DASH_TIME)
	player.bot_dash = true
	player._physics_process(SIMULATION_STEP)
	check(player.dash_charges == 0, "A second dash consumes the last available charge")
	player._physics_process(Player.DASH_TIME)
	player.bot_dash = true
	player._physics_process(SIMULATION_STEP)
	check(player.dash_charges == 0 and player.dash_time <= 0.0, "Dash input cannot start another dash with no charges")
	player.bot_move = Vector2.ZERO
	player._physics_process(player.dash_recharge - 0.001)
	check(player.dash_charges == 0, "Dash charges remain empty until the recharge deadline")
	player._physics_process(0.002)
	check(player.dash_charges == 1 and is_equal_approx(player.dash_recharge, Player.DASH_RECHARGE), "Recharge restores one charge and starts the next sequential recharge")
	player._physics_process(Player.DASH_RECHARGE + 0.001)
	check(player.dash_charges == Player.DASH_MAX and player.dash_recharge == 0.0, "Sequential recharge stops when both charges are full")
	game.inventory.add("heat_exchanger")
	player.bot_dash = true
	player._physics_process(SIMULATION_STEP)
	var modified_recharge := Player.DASH_RECHARGE * game.inventory.dash_recharge_mult()
	check(is_equal_approx(player.dash_recharge, modified_recharge), "Heat Exchanger shortens the dash recharge deadline")
	player._physics_process(modified_recharge + 0.001)
	check(player.dash_charges == Player.DASH_MAX, "A modified recharge restores the spent charge at its shorter deadline")
	game.inventory.remove("heat_exchanger")
	player.bot = false
	player.bot_move = Vector2.ZERO
	player.position = original_position
	player.velocity = Vector2.ZERO
	player.pips = original_pips
	player.invuln = 0.0
	player.dash_time = 0.0
	player.dash_recharge = 0.0
	player.heat.set_value(0.0)


func _clinker_contracts(game: RunGame) -> void:
	var player: Player = game.player
	var pips_before := player.pips
	var clinker: Clinker = ClinkerScript.new()
	clinker.game = game
	clinker.position = player.position + Vector2(40.0, 0.0)
	clinker.set_physics_process(false)
	game.world.add_child(clinker)
	clinker._ai(0.01)
	check(clinker.state == Clinker.S.WINDUP and is_equal_approx(clinker.t, Clinker.WINDUP), "Clinker begins its telegraphed bite inside trigger range (state %d, game dead %s)" % [clinker.state, game.dead])
	clinker.t = 0.01
	clinker._ai(0.02)
	check(clinker.state == Clinker.S.LUNGE and is_equal_approx(clinker.t, Clinker.LUNGE_TIME), "Clinker enters its timed lunge after the windup")
	player.invuln = 0.0
	clinker.position = player.position - Vector2(20.0, 0.0)
	clinker.facing = Vector2.RIGHT
	clinker.t = 0.1
	clinker._ai(0.01)
	clinker._ai(0.01)
	check(clinker.bit and player.pips == pips_before - 1, "Clinker lunge applies at most one bite during its attack")
	player.pips = pips_before
	player.invuln = 0.0
	clinker.queue_free()
	await get_tree().process_frame


func _forgewarden_contracts(game: RunGame) -> void:
	var player := game.player
	var warden: Forgewarden = ForgewardenScript.new()
	warden.game = game
	warden.position = player.position + Vector2(400.0, 0.0)
	warden.set_physics_process(false)
	game.world.add_child(warden)
	warden.facing = Vector2.RIGHT

	warden.take_damage(40.0, false, Vector2.LEFT, "contract")
	check(is_equal_approx(warden.hp, 590.0) and is_equal_approx(warden.plate_hp, 40.0), "Front plate blocks 75% of damage and tracks absorbed damage")
	warden.take_damage(40.0, false, Vector2.LEFT, "contract")
	check(is_equal_approx(warden.hp, 580.0) and warden.plates == 2 and is_equal_approx(warden.plate_hp, Forgewarden.PLATE_HP), "A plate breaks at 80 absorbed damage and restores the next plate")
	warden.take_damage(10.0, false, Vector2.RIGHT, "contract")
	check(is_equal_approx(warden.hp, 565.0), "Back damage receives the 50% bonus")
	warden.take_damage(10.0, false, Vector2.ZERO, "ignite")
	check(is_equal_approx(warden.hp, 555.0), "Ignite damage bypasses directional armour")

	player.pips = player.max_pips
	player.invuln = 0.0
	player.global_position = warden.global_position + Vector2.LEFT * 200.0
	warden.facing = Vector2.LEFT
	warden.target = player.global_position
	warden.state = Forgewarden.S.RAISE
	warden.t = 0.0
	warden._physics_process(SIMULATION_STEP)
	check(warden.state == Forgewarden.S.LEAP and is_equal_approx(warden.t, Forgewarden.LEAP_TIME), "Hammerfall raise transitions into its timed leap")
	warden.t = 0.001
	warden._physics_process(SIMULATION_STEP)
	check(warden.state == Forgewarden.S.SHOCK and player.pips == player.max_pips - 2 and warden.ring_hit, "Hammerfall lands, damages a nearby player, and marks the ring hit")

	player.pips = player.max_pips
	player.invuln = 0.0
	warden.state = Forgewarden.S.INHALE
	warden.t = 0.001
	warden._physics_process(SIMULATION_STEP)
	check(warden.state == Forgewarden.S.BREATH and is_equal_approx(warden.t, Forgewarden.BREATH), "Bellows inhale transitions into its timed breath")

	player.pips = player.max_pips
	player.invuln = 0.0
	player.global_position = warden.global_position + Vector2.LEFT * 200.0
	warden.facing = Vector2.LEFT
	warden.ring_hit = false
	warden.state = Forgewarden.S.SHOCK
	warden.t = Forgewarden.RING_TIME * (1.0 - 200.0 / Forgewarden.RING_REACH)
	warden._physics_process(SIMULATION_STEP)
	check(warden.ring_hit and player.pips == player.max_pips - 2, "Hammerfall ring crossing deals two pips through the shock state")
	player.invuln = 0.0
	warden._physics_process(SIMULATION_STEP)
	check(player.pips == player.max_pips - 2, "Hammerfall shock state cannot hit the player twice")

	player.pips = player.max_pips
	player.invuln = 0.0
	player.global_position = warden.global_position + Vector2.LEFT * 30.0
	warden.facing = Vector2.LEFT
	warden.breath_hit = false
	warden.state = Forgewarden.S.BREATH
	warden.t = Forgewarden.BREATH
	player.dash_time = 0.01 # not invulnerable, but prevents a random MoltenPatch from obscuring the breath result
	warden._physics_process(SIMULATION_STEP)
	check(warden.breath_hit and player.pips == player.max_pips - 2, "Bellows Breath hits a player in the forward cone through the breath state")
	player.invuln = 0.0
	warden._physics_process(SIMULATION_STEP)
	check(player.pips == player.max_pips - 2, "Bellows Breath state applies damage only once per attack")
	player.invuln = 0.0
	player.global_position = warden.global_position + Vector2.RIGHT * 100.0
	warden.breath_hit = false
	warden._physics_process(SIMULATION_STEP)
	check(player.pips == player.max_pips - 2, "Bellows Breath does not hit a player behind the Forgewarden")
	player.dash_time = 0.0
	for child: Node in game.world.get_children():
		if child is MoltenPatch:
			child.queue_free()
	warden.queue_free()
	await get_tree().process_frame

func _linesman_contracts(game: RunGame) -> void:
	var player: Player = game.player
	var line: Linesman = LinesmanScript.new()
	line.game = game
	line.position = player.position + Vector2(6.0 * C.TILE, 0.0)
	line.set_physics_process(false)
	game.world.add_child(line)
	var partner: Clinker = ClinkerScript.new()
	partner.game = game
	partner.position = line.position + Vector2(2.0 * C.TILE, 0.0)
	partner.set_physics_process(false)
	game.world.add_child(partner)

	line.tether = Linesman.T.AIM
	line.partner = partner
	line.tether_t = Linesman.TETHER_AIM
	line._tick_tether(Linesman.TETHER_AIM + 0.01)
	check(line.beam_active() and line.tether == Linesman.T.BEAM, "Linesman advances a valid aim into one live tether beam")
	partner.dead = true
	line._tick_tether(0.01)
	check(line.tether == Linesman.T.IDLE and line.partner == null, "Linesman drops its beam immediately when its partner dies")
	partner.dead = false

	line.state = Linesman.S.CROUCH
	line.t = 0.01
	line._ai(0.02)
	check(line.state == Linesman.S.HOP and line.hop_dir.is_normalized(), "Linesman finishes its crouch with a normalized escape direction")
	line.t = 0.01
	line._ai(Linesman.HOP_TIME)
	check(line.state == Linesman.S.DRIFT and is_equal_approx(line.hop_cd, Linesman.HOP_COOLDOWN), "Linesman ends its hop and starts the cooldown")
	line.queue_free()
	partner.queue_free()
	await get_tree().process_frame


func _touch_controls_contracts(game: RunGame) -> void:
	var controls: TouchControls = TouchControlsScript.new()
	controls.game = game
	controls.aim_changed.connect(game.player.set_aim_input)
	add_child(controls)
	controls.view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	controls.view.size = Vector2(1280.0, 720.0)
	controls.active = true

	var vent_down := InputEventScreenTouch.new()
	vent_down.index = 4
	vent_down.position = Vector2(1196.0, 452.0)
	vent_down.pressed = true
	controls._input(vent_down)
	check(Input.is_action_pressed("vent"), "Touching the Vent button presses the matching action")
	var vent_up := InputEventScreenTouch.new()
	vent_up.index = 4
	vent_up.position = vent_down.position
	vent_up.pressed = false
	controls._input(vent_up)
	check(not Input.is_action_pressed("vent"), "Releasing the Vent touch releases its action")

	var move_down := InputEventScreenTouch.new()
	move_down.index = 5
	move_down.position = Vector2(200.0, 300.0)
	move_down.pressed = true
	controls._input(move_down)
	var move_drag := InputEventScreenDrag.new()
	move_drag.index = 5
	move_drag.position = Vector2(260.0, 300.0)
	controls._input(move_drag)
	check(Input.is_action_pressed("move_right"), "Dragging the left touch stick presses the matching move action")
	var move_up := InputEventScreenTouch.new()
	move_up.index = 5
	move_up.position = move_down.position
	move_up.pressed = false
	controls._input(move_up)
	check(not Input.is_action_pressed("move_right"), "Releasing the move stick clears its held movement action")

	var aim_down := InputEventScreenTouch.new()
	aim_down.index = 6
	aim_down.position = Vector2(900.0, 300.0)
	aim_down.pressed = true
	controls._input(aim_down)
	var aim_drag := InputEventScreenDrag.new()
	aim_drag.index = 6
	aim_drag.position = Vector2(960.0, 300.0)
	controls._input(aim_drag)
	check(Input.is_action_pressed("fire") and controls.aim.is_equal_approx(Vector2.RIGHT), "Dragging the right touch stick aims and holds fire")
	var was_bot := game.player.bot
	game.player.bot = false
	game.player._update_aim()
	check(game.player.aim_dir.is_equal_approx(Vector2.RIGHT), "The composed aim signal delivers touch direction to Player without sibling lookup")
	var aim_up := InputEventScreenTouch.new()
	aim_up.index = 6
	aim_up.position = aim_down.position
	aim_up.pressed = false
	controls._input(aim_up)
	check(not Input.is_action_pressed("fire") and controls.aim == Vector2.ZERO, "Releasing the aim stick clears fire and aim")
	game.player._update_aim()
	check(game.player.aim_dir.is_equal_approx(Vector2.RIGHT), "Releasing touch aim retains the last direction instead of reverting to emulated mouse aim")
	game.player.bot = was_bot
	game.player.set_aim_input(Vector2.ZERO, false)
	controls.queue_free()
	await get_tree().process_frame


func _projectile_and_scrap_contracts(game: RunGame) -> void:
	var player: Player = game.player
	var shard: Shard = ShardScript.new()
	shard.inventory = game.inventory
	shard.age = Shard.RANGE_TIME
	game.world.add_child(shard)
	shard._physics_process(0.01)
	check(shard.is_queued_for_deletion(), "Shard expires after its configured short range lifetime")

	var scrap_before := game.scrap
	var pickup: ScrapBit = ScrapBitScript.new()
	pickup.game = game
	pickup.value = 3
	pickup.position = player.position
	game.world.add_child(pickup)
	pickup._process(0.001)
	check(game.scrap == scrap_before + 3 and not pickup.is_in_group("scrap"), "Scrap pickup grants its value once and leaves the pickup group")

	var pips_before := player.pips
	player.invuln = 0.0
	player.dash_time = 0.0
	var patch: MoltenPatch = MoltenPatchScript.new()
	patch.game = game
	patch.position = player.position
	game.world.add_child(patch)
	patch._physics_process(0.01)
	patch._physics_process(0.01)
	check(player.pips == pips_before - 1 and patch.burned, "Molten floor damages a nearby player at most once per patch")
	shard.queue_free()
	pickup.queue_free()
	patch.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame


func _ui_contracts(game: RunGame) -> void:
	var picker: Picker = PickerScript.new()
	add_child(picker)
	var choices: Array[String] = []
	picker.chosen.connect(func(id: String) -> void: choices.append(id))
	picker.open(Picker.items(["bellows_valve", "tinder_rounds"], game.inventory, "CHOOSE", Callable()))
	check(picker.is_open and get_tree().paused, "Picker opens its selection view and pauses gameplay")
	picker.choose(4)
	check(picker.is_open and choices.is_empty(), "Picker ignores out-of-range selections without closing")
	picker.choose(1)
	check(not picker.is_open and not get_tree().paused and choices == ["tinder_rounds"], "Picker emits the selected item and resumes gameplay")
	var cancellable_offer := Picker.items(["bellows_valve"], game.inventory, "CHOOSE", Callable())
	var completions: Array[String] = []
	cancellable_offer.complete = func(id: String) -> void: completions.append(id)
	cancellable_offer.cancellable = true
	picker.open(cancellable_offer)
	picker.cancel()
	check(not picker.is_open and choices == ["tinder_rounds", ""], "Cancellable Picker emits an empty choice when dismissed")
	picker.cancel()
	picker.choose(0)
	check(completions == [""], "A completed request clears its callback so later choose/cancel calls cannot repeat it")
	picker.queue_free()
	var pause: PauseMenu = PauseMenuScript.new()
	pause.game = game
	add_child(pause)
	pause.open()
	check(pause.is_open and get_tree().paused, "Pause menu opens and freezes gameplay")
	pause.close()
	check(not pause.is_open and not get_tree().paused, "Pause menu close resumes gameplay")
	pause.queue_free()
	var menu: MainMenu = MainMenuScript.new()
	add_child(menu)
	menu._show_codex()
	check(menu.codex.visible and not menu.buttons.visible, "Main menu opens Codex in place of its primary buttons")
	check(menu.codex.get_script() == CodexPanelScript, "Main menu hosts the directly tested Codex script")
	menu.codex.show_page(menu.codex.PAGES.size())
	check(menu.codex.page == 0 and not menu.codex.text.text.is_empty(), "Codex wraps page indexes and renders the selected page")
	menu.queue_free()
	var settings_panel: SettingsPanel = SettingsPanelScript.new()
	add_child(settings_panel)
	settings_panel.open()
	check(settings_panel.visible and is_equal_approx(settings_panel.volume.value, Settings.volume), "Settings panel opens with the current volume value")
	settings_panel.queue_free()
	await get_tree().process_frame


func _presentation_output_contracts(game: RunGame) -> void:
	game.fx.clear()
	game.fx.ring(Vector2(10.0, 20.0), 40.0, Color.ORANGE, 0.2)
	game.fx.number(Vector2(10.0, 20.0), 12.0, false)
	check(game.fx.rings.size() == 1 and game.fx.texts.size() == 1, "FX stores ring and floating damage-number events")
	game.fx.clear()
	check(game.fx.rings.is_empty() and game.fx.texts.is_empty(), "FX clear removes pending visual events")
	game.hud.banner("CONTRACT", "runtime")
	game.hud.damage_flash()
	game.hud.dim(0.2)
	check(game.hud._banner == "CONTRACT" and is_equal_approx(game.hud._banner_t, 2.0) and game.hud._damage == 1.0, "HUD exposes banner and damage feedback for runtime events")
	game.hud._process(0.25)
	check(is_equal_approx(game.hud._banner_t, 1.75) and is_zero_approx(game.hud._dim), "HUD advances banner timing and expires short dim effects")


func _world_interaction_contracts(game: RunGame) -> void:
	var prior_scrap := game.scrap
	var pedestal: Pedestal = PedestalScript.new()
	pedestal.game = game
	pedestal.price = 4
	pedestal.position = game.player.position
	game.world.add_child(pedestal)
	game.scrap = 5
	pedestal._process(0.0)
	check(pedestal.near and pedestal.affordable(), "Pedestal detects an in-range player with enough Scrap")
	game.scrap = 3
	check(not pedestal.affordable(), "Pedestal rejects purchases below its Scrap price")
	var door: Door = DoorScript.new()
	door.game = game
	game.world.add_child(door)
	check(is_equal_approx(door._neon_level(), 0.5), "Closed Door uses its dim sealed-light level")
	door.open = true
	door._flicker = 0.0
	var neon := door._neon_level()
	check(neon >= 0.84 and neon <= 1.0, "Open Door holds a bright neon level after its startup flicker")
	pedestal.queue_free()
	door.queue_free()
	game.scrap = prior_scrap
	await get_tree().process_frame

