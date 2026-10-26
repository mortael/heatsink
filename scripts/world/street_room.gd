class_name StreetRoom
extends Room
## Rainside: a rainy night yard in 3/4 top-down view, the first room that breaks the flat
## top-down look. The simulation is the same 24x13 grid as every room; only the drawing changes.
## A painted backdrop (the hall, the yard walls and the wet ground, with their light baked in) is
## dressed with prop sprites standing on their tiles, each with the light it throws on the wet
## ground and its halo; StreetGen decides which props stand where. All of it is painted by
## tools/street_art.py. The hall fills rows 0-2, so its doors sit in the facade at row 3.
## The parts of props that rise in front of the tiles north of them are drawn above actors and
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

var backdrop := 0
var props: Array = [] # from StreetGen: {"key", "tile", "variant"}
var focus: Node2D # the player, so crowns in front of them fade
var _over_mat: ShaderMaterial
var _neon: Sprite2D
var _rain: Node2D
var _splash: Node2D
var _drops: Array = [] # per drop: [position, ground y, length]
var _splashes: Array = [] # per splash: [position, age]
var _flicker := 0.0
var _next_flicker := 4.0
var _rng := RandomNumberGenerator.new()


func _init(layout: Dictionary) -> void:
	backdrop = layout.backdrop
	props = layout.props
	super(layout.lines)
	door_row = 3
	occluders = false # a flat shadow wedge behind a lamp post or a tank reads wrong in this view


func backdrop_name() -> String:
	return StreetData.BACKDROPS[backdrop].name


func _ready() -> void:
	super()
	_rng.seed = randi()
	if _over_shader == null:
		_over_shader = Shader.new()
		_over_shader.code = OVER_SHADER
	_over_mat = ShaderMaterial.new()
	_over_mat.shader = _over_shader
	_over_mat.set_shader_parameter("radius", FADE_RADIUS)
	var name_ := backdrop_name()
	_layer(name_ + "_base", StreetData.ART_OFFSET, true)
	# North to south, so a prop's body covers the ground light of the ones behind it.
	var order := props.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _foot(a) < _foot(b))
	for p: Dictionary in order:
		_prop_layer(p, "pool", Glow.additive())
	for p: Dictionary in order:
		_prop_layer(p, "body", null)
	_layer(name_ + "_glow", StreetData.ART_OFFSET, false).material = Glow.additive()
	for p: Dictionary in order:
		_prop_layer(p, "glow", Glow.additive())
	_neon = _layer(name_ + "_neon", StreetData.ART_OFFSET, true)
	_neon.material = Glow.additive()
	_over(_layer(name_ + "_over", StreetData.ART_OFFSET, true))
	for p: Dictionary in order:
		var s := _prop_layer(p, "over", null)
		if s != null:
			_over(s)
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


static func _foot(p: Dictionary) -> int:
	var t: Vector2i = p.tile
	return t.y + (1 if p.key == "v" else 0)


func _layer(file: String, at: Vector2, pixel: bool) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load("res://art/street/%s.png" % file)
	s.centered = false
	s.position = at
	s.scale = Vector2.ONE * StreetData.ART_SCALE
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel else CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(s)
	return s


## One layer of a prop, or null when that prop has no such layer.
func _prop_layer(p: Dictionary, layer: String, mat: Material) -> Sprite2D:
	var art: Dictionary = StreetData.PROPS[p.key][p.variant]
	if not art.has(layer):
		return null
	var t: Vector2i = p.tile
	var s := _layer(art[layer][0], Vector2(t) * C.TILE + art[layer][1], layer == "body" or layer == "over")
	if mat != null:
		s.material = mat
	return s


func _over(s: Sprite2D) -> void:
	s.z_index = 5
	s.material = _over_mat


func _new_drop() -> Array:
	var ground := Vector2(_rng.randf_range(-40.0, size_px.x + 40.0), _rng.randf_range(-20.0, size_px.y + 60.0))
	var start := ground - RAIN_DIR * _rng.randf_range(500.0, 760.0)
	return [start, ground.y, _rng.randf_range(12.0, 24.0)]


func _process(delta: float) -> void:
	# No rim glow here: the faces bolts would light are painted props, not flat blocks.
	if focus != null and is_instance_valid(focus):
		_over_mat.set_shader_parameter("focus", focus.global_position)
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
