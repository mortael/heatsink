extends Node
## Regression test: standing flush against a pillar and firing into it must never put a bolt
## behind the pillar (the muzzle pokes past the player's body into the wall).
## The same goes for every Frame: Furnace shockwaves and the Arclight's beam must stop on the pillar too.
## Run: godot --headless --path . --fixed-fps 60 res://tests/muzzle_test.tscn [-- frame=furnace|arclight]

const PILLAR := 48.0 # one tile, the thinnest pillar a room can have
const AIMS := [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP, Vector2(1, 1), Vector2(1, -0.4)]

var game: Node
var pillar: StaticBody2D
var rect: Rect2
var case := -1
var frames := 0
var failures := 0
var frame := Frames.DEFAULT


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("frame="):
			frame = Frames.clamp_id(a.substr(6))
	Settings.frame = frame
	game = load("res://main.tscn").instantiate()
	add_child(game)


func _physics_process(_delta: float) -> void:
	frames += 1
	if case == -1:
		if frames < 10:
			return
		_setup()
		_next()
		return
	for b in get_tree().get_nodes_in_group("bolts"):
		if not (b as Node2D).is_queued_for_deletion() and rect.has_point((b as Node2D).global_position) == false \
				and _behind((b as Node2D).global_position):
			push_error("aim %s: bolt got behind the pillar at %s" % [AIMS[case], (b as Node2D).global_position])
			failures += 1
			b.queue_free()
	_check_frame_weapon()
	if frames >= (20 if frame == "riveter" else 30):
		_next()


func _setup() -> void:
	var p: Player = game.player
	p.bot = true
	game.director.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	var c: Vector2 = game.room.center()
	rect = Rect2(c - Vector2(PILLAR, PILLAR) * 0.5, Vector2(PILLAR, PILLAR))
	pillar = StaticBody2D.new()
	pillar.collision_layer = C.LAYER_WALL
	var sh := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	sh.shape = box
	pillar.add_child(sh)
	pillar.global_position = rect.get_center()
	game.world.add_child(pillar)


## Shockwaves (Furnace) and beam ends (Arclight) that got past the pillar's centre went through it.
func _check_frame_weapon() -> void:
	var p: Player = game.player
	var aim: Vector2 = AIMS[case].normalized()
	var pts: Array[Vector2] = []
	for n in game.world.get_children():
		if n is Shockwave and not n.is_queued_for_deletion():
			pts.append(n.global_position)
	if p.lance != null:
		for b: Array in p.lance.beams:
			pts.append(p.global_position + (b[0] as Vector2))
	for pt in pts:
		if (pt - p.global_position).dot(aim) > (rect.get_center() - p.global_position).dot(aim):
			push_error("%s aim %s: attack got past the pillar at %s" % [frame, AIMS[case], pt])
			failures += 1
			for n in game.world.get_children():
				if n is Shockwave:
					n.queue_free()
			return


## A point on the far side of the pillar from the player, i.e. the bolt went through it.
func _behind(pos: Vector2) -> bool:
	var aim: Vector2 = AIMS[case].normalized()
	var start: Vector2 = game.player.global_position
	return (pos - start).dot(aim) > (rect.get_center() - start).dot(aim) and rect.grow(PILLAR).has_point(pos)


func _next() -> void:
	for b in get_tree().get_nodes_in_group("bolts"):
		b.queue_free()
	for n in game.world.get_children():
		if n is Shockwave:
			n.queue_free()
	case += 1
	frames = 0
	if case >= AIMS.size():
		print("muzzle test (%s): %d failures" % [frame, failures])
		get_tree().quit(1 if failures > 0 else 0)
		return
	var aim: Vector2 = AIMS[case].normalized()
	var p: Player = game.player
	p.bot_aim = aim
	p.aim_dir = aim
	# Flush against the face (or corner) the aim points into.
	var c := rect.get_center()
	var edge := Vector2(signf(aim.x), signf(aim.y)) * PILLAR * 0.5
	var flush := c - edge - Vector2(signf(aim.x), signf(aim.y)) * (Player.RADIUS + 0.5)
	if aim.x != 0.0 and aim.y != 0.0 and absf(aim.x) != absf(aim.y):
		flush = c - Vector2(edge.x, 0) - Vector2(signf(aim.x) * (Player.RADIUS + 0.5), 0)
	p.global_position = flush
	p.velocity = Vector2.ZERO
	if frame == "riveter":
		p._fire()
		return
	# The Furnace needs Overdrive for shockwaves; the Arclight stays Cold so a single beam aims straight in.
	p.bot_fire = true
	p.heat.set_value(85.0 if frame == "furnace" else 0.0)
	if p.maul != null:
		p.maul.cd = 0.0
