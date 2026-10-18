class_name RunMap
extends RefCounted
## The Stratum route (GDD section 6): 12 rooms, then the Foundry Gate.
## Each exit offers 2-3 doors whose room type and reward are shown before you pick.
## Doors are rolled one room ahead from a seeded RNG, so the preview is always honest.
##
## Constraints from the GDD:
## - after 3 combat rooms in a row, at least one door is non-combat;
## - the same non-combat type is never offered twice in a row;
## - the Scrapper is always on offer by room 7 and the Crucible Wager by room 10, as one door
##   among the usual 2-3, so the safe route has both without taking away the choice;
## - a Cooling Vault always sits right before the Gate, plus a 50% chance of one mid-run;
## - an Elite door (red frame) is offered at least twice per Stratum, never as the only door,
##   so the safe route always exists. Harder difficulty levels offer Elite doors more often.
## - one Rainside door (a 2.5D street fight) per Stratum, between rooms 2 and 9, at the latest by room 6.

const ROOMS := 12
const GATE := ROOMS + 1
const ELITE_FIRST := 3 # earliest room an Elite door can lead to
const ELITE_LAST := 11
const STREET_FIRST := 2
const STREET_DUE := 6 # the Rainside door is always on offer by this room
const STREET_LAST := 9
const STREET_CHANCE := 0.3

const KINDS := {
	"combat_item": {"name": "SALVAGE", "sub": "combat · pick 1 of 3 items", "color": Color(1.0, 0.6, 0.25), "combat": true},
	"combat_conductor": {"name": "CONDUCTOR", "sub": "combat · pick 1 of 3 Conductors", "color": Color(0.72, 0.78, 0.85), "combat": true},
	"elite": {"name": "ELITE", "sub": "Forgewarden · 1 Core + Rare pick", "color": Color(1.0, 0.22, 0.2), "combat": true},
	"street": {"name": "RAINSIDE", "sub": "2.5D street fight · pick 1 of 3 items", "color": Color(1.0, 0.4, 0.62), "combat": true},
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
var elite_offers := 0
var elite_min := 2
var elite_chance := 0.25
var street_offered := false
var _used := {} # non-combat types already taken this Stratum


func _init(seed_value: int) -> void:
	rng.seed = seed_value
	elite_min = Difficulty.value("elite_min")
	elite_chance = Difficulty.value("elite_chance")
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
	var count := 2 if rng.randf() < 0.5 else 3
	var specials := _available_specials(next)
	# Last chance for the shop or the Wager: it is always one of the doors.
	var due := "shop" if next == 7 else ("wager" if next == 10 else "")
	if specials.has(due):
		out.append(due)
		specials.erase(due)
	if combat_streak() >= 3 and not specials.is_empty():
		var s: String = specials[rng.randi_range(0, specials.size() - 1)]
		out.append(s)
		specials.erase(s)
	if _elite_due(next) or (next >= ELITE_FIRST and next <= ELITE_LAST and rng.randf() < elite_chance):
		# An Elite always shares the exit with at least one other door.
		count = mini(3, maxi(count, out.size() + 2))
		out.append("elite")
		elite_offers += 1
	if not street_offered and next >= STREET_FIRST and next <= STREET_LAST and (next >= STREET_DUE or rng.randf() < STREET_CHANCE):
		count = mini(3, maxi(count, out.size() + 1))
		if out.size() < count:
			out.append("street")
			street_offered = true
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


## True when this exit is the last chance to reach the minimum number of Elite offers.
func _elite_due(next: int) -> bool:
	if next < ELITE_FIRST or next > ELITE_LAST or elite_offers >= elite_min:
		return false
	var chances_left := ELITE_LAST - next + 1
	return chances_left <= elite_min - elite_offers


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
