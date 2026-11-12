extends Control
## Title screen: Play, How To Play, Settings, Credits, Quit.

## Edit this list to change the credits roll. [style, text]
## Styles: "title", "head" (section heading), "line", "gap".
const CREDITS := [
	["title", "GALVESTON MINES"],
	["gap", ""],
	["head", "A GAME BY"],
	["studio", "@studio"],
	["gap", ""],
	["head", "DEVELOPMENT TEAM"],
	["line", "Oph"],
	["line", "KK"],
	["line", "PvN"],
	["gap", ""],
	["head", "STARRING"],
	["line", "Bruce Cambell  as himself"],
	["line", "The Wanderer  as  ???"],
	["gap", ""],
	["head", "PIXEL ART"],
	["line", "Bruce, the mine tileset and the hanging lanterns"],
	["gap", ""],
	["head", "FONTS"],
	["line", "Gtek Caverna"],
	["line", "MINER"],
	["gap", ""],
	["head", "SOUND"],
	["line", "Synthesised live in the engine"],
	["gap", ""],
	["head", "INSPIRED BY"],
	["line", "DOORS and GRACE on Roblox"],
	["gap", ""],
	["head", "MADE WITH"],
	["line", "Godot Engine 4  -  godotengine.org"],
	["small", "Godot Engine is MIT licensed. (c) Godot Engine contributors."],
	["gap", ""],
	["gap", ""],
	["head", "THANK YOU FOR PLAYING"],
	["line", "Compare your high score with your friends."],
	["gap", ""],
	["studio", "@studio"],
]

const HOW_TO_PLAY := """[b]THE STORY[/b]
Bruce Cambell was urban exploring when he stumbled into the abandoned Galveston mines. A few steps in, the way out caved in behind him. So Bruce ran, and found he could run and slide forever.

Every room is the same length. Every room ends in an 8-inch-thick metal door. You only build doors like that to keep something in... or to keep something out.

[b]CONTROLS[/b]
[color=#f2c46d]A / D[/color] or arrows  move
[color=#f2c46d]SHIFT[/color]  sprint
[color=#f2c46d]SPACE / W[/color]  jump  (tap for a short hop)
[color=#f2c46d]CTRL / S / C[/color]  slide while running (hold it and you slide forever), crouch while still
[color=#f2c46d]E[/color]  hide in a crawlspace, pull levers, use keypads
[color=#f2c46d]ESC / P[/color]  pause

[b]THE WANDERER[/b]
A fast-moving black... thing that roams the halls. When the [color=#ffb35c]lanterns start swinging[/color] and the ground rumbles, he's coming. Get into a [color=#ffb35c]crawlspace[/color] and press E. There is ALWAYS a crawlspace in the room where he shows up. Stay hidden until the lanterns stop. Deeper down he sometimes comes back for a second pass.

[b]OBSTACLES[/b]
Jump over rubble, slide under low beams, and clear the pits. Jump out of a slide for a slide-jump: it keeps your speed and adds a little more. Hold slide as you land and jump again to chain them and go even faster.

[b]PUZZLE ROOMS[/b]
Some doors are locked (red light). Pull every lever, find the key, or find the two halves of the door code written on the walls and type it into the keypad.

[b]SCORING[/b]
Every new room is worth 100 x the level. Surviving The Wanderer, solving puzzles and grabbing ore give bonuses. Every 10 rooms is a new level: more Wanderers, more puzzle rooms, less warning.

Get the highest score and compare it with your friends!"""

var _main_box: VBoxContainer
var _panels: Dictionary = {}
var _credits_inner: VBoxContainer
var _credits_tween: Tween
var _best_label: Label
var _menu_theme: MineTheme
var _t := 0.0
var _lantern: AnimatedSprite2D
var _glow: TextureRect


func _ready() -> void:
	get_tree().paused = false
	Sfx.set_rumble(0.0)
	theme = Game.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_theme = MineTheme.for_level(1)
	_build_background()
	_build_title()
	_build_main_buttons()
	_build_how_to_play()
	_build_settings()
	_build_credits()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.8)


# --- Background --------------------------------------------------------------

