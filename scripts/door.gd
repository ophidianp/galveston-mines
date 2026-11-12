class_name Door
extends StaticBody2D
## The 8-inch-thick metal door at the end of every room. Origin = floor level,
## centred in the wall between two rooms. It slides up into the rock to open.

const W := 14.0
const H := 48.0

var label := "001"            # shown on the plate above the door
var locked := false
var is_open := false
var _slab_y := 0.0            # 0 = closed, -H = fully open
var _shape: CollisionShape2D
var _lamp: PointLight2D


func _ready() -> void:
	collision_layer = 1
	_shape = CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(W, H)
	_shape.shape = r
	_shape.position = Vector2(0, -H / 2.0)
	add_child(_shape)

	_lamp = PointLight2D.new()
	_lamp.texture = Game.light_texture()
	_lamp.texture_scale = 0.35
	_lamp.energy = 1.2
	_lamp.position = Vector2(0, -H - 14)
	_lamp.height = 20.0
	add_child(_lamp)
	_refresh_lamp()


func set_locked(v: bool) -> void:
	locked = v
	_refresh_lamp()
	queue_redraw()


func _refresh_lamp() -> void:
	if _lamp != null:
		_lamp.color = Color(1.0, 0.25, 0.2) if locked else Color(0.4, 1.0, 0.45)


func open() -> void:
	if is_open or locked:
		return
	is_open = true
	_shape.set_deferred("disabled", true)
	Sfx.play("door_open", -4.0)
	var tw := create_tween()
	tw.tween_method(_set_slab, _slab_y, -H, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func slam() -> void:
	if not is_open:
		return
	is_open = false
	_shape.set_deferred("disabled", false)
	var tw := create_tween()
	tw.tween_method(_set_slab, _slab_y, 0.0, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void: Sfx.play("thud", 0.0))


func _set_slab(y: float) -> void:
	_slab_y = y
	queue_redraw()


func _draw() -> void:
	# Number plate above the door.
	var plate := Rect2(-16, -H - 34, 32, 13)
	draw_rect(plate, Color(0.16, 0.13, 0.10))
	draw_rect(plate, Color(0.55, 0.42, 0.22), false, 1.0)
	draw_string(Game.title_font, Vector2(-16, -H - 24), label, HORIZONTAL_ALIGNMENT_CENTER, 32, 10, Color(0.95, 0.85, 0.6))
	# Status lamp.
	draw_circle(Vector2(0, -H - 14), 2.0, Color(1, 0.3, 0.25) if locked else Color(0.45, 1, 0.5))
	# Dark recess behind the slab.
	draw_rect(Rect2(-W / 2 - 1, -H, W + 2, H), Color(0.03, 0.03, 0.035))
	# The steel slab, clipped where it has slid up into the rock.
	var top := -H + _slab_y
	var visible_top := maxf(top, -H)
	var h := (top + H) - visible_top
	if h > 0.5:
		var src_y := visible_top - top
		draw_texture_rect_region(MineTheme.shared("door"), Rect2(-W / 2, visible_top, W, h), Rect2(0, src_y, W, h))
		if locked:
			draw_rect(Rect2(-3, top + H * 0.45, 6, 7), Color(0.75, 0.6, 0.2))
			draw_rect(Rect2(-1, top + H * 0.45 + 2, 2, 3), Color(0.1, 0.08, 0.05))
