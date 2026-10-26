extends Node
## Real physics queries with fixed actor steps and deterministic critical chance.

const RivetScript = preload("res://scripts/combat/projectiles/rivet.gd")
const ShardScript = preload("res://scripts/combat/projectiles/shard.gd")
const EnemyScript = preload("res://scripts/combat/enemies/enemy.gd")
const CombatEffectsScript = preload("res://scripts/combat/combat_effects.gd")

class ControlledInventory extends Inventory:
	func crit_chance() -> float:
		return 0.0

var game: RunGame
var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	var strength: float = Juice.hitstop_strength
	Juice.hitstop_strength = 0.0
	await _shard_recursion()
	await _homing_and_flare_lifetime()
	await _flare_detonation()
	await _rivet_pierce()
	await _rivet_dead_colliders()
	await _rivet_ricochet()
	await _rivet_wall_and_expiry()
	await _tempered_death_hooks()
	await _tempered_pyre_coating()
	await _tempered_arcs()
	Juice.hitstop_strength = strength
	Juice.reset()
	print("projectile test: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _fixture() -> void:
	# RunGame supplies the concrete collaborator types; its run lifecycle stays off-tree.
	game = RunGame.new()
	game.world = Node2D.new()
	game.world.child_entered_tree.connect(func(node: Node) -> void: node.set_physics_process(false))
	add_child(game.world)
	game.fx = Fx.new()
	game.world.add_child(game.fx)
	game.player = Player.new()
	game.add_child(game.player)
	game.player.add_child(game.player.heat)
	game.player.position = Vector2(1000.0, 1000.0)
	game.inventory = ControlledInventory.new()
	game.inventory.player = game.player
	game.world.add_child(game.inventory)
	game.effects = CombatEffectsScript.new()
	game.effects.inventory = game.inventory
	game.effects.player = game.player
	game.effects.fx = game.fx
	game.effects.projectile_parent = game.world
	game.world.add_child(game.effects)


func _clear_fixture() -> void:
	game.world.queue_free()
	game.free()
	await get_tree().process_frame


func _enemy(pos: Vector2, hp := 100.0) -> Enemy:
	var enemy := EnemyScript.new()
	enemy.game = game
	enemy.position = pos
	enemy.max_hp = hp
	enemy.defeated.connect(game.effects.on_kill)
	game.world.add_child(enemy)
	return enemy


func _shards() -> Array:
	return game.world.get_children().filter(func(node: Node) -> bool: return node is Shard)


func _rivet(pos: Vector2) -> Rivet:
	var rivet := RivetScript.new()
	rivet.inventory = game.inventory
	rivet.effects = game.effects
	rivet.fx = game.fx
	rivet.position = pos
	game.world.add_child(rivet)
	return rivet


func _wall(pos: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.position = pos
	wall.collision_layer = C.LAYER_WALL
	wall.collision_mask = 0
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8.0, 100.0)
	collision.shape = rectangle
	wall.add_child(collision)
	game.world.add_child(wall)


func _shard_recursion() -> void:
	_fixture()
	game.inventory.add("frag_lattice")
	var victim := _enemy(Vector2.ZERO, 1.0)
	victim.take_damage(1.0, false, Vector2.ZERO, Enemy.DamageKind.SHARD, 1)
	var shards := _shards()
	check(shards.size() == 4, "A generation-one shard kill spawns four next-generation shards")
	check(shards.all(func(shard: Shard) -> bool: return shard.depth == CombatEffects.SHARD_DEPTH_CAP), "Spawned shards carry the recursion depth cap")
	victim = _enemy(Vector2(100.0, 0.0), 1.0)
	victim.take_damage(1.0, false, Vector2.ZERO, Enemy.DamageKind.SHARD, CombatEffects.SHARD_DEPTH_CAP)
	check(_shards().size() == 4, "A shard kill at the depth cap cannot create another generation")
	await _clear_fixture()


func _homing_and_flare_lifetime() -> void:
	_fixture()
	_enemy(Vector2(0.0, -30.0)) # nearest, but not Ignited
	var dead_target := _enemy(Vector2(0.0, -50.0))
	dead_target.add_ignite(1, 10)
	dead_target.dead = true
	var distant := _enemy(Vector2(0.0, -Shard.HOMING_REACH - 50.0))
	distant.add_ignite(1, 10)
	var eligible := _enemy(Vector2(0.0, 100.0))
	eligible.add_ignite(1, 10)
	var shard := ShardScript.new()
	shard.inventory = game.inventory
	shard.effects = game.effects
	shard.homing = true
	game.world.add_child(shard)
	shard._physics_process(0.1)
	check(is_equal_approx(shard.dir.angle(), Shard.HOMING_TURN * 0.1), "Homing turns at its capped rate toward an in-range living Ignited target")
	eligible.clear_ignite()
	var previous_dir := shard.dir
	shard._physics_process(0.01)
	check(shard.dir.is_equal_approx(previous_dir), "Homing ignores non-Ignited, dead, and out-of-range enemies")
	var flare := ShardScript.new()
	flare.inventory = game.inventory
	flare.effects = game.effects
	flare.flare = true
	flare.position = Vector2(500.0, 500.0)
	game.world.add_child(flare)
	flare.age = Shard.FLARE_LIFE - 0.02
	flare._physics_process(0.01)
	check(not flare.is_queued_for_deletion(), "A flare survives until its configured lifetime")
	flare._physics_process(0.02)
	check(flare.is_queued_for_deletion(), "An undetonated flare expires at its lifetime")
	await _clear_fixture()


func _flare_detonation() -> void:
	_fixture()
	for id: String in ["tinder_rounds", "frag_lattice", "feedback_coil"]:
		game.inventory.add(id)
	var web_target := _enemy(Vector2(72.0, 0.0))
	var burst_target := _enemy(Vector2.ZERO)
	for x: float in [0.0, 144.0, 192.0]:
		game.effects.spawn_shard(Vector2(x, 0.0), Vector2.RIGHT, 1)
	var detonations: Array[bool] = []
	game.effects.flares_detonated.connect(func() -> void: detonations.append(true))
	game.effects.on_vent(0.0)
	check(is_equal_approx(web_target.hp, 88.0), "Overlapping flare web segments damage an enemy only once")
	check(is_equal_approx(burst_target.hp, 76.0), "A flare endpoint applies its burst plus one web hit")
	check(get_tree().get_nodes_in_group("flares").is_empty(), "Vent immediately consumes every flare")
	game.effects.on_vent(0.0)
	check(is_equal_approx(web_target.hp, 88.0) and is_equal_approx(burst_target.hp, 76.0) and detonations.size() == 1, "A second Vent cannot detonate consumed flares again")
	await _clear_fixture()


func _rivet_pierce() -> void:
	_fixture()
	var first := _enemy(Vector2(100.0, 0.0))
	var second := _enemy(Vector2(180.0, 0.0))
	var rivet := _rivet(Vector2.ZERO)
	rivet.pierce = 1
	await get_tree().physics_frame
	await get_tree().process_frame
	rivet._physics_process(250.0 / Rivet.SPEED)
	check(is_equal_approx(first.hp, 92.0) and first.rivet_count() == 1, "A piercing Rivet damages and embeds in its first enemy once")
	check(is_equal_approx(second.hp, 92.0) and second.rivet_count() == 1 and rivet.is_queued_for_deletion(), "Pierce excludes the first collider, reaches the second, and consumes the Rivet")
	await _clear_fixture()


func _rivet_dead_colliders() -> void:
	for piercing_hits in [0, 1]:
		_fixture()
		game.inventory.add("bellows_valve")
		game.player.heat.set_value(Heat.WARM_AT)
		var corpse := _enemy(Vector2(100.0, 0.0))
		var first := _enemy(Vector2(180.0, 0.0))
		var second := _enemy(Vector2(260.0, 0.0))
		var rivet := _rivet(Vector2.ZERO)
		rivet.pierce = piercing_hits
		await get_tree().physics_frame
		await get_tree().process_frame
		# Kill after physics registration, then fire before deferred deletion runs.
		corpse.take_damage(100.0, false, Vector2.ZERO, Enemy.DamageKind.OTHER)
		rivet._physics_process(300.0 / Rivet.SPEED)
		check(corpse.is_queued_for_deletion() and corpse.rivet_count() == 0, "A pending enemy deletion cannot absorb or embed another Rivet")
		check(first.hp == 92.0 and first.rivet_count() == 1, "A Rivet passes the dead collider and reaches the first live enemy")
		check(second.hp == (92.0 if piercing_hits == 1 else 100.0), "Dead colliders do not consume the pierce reserved for living enemies")
		check(is_equal_approx(game.inventory.proc_bonus, 0.02 * (piercing_hits + 1)), "Only living hits trigger Bellows Valve's item hook")
		check(rivet.is_queued_for_deletion(), "The final live target consumes the Rivet")
		await _clear_fixture()


func _rivet_ricochet() -> void:
	for tempered in [false, true]:
		await _rebound_charge(tempered)


func _rebound_charge(tempered: bool) -> void:
	_fixture()
	game.inventory.add("rebound_charge")
	if tempered:
		game.inventory.temper("rebound_charge")
	_wall(Vector2(200.0, 0.0))
	_wall(Vector2(-80.0, 0.0))
	var target := _enemy(Vector2(50.0, 0.0))
	var rivet := _rivet(Vector2(100.0, 0.0))
	rivet.ricochet = 1
	await get_tree().physics_frame
	await get_tree().process_frame
	rivet._physics_process(400.0 / Rivet.SPEED)
	check(rivet.ricocheted and rivet.ricochet == 0 and rivet.dir.is_equal_approx(Vector2.LEFT), "A wall collision consumes one ricochet and reflects the direction")
	check(is_equal_approx(target.hp, 84.0 if tempered else 88.0) and target.rivet_count() == 1 and rivet.pierce == (1 if tempered else 0), "Rebound Charge applies its ordinary or tempered damage and pierce to the reflected hit")
	check(rivet.is_queued_for_deletion(), "The next wall consumes a Rivet after its ricochet is exhausted")
	await _clear_fixture()


func _rivet_wall_and_expiry() -> void:
	for tempered in [false, true]:
		await _splinter_wall_stop(tempered)


func _splinter_wall_stop(tempered: bool) -> void:
	_fixture()
	game.inventory.add("splinter_heads")
	if tempered:
		game.inventory.temper("splinter_heads")
	_wall(Vector2(200.0, 0.0))
	var behind_wall := _enemy(Vector2(250.0, 0.0))
	var rivet := _rivet(Vector2(100.0, 0.0))
	await get_tree().physics_frame
	await get_tree().process_frame
	rivet._physics_process(200.0 / Rivet.SPEED)
	check(rivet.is_queued_for_deletion() and _shards().size() == (5 if tempered else 3) and behind_wall.hp == 100.0, "A wall hit creates the ordinary or tempered Splinter Heads burst without hitting through the wall")
	var expired := _rivet(Vector2(225.0, 0.0))
	expired.life = 0.001
	expired._physics_process(0.01)
	check(expired.is_queued_for_deletion() and behind_wall.hp == 100.0, "An expired Rivet cannot damage an enemy")
	await _clear_fixture()


func _tempered_death_hooks() -> void:
	for tempered in [false, true]:
		_fixture()
		game.inventory.add("tinder_rounds")
		if tempered:
			game.inventory.temper("tinder_rounds")
		var nearby := _enemy(Vector2(C.TILE, 0.0))
		var extended := _enemy(Vector2(2.0 * C.TILE, 0.0))
		var outside := _enemy(Vector2(3.0 * C.TILE, 0.0))
		var victim := _enemy(Vector2.ZERO)
		victim.add_ignite(6, 10)
		victim.take_damage(100.0, false, Vector2.ZERO, Enemy.DamageKind.RIVET)
		check(nearby.ignite_stacks == 3 and outside.ignite_stacks == 0, "Tinder's death burst shares half the stacks within its range only")
		check(extended.ignite_stacks == (3 if tempered else 0), "Tempered Tinder extends the death burst from 1.5 to 2.5 tiles")
		await _clear_fixture()

		_fixture()
		game.inventory.add("frag_lattice")
		if tempered:
			game.inventory.temper("frag_lattice")
		victim = _enemy(Vector2.ZERO)
		victim.take_damage(100.0, false, Vector2.ZERO, Enemy.DamageKind.RIVET)
		check(_shards().size() == (6 if tempered else 4), "Frag Lattice creates its ordinary or tempered shard count on death")
		await _clear_fixture()


func _tempered_pyre_coating() -> void:
	for tempered in [false, true]:
		_fixture()
		game.inventory.add("pyre_coating")
		if tempered:
			game.inventory.temper("pyre_coating")
		game.player.position = Vector2.ZERO
		var nearby := _enemy(Vector2(C.TILE, 0.0))
		var extended := _enemy(Vector2(4.5 * C.TILE, 0.0))
		var outside := _enemy(Vector2(6.0 * C.TILE, 0.0))
		var rivet := _rivet(Vector2.ZERO)
		rivet.overdrive = true
		rivet._hit_enemy(nearby)
		check(nearby.ignite_stacks == (3 if tempered else 2), "Pyre Coating applies its ordinary or tempered Ignite stacks on a Hot Rivet hit")
		nearby.clear_ignite()
		game.effects.on_overheat()
		check(nearby.ignite_stacks == (5 if tempered else 3), "Pyre Coating's Overheat burst applies its upgraded stack count")
		check(extended.ignite_stacks == (5 if tempered else 0) and outside.ignite_stacks == 0, "Tempered Pyre extends Overheat range from four to five tiles")
		await _clear_fixture()


func _tempered_arcs() -> void:
	for tempered in [false, true]:
		_fixture()
		game.inventory.add("feedback_coil")
		if tempered:
			game.inventory.temper("feedback_coil")
		game.player.position = Vector2.ZERO
		var targets: Array[Enemy] = []
		for i in 6:
			targets.append(_enemy(Vector2((i + 1) * 40.0, 0.0)))
		targets[-1].add_ignite(2, 10)
		game.effects.on_vent(0.0)
		var ordinary_hits := 4 if tempered else 2
		for i in 5:
			var expected_hp := 100.0
			if i < ordinary_hits:
				expected_hp = 86.0 if tempered else 90.0
			check(targets[i].hp == expected_hp, "Feedback Coil limits arcs to its ordinary or tempered target count and damage")
		check(targets[-1].hp == (76.0 if tempered else 80.0) and targets[-1].ignite_stacks == 0, "Vent prioritizes Ignite, adds stack damage, and consumes it with either upgrade state")
		await _clear_fixture()

		_fixture()
		game.inventory.add("static_rivets")
		if tempered:
			game.inventory.temper("static_rivets")
		var struck := _enemy(Vector2.ZERO)
		var neighbor := _enemy(Vector2(2.0 * C.TILE, 0.0))
		var rivet := _rivet(Vector2.ZERO)
		var trigger := 3 if tempered else 5
		for i in trigger - 1:
			rivet._hit_enemy(struck)
		check(neighbor.hp == 100.0, "Static Rivets waits for its ordinary or tempered hit threshold")
		rivet._hit_enemy(struck)
		check(neighbor.hp == 92.0, "Static Rivets arcs on the fifth ordinary or third tempered hit")
		rivet._hit_enemy(struck)
		check(neighbor.hp == 92.0, "Static Rivets begins a new hit interval after its arc")
		await _clear_fixture()
