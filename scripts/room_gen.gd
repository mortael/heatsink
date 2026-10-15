class_name RoomGen
## Procedural combat rooms (GDD section 6): stamps wall shapes into an empty 24x13 chunk,
## usually mirrored so the room reads as designed rather than random.
##
## Rules, matching the hand-authored Layouts:
## - shapes only go in rows 3-9 and columns 3-20, so rows 1-2 (doors), rows 10-11 (entry)
##   and a two-tile lane along each side wall stay open;
## - every floor tile is reachable from the entry, so nothing can spawn in a sealed pocket;
## - few single-tile slits, so bodies and the pathing don't snag;
## - wall count stays in a band so a room is never empty or a maze;
## - cover sits in at least three of the four quarters, so no half of the room is bare.
## A room that breaks a rule is thrown away and rolled again.

enum Sym { MIRROR_X, MIRROR_XY, ROTATE, NONE }

const AREA := Rect2i(3, 3, 18, 7) # x 3-20, y 3-9
const MIN_WALLS := 10
const MAX_WALLS := 36
const MAX_SLITS := 2
const ATTEMPTS := 40

## Shapes as rows of '#' (wall) and '.' (skip). Each gets a random flip/transpose when placed.
const STAMPS := [
	["#"],
	["##", "##"],
	["###"],
	["####"],
	["#####"],
	["######"],
	["###", "###"],
	["###", "#.."],
	["####", "#..."],
	["###", ".#."],
	[".#.", "###", ".#."],
	["#..#", "####"],
	["#...#", "#...#"],
	["##..", ".##."],
]
const SYM_WEIGHTS := {Sym.MIRROR_X: 35, Sym.MIRROR_XY: 30, Sym.ROTATE: 20, Sym.NONE: 15}

static var fallbacks := 0 # times generate() gave up; tests read this


## Returns a fresh layout in the same format as Layouts.COMBAT, or Layouts.COMBAT[0] if
## every attempt failed (has not happened in testing, but the game must never get stuck).
## density scales the wall budget: Elite rooms use less so the Forgewarden has space to turn.
static func generate(rng: RandomNumberGenerator, density := 1.0) -> Array[String]:
	for attempt in ATTEMPTS:
		var grid := _blank()
		var sym := _pick_sym(rng)
		var budget := int(rng.randi_range(16, 32) * density)
		var walls := 0
		for tries in 80:
			if walls >= budget:
				break
			var cells := _place(rng, sym)
			if cells.is_empty() or not _fits(grid, cells):
				continue
			for c: Vector2i in cells:
				if not grid[c.y][c.x]:
					grid[c.y][c.x] = true
					walls += 1
		if is_good(grid):
			return _to_lines(grid)
	fallbacks += 1
	push_warning("RoomGen: no valid room in %d attempts, using the Pillars template" % ATTEMPTS)
	var fallback: Array[String] = []
	fallback.assign(Layouts.COMBAT[0])
	return fallback


## True when the grid passes every rule above. Public so tests can check the templates too.
static func is_good(grid: Array) -> bool:
	var walls := 0
	var floor_tiles := 0
	var quarters := {}
	for y in range(1, C.ROOM_H - 1):
		for x in range(1, C.ROOM_W - 1):
			if grid[y][x]:
				walls += 1
				quarters[Vector2i(int(x * 2 >= C.ROOM_W), int(y * 2 > C.ROOM_H))] = true
			else:
				floor_tiles += 1
	if walls < MIN_WALLS or walls > MAX_WALLS or quarters.size() < 3:
		return false
	return _flood(grid, Room.ENTRY_TILE) == floor_tiles and slits(grid) <= MAX_SLITS


## Open tiles squeezed between walls on opposite sides (a one-tile gap).
static func slits(grid: Array) -> int:
	var n := 0
	for y in range(1, C.ROOM_H - 1):
		for x in range(1, C.ROOM_W - 1):
			if grid[y][x]:
				continue
			if (grid[y][x - 1] and grid[y][x + 1]) or (grid[y - 1][x] and grid[y + 1][x]):
				n += 1
	return n


