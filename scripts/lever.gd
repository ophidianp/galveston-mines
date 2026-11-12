class_name Lever
extends Interactable
## Puzzle lever. Pull every lever in the room to power the door.
## Origin = where it is mounted (floor or plank level).

signal pulled

var is_pulled := false
var _angle := -0.6
var _lamp: PointLight2D


func _ready() -> void:
	reach = Vector2(14, 22)
	_lamp = PointLight2D.new()
	_lamp.texture = Game.light_texture()
	_lamp.texture_scale = 0.25
	_lamp.energy = 1.0
	_lamp.color = Color(1, 0.3, 0.2)
	_lamp.position = Vector2(0, -26)
	add_child(_lamp)


func can_interact(_player: Player) -> bool:
	return not is_pulled


func prompt() -> String:
	return "Pull lever"


func interact(_game: Node) -> void:
	if is_pulled:
		return
	is_pulled = true
	Sfx.play("lever", -2.0)
	_lamp.color = Color(0.4, 1, 0.45)
	var tw := create_tween()
	tw.tween_method(_set_angle, _angle, 0.6, 0.2)
	pulled.emit()


func _set_angle(a: float) -> void:
	_angle = a
	queue_redraw()


func _draw() -> void:
	# Wall box.
	draw_rect(Rect2(-7, -22, 14, 18), Color(0.25, 0.26, 0.28))
	draw_rect(Rect2(-7, -22, 14, 18), Color(0.45, 0.46, 0.5), false, 1.0)
	draw_rect(Rect2(-5, -6, 10, 6), Color(0.18, 0.18, 0.2))   # stand
	# Handle.
	var pivot := Vector2(0, -12)
	var tip := pivot + Vector2(sin(_angle), -cos(_angle)) * 11.0
	draw_line(pivot, tip, Color(0.7, 0.7, 0.72), 2.0)
	draw_circle(tip, 2.2, Color(0.85, 0.2, 0.15) if not is_pulled else Color(0.3, 0.8, 0.35))
	draw_circle(pivot, 1.6, Color(0.1, 0.1, 0.1))
	# Status light.
	draw_circle(Vector2(0, -26), 1.8, Color(1, 0.3, 0.2) if not is_pulled else Color(0.4, 1, 0.45))
