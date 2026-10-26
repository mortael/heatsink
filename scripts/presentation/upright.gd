class_name Upright
## 2.5D figures for the Rainside rooms: the Sink and the enemies are drawn as standing sprites
## (art/actors, cut by tools/actor_sprites.py), seen from the same 3/4 angle as the room.
## The simulation does not change: collisions stay on the floor, only the drawing stands up.
## An actor's _draw calls figure() instead of its flat art while `on` is set.

const BOLT_LIFT := 14.0 # projectiles fly at chest height
const FEET := 0.45 # the feet stand this far below the floor point, in radii, so the body covers it
const WALK_MS := 110 # per walk frame
const IDLE_MS := 520 # per idle frame

static var on := false # set by Game for each room
static var _tex := {}


static func texture(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://art/actors/%s.png" % name)
	return _tex[name]


## Where the feet of an actor with this radius stand.
static func feet(r: float) -> Vector2:
	return Vector2(0, r * FEET)


## Shadow, then the sprite frame for the facing, walk cycle and pose, standing on the feet point.
## pose counts back from the last frame of a row: 1 is the attack pose, 2 the one before it.
static func figure(ci: CanvasItem, fig: String, r: float, face: Vector2, moving: bool, pose := 0, mod := Color.WHITE, lift := 0.0) -> void:
	var d: Dictionary = FigureData.FIGURES[fig]
	var cell: Vector2 = d.cell
	var n: int = d.frames
	var foot := feet(r)
	ci.draw_set_transform(foot, 0.0, Vector2(1.0, 0.45))
	ci.draw_circle(Vector2.ZERO, r * 1.1, Color(0, 0, 0, 0.42 * mod.a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var row := 0 # down, up, left, right as in the source sheets
	if absf(face.x) > absf(face.y):
		row = 2 if face.x < 0.0 else 3
	elif face.y < 0.0:
		row = 1
	var seed := ci.get_instance_id() % 997
	var col := (Time.get_ticks_msec() / IDLE_MS + seed) % 2
	if pose > 0:
		col = n - pose
	elif moving:
		col = 2 + (Time.get_ticks_msec() / WALK_MS + seed) % 4
	var size := cell / FigureData.RES
	var pad := float(FigureData.PAD) / FigureData.RES
	var rect := Rect2(foot + Vector2(-size.x * 0.5, -size.y + pad + lift), size)
	ci.draw_texture_rect_region(texture(fig), rect, Rect2(Vector2(col, row) * cell, cell), mod)


## A held weapon, turned to the aim; flipped when it points left so it is never upside down.
static func weapon(ci: CanvasItem, name: String, hand: Vector2, angle: float, mod := Color.WHITE) -> void:
	var flip := -1.0 if absf(wrapf(angle, -PI, PI)) > PI * 0.5 else 1.0
	ci.draw_set_transform(hand, angle, Vector2(1.0, flip) / FigureData.RES)
	ci.draw_texture(texture(name), -FigureData.WEAPONS[name], mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


const MUZZLE_TIP := { # barrel tip in atlas pixels, measured from the grip, gun facing right
	"coil_gun": Vector2(46.6, -5.4),
}


## Where a weapon's muzzle actually sits, world space: the grip point rotated to the aim plus
## the barrel's own length and lift, so an emitted beam or bolt starts at the visible barrel tip
## instead of the body's centre (noticeable side-on, where the barrel sits well above the grip).
static func muzzle(name: String, hand: Vector2, angle: float) -> Vector2:
	var flip := -1.0 if absf(wrapf(angle, -PI, PI)) > PI * 0.5 else 1.0
	var tip: Vector2 = MUZZLE_TIP.get(name, Vector2(20.0 * FigureData.RES, 0.0))
	return hand + Vector2(tip.x, tip.y * flip).rotated(angle) / FigureData.RES


## Hit flash for a sprite: a modulate above white brightens it.
static func flash(frames: int, crit: bool) -> Color:
	if frames <= 0:
		return Color.WHITE
	var k := 3.0 if frames == 3 else 2.0
	return Color(k, k * 0.95, k * 0.6) if crit else Color(k, k, k)


## Projectiles: a small shadow on the floor, then the shot drawn at chest height.
static func bolt(ci: CanvasItem, r := 4.0) -> void:
	if not on:
		return
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	ci.draw_circle(Vector2.ZERO, r, Color(0, 0, 0, 0.35))
	ci.draw_set_transform(Vector2(0, -BOLT_LIFT), 0.0, Vector2.ONE)
