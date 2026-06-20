extends Control
## Main menu: generated office artwork with independently animated SVG overlays.

const INK := Color("3a352f")
const CREAM := Color("f7f0e2")
const BLUE := Color("aecbe0")
const SAGE := Color("b9d6c2")
const ROSE := Color("d8b3b0")
const GOLD := Color("d9c79a")

@onready var brand: Control = $Brand
@onready var logo: TextureRect = $Brand/Logo
@onready var logo_gloss: TextureRect = $Brand/LogoGloss
@onready var chart_a: TextureRect = $Ambient/ChartA
@onready var chart_b: TextureRect = $Ambient/ChartB
@onready var lamp_glow: TextureRect = $Ambient/LampGlow
@onready var steam_1: TextureRect = $Ambient/Steam1
@onready var steam_2: TextureRect = $Ambient/Steam2

@onready var start_button: Button = $Menu/StartButton
@onready var continue_button: Button = $Menu/ContinueButton
@onready var growth_button: Button = $Menu/GrowthButton
@onready var settings_button: Button = $Menu/SettingsButton
@onready var credits_button: Button = $Menu/CreditsButton
@onready var quit_button: Button = $Menu/QuitButton
@onready var test_start_button: Button = $Menu/TestStartButton

@onready var overlay_dim: ColorRect = $OverlayDim
@onready var settings_panel: PanelContainer = $SettingsPanel
@onready var settings_close: Button = $SettingsPanel/Margin/Content/Header/CloseButton
@onready var volume_slider: HSlider = $SettingsPanel/Margin/Content/VolumeRow/Slider
@onready var volume_value: Label = $SettingsPanel/Margin/Content/VolumeRow/Value
@onready var music_volume_slider: HSlider = $SettingsPanel/Margin/Content/MusicVolumeRow/Slider
@onready var music_volume_value: Label = $SettingsPanel/Margin/Content/MusicVolumeRow/Value
@onready var fullscreen_toggle: CheckButton = $SettingsPanel/Margin/Content/Fullscreen
@onready var reduce_motion_toggle: CheckButton = $SettingsPanel/Margin/Content/ReduceMotion
var display_mode_btn: OptionButton = null
var resolution_btn: OptionButton = null
var clarity_btn: OptionButton = null
var bias_btn: OptionButton = null
var background_mode_btn: OptionButton = null

@onready var developer_panel: PanelContainer = $DeveloperPanel
@onready var developer_close: Button = $DeveloperPanel/Margin/Content/Header/CloseButton
@onready var dev_button: Button = $DeveloperPanel/Margin/Content/DevButton

@onready var credits_panel: Control = $CreditsPanel
@onready var credits_reel: VBoxContainer = $CreditsPanel/Reel
@onready var credits_hint: Label = $CreditsPanel/Hint
@onready var credits_skip: Button = $CreditsPanel/SkipButton

var pixel_font: Font
var credits_font: Font
var _motion_tweens: Array[Tween] = []
var _steam_origins: Dictionary = {}
var _credits_speed := 0.0
var _credits_paused := false
var _credits_dragging := false
var _credits_drag_y := 0.0
var _credits_reel_y := 0.0
var _credits_drag_distance := 0.0
var _starting_transition := false

func _ready() -> void:
	CursorManager.reset()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style_interface()
	_connect_interface()
	_sync_settings()
	_build_credits()
	_layout_responsive()

	_steam_origins[steam_1] = steam_1.position
	_steam_origins[steam_2] = steam_2.position
	brand.pivot_offset = brand.size * 0.5
	_setup_logo_gloss()
	# _setup_background_squiggllevision()

	Settings.display_settings_changed.connect(_on_display_settings_changed)
	Settings.sfx_volume_changed.connect(_on_sfx_volume_changed)
	Settings.music_volume_changed.connect(_on_music_volume_changed)
	_build_extra_settings()
	Settings.card_clarity_changed.connect(_on_card_clarity_changed)
	Settings.mipmap_bias_changed.connect(_on_mipmap_bias_changed)
	Settings.background_mode_changed.connect(_on_background_mode_changed)
	_refresh_motion()
	start_button.grab_focus.call_deferred()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_setup_gradient_overlay()

func _setup_gradient_overlay() -> void:
	var overlay := TextureRect.new()
	overlay.name = "LeftGradientOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var grad := Gradient.new()
	grad.offsets = [0.0, 1.0]
	grad.colors = [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
	
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 0.0)
	
	overlay.texture = tex
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 0.58333
	overlay.anchor_bottom = 1.0
	overlay.offset_left = 0
	overlay.offset_top = 0
	overlay.offset_right = 0
	overlay.offset_bottom = 0
	
	var ambient_node := get_node_or_null("Ambient")
	if ambient_node != null:
		var idx := ambient_node.get_index()
		add_child(overlay)
		move_child(overlay, idx + 1)
	else:
		add_child(overlay)

func _on_viewport_size_changed() -> void:
	_layout_responsive()
	_steam_origins[steam_1] = steam_1.position
	_steam_origins[steam_2] = steam_2.position

