extends SubViewport
class_name CityBackground
## 游戏背景只加载手工编辑的 Godot3D 背景场景。
## 不在这里生成、清空或改写背景元素，避免覆盖编辑器里的手动摆放。

const VIEW_W := 1920
const VIEW_H := 1080
const LIVE_UPDATE := true
const CAM_FOV := 46.0
const CAM_PITCH_DEG := 56.0
const CAM_DIST := 30.0
const CAM_TARGET_Y := 0.4
const EDITABLE_BACKGROUND_SCENE := "res://scenes/backgrounds/EditableBattleBackground3D.tscn"
const BOARD_GRID_COLS := 36
const BOARD_GRID_ROWS := 20
const BOARD_GRID_TEX_CELL := 32
const BOARD_GRID_CARAMEL := Color("e2ddd1")
const BOARD_GRID_GRAY := Color("eae5dc")
const BOARD_GRID_GROUT := Color("d3ccbb")

var cam: Camera3D
var pitch_deg: float = CAM_PITCH_DEG
var card_root: Node3D

var _root3d: Node3D
var _background_root: Node3D
var _board_root: Node3D

func world_card_root() -> Node3D:
	return card_root

func _ready() -> void:
	if size.x <= 1 or size.y <= 1:
		size = Vector2i(VIEW_W, VIEW_H)
	transparent_bg = false
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if LIVE_UPDATE else SubViewport.UPDATE_ONCE
	own_world_3d = true

	_root3d = Node3D.new()
	_root3d.name = "BackgroundWorld"
	add_child(_root3d)

	_load_editable_background()
	_build_board_surface()
	_build_camera()

	card_root = Node3D.new()
	card_root.name = "CardRoot"
	_root3d.add_child(card_root)

func set_background_mode(value: int) -> void:
	if _background_root != null:
		_background_root.visible = value == 0 or value == 1

func _load_editable_background() -> void:
	var packed := load(EDITABLE_BACKGROUND_SCENE) as PackedScene
	if packed == null:
		push_warning("Editable background scene missing: %s" % EDITABLE_BACKGROUND_SCENE)
		return
	_background_root = packed.instantiate() as Node3D
	if _background_root == null:
		push_warning("Editable background scene root is not Node3D: %s" % EDITABLE_BACKGROUND_SCENE)
		return
	_background_root.name = "EditableBackground"
	_root3d.add_child(_background_root)
	_disable_embedded_cameras(_background_root)
	_hide_embedded_board(_background_root)

func _hide_embedded_board(root: Node) -> void:
	for path in ["ActiveCanvasWhiteboard", "WhiteboardBorder"]:
		var node := root.get_node_or_null(path) as Node3D
		if node != null:
			node.visible = false

func _disable_embedded_cameras(node: Node) -> void:
	if node is Camera3D:
		(node as Camera3D).current = false
	for child in node.get_children():
		_disable_embedded_cameras(child)

func _build_board_surface() -> void:
	_board_root = Node3D.new()
	_board_root.name = "RestoredBoardSurface"
	_root3d.add_child(_board_root)
	var board := MeshInstance3D.new()
	board.name = "ActiveCanvasWhiteboard"
	board.mesh = _office_plot_mesh()
	board.position = Vector3(-4.0, -0.04, -2.0)
	_board_root.add_child(board)
	_board_root.add_child(_rounded_frame_plane(Vector2(9.12, 5.12), Color("2f2d2a"), 0.08, 0.002))

func _office_plot_mesh() -> Mesh:
	var pm := PlaneMesh.new()
	pm.size = Vector2(9, 5)
	pm.center_offset = Vector3(4.0, 0.05, 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = _office_plot_checker_texture()
	mat.roughness = 0.95
	pm.material = mat
	return pm

func _office_plot_checker_texture() -> Texture2D:
	var w := BOARD_GRID_COLS * BOARD_GRID_TEX_CELL
	var h := BOARD_GRID_ROWS * BOARD_GRID_TEX_CELL
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var grout := 2
	for y in h:
		var row := y / BOARD_GRID_TEX_CELL
		for x in w:
			var col := x / BOARD_GRID_TEX_CELL
			var c := BOARD_GRID_CARAMEL if ((row + col) % 2 == 0) else BOARD_GRID_GRAY
			if (x % BOARD_GRID_TEX_CELL) < grout or (y % BOARD_GRID_TEX_CELL) < grout:
				c = BOARD_GRID_GROUT
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _rounded_frame_plane(frame_size: Vector2, color: Color, radius: float, y: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "RoundedBoardBorder"
	var mesh := QuadMesh.new()
	mesh.size = frame_size
	mesh_instance.mesh = mesh
	mesh_instance.position.y = y
	mesh_instance.rotation_degrees.x = -90.0
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform vec4 frame_color : source_color;
uniform vec2 frame_size;
uniform float corner_radius;

void fragment() {
	vec2 p = abs((UV - vec2(0.5)) * frame_size) - (frame_size * 0.5 - vec2(corner_radius));
	float distance_to_edge = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - corner_radius;
	if (distance_to_edge > 0.0) {
		discard;
	}
	ALBEDO = frame_color.rgb;
	ALPHA = frame_color.a;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("frame_color", color)
	material.set_shader_parameter("frame_size", frame_size)
	material.set_shader_parameter("corner_radius", radius)
	mesh_instance.material_override = material
	return mesh_instance

func _build_camera() -> void:
	cam = Camera3D.new()
	cam.name = "GamePerspectiveCamera"
	cam.fov = CAM_FOV
	cam.far = 600.0
	cam.current = true
	_root3d.add_child(cam)
	aim(Vector3.ZERO, CAM_DIST)

func aim(center: Vector3, dist: float) -> void:
	if cam == null:
		return
	var look := center + Vector3(0, CAM_TARGET_Y, 0)
	var pitch := deg_to_rad(pitch_deg)
	var dir := Vector3(0, sin(pitch), cos(pitch))
	cam.position = look + dir * dist
	cam.look_at(look, Vector3.UP)
