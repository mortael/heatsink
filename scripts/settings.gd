extends Node
## Player settings (volume, screen shake, fullscreen, lights, FPS counter), saved to user://settings.cfg and applied at startup.

const PATH := "user://settings.cfg"

var volume := 0.8 # master volume, 0..1
var shake := 1.0 # screen shake strength, 0..1
var fullscreen := false
var lights := true # dynamic 2D lights and wall shadows; glow drawing stays on either way
var show_fps := false # small frames-per-second readout in the top-left corner
var dirty := false # changed since the last save; saved on quit if the panel was never closed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err == OK:
		volume = clampf(cfg.get_value("audio", "volume", volume), 0.0, 1.0)
		shake = clampf(cfg.get_value("video", "shake", shake), 0.0, 1.0)
		fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
		var l: Variant = cfg.get_value("video", "lights", lights)
		if l is bool:
			lights = l
		var f: Variant = cfg.get_value("video", "show_fps", show_fps)
		if f is bool:
			show_fps = f
	elif err != ERR_FILE_NOT_FOUND:
		push_warning("Settings: could not read %s (error %d), using defaults" % [PATH, err])
	# A browser only allows fullscreen from a click, so the web build never restores it at startup.
	apply(not OS.has_feature("web"))
	add_child(FpsCounter.new())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and dirty:
		save()


## Fullscreen only exists on desktop and in the browser; other platforms ignore it.
static func can_fullscreen() -> bool:
	return not OS.has_feature("mobile") and DisplayServer.get_name() != "headless"


## Applies the current values. with_fullscreen is false only for the web build's startup.
func apply(with_fullscreen := true) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(volume) if volume > 0.0 else -80.0)
	AudioServer.set_bus_mute(0, volume <= 0.0)
	Juice.shake_strength = shake
	if with_fullscreen and can_fullscreen():
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("video", "shake", shake)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "lights", lights)
	cfg.set_value("video", "show_fps", show_fps)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [PATH, err])
		return
	dirty = false


func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
