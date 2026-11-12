class_name Room
extends Node2D
## One room of the mine. Every normal room is the same length and ends in an
## 8-inch metal door. Between levels there is a "descent" room: a sloped
## tunnel that takes Bruce down into the next (differently themed) level.
##
## Coordinates: x = 0 .. WIDTH from the room's left edge, y = 0 is the floor
## at the room's entrance, negative y goes up towards the ceiling.

signal puzzle_solved(room: Room)

const TILE := 16
const TILES := 40                  # room length in tiles (all rooms are the same)
const WIDTH := TILE * TILES        # 640px
const LAST := TILES - 8            # last tile where hazards / puzzle pieces may go
const CEIL_Y := -160               # ceiling height above the floor
const CEIL_TOP := -256             # top of the drawn rock above the ceiling
const FLOOR_BOTTOM := 96
const LOW_CLEARANCE := 18          # gap under tunnels (standing = 26, low = 12)

# Descent room shape: flat, a long slope down, flat again.
const DROP := 192
const SLOPE_START := 5 * TILE
const SLOPE_END := 35 * TILE

# --- What kind of room -------------------------------------------------------
var slot := 0                      # position in the run (x = slot * WIDTH)
var number := 0                    # room number shown on the HUD (0 = descent)
var level := 1
var kind := "normal"               # "start", "normal" or "descent"
var theme: MineTheme

# --- Generated layout ------------------------------------------------------
var is_puzzle := false
var puzzle_type := ""              # "levers", "key" or "code"
var has_wanderer := false
var wanderer_trigger_x := 0.0      # global x where the warning starts
var wanderer_passes := 1
var wanderer_from_front := false
var wanderer_state := 0            # 0 = waiting, 1 = happening, 2 = done
var visited := false

var levers_needed := 0
var levers_pulled := 0
var code := ""

var pits: Array[Vector2i] = []     # tile ranges [start, end)
var tunnels: Array[Vector2i] = []
var rubbles: Array = []            # [tile_x, width_tiles, height_px]
var platforms: Array = []          # [tile_x, width_tiles, y_px]
var rails: Array[Vector2i] = []
var signs: Array = []              # [x_px, text, width_px]
var decor: Array = []              # [prop_name, x_px, y_px]
var crawl_tiles: Array[int] = []
var lever_spots: Array[Vector2] = []
var key_spot := Vector2.ZERO
var ore_spots: Array[Vector2] = []
var lantern_tiles: Array[int] = []
var post_tiles: Array[int] = []

# --- Nodes -----------------------------------------------------------------
var door: Door
var keypad: Keypad
var lanterns: Array[Lantern] = []
var crawlspaces: Array[Crawlspace] = []
var interactables: Array[Interactable] = []
var pickups: Array[Pickup] = []

var _rng := RandomNumberGenerator.new()
var _fore: Node2D


# ===========================================================================
# Shape helpers
# ===========================================================================

## Floor height (local y) at local x. Only descent rooms slope.
func floor_y_at(x: float) -> float:
	if kind != "descent":
		return 0.0
	return clampf((x - SLOPE_START) / float(SLOPE_END - SLOPE_START), 0.0, 1.0) * DROP


## The y offset the NEXT room starts at, relative to this one.
func exit_drop() -> float:
	return DROP if kind == "descent" else 0.0


# ===========================================================================
# Generation
# ===========================================================================

func generate(p_slot: int, p_number: int, p_level: int, p_kind: String, base_y: float,
		seed_value: int, prev_was_puzzle: bool) -> void:
	slot = p_slot
	number = p_number
	level = p_level
	kind = p_kind
	theme = MineTheme.for_level(level)
	position = Vector2(slot * WIDTH, base_y)
	_rng.seed = seed_value

	# The first few tiles after each door and the area before the next door
	# stay clear so you never land on a hazard.
	var reserved: Array[Vector2i] = [Vector2i(-10, 4), Vector2i(TILES - 6, TILES + 20)]

	match kind:
		"start":
			_gen_start_room(reserved)
		"descent":
			pass
		_:
			var wanderer_chance := clampf(0.12 + 0.07 * (level - 1), 0.0, 0.6)
			var puzzle_chance := clampf(0.10 + 0.06 * (level - 1), 0.0, 0.45)
			has_wanderer = number >= 3 and _rng.randf() < wanderer_chance
			is_puzzle = number >= 4 and not prev_was_puzzle and _rng.randf() < puzzle_chance

			if has_wanderer:
				# There is ALWAYS a crawlspace where The Wanderer shows up.
				var spots: Array[int] = [10, 20, 30]
				if level >= 3:
					spots = [12, 28]
				for s in spots:
					_add_crawlspace(s + _rng.randi_range(-2, 2), reserved)
				if level >= 2 and _rng.randf() < clampf(0.15 * (level - 1), 0.0, 0.6):
					wanderer_passes = 2
				wanderer_from_front = level >= 3 and _rng.randf() < 0.3
				wanderer_trigger_x = position.x + TILE * _rng.randi_range(5, 12)
			elif _rng.randf() < 0.45:
				# Decoy crawlspaces: sometimes they're just holes.
				_add_crawlspace(_rng.randi_range(8, LAST), reserved)

			if is_puzzle:
				_gen_puzzle(reserved)
			_gen_obstacles(reserved)

	_gen_decor(reserved)


