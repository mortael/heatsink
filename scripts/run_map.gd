class_name RunMap
extends RefCounted
## The Stratum route (GDD section 6): 12 rooms, then the Foundry Gate.
## Each exit offers 2-3 doors whose room type and reward are shown before you pick.
## Doors are rolled one room ahead from a seeded RNG, so the preview is always honest.
##
## Constraints from the GDD:
## - after 3 combat rooms in a row, at least one door is non-combat;
## - the same non-combat type is never offered twice in a row;
## - the Scrapper is guaranteed between rooms 5 and 7, the Crucible Wager once per Stratum;
## - a Cooling Vault always sits right before the Gate, plus a 50% chance of one mid-run.

const ROOMS := 12
const GATE := ROOMS + 1

const KINDS := {
	"combat_item": {"name": "SALVAGE", "sub": "combat · pick 1 of 3 items", "color": Color(1.0, 0.6, 0.25), "combat": true},
	"combat_conductor": {"name": "CONDUCTOR", "sub": "combat · pick 1 of 3 Conductors", "color": Color(0.72, 0.78, 0.85), "combat": true},
	"combat_scrap": {"name": "SCRAP CACHE", "sub": "combat · +25 Scrap", "color": Color(0.9, 0.78, 0.45), "combat": true},
	"shop": {"name": "SCRAPPER", "sub": "shop · no enemies", "color": Color(1.0, 0.85, 0.3), "combat": false},
	"vault": {"name": "COOLING VAULT", "sub": "rest · no enemies", "color": Color(0.45, 0.8, 1.0), "combat": false},
	"wager": {"name": "CRUCIBLE WAGER", "sub": "gamble · no enemies", "color": Color(0.8, 0.45, 1.0), "combat": false},
	"gate": {"name": "FOUNDRY GATE", "sub": "final fight of the Stratum", "color": Color(1.0, 0.3, 0.25), "combat": true},
}

var rng := RandomNumberGenerator.new()
var index := 0 # 1-based number of the room you are in
var visited: Array[String] = []
var exits: Array[String] = [] # doors out of the current room
var extra_vault := false
var _used := {} # non-combat types already taken this Stratum


func _init(seed_value: int) -> void:
	rng.seed = seed_value
	extra_vault = rng.randf() < 0.5


static func is_combat(kind: String) -> bool:
	return KINDS[kind].combat


## Moves into a room of this kind and rolls the doors that lead out of it.
func enter(kind: String) -> void:
	index += 1
	visited.append(kind)
	if not is_combat(kind):
		_used[kind] = true
	exits = _roll_exits()


func combat_streak() -> int:
	var n := 0
	for i in range(visited.size() - 1, -1, -1):
		if not is_combat(visited[i]):
			break
		n += 1
	return n


func _roll_exits() -> Array[String]:
	var next := index + 1
	var out: Array[String] = []
	if next > GATE:
		return out
	if next == GATE:
		out.append("gate")
		return out
	if next == ROOMS:
		out.append("vault")
		return out
	# Forced picks keep the safe route's promises.
	if next == 7 and not _used.has("shop"):
		out.append("shop")
		return out
	if next == 10 and not _used.has("wager"):
		out.append("wager")
		return out
	var count := 2 if rng.randf() < 0.5 else 3
	var specials := _available_specials(next)
	if combat_streak() >= 3 and not specials.is_empty():
		var s: String = specials[rng.randi_range(0, specials.size() - 1)]
		out.append(s)
		specials.erase(s)
	while out.size() < count:
		if not specials.is_empty() and rng.randf() < 0.35:
			var s: String = specials[rng.randi_range(0, specials.size() - 1)]
			out.append(s)
			specials.erase(s)
			continue
		var roll := rng.randf()
		var c := "combat_item" if roll < 0.5 else ("combat_scrap" if roll < 0.75 else "combat_conductor")
		if out.has(c):
			# Duplicate door: fall back to any combat type not on offer yet.
			for alt: String in ["combat_item", "combat_scrap", "combat_conductor"]:
				if not out.has(alt):
					c = alt
					break
		out.append(c)
	_shuffle(out)
	return out


func _available_specials(next: int) -> Array[String]:
	var out: Array[String] = []
	var last: String = visited[-1] if not visited.is_empty() else ""
	if not _used.has("shop") and next >= 5 and next <= 7 and last != "shop":
		out.append("shop")
	if not _used.has("wager") and next >= 3 and next <= 10 and last != "wager":
		out.append("wager")
	if extra_vault and not _used.has("vault") and next >= 6 and next <= 10 and last != "vault":
		out.append("vault")
	return out


func _shuffle(a: Array[String]) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := a[i]
		a[i] = a[j]
		a[j] = tmp
