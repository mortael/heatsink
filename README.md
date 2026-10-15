# HEATSINK prototype

Playable build for the HEATSINK GDD: the Riveter Frame, the Heat gauge, Vent, three enemies (Clinker, Linesman, Forgewarden), items with Resonance and Fusions, and a full Stratum route of 12 rooms plus the Foundry Gate, with doors, Elite rooms, a shop, a rest room with the Anvil and a gamble room.

## Download a build

Every merge to `main` builds the game on GitHub (`.github/workflows/release.yml`):

- **Play in the browser:** https://mortael.github.io/heatsink/
- **Windows:** grab `HEATSINK-windows.zip` from the latest [Release](https://github.com/mortael/heatsink/releases/latest), unzip and run `HEATSINK.exe`. It is unsigned, so Windows SmartScreen may ask you to click **More info → Run anyway**.
- **Android:** open the latest Release on your phone, download `HEATSINK-android.apk` and open it. Android asks once to allow installing apps from your browser. Each build installs over the previous one.

On a touch screen (phone, tablet, or the browser version on one) on-screen controls appear after the first touch: drag on the left half to move, drag on the right half to aim and fire, and tap **DASH**, **VENT** or **USE**. The **II** button at the top right pauses. Tap a card to pick it, and tap anywhere after death to start a new run.

The export settings live in `export_presets.cfg`. The Web build is single-threaded so it runs on GitHub Pages, which can't send the cross-origin isolation headers threaded builds need. The APK is signed with `ci/heatsink-debug.keystore`, a committed debug key that is fine for sideloading but not for the Play Store.

## Run it

1. Install Godot 4.7.2 (standard build, not .NET).
2. Open Godot, click **Import**, and pick `project.godot` in this folder.
3. Press **F5** (or the Play button). The game opens on the main menu: **Start Run**, **Codex** (how to play: Heat, Vent, every item, the enemies and the room types), **Settings** (volume, screen shake, fullscreen, lights & shadows, an FPS counter; saved between sessions) and **Quit** (not shown in the browser). The Codex is also in the pause menu.

## Controls

| Action | Keyboard + mouse | Gamepad |
| --- | --- | --- |
| Move | WASD / arrows | Left stick |
| Aim | Mouse | Right stick |
| Fire (hold) | Left mouse | Right trigger |
| Dash | Space / Shift | Left bumper |
| Vent | Right mouse / Q | Left trigger |
| Use (shop, altar, crucible) | E / F | A |
| Pause (resume, settings, main menu) | Esc / P | Start |
| Restart after death | R | Start |
| Main menu after death | Esc | |

## What to try

- Fire to build Heat. At 80+ you're **Hot**: rivets turn gold, pierce one enemy and ricochet off walls.
- Keep firing to 100 and you **Overheat**: the gun locks for 2 s, you move slower, and every hit costs an extra pip.
- **Vent** dumps all Heat as a nova that grows with Heat, and every rivet stuck in an enemy detonates. The ring around your Sink fills while the Vent cools down and glows orange (with a flash and a soft chime) when it's ready again.
- **Dash** gives brief invulnerability and quenches 10 Heat, so you can use it to stay in the Hot band longer.
- Clinkers glow orange and squash for 0.6 s before they lunge. Dash through or step out of the way.

## Enemies and Elites (vertical slice step 3)

- **Linesman** (from room 3): a tall drone that keeps its distance. It draws a dotted violet line to a nearby enemy, and 0.7 s later the line becomes a cyan beam for 3 s that costs 1 pip to touch. Kill either end to drop the beam, or dash through it. Get within 3 tiles and it chirps, crouches and hops away.
- **Forgewarden** (Elite): 600 HP behind 3 front plates that block 75% of damage from the front until each takes 80. Its back takes +50%, and it turns slowly, so circle behind it.
  - *Hammerfall*: a red circle grows where you stand, then it leaps and slams. Walk out of the circle, then dash through the ring that rolls out to 5 tiles. 2 pips.
  - *Bellows Breath*: the chest glows and a red cone shows for 1 s, then flame fills it for 1.2 s and leaves Molten floor for 3 s. Step out to the side. 2 pips.
  - After each attack it rests for 2 s: the moment to Vent.
- **Elite doors** have a red double frame. Inside: a Forgewarden, 4-6 Clinkers, sometimes a Linesman, and a second Clinker wave. Every Stratum offers at least two, never as the only door. Reward: **1 Core** and a pick of 3 Rare-or-better items, where each card has a 20% chance to be a Slagged item.
- The **Foundry Gate** now ends with a Forgewarden and a Linesman.
- **Cores** only come from Elites. Spend them at **the Anvil** in a Cooling Vault:
  - *Temper* (1 Core) upgrades how an item works, e.g. Frag Lattice drops 6 shards instead of 4. Tempered items get a cyan mark on the HUD.
  - *Forced Fusion* (3 Cores) completes a Fusion you're one ingredient short of. The Fusion also gives you that ingredient's effect.
- A Cooling Vault is now a choice between the Cooling Bath (repair 2 pips) and the Anvil. A Stoke Altar shows up in 1 of every 3 Vaults as a separate option.

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
- **Cooling Vault:** repair 2 pips or use the Anvil (see step 3), and sometimes a Stoke Altar (−1 max pip, Heat cap 120, Overheat +1 s). Always right before the Gate, sometimes once mid-run too.
- **Slagged items** (Brittle Crown, Hungry Coal, Feral Valve) are strong with a drawback printed in red. Finish the Absolution shown on the HUD and the drawback goes away.
- Combat rooms are **generated**: wall shapes (pillars, bars, L-, T- and U-shapes, crosses) are stamped into the room, usually mirrored or rotated so it looks designed. Every room is checked before you see it: the entry and all doors stay reachable, there are no sealed pockets for enemies to spawn in, almost no one-tile slits, and cover in at least three quarters of the room. Elite rooms get less cover so the Forgewarden has space. 1 in 4 combat rooms still uses one of the 8 hand-made templates, and room 1 and the Gate keep their fixed layout.
- The **Foundry Gate** is a tougher 3-wave fight that stands in for the Stratum boss until bosses exist.
- Not built yet: Scorched Paths (two chained Elites), Legendary items and elite affixes. Until Legendaries exist, the Ember Coin pays out a Rare.

## Layout

| Path | What it is |
| --- | --- |
| `scripts/heat.gd` | Heat gauge, bands, decay, Overheat |
| `scripts/player.gd` | Movement, Rivet Gun, dash, Vent, damage |
| `scripts/rivet.gd` | Projectile with embed, pierce and ricochet |
| `scripts/enemy.gd`, `scripts/clinker.gd` | Enemy base and the Clinker fodder |
| `scripts/linesman.gd` | Linesman: Tether beam and Snap Back |
| `scripts/forgewarden.gd`, `scripts/molten_patch.gd` | Forgewarden Elite: armour, Hammerfall, Bellows Breath, Molten floor |
| `scripts/director.gd` | Wave plans from Threat Point budgets, Elite rooms, portal warnings |
| `scripts/juice.gd`, `scripts/sfx.gd`, `scripts/fx.gd` | Hit-stop, shake, synthesized sound, particles |
| `scripts/hud.gd` | Heat gauge, pips, item chips, edge tints, Death Ledger |
| `scripts/item_db.gd` | Item, Resonance and Fusion data |
| `scripts/inventory.gd` | Owned items, offers, and the trigger hooks that give items their behaviour |
| `scripts/shard.gd` | Shrapnel shards, homing embers and Firestorm flares |
| `scripts/picker.gd` | Pick-1-of-N card screen for rewards, the Crucible and the coin flip |
| `scripts/run_map.gd` | The Stratum route: room types and door rolls with the GDD's constraints |
| `scripts/room.gd`, `scripts/layouts.gd` | Room built from a layout template, plus pathing and line-of-sight helpers |
| `scripts/room_gen.gd` | Procedural combat-room generator and the rules every room must pass |
| `scripts/door.gd` | Doors that preview the next room |
| `scripts/pedestal.gd` | Shop items, repairs, the Anvil, altars and the Crucible |
| `scripts/scrap_bit.gd` | Scrap pickups |
| `scripts/glow.gd`, `scripts/lights.gd`, `scripts/ambience.gd` | Additive glow textures, the pool of 2D light flashes that throw wall shadows, and the room dimming that makes lights read |
| `menu.tscn`, `scripts/main_menu.gd` | Title screen (the scene the game starts on) |
| `scripts/pause_menu.gd`, `scripts/settings_panel.gd` | Pause menu and the shared Settings panel |
| `scripts/codex_panel.gd` | The Codex: how-to-play pages, with items and room types read from the game data |
| `scripts/settings.gd`, `scripts/ui_style.gd`, `scripts/fps_counter.gd` | Saved settings (autoload), the menu look and the optional FPS counter |
| `tests/bot_playtest.tscn` | Automated bot playtest that reports room clear times |
| `tests/room_gen_test.gd` | Generates 2000 rooms and fails if any breaks the rules or the door check |
| `tests/menu_test.tscn` | Walks menu → settings → codex → run → pause → menu and fails if a step doesn't work |
| `tests/ui_shots.tscn` | Screenshots of the Codex, the FPS counter and the Vent ring (needs a renderer, not headless) |
| `tests/lighting_shots.tscn` | Staged screenshots of tracers, the Linesman beam and a Vent (needs a renderer, not headless) |

Automated playtest (headless):

```
godot --headless --path . --fixed-fps 60 res://tests/bot_playtest.tscn -- 400 1 x
```

Use `allitems` instead of `x` to start with every item and 4 Cores as a stress test, `slagged` to start with the three Slagged items, `elite` to take every Elite door, or `forge` to start with Tinder Rounds and 3 Cores. The report lists pips lost by source. The bot shops, rests, gambles and picks doors on its own, and the run ends when it clears the Gate.

Room generator check (exits with code 1 on a bad room):

```
godot --headless --path . -s res://tests/room_gen_test.gd -- 2000 1
```

Menu check (exits with code 1 if a menu step fails):

```
godot --headless --path . res://tests/menu_test.tscn
```
