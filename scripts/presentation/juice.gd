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
var _slow_until_ms := 0
var _slow_scale := 1.0
var _punch := 0.0
var _last_start_ms := -100000
var _window_start_ms := 0
var _window_used := 0
var _last_us := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_us = Time.get_ticks_usec()


## force: big moments (plate breaks, elite kills) skip the 100 ms gap rule so a rivet's
## own 2-frame stop can't swallow them; they still count against the budget.
func hitstop(frames: int, force := false) -> void:
	frames = int(round(frames * hitstop_strength))
	if frames <= 0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_start_ms < HITSTOP_MIN_GAP_MS and not force:
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


## Slow motion after the current hit-stop ends (elite and boss kills: 0.3x for 0.25 s).
func slowmo(scale: float, seconds: float) -> void:
	_slow_scale = scale
	_slow_until_ms = maxi(_hitstop_until_ms, Time.get_ticks_msec()) + int(seconds * 1000.0)


## Camera punch-in, eased back over 0.4 s.
func punch(amount: float) -> void:
	_punch = maxf(_punch, amount)


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func reset() -> void:
	trauma = 0.0
	_hitstop_until_ms = 0
	_slow_until_ms = 0
	_punch = 0.0
	Engine.time_scale = 1.0


func _process(_delta: float) -> void:
	var now_us := Time.get_ticks_usec()
	var real_dt := (now_us - _last_us) / 1000000.0
	_last_us = now_us
	var now := Time.get_ticks_msec()
	if Engine.time_scale == 0.0 and now >= _hitstop_until_ms:
		Engine.time_scale = _slow_scale if now < _slow_until_ms else 1.0
	elif Engine.time_scale > 0.0 and Engine.time_scale < 1.0 and now >= _slow_until_ms:
		Engine.time_scale = 1.0
	elif Engine.time_scale == 1.0 and now < _slow_until_ms and now >= _hitstop_until_ms:
		Engine.time_scale = _slow_scale
	_punch = maxf(0.0, _punch - real_dt * 0.1)
	trauma = maxf(0.0, trauma - 1.6 * real_dt)
	if is_instance_valid(camera):
		var s := trauma * trauma * shake_strength
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 12.0 * s
		camera.rotation = deg_to_rad(1.5) * s * randf_range(-1, 1)
		camera.zoom = Vector2.ONE * (1.0 + _punch)
