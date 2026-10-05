class_name ItemDB
## Item and Fusion catalogue (GDD section 5). Behaviour lives in Inventory hooks, keyed by id.

const KEYWORD_COLORS := {
	"conductor": Color(0.7, 0.75, 0.8),
	"ignite": Color(1.0, 0.5, 0.15),
	"shrapnel": Color(0.82, 0.85, 0.92),
	"arc": Color(0.4, 0.9, 1.0),
	"ricochet": Color(1.0, 0.86, 0.45),
}

## Resonance I unlocks at 2 items of one keyword.
const RESONANCE := {
	"ignite": "Ignite max stacks 10 -> 15",
	"shrapnel": "Every shard burst releases +2 shards",
	"arc": "Arcs hit +1 extra target",
	"ricochet": "All rivets ricochet +1 time",
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
		"desc": "Rivets and shards fly 30% faster and 30% farther.",
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
		"desc": "While Hot, rivets apply +2 Ignite. Overheating sets every enemy within 4 tiles on fire (3 stacks).",
	},
	"frag_lattice": {
		"name": "Frag Lattice", "keyword": "shrapnel", "tier": "B", "rarity": "Rare",
		"desc": "When an enemy you hit dies, it releases 4 shards in an X (6 dmg). Shards trigger your on-hit effects at 50% chance.",
	},
	"splinter_heads": {
		"name": "Splinter Heads", "keyword": "shrapnel", "tier": "B", "rarity": "Uncommon",
		"desc": "Rivets that stop against a wall burst into 3 shards that spray back into the room.",
	},
	"feedback_coil": {
		"name": "Feedback Coil", "keyword": "arc", "tier": "B", "rarity": "Rare",
		"desc": "Vent fires arcs at up to 3 enemies within 8 tiles (10 dmg). Arcs prefer Ignited enemies and consume their stacks for +5 dmg each.",
	},
	"static_rivets": {
		"name": "Static Rivets", "keyword": "arc", "tier": "B", "rarity": "Uncommon",
		"desc": "Every 5th rivet hit arcs to 2 enemies within 3 tiles of the target (8 dmg).",
	},
	"bank_shot": {
		"name": "Bank Shot", "keyword": "ricochet", "tier": "B", "rarity": "Uncommon",
		"desc": "Rivets always ricochet once, even when not Hot.",
	},
	"rebound_charge": {
		"name": "Rebound Charge", "keyword": "ricochet", "tier": "B", "rarity": "Uncommon",
		"desc": "After a ricochet, a rivet deals +50% damage and pierces 1 more enemy.",
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

## Filler offered when the item pool runs dry.
const PATCH_KIT := {
	"name": "Patch Kit", "keyword": "conductor", "tier": "-", "rarity": "Common",
	"desc": "Repair 1 Plating pip.",
}


static func get_item(id: String) -> Dictionary:
	if id == "patch_kit":
		return PATCH_KIT
	return ITEMS[id]


static func keyword_color(kw: String) -> Color:
	return KEYWORD_COLORS.get(kw, Color.WHITE)
