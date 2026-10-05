class_name Heat
extends Node
## Heat gauge 0-100 with Cold / Warm / Hot bands and Overheat (GDD section 2).

signal band_changed(new_band: int, old_band: int)
signal overheated
signal overheat_ended

enum Band { COLD, WARM, HOT, OVERHEAT }

const WARM_AT := 40.0
const HOT_AT := 80.0
const OVERHEAT_TIME := 2.0
const RESET_AFTER_OVERHEAT := 50.0

var value := 0.0
var cap := 100.0
var decay_rate := 12.0
var decay_delay := 1.0
var band: int = Band.COLD
var overheat_timer := 0.0
var overheat_count := 0
var _since_gain := 99.0


func is_overheated() -> bool:
	return overheat_timer > 0.0


func add(amount: float) -> void:
	if is_overheated():
		return
	value = minf(value + amount, cap)
	_since_gain = 0.0
	if value >= cap:
		_overheat()
	else:
		_update_band()


func quench(amount: float) -> void:
	if is_overheated():
		return
	value = maxf(0.0, value - amount)
	_update_band()


## Empties the gauge and returns how much Heat was dumped.
func vent() -> float:
	var dumped := value
	value = 0.0
	_update_band()
	return dumped


func set_value(v: float) -> void:
	if is_overheated():
		return
	value = clampf(v, 0.0, cap - 1.0)
	_update_band()


func tick(delta: float) -> void:
	if is_overheated():
		overheat_timer -= delta
		if overheat_timer <= 0.0:
			overheat_timer = 0.0
			value = RESET_AFTER_OVERHEAT
			_update_band()
			overheat_ended.emit()
		return
	_since_gain += delta
	if _since_gain >= decay_delay and value > 0.0:
		value = maxf(0.0, value - decay_rate * delta)
		_update_band()


func band_name() -> String:
	return ["COLD", "WARM", "HOT", "OVERHEAT"][band]


func _overheat() -> void:
	overheat_timer = OVERHEAT_TIME
	overheat_count += 1
	var old := band
	band = Band.OVERHEAT
	band_changed.emit(band, old)
	overheated.emit()


func _update_band() -> void:
	var b: int = Band.COLD
	if value >= HOT_AT:
		b = Band.HOT
	elif value >= WARM_AT:
		b = Band.WARM
	if b != band:
		var old := band
		band = b
		band_changed.emit(band, old)
