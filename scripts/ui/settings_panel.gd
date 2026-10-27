class_name SettingsPanel
extends PanelContainer
## Volume, screen shake, fullscreen, lights and the FPS counter. Used by the main menu and the pause menu.
## Changes apply at once and are saved when you leave the panel.

signal back

var volume: HSlider
var music: HSlider
var shake: HSlider
var fullscreen: CheckButton
var lights: CheckButton
var bloom: CheckButton
var fps: CheckButton
var back_button: Button


func _init() -> void:
	custom_minimum_size = Vector2(520, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	add_child(col)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiStyle.HOT)
	col.add_child(title)
	volume = _slider(col, "Volume", Settings.volume)
	volume.value_changed.connect(func(v: float) -> void:
		Settings.volume = v
		Settings.dirty = true
		Settings.apply()
		Sfx.play("shot", 0.0, -6.0))
	music = _slider(col, "Music", Settings.music)
	music.value_changed.connect(func(v: float) -> void:
		Settings.music = v
		Settings.dirty = true
		Settings.apply())
	shake = _slider(col, "Screen shake", Settings.shake)
	shake.value_changed.connect(func(v: float) -> void:
		Settings.shake = v
		Settings.dirty = true
		Settings.apply())
	fullscreen = CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = Settings.fullscreen
	fullscreen.focus_mode = Control.FOCUS_ALL
	fullscreen.custom_minimum_size = Vector2(0, 44)
	fullscreen.add_theme_font_size_override("font_size", 20)
	fullscreen.visible = Settings.can_fullscreen()
	fullscreen.toggled.connect(func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.dirty = true
		Settings.apply())
	col.add_child(fullscreen)
	lights = CheckButton.new()
	lights.text = "Lights & shadows"
	lights.tooltip_text = "Light from energy bolts, Vents, beams and your lamp, with shadows behind walls and pillars. Turn off on slow devices."
	lights.button_pressed = Settings.lights
	lights.focus_mode = Control.FOCUS_ALL
	lights.custom_minimum_size = Vector2(0, 44)
	lights.add_theme_font_size_override("font_size", 20)
	lights.toggled.connect(func(on: bool) -> void:
		Settings.lights = on
		Settings.dirty = true
		# Apply at once: the game may be paused behind this panel, so nothing would update by itself.
		get_tree().call_group("dynamic_lights", "apply_lights"))
	col.add_child(lights)
	bloom = CheckButton.new()
	bloom.text = "Bloom"
	bloom.tooltip_text = "Soft glow around bright light. Needs Lights & shadows. Turn off if the game stutters."
	bloom.button_pressed = Settings.bloom
	bloom.focus_mode = Control.FOCUS_ALL
	bloom.custom_minimum_size = Vector2(0, 44)
	bloom.add_theme_font_size_override("font_size", 20)
	bloom.visible = Bloom.supported() # the web and Android builds have no bloom to switch
	bloom.toggled.connect(func(on: bool) -> void:
		Settings.bloom = on
		Settings.dirty = true
		get_tree().call_group("dynamic_lights", "apply_lights"))
	col.add_child(bloom)
	fps = CheckButton.new()
	fps.text = "Show FPS"
	fps.tooltip_text = "Frames per second in the top-left corner."
	fps.button_pressed = Settings.show_fps
	fps.focus_mode = Control.FOCUS_ALL
	fps.custom_minimum_size = Vector2(0, 44)
	fps.add_theme_font_size_override("font_size", 20)
	fps.toggled.connect(func(on: bool) -> void:
		Settings.show_fps = on
		Settings.dirty = true)
	col.add_child(fps)
	back_button = UiStyle.button("BACK", 0)
	back_button.pressed.connect(close)
	col.add_child(back_button)


func _slider(parent: Control, text: String, value: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(170, 0)
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 40)
	s.focus_mode = Control.FOCUS_ALL
	row.add_child(s)
	parent.add_child(row)
	return s


func open() -> void:
	volume.set_value_no_signal(Settings.volume)
	music.set_value_no_signal(Settings.music)
	shake.set_value_no_signal(Settings.shake)
	# Show the real window mode: the browser can leave fullscreen on its own (Esc) or refuse it.
	if Settings.can_fullscreen():
		Settings.fullscreen = Settings.is_fullscreen()
	fullscreen.set_pressed_no_signal(Settings.fullscreen)
	lights.set_pressed_no_signal(Settings.lights)
	fps.set_pressed_no_signal(Settings.show_fps)
	visible = true
	volume.grab_focus()


func close() -> void:
	if not visible:
		return
	Settings.save()
	visible = false
	back.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)):
		get_viewport().set_input_as_handled()
		close()