func _gen_start_room(reserved: Array[Vector2i]) -> void:
	rubbles.append([8, 1, 16])
	signs.append([7 * TILE, "SPACE / W  =  JUMP", 92])
	tunnels.append(Vector2i(15, 18))
	signs.append([14 * TILE, "CTRL / S  =  SLIDE", 92])
	pits.append(Vector2i(23, 25))
	signs.append([22 * TILE, "SHIFT  =  SPRINT", 84])
	_add_crawlspace(30, reserved)
	signs.append([30 * TILE + 8, "E  =  HIDE", 60])
	for r in [Vector2i(7, 10), Vector2i(14, 19), Vector2i(22, 26)]:
		reserved.append(r)


func _gen_puzzle(reserved: Array[Vector2i]) -> void:
	var kinds := ["levers", "key", "code"]
	puzzle_type = kinds[_rng.randi() % kinds.size()]
	match puzzle_type:
		"levers":
			var want := 2 if level < 4 else 3
			var slots: Array[int] = [9, 19, 29]
			for i in range(slots.size() - 1, 0, -1):   # seeded shuffle
				var j := _rng.randi_range(0, i)
				var tmp := slots[i]
				slots[i] = slots[j]
				slots[j] = tmp
			for i in want:
				var t := _free_spot(slots[i] + _rng.randi_range(-2, 2), 2, reserved)
				if t < 0:
					continue
				var y := 0.0
				if _rng.randf() < 0.35:
					platforms.append([t - 1, 3, -40])
					y = -40.0
				lever_spots.append(Vector2(t * TILE + 8, y))
				reserved.append(Vector2i(t - 2, t + 3))
			levers_needed = lever_spots.size()
		"key":
			var t := _free_spot(_rng.randi_range(14, LAST - 2), 4, reserved)
			if t >= 0:
				if _rng.randf() < 0.55:
					# Key up on a high ledge: two planks to climb.
					platforms.append([t - 4, 3, -34])
					platforms.append([t, 3, -68])
					key_spot = Vector2(t * TILE + 24, -80)
				else:
					key_spot = Vector2(t * TILE + 8, -12)
				reserved.append(Vector2i(t - 5, t + 4))
			else:
				puzzle_type = ""
		"code":
			for i in 4:
				code += str(_rng.randi_range(0, 9))
			var a := _free_spot(_rng.randi_range(7, 14), 2, reserved)
			var b := _free_spot(_rng.randi_range(21, LAST), 2, reserved)
			if a < 0 or b < 0:
				puzzle_type = ""
				code = ""
			else:
				signs.append([a * TILE + 8, "CODE  " + code.substr(0, 2) + "??", 0])
				signs.append([b * TILE + 8, "CODE  ??" + code.substr(2, 2), 0])
				reserved.append(Vector2i(a - 2, a + 3))
				reserved.append(Vector2i(b - 2, b + 3))
	if puzzle_type == "" or (puzzle_type == "levers" and levers_needed == 0):
		is_puzzle = false
		puzzle_type = ""


