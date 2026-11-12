extends Node2D
## Runs a single attempt at the mines: generates rooms ahead of Bruce, frees
## the ones behind him, opens/slams doors, runs The Wanderer events, handles
## interaction, scoring and death.

const ROOMS_AHEAD := 2
const ROOMS_PER_LEVEL := 10
const CAMERA_Y := -78.0
const FALL_DEATH_Y := 150.0

const SCORE_ROOM := 100        # x level, for every new room reached
const SCORE_SURVIVE := 150     # surviving a Wanderer pass
const SCORE_PUZZLE := 75
const SCORE_ORE := 50

var rooms: Dictionary = {}          # slot -> Room
var player: Player
var camera: Camera2D
var hud: Hud

var current_index := 0              # slot of the room Bruce is in
var furthest_number := 1            # highest room number reached
var level := 1
var score := 0
var run_seed := 0
var _next_to_generate := 0
var _last_was_puzzle := false
var _gen_number := 1                # next room number to generate
var _gen_level := 1
var _gen_base_y := 0.0              # floor height of the next room (descents add to it)
var _pending_descent := false
var _theme: MineTheme
var _dark: CanvasModulate
var _post: ShaderMaterial
var _dust: CPUParticles2D
var _fog: CPUParticles2D
var _game_over := false
var _shake := 0.0
var _active_keypad: Keypad = null
var _hide_cooldown := 0.0           # stops E-mashing from flickering in/out

# Wanderer event state.
var _event_phase := ""              # "", "warning", "pass", "between"
var _event_room: Room = null
var _event_timer := 0.0
var _warn_total := 1.0
var _passes_left := 0
var _wanderer_dir := 1.0
var _wanderer: Wanderer = null
var _last_rel := 0.0


func _ready() -> void:
	get_tree().paused = false
	randomize()
	run_seed = randi()
	RenderingServer.set_default_clear_color(Color(0.015, 0.015, 0.02))

	_dark = CanvasModulate.new()
	add_child(_dark)
	_build_post_process()

	for i in ROOMS_AHEAD + 1:
		_generate_next_room()

	player = Player.new()
	player.position = Vector2(56, 0)
	player.z_index = 1
	player.died.connect(_on_player_died)
	add_child(player)

	camera = Camera2D.new()
	camera.zoom = Vector2(3, 3)
	camera.limit_left = -40
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	camera.position = Vector2(player.position.x, CAMERA_Y)
	add_child(camera)
	camera.make_current()
	_build_particles()
	_apply_theme(MineTheme.for_level(1), true)

	hud = Hud.new()
	hud.game = self
	add_child(hud)
	hud.retry_pressed.connect(_on_retry)
	hud.menu_pressed.connect(_on_menu)
	hud.code_submitted.connect(_on_code_submitted)
	hud.keypad_closed.connect(_on_keypad_closed)

	_rooms_entered(0)
	hud.show_banner("GALVESTON MINES", "The way out has caved in. Keep moving.")
	hud.show_hint("A / D to move   SHIFT to sprint   SPACE to jump   CTRL or S to slide   E to interact   ESC to pause", 6.0)
	_refresh_hud()


# ===========================================================================
# Rooms
# ===========================================================================

func _generate_next_room() -> void:
	var i := _next_to_generate
	var r := Room.new()
	var what := "normal"
	var number := _gen_number
	if i == 0:
		what = "start"
	elif _pending_descent:
		# Between levels: a sloped tunnel down into the next level.
		what = "descent"
		number = 0
		_gen_level += 1
		_pending_descent = false
	r.generate(i, number, _gen_level, what, _gen_base_y, hash(run_seed + i * 7919), _last_was_puzzle)
	if what != "descent":
		_gen_number += 1
		if number % ROOMS_PER_LEVEL == 0:
			_pending_descent = true
	_gen_base_y += r.exit_drop()
	_last_was_puzzle = r.is_puzzle
	r.puzzle_solved.connect(_on_puzzle_solved)
	add_child(r)
	rooms[i] = r
	_next_to_generate += 1
	if _event_phase != "":
		r.set_lanterns_swinging(true)


func _rooms_entered(idx: int) -> void:
	current_index = idx
	var room: Room = rooms.get(idx)
	if room != null and not room.visited:
		room.visited = true
		if room.number > furthest_number:
			furthest_number = room.number
			score += SCORE_ROOM * room.level
		if room.level != level:
			level = room.level
			hud.show_banner("LEVEL %d" % level, room.theme.title)
			Sfx.play("level", -2.0)
		_apply_theme(room.theme, false)
	while _next_to_generate <= idx + ROOMS_AHEAD:
		_generate_next_room()
	# Free rooms that are two or more behind.
	for k in rooms.keys():
		if int(k) < idx - 1:
			var old: Room = rooms[k]
			if old == _event_room:
				continue
			rooms.erase(k)
			old.queue_free()


