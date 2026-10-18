class_name Upright
## 2.5D figures for the Rainside rooms: an actor's top-down art becomes the lid of a short
## body standing on its floor position, seen from the same 3/4 angle as the room. The simulation
## does not change: collisions stay on the floor, only the drawing is lifted.
## An actor's _draw calls body() before its art and xf() wherever it would call draw_set_transform.

const SQUASH := 0.8 # a round lid seen at 3/4 is an ellipse
const BOLT_LIFT := 14.0 # projectiles fly at chest height

static var on := false # set by Game for each room


## Shadow on the floor, feet that step while the actor moves, and the body below the lid;
## leaves the lift transform active for the art. feet: 0 for actors whose art already has legs.
static func body(ci: CanvasItem, r: float, h: float, col: Color, feet := 2) -> void:
	if not on:
		return
	const HOVER := 5.0 # the body stands this high on its feet
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	ci.draw_circle(Vector2(0, 2.0), r * 1.15, Color(0, 0, 0, 0.42))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var lift := HOVER if feet > 0 else 0.0
	if feet > 0:
		var moving := ci is CharacterBody2D and (ci as CharacterBody2D).velocity.length() > 20.0
		var phase := Time.get_ticks_msec() / 85.0 + ci.get_instance_id() % 7 if moving else 0.0
		var fw := r * (0.55 if feet == 2 else 0.4)
		for i in feet:
			var x := lerpf(-r * 0.5, r * 0.5, float(i) / maxf(1.0, feet - 1.0))
			var step := sin(phase + i * PI) * 2.5
			ci.draw_rect(Rect2(x - fw * 0.5, -HOVER - 1.0 + minf(step, 0.0), fw, HOVER + 2.0), col.darkened(0.75))
			ci.draw_rect(Rect2(x - fw * 0.5, minf(step, 0.0) - 1.0, fw, 2.0), col.darkened(0.4))
	# The front of the body: a band between the bottom ellipse and the lid ellipse.
	var base := Vector2(0, -lift)
	ci.draw_set_transform(base, 0.0, Vector2(1.0, SQUASH))
	ci.draw_circle(Vector2.ZERO, r, col.darkened(0.55))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_rect(Rect2(-r, -h - lift, 2.0 * r, h), col.darkened(0.45))
	ci.draw_rect(Rect2(-r * 0.75, -h - lift, r * 0.5, h), col.lightened(0.08)) # light from the upper left
	ci.draw_rect(Rect2(r * 0.55, -h - lift, r * 0.45, h), col.darkened(0.65))
	ci.draw_line(Vector2(-r, -h * 0.45 - lift), Vector2(r, -h * 0.45 - lift), col.darkened(0.7), 1.5) # panel seam
	ci.set_meta("upright_h", h + lift)
	xf(ci)


## Stands in for draw_set_transform: the same transform, lifted onto the lid while 2.5D is on.
static func xf(ci: CanvasItem, pos := Vector2.ZERO, rot := 0.0, scl := Vector2.ONE) -> void:
	if not on:
		ci.draw_set_transform(pos, rot, scl)
		return
	var h: float = ci.get_meta("upright_h", 0.0)
	var lid := Transform2D(0.0, Vector2(1.0, SQUASH), 0.0, Vector2(0, -h))
	ci.draw_set_transform_matrix(lid * Transform2D(rot, scl, 0.0, pos))


## Back to plain floor drawing (telegraphs, rings around the feet).
static func ground(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Projectiles: a small shadow on the floor, then the shot drawn at chest height.
static func bolt(ci: CanvasItem, r := 4.0) -> void:
	if not on:
		return
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	ci.draw_circle(Vector2.ZERO, r, Color(0, 0, 0, 0.35))
	ci.draw_set_transform(Vector2(0, -BOLT_LIFT), 0.0, Vector2.ONE)
