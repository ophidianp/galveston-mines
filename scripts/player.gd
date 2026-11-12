class_name Player
extends CharacterBody2D
## Bruce Cambell. Runs, sprints, slides, crouch-walks, jumps and hides in
## crawlspaces. The node's origin is at Bruce's feet.

signal died(reason: String)

const WALK_SPEED := 135.0
const SPRINT_SPEED := 215.0
const CRAWL_SPEED := 75.0
const SLIDE_BOOST := 340.0        # speed you get when a slide starts
const SLIDE_FRICTION := 320.0     # how fast the start boost settles (px/s^2)
const SLIDE_SPEED := 290.0         # held slides keep this speed forever
const SLIDE_JUMP_BONUS := 28.0    # every chained slide-jump adds this much speed
const MAX_SLIDE_SPEED := 430.0     # cap for slide-jump chains
const CHAIN_GRACE := 0.2           # time after landing to press slide and keep the chain
const ACCEL := 1500.0
const AIR_ACCEL := 850.0
const GRAVITY := 1350.0
const MAX_FALL := 760.0
const JUMP_VELOCITY := -370.0     # ~50px jump height, snappier
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12

const STAND_SIZE := Vector2(10, 26)
const LOW_SIZE := Vector2(12, 12)

var sprite: AnimatedSprite2D
var light: PointLight2D           # soft glow around Bruce
var beam: PointLight2D            # hard-hat lamp beam
var _shape_node: CollisionShape2D
var _stand_shape: RectangleShape2D
var _low_shape: RectangleShape2D
var _probe_shape: RectangleShape2D

var is_low := false
var sliding := false
var facing := 1.0
var hiding_spot: Node2D = null
var is_dead := false
var controls_enabled := true

var slide_chain := 0               # consecutive slide-jumps (more = faster)
var _slide_jump_air := false       # airborne from a slide-jump (keeps momentum)
var _chain_grace := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0

static var _frames: SpriteFrames


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 6.0
	safe_margin = 0.5

	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = build_frames()
	sprite.position = Vector2(0, -16)
	add_child(sprite)
	sprite.play("idle")

	_stand_shape = RectangleShape2D.new()
	_stand_shape.size = STAND_SIZE
	_low_shape = RectangleShape2D.new()
	_low_shape.size = LOW_SIZE
	_probe_shape = RectangleShape2D.new()
	_probe_shape.size = STAND_SIZE - Vector2(2, 2)
	_shape_node = CollisionShape2D.new()
	add_child(_shape_node)
	_set_low(false)

	# Soft glow so Bruce and the floor around him are always readable.
	light = PointLight2D.new()
	light.texture = Game.light_texture()
	light.texture_scale = 0.75
	light.energy = 0.55
	light.height = 30.0
	light.color = Color(1.0, 0.88, 0.7)
	light.position = Vector2(0, -18)
	add_child(light)
	# Hard-hat lamp: a beam that points where Bruce is facing.
	beam = PointLight2D.new()
	beam.texture = Game.cone_texture()
	beam.texture_scale = 1.45
	beam.energy = 1.15
	beam.height = 24.0
	beam.color = Color(1.0, 0.95, 0.82)
	beam.position = Vector2(3, -27)
	add_child(beam)


