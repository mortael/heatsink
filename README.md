# HEATSINK prototype

Playable build for the HEATSINK GDD: three Frames (Riveter, Furnace, Arclight), the Heat gauge, Vent, six enemies (Clinker, Sparkhound, Slagspitter, Slag Mortar, Linesman, Forgewarden), five difficulty levels, items with Resonance and Fusions, and a full Stratum route of 12 rooms plus the Foundry Gate, with doors, Elite rooms, a shop, a rest room with the Anvil and a gamble room.

## Download a build

Every merge to `main` builds the game on GitHub (`.github/workflows/release.yml`):

- **Play in the browser:** https://mortael.github.io/heatsink/
- **Windows:** grab `HEATSINK-windows.zip` from the latest [Release](https://github.com/mortael/heatsink/releases/latest), unzip and run `HEATSINK.exe`. It is unsigned, so Windows SmartScreen may ask you to click **More info → Run anyway**.
- **Android:** open the latest Release on your phone, download `HEATSINK-android.apk` and open it. Android asks once to allow installing apps from your browser. Each build installs over the previous one.

On a phone or tablet (the app, or the browser version) on-screen controls are shown from the start; on other touch screens they appear after the first touch. In the browser, turn the phone sideways; on Android the first tap also switches to fullscreen landscape. Controls: drag on the left half to move, drag on the right half to aim and fire, and tap **DASH**, **VENT** or **USE**. The **II** button at the top right pauses. Tap a card to pick it, and tap anywhere after death to start a new run.

The export settings live in `export_presets.cfg`. The Web build is single-threaded so it runs on GitHub Pages, which can't send the cross-origin isolation headers threaded builds need. The APK is signed with `ci/heatsink-debug.keystore`, a committed debug key that is fine for sideloading but not for the Play Store.

## Run it

1. Install Godot 4.7.2 (standard build, not .NET).
2. Open Godot, click **Import**, and pick `project.godot` in this folder.
3. Press **F5** (or the Play button). The game opens on the main menu: **Start Run** (pick a Frame, then a difficulty), **Codex** (how to play: Heat, Vent, every item, the enemies and the room types), **Settings** (volume, screen shake, fullscreen, lights & shadows, an FPS counter; saved between sessions) and **Quit** (not shown in the browser). The Codex is also in the pause menu.

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

## Frames (vertical slice step 4)

START RUN first asks which Frame you take; the choice is remembered. Each Frame has its own weapon, Overdrive, Vent and passive (GDD section 3). Fire is the same button for all three, so keyboard, pad and the touch aim stick all work.

| Frame | Weapon | Overdrive (Hot) | Vent | Passive |
| --- | --- | --- | --- | --- |
| **Riveter** (6 pips) | Rivet Gun: 5 shots/s, 8 dmg, +6 Heat per shot, rivets stick | Pierce 1, ricochet once | x1.0, stuck rivets detonate | Tension: +5% Vent damage per rivet |
| **Furnace** (7 pips) | Slag Maul: hold to swing a 3-hit combo (22 / 22 / 40) in a 150° arc, +12 Heat per swing; the third hit leaves a Molten pool | Every swing throws a shockwave 4 tiles forward (15 dmg) | x1.5; at 80+ Heat a Slag Shield blocks the next hit for 4 s (gold pip on the HUD) | Momentum: hits chained within 0.6 s delay cooling by 0.3 s each, up to 2 s |
| **Arclight** (6 pips) | Coil Lance: hold to channel a 7-tile beam, 40 dmg/s, +20 Heat/s; chains to 1 more enemy, +1 per Heat band (chained enemies take 35%) | The beam forks into 3 | x0.8, leaves a Static Pylon that zaps for 12 every 0.5 s for 4 s | Grounded: 1 s after you stop channelling, Heat cools twice as fast |

- Items work with every Frame ("hits" means rivets, swings, shockwaves and beam pulses; the beam triggers on-hit items on every 3rd pulse per enemy). Bank Shot and Rebound Charge are only offered to the Riveter, Splinter Heads not to the Arclight. Brittle Crown gives +2 rivets, a shockwave on every swing, or +2 beam forks.
- Item offers lean toward the Frame's native keyword: Shrapnel, Molten or Arc.
- New keyword **Molten** with two items: **Slag Trail** (dashes leave Molten pools) and **Cinder Spill** (kills while Hot leave a pool; your pools set enemies on fire). Its Resonance makes pools 50% wider and 1 s longer.
- The Furnace has 7 Plating instead of 6: in melee the bot lost about twice as many runs as the Riveter on HOT without it.
- The Codex has a FRAMES page.

## What to try

- Fire to build Heat. At 80+ you're **Hot**: rivets turn gold, pierce one enemy and ricochet off walls (the Furnace throws shockwaves, the Arclight's beam forks).
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

## Difficulty and new enemies

START RUN asks how hot you run; the choice is remembered. WARM is the original balance.

