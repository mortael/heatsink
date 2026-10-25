extends Node
## Smoke test for the menus: title screen -> Settings -> Codex -> Start -> run -> pause -> Main menu.
## Run: python tests/run_headless.py res://tests/menu_test.tscn

const TestEnvironment = preload("res://tests/test_environment.gd")

var step := 0
var wait := 0
var tree: SceneTree
var paused: bool:
	get: return tree.paused


func _ready() -> void:
	tree = get_tree()
	if not TestEnvironment.is_isolated():
		_fail("run through tests/run_headless.py so menu navigation cannot overwrite player settings")
		return
	if ProjectSettings.get_setting("application/run/main_scene") != "res://menu.tscn":
		_fail("the game's start scene is not the main menu")
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Hand "current scene" to a stand-in so changing scenes frees that and leaves this test running.
	var stand_in := Node.new()
	tree.root.add_child.call_deferred(stand_in)
	(func() -> void:
		tree.current_scene = stand_in
		tree.change_scene_to_file("res://menu.tscn")).call_deferred()


func quit(code: int) -> void:
	tree.quit(code)


func _fail(msg: String) -> void:
	push_error("menu test: " + msg)
	quit(1)


func _process(_delta: float) -> void:
	_step()


func _step() -> bool:
	wait += 1
	if wait < 5:
		return false
	wait = 0
	var scene := tree.current_scene
	match step:
		0:
			if not scene is MainMenu:
				_fail("game did not open on the main menu")
				return true
			if scene.get_viewport().gui_get_focus_owner() != scene.start_button:
				_fail("Start is not focused, so keys and pads can't use the menu")
				return true
			scene.settings_button.pressed.emit()
		1:
			if not scene.settings.visible or scene.buttons.visible:
				_fail("Settings did not open")
				return true
			scene.settings.close()
		2:
			if not scene.buttons.visible:
				_fail("Back did not return to the menu")
				return true
			scene.codex_button.pressed.emit()
		3:
			if not scene.codex.visible or scene.buttons.visible:
				_fail("Codex did not open")
				return true
			for i in CodexPanel.PAGES.size():
				scene.codex.show_page(i)
				if scene.codex.text.get_parsed_text().length() < 200:
					_fail("Codex page %s is empty" % CodexPanel.PAGES[i])
					return true
			scene.codex.close()
		4:
			if not scene.buttons.visible or scene.get_viewport().gui_get_focus_owner() != scene.codex_button:
				_fail("Back from the Codex did not return to the menu")
				return true
			scene.start_button.pressed.emit()
		5:
			if scene == null or scene.name != "Game":
				_fail("Start did not begin a run")
				return true
			var ev := InputEventAction.new()
			ev.action = "pause"
			ev.pressed = true
			Input.parse_input_event(ev)
		6:
			if not scene.pause_menu.is_open or not paused:
				_fail("Esc did not pause the run")
				return true
			scene.pause_menu.menu_button.pressed.emit()
		7:
			if not scene is MainMenu or paused:
				_fail("Main menu button did not return to an unpaused title screen")
				return true
			print("menu test: ok")
			quit(0)
			return true
	step += 1
	return false
