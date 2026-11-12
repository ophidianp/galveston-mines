class_name Pickup
extends Node2D
## Something Bruce collects by touching it: the door key, or a chunk of ore
## (bonus score). Origin = the item's centre.

enum Kind { KEY, ORE }

var kind: Kind = Kind.ORE
var collected := false
var _t := 0.0
var _base_y := 0.0
var _light: PointLight2D

var ore_texture: Texture2D       # set by the Room (each level has its own ore)


func _ready() -> void:
	_base_y = position.y
	_t = randf() * 5.0
	_light = PointLight2D.new()
	_light.texture = Game.light_texture()
	_light.texture_scale = 0.3
	_light.height = 16.0
	_light.energy = 0.9
	_light.color = Color(1.0, 0.85, 0.35) if kind == Kind.KEY else Color(1.0, 0.35, 0.3)
	add_child(_light)


func touching(player: Player) -> bool:
	if collected:
		return false
	var d := (player.global_position + Vector2(0, -13)) - global_position
	return absf(d.x) < 11.0 and absf(d.y) < 18.0


func collect() -> void:
	collected = true
	Sfx.play("pickup" if kind == Kind.KEY else "ore", -3.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:y", position.y - 14.0, 0.3)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	if collected:
		return
	_t += delta
	position.y = _base_y + sin(_t * 3.0) * 1.5
	queue_redraw()


func _draw() -> void:
	if kind == Kind.KEY:
		var gold := Color(0.95, 0.75, 0.25)
		draw_arc(Vector2(-4, 0), 3.2, 0, TAU, 12, gold, 1.6)
		draw_line(Vector2(-1, 0), Vector2(7, 0), gold, 1.6)
		draw_line(Vector2(5, 0), Vector2(5, 3), gold, 1.4)
		draw_line(Vector2(7, 0), Vector2(7, 3), gold, 1.4)
		# Glint.
		var g := 0.5 + 0.5 * sin(_t * 5.0)
		draw_circle(Vector2(-5, -1.5), 0.8, Color(1, 1, 0.9, g))
	else:
		if ore_texture != null:
			draw_texture(ore_texture, Vector2(-12, -6))