func _gen_obstacles(reserved: Array[Vector2i]) -> void:
	var x := 6 + _rng.randi_range(0, 2)
	var guard := 0
	while x < LAST and guard < 80:
		guard += 1
		var roll := _rng.randf()
		var what := "rubble"
		if roll < 0.33:
			what = "rubble"
		elif roll < 0.60:
			what = "tunnel"
		elif roll < 0.85:
			what = "pit"
		else:
			what = "platform"
		var w := 1
		match what:
			"rubble":
				w = _rng.randi_range(1, 2)
			"tunnel":
				w = _rng.randi_range(2, 3 + mini(level, 3))
			"pit":
				w = _rng.randi_range(2, mini(1 + level, 4))
			"platform":
				w = _rng.randi_range(2, 3)
		if x + w > LAST + 1:
			break
		if _overlaps(x - 1, x + w + 1, reserved):
			x += 1
			continue
		match what:
			"rubble":
				rubbles.append([x, w, 16 if _rng.randf() < 0.6 else 24])
			"tunnel":
				tunnels.append(Vector2i(x, x + w))
			"pit":
				pits.append(Vector2i(x, x + w))
			"platform":
				var py := -36 - _rng.randi_range(0, 1) * 8
				platforms.append([x, w, py])
				if _rng.randf() < 0.65:
					ore_spots.append(Vector2(x * TILE + w * 8, py - 9))
		reserved.append(Vector2i(x - 1, x + w + 1))
		# Leave enough room to land after a jump before the next hazard.
		x += w + _rng.randi_range(5, maxi(6, 9 - level))


func _gen_decor(reserved: Array[Vector2i]) -> void:
	# Lanterns roughly every 10 tiles, never inside a tunnel's rock.
	for base in range(4, TILES, 10):
		var t: int = int(base) + _rng.randi_range(-1, 1)
		if not _in_ranges(t, tunnels):
			lantern_tiles.append(t)
	# Timber support sets (two posts and a cap beam).
	for t in range(1, TILES - 4, 10):
		if not _overlaps(t, t + 4, pits):
			post_tiles.append(t)
	if kind == "descent":
		return
	# Rails along the floor (in themes that have them).
	if theme.props.has("rail"):
		var x := 1
		while x < TILES - 4:
			var len := _rng.randi_range(5, 12)
			if _rng.randf() < 0.45 and not _overlaps(x, x + len, pits):
				rails.append(Vector2i(x, x + len))
			x += len + _rng.randi_range(2, 6)
	# Floor props, kept clear of hazards and crawlspaces.
	var free_ranges: Array[Vector2i] = reserved.duplicate()
	for t in tunnels:
		free_ranges.append(t)
	for i in _rng.randi_range(1, 3):
		var prop: String = theme.props[_rng.randi() % theme.props.size()]
		var t := _rng.randi_range(4, TILES - 6)
		if _overlaps(t - 1, t + 3, free_ranges) or _overlaps(t - 1, t + 3, pits):
			continue
		free_ranges.append(Vector2i(t - 1, t + 3))
		if prop == "ore":
			decor.append(["ore", t * TILE, -_rng.randi_range(50, 130)])
		elif prop == "claws":
			decor.append(["claws", t * TILE, -_rng.randi_range(60, 110)])
		elif prop != "rail":
			decor.append([prop, t * TILE, 0])
	# A couple of ore veins in the walls of every theme.
	for i in _rng.randi_range(1, 2):
		decor.append(["ore", _rng.randi_range(2, TILES - 4) * TILE, -_rng.randi_range(55, 135)])
	# A little loose ore on the floor now and then.
	if number > 1 and _rng.randf() < 0.25:
		var t := _rng.randi_range(6, LAST)
		if not _in_ranges(t, pits) and not _in_ranges(t, tunnels):
			ore_spots.append(Vector2(t * TILE + 8, -8))


func _add_crawlspace(tile: int, reserved: Array[Vector2i]) -> void:
	var t := _free_spot(clampi(tile, 5, LAST), 3, reserved)
	if t < 0:
		return
	crawl_tiles.append(t)
	reserved.append(Vector2i(t - 3, t + 4))


## Finds a tile near `tile` whose [t - half, t + half] range is free.
func _free_spot(tile: int, half: int, reserved: Array[Vector2i]) -> int:
	for off in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 8, -8]:
		var t: int = tile + off
		if t < 5 or t > LAST:
			continue
		if not _overlaps(t - half, t + half + 1, reserved):
			return t
	return -1


func _overlaps(a: int, b: int, ranges: Array[Vector2i]) -> bool:
	for r in ranges:
		if a < r.y and b > r.x:
			return true
	return false