# ===========================================================================
# Main loop
# ===========================================================================

func _process(delta: float) -> void:
	_update_shake(delta)
	if _game_over:
		return

	var px := player.global_position.x
	var idx := int(floor(px / Room.WIDTH))
	if idx > current_index and rooms.has(idx):
		_rooms_entered(idx)

	var room: Room = rooms.get(current_index)
	# Camera follows Bruce, and the floor line down slopes.
	var look := clampf(player.velocity.x * 0.35, -85.0, 85.0)
	var cam_y := CAMERA_Y
	if room != null:
		var ahead: Room = room
		var lx := px + look - room.position.x
		if lx > Room.WIDTH and rooms.has(current_index + 1):
			ahead = rooms[current_index + 1]
			lx -= Room.WIDTH
		cam_y += ahead.position.y + ahead.floor_y_at(lx)
	camera.position = Vector2(px + look, cam_y)
	_dust.global_position = camera.global_position
	_fog.global_position = camera.global_position
	if room != null:
		_update_doors(room, px)
		_update_pickups(room)
		hud.set_objective(room.objective_text())
	_update_interaction(room)
	_update_wanderer(delta, room)

	# Fell into a pit: measured from the floor under Bruce (descent rooms slope down).
	var floor_y := 0.0
	if room != null:
		floor_y = room.position.y + room.floor_y_at(px - room.position.x)
	if player.global_position.y > floor_y + FALL_DEATH_Y and not player.is_dead:
		player.die("Bruce fell into the dark.")
	_refresh_hud()


func _update_doors(room: Room, px: float) -> void:
	var door_x := room.position.x + Room.WIDTH
	if not room.door.is_open and not room.door.locked and px > door_x - 110.0 and px < door_x:
		room.door.open()
	# Slam the door behind Bruce once he is through.
	var prev: Room = rooms.get(current_index - 1)
	if prev != null and prev.door.is_open and px > prev.position.x + Room.WIDTH + 56.0:
		prev.door.slam()
		_add_shake(2.0)


func _update_pickups(room: Room) -> void:
	for p in room.pickups:
		if is_instance_valid(p) and p.touching(player):
			p.collect()
			if p.kind == Pickup.Kind.KEY:
				hud.popup("Got the key")
				room.take_key()
			else:
				score += SCORE_ORE
				hud.popup("+%d  ore" % SCORE_ORE)


func _update_interaction(room: Room) -> void:
	if hud.keypad_open or hud.keypad_just_closed() or player.is_dead:
		hud.set_prompt("")
		return
	_hide_cooldown -= get_process_delta_time()
	if player.is_hidden():
		hud.set_prompt("[E]  Leave crawlspace")
		if _hide_cooldown <= 0.0 and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("jump")):
			player.leave_hiding()
			hud.set_hidden_overlay(false)
			_hide_cooldown = 0.4
		return

	var target: Interactable = null
	var best := INF
	if room != null:
		for it in room.interactables:
			if is_instance_valid(it) and it.can_interact(player) and it.in_reach(player):
				var d := absf(it.global_position.x - player.global_position.x)
				if d < best:
					best = d
					target = it
	if target == null:
		var door_x := room.position.x + Room.WIDTH if room != null else 0.0
		if room != null and room.door.locked and absf(player.global_position.x - door_x) < 40.0:
			hud.set_prompt("Locked")
		else:
			hud.set_prompt("")
		return

	hud.set_prompt("[E]  " + target.prompt())
	if Input.is_action_just_pressed("interact"):
		if target is Crawlspace:
			if player.is_on_floor() and _hide_cooldown <= 0.0:
				_hide_cooldown = 0.4
				player.hide_in(target)
				hud.set_hidden_overlay(true)
		else:
			target.interact(self)


# ===========================================================================
# Puzzles
# ===========================================================================

func open_keypad(pad: Keypad) -> void:
	_active_keypad = pad
	player.controls_enabled = false
	hud.open_keypad()


func _on_code_submitted(code: String) -> void:
	if _active_keypad == null:
		return
	var room := _active_keypad.room as Room
	hud.keypad_result(room.try_code(code))


func _on_keypad_closed() -> void:
	_active_keypad = null
	if not player.is_dead:
		player.controls_enabled = true


func _on_puzzle_solved(_room: Room) -> void:
	score += SCORE_PUZZLE
	hud.popup("Door unlocked   +%d" % SCORE_PUZZLE)


