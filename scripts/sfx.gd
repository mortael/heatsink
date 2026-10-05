extends Node
## Procedurally synthesised sound effects (no audio assets needed for the prototype).
## Layering per GDD section 8: crits add a bright ting + sub thump; repeated procs ramp in pitch.

const RATE := 22050
const POOL := 16
const VOICE_LIMIT := 4
const RAMP_WINDOW_MS := 500
const RAMP_CAP := 7

var streams := {}
var players: Array[AudioStreamPlayer] = []
var _ramp := {} # name -> [last_ms, step]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	_build()


## semitones shifts pitch; db is a volume offset.
func play(sound: String, semitones := 0.0, db := 0.0) -> void:
	if not streams.has(sound):
		return
	var stream: AudioStream = streams[sound]
	var same := 0
	var free_player: AudioStreamPlayer = null
	for p in players:
		if p.playing:
			if p.stream == stream:
				same += 1
		elif free_player == null:
			free_player = p
	if same >= VOICE_LIMIT or free_player == null:
		return
	free_player.stream = stream
	free_player.pitch_scale = pow(2.0, semitones / 12.0) * randf_range(0.97, 1.03)
	free_player.volume_db = db
	free_player.play()


## Consecutive plays within 0.5 s rise one semitone each (cap +7).
func play_ramp(sound: String, db := 0.0) -> void:
	var now := Time.get_ticks_msec()
	var st: Array = _ramp.get(sound, [0, 0])
	var step: int = st[1] + 1 if now - int(st[0]) < RAMP_WINDOW_MS else 0
	step = mini(step, RAMP_CAP)
	_ramp[sound] = [now, step]
	play(sound, float(step), db)


func _build() -> void:
	streams["shot"] = _gen(0.07, func(t: float, n: float) -> float:
		return n * exp(-t * 70.0) * 0.45 + sin(TAU * 900.0 * t) * exp(-t * 55.0) * 0.35)
	streams["hit"] = _gen(0.08, func(t: float, n: float) -> float:
		return sin(TAU * (180.0 - 700.0 * t) * t) * exp(-t * 40.0) * 0.6 + n * exp(-t * 90.0) * 0.25)
	streams["crit"] = _gen(0.25, func(t: float, _n: float) -> float:
		return sin(TAU * 2400.0 * t) * exp(-t * 18.0) * 0.35 + sin(TAU * 60.0 * t) * exp(-t * 12.0) * (0.8 if t < 0.08 else 0.0))
	streams["kill"] = _gen(0.18, func(t: float, n: float) -> float:
		return n * exp(-t * 22.0) * 0.35 + sin(TAU * (130.0 - 200.0 * t) * t) * exp(-t * 18.0) * 0.5)
	streams["burst"] = _gen(0.12, func(t: float, n: float) -> float:
		return n * exp(-t * 35.0) * 0.5 + sin(TAU * 1500.0 * t) * exp(-t * 60.0) * 0.3)
	streams["vent"] = _gen(0.75, func(t: float, n: float) -> float:
		return sin(TAU * (110.0 - 70.0 * t) * t) * exp(-t * 4.0) * 0.8 + n * exp(-t * 6.0) * 0.3 * (1.0 - exp(-t * 40.0)))
	streams["overheat"] = _gen(0.5, func(t: float, _n: float) -> float:
		var f := 440.0 if int(t * 12.0) % 2 == 0 else 330.0
		return (1.0 if sin(TAU * f * t) > 0.0 else -1.0) * 0.18 * (1.0 - t / 0.5))
	streams["player_hit"] = _gen(0.22, func(t: float, n: float) -> float:
		return n * exp(-t * 14.0) * 0.6 + sin(TAU * 90.0 * t) * exp(-t * 20.0) * 0.5)
	streams["dash"] = _gen(0.15, func(t: float, n: float) -> float:
		return n * sin(PI * t / 0.15) * 0.25)
	streams["band"] = _gen(0.12, func(t: float, _n: float) -> float:
		return sin(TAU * 660.0 * t) * exp(-t * 25.0) * 0.4)
	streams["windup"] = _gen(0.3, func(t: float, _n: float) -> float:
		return sin(TAU * (200.0 + 500.0 * t) * t) * 0.3 * (t / 0.3))
	streams["ricochet"] = _gen(0.12, func(t: float, _n: float) -> float:
		return sin(TAU * (3000.0 - 5000.0 * t) * t) * exp(-t * 30.0) * 0.3)
	streams["portal"] = _gen(0.3, func(t: float, _n: float) -> float:
		return sin(TAU * (300.0 + 600.0 * t) * t) * 0.12 * sin(PI * t / 0.3))
	streams["clear"] = _gen(0.6, func(t: float, _n: float) -> float:
		var f := 523.0 if t < 0.15 else 784.0
		return sin(TAU * f * t) * exp(-fmod(t, 0.15) * 6.0) * 0.3)


func _gen(duration: float, fn: Callable) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	for i in count:
		var t := float(i) / RATE
		lp = lp * 0.6 + randf_range(-1.0, 1.0) * 0.4 # softened noise
		var v: float = clampf(fn.call(t, lp), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