func _in_ranges(t: int, ranges: Array[Vector2i]) -> bool:
	for r in ranges:
		if t >= r.x and t < r.y:
			return true
	return false


# ===========================================================================
# Building nodes
# ===========================================================================

func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_build_collision()
	_build_props()
	_fore = Node2D.new()
	_fore.z_index = 2
	_fore.draw.connect(_draw_fore)
	add_child(_fore)


func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var drop := exit_drop()

	if kind == "descent":
		var fl := CollisionPolygon2D.new()
		fl.polygon = PackedVector2Array([
			Vector2(-8, 0), Vector2(SLOPE_START, 0), Vector2(SLOPE_END, DROP), Vector2(WIDTH + 8, DROP),
			Vector2(WIDTH + 8, DROP + FLOOR_BOTTOM), Vector2(-8, FLOOR_BOTTOM)])
		body.add_child(fl)
		var cl := CollisionPolygon2D.new()
		cl.polygon = PackedVector2Array([
			Vector2(-8, CEIL_TOP), Vector2(WIDTH + 8, CEIL_TOP + DROP), Vector2(WIDTH + 8, CEIL_Y + DROP),
			Vector2(SLOPE_END, CEIL_Y + DROP), Vector2(SLOPE_START, CEIL_Y), Vector2(-8, CEIL_Y)])
		body.add_child(cl)
	else:
		# Floor, split around pits. Ends overlap the neighbouring rooms a little.
		for seg in _floor_segments():
			var x0 := float(seg.x * TILE)
			var x1 := float(seg.y * TILE)
			if seg.x == 0:
				x0 -= 8.0
			if seg.y == TILES:
				x1 += 8.0
			_add_rect(body, Rect2(x0, 0, x1 - x0, FLOOR_BOTTOM))
		_add_rect(body, Rect2(-8, CEIL_TOP, WIDTH + 16, CEIL_Y - CEIL_TOP))

	# Wall above the exit door.
	_add_rect(body, Rect2(WIDTH - 8, CEIL_Y + drop, 16, -Door.H - CEIL_Y))
	# The way Bruce came in has caved in.
	if kind == "start":
		_add_rect(body, Rect2(-24, CEIL_TOP, 24, FLOOR_BOTTOM - CEIL_TOP))
	for t in tunnels:
		_add_rect(body, Rect2(t.x * TILE, CEIL_Y, (t.y - t.x) * TILE, -LOW_CLEARANCE - CEIL_Y))
	for r in rubbles:
		var h: int = r[2]
		_add_rect(body, Rect2(int(r[0]) * TILE + 1, -h, int(r[1]) * TILE - 2, h))
	for p in platforms:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(int(p[1]) * TILE, 6)
		cs.shape = shape
		cs.position = Vector2(int(p[0]) * TILE + int(p[1]) * TILE / 2.0, int(p[2]) + 3)
		cs.one_way_collision = true
		body.add_child(cs)


func _add_rect(body: StaticBody2D, r: Rect2) -> void:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	cs.position = r.get_center()
	body.add_child(cs)


func _floor_segments() -> Array[Vector2i]:
	var segs: Array[Vector2i] = []
	var sorted_pits := pits.duplicate()
	sorted_pits.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var start := 0
	for p in sorted_pits:
		if p.x > start:
			segs.append(Vector2i(start, p.x))
		start = p.y
	if start < TILES:
		segs.append(Vector2i(start, TILES))
	return segs


