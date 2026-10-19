class_name CodexPanel
extends PanelContainer
## The Codex: how to play, explained page by page. Opened from the main menu and the pause menu.
## Items, Fusions, Resonance and room types are read from ItemDB and RunMap, so new content shows up here
## by itself. Mouse wheel, touch drag, arrows / d-pad or the right stick scroll; Left / Right, LB / RB or
## the tabs switch pages; Esc / B / BACK closes it.

signal back

const SCROLL_SPEED := 700.0 # pixels per second at full stick
const PAGES := ["BASICS", "FRAMES", "HEAT & VENT", "ITEMS", "ENEMIES", "THE ROUTE"]

var tabs: Array[Button] = []
var page := 0
var scroll: ScrollContainer
var text: RichTextLabel
var back_button: Button


func _init() -> void:
	custom_minimum_size = Vector2(1060, 640)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var title := Label.new()
	title.text = "CODEX"
	title.custom_minimum_size = Vector2(130, 0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiStyle.HOT)
	head.add_child(title)
	for i in PAGES.size():
		var b := UiStyle.button(PAGES[i], 0)
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 17)
		b.toggle_mode = true
		b.pressed.connect(show_page.bind(i))
		b.focus_entered.connect(show_page.bind(i)) # arrows along the tab row turn the pages
		# Up and down scroll the page instead of leaving the tab row.
		b.focus_neighbor_top = NodePath(".")
		b.focus_neighbor_bottom = NodePath(".")
		head.add_child(b)
		tabs.append(b)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.selection_enabled = false
	text.mouse_filter = Control.MOUSE_FILTER_PASS # touch drags reach the ScrollContainer
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 17)
	text.add_theme_color_override("default_color", UiStyle.TEXT)
	text.add_theme_constant_override("line_separation", 3)
	scroll.add_child(text)
	var foot := HBoxContainer.new()
	col.add_child(foot)
	back_button = UiStyle.button("BACK", 200)
	back_button.pressed.connect(close)
	foot.add_child(back_button)
	var hint := Label.new()
	hint.text = "   Left / Right or LB / RB: page   ·   Up / Down or right stick: scroll"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UiStyle.DIM)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(hint)
	back_button.focus_neighbor_top = NodePath("../../" + head.name + "/" + tabs[0].name)


func open(start_page := page) -> void:
	visible = true
	show_page(start_page)
	tabs[page].grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	back.emit()


func show_page(i: int) -> void:
	i = wrapi(i, 0, PAGES.size())
	if i == page and text.text != "":
		return
	page = i
	for j in tabs.size():
		tabs[j].set_pressed_no_signal(j == page)
	# A line break right before [/ul] would add an empty bullet.
	text.text = page_text(page).replace("\n[/ul]", "[/ul]")
	scroll.scroll_vertical = 0


func page_text(i: int) -> String:
	match i:
		0: return _basics()
		1: return _frames()
		2: return _heat()
		3: return _items()
		4: return _enemies()
		_: return _route()


func _process(delta: float) -> void:
	if not visible:
		return
	var v := Input.get_axis("ui_up", "ui_down")
	if absf(v) < 0.2:
		v = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(v) > 0.2:
		scroll.scroll_vertical += int(v * SCROLL_SPEED * delta)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
		get_viewport().set_input_as_handled()
		close()
	elif event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		get_viewport().set_input_as_handled()
		show_page(page + (1 if event.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1))
		tabs[page].grab_focus()


# --- Pages -------------------------------------------------------------------------------------

static func _h(title: String, col := UiStyle.HOT) -> String:
	return "[font_size=24][color=#%s]%s[/color][/font_size]\n" % [col.to_html(false), title]


static func _c(s: String, col: Color) -> String:
	return "[color=#%s]%s[/color]" % [col.to_html(false), s]


static func _dim(s: String) -> String:
	return "[color=#a8a39e]%s[/color]" % s


