class_name Clinker
extends Enemy
## Fodder. One attack: Lunge Bite with a 0.6 s orange mouth-glow + squash telegraph (GDD section 7).

enum S { CHASE, WINDUP, LUNGE, RECOVER }

const SPEED := 2.5 * C.TILE
const TRIGGER_RANGE := 2.0 * C.TILE
const WINDUP := 0.6
const AIM_LOCK := 0.15 # stops tracking this long before the lunge, so dodges are fair
const LUNGE_TIME := 0.2
const LUNGE_DIST := 2.0 * C.TILE
const RECOVER := 0.5

var state: int = S.CHASE
var t := 0.0
var facing := Vector2.RIGHT
var bit := false
var wobble := randf() * TAU


func _init() -> void:
	max_hp = 14.0
	radius = 13.0
	source_name = "Clinker · Lunge Bite"


func _ai(delta: float) -> void:
	wobble += delta * 6.0
	var p: Player = game.player
	var to_p := p.global_position - global_position
	match state:
		S.CHASE:
			if to_p.length() > 1.0:
				facing = nav_dir(p.global_position, delta)
			var desired := (facing * SPEED + _separation().limit_length(1.0) * SPEED * 1.2).limit_length(SPEED)
			velocity = velocity.lerp(desired, 0.15)
			if to_p.length() < TRIGGER_RANGE and not game.dead:
				state = S.WINDUP
				t = WINDUP
				Sfx.play("windup", randf_range(-1.0, 1.0), -14.0)
		S.WINDUP:
			t -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			if t > AIM_LOCK and to_p.length() > 1.0:
				facing = to_p.normalized()
			if t <= 0.0:
				state = S.LUNGE
				t = LUNGE_TIME
				bit = false
		S.LUNGE:
			t -= delta
			velocity = facing * (LUNGE_DIST / LUNGE_TIME)
			if not bit and to_p.length() < radius + Player.RADIUS + 4.0:
				bit = true
				p.take_hit(1, source_name)
			if t <= 0.0:
				state = S.RECOVER
				t = RECOVER
		S.RECOVER:
			t -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
			if t <= 0.0:
				state = S.CHASE


func _draw() -> void:
	var sx := 1.0
	var sy := 1.0 + sin(wobble) * 0.04
	var glow := 0.0
	if state == S.WINDUP:
		var k := 1.0 - t / WINDUP
		sx = 1.0 + 0.25 * k
		sy = 1.0 - 0.2 * k
		glow = k
	elif state == S.LUNGE:
		sx = 0.85
		sy = 1.2
		glow = 1.0
	draw_set_transform(Vector2.ZERO, facing.angle(), Vector2(sy, sx))
	if glow > 0.0:
		draw_circle(Vector2.ZERO, radius + 8.0 * glow, Color(C.TELE_MELEE, 0.22 * glow))
	var body := flash_color(Color(0.38, 0.28, 0.23))
	draw_circle(Vector2.ZERO, radius, body)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 20, flash_color(Color(0.62, 0.46, 0.36)), 2.0)
	# Mouth crack on the facing side
	var mouth := Color(0.85, 0.4, 0.12).lerp(Color(1.0, 0.85, 0.4), glow)
	draw_arc(Vector2(radius * 0.35, 0), radius * 0.55, -0.9, 0.9, 8, flash_color(mouth), 2.5 + 2.0 * glow)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rivets(radius)
	draw_status(radius)