func _screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _layout_responsive() -> void:
	var viewport_size := get_viewport_rect().size
	var extra := viewport_size - Vector2(1920.0, 1080.0)

	brand.position = Vector2(54.0, 158.0 + extra.y * 0.5)
	$Menu.position = Vector2(126.0, 446.0 + extra.y * 0.5)
	$Footer.position = Vector2(128.0, 976.0 + extra.y)

	settings_panel.position = Vector2(650.0, 208.0) + extra * 0.5
	developer_panel.position = Vector2(680.0, 264.0) + extra * 0.5

	credits_reel.position.x = 410.0 + extra.x * 0.5
	credits_hint.position = Vector2(610.0 + extra.x * 0.5, 1016.0 + extra.y)
	credits_skip.position = Vector2(1740.0 + extra.x, 1004.0 + extra.y)

	steam_1.position = Vector2(1028.0 + extra.x * 0.535, 314.0 + extra.y * 0.291)
	steam_2.position = Vector2(1362.0 + extra.x * 0.709, 648.0 + extra.y * 0.600)

func _process(delta: float) -> void:
	_update_menu_cursor()
	if not credits_panel.visible or _credits_paused or _credits_dragging:
		return
	credits_reel.position.y -= _credits_speed * delta
	if credits_reel.position.y <= -credits_reel.size.y + 760.0:
		_credits_paused = true

func _update_menu_cursor() -> void:
	if _credits_dragging:
		CursorManager.set_state("drag")
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and CursorManager.is_interactive_control(hovered):
		CursorManager.set_state("hover")
	else:
		CursorManager.set_state("default")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_D and (event.ctrl_pressed or event.meta_pressed):
		_toggle_developer()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and (settings_panel.visible or developer_panel.visible or credits_panel.visible):
		_close_overlays()
		get_viewport().set_input_as_handled()

func _style_interface() -> void:
	$Menu.add_theme_constant_override("separation", 12)
	_font($Footer, 20)
	$Footer.add_theme_color_override("font_color", Color("6f675e"))

	_font($SettingsPanel/Margin/Content/Header/Title, 34)
	_font($SettingsPanel/Margin/Content/VolumeRow/Label, 22)
	_font(volume_value, 20)
	_font($SettingsPanel/Margin/Content/MusicVolumeRow/Label, 22)
	_font(music_volume_value, 20)
	_font(fullscreen_toggle, 22)
	_font(reduce_motion_toggle, 22)
	_font($SettingsPanel/Margin/Content/MotionHint, 16)
	$SettingsPanel/Margin/Content/Header/Title.add_theme_color_override("font_color", INK)
	$SettingsPanel/Margin/Content/VolumeRow/Label.add_theme_color_override("font_color", INK)
	volume_value.add_theme_color_override("font_color", INK)
	$SettingsPanel/Margin/Content/MusicVolumeRow/Label.add_theme_color_override("font_color", INK)
	music_volume_value.add_theme_color_override("font_color", INK)
	$SettingsPanel/Margin/Content/MotionHint.add_theme_color_override("font_color", Color("777067"))

	_font($DeveloperPanel/Margin/Content/Header/Title, 34)
	_font($DeveloperPanel/Margin/Content/Hint, 17)
	_font($DeveloperPanel/Margin/Content/Shortcut, 15)
	$DeveloperPanel/Margin/Content/Header/Title.add_theme_color_override("font_color", INK)
	$DeveloperPanel/Margin/Content/Hint.add_theme_color_override("font_color", Color("777067"))
	$DeveloperPanel/Margin/Content/Shortcut.add_theme_color_override("font_color", Color("777067"))

	_credits_font_apply(credits_hint, 15)
	credits_hint.add_theme_color_override("font_color", Color(0.96, 0.90, 0.78, 0.55))

	settings_panel.add_theme_stylebox_override("panel", _panel_style())
	developer_panel.add_theme_stylebox_override("panel", _panel_style())

	_prepare_menu_text_button(start_button, 47)
	_prepare_menu_text_button(continue_button, 40)
	_prepare_menu_text_button(growth_button, 40)
	_prepare_menu_text_button(settings_button, 40)
	_prepare_menu_text_button(credits_button, 40)
	_prepare_menu_text_button(quit_button, 40)
	_prepare_menu_text_button(test_start_button, 26)
	continue_button.add_theme_color_override("font_disabled_color", Color("9b958c"))
	growth_button.add_theme_color_override("font_color", Color("777067"))
	growth_button.add_theme_color_override("font_hover_color", Color("777067"))
	growth_button.add_theme_color_override("font_focus_color", Color("777067"))
	test_start_button.add_theme_color_override("font_color", Color("8b8780"))
	test_start_button.add_theme_color_override("font_hover_color", Color("9a9690"))
	test_start_button.add_theme_color_override("font_focus_color", Color("9a9690"))
	test_start_button.add_theme_color_override("font_pressed_color", Color("77736d"))
	_prepare_button(settings_close, GOLD, 18)
	_prepare_button(developer_close, GOLD, 18)
	_prepare_credits_skip()
	_prepare_button(dev_button, SAGE, 22)

	for toggle in [fullscreen_toggle, reduce_motion_toggle]:
		toggle.add_theme_color_override("font_color", INK)
		toggle.add_theme_color_override("font_hover_color", INK)
		toggle.add_theme_color_override("font_pressed_color", INK)