func _build_props() -> void:
	door = Door.new()
	door.position = Vector2(WIDTH, exit_drop())
	if kind == "descent" or (number > 0 and number % 10 == 0):
		door.label = "LV %d" % (level + (0 if kind == "descent" else 1))
	else:
		door.label = "%03d" % (number + 1)
	door.z_index = 3
	add_child(door)
	door.set_locked(is_puzzle)

	for t in lantern_tiles:
		var l := Lantern.new()
		var lx := t * TILE + 8.0
		l.position = Vector2(lx, CEIL_Y + floor_y_at(lx))
		l.light_color = theme.lantern
		l.z_index = 1
		add_child(l)
		lanterns.append(l)

	for t in crawl_tiles:
		var c := Crawlspace.new()
		c.position = Vector2(t * TILE + 8, 0)
		c.room = self
		add_child(c)
		crawlspaces.append(c)
		interactables.append(c)

	for spot in lever_spots:
		var lv := Lever.new()
		lv.position = spot
		lv.room = self
		lv.pulled.connect(_on_lever_pulled)
		add_child(lv)
		interactables.append(lv)

	if puzzle_type == "key":
		var k := Pickup.new()
		k.kind = Pickup.Kind.KEY
		k.position = key_spot
		k.z_index = 1
		add_child(k)
		pickups.append(k)

	if puzzle_type == "code":
		keypad = Keypad.new()
		keypad.position = Vector2(WIDTH - 40, 0)
		keypad.room = self
		add_child(keypad)
		interactables.append(keypad)

	for o in ore_spots:
		var p := Pickup.new()
		p.kind = Pickup.Kind.ORE
		p.ore_texture = theme.tex("ore")
		p.position = o
		p.z_index = 1
		add_child(p)
		pickups.append(p)

	# Glowing crystals light up their surroundings.
	for d in decor:
		if d[0] == "crystals":
			var light := PointLight2D.new()
			light.texture = Game.light_texture()
			light.texture_scale = 0.55
			light.energy = 0.9
			light.height = 20.0
			light.color = Color(0.55, 0.45, 1.0) if randf() < 0.6 else Color(0.35, 0.85, 1.0)
			light.position = Vector2(float(d[1]) + 9.0, -10.0)
			add_child(light)


# ===========================================================================
# Puzzles
# ===========================================================================

func is_locked() -> bool:
	return door.locked


func objective_text() -> String:
	if not door.locked:
		return ""
	match puzzle_type:
		"levers":
			return "Pull the levers to power the door   %d / %d" % [levers_pulled, levers_needed]
		"key":
			return "The door is locked. Find the key."
		"code":
			return "The door needs a code. Look around the walls."
	return ""


func _on_lever_pulled() -> void:
	levers_pulled += 1
	if levers_pulled >= levers_needed:
		_unlock()


func take_key() -> void:
	_unlock()


func try_code(entered: String) -> bool:
	if entered == code:
		if keypad != null:
			keypad.mark_solved()
		_unlock()
		return true
	return false


func _unlock() -> void:
	if not door.locked:
		return
	door.set_locked(false)
	Sfx.play("unlock", -2.0)
	puzzle_solved.emit(self)


func set_lanterns_swinging(on: bool) -> void:
	for l in lanterns:
		if is_instance_valid(l):
			l.set_swinging(on)


# ===========================================================================
# Drawing
# ===========================================================================

func _tiled(ci: CanvasItem, tex_name: String, r: Rect2, mod := Color.WHITE) -> void:
	ci.draw_texture_rect(theme.tex(tex_name), r, true, mod)


## Draws a textured polygon; UVs repeat every `tile` pixels.
func _poly(ci: CanvasItem, tex: Texture2D, pts: PackedVector2Array, tile: Vector2, mod := Color.WHITE,
		origin := Vector2.ZERO) -> void:
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append((p - origin) / tile)
	ci.draw_colored_polygon(pts, mod, uvs, tex)


## A strip texture (floor top / ceiling edge / beam) laid along a line.
func _strip(ci: CanvasItem, tex: Texture2D, a: Vector2, b: Vector2, offset: float, thickness: float,
		tile_len: float, mod := Color.WHITE) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var nrm := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([a + nrm * offset, b + nrm * offset, b + nrm * (offset + thickness), a + nrm * (offset + thickness)])
	var u1 := length / tile_len
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(0, 1)])
	ci.draw_colored_polygon(pts, mod, uvs, tex)


