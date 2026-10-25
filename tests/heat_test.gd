extends Node

const HeatScript = preload("res://scripts/combat/heat.gd")

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _ready() -> void:
	_heat_contracts()
	_clamping_and_signals()
	_threshold_changes_during_decay_delay()
	print("heat test: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _heat_contracts() -> void:
	var heat := HeatScript.new()
	var events: Array[String] = []
	heat.band_changed.connect(func(new_band: int, _old: int) -> void: events.append("band:%d" % new_band))
	heat.overheated.connect(func() -> void: events.append("overheated"))
	heat.overheat_ended.connect(func() -> void: events.append("recovered"))
	heat.add(39.0)
	check(heat.band == Heat.Band.COLD, "39 Heat stays Cold")
	heat.add(1.0)
	check(heat.band == Heat.Band.WARM, "40 Heat enters Warm")
	heat.add(40.0)
	check(heat.band == Heat.Band.HOT, "80 Heat enters Hot")
	heat.add(20.0)
	check(events == ["band:1", "band:2", "band:3", "overheated"], "Overheat emits band before notification")
	heat.add(20.0)
	heat.quench(10.0)
	heat.set_value(0.0)
	check(heat.value == 100.0, "Lockout suppresses gain, quench and set")
	heat.tick(2.0)
	check(heat.value == Heat.RESET_AFTER_OVERHEAT and heat.band == Heat.Band.WARM, "Lockout recovers Warm")
	check(events.slice(-2) == ["band:1", "recovered"], "Recovery emits band before ended")
	heat.set_value(79.0)
	heat.tick(0.5)
	check(heat.value == 79.0, "Gain delay suppresses decay")
	heat.tick(0.5)
	check(is_equal_approx(heat.value, 73.0), "Decay begins at the configured delay")
	check(heat.vent() == 73.0 and heat.band == Heat.Band.COLD, "Vent returns dumped amount and enters Cold")
	heat.cap = 120.0
	heat.hot_at = 65.0
	heat.overheat_time = 3.0
	heat.add(65.0)
	check(heat.band == Heat.Band.HOT, "Modified Hot threshold applies")
	heat.add(55.0)
	heat.tick(2.0)
	check(heat.is_overheated(), "Modified lockout lasts longer")
	heat.tick(1.0)
	check(not heat.is_overheated(), "Modified lockout completes")
	heat.free()


func _clamping_and_signals() -> void:
	var heat := HeatScript.new()
	var changes: Array[int] = []
	heat.band_changed.connect(func(band: int, _old: int) -> void: changes.append(band))
	heat.set_value(-5.0)
	check(heat.value == 0.0 and changes.is_empty(), "Setting negative Heat clamps to Cold without a redundant signal")
	heat.set_value(200.0)
	check(heat.value == 99.0 and heat.band_name() == "HOT" and not heat.is_overheated(), "Setting Heat clamps below Overheat rather than triggering a lockout")
	heat.set_value(90.0)
	check(changes == [Heat.Band.HOT], "Changes within one band do not emit another band notification")
	heat.quench(200.0)
	check(heat.value == 0.0 and heat.band_name() == "COLD", "Quenching cannot produce negative Heat")
	heat.add(200.0)
	heat.add(200.0)
	check(heat.value == heat.cap and heat.overheat_count == 1 and heat.band_name() == "OVERHEAT", "Reaching the cap enters exactly one lockout and records one Overheat")
	heat.tick(Heat.OVERHEAT_TIME + 1.0)
	check(heat.overheat_timer == 0.0 and heat.value == Heat.RESET_AFTER_OVERHEAT, "An oversized recovery step clamps its timer and preserves the recovery Heat")
	heat.free()


func _threshold_changes_during_decay_delay() -> void:
	var heat := HeatScript.new()
	var changes: Array[int] = []
	heat.band_changed.connect(func(band: int, _old: int) -> void: changes.append(band))
	heat.add(70.0)
	heat.hot_at = 60.0 # Acquiring Feral Valve changes the threshold immediately.
	heat.tick(0.01)
	check(heat.value == 70.0 and heat.band == Heat.Band.HOT and changes == [Heat.Band.WARM, Heat.Band.HOT], "A lower Hot threshold applies during the gain delay without requiring decay or another shot")
	heat.hot_at = Heat.HOT_AT
	heat.tick(0.01)
	check(heat.value == 70.0 and heat.band == Heat.Band.WARM and changes[-1] == Heat.Band.WARM, "Removing the lower threshold immediately restores Warm without changing Heat")
	heat.add(30.0)
	heat.hot_at = 60.0
	heat.tick(0.01)
	check(heat.band == Heat.Band.OVERHEAT, "Threshold refresh cannot replace an active Overheat lockout band")
	heat.free()