static func _basics() -> String:
	var t := _h("What is HEATSINK?")
	t += "You are a Sink: a small war machine whose weapon runs on heat. Pick a Frame (your weapon and play style), then fight through a Stratum of 12 rooms, pick up items that change how your shots, Vents and dashes work, and beat the Foundry Gate at the end. Die and the run is over: the Death Ledger shows what got you, and a new run starts from scratch.\n\n"
	t += "The core idea: attacking makes you hotter, and hotter is stronger, until it isn't. Run hot, Vent hard, don't melt.\n\n"
	t += _h("Controls")
	t += "[table=3]"
	var rows := [
		["", "Keyboard + mouse", "Gamepad"],
		["Move", "WASD / arrows", "Left stick"],
		["Aim", "Mouse", "Right stick"],
		["Fire (hold)", "Left mouse", "Right trigger"],
		["Dash", "Space / Shift", "Left bumper"],
		["Vent", "Right mouse / Q", "Left trigger"],
		["Use (shop, altar, Crucible)", "E / F", "A"],
		["Pause", "Esc / P", "Start"],
		["New run after death", "R", "Start"],
	]
	for r in rows:
		for k in r.size():
			var cell: String = r[k]
			if rows.find(r) == 0 or k == 0:
				cell = _c(cell, UiStyle.HOT)
			t += "[cell padding=0,2,28,2]%s[/cell]" % cell
	t += "[/table]\n\n"
	t += _c("Touch screens: ", UiStyle.HOT) + "the controls appear after your first touch. Drag on the left half to move, drag on the right half to aim and fire, and tap DASH, VENT or USE. The II button at the top right pauses. Tap a card to pick it.\n\n"
	t += _h("Reading the screen")
	t += "[ul]"
	t += _c("Plating", Color(0.8, 0.85, 0.9)) + " (top left): your health, 6 pips. Most hits cost 1 pip.\n"
	t += _c("Item chips", UiStyle.HOT) + " under the Plating: one per item, in its keyword colour. Active Resonance, Fusions and Slagged progress are listed below them.\n"
	t += _c("Route strip", UiStyle.HOT) + " (top centre): one cell per room, coloured by the type of room you took.\n"
	t += _c("Kills, time, Scrap and Cores", Color(1, 0.85, 0.35)) + " (top right).\n"
	t += _c("Heat gauge", C.HEAT_WARM) + " (bottom centre) with the Warm and Hot marks, your dash charges to its left and the Vent timer to its right.\n"
	t += _c("The ring around your Sink", Color(1, 0.75, 0.35)) + " shows the Vent: a dim ring fills up while it cools down, and once it glows orange (with a flash and a soft chime) you can Vent again.\n"
	t += "[/ul]\n"
	t += _dim("Settings has volume, screen shake, fullscreen, lights & shadows and an FPS counter. They are saved between sessions.")
	return t


static func _frames() -> String:
	var t := "START RUN first asks which Frame you take. Each one has its own weapon, its own Overdrive in the Hot band, its own Vent and a passive. The last Frame you played is remembered.\n\n"
	for id in Frames.ORDER:
		var f: Dictionary = Frames.info(id)
		var kw: String = f.keyword
		t += _h(f.name + "  " + _dim(f.role), f.color)
		t += f.blurb + "\n"
		t += "[ul]"
		t += _c("Weapon: ", UiStyle.HOT) + f.weapon + "\n"
		t += _c("Overdrive (Hot): ", C.HEAT_HOT) + f.overdrive + "\n"
		t += _c("Vent: ", C.HEAT_WARM) + f.vent + "\n"
		t += _c("Passive: ", UiStyle.HOT) + f.passive + "\n"
		t += _c("Plating: ", Color(0.8, 0.85, 0.9)) + "%d pips.  " % f.pips + _c("Native keyword: ", ItemDB.keyword_color(kw)) + kw.capitalize() + " (item offers lean toward it).\n"
		t += "[/ul]\n"
	t += _dim("Items work with every Frame: \"hits\" means rivets, swings, shockwaves and beam pulses alike. A few rivet-only items (Bank Shot, Rebound Charge, and Splinter Heads for the Arclight) are never offered to a Frame they can't help.")
	return t


