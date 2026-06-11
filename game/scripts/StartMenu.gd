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

@onready var overlay_dim: ColorRect = $OverlayDim
@onready var settings_panel: PanelContainer = $SettingsPanel
@onready var settings_close: Button = $SettingsPanel/Margin/Content/Header/CloseButton
@onready var volume_slider: HSlider = $SettingsPanel/Margin/Content/VolumeRow/Slider
@onready var volume_value: Label = $SettingsPanel/Margin/Content/VolumeRow/Value
@onready var fullscreen_toggle: CheckButton = $SettingsPanel/Margin/Content/Fullscreen
@onready var reduce_motion_toggle: CheckButton = $SettingsPanel/Margin/Content/ReduceMotion

@onready var developer_panel: PanelContainer = $DeveloperPanel
@onready var developer_close: Button = $DeveloperPanel/Margin/Content/Header/CloseButton
@onready var dev_button: Button = $DeveloperPanel/Margin/Content/DevButton
@onready var city_builder_button: Button = $DeveloperPanel/Margin/Content/CityBuilderButton

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

func _ready() -> void:
	CursorManager.reset()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style_interface()
	_connect_interface()
	_sync_settings()
	_build_credits()

	_steam_origins[steam_1] = steam_1.position
	_steam_origins[steam_2] = steam_2.position
	brand.pivot_offset = brand.size * 0.5
	_setup_logo_gloss()

	Settings.reduce_motion_changed.connect(_on_reduce_motion_changed)
	Settings.fullscreen_changed.connect(_on_fullscreen_changed)
	Settings.sfx_volume_changed.connect(_on_sfx_volume_changed)
	_refresh_motion()
	start_button.grab_focus.call_deferred()

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
	_font($Footer, 15)
	$Footer.add_theme_color_override("font_color", Color("6f675e"))

	_font($SettingsPanel/Margin/Content/Header/Title, 34)
	_font($SettingsPanel/Margin/Content/VolumeRow/Label, 22)
	_font(volume_value, 20)
	_font(fullscreen_toggle, 22)
	_font(reduce_motion_toggle, 22)
	_font($SettingsPanel/Margin/Content/MotionHint, 16)
	$SettingsPanel/Margin/Content/Header/Title.add_theme_color_override("font_color", INK)
	$SettingsPanel/Margin/Content/VolumeRow/Label.add_theme_color_override("font_color", INK)
	volume_value.add_theme_color_override("font_color", INK)
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

	_prepare_menu_text_button(start_button, 36)
	_prepare_menu_text_button(continue_button, 31)
	_prepare_menu_text_button(growth_button, 31)
	_prepare_menu_text_button(settings_button, 31)
	_prepare_menu_text_button(credits_button, 31)
	_prepare_menu_text_button(quit_button, 31)
	continue_button.add_theme_color_override("font_disabled_color", Color("9b958c"))
	growth_button.add_theme_color_override("font_color", Color("777067"))
	growth_button.add_theme_color_override("font_hover_color", Color("777067"))
	growth_button.add_theme_color_override("font_focus_color", Color("777067"))
	_prepare_button(settings_close, GOLD, 18)
	_prepare_button(developer_close, GOLD, 18)
	_prepare_credits_skip()
	_prepare_button(dev_button, SAGE, 22)
	_prepare_button(city_builder_button, BLUE, 22)

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
	settings_close.pressed.connect(_close_overlays)
	developer_close.pressed.connect(_close_overlays)
	credits_skip.pressed.connect(_close_overlays)
	credits_panel.gui_input.connect(_on_credits_input)
	dev_button.pressed.connect(_start_game_dev)
	city_builder_button.pressed.connect(_open_city_builder)
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	reduce_motion_toggle.toggled.connect(_on_reduce_motion_toggled)

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
	var target := Vector2.ONE * (1.025 if emphasized else 1.0)
	var old: Tween = button.get_meta("menu_scale_tween") as Tween if button.has_meta("menu_scale_tween") else null
	if old != null and old.is_valid():
		old.kill()
	if Settings.reduce_motion:
		button.scale = target
		return
	var tw := create_tween()
	button.set_meta("menu_scale_tween", tw)
	tw.tween_property(button, "scale", target, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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

func _credits_ui_font() -> Font:
	if credits_font != null:
		return credits_font
	var ff: FontFile
	var loaded := load("res://fonts/zpix.ttf")
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
uniform float enabled = 1.0;
uniform float speed = 0.16;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float travel = mix(-0.35, 1.35, fract(TIME * speed));
	float diagonal = UV.x + UV.y * 0.34;
	float band = 1.0 - smoothstep(0.0, 0.13, abs(diagonal - travel));
	COLOR = vec4(1.0, 0.96, 0.76, tex.a * band * 0.58 * enabled);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("enabled", 0.0 if Settings.reduce_motion else 1.0)
	logo_gloss.material = material

func _font(control: Control, font_size: int) -> void:
	control.add_theme_font_override("font", _ui_font())
	control.add_theme_font_size_override("font_size", font_size)

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
	fullscreen_toggle.set_pressed_no_signal(Settings.fullscreen)
	reduce_motion_toggle.set_pressed_no_signal(Settings.reduce_motion)

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

func _on_fullscreen_toggled(enabled: bool) -> void:
	Settings.set_fullscreen(enabled)

func _on_reduce_motion_toggled(enabled: bool) -> void:
	Settings.set_reduce_motion(enabled)

func _on_sfx_volume_changed(value: float) -> void:
	volume_slider.set_value_no_signal(value * 100.0)
	volume_value.text = "%d%%" % roundi(value * 100.0)

func _on_fullscreen_changed(enabled: bool) -> void:
	fullscreen_toggle.set_pressed_no_signal(enabled)

func _on_reduce_motion_changed(enabled: bool) -> void:
	reduce_motion_toggle.set_pressed_no_signal(enabled)
	if logo_gloss.material is ShaderMaterial:
		(logo_gloss.material as ShaderMaterial).set_shader_parameter("enabled", 0.0 if enabled else 1.0)
	_refresh_motion()

func _refresh_motion() -> void:
	for tw in _motion_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_motion_tweens.clear()

	brand.scale = Vector2.ONE
	logo.modulate.a = 0.96
	chart_a.modulate.a = 0.82
	chart_b.modulate.a = 0.0
	lamp_glow.modulate.a = 0.36
	_reset_steam(steam_1, 0.30)
	_reset_steam(steam_2, 0.24)

	if Settings.reduce_motion:
		return

	var logo_tw := create_tween().set_loops()
	logo_tw.tween_property(brand, "scale", Vector2.ONE * 1.018, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	logo_tw.parallel().tween_property(logo, "modulate:a", 1.0, 1.8)
	logo_tw.tween_property(brand, "scale", Vector2.ONE, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	logo_tw.parallel().tween_property(logo, "modulate:a", 0.94, 1.8)
	_motion_tweens.append(logo_tw)

	var chart_tw := create_tween().set_loops()
	chart_tw.tween_interval(2.6)
	chart_tw.tween_property(chart_a, "modulate:a", 0.0, 0.7)
	chart_tw.parallel().tween_property(chart_b, "modulate:a", 0.84, 0.7)
	chart_tw.tween_interval(3.1)
	chart_tw.tween_property(chart_b, "modulate:a", 0.0, 0.7)
	chart_tw.parallel().tween_property(chart_a, "modulate:a", 0.82, 0.7)
	_motion_tweens.append(chart_tw)

	var lamp_tw := create_tween().set_loops()
	lamp_tw.tween_property(lamp_glow, "modulate:a", 0.50, 2.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	lamp_tw.tween_property(lamp_glow, "modulate:a", 0.29, 2.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion_tweens.append(lamp_tw)

	_motion_tweens.append(_steam_tween(steam_1, 0.2, 3.8))
	_motion_tweens.append(_steam_tween(steam_2, 1.4, 4.4))

func _steam_tween(steam: TextureRect, delay: float, duration: float) -> Tween:
	var base: Vector2 = _steam_origins[steam]
	var tw := create_tween().set_loops()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		steam.position = base
		steam.modulate.a = 0.0
	)
	tw.tween_property(steam, "modulate:a", 0.56, 0.55)
	tw.parallel().tween_property(steam, "position", base + Vector2(0, -8), 0.55)
	tw.tween_property(steam, "position", base + Vector2(0, -30), duration - 0.55).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(steam, "modulate:a", 0.0, duration - 0.55)
	tw.tween_interval(0.6)
	return tw

func _reset_steam(steam: TextureRect, alpha: float) -> void:
	if _steam_origins.has(steam):
		steam.position = _steam_origins[steam]
	steam.modulate.a = alpha

func _start_game() -> void:
	GameState.dev_mode = false
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_growth_pressed() -> void:
	pass

func _start_game_dev() -> void:
	GameState.dev_mode = true
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _open_city_builder() -> void:
	var godot := OS.get_executable_path()
	var project_path := (ProjectSettings.globalize_path("res://") + "../City-Builder").simplify_path()
	if not DirAccess.dir_exists_absolute(project_path):
		push_warning("未找到 City-Builder 工程：%s" % project_path)
		return
	var pid := OS.create_process(godot, ["--path", project_path])
	if pid <= 0:
		push_warning("启动 City Builder 失败（pid=%d）" % pid)

func _quit() -> void:
	get_tree().quit()
