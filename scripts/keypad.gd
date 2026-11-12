class_name Keypad
extends Interactable
## Wall keypad next to a code-locked door. Opening it shows the keypad UI.

var solved := false


func _ready() -> void:
	reach = Vector2(16, 30)


func can_interact(_player: Player) -> bool:
	return not solved


func prompt() -> String:
	return "Enter code"


func interact(game: Node) -> void:
	if not solved:
		game.open_keypad(self)


func mark_solved() -> void:
	solved = true
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-7, -40, 14, 20), Color(0.2, 0.21, 0.23))
	draw_rect(Rect2(-7, -40, 14, 20), Color(0.5, 0.5, 0.55), false, 1.0)
	draw_rect(Rect2(-5, -38, 10, 4), Color(0.1, 0.35, 0.15) if solved else Color(0.12, 0.2, 0.12))
	for r in 3:
		for c in 3:
			draw_rect(Rect2(-5 + c * 3.5, -32 + r * 3.5, 2.5, 2.5), Color(0.6, 0.6, 0.62))
	draw_line(Vector2(0, -20), Vector2(0, -4), Color(0.15, 0.15, 0.17), 1.0)   # cable
