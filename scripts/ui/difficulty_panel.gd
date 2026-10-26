class_name DifficultyPanel
extends PanelContainer
## The difficulty picker shown after START RUN. The last level played is focused, and the choice is saved.
## Works with mouse, touch, keys and a pad; Esc / B goes back to the title screen.

signal chosen(level: int)
signal back

var level_buttons: Array[Button] = []
var blurb: Label
var back_button: Button


func _init() -> void:
	custom_minimum_size = Vector2(560, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var title := Label.new()
	title.text = "HOW HOT DO YOU RUN?"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiStyle.HOT)
	col.add_child(title)
	for i in Difficulty.LEVELS.size():
		var lv: Dictionary = Difficulty.LEVELS[i]
		var b := UiStyle.button(lv.name, 0)
		b.custom_minimum_size.y = 44
		b.add_theme_color_override("font_color", lv.color)
		b.add_theme_color_override("font_focus_color", lv.color)
		b.add_theme_color_override("font_hover_color", lv.color)
		b.pressed.connect(_choose.bind(i))
		b.focus_entered.connect(_show_blurb.bind(i))
		b.mouse_entered.connect(_show_blurb.bind(i))
		col.add_child(b)
		level_buttons.append(b)
	blurb = Label.new()
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(0, 56)
	blurb.add_theme_font_size_override("font_size", 17)
	blurb.add_theme_color_override("font_color", UiStyle.DIM)
	col.add_child(blurb)
	back_button = UiStyle.button("BACK", 0)
	back_button.custom_minimum_size.y = 44
	back_button.pressed.connect(close)
	col.add_child(back_button)


func open() -> void:
	visible = true
	var i := Difficulty.clamp_level(Settings.difficulty)
	level_buttons[i].grab_focus()
	_show_blurb(i)


func close() -> void:
	if not visible:
		return
	visible = false
	back.emit()


func _show_blurb(i: int) -> void:
	blurb.text = Difficulty.LEVELS[i].blurb


func _choose(i: int) -> void:
	if Settings.difficulty != i:
		Settings.difficulty = i
		Settings.save()
	chosen.emit(i)


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)):
		get_viewport().set_input_as_handled()
		close()
