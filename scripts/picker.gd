class_name Picker
extends CanvasLayer
## "Pick 1 of 3" reward screen shown after each room. Pauses the game while open.
## Mouse: hover + click. Keys: 1/2/3 or arrows + Enter. Pad: d-pad + A.

signal chosen(id: String)

const CARD_W := 330.0
const CARD_H := 250.0
const GAP := 28.0

var game: Node
var options: Array[String] = []
var selected := 0
var is_open := false
var view := Control.new()
var _opened_at := 0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.draw.connect(_draw_view)
	view.visible = false
	add_child(view)


func open(opts: Array[String]) -> void:
	options = opts
	selected = 0
	is_open = true
	view.visible = true
	_opened_at = Time.get_ticks_msec()
	get_tree().paused = true
	Sfx.play("band", 7.0, -6.0)
	view.queue_redraw()


func choose(i: int) -> void:
	if not is_open or i < 0 or i >= options.size():
		return
	is_open = false
	view.visible = false
	get_tree().paused = false
	Sfx.play("clear", 4.0, -4.0)
	chosen.emit(options[i])


func _card_rect(i: int) -> Rect2:
	var s := view.size
	var total := options.size() * CARD_W + (options.size() - 1) * GAP
	return Rect2((s.x - total) * 0.5 + i * (CARD_W + GAP), s.y * 0.5 - CARD_H * 0.5 + 10.0, CARD_W, CARD_H)


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	# Ignore input for a moment so a held fire button doesn't pick by accident.
	if Time.get_ticks_msec() - _opened_at < 350:
		return
	if event is InputEventMouseMotion:
		for i in options.size():
			if _card_rect(i).has_point(event.position):
				selected = i
		view.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in options.size():
			if _card_rect(i).has_point(event.position):
				choose(i)
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: choose(0)
			KEY_2: choose(1)
			KEY_3: choose(2)
	if not is_open:
		return
	if event.is_action_pressed("ui_left"):
		selected = (selected - 1 + options.size()) % options.size()
		view.queue_redraw()
	elif event.is_action_pressed("ui_right"):
		selected = (selected + 1) % options.size()
		view.queue_redraw()
	elif event.is_action_pressed("ui_accept"):
		choose(selected)


func _draw_view() -> void:
	var font := ThemeDB.fallback_font
	var s := view.size
	view.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.72))
	view.draw_string(font, Vector2(0, s.y * 0.5 - CARD_H * 0.5 - 40), "CHOOSE A SALVAGE", HORIZONTAL_ALIGNMENT_CENTER, s.x, 30, Color(1, 0.75, 0.45))
	var inv: Inventory = game.inventory
	for i in options.size():
		var id := options[i]
		var item: Dictionary = ItemDB.get_item(id)
		var r := _card_rect(i)
		var kw: String = item.keyword
		var kc := ItemDB.keyword_color(kw)
		var sel := i == selected
		if sel:
			r = r.grow(6)
		view.draw_rect(r, Color(0.11, 0.09, 0.08, 0.97))
		view.draw_rect(r, kc if sel else Color(kc, 0.45), false, 3.0 if sel else 1.5)
		var x := r.position.x + 18
		var y := r.position.y + 36
		view.draw_string(font, Vector2(x, y), "%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.4))
		view.draw_string(font, Vector2(x + 22, y), item.name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 50, 21, Color(1, 1, 1))
		var tag := "%s  ·  %s" % [kw.to_upper(), item.rarity]
		if item.tier != "-":
			tag = "TIER %s  ·  %s" % [item.tier, tag]
		view.draw_string(font, Vector2(x, y + 24), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, kc)
		view.draw_multiline_string(font, Vector2(x, y + 56), item.desc, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36, 15, 6, Color(0.88, 0.86, 0.84))
		# Synergy hints
		var hint := ""
		var hint_col := Color(0.75, 0.75, 0.75)
		if id != "patch_kit":
			var f := inv.completes_fusion(id)
			if f != "":
				hint = "COMPLETES FUSION: " + ItemDB.FUSIONS[f].name
				hint_col = Color(1, 0.82, 0.3)
			elif kw != "conductor" and inv.count_keyword(kw) == 1:
				hint = "UNLOCKS RESONANCE: " + kw.to_upper()
				hint_col = kc
			elif inv.is_fusion_ingredient(id):
				hint = "Fusion ingredient"
		if hint != "":
			view.draw_string(font, Vector2(x, r.end.y - 18), hint, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36, 13, hint_col)
	view.draw_string(font, Vector2(0, s.y * 0.5 + CARD_H * 0.5 + 56), "Click a card, press 1-3, or use arrows/d-pad + Enter/A", HORIZONTAL_ALIGNMENT_CENTER, s.x, 13, Color(1, 1, 1, 0.5))