static func _heat() -> String:
	var t := _h("The Heat gauge")
	t += "Attacking adds Heat: %d per rivet, %d per maul swing, %d per second of beam. Heat starts to cool %d s after your last attack, at %d per second. The gauge has three bands:\n" % [int(Player.HEAT_PER_SHOT), int(SlagMaul.HEAT_PER_SWING), int(CoilLance.HEAT_PER_SEC), int(Heat.DECAY_DELAY), int(Heat.DECAY_RATE)]
	t += "[ul]"
	t += _c("COLD", C.HEAT_COLD) + " (0-%d): your weapon's base form.\n" % int(Heat.WARM_AT)
	t += _c("WARM", C.HEAT_WARM) + " (%d-%d): still the base form, but some items only work from Warm up, and the Coil Lance chains one enemy further.\n" % [int(Heat.WARM_AT), int(Heat.HOT_AT)]
	t += _c("HOT", C.HEAT_HOT) + " (%d+): " % int(Heat.HOT_AT) + _c("Overdrive", C.HEAT_HOT) + ". Rivets burn gold, pierce one enemy and ricochet; the Slag Maul throws shockwaves; the Coil Lance forks into three. The screen edges glow orange.\n"
	t += "[/ul]"
	t += _dim("Some items move these lines: Feral Valve starts Overdrive at 60, and a Stoke Altar raises the cap to 120 Heat.") + "\n\n"
	t += _h("Overheat", C.HEAT_OVER)
	t += "Reach the cap (100 Heat) and you Overheat: the gun locks for %d s, you move 20%% slower and every hit costs 1 extra pip. Afterwards the gauge resets to %d. The gauge flashes red just before it happens.\n\n" % [int(Heat.OVERHEAT_TIME), int(Heat.RESET_AFTER_OVERHEAT)]
	t += _h("Vent")
	t += "Vent dumps all your Heat at once as a nova around you. The more Heat you dump, the bigger and harder it hits: the radius grows from %.1f tiles (cold) to %.1f tiles (full), and damage is 0.6 per point of Heat, times your Frame's Vent multiplier (Riveter x1.0, Furnace x1.5, Arclight x0.8).\n" % [2.5, 2.5 + 100.0 / 25.0]
	t += "[ul]"
	t += _c("Riveter: ", Frames.info("riveter").color) + "every rivet stuck in an enemy detonates for %d damage, and each one adds +%d%% Vent damage to the enemy it sits in. Shoot first, Vent second.\n" % [int(Player.RIVET_BURST_DAMAGE), int(Player.TENSION_PER_RIVET * 100.0)]
	t += _c("Furnace: ", Frames.info("furnace").color) + "Vent at %d+ Heat and a Slag Shield takes the next hit within %d s (a gold pip next to your Plating).\n" % [int(Player.SLAG_SHIELD_AT), int(Player.SLAG_SHIELD_TIME)]
	t += _c("Arclight: ", Frames.info("arclight").color) + "a Static Pylon stays behind and zaps the nearest enemy for %d every %.1f s for %d s.\n" % [int(StaticPylon.DAMAGE), StaticPylon.EVERY, int(StaticPylon.LIFE)]
	t += "You can Vent while Overheated, but only at half damage.\n"
	t += "Cooldown: %d s (Coolant Line shortens it). The ring around your Sink fills while it cools down and glows orange when it's ready.\n" % int(Player.VENT_COOLDOWN)
	t += "[/ul]\n"
	t += _h("Dash", Color(0.35, 0.9, 1.0))
	t += "You have %d dash charges; each recharges in %.1f s. A dash makes you briefly untouchable and quenches %d Heat, so it doubles as a way to stay in the Hot band without Overheating.\n\n" % [Player.DASH_MAX, Player.DASH_RECHARGE, int(Player.DASH_QUENCH)]
	t += _h("Tips")
	t += "[ul]"
	t += "Attack in bursts to ride the Hot band, dash to shave off Heat, and Vent when a crowd is stuck full of rivets.\n"
	t += "A Vent at low Heat is small. Save it for when the gauge is high, unless you need the push-back to escape.\n"
	t += "Every hit has a %d%% chance to crit.\n" % int(Player.CRIT_CHANCE * 100.0)
	t += "[/ul]"
	return t


