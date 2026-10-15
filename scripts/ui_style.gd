class_name UiStyle
extends RefCounted
## Shared look for the menus: the dark panels and ember-orange edges of the HUD's Death Ledger.

const PANEL := Color(0.1, 0.08, 0.07, 0.95)
const EDGE := Color(0.9, 0.4, 0.1, 0.8)
const HOT := Color(1.0, 0.6, 0.3)
const TEXT := Color(0.92, 0.9, 0.88)
const DIM := Color(1, 1, 1, 0.55)


static func box(fill: Color, edge: Color, width := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(width)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_stylebox("normal", "Button", box(PANEL, Color(EDGE, 0.45)))
	t.set_stylebox("hover", "Button", box(Color(0.2, 0.11, 0.06, 0.95), EDGE))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), HOT, 3))
	t.set_stylebox("pressed", "Button", box(Color(0.35, 0.15, 0.05, 0.95), HOT))
	t.set_stylebox("disabled", "Button", box(Color(PANEL, 0.6), Color(1, 1, 1, 0.1)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.85, 0.6))
	t.set_color("font_focus_color", "Button", Color(1, 0.85, 0.6))
	t.set_color("font_pressed_color", "Button", Color(1, 0.9, 0.7))
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, EDGE))
	# Sliders: a Heat-gauge style bar that fills orange.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.75)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	t.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = C.HEAT_WARM
	fill.content_margin_top = 7
	fill.content_margin_bottom = 7
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_stylebox("focus", "HSlider", box(Color(0, 0, 0, 0), HOT, 2))
	t.set_icon("grabber", "HSlider", _knob(Color(1, 0.85, 0.6)))
	t.set_icon("grabber_highlight", "HSlider", _knob(Color(1, 1, 1)))
	t.set_stylebox("focus", "CheckButton", box(Color(0, 0, 0, 0), HOT, 2))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color(1, 0.85, 0.6))
	t.set_color("font_focus_color", "CheckButton", Color(1, 0.85, 0.6))
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_color("font_hover_pressed_color", "CheckButton", Color(1, 0.85, 0.6))
	return t


static func _knob(col: Color) -> ImageTexture:
	var img := Image.create(12, 26, false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)


static func button(text: String, min_w := 300.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 52)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void: Sfx.play("clear", 4.0, -8.0))
	b.focus_entered.connect(func() -> void: Sfx.play("band", 9.0, -18.0))
	return b
