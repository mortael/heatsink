extends SceneTree
## Checks the procedural room generator: every room passes the rules, the game's own door check,
## and rooms don't repeat. Exits with code 1 on a failure.
## Run: godot --headless --path . -s res://tests/room_gen_test.gd -- [count] [seed]

const RoomScript = preload("res://scripts/world/room.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var count := int(args[0]) if args.size() > 0 else 2000
	var rng := RandomNumberGenerator.new()
	rng.seed = int(args[1]) if args.size() > 1 else 1
	var failures := 0
	if not _placement_boundary_contracts(rng):
		failures += 1
	if not _room_los_contracts():
		failures += 1
	if not _connectivity_contracts():
		failures += 1
	var seen := {}
	var walls_total := 0
	var started := Time.get_ticks_usec()
	for i in count:
		var density := 0.7 if i % 4 == 0 else 1.0
		var lines := RoomGen.generate(rng, density)
		var grid := RoomGen.to_grid(lines)
		var room := RoomScript.new(lines)
		var ok := RoomGen.is_good(grid) and room.is_valid()
		room.free()
		if not ok:
			failures += 1
			if failures <= 3:
				print("BAD ROOM:\n" + "\n".join(lines))
		seen["".join(lines)] = true
		for row: String in lines:
			walls_total += row.count("#")
	var fallbacks := RoomGen.fallbacks
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	var border := 2 * C.ROOM_W + 2 * (C.ROOM_H - 2)
	print("rooms: %d  unique: %d  failures: %d  fallbacks: %d" % [count, seen.size(), failures, fallbacks])
	print("avg inner walls: %.1f  avg ms per room: %.2f" % [float(walls_total) / count - border, ms / count])
	for i in 3:
		print("\n".join(RoomGen.generate(rng)) + "\n")
	quit(1 if failures > 0 or fallbacks > 0 or seen.size() < count * 0.98 else 0)


func _placement_boundary_contracts(rng: RandomNumberGenerator) -> bool:
	var grid := RoomGen.to_grid(RoomGen.generate(rng))
	var edge_cells: Array[Vector2i] = []
	for x in range(RoomGen.AREA.position.x, RoomGen.AREA.end.x):
		edge_cells.append(Vector2i(x, RoomGen.AREA.position.y))
		edge_cells.append(Vector2i(x, RoomGen.AREA.end.y - 1))
	for y in range(RoomGen.AREA.position.y + 1, RoomGen.AREA.end.y - 1):
		edge_cells.append(Vector2i(RoomGen.AREA.position.x, y))
		edge_cells.append(Vector2i(RoomGen.AREA.end.x - 1, y))
	var found_valid_edge := false
	for cell in edge_cells:
		if grid[cell.y][cell.x]:
			continue
		grid[cell.y][cell.x] = true
		if RoomGen.is_good(grid):
			found_valid_edge = true
			break
		grid[cell.y][cell.x] = false
	if not found_valid_edge:
		push_error("RoomGen accepts legal stamps on the AREA boundary")
		return false
	var side_lane := grid.duplicate(true)
	side_lane[5][1] = true
	var door_lane := grid.duplicate(true)
	door_lane[2][6] = true
	var entry_lane := grid.duplicate(true)
	entry_lane[10][12] = true
	if RoomGen.is_good(side_lane) or RoomGen.is_good(door_lane) or RoomGen.is_good(entry_lane):
		push_error("RoomGen rejects walls in side, door, and entry lanes")
		return false
	return true


func _room_los_contracts() -> bool:
	var lines: Array[String] = []
	for y in C.ROOM_H:
		var row := ""
		for x in C.ROOM_W:
			row += "#" if x == 0 or y == 0 or x == C.ROOM_W - 1 or y == C.ROOM_H - 1 else "."
		lines.append(row)
	lines[5] = lines[5].left(5) + "#" + lines[5].substr(6)
	var room := RoomScript.new(lines)
	var corner_case_clear := room.has_los(Vector2(230, 230), Vector2(230, 235))
	var corner_case_blocked := not room.has_los(Vector2(230, 230), Vector2(230, 235), 20.0)
	var wall_crossing_blocked := not room.has_los(Vector2(200, 264), Vector2(320, 264))
	var clear_body_path := room.has_los(Vector2(100, 100), Vector2(180, 180), 20.0)
	for invalid: Vector2 in [Vector2(-100, 100), Vector2(room.size_px.x + 100, 100), Vector2(100, -100), Vector2(100, room.size_px.y + 100), Vector2.INF]:
		for radius: float in [0.0, 20.0]:
			if room.has_los(invalid, invalid, radius) or room.has_los(Vector2(100, 100), invalid, radius) or room.has_los(invalid, Vector2(100, 100), radius):
				push_error("Room.has_los rejects invalid endpoints consistently for point and body paths")
				room.free()
				return false
	room.free()
	if not corner_case_clear or not corner_case_blocked or not wall_crossing_blocked or not clear_body_path:
		push_error("Room.has_los preserves radius-zero checks and rejects swept bodies overlapping a wall corner")
		return false
	return true


func _connectivity_contracts() -> bool:
	var divided: Array = [[false, true, false], [false, true, false], [false, true, false]]
	var reachable := RoomScript.reachable_cells(divided, Vector2i(0, 1))
	var open_edges: Array = [[false, false], [false, false]]
	if reachable.size() != 3 or reachable.has(Vector2i(2, 1)) or RoomScript.reachable_cells(open_edges, Vector2i.ZERO).size() != 4:
		push_error("Connectivity respects walls and safely traverses open grid edges")
		return false
	if not RoomScript.reachable_cells(divided, Vector2i(1, 1)).is_empty() or not RoomScript.reachable_cells(divided, Vector2i(-1, 0)).is_empty() or not RoomScript.reachable_cells([], Vector2i.ZERO).is_empty():
		push_error("Connectivity rejects blocked or out-of-grid starting cells")
		return false
	return true
