class_name Room
extends Node2D
## One 24x13 chunk built from a layout template (see Layouts). Doors sit in the top wall,
## the entry in the bottom wall. Also answers walkability questions for spawning and the bot.

const DOOR_TILES := [6, 12, 18] # x of each door slot's centre line, in tiles
const ENTRY_TILE := Vector2i(12, 11)
const RIM_RANGE := 3.0 * C.TILE # how far a bolt light reaches the wall faces (Lights.BOLT_RADIUS)
const RIM_DEPTH := 14.0 # px a face's glow reaches into the block

var lines: Array[String] = []
var solid: Array = [] # solid[y][x] -> bool
var rects: Array[Rect2] = []
var size_px := Vector2(C.ROOM_W * C.TILE, C.ROOM_H * C.TILE)
var accent := Color(0.9, 0.4, 0.1)
var occluders := true # walls throw light shadows (StreetRoom turns this off: its props stand up instead)
var door_row := 1 # tile row the player walks into to take a door (StreetRoom moves it down to its facade)
var _rim: Node2D # wall faces turned towards a bolt light catch its glow
var _rim_lights: Array = [] # [local pos, colour] per lit bolt this frame
var _rim_drawn := false


func _init(layout: Array = Layouts.COMBAT[0]) -> void:
	for row: String in layout:
		lines.append(row)
	for y in C.ROOM_H:
		var r: Array[bool] = []
		for x in C.ROOM_W:
			r.append(lines[y][x] == "#")
		solid.append(r)


func _ready() -> void:
	# Merge each row's wall runs into one body per run.
	var t := C.TILE
	for y in C.ROOM_H:
		var x := 0
		while x < C.ROOM_W:
			if not solid[y][x]:
				x += 1
				continue
			var start := x
			while x < C.ROOM_W and solid[y][x]:
				x += 1
			_solid(Rect2(start * t, y * t, (x - start) * t, t))
	z_index = 0
	var glow := Node2D.new()
	glow.material = Glow.additive()
	glow.draw.connect(_draw_glow.bind(glow))
	add_child(glow)
	_rim = Node2D.new()
	_rim.material = Glow.additive()
	_rim.draw.connect(_draw_rim)
	add_child(_rim)
	add_to_group("dynamic_lights")


## Called when the Lights & shadows setting changes, also while paused.
## Drops the rims now; the next frame redraws them if lights are still on.
func apply_lights() -> void:
	_rim_lights.clear()
	_rim.queue_redraw()


func _process(_delta: float) -> void:
	_rim_lights.clear()
	# Untyped on purpose: the room-generator test loads Room without the game's autoloads.
	for bolt in get_tree().get_nodes_in_group("bolts"):
		if bolt.lit: # only true while Lights has a light on it, so off with Lights & shadows off
			_rim_lights.append([to_local(bolt.global_position), bolt.light_color()])
	if not _rim_lights.is_empty() or _rim_drawn:
		_rim.queue_redraw()


## True when the entry and every door slot are connected by open floor.
func is_valid() -> bool:
	var reach := reachable_cells(solid, ENTRY_TILE)
	for dx: int in DOOR_TILES:
		if not reach.has(Vector2i(dx, door_row)) or not reach.has(Vector2i(dx - 1, door_row)):
			return false
	return true


func center() -> Vector2:
	return size_px * 0.5


func entry_point() -> Vector2:
	return Vector2(ENTRY_TILE.x * C.TILE, (ENTRY_TILE.y + 0.5) * C.TILE)


## Where the player stands to walk through door slot i.
func door_point(slot: int) -> Vector2:
	return Vector2(DOOR_TILES[slot] * C.TILE, door_row * C.TILE)


func tile_open(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < C.ROOM_W and tile.y < C.ROOM_H and not solid[tile.y][tile.x]


func to_tile(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / C.TILE)), int(floor(p.y / C.TILE)))


func is_open(p: Vector2, margin := 20.0) -> bool:
	if p.x < C.TILE + margin or p.y < C.TILE + margin or p.x > size_px.x - C.TILE - margin or p.y > size_px.y - C.TILE - margin:
		return false
	for r in rects:
		if r.grow(margin).has_point(p):
			return false
	return true


## Returns Vector2.INF when no floor position meets clearance and distance requirements.
func random_open_point(margin := 24.0, avoid := Vector2.ZERO, min_distance := 0.0) -> Vector2:
	for i in 60:
		var p := Vector2(randf_range(C.TILE, size_px.x - C.TILE), randf_range(C.TILE, size_px.y - C.TILE))
		if is_open(p, margin) and p.distance_to(avoid) >= min_distance:
			return p
	# Sampling exhaustion is not proof that the room has no valid position.
	for y in range(1, C.ROOM_H - 1):
		for x in range(1, C.ROOM_W - 1):
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) * C.TILE
			if is_open(p, margin) and p.distance_to(avoid) >= min_distance:
				return p
	return Vector2.INF


