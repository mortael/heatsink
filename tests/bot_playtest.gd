extends Node
## Automated playtest: a simple bot plays the prototype and reports clear times and deaths.
## Run: godot --headless --path . --fixed-fps 60 res://tests/bot_playtest.tscn -- [seconds] [seed] [mode] [shot_dir]
## mode: "x" normal, "passive" stands still, "allitems" starts with every item (stress test),
## "slagged" starts with the three Slagged items. Between fights the bot shops, rests, gambles
## and walks through a random door, so a long run exercises the whole Stratum route.

var game: Node
var frames := 0
var max_frames := 60 * 240
var report_done := false
var min_heat_seen_hot := false
var overdrive_shots := 0
var passive := false
var shot_dir := ""
var last_shot := -1000
var shots := 0
var vent_shot_at := -1
var all_items := false
var picks := 0
var picker_frames := 0
var slagged := false
var plan: Array = [] # pedestals to use in the current room
var plan_room := -1
var door_pick := -1
var used := {} # pedestal kind -> times used this run
var room_shots := {} # name -> true once saved
var room_seen_at := 0
var room_seen := -1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		max_frames = int(args[0]) * 60
	if args.size() > 1:
		seed(int(args[1]))
	process_mode = Node.PROCESS_MODE_ALWAYS # keep running while the reward picker pauses the game
	passive = args.size() > 2 and args[2] == "passive"
	all_items = args.size() > 2 and args[2] == "allitems"
	slagged = args.size() > 2 and args[2] == "slagged"
	if args.size() > 3:
		shot_dir = args[3]
	game = load("res://main.tscn").instantiate()
	add_child(game)
	for id: String in ItemDB.ITEMS:
		if (all_items and not ItemDB.is_slagged(id)) or (slagged and ItemDB.is_slagged(id)):
			game.inventory.add(id)


func _process(_delta: float) -> void:
	frames += 1
	if game.get("picker") == null:
		push_error("game failed to start")
		get_tree().quit(1)
		return
	if report_done or game.player == null:
		return
	var p: Player = game.player
	if game.picker.is_open:
		picker_frames += 1
		if picker_frames == 6 and shot_dir != "" and picks == 1:
			get_viewport().get_texture().get_image().save_png("%s/picker.png" % shot_dir)
		if picker_frames == 6 and shot_dir != "" and game.room_kind == "wager":
			_save("wager_picker")
		if picker_frames >= 10:
			picker_frames = 0
			_pick()
		return
	p.bot = true
	_bot(p)
	if p.heat.band == Heat.Band.HOT:
		min_heat_seen_hot = true
	if shot_dir != "":
		_maybe_shot(p)
		_room_shot(p)
	if game.dead or game.victory or frames >= max_frames:
		report_done = true
		if shot_dir != "" and game.victory:
			for i in 90:
				await get_tree().process_frame
			_save("victory")
		if shot_dir != "" and game.dead:
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/death_ledger.png" % shot_dir)
		_report(p)
		# An active bot that never clears a room means the game loop is broken.
		get_tree().quit(1 if not passive and game.director.clear_times.is_empty() else 0)


func _bot(p: Player) -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var nd := INF
	var close := 0
	var threat: Node2D = null
	for e in enemies:
		var d: float = p.global_position.distance_to(e.global_position)
		if d < nd:
			nd = d
			nearest = e
		if d < 3.0 * C.TILE:
			close += 1
		if e is Clinker and (e as Clinker).state == Clinker.S.WINDUP and d < 2.6 * C.TILE:
			threat = e
	var centre: Vector2 = game.room.center()
	if nearest == null:
		p.bot_fire = false
		if passive:
			p.bot_move = Vector2.ZERO
			return
		_explore(p)
		return
	# Shoot the nearest enemy we can see; if walls hide them all, go find one.
	var seen: Node2D = null
	var sd := INF
	for e in enemies:
		var d: float = p.global_position.distance_to(e.global_position)
		if d < sd and game.room.has_los(p.global_position, e.global_position, 3.0):
			sd = d
			seen = e
	if seen == null:
		p.bot_fire = false
		_walk(p, nearest.global_position)
		return
	nearest = seen
	nd = sd
	var to_e := nearest.global_position - p.global_position
	p.bot_aim = to_e
	# Keep ~4 tiles away, strafe, and drift toward the centre to avoid corners.
	var away := -to_e.normalized() if nd < 4.0 * C.TILE else to_e.normalized() * 0.3
	var strafe := to_e.normalized().orthogonal() * 0.6
	var home := (centre - p.global_position) / 400.0
	p.bot_move = away + strafe + home
	# Heat management: stop firing near the cap if Vent isn't ready.
	p.bot_fire = not (p.heat.value >= 92.0 and p.vent_cd > 0.0)
	if p.heat.band == Heat.Band.HOT and p.bot_fire:
		overdrive_shots += 1
	if p.vent_cd <= 0.0 and (p.heat.value >= 85.0 or (close >= 4 and p.heat.value >= 40.0)):
		p.bot_vent = true
		if vent_shot_at < frames:
			vent_shot_at = frames + 5
	if passive:
		p.bot_move = Vector2.ZERO
		p.bot_vent = false
		return
	if threat != null and p.dash_charges > 0 and p.dash_time <= 0.0:
		p.bot_move = (p.global_position - threat.global_position).normalized().orthogonal()
		p.bot_dash = true


