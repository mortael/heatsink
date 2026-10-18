class_name Linesman
extends Enemy
## Pattern-disrupter (GDD section 7, profile 2). Harmless alone: it tethers another enemy with a beam.
## Tether: 0.7 s dotted violet line to the nearest other enemy within 8 tiles and in sight, then a solid cyan beam
## for 3 s that costs 1 pip on contact. Recast every 5 s. The beam drops the moment either end dies.
## The live beam is drawn like a lightsaber: it ignites from the Linesman outward in IGNITE s, hums,
## and lights the floor around it. Only the part that has ignited can hit.
## Snap Back: when the player comes within 3 tiles, a 0.4 s crouch with a rising chirp, then a 4-tile hop.

enum S { DRIFT, CROUCH, HOP }
enum T { IDLE, AIM, BEAM }

const SPEED := 2.2 * C.TILE
const KEEP_MIN := 6.0 * C.TILE
const KEEP_MAX := 9.0 * C.TILE
const TETHER_RANGE := 8.0 * C.TILE
const TETHER_AIM := 0.7
const TETHER_BEAM := 3.0
const TETHER_EVERY := 5.0
const SNAP_RANGE := 3.0 * C.TILE
const CROUCH := 0.4
const HOP_DIST := 4.0 * C.TILE
const HOP_TIME := 0.25
const HOP_COOLDOWN := 1.5
const BEAM_SOURCE := "Linesman · Tether beam"
const IGNITE := 0.1

var state: int = S.DRIFT
var t := 0.0
var tether: int = T.IDLE
var tether_t := 1.5 # first cast comes quickly so the room teaches the beam early
var partner: Enemy = null
var beam_hit := false
var hop_dir := Vector2.ZERO
var hop_cd := 0.0
var spot := Vector2.ZERO
var spot_t := 0.0
var bob := randf() * TAU
var _beam_fx: Node2D # additive layer under the body
var _beam_light: PointLight2D


func _ready() -> void:
	super._ready()
	_beam_fx = Node2D.new()
	_beam_fx.material = Glow.additive()
	_beam_fx.show_behind_parent = true
	_beam_fx.draw.connect(_draw_beam)
	add_child(_beam_fx)
	_beam_light = PointLight2D.new()
	_beam_light.texture = Glow.light()
	_beam_light.color = C.TELE_LINE
	_beam_light.blend_mode = Light2D.BLEND_MODE_ADD
	_beam_light.enabled = false
	add_child(_beam_light)
	add_to_group("dynamic_lights")


func _init() -> void:
	max_hp = 60.0
	radius = 14.0
	tp = 4
	source_name = "Linesman · Snap Back"


func _ai(delta: float) -> void:
	bob += delta * 3.0
	hop_cd -= delta
	_tick_tether(delta)
	_update_beam_light()
	_beam_fx.queue_redraw()
	var p: Player = game.player
	var to_p := p.global_position - global_position
	match state:
		S.DRIFT:
			spot_t -= delta
			if spot_t <= 0.0 or global_position.distance_to(spot) < 10.0:
				spot_t = 1.2
				spot = _pick_spot()
			var want := nav_dir(spot, delta) * SPEED if global_position.distance_to(spot) > 12.0 else Vector2.ZERO
			want += _separation().limit_length(1.0) * SPEED * 0.6
			velocity = velocity.lerp(want.limit_length(SPEED), 0.12)
			if to_p.length() < SNAP_RANGE and hop_cd <= 0.0 and not game.dead:
				state = S.CROUCH
				t = CROUCH
				Sfx.play("chirp", 0.0, -8.0)
		S.CROUCH:
			t -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
			if t <= 0.0:
				hop_dir = _hop_dir()
				state = S.HOP
				t = HOP_TIME
		S.HOP:
			t -= delta
			velocity = hop_dir * (HOP_DIST / HOP_TIME)
			if t <= 0.0:
				velocity = Vector2.ZERO
				state = S.DRIFT
				hop_cd = HOP_COOLDOWN
				spot_t = 0.0


