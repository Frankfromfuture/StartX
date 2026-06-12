extends SubViewport
class_name CityBackground
## 把 City-Builder 里亲手搭好并存档的城市（city_map.res）渲染成 StartX 画布外的 3D 背景。
## 用 GridMap + MeshLibrary 复现 City-Builder 的摆放，相机保持「正南上方」俯视，
## 并以你放置的白色标记板（office-plot）为中心，让 StartX 办公室画布正好落在它上面。
##
## 调参：
##   视图：VIEW_W/H, LIVE_UPDATE
##   相机：CAM_FOV, CAM_PITCH_DEG（俯角，越大越top-down）, CAM_DIST, CAM_TARGET_Y（CAM_YAW=0 固定正南）
##   光照/天空：SUN_*, SKY_*, GROUND

const VIEW_W := 1920
const VIEW_H := 1080
const LIVE_UPDATE := true        # 相机随缩放/平移移动 → 必须每帧渲染
const PLATE_Y := 0.05            # 白板平面高度（卡牌贴在其上方）

# 相机：正南上方（YAW 固定 0 = 从正南看向正北，不旋转）
const CAM_FOV := 46.0
const CAM_PITCH_DEG := 56.0      # 俯角（越大越接近正俯视）
const CAM_DIST := 30.0           # 离中心距离（越大城市越小看得越全）
const CAM_TARGET_Y := 0.4

const SUN_PITCH_DEG := 52.0
const SUN_YAW_DEG := 30.0
const SUN_ENERGY := 1.15
const SHADOWS := true
const SKY_TOP := Color("8fb6d8")
const SKY_HORIZON := Color("d7e3ea")
const GROUND := Color("9fae9b")
const BOARD_GRID_COLS := 36
const BOARD_GRID_ROWS := 20
const BOARD_GRID_TEX_CELL := 32
const BOARD_GRID_CARAMEL := Color("e2ddd1")   # 偏深格子
const BOARD_GRID_GRAY := Color("eae5dc")       # 偏浅格子
const BOARD_GRID_GROUT := Color("d3ccbb")      # 格缝（细线，让浅色棋盘也看得清网格）

# wallkit 套件：模型块与布置单位整体 1/4（与 City-Builder builder.gd 一致）
const WALLKIT_SCALE := 0.25
const WALLKIT_CELL := 0.25

const BUNDLED_MAP_PATH := "res://assets/city/city_map.res"
const LIVE_MAP_COPY_PATH := "user://startx_live_city_map.res"
const MAP_POLL_INTERVAL := 0.5
const OFFICE_PLOT_INDEX := 15    # 白色标记板在结构列表中的序号（City-Builder 里放在最后）

# 结构列表 —— 顺序必须与 City-Builder/scenes/main.tscn 的 structures 数组完全一致，
# 否则读档时序号对不上。索引 15 = office-plot（白板，无 glb，代码内生成平面）。
const MODELS := [
	"res://assets/city/road-straight.glb",            # 0
	"res://assets/city/road-straight-lightposts.glb", # 1
	"res://assets/city/road-corner.glb",              # 2
	"res://assets/city/road-split.glb",               # 3
	"res://assets/city/road-intersection.glb",        # 4
	"res://assets/city/pavement.glb",                 # 5
	"res://assets/city/pavement-fountain.glb",        # 6
	"res://assets/city/building-small-a.glb",         # 7
	"res://assets/city/building-small-b.glb",         # 8
	"res://assets/city/building-small-c.glb",         # 9
	"res://assets/city/building-small-d.glb",         # 10
	"res://assets/city/building-garage.glb",          # 11
	"res://assets/city/grass.glb",                    # 12
	"res://assets/city/grass-trees.glb",              # 13
	"res://assets/city/grass-trees-tall.glb",         # 14
	"",                                               # 15 office-plot（代码内生成）
	"res://assets/city/wall.glb",                     # 16 围墙（City-Builder 新增元素）
]

var cam: Camera3D
var _root3d: Node3D
var _gridmap: GridMap
var _plot_gridmap: GridMap   # 白板独立底层（永远在非白板模型之下）
var _wallkit_gridmap: GridMap   # wallkit 精细层（cell_size 1/4、模型缩 1/4）
var _wallkit_base: int = 0      # wallkit 起始索引（>= 此值即 wallkit 模型）
var card_root: Node3D    # 卡牌 3D 网格挂在这里（与城市同一世界，共用相机/光照/阴影）
var _map_check_timer := 0.0
var _loaded_map_path := ""
var _loaded_map_signature := ""

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
	add_child(_root3d)
	_build_environment()
	_build_gridmap()
	var center := _reload_map()
	_build_camera(center)
	card_root = Node3D.new()
	card_root.name = "CardRoot"
	_root3d.add_child(card_root)