## Background: the back wall, timber supports, rails and props.
func _draw() -> void:
	var back_mod := Color(0.85, 0.85, 0.9)
	if kind == "descent":
		_tiled(self, "wall_back", Rect2(0, CEIL_Y, WIDTH, DROP - CEIL_Y), back_mod)
	else:
		_tiled(self, "wall_back", Rect2(0, CEIL_Y, WIDTH, -CEIL_Y), back_mod)

	# Ore veins / claw marks on the wall.
	for d in decor:
		var name: String = d[0]
		var dx: float = d[1]
		var dy: float = float(d[2]) + floor_y_at(dx)
		match name:
			"ore":
				draw_texture(theme.tex("ore"), Vector2(dx, dy), Color(0.9, 0.9, 0.9))
			"claws":
				draw_texture(MineTheme.shared("claws"), Vector2(dx, dy))

	# Timber support sets.
	var post := theme.tex("post")
	var beam := theme.tex("beam")
	for t in post_tiles:
		var x := t * TILE
		var top := CEIL_Y + floor_y_at(x)
		var fy := floor_y_at(x)
		var fy2 := floor_y_at(x + 52)
		draw_texture_rect(post, Rect2(x, top, 12, fy - top), true, Color(0.9, 0.88, 0.85))
		draw_texture_rect(post, Rect2(x + 52, CEIL_Y + fy2, 12, fy2 - CEIL_Y - fy2), true, Color(0.9, 0.88, 0.85))
		if kind == "descent":
			_strip(self, beam, Vector2(x - 4, top + 2), Vector2(x + 68, CEIL_Y + fy2 + 2), 0, 12, 64)
		else:
			draw_texture_rect(beam, Rect2(x - 4, top + 2, 72, 12), true)

	# Rails sit on the floor.
	var rail := MineTheme.shared("rail")
	for r in rails:
		draw_texture_rect(rail, Rect2(r.x * TILE, -10, (r.y - r.x) * TILE, 12), true, Color(0.9, 0.9, 0.9))

	# Floor props.
	for d in decor:
		var name: String = d[0]
		var dx: float = d[1]
		var fy := floor_y_at(dx)
		match name:
			"crate":
				draw_texture(MineTheme.shared("crate"), Vector2(dx, fy - 18))
			"barrel":
				draw_texture(MineTheme.shared("barrel"), Vector2(dx, fy - 16))
			"minecart":
				draw_texture(MineTheme.shared("minecart"), Vector2(dx, fy - 21))
			"bones":
				draw_texture(MineTheme.shared("bones"), Vector2(dx, fy - 7))
			"crystals":
				draw_texture(MineTheme.shared("crystals"), Vector2(dx, fy - 22))

	# Signs (tutorial boards and code hints).
	for s in signs:
		var sx: float = s[0]
		var text: String = s[1]
		var w: float = s[2]
		if w <= 0.0:
			draw_rect(Rect2(sx - 22, -86, 44, 28), Color(0.22, 0.15, 0.09))
			draw_rect(Rect2(sx - 22, -86, 44, 28), Color(0.45, 0.32, 0.18), false, 2.0)
			draw_string(Game.title_font, Vector2(sx - 22, -76), "CODE", HORIZONTAL_ALIGNMENT_CENTER, 44, 7, Color(0.85, 0.8, 0.7))
			draw_string(Game.title_font, Vector2(sx - 22, -63), text.substr(6), HORIZONTAL_ALIGNMENT_CENTER, 44, 12, Color(1.0, 0.55, 0.35))
		else:
			draw_rect(Rect2(sx - w / 2, -86, w, 16), Color(0.26, 0.17, 0.10))
			draw_rect(Rect2(sx - w / 2, -86, w, 16), Color(0.5, 0.35, 0.2), false, 1.0)
			draw_line(Vector2(sx, -70), Vector2(sx, -58), Color(0.3, 0.2, 0.12), 2.0)
			draw_string(Game.title_font, Vector2(sx - w / 2, -74), text, HORIZONTAL_ALIGNMENT_CENTER, w, 8, Color(0.95, 0.88, 0.7))


