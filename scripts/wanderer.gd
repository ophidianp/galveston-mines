class_name Wanderer
extends Node2D
## The Wanderer: a fast-moving black... thing that tears through the halls.
## It fills the tunnel from floor to ceiling, so the only way to survive is to
## be inside a crawlspace when it passes. Origin = floor level.

var direction := 1.0      # +1 = moving right, -1 = moving left
var speed := 650.0
var end_x := 0.0
var finished := false
var _t := 0.0
var _smoke: CPUParticles2D
var _eye_light: PointLight2D


func _ready() -> void:
	_smoke = CPUParticles2D.new()
	_smoke.amount = 110
	_smoke.lifetime = 0.8
	_smoke.local_coords = false
	_smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_smoke.emission_rect_extents = Vector2(12, 72)
	_smoke.position = Vector2(0, -80)
	_smoke.direction = Vector2(-direction, 0)
	_smoke.spread = 30.0
	_smoke.gravity = Vector2(0, -15)
	_smoke.initial_velocity_min = 20.0
	_smoke.initial_velocity_max = 110.0
	_smoke.texture = MineTheme.shared("soft")
	_smoke.scale_amount_min = 0.6
	_smoke.scale_amount_max = 1.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0, 0, 0, 0.95))
	ramp.set_color(1, Color(0, 0, 0, 0))
	_smoke.color_ramp = ramp
	add_child(_smoke)
	_smoke.emitting = true

	_eye_light = PointLight2D.new()
	_eye_light.texture = Game.light_texture()
	_eye_light.texture_scale = 0.22
	_eye_light.energy = 2.2
	_eye_light.color = Color(1.0, 0.85, 0.85)
	_eye_light.position = Vector2(direction * 6, -96)
	_eye_light.height = 10.0
	add_child(_eye_light)


func _process(delta: float) -> void:
	_t += delta
	position.x += direction * speed * delta
	if (direction > 0.0 and position.x > end_x) or (direction < 0.0 and position.x < end_x):
		finished = true
	queue_redraw()


func _draw() -> void:
	var black := Color(0, 0, 0, 0.94)
	# Trailing streaks.
	for i in 7:
		var a := 0.5 - i * 0.07
		var len := 30.0 + i * 16.0
		var y := -150.0 + i * 21.0 + sin(_t * 30.0 + i) * 4.0
		draw_rect(Rect2(-direction * (10.0 + len) if direction > 0.0 else 10.0, y, len, 9), Color(0, 0, 0, a))
	# Writhing body: a column of jittering blobs from floor to ceiling.
	for i in 15:
		var y := -6.0 - i * 10.5
		var bulge := 1.0 - absf(i - 8.5) / 9.0
		var r := 10.0 + bulge * 9.0 + sin(_t * 22.0 + i * 1.7) * 3.0
		var x := sin(_t * 17.0 + i * 0.9) * 3.0 - direction * float(i % 3) * 2.0
		draw_circle(Vector2(x, y), r, black)
	# Arms / tendrils reaching forward.
	for i in 4:
		var y := -40.0 - i * 26.0
		var reach := 18.0 + sin(_t * 25.0 + i * 2.0) * 8.0
		draw_line(Vector2(0, y), Vector2(direction * reach, y + sin(_t * 31.0 + i) * 6.0), black, 3.0)
	# Eyes.
	var ey := -96.0 + sin(_t * 9.0) * 2.0
	var ex := direction * 6.0
	draw_circle(Vector2(ex - 4, ey), 2.6, Color(1, 1, 1))
	draw_circle(Vector2(ex + 4, ey), 2.6, Color(1, 1, 1))
	draw_circle(Vector2(ex - 4 + direction, ey), 1.0, Color(0.6, 0, 0))
	draw_circle(Vector2(ex + 4 + direction, ey), 1.0, Color(0.6, 0, 0))