func _process(delta: float) -> void:
	_map_check_timer -= delta
	if _map_check_timer > 0.0:
		return
	_map_check_timer = MAP_POLL_INTERVAL
	var path := _map_source_path()
	var signature := _file_signature(path)
	if path == _loaded_map_path and signature == _loaded_map_signature:
		return
	_reload_map()

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = _faded(SKY_TOP)
	sky_mat.sky_horizon_color = _faded(SKY_HORIZON)
	sky_mat.ground_bottom_color = _faded(GROUND)
	sky_mat.ground_horizon_color = _faded(SKY_HORIZON)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4     # 压低 → 卡牌盒子在白板上的投影更明显
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_root3d.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-SUN_PITCH_DEG, SUN_YAW_DEG, 0.0)
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = SHADOWS
	sun.directional_shadow_max_distance = 160.0
	_root3d.add_child(sun)

func _build_gridmap() -> void:
	_gridmap = GridMap.new()
	_gridmap.cell_size = Vector3(1, 1, 1)
	_gridmap.cell_center_x = false
	_gridmap.cell_center_y = false
	_gridmap.cell_center_z = false
	var lib := MeshLibrary.new()
	var all_models := _all_model_paths()
	_wallkit_base = MODELS.size()      # wallkit 从此索引起（与 City-Builder 一致）
	for i in all_models.size():
		var m: Mesh = _office_plot_mesh() if i == OFFICE_PLOT_INDEX else _glb_mesh(all_models[i])
		if m == null:
			continue
		if i != OFFICE_PLOT_INDEX:
			_fade_city_mesh(m)        # 白板除外：城市统一变淡 30% + 降饱和 30%
		lib.create_item(i)
		lib.set_item_mesh(i, m)
		# wallkit 模型块缩到 1/4（配合 1/4 cell）；其余原样
		if i >= _wallkit_base:
			lib.set_item_mesh_transform(i, Transform3D(Basis().scaled(Vector3(WALLKIT_SCALE, WALLKIT_SCALE, WALLKIT_SCALE)), Vector3.ZERO))
		else:
			lib.set_item_mesh_transform(i, Transform3D())
	_gridmap.mesh_library = lib
	_root3d.add_child(_gridmap)

	# 白板独立底层：与主网格共用 mesh_library，整体下沉 → 任何模型都显示在白板之上
	_plot_gridmap = GridMap.new()
	_plot_gridmap.cell_size = Vector3(1, 1, 1)
	_plot_gridmap.cell_center_x = false
	_plot_gridmap.cell_center_y = false
	_plot_gridmap.cell_center_z = false
	_plot_gridmap.mesh_library = lib
	_root3d.add_child(_plot_gridmap)
	_plot_gridmap.position.y -= 0.04   # 白板永远沉在非白板模型之下

	# wallkit 精细层：cell_size = 1/4、共用 mesh_library（wallkit 项已缩 1/4）
	_wallkit_gridmap = GridMap.new()
	_wallkit_gridmap.cell_size = Vector3(WALLKIT_CELL, WALLKIT_CELL, WALLKIT_CELL)
	_wallkit_gridmap.cell_center_x = false
	_wallkit_gridmap.cell_center_y = false
	_wallkit_gridmap.cell_center_z = false
	_wallkit_gridmap.mesh_library = lib
	_root3d.add_child(_wallkit_gridmap)

# ---- 外部世界统一褪色：变淡 30% + 降饱和 30%（白板/卡牌不受影响）----
const FADE_DESAT := 0.6   # 饱和度降低比例（mix 到灰度的比例；0.6=保留约 40% 饱和度）
const FADE_LIGHT := 0.06   # 向白靠拢比例（变淡）

# 颜色域的同款变换，用于天空/地面等常量色
func _faded(c: Color) -> Color:
	var l := c.get_luminance()
	var r := lerpf(c.r, l, FADE_DESAT)
	var g := lerpf(c.g, l, FADE_DESAT)
	var b := lerpf(c.b, l, FADE_DESAT)
	return Color(lerpf(r, 1.0, FADE_LIGHT), lerpf(g, 1.0, FADE_LIGHT), lerpf(b, 1.0, FADE_LIGHT), c.a)

