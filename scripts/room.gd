class_name Room
extends Node2D
## One hand-made 24x13 chunk: border walls plus four 2x2 pillars (cover sockets).

const PILLARS := [Vector2i(5, 3), Vector2i(17, 3), Vector2i(5, 8), Vector2i(17, 8)]

var rects: Array[Rect2] = []
var size_px := Vector2(C.ROOM_W * C.TILE, C.ROOM_H * C.TILE)


func _ready() -> void:
	var t := C.TILE
	_solid(Rect2(0, 0, size_px.x, t))
	_solid(Rect2(0, size_px.y - t, size_px.x, t))
	_solid(Rect2(0, 0, t, size_px.y))
	_solid(Rect2(size_px.x - t, 0, t, size_px.y))
	for p: Vector2i in PILLARS:
		_solid(Rect2(p.x * t, p.y * t, 2 * t, 2 * t))
	z_index = 0


func center() -> Vector2:
	return size_px * 0.5


func is_open(p: Vector2, margin := 20.0) -> bool:
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
		draw_line(Vector2(r.position.x, r.end.y), r.end, Color(0.9, 0.4, 0.1, 0.55), 2.0)
	draw_rect(Rect2(Vector2.ZERO, size_px), Color(0.9, 0.4, 0.1, 0.25), false, 2.0)
