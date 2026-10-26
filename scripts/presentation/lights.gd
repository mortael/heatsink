class_name Lights
extends Node2D
## A small pool of PointLight2D flashes: Vents, kills and slams light up the room for a moment.
## Of the flashes, only big blasts cast shadows from the walls, and only the newest one at a time.
## Turned off entirely by the "Lights & shadows" setting.
## A second small pool follows energy bolts in flight, so each bolt lights the floor and walls
## it passes, and walls and pillars throw shadows away from it. Capped at BOLT_POOL shadowed
## lights (about 6% extra frame time on a software renderer): with more bolts than that, the
## newest ones carry the lights.

const POOL := 8
const BOLT_POOL := 4
const BOLT_RADIUS := 3.0 * C.TILE
const BOLT_ENERGY := 2.0

var _lights: Array[PointLight2D] = []
var _state: Array = [] # per light: [life, max_life, energy]
var _bolt_lights: Array[PointLight2D] = []


func _ready() -> void:
	add_to_group("dynamic_lights")
	for i in POOL:
		var l := PointLight2D.new()
		l.texture = Glow.light()
		l.blend_mode = Light2D.BLEND_MODE_ADD
		l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		l.shadow_filter_smooth = 2.0
		l.shadow_color = Color(0, 0, 0, 0.85)
		l.enabled = false
		add_child(l)
		_lights.append(l)
		_state.append([0.0, 1.0, 0.0])
	for i in BOLT_POOL:
		var b := PointLight2D.new()
		b.texture = Glow.light()
		b.texture_scale = BOLT_RADIUS * 2.0 / Glow.TEX_SIZE
		b.energy = BOLT_ENERGY
		b.shadow_enabled = true
		b.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		b.shadow_filter_smooth = 1.5
		b.shadow_color = Color(0, 0, 0, 0.9)
		b.enabled = false
		add_child(b)
		_bolt_lights.append(b)


## Lights a circle of `radius` px around pos, fading out over `life` seconds.
func flash(pos: Vector2, color: Color, radius: float, energy: float, life: float, shadows := false) -> void:
	if not Settings.lights:
		return
	var i := _pick()
	var l := _lights[i]
	l.global_position = pos
	l.color = color
	l.texture_scale = radius * 2.0 / Glow.TEX_SIZE
	l.energy = energy
	l.shadow_enabled = shadows
	l.enabled = true
	_state[i] = [life, life, energy]
	if shadows:
		# Only the newest blast keeps its shadows.
		for j in POOL:
			if j != i:
				_lights[j].shadow_enabled = false


func clear() -> void:
	for i in POOL:
		_lights[i].enabled = false
		_state[i][0] = 0.0
	for b in _bolt_lights:
		b.enabled = false
	if not is_inside_tree():
		return
	for bolt: Rivet in get_tree().get_nodes_in_group("bolts"):
		bolt.lit = false # brings back their floor wash, even while paused
		bolt.queue_redraw()


## The bolt lights switched on right now (the lighting screenshots check this).
func bolt_lights_active() -> int:
	return _bolt_lights.filter(func(l: PointLight2D) -> bool: return l.enabled).size()


## Called when the Lights & shadows setting changes.
func apply_lights() -> void:
	if not Settings.lights:
		clear()


func active_count() -> int:
	return _lights.filter(func(l: PointLight2D) -> bool: return l.enabled).size()


func _pick() -> int:
	var best := 0
	var best_life := INF
	for i in POOL:
		if not _lights[i].enabled:
			return i
		if _state[i][0] < best_life:
			best_life = _state[i][0]
			best = i
	return best


func _process(delta: float) -> void:
	_follow_bolts()
	for i in POOL:
		var l := _lights[i]
		if not l.enabled:
			continue
		var s: Array = _state[i]
		s[0] -= delta
		if s[0] <= 0.0:
			l.enabled = false
			continue
		var k: float = s[0] / s[1]
		l.energy = s[2] * k * k # fast fall-off reads as a flash, not a lamp


## Puts the bolt lights on the newest bolts in flight; spare lights switch off.
func _follow_bolts() -> void:
	var bolts: Array = get_tree().get_nodes_in_group("bolts")
	for bolt: Rivet in bolts:
		bolt.lit = false
	if not Settings.lights:
		bolts = []
	elif bolts.size() > BOLT_POOL:
		bolts.sort_custom(func(a: Rivet, b: Rivet) -> bool: return a.spawn_id > b.spawn_id)
	for i in BOLT_POOL:
		var b := _bolt_lights[i]
		if i >= bolts.size():
			b.enabled = false
			continue
		var bolt: Rivet = bolts[i]
		bolt.lit = true
		b.global_position = bolt.global_position
		b.color = Rivet.color_for(bolt.overdrive or bolt.ricocheted)
		b.enabled = true
