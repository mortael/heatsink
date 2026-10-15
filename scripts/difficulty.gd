class_name Difficulty
## Five difficulty levels, picked on the title screen and remembered in Settings.
## WARM is the original balance. Harder levels mostly add bodies, not HP: bigger room budgets,
## extra waves that overlap (the next wave comes sooner), special enemies earlier and more often,
## more Elite doors, and a second Forgewarden at the Gate on MELTDOWN.
## Enemies also get smarter: from HOT Clinkers spread out to surround you (flank), and from SEARING
## Slagspitters aim where you are going instead of where you are (lead_aim).

const DEFAULT := 1

const LEVELS: Array[Dictionary] = [
	{
		"name": "COLD", "color": Color(0.45, 0.75, 1.0),
		"blurb": "Smaller packs and softer enemies. For learning the Heat dance.",
		"budget": 0.7, "extra_waves": 0, "next_wave_at": 0.2, "wave_timeout": 9.0, "hp": 0.85,
		"special_shift": -1, "special_mult": 0.7, "elite_min": 1, "elite_chance": 0.15, "gate_wardens": 1, "flank": false, "lead_aim": false,
	},
	{
		"name": "WARM", "color": Color(1.0, 0.62, 0.2),
		"blurb": "The original balance.",
		"budget": 1.0, "extra_waves": 0, "next_wave_at": 0.25, "wave_timeout": 8.0, "hp": 1.0,
		"special_shift": 0, "special_mult": 1.0, "elite_min": 2, "elite_chance": 0.25, "gate_wardens": 1, "flank": false, "lead_aim": false,
	},
	{
		"name": "HOT", "color": Color(1.0, 0.85, 0.45),
		"blurb": "Half again as many enemies, an extra wave per room, specials sooner.",
		"budget": 1.5, "extra_waves": 1, "next_wave_at": 0.4, "wave_timeout": 7.0, "hp": 1.05,
		"special_shift": 1, "special_mult": 1.25, "elite_min": 2, "elite_chance": 0.35, "gate_wardens": 1, "flank": true, "lead_aim": false,
	},
	{
		"name": "SEARING", "color": Color(1.0, 0.45, 0.2),
		"blurb": "Hordes: two extra waves that pile on top of each other. Tougher enemies, more Elite doors.",
		"budget": 1.85, "extra_waves": 2, "next_wave_at": 0.5, "wave_timeout": 5.5, "hp": 1.15,
		"special_shift": 2, "special_mult": 1.5, "elite_min": 3, "elite_chance": 0.45, "gate_wardens": 1, "flank": true, "lead_aim": true,
	},
	{
		"name": "MELTDOWN", "color": Color(1.0, 0.18, 0.12),
		"blurb": "Double the enemies, two extra waves, two Forgewardens at the Gate.",
		"budget": 2.1, "extra_waves": 2, "next_wave_at": 0.55, "wave_timeout": 5.0, "hp": 1.25,
		"special_shift": 3, "special_mult": 1.8, "elite_min": 3, "elite_chance": 0.55, "gate_wardens": 2, "flank": true, "lead_aim": true,
	},
]


static func clamp_level(level: int) -> int:
	return clampi(level, 0, LEVELS.size() - 1)


## The level of the run being played (Settings.difficulty).
static func level() -> int:
	var s := Engine.get_main_loop() as SceneTree
	if s == null or not s.root.has_node("Settings"):
		return DEFAULT
	return clamp_level(s.root.get_node("Settings").difficulty)


static func current() -> Dictionary:
	return LEVELS[level()]


static func value(key: String) -> Variant:
	return current()[key]


static func level_name(level_index := -1) -> String:
	return LEVELS[clamp_level(level() if level_index < 0 else level_index)].name
