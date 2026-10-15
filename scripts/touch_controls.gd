class_name TouchControls
extends CanvasLayer
## On-screen twin-stick for touch screens (Android, phones and tablets in the browser).
## Left half: a floating move stick. Right half: a floating aim stick that fires while pushed.
## Buttons for Dash, Vent and Use sit on the right edge. Hidden until the first touch,
## so mouse and keyboard players never see it. Feeds the same input actions as the keyboard.

const STICK_R := 80.0
const DEADZONE := 0.25
const BUTTON_R := 46.0
const MOVE_REST := Vector2(180, 560)
const AIM_REST := Vector2(960, 540)
const BUTTONS := [
	{"action": "vent", "label": "VENT", "pos": Vector2(1196, 452)},
	{"action": "dash", "label": "DASH", "pos": Vector2(1196, 580)},
	{"action": "interact", "label": "USE", "pos": Vector2(1080, 650)},
]

var game: Node
## Unit aim direction while the aim stick is pushed, else zero. Read by Player.
var aim := Vector2.ZERO
var active := false
var view := Control.new()

var _move_id := -1
var _move_origin := MOVE_REST
var _move_vec := Vector2.ZERO
var _aim_id := -1
var _aim_origin := AIM_REST
var _aim_vec := Vector2.ZERO
var _button_ids := {} # touch index -> action
var _restart_frames := 0


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.draw.connect(_draw_view)
	view.visible = false
	add_child(view)


func _activate() -> void:
	active = true
	view.visible = true
	# Touches also arrive as emulated mouse clicks (the reward picker relies on that),
	# so the mouse must stop firing, venting and aiming once the sticks take over.
	for action in ["fire", "vent"]:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton:
				InputMap.action_erase_event(action, ev)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not active:
			_activate()
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
		view.queue_redraw()
	elif event is InputEventScreenDrag and active:
		if event.index == _move_id:
			_move_origin = _follow(event.position, _move_origin)
			_move_vec = (event.position - _move_origin) / STICK_R
			_apply_move()
		elif event.index == _aim_id:
			_aim_origin = _follow(event.position, _aim_origin)
			_aim_vec = (event.position - _aim_origin) / STICK_R
			_apply_aim()
		view.queue_redraw()


func _process(_delta: float) -> void:
	if _restart_frames > 0:
		_restart_frames -= 1
		if _restart_frames == 0:
			Input.action_release("restart")


func _touch_down(index: int, pos: Vector2) -> void:
	if game.dead or game.victory:
		# Tap anywhere to start a new run. Held for a couple of frames so Game sees it.
		Input.action_press("restart")
		_restart_frames = 2
		return
	if game.picker.is_open:
		return # the picker reads the emulated mouse click
	for b in BUTTONS:
		if pos.distance_to(b.pos) <= BUTTON_R * 1.25:
			_button_ids[index] = b.action
			Input.action_press(b.action)
			return
	if pos.x < view.size.x * 0.5:
		if _move_id == -1:
			_move_id = index
			_move_origin = pos
			_move_vec = Vector2.ZERO
	elif _aim_id == -1:
		_aim_id = index
		_aim_origin = pos
		_aim_vec = Vector2.ZERO


func _touch_up(index: int) -> void:
	if _button_ids.has(index):
		Input.action_release(_button_ids[index])
		_button_ids.erase(index)
	elif index == _move_id:
		_move_id = -1
		_move_vec = Vector2.ZERO
		_move_origin = MOVE_REST
		_apply_move()
	elif index == _aim_id:
		_aim_id = -1
		_aim_vec = Vector2.ZERO
		_aim_origin = AIM_REST
		_apply_aim()


## Drags the stick's origin along when the finger goes past the rim.
func _follow(pos: Vector2, origin: Vector2) -> Vector2:
	var d := pos - origin
	return pos - d.normalized() * STICK_R if d.length() > STICK_R else origin


func _apply_move() -> void:
	var v := _move_vec if _move_vec.length() > DEADZONE else Vector2.ZERO
	_set_strength("move_left", -v.x)
	_set_strength("move_right", v.x)
	_set_strength("move_up", -v.y)
	_set_strength("move_down", v.y)


func _apply_aim() -> void:
	if _aim_vec.length() > DEADZONE:
		aim = _aim_vec.normalized()
		Input.action_press("fire")
	else:
		aim = Vector2.ZERO
		Input.action_release("fire")


func _set_strength(action: String, s: float) -> void:
	if s > 0.0:
		Input.action_press(action, minf(s, 1.0))
	else:
		Input.action_release(action)


func _draw_view() -> void:
	if game.dead or game.victory or game.picker.is_open:
		return
	_draw_stick(_move_origin, _move_vec, _move_id != -1)
	_draw_stick(_aim_origin, _aim_vec, _aim_id != -1)
	var font := ThemeDB.fallback_font
	var held := _button_ids.values()
	for b in BUTTONS:
		var on: bool = held.has(b.action)
		view.draw_circle(b.pos, BUTTON_R, Color(1, 1, 1, 0.18 if on else 0.07))
		view.draw_arc(b.pos, BUTTON_R, 0, TAU, 40, Color(1, 1, 1, 0.45 if on else 0.25), 2.0, true)
		var w := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, 16).x
		view.draw_string(font, b.pos + Vector2(-w * 0.5, 6), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))


func _draw_stick(origin: Vector2, v: Vector2, held: bool) -> void:
	view.draw_arc(origin, STICK_R, 0, TAU, 48, Color(1, 1, 1, 0.3 if held else 0.14), 2.0, true)
	view.draw_circle(origin + v * STICK_R, 30.0, Color(1, 1, 1, 0.25 if held else 0.1))