| Level | What changes | Bot deaths, Riveter / Furnace / Arclight (16 runs each) |
| --- | --- | --- |
| COLD | 70% of the enemies, 85% HP, specials later, fewer Elite doors | 0 / 0 / 0 |
| WARM | The original balance | 1 / 1 / 0 |
| HOT | 1.5x enemies, +1 wave per room, waves overlap sooner, specials earlier, Clinkers surround you | 1 / 4 / 0 |
| SEARING | 1.85x enemies, +2 waves that pile up, +15% HP, at least 3 Elite doors, Slagspitters aim ahead | 10 / 7 / 3 |
| MELTDOWN | 2.1x enemies, +2 waves, +25% HP, two Forgewardens at the Gate | 11 / 11 / 6 |

The bot never lets the Arclight Overheat, which is the Frame's real risk for a person, so its numbers flatter it.

- **Sparkhound** (chaser, from room 2): a fast low hound. It plants its feet while an orange arrow shows its lane for 0.55 s, then rushes 6 tiles. Step sideways or dash; a missed rush leaves it skidding for 0.9 s.
- **Slagspitter** (zoner, from room 4): keeps 5-8 tiles away. Five dotted cyan lanes show for 0.6 s, then five slow slag bolts fly along them.
- **Slag Mortar** (artillery, from room 5): a tracked kiln that backs away. A red ring marks where its shell lands and fills in during the 1.1 s flight.

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
| `scripts/combat/heat.gd` | Heat gauge, bands, decay, Overheat |
| `scripts/combat/player.gd` | Movement, Rivet Gun, dash, Vent, damage; picks the Frame's weapon |
| `scripts/frames.gd`, `scripts/ui/frame_panel.gd` | The three Frames' data and the Frame cards after START RUN |
| `scripts/combat/weapons/slag_maul.gd`, `scripts/combat/projectiles/shockwave.gd`, `scripts/combat/projectiles/slag_pool.gd` | Furnace: maul combo and Momentum, Overdrive shockwaves, the Molten pools the player leaves |
| `scripts/combat/weapons/coil_lance.gd`, `scripts/combat/projectiles/static_pylon.gd` | Arclight: channelled beam with chains and forks, the Vent's Static Pylon |
| `scripts/combat/projectiles/rivet.gd` | Projectile with embed, pierce and ricochet |
| `scripts/combat/enemies/enemy.gd`, `scripts/combat/enemies/clinker.gd` | Enemy base and the Clinker fodder |
| `scripts/combat/enemies/linesman.gd` | Linesman: Tether beam and Snap Back |
| `scripts/combat/enemies/sparkhound.gd`, `scripts/combat/enemies/slagspitter.gd`, `scripts/combat/projectiles/slag_bolt.gd`, `scripts/combat/enemies/slag_mortar.gd` | Sparkhound, Slagspitter and its bolts, Slag Mortar and its shells |
| `scripts/difficulty.gd`, `scripts/ui/difficulty_panel.gd` | The five difficulty levels and the picker after START RUN |
| `scripts/combat/enemies/forgewarden.gd`, `scripts/combat/projectiles/molten_patch.gd` | Forgewarden Elite: armour, Hammerfall, Bellows Breath, Molten floor |
| `scripts/combat/director.gd` | Wave plans from Threat Point budgets, Elite rooms, portal warnings |
| `scripts/presentation/juice.gd`, `scripts/presentation/sfx.gd`, `scripts/presentation/fx.gd` | Hit-stop, shake, synthesized sound, particles |
| `scripts/ui/hud.gd` | Heat gauge, pips, item chips, edge tints, Death Ledger |
| `scripts/item_db.gd` | Item, Resonance and Fusion data |
| `scripts/combat/inventory.gd` | Owned items, offers, and the trigger hooks that give items their behaviour |
| `scripts/combat/projectiles/shard.gd` | Shrapnel shards, homing embers and Firestorm flares |
| `scripts/ui/picker.gd` | Pick-1-of-N card screen for rewards, the Crucible and the coin flip |
| `scripts/run/run_map.gd` | The Stratum route: room types and door rolls with the GDD's constraints |
| `scripts/world/room.gd`, `scripts/world/layouts.gd` | Room built from a layout template, plus pathing and line-of-sight helpers |
| `scripts/world/room_gen.gd` | Procedural combat-room generator and the rules every room must pass |
| `scripts/world/street_room.gd`, `scripts/world/street_gen.gd`, `scripts/world/street_data.gd` | Rainside yards: the 2.5D room type, its procedural generator, and hand-authored templates |
| `scripts/world/door.gd` | Doors that preview the next room |
| `scripts/world/pedestal.gd` | Shop items, repairs, the Anvil, altars and the Crucible |
| `scripts/world/scrap_bit.gd` | Scrap pickups |
| `scripts/presentation/glow.gd`, `scripts/presentation/lights.gd`, `scripts/presentation/ambience.gd` | Additive glow textures, the pool of 2D light flashes that throw wall shadows, and the room dimming that makes lights read |
| `scripts/presentation/upright.gd`, `scripts/presentation/figure_data.gd` | Rainside's standing sprites: draws each actor as a 2.5D figure and holds their per-pose art data |
| `scripts/presentation/bloom.gd` | Soft bloom on bright things; desktop builds only (they run Forward+), Android and web stay on Compatibility without bloom |
| `menu.tscn`, `scripts/ui/main_menu.gd` | Title screen (the scene the game starts on) |
| `scripts/ui/pause_menu.gd`, `scripts/ui/settings_panel.gd` | Pause menu and the shared Settings panel |
| `scripts/ui/codex_panel.gd` | The Codex: how-to-play pages, with items and room types read from the game data |
| `scripts/settings.gd`, `scripts/ui/ui_style.gd`, `scripts/ui/fps_counter.gd` | Saved settings (autoload), the menu look and the optional FPS counter |
| `tests/bot_playtest.tscn` | Automated bot playtest that reports room clear times |
| `tests/contracts_test.tscn` | Deterministic fusion, combat, dash, input and UI contracts |
| `tests/heat_test.tscn`, `tests/run_map_test.tscn` | Heat boundaries and signals; seeded Stratum route invariants and replay |
| `tests/game_test.tscn` | Run lifecycle, one-time kill rewards, delayed Salvage and door transitions |
| `tests/director_test.tscn` | Placement failure/retry, mandatory Elite spawning and encounter events |
| `tests/presentation_test.tscn` | Glow resources, lighting and FPS settings, inherited menu styles |
| `tests/settings_test.tscn` | Settings disk round-trip and failed-write recovery in isolated user data |
| `tests/special_rooms_test.tscn` | Shop and vault transactions plus controlled Coin and Crucible outcomes |
| `tests/projectile_test.tscn` | Real physics checks for Rivet collisions, shard recursion/homing and flare detonation |
| `tests/absolution_test.tscn` | Slagged-item progress, completion signals and drawback removal |
| `tests/inventory_test.tscn`, `tests/room_spawn_test.tscn` | Focused fusion ownership and safe spawn-placement checks |
| `tests/room_gen_test.gd` | Generates 2000 rooms and fails if any breaks the rules or the door check |
| `tests/menu_test.tscn` | Walks menu → settings → codex → run → pause → menu and fails if a step doesn't work |
| `tests/frame_shots.tscn` | Screenshots of the Frame cards, the Codex page and each Frame's weapon, Overdrive and Vent (needs a renderer, not headless) |
| `tests/muzzle_test.tscn` | Checks each Frame's weapon fires/swings/channels and reports visible muzzle state |
| `tests/street_shots.tscn` | Screenshots of a generated Rainside yard, its props and figures (needs a renderer, not headless) |
| `tests/ui_shots.tscn` | Screenshots of the Codex, the FPS counter and the Vent ring (needs a renderer, not headless) |
| `tests/lighting_shots.tscn` | Staged screenshots of tracers, the Linesman beam, a Vent and bolt light and shadows by the pillars (needs a renderer, not headless; `--rendering-method forward_plus` shows bloom, `gl_compatibility` the Android/web look) |

