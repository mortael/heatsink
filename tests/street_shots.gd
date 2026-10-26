extends Node
## Staged screenshots of each hand-made Rainside layout and of a few generated ones: a fight with bolts in the air and the doors open,
## and the player standing behind a tall prop so its crown fades out.
## Needs a real renderer, not --headless:
## xvfb-run godot --rendering-driver opengl3 --path . --fixed-fps 60 res://tests/street_shots.tscn -- <shot_dir>

var shot_dir := "user://shots"
var game: Node
var layout := -1
var stage_frame := 0
const GENERATED := 5


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		shot_dir = args[0]
	shot_dir = ProjectSettings.globalize_path(shot_dir)
	if shot_dir.is_relative_path():
		shot_dir = OS.get_environment("PWD").path_join(shot_dir)
	DirAccess.make_dir_recursive_absolute(shot_dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	seed(5)
	Settings.frame = Frames.DEFAULT
	_next_layout()


func _next_layout() -> void:
	if game != null:
		game.queue_free()
		game = null
	layout += 1
	if layout >= StreetData.TEMPLATES.size() + GENERATED:
		get_tree().quit(0)
		return
	seed(5 + layout)
	game = load("res://main.tscn").instantiate()
	game.street_layout = layout if layout < StreetData.TEMPLATES.size() else -1
	add_child(game)
	stage_frame = 0


func _process(_delta: float) -> void:
	if game == null:
		return
	stage_frame += 1
	var p: Player = game.player
	var name_: String = StreetData.TEMPLATES[layout].name if layout < StreetData.TEMPLATES.size() else "gen%d" % (layout - StreetData.TEMPLATES.size())
	match stage_frame:
		3:
			game.run.index = RunMap.FLAT_ROOMS # the next room is past the flat start
			game._build_room("combat_item")
		6:
			game.director.active = false
			for c in game.director.get_children():
				c.queue_free()
			for e in get_tree().get_nodes_in_group("enemies"):
				e.queue_free()
			game._open_doors()
			p.bot = true
			p.position = Vector2(7.5, 8.5) * C.TILE
			if not game.room.is_open(p.position, 20.0):
				p.position = Vector2(12.5, 10.5) * C.TILE
			var kinds := [Clinker, Sparkhound, Slagspitter, SlagMortar, Linesman, Forgewarden, Clinker]
			var offs := [Vector2(5, -1.5), Vector2(6.5, 0.5), Vector2(8, -2.5), Vector2(10.5, 1.0), Vector2(3, 2.0), Vector2(11, -3.0), Vector2(2.5, -2.0)]
			for i in kinds.size():
				var off: Vector2 = offs[i]
				var at: Vector2 = game.room.random_open_point() if not game.room.is_open(p.position + off * C.TILE, 30.0) else p.position + off * C.TILE
				var e: Enemy = kinds[i].new()
				e.game = game
				e.max_hp = 4000.0
				e.position = at
				game.world.add_child(e)
		8:
			for e in get_tree().get_nodes_in_group("enemies"):
				e.set_physics_process(false)
			p.bot_aim = Vector2(1, -0.2).normalized()
			p.bot_fire = true
			p.heat.value = 40.0
		50:
			_shot(name_ + "_fight")
			_zoom(name_ + "_zoom", Rect2(p.global_position + Vector2(-3, -4) * C.TILE, Vector2(15, 7) * C.TILE))
			p.bot_fire = false
		70:
			p.position = _behind_prop()
			for e in get_tree().get_nodes_in_group("enemies"):
				e.queue_free()
		90:
			_shot(name_ + "_behind")
		95:
			_next_layout()


## A floor tile right above an interior prop, so its crown or roof covers the player.
func _behind_prop() -> Vector2:
	var r: Room = game.room
	for y in range(6, C.ROOM_H - 1):
		for x in range(2, C.ROOM_W - 2):
			if r.solid[y][x] and not r.solid[y - 1][x] and not r.solid[y + 1][x]:
				return (Vector2(x, y - 1) + Vector2(0.5, 0.6)) * C.TILE
	return r.center()


func _shot(name_: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [shot_dir, name_])


## A close-up of a world rectangle, doubled, to judge the figures.
func _zoom(name_: String, area: Rect2) -> void:
	var img := get_viewport().get_texture().get_image()
	var xf := get_viewport().get_canvas_transform()
	var r := Rect2i(Rect2(xf * area.position, xf.basis_xform(area.size))).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img = img.get_region(r)
	img.resize(r.size.x * 2, r.size.y * 2, Image.INTERPOLATE_LANCZOS)
	img.save_png("%s/%s.png" % [shot_dir, name_])
