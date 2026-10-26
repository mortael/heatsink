extends Node
## Generated visual resources and settings-driven behavior without pixel snapshots.

const GlowScript = preload("res://scripts/presentation/glow.gd")
const AmbienceScript = preload("res://scripts/presentation/ambience.gd")
const FpsScript = preload("res://scripts/ui/fps_counter.gd")
const StyleScript = preload("res://scripts/ui/ui_style.gd")

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	_glow_resources()
	_lighting_setting()
	_fps_setting()
	_menu_theme()
	print("presentation test: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _glow_resources() -> void:
	var halo: GradientTexture2D = GlowScript.soft()
	check(halo.width == halo.height and halo.width > 0 and halo.fill == GradientTexture2D.FILL_RADIAL, "Halo textures are square radial resources")
	check(halo.gradient.sample(0.0).a > halo.gradient.sample(0.5).a and halo.gradient.sample(1.0).a == 0.0, "Halos fade from a bright center to a transparent rim")
	check(GlowScript.soft() == halo, "Repeated halo requests share the cached resource")
	var beam: GradientTexture2D = GlowScript.band()
	check(beam.gradient.sample(0.5).a > 0.99 and beam.gradient.sample(0.0).a == 0.0 and beam.gradient.sample(1.0).a == 0.0, "Beam strips have a bright center and transparent edges")
	var light: GradientTexture2D = GlowScript.light()
	check(light.gradient.sample(0.0) == Color.WHITE and light.gradient.sample(1.0) == Color.BLACK, "Point-light textures fall off from white to black")
	var material := GlowScript.additive()
	check(material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD and material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED, "Glow remains additive and independent of room lighting")


func _lighting_setting() -> void:
	var previous: bool = Settings.lights
	Settings.lights = true
	var ambience := AmbienceScript.new()
	add_child(ambience)
	check(ambience.is_in_group("dynamic_lights") and ambience.color == AmbienceScript.DIM, "Room ambience registers for lighting updates and dims an enabled room")
	Settings.lights = false
	get_tree().call_group("dynamic_lights", "apply_lights")
	check(ambience.color == Color.WHITE, "Disabling lights restores full room brightness")
	Settings.lights = true
	get_tree().call_group("dynamic_lights", "apply_lights")
	check(ambience.color == AmbienceScript.DIM, "Re-enabling lights restores ambience dimming")
	ambience.free()
	Settings.lights = previous
	get_tree().call_group("dynamic_lights", "apply_lights")


func _fps_setting() -> void:
	var previous: bool = Settings.show_fps
	Settings.show_fps = false
	var counter := FpsScript.new()
	add_child(counter)
	counter.set_process(false)
	check(not counter.label.visible and counter.label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The disabled FPS overlay stays hidden and cannot capture menu input")
	Settings.show_fps = true
	counter.label.text = "waiting"
	counter._process(FpsScript.REFRESH * 0.5)
	check(counter.label.visible and counter.label.text == "waiting", "Enabling FPS reveals it without refreshing before its interval")
	counter._process(FpsScript.REFRESH * 0.5)
	check(counter.label.text == "%d FPS" % roundi(Engine.get_frames_per_second()), "The refresh interval publishes the current engine FPS")
	get_tree().paused = true
	check(counter.can_process(), "The FPS overlay continues processing while a menu pauses the run")
	get_tree().paused = false
	Settings.show_fps = false
	counter._process(FpsScript.REFRESH)
	check(not counter.label.visible, "Disabling FPS hides an already-visible overlay")
	counter.free()
	Settings.show_fps = previous


func _menu_theme() -> void:
	var panel := PanelContainer.new()
	panel.theme = StyleScript.theme()
	var button := StyleScript.button("CONTINUE", 240.0)
	panel.add_child(button)
	add_child(panel)
	check(button.text == "CONTINUE" and button.custom_minimum_size.x == 240.0 and button.focus_mode == Control.FOCUS_ALL, "Menu buttons retain their label, requested width and keyboard/pad focus")
	check(button.get_theme_font_size("font_size") == 22 and button.get_theme_color("font_color") == StyleScript.TEXT, "Menu buttons inherit readable type and text colors from their theme")
	var normal: StyleBoxFlat = button.get_theme_stylebox("normal")
	var hover: StyleBoxFlat = button.get_theme_stylebox("hover")
	var focus: StyleBoxFlat = button.get_theme_stylebox("focus")
	check(normal.bg_color != hover.bg_color and focus.border_width_left > normal.border_width_left, "Hover and keyboard focus have distinct visible button styles")
	var slider := HSlider.new()
	panel.add_child(slider)
	var grabber := slider.get_theme_icon("grabber")
	check(grabber.get_width() > 0 and grabber.get_height() > 0 and slider.has_theme_stylebox("grabber_area_highlight"), "Sliders inherit a generated visible grabber and highlighted filled track")
	panel.free()
