extends Node
## Persistent player-facing settings shared by menus, gameplay, and audio.

signal sfx_volume_changed(value: float)
signal fullscreen_changed(enabled: bool)
signal reduce_motion_changed(enabled: bool)

const SETTINGS_PATH := "user://startx_settings.cfg"

var sfx_volume: float = 0.8
var fullscreen: bool = false
var reduce_motion: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	call_deferred("_apply_fullscreen")

func set_sfx_volume(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, sfx_volume):
		return
	sfx_volume = next
	sfx_volume_changed.emit(sfx_volume)
	_save_settings()

func set_fullscreen(enabled: bool) -> void:
	if enabled == fullscreen:
		_apply_fullscreen()
		return
	fullscreen = enabled
	_apply_fullscreen()
	fullscreen_changed.emit(fullscreen)
	_save_settings()

func set_reduce_motion(enabled: bool) -> void:
	if enabled == reduce_motion:
		return
	reduce_motion = enabled
	reduce_motion_changed.emit(reduce_motion)
	_save_settings()

func sfx_volume_db() -> float:
	if sfx_volume <= 0.001:
		return -80.0
	return linear_to_db(sfx_volume)

func _apply_fullscreen() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	reduce_motion = bool(cfg.get_value("accessibility", "reduce_motion", reduce_motion))

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("accessibility", "reduce_motion", reduce_motion)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("无法保存设置：%s (err=%d)" % [SETTINGS_PATH, err])
