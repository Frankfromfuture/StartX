extends Node
## Persistent player-facing settings shared by menus, gameplay, and audio.

signal sfx_volume_changed(value: float)
signal display_settings_changed
signal card_clarity_changed(value: int)
signal mipmap_bias_changed(value: float)
signal background_mode_changed(value: int)

const SETTINGS_PATH := "user://startx_settings.cfg"

var sfx_volume: float = 0.8
var display_mode: int = 0  # 0 = 1x Window (1280x720), 1 = 2x Window (1920x1080), 2 = 3x Window (2560x1440), 3 = Fullscreen
var fullscreen_resolution: int = 0 # 0 = 1920x1080, 1 = 2560x1440, 2 = 3840x2160, 3 = 1280x720, 4 = 1600x900
var card_clarity: int = 1
var mipmap_bias: float = 0.0
var background_mode: int = 1 # 0 = City Builder, 1 = 简单环境

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	call_deferred("apply_display_settings")
	call_deferred("_apply_mipmap_bias")

func set_sfx_volume(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, sfx_volume):
		return
	sfx_volume = next
	sfx_volume_changed.emit(sfx_volume)
	_save_settings()

func set_display_mode(value: int) -> void:
	if value == display_mode:
		return
	display_mode = value
	apply_display_settings()
	display_settings_changed.emit()
	_save_settings()

func set_fullscreen_resolution(value: int) -> void:
	if value == fullscreen_resolution:
		return
	fullscreen_resolution = value
	apply_display_settings()
	display_settings_changed.emit()
	_save_settings()

func set_card_clarity(value: int) -> void:
	if value == card_clarity:
		return
	card_clarity = value
	card_clarity_changed.emit(card_clarity)
	_save_settings()

func set_mipmap_bias(value: float) -> void:
	if is_equal_approx(value, mipmap_bias):
		return
	mipmap_bias = value
	_apply_mipmap_bias()
	mipmap_bias_changed.emit(mipmap_bias)
	_save_settings()

func set_background_mode(value: int) -> void:
	var next := clampi(value, 0, 1)
	if next == background_mode:
		return
	background_mode = next
	background_mode_changed.emit(background_mode)
	_save_settings()

func open_city_builder() -> bool:
	var godot := OS.get_executable_path()
	var project_path := (ProjectSettings.globalize_path("res://") + "../City-Builder").simplify_path()
	if not DirAccess.dir_exists_absolute(project_path):
		push_warning("未找到 City-Builder 工程：%s" % project_path)
		return false
	var pid := OS.create_process(godot, ["--path", project_path])
	if pid <= 0:
		push_warning("启动 City Builder 失败（pid=%d）" % pid)
		return false
	return true

func _apply_mipmap_bias() -> void:
	var vp := get_viewport()
	if vp != null and "texture_mipmap_bias" in vp:
		vp.texture_mipmap_bias = mipmap_bias

func sfx_volume_db() -> float:
	if sfx_volume <= 0.001:
		return -80.0
	return linear_to_db(sfx_volume)

func apply_display_settings() -> void:
	if display_mode == 3: # Fullscreen
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		var res := Vector2i(1920, 1080)
		match fullscreen_resolution:
			0: res = Vector2i(1920, 1080)
			1: res = Vector2i(2560, 1440)
			2: res = Vector2i(3840, 2160)
			3: res = Vector2i(1280, 720)
			4: res = Vector2i(1600, 900)
		DisplayServer.window_set_size(res)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var size := Vector2i(1280, 720)
		match display_mode:
			0: size = Vector2i(1280, 720)
			1: size = Vector2i(1920, 1080)
			2: size = Vector2i(2560, 1440)
		DisplayServer.window_set_size(size)
		# Center the window on the current screen
		var screen := DisplayServer.window_get_current_screen()
		var screen_size := DisplayServer.screen_get_usable_rect(screen).size
		DisplayServer.window_set_position((screen_size - size) / 2)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	display_mode = int(cfg.get_value("display", "display_mode", display_mode))
	fullscreen_resolution = int(cfg.get_value("display", "fullscreen_resolution", fullscreen_resolution))
	card_clarity = int(cfg.get_value("display", "card_clarity", card_clarity))
	mipmap_bias = float(cfg.get_value("display", "mipmap_bias", mipmap_bias))
	background_mode = clampi(int(cfg.get_value("display", "background_mode", background_mode)), 0, 1)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("display", "display_mode", display_mode)
	cfg.set_value("display", "fullscreen_resolution", fullscreen_resolution)
	cfg.set_value("display", "card_clarity", card_clarity)
	cfg.set_value("display", "mipmap_bias", mipmap_bias)
	cfg.set_value("display", "background_mode", background_mode)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("无法保存设置：%s (err=%d)" % [SETTINGS_PATH, err])
