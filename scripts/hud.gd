class_name Hud
extends CanvasLayer
## Heat gauge, Plating pips, dash/vent readiness, screen-edge tints, banners and the Death Ledger.

var game: Node
var view := Control.new()

var _gauge_pulse := 0.0
var _damage := 0.0
var _chroma := 0.0
var _banner := ""
var _banner_t := 0.0
var _sub := ""
var _dim := 0.0
var _fade := 0.0
var _fade_len := 0.25


## Black out for one room transition: fades to black over t, then back in over t.
func fade(t: float) -> void:
	_fade_len = t
	_fade = 2.0 * t


func dim(seconds: float) -> void:
	_dim = seconds


func _ready() -> void:
	layer = 10
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.draw.connect(_draw_view)
	add_child(view)
	process_mode = Node.PROCESS_MODE_ALWAYS


func pulse_gauge() -> void:
	_gauge_pulse = 1.0


func damage_flash() -> void:
	_damage = 1.0


func chromatic(amount: float) -> void:
	_chroma = clampf(amount / 100.0, 0.2, 1.0)


func banner(text: String, sub := "") -> void:
	_banner = text
	_sub = sub
	_banner_t = 2.0


func _process(delta: float) -> void:
	var d := delta if delta > 0.0 else 0.016 # keep fading during hit-stop
	_gauge_pulse = maxf(0.0, _gauge_pulse - d * 4.0)
	_damage = maxf(0.0, _damage - d / 0.4)
	_chroma = maxf(0.0, _chroma - d * 3.0)
	_banner_t = maxf(0.0, _banner_t - d)
	_dim = maxf(0.0, _dim - d)
	_fade = maxf(0.0, _fade - d)
	view.queue_redraw()


func _edge_glow(color: Color, alpha: float, depth: float) -> void:
	var s := view.size
	var steps := 8
	for i in steps:
		var k := 1.0 - float(i) / steps
		var c := Color(color, alpha * k * k)
		var w := depth / steps
		var o := i * w
		view.draw_rect(Rect2(o, o, s.x - 2 * o, w), c)
		view.draw_rect(Rect2(o, s.y - o - w, s.x - 2 * o, w), c)
		view.draw_rect(Rect2(o, o + w, w, s.y - 2 * o - 2 * w), c)
		view.draw_rect(Rect2(s.x - o - w, o + w, w, s.y - 2 * o - 2 * w), c)