func _build_background() -> void:
	var wall := Control.new()
	wall.set_anchors_preset(Control.PRESET_FULL_RECT)
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wall.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	wall.draw.connect(_draw_wall.bind(wall))
	add_child(wall)

	_glow = TextureRect.new()
	_glow.texture = Game.light_texture()
	_glow.modulate = Color(1.0, 0.6, 0.25, 0.32)
	_glow.size = Vector2(900, 900)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)

	var holder := Node2D.new()
	add_child(holder)
	_lantern = AnimatedSprite2D.new()
	_lantern.sprite_frames = Lantern.build_frames()
	_lantern.scale = Vector2(4, 4)
	_lantern.play(&"swing_fast")
	_lantern.speed_scale = 0.28
	holder.add_child(_lantern)

	var bruce := AnimatedSprite2D.new()
	bruce.sprite_frames = Player.build_frames()
	bruce.scale = Vector2(4, 4)
	bruce.play(&"idle")
	bruce.name = "Bruce"
	holder.add_child(bruce)

	var dust := CPUParticles2D.new()
	dust.name = "Dust"
	dust.amount = 60
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(700, 400)
	dust.direction = Vector2(0.3, 1)
	dust.spread = 40.0
	dust.gravity = Vector2(0, 4)
	dust.initial_velocity_min = 4.0
	dust.initial_velocity_max = 14.0
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 3.0
	dust.color = Color(1.0, 0.85, 0.6, 0.35)
	holder.add_child(dust)
	holder.name = "Holder"

	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.9))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(1.1, 0.45)
	shade.texture = gt
	add_child(shade)
	resized.connect(_layout_background)
	_layout_background()


func _layout_background() -> void:
	var s := size if size.x > 0.0 else Vector2(1280, 720)
	var holder := get_node_or_null("Holder") as Node2D
	if holder == null:
		return
	# Lantern hangs from the ceiling edge; Bruce stands on the floor (4x scale).
	_lantern.position = Vector2(s.x * 0.8, 40 + 128)
	_glow.position = Vector2(s.x * 0.8 - 450, 40 + 160 - 450)
	(holder.get_node("Bruce") as Node2D).position = Vector2(s.x * 0.8 - 40, s.y - 72 - 64)
	queue_redraw()
	(holder.get_node("Dust") as Node2D).position = s / 2.0


func _draw_wall(wall: Control) -> void:
	# The menu shows the first level's art at 4x scale.
	var s := wall.size
	var t := _menu_theme
	var k := 4.0
	wall.draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var w := s.x / k
	var h := s.y / k
	var floor_y := h - 18.0
	wall.draw_texture_rect(t.tex("wall_back"), Rect2(0, 0, w, floor_y), true, Color(0.42, 0.40, 0.42))
	for x in [w * 0.1, w * 0.55]:
		wall.draw_texture_rect(t.tex("post"), Rect2(x, 0, 12, floor_y), true, Color(0.5, 0.47, 0.45))
		wall.draw_texture_rect(t.tex("post"), Rect2(x + 52, 0, 12, floor_y), true, Color(0.5, 0.47, 0.45))
		wall.draw_texture_rect(t.tex("beam"), Rect2(x - 4, 10, 72, 12), true, Color(0.55, 0.5, 0.47))
	wall.draw_texture_rect(t.tex("wall_front"), Rect2(0, -40, w, 48), true, Color(0.5, 0.48, 0.5))
	wall.draw_texture_rect(t.tex("ceiling_edge"), Rect2(0, 6, w, 24), true, Color(0.5, 0.48, 0.5))
	wall.draw_texture_rect(t.tex("wall_front"), Rect2(0, floor_y, w, 40), true, Color(0.55, 0.52, 0.54))
	wall.draw_texture_rect(t.tex("floor_top"), Rect2(0, floor_y - 4, w, 16), true, Color(0.6, 0.57, 0.58))
	wall.draw_texture_rect(MineTheme.shared("rail"), Rect2(0, floor_y - 10, w, 12), true, Color(0.5, 0.5, 0.5))
	wall.draw_texture(MineTheme.shared("minecart"), Vector2(w * 0.36, floor_y - 21), Color(0.55, 0.52, 0.52))
	wall.draw_texture(MineTheme.shared("crate"), Vector2(w * 0.62, floor_y - 18), Color(0.5, 0.48, 0.48))
	wall.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _process(delta: float) -> void:
	_t += delta
	_glow.modulate.a = 0.3 + 0.03 * sin(_t * 3.0) * sin(_t * 1.3)


