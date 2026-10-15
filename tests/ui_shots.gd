extends Node
## Staged screenshots for the Vent ring on the Sink, the FPS counter and the Codex.
## Needs a real renderer, not --headless:
## xvfb-run godot --rendering-driver opengl3 --path . --fixed-fps 60 res://tests/ui_shots.tscn -- <shot_dir>

var frame := 0
var shot_dir := "user://shots"
var menu: MainMenu
var game: Node
var _flash_taken := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		shot_dir = args[0]
	shot_dir = ProjectSettings.globalize_path(shot_dir)
	if shot_dir.is_relative_path():
		shot_dir = OS.get_environment("PWD").path_join(shot_dir)
	DirAccess.make_dir_recursive_absolute(shot_dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	seed(7)
	Settings.show_fps = true
	menu = load("res://menu.tscn").instantiate()
	add_child(menu)


func _process(_delta: float) -> void:
	frame += 1
	if not _flash_taken and game != null and frame > 200 and game.player.vent_ready_flash > 0.0 and game.player.vent_ready_flash < 0.6:
		_flash_taken = true
		_shot("vent_ready_flash")
		_zoom("vent_ready_flash_zoom")
	match frame:
		20:
			_shot("menu")
			menu._show_codex()
		40, 50, 60, 70, 80:
			var i := (frame - 40) / 10
			if i > 0:
				menu.codex.show_page(i)
		45, 55, 65, 75, 85:
			_shot("codex_%d" % ((frame - 45) / 10))
		90:
			menu.codex.show_page(2)
			menu.codex.scroll.scroll_vertical = 900
		95:
			_shot("codex_2_scrolled")
			menu.queue_free()
			game = load("res://main.tscn").instantiate()
			add_child(game)
		100:
			game.director.active = false
			for c in game.director.get_children():
				c.queue_free()
			for e in get_tree().get_nodes_in_group("enemies"):
				e.queue_free()
			game.player.bot = true
		110:
			game.player.heat.value = 70.0
			game.player.bot_vent = true
		200:
			_shot("vent_cooldown")
			_zoom("vent_cooldown_zoom")
		520:
			_zoom("vent_ready_zoom")
			game.pause_menu.open()
		530:
			game.pause_menu.codex_button.pressed.emit()
		545:
			_shot("pause_codex")
			game.pause_menu.codex.close()
			game.pause_menu.settings_button.pressed.emit()
		555:
			_shot("pause_settings")
			get_tree().quit(0)


func _img() -> Image:
	return get_viewport().get_texture().get_image()


func _shot(name: String) -> void:
	_img().save_png("%s/%s.png" % [shot_dir, name])


## A close-up of the Sink, scaled up 3x.
func _zoom(name: String) -> void:
	var img := _img()
	var p: Vector2 = game.player.get_global_transform_with_canvas().origin
	var r := Rect2i(Vector2i(p) - Vector2i(80, 80), Vector2i(160, 160))
	var crop := img.get_region(r)
	crop.resize(480, 480, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [shot_dir, name])