static func _items() -> String:
	var t := _h("How items work")
	t += "After most fights you pick 1 of 3 item cards. Items come in three tiers:\n"
	t += "[ul]"
	t += _c("Conductors", ItemDB.keyword_color("conductor")) + " (Tier A): plain stat and rule changes that help every build.\n"
	t += _c("Keyword items", ItemDB.keyword_color("ignite")) + " (Tier B): each belongs to a keyword. Own 2 of one keyword and its " + _c("Resonance", UiStyle.HOT) + " turns on.\n"
	t += _c("Fusions", ItemDB.keyword_color("fusion")) + " (Tier C): own the right items and they fuse into something new, on top of what they already do.\n"
	t += _c("Slagged items", ItemDB.keyword_color("slagged")) + ": very strong, with a drawback. Finish the Absolution and the drawback goes away for good.\n"
	t += "[/ul]"
	t += "Cards tell you when a pick unlocks a Resonance or completes a Fusion. At the Anvil you can " + _c("Temper", Color(0.55, 0.95, 1.0)) + " an item (1 Core) to upgrade how it works; tempered items get a cyan mark.\n\n"

	t += _h("Resonance")
	t += "[ul]"
	for kw: String in ItemDB.RESONANCE:
		t += _c(kw.to_upper(), ItemDB.keyword_color(kw)) + ": " + ItemDB.RESONANCE[kw] + "\n"
	t += "[/ul]\n"

	# Conductors first, then every keyword in the order the items list it; Slagged items get their own section.
	var groups: Array[String] = ["conductor"]
	for id: String in ItemDB.ITEMS:
		var kw: String = ItemDB.ITEMS[id].keyword
		if kw != "slagged" and not kw in groups:
			groups.append(kw)
	for g in groups:
		t += _h("Conductors" if g == "conductor" else g.capitalize(), ItemDB.keyword_color(g))
		for id: String in ItemDB.ITEMS:
			var item: Dictionary = ItemDB.ITEMS[id]
			if item.keyword != g:
				continue
			t += _c(item.name, ItemDB.keyword_color(item.keyword)) + "  " + _dim(item.rarity) + "\n"
			t += "    " + item.desc + "\n"
			if ItemDB.TEMPER.has(id):
				t += "    " + _c("Tempered: ", Color(0.55, 0.95, 1.0)) + _dim(ItemDB.TEMPER[id]) + "\n"
		t += "\n"

	t += _h("Fusions", ItemDB.keyword_color("fusion"))
	for f: String in ItemDB.FUSIONS:
		var fu: Dictionary = ItemDB.FUSIONS[f]
		var parts: Array[String] = []
		for id: String in fu.recipe:
			parts.append(_c(ItemDB.ITEMS[id].name, ItemDB.keyword_color(ItemDB.ITEMS[id].keyword)))
		t += _c(fu.name, ItemDB.keyword_color("fusion")) + "  =  " + " + ".join(parts) + "\n"
		t += "    " + fu.desc + "\n"
	t += _dim("Forced Fusion (3 Cores at the Anvil) completes a Fusion you're one item short of.") + "\n\n"

	t += _h("Slagged items", ItemDB.keyword_color("slagged"))
	for id: String in ItemDB.ITEMS:
		var item: Dictionary = ItemDB.ITEMS[id]
		if item.keyword != "slagged":
			continue
		t += _c(item.name, ItemDB.keyword_color("slagged")) + "\n"
		t += "    " + item.desc + "\n"
		t += "    " + _c("Drawback: ", ItemDB.keyword_color("slagged")) + item.drawback + "\n"
		t += "    " + _c("Absolution: ", UiStyle.HOT) + item.absolution + "\n"
	t += "\n" + _dim("When the item pool runs dry, a Patch Kit (repair 1 pip) fills the empty card.")
	return t