## True when a body of this radius could travel straight from a to b without touching a wall tile.
func has_los(a: Vector2, b: Vector2, body_radius := 0.0) -> bool:
	if not a.is_finite() or not b.is_finite() or not tile_open(to_tile(a)) or not tile_open(to_tile(b)):
		return false
	if body_radius > 0.0:
		return _has_swept_circle_los(a, b, body_radius)
	var d := b - a
	var n := maxi(1, int(d.length() / 10.0))
	for i in n + 1:
		var p := a + d * (float(i) / n)
		if not tile_open(to_tile(p)):
			return false
	return true


func _has_swept_circle_los(a: Vector2, b: Vector2, body_radius: float) -> bool:
	var t := C.TILE
	var min_x := maxi(0, int(floor((minf(a.x, b.x) - body_radius) / t)))
	var max_x := mini(C.ROOM_W - 1, int(floor((maxf(a.x, b.x) + body_radius) / t)))
	var min_y := maxi(0, int(floor((minf(a.y, b.y) - body_radius) / t)))
	var max_y := mini(C.ROOM_H - 1, int(floor((maxf(a.y, b.y) + body_radius) / t)))
	var radius_squared := body_radius * body_radius
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if solid[y][x] and _segment_distance_squared_to_rect(a, b, Rect2(x * t, y * t, t, t)) <= radius_squared:
				return false
	return true


func _segment_distance_squared_to_rect(a: Vector2, b: Vector2, rect: Rect2) -> float:
	if _segment_intersects_rect(a, b, rect):
		return 0.0
	var closest_a := Vector2(clampf(a.x, rect.position.x, rect.end.x), clampf(a.y, rect.position.y, rect.end.y))
	var closest_b := Vector2(clampf(b.x, rect.position.x, rect.end.x), clampf(b.y, rect.position.y, rect.end.y))
	var best := minf(a.distance_squared_to(closest_a), b.distance_squared_to(closest_b))
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		best = minf(best, _point_distance_squared_to_segment(corner, a, b))
	return best


func _segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var start := 0.0
	var finish := 1.0
	var direction := b - a
	for axis in 2:
		var origin := a.x if axis == 0 else a.y
		var delta := direction.x if axis == 0 else direction.y
		var lower := rect.position.x if axis == 0 else rect.position.y
		var upper := rect.end.x if axis == 0 else rect.end.y
		if is_zero_approx(delta):
			if origin < lower or origin > upper:
				return false
			continue
		var enter := (lower - origin) / delta
		var leave := (upper - origin) / delta
		if enter > leave:
			var swap := enter
			enter = leave
			leave = swap
		start = maxf(start, enter)
		finish = minf(finish, leave)
		if start > finish:
			return false
	return true


func _point_distance_squared_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var length_squared := segment.length_squared()
	if is_zero_approx(length_squared):
		return point.distance_squared_to(a)
	var nearest := a + segment * clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_squared_to(nearest)


## Tile-centre waypoints from a to b over open floor (4-way BFS). Empty if unreachable.
func path(a: Vector2, b: Vector2) -> Array[Vector2]:
	var start := to_tile(a)
	var goal := to_tile(b)
	var out: Array[Vector2] = []
	if not tile_open(start) or not tile_open(goal):
		return out
	var came := {start: start}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			break
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := cur + d
			if tile_open(n) and not came.has(n):
				came[n] = cur
				queue.append(n)
	if not came.has(goal):
		return out
	var step := goal
	while step != start:
		out.push_front((Vector2(step) + Vector2(0.5, 0.5)) * C.TILE)
		step = came[step]
	out.append(b)
	return out


## Shared connectivity check for runtime layouts and generator candidates.
static func reachable_cells(grid: Array, from: Vector2i) -> Dictionary:
	var height := grid.size()
	if height == 0:
		return {}
	var width: int = grid[0].size()
	if from.x < 0 or from.y < 0 or from.x >= width or from.y >= height or grid[from.y][from.x]:
		return {}
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := cur + d
			if n.x >= 0 and n.y >= 0 and n.x < width and n.y < height and not grid[n.y][n.x] and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


func _solid(r: Rect2) -> void:
	rects.append(r)
	var b := StaticBody2D.new()
	b.collision_layer = C.LAYER_WALL
	b.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = r.size
	cs.shape = sh
	cs.position = r.get_center()
	b.add_child(cs)
	add_child(b)
	# Walls block light, so Vents and slams throw shadows behind them.
	if not occluders:
		return
	var occ := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	occ.occluder = poly
	add_child(occ)