## Between fights: use the room's pedestals, then walk to a door.
func _explore(p: Player) -> void:
	if game.run.index != plan_room:
		plan_room = game.run.index
		door_pick = -1
		plan = _make_plan(p)
	while not plan.is_empty() and (not is_instance_valid(plan[0]) or not plan[0].active or plan[0].price > game.scrap):
		plan.pop_front()
	if not plan.is_empty():
		var ped: Pedestal = plan[0]
		if ped.near:
			p.bot_move = Vector2.ZERO
			p.bot_interact = true
			used[ped.kind] = used.get(ped.kind, 0) + 1
			plan.pop_front()
			return
		_walk(p, ped.global_position)
		return
	var open: Array = game.doors.filter(func(d: Door) -> bool: return d.open)
	if open.is_empty():
		p.bot_move = Vector2.ZERO
		return
	if door_pick < 0 or door_pick >= open.size():
		door_pick = randi() % open.size()
	_walk(p, open[door_pick].global_position + Vector2(0, 2))


func _make_plan(p: Player) -> Array:
	var out: Array = []
	var peds: Array = game.pedestals
	match game.room_kind:
		"shop":
			var items := peds.filter(func(q: Pedestal) -> bool: return q.kind == "item")
			items.sort_custom(func(a: Pedestal, b: Pedestal) -> bool: return a.price > b.price)
			out.append_array(items)
			if p.pips < p.max_pips:
				out.push_front(peds.filter(func(q: Pedestal) -> bool: return q.kind == "repair")[0])
		"vault":
			var kind := "vault_repair" if p.pips < p.max_pips or p.max_pips <= 4 else "altar"
			out.append_array(peds.filter(func(q: Pedestal) -> bool: return q.kind == kind))
		"wager":
			if not game.inventory.owned.is_empty():
				out.append_array(peds.filter(func(q: Pedestal) -> bool: return q.kind == "crucible"))
			if p.max_pips >= 5 and randf() < 0.5:
				out.append_array(peds.filter(func(q: Pedestal) -> bool: return q.kind == "coinflip"))
	return out


func _walk(p: Player, target: Vector2) -> void:
	var route: Array[Vector2] = game.room.path(p.global_position, target)
	if route.is_empty():
		p.bot_move = (target - p.global_position).normalized()
		return
	var wp: Vector2 = route[0]
	if route.size() > 1 and p.global_position.distance_to(wp) < 10.0:
		wp = route[1]
	p.bot_move = (wp - p.global_position).normalized()


func _pick() -> void:
	var inv: Inventory = game.inventory
	var best := 0
	for i in game.picker.options.size():
		if inv.completes_fusion(game.picker.options[i]) != "":
			best = i
	picks += 1
	game.picker.choose(best)


func _report(p: Player) -> void:
	var d: Director = game.director
	var times: Array[float] = d.clear_times
	var avg := 0.0
	for t in times:
		avg += t
	if times.size() > 0:
		avg /= times.size()
	print("=== BOT PLAYTEST ===")
	print("sim time: %.1fs  died: %s" % [frames / 60.0, game.dead])
	print("rooms cleared: %d  current room: %d" % [times.size(), game.run.index])
	print("clear times: %s" % str(times.map(func(t: float) -> String: return "%.1f" % t)))
	print("avg clear: %.1fs" % avg)
	print("kills: %d  pips left: %d/%d" % [game.kills, p.pips, p.max_pips])
	print("shots: %d  vents: %d  overheats: %d  reached Hot: %s" % [p.shots_fired, p.vents, p.heat.overheat_count, min_heat_seen_hot])
	print("hit-stop frames total: %d" % Juice.total_hitstop_frames)
	print("picks: %d  items: %s" % [picks, str(game.inventory.owned)])
	print("fusions: %s" % str(game.inventory.fusions))
	print("route: %s" % str(game.run.visited))
	print("scrap: %d  max pips: %d  used: %s  victory: %s" % [game.scrap, p.max_pips, str(used), game.victory])
	var cursed: Array = game.inventory.owned.filter(func(id: String) -> bool: return ItemDB.is_slagged(id))
	if not cursed.is_empty():
		print("slagged: %s  absolution: %s  absolved: %s" % [str(cursed), str(game.inventory.absolution), str(game.inventory.absolved_ids)])
	if game.dead:
		print("ledger: %s" % str(game.ledger_lines()))
	var left := get_tree().get_nodes_in_group("enemies")
	if not left.is_empty():
		print("enemies left: %d  first at %s  player at %s  pending portals: %d" % [left.size(), str(left[0].global_position), str(p.global_position), game.director.pending])


## One screenshot per room type (shortly after entering), plus the first open doors.
func _room_shot(p: Player) -> void:
	if game.run.index != room_seen:
		room_seen = game.run.index
		room_seen_at = frames
	var kind: String = game.room_kind
	if frames - room_seen_at == 50 and not RunMap.is_combat(kind):
		_save(kind)
	if RunMap.is_combat(kind) and not game.doors.is_empty() and game.doors[0].open and game.doors.size() >= 2 and not room_shots.has("doors"):
		if p.global_position.y < 7.0 * C.TILE:
			_save("doors")
	# Stand next to a pedestal long enough to see its card.
	for ped: Pedestal in game.pedestals:
		if ped.near and ped.kind == "item" and not room_shots.has("shop_card"):
			_save("shop_card")


func _save(name: String) -> void:
	if room_shots.has(name):
		return
	room_shots[name] = true
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shot_dir, name])


func _maybe_shot(p: Player) -> void:
	if shots >= 8 or frames - last_shot < 200:
		return
	if frames == vent_shot_at:
		shots += 1
		get_viewport().get_texture().get_image().save_png("%s/vent_%02d.png" % [shot_dir, shots])
		return
	var n := get_tree().get_nodes_in_group("enemies").size()
	var interesting: bool = n >= 5 and (game.fx.rings.size() > 0 and game.fx.parts.size() > 25 or p.heat.band == Heat.Band.HOT)
	if game.dead:
		interesting = true
	if interesting:
		last_shot = frames
		shots += 1
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%02d.png" % [shot_dir, shots])