# --- Title + buttons ------------------------------------------------------------

func _build_title() -> void:
	var title := Game.make_label("GALVESTON\nMINES", Game.title_font, 112, Color(0.96, 0.78, 0.45))
	title.position = Vector2(80, 50)
	title.add_theme_constant_override("line_spacing", -18)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 5)
	title.add_theme_constant_override("shadow_offset_y", 6)
	add_child(title)

	var by := Game.make_label("a  " + Game.STUDIO_NAME + "  game", Game.mono_font, 22, Color(1.0, 0.72, 0.32))
	by.position = Vector2(86, 290)
	add_child(by)

	_best_label = Game.make_label("", Game.heading_font, 22, Color(0.8, 0.72, 0.6))
	_best_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_best_label.offset_left = 86
	_best_label.offset_top = -60
	_best_label.offset_right = 800
	_best_label.offset_bottom = -30
	add_child(_best_label)
	_refresh_best()

	var foot := Game.make_label(Game.STUDIO_NAME + "  " + Game.VERSION, Game.mono_font, 14, Color(0.55, 0.47, 0.38))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.offset_left = -500
	foot.offset_right = -24
	foot.offset_top = -34
	foot.offset_bottom = -12
	add_child(foot)


func _refresh_best() -> void:
	if Game.best_score > 0:
		_best_label.text = "BEST SCORE  %d     FURTHEST ROOM  %d" % [Game.best_score, Game.best_room + 1]
	else:
		_best_label.text = "NO RUNS YET"


func _build_main_buttons() -> void:
	_main_box = VBoxContainer.new()
	_main_box.position = Vector2(86, 350)
	_main_box.add_theme_constant_override("separation", 12)
	add_child(_main_box)
	var play := _menu_button("Play", _main_box)
	play.pressed.connect(_on_play)
	_menu_button("How To Play", _main_box).pressed.connect(_show_panel.bind("how"))
	_menu_button("Settings", _main_box).pressed.connect(_show_panel.bind("settings"))
	_menu_button("Credits", _main_box).pressed.connect(_show_panel.bind("credits"))
	_menu_button("Quit", _main_box).pressed.connect(func() -> void: get_tree().quit())
	play.grab_focus.call_deferred()


func _menu_button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 52)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.mouse_entered.connect(func() -> void: Sfx.play("blip", -10.0))
	b.focus_entered.connect(func() -> void: Sfx.play("blip", -14.0))
	parent.add_child(b)
	return b


func _on_play() -> void:
	Sfx.play("select")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file("res://scenes/game.tscn"))


# --- Panels ----------------------------------------------------------------------

func _make_panel(key: String, heading: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 470
	panel.offset_top = 60
	panel.offset_right = -60
	panel.offset_bottom = -60
	panel.visible = false
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var h := Game.make_label(heading, Game.heading_font, 40, Color(0.96, 0.78, 0.45))
	v.add_child(h)
	_panels[key] = panel
	return v


func _add_back(v: VBoxContainer) -> void:
	var back := Button.new()
	back.text = "Back"
	back.name = "Back"
	back.custom_minimum_size = Vector2(200, 48)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(_hide_panels)
	v.add_child(back)


func _show_panel(key: String) -> void:
	Sfx.play("select", -6.0)
	for k in _panels:
		(_panels[k] as Control).visible = k == key
	_main_box.modulate.a = 0.35
	if key == "credits":
		_roll_credits()
	var panel := _panels[key] as Control
	var back := panel.find_child("Back", true, false) as Button
	if back != null:
		back.grab_focus()
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.25)