## Foreground (drawn over Bruce): ceiling, floor, tunnels, rubble, planks, door wall.
func _draw_fore() -> void:
	var c := _fore
	var front := theme.tex("wall_front")
	var top_strip := theme.tex("floor_top")
	var ceil_strip := theme.tex("ceiling_edge")
	var front_mod := Color(0.92, 0.92, 0.95)

	if kind == "descent":
		var a := Vector2(SLOPE_START, 0)
		var b := Vector2(SLOPE_END, DROP)
		_poly(c, front, PackedVector2Array([Vector2(0, 0), a, b, Vector2(WIDTH, DROP), Vector2(WIDTH, DROP + FLOOR_BOTTOM), Vector2(0, FLOOR_BOTTOM)]), Vector2(64, 64), front_mod)
		_poly(c, front, PackedVector2Array([Vector2(0, CEIL_TOP), Vector2(WIDTH, CEIL_TOP + DROP), Vector2(WIDTH, CEIL_Y + DROP), b + Vector2(0, CEIL_Y), a + Vector2(0, CEIL_Y), Vector2(0, CEIL_Y)]), Vector2(64, 64), front_mod)
		for seg in [[Vector2(0, 0), a], [a, b], [b, Vector2(WIDTH, DROP)]]:
			_strip(c, top_strip, seg[0], seg[1], 4, -16, 64)
			_strip(c, ceil_strip, seg[0] + Vector2(0, CEIL_Y), seg[1] + Vector2(0, CEIL_Y), -2, 24, 64)
	else:
		# Ceiling rock + its jagged underside.
		c.draw_texture_rect(front, Rect2(0, CEIL_TOP, WIDTH, CEIL_Y - CEIL_TOP), true, front_mod)
		c.draw_texture_rect(ceil_strip, Rect2(0, CEIL_Y - 2, WIDTH, 24), true)
		# Floor.
		for seg in _floor_segments():
			var x0 := float(seg.x * TILE)
			var x1 := float(seg.y * TILE)
			c.draw_texture_rect(front, Rect2(x0, 0, x1 - x0, FLOOR_BOTTOM), true, front_mod)
			c.draw_texture_rect(top_strip, Rect2(x0, -4, x1 - x0, 16), true)
		# Pits: a drop into nothing.
		for p in pits:
			var r := Rect2(p.x * TILE, 0, (p.y - p.x) * TILE, FLOOR_BOTTOM)
			c.draw_rect(r, Color(0, 0, 0))
			c.draw_texture_rect(front, Rect2(r.position.x - 3, 0, 3, 40), true, Color(0.5, 0.5, 0.5))
			c.draw_texture_rect(front, Rect2(r.end.x, 0, 3, 40), true, Color(0.5, 0.5, 0.5))
		# Low tunnels (slide under).
		var beam := theme.tex("beam")
		for t in tunnels:
			var r := Rect2(t.x * TILE, CEIL_Y, (t.y - t.x) * TILE, -LOW_CLEARANCE - CEIL_Y)
			c.draw_texture_rect(front, r, true, front_mod)
			c.draw_texture_rect(beam, Rect2(r.position.x - 3, r.end.y - 11, r.size.x + 6, 12), true)
			c.draw_rect(Rect2(r.position.x - 4, r.end.y - 12, 3, 13), Color(0.85, 0.65, 0.15))
			c.draw_rect(Rect2(r.end.x + 1, r.end.y - 12, 3, 13), Color(0.85, 0.65, 0.15))
		# Rubble piles (jump over or onto).
		var rubble := theme.tex("rubble")
		for rb in rubbles:
			var h: float = rb[2]
			var x := int(rb[0]) * TILE
			var w := int(rb[1]) * TILE
			c.draw_texture_rect(rubble, Rect2(x - 5, -h - 3, w + 10, h + 5), false)
		# Plank platforms with ropes up to the ceiling.
		var plank := theme.tex("plank")
		for p in platforms:
			var px := int(p[0]) * TILE
			var pw := int(p[1]) * TILE
			var py: float = p[2]
			c.draw_line(Vector2(px + 2, py), Vector2(px + 2, CEIL_Y), Color(0.42, 0.33, 0.22), 1.0)
			c.draw_line(Vector2(px + pw - 2, py), Vector2(px + pw - 2, CEIL_Y), Color(0.42, 0.33, 0.22), 1.0)
			c.draw_texture_rect(plank, Rect2(px, py - 1, pw, 8), true)
		# Puddles (flooded theme) shine on the floor.
		for d in decor:
			if d[0] == "puddle":
				var px: float = d[1]
				c.draw_rect(Rect2(px - 6, -2, 40, 3), Color(0.05, 0.09, 0.09, 0.85))
				c.draw_line(Vector2(px - 2, -2), Vector2(px + 26, -2), Color(0.5, 0.75, 0.75, 0.6), 1.0)

	# Wall between this room and the next, with the door frame.
	var drop := exit_drop()
	c.draw_texture_rect(front, Rect2(WIDTH - 10, CEIL_Y + drop, 20, -Door.H - CEIL_Y), true, front_mod)
	c.draw_texture(MineTheme.shared("door_frame"), Vector2(WIDTH - 14, drop - Door.H - 9))
	# The caved-in entrance of the very first room.
	if kind == "start":
		c.draw_texture_rect(front, Rect2(-40, CEIL_Y, 40, -CEIL_Y), true, front_mod)
		c.draw_texture_rect(theme.tex("rubble"), Rect2(-10, -28, 46, 30), false)
