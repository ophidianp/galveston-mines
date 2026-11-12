class_name Hud
extends CanvasLayer
## In-game overlay: room/level/score, prompts, hints, the keypad, pause menu
## and the death screen. Built in code so it is easy to read top to bottom.

signal retry_pressed
signal menu_pressed
signal code_submitted(code: String)
signal keypad_closed

var game: Node

var _room_label: Label
var _level_label: Label
var _score_label: Label
var _best_label: Label
var _objective: Label
var _prompt: Label
var _hint: Label
var _banner: Label
var _banner_sub: Label
var _popup: Label
var _chain: Label
var _chain_shown := 0
var _vignette: TextureRect
var _hide_overlay: ColorRect
var _flash: ColorRect

var _keypad_panel: PanelContainer
var _keypad_display: Label
var _keypad_status: Label
var _entered := ""
var keypad_open := false
var _closed_frame := -10

var _pause_panel: Control
var _death_panel: Control
var _death_title: Label
var _death_reason: Label
var _death_stats: Label
var _death_best: Label
var _retry_button: Button

var _hint_tween: Tween
var _popup_tween: Tween


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Game.theme()
	add_child(root)

	# Darkened screen edges.
	_vignette = TextureRect.new()
	_vignette.modulate.a = 0.5
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.texture = _vignette_texture()
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(_vignette)

	_hide_overlay = ColorRect.new()
	_hide_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hide_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_overlay.color = Color(0, 0, 0, 0)
	root.add_child(_hide_overlay)

	# Top-left: room + level.
	_room_label = Game.make_label("ROOM 001", Game.title_font, 40, Color(0.95, 0.82, 0.55))
	_room_label.position = Vector2(28, 18)
	root.add_child(_room_label)
	_level_label = Game.make_label("LEVEL 1", Game.heading_font, 22, Color(0.75, 0.68, 0.58))
	_level_label.position = Vector2(30, 66)
	root.add_child(_level_label)

	# Top-right: score + best.
	_score_label = Game.make_label("0", Game.title_font, 40, Color(0.95, 0.82, 0.55))
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_score_label.offset_left = -420
	_score_label.offset_right = -28
	_score_label.offset_top = 18
	root.add_child(_score_label)
	_best_label = Game.make_label("BEST 0", Game.heading_font, 22, Color(0.75, 0.68, 0.58))
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_best_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_best_label.offset_left = -420
	_best_label.offset_right = -28
	_best_label.offset_top = 66
	root.add_child(_best_label)

	# Puzzle objective (top centre).
	_objective = _centered_label(Game.body_font, 22, Color(1.0, 0.72, 0.4), 22)
	root.add_child(_objective)

	# Interaction prompt (lower centre).
	_prompt = _centered_label(Game.body_font, 24, Color(1, 0.95, 0.85), 0)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -400
	_prompt.offset_right = 400
	_prompt.offset_top = -130
	_prompt.offset_bottom = -90
	root.add_child(_prompt)

	# Hint text (centre, fades).
	_hint = _centered_label(Game.body_font, 24, Color(0.95, 0.9, 0.8), 0)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -560
	_hint.offset_right = 560
	_hint.offset_top = -86
	_hint.offset_bottom = -30
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint.modulate.a = 0.0
	root.add_child(_hint)

	# Level banner.
	_banner = _centered_label(Game.title_font, 84, Color(0.95, 0.75, 0.42), 0)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -600
	_banner.offset_right = 600
	_banner.offset_top = -150
	_banner.offset_bottom = -50
	_banner.modulate.a = 0.0
	root.add_child(_banner)
	_banner_sub = _centered_label(Game.body_font, 24, Color(0.85, 0.8, 0.72), 0)
	_banner_sub.set_anchors_preset(Control.PRESET_CENTER)
	_banner_sub.offset_left = -600
	_banner_sub.offset_right = 600
	_banner_sub.offset_top = -50
	_banner_sub.offset_bottom = -10
	_banner_sub.modulate.a = 0.0
	root.add_child(_banner_sub)

	# Score popups.
	_popup = _centered_label(Game.title_font, 30, Color(1.0, 0.85, 0.45), 0)
	_popup.set_anchors_preset(Control.PRESET_CENTER)
	_popup.offset_left = -500
	_popup.offset_right = 500
	_popup.offset_top = 40
	_popup.offset_bottom = 90
	_popup.modulate.a = 0.0
	root.add_child(_popup)

	# Slide-jump chain counter (bottom left).
	_chain = Game.make_label("", Game.title_font, 30, Color(1.0, 0.75, 0.35))
	_chain.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chain.offset_left = 30
	_chain.offset_right = 500
	_chain.offset_top = -70
	_chain.offset_bottom = -30
	_chain.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_chain.add_theme_constant_override("outline_size", 6)
	root.add_child(_chain)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0, 0, 0, 0)
	root.add_child(_flash)

	_build_keypad(root)
	_build_pause(root)
	_build_death(root)