static func _enemies() -> String:
	var t := "Every attack is announced before it lands, and the colour tells you what kind it is: "
	t += _c("orange", C.TELE_MELEE) + " is a melee lunge, " + _c("red", C.TELE_GROUND) + " is ground you should leave, "
	t += _c("cyan", C.TELE_LINE) + " is a line or beam, " + _c("violet", C.TELE_STATE) + " is a warning that something is about to change.\n\n"
	t += _h("Clinker", C.TELE_MELEE)
	t += "Fodder that comes in packs. Its mouth glows orange and it squashes down for %.1f s, then it lunges %d tiles. It stops tracking you just before the lunge, so dash through it or step aside. Clinkers sometimes drop Scrap.\n\n" % [Clinker.WINDUP, int(Clinker.LUNGE_DIST / C.TILE)]
	t += _h("Sparkhound", C.TELE_MELEE)
	t += "A fast, low hound (from room 2). It plants its feet while an " + _c("orange arrow", C.TELE_MELEE) + " shows its lane for %.2f s, then rushes %d tiles. Step sideways or dash; a missed rush leaves it skidding for %.1f s.\n\n" % [Sparkhound.AIM, int(Sparkhound.RUSH_DIST / C.TILE), Sparkhound.SKID]
	t += _h("Slagspitter", C.TELE_LINE)
	t += "A squat crucible on legs (from room 4) that keeps %d-%d tiles away. Five dotted " % [int(Slagspitter.KEEP_MIN / C.TILE), int(Slagspitter.KEEP_MAX / C.TILE)] + _c("cyan lanes", C.TELE_LINE) + " show for %.1f s, then five slow slag bolts fly along them. Stand between the lanes or dash through.\n\n" % Slagspitter.AIM
	t += _h("Slag Mortar", C.TELE_GROUND)
	t += "A tracked kiln (from room 5) that backs away from you. A " + _c("red ring", C.TELE_GROUND) + " on the floor marks where its shell lands and fills in during the %.1f s flight. Leave the ring.\n\n" % SlagMortar.MortarShell.FLIGHT
	t += _h("Linesman", C.TELE_LINE)
	t += "A tall drone (from room 3) that is harmless on its own and keeps %d-%d tiles away. It draws a dotted " % [int(Linesman.KEEP_MIN / C.TILE), int(Linesman.KEEP_MAX / C.TILE)]
	t += _c("violet", C.TELE_STATE) + " line to a nearby enemy, and %.1f s later the line becomes a " % Linesman.TETHER_AIM + _c("cyan beam", C.TELE_LINE)
	t += " for %d s that costs 1 pip to touch. Kill either end and the beam drops; you can also dash through it.\n" % int(Linesman.TETHER_BEAM)
	t += "Get within %d tiles and it chirps, crouches and hops away.\n\n" % int(Linesman.SNAP_RANGE / C.TILE)
	t += _h("Forgewarden (Elite)", C.TELE_GROUND)
	t += "600 HP behind %d front plates that block 75%% of damage from the front until each one has taken %d. Its back takes +50%%, and it turns slowly: circle behind it.\n" % [Forgewarden.PLATES, int(Forgewarden.PLATE_HP)]
	t += "[ul]"
	t += _c("Hammerfall", C.TELE_GROUND) + ": a red circle grows where you stand, then it leaps and slams. Walk out of the circle, then dash through the ring that rolls out to %d tiles. 2 pips.\n" % int(Forgewarden.RING_REACH / C.TILE)
	t += _c("Bellows Breath", C.TELE_GROUND) + ": its chest glows and a red cone shows for %.1f s, then flame fills the cone for %.1f s and leaves " % [Forgewarden.INHALE, Forgewarden.BREATH] + _c("Molten floor", C.HEAT_OVER) + " for %d s (1 pip to stand in). Step out to the side. 2 pips.\n" % int(MoltenPatch.LIFE)
	t += "After every attack it rests for %d s. That's the moment to Vent.\n" % int(Forgewarden.RECOVER)
	t += "[/ul]"
	t += "Forgewardens guard Elite rooms and the Foundry Gate. Beating one drops a Core.\n\n"
	t += _dim("Portals flash on the floor a moment before new enemies arrive, so you can see where the next wave comes from.")
	return t


