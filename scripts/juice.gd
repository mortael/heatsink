extends Node
## Global game-feel service: hit-stop with a budget, and trauma-based screen shake (GDD section 8).

const HITSTOP_MIN_GAP_MS := 100
const HITSTOP_BUDGET_FRAMES := 12 # per second of play

var camera: Camera2D
var trauma := 0.0
var shake_strength := 1.0 # accessibility slider 0..1
var hitstop_strength := 1.0
var total_hitstop_frames := 0

var _hitstop_until_ms := 0
var _last_start_ms := -100000
var _window_start_ms := 0
var _window_used := 0
var _last_us := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_us = Time.get_ticks_usec()


func hitstop(frames: int) -> void:
	frames = int(round(frames * hitstop_strength))
	if frames <= 0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_start_ms < HITSTOP_MIN_GAP_MS:
		return
	if now - _window_start_ms > 1000:
		_window_start_ms = now
		_window_used = 0
	frames = mini(frames, HITSTOP_BUDGET_FRAMES - _window_used)
	if frames <= 0:
		return
	_window_used += frames
	total_hitstop_frames += frames
	_last_start_ms = now
	_hitstop_until_ms = maxi(_hitstop_until_ms, now + int(frames * 1000.0 / 60.0))
	Engine.time_scale = 0.0


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func reset() -> void:
	trauma = 0.0
	_hitstop_until_ms = 0
	Engine.time_scale = 1.0


func _process(_delta: float) -> void:
	var now_us := Time.get_ticks_usec()
	var real_dt := (now_us - _last_us) / 1000000.0
	_last_us = now_us
	if Engine.time_scale == 0.0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		Engine.time_scale = 1.0
	trauma = maxf(0.0, trauma - 1.6 * real_dt)
	if is_instance_valid(camera):
		var s := trauma * trauma * shake_strength
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 12.0 * s
		camera.rotation = deg_to_rad(1.5) * s * randf_range(-1, 1)
