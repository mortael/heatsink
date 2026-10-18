class_name SlagMortar
extends Enemy
## Artillery (GDD section 7 roles, 3 TP). A slow tracked kiln with a stubby barrel.
## One attack: Shell. It lobs a slag shell at where you stand; a red ring on the floor marks the
## landing spot for the whole 1.1 s flight and fills in as it falls. 1 pip if you are inside on impact.
## Every 3.2 s. It backs away to 6-10 tiles when you close in.

const SPEED := 1.1 * C.TILE
const KEEP_MIN := 6.0 * C.TILE
const KEEP_MAX := 10.0 * C.TILE
const EVERY := 3.2
const RECOIL := 0.3

var cd := 2.0
var recoil := 0.0
var aim := Vector2.RIGHT
var spot := Vector2.ZERO
var spot_t := 0.0


func _init() -> void:
	max_hp = 45.0
	radius = 16.0
	tp = 3
	source_name = "Slag Mortar · Shell"


func _ai(delta: float) -> void:
	cd -= delta
	recoil = maxf(0.0, recoil - delta)
	var p: Player = game.player
	var to_p := p.global_position - global_position
	if to_p.length() > 1.0:
		aim = aim.slerp(to_p.normalized(), minf(1.0, delta * 4.0))
	spot_t -= delta
	if spot_t <= 0.0 or global_position.distance_to(spot) < 10.0 or to_p.length() < KEEP_MIN * 0.7:
		spot_t = 2.0
		spot = _pick_spot()
	var want := nav_dir(spot, delta) * SPEED if global_position.distance_to(spot) > 12.0 else Vector2.ZERO
	want += _separation().limit_length(1.0) * SPEED * 0.6
	velocity = velocity.lerp(want.limit_length(SPEED), 0.1)
	if cd <= 0.0 and not game.dead and to_p.length() < 14.0 * C.TILE:
		cd = EVERY
		recoil = RECOIL
		var s := MortarShell.new()
		s.game = game
		s.from = global_position + aim * (radius + 8.0)
		# Aim a little ahead of a moving player, but land on open floor.
		var target := p.global_position + p.velocity * 0.35
		s.target = target if game.room.is_open(target, 4.0) else p.global_position
		game.world.add_child(s)
		Sfx.play("slam", 9.0, -12.0)
		knock -= aim * 90.0


func _pick_spot() -> Vector2:
	var p: Vector2 = game.player.global_position
	var room: Room = game.room
	var best := global_position
	var best_score := INF
	for i in 10:
		var cand := p + Vector2.from_angle(randf() * TAU) * randf_range(KEEP_MIN, KEEP_MAX)
		if not room.is_open(cand, radius + 6.0):
			continue
		var score := cand.distance_to(global_position)
		if score < best_score:
			best_score = score
			best = cand
	return best


func _draw() -> void:
	if draw_figure("slag_mortar", aim, 1 if recoil > 0.0 or cd < 0.4 else 0):
		return
	var body := flash_color(Color(0.3, 0.27, 0.25))
	# Tracks
	draw_rect(Rect2(-radius - 3, -radius, 6, radius * 2.0), Color(0.2, 0.19, 0.18))
	draw_rect(Rect2(radius - 3, -radius, 6, radius * 2.0), Color(0.2, 0.19, 0.18))
	# Kiln body
	draw_rect(Rect2(-radius + 2, -radius + 2, radius * 2.0 - 4, radius * 2.0 - 4), body)
	draw_rect(Rect2(-radius + 2, -radius + 2, radius * 2.0 - 4, radius * 2.0 - 4), flash_color(Color(0.55, 0.48, 0.42)), false, 2.0)
	# Barrel, pulled back on recoil, glowing as the next shell heats up
	var pull := 6.0 * recoil / RECOIL
	var heat := clampf(1.0 - cd / EVERY, 0.0, 1.0)
	draw_line(aim * (4.0 - pull), aim * (radius + 10.0 - pull), flash_color(Color(0.5, 0.46, 0.42)), 9.0)
	draw_circle(aim * (radius + 10.0 - pull), 4.0, Color(0.3, 0.12, 0.05).lerp(C.TELE_GROUND, heat))
	draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.45, 0.12, 0.4 + 0.5 * heat))
	draw_rivets(radius)
	draw_status(radius)


## The shell in flight and its landing marker. Lives in the world, so it still lands if the mortar dies.
class MortarShell:
	extends Node2D

	const FLIGHT := 1.1
	const RADIUS := 1.3 * C.TILE
	const SOURCE := "Slag Mortar · Shell"

	var game: Node
	var from := Vector2.ZERO
	var target := Vector2.ZERO
	var t := 0.0

	func _ready() -> void:
		z_index = 1
		add_to_group("mortar_shells")

	## 0..1 of the flight done.
	func progress() -> float:
		return t / FLIGHT

	func _physics_process(delta: float) -> void:
		if game.dead:
			return
		t += delta
		if t >= FLIGHT:
			var p: Player = game.player
			if p.global_position.distance_to(target) < RADIUS + Player.RADIUS * 0.5 and not p.is_invulnerable():
				p.take_hit(1, SOURCE)
			game.fx.explosion(target, RADIUS, Color(1.0, 0.45, 0.15), 0.6)
			Sfx.play("slam", 4.0, -10.0)
			Juice.add_trauma(0.08)
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := progress()
		var c := target - global_position
		# Red landing ring, filling in as the shell falls (GDD: red = area on the ground).
		draw_arc(c, RADIUS, 0, TAU, 32, Color(C.TELE_GROUND, 0.85), 2.5)
		draw_circle(c, RADIUS * k, Color(C.TELE_GROUND, 0.18 + 0.12 * k))
		# The shell itself, on an arc from barrel to target.
		var pos := from.lerp(target, k) - global_position + Vector2(0, -sin(k * PI) * 3.0 * C.TILE)
		draw_circle(pos, 6.0 + 3.0 * sin(k * PI), Color(1.0, 0.55, 0.2))
		draw_circle(pos, 3.0, Color(1, 0.9, 0.6))
