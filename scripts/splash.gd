extends Control
## Startup screen: the ~/ophidianp/studios logo typed out terminal-style,
## then "presents", then off to the main menu. Any key / click skips.

const AMBER := Color(1.0, 0.72, 0.32)
const DIM := Color(0.55, 0.45, 0.32)

var _boot: Label
var _logo: Label
var _presents: Label
var _cursor_on := true
var _cursor_t := 0.0
var _typed := ""
var _skipped := false
var _leaving := false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.01, 0.012)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_boot = Game.make_label("", Game.mono_font, 18, DIM)
	_boot.position = Vector2(48, 40)
	add_child(_boot)

	_logo = Game.make_label("", Game.mono_font, 64, AMBER)
	_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.offset_left = -640
	_logo.offset_right = 640
	_logo.offset_top = -60
	_logo.offset_bottom = 30
	_logo.add_theme_color_override("font_shadow_color", Color(1.0, 0.55, 0.15, 0.35))
	_logo.add_theme_constant_override("shadow_offset_x", 0)
	_logo.add_theme_constant_override("shadow_offset_y", 0)
	_logo.add_theme_constant_override("shadow_outline_size", 18)
	add_child(_logo)

	_presents = Game.make_label("presents", Game.mono_font, 24, DIM)
	_presents.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_presents.set_anchors_preset(Control.PRESET_CENTER)
	_presents.offset_left = -400
	_presents.offset_right = 400
	_presents.offset_top = 50
	_presents.offset_bottom = 90
	_presents.modulate.a = 0.0
	add_child(_presents)

	var scan := Control.new()
	scan.set_anchors_preset(Control.PRESET_FULL_RECT)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scan.draw.connect(_draw_scanlines.bind(scan))
	add_child(scan)

	_run()


func _draw_scanlines(scan: Control) -> void:
	for y in range(0, int(scan.size.y), 4):
		scan.draw_line(Vector2(0, y), Vector2(scan.size.x, y), Color(0, 0, 0, 0.25), 1.0)


func _process(delta: float) -> void:
	_cursor_t += delta
	if _cursor_t > 0.45:
		_cursor_t = 0.0
		_cursor_on = not _cursor_on
	_logo.text = _typed + ("_" if _cursor_on else " ")


func _run() -> void:
	var boot_lines := [
		"galveston_mines %s" % Game.VERSION,
		"mounting /mines/galveston ......... ok",
		"checking lanterns ................. ok",
		"locating exit ..................... not found",
	]
	for line in boot_lines:
		_boot.text += line + "\n"
		Sfx.play("tick", -14.0)
		if await _wait(0.22):
			return
	if await _wait(0.4):
		return

	for ch in Game.STUDIO_NAME:
		_typed += ch
		Sfx.play("tick", -6.0, randf_range(0.9, 1.2))
		if await _wait(0.075):
			return
	if await _wait(0.5):
		return
	create_tween().tween_property(_presents, "modulate:a", 1.0, 0.8)
	if await _wait(2.2):
		return
	_go_to_menu()


## Waits, returning true if the player skipped in the meantime.
func _wait(seconds: float) -> bool:
	await get_tree().create_timer(seconds).timeout
	return _skipped


func _input(event: InputEvent) -> void:
	if _leaving:
		return
	var pressed: bool = (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if pressed:
		_skipped = true
		_go_to_menu()


func _go_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