func _prepare_menu_text_button(button: Button, font_size: int) -> void:
	_font(button, font_size)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color("5b8295"))
	button.add_theme_color_override("font_focus_color", Color("5b8295"))
	button.add_theme_color_override("font_pressed_color", Color("3f6f85"))
	button.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0))
	button.add_theme_constant_override("outline_size", 0)

	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 8
	empty.content_margin_right = 8
	empty.content_margin_top = 4
	empty.content_margin_bottom = 4
	for state in ["normal", "hover", "focus", "pressed"]:
		button.add_theme_stylebox_override(state, empty)
	button.add_theme_stylebox_override("disabled", empty)

	button.resized.connect(_update_button_pivot.bind(button))
	button.mouse_entered.connect(_set_button_emphasis.bind(button, true))
	button.mouse_exited.connect(_set_button_emphasis.bind(button, false))
	button.focus_entered.connect(_set_button_emphasis.bind(button, true))
	button.focus_exited.connect(_set_button_emphasis.bind(button, false))
	_update_button_pivot(button)

func _connect_interface() -> void:
	start_button.pressed.connect(_start_game)
	growth_button.pressed.connect(_on_growth_pressed)
	settings_button.pressed.connect(_toggle_settings)
	credits_button.pressed.connect(_toggle_credits)
	quit_button.pressed.connect(_quit)
	test_start_button.pressed.connect(_start_game_test)
	settings_close.pressed.connect(_close_overlays)
	developer_close.pressed.connect(_close_overlays)
	credits_skip.pressed.connect(_close_overlays)
	credits_panel.gui_input.connect(_on_credits_input)
	dev_button.pressed.connect(_start_game_dev)
	volume_slider.value_changed.connect(_on_volume_changed)
	music_volume_slider.value_changed.connect(_on_music_volume_changed_by_user)

func _prepare_button(button: Button, fill: Color, font_size: int) -> void:
	_font(button, font_size)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.32))
	button.add_theme_constant_override("outline_size", 1)

	for state in ["normal", "hover", "focus", "pressed"]:
		var sb := StyleBoxFlat.new()
		var color := fill
		if state == "normal":
			color.a = 0.88
		elif state in ["hover", "focus"]:
			color = fill.lightened(0.10)
			color.a = 0.96
		else:
			color = fill.darkened(0.08)
			color.a = 0.98
		sb.bg_color = color
		sb.border_color = INK
		sb.set_border_width_all(3 if state in ["hover", "focus"] else 2)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		button.add_theme_stylebox_override(state, sb)

	button.resized.connect(_update_button_pivot.bind(button))
	button.mouse_entered.connect(_set_button_emphasis.bind(button, true))
	button.mouse_exited.connect(_set_button_emphasis.bind(button, false))
	button.focus_entered.connect(_set_button_emphasis.bind(button, true))
	button.focus_exited.connect(_set_button_emphasis.bind(button, false))
	_update_button_pivot(button)

func _update_button_pivot(button: Button) -> void:
	button.pivot_offset = button.size * 0.5

func _set_button_emphasis(button: Button, emphasized: bool) -> void:
	button.scale = Vector2.ONE * (1.025 if emphasized else 1.0)

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.94, 0.87, 0.98)
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0.12, 0.10, 0.08, 0.32)
	sb.shadow_size = 18
	return sb

func _prepare_credits_skip() -> void:
	_credits_font_apply(credits_skip, 16)
	credits_skip.add_theme_color_override("font_color", Color("ffe28a"))
	credits_skip.add_theme_color_override("font_hover_color", Color.WHITE)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.62 if state == "normal" else 0.82)
		sb.border_color = Color("ffe28a")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		credits_skip.add_theme_stylebox_override(state, sb)

func _credits_font_apply(control: Control, size: int) -> void:
	control.add_theme_font_override("font", _credits_ui_font())
	control.add_theme_font_size_override("font_size", size)
	if control is Label:
		control.add_theme_constant_override("line_spacing", 6)

func _credits_ui_font() -> Font:
	if credits_font != null:
		return credits_font
	var ff: FontFile
	var loaded := preload("res://fonts/zpix.ttf")
	if loaded is FontFile:
		ff = (loaded as FontFile).duplicate() as FontFile
	else:
		ff = FontFile.new()
		ff.load_dynamic_font("res://fonts/zpix.ttf")
	ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	credits_font = ff
	return credits_font