var _city_fade_shader: Shader = null
func _get_city_fade_shader() -> Shader:
	if _city_fade_shader != null:
		return _city_fade_shader
	_city_fade_shader = Shader.new()
	_city_fade_shader.code = """
shader_type spatial;
// 不透明、正常写深度（与原 GLB 材质一致，避免被丢进透明队列导致前后错乱）；
// 保持受光（太阳/阴影照常），只对反照率做褪色处理
render_mode depth_draw_opaque;
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform float desat = %f;
uniform float lighten = %f;

void fragment() {
	vec4 t = texture(albedo_tex, UV) * albedo_col;
	vec3 c = t.rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desat);      // 降饱和
	c = mix(c, vec3(1.0), lighten);  // 变淡（向白）
	ALBEDO = c;
}
""" % [FADE_DESAT, FADE_LIGHT]
	return _city_fade_shader

# 把一张城市网格的所有表面材质换成「褪色」着色器（保留贴图与原色调，仅整体变淡降饱和）
func _fade_city_mesh(mesh: Mesh) -> void:
	for s in mesh.get_surface_count():
		var sm := ShaderMaterial.new()
		sm.shader = _get_city_fade_shader()
		var base := mesh.surface_get_material(s) as BaseMaterial3D
		if base != null:
			if base.albedo_texture != null:
				sm.set_shader_parameter("albedo_tex", base.albedo_texture)
			sm.set_shader_parameter("albedo_col", base.albedo_color)
		mesh.surface_set_material(s, sm)

# 基础 MODELS（0..16）+ res://assets/city/new/ 下按文件名排序的新模型（17 起）。
# 顺序必须与 City-Builder builder.gd 的 _append_new_models 完全一致（同一组文件、同样排序）。
# 基础 MODELS（0..16）+ res://assets/city/wallkit/ 下按文件名排序的墙体套件（17 起）。
# 顺序必须与 City-Builder builder.gd 的 _append_wallkit_models 完全一致（同一组文件、同样排序）。
func _all_model_paths() -> Array:
	var paths := MODELS.duplicate()
	const WALLKIT_DIR := "res://assets/city/wallkit"
	var dir := DirAccess.open(WALLKIT_DIR)
	if dir != null:
		var names: Array[String] = []
		for f in dir.get_files():
			if f.get_extension() == "glb":
				names.append(f)
		names.sort()
		for n in names:
			paths.append(WALLKIT_DIR + "/" + n)
	return paths

# 从 glb 取第一个 MeshInstance3D 的网格（与 City-Builder builder.gd 一致）。
# 这些 Kenney 模型都是单网格单面，取首个即完整。
func _glb_mesh(path: String) -> Mesh:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate()
	var m := _find_mesh(inst)
	inst.free()
	return m

func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for c in node.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null

