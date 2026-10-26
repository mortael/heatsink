extends Node

const SettingsScript = preload("res://scripts/settings.gd")
const TestEnvironment = preload("res://tests/test_environment.gd")

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	# Refuse persistence checks unless the runner isolated data before autoloads.
	if not TestEnvironment.is_isolated():
		check(false, "Run settings_test through tests/run_headless.py to isolate user data")
		get_tree().quit(1)
		return
	Settings.volume = 0.35
	Settings.shake = 0.25
	Settings.fullscreen = true
	Settings.lights = false
	Settings.show_fps = true
	Settings.dirty = true
	check(Settings.save() == OK and not Settings.dirty, "Successful persistence clears the dirty flag")
	var cfg := ConfigFile.new()
	check(cfg.load(Settings.PATH) == OK and is_equal_approx(cfg.get_value("audio", "volume", -1.0), 0.35), "Saving writes a readable configuration file with the requested volume")
	var restored := SettingsScript.new()
	add_child(restored) # Exercise the same disk-load path as startup.
	check(is_equal_approx(restored.volume, 0.35) and is_equal_approx(restored.shake, 0.25), "Startup restores both numeric preferences from disk")
	check(restored.fullscreen and not restored.lights and restored.show_fps, "Startup restores all three boolean preferences from disk")
	restored.free()
	Settings.dirty = true
	var invalid_path := "user://missing-parent/settings.cfg"
	check(Settings.save(invalid_path) != OK and Settings.dirty, "An actual failed write reports failure and retains dirty state for retry")
	check(Settings.save() == OK and not Settings.dirty, "A later successful save recovers from the failed write")
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH)) == OK, "The settings round-trip removes its saved fixture")
	print("settings test: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