func _build_credits() -> void:
	_add_credits_title(["A FRANK FAN", "PRODUCTION"], 56, Color("ffe28a"))
	_add_credits_spacer()
	_add_credits_title(["制 作 组", "— STAFF ROLL —"], 40, Color("ffe28a"))
	_add_credits_spacer()
	_add_credits_role("总 监 制", [["Executive Producer", "Frank Fan"]])
	_add_credits_role("执 行 制 作", [["Producer", "Frank Fan"]])
	_add_credits_spacer()
	_add_credits_role("游戏设计 · GAME DESIGN", [
		["主策划 · Lead Design", "Frank Fan"],
		["系统策划 · Systems", "Frank Fan"],
		["数值策划 · Balance", "Frank Fan"],
		["关卡设计 · Level", "Frank Fan"],
		["剧情编剧 · Narrative", "Frank Fan"],
	])
	_add_credits_spacer()
	_add_credits_role("美术 · ART", [
		["美术总监 · Art Director", "Frank Fan"],
		["角色像素 · Character Pixel", "Frank Fan"],
		["UI 设计 · UI Design", "Frank Fan"],
		["图标绘制 · Iconography", "Frank Fan"],
		["特效设计 · VFX", "Frank Fan"],
	])
	_add_credits_spacer()
	_add_credits_role("音频 · AUDIO", [
		["音乐总监 · Music Director", "Frank Fan"],
		["作曲 · Composer", "Frank Fan"],
		["音效 · Sound Design", "Frank Fan"],
		["混音 · Mixing", "Frank Fan"],
	])
	_add_credits_spacer()
	_add_credits_role("程序 · ENGINEERING", [
		["主程序 · Lead Engineer", "Frank Fan"],
		["战斗系统 · Battle System", "Frank Fan"],
		["UI 工程 · UI Engineering", "Frank Fan"],
		["工具链 · Tooling", "Frank Fan"],
		["AI 协作 · AI Pair", "Codex / Claude"],
	])
	_add_credits_spacer()
	_add_credits_role("测试 · QA", [
		["首席测试 · Lead QA", "你"],
		["压力测试 · Stress Test", "你"],
		["平衡测试 · Playtest", "你"],
		["Bug Hunter", "你"],
	])
	_add_credits_spacer()
	_add_credits_role("发行 · PUBLISHING", [
		["发行 · Publisher", "也许是你"],
		["市场推广 · Marketing", "也许是你"],
		["社区运营 · Community", "也许是你"],
		["商务合作 · Business Dev", "也许是你"],
	])
	_add_credits_spacer()
	_add_credits_title(["— 特 别 鸣 谢 —", "SPECIAL THANKS"], 38, Color("ffe28a"))
	_add_credits_list([
		"Vite · React · Phaser",
		"TakWolf / Fusion Pixel 字体",
		"Balatro · Slay the Spire · 炉石",
		"所有还在熬夜的独立游戏作者",
	])
	_add_credits_spacer()
	_add_credits_title(["— 谨以此局献给 —"], 38, Color("ffe28a"))
	_add_credits_list([
		"每一位还在加班的 CEO",
		"每一位刚被裁的员工",
		"每一位「下一关再说」的赌徒",
	])
	_add_credits_spacer()
	_add_credits_spacer()
	_add_credits_finale([
		["主角 · PROTAGONIST", "Frank"],
		["玩家 · PLAYER", "你"],
		["未来 · FUTURE", "也许是你"],
	])
	_add_credits_spacer()
	_add_credits_title(["— FIN —"], 32, Color("b8a47a"))

func _add_credits_title(lines: Array, size: int, color: Color) -> void:
	for text in lines:
		var label := Label.new()
		label.text = String(text)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(1100, size + 18)
		_credits_font_apply(label, size)
		label.add_theme_color_override("font_color", color)
		credits_reel.add_child(label)

func _add_credits_role(heading: String, rows: Array) -> void:
	var title := Label.new()
	title.text = heading
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(1100, 54)
	_credits_font_apply(title, 28)
	title.add_theme_color_override("font_color", Color("c084fc"))
	credits_reel.add_child(title)
	for row in rows:
		var line := HBoxContainer.new()
		line.custom_minimum_size = Vector2(1100, 36)
		var key := Label.new()
		key.text = String(row[0])
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.custom_minimum_size = Vector2(520, 36)
		_credits_font_apply(key, 22)
		key.add_theme_color_override("font_color", Color("b8a47a"))
		line.add_child(key)
		var value := Label.new()
		value.text = String(row[1])
		value.custom_minimum_size = Vector2(520, 36)
		_credits_font_apply(value, 22)
		value.add_theme_color_override("font_color", Color("f5e6c8"))
		line.add_child(value)
		credits_reel.add_child(line)

func _add_credits_list(items: Array) -> void:
	for item in items:
		var label := Label.new()
		label.text = String(item)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(1100, 38)
		_credits_font_apply(label, 22)
		label.add_theme_color_override("font_color", Color("d9c89a"))
		credits_reel.add_child(label)

