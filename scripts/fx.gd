class_name Fx
extends Node2D
## Lightweight particle, ring, portal and damage-number renderer.
## Particle silhouettes follow GDD section 8: shrapnel = triangles, molten/slag = round blobs, sparks = streaks.

const MAX_PARTS := 500

var parts: Array = [] # [pos, vel, life, max_life, shape, color, size, rot, spin, drag]
var rings: Array = [] # [pos, radius, color, life, max_life]
var texts: Array = [] # [pos, text, color, size, life, max_life]
var portals: Array = [] # [pos, life, max_life]
var arcs: Array = [] # [from, to, life, max_life]


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	for i in range(parts.size() - 1, -1, -1):
		var p: Array = parts[i]
		p[2] -= delta
		if p[2] <= 0.0:
			parts.remove_at(i)
			continue
		p[0] += p[1] * delta
		p[1] *= pow(p[9], delta)
		p[7] += p[8] * delta
	for i in range(rings.size() - 1, -1, -1):
		rings[i][3] -= delta
		if rings[i][3] <= 0.0:
			rings.remove_at(i)
	for i in range(texts.size() - 1, -1, -1):
		texts[i][4] -= delta
		texts[i][0] += Vector2(0, -48.0) * delta
		if texts[i][4] <= 0.0:
			texts.remove_at(i)
	for i in range(arcs.size() - 1, -1, -1):
		arcs[i][2] -= delta
		if arcs[i][2] <= 0.0:
			arcs.remove_at(i)
	for i in range(portals.size() - 1, -1, -1):
		portals[i][1] -= delta
		if portals[i][1] <= 0.0:
			portals.remove_at(i)
	queue_redraw()


func _add(pos: Vector2, vel: Vector2, life: float, shape: String, color: Color, size: float, drag := 0.02) -> void:
	if parts.size() >= MAX_PARTS:
		parts.remove_at(0)
	parts.append([pos, vel, life, life, shape, color, size, randf() * TAU, randf_range(-12.0, 12.0), drag])


func sparks(pos: Vector2, normal: Vector2, n: int, color: Color) -> void:
	for i in n:
		var v := normal.rotated(randf_range(-1.1, 1.1)) * randf_range(120.0, 320.0)
		_add(pos, v, randf_range(0.12, 0.25), "spark", color, 2.0, 0.005)


func trail(pos: Vector2, color: Color) -> void:
	_add(pos + Vector2(randf_range(-6, 6), randf_range(-6, 6)), Vector2.ZERO, 0.18, "circle", Color(color, 0.5), 9.0)


func pop(pos: Vector2, color: Color) -> void:
	for i in 10:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(80.0, 260.0)
		_add(pos, v, randf_range(0.25, 0.5), "circle", color.lerp(Color(1, 0.55, 0.2), randf() * 0.5), randf_range(3.0, 6.0), 0.01)
	for i in 4:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(150.0, 300.0)
		_add(pos, v, 0.3, "spark", Color(1, 0.7, 0.3), 2.0, 0.005)
	ring(pos, 22.0, Color(1, 0.6, 0.25, 0.8), 0.15)


func rivet_burst(pos: Vector2, count: int) -> void:
	for i in 4 + count * 2:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(180.0, 380.0)
		_add(pos, v, randf_range(0.2, 0.35), "tri", Color(0.82, 0.85, 0.9), randf_range(4.0, 6.0), 0.01)
	ring(pos, C.TILE, Color(1, 1, 1, 0.9), 0.16)


func vent_embers(pos: Vector2, radius: float, amount: float) -> void:
	var n := int(8 + amount * 0.3)
	for i in n:
		var dir := Vector2.from_angle(randf() * TAU)
		_add(pos + dir * 10.0, dir * radius * randf_range(2.0, 3.2), randf_range(0.25, 0.45), "teardrop", Color(1, randf_range(0.45, 0.8), 0.2), randf_range(3.0, 5.0), 0.004)


func ring(pos: Vector2, radius: float, color: Color, life: float) -> void:
	rings.append([pos, radius, color, life, life])


