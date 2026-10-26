class_name Ambience
extends CanvasModulate
## Dims the room so lights read as light: the Sink's own lamp, the neon doors, beams and blasts
## brighten it again, and walls throw shadows. With Lights & shadows off the room stays fully lit.

const DIM := Color(0.68, 0.66, 0.72)
const NIGHT := Color(0.62, 0.66, 0.84) # Rainside rooms: cold night light (StreetData art is painted for this tint)

var night := false


func _ready() -> void:
	add_to_group("dynamic_lights")
	apply_lights()


func apply_lights() -> void:
	# The night tint stays with lights off too: the street's art is painted for it.
	if night:
		color = NIGHT
	else:
		color = DIM if Settings.lights else Color.WHITE
