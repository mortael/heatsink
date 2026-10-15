class_name Lights
extends Node2D
## A small pool of PointLight2D flashes: Vents, kills and slams light up the room for a moment.
## Only big blasts cast shadows from the walls (one shadowed light at a time keeps phones and the
## web build fast). Turned off entirely by the "Lights & shadows" setting.
## A second small pool follows energy bolts in flight, so each bolt lights the floor and walls
## it passes. Capped at BOLT_POOL: with more bolts than that, the newest ones carry the lights.

const POOL := 8
const BOLT_POOL := 4
const BOLT_RADIUS := 2.2 * C.TILE
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
	var bolts := get_tree().get_nodes_in_group("bolts") if Settings.lights else []
	var n := bolts.size()
	for i in BOLT_POOL:
		var b := _bolt_lights[i]
		var k := n - 1 - i # newest first: nodes join the group in the order they spawn
		if k < 0:
			b.enabled = false
			continue
		var bolt: Rivet = bolts[k]
		b.global_position = bolt.global_position
		b.color = Rivet.color_for(bolt.overdrive or bolt.ricocheted)
		b.enabled = true
