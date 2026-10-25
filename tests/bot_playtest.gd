extends Node
## Automated playtest: a simple bot plays the prototype and reports clear times and deaths.
## Run: godot --headless --path . --fixed-fps 60 res://tests/bot_playtest.tscn -- [seconds] [seed] [mode] [shot_dir]
## mode: "x" normal, "passive" stands still, "allitems" starts with every item (stress test),
## "slagged" starts with the three Slagged items, "elite" always takes an Elite door when one is offered,
## "forge" starts with Tinder Rounds, 3 Cores and an Anvil choice before random drops can finish the recipe. Between fights the bot shops, rests, gambles
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
var elite_mode := false
var forge_mode := false
var forced_fusion_observed := false
var dodges := 0
var hits := {} # damage source -> pips lost
var last_pips := -1
var last_max := -1
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
	elite_mode = args.size() > 2 and args[2] == "elite"
	forge_mode = args.size() > 2 and args[2] == "forge"
	if args.size() > 3:
		shot_dir = args[3]
	game = load("res://main.tscn").instantiate()
	add_child(game)
	if all_items:
		game.cores = 4 # exercise the Anvil
	if args.size() > 2 and args[2] == "forge":
		game.cores = 3 # exercise a Forced Fusion: Cluster Embers without Frag Lattice
		game.inventory.add("tinder_rounds")
	for id: String in ItemDB.ITEMS:
		if (all_items and not ItemDB.is_slagged(id)) or (slagged and ItemDB.is_slagged(id)):
			game.inventory.add(id)
	if forge_mode:
		# Pin the scenario's precondition, not its result: use the actual choice and payment path.
		var anvil := Pedestal.new()
		anvil.game = game
		anvil.kind = "anvil"
		anvil.position = game.player.position
		game.world.add_child(anvil)
		game.special_rooms.pedestals.append(anvil)
		game.use_pedestal(anvil)


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
		if picker_frames == 6 and shot_dir != "" and game.room_kind == "vault":
			_save("anvil_picker")
		if picker_frames == 6 and shot_dir != "" and game.room_kind == "elite":
			_save("elite_picker")
		if picker_frames >= 10:
			picker_frames = 0
			_pick()
		return
	p.bot = true
	if last_pips >= 0 and p.pips < last_pips and p.max_pips == last_max:
		hits[game.last_hit_source] = hits.get(game.last_hit_source, 0) + last_pips - p.pips
	last_pips = p.pips
	last_max = p.max_pips
	_bot(p)
	if not passive:
		_dodge(p)
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
		var success: bool = passive or (game.victory and game.run.index == RunMap.GATE and game.rooms_cleared >= 8)
		if elite_mode:
			success = success and game.elites_killed >= 2
		if forge_mode:
			success = success and forced_fusion_observed
		if all_items:
			success = success and game.inventory.fusions.size() == ItemDB.FUSIONS.size()
		if not success:
			push_error("Bot scenario failed: expected Gate victory and mode-specific progression before the frame limit")
		get_tree().quit(0 if success else 1)


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
	var keep := (6.0 if nearest is Forgewarden else 4.0) * C.TILE
	var away := -to_e.normalized() if nd < keep else to_e.normalized() * 0.3
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


