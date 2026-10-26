class_name Frames
## The three starting Frames (GDD section 3): each brings its own weapon, Overdrive, Vent and passive.
## Picked after START RUN and remembered in Settings. The numbers live on the weapon scripts
## (Player for the Rivet Gun, SlagMaul, CoilLance); this table is what the menus and the Codex show.

const DEFAULT := "riveter"
const ORDER: Array[String] = ["riveter", "furnace", "arclight"]

const INFO := {
	"riveter": {
		"name": "RIVETER", "role": "Ranged · precision", "color": Color(0.5, 0.8, 1.0),
		"keyword": "shrapnel", "vent_mult": 1.0, "pips": 6,
		"weapon": "Rivet Gun: 5 shots/s, 8 damage, +6 Heat per shot. Rivets stick in enemies.",
		"overdrive": "Rivets burn gold, pierce 1 enemy and ricochet off a wall once.",
		"vent": "x1.0. Every stuck rivet detonates for 10 damage.",
		"passive": "Tension: each rivet in an enemy adds +5% Vent damage to it.",
		"blurb": "Tag a crowd with rivets, then Vent to pop the room.",
	},
	"furnace": {
		"name": "FURNACE", "role": "Melee · brawler", "color": Color(1.0, 0.5, 0.18),
		"keyword": "molten", "vent_mult": 1.5, "pips": 7,
		"weapon": "Slag Maul: a 3-hit combo (22 / 22 / 40) in a wide arc, +12 Heat per swing. The third hit leaves a Molten pool.",
		"overdrive": "Every swing throws a shockwave 4 tiles forward (15 damage).",
		"vent": "x1.5. Vent at 80+ Heat for a Slag Shield that blocks the next hit for 4 s.",
		"passive": "Momentum: each swing that lands within 0.6 s of the last delays cooling 0.3 s more, up to 2 s.",
		"blurb": "Stay in the crowd, keep the combo going, Vent for armour.",
	},
	"arclight": {
		"name": "ARCLIGHT", "role": "Beam · crowd control", "color": Color(0.45, 0.95, 1.0),
		"keyword": "arc", "vent_mult": 0.8, "pips": 6,
		"weapon": "Coil Lance: hold to channel a 7-tile beam, 40 damage/s, +20 Heat/s. It chains to 1 more enemy, +1 per band above Cold.",
		"overdrive": "The beam forks into 3 beams in a 30° spread.",
		"vent": "x0.8. Leaves a Static Pylon that zaps the nearest enemy for 12 every 0.5 s for 4 s.",
		"passive": "Grounded: stop channelling for 1 s and Heat cools twice as fast.",
		"blurb": "Heat climbs fast, so managing Overheat is the whole skill.",
	},
}


static func clamp_id(id: String) -> String:
	return id if INFO.has(id) else DEFAULT


static func info(id: String) -> Dictionary:
	return INFO[clamp_id(id)]


## The Frame of the run being played (Settings.frame).
static func current() -> String:
	var s := Engine.get_main_loop() as SceneTree
	if s == null or not s.root.has_node("Settings"):
		return DEFAULT
	return clamp_id(s.root.get_node("Settings").frame)
