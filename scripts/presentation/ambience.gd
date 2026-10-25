class_name Ambience
extends CanvasModulate
## Dims the room so lights read as light: the Sink's own lamp, the neon doors, beams and blasts
## brighten it again, and walls throw shadows. With Lights & shadows off the room stays fully lit.

const DIM := Color(0.68, 0.66, 0.72)


func _ready() -> void:
	add_to_group("dynamic_lights")
	apply_lights()


func apply_lights() -> void:
	color = DIM if Settings.lights else Color.WHITE