## Reads the Forgewarden's and Linesman's telegraphs the way a player would and steps out of them.
func _dodge(p: Player) -> void:
	var pos := p.global_position
	var away := Vector2.ZERO
	var dash := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Forgewarden:
			var f: Forgewarden = e
			match f.state:
				Forgewarden.S.RAISE, Forgewarden.S.LEAP:
					var d := pos.distance_to(f.target)
					if d < Forgewarden.SLAM_RADIUS + 30.0:
						away += (pos - f.target).normalized() * 2.0 if d > 1.0 else Vector2.RIGHT * 2.0
				Forgewarden.S.SHOCK:
					var r := Forgewarden.RING_REACH * (1.0 - maxf(f.t, 0.0) / Forgewarden.RING_TIME)
					var d2 := pos.distance_to(f.global_position)
					if d2 > r and d2 - r < 60.0 and d2 < Forgewarden.RING_REACH + 20.0:
						dash = true
						away += (f.global_position - pos).normalized()
				Forgewarden.S.INHALE, Forgewarden.S.BREATH:
					var to := pos - f.global_position
					if to.length() < Forgewarden.CONE_REACH + 60.0 and absf(f.facing.angle_to(to)) < Forgewarden.CONE_HALF + 0.5:
						var side := f.facing.orthogonal()
						away += (side if side.dot(to) >= 0.0 else -side) * 2.0
		elif e is Linesman:
			var l: Linesman = e
			if l.tether != Linesman.T.IDLE and l.partner != null and is_instance_valid(l.partner):
				var c := Geometry2D.get_closest_point_to_segment(pos, l.global_position, l.partner.global_position)
				if c.distance_to(pos) < 50.0:
					away += (pos - c).normalized() * 1.5 if c.distance_to(pos) > 1.0 else Vector2.UP
	for m in game.world.get_children():
		if m is MoltenPatch and pos.distance_to(m.global_position) < MoltenPatch.RADIUS + 30.0:
			away += (pos - m.global_position).normalized()
	if away == Vector2.ZERO and not dash:
		return
	dodges += 1
	p.bot_move = away.normalized() if away != Vector2.ZERO else p.bot_move
	if dash and p.dash_charges > 0 and p.dash_time <= 0.0:
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
		if elite_mode:
			for i in open.size():
				if open[i].kind == "elite":
					door_pick = i
	_walk(p, open[door_pick].global_position + Vector2(0, 2))


func _make_plan(p: Player) -> Array:
	var out: Array = []
	var peds: Array = game.special_rooms.pedestals
	match game.room_kind:
		"shop":
			var items := peds.filter(func(q: Pedestal) -> bool: return q.kind == "item")
			items.sort_custom(func(a: Pedestal, b: Pedestal) -> bool: return a.price > b.price)
			out.append_array(items)
			if p.pips < p.max_pips:
				out.push_front(peds.filter(func(q: Pedestal) -> bool: return q.kind == "repair")[0])
		"vault":
			var can_force_fusion: bool = forge_mode and game.cores >= ItemDB.FORGE_COST and not game.inventory.forgeable().is_empty()
			var kind: String = "anvil" if can_force_fusion else ("vault_repair" if p.pips < p.max_pips - 1 or game.cores == 0 else "anvil")
			out.append_array(peds.filter(func(q: Pedestal) -> bool: return q.kind == kind))
			if p.max_pips >= 5:
				out.append_array(peds.filter(func(q: Pedestal) -> bool: return q.kind == "altar"))
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
		var o: String = game.picker.options[i]
		if o.begins_with("forge:") or (not o.contains(":") and inv.fusion_completed_by(o) != ""):
			best = i
	var selected: String = game.picker.options[best]
	picks += 1
	game.picker.choose(best)
	if forge_mode and selected.begins_with("forge:"):
		forced_fusion_observed = inv.forged.has(selected.trim_prefix("forge:"))


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
	print("pips lost by source: %s" % str(hits))
	print("elites: %d  cores: %d  tempered: %s  forged: %s  forced fusion observed: %s  frames spent dodging: %d" % [game.elites_killed, game.cores, str(game.inventory.tempered), str(game.inventory.forged), forced_fusion_observed, dodges])
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
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Forgewarden:
			var f: Forgewarden = e
			if f.state == Forgewarden.S.RAISE and f.t < 0.4:
				_save("forgewarden_hammerfall")
			elif f.state == Forgewarden.S.SHOCK and f.t < 0.3:
				_save("forgewarden_ring")
			elif f.state == Forgewarden.S.BREATH and f.t < 0.8:
				_save("forgewarden_breath")
			elif f.state == Forgewarden.S.INHALE and f.t < 0.5:
				_save("forgewarden_inhale")
		elif e is Linesman:
			var l: Linesman = e
			if l.beam_active():
				_save("linesman_beam")
			elif l.tether == Linesman.T.AIM:
				_save("linesman_aim")
	if game.doors.any(func(d: Door) -> bool: return d.open and d.kind == "elite") and p.global_position.y < 7.0 * C.TILE:
		_save("elite_door")
	if kind == "elite" and frames - room_seen_at == 70:
		_save("elite_room")
	# Stand next to a pedestal long enough to see its card.
	for ped: Pedestal in game.special_rooms.pedestals:
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
