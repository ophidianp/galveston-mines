extends Node
## Autoload "Game": save data, settings, shared fonts, the UI theme and a few
## helpers every scene uses. Lives for the whole session.

const SAVE_PATH := "user://galveston_save.cfg"
const STUDIO_NAME := "~/ophidianp/studios"
const VERSION := "v0.1.0"

# --- Save data -------------------------------------------------------------
var best_score: int = 0
var best_room: int = 0
var runs_played: int = 0
var seen_wanderer_hint: bool = false

# --- Settings --------------------------------------------------------------
var master_volume: float = 0.8
var fullscreen: bool = false
var screen_shake: bool = true

# --- Shared resources ------------------------------------------------------
var title_font: Font      # Gtek Caverna (has every ASCII glyph)
var heading_font: Font    # MINER (letters, digits and . , ! ? only)
var body_font: Font       # system sans-serif for long text
var mono_font: Font       # system monospace for the studio terminal look

var _light_tex: Texture2D
var _cone_tex: Texture2D
var _theme: Theme


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	title_font = load("res://assets/fonts/Gtek Caverna.ttf")
	heading_font = load("res://assets/fonts/MINER.ttf")

	var body := SystemFont.new()
	body.font_names = PackedStringArray(["Segoe UI", "Helvetica Neue", "Arial", "sans-serif"])
	body_font = body

	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Courier New", "monospace"])
	mono_font = mono

	load_data()
	apply_settings()


# --- Persistence -----------------------------------------------------------

func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_score = int(cfg.get_value("save", "best_score", 0))
	best_room = int(cfg.get_value("save", "best_room", 0))
	runs_played = int(cfg.get_value("save", "runs_played", 0))
	seen_wanderer_hint = bool(cfg.get_value("save", "seen_wanderer_hint", false))
	master_volume = float(cfg.get_value("settings", "master_volume", 0.8))
	fullscreen = bool(cfg.get_value("settings", "fullscreen", false))
	screen_shake = bool(cfg.get_value("settings", "screen_shake", true))


func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("save", "best_score", best_score)
	cfg.set_value("save", "best_room", best_room)
	cfg.set_value("save", "runs_played", runs_played)
	cfg.set_value("save", "seen_wanderer_hint", seen_wanderer_hint)
	cfg.set_value("settings", "master_volume", master_volume)
	cfg.set_value("settings", "fullscreen", fullscreen)
	cfg.set_value("settings", "screen_shake", screen_shake)
	cfg.save(SAVE_PATH)


func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## Records a finished run. Returns true when it beat the high score.
func submit_run(score: int, rooms: int) -> bool:
	runs_played += 1
	var is_best := score > best_score
	if is_best:
		best_score = score
	best_room = maxi(best_room, rooms)
	save_data()
	return is_best


# --- Shared visuals --------------------------------------------------------

## Soft round light used by every PointLight2D (radius 128px at scale 1).
func light_texture() -> Texture2D:
	if _light_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.45))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 256
		t.height = 256
		_light_tex = t
	return _light_tex


## Headlamp beam: a soft cone pointing right from the texture's centre.
func cone_texture() -> Texture2D:
	if _cone_tex == null:
		var size := 256
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var c := size / 2.0
		for y in size:
			for x in size:
				var dx := x - c
				var dy := y - c
				var dist := sqrt(dx * dx + dy * dy) / c
				var a := 0.0
				if dx > 0.0 and dist < 1.0:
					var ang := absf(atan2(dy, dx))
					var cone := clampf(1.0 - (ang - 0.22) / 0.16, 0.0, 1.0)
					a = cone * pow(1.0 - dist, 1.3)
				# A little spill around the lamp itself.
				a = maxf(a, clampf(1.0 - dist * 9.0, 0.0, 1.0) * 0.6)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_cone_tex = ImageTexture.create_from_image(img)
	return _cone_tex


func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = heading_font
	t.default_font_size = 26

	var normal := _box(Color(0.07, 0.055, 0.05, 0.88), Color(0.42, 0.29, 0.16))
	var hover := _box(Color(0.17, 0.10, 0.05, 0.95), Color(0.96, 0.62, 0.24))
	var pressed := _box(Color(0.27, 0.15, 0.06, 1.0), Color(1.0, 0.78, 0.36))
	var focus := _box(Color(0, 0, 0, 0), Color(0.96, 0.62, 0.24))
	focus.draw_center = false
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", normal)
	t.set_color("font_color", "Button", Color(0.86, 0.80, 0.70))
	t.set_color("font_hover_color", "Button", Color(1.0, 0.86, 0.56))
	t.set_color("font_pressed_color", "Button", Color(1.0, 0.92, 0.72))
	t.set_color("font_focus_color", "Button", Color(1.0, 0.86, 0.56))
	t.set_color("font_color", "Label", Color(0.86, 0.80, 0.70))
	t.set_color("font_color", "CheckButton", Color(0.86, 0.80, 0.70))
	t.set_color("font_hover_color", "CheckButton", Color(1.0, 0.86, 0.56))
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.035, 0.03, 0.035, 0.94), Color(0.42, 0.29, 0.16)))
	_theme = t
	return t


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_content_margin_all(12)
	s.content_margin_left = 24
	s.content_margin_right = 24
	return s


## Quick label factory used by the menus and HUD.
func make_label(text: String, font: Font, size: int, color := Color(0.86, 0.80, 0.70)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