func number(pos: Vector2, value: float, crit: bool, color := Color.WHITE, size := 18) -> void:
	var txt := str(int(round(value))) + ("!" if crit else "")
	var col := Color(1, 0.85, 0.2) if crit else color
	texts.append([pos + Vector2(randf_range(-8, 8), 0), txt, col, 28 if crit else size, 0.5, 0.5])


## Ignite: rising orange teardrop embers.
func ember(pos: Vector2) -> void:
	_add(pos, Vector2(randf_range(-15, 15), randf_range(-70, -40)), randf_range(0.3, 0.5), "teardrop", Color(1, randf_range(0.4, 0.7), 0.15), randf_range(2.0, 3.0), 0.3)


## Arc: jagged cyan-white polyline, redrawn with new jitter every frame.
func arc(from: Vector2, to: Vector2, life := 0.12) -> void:
	arcs.append([from, to, life, life])


func portal(pos: Vector2, time: float) -> void:
	portals.append([pos, time, time])


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for pt in portals:
		var k: float = 1.0 - pt[1] / pt[2]
		draw_circle(pt[0], 6.0 + 14.0 * k, Color(1, 0.45, 0.15, 0.15 + 0.25 * k))
		draw_arc(pt[0], 20.0 - 6.0 * k, 0, TAU, 20, Color(1, 0.7, 0.35, 0.8), 2.0)
	for a in arcs:
		var from: Vector2 = a[0]
		var to: Vector2 = a[1]
		var k: float = a[2] / a[3]
		var segs := maxi(3, int(from.distance_to(to) / 28.0))
		var normal := (to - from).normalized().orthogonal()
		var pts := PackedVector2Array([from])
		for i in range(1, segs):
			pts.append(from.lerp(to, float(i) / segs) + normal * randf_range(-10.0, 10.0))
		pts.append(to)
		draw_polyline(pts, Color(0.4, 0.9, 1.0, 0.35 * k), 7.0)
		draw_polyline(pts, Color(0.85, 0.97, 1.0, k), 2.0)
	for r in rings:
		var k: float = 1.0 - r[3] / r[4]
		var rad: float = r[1] * (0.25 + 0.75 * sqrt(k))
		var c: Color = r[2]
		draw_arc(r[0], rad, 0, TAU, 48, Color(c, c.a * (1.0 - k)), 6.0 * (1.0 - k) + 1.0)
		draw_circle(r[0], rad, Color(c, 0.08 * (1.0 - k)))
	for p in parts:
		var k: float = p[2] / p[3]
		var c: Color = p[5]
		c.a *= k
		var pos: Vector2 = p[0]
		var s: float = p[6]
		match p[4]:
			"circle":
				draw_circle(pos, s * (0.4 + 0.6 * k), c)
			"spark":
				var v: Vector2 = p[1]
				draw_line(pos, pos - v * 0.03, c, s)
			"tri":
				var r: float = p[7]
				var pts := PackedVector2Array([
					pos + Vector2.from_angle(r) * s,
					pos + Vector2.from_angle(r + 2.4) * s * 0.7,
					pos + Vector2.from_angle(r - 2.4) * s * 0.7,
				])
				draw_colored_polygon(pts, c)
			"teardrop":
				var v2: Vector2 = p[1]
				var d := v2.normalized()
				draw_circle(pos, s * k, c)
				draw_line(pos, pos - d * s * 3.0 * k, c, s * k)
	for t in texts:
		var k: float = t[4] / t[5]
		var c: Color = t[2]
		c.a = clampf(k * 2.0, 0.0, 1.0)
		var size: int = t[3]
		var pop := 1.0
		if size > 20 and k > 0.85:
			pop = 1.25
		var fs := int(size * pop)
		draw_string_outline(font, t[0] - Vector2(fs * 0.6, 0), t[1], HORIZONTAL_ALIGNMENT_CENTER, fs * 1.2, fs, 4, Color(0, 0, 0, c.a))
		draw_string(font, t[0] - Vector2(fs * 0.6, 0), t[1], HORIZONTAL_ALIGNMENT_CENTER, fs * 1.2, fs, c)
