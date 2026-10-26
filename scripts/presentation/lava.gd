class_name Lava
## Shared molten-puddle drawing (dash pools, Molten items, Forgewarden's floor hazard):
## an irregular crusted blob instead of a perfect circle, generated in code like the rest of
## the art (GDD section 8: Molten = round blobs, but a lava pool's edge is never that clean).

const SEGS := 16


## A wobbly ring, `r` on average, that settles into a slightly different shape each call of
## the clock so the puddle looks alive without being a simple pulsing circle.
static func _blob(r: float, t: float, seed: float, segs := SEGS) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var ang := i * TAU / segs
		var wob := 1.0 + 0.14 * sin(ang * 3.0 + seed + t * 0.5) + 0.07 * sin(ang * 7.0 - seed * 1.7 + t * 0.8)
		pts.append(Vector2.from_angle(ang) * r * wob)
	return pts


## Draws a molten puddle of average radius `r` on `ci`, fading with `fade` (0-1). `rim_color`
## distinguishes a player-damaging hazard (C.TELE_GROUND, matching every other ground telegraph)
## from a pool that only burns enemies (the default warm orange).
static func pool(ci: CanvasItem, r: float, t: float, seed: float, fade: float, rim_color := Color(1.0, 0.6, 0.2)) -> void:
	var outer := _blob(r, t, seed)
	var inner := _blob(r * 0.68, t * 1.3, seed + 5.0)
	ci.draw_colored_polygon(outer, Color(0.3, 0.1, 0.04, 0.55 * fade)) # dark crust base
	var core := PackedVector2Array()
	for p in outer:
		core.append(p * 0.92)
	ci.draw_colored_polygon(core, Color(0.75, 0.28, 0.05, 0.6 * fade))
	ci.draw_colored_polygon(inner, Color(1.0, 0.55, 0.15, 0.55 * fade))
	# Glossy blobs with a highlight, bubbling.
	for i in 5:
		var ang := i * TAU / 5.0 + t * 0.4
		var br := r * (0.3 + 0.25 * sin(t * 2.0 + i))
		var p := Vector2.from_angle(ang) * br
		var s := r * 0.18 * (0.8 + 0.2 * sin(t * 5.0 + i * 1.7))
		ci.draw_circle(p, s, Color(1.0, 0.75, 0.3, 0.75 * fade))
		ci.draw_circle(p + Vector2(-s * 0.3, -s * 0.3), s * 0.3, Color(1, 1, 0.85, 0.85 * fade))
	# A thin bright seam along the crust's broken edge, not a clean circular rim.
	var rim := outer.duplicate()
	rim.append(outer[0])
	ci.draw_polyline(rim, Color(rim_color, 0.6 * fade), 2.5)