static func to_grid(lines: Array) -> Array:
	var grid := []
	for y in C.ROOM_H:
		var row := []
		for x in C.ROOM_W:
			row.append(lines[y][x] == "#")
		grid.append(row)
	return grid


static func _blank() -> Array:
	var grid := []
	for y in C.ROOM_H:
		var row := []
		for x in C.ROOM_W:
			row.append(x == 0 or y == 0 or x == C.ROOM_W - 1 or y == C.ROOM_H - 1)
		grid.append(row)
	return grid


static func _pick_sym(rng: RandomNumberGenerator) -> Sym:
	var total := 0
	for w: int in SYM_WEIGHTS.values():
		total += w
	var roll := rng.randi_range(0, total - 1)
	for s: Sym in SYM_WEIGHTS:
		roll -= SYM_WEIGHTS[s]
		if roll < 0:
			return s
	return Sym.NONE


## One random stamp at a random spot, plus its symmetric copies. Empty if it leaves the area.
static func _place(rng: RandomNumberGenerator, sym: Sym) -> Array[Vector2i]:
	var shape := _shape(rng)
	var w := 0
	var h := 0
	for c: Vector2i in shape:
		w = maxi(w, c.x + 1)
		h = maxi(h, c.y + 1)
	if w > AREA.size.x or h > AREA.size.y:
		return []
	var at := Vector2i(rng.randi_range(AREA.position.x, AREA.end.x - w), rng.randi_range(AREA.position.y, AREA.end.y - h))
	var mx := C.ROOM_W - 1
	var my := C.ROOM_H - 1
	var out: Array[Vector2i] = []
	for c: Vector2i in shape:
		var p := at + c
		out.append(p)
		match sym:
			Sym.MIRROR_X:
				out.append(Vector2i(mx - p.x, p.y))
			Sym.MIRROR_XY:
				out.append(Vector2i(mx - p.x, p.y))
				out.append(Vector2i(p.x, my - p.y))
				out.append(Vector2i(mx - p.x, my - p.y))
			Sym.ROTATE:
				out.append(Vector2i(mx - p.x, my - p.y))
	return out


static func _shape(rng: RandomNumberGenerator) -> Array[Vector2i]:
	var rows: Array = STAMPS[rng.randi_range(0, STAMPS.size() - 1)]
	var flip_x := rng.randf() < 0.5
	var flip_y := rng.randf() < 0.5
	var transpose := rng.randf() < 0.5
	var h := rows.size()
	var w: int = rows[0].length()
	var out: Array[Vector2i] = []
	for y in h:
		for x in w:
			if rows[y][x] != "#":
				continue
			var c := Vector2i(w - 1 - x if flip_x else x, h - 1 - y if flip_y else y)
			out.append(Vector2i(c.y, c.x) if transpose else c)
	return out


## A stamp may not touch or sit one tile away from an earlier shape (that would make slits
## and odd merged blobs); its own symmetric copies may touch each other.
static func _fits(grid: Array, cells: Array[Vector2i]) -> bool:
	var own := {}
	for c: Vector2i in cells:
		if not AREA.has_point(c):
			return false
		own[c] = true
	for c: Vector2i in cells:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var n := c + Vector2i(dx, dy)
				if own.has(n) or n.x <= 0 or n.y <= 0 or n.x >= C.ROOM_W - 1 or n.y >= C.ROOM_H - 1:
					continue
				if grid[n.y][n.x]:
					return false
	return true


static func _flood(grid: Array, from: Vector2i) -> int:
	if grid[from.y][from.x]:
		return 0
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := cur + d
			if not grid[n.y][n.x] and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.size()


static func _to_lines(grid: Array) -> Array[String]:
	var out: Array[String] = []
	for y in C.ROOM_H:
		var s := ""
		for x in C.ROOM_W:
			s += "#" if grid[y][x] else "."
		out.append(s)
	return out