func _hide_panels() -> void:
	Sfx.play("blip", -8.0)
	for k in _panels:
		(_panels[k] as Control).visible = false
	_main_box.modulate.a = 1.0
	if _credits_tween:
		_credits_tween.kill()
	(_main_box.get_child(0) as Button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		for k in _panels:
			if (_panels[k] as Control).visible:
				_hide_panels()
				get_viewport().set_input_as_handled()
				return


func _build_how_to_play() -> void:
	var v := _make_panel("how", "HOW TO PLAY")
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.text = HOW_TO_PLAY
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_override("normal_font", Game.body_font)
	text.add_theme_font_override("bold_font", Game.heading_font)
	text.add_theme_font_size_override("normal_font_size", 19)
	text.add_theme_font_size_override("bold_font_size", 22)
	text.add_theme_color_override("default_color", Color(0.86, 0.80, 0.70))
	v.add_child(text)
	_add_back(v)


func _build_settings() -> void:
	var v := _make_panel("settings", "SETTINGS")

	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 20)
	var vol_label := Game.make_label("Volume", Game.heading_font, 24)
	vol_label.custom_minimum_size = Vector2(220, 0)
	vol_row.add_child(vol_label)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Game.master_volume
	vol.custom_minimum_size = Vector2(320, 32)
	vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol.value_changed.connect(_on_volume_changed)
	vol_row.add_child(vol)
	v.add_child(vol_row)

	var full := CheckButton.new()
	full.text = "Fullscreen"
	full.button_pressed = Game.fullscreen
	full.add_theme_font_override("font", Game.heading_font)
	full.add_theme_font_size_override("font_size", 24)
	full.toggled.connect(_on_fullscreen_toggled)
	v.add_child(full)

	var shake := CheckButton.new()
	shake.text = "Screen shake"
	shake.button_pressed = Game.screen_shake
	shake.add_theme_font_override("font", Game.heading_font)
	shake.add_theme_font_size_override("font_size", 24)
	shake.toggled.connect(_on_shake_toggled)
	v.add_child(shake)

	var reset := Button.new()
	reset.text = "Reset High Score"
	reset.custom_minimum_size = Vector2(300, 48)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(_on_reset_best)
	v.add_child(reset)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	_add_back(v)


func _on_volume_changed(value: float) -> void:
	Game.master_volume = value
	Game.apply_settings()
	Game.save_data()
	Sfx.play("blip", -8.0)


func _on_fullscreen_toggled(on: bool) -> void:
	Game.fullscreen = on
	Game.apply_settings()
	Game.save_data()


func _on_shake_toggled(on: bool) -> void:
	Game.screen_shake = on
	Game.save_data()


func _on_reset_best() -> void:
	Game.best_score = 0
	Game.best_room = 0
	Game.save_data()
	_refresh_best()
	Sfx.play("buzz")


func _build_credits() -> void:
	var v := _make_panel("credits", "CREDITS")
	var clip := Control.new()
	clip.clip_contents = true
	clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip.name = "Clip"
	v.add_child(clip)
	_credits_inner = VBoxContainer.new()
	_credits_inner.add_theme_constant_override("separation", 6)
	clip.add_child(_credits_inner)
	for entry in CREDITS:
		var style: String = entry[0]
		var text: String = entry[1]
		var l: Label
		match style:
			"title":
				l = Game.make_label(text, Game.title_font, 64, Color(0.96, 0.78, 0.45))
			"studio":
				l = Game.make_label(text.replace("@studio", Game.STUDIO_NAME), Game.mono_font, 36, Color(1.0, 0.72, 0.32))
			"head":
				l = Game.make_label(text, Game.heading_font, 22, Color(0.7, 0.6, 0.48))
			"small":
				l = Game.make_label(text, Game.body_font, 15, Color(0.6, 0.55, 0.5))
			"gap":
				l = Game.make_label(" ", Game.body_font, 20)
			_:
				l = Game.make_label(text, Game.body_font, 26, Color(0.92, 0.88, 0.8))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_credits_inner.add_child(l)
	_add_back(v)


func _roll_credits() -> void:
	if _credits_tween:
		_credits_tween.kill()
	await get_tree().process_frame
	var clip := _credits_inner.get_parent() as Control
	_credits_inner.size = Vector2(clip.size.x, _credits_inner.get_combined_minimum_size().y)
	var h := _credits_inner.size.y
	_credits_inner.position = Vector2(0, clip.size.y)
	_credits_tween = create_tween().set_loops()
	_credits_tween.tween_property(_credits_inner, "position:y", -h, (clip.size.y + h) / 55.0).from(clip.size.y)
