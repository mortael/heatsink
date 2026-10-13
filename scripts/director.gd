class_name Director
extends Node
## Encounter director for combat rooms (GDD section 6).
## Room budget TP = 8 + 2 x room index; Clinkers cost 1 TP; waves split the budget.
## The Foundry Gate stands in for the Stratum boss until bosses exist: a bigger 3-wave fight.
## Next wave arrives when < 25% of the wave remains or after 8 s. Portals warn 0.8 s ahead,
## and nothing spawns within 3 tiles of the player.

const PORTAL_TIME := 0.8
const MIN_SPAWN_DIST := 3.0 * C.TILE
const WAVE_TIMEOUT := 8.0

var game: Node
var room_index := 0
var budget := 0
var waves_total := 1
var wave := 0
var wave_size := 0
var wave_timer := 0.0
var room_time := 0.0
var active := false
var pending := 0
var clear_times: Array[float] = []


func start_room(index: int, gate := false) -> void:
	room_index = index
	budget = 8 + 2 * room_index
	waves_total = 1 if room_index == 1 else (2 if room_index < 4 else 3)
	if gate:
		budget = int(budget * 1.25)
		waves_total = 3
	wave = 0
	room_time = 0.0
	active = true
	_spawn_wave()


func _spawn_wave() -> void:
	wave += 1
	# Split the budget so the waves add up to it exactly; earlier waves take the remainder.
	wave_size = budget / waves_total + (1 if wave <= budget % waves_total else 0)
	wave_timer = WAVE_TIMEOUT
	# Packs: spawn around 2 cluster centres so they arrive as crowds.
	var centres: Array[Vector2] = [_spawn_point(), _spawn_point()]
	for i in wave_size:
		var c: Vector2 = centres[i % 2]
		var pos := c
		for tries in 10:
			var cand := c + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 1.5 * C.TILE)
			if game.room.is_open(cand, 20.0) and cand.distance_to(game.player.global_position) >= MIN_SPAWN_DIST:
				pos = cand
				break
		_portal(pos)


func _spawn_point() -> Vector2:
	var best: Vector2 = game.room.random_open_point()
	for i in 30:
		var p: Vector2 = game.room.random_open_point()
		if p.distance_to(game.player.global_position) >= MIN_SPAWN_DIST + 2.0 * C.TILE:
			return p
		best = p
	return best


func _portal(pos: Vector2) -> void:
	pending += 1
	game.fx.portal(pos, PORTAL_TIME)
	Sfx.play("portal", randf_range(-2.0, 2.0), -12.0)
	# A Timer child dies with the director, so a restart mid-portal can't spawn into a freed scene.
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = PORTAL_TIME
	add_child(t)
	t.timeout.connect(func() -> void:
		t.queue_free()
		pending -= 1
		if game.dead:
			return
		var c := Clinker.new()
		c.game = game
		c.position = pos
		game.world.add_child(c))
	t.start()


func _physics_process(delta: float) -> void:
	if game.dead:
		return
	if not active:
		return
	room_time += delta
	wave_timer -= delta
	var alive := get_tree().get_nodes_in_group("enemies").size() + pending
	if wave < waves_total:
		if alive < wave_size * 0.25 or wave_timer <= 0.0:
			_spawn_wave()
	elif alive == 0:
		active = false
		clear_times.append(room_time)
		game.on_room_cleared(room_time)