# ===========================================================================
# The Wanderer
# ===========================================================================

func _update_wanderer(delta: float, room: Room) -> void:
	if _event_phase == "" and room != null and room.has_wanderer and room.wanderer_state == 0 \
			and player.global_position.x >= room.wanderer_trigger_x:
		_start_wanderer_event(room)

	match _event_phase:
		"warning":
			_event_timer -= delta
			var k := 1.0 - _event_timer / _warn_total
			Sfx.set_rumble(0.2 + 0.8 * k)
			_shake = maxf(_shake, 0.4 + 1.8 * k)
			if _event_timer <= 0.0:
				_spawn_wanderer()
		"pass":
			if _wanderer != null:
				var rel := _wanderer.global_position.x - player.global_position.x
				var dx := absf(rel)
				Sfx.set_rumble(clampf(1.0 - dx / 800.0, 0.35, 1.0))
				_shake = maxf(_shake, clampf(5.0 - dx / 90.0, 0.6, 5.0))
				# Caught if it is on top of Bruce, or swept past him this frame.
				var crossed := signf(rel) != signf(_last_rel) and _last_rel != 0.0
				_last_rel = rel
				if (dx < 16.0 or crossed) and not player.is_hidden() and not player.is_dead:
					_killed_by_wanderer()
				if _wanderer.finished:
					_wanderer.queue_free()
					_wanderer = null
					_passes_left -= 1
					if _passes_left > 0:
						_event_phase = "between"
						_event_timer = randf_range(1.0, 1.8)
					else:
						_end_wanderer_event()
		"between":
			_event_timer -= delta
			Sfx.set_rumble(0.4)
			_shake = maxf(_shake, 0.8)
			if _event_timer <= 0.0:
				_spawn_wanderer()


func _start_wanderer_event(room: Room) -> void:
	room.wanderer_state = 1
	_event_room = room
	_event_phase = "warning"
	_warn_total = maxf(2.2, 3.8 - 0.3 * (room.level - 1))
	_event_timer = _warn_total
	_passes_left = room.wanderer_passes
	_wanderer_dir = -1.0 if room.wanderer_from_front else 1.0
	for r in rooms.values():
		(r as Room).set_lanterns_swinging(true)
	if hud.keypad_open:
		hud.close_keypad()
	if not Game.seen_wanderer_hint:
		hud.show_hint("The lanterns are swinging... something is coming.  HIDE in a crawlspace!  [E]", 4.5)
		Game.seen_wanderer_hint = true
		Game.save_data()


func _spawn_wanderer() -> void:
	_event_phase = "pass"
	_wanderer = Wanderer.new()
	_wanderer.direction = _wanderer_dir
	_wanderer.speed = minf(800.0 + 50.0 * (level - 1), 1150.0)
	var room: Room = rooms.get(current_index)
	var floor_y := room.position.y if room != null else 0.0
	_wanderer.position = Vector2(player.global_position.x - _wanderer_dir * 640.0, floor_y)
	_wanderer.end_x = player.global_position.x + _wanderer_dir * 720.0
	_wanderer.z_index = 5
	_last_rel = _wanderer.position.x - player.global_position.x
	add_child(_wanderer)
	Sfx.play("screech", 2.0)
	_wanderer_dir = -_wanderer_dir      # a second pass comes back the other way


func _end_wanderer_event() -> void:
	_event_phase = ""
	Sfx.set_rumble(0.0)
	for r in rooms.values():
		(r as Room).set_lanterns_swinging(false)
	if _event_room != null and is_instance_valid(_event_room):
		_event_room.wanderer_state = 2
	_event_room = null
	if not player.is_dead:
		score += SCORE_SURVIVE
		hud.popup("+%d  Survived The Wanderer" % SCORE_SURVIVE)
	# Free rooms we kept around during the event.
	_rooms_entered(current_index)


func _killed_by_wanderer() -> void:
	hud.flash(Color(0, 0, 0, 1), 0.35, 1.2)
	_add_shake(8.0)
	player.die("The Wanderer got Bruce.")


# ===========================================================================
# Death, HUD, shake
# ===========================================================================

func _on_player_died(reason: String) -> void:
	_game_over = true
	Sfx.set_rumble(0.0)
	Sfx.play("death", 0.0)
	hud.set_prompt("")
	hud.set_objective("")
	hud.close_keypad()
	var rooms_survived := furthest_number - 1
	var new_best := Game.submit_run(score, rooms_survived)
	await get_tree().create_timer(1.3).timeout
	hud.show_death(reason, rooms_survived, score, Game.best_score, new_best)