func _centered_label(font: Font, size: int, color: Color, top: float) -> Label:
	var l := Game.make_label("", font, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.offset_left = -500
	l.offset_right = 500
	l.offset_top = top
	l.offset_bottom = top + 40
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _vignette_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.85))
	g.add_point(0.6, Color(0, 0, 0, 0.1))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.05, 0.5)
	t.width = 256
	t.height = 256
	return t


# --- Updating ----------------------------------------------------------------

func set_stats(room_text: String, level: int, score: int, best: int) -> void:
	_room_label.text = room_text
	_level_label.text = "LEVEL %d" % level
	_score_label.text = str(score)
	_best_label.text = "BEST %d" % maxi(best, score)


func set_chain(chain: int) -> void:
	if chain == _chain_shown:
		return
	if chain > _chain_shown and chain > 0:
		_chain.scale = Vector2(1.25, 1.25)
		create_tween().tween_property(_chain, "scale", Vector2.ONE, 0.2)
	_chain_shown = chain
	_chain.text = "SLIDE JUMP  x%d" % chain if chain > 0 else ""


func set_objective(text: String) -> void:
	_objective.text = text


func set_prompt(text: String) -> void:
	_prompt.text = text


func set_hidden_overlay(hidden: bool) -> void:
	var tw := create_tween()
	tw.tween_property(_hide_overlay, "color:a", 0.45 if hidden else 0.0, 0.25)


func show_hint(text: String, seconds: float = 4.0) -> void:
	_hint.text = text
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint, "modulate:a", 1.0, 0.3)
	_hint_tween.tween_interval(seconds)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.8)


func show_banner(title: String, subtitle: String) -> void:
	_banner.text = title
	_banner_sub.text = subtitle
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.5)
	tw.tween_property(_banner_sub, "modulate:a", 1.0, 0.8)
	tw.chain().tween_interval(2.2)
	tw.chain().tween_property(_banner, "modulate:a", 0.0, 1.0)
	tw.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 1.0)


func popup(text: String) -> void:
	_popup.text = text
	if _popup_tween:
		_popup_tween.kill()
	_popup.modulate.a = 1.0
	_popup.offset_top = 40
	_popup_tween = create_tween().set_parallel(true)
	_popup_tween.tween_property(_popup, "offset_top", 0.0, 1.4)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, 1.4).set_delay(0.5)


func flash(color: Color, hold: float = 0.1, fade: float = 0.8) -> void:
	_flash.color = color
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_property(_flash, "color:a", 0.0, fade)


# --- Keypad --------------------------------------------------------------------

func _build_keypad(root: Control) -> void:
	_keypad_panel = PanelContainer.new()
	_keypad_panel.set_anchors_preset(Control.PRESET_CENTER)
	_keypad_panel.offset_left = -190
	_keypad_panel.offset_right = 190
	_keypad_panel.offset_top = -230
	_keypad_panel.offset_bottom = 230
	_keypad_panel.visible = false
	root.add_child(_keypad_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_keypad_panel.add_child(v)
	var title := Game.make_label("ENTER CODE", Game.heading_font, 30, Color(0.95, 0.8, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_keypad_display = Game.make_label("_ _ _ _", Game.title_font, 54, Color(0.5, 1.0, 0.55))
	_keypad_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_keypad_display)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK"]:
		var b := Button.new()
		b.text = key
		b.custom_minimum_size = Vector2(100, 54)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_keypad_button.bind(key))
		grid.add_child(b)

	_keypad_status = Game.make_label("Type digits, Enter to confirm, Esc to step away", Game.body_font, 15, Color(0.7, 0.65, 0.6))
	_keypad_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keypad_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_keypad_status)


func open_keypad() -> void:
	_entered = ""
	_refresh_keypad()
	_keypad_status.text = "Type digits, Enter to confirm, Esc to step away"
	_keypad_panel.visible = true
	keypad_open = true
	Sfx.play("click")


func close_keypad() -> void:
	if not keypad_open:
		return
	_keypad_panel.visible = false
	keypad_open = false
	_closed_frame = Engine.get_process_frames()
	keypad_closed.emit()


## True on the frame the keypad was closed (so the same E press can't reopen it).
func keypad_just_closed() -> bool:
	return Engine.get_process_frames() - _closed_frame <= 1


