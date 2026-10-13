class_name Director
extends Node
## Encounter director for combat rooms (GDD section 6).
## Room budget TP = 8 + 2 x room index. Unit costs: Clinker 1, Linesman 4, Forgewarden 12.
## Waves mix at most one support role with fodder, and at least 40% of each wave's TP is fodder.
## The next wave arrives when less than 25% of the current wave's TP remains, or after 8 s.
## Portals warn 0.8 s ahead, and nothing spawns within 3 tiles of the player.
## Elite rooms lead with a Forgewarden, 4-6 Clinkers and sometimes a Linesman.
## The Foundry Gate stands in for the Stratum boss: 3 waves, the last one led by a Forgewarden.

const PORTAL_TIME := 0.8
const MIN_SPAWN_DIST := 3.0 * C.TILE
const WAVE_TIMEOUT := 8.0
const LINESMAN_FROM := 3 # first room index that can roll a Linesman

var game: Node
var room_index := 0
var budget := 0
var waves: Array = [] # each: Array of unit names
var wave := 0
var wave_tp := 0
var wave_timer := 0.0
var room_time := 0.0
var active := false
var pending := 0
var pending_tp := 0
var clear_times: Array[float] = []


func start_room(index: int, kind := "combat") -> void:
	room_index = index
	budget = 8 + 2 * room_index
	waves = _plan(kind)
	wave = 0
	room_time = 0.0
	active = true
	_spawn_wave()


## Builds every wave of the room up front from the TP budget.
func _plan(kind: String) -> Array:
	var out: Array = []
	match kind:
		"elite":
			var lead: Array = ["forgewarden"]
			for i in randi_range(4, 6):
				lead.append("clinker")
			if room_index >= 5 and randf() < 0.5:
				lead.append("linesman")
			out.append(lead)
			out.append(_fodder(maxi(4, (budget - _cost(lead)) / 2)))
		"gate":
			budget = int(budget * 1.25)
			out.append(_mixed(budget / 3))
			out.append(_mixed(budget / 3))
			var last: Array = ["forgewarden", "linesman"]
			last.append_array(_fodder(6))
			out.append(last)
		_:
			var n := 1 if room_index == 1 else (2 if room_index < 4 else 3)
			for i in n:
				out.append(_mixed(budget / n + (1 if i < budget % n else 0)))
	return out


## A wave of tp points: Clinkers plus, from room 3, Linesmen that keep at least 40% fodder.
func _mixed(tp: int) -> Array:
	var units: Array = []
	if room_index >= LINESMAN_FROM:
		var lines := 0
		if tp >= 8 and randf() < 0.65:
			lines = 1
		if tp >= 14 and room_index >= 7 and randf() < 0.5:
			lines = 2
		for i in lines:
			units.append("linesman")
	var rest := tp - _cost(units)
	units.append_array(_fodder(maxi(rest, int(ceil(tp * 0.4)))))
	return units


func _fodder(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append("clinker")
	return out


static func _cost(units: Array) -> int:
	var tp := 0
	for u: String in units:
		tp += {"clinker": 1, "linesman": 4, "forgewarden": 12}[u]
	return tp


func _spawn_wave() -> void:
	var units: Array = waves[wave]
	wave += 1
	wave_tp = _cost(units)
	wave_timer = WAVE_TIMEOUT
	# Packs: spawn around 2 cluster centres so they arrive as crowds. Big units get their own spot.
	var centres: Array[Vector2] = [_spawn_point(), _spawn_point()]
	var i := 0
	for u: String in units:
		if u == "forgewarden":
			_portal(_spawn_point(5.0), u)
			continue
		var c: Vector2 = centres[i % 2]
		i += 1
		var pos := c
		for tries in 10:
			var cand := c + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 1.5 * C.TILE)
			if game.room.is_open(cand, 20.0) and cand.distance_to(game.player.global_position) >= MIN_SPAWN_DIST:
				pos = cand
				break
		_portal(pos, u)


func _spawn_point(min_tiles := 3.0) -> Vector2:
	var best: Vector2 = game.room.random_open_point(30.0)
	for i in 40:
		var p: Vector2 = game.room.random_open_point(30.0)
		if p.distance_to(game.player.global_position) >= (min_tiles + 2.0) * C.TILE:
			return p
		best = p
	return best


func _portal(pos: Vector2, unit: String) -> void:
	var cost := _cost([unit])
	pending += 1
	pending_tp += cost
	game.fx.portal(pos, PORTAL_TIME)
	Sfx.play("portal", randf_range(-2.0, 2.0) - (6.0 if unit == "forgewarden" else 0.0), -12.0)
	# A Timer child dies with the director, so a restart mid-portal can't spawn into a freed scene.
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = PORTAL_TIME
	add_child(t)
	t.timeout.connect(func() -> void:
		t.queue_free()
		pending -= 1
		pending_tp -= cost
		if game.dead:
			return
		var e: Enemy
		match unit:
			"linesman":
				e = Linesman.new()
			"forgewarden":
				e = Forgewarden.new()
			_:
				e = Clinker.new()
		e.game = game
		e.position = pos
		game.world.add_child(e))
	t.start()


func alive_tp() -> int:
	var tp := pending_tp
	for e in get_tree().get_nodes_in_group("enemies"):
		tp += e.tp
	return tp


func _physics_process(delta: float) -> void:
	if game.dead:
		return
	if not active:
		return
	room_time += delta
	wave_timer -= delta
	var tp := alive_tp()
	if wave < waves.size():
		if tp < wave_tp * 0.25 or wave_timer <= 0.0:
			_spawn_wave()
	elif tp == 0 and pending == 0:
		active = false
		clear_times.append(room_time)
		game.on_room_cleared(room_time)