func _draw_view() -> void:
	if game == null or game.player == null:
		return
	var font := ThemeDB.fallback_font
	var s := view.size
	var p: Player = game.player
	var h := p.heat

	if _dim > 0.0:
		view.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.2))
	# Screen-edge tints: orange while Hot, red vignette on damage, white pulse on big vents.
	if h.band == Heat.Band.HOT:
		_edge_glow(Color(1.0, 0.55, 0.15), 0.15, 70.0)
	if h.is_overheated():
		_edge_glow(C.HEAT_OVER, 0.12 + 0.08 * sin(Time.get_ticks_msec() / 60.0), 90.0)
	if _damage > 0.0:
		_edge_glow(Color(0.9, 0.05, 0.05), 0.6 * _damage, 140.0)
	if _chroma > 0.0:
		_edge_glow(Color(1.0, 0.9, 0.7), 0.25 * _chroma, 50.0)

	# Plating pips (top-left)
	for i in p.max_pips:
		var r := Rect2(24 + i * 30, 18, 24, 14)
		view.draw_rect(r, Color(0.1, 0.1, 0.1, 0.8))
		if i < p.pips:
			view.draw_rect(r.grow(-2), Color(0.8, 0.85, 0.9))
	view.draw_string(font, Vector2(24, 52), "PLATING", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.7))
	_draw_items(font)

	# Heat gauge (bottom centre)
	var gw := 440.0 + 24.0 * _gauge_pulse
	var gh := 18.0 + 6.0 * _gauge_pulse
	var gx := (s.x - gw) * 0.5
	var gy := s.y - 40.0 - gh * 0.5
	view.draw_rect(Rect2(gx - 3, gy - 3, gw + 6, gh + 6), Color(0, 0, 0, 0.75))
	var fill := h.value / h.cap
	var col := C.HEAT_COLD
	if h.is_overheated():
		fill = 1.0
		col = C.HEAT_OVER if int(Time.get_ticks_msec() / 100) % 2 == 0 else Color(0.5, 0.05, 0.05)
	elif h.band == Heat.Band.HOT:
		col = C.HEAT_HOT
	elif h.band == Heat.Band.WARM:
		col = C.HEAT_WARM
	if not h.is_overheated() and h.value >= 92.0 and int(Time.get_ticks_msec() / 70) % 2 == 0:
		col = C.HEAT_OVER
	view.draw_rect(Rect2(gx, gy, gw * fill, gh), col)
	for m in [Heat.WARM_AT, h.hot_at]:
		var mx: float = gx + gw * m / h.cap
		view.draw_line(Vector2(mx, gy - 4), Vector2(mx, gy + gh + 4), Color(1, 1, 1, 0.7), 2.0)
	var label := "HEAT %d  ·  %s" % [int(h.value), h.band_name()]
	if h.is_overheated():
		label = "OVERHEAT  ·  LOCKED %.1fs" % h.overheat_timer
	elif h.band == Heat.Band.HOT:
		label += "  ·  OVERDRIVE"
	view.draw_string(font, Vector2(gx, gy - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))

	# Dash charges (left of gauge) and Vent (right of gauge)
	for i in Player.DASH_MAX:
		var c := Color(0.35, 0.9, 1.0) if i < p.dash_charges else Color(0.2, 0.25, 0.3)
		view.draw_circle(Vector2(gx - 50 + i * 20, gy + gh * 0.5), 7.0, c)
	view.draw_string(font, Vector2(gx - 64, gy - 8), "DASH", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.7))
	var vx := gx + gw + 24
	var vready := p.vent_cd <= 0.0
	var vk: float = 1.0 - p.vent_cd / game.inventory.vent_cooldown()
	view.draw_arc(Vector2(vx + 12, gy + gh * 0.5), 11.0, -PI / 2, -PI / 2 + TAU * vk, 24, Color(1, 0.7, 0.3) if vready else Color(0.5, 0.4, 0.3), 4.0)
	view.draw_string(font, Vector2(vx + 30, gy + gh * 0.5 + 5), "VENT" if vready else "%.1f" % p.vent_cd, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9 if vready else 0.5))

	# Run info (top-right)
	var d: Director = game.director
	var info := "KILLS %d   %d:%02d" % [game.kills, int(game.run_time) / 60, int(game.run_time) % 60]
	view.draw_string(font, Vector2(0, 32), info, HORIZONTAL_ALIGNMENT_RIGHT, s.x - 24, 16, Color(1, 1, 1, 0.85))
	view.draw_string(font, Vector2(0, 54), "SCRAP %d" % game.scrap, HORIZONTAL_ALIGNMENT_RIGHT, s.x - 24, 16, Color(1, 0.85, 0.35))
	if d.clear_times.size() > 0:
		view.draw_string(font, Vector2(0, 72), "last clear %.1fs" % d.clear_times[-1], HORIZONTAL_ALIGNMENT_RIGHT, s.x - 24, 12, Color(0.75, 0.75, 0.75))
	_draw_route(font, s)

	# Banner
	if _banner_t > 0.0:
		var a := clampf(_banner_t, 0.0, 1.0)
		# Sits below the door labels so a room's name never hides where the doors lead.
		var by := 236.0
		view.draw_string_outline(font, Vector2(0, by), _banner, HORIZONTAL_ALIGNMENT_CENTER, s.x, 36, 6, Color(0, 0, 0, a))
		view.draw_string(font, Vector2(0, by), _banner, HORIZONTAL_ALIGNMENT_CENTER, s.x, 36, Color(1, 0.85, 0.6, a))
		if _sub != "":
			view.draw_string_outline(font, Vector2(0, by + 30), _sub, HORIZONTAL_ALIGNMENT_CENTER, s.x, 16, 4, Color(0, 0, 0, a * 0.8))
			view.draw_string(font, Vector2(0, by + 30), _sub, HORIZONTAL_ALIGNMENT_CENTER, s.x, 16, Color(1, 1, 1, a * 0.8))

	# Controls hint during the first room
	if game.run.index <= 1 and not game.dead:
		var hint := "WASD move  ·  Mouse aim  ·  LMB fire  ·  Space dash  ·  RMB vent  ·  E use      (pad: sticks, RT, LB, LT, A)"
		view.draw_string(font, Vector2(0, s.y - 8), hint, HORIZONTAL_ALIGNMENT_CENTER, s.x, 12, Color(1, 1, 1, 0.55))

	if game.dead:
		_draw_ledger(font, s)
	elif game.victory:
		_draw_victory(font, s)
	if _fade > 0.0:
		var k := _fade / _fade_len # 2 -> 1: darkening, 1 -> 0: lifting
		var a := 2.0 - k if k > 1.0 else k
		view.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, clampf(a, 0.0, 1.0)))


