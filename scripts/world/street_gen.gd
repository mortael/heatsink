class_name StreetGen
## Procedural Rainside yards. RoomGen places the cover with its usual rules, kept clear of the
## hall and the door walkway, then every wall shape is dressed as props: long runs become crash
## barriers, pairs become crate stacks, scrap bins or pipe stacks (or a slag wagon when they stand
## north-south), single tiles become tanks, floodlights, consoles, gas bottles or ingot pallets.
## Picks are keyed on the mirrored position, so a symmetric room gets symmetric props.

const AREA := Rect2i(3, 5, 18, 5) # cover rows 5-9: row 3 is the walkway to the doors, rows 10-11 the entry
const TEMPLATE_CHANCE := 0.2
const PAIRS := "cdp"
const SINGLES := "TTLLmggi"
const LIGHTS := "TLmiv" # props that light the yard
const MIN_LIGHTS := 2
const HALL_ROWS := 3


## A layout ready for StreetRoom: {"backdrop": index, "lines": prop chars, "props": [...]}.
static func generate(rng: RandomNumberGenerator) -> Dictionary:
	var backdrop := rng.randi_range(0, StreetData.BACKDROPS.size() - 1)
	if rng.randf() < TEMPLATE_CHANCE:
		var t: Dictionary = StreetData.TEMPLATES[rng.randi_range(0, StreetData.TEMPLATES.size() - 1)]
		return layout(t.lines, t.backdrop, rng.randi())
	var fell_back := RoomGen.fallbacks
	var lines := RoomGen.generate(rng, 0.8, AREA)
	if RoomGen.fallbacks > fell_back: # its fallback is a flat room's layout: use a hand-made yard instead
		var t: Dictionary = StreetData.TEMPLATES[0]
		return layout(t.lines, t.backdrop, rng.randi())
	for y in range(1, HALL_ROWS):
		lines[y] = "#".repeat(C.ROOM_W)
	return layout(_dress(lines, rng.randi()), backdrop, rng.randi())


## Groups prop chars into props and picks each one's art variant.
static func layout(lines: Array, backdrop: int, salt: int) -> Dictionary:
	var props := []
	var seen := {}
	for y in C.ROOM_H:
		for x in C.ROOM_W:
			var ch: String = lines[y][x]
			if ch == "#" or ch == "." or seen.has(Vector2i(x, y)):
				continue
			var n := 1
			var key := ch
			if ch == "v":
				seen[Vector2i(x, y + 1)] = true
			elif ch in StreetData.WIDE:
				n = 2
			elif ch == "h":
				while x + n < C.ROOM_W and n < 6 and lines[y][x + n] == "h": # longer runs are two barriers
					n += 1
				key = "h%d" % n
			for i in n:
				seen[Vector2i(x + i, y)] = true
			var variants: Array = StreetData.PROPS[key]
			props.append({"key": key, "tile": Vector2i(x, y), "variant": _pick(x, y, n, salt) % variants.size()})
	var walls: Array[String] = [] # the collision grid: every prop tile is solid
	for row: String in lines:
		var r := ""
		for ch in row:
			r += "." if ch == "." else "#"
		walls.append(r)
	return {"backdrop": backdrop, "lines": walls, "props": props}


## Turns the generator's '#' cover into prop chars.
static func _dress(lines: Array[String], salt: int) -> Array[String]:
	var g := []
	for row in lines:
		g.append(row.split(""))
	var free := func(x: int, y: int) -> bool: return AREA.has_point(Vector2i(x, y)) and g[y][x] == "#"
	var singles: Array[Vector2i] = []
	var pairs: Array[Vector2i] = []
	for y in range(AREA.position.y, AREA.end.y):
		var x := AREA.position.x
		while x < AREA.end.x:
			if not free.call(x, y):
				x += 1
				continue
			var run := 0
			while free.call(x + run, y):
				run += 1
			if run >= 3:
				for i in mini(run, 6):
					g[y][x + i] = "h"
				x += mini(run, 6)
			elif run == 2:
				var ch := PAIRS[_pick(x, y, 2, salt) % PAIRS.length()]
				g[y][x] = ch
				g[y][x + 1] = ch
				pairs.append(Vector2i(x, y))
				x += 2
			elif free.call(x, y + 1) and not free.call(x + 1, y + 1) and not free.call(x - 1, y + 1):
				g[y][x] = "v"
				g[y + 1][x] = "v"
				x += 1
			else:
				g[y][x] = SINGLES[_pick(x, y, 1, salt) % SINGLES.length()]
				singles.append(Vector2i(x, y))
				x += 1
	# Enough lamps that the yard is not a black hole: swap singles nearest the middle for floodlights,
	# and when there are too few singles, split pairs into a floodlight and a tank.
	var lights := 0
	for row in g:
		for ch: String in row:
			if ch in LIGHTS:
				lights += 1 if ch != "v" else 0
	for row in g:
		lights += "".join(row).count("v") / 2 # one lit load per wagon, on two tiles
	var middle_first := func(a: Vector2i, b: Vector2i) -> bool: return absf(a.x - 11.5) < absf(b.x - 11.5)
	singles.sort_custom(middle_first)
	pairs.sort_custom(middle_first)
	for c in singles:
		if lights >= MIN_LIGHTS:
			break
		if not (g[c.y][c.x] in LIGHTS):
			g[c.y][c.x] = "L"
			lights += 1
	for c in pairs:
		if lights >= MIN_LIGHTS:
			break
		g[c.y][c.x] = "L"
		g[c.y][c.x + 1] = "T"
		lights += 2
	var out: Array[String] = []
	for row in g:
		out.append("".join(row))
	return out


## A stable pick for a prop of width n at (x, y), the same for its mirror image across the room.
static func _pick(x: int, y: int, n: int, salt: int) -> int:
	var c2 := 2 * x + n - 1 # doubled centre column
	var key := mini(c2, 2 * (C.ROOM_W - 1) - c2)
	return absi(hash([key, mini(y, C.ROOM_H - 1 - y), salt]))
