class_name Bloom
extends WorldEnvironment
## Soft bloom: the brightest things in the room (bolts, beams, neon doors, blasts) bleed a haze
## past their edges. Only Forward+ and Mobile can do this, so desktop builds run Forward+.
## Android and the web stay on Compatibility and keep the drawn glow without bloom: the Mobile
## renderer showed banding rings around every light. Without Vulkan or Direct3D 12 the desktop
## build falls back to OpenGL, and supported() turns bloom off there too.
## Follows the Lights & shadows and Bloom settings. The HUD sits on higher canvas layers and never blooms.


func _ready() -> void:
	add_to_group("dynamic_lights")
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS # the 2D world is the "background" the glow works on
	env.glow_enabled = true
	env.glow_intensity = 1.4
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.7
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment = env
	apply_lights()


static func supported() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


func apply_lights() -> void:
	environment.glow_enabled = Settings.lights and Settings.bloom and supported()
