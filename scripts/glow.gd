class_name Glow
## Shared pieces for light: soft glow textures, the additive material, and the light texture
## that PointLight2D flashes use. Everything is generated in code, like the rest of the art.
## Additive drawing is plain 2D canvas work, so it costs the same on web and phones as anywhere else.

const TEX_SIZE := 128

static var _soft: Texture2D
static var _band: Texture2D
static var _light: Texture2D
static var _add: CanvasItemMaterial


## Round halo: bright centre, long soft tail.
static func soft() -> Texture2D:
	if _soft == null:
		_soft = _radial([0.0, 0.18, 0.5, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0)])
	return _soft


## A strip that is bright along its middle line and fades to nothing at both edges (beams, tracers).
static func band() -> Texture2D:
	if _band == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.7, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.3), Color(1, 1, 1, 1), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 4
		t.height = 64
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(0, 1)
		_band = t
	return _band


## PointLight2D texture: white in the middle, black at the rim, so lights fade out smoothly.
static func light() -> Texture2D:
	if _light == null:
		var t := _radial([0.0, 0.25, 1.0], [Color.WHITE, Color(0.55, 0.55, 0.55), Color.BLACK])
		_light = t
	return _light


static func additive() -> CanvasItemMaterial:
	if _add == null:
		_add = CanvasItemMaterial.new()
		_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add


## Draws a halo of the given radius. Call from a node that uses additive().
static func halo(ci: CanvasItem, pos: Vector2, radius: float, color: Color) -> void:
	ci.draw_texture_rect(soft(), Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)


## Draws a soft strip from a to b, `width` across. Call from a node that uses additive().
static func strip(ci: CanvasItem, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var d := b - a
	if d.length_squared() < 0.01:
		return
	ci.draw_set_transform(a, d.angle())
	ci.draw_texture_rect(band(), Rect2(0, -width * 0.5, d.length(), width), false, color)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _radial(offsets: Array, colors: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = TEX_SIZE
	t.height = TEX_SIZE
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t