func _add_credits_finale(rows: Array) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 250)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0.55)
	frame.border_color = Color("ffe28a")
	frame.set_border_width_all(4)
	frame.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", frame)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	for row in rows:
		var line := HBoxContainer.new()
		var key := Label.new()
		key.text = String(row[0])
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.custom_minimum_size = Vector2(410, 52)
		_credits_font_apply(key, 24)
		key.add_theme_color_override("font_color", Color("b8a47a"))
		line.add_child(key)
		var value := Label.new()
		value.text = String(row[1])
		value.custom_minimum_size = Vector2(410, 52)
		_credits_font_apply(value, 34 if String(row[1]) != "Frank" else 30)
		value.add_theme_color_override(
			"font_color",
			Color("ffe28a") if String(row[1]) == "你" else Color("c084fc") if String(row[1]) == "也许是你" else Color("f5e6c8")
		)
		line.add_child(value)
		box.add_child(line)
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(1100, 280)
	center.add_child(panel)
	credits_reel.add_child(center)

func _add_credits_spacer() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(1, 48)
	credits_reel.add_child(spacer)

func _setup_logo_gloss() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float speed = 4.0;
uniform float spot_count = 24.0;
uniform float spot_size = 0.08;
uniform vec4 glow_color : source_color = vec4(1.0, 0.88, 0.45, 1.0);
uniform float glow_intensity = 2.5;

