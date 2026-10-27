class_name TitleScreen
extends Control
## Logo splash shown once at launch, before the main menu: starts the music, shows an animated
## HEATSINK wordmark rising out of the embers, then fades into the menu on any input or after
## HOLD_TIME if nobody presses anything.

const MENU_SCENE := "res://menu.tscn"
const HOLD_TIME := 5.0
const FADE_TIME := 0.6
const EMBERS := 90

var _t := 0.0
var _embers: Array[Vector4] = [] # x, y, speed, size
var _advancing := false
var _fade := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in EMBERS:
		_embers.append(Vector4(randf(), randf(), randf_range(0.03, 0.14), randf_range(1.0, 3.0)))
	Music.start()


func _process(delta: float) -> void:
	_t += delta
	for i in _embers.size():
		var e := _embers[i]
		e.y -= e.z * delta
		e.x += sin(_t * 0.7 + i) * 0.004 * delta
		if e.y < -0.02:
			e = Vector4(randf(), 1.02, randf_range(0.03, 0.14), randf_range(1.0, 3.0))
		_embers[i] = e
	if _advancing:
		_fade += delta / FADE_TIME
		if _fade >= 1.0:
			_go()
	elif _t >= HOLD_TIME:
		_advance()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _advancing:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventJoypadButton:
		_advance()


func _advance() -> void:
	_advancing = true
	_fade = 0.0


func _go() -> void:
	var err := get_tree().change_scene_to_file(MENU_SCENE)
	if err != OK:
		push_error("TitleScreen: failed to change scene to %s (Error %d)" % [MENU_SCENE, err])


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.03, 0.03))
	for i in 14:
		var k := float(i) / 14.0
		var h := s.y * 0.5 * (1.0 - k)
		draw_rect(Rect2(0, s.y - h, s.x, h), Color(0.9, 0.3, 0.05, 0.02))
	for e in _embers:
		var a := clampf(e.y * 1.4, 0.0, 1.0) * (0.5 + 0.5 * sin(_t * 3.0 + e.x * 40.0))
		draw_circle(Vector2(e.x * s.x, e.y * s.y), e.w, Color(1.0, 0.55 + 0.3 * e.w / 3.0, 0.2, a * 0.8))

	var font := ThemeDB.fallback_font
	# The wordmark eases up and in over the first second, then the subtitle and prompt follow.
	var rise := 1.0 - pow(1.0 - clampf(_t / 1.2, 0.0, 1.0), 3.0)
	var ty := s.y * 0.5 - 90.0 + (1.0 - rise) * 40.0
	var title := "HEATSINK"
	draw_string_outline(font, Vector2(0, ty), title, HORIZONTAL_ALIGNMENT_CENTER, s.x, 150, 16, Color(0, 0, 0, 0.9 * rise))
	draw_string(font, Vector2(0, ty), title, HORIZONTAL_ALIGNMENT_CENTER, s.x, 150, Color(1.0, 0.55, 0.2, rise))
	var sub_a := clampf((_t - 1.0) / 1.0, 0.0, 1.0)
	draw_string(font, Vector2(0, ty + 50), "a foundry roguelite", HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, Color(1, 1, 1, 0.6 * sub_a))
	var prompt_a := (0.4 + 0.3 * sin(_t * 2.2)) * clampf((_t - 2.0) / 1.0, 0.0, 1.0)
	draw_string(font, Vector2(0, s.y - 60), "press any key", HORIZONTAL_ALIGNMENT_CENTER, s.x, 16, Color(1, 1, 1, prompt_a))

	if _advancing:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, clampf(_fade, 0.0, 1.0)))
