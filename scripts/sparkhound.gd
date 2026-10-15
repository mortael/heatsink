class_name Sparkhound
extends Enemy
## Chaser (GDD section 7 roles, 2 TP). A low, fast scrap hound that runs you down.
## One attack: Spark Rush. It plants its feet for 0.55 s while an orange arrow shows the lane,
## stops turning 0.2 s before it goes, then charges 6 tiles in a straight line. 1 pip on contact.
## A missed charge skids it to a stop for 0.9 s: the moment to punish it.

enum S { CHASE, AIM, RUSH, SKID }

const SPEED := 3.4 * C.TILE
const RUSH_RANGE := 5.5 * C.TILE
const AIM := 0.55
const AIM_LOCK := 0.2
const RUSH_DIST := 6.0 * C.TILE
const RUSH_TIME := 0.38
const SKID := 0.9
const COOLDOWN := 1.6
const SOURCE := "Sparkhound · Spark Rush"

var state: int = S.CHASE
var t := 0.0
var cd := 1.0
var facing := Vector2.RIGHT
var bit := false
var gait := randf() * TAU


func _init() -> void:
	max_hp = 22.0
	radius = 11.0
	tp = 2
	source_name = SOURCE


func _ai(delta: float) -> void:
	gait += delta * 14.0
	cd -= delta
	var p: Player = game.player
	var to_p := p.global_position - global_position
	match state:
		S.CHASE:
			if to_p.length() > 1.0:
				facing = nav_dir(p.global_position, delta)
			var desired := (facing * SPEED + _separation().limit_length(1.0) * SPEED).limit_length(SPEED)
			velocity = velocity.lerp(desired, 0.2)
			if cd <= 0.0 and to_p.length() < RUSH_RANGE and not game.dead and game.room.has_los(global_position, p.global_position, radius):
				state = S.AIM
				t = AIM
				Sfx.play("windup", 5.0, -12.0)
		S.AIM:
			t -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
			if t > AIM_LOCK and to_p.length() > 1.0:
				facing = to_p.normalized()
			if t <= 0.0:
				state = S.RUSH
				t = RUSH_TIME
				bit = false
				Sfx.play("dash", 3.0, -10.0)
		S.RUSH:
			t -= delta
			velocity = facing * (RUSH_DIST / RUSH_TIME)
			if randf() < 0.6:
				game.fx.sparks(global_position - facing * radius, -facing, 1, C.TELE_MELEE)
			if not bit and to_p.length() < radius + Player.RADIUS + 4.0:
				bit = true
				p.take_hit(1, SOURCE)
			if t <= 0.0 or (get_slide_collision_count() > 0 and t < RUSH_TIME - 0.05):
				state = S.SKID
				t = SKID
		S.SKID:
			t -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 2200.0 * delta)
			if t <= 0.0:
				state = S.CHASE
				cd = COOLDOWN


## The lane the rush will take, for the bot and for drawing.
func rush_lane() -> Vector2:
	return facing * RUSH_DIST


func _draw() -> void:
	if state == S.AIM:
		# Orange arrow along the lane: grows in, locks (solid) for the last AIM_LOCK seconds.
		var k := 1.0 - t / AIM
		var tip := facing * RUSH_DIST * minf(1.0, k * 1.6)
		var a := 0.35 + 0.45 * k if t > AIM_LOCK else 0.9
		draw_line(Vector2.ZERO, tip, Color(C.TELE_MELEE, a * 0.35), radius * 2.0)
		draw_line(Vector2.ZERO, tip, Color(C.TELE_MELEE, a), 2.0)
		var side := facing.orthogonal() * 8.0
		draw_colored_polygon(PackedVector2Array([tip + facing * 12.0, tip + side, tip - side]), Color(C.TELE_MELEE, a))
	var stretch := 1.0
	if state == S.RUSH:
		stretch = 1.45
	elif state == S.AIM:
		stretch = 0.8
	draw_set_transform(Vector2.ZERO, facing.angle(), Vector2(stretch, 1.0 / sqrt(stretch)))
	var body := flash_color(Color(0.3, 0.24, 0.2))
	# Long low body, a wedge head and four flicking legs.
	var step := sin(gait) * 4.0 if state == S.CHASE else 0.0
	for leg in [Vector2(5, 1), Vector2(-5, -1)]:
		draw_line(Vector2(leg.x, -radius * 0.6), Vector2(leg.x + step * leg.y, -radius - 3.0), Color(0.5, 0.42, 0.35), 2.0)
		draw_line(Vector2(leg.x, radius * 0.6), Vector2(leg.x - step * leg.y, radius + 3.0), Color(0.5, 0.42, 0.35), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(radius + 6, 0), Vector2(radius * 0.2, -radius * 0.8), Vector2(-radius, -radius * 0.55), Vector2(-radius - 4, 0), Vector2(-radius, radius * 0.55), Vector2(radius * 0.2, radius * 0.8)]), body)
	var eye := C.TELE_MELEE if state == S.AIM or state == S.RUSH else Color(0.95, 0.5, 0.2)
	draw_circle(Vector2(radius * 0.55, 0), 2.5, flash_color(eye))
	# Spark tail
	draw_line(Vector2(-radius - 4, 0), Vector2(-radius - 12, sin(gait * 0.5) * 3.0), Color(1, 0.75, 0.3, 0.8), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rivets(radius)
	draw_status(radius)