func keypad_result(ok: bool) -> void:
	if ok:
		_keypad_status.text = "ACCEPTED"
		_keypad_display.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
		var tw := create_tween()
		tw.tween_interval(0.5)
		tw.tween_callback(close_keypad)
	else:
		Sfx.play("buzz")
		_keypad_status.text = "WRONG CODE"
		_keypad_display.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		var tw := create_tween()
		tw.tween_interval(0.6)
		tw.tween_callback(_reset_keypad_entry)


func _reset_keypad_entry() -> void:
	_entered = ""
	_keypad_display.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
	_refresh_keypad()


func _on_keypad_button(key: String) -> void:
	match key:
		"C":
			_entered = ""
			Sfx.play("click")
		"OK":
			_submit_code()
			return
		_:
			if _entered.length() < 4:
				_entered += key
				Sfx.play("click", 0.0, 1.0 + _entered.length() * 0.05)
	_refresh_keypad()


func _submit_code() -> void:
	if _entered.length() == 4:
		code_submitted.emit(_entered)


func _refresh_keypad() -> void:
	var s := ""
	for i in 4:
		s += (_entered[i] if i < _entered.length() else "_")
		if i < 3:
			s += " "
	_keypad_display.text = s


# --- Pause ---------------------------------------------------------------------

func _build_pause(root: Control) -> void:
	_pause_panel = _make_overlay(root)
	var v := _overlay_box(_pause_panel)
	var t := Game.make_label("PAUSED", Game.title_font, 72, Color(0.95, 0.78, 0.45))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var resume := _button("Resume", v)
	resume.pressed.connect(toggle_pause)
	var menu := _button("Main Menu", v)
	menu.pressed.connect(func() -> void: menu_pressed.emit())


func toggle_pause() -> void:
	if _death_panel.visible:
		return
	var p := not get_tree().paused
	get_tree().paused = p
	_pause_panel.visible = p
	if p:
		Sfx.set_rumble(0.0)
		(_pause_panel.find_child("Resume", true, false) as Button).grab_focus()


# --- Death screen ----------------------------------------------------------------

func _build_death(root: Control) -> void:
	_death_panel = _make_overlay(root)
	var v := _overlay_box(_death_panel)
	_death_title = Game.make_label("YOU DIED", Game.title_font, 86, Color(0.85, 0.18, 0.15))
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_death_title)
	_death_reason = Game.make_label("", Game.body_font, 24, Color(0.85, 0.8, 0.72))
	_death_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_death_reason)
	_death_stats = Game.make_label("", Game.title_font, 34, Color(0.95, 0.82, 0.55))
	_death_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_death_stats)
	_death_best = Game.make_label("", Game.heading_font, 26, Color(0.75, 0.68, 0.58))
	_death_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_death_best)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	v.add_child(spacer)
	_retry_button = _button("Run Again", v)
	_retry_button.pressed.connect(func() -> void: retry_pressed.emit())
	var menu := _button("Main Menu", v)
	menu.pressed.connect(func() -> void: menu_pressed.emit())


func show_death(reason: String, rooms: int, score: int, best: int, new_best: bool) -> void:
	_death_reason.text = reason
	_death_stats.text = "Rooms survived  %d      Score  %d" % [rooms, score]
	if new_best:
		_death_best.text = "NEW HIGH SCORE!  Show your friends."
		_death_best.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	else:
		_death_best.text = "Best %d" % best
	_death_panel.visible = true
	_death_panel.modulate.a = 0.0
	create_tween().tween_property(_death_panel, "modulate:a", 1.0, 0.8)
	_retry_button.grab_focus()


# --- Helpers -------------------------------------------------------------------

func _make_overlay(root: Control) -> Control:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.78)
	bg.visible = false
	root.add_child(bg)
	return bg


func _overlay_box(parent: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(520, 0)
	center.add_child(v)
	return v


func _button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.name = text
	b.text = text
	b.custom_minimum_size = Vector2(360, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.mouse_entered.connect(func() -> void: Sfx.play("blip", -10.0))
	parent.add_child(b)
	return b


# --- Input -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if keypad_open and event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		var code := k.keycode
		if code >= KEY_0 and code <= KEY_9:
			_on_keypad_button(str(code - KEY_0))
		elif code >= KEY_KP_0 and code <= KEY_KP_9:
			_on_keypad_button(str(code - KEY_KP_0))
		elif code == KEY_BACKSPACE:
			if _entered.length() > 0:
				_entered = _entered.substr(0, _entered.length() - 1)
				_refresh_keypad()
		elif code == KEY_ENTER or code == KEY_KP_ENTER:
			_submit_code()
		elif code == KEY_ESCAPE or code == KEY_E:
			close_keypad()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and not _death_panel.visible:
		toggle_pause()
		get_viewport().set_input_as_handled()