static func _route() -> String:
	var t := _h("A Stratum")
	t += "A run is %d rooms followed by the Foundry Gate. After a fight, 2 or 3 doors open in the top wall, and each door shows what's behind it before you walk through. Combat rooms are generated, so no two runs look the same.\n\n" % RunMap.ROOMS
	t += _h("Room types")
	t += "[ul]"
	for kind: String in RunMap.KINDS:
		var k: Dictionary = RunMap.KINDS[kind]
		t += _c(k.name, k.color) + "  " + _dim(k.sub) + "\n"
	t += "[/ul]\n"
	t += _h("Rooms without enemies")
	t += "[ul]"
	t += _c("Scrapper", RunMap.KINDS.shop.color) + ": a shop with 4 items (one is always a Conductor), a 1-pip repair and a reroll that gets dearer each time. Always one of the doors by room 7.\n"
	t += _c("Cooling Vault", RunMap.KINDS.vault.color) + ": choose the Cooling Bath (repair 2 pips) or the Anvil. Sometimes a Stoke Altar waits there too: -1 max pip for a 120 Heat cap and +1 s Overheat. There is always a Vault right before the Gate.\n"
	t += _c("Crucible Wager", RunMap.KINDS.wager.color) + ": feed in an item for 50% upgrade / 35% transmute / 15% Slagged, or stake 1 max Plating pip on a 60% coin flip for a Rare pick. Always one of the doors by room 10.\n"
	t += "[/ul]"
	t += "Walk up to a pedestal to read it and press Use (E / A / USE) to buy or use it.\n\n"
	t += _h("Scrap and Cores")
	t += "[ul]"
	t += _c("Scrap", Color(1, 0.85, 0.35)) + " comes from every cleared fight and from Clinker drops. Spend it at the Scrapper.\n"
	t += _c("Cores", Color(0.55, 0.95, 1.0)) + " only come from Elites. Spend them at the Anvil: Temper an item for 1 Core, or Force a Fusion for 3.\n"
	t += "[/ul]\n"
	t += _h("Elite doors", RunMap.KINDS.elite.color)
	t += "A red double frame. Inside waits a Forgewarden with Clinkers (and sometimes a Linesman), plus a second wave. The reward is 1 Core and a pick of 3 Rare-or-better items, each with a 20% chance to be Slagged. Every Stratum offers at least two, but never as the only door, so there is always a safer way.\n\n"
	t += _h("Rainside", RunMap.KINDS.street.color)
	t += "A foundry yard at night in the rain, seen at an angle: tanks, floodlights, crates, wagons and barriers stand up out of the wet floor, and tall things hide what is behind them until you walk under them. Every yard is laid out anew. The fight and the reward are a Salvage room's. One Rainside door per Stratum, usually by room %d.\n\n" % RunMap.STREET_DUE
	t += _h("The Foundry Gate", RunMap.KINDS.gate.color)
	t += "The last fight of the Stratum: three waves, ending with a Forgewarden and a Linesman. Clear it and the Stratum is yours."
	return t