## Builds Bruce's animations from the sprite sheet (see BRUCE_SPRITESHEET_GUIDE.md).
static func build_frames() -> SpriteFrames:
	if _frames != null:
		return _frames
	var tex: Texture2D = MineTheme.shared("bruce")
	var f := SpriteFrames.new()
	if f.has_animation("default"):
		f.remove_animation("default")
	# name, sheet row, frame count, fps
	var defs := [
		["idle", 0, 4, 5.0],
		["walk", 1, 4, 8.0],
		["run", 2, 6, 12.0],
		["jump", 3, 2, 6.0],
		["crouch", 4, 2, 5.0],
		["slide", 5, 4, 10.0],
	]
	for d in defs:
		var anim: StringName = StringName(d[0])
		f.add_animation(anim)
		f.set_animation_speed(anim, float(d[3]))
		f.set_animation_loop(anim, true)
		for i in int(d[2]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * 32, int(d[1]) * 32, 32, 32)
			f.add_frame(anim, at)
	_frames = f
	return f


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
		velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
		move_and_slide()
		return
	if hiding_spot != null:
		velocity = Vector2.ZERO
		return

	var dir := 0.0
	var want_low := false
	var sprinting := false
	if controls_enabled:
		dir = Input.get_axis("move_left", "move_right")
		want_low = Input.is_action_pressed("slide")
		sprinting = Input.is_action_pressed("sprint")
		if Input.is_action_just_pressed("jump"):
			_jump_buffer = JUMP_BUFFER
	_jump_buffer -= delta
	if dir != 0.0:
		facing = signf(dir)

	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote -= delta
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	# Landing from a slide-jump: keep the chain alive for a moment.
	if on_floor and _slide_jump_air:
		_slide_jump_air = false
		_chain_grace = CHAIN_GRACE
	_chain_grace -= delta
	if on_floor and not sliding and _chain_grace <= 0.0:
		slide_chain = 0

	# --- Slide / crouch -----------------------------------------------------
	if want_low and on_floor and not is_low:
		_set_low(true)
		if absf(velocity.x) > WALK_SPEED * 0.6:
			sliding = true
			facing = signf(velocity.x)
			if slide_chain > 0:
				# Landed from a slide-jump into a slide: carry all that speed.
				velocity.x = facing * maxf(absf(velocity.x), chain_speed())
			else:
				velocity.x = facing * maxf(absf(velocity.x) + 70.0, SLIDE_BOOST)
			Sfx.play("slide", -6.0, randf_range(0.9, 1.1) + slide_chain * 0.05)
	elif is_low and not want_low and _can_stand():
		_set_low(false)
		sliding = false
		slide_chain = 0

	# --- Horizontal movement ------------------------------------------------
	if sliding and on_floor:
		# Infinite slide: the boost settles to SLIDE_SPEED and holds there
		# for as long as the slide button is held (or a tunnel keeps you low).
		var target_slide := chain_speed()
		if get_floor_normal().x * facing > 0.15:
			target_slide += 120.0      # sliding downhill is faster
		velocity.x = move_toward(velocity.x, facing * target_slide, SLIDE_FRICTION * delta)
	elif _slide_jump_air and (dir == 0.0 or signf(dir) == signf(velocity.x)):
		pass   # slide-jumps keep their speed in the air unless you steer back
	else:
		var top := WALK_SPEED
		if is_low:
			top = CRAWL_SPEED
		elif sprinting:
			top = SPRINT_SPEED
		var target := dir * top
		var accel := ACCEL if on_floor else AIR_ACCEL
		# Keep slide-jump momentum in the air while still holding forward.
		if not on_floor and dir != 0.0 and signf(target) == signf(velocity.x) and absf(velocity.x) > absf(target):
			accel = 160.0
		velocity.x = move_toward(velocity.x, target, accel * delta)

	# --- Jump ---------------------------------------------------------------
	if _jump_buffer > 0.0 and _coyote > 0.0 and (not is_low or _can_stand()):
		var was_sliding := sliding
		if is_low:
			_set_low(false)
		sliding = false
		velocity.y = JUMP_VELOCITY
		if was_sliding:
			# Slide-jump: a little faster every time you chain one.
			slide_chain += 1
			_slide_jump_air = true
			velocity.x = facing * maxf(absf(velocity.x), chain_speed())
		_jump_buffer = 0.0
		_coyote = 0.0
		Sfx.play("jump", -10.0, randf_range(0.9, 1.15) + slide_chain * 0.06)
	if controls_enabled and Input.is_action_just_released("jump") and velocity.y < -260.0:
		velocity.y = -260.0   # shorter hop (~25px) when jump is tapped

	move_and_slide()
	# Sliding into something solid (like rubble) stops the slide.
	if is_on_wall() and absf(get_real_velocity().x) < 20.0 and (sliding or _slide_jump_air):
		sliding = false
		_slide_jump_air = false
		slide_chain = 0
		velocity.x = 0.0
	_update_animation()


