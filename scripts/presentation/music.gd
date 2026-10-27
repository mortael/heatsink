extends Node
## Background music: one continuous track that starts once, at the title screen, and keeps
## playing through the menu and every run - scene changes never touch this autoload, so there's
## nothing to restart. Runs on its own "Music" bus so Settings can balance it against SFX.

var _track: AudioStream = preload("res://audio/music/neon_horizon.ogg")
var player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
	_track.loop = true
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	player.stream = _track
	add_child(player)
	apply_volume()


## Starts the track if it isn't already playing. Safe to call more than once (the title screen
## is the only caller, but nothing breaks if that ever changes).
func start() -> void:
	if not player.playing:
		player.play()


## No-ops if called before _ready() has created the bus (Settings autoloads first and applies
## its values once at startup, before Music exists yet); _ready() applies the current value itself.
func apply_volume() -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(Settings.music) if Settings.music > 0.0 else -80.0)
	AudioServer.set_bus_mute(idx, Settings.music <= 0.0)