## A spot 6-9 tiles from the player, preferring one that puts the nearest Clinker pack between us
## so the beam cuts across the player's lane; otherwise the open spot nearest to where we are.
func _pick_spot() -> Vector2:
	var p: Vector2 = game.player.global_position
	var room: Room = game.room
	var pack := _pack_centre()
	var best := global_position
	var best_score := INF
	for i in 12:
		var ang := i * TAU / 12.0
		var cand := p + Vector2.from_angle(ang) * randf_range(KEEP_MIN, KEEP_MAX)
		if not room.is_open(cand, radius + 6.0):
			continue
		var score := cand.distance_to(global_position)
		if pack != Vector2.INF:
			# Beam from cand to the pack should pass close to the player.
			var c := Geometry2D.get_closest_point_to_segment(p, cand, pack)
			score += c.distance_to(p) * 1.5
		if score < best_score:
			best_score = score
			best = cand
	return best


func _pack_centre() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for o in get_tree().get_nodes_in_group("enemies"):
		if o is Clinker:
			sum += o.global_position
			n += 1
	return sum / n if n > 0 else Vector2.INF


func _hop_dir() -> Vector2:
	var away: Vector2 = (global_position - game.player.global_position).normalized()
	if away == Vector2.ZERO:
		away = Vector2.UP
	var room: Room = game.room
	for a in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var d := away.rotated(a)
		if room.is_open(global_position + d * HOP_DIST, radius + 4.0) and room.has_los(global_position, global_position + d * HOP_DIST, radius):
			return d
	return away


func _tick_tether(delta: float) -> void:
	if tether != T.IDLE and (partner == null or not is_instance_valid(partner) or partner.dead):
		_drop_tether()
	match tether:
		T.IDLE:
			tether_t -= delta
			if tether_t <= 0.0:
				partner = _find_partner()
				if partner == null:
					tether_t = 0.5
				else:
					tether = T.AIM
					tether_t = TETHER_AIM
					Sfx.play("beam", -5.0, -16.0)
		T.AIM:
			tether_t -= delta
			if tether_t <= 0.0:
				tether = T.BEAM
				tether_t = TETHER_BEAM
				beam_hit = false
				Sfx.play("beam", 0.0, -8.0)
		T.BEAM:
			tether_t -= delta
			var p: Player = game.player
			var tip := global_position.lerp(partner.global_position, beam_extent())
			var c := Geometry2D.get_closest_point_to_segment(p.global_position, global_position, tip)
			if not beam_hit and c.distance_to(p.global_position) < Player.RADIUS + 3.0 and not game.dead and not p.is_invulnerable():
				beam_hit = true # 1 pip per beam; dash i-frames pass straight through
				p.take_hit(1, BEAM_SOURCE)
			if tether_t <= 0.0:
				_drop_tether()


func _drop_tether() -> void:
	tether = T.IDLE
	tether_t = TETHER_EVERY - TETHER_AIM - TETHER_BEAM
	partner = null


func _find_partner() -> Enemy:
	var best: Enemy = null
	var bd := TETHER_RANGE
	for o in get_tree().get_nodes_in_group("enemies"):
		var e: Enemy = o
		if e == self or e.dead or e is Linesman:
			continue
		if not game.room.has_los(global_position, e.global_position):
			continue # never beam through a wall
		var d := global_position.distance_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


## 0..1: how far the beam has ignited from the Linesman toward its partner.
func beam_extent() -> float:
	return clampf((TETHER_BEAM - tether_t) / IGNITE, 0.0, 1.0) if tether == T.BEAM else 0.0


## True while the beam is live: the bot and the Forgewarden read this.
func beam_active() -> bool:
	return tether == T.BEAM and partner != null and is_instance_valid(partner)


func _die() -> void:
	_drop_tether()
	_beam_light.enabled = false
	_beam_fx.queue_redraw()
	super._die()


## The floor along the beam glows cyan: one light, stretched along the beam, no shadows.
func _update_beam_light() -> void:
	var on := Settings.lights and beam_active()
	_beam_light.enabled = on
	if not on:
		return
	var to := (partner.global_position - global_position) * beam_extent()
	_beam_light.position = to * 0.5
	_beam_light.rotation = to.angle()
	_beam_light.scale = Vector2(maxf(to.length() + 80.0, 1.0) / Glow.TEX_SIZE, 160.0 / Glow.TEX_SIZE)
	_beam_light.energy = 2.4 * _hum()


