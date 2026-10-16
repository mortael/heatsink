extends Node
## Staged screenshots of the three Frames: the Frame cards, the Codex page, and each weapon in action
## (Furnace swing, shockwave, Molten pool and Slag Shield; Arclight beam, chains, forks and Static Pylon).
## Needs a real renderer, not --headless:
## xvfb-run godot --rendering-driver opengl3 --path . --fixed-fps 60 res://tests/frame_shots.tscn -- <shot_dir>

var frame := 0
var shot_dir := "user://shots"
var menu: MainMenu
var game: Node
var stage := 0
var stage_frame := 0
var frames_left: Array[String] = ["riveter", "furnace", "arclight"]
var current := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		shot_dir = args[0]
	shot_dir = ProjectSettings.globalize_path(shot_dir)
	if shot_dir.is_relative_path():
		shot_dir = OS.get_environment("PWD").path_join(shot_dir)
	DirAccess.make_dir_recursive_absolute(shot_dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	seed(11)
	Settings.frame = "furnace"
	menu = load("res://menu.tscn").instantiate()
	add_child(menu)


func _process(_delta: float) -> void:
	frame += 1
	if menu != null:
		match frame:
			10:
				menu._show_frames()
			30:
				_shot("frame_cards")
				menu.frames.visible = false
				menu._show_codex()
				menu.codex.show_page(1)
			45:
				_shot("codex_frames")
				menu.codex.scroll.scroll_vertical = 420
			55:
				_shot("codex_frames_scrolled")
				menu.queue_free()
				menu = null
				_next_frame()
		return
	stage_frame += 1
	_run_stage()


func _next_frame() -> void:
	if game != null:
		game.queue_free()
		game = null
	if frames_left.is_empty():
		get_tree().quit(0)
		return
	current = frames_left.pop_front()
	Settings.frame = current
	game = load("res://main.tscn").instantiate()
	add_child(game)
	stage = 0
	stage_frame = 0


func _run_stage() -> void:
	var p: Player = game.player
	match stage_frame:
		5:
			game.director.active = false
			for c in game.director.get_children():
				c.queue_free()
			for e in get_tree().get_nodes_in_group("enemies"):
				e.queue_free()
			p.bot = true
			p.position = game.room.center() + Vector2(-3.5, 0) * C.TILE
		10:
			# A pack in front, close enough for the maul and spread out for the beam's chains.
			var near := 1.2 if current == "furnace" else 3.5
			for off in [Vector2(near, 0), Vector2(near + 0.6, -1.4), Vector2(near + 0.6, 1.4), Vector2(near + 2.6, -0.5), Vector2(near + 2.8, 1.6), Vector2(near + 1.8, -2.6)]:
				var e := Clinker.new()
				e.game = game
				e.max_hp = 4000.0
				e.position = p.position + off * C.TILE
				game.world.add_child(e)
		12:
			for e in get_tree().get_nodes_in_group("enemies"):
				e.set_physics_process(false) # hold still for the camera (they keep their collision)
			p.bot_aim = Vector2.RIGHT
			p.bot_fire = true
			p.heat.value = 30.0
		40:
			_shot(current + "_warm")
		60:
			p.heat.set_value(82.0)
		64:
			_shot(current + "_hot")
		68:
			_shot(current + "_hot_b")
		78:
			_shot(current + "_hot_c")
		90:
			p.bot_fire = false
			p.heat.set_value(92.0)
			p.vent_cd = 0.0
			p.bot_vent = true
		94:
			_shot(current + "_vent")
		130:
			p.position += Vector2(-0.8, 0) * C.TILE
			_shot(current + "_after_vent")
		140:
			_next_frame()


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [shot_dir, name])
