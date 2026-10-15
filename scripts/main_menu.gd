class_name MainMenu
extends Control
## Title screen: Start, Settings and Quit (Quit is hidden in the browser and on phones).
## Works with mouse, touch, keys (arrows + Enter) and a pad (d-pad + A, B backs out).

const GAME_SCENE := "res://main.tscn"
const EMBERS := 70

var buttons: VBoxContainer
var start_button: Button
var settings_button: Button
var quit_button: Button
var settings: SettingsPanel
var _embers: Array[Vector4] = [] # x, y, speed, size
var _t := 0.0


func _ready() -> void:
	get_tree().paused = false
	Juice.reset()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.theme()
	for i in EMBERS:
		_embers.append(Vector4(randf(), randf(), randf_range(0.03, 0.12), randf_range(1.0, 3.0)))

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 150
	add_child(center)
	buttons = VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	center.add_child(buttons)
	start_button = UiStyle.button("START RUN")
	start_button.pressed.connect(start_run)
	buttons.add_child(start_button)
	settings_button = UiStyle.button("SETTINGS")
	settings_button.pressed.connect(_show_settings)
	buttons.add_child(settings_button)
	quit_button = UiStyle.button("QUIT")
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	quit_button.visible = not OS.has_feature("web") and not OS.has_feature("mobile")
	buttons.add_child(quit_button)
	settings = SettingsPanel.new()
	settings.visible = false
	settings.back.connect(_hide_settings)
	center.add_child(settings)
	start_button.grab_focus()


func start_run() -> void:
	Sfx.play("portal", 0.0, -4.0)
	get_tree().change_scene_to_file(GAME_SCENE)


func _show_settings() -> void:
	buttons.visible = false
	settings.open()


func _hide_settings() -> void:
	buttons.visible = true
	settings_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# A pad or key press with nothing focused (after a mouse or touch tap elsewhere) refocuses the menu.
	if (event is InputEventKey or event is InputEventJoypadButton) and get_viewport().gui_get_focus_owner() == null:
		if settings.visible:
			settings.volume.grab_focus()
		else:
			start_button.grab_focus()


func _process(delta: float) -> void:
	_t += delta
	for i in _embers.size():
		var e := _embers[i]
		e.y -= e.z * delta
		e.x += sin(_t * 0.7 + i) * 0.004 * delta
		if e.y < -0.02:
			e = Vector4(randf(), 1.02, randf_range(0.03, 0.12), randf_range(1.0, 3.0))
		_embers[i] = e
	queue_redraw()


func _draw() -> void:
	var s := size
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.04, 0.04))
	# Furnace glow rising from the bottom edge.
	for i in 12:
		var k := float(i) / 12.0
		var h := s.y * 0.45 * (1.0 - k)
		draw_rect(Rect2(0, s.y - h, s.x, h), Color(0.9, 0.3, 0.05, 0.025))
	for e in _embers:
		var a := clampf(e.y * 1.4, 0.0, 1.0) * (0.5 + 0.5 * sin(_t * 3.0 + e.x * 40.0))
		draw_circle(Vector2(e.x * s.x, e.y * s.y), e.w, Color(1.0, 0.55 + 0.3 * e.w / 3.0, 0.2, a * 0.8))

	# Title, with a heat gauge that slowly fills and vents underneath it.
	var ty := s.y * 0.5 - 150
	var title := "HEATSINK"
	var flicker := 0.85 + 0.15 * sin(_t * 9.0) * sin(_t * 2.3)
	draw_string_outline(font, Vector2(0, ty), title, HORIZONTAL_ALIGNMENT_CENTER, s.x, 96, 12, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(0, ty), title, HORIZONTAL_ALIGNMENT_CENTER, s.x, 96, Color(1.0, 0.55, 0.2, flicker))
	var gw := 440.0
	var gx := (s.x - gw) * 0.5
	var gy := ty + 26
	var fill := fmod(_t * 0.18, 1.0)
	var col := C.HEAT_COLD if fill < 0.4 else (C.HEAT_WARM if fill < 0.8 else C.HEAT_HOT)
	draw_rect(Rect2(gx - 3, gy - 3, gw + 6, 16), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(gx, gy, gw * fill, 10), col)
	for m in [0.4, 0.8]:
		draw_line(Vector2(gx + gw * m, gy - 4), Vector2(gx + gw * m, gy + 14), Color(1, 1, 1, 0.7), 2.0)
	if not settings.visible:
		draw_string(font, Vector2(0, gy + 42), "Run hot. Vent hard. Don't melt.", HORIZONTAL_ALIGNMENT_CENTER, s.x, 16, UiStyle.DIM)
	draw_string(font, Vector2(0, s.y - 16), "Mouse, touch, keys or pad  ·  Enter / A to choose  ·  Esc / B to go back", HORIZONTAL_ALIGNMENT_CENTER, s.x, 12, Color(1, 1, 1, 0.4))
