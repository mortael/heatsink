class_name FramePanel
extends PanelContainer
## The Frame picker shown after START RUN: three cards side by side, each with its weapon, Overdrive,
## Vent and passive. The last Frame played is focused, and the choice is saved.
## Works with mouse, touch, keys and a pad; Esc / B goes back to the title screen.

signal chosen(frame: String)
signal back

const CARD := Vector2(330, 470)

var cards: Array[Button] = []
var back_button: Button
var _icons: Array[Control] = []
var _t := 0.0


func _init() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var title := Label.new()
	title.text = "CHOOSE YOUR FRAME"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiStyle.HOT)
	col.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	for id in Frames.ORDER:
		var b := _card(id)
		b.pressed.connect(_choose.bind(id))
		row.add_child(b)
		cards.append(b)
	back_button = UiStyle.button("BACK", 0)
	back_button.custom_minimum_size.y = 44
	back_button.pressed.connect(close)
	col.add_child(back_button)


func _card(id: String) -> Button:
	var f: Dictionary = Frames.info(id)
	var b := UiStyle.button("", 0)
	b.custom_minimum_size = CARD
	b.clip_contents = true
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 5)
	m.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(84, 64)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_icon.bind(icon, id))
	_icons.append(icon)
	head.add_child(icon)
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(names)
	names.add_child(_label(f.name, 26, f.color))
	names.add_child(_label(f.role, 15, UiStyle.DIM))
	var kw: String = f.keyword
	v.add_child(_label("%d Plating  ·  native keyword %s" % [f.pips, kw.capitalize()], 14, ItemDB.keyword_color(kw)))
	v.add_child(_text("WEAPON", f.weapon))
	v.add_child(_text("OVERDRIVE", f.overdrive))
	v.add_child(_text("VENT", f.vent))
	v.add_child(_text("PASSIVE", f.passive))
	return b


func _label(s: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _text(head: String, body: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_color_override("default_color", UiStyle.TEXT)
	r.text = "[color=#%s]%s[/color]  %s" % [UiStyle.HOT.to_html(false), head, body]
	return r


func open() -> void:
	visible = true
	var i := Frames.ORDER.find(Frames.clamp_id(Settings.frame))
	cards[maxi(i, 0)].grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	back.emit()


func _choose(id: String) -> void:
	if Settings.frame != id:
		Settings.frame = id
		Settings.save()
	chosen.emit(id)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	for icon in _icons:
		icon.queue_redraw()


## A big version of the Sink as it looks in the game, its core warming and cooling.
func _draw_icon(c: Control, id: String) -> void:
	var o := c.size * 0.5
	var heat := 0.5 + 0.5 * sin(_t * 1.6 + Frames.ORDER.find(id) * 2.0)
	var core := C.HEAT_COLD.lerp(C.HEAT_WARM, heat)
	var aim := Vector2.from_angle(-0.5)
	var s := 1.25
	var col: Color = Frames.info(id).color
	match id:
		"furnace":
			var side := aim.orthogonal()
			var head := o + aim * 26.0 * s
			c.draw_line(o, head, Color(0.35, 0.3, 0.27), 5.0 * s)
			var hd := PackedVector2Array([head + side * 14 - aim * 6, head + side * 14 + aim * 9, head - side * 14 + aim * 9, head - side * 14 - aim * 6])
			c.draw_colored_polygon(hd, Color(0.32, 0.3, 0.3))
			c.draw_line(hd[1], hd[2], col, 3.0)
			var hull := PackedVector2Array()
			for i in 8:
				hull.append(o + Vector2.from_angle(i * TAU / 8.0 + PI / 8.0) * 16.0 * s)
			c.draw_colored_polygon(hull, Color(0.24, 0.2, 0.19))
			hull.append(hull[0])
			c.draw_polyline(hull, Color(0.7, 0.5, 0.35), 2.0)
			for i in 3:
				var y := (-6.0 + i * 6.0)
				c.draw_line(o + Vector2(-9, y), o + Vector2(9, y), core, 3.0)
		"arclight":
			var side := aim.orthogonal()
			c.draw_line(o, o + aim * 24.0 * s, Color(0.28, 0.32, 0.36), 9.0)
			for i in 3:
				var p := o + aim * (14.0 + i * 6.0) * s
				c.draw_line(p + side * 9, p - side * 9, col if heat > i * 0.3 else Color(0.4, 0.45, 0.5), 3.0)
			c.draw_circle(o, 13.0 * s, Color(0.17, 0.2, 0.24))
			c.draw_arc(o, 13.0 * s, 0, TAU, 32, Color(0.45, 0.8, 0.95), 2.0)
			c.draw_circle(o, 9.0, core)
		_:
			c.draw_line(o + aim * 8.0, o + aim * 26.0 * s, Color(0.3, 0.32, 0.35), 10.0)
			c.draw_line(o + aim * 8.0, o + aim * 26.0 * s, Color(0.75, 0.78, 0.8), 4.0)
			c.draw_circle(o, 14.0 * s, Color(0.2, 0.21, 0.23))
			c.draw_arc(o, 14.0 * s, 0, TAU, 32, C.STEEL, 2.0)
			c.draw_circle(o, 10.0, core)


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)):
		get_viewport().set_input_as_handled()
		close()
