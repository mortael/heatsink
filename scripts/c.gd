class_name C
## Shared constants. Numbers come from the HEATSINK GDD.

const TILE := 48.0
const ROOM_W := 24
const ROOM_H := 13

const LAYER_WALL := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

# Telegraph colour code (GDD section 7)
const TELE_MELEE := Color(1.0, 0.55, 0.12)
const TELE_GROUND := Color(0.95, 0.2, 0.18)
const TELE_LINE := Color(0.35, 0.9, 1.0)
const TELE_STATE := Color(0.7, 0.45, 1.0)

const HEAT_COLD := Color(0.45, 0.55, 0.65)
const HEAT_WARM := Color(1.0, 0.62, 0.2)
const HEAT_HOT := Color(1.0, 0.95, 0.75)
const HEAT_OVER := Color(1.0, 0.18, 0.12)

const STEEL := Color(0.62, 0.66, 0.7)
const RIVET_GOLD := Color(1.0, 0.86, 0.45)
