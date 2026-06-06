extends Control
## 简单主菜单：标题 + 开始游戏 / 退出。从齿轮菜单「回到主菜单」进入。

const BASE_W := 1920.0
const BASE_H := 1080.0
const INK := Color("3a352f")
const BG := Color("efe7d8")

var pixel_font: Font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	box.position = Vector2(BASE_W * 0.5 - 200, 360)
	box.custom_minimum_size = Vector2(400, 0)
	add_child(box)

	var title := Label.new()
	title.text = "StartX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(title, 72)
	title.add_theme_color_override("font_color", INK)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "像素企业经营"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(subtitle, 26)
	subtitle.add_theme_color_override("font_color", Color("777067"))
	box.add_child(subtitle)

	box.add_child(_make_button("新开始游戏", Color("aecbe0"), _start_game))
	box.add_child(_make_button("新开始游戏（DEV）", Color("b9d6c2"), _start_game_dev))
	box.add_child(_make_button("退出", Color("d8b3b0"), _quit))

func _make_button(text: String, fill: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	_font(b, 28)
	_style(b, fill)
	b.pressed.connect(cb)
	return b

func _start_game() -> void:
	GameState.dev_mode = false
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _start_game_dev() -> void:
	GameState.dev_mode = true
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _quit() -> void:
	get_tree().quit()

func _font(c: Control, font_size: int) -> void:
	c.add_theme_font_override("font", _ui_font())
	c.add_theme_font_size_override("font_size", font_size)

func _ui_font() -> Font:
	if pixel_font != null:
		return pixel_font
	var candidates := [
		"res://fonts/SmileySans-Oblique.ttf",
		"res://fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/Users/frankfan/Library/Fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/System/Library/Fonts/STHeiti Medium.ttc",
		"/System/Library/Fonts/PingFang.ttc",
	]
	for path in candidates:
		if not FileAccess.file_exists(path):
			continue
		var ff := FontFile.new()
		ff.load_dynamic_font(path)
		ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		ff.generate_mipmaps = true
		pixel_font = ff
		return pixel_font
	pixel_font = ThemeDB.fallback_font
	return pixel_font

func _style(b: Button, fill: Color) -> void:
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		var c := fill
		if state == "hover":
			c = fill.lightened(0.10)
		elif state == "pressed":
			c = fill.darkened(0.08)
		sb.bg_color = c
		sb.set_corner_radius_all(10)
		sb.border_color = INK
		sb.set_border_width_all(2)
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		b.add_theme_stylebox_override(state, sb)
