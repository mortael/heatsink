extends Node
## Staged screenshots for the lighting: rivet tracers crossing a live Linesman beam, a full Vent
## next to the pillars of the first room, then the open doors. Needs a real renderer, not --headless:
## xvfb-run godot --rendering-driver opengl3 --path . --fixed-fps 60 res://tests/lighting_shots.tscn -- <shot_dir>

var game: Node
var frame := 0
var shot_dir := "user://shots"
var linesman: Node2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		shot_dir = args[0]
	shot_dir = ProjectSettings.globalize_path(shot_dir)
	if shot_dir.is_relative_path():
		shot_dir = OS.get_environment("PWD").path_join(shot_dir)
	var err := DirAccess.make_dir_recursive_absolute(shot_dir)
	if err != OK:
		push_error("lighting shots: cannot create %s (error %d)" % [shot_dir, err])
		get_tree().quit(1)
		return
	seed(7)
	game = load("res://main.tscn").instantiate()
	add_child(game)


func _physics_process(_delta: float) -> void:
	frame += 1
	var t := C.TILE
	var p: Player = game.player
	match frame:
		2:
			game.director.active = false
			for c in game.director.get_children():
				c.queue_free() # pending portals
			for e in get_tree().get_nodes_in_group("enemies"):
				e.queue_free()
		152:
			game.fx.clear()
			p.bot = true
			p.position = Vector2(9 * t, 6.5 * t)
			linesman = _spawn(Linesman.new(), Vector2(14.5 * t, 2.3 * t))
			var partner := _spawn(Clinker.new(), Vector2(14.5 * t, 10.7 * t))
			linesman.partner = partner
			linesman.tether = Linesman.T.BEAM
			linesman.tether_t = 2.0
		153:
			for e in get_tree().get_nodes_in_group("enemies"):
				e.process_mode = Node.PROCESS_MODE_DISABLED
				e.propagate_call("queue_redraw")
			linesman._update_beam_light()
			p.bot_aim = Vector2(1, -0.12)
			p.bot_fire = true
		200:
			_shot("combat")
			p.bot_fire = false
		205:
			linesman.tether = Linesman.T.IDLE
			linesman.partner = null
			linesman._update_beam_light()
			linesman.propagate_call("queue_redraw")
		240:
			p.heat.value = 95.0
			p.vent_cd = 0.0
			p.bot_vent = true
		243:
			_shot("vent_a")
		248:
			_shot("vent_b")
		256:
			_shot("vent_c")
			p.position = Vector2(12 * t, 4.5 * t)
			p.bot_aim = Vector2(0, -1)
			game._open_doors()
		300:
			_shot("doors")
			get_tree().quit(0)


func _spawn(e: Enemy, pos: Vector2) -> Enemy:
	e.game = game
	e.position = pos
	game.world.add_child(e)
	return e


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shot_dir, name])
