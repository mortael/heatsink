# HEATSINK prototype

Playable build for the HEATSINK GDD: the Riveter Frame, the Heat gauge, Vent, Clinker fodder, items with Resonance and Fusions, and a full Stratum route of 12 rooms plus the Foundry Gate, with doors, a shop, a rest room and a gamble room.

## Run it

1. Install Godot 4.5.1 (standard build, not .NET).
2. Open Godot, click **Import**, and pick `project.godot` in this folder.
3. Press **F5** (or the Play button).

## Controls

| Action | Keyboard + mouse | Gamepad |
| --- | --- | --- |
| Move | WASD / arrows | Left stick |
| Aim | Mouse | Right stick |
| Fire (hold) | Left mouse | Right trigger |
| Dash | Space / Shift | Left bumper |
| Vent | Right mouse / Q | Left trigger |
| Use (shop, altar, crucible) | E / F | A |
| Restart after death | R | Start |

## What to try

- Fire to build Heat. At 80+ you're **Hot**: rivets turn gold, pierce one enemy and ricochet off walls.
- Keep firing to 100 and you **Overheat**: the gun locks for 2 s, you move slower, and every hit costs an extra pip.
- **Vent** dumps all Heat as a nova that grows with Heat, and every rivet stuck in an enemy detonates.
- **Dash** gives brief invulnerability and quenches 10 Heat, so you can use it to stay in the Hot band longer.
- Clinkers glow orange and squash for 0.6 s before they lunge. Dash through or step out of the way.

## Items (vertical slice step 1)

After each room you pick 1 of 3 salvage cards. There are 13 items across the three synergy tiers:

- **Conductors (Tier A):** Bellows Valve, Heat Exchanger, Coolant Line, Long Barrel, Cinder Lens.
- **Keywords (Tier B):** Ignite (Tinder Rounds, Pyre Coating), Shrapnel (Frag Lattice, Splinter Heads), Arc (Feedback Coil, Static Rivets), Ricochet (Bank Shot, Rebound Charge). Owning 2 of a keyword turns on its **Resonance**.
- **Fusions (Tier C):** Cluster Embers (Tinder Rounds + Frag Lattice), Firestorm Lattice (+ Feedback Coil), Heat Engine (Bellows Valve + Feedback Coil).

Cards tell you when a pick unlocks Resonance or completes a Fusion.

## The Stratum route (vertical slice step 2)

A run is 12 rooms, then the Foundry Gate. The strip at the top of the screen shows where you are.

- After a fight, 2 or 3 doors open in the top wall. Each door shows what's behind it before you commit: a **Salvage** fight (pick 1 of 3 items), a **Conductor** fight (pick 1 of 3 Conductors), a **Scrap Cache** fight (+25 Scrap), or a room with no enemies.
- **Scrap** comes from every cleared fight (8–15) and from Clinker drops.
- **Scrapper (shop):** 4 items (one is always a Conductor), a 1-pip repair for 40, and a reroll for 15 that costs 10 more each time. Offered from room 5, and always one of the doors by room 7.
- **Crucible Wager:** feed in an item for 50% upgrade / 35% transmute / 15% Slagged, or stake 1 max Plating pip on a 60% coin flip for a Rare pick. Always one of the doors by room 10.
- **Cooling Vault:** repair 2 pips, or take the Stoke Altar (−1 max pip, Heat cap 120, Overheat +1 s). Always right before the Gate, sometimes once mid-run too.
- **Slagged items** (Brittle Crown, Hungry Coal, Feral Valve) are strong with a drawback printed in red. Finish the Absolution shown on the HUD and the drawback goes away.
- Room layouts come from 8 hand-made templates, each mirrored into 4 variants.
- The **Foundry Gate** is a tougher 3-wave fight that stands in for the Stratum boss until bosses exist.

## Layout

| Path | What it is |
| --- | --- |
| `scripts/heat.gd` | Heat gauge, bands, decay, Overheat |
| `scripts/player.gd` | Movement, Rivet Gun, dash, Vent, damage |
| `scripts/rivet.gd` | Projectile with embed, pierce and ricochet |
| `scripts/enemy.gd`, `scripts/clinker.gd` | Enemy base and the Clinker fodder |
| `scripts/director.gd` | Wave spawning with portal warnings and threat budgets |
| `scripts/juice.gd`, `scripts/sfx.gd`, `scripts/fx.gd` | Hit-stop, shake, synthesized sound, particles |
| `scripts/hud.gd` | Heat gauge, pips, item chips, edge tints, Death Ledger |
| `scripts/item_db.gd` | Item, Resonance and Fusion data |
| `scripts/inventory.gd` | Owned items, offers, and the trigger hooks that give items their behaviour |
| `scripts/shard.gd` | Shrapnel shards, homing embers and Firestorm flares |
| `scripts/picker.gd` | Pick-1-of-N card screen for rewards, the Crucible and the coin flip |
| `scripts/run_map.gd` | The Stratum route: room types and door rolls with the GDD's constraints |
| `scripts/room.gd`, `scripts/layouts.gd` | Room built from a layout template, plus pathing and line-of-sight helpers |
| `scripts/door.gd` | Doors that preview the next room |
| `scripts/pedestal.gd` | Shop items, repairs, altars and the Crucible |
| `scripts/scrap_bit.gd` | Scrap pickups |
| `tests/bot_playtest.tscn` | Automated bot playtest that reports room clear times |

Automated playtest (headless):

```
godot --headless --path . --fixed-fps 60 res://tests/bot_playtest.tscn -- 400 1 x
```

Use `allitems` instead of `x` to start with every item as a stress test, or `slagged` to start with the three Slagged items. The bot shops, rests, gambles and picks doors on its own, and the run ends when it clears the Gate.
