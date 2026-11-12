class_name Crawlspace
extends Interactable
## A low hole in the mine wall. Bruce can crawl inside to hide from
## The Wanderer. Origin = floor level, centre of the opening.



func _ready() -> void:
	reach = Vector2(16, 20)


func prompt() -> String:
	return "Hide"


func interact(_game: Node) -> void:
	pass   # handled by Game (it needs to toggle the player's hidden state)


func _draw() -> void:
	draw_texture(MineTheme.shared("crawlspace"), Vector2(-22, -26))
