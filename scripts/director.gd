class_name Director
extends Node
## Encounter director for the prototype's endless single room (GDD section 6).
## Room budget TP = 8 + 2 x room index; Clinkers cost 1 TP; waves split the budget.
## Next wave arrives when < 25% of the wave remains or after 8 s. Portals warn 0.8 s ahead,
## and nothing spawns within 3 tiles of the player.

const PORTAL_TIME := 0.8
const MIN_SPAWN_DIST := 3.0 * C.TILE
const WAVE_TIMEOUT := 8.0
const BETWEEN_ROOMS := 2.5

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
var between := 0.0
var clear_times: Array[float] = []
var reward_pending := false


func start_room() -> void:
	room_index += 1
	budget = 8 + 2 * room_index
	waves_total = 1 if room_index == 1 else (2 if room_index < 4 else 3)
	wave = 0
	room_time = 0.0
	active = true
	game.hud.banner("ROOM %d" % room_index, "%d Clinkers in %d wave%s" % [budget, waves_total, "" if waves_total == 1 else "s"])
	_spawn_wave()


func _spawn_wave() -> void:
	wave += 1
	wave_size = int(ceil(float(budget) / waves_total))
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
	get_tree().create_timer(PORTAL_TIME, false).timeout.connect(func() -> void:
		pending -= 1
		if game.dead:
			return
		var c := Clinker.new()
		c.game = game
		c.position = pos
		game.world.add_child(c))


func _physics_process(delta: float) -> void:
	if game.dead:
		return
	if between > 0.0:
		between -= delta
		if between <= 0.0:
			if reward_pending:
				reward_pending = false
				game.offer_reward()
			else:
				start_room()
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
		game.hud.banner("ROOM CLEAR", "%.1f s" % room_time)
		Sfx.play("clear")
		reward_pending = true
		between = 1.2
