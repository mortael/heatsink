class_name PauseMenu
extends CanvasLayer
## Esc (or Start on a pad) mid-run: Resume, Codex, Settings, Main menu. Pauses the game while open.

const MENU_SCENE := "res://menu.tscn"

var game: Node
var is_open := false
var root := Control.new()
var buttons: VBoxContainer
var resume_button: Button
var codex_button: Button
var settings_button: Button
var menu_button: Button
var settings: SettingsPanel
var codex: CodexPanel


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiStyle.theme()
	root.visible = false
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	buttons = VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	center.add_child(buttons)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", UiStyle.HOT)
	buttons.add_child(title)
	resume_button = UiStyle.button("RESUME")
	resume_button.pressed.connect(close)
	buttons.add_child(resume_button)
	codex_button = UiStyle.button("CODEX")
	codex_button.pressed.connect(func() -> void:
		buttons.visible = false
		codex.open())
	buttons.add_child(codex_button)
	settings_button = UiStyle.button("SETTINGS")
	settings_button.pressed.connect(func() -> void:
		buttons.visible = false
		settings.open())
	buttons.add_child(settings_button)
	menu_button = UiStyle.button("MAIN MENU")
	menu_button.pressed.connect(to_menu)
	buttons.add_child(menu_button)
	var note := Label.new()
	note.text = "Leaving ends this run"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", UiStyle.DIM)
	buttons.add_child(note)
	settings = SettingsPanel.new()
	settings.visible = false
	settings.back.connect(func() -> void:
		buttons.visible = true
		settings_button.grab_focus())
	center.add_child(settings)
	codex = CodexPanel.new()
	codex.visible = false
	codex.back.connect(func() -> void:
		buttons.visible = true
		codex_button.grab_focus())
	center.add_child(codex)


func open() -> void:
	if is_open:
		return
	is_open = true
	root.visible = true
	buttons.visible = true
	settings.visible = false
	codex.visible = false
	get_tree().paused = true
	Sfx.play("band", 3.0, -6.0)
	resume_button.grab_focus()


func close() -> void:
	if not is_open:
		return
	if settings.visible:
		settings.close()
	codex.visible = false
	is_open = false
	root.visible = false
	get_tree().paused = false


func to_menu() -> void:
	is_open = false
	get_tree().paused = false
	Juice.reset()
	get_tree().change_scene_to_file(MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		if is_open and not settings.visible and not codex.visible and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
			get_viewport().set_input_as_handled()
			close()
		return
	if is_open:
		if settings.visible:
			settings.close()
		elif codex.visible:
			codex.close()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif game != null and game.can_pause():
		open()
		get_viewport().set_input_as_handled()