## Called when the Lights & shadows setting changes.
func apply_lights() -> void:
	_update_beam_light()


## Lightsaber hum: a fast shimmer with a little noise.
func _hum() -> float:
	return 0.88 + 0.08 * sin(Time.get_ticks_msec() / 22.0) + randf() * 0.06


func _draw_beam() -> void:
	if tether == T.IDLE or partner == null or not is_instance_valid(partner):
		return
	var to := partner.global_position - global_position
	_beam_fx.draw_set_transform(Vector2(0, -Upright.BOLT_LIFT) if Upright.on else Vector2.ZERO)
	if tether == T.AIM:
		# A faint violet charge-up along the dotted telegraph line.
		var k := 1.0 - tether_t / TETHER_AIM
		Glow.strip(_beam_fx, Vector2.ZERO, to, 10.0 + 8.0 * k, Color(C.TELE_STATE, 0.12 + 0.2 * k))
		return
	var tip := to * beam_extent()
	var hum := _hum()
	Glow.strip(_beam_fx, Vector2.ZERO, tip, 64.0 * hum, Color(C.TELE_LINE, 0.35))
	Glow.strip(_beam_fx, Vector2.ZERO, tip, 22.0 * hum, Color(C.TELE_LINE, 0.95))
	Glow.strip(_beam_fx, Vector2.ZERO, tip, 8.0, Color(0.8, 1, 1, 1))
	_beam_fx.draw_line(Vector2.ZERO, tip, Color(1, 1, 1, 0.9), 2.5)
	Glow.halo(_beam_fx, Vector2.ZERO, 30.0 * hum, Color(C.TELE_LINE, 0.8))
	Glow.halo(_beam_fx, tip, 30.0 * hum, Color(C.TELE_LINE, 0.8))


func _draw() -> void:
	# Tether first, so the body sits on top of it.
	if tether != T.IDLE and partner != null and is_instance_valid(partner):
		var to := partner.global_position - global_position
		if tether == T.AIM:
			var segs := int(to.length() / 14.0)
			for i in segs:
				if i % 2 == 0:
					draw_line(to * (float(i) / segs), to * (float(i + 1) / segs), Color(C.TELE_STATE, 0.85), 2.0)
		# The live beam is drawn by _draw_beam on the additive layer.
	if Upright.on:
		var face := velocity
		if face.length() < 20.0:
			var partnered := tether != T.IDLE and partner != null and is_instance_valid(partner)
			face = (partner.global_position if partnered else game.player.global_position) - global_position
		var pose := 1 if tether == T.BEAM else (2 if tether == T.AIM or state == S.CROUCH else 0)
		draw_figure("linesman", face, pose, -10.0 if state == S.HOP else 0.0)
		return
	var squash := 1.0
	var lift := sin(bob) * 2.0
	if state == S.CROUCH:
		var k := 1.0 - t / CROUCH
		squash = 1.0 - 0.35 * k
		draw_circle(Vector2.ZERO, radius + 6.0 * k, Color(C.TELE_STATE, 0.25 * k))
	elif state == S.HOP:
		lift = -10.0
	var body := flash_color(Color(0.3, 0.33, 0.4))
	var h := radius * 2.2 * squash
	# Tall thin surveyor body with two pylons on its back.
	draw_rect(Rect2(-radius * 0.55, -h * 0.5 + lift, radius * 1.1, h), body)
	draw_rect(Rect2(-radius * 0.55, -h * 0.5 + lift, radius * 1.1, h), flash_color(Color(0.55, 0.6, 0.7)), false, 2.0)
	for sx in [-1.0, 1.0]:
		var base := Vector2(sx * radius * 0.75, -h * 0.5 + lift + 4.0)
		draw_line(base, base + Vector2(0, -12.0 * squash), Color(0.6, 0.65, 0.75), 3.0)
		var lit := tether != T.IDLE
		draw_circle(base + Vector2(0, -13.0 * squash), 3.0, C.TELE_LINE if lit else Color(0.35, 0.4, 0.5))
	draw_circle(Vector2(0, -h * 0.18 + lift), 4.0, Color(0.6, 0.9, 1.0))
	draw_rivets(radius)
	draw_status(radius)
