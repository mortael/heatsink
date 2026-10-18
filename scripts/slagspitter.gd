class_name Slagspitter
extends Enemy
## Zoner (GDD section 7 roles, 3 TP). A squat crucible on legs that keeps its distance and fills lanes.
## One attack: Slag Fan. 0.6 s of cyan dotted lines show the five lanes (they stop tracking 0.2 s
## before the shot), then five slow slag bolts fly along them. Every 2.8 s.
## It shuffles to a new spot 5-8 tiles away between volleys. From SEARING it leads its aim.

enum S { MOVE, AIM, RECOIL }

const SPEED := 1.4 * C.TILE
const KEEP_MIN := 5.0 * C.TILE
const KEEP_MAX := 8.0 * C.TILE
const AIM := 0.6
const AIM_LOCK := 0.2
const RECOIL := 0.35
const EVERY := 2.8
const BOLTS := 5
const SPREAD := deg_to_rad(16.0) # between neighbouring lanes
const BOLT_SPEED := 4.5 * C.TILE
const LANE_LEN := 5.0 * C.TILE

var state: int = S.MOVE
var t := 0.0
var cd := 1.6
var aim := Vector2.RIGHT
var spot := Vector2.ZERO
var spot_t := 0.0
var bob := randf() * TAU
var lead_aim := false # set from the difficulty


func _init() -> void:
	max_hp = 40.0
	radius = 15.0
	tp = 3
	source_name = "Slagspitter · Slag bolt"


func _ready() -> void:
	super._ready()
	lead_aim = Difficulty.value("lead_aim")


func _ai(delta: float) -> void:
	bob += delta * 4.0
	var p: Player = game.player
	var to_p := p.global_position - global_position
	match state:
		S.MOVE:
			cd -= delta
			spot_t -= delta
			if spot_t <= 0.0 or global_position.distance_to(spot) < 10.0:
				spot_t = 1.5
				spot = _pick_spot()
			var want := nav_dir(spot, delta) * SPEED if global_position.distance_to(spot) > 12.0 else Vector2.ZERO
			want += _separation().limit_length(1.0) * SPEED * 0.6
			velocity = velocity.lerp(want.limit_length(SPEED), 0.12)
			if to_p.length() > 1.0:
				aim = to_p.normalized()
			if cd <= 0.0 and not game.dead and game.room.has_los(global_position, p.global_position, 4.0):
				state = S.AIM
				t = AIM
				Sfx.play("beam", 6.0, -16.0)
		S.AIM:
			t -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			if t > AIM_LOCK and to_p.length() > 1.0:
				aim = to_p.normalized()
				if lead_aim:
					# Aim where the player will be when the middle bolt arrives.
					var ahead := p.global_position + p.velocity * (to_p.length() / BOLT_SPEED) * 0.7
					aim = (ahead - global_position).normalized()
			if t <= 0.0:
				_fire()
				state = S.RECOIL
				t = RECOIL
		S.RECOIL:
			t -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			if t <= 0.0:
				state = S.MOVE
				cd = EVERY - AIM - RECOIL


func lanes() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in BOLTS:
		out.append(aim.rotated((i - (BOLTS - 1) * 0.5) * SPREAD))
	return out


func _fire() -> void:
	Sfx.play("shot", -6.0, -8.0)
	Juice.add_trauma(0.05)
	for d in lanes():
		var b := SlagBolt.new()
		b.game = game
		b.vel = d * BOLT_SPEED
		b.position = global_position + d * (radius + 4.0)
		game.world.add_child(b)
	knock -= aim * 120.0


func _pick_spot() -> Vector2:
	var p: Vector2 = game.player.global_position
	var room: Room = game.room
	var best := global_position
	var best_score := INF
	for i in 10:
		var cand := p + Vector2.from_angle(randf() * TAU) * randf_range(KEEP_MIN, KEEP_MAX)
		if not room.is_open(cand, radius + 6.0) or not room.has_los(cand, p, 4.0):
			continue
		var score := cand.distance_to(global_position)
		if score < best_score:
			best_score = score
			best = cand
	return best


func _draw() -> void:
	if state == S.AIM:
		var k := 1.0 - t / AIM
		var a := 0.4 + 0.5 * k if t > AIM_LOCK else 0.95
		for d in lanes():
			var segs := 9
			for i in segs:
				if i % 2 == 0:
					draw_line(d * (radius + LANE_LEN * i / segs), d * (radius + LANE_LEN * (i + 1) / segs), Color(C.TELE_LINE, a), 2.0)
	var lift := sin(bob) * 1.5
	var squash := 1.0
	if state == S.AIM:
		squash = 1.0 - 0.15 * (1.0 - t / AIM)
	elif state == S.RECOIL:
		squash = 1.15
	Upright.body(self, radius, radius * 0.8, Color(0.34, 0.3, 0.3), 3)
	# Three stubby legs under a round crucible with a glowing spout toward the player.
	for i in 3:
		var a2 := TAU * i / 3.0 + 0.5
		draw_line(Vector2.ZERO, Vector2.from_angle(a2) * (radius + 6.0), Color(0.45, 0.4, 0.36), 3.0)
	var body := flash_color(Color(0.34, 0.3, 0.3))
	Upright.xf(self, Vector2(0, lift), 0.0, Vector2(1.0, squash))
	draw_circle(Vector2.ZERO, radius, body)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 20, flash_color(Color(0.6, 0.5, 0.45)), 2.0)
	draw_circle(Vector2.ZERO, radius * 0.5, Color(1.0, 0.5, 0.15, 0.8 if state == S.AIM else 0.5))
	Upright.xf(self)
	var spout := aim * (radius + 5.0)
	draw_line(aim * radius * 0.5, spout, flash_color(Color(0.55, 0.5, 0.46)), 7.0)
	draw_circle(spout, 3.5, C.TELE_LINE if state == S.AIM else Color(1, 0.55, 0.2))
	draw_rivets(radius)
	draw_status(radius)