void fragment() {
	// Sample original texture
	vec4 tex = texture(TEXTURE, UV);
	
	// Outline detection using a 3x3 kernel
	vec2 ps = TEXTURE_PIXEL_SIZE * 2.0;
	float max_a = tex.a;
	float min_a = tex.a;
	
	for (float x = -1.0; x <= 1.0; x += 1.0) {
		for (float y = -1.0; y <= 1.0; y += 1.0) {
			if (x == 0.0 && y == 0.0) continue;
			float neighbor_a = texture(TEXTURE, UV + vec2(x, y) * ps).a;
			max_a = max(max_a, neighbor_a);
			min_a = min(min_a, neighbor_a);
		}
	}
	
	// Outline mask: 1.0 at the transition boundary
	float outline = max_a - min_a;
	
	// Coordinate centering for circular rotation
	vec2 center = vec2(0.5, 0.5);
	vec2 dir = UV - center;
	
	// Aspect ratio correction (width: 660, height: 264 -> ratio = 2.5)
	dir.x *= 2.5;
	
	// Radial angle calculation
	float angle = atan(dir.y, dir.x);
	float t = (angle + 3.14159265) / 6.28318530;
	
	// Marquee running spots animation
	float marquee = cos(t * 6.28318530 * spot_count - TIME * speed);
	float spots = smoothstep(1.0 - spot_size, 1.0, marquee);
	
	// Calculate light spots color with glow
	vec4 spot_color = glow_color * spots * outline * glow_intensity;
	
	// Output only the light spots overlay
	COLOR = spot_color;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	logo_gloss.material = material

func _setup_background_squiggllevision() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode world_vertex_coords;

uniform vec2 scale = vec2(1.0, 1.0);
uniform float strength = 1.0;
uniform float fps = 6.0;
uniform sampler2D noise : filter_linear, repeat_enable;

varying vec4 modulate;
varying vec2 noise_uv;

void vertex() {
	modulate = COLOR;
	ivec2 tex_size = textureSize(noise, 0);
	vec2 size_vec = vec2(tex_size.x > 0 ? float(tex_size.x) : 512.0, tex_size.y > 0 ? float(tex_size.y) : 512.0);
	noise_uv = (VERTEX - MODEL_MATRIX[3].xy) / (size_vec * scale);
}

#define offset_multiplier vec2(3.14159265, 2.71828182)

void fragment() {
	vec2 noise_offset = vec2(floor(TIME * fps)) * offset_multiplier;
	float noise_sample = texture(noise, noise_uv + noise_offset).r * 4.0 * 3.14159265;
	vec2 direction = vec2(cos(noise_sample), sin(noise_sample));
	vec2 squiggle_uv = UV + direction * strength * 0.005;
	
	COLOR = texture(TEXTURE, squiggle_uv) * modulate;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.seamless = true
	
	var f_noise := FastNoiseLite.new()
	f_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	f_noise.frequency = 0.015
	noise_tex.noise = f_noise
	
	material.set_shader_parameter("noise", noise_tex)
	material.set_shader_parameter("strength", 0.0 if Settings.reduce_motion else 0.1)
	material.set_shader_parameter("fps", 6.0)
	material.set_shader_parameter("scale", Vector2(1.0, 1.0))
	
	$Background.material = material


func _font(control: Control, font_size: int) -> void:
	control.add_theme_font_override("font", _ui_font())
	control.add_theme_font_size_override("font_size", font_size)
	if control is Label:
		control.add_theme_constant_override("line_spacing", 8)

func _ui_font() -> Font:
	if pixel_font != null:
		return pixel_font
	for path in [
		"res://fonts/SmileySans-Oblique.ttf",
		"res://fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"res://fonts/zpix.ttf",
	]:
		var ff: FontFile
		if FileAccess.file_exists(path):
			ff = FontFile.new()
			ff.load_dynamic_font(path)
		elif path.begins_with("res://"):
			var loaded := load(path)
			if loaded is FontFile:
				ff = (loaded as FontFile).duplicate() as FontFile
		if ff == null:
			continue
		ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		ff.generate_mipmaps = true
		pixel_font = ff
		return pixel_font
	pixel_font = ThemeDB.fallback_font
	return pixel_font

func _sync_settings() -> void:
	volume_slider.set_value_no_signal(Settings.sfx_volume * 100.0)
	volume_value.text = "%d%%" % roundi(Settings.sfx_volume * 100.0)
	music_volume_slider.set_value_no_signal(Settings.music_volume * 100.0)
	music_volume_value.text = "%d%%" % roundi(Settings.music_volume * 100.0)
	fullscreen_toggle.visible = false
	reduce_motion_toggle.visible = false
	var motion_hint := $SettingsPanel/Margin/Content/MotionHint
	if motion_hint != null:
		motion_hint.visible = false
	if display_mode_btn != null:
		display_mode_btn.selected = Settings.display_mode
	if resolution_btn != null:
		resolution_btn.selected = Settings.fullscreen_resolution
		resolution_btn.disabled = (Settings.display_mode != 2)
	if clarity_btn != null:
		clarity_btn.selected = Settings.card_clarity
	if bias_btn != null:
		var selected_bias := 0
		if is_equal_approx(Settings.mipmap_bias, -0.5):
			selected_bias = 1
		elif is_equal_approx(Settings.mipmap_bias, -1.0):
			selected_bias = 2
		bias_btn.selected = selected_bias
	if background_mode_btn != null:
		background_mode_btn.selected = Settings.background_mode

func _toggle_settings() -> void:
	var should_open := not settings_panel.visible
	_close_overlays()
	if should_open:
		overlay_dim.visible = true
		settings_panel.visible = true
		volume_slider.grab_focus()

func _toggle_developer() -> void:
	var should_open := not developer_panel.visible
	_close_overlays()
	if should_open:
		overlay_dim.visible = true
		developer_panel.visible = true
		dev_button.grab_focus()

func _toggle_credits() -> void:
	var should_open := not credits_panel.visible
	_close_overlays()
	if should_open:
		credits_panel.visible = true
		credits_skip.grab_focus()
		_reset_credits_roll.call_deferred()

func _reset_credits_roll() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	credits_reel.position.y = 1160.0
	_credits_speed = maxf(120.0, (credits_reel.size.y + 540.0) / 20.0)
	_credits_paused = false
	_credits_dragging = false
	credits_hint.text = "点字幕暂停 · 按住可拖动"

func _on_credits_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_credits_dragging = true
			_credits_drag_y = event.position.y
			_credits_reel_y = credits_reel.position.y
			_credits_drag_distance = 0.0
		else:
			_credits_dragging = false
			if _credits_drag_distance < 8.0:
				_credits_paused = not _credits_paused
			else:
				_credits_paused = true
			credits_hint.text = "按住拖动 · 点字幕继续" if _credits_paused else "点字幕暂停 · 按住可拖动"
	elif event is InputEventMouseMotion and _credits_dragging:
		var delta_y: float = event.position.y - _credits_drag_y
		_credits_drag_distance = maxf(_credits_drag_distance, absf(delta_y))
		credits_reel.position.y = _credits_reel_y + delta_y

func _close_overlays() -> void:
	overlay_dim.visible = false
	settings_panel.visible = false
	developer_panel.visible = false
	credits_panel.visible = false
	start_button.grab_focus()

func _on_volume_changed(value: float) -> void:
	volume_value.text = "%d%%" % roundi(value)
	Settings.set_sfx_volume(value / 100.0)

func _on_sfx_volume_changed(value: float) -> void:
	volume_slider.set_value_no_signal(value * 100.0)
	volume_value.text = "%d%%" % roundi(value * 100.0)

func _on_music_volume_changed_by_user(value: float) -> void:
	music_volume_value.text = "%d%%" % roundi(value)
	Settings.set_music_volume(value / 100.0)

func _on_music_volume_changed(value: float) -> void:
	music_volume_slider.set_value_no_signal(value * 100.0)
	music_volume_value.text = "%d%%" % roundi(value * 100.0)

func _refresh_motion() -> void:
	_reset_ambient_static()

func _reset_ambient_static() -> void:
	brand.scale = Vector2.ONE
	logo.modulate.a = 0.96
	chart_a.modulate.a = 0.82
	chart_b.modulate.a = 0.0
	lamp_glow.modulate.a = 0.36
	_reset_steam(steam_1, 0.30)
	_reset_steam(steam_2, 0.24)

func _reset_steam(steam: TextureRect, alpha: float) -> void:
	if _steam_origins.has(steam):
		steam.position = _steam_origins[steam]
	steam.modulate.a = alpha

func _start_game() -> void:
	if _starting_transition:
		return
	GameState.dev_mode = false
	GameState.skip_beginning = false
	_play_start_curtain_transition()

func _play_start_curtain_transition() -> void:
	_starting_transition = true
	_close_overlays()
	for button in [start_button, continue_button, growth_button, settings_button, credits_button, quit_button, test_start_button]:
		button.disabled = true
	var overlay := Control.new()
	overlay.name = "StartCurtainTransition"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 5000
	get_tree().root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var screen := _screen_size()
	var top_mask := ColorRect.new()
	top_mask.name = "TopMask"
	top_mask.color = Color.BLACK
	top_mask.position = Vector2.ZERO
	top_mask.size = Vector2(screen.x, 0.0)
	overlay.add_child(top_mask)

	var bottom_mask := ColorRect.new()
	bottom_mask.name = "BottomMask"
	bottom_mask.color = Color.BLACK
	bottom_mask.position = Vector2(0.0, screen.y)
	bottom_mask.size = Vector2(screen.x, 0.0)
	overlay.add_child(bottom_mask)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(top_mask, "size:y", screen.y * 0.5, 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(bottom_mask, "position:y", screen.y * 0.5, 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(bottom_mask, "size:y", screen.y * 0.5, 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	await get_tree().create_timer(0.08).timeout
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_growth_pressed() -> void:
	pass

func _start_game_dev() -> void:
	GameState.dev_mode = true
	GameState.skip_beginning = true
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _start_game_test() -> void:
	GameState.dev_mode = true
	GameState.skip_beginning = true
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _open_city_builder() -> void:
	Settings.open_city_builder()

func _quit() -> void:
	get_tree().quit()

func _build_extra_settings() -> void:
	var content := $SettingsPanel/Margin/Content as VBoxContainer
	if content == null:
		return
		
	# 显示模式
	var display_row := HBoxContainer.new()
	display_row.add_theme_constant_override("separation", 12)
	content.add_child(display_row)
	
	var display_label := Label.new()
	display_label.text = "显示模式"
	display_label.custom_minimum_size = Vector2(120, 48)
	_font(display_label, 22)
	display_label.add_theme_color_override("font_color", INK)
	display_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	display_row.add_child(display_label)
	
	display_mode_btn = OptionButton.new()
	display_mode_btn.custom_minimum_size = Vector2(240, 48)
	_prepare_button(display_mode_btn, Color("f7f0e2"), 18)
	display_mode_btn.add_item("1x窗口 (1280x720)", 0)
	display_mode_btn.add_item("2x窗口 (1920x1080)", 1)
	display_mode_btn.add_item("3x窗口 (2560x1440)", 2)
	display_mode_btn.add_item("全屏", 3)
	display_mode_btn.selected = Settings.display_mode
	display_mode_btn.item_selected.connect(_on_display_mode_selected)
	display_row.add_child(display_mode_btn)
	_remove_popup_checkmarks(display_mode_btn)

	# 全屏分辨率
	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 12)
	content.add_child(res_row)
	
	var res_label := Label.new()
	res_label.text = "全屏分辨率"
	res_label.custom_minimum_size = Vector2(120, 48)
	_font(res_label, 22)
	res_label.add_theme_color_override("font_color", INK)
	res_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res_row.add_child(res_label)
	
	resolution_btn = OptionButton.new()
	resolution_btn.custom_minimum_size = Vector2(240, 48)
	_prepare_button(resolution_btn, Color("f7f0e2"), 18)
	resolution_btn.add_item("1920x1080", 0)
	resolution_btn.add_item("2560x1440 (2K)", 1)
	resolution_btn.add_item("3840x2160 (4K)", 2)
	resolution_btn.add_item("1280x720", 3)
	resolution_btn.add_item("1600x900", 4)
	resolution_btn.selected = Settings.fullscreen_resolution
	resolution_btn.item_selected.connect(_on_resolution_selected)
	resolution_btn.disabled = (Settings.display_mode != 3)
	res_row.add_child(resolution_btn)
	_remove_popup_checkmarks(resolution_btn)
		
	# 卡牌过滤
	var clarity_row := HBoxContainer.new()
	clarity_row.add_theme_constant_override("separation", 12)
	content.add_child(clarity_row)
	
	var clarity_label := Label.new()
	clarity_label.text = "卡牌过滤"
	clarity_label.custom_minimum_size = Vector2(120, 48)
	_font(clarity_label, 22)
	clarity_label.add_theme_color_override("font_color", INK)
	clarity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clarity_row.add_child(clarity_label)
	
	clarity_btn = OptionButton.new()
	clarity_btn.custom_minimum_size = Vector2(240, 48)
	_prepare_button(clarity_btn, Color("f7f0e2"), 18)
	clarity_btn.add_item("标准平滑", 0)
	clarity_btn.add_item("各向异性清晰", 1)
	clarity_btn.add_item("像素点阵锐利", 2)
	clarity_btn.selected = Settings.card_clarity
	clarity_btn.item_selected.connect(_on_clarity_selected)
	clarity_row.add_child(clarity_btn)
	_remove_popup_checkmarks(clarity_btn)

	# 细节锐化
	var bias_row := HBoxContainer.new()
	bias_row.add_theme_constant_override("separation", 12)
	content.add_child(bias_row)
	
	var bias_label := Label.new()
	bias_label.text = "细节锐化"
	bias_label.custom_minimum_size = Vector2(120, 48)
	_font(bias_label, 22)
	bias_label.add_theme_color_override("font_color", INK)
	bias_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bias_row.add_child(bias_label)
	
	bias_btn = OptionButton.new()
	bias_btn.custom_minimum_size = Vector2(240, 48)
	_prepare_button(bias_btn, Color("f7f0e2"), 18)
	bias_btn.add_item("正常", 0)
	bias_btn.add_item("清晰 (Bias -0.5)", 1)
	bias_btn.add_item("极其清晰 (Bias -1.0)", 2)
	
	var selected_bias := 0
	if is_equal_approx(Settings.mipmap_bias, -0.5):
		selected_bias = 1
	elif is_equal_approx(Settings.mipmap_bias, -1.0):
		selected_bias = 2
	bias_btn.selected = selected_bias
	bias_btn.item_selected.connect(_on_bias_selected)
	bias_row.add_child(bias_btn)
	_remove_popup_checkmarks(bias_btn)

	var background_row := HBoxContainer.new()
	background_row.add_theme_constant_override("separation", 12)
	content.add_child(background_row)

	var background_label := Label.new()
	background_label.text = "背景环境"
	background_label.custom_minimum_size = Vector2(120, 48)
	_font(background_label, 22)
	background_label.add_theme_color_override("font_color", INK)
	background_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	background_row.add_child(background_label)

	background_mode_btn = OptionButton.new()
	background_mode_btn.custom_minimum_size = Vector2(240, 48)
	_prepare_button(background_mode_btn, Color("f7f0e2"), 18)
	background_mode_btn.add_item("Godot3D 标记", 0)
	background_mode_btn.add_item("简单环境", 1)
	background_mode_btn.selected = Settings.background_mode
	background_mode_btn.item_selected.connect(_on_background_mode_selected)
	background_row.add_child(background_mode_btn)
	_remove_popup_checkmarks(background_mode_btn)

	var city_builder_button := Button.new()
	city_builder_button.text = "编辑 Godot3D 背景"
	city_builder_button.custom_minimum_size = Vector2(0, 58)
	_prepare_button(city_builder_button, BLUE, 20)
	city_builder_button.pressed.connect(_open_city_builder)
	content.add_child(city_builder_button)

func _on_display_mode_selected(idx: int) -> void:
	Settings.set_display_mode(idx)

func _on_resolution_selected(idx: int) -> void:
	Settings.set_fullscreen_resolution(idx)

func _on_clarity_selected(idx: int) -> void:
	Settings.set_card_clarity(idx)

func _on_bias_selected(idx: int) -> void:
	var val := 0.0
	match idx:
		0: val = 0.0
		1: val = -0.5
		2: val = -1.0
	Settings.set_mipmap_bias(val)

func _on_background_mode_selected(idx: int) -> void:
	Settings.set_background_mode(idx)

func _on_background_mode_changed(val: int) -> void:
	if background_mode_btn != null:
		background_mode_btn.selected = val

func _on_card_clarity_changed(val: int) -> void:
	if clarity_btn != null:
		clarity_btn.selected = val

func _on_mipmap_bias_changed(val: float) -> void:
	if bias_btn != null:
		var selected_bias := 0
		if is_equal_approx(val, -0.5):
			selected_bias = 1
		elif is_equal_approx(val, -1.0):
			selected_bias = 2
		bias_btn.selected = selected_bias

func _on_display_settings_changed() -> void:
	if display_mode_btn != null:
		display_mode_btn.selected = Settings.display_mode
	if resolution_btn != null:
		resolution_btn.selected = Settings.fullscreen_resolution
		resolution_btn.disabled = (Settings.display_mode != 3)

func _remove_popup_checkmarks(btn: OptionButton) -> void:
	if btn == null:
		return
	var popup := btn.get_popup()
	popup.about_to_popup.connect(func():
		var popup_style := StyleBoxFlat.new()
		popup_style.bg_color = Color(0.98, 0.95, 0.89)
		popup_style.border_color = INK
		popup_style.set_border_width_all(3)
		popup_style.set_corner_radius_all(8)
		popup_style.content_margin_left = 10
		popup_style.content_margin_right = 10
		popup_style.content_margin_top = 8
		popup_style.content_margin_bottom = 8
		popup.add_theme_stylebox_override("panel", popup_style)
		
		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color("aecbe0")
		hover_style.set_corner_radius_all(4)
		popup.add_theme_stylebox_override("hover", hover_style)
		
		popup.add_theme_font_override("font", _ui_font())
		popup.add_theme_font_size_override("font_size", 18)
		popup.add_theme_color_override("font_color", INK)
		popup.add_theme_color_override("font_hover_color", INK)

		for i in popup.get_item_count():
			popup.set_item_as_radio_checkable(i, false)
			popup.set_item_as_checkable(i, false)
	)