## The hot seams along the walls glow softly onto the floor.
func _draw_glow(glow: Node2D) -> void:
	var a := Color(accent, 0.35)
	for r in rects:
		if r.end.y >= size_px.y:
			continue # the bottom wall's seam faces out of the room
		Glow.strip(glow, Vector2(r.position.x, r.end.y), r.end, 16.0, a)
	var inner := Rect2(Vector2(C.TILE, C.TILE), size_px - Vector2(C.TILE, C.TILE) * 2.0)
	for side in [[inner.position, Vector2(inner.end.x, inner.position.y)], [inner.position, Vector2(inner.position.x, inner.end.y)],
			[Vector2(inner.end.x, inner.position.y), inner.end], [Vector2(inner.position.x, inner.end.y), inner.end]]:
		Glow.strip(glow, side[0], side[1], 10.0, Color(accent, 0.12))


## Wall and pillar faces that look towards a bolt light catch a rim of its colour, brightest
## nearest the bolt. Together with the shadow the light throws behind them, walls read as
## blocks with height instead of flat floor markings.
func _draw_rim() -> void:
	_rim_drawn = not _rim_lights.is_empty()
	var t := C.TILE
	for l: Array in _rim_lights:
		var p: Vector2 = l[0]
		var col: Color = l[1]
		var c := Vector2i((p / t).floor())
		for y in range(maxi(c.y - 3, 0), mini(c.y + 4, C.ROOM_H)):
			for x in range(maxi(c.x - 3, 0), mini(c.x + 4, C.ROOM_W)):
				if not solid[y][x]:
					continue
				var o := Vector2(x, y) * t
				# Each face that borders open floor, has the light in front of it and can see it.
				if p.y < o.y and _open(x, y - 1) and _sees(p, o + Vector2(t * 0.5, -1.0)):
					_rim_face(p, col, o, o + Vector2(t, 0), Vector2.DOWN)
				if p.y > o.y + t and _open(x, y + 1) and _sees(p, o + Vector2(t * 0.5, t + 1.0)):
					_rim_face(p, col, o + Vector2(0, t), o + Vector2(t, t), Vector2.UP)
				if p.x < o.x and _open(x - 1, y) and _sees(p, o + Vector2(-1.0, t * 0.5)):
					_rim_face(p, col, o, o + Vector2(0, t), Vector2.RIGHT)
				if p.x > o.x + t and _open(x + 1, y) and _sees(p, o + Vector2(t + 1.0, t * 0.5)):
					_rim_face(p, col, o + Vector2(t, 0), o + Vector2(t, t), Vector2.LEFT)


## True when no wall tile lies on the straight line from a to b (sampled every few px).
func _sees(a: Vector2, b: Vector2) -> bool:
	var steps := ceili(a.distance_to(b) / 8.0)
	for i in range(1, steps):
		var c := Vector2i((a.lerp(b, float(i) / steps) / C.TILE).floor())
		if not _open(c.x, c.y):
			return false
	return true


func _open(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < C.ROOM_W and y < C.ROOM_H and not solid[y][x]


## A glow band along one face from a to b, fading into the block along `inward`.
func _rim_face(p: Vector2, col: Color, a: Vector2, b: Vector2, inward: Vector2) -> void:
	const STEPS := 4
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var lit := false
	for i in STEPS + 1:
		var q := a.lerp(b, float(i) / STEPS)
		var k := clampf(1.0 - q.distance_to(p) / RIM_RANGE, 0.0, 1.0)
		lit = lit or k > 0.0
		pts.append(q)
		cols.append(Color(col, 0.9 * k * k))
	if not lit:
		return
	for i in range(STEPS, -1, -1):
		pts.append(pts[i] + inward * RIM_DEPTH)
		cols.append(Color(col, 0.0))
	_rim.draw_polygon(pts, cols)


func _draw() -> void:
	var t := C.TILE
	for x in C.ROOM_W:
		for y in C.ROOM_H:
			var shade := 0.11 if (x + y) % 2 == 0 else 0.095
			draw_rect(Rect2(x * t, y * t, t, t), Color(shade + 0.02, shade, shade - 0.01))
	for r in rects:
		draw_rect(r, Color(0.16, 0.13, 0.12))
		draw_rect(r.grow(-4), Color(0.21, 0.17, 0.15))
		# Glowing seam along the floor-facing edges
		draw_line(Vector2(r.position.x, r.end.y), r.end, Color(accent, 0.55), 2.0)
	draw_rect(Rect2(Vector2.ZERO, size_px), Color(accent, 0.25), false, 2.0)
	# Entry arch in the bottom wall
	var e := Vector2(ENTRY_TILE.x * t, size_px.y - t)
	draw_rect(Rect2(e.x - t, e.y, 2 * t, t), Color(0.07, 0.06, 0.06))
	draw_line(Vector2(e.x - t, e.y), Vector2(e.x + t, e.y), Color(accent, 0.35), 2.0)
