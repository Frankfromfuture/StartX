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

const MAP_PATH := "res://assets/city/city_map.res"
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
]

var cam: Camera3D
var _root3d: Node3D
var _gridmap: GridMap
var card_root: Node3D    # 卡牌 3D 网格挂在这里（与城市同一世界，共用相机/光照/阴影）

func world_card_root() -> Node3D:
	return card_root

func _ready() -> void:
	size = Vector2i(VIEW_W, VIEW_H)
	transparent_bg = false
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if LIVE_UPDATE else SubViewport.UPDATE_ONCE
	own_world_3d = true

	_root3d = Node3D.new()
	add_child(_root3d)
	_build_environment()
	_build_gridmap()
	var center := _load_map()
	_build_camera(center)
	card_root = Node3D.new()
	card_root.name = "CardRoot"
	_root3d.add_child(card_root)

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP
	sky_mat.sky_horizon_color = SKY_HORIZON
	sky_mat.ground_bottom_color = GROUND
	sky_mat.ground_horizon_color = SKY_HORIZON
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55     # 压低环境光 → 阴影更明显（卡牌投影更有立体感）
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
	for i in MODELS.size():
		var m: Mesh = _office_plot_mesh() if i == OFFICE_PLOT_INDEX else _glb_mesh(MODELS[i])
		if m == null:
			continue
		lib.create_item(i)
		lib.set_item_mesh(i, m)
		lib.set_item_mesh_transform(i, Transform3D())
	_gridmap.mesh_library = lib
	_root3d.add_child(_gridmap)

# 从 glb 取第一个 MeshInstance3D 的网格（与 City-Builder builder.gd 一致）
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

# office-plot 白板：9×5 平面，贴地，白色无光照（与 City-Builder 的 office_plot.tscn 一致）
func _office_plot_mesh() -> Mesh:
	var pm := PlaneMesh.new()
	pm.size = Vector2(9, 5)
	pm.center_offset = Vector3(4.0, 0.05, 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)   # 受光着色 → 能接收卡牌投影（Stacklands 式立体感）
	mat.roughness = 0.95
	pm.material = mat
	return pm

# 读档摆放，返回白板中心（用于相机对准）。无存档则返回 Vector3.ZERO。
func _load_map() -> Vector3:
	var dm = ResourceLoader.load(MAP_PATH)
	if dm == null or not ("structures" in dm):
		push_warning("CityBackground: 读取不到城市存档 %s" % MAP_PATH)
		return Vector3.ZERO
	var plot_sum := Vector2.ZERO
	var plot_n := 0
	var all_sum := Vector2.ZERO
	var all_n := 0
	for ds in dm.structures:
		_gridmap.set_cell_item(Vector3i(ds.position.x, 0, ds.position.y), ds.structure, ds.orientation)
		all_sum += Vector2(ds.position.x, ds.position.y)
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
	# 平移 GridMap，让中心落到世界原点（相机注视点）
	_gridmap.position = Vector3(-c.x, 0, -c.y)
	return Vector3.ZERO

func _build_camera(_target: Vector3) -> void:
	cam = Camera3D.new()
	cam.fov = CAM_FOV
	cam.far = 600.0
	_root3d.add_child(cam)
	aim(Vector3.ZERO, CAM_DIST)

# 正南上方俯视：注视 center、距离 dist（YAW=0，相机在 +Z 抬高看向 center）
func aim(center: Vector3, dist: float) -> void:
	if cam == null:
		return
	var look := center + Vector3(0, CAM_TARGET_Y, 0)
	var pitch := deg_to_rad(CAM_PITCH_DEG)
	var dir := Vector3(0, sin(pitch), cos(pitch))
	cam.position = look + dir * dist
	cam.look_at(look, Vector3.UP)