Automated playtest (headless):

```
python tests/run_headless.py res://tests/bot_playtest.tscn -- 400 1 x
```

Use `allitems` instead of `x` to start with every item and 4 Cores as a stress test, `slagged` to start with the three Slagged items, `elite` to take every Elite door, or `forge` to start with Tinder Rounds, 3 Cores and an Anvil choice before random drops can complete the recipe naturally. Add `diff=0` to `diff=4` to play COLD to MELTDOWN (default WARM), and `frame=furnace` or `frame=arclight` to play another Frame (default Riveter). The report lists pips lost by source. The bot shops, rests, gambles and picks doors on its own, and the run ends when it clears the Gate.

Room generator check (exits with code 1 on a bad room):

```
python tests/run_headless.py res://tests/room_gen_test.gd -- 2000 1
```

Menu check (exits with code 1 if a menu step fails):

The Python runner uses a fresh temporary user-data directory before Godot starts
and removes it afterward, so tests cannot overwrite player preferences. It runs
on Windows and Linux with a fixed 60 FPS. Set `GODOT_BIN` or pass `--godot` if the
engine is not on PATH; on Windows, `py -3.11` can replace `python`.

```
python tests/run_headless.py res://tests/menu_test.tscn
```

Focused gameplay checks (each reports failures and exits nonzero if a check fails):

```
python tests/run_headless.py res://tests/contracts_test.tscn
python tests/run_headless.py res://tests/heat_test.tscn
python tests/run_headless.py res://tests/run_map_test.tscn
python tests/run_headless.py res://tests/game_test.tscn
python tests/run_headless.py res://tests/director_test.tscn
python tests/run_headless.py res://tests/presentation_test.tscn
python tests/run_headless.py res://tests/settings_test.tscn
python tests/run_headless.py res://tests/special_rooms_test.tscn
python tests/run_headless.py res://tests/projectile_test.tscn
python tests/run_headless.py res://tests/absolution_test.tscn
python tests/run_headless.py res://tests/inventory_test.tscn
python tests/run_headless.py res://tests/room_spawn_test.tscn
```
