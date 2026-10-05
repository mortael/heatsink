# HEATSINK prototype

First playable for the HEATSINK GDD: the Riveter Frame, the Heat gauge, Vent, Clinker fodder and one hand-made room with endless waves.

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
| Restart after death | R | Start |

## What to try

- Fire to build Heat. At 80+ you're **Hot**: rivets turn gold, pierce one enemy and ricochet off walls.
- Keep firing to 100 and you **Overheat**: the gun locks for 2 s, you move slower, and every hit costs an extra pip.
- **Vent** dumps all Heat as a nova that grows with Heat, and every rivet stuck in an enemy detonates.
- **Dash** gives brief invulnerability and quenches 10 Heat, so you can use it to stay in the Hot band longer.
- Clinkers glow orange and squash for 0.6 s before they lunge. Dash through or step out of the way.

## Layout

| Path | What it is |
| --- | --- |
| `scripts/heat.gd` | Heat gauge, bands, decay, Overheat |
| `scripts/player.gd` | Movement, Rivet Gun, dash, Vent, damage |
| `scripts/rivet.gd` | Projectile with embed, pierce and ricochet |
| `scripts/enemy.gd`, `scripts/clinker.gd` | Enemy base and the Clinker fodder |
| `scripts/director.gd` | Wave spawning with portal warnings and threat budgets |
| `scripts/juice.gd`, `scripts/sfx.gd`, `scripts/fx.gd` | Hit-stop, shake, synthesized sound, particles |
| `scripts/hud.gd` | Heat gauge, pips, edge tints, Death Ledger |
| `tests/bot_playtest.tscn` | Automated bot playtest that reports room clear times |

Automated playtest (headless):

```
godot --headless --path . --fixed-fps 60 res://tests/bot_playtest.tscn -- 180 1
```
