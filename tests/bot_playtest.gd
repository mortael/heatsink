extends Node
## Automated playtest: a simple bot plays the prototype and reports clear times and deaths.
## Run: godot --headless --path . --fixed-fps 60 res://tests/bot_playtest.tscn -- [seconds] [seed] [mode] [shot_dir]
## mode: "x" normal, "passive" stands still, "allitems" starts with every item (stress test).

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


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		max_frames = int(args[0]) * 60
	if args.size() > 1:
		seed(int(args[1]))
	process_mode = Node.PROCESS_MODE_ALWAYS # keep running while the reward picker pauses the game
	passive = args.size() > 2 and args[2] == "passive"
	all_items = args.size() > 2 and args[2] == "allitems"
	if args.size() > 3:
		shot_dir = args[3]
	game = load("res://main.tscn").instantiate()
	add_child(game)
	if all_items:
		for id: String in ItemDB.ITEMS:
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
	if game.dead or frames >= max_frames:
		report_done = true
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
		p.bot_move = (centre - p.global_position) / 200.0
		return
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
	print("rooms cleared: %d  current room: %d" % [times.size(), d.room_index])
	print("clear times: %s" % str(times.map(func(t: float) -> String: return "%.1f" % t)))
	print("avg clear: %.1fs" % avg)
	print("kills: %d  pips left: %d/%d" % [game.kills, p.pips, Player.MAX_PIPS])
	print("shots: %d  vents: %d  overheats: %d  reached Hot: %s" % [p.shots_fired, p.vents, p.heat.overheat_count, min_heat_seen_hot])
	print("hit-stop frames total: %d" % Juice.total_hitstop_frames)
	print("picks: %d  items: %s" % [picks, str(game.inventory.owned)])
	print("fusions: %s" % str(game.inventory.fusions))
	if game.dead:
		print("ledger: %s" % str(game.ledger_lines()))


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
