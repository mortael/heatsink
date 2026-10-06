class_name Room
extends Node2D
## One 24x13 chunk built from a layout template (see Layouts). Doors sit in the top wall,
## the entry in the bottom wall. Also answers walkability questions for spawning and the bot.

const DOOR_TILES := [6, 12, 18] # x of each door slot's centre line, in tiles
const ENTRY_TILE := Vector2i(12, 11)

var lines: Array[String] = []
var solid: Array = [] # solid[y][x] -> bool
var rects: Array[Rect2] = []
var size_px := Vector2(C.ROOM_W * C.TILE, C.ROOM_H * C.TILE)
var accent := Color(0.9, 0.4, 0.1)


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


## True when the entry and every door slot are connected by open floor.
func is_valid() -> bool:
	var reach := _flood(ENTRY_TILE)
	for dx: int in DOOR_TILES:
		if not reach.has(Vector2i(dx, 1)) or not reach.has(Vector2i(dx - 1, 1)):
			return false
	return true


func center() -> Vector2:
	return size_px * 0.5


func entry_point() -> Vector2:
	return Vector2(ENTRY_TILE.x * C.TILE, (ENTRY_TILE.y + 0.5) * C.TILE)


## Where the player stands to walk through door slot i.
func door_point(slot: int) -> Vector2:
	return Vector2(DOOR_TILES[slot] * C.TILE, 1.0 * C.TILE)


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


func random_open_point(margin := 24.0) -> Vector2:
	for i in 60:
		var p := Vector2(randf_range(C.TILE, size_px.x - C.TILE), randf_range(C.TILE, size_px.y - C.TILE))
		if is_open(p, margin):
			return p
	return center()


## True when a body of this radius could travel straight from a to b without touching a wall tile.
func has_los(a: Vector2, b: Vector2, body_radius := 0.0) -> bool:
	var d := b - a
	var n := maxi(1, int(d.length() / 10.0))
	var side := d.normalized().orthogonal() * body_radius
	for i in n + 1:
		var p := a + d * (float(i) / n)
		if not tile_open(to_tile(p)) or not tile_open(to_tile(p + side)) or not tile_open(to_tile(p - side)):
			return false
	return true


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


func _flood(from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := cur + d
			if tile_open(n) and not seen.has(n):
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
