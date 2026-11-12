class_name Lantern
extends Node2D
## A hanging lantern. Hangs still normally; swings fast (and flickers) when
## The Wanderer is coming. Origin = the ceiling hook.

var sprite: AnimatedSprite2D
var light: PointLight2D
var swinging := false
var light_color := Color(1.0, 0.72, 0.38)
var _t := 0.0
var _base_energy := 1.0

static var _frames: SpriteFrames


static func build_frames() -> SpriteFrames:
	if _frames != null:
		return _frames
	var tex: Texture2D = MineTheme.shared("lantern")
	var f := SpriteFrames.new()
	if f.has_animation("default"):
		f.remove_animation("default")
	f.add_animation(&"still")
	f.add_animation(&"swing_fast")
	f.set_animation_speed(&"swing_fast", 11.0)
	f.set_animation_loop(&"swing_fast", true)
	for i in 4:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * 32, 0, 32, 64)
		f.add_frame(&"swing_fast", at)
		if i == 0:
			f.add_frame(&"still", at)
	_frames = f
	return f


func _ready() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = build_frames()
	sprite.position = Vector2(0, 32)
	sprite.play(&"still")
	add_child(sprite)

	light = PointLight2D.new()
	light.texture = Game.light_texture()
	light.texture_scale = 1.15
	light.color = light_color
	light.position = Vector2(0, 40)
	light.height = 36.0
	_base_energy = randf_range(0.95, 1.15)
	light.energy = _base_energy
	add_child(light)
	_t = randf() * 10.0


func set_swinging(on: bool) -> void:
	if on == swinging:
		return
	swinging = on
	if on:
		sprite.play(&"swing_fast")
		sprite.frame = randi() % 4
	else:
		sprite.play(&"still")
		light.position.x = 0.0


func _process(delta: float) -> void:
	_t += delta
	if swinging:
		light.position.x = sin(_t * 11.0) * 5.0
		# Lights stutter while it's near.
		light.energy = _base_energy * (0.45 + 0.55 * absf(sin(_t * 23.0 + sin(_t * 7.0) * 3.0)))
	else:
		light.energy = _base_energy * (0.93 + 0.07 * sin(_t * 3.1) * sin(_t * 1.7))
