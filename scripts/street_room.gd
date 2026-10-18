class_name StreetRoom
extends Room
## Rainside: a rainy night street in 3/4 top-down view, the first room that breaks the flat
## top-down look. The simulation is the same 24x13 grid as every room; only the drawing changes.
## Buildings and props are painted by tools/street_art.py (light and wet reflections baked in) and
## stand up out of their tiles. The building fills rows 0-2, so its doors sit in the facade at row 3.
## Crowns and lamp heads that rise in front of the tiles north of them are drawn above actors and
## fade out around the player. Rain, splashes and a stuttering neon sign are drawn live.

const DROPS := 170
const RAIN_DIR := Vector2(-0.16, 1.0)
const RAIN_SPEED := 980.0
const SPLASH_LIFE := 0.28
const FADE_RADIUS := 72.0

const OVER_SHADER := """
shader_type canvas_item;
uniform vec2 focus = vec2(-9999.0);
uniform float radius = 72.0;
varying vec2 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	vec4 c = COLOR; // already the texture times the modulate
	c.a *= mix(0.28, 1.0, smoothstep(radius * 0.55, radius, distance(world, focus)));
	COLOR = c;
}
"""

static var _over_shader: Shader

var layout := 0
var focus: Node2D # the player, so crowns in front of them fade
var _over: Sprite2D
var _neon: Sprite2D
var _rain: Node2D
var _splash: Node2D
var _drops: Array = [] # per drop: [position, ground y, length]
var _splashes: Array = [] # per splash: [position, age]
var _flicker := 0.0
var _next_flicker := 4.0
var _rng := RandomNumberGenerator.new()


func _init(layout_index := 0) -> void:
	layout = posmod(layout_index, StreetData.LAYOUTS.size())
	super(StreetData.LAYOUTS[layout].lines)
	door_row = 3
	occluders = false # a flat shadow wedge behind a lamp post or a tree reads wrong in this view


func _ready() -> void:
	super()
	_rng.seed = randi()
	var name_: String = StreetData.LAYOUTS[layout].name
	var base := _layer(name_ + "_base", true)
	base.z_index = 0
	var glow := _layer(name_ + "_glow", false)
	glow.material = Glow.additive()
	_neon = _layer(name_ + "_neon", true)
	_neon.material = Glow.additive()
	_over = _layer(name_ + "_over", true)
	_over.z_index = 5
	if _over_shader == null:
		_over_shader = Shader.new()
		_over_shader.code = OVER_SHADER
	var m := ShaderMaterial.new()
	m.shader = _over_shader
	m.set_shader_parameter("radius", FADE_RADIUS)
	_over.material = m
	_splash = Node2D.new()
	_splash.z_index = 1
	_splash.draw.connect(_draw_splashes)
	add_child(_splash)
	_rain = Node2D.new()
	_rain.z_index = 7
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_rain.material = unshaded
	_splash.material = unshaded
	_rain.draw.connect(_draw_rain)
	add_child(_rain)
	for i in DROPS:
		var d := _new_drop()
		d[0].y = lerpf(d[1] - 700.0, d[1], _rng.randf()) # start mid-fall so the first frame is already raining
		_drops.append(d)


func _layer(file: String, pixel: bool) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load("res://art/street/%s.png" % file)
	s.centered = false
	s.position = StreetData.ART_OFFSET
	s.scale = Vector2.ONE * StreetData.ART_SCALE
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel else CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(s)
	return s


func _new_drop() -> Array:
	var ground := Vector2(_rng.randf_range(-40.0, size_px.x + 40.0), _rng.randf_range(-20.0, size_px.y + 60.0))
	var start := ground - RAIN_DIR * _rng.randf_range(500.0, 760.0)
	return [start, ground.y, _rng.randf_range(12.0, 24.0)]


func _process(delta: float) -> void:
	# No rim glow here: the faces bolts would light are painted props, not flat blocks.
	if focus != null and is_instance_valid(focus):
		(_over.material as ShaderMaterial).set_shader_parameter("focus", focus.global_position)
	var step := RAIN_DIR * RAIN_SPEED * delta
	for d: Array in _drops:
		d[0] += step
		if d[0].y >= d[1]:
			if _splashes.size() < 60:
				_splashes.append([Vector2(d[0].x, d[1]), 0.0])
			var n := _new_drop()
			d[0] = n[0]
			d[1] = n[1]
			d[2] = n[2]
	for s: Array in _splashes:
		s[1] += delta
	_splashes = _splashes.filter(func(s: Array) -> bool: return s[1] < SPLASH_LIFE)
	_update_neon(delta)
	_rain.queue_redraw()
	_splash.queue_redraw()


## The sign hums, and now and then stutters off and back on like a tired tube.
func _update_neon(delta: float) -> void:
	_next_flicker -= delta
	if _next_flicker <= 0.0:
		_flicker = _rng.randf_range(0.25, 0.6)
		_next_flicker = _rng.randf_range(4.0, 10.0)
	var k := 0.93 + 0.07 * sin(Time.get_ticks_msec() / 70.0)
	if _flicker > 0.0:
		_flicker -= delta
		k = 1.0 if _rng.randf() < 0.45 else 0.12
	_neon.modulate.a = k


func _draw_rain() -> void:
	for d: Array in _drops:
		var p: Vector2 = d[0]
		_rain.draw_line(p - RAIN_DIR * d[2], p, Color(0.62, 0.72, 0.95, 0.32), 1.5)


func _draw_splashes() -> void:
	for s: Array in _splashes:
		var k: float = s[1] / SPLASH_LIFE
		var p: Vector2 = s[0]
		_splash.draw_set_transform(p, 0.0, Vector2(1.0, 0.45))
		_splash.draw_arc(Vector2.ZERO, 3.0 + 9.0 * k, 0.0, TAU, 12, Color(0.65, 0.75, 1.0, 0.45 * (1.0 - k)), 1.2)
	_splash.draw_set_transform_matrix(Transform2D.IDENTITY)


# The painted layers replace the flat room drawing, the hot wall seams and the rim glow.
func _draw() -> void:
	pass


func _draw_glow(_glow: Node2D) -> void:
	pass


func _draw_rim() -> void:
	pass
