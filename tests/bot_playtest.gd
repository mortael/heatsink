extends Node
## Automated playtest: a simple bot plays the prototype and reports clear times and deaths.
## Run: godot --headless --path . --fixed-fps 60 res://tests/bot_playtest.tscn -- [seconds] [seed] [mode] [shot_dir]
## mode: "x" normal, "passive" stands still, "allitems" starts with every item (stress test),
## "slagged" starts with the three Slagged items, "elite" always takes an Elite door when one is offered,
## "forge" starts with Tinder Rounds and 3 Cores so the Anvil can force a Fusion. Between fights the bot shops, rests, gambles
## and walks through a random door, so a long run exercises the whole Stratum route.
## Add "diff=N" anywhere after the seconds (0 COLD .. 4 MELTDOWN, default 1 WARM) to play a difficulty level,
## and "frame=riveter|furnace|arclight" to pick the Frame (default Riveter). The bot fights the way each Frame wants:
## the Riveter and the Arclight keep their distance, the Furnace walks into melee range.

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
	var args := Array(OS.get_cmdline_user_args())
	Settings.frame = Frames.DEFAULT # never the Frame saved by the last menu session
	for a: String in args.duplicate():
		if a.begins_with("diff="):
			Settings.difficulty = Difficulty.clamp_level(int(a.substr(5)))
			args.erase(a)
		elif a.begins_with("frame="):
			Settings.frame = Frames.clamp_id(a.substr(6))
			args.erase(a)
	if args.size() > 0:
		max_frames = int(args[0]) * 60
	if args.size() > 1:
		seed(int(args[1]))
	process_mode = Node.PROCESS_MODE_ALWAYS # keep running while the reward picker pauses the game
	passive = args.size() > 2 and args[2] == "passive"
	all_items = args.size() > 2 and args[2] == "allitems"
	slagged = args.size() > 2 and args[2] == "slagged"
	elite_mode = args.size() > 2 and args[2] == "elite"
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
		if not game.inventory.fits(id):
			continue
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
		if e is Sparkhound and (e as Sparkhound).state == Sparkhound.S.AIM and (e as Sparkhound).t < 0.3 and _in_lane(p.global_position, e.global_position, (e as Sparkhound).rush_lane(), 34.0):
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
	var strafe := to_e.normalized().orthogonal() * 0.6
	var home := (centre - p.global_position) / 400.0
	if p.frame == "furnace":
		# Walk into the pack and swing; back off a step from a Forgewarden's front.
		var reach: float = SlagMaul.REACH + nearest.radius
		var want: float = reach * (0.8 if not nearest is Forgewarden else 0.95)
		var close_in := to_e.normalized() if nd > want else -to_e.normalized() * 0.4
		p.bot_move = close_in + strafe * 0.7 + home * 0.5
		p.bot_fire = nd < reach + 0.6 * C.TILE and not (p.heat.value >= 88.0 and p.vent_cd > 0.0)
	else:
		# Keep ~4 tiles away (the Arclight a little more, its beam reaches 7), strafe, drift toward the centre.
		var keep := (6.0 if nearest is Forgewarden else (4.5 if p.frame == "arclight" else 4.0)) * C.TILE
		var away := -to_e.normalized() if nd < keep else to_e.normalized() * 0.3
		p.bot_move = away + strafe + home
		# Heat management: stop firing near the cap if Vent isn't ready.
		var cap := 90.0 if p.frame == "arclight" else 92.0
		p.bot_fire = not (p.heat.value >= cap and p.vent_cd > 0.0)
		if p.frame == "arclight" and nd > CoilLance.RANGE * 1.1:
			p.bot_fire = false
	if p.heat.band == Heat.Band.HOT and p.bot_fire:
		overdrive_shots += 1
	# The Furnace Vents as soon as it is Hot with enemies close, to keep its Slag Shield up.
	var furnace_vent := p.frame == "furnace" and p.heat.value >= Player.SLAG_SHIELD_AT and close >= 1 and p.shield <= 0.0
	if p.vent_cd <= 0.0 and (furnace_vent or p.heat.value >= 85.0 or (close >= 4 and p.heat.value >= 40.0)):
		p.bot_vent = true
		if vent_shot_at < frames:
			vent_shot_at = frames + 5
	if passive:
		p.bot_move = Vector2.ZERO
		p.bot_vent = false
		return
	# The Furnace answers a Clinker's windup by smashing it first when it is in reach.
	if threat != null and p.frame == "furnace" and threat is Clinker and p.global_position.distance_to(threat.global_position) < SlagMaul.REACH + threat.radius and not p.heat.is_overheated():
		p.bot_aim = threat.global_position - p.global_position
		p.bot_fire = true
		threat = null
	# In melee range of a Forgewarden the Furnace keeps one dash for its Hammerfall ring.
	var reserve := 1 if p.frame == "furnace" and enemies.any(func(e: Node) -> bool: return e is Forgewarden) else 0
	if threat != null and p.dash_charges > reserve and p.dash_time <= 0.0:
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
	for s in get_tree().get_nodes_in_group("mortar_shells"):
		var tgt: Vector2 = s.target
		if pos.distance_to(tgt) < SlagMortar.MortarShell.RADIUS + 26.0:
			away += (pos - tgt).normalized() * 2.0 if pos.distance_to(tgt) > 1.0 else Vector2.RIGHT * 2.0
	for b in get_tree().get_nodes_in_group("enemy_bolts"):
		var bolt: SlagBolt = b
		var to := pos - bolt.global_position
		if to.length() < 3.5 * C.TILE and to.dot(bolt.vel) > 0.0:
			var dir := bolt.vel.normalized()
			var miss := to - dir * to.dot(dir)
			if miss.length() < SlagBolt.RADIUS + Player.RADIUS + 10.0:
				away += (miss.normalized() if miss.length() > 0.5 else dir.orthogonal()) * 1.5
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Sparkhound:
			var h: Sparkhound = e
			if h.state == Sparkhound.S.AIM and _in_lane(pos, h.global_position, h.rush_lane(), 40.0):
				var side := h.facing.orthogonal()
				away += (side if side.dot(pos - h.global_position) >= 0.0 else -side) * 2.0
	for m in game.world.get_children():
		if m is MoltenPatch and pos.distance_to(m.global_position) < MoltenPatch.RADIUS + 30.0:
			away += (pos - m.global_position).normalized()
	if away == Vector2.ZERO and not dash:
		return
	dodges += 1
	p.bot_move = away.normalized() if away != Vector2.ZERO else p.bot_move
	if dash and p.dash_charges > 0 and p.dash_time <= 0.0:
		p.bot_dash = true