## Route strip (top centre): one cell per room, coloured by the room type taken.
func _draw_route(font: Font, s: Vector2) -> void:
	var run: RunMap = game.run
	var cell := 22.0
	var gap := 4.0
	var total := RunMap.GATE * cell + (RunMap.GATE - 1) * gap
	var x0 := (s.x - total) * 0.5
	var y := 14.0
	for i in RunMap.GATE:
		var r := Rect2(x0 + i * (cell + gap), y, cell, cell)
		view.draw_rect(r, Color(0.06, 0.05, 0.05, 0.8))
		if i < run.visited.size():
			var kind: String = run.visited[i]
			var col: Color = RunMap.KINDS[kind].color
			view.draw_rect(r.grow(-3), Color(col, 0.85 if i == run.index - 1 else 0.45))
		var edge := Color(1, 1, 1, 0.9) if i == run.index - 1 else Color(1, 1, 1, 0.2)
		if i == RunMap.GATE - 1:
			edge = Color(1, 0.3, 0.25, 0.9)
		view.draw_rect(r, edge, false, 1.5)
	var here: String = run.visited[-1] if not run.visited.is_empty() else ""
	if here != "":
		view.draw_string(font, Vector2(0, y + cell + 15), "%s  ·  ROOM %d / %d" % [RunMap.KINDS[here].name, run.index, RunMap.GATE], HORIZONTAL_ALIGNMENT_CENTER, s.x, 11, Color(1, 1, 1, 0.6))


func _draw_victory(font: Font, s: Vector2) -> void:
	view.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.55))
	var w := 560.0
	var box := Rect2((s.x - w) * 0.5, s.y * 0.5 - 130, w, 260)
	view.draw_rect(box, Color(0.1, 0.08, 0.07, 0.95))
	view.draw_rect(box, Color(1, 0.8, 0.35, 0.9), false, 2.0)
	var x := box.position.x + 28
	var y := box.position.y + 50
	view.draw_string(font, Vector2(x, y), "STRATUM 1 CLEARED", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 0.85, 0.4))
	var lines := [
		"%d rooms  ·  %d kills  ·  %d:%02d" % [game.run.index, game.kills, int(game.run_time) / 60, int(game.run_time) % 60],
		"Items: %d  ·  Fusions: %d  ·  Scrap left: %d" % [game.inventory.owned.size(), game.inventory.fusions.size(), game.scrap],
		"The Stratum boss and Strata 2-4 arrive in later builds.",
	]
	for i in lines.size():
		view.draw_string(font, Vector2(x, y + 44 + i * 28), lines[i], HORIZONTAL_ALIGNMENT_LEFT, w - 56, 17, Color(0.92, 0.9, 0.88))
	view.draw_string(font, Vector2(x, box.end.y - 24), "Press R (or Start) to start a new run", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.7))


## Owned items as small keyword-coloured chips, then active Resonance and Fusions.
func _draw_items(font: Font) -> void:
	var inv: Inventory = game.inventory
	var x := 24.0
	var y := 62.0
	for id in inv.owned:
		var item: Dictionary = ItemDB.ITEMS[id]
		var kc := ItemDB.keyword_color(item.keyword)
		var words: PackedStringArray = item.name.split(" ")
		var abbr: String = words[0].substr(0, 1) + (words[1].substr(0, 1) if words.size() > 1 else words[0].substr(1, 1))
		var r := Rect2(x, y, 26, 22)
		view.draw_rect(r, Color(0.08, 0.07, 0.06, 0.85))
		view.draw_rect(r, kc, false, 1.5)
		view.draw_string(font, Vector2(x, y + 16), abbr.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 26, 11, kc)
		x += 30.0
	var line := y + 40.0
	for kw: String in ItemDB.RESONANCE:
		if inv.resonance(kw):
			view.draw_string(font, Vector2(24, line), "RESONANCE · %s" % kw.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ItemDB.keyword_color(kw))
			line += 15.0
	for f in inv.fusions:
		view.draw_string(font, Vector2(24, line), "FUSION · %s" % ItemDB.FUSIONS[f].name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.82, 0.3))
		line += 15.0
	for id in inv.owned:
		if not inv.cursed(id):
			continue
		var item: Dictionary = ItemDB.ITEMS[id]
		var text := "SLAGGED · %s  %d/%d  (%s)" % [item.name.to_upper(), int(inv.absolution.get(id, 0.0)), int(item.goal), item.absolution]
		view.draw_string(font, Vector2(24, line), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ItemDB.keyword_color("slagged"))
		line += 15.0


func _draw_ledger(font: Font, s: Vector2) -> void:
	view.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.7))
	var w := 560.0
	var box := Rect2((s.x - w) * 0.5, s.y * 0.5 - 150, w, 300)
	view.draw_rect(box, Color(0.1, 0.08, 0.07, 0.95))
	view.draw_rect(box, Color(0.9, 0.4, 0.1, 0.8), false, 2.0)
	var x := box.position.x + 28
	var y := box.position.y + 50
	view.draw_string(font, Vector2(x, y), "DEATH LEDGER", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 0.6, 0.3))
	var lines: Array = game.ledger_lines()
	for i in lines.size():
		view.draw_string(font, Vector2(x, y + 44 + i * 28), lines[i], HORIZONTAL_ALIGNMENT_LEFT, w - 56, 17, Color(0.92, 0.9, 0.88))
	view.draw_string(font, Vector2(x, box.end.y - 24), "Press R (or Start) to cast a new Sink", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.7))
