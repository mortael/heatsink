extends Node
## Player settings (volume, screen shake, fullscreen), saved to user://settings.cfg and applied at startup.

const PATH := "user://settings.cfg"

var volume := 0.8 # master volume, 0..1
var shake := 1.0 # screen shake strength, 0..1
var fullscreen := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		volume = clampf(cfg.get_value("audio", "volume", volume), 0.0, 1.0)
		shake = clampf(cfg.get_value("video", "shake", shake), 0.0, 1.0)
		fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	apply()


## Fullscreen only exists on desktop and in the browser; other platforms ignore it.
static func can_fullscreen() -> bool:
	return not OS.has_feature("mobile") and DisplayServer.get_name() != "headless"


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(volume) if volume > 0.0 else -80.0)
	AudioServer.set_bus_mute(0, volume <= 0.0)
	Juice.shake_strength = shake
	if can_fullscreen():
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("video", "shake", shake)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(PATH)
