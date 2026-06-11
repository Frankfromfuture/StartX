extends Node

const CURSOR_SOURCE_PX := 64
const CURSOR_SCREEN_PX := 34.0
const CURSOR_PATHS := {
	"default": "res://assets/cursors/1.svg",
	"hover": "res://assets/cursors/2.svg",
	"drag": "res://assets/cursors/3.svg",
	"pan": "res://assets/cursors/4.svg",
}
const ALL_CURSOR_SHAPES := [
	Input.CURSOR_ARROW,
	Input.CURSOR_IBEAM,
	Input.CURSOR_POINTING_HAND,
	Input.CURSOR_CROSS,
	Input.CURSOR_WAIT,
	Input.CURSOR_BUSY,
	Input.CURSOR_DRAG,
	Input.CURSOR_CAN_DROP,
	Input.CURSOR_FORBIDDEN,
	Input.CURSOR_VSIZE,
	Input.CURSOR_HSIZE,
	Input.CURSOR_BDIAGSIZE,
	Input.CURSOR_FDIAGSIZE,
	Input.CURSOR_MOVE,
	Input.CURSOR_VSPLIT,
	Input.CURSOR_HSPLIT,
	Input.CURSOR_HELP,
]

var textures: Dictionary = {}
var hotspots: Dictionary = {}
var current_state := ""
var lock_refresh := 0.0
var cursor_layer: CanvasLayer
var cursor_sprite: TextureRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for state in CURSOR_PATHS:
		var texture := _load_cursor_texture(String(CURSOR_PATHS[state]))
		if texture != null:
			textures[state] = texture
	_build_software_cursor()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	set_state("default", true)

func _process(delta: float) -> void:
	if cursor_sprite != null:
		var texture: Texture2D = textures.get(current_state)
		var display_size := _software_cursor_size()
		var hotspot_ratio: Vector2 = hotspots.get(texture, Vector2.ZERO)
		cursor_sprite.size = display_size
		cursor_sprite.position = get_viewport().get_mouse_position() - hotspot_ratio * display_size
	lock_refresh -= delta
	if lock_refresh <= 0.0:
		lock_refresh = 0.25
		if Input.get_mouse_mode() != Input.MOUSE_MODE_HIDDEN:
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		set_state(current_state, true)

func set_state(state: String, force: bool = false) -> void:
	if not textures.has(state):
		state = "default"
	if not force and current_state == state:
		return
	current_state = state
	var texture: Texture2D = textures.get(state)
	if texture == null:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	if cursor_sprite != null:
		cursor_sprite.texture = texture
		cursor_sprite.size = _software_cursor_size()
		cursor_sprite.visible = true
	var hotspot_ratio: Vector2 = hotspots.get(texture, Vector2.ZERO)
	var hotspot := hotspot_ratio * Vector2(CURSOR_SOURCE_PX, CURSOR_SOURCE_PX)
	# Every Control can request a different system cursor shape. Keep every slot
	# mapped to the active custom texture so no UI node can revert it to an arrow.
	for shape in ALL_CURSOR_SHAPES:
		Input.set_custom_mouse_cursor(texture, shape, hotspot)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func reset() -> void:
	set_state("default", true)

func _build_software_cursor() -> void:
	cursor_layer = CanvasLayer.new()
	cursor_layer.layer = 10000
	add_child(cursor_layer)
	cursor_sprite = TextureRect.new()
	cursor_sprite.name = "SoftwareCursor"
	cursor_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cursor_sprite.z_index = 4096
	cursor_layer.add_child(cursor_sprite)

func _software_cursor_size() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var window_size := Vector2(DisplayServer.window_get_size())
	var stretch := 1.0
	if window_size.x > 0.0 and window_size.y > 0.0:
		stretch = maxf(viewport_size.x / window_size.x, viewport_size.y / window_size.y)
	var logical_px := CURSOR_SCREEN_PX * maxf(stretch, 1.0)
	return Vector2(logical_px, logical_px)

func is_interactive_control(control: Control) -> bool:
	var current: Node = control
	while current is Control:
		if current is BaseButton:
			return not (current as BaseButton).disabled
		if current is Range:
			return true
		current = current.get_parent()
	return false

func _load_cursor_texture(path: String) -> Texture2D:
	var image: Image = null
	var imported := ResourceLoader.load(path) as Texture2D
	if imported != null:
		image = imported.get_image()
	else:
		image = Image.load_from_file(path)
	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		push_warning("无法加载鼠标指针：%s" % path)
		return null
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(CURSOR_SOURCE_PX, CURSOR_SOURCE_PX, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	hotspots[texture] = _find_hotspot(image) / Vector2(image.get_width(), image.get_height())
	return texture

func _find_hotspot(image: Image) -> Vector2:
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.4:
				return Vector2(x, y)
	return Vector2.ZERO
