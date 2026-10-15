class_name FpsCounter
extends CanvasLayer
## Optional frames-per-second readout in the top-left corner (Settings › Show FPS).
## Lives under the Settings autoload, so it shows on every screen, menus and pause included.

const REFRESH := 0.25

var label := Label.new()
var _t := 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	label.position = Vector2(4, 0)
	label.visible = Settings.show_fps
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.6))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	_refresh()


func _process(delta: float) -> void:
	label.visible = Settings.show_fps
	if not label.visible:
		return
	_t += delta
	if _t >= REFRESH:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	label.text = "%d FPS" % roundi(Engine.get_frames_per_second())
