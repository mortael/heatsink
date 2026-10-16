class_name ItemDB
## Item and Fusion catalogue (GDD section 5). Behaviour lives in Inventory hooks, keyed by id.
## An item with a "frames" list is only offered to those Frames (rivet-only behaviour such as ricochets).

const KEYWORD_COLORS := {
	"conductor": Color(0.7, 0.75, 0.8),
	"ignite": Color(1.0, 0.5, 0.15),
	"shrapnel": Color(0.82, 0.85, 0.92),
	"arc": Color(0.4, 0.9, 1.0),
	"ricochet": Color(1.0, 0.86, 0.45),
	"molten": Color(1.0, 0.7, 0.25),
	"slagged": Color(1.0, 0.25, 0.3),
	"fusion": Color(1.0, 0.82, 0.3),
}

const RARITY_RANK := {"Common": 0, "Uncommon": 1, "Rare": 2, "Slagged": 3}

## Scrapper prices (GDD section 9). Conductors have their own flat price.
const PRICE := {"conductor": 35, "Common": 40, "Uncommon": 65, "Rare": 100}

## Resonance I unlocks at 2 items of one keyword.
const RESONANCE := {
	"ignite": "Ignite max stacks 10 -> 15",
	"shrapnel": "Every shard burst releases +2 shards",
	"arc": "Arcs hit +1 extra target",
	"ricochet": "All rivets ricochet +1 time",
	"molten": "Your Molten pools are 50% wider and last 1 s longer",
}

const ITEMS := {
	"bellows_valve": {
		"name": "Bellows Valve", "keyword": "conductor", "tier": "A", "rarity": "Common",
		"desc": "+20% attack rate. Each hit while Warm or hotter adds +2% proc chance (max +20%), reset on Vent.",
	},
	"heat_exchanger": {
		"name": "Heat Exchanger", "keyword": "conductor", "tier": "A", "rarity": "Common",
		"desc": "Heat decays 30% faster and dash charges recharge 25% faster.",
	},
	"coolant_line": {
		"name": "Coolant Line", "keyword": "conductor", "tier": "A", "rarity": "Common",
		"desc": "Vent cooldown -1.5 s.",
	},
	"long_barrel": {
		"name": "Long Barrel", "keyword": "conductor", "tier": "A", "rarity": "Common",
		"desc": "Rivets, shards and shockwaves fly 30% faster and farther. Swings and beams reach 30% farther.",
	},
	"cinder_lens": {
		"name": "Cinder Lens", "keyword": "conductor", "tier": "A", "rarity": "Uncommon",
		"desc": "+10% crit chance. Crits apply your on-hit effects twice.",
	},
	"tinder_rounds": {
		"name": "Tinder Rounds", "keyword": "ignite", "tier": "B", "rarity": "Uncommon",
		"desc": "Hits apply 1 Ignite (4 dmg/s per stack, 3 s). Ignited enemies that die burst, passing half their stacks to enemies within 1.5 tiles.",
	},
	"pyre_coating": {
		"name": "Pyre Coating", "keyword": "ignite", "tier": "B", "rarity": "Uncommon",
		"desc": "While Hot, your hits apply +2 Ignite. Overheating sets every enemy within 4 tiles on fire (3 stacks).",
	},
	"frag_lattice": {
		"name": "Frag Lattice", "keyword": "shrapnel", "tier": "B", "rarity": "Rare",
		"desc": "When an enemy you hit dies, it releases 4 shards in an X (6 dmg). Shards trigger your on-hit effects at 50% chance.",
	},
	"splinter_heads": {
		"name": "Splinter Heads", "keyword": "shrapnel", "tier": "B", "rarity": "Uncommon", "frames": ["riveter", "furnace"],
		"desc": "Rivets and shockwaves that break on a wall burst into 3 shards that spray back into the room.",
	},
	"feedback_coil": {
		"name": "Feedback Coil", "keyword": "arc", "tier": "B", "rarity": "Rare",
		"desc": "Vent fires arcs at up to 3 enemies within 8 tiles (10 dmg). Arcs prefer Ignited enemies and consume their stacks for +5 dmg each.",
	},
	"static_rivets": {
		"name": "Static Rivets", "keyword": "arc", "tier": "B", "rarity": "Uncommon",
		"desc": "Every 5th hit arcs to 2 enemies within 3 tiles of the target (8 dmg).",
	},
	"bank_shot": {
		"name": "Bank Shot", "keyword": "ricochet", "tier": "B", "rarity": "Uncommon", "frames": ["riveter"],
		"desc": "Rivets always ricochet once, even when not Hot.",
	},
	"rebound_charge": {
		"name": "Rebound Charge", "keyword": "ricochet", "tier": "B", "rarity": "Uncommon", "frames": ["riveter"],
		"desc": "After a ricochet, a rivet deals +50% damage and pierces 1 more enemy.",
	},
	"slag_trail": {
		"name": "Slag Trail", "keyword": "molten", "tier": "B", "rarity": "Uncommon",
		"desc": "Dashes leave a Molten pool where they start and where they end (6 dmg/s to enemies, 2 s).",
	},
	"cinder_spill": {
		"name": "Cinder Spill", "keyword": "molten", "tier": "B", "rarity": "Uncommon",
		"desc": "Enemies you kill while Hot leave a Molten pool. Your Molten pools set enemies in them on fire (1 Ignite per tick).",
	},
	# Slagged items (GDD section 4): Legendary-strength power with a printed drawback.
	# Completing the Absolution removes the drawback and keeps the power.
	"brittle_crown": {
		"name": "Brittle Crown", "keyword": "slagged", "tier": "S", "rarity": "Slagged",
		"desc": "Always on: +2 rivets per shot (Riveter), a shockwave on every swing (Furnace), +2 beam forks (Arclight).",
		"drawback": "Any hit taken while Hot costs 3 pips.",
		"absolution": "Clear 3 rooms in a row without taking damage.", "goal": 3,
	},
	"hungry_coal": {
		"name": "Hungry Coal", "keyword": "slagged", "tier": "S", "rarity": "Slagged",
		"desc": "Vent damage x3.",
		"drawback": "Heat never decays on its own. Only Vent and dashes lower it.",
		"absolution": "Kill 40 enemies with Vent.", "goal": 40,
	},
	"feral_valve": {
		"name": "Feral Valve", "keyword": "slagged", "tier": "S", "rarity": "Slagged",
		"desc": "Overdrive starts at 60 Heat instead of 80.",
		"drawback": "Overheat lasts 4 s instead of 2 s.",
		"absolution": "Stay in the Hot band for a combined 90 s.", "goal": 90,
	},
}

