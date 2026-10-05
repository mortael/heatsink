extends Node2D
## Root of the prototype: builds the room, player, camera, FX, HUD and director.

var world: Node2D
var room: Room
var fx: Fx
var player: Player
var camera: Camera2D
var hud: Hud
var director: Director
var inventory: Inventory
var picker: Picker

var dead := false
var kills := 0
var run_time := 0.0
var last_hit_source := ""
var last_hit_band := ""
var rooms_cleared := 0


func _ready() -> void:
	_setup_input()
	randomize()
	Juice.reset()
	get_tree().paused = false
	inventory = Inventory.new()
	inventory.game = self
	add_child(inventory)
	inventory.fusion_unlocked.connect(_on_fusion)
	world = Node2D.new()
	add_child(world)
	room = Room.new()
	world.add_child(room)
	fx = Fx.new()
	fx.z_index = 6
	world.add_child(fx)
	player = Player.new()
	player.game = self
	player.position = room.center()
	world.add_child(player)
	camera = Camera2D.new()
	camera.ignore_rotation = false
	camera.position = room.center() + Vector2(0, 10)
	add_child(camera)
	camera.make_current()
	Juice.camera = camera
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	director = Director.new()
	director.game = self
	add_child(director)
	picker = Picker.new()
	picker.game = self
	add_child(picker)
	picker.chosen.connect(_on_reward_chosen)
	director.start_room()


func offer_reward() -> void:
	picker.open(inventory.offer(3))


func _on_reward_chosen(id: String) -> void:
	inventory.add(id)
	director.start_room()


func _on_fusion(id: String) -> void:
	var f: Dictionary = ItemDB.FUSIONS[id]
	hud.banner("FUSION: " + f.name.to_upper(), f.desc)
	Sfx.play("fusion")
	Juice.add_trauma(0.3)


func _process(delta: float) -> void:
	if not dead:
		run_time += delta
	elif Input.is_action_just_pressed("restart"):
		Juice.reset()
		get_tree().reload_current_scene()


func on_enemy_killed(_e: Enemy) -> void:
	kills += 1


func on_room_cleared(_time: float) -> void:
	rooms_cleared += 1


func on_player_died() -> void:
	dead = true
	Juice.reset()
	Juice.add_trauma(0.5)


func ledger_lines() -> Array:
	var lines := []
	lines.append("Killed by %s" % last_hit_source)
	lines.append("Heat band at death: %s" % last_hit_band)
	if last_hit_band == "OVERHEAT":
		lines.append("Risk taken: overheated, so every hit cost +1 pip")
	lines.append("Room %d  ·  %d kills  ·  %d:%02d" % [director.room_index, kills, int(run_time) / 60, int(run_time) % 60])
	lines.append("Overheats this run: %d  ·  Vents: %d" % [player.heat.overheat_count, player.vents])
	return lines


func _setup_input() -> void:
	if InputMap.has_action("fire"):
		return # already registered (scene reload)
	_key_action("move_left", [KEY_A, KEY_LEFT])
	_key_action("move_right", [KEY_D, KEY_RIGHT])
	_key_action("move_up", [KEY_W, KEY_UP])
	_key_action("move_down", [KEY_S, KEY_DOWN])
	_key_action("dash", [KEY_SPACE, KEY_SHIFT])
	_key_action("restart", [KEY_R])
	_key_action("fire", [])
	_key_action("vent", [KEY_Q])
	_mouse_action("fire", MOUSE_BUTTON_LEFT)
	_mouse_action("vent", MOUSE_BUTTON_RIGHT)
	_axis_action("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis_action("move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis_action("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_axis_action("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_axis_action("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_axis_action("vent", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_button_action("dash", JOY_BUTTON_LEFT_SHOULDER)
	_button_action("restart", JOY_BUTTON_START)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)


func _key_action(action: String, keys: Array) -> void:
	_ensure(action)
	for k: Key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _mouse_action(action: String, button: MouseButton) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _axis_action(action: String, axis: JoyAxis, dir: float) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = dir
	InputMap.action_add_event(action, ev)


func _button_action(action: String, button: JoyButton) -> void:
	_ensure(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
