extends SceneTree
## Checks the procedural room generator: every room passes the rules, the game's own door check,
## and rooms don't repeat. Exits with code 1 on a failure.
## Run: godot --headless --path . -s res://tests/room_gen_test.gd -- [count] [seed]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var count := int(args[0]) if args.size() > 0 else 2000
	var rng := RandomNumberGenerator.new()
	rng.seed = int(args[1]) if args.size() > 1 else 1
	var failures := 0
	var seen := {}
	var walls_total := 0
	var started := Time.get_ticks_usec()
	for i in count:
		var density := 0.7 if i % 4 == 0 else 1.0
		var lines := RoomGen.generate(rng, density)
		var grid := RoomGen.to_grid(lines)
		var room := Room.new(lines)
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
