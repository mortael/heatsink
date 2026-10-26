extends Node

const RunMapScript = preload("res://scripts/run/run_map.gd")

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	_route_contracts()
	_seed_reproducibility()
	print("run_map test: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _route_contracts() -> void:
	for route_seed in 200:
		for policy in 3:
			var route := RunMapScript.new(route_seed)
			route.enter("combat_item")
			while route.index < RunMap.GATE:
				var next := route.index + 1
				var exits := route.exits
				check(not exits.is_empty(), "Route has a next room")
				var unique := {}
				for kind: String in exits:
					unique[kind] = true
				check(unique.size() == exits.size(), "Door previews never duplicate a room choice")
				if next == 7 and not route.visited.has("shop"):
					check(exits.has("shop"), "Shop offered by room 7")
				if next == 10 and not route.visited.has("wager"):
					check(exits.has("wager"), "Wager offered by room 10")
				if next < RunMap.ROOMS:
					check(exits.size() >= 2 and exits.size() <= 3, "Normal exits offer 2-3 choices")
					if route.combat_streak() >= 3:
						check(exits.any(func(kind: String) -> bool: return not RunMap.is_combat(kind)), "Combat streak always offers a rest")
				if exits.has("elite"):
					check(exits.any(func(kind: String) -> bool: return kind != "elite"), "Elite always has an alternative")
				if next == RunMap.ROOMS:
					check(exits == ["vault"], "Room 12 is a Cooling Vault")
				if next == RunMap.GATE:
					check(exits == ["gate"], "Vault leads to the Gate")
				var choice := exits[0]
				for kind in exits:
					if (policy == 1 and RunMap.is_combat(kind)) or (policy == 2 and not RunMap.is_combat(kind)):
						choice = kind
				route.enter(choice)
			check(route.elite_offers >= route.elite_min, "Every route offers at least its difficulty's minimum Elites")
			check(route.exits.is_empty(), "Gate terminates the route")


func _seed_reproducibility() -> void:
	for route_seed in 20:
		var first := RunMapScript.new(route_seed)
		var replay := RunMapScript.new(route_seed)
		first.enter("combat_item")
		replay.enter("combat_item")
		while first.index < RunMap.GATE:
			check(first.exits == replay.exits, "The same seed and choices reproduce the exact door order")
			var chosen: String = first.exits[-1]
			first.enter(chosen)
			replay.enter(chosen)
		check(first.visited == replay.visited and first.visited.size() == RunMap.GATE, "A seeded replay records the same complete Stratum history")