# office-plot 白板：9×5 平面，贴地，画成 18×10 的淡色棋盘格
func _office_plot_mesh() -> Mesh:
	var pm := PlaneMesh.new()
	pm.size = Vector2(9, 5)
	pm.center_offset = Vector3(4.0, 0.05, 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = _office_plot_checker_texture()
	# 不受光照：棋盘按贴图原色 1:1 显示，避免被太阳+环境光+FILMIC 顶到过曝发白
	# （那层“白色蒙版”其实是过曝，不是真实平面）。拿起卡时的 blob 软阴影是独立平面，仍正常。
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 0.95
	pm.material = mat
	return pm

func _office_plot_checker_texture() -> Texture2D:
	var w := BOARD_GRID_COLS * BOARD_GRID_TEX_CELL
	var h := BOARD_GRID_ROWS * BOARD_GRID_TEX_CELL
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var grout := 2   # 格缝宽度（像素）
	for y in h:
		var row := y / BOARD_GRID_TEX_CELL
		for x in w:
			var col := x / BOARD_GRID_TEX_CELL
			var c := BOARD_GRID_CARAMEL if ((row + col) % 2 == 0) else BOARD_GRID_GRAY
			# 单元格边缘画细格缝，使浅色棋盘也能看清网格
			if (x % BOARD_GRID_TEX_CELL) < grout or (y % BOARD_GRID_TEX_CELL) < grout:
				c = BOARD_GRID_GROUT
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# 读档摆放，返回白板中心（用于相机对准）。无存档则返回 Vector3.ZERO。
func _reload_map() -> Vector3:
	var path := _map_source_path()
	_gridmap.clear()
	_plot_gridmap.clear()
	_wallkit_gridmap.clear()
	_loaded_map_path = path
	_loaded_map_signature = _file_signature(path)
	var dm = _load_data_map(path)
	if dm == null or not ("structures" in dm):
		push_warning("CityBackground: 读取不到城市存档 %s" % path)
		return Vector3.ZERO
	var plot_sum := Vector2.ZERO
	var plot_n := 0
	var all_sum := Vector2.ZERO
	var all_n := 0
	for ds in dm.structures:
		# wallkit -> 精细层；白板 -> 底层；其余 -> 上层（各层格坐标按各自 cell_size）
		var layer: GridMap = _gridmap
		if ds.structure >= _wallkit_base:
			layer = _wallkit_gridmap
		elif ds.structure == OFFICE_PLOT_INDEX:
			layer = _plot_gridmap
		layer.set_cell_item(Vector3i(ds.position.x, 0, ds.position.y), ds.structure, ds.orientation)
		# wallkit 用 1/4 格，换算回整格坐标参与中心统计
		var wx: int = ds.position.x
		var wy: int = ds.position.y
		if ds.structure >= _wallkit_base:
			wx = int(round(float(ds.position.x) * WALLKIT_CELL))
			wy = int(round(float(ds.position.y) * WALLKIT_CELL))
		all_sum += Vector2(wx, wy)
		all_n += 1
		if ds.structure == OFFICE_PLOT_INDEX:
			plot_sum += Vector2(ds.position.x, ds.position.y)
			plot_n += 1
	# 中心：优先用白板格（含板自身 9×5 的视觉中心偏移 +4,+2），否则用全城几何中心
	var c: Vector2
	if plot_n > 0:
		c = plot_sum / float(plot_n) + Vector2(4.0, 2.0)
	elif all_n > 0:
		c = all_sum / float(all_n)
	else:
		c = Vector2.ZERO
	# 平移两层 GridMap，让中心落到世界原点（相机注视点）；白板层保持 -0.04 下沉
	_gridmap.position = Vector3(-c.x, 0, -c.y)
	_plot_gridmap.position = Vector3(-c.x, -0.04, -c.y)
	_wallkit_gridmap.position = Vector3(-c.x, 0, -c.y)
	return Vector3.ZERO

func _map_source_path() -> String:
	var city_builder_map := (ProjectSettings.globalize_path("res://") + "../City-Builder/maps/city_map.res").simplify_path()
	if FileAccess.file_exists(city_builder_map):
		return city_builder_map
	return BUNDLED_MAP_PATH

func _load_data_map(path: String):
	var dm = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if dm != null:
		return dm
	if not path.is_absolute_path():
		return null
	var copy_target := ProjectSettings.globalize_path(LIVE_MAP_COPY_PATH)
	var copy_err := DirAccess.copy_absolute(path, copy_target)
	if copy_err != OK:
		push_warning("CityBackground: 无法同步城市存档 %s -> %s (err=%d)" % [path, LIVE_MAP_COPY_PATH, copy_err])
		return null
	return ResourceLoader.load(LIVE_MAP_COPY_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)

func _file_signature(path: String) -> String:
	var file_path := path
	if not file_path.is_absolute_path():
		file_path = ProjectSettings.globalize_path(file_path)
	if not FileAccess.file_exists(file_path):
		return ""
	var size := 0
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f != null:
		size = f.get_length()
		f.close()
	return "%d:%d" % [FileAccess.get_modified_time(file_path), size]

func _build_camera(_target: Vector3) -> void:
	cam = Camera3D.new()
	cam.fov = CAM_FOV
	cam.far = 600.0
	_root3d.add_child(cam)
	aim(Vector3.ZERO, CAM_DIST)

var pitch_deg: float = CAM_PITCH_DEG    # 可调俯角（向前下/向后下按钮）

# 正南上方俯视：注视 center、距离 dist（YAW=0，相机在 +Z 抬高看向 center）
func aim(center: Vector3, dist: float) -> void:
	if cam == null:
		return
	var look := center + Vector3(0, CAM_TARGET_Y, 0)
	var pitch := deg_to_rad(pitch_deg)
	var dir := Vector3(0, sin(pitch), cos(pitch))
	cam.position = look + dir * dist
	cam.look_at(look, Vector3.UP)