## Sustained slide speed: base speed plus a bonus per chained slide-jump.
func chain_speed() -> float:
	return minf(SLIDE_SPEED + slide_chain * SLIDE_JUMP_BONUS, MAX_SLIDE_SPEED)


func _set_low(low: bool) -> void:
	is_low = low
	var s: Vector2 = LOW_SIZE if low else STAND_SIZE
	_shape_node.shape = _low_shape if low else _stand_shape
	_shape_node.position = Vector2(0, -s.y / 2.0)


## True when there is head room to stand up (e.g. not under a low tunnel).
func _can_stand() -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = _probe_shape
	q.transform = Transform2D(0.0, global_position + Vector2(0, -STAND_SIZE.y / 2.0 - 1.5))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _update_animation() -> void:
	var anim := "idle"
	var speed := absf(velocity.x)
	if not is_on_floor():
		anim = "jump"
	elif sliding:
		anim = "slide"
	elif is_low:
		anim = "crouch"
	elif speed > 170.0:
		anim = "run"
	elif speed > 8.0:
		anim = "walk"
	if sprite.animation != anim:
		sprite.play(anim)
	match anim:
		"crouch":
			# Crouch-walk animates fast, crouching still keeps a slow bob.
			sprite.speed_scale = 1.4 if speed > 5.0 else 0.45
		"walk":
			sprite.speed_scale = clampf(speed / WALK_SPEED, 0.5, 1.5)
		"run":
			sprite.speed_scale = clampf(speed / SPRINT_SPEED, 0.7, 1.6)
		_:
			sprite.speed_scale = 1.0
	sprite.flip_h = facing < 0.0
	beam.position.x = 3.0 * facing
	beam.rotation = 0.0 if facing > 0.0 else PI
	# The beam dips a little while sliding / crouching.
	beam.position.y = -14.0 if is_low else -27.0


# --- Hiding ----------------------------------------------------------------

func hide_in(spot: Node2D) -> void:
	hiding_spot = spot
	velocity = Vector2.ZERO
	sliding = false
	_set_low(true)
	global_position.x = spot.global_position.x
	sprite.play("crouch")
	sprite.speed_scale = 0.3
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "modulate", Color(0.35, 0.35, 0.42, 0.6), 0.25)
	tw.tween_property(sprite, "position", Vector2(0, -13), 0.25)
	tw.tween_property(light, "energy", 0.1, 0.25)
	tw.tween_property(beam, "energy", 0.0, 0.25)
	Sfx.play("hide", -6.0)


func leave_hiding() -> void:
	if hiding_spot == null:
		return
	hiding_spot = null
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.2)
	tw.tween_property(sprite, "position", Vector2(0, -16), 0.2)
	tw.tween_property(light, "energy", 0.55, 0.3)
	tw.tween_property(beam, "energy", 1.15, 0.3)
	Sfx.play("hide", -8.0, 1.2)


func is_hidden() -> bool:
	return hiding_spot != null


# --- Death -----------------------------------------------------------------

func die(reason: String) -> void:
	if is_dead:
		return
	is_dead = true
	controls_enabled = false
	hiding_spot = null
	sprite.play("crouch")
	sprite.speed_scale = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "modulate", Color(0.45, 0.08, 0.08), 0.4)
	tw.tween_property(light, "energy", 0.0, 1.2)
	tw.tween_property(beam, "energy", 0.0, 0.6)
	died.emit(reason)
