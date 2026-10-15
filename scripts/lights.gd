class_name Lights
extends Node2D
## A small pool of PointLight2D flashes: Vents, kills and slams light up the room for a moment.
## Only big blasts cast shadows from the walls (one shadowed light at a time keeps phones and the
## web build fast). Turned off entirely by the "Lights & shadows" setting.

const POOL := 8

var _lights: Array[PointLight2D] = []
var _state: Array = [] # per light: [life, max_life, energy]


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
