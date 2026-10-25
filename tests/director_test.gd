extends Node

const DirectorScript = preload("res://scripts/combat/director.gd")

class PlacementDirector extends Director:
	var placement_available := false

	func _spawn_point(_min_tiles := 3.0) -> Vector2:
		return Vector2(400.0, 300.0) if placement_available else Vector2.INF

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	var game := RunGame.new()
	game.world = Node2D.new()
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(game.world)
	game.player = Player.new()
	game.add_child(game.player)
	game.player.add_child(game.player.heat)
	game.fx = Fx.new()
	game.world.add_child(game.fx)
	var director := PlacementDirector.new()
	director.game = game
	director.set_physics_process(false)
	add_child(director)
	var clears: Array[float] = []
	var defeats: Array[Enemy] = []
	var armour_events: Array[bool] = []
	director.room_cleared.connect(func(time: float) -> void: clears.append(time))
	director.enemy_defeated.connect(func(enemy: Enemy) -> void: defeats.append(enemy))
	director.armour_broken.connect(func() -> void: armour_events.append(true))
	director.waves = [["forgewarden", "clinker"]]
	director.room_index = 8
	director.active = true
	director._spawn_wave()
	director._physics_process(0.6)
	check(director.active and clears.is_empty() and director.pending == 0, "Placement failure keeps the encounter active instead of awarding an empty clear")
	director.placement_available = true
	director._physics_process(0.6)
	check(director.pending == 2 and director.pending_tp == 13 and director.wave == 1, "A later safe placement schedules both retained units without advancing the wave again")
	await get_tree().create_timer(DirectorScript.PORTAL_TIME + 0.05).timeout
	var enemies := get_tree().get_nodes_in_group("enemies")
	check(enemies.size() == 2 and director.pending == 0 and director.alive_tp() == 13, "Retry portals produce the required Elite and fodder and transfer pending threat to living enemies")
	for enemy: Enemy in enemies:
		if enemy is Forgewarden:
			enemy.plates = 1
			enemy.plate_hp = 1.0
			enemy.facing = Vector2.RIGHT
			enemy.take_damage(4.0, false, Vector2.LEFT, "test")
			check(armour_events.size() == 1, "Breaking the final plate forwards an armour event through Director")
		enemy.take_damage(10000.0, false, Vector2.ZERO, "test")
	director._physics_process(0.1)
	director._physics_process(0.1)
	check(defeats.size() == 2 and clears.size() == 1 and not director.active, "The encounter clears exactly once after every retained unit actually dies")
	director.free()
	game.world.queue_free()
	game.free()
	await get_tree().process_frame
	print("director test: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