func _on_retry() -> void:
	get_tree().paused = false
	Sfx.set_rumble(0.0)
	get_tree().reload_current_scene()


func _on_menu() -> void:
	get_tree().paused = false
	Sfx.set_rumble(0.0)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _refresh_hud() -> void:
	var room: Room = rooms.get(current_index)
	var label := "DESCENDING" if room != null and room.kind == "descent" else "ROOM %03d" % furthest_number
	hud.set_stats(label, level, score, Game.best_score)
	hud.set_chain(player.slide_chain)


func _add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _update_shake(delta: float) -> void:
	if not Game.screen_shake or _shake <= 0.01:
		camera.offset = Vector2.ZERO
		_shake = maxf(_shake - delta * 6.0, 0.0)
		return
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	_shake = maxf(_shake - delta * 6.0, 0.0)


# ===========================================================================
# Atmosphere: per-level theme, colour grading, particles
# ===========================================================================

func _build_post_process() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post = ShaderMaterial.new()
	_post.shader = load("res://shaders/post.gdshader")
	rect.material = _post
	layer.add_child(rect)


func _build_particles() -> void:
	_dust = CPUParticles2D.new()
	_dust.amount = 70
	_dust.lifetime = 6.0
	_dust.preprocess = 6.0
	_dust.local_coords = false
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.emission_rect_extents = Vector2(260, 140)
	_dust.z_index = 1
	add_child(_dust)

	# Slow drifting fog banks.
	_fog = CPUParticles2D.new()
	_fog.texture = MineTheme.shared("soft")
	_fog.amount = 14
	_fog.lifetime = 14.0
	_fog.preprocess = 14.0
	_fog.local_coords = false
	_fog.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_fog.emission_rect_extents = Vector2(300, 60)
	_fog.direction = Vector2(1, 0)
	_fog.spread = 20.0
	_fog.gravity = Vector2.ZERO
	_fog.initial_velocity_min = 3.0
	_fog.initial_velocity_max = 9.0
	_fog.scale_amount_min = 7.0
	_fog.scale_amount_max = 12.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.5, Color(1, 1, 1, 1))
	_fog.color_ramp = fade
	_fog.z_index = 1
	add_child(_fog)


func _set_post(value: Variant, param: String) -> void:
	_post.set_shader_parameter(param, value)


## Switches lighting, grading and particles to a level's look.
func _apply_theme(t: MineTheme, instant: bool) -> void:
	if t == _theme:
		return
	_theme = t
	var dur := 0.01 if instant else 2.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dark, "color", t.ambient, dur)
	var from_tint: Color = _post.get_shader_parameter("tint") if _post.get_shader_parameter("tint") != null else t.tint
	var from_sat: float = _post.get_shader_parameter("saturation") if _post.get_shader_parameter("saturation") != null else t.saturation
	var from_con: float = _post.get_shader_parameter("contrast") if _post.get_shader_parameter("contrast") != null else t.contrast
	tw.tween_method(_set_post.bind("tint"), from_tint, t.tint, dur)
	tw.tween_method(_set_post.bind("saturation"), from_sat, t.saturation, dur)
	tw.tween_method(_set_post.bind("contrast"), from_con, t.contrast, dur)
	_fog.color = t.fog

	var d := _dust
	d.gravity = Vector2(0, 2)
	d.direction = Vector2(0.3, 1)
	d.spread = 50.0
	d.initial_velocity_min = 2.0
	d.initial_velocity_max = 8.0
	d.scale_amount_min = 1.0
	d.scale_amount_max = 1.6
	match t.particles:
		"dust":
			d.color = Color(1.0, 0.9, 0.7, 0.45)
		"drips":
			d.color = Color(0.6, 0.85, 0.9, 0.7)
			d.direction = Vector2(0, 1)
			d.spread = 0.0
			d.gravity = Vector2(0, 260)
			d.initial_velocity_min = 0.0
			d.initial_velocity_max = 0.0
			d.scale_amount_max = 1.2
		"embers":
			d.color = Color(1.0, 0.55, 0.2, 0.9)
			d.direction = Vector2(0.2, -1)
			d.gravity = Vector2(0, -8)
			d.initial_velocity_min = 4.0
			d.initial_velocity_max = 14.0
		"sparkles":
			d.color = Color(0.75, 0.7, 1.0, 0.9)
			d.gravity = Vector2.ZERO
			d.initial_velocity_max = 3.0
		"ash":
			d.color = Color(0.55, 0.5, 0.5, 0.6)
			d.gravity = Vector2(4, 6)
			d.scale_amount_max = 2.0
