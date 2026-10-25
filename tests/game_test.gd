extends Node
## Run lifecycle and reward wiring, advanced without automatic gameplay steps.

const GameScript = preload("res://scripts/game.gd")
const EnemyScript = preload("res://scripts/combat/enemies/enemy.gd")

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	var strength: float = Juice.hitstop_strength
	Juice.hitstop_strength = 0.0
	var game := _fixture()
	_scrap_spawn_state(game)
	await _enemy_reward_routing_contracts(game)
	await _clear_fixture(game)
	await _room_rewards_and_transition()
	await _terminal_state(false)
	await _terminal_state(true)
	Juice.hitstop_strength = strength
	Juice.reset()
	print("game test: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _fixture() -> RunGame:
	var game := GameScript.new()
	add_child(game)
	game.set_process(false)
	game.player.set_physics_process(false)
	game.director.set_physics_process(false)
	return game


func _clear_fixture(game: RunGame) -> void:
	get_tree().paused = false
	game.queue_free()
	await get_tree().process_frame


func _scrap_spawn_state(game: RunGame) -> void:
	var active_before := game.director.active
	game.director.active = true
	game._spawn_scrap(2, game.room.center())
	game.director.active = false
	game._spawn_scrap(3, game.room.center())
	var pickups := get_tree().get_nodes_in_group("scrap")
	check(pickups.size() == 2 and not pickups[0].sweep and pickups[1].sweep, "RunGame supplies pickup sweep state at insertion, including drops after the encounter ends")
	for pickup: Node in pickups:
		pickup.free()
	game.director.active = active_before
	game.director.armour_broken.emit()
	check(game.hud._banner == "ARMOUR BROKEN", "The run root translates the Director armour event into HUD feedback")


func _room_rewards_and_transition() -> void:
	var game := _fixture()
	var scrap_before := game.scrap
	game.director.room_cleared.emit(2.0)
	var scrap_gain := game.scrap - scrap_before
	check(game.rooms_cleared == 1 and scrap_gain >= GameScript.CLEAR_SCRAP.x and scrap_gain <= GameScript.CLEAR_SCRAP.y, "Room clear records progress and awards Scrap within the promised range")
	game._process(GameScript.REWARD_DELAY * 0.5)
	check(not game.picker.is_open and game.doors.all(func(door: Door) -> bool: return not door.open), "Salvage and doors remain unavailable before the reward delay")
	game._process(GameScript.REWARD_DELAY * 0.5 + 0.01)
	check(game.picker.is_open and get_tree().paused and game.picker.options.size() == 3, "The reward deadline opens three Salvage choices and pauses gameplay")
	if not game.picker.options.is_empty():
		var selected: String = game.picker.options[0]
		game.picker.choose(0)
		check(game.inventory.has(selected) and not game.picker.is_open and not get_tree().paused, "Choosing Salvage awards the selected item and resumes the run")
	check(game.doors.all(func(door: Door) -> bool: return door.open), "Claiming a room reward opens its exits")
	get_tree().paused = false
	game._process(GameScript.REWARD_DELAY)
	check(not game.picker.is_open and game.rooms_cleared == 1, "Later frames do not repeat the completed room reward")
	if not game.doors.is_empty():
		var index_before := game.run.index
		var chosen_kind := game.doors[0].kind
		game.take_door(game.doors[0])
		game.take_door(game.doors[-1])
		game._process(GameScript.TRANSITION_TIME * 0.5)
		check(game.in_transition() and game.run.index == index_before, "A door waits for the transition fade before advancing the route")
		game._process(GameScript.TRANSITION_TIME)
		check(not game.in_transition() and game.run.index == index_before + 1 and game.room_kind == chosen_kind, "A transition builds the chosen room once and ignores another door during the fade")
	await _clear_fixture(game)


func _terminal_state(won: bool) -> void:
	var game := _fixture()
	game.on_room_cleared(1.0) # Leave a real pending Salvage reward.
	game.doors[0].open = true
	game.take_door(game.doors[0])
	if won:
		game.room_kind = "gate"
		game.on_room_cleared(2.0)
	else:
		game.on_player_died()
	var ended_at := game.run_time
	var ended_index := game.run.index
	game._process(GameScript.REWARD_DELAY + GameScript.TRANSITION_TIME)
	check(game.victory if won else game.dead, "The terminal run state is retained")
	check(not game.inventory.run_active and game.run_time == ended_at, "Death and victory stop active-run effects and run-time accumulation")
	check(game.run.index == ended_index and not game.picker.is_open and not get_tree().paused, "Death and victory suppress queued transitions and delayed rewards")
	await _clear_fixture(game)


func _enemy_reward_routing_contracts(game: RunGame) -> void:
	game.inventory.add("hungry_coal")
	var kills_before := game.kills
	var elites_before := game.elites_killed
	var cores_before := game.cores
	var progress_before: float = game.inventory.absolution.get("hungry_coal", 0.0)
	var defeated_count := [0]
	var enemy: Enemy = EnemyScript.new()
	enemy.game = game
	enemy.max_hp = 20.0
	enemy.set_physics_process(false)
	enemy.defeated.connect(game.director.enemy_defeated.emit)
	enemy.defeated.connect(func(_dead: Enemy) -> void: defeated_count[0] += 1)
	game.world.add_child(enemy)
	enemy.take_damage(20.0, false, Vector2.ZERO, Enemy.DamageKind.VENT)
	enemy.take_damage(20.0, false, Vector2.ZERO, Enemy.DamageKind.VENT)
	check(defeated_count[0] == 1, "Repeated lethal damage emits Enemy.defeated once")
	check(game.kills == kills_before + 1 and game.elites_killed == elites_before and game.cores == cores_before, "Ordinary defeat routes kill rewards without elite rewards")
	check(is_equal_approx(game.inventory.absolution["hungry_coal"], progress_before + 1.0), "Inventory kill hook advances Hungry Coal exactly once")

	var elite: Enemy = EnemyScript.new()
	elite.game = game
	elite.max_hp = 20.0
	elite.elite = true
	elite.set_physics_process(false)
	elite.defeated.connect(game.director.enemy_defeated.emit)
	elite.defeated.connect(func(_dead: Enemy) -> void: defeated_count[0] += 1)
	game.world.add_child(elite)
	elite.take_damage(20.0, false, Vector2.ZERO, Enemy.DamageKind.VENT)
	elite.take_damage(20.0, false, Vector2.ZERO, Enemy.DamageKind.VENT)
	check(defeated_count[0] == 2, "Repeated lethal damage emits an elite defeat once")
	check(game.kills == kills_before + 2 and game.elites_killed == elites_before + 1 and game.cores == cores_before + 1, "Elite defeat routes ordinary and elite rewards exactly once")
	check(is_equal_approx(game.inventory.absolution["hungry_coal"], progress_before + 2.0), "Inventory kill hook advances once for each defeated enemy")
	game.inventory.remove("hungry_coal")
	await get_tree().process_frame