const FUSIONS := {
	"cluster_embers": {
		"name": "Cluster Embers", "recipe": ["tinder_rounds", "frag_lattice"],
		"desc": "Shards curve toward the nearest Ignited enemy and always apply Ignite.",
	},
	"firestorm_lattice": {
		"name": "Firestorm Lattice", "recipe": ["tinder_rounds", "frag_lattice", "feedback_coil"],
		"desc": "Shards hang in the air as burning flares. Vent detonates every flare and chains lightning between them.",
	},
	"heat_engine": {
		"name": "Heat Engine", "recipe": ["bellows_valve", "feedback_coil"],
		"desc": "Arc kills refund 0.5 s of Vent cooldown, and Vent leaves you Warm (40 Heat) instead of Cold.",
	},
}

## Anvil Temper (GDD section 9, 1 Core): upgrades an item's mechanic. Slagged items can't be tempered.
const TEMPER := {
	"bellows_valve": "+35% attack rate (was +20%).",
	"heat_exchanger": "Heat decays 60% faster, dashes recharge 35% faster.",
	"coolant_line": "Vent cooldown -2.5 s (was -1.5 s).",
	"long_barrel": "50% faster and farther (was 30%).",
	"cinder_lens": "+20% crit chance (was +10%).",
	"tinder_rounds": "Death bursts reach 2.5 tiles (was 1.5).",
	"pyre_coating": "+3 Ignite while Hot; Overheat ignites within 5 tiles for 5 stacks.",
	"slag_trail": "Your Molten pools burn for 12 dmg/s (was 6).",
	"cinder_spill": "Kills leave a pool from Warm up (was Hot).",
	"frag_lattice": "6 shards per death (was 4).",
	"splinter_heads": "5 shards per wall stop (was 3).",
	"feedback_coil": "Vent arcs hit 5 enemies for 14 dmg.",
	"static_rivets": "Arcs every 3rd rivet hit (was every 5th).",
	"bank_shot": "+2 ricochets instead of +1 (3 while Hot).",
	"rebound_charge": "After a ricochet: +100% damage and pierce 2 more.",
}
const TEMPER_COST := 1
const FORGE_COST := 3

## Filler offered when the item pool runs dry.
const PATCH_KIT := {
	"name": "Patch Kit", "keyword": "conductor", "tier": "-", "rarity": "Common",
	"desc": "Repair 1 Plating pip.",
}


static func get_item(id: String) -> Dictionary:
	if id == "patch_kit":
		return PATCH_KIT
	return ITEMS[id]


static func fits(id: String, frame: String) -> bool:
	if id == "patch_kit":
		return true
	var only: Array = ITEMS[id].get("frames", [])
	return only.is_empty() or only.has(frame)


static func is_slagged(id: String) -> bool:
	return id != "patch_kit" and ITEMS[id].keyword == "slagged"


static func price(id: String) -> int:
	var item: Dictionary = get_item(id)
	if item.keyword == "conductor":
		return PRICE.conductor
	return PRICE.get(item.rarity, 100)


static func keyword_color(kw: String) -> Color:
	return KEYWORD_COLORS.get(kw, Color.WHITE)
