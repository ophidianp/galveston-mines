class_name Interactable
extends Node2D
## Base class for anything Bruce can use with [E]: crawlspaces, levers and
## keypads. The Game scene finds the closest one in range and shows a prompt.

var reach := Vector2(14, 28)   # how close Bruce must be (x, y)
var room: Node = null          # the Room this belongs to


func can_interact(_player: Player) -> bool:
	return true


func prompt() -> String:
	return "Use"


func interact(_game: Node) -> void:
	pass


func in_reach(player: Player) -> bool:
	var d := player.global_position - global_position
	return absf(d.x) <= reach.x and absf(d.y) <= reach.y