## True when pos sits within width of the segment from start along lane.
func _in_lane(pos: Vector2, start: Vector2, lane: Vector2, width: float) -> bool:
	var c := Geometry2D.get_closest_point_to_segment(pos, start, start + lane)
	return c.distance_to(pos) < width


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
	var peds: Array = game.pedestals
	match game.room_kind:
		"shop":
			var items := peds.filter(func(q: Pedestal) -> bool: return q.kind == "item")
			items.sort_custom(func(a: Pedestal, b: Pedestal) -> bool: return a.price > b.price)
			out.append_array(items)
			if p.pips < p.max_pips:
				out.push_front(peds.filter(func(q: Pedestal) -> bool: return q.kind == "repair")[0])
		"vault":
			var kind := "vault_repair" if p.pips < p.max_pips - 1 or game.cores == 0 else "anvil"
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
		if o.begins_with("forge:") or (not o.contains(":") and inv.completes_fusion(o) != ""):
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
	print("frame: %s  difficulty: %s" % [p.frame, Difficulty.level_name()])
	print("sim time: %.1fs  died: %s" % [frames / 60.0, game.dead])
	print("rooms cleared: %d  current room: %d" % [times.size(), game.run.index])
	print("clear times: %s" % str(times.map(func(t: float) -> String: return "%.1f" % t)))
	print("avg clear: %.1fs" % avg)
	print("kills: %d  pips left: %d/%d" % [game.kills, p.pips, p.max_pips])
	var attacks := p.shots_fired
	if p.maul != null:
		attacks = p.maul.swings
	elif p.lance != null:
		attacks = p.lance.ticks
	print("attacks: %d  vents: %d  overheats: %d  reached Hot: %s  shields used: %d" % [attacks, p.vents, p.heat.overheat_count, min_heat_seen_hot, p.shields_used])
	print("hit-stop frames total: %d" % Juice.total_hitstop_frames)
	print("picks: %d  items: %s" % [picks, str(game.inventory.owned)])
	print("fusions: %s" % str(game.inventory.fusions))
	print("route: %s" % str(game.run.visited))
	print("scrap: %d  max pips: %d  used: %s  victory: %s" % [game.scrap, p.max_pips, str(used), game.victory])
	print("pips lost by source: %s" % str(hits))
	print("elites: %d  cores: %d  tempered: %s  forged: %s  frames spent dodging: %d" % [game.elites_killed, game.cores, str(game.inventory.tempered), str(game.inventory.forged), dodges])
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
		elif e is Sparkhound and (e as Sparkhound).state == Sparkhound.S.AIM and (e as Sparkhound).t < 0.25:
			_save("sparkhound_rush")
		elif e is Slagspitter and (e as Slagspitter).state == Slagspitter.S.AIM and (e as Slagspitter).t < 0.25:
			_save("slagspitter_fan")
		elif e is SlagMortar and get_tree().get_nodes_in_group("mortar_shells").any(func(m: Node) -> bool: return m.progress() > 0.6):
			_save("slag_mortar_shell")
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
