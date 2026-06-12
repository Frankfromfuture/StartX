extends Node2D
## Zoned board with a shared 1-point perspective projection applied to BOTH the
## background and the cards. All gameplay logic runs in flat "board space";
## rendering projects board space -> display space (top narrower than bottom).

const CardScript = preload("res://scripts/Card.gd")
const PackCardScript = preload("res://scripts/PackCard.gd")
const FloatingCostScript = preload("res://scripts/FloatingCost.gd")
const CARD_SCALE := 1.0 / 3.0         # 卡面源图仍按 180×180 烘焙，显示/交互为 60×60
const CW := 60.0
const CH := 60.0
const CARD_OFFSET := 34.0 / 3.0       # 叠放时每张上面的牌再往下一点
const PACK_SCALE := 1.0 / 3.0
const PACK_W := PackCardScript.W * PACK_SCALE
const PACK_H := PackCardScript.H * PACK_SCALE
const DRAG_Z := 4000
const BATTLE_Z := 3000              # 战斗中攻击方置顶

# ---- Layout (board space 1920x1080) ----
const BASE_W := 1920.0
const BASE_H := 1080.0
const HUD_H := 62.0
const DRAW_Y0 := 52.0
const DRAW_Y1 := 160.0          # 抽卡区压扁成一条工具栏（研发|卡包|出售同排）
const MID_Y0 := 160.0           # 画布上边（锚定在 UI 区下方）
# 活跃画布 = City-Builder 里 9×5 的白色标记板：CELL=168 单位/格，宽=9 格(1512)、高=5 格(840)
const CITY_CELL := 168.0        # 每个 city-builder 格子对应的画布单位
const MID_Y1 := 1000.0          # 画布下边 = MID_Y0 + 5*CITY_CELL = 160+840（高=5 格）
const ORG_Y0 := 1000.0          # 组织/部门折叠区位于画布底部（跟随 MID_Y1）
const INFO_Y := 1016.0          # fixed bottom information strip
const DIVIDER_X := 960.0
const CANVAS_X0 := 204.0        # 画布左边 = 960 - 4.5*CITY_CELL（以中线 960 为中心，宽 9 格=1512）
const CANVAS_X1 := 1716.0       # 画布右边 = 960 + 4.5*CITY_CELL
const GAP := 16.0
const BANK_RECT := Rect2(1590, 60, 300, 84)     # fixed HUD bank, outside canvas zoom
const VIEW_PAD := 420.0
const BUSINESS_CAPACITY_PER_OFFICE := 18
const TOOLBAR_BUTTON_H := 72.0
const TOP_LABEL_FONT_SIZE := 26
const TOP_ICON_SIZE := 24.0

# ---- Perspective ----  (1.0 = OFF/flat)；0.9 = 轻微一点透视（顶窄底宽）
const TOP_SCALE := 0.9         # horizontal width factor at the very top (y=0)

# ---- 拖拽弹簧（滞后 + 摆动）----  减衰調和振動：顶牌跟手、越往下越软越晃
const DRAG_OMEGA_TOP := 26.0       # 顶牌角频率（越大越跟手）
const DRAG_OMEGA_FALLOFF := 0.50   # 每往上一张，频率×此值 → 滞后/摆动递增
const DRAG_ZETA := 0.55            # 阻尼比 <1 → 欠阻尼，产生回摆/甩动感

# 莫兰迪淡色 + 奶白底
const BG := Color("efe7d8")          # 画布纸面（画布内底色）
const BG_OUT := Color("aebfcb")      # 画布外·莫兰迪淡蓝
const DRAW_BG := Color("e6ddcb")     # 抽卡区·暖米
const OFFICE_BG := Color(0.80, 0.85, 0.88, 0.20)   # 办公室·20% 透明淡蓝
const MARKET_BG := Color(0.90, 0.84, 0.78, 0.20)   # 市场·20% 透明暖砂粉
const ORG_BG := Color("d8d2dc")      # 组织·雾紫灰
const INK := Color("3a352f")         # 墨线/深字

var all_cards: Array = []
var stacks: Dictionary = {}
var stack_base: Dictionary = {}     # board-space top-left of bottom card
var productions: Dictionary = {}
var next_stack_id: int = 0

var drag_cards: Array = []
var drag_sid: int = -1
var drag_offset: Vector2 = Vector2.ZERO   # board space
var press_pos: Vector2 = Vector2.ZERO     # 按下点（判定 tap vs 拖动）
var press_moved: bool = false             # 本次按下后是否真的移动过
const DRAG_TAP_PX := 6.0                   # 位移超过此值才算"拖动"，否则视为点击
var drag_pack: Node2D = null               # 正在拖动的卡包（按住拖=移动，轻点=拆一张）
var pack_drag_offset: Vector2 = Vector2.ZERO  # display space
var hover_card = null
var cursor_state: String = ""
var dash_phase: float = 0.0

# 供应链：连接绑定卡牌实例而非 stack_id，避免牌堆合并重编号后断线。
# 每项为 {source: Card, target: Card}；source 是生产堆中的稳定锚点。
var supply_chains: Array = []
var supply_drag_source = null
var supply_drag_mouse: Vector2 = Vector2.ZERO
var supply_drag_target = null
var supply_flow_phase: float = 0.0
var supply_hover_chain = null
var supply_hover_scale: float = 0.0
var supply_transits: Array = []
var supply_arrow_mesh: MeshInstance3D
const SUPPLY_BLUE := Color("465d78")
const SUPPLY_BLUE_LIGHT := Color("607792")
const SUPPLY_BLUE_DARK := Color("33485f")
const SUPPLY_ARROW_Y := 0.052

var month_time: float = 0.0

const DEFAULT_HINT := "「公司的地板光亮如新，有可能是创始人晚上擦的」"

var hud: CanvasLayer
var top_bar: Control
var bottom_info: Node2D     # 底部信息栏（HUD 层绘制，始终盖在卡牌之上）
var book_tab_shadow: Node2D # 商业模式整体阴影背景
var book_tab_seam: Node2D   # 商业模式弹窗与按钮的「文件夹标签」融合缝盖
var book_btn: Button        # 商业模式按钮（作为弹窗的文件夹标签）
const PANEL_CREAM := Color(0.98, 0.95, 0.89, 0.97)   # 弹窗/标签共用奶白底
var lbl_status: Label
var lbl_top_rp: Label
var lbl_finance: Label
var lbl_expense: Label
var lbl_val: Label
var lbl_business: Label
var hover_panel: Panel
var hover_label: Label
var founder_bubble: Control = null
var founder_bubble_anchor: Vector2 = Vector2.ZERO   # board-space topleft when bubble appeared; bubble dies if the card moves

# 战斗：对手卡触碰员工（含创始人）时进入
var battle_active: bool = false
var battle_rival = null
var battle_employee = null
var battle_center: Vector2 = Vector2.ZERO   # 战斗框中心（board）
var battle_border: Node2D = null
var battle_hp_left: float = 0.0             # 对手（左）资金 HP
var battle_hp_right: float = 0.0            # 我方（右）现金 HP
var battle_hp_shown_left: float = 0.0       # 显示用（计数动画）
var battle_hp_shown_right: float = 0.0
var battle_dmg_to_player: float = 0.0       # 我方累计受伤（战斗结束按整数扣现金卡）
var battle_hp_label_left: Label = null
var battle_hp_label_right: Label = null
var battle_hp_icon_left: TextureRect = null
var battle_hp_icon_right: TextureRect = null
var battle_running: bool = false            # 回合循环进行中
var battle_bubble_tex: Texture2D = null
var battle_versus_tex: Texture2D = null     # 战斗区域中心 VS 装饰
var battle3d: Node3D = null                  # 战斗装饰的 3D 表现（边框/VS/HP 数字躺白板）
var battle_hp3d_left: Label3D = null
var battle_hp3d_right: Label3D = null
var battle_saved_zoom: float = 0.0          # 进战斗前的视角，结束后恢复
var battle_saved_offset: Vector2 = Vector2.ZERO
var battle_view_changed: bool = false
var battle_dash_phase: float = 0.0          # 战斗边框虚线行进相位（转圈动画）
const BATTLE_TOP_EXTRA := CARD_OFFSET * 0.5 + CH * 0.25
# 拖拽叠放提示：所有可与被拖卡互动的栈都套一个细的、慢速走马灯虚线框（3D 平贴白板，
# 位于卡牌之下 → 不会压在其他牌上）
var stack_hint_sids: Array = []
var stack_hint_quads: Array = []           # MeshInstance3D 池（平铺白板的虚线框）
var stack_hint_border_shader: Shader = null
var battle_rival_first: bool = true         # 谁先碰到谁先攻击
var battle_attacker_sid: int = -1           # 当前攻击方栈：relayout 时置顶
var month_progress: Panel
var month_progress_full_width: float = 320.0
var bank_button: Button
var pixel_font: Font
var pixel_regular_font: Font
var battle_bold_font: Font
var hint_text: String = DEFAULT_HINT
var selected_card = null
var toast_t: float = 0.0
var emergency: bool = false
var emergency_t: float = 0.0
var game_over: bool = false
var dbg_last := Vector2.ZERO
var view_zoom: float = 0.6             # 派生量：屏幕每 board 单位的像素数（特效仍按它缩放）
var view_offset: Vector2 = Vector2.ZERO   # 弃用（保留以兼容旧引用）
var panning_canvas: bool = false
var pan_last: Vector2 = Vector2.ZERO
const VIEW_ZOOM_MIN := 0.286
const VIEW_ZOOM_MAX := 6.0
const VIEW_ZOOM_STEP := 1.12

# ---- 3D 相机驱动（Phase 1）：缩放/平移动 City Builder 的 3D 相机 ----
# board 空间 [CANVAS_X0..X1]×[MID_Y0..MID_Y1] 线性映射到白板世界矩形（中心在世界原点）
const BOARD_CX := (CANVAS_X0 + CANVAS_X1) * 0.5   # 960
const BOARD_CY := (MID_Y0 + MID_Y1) * 0.5         # 580
const CARD3D_THICK := 0.05 / 3.0                    # 卡牌厚度（薄盒子，用来投射真阴影）
const CARD_PLANE_Y := 0.05 + CARD3D_THICK           # 卡顶高度（盒底正好贴白板）
const CARD3D_RADIUS := 9.0 / 180.0 * (CW / CITY_CELL) # 与 Card.CARD_RADIUS 一致的轻微圆角
const PACK3D_THICK := CARD3D_THICK * 2.5            # 卡包厚度（原厚度的一半）
const DEFAULT_CAM_PITCH_DEG := 77.0
const DEFAULT_CAM_DIST := 2.31
const VIEW_PREF_PATH := "user://startx_view.cfg"
var cam_dist: float = DEFAULT_CAM_DIST             # 相机距离（缩放）：默认聚焦起始车库创业包
var cam_target: Vector3 = Vector3.ZERO             # 相机注视点（平移，沿白板/城市平面）
var cam_pitch_deg: float = DEFAULT_CAM_PITCH_DEG   # 俯角（向前下/向后下按钮调节；越大越俯视）
const CAM_PITCH_MIN := 59.0
const CAM_PITCH_MAX := 86.0
const CAM_PITCH_STEP := 9.0
const CAM_DIST_MIN := 1.6
const CAM_DIST_MAX := 9.0
const CAM_DIST_STEP := 1.12
const FLY_OUT_TIME := 0.43
const FLY_OUT_ROT_TIME := 0.37

var departments: Array = []          # [{card, specialty, headcount, capacity, timer, interval}]
var research_panel: Control
var lbl_rp: Label
var research_rows: Array = []        # [{btn, id}]
var pack_buttons: Array = []         # [{btn, id, pack}]
var loose_packs: Array = []
var recipe_panel: PanelContainer
var recipe_list: RichTextLabel
var codex_panel: PanelContainer
var codex_grid: GridContainer
var codex_preview: Node2D
var codex_preview_bg: Panel
var settings_panel: PanelContainer
var gear_menu: Control
var school_empty_toast_t: float = 0.0
var val_timer: float = 0.0

const SCHOOL_INSIGHT_NEED := 25.0

var street_bg_tex: Texture2D = null
var ui_icon_cache: Dictionary = {}

func _ready() -> void:
	GameState.reset()
	street_bg_tex = _load_image_tex("res://assets/bg_street.png")
	_setup_city_background()
	face_baker = CardFaceBakerScript.new()
	add_child(face_baker)
	_load_cursors()
	month_time = float(DataLoader.balance.get("month_seconds", 90.0))
	_reset_view_default()               # 初始视角：画布水平居中、顶边锚定
	_build_hud()
	get_viewport().size_changed.connect(_layout_responsive)
	_layout_responsive()
	_spawn_start_cards()
	GameState.recipe_discovered.connect(_on_discovery)
	GameState.idea_unlocked.connect(_on_idea_unlocked)
	GameState.stage_changed.connect(_on_stage_changed)
	GameState.business_model_unlocked.connect(_on_business_model_unlocked)

	# 对手卡每 3 秒朝创始人方向跳动半张卡（随机折线）
	var rival_timer := Timer.new()
	rival_timer.name = "RivalHopTimer"
	rival_timer.wait_time = 3.0
	rival_timer.autostart = true
	add_child(rival_timer)
	rival_timer.timeout.connect(_rival_hop_tick)

func _screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _screen_center() -> Vector2:
	return _screen_size() * 0.5

func _bottom_y() -> float:
	return _screen_size().y - (BASE_H - INFO_Y)

# ---------------------------------------------------------------- perspective
func _row_scale(_y: float) -> float:
	return 1.0   # 透视交给 3D 相机，行缩放退役

# board 坐标 → 白板世界坐标（XZ 平面，y=卡面高）。白板中心在世界原点。
func board_to_world(p: Vector2) -> Vector3:
	return Vector3((p.x - BOARD_CX) / CITY_CELL, CARD_PLANE_Y, (p.y - BOARD_CY) / CITY_CELL)

func world_to_board(w: Vector3) -> Vector2:
	return Vector2(w.x * CITY_CELL + BOARD_CX, w.z * CITY_CELL + BOARD_CY)

func _cam() -> Camera3D:
	return city_bg.cam if (city_bg != null and city_bg.cam != null) else null

func _project(p: Vector2) -> Vector2:
	var c := _cam()
	if c == null:
		return p
	return c.unproject_position(board_to_world(p))

# 屏幕点 → 白板平面世界点
func _unproject_world(d: Vector2) -> Vector3:
	var c := _cam()
	if c == null:
		return Vector3(d.x, CARD_PLANE_Y, d.y)
	var o := c.project_ray_origin(d)
	var n := c.project_ray_normal(d)
	var denom := n.y
	if absf(denom) < 1e-6:
		return o
	var t := (CARD_PLANE_Y - o.y) / denom
	return o + n * t

func _unproject(d: Vector2) -> Vector2:
	return world_to_board(_unproject_world(d))

func _screen_to_view(p: Vector2) -> Vector2:
	return p

# 缩放：推拉 3D 相机距离（factor>1 = 拉近放大）。屏幕锚点暂忽略，绕注视点缩放。
func _zoom_view_at(_screen_pos: Vector2, factor: float) -> void:
	cam_dist = clampf(cam_dist / factor, CAM_DIST_MIN, CAM_DIST_MAX)
	_apply_camera()

func _apply_camera() -> void:
	if city_bg == null:
		return
	city_bg.pitch_deg = cam_pitch_deg
	city_bg.aim(cam_target, cam_dist)
	_clamp_view_offset()
	city_bg.aim(cam_target, cam_dist)
	_recompute_view_zoom()
	_relayout_all()
	_relayout_loose_packs()
	queue_redraw()

# 视角俯仰：向前下（更平视/前倾）/ 向后下（更俯视）
func _tilt_view(delta: float) -> void:
	cam_pitch_deg = clampf(cam_pitch_deg + delta, CAM_PITCH_MIN, CAM_PITCH_MAX)
	_save_default_camera_pitch(cam_pitch_deg)
	_apply_camera()

# 把 view_zoom 同步为「屏幕每 board 单位像素数」，让所有 *view_zoom 的特效继续合理缩放
func _recompute_view_zoom() -> void:
	var a := _project(Vector2(BOARD_CX, BOARD_CY))
	var b := _project(Vector2(BOARD_CX + 100.0, BOARD_CY))
	view_zoom = clampf(a.distance_to(b) / 100.0, 0.05, 8.0)

func _reset_view_default() -> void:
	cam_pitch_deg = DEFAULT_CAM_PITCH_DEG   # 进入/重置视角始终为 77° 俯角（不沿用上次保存的角度）
	cam_dist = DEFAULT_CAM_DIST
	cam_target = Vector3.ZERO
	_apply_camera()

func _load_default_camera_pitch() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(VIEW_PREF_PATH) != OK:
		return DEFAULT_CAM_PITCH_DEG
	return clampf(float(cfg.get_value("view", "cam_pitch_deg", DEFAULT_CAM_PITCH_DEG)), CAM_PITCH_MIN, CAM_PITCH_MAX)

func _save_default_camera_pitch(value: float) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("view", "cam_pitch_deg", clampf(value, CAM_PITCH_MIN, CAM_PITCH_MAX))
	var err := cfg.save(VIEW_PREF_PATH)
	if err != OK:
		push_warning("保存默认视角角度失败：%s (err=%d)" % [VIEW_PREF_PATH, err])

func _clamp_view_offset() -> void:
	var canvas_half_w := (CANVAS_X1 - CANVAS_X0) / CITY_CELL * 0.5
	var canvas_half_d := (MID_Y1 - MID_Y0) / CITY_CELL * 0.5
	var visible_half := _visible_world_half_extents()
	var half_w := canvas_half_w * 0.25 + maxf(0.0, canvas_half_w - visible_half.x)
	var half_d := canvas_half_d + maxf(0.0, canvas_half_d - visible_half.y)
	cam_target.x = clampf(cam_target.x, -half_w, half_w)
	cam_target.z = clampf(cam_target.z, -half_d, half_d)

func _visible_world_half_extents() -> Vector2:
	if _cam() == null:
		return Vector2(INF, INF)
	var screen := _screen_size()
	var pts := [
		_unproject_world(Vector2.ZERO),
		_unproject_world(Vector2(screen.x, 0.0)),
		_unproject_world(screen),
		_unproject_world(Vector2(0.0, screen.y)),
	]
	var min_x: float = pts[0].x
	var max_x: float = pts[0].x
	var min_z: float = pts[0].z
	var max_z: float = pts[0].z
	for p in pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	return Vector2((max_x - min_x) * 0.5, (max_z - min_z) * 0.5)

func _band(x0: float, x1: float, y0: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([
		_project(Vector2(x0, y0)), _project(Vector2(x1, y0)),
		_project(Vector2(x1, y1)), _project(Vector2(x0, y1))])

func _apply_card_projection(c: Node2D, bp: Vector2, keep_position: bool = false) -> void:
	var lift := Vector2(0, -_card_lift(c) * view_zoom)
	var tl := _project(bp) + lift
	var tr := _project(bp + Vector2(CW, 0)) + lift
	var bl := _project(bp + Vector2(0, CH)) + lift
	var x_axis := (tr - tl) / CW
	var y_axis := (bl - tl) / CH
	var pos := c.position if keep_position else tl
	c.transform = Transform2D(x_axis * CARD_SCALE, y_axis * CARD_SCALE, pos)

# ---------------------------------------------------------------- zone helpers
func is_person(c) -> bool:
	return c.ctype == "employee"

func _is_battle_person(c) -> bool:
	return is_instance_valid(c) and (c.ctype == "employee" or c.card_id == "founder")

func is_fixed(c) -> bool:
	return c.ctype == "resource_node" or c.ctype == "facility"

func is_resource_like(c) -> bool:
	return c.ctype == "resource" or c.ctype == "customer" or c.ctype == "product"

func region_of(p: Vector2) -> String:
	if p.y < DRAW_Y1:
		return "draw"
	if p.y >= ORG_Y0:
		return "org"
	return "office" if p.x < DIVIDER_X else "market"

func clamp_to_zone(pos: Vector2, _zone: String = "") -> Vector2:
	# 单一画布：不再分区，所有卡夹在整块画布内（zone 参数保留但不再限制横向）
	var y := clampf(pos.y, MID_Y0 + 2, MID_Y1 - CH)
	var x := clampf(pos.x, CANVAS_X0 + GAP, CANVAS_X1 - GAP - CW)
	return Vector2(x, y)

func _zone_for_center(_center: Vector2) -> String:
	return "all"

func _bank_rect() -> Rect2:
	if bank_button != null and is_instance_valid(bank_button):
		return Rect2(bank_button.position, bank_button.size)
	return BANK_RECT

# 3D 城市背景：在独立 SubViewport 渲染 Kenney 低多边形城市，作为画布外的背景层
var city_bg: SubViewport = null
const CityBackgroundScript = preload("res://scripts/CityBackground.gd")
const CardFaceBakerScript = preload("res://scripts/CardFaceBaker.gd")
var face_baker = null
# 3D 卡牌网格尺寸（世界单位）：board 120×180 / CITY_CELL(168)
const CARD3D_W := CW / CITY_CELL    # = 180/CELL，与卡牌实际尺寸一致（正方形）
const CARD3D_H := CH / CITY_CELL
const CARD3D_STACK_DY := 0.004     # 同栈每张抬高，避免共面闪烁
const CARD3D_ORDER_DY := 0.00002   # 不同栈完全重叠时，后出现的卡略高一点
func _setup_city_background() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CityBackground"
	layer.layer = -10                       # 在所有 2D 棋盘内容之后（最底）
	add_child(layer)
	city_bg = CityBackgroundScript.new()
	city_bg.size = Vector2i(_screen_size())
	layer.add_child(city_bg)
	_setup_supply_arrow_mesh()
	var tr := TextureRect.new()
	tr.name = "CityView"
	tr.texture = city_bg.get_texture()
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE   # 1:1 铺满，保证 unproject 屏幕坐标对齐
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tr)
	# 初始化 3D 相机（city_bg._ready 已建好 cam）
	_apply_camera()

func _setup_supply_arrow_mesh() -> void:
	supply_arrow_mesh = MeshInstance3D.new()
	supply_arrow_mesh.name = "SupplyArrows"
	supply_arrow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	supply_arrow_mesh.material_override = material
	city_bg.world_card_root().add_child(supply_arrow_mesh)

func _load_image_tex(path: String) -> Texture2D:
	# 读取 Godot 导入后的资源；直接 Image.load() 在 Web 导出中拿不到源文件。
	return ResourceLoader.load(path) as Texture2D if ResourceLoader.exists(path) else null

# 画布外的俯视街道：在围绕画布的大世界矩形内平铺街景图，随透视投影/缩放一起平移
const STREET_TILE_W := 2600.0   # 单张街景图覆盖的世界宽
const STREET_TILE_H := 1900.0   # 单张街景图覆盖的世界高
const STREET_EDGE := Color("8f968f")   # 画布圆角缺口填充色（街道中性灰，融入城市）
func _draw_street() -> void:
	if street_bg_tex == null:
		return
	var cx := (CANVAS_X0 + CANVAS_X1) * 0.5
	var cy := (MID_Y0 + MID_Y1) * 0.5
	# 足够大，缩到最小（居中）时也铺满屏幕
	var half_w := 6200.0
	var half_h := 4600.0
	var sx0 := cx - half_w
	var sy0 := cy - half_h
	var tiles_x := int(ceil(half_w * 2.0 / STREET_TILE_W))
	var tiles_y := int(ceil(half_h * 2.0 / STREET_TILE_H))
	var sub := 3
	for ti in range(tiles_x):
		for tj in range(tiles_y):
			var ox := sx0 + ti * STREET_TILE_W
			var oy := sy0 + tj * STREET_TILE_H
			for r in range(sub):
				var v0 := float(r) / sub
				var v1 := float(r + 1) / sub
				for c in range(sub):
					var u0 := float(c) / sub
					var u1 := float(c + 1) / sub
					var w_tl := Vector2(ox + u0 * STREET_TILE_W, oy + v0 * STREET_TILE_H)
					var w_tr := Vector2(ox + u1 * STREET_TILE_W, oy + v0 * STREET_TILE_H)
					var w_br := Vector2(ox + u1 * STREET_TILE_W, oy + v1 * STREET_TILE_H)
					var w_bl := Vector2(ox + u0 * STREET_TILE_W, oy + v1 * STREET_TILE_H)
					var quad := PackedVector2Array([
						_project(w_tl), _project(w_tr), _project(w_br), _project(w_bl)])
					var uvs := PackedVector2Array([
						Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
					draw_colored_polygon(quad, Color.WHITE, uvs, street_bg_tex)

func _load_cursors() -> void:
	CursorManager.reset()

func _set_cursor_state(state: String) -> void:
	if cursor_state == state:
		return
	cursor_state = state
	CursorManager.set_state(state)

# ---------------------------------------------------------------- spawning
const START_JITTER := 130.0     # 初始卡随机散布幅度（加大随机性）

func _jit(amount: float) -> Vector2:
	return Vector2(GameState.rng.randf_range(-amount, amount), GameState.rng.randf_range(-amount, amount))

func _spawn_start_cards() -> void:
	# 开局只有一个车库包（5 张牌，含创始人）；点一下跳一张，点完消失
	var pack: Dictionary = DataLoader.packs.get("garage_pack", {"name": "车库创业包"})
	var contents := ["founder", "p1_neighborhood", "p1_wholesale", "p1_office", "cash", "cash"]
	# 开局卡包直接弹到屏幕中央：以屏幕中心反投影到 board，再减去半张卡居中
	var center_tl := _unproject(_screen_center() \
		- Vector2(PACK_W, PACK_H) * 0.5 * view_zoom)
	_spawn_loose_pack("garage_pack", pack, contents, center_tl, true)   # 直接 3D 出现在白板上

func _spawn_card_pop(id: String, pos: Vector2, delay: float = 0.0) -> Node2D:
	var c := spawn_card(id, pos)
	_play_card_pop(c, delay)
	return c

func spawn_card(id: String, pos: Vector2) -> Node2D:
	if id == "founder" and _founder_on_board() != null:
		return null
	var first_appearance := not GameState.drawn_cards.has(id)
	if first_appearance:
		GameState.drawn_cards[id] = true
	var c = CardScript.new()
	add_child(c)
	c.setup(id)
	c.is_new_discovery = first_appearance and c.ctype != "rival"
	if not is_person(c):
		c.zone = _zone_for_center(pos + Vector2(CW * 0.5, CH * 0.5))
	var sid := next_stack_id
	next_stack_id += 1
	c.stack_id = sid
	c.stack_pos = 0
	stacks[sid] = [c] as Array
	stack_base[sid] = pos
	all_cards.append(c)
	relayout(sid)
	return c

func _founder_on_board():
	for c in all_cards:
		if is_instance_valid(c) and c.card_id == "founder":
			return c
	return null

func _play_card_pop(c, delay: float = 0.0, from_display = null) -> void:
	if not is_instance_valid(c):
		return
	var final_pos: Vector2 = c.position
	var final_scale: Vector2 = c.scale
	if from_display != null:
		c.position = (from_display as Vector2) - Vector2(CW, CH) * 0.35 * maxf(view_zoom, 0.1)
	else:
		c.position = final_pos + Vector2(0, 24.0 * view_zoom)
	c.scale = final_scale * 0.18
	c.rotation = GameState.rng.randf_range(-0.06, 0.06)
	var old_z: int = c.z_index
	c.z_index = max(old_z, 2300)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "position", final_pos, 0.36).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", final_scale, 0.36).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", 0.0, 0.30).set_delay(delay)
	tw.chain().tween_callback(func():
		if is_instance_valid(c):
			c.z_index = old_z
			relayout(c.stack_id)
	)

# ---------------------------------------------------------------- stack utils
func relayout(sid: int) -> void:
	if not stacks.has(sid):
		return
	var arr: Array = stacks[sid]
	var base: Vector2 = stack_base[sid]
	var zbase := DRAG_Z if sid == drag_sid else (BATTLE_Z if sid == battle_attacker_sid else 0)
	for i in arr.size():
		var c = arr[i]
		c.stack_pos = i
		var bp := base + Vector2(0, i * CARD_OFFSET)        # board space
		_apply_card_projection(c, bp, sid == drag_sid)      # 仍设 c.transform 供旧 2D 代码读位置
		c.z_index = zbase + i
		if sid == drag_sid:
			_place_face3d_from_display(c, c.position, bp, i, true)
		else:
			_place_face3d(c, bp, i, false)                  # 真 3D 卡牌网格

# ---- Phase 2：3D 卡牌网格 ----
# c.face3d = pivot(Node3D)，pivot 下挂 MeshInstance3D(卡面)。relayout 只动 pivot 的
# transform；pop/hover 等动画改 mesh 的 scale/emission，互不覆盖。
func _ensure_face3d(c) -> void:
	if c.face3d != null and is_instance_valid(c.face3d):
		return
	if city_bg == null or city_bg.world_card_root() == null:
		return
	c.visible = false                                       # 2D 卡面隐藏，仅留作逻辑/烘焙源
	var pivot := Node3D.new()
	var cardroot := Node3D.new()                            # 可缩放节点（pop/dissolve），relayout 不动它
	pivot.add_child(cardroot)
	# 卡身边框（黑，与牌面黑框线一致）：满尺寸薄盒 → 投射阴影 + 厚度上下黑边线
	var frame := MeshInstance3D.new()
	var fbm := _rounded_card_box_mesh(CARD3D_W, CARD3D_H, CARD3D_THICK, CARD3D_RADIUS)
	frame.mesh = fbm
	frame.position = Vector3(0, -CARD3D_THICK * 0.5, 0)     # 顶面在 cardroot 原点、底面贴白板
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color("141414")
	frame.material_override = fmat
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	cardroot.add_child(frame)
	# 厚度涂色（奶白）：X/Z 略大盖住侧面中段、Y 内缩露出上下黑框线
	var eb := 0.00867
	var body := MeshInstance3D.new()
	var bm := _rounded_card_box_mesh(
		CARD3D_W * 1.004,
		CARD3D_H * 1.004,
		CARD3D_THICK - eb * 2.0,
		CARD3D_RADIUS
	)
	body.mesh = bm
	body.position = Vector3(0, -CARD3D_THICK * 0.5, 0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = c.body_color()                     # 厚度=卡牌本身的颜色
	bmat.roughness = 0.9
	body.material_override = bmat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cardroot.add_child(body)
	# 卡面：整张 2D 卡面以 1024 烘焙后贴在盒子顶面
	var m := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(CARD3D_W, CARD3D_H)
	m.mesh = qm
	m.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	m.position = Vector3(0, 0.002, 0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.86, 0.84, 0.78)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # 卡面保持原色
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cardroot.add_child(m)
	if c.is_cash or c.ctype == "business_model":
		_add_glass_coat(cardroot, CARD3D_W, CARD3D_H, 0.004)   # 现金 / 商业模式：玻璃反光
	if c.card_id == "founder":
		_add_holo_coat(cardroot, CARD3D_W, CARD3D_H, 0.004)   # 创始人：彩色镭射效果
	if c.is_new_discovery:
		_add_new_card_badge(c, cardroot)
	# 拿起时的 solid 同形阴影：贴白板的浅色圆角方块（与 cardroot 同级，不受 pop 缩放影响）
	var shadow := MeshInstance3D.new()
	shadow.name = "DropShadow"
	var sqm := QuadMesh.new()
	sqm.size = Vector2(CARD3D_W, CARD3D_H) * 1.3
	shadow.mesh = sqm
	shadow.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_texture = _blob_shadow_tex()
	smat.albedo_color = Color(0, 0, 0, 0.0)
	smat.render_priority = -1
	shadow.material_override = smat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.visible = false
	pivot.add_child(shadow)
	city_bg.world_card_root().add_child(pivot)
	c.face3d = pivot
	c.tree_exited.connect(func():
		if c.new_badge_tween != null and c.new_badge_tween.is_valid():
			c.new_badge_tween.kill()
		if is_instance_valid(pivot):
			pivot.queue_free())
	_bake_face_async(c, mat)
	# 出现时弹一下（整张卡 scale 0→1）
	cardroot.scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(cardroot, "scale", Vector3.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _add_new_card_badge(c, cardroot: Node3D) -> void:
	var badge := Node3D.new()
	badge.name = "NewBadge"
	badge.position = Vector3(CARD3D_W * 0.46, 0.011, -CARD3D_H * 0.46)
	var mesh_instance := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	var badge_size := CARD3D_W * 0.34 * 1.3
	mesh.size = Vector2(badge_size, badge_size)
	mesh_instance.mesh = mesh
	mesh_instance.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.25
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = load("res://assets/ui/new.svg")
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	badge.add_child(mesh_instance)
	cardroot.add_child(badge)
	c.new_badge3d = badge
	badge.scale = Vector3.ONE * 0.95
	var pulse := create_tween()
	pulse.tween_property(badge, "scale", Vector3.ONE * 1.05, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(badge, "scale", Vector3.ONE * 0.95, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.set_loops()
	c.new_badge_tween = pulse

func _dismiss_new_card_badge(c) -> void:
	if c == null or not is_instance_valid(c) or not c.is_new_discovery:
		return
	c.is_new_discovery = false
	if c.new_badge_tween != null and c.new_badge_tween.is_valid():
		c.new_badge_tween.kill()
	c.new_badge_tween = null
	var badge = c.new_badge3d
	c.new_badge3d = null
	if badge == null or not is_instance_valid(badge):
		return
	var tw := create_tween()
	tw.tween_property(badge, "scale", Vector3.ZERO, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(badge.queue_free)

func _rounded_card_box_mesh(width: float, height: float, thickness: float, radius: float) -> ArrayMesh:
	var perimeter := PackedVector2Array()
	var centers := [
		Vector2(width * 0.5 - radius, height * 0.5 - radius),
		Vector2(-width * 0.5 + radius, height * 0.5 - radius),
		Vector2(-width * 0.5 + radius, -height * 0.5 + radius),
		Vector2(width * 0.5 - radius, -height * 0.5 + radius),
	]
	var starts := [0.0, PI * 0.5, PI, PI * 1.5]
	const CORNER_STEPS := 4
	for corner in 4:
		for step in CORNER_STEPS:
			var angle: float = starts[corner] + (PI * 0.5) * float(step) / float(CORNER_STEPS)
			perimeter.append(centers[corner] + Vector2(cos(angle), sin(angle)) * radius)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var top_y := thickness * 0.5
	var bottom_y := -thickness * 0.5
	var count := perimeter.size()

	# 顶面和底面各用一个中心扇形。
	vertices.append(Vector3(0, top_y, 0))
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))
	for point in perimeter:
		vertices.append(Vector3(point.x, top_y, point.y))
		normals.append(Vector3.UP)
		uvs.append(Vector2(point.x / width + 0.5, point.y / height + 0.5))
	for i in count:
		indices.append(0)
		indices.append(1 + (i + 1) % count)
		indices.append(1 + i)

	var bottom_center := vertices.size()
	vertices.append(Vector3(0, bottom_y, 0))
	normals.append(Vector3.DOWN)
	uvs.append(Vector2(0.5, 0.5))
	var bottom_start := vertices.size()
	for point in perimeter:
		vertices.append(Vector3(point.x, bottom_y, point.y))
		normals.append(Vector3.DOWN)
		uvs.append(Vector2(point.x / width + 0.5, point.y / height + 0.5))
	for i in count:
		indices.append(bottom_center)
		indices.append(bottom_start + (i + 1) % count)
		indices.append(bottom_start + i)

	# 侧面独立顶点，保证法线沿圆角轮廓向外。
	for i in count:
		var a := perimeter[i]
		var b := perimeter[(i + 1) % count]
		var side_start := vertices.size()
		var outward := Vector3(a.x + b.x, 0, a.y + b.y).normalized()
		vertices.append(Vector3(a.x, top_y, a.y))
		vertices.append(Vector3(b.x, top_y, b.y))
		vertices.append(Vector3(b.x, bottom_y, b.y))
		vertices.append(Vector3(a.x, bottom_y, a.y))
		for j in 4:
			normals.append(outward)
			uvs.append(Vector2(float(j % 2), float(j / 2)))
		indices.append_array(PackedInt32Array([
			side_start, side_start + 1, side_start + 2,
			side_start, side_start + 2, side_start + 3,
		]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

var _blob_tex: Texture2D = null
func _blob_shadow_tex() -> Texture2D:
	if _blob_tex != null:
		return _blob_tex
	# 与卡牌同形：正方形圆角，solid 实心填充 + 窄柔边（仅抗锯齿）
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var edge := 4.0       # 柔边宽度（像素，仅抗锯齿）
	var rad := 12.0       # 圆角半径
	var hx := w * 0.5
	var hy := h * 0.5
	for y in h:
		for x in w:
			# 到「内缩圆角矩形」外部的距离 → 柔边
			var dx := maxf(absf(float(x) - hx + 0.5) - (hx - rad - edge), 0.0)
			var dy := maxf(absf(float(y) - hy + 0.5) - (hy - rad - edge), 0.0)
			var dist := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - dist / edge, 0.0, 1.0)
			img.set_pixel(x, y, Color(0, 0, 0, a))
	_blob_tex = ImageTexture.create_from_image(img)
	return _blob_tex

func _face3d_mesh(c) -> MeshInstance3D:
	if c.face3d != null and is_instance_valid(c.face3d) and c.face3d.get_child_count() > 0:
		var root: Node = c.face3d.get_child(0)
		if root != null and root.get_child_count() > 2:
			return root.get_child(2) as MeshInstance3D
	return null

# 玻璃反光罩：覆在卡面上的一层加色斜光带。只有 1~2 条窄斜光带代表玻璃反光，
# 黑色处=完全不增亮、不改卡面颜色；光带随视角移动 → 玻璃反光感，但卡色不变。
var _glass_shader: Shader = null
func _glass_coat_shader() -> Shader:
	if _glass_shader != null:
		return _glass_shader
	_glass_shader = Shader.new()
	_glass_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, depth_test_disabled;

uniform float intensity = 0.1;

void fragment() {
	// 沿视角方向平移光带 → 倾斜/转动卡面时反光带滑动
	float off = VIEW.x * 0.65 + VIEW.y * 0.35;
	// 斜对角坐标
	float t = UV.x * 0.72 + (1.0 - UV.y) * 0.72 + off;
	// 主光带（较亮较宽）
	float d1 = fract(t) - 0.5;
	float b1 = exp(-(d1 * d1) / (2.0 * 0.060 * 0.060));
	// 次光带（更窄更淡）
	float d2 = fract(t + 0.34) - 0.5;
	float b2 = 0.45 * exp(-(d2 * d2) / (2.0 * 0.035 * 0.035));
	float band = (b1 + b2) * intensity;
	ALBEDO = vec3(band);   // 加色混合：黑(0)不改色，光带处微微提亮
	ALPHA = 1.0;
}
"""
	return _glass_shader

func _add_glass_coat(parent: Node3D, w: float, h: float, y: float) -> void:
	var g := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	g.mesh = qm
	g.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	g.position = Vector3(0, y, 0)
	var gm := ShaderMaterial.new()
	gm.shader = _glass_coat_shader()
	g.material_override = gm
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(g)

# 彩色镭射反光罩：覆在卡面上的一层加色彩虹镭射效果（用于创始人卡牌）。
# 会随视角倾斜滑动，并伴随微小的金属闪光颗粒感。
var _holo_shader: Shader = null
func _holo_coat_shader() -> Shader:
	if _holo_shader != null:
		return _holo_shader
	_holo_shader = Shader.new()
	_holo_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, depth_test_disabled;

uniform float intensity = 0.16;

vec3 rainbow(float t) {
	return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

void fragment() {
	// 视角偏移，倾斜卡片时发生滑动
	float view_offset = VIEW.x * 0.75 + VIEW.y * 0.75;
	
	// 彩虹基础坐标
	float t = UV.x * 0.5 + UV.y * 0.5 + view_offset * 0.5;
	vec3 base_rainbow = rainbow(t);
	
	// 高频闪烁亮片效果（模拟金属镭射微粒）
	float sparkle1 = sin(UV.x * 150.0) * sin(UV.y * 150.0);
	float sparkle2 = sin(UV.x * 80.0 - VIEW.x * 30.0) * sin(UV.y * 80.0 - VIEW.y * 30.0);
	float sparkle = clamp((sparkle1 * sparkle2) * 4.0 - 2.8, 0.0, 1.0);
	
	// 双层彩虹条纹交叉，更有立体镭射质感
	float t2 = (1.0 - UV.x) * 0.4 + UV.y * 0.4 - view_offset * 0.3;
	vec3 cross_rainbow = rainbow(t2);
	
	// 混合两组彩虹以及亮片
	vec3 final_color = mix(base_rainbow, cross_rainbow, 0.4) * intensity;
	final_color += vec3(sparkle * 0.3);
	
	ALBEDO = final_color;
	ALPHA = 1.0;
}
"""
	return _holo_shader

func _add_holo_coat(parent: Node3D, w: float, h: float, y: float) -> void:
	var g := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	g.mesh = qm
	g.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	g.position = Vector3(0, y, 0)
	var gm := ShaderMaterial.new()
	gm.shader = _holo_coat_shader()
	g.material_override = gm
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(g)

func _bake_face_async(c, mat) -> void:
	if face_baker == null or c == null or not is_instance_valid(c):
		return
	var revision := int(c.get_meta("face_bake_revision", 0)) + 1
	c.set_meta("face_bake_revision", revision)
	var tex = await face_baker.bake(c)
	if not is_instance_valid(c) or int(c.get_meta("face_bake_revision", 0)) != revision:
		return
	if tex != null and is_instance_valid(mat):
		mat.albedo_texture = tex
		mat.albedo_color = Color(1, 1, 1)
		if mat.emission_enabled:
			mat.emission_texture = tex

func _refresh_card_face(c) -> void:
	if c == null or not is_instance_valid(c):
		return
	c.queue_redraw()
	var mesh := _face3d_mesh(c)
	if mesh == null:
		return
	var mat = mesh.material_override
	if mat != null:
		_bake_face_async(c, mat)

func _place_face3d(c, bp: Vector2, idx: int, dragging: bool) -> void:
	_ensure_face3d(c)
	var pivot = c.face3d
	if pivot == null or not is_instance_valid(pivot):
		return
	var w := board_to_world(bp + Vector2(CW * 0.5, CH * 0.5))
	var lift := _face3d_lift(c, idx, dragging)
	w.y = CARD_PLANE_Y + lift
	pivot.transform = Transform3D(Basis.IDENTITY, w)
	_update_drop_shadow(c, lift, idx, dragging)

func _place_face3d_from_display(c, display_topleft: Vector2, bp: Vector2, idx: int, dragging: bool) -> void:
	_ensure_face3d(c)
	var pivot = c.face3d
	if pivot == null or not is_instance_valid(pivot):
		return
	var center_offset := _project(bp + Vector2(CW * 0.5, CH * 0.5)) - _project(bp)
	var w := _unproject_world(display_topleft + center_offset)
	var lift := _face3d_lift(c, idx, dragging)
	w.y = CARD_PLANE_Y + lift
	pivot.transform = Transform3D(Basis.IDENTITY, w)
	_update_drop_shadow(c, lift, idx, dragging)

# 拿起时的 solid 同形阴影：浅色方形贴白板，真实投影同时关闭（互斥，避免双重阴影）。
# 整叠拖动只有最底一张（idx 0）显示，防止半透明阴影叠加变黑。
const DROP_SHADOW_ALPHA := 0.5
func _update_drop_shadow(c, lift: float, idx: int, dragging: bool) -> void:
	var pivot = c.face3d
	if pivot == null or not is_instance_valid(pivot):
		return
	var shadow := pivot.get_node_or_null("DropShadow") as MeshInstance3D
	if shadow == null:
		return
	var picked: bool = c.carried or dragging
	# 紧贴选中卡牌底面，使阴影显示在下层卡牌之上。
	shadow.position = Vector3(lift * 0.3, -(CARD3D_THICK + 0.0015), lift * 0.3)
	var cardroot: Node = pivot.get_child(0)
	if cardroot != null and cardroot.get_child_count() > 0:
		var frame := cardroot.get_child(0) as MeshInstance3D
		if frame != null:
			frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if picked \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var target := DROP_SHADOW_ALPHA if (picked and idx == 0) else 0.0
	if absf(float(pivot.get_meta("shadow_a", -1.0)) - target) < 0.001:
		return
	pivot.set_meta("shadow_a", target)
	var mat := shadow.material_override as StandardMaterial3D
	if mat == null:
		return
	if target > 0.0:
		shadow.visible = true
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", target, 0.12)
	if target <= 0.0:
		tw.tween_callback(func():
			if is_instance_valid(shadow) and is_instance_valid(pivot) \
					and float(pivot.get_meta("shadow_a", 0.0)) <= 0.001:
				shadow.visible = false)

func _face3d_lift(c, idx: int, dragging: bool) -> float:
	var lift := float(idx) * CARD3D_STACK_DY
	lift += float(maxi(c.stack_id, 0)) * CARD3D_ORDER_DY
	if c.carried or dragging:
		lift += 0.05335       # 拿起/选中抬升减半
	elif c.hovered:
		lift += 0.02          # hover 时轻轻上抬（单牌/整叠均适用）
	return lift

func _relayout_all() -> void:
	for sid in stacks.keys():
		relayout(int(sid))

func _board_topleft(c) -> Vector2:
	var b: Vector2 = stack_base[c.stack_id]
	return Vector2(b.x, b.y + c.stack_pos * CARD_OFFSET)

func _board_center(c) -> Vector2:
	return _board_topleft(c) + Vector2(CW, CH) * 0.5

func _card_lift(c) -> float:
	if c == null or not is_instance_valid(c):
		return 0.0
	if c.carried:
		return 3.665
	if c.hovered:
		return 3.33
	return 0.0

func _stack_size_for_card(c) -> int:
	if c == null or not is_instance_valid(c) or not stacks.has(c.stack_id):
		return 0
	return stacks[c.stack_id].size()

func _cash_card_count() -> int:
	var n := 0
	for c in all_cards:
		if c.card_id == "cash":
			n += 1
	return n

func _sync_cash_state() -> void:
	GameState.cash = GameState.dev_base_cash + _cash_card_count()

func _spend_cash_cards(amount: int) -> bool:
	_sync_cash_state()
	if GameState.cash < amount:
		return false
	var need := amount
	for c in all_cards.duplicate():
		if need <= 0:
			break
		if c.card_id != "cash":
			continue
		destroy_card(c)
		need -= 1
	if need > 0:
		GameState.dev_base_cash -= need
		need = 0
	_sync_cash_state()
	return true

func _spawn_cash_cards(amount: int, around: Vector2, zone: String = "office", from_display = null) -> void:
	if amount <= 0:
		return
	# 一批现金叠成一摞：朝旁边飞出一小段后落在同一摞里，快速依次弹出
	var ang := GameState.rng.randf() * TAU
	var land := clamp_to_zone(around + Vector2(cos(ang), sin(ang)) * 130.0, zone)
	var first := spawn_card("cash", land)
	first.zone = zone
	var sid: int = first.stack_id
	for i in range(1, amount):
		var c := spawn_card("cash", land)
		c.zone = zone
		sid = _merge(c.stack_id, sid)   # 并入同一摞（_merge 会生成新栈号，须回写）
	relayout(sid)
	var origin_display: Vector2 = (from_display as Vector2) if from_display != null else _project(around + Vector2(CW, CH) * 0.5)
	var arr: Array = stacks[sid]
	for i in arr.size():
		_play_card_pop(arr[i], 0.05 * i, origin_display)
	_sync_cash_state()

func destroy_card(c) -> void:
	var sid: int = c.stack_id
	if stacks.has(sid):
		stacks[sid].erase(c)
		if stacks[sid].is_empty():
			stacks.erase(sid)
			stack_base.erase(sid)
			productions.erase(sid)
	all_cards.erase(c)
	c.queue_free()

# Remove from game logic, then shrink the card into a rising smoke burst.
func _dissolve_node(c) -> void:
	var sid: int = c.stack_id
	if stacks.has(sid):
		stacks[sid].erase(c)
		if stacks[sid].is_empty():
			stacks.erase(sid)
			stack_base.erase(sid)
			productions.erase(sid)
	all_cards.erase(c)
	if is_instance_valid(c.face3d):
		_smoke_burst3d(c.face3d.global_position)
	c.z_index = 2500
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "scale", c.scale * 0.05, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "modulate", Color(0.35, 0.35, 0.35, 0.0), 0.34)
	tw.tween_property(c, "rotation", 0.35, 0.34)
	tw.tween_property(c, "position:y", c.position.y - 22, 0.34)
	tw.chain().tween_callback(c.queue_free)
	# 3D 卡牌整体缩进烟里，同时轻微上浮。
	if is_instance_valid(c.face3d) and c.face3d.get_child_count() > 0:
		var cardroot := c.face3d.get_child(0) as Node3D
		var tw3 := create_tween()
		tw3.set_parallel(true)
		if cardroot != null:
			tw3.tween_property(cardroot, "scale", Vector3.ZERO, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw3.tween_property(c.face3d, "position:y", c.face3d.position.y + 0.10, 0.32)
	if stacks.has(sid):
		relayout(sid)

func _smoke_burst3d(world_pos: Vector3) -> void:
	if city_bg == null or city_bg.world_card_root() == null:
		return
	var smoke := CPUParticles3D.new()
	smoke.emitting = false
	smoke.amount = 20
	smoke.lifetime = 0.68
	smoke.one_shot = true
	smoke.explosiveness = 0.88
	smoke.randomness = 0.55
	smoke.local_coords = false
	smoke.direction = Vector3.UP
	smoke.spread = 42.0
	smoke.initial_velocity_min = 0.24
	smoke.initial_velocity_max = 0.58
	smoke.gravity = Vector3(0, 0.18, 0)
	smoke.damping_min = 0.25
	smoke.damping_max = 0.65
	smoke.radial_accel_min = 0.08
	smoke.radial_accel_max = 0.22
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	smoke.emission_box_extents = Vector3(CW / CITY_CELL * 0.24, 0.018, CH / CITY_CELL * 0.25)
	smoke.scale_amount_min = 0.065
	smoke.scale_amount_max = 0.14
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.35))
	scale_curve.add_point(Vector2(0.32, 1.0))
	scale_curve.add_point(Vector2(1.0, 1.28))
	smoke.scale_amount_curve = scale_curve
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.18, 0.72, 1.0])
	colors.colors = PackedColorArray([
		Color(0.82, 0.82, 0.79, 0.0),
		Color(0.64, 0.64, 0.61, 0.82),
		Color(0.39, 0.39, 0.38, 0.42),
		Color(0.25, 0.25, 0.25, 0.0)
	])
	smoke.color_ramp = colors
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 8
	puff.rings = 4
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	puff.material = mat
	smoke.mesh = puff
	smoke.visibility_aabb = AABB(Vector3(-2, -0.2, -2), Vector3(4, 3, 4))
	city_bg.world_card_root().add_child(smoke)
	smoke.global_position = world_pos + Vector3(0, 0.04, 0)
	smoke.restart()
	smoke.emitting = true
	smoke.finished.connect(smoke.queue_free)

# ---------------------------------------------------------------- input / drag
func _to_world(event: InputEvent) -> Vector2:
	return get_canvas_transform().affine_inverse() * (event as InputEventMouse).position

func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var wp := _to_world(event)
		dbg_last = _unproject(wp)
		if event.pressed:
			var delete_chain = _supply_delete_chain_at(wp)
			if delete_chain != null:
				supply_chains.erase(delete_chain)
				supply_hover_chain = null
				supply_hover_scale = 0.0
				_show_toast("供应链已解除")
				queue_redraw()
				return
			panning_canvas = false
			if not drag_cards.is_empty():
				_end_drag(wp)            # 携带中再次点击 = 放下
			else:
				var pack: Node2D = _topmost_pack_at(wp)
				if pack != null:
					# 按住卡包：先记为待拖动；松开时没移动=拆一张，移动了=只是挪位置
					drag_pack = pack
					pack_drag_offset = _unproject(wp) - pack.board_pos
					press_pos = wp
					press_moved = false
					pack.z_index = 2300
					return
				var picked := _topmost_at(wp, battle_active)
				if battle_active and picked != null and _is_battle_combatant_stack(picked.stack_id):
					return                   # 交战双方锁定；框外其它卡仍可自由拖动
				if picked != null:
					_begin_drag(wp, picked)          # 点击即拿起并跟随光标（sticky）
					press_pos = wp
					press_moved = false
				else:
					_deselect()
					panning_canvas = true
					pan_last = wp
					_set_cursor_state("pan")   # 用自定义“拖动画布”光标（原来这里误设系统光标→突然变大）
		else:
			panning_canvas = false
			# 卡包：松开时若没移动=拆一张；移动过=留在新位置
			if drag_pack != null:
				var p := drag_pack
				drag_pack = null
				if is_instance_valid(p):
					p.z_index = 2100
					if not press_moved:
						_open_loose_pack(p)
				return
			# 松开：真正拖动过才落下；只是轻点则保持携带、继续跟随光标
			if not drag_cards.is_empty() and press_moved:
				_end_drag(wp)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_view_at(_to_world(event), VIEW_ZOOM_STEP)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_view_at(_to_world(event), 1.0 / VIEW_ZOOM_STEP)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		var wp := _to_world(event)
		if event.pressed:
			var picked := _topmost_at(wp, true)
			if picked != null and productions.has(picked.stack_id):
				_begin_supply_drag(picked, wp)
			else:
				# 非生产牌堆上右键仍保持原来的“放下/取消选择”行为。
				if not drag_cards.is_empty():
					_cancel_drag()
				_deselect()
		elif supply_drag_source != null:
			_end_supply_drag(wp)
	elif event is InputEventMouseMotion and panning_canvas:
		var wp := _to_world(event)
		# 抓取式平移：让光标下的世界点跟手 → 反向移动相机注视点
		var w_last := _unproject_world(pan_last)
		var w_now := _unproject_world(wp)
		cam_target += Vector3(w_last.x - w_now.x, 0.0, w_last.z - w_now.z)
		pan_last = wp
		_apply_camera()
	elif event is InputEventMouseMotion and drag_pack != null:
		var wp := _to_world(event)
		if is_instance_valid(drag_pack):
			drag_pack.board_pos = _unproject(wp) - pack_drag_offset
			drag_pack.position = _project(drag_pack.board_pos)
			_place_pack3d(drag_pack)
			if wp.distance_to(press_pos) > DRAG_TAP_PX:
				press_moved = true
	elif event is InputEventMouseMotion and not drag_cards.is_empty():
		var wp := _to_world(event)
		stack_base[drag_sid] = _unproject(wp) - drag_offset
		relayout(drag_sid)
		if wp.distance_to(press_pos) > DRAG_TAP_PX:
			press_moved = true
	elif event is InputEventMouseMotion and supply_drag_source != null:
		supply_drag_mouse = _to_world(event)
		supply_drag_target = _supply_target_at(supply_drag_mouse)
		queue_redraw()

func _begin_supply_drag(picked, wp: Vector2) -> void:
	if picked == null or not is_instance_valid(picked) or not productions.has(picked.stack_id):
		return
	var source = _supply_source_anchor(picked.stack_id)
	if source == null:
		return
	supply_drag_source = source
	supply_drag_mouse = wp
	supply_drag_target = null
	panning_canvas = false
	_show_toast("拖到可互动的下游牌堆，松开右键建立供应链")
	queue_redraw()

func _end_supply_drag(wp: Vector2) -> void:
	supply_drag_mouse = wp
	var target = _supply_target_at(wp)
	if target != null:
		_set_supply_chain(supply_drag_source, target)
		_show_toast("供应链已连接：产出将直接叠到下游")
	supply_drag_source = null
	supply_drag_target = null
	queue_redraw()

func _supply_source_anchor(sid: int):
	if not productions.has(sid) or not stacks.has(sid):
		return null
	var rec: Dictionary = productions[sid].get("recipe", {})
	for inp in rec.get("inputs", []):
		if inp.get("consume", false):
			continue
		var input_id := String(inp.get("id", ""))
		for c in stacks[sid]:
			if c.card_id == input_id:
				return c
	for c in stacks[sid]:
		if is_person(c):
			return c
	return stacks[sid][0] if not stacks[sid].is_empty() else null

func _supply_target_at(display_pt: Vector2):
	var target = _topmost_at(display_pt, true)
	if target == null or not is_instance_valid(target):
		return null
	if supply_drag_source == null or not is_instance_valid(supply_drag_source):
		return null
	if target.stack_id == supply_drag_source.stack_id:
		return null
	if not _stack_accepts_supply_outputs(supply_drag_source.stack_id, target.stack_id):
		return null
	return target

func _set_supply_chain(source, target) -> void:
	if source == null or target == null:
		return
	for chain in supply_chains:
		if chain.get("source") == source:
			chain["target"] = target
			return
	supply_chains.append({"source": source, "target": target})

func _supply_delete_chain_at(display_pt: Vector2):
	if supply_hover_chain == null or not supply_chains.has(supply_hover_chain):
		return null
	var center := _supply_chain_midpoint(supply_hover_chain)
	var radius := 18.0 * maxf(supply_hover_scale, 0.65)
	return supply_hover_chain if center.distance_to(display_pt) <= radius else null

func _stack_accepts_supply_outputs(source_sid: int, target_sid: int) -> bool:
	if not productions.has(source_sid) or not stacks.has(target_sid):
		return false
	var rec: Dictionary = productions[source_sid].get("recipe", {})
	for outp in rec.get("outputs", []):
		var output_id := "cash" if outp.has("cash") else String(outp.get("id", ""))
		if output_id != "" and _output_id_interacts_with_stack(output_id, target_sid):
			return true
	return false

func _output_id_interacts_with_stack(output_id: String, target_sid: int) -> bool:
	if output_id == "" or not stacks.has(target_sid):
		return false
	var counts: Dictionary = {output_id: 1}
	var all_same := true
	var first_id := output_id
	var has_worker := DataLoader.card_type(output_id) == "employee"
	for c in stacks[target_sid]:
		counts[c.card_id] = int(counts.get(c.card_id, 0)) + 1
		if c.card_id != first_id:
			all_same = false
		if c.ctype == "employee":
			has_worker = true
	if all_same and not has_worker and DataLoader.card_type(output_id) not in ["department", "risk", "idea"]:
		return true
	if _is_partial_recipe_stack(counts):
		return true
	if has_worker and counts.has("business_school"):
		return true
	for recipe in DataLoader.recipes:
		var gate := String(recipe.get("requiredIdeaId", ""))
		if gate != "" and not GameState.idea_done(gate):
			continue
		if _supply_counts_match_recipe(recipe, counts, target_sid, output_id):
			return true
	return false

func _supply_counts_match_recipe(recipe: Dictionary, counts: Dictionary, target_sid: int, output_id: String) -> bool:
	for inp in recipe.get("inputs", []):
		if int(counts.get(String(inp.get("id", "")), 0)) < int(inp.get("count", 1)):
			return false
	var tags: Dictionary = {}
	var has_worker := false
	for c in stacks[target_sid]:
		if c.ctype == "employee":
			has_worker = true
			for tag in c.cdef.get("workTags", []):
				tags[tag] = true
	if DataLoader.card_type(output_id) == "employee":
		has_worker = true
		for tag in DataLoader.card_def(output_id).get("workTags", []):
			tags[tag] = true
	var required_tags: Array = recipe.get("worker_tags", [])
	if required_tags.is_empty():
		return true
	for tag in required_tags:
		if (tag == "any" and has_worker) or tags.has(tag):
			return true
	return false

func _topmost_at(display_pt: Vector2, include_rivals: bool = false) -> Node2D:
	# 3D：把屏幕点投到白板平面得 board 点，再测哪张卡的 board 矩形命中；
	# 取最靠近相机（board y 最大 = 栈内最上/最靠前）的一张。
	var bpt := _unproject(display_pt)
	var best: Node2D = null
	var best_key := -INF
	for c in all_cards:
		if c.ctype == "department":
			continue
		if c.ctype == "rival" and not include_rivals:
			continue
		var tl := _board_topleft(c)
		if bpt.x >= tl.x and bpt.x <= tl.x + CW and bpt.y >= tl.y and bpt.y <= tl.y + CH:
			if tl.y > best_key:
				best_key = tl.y
				best = c
	return best

func _begin_drag(wp: Vector2, picked: Node2D = null) -> void:
	if picked == null:
		picked = _topmost_at(wp)
		if picked == null:
			return
	if battle_active and _is_battle_combatant_stack(picked.stack_id):
		return
	_select_card(picked)        # 单击即选中并出 hint，同时下面照常拖拽
	if is_instance_valid(hover_card):
		hover_card.set_hovered(false)
	hover_card = null
	var src: int = picked.stack_id
	var arr: Array = stacks[src]
	var k: int = picked.stack_pos
	var original_base: Vector2 = stack_base.get(src, Vector2.ZERO)
	var moving: Array = arr.slice(k)
	var remaining: Array = arr.slice(0, k)
	productions.erase(src)
	if remaining.is_empty():
		stacks.erase(src)
		stack_base.erase(src)
	else:
		stacks[src] = remaining
		relayout(src)
		evaluate_stack(src)
	var sid := next_stack_id
	next_stack_id += 1
	for c in moving:
		c.stack_id = sid
	stacks[sid] = moving
	drag_cards = moving.duplicate()
	drag_sid = sid
	_set_drag_cards_carried(true)
	var moving_base: Vector2 = original_base + Vector2(0, k * CARD_OFFSET)
	drag_offset = _unproject(wp) - moving_base
	stack_base[sid] = moving_base
	for c in moving:
		c.drag_vel = Vector2.ZERO    # 从原位开始平滑弹向光标
	relayout(sid)
	_sfx("grab")                     # 拿起卡音效

# 播放音效（用节点路径取 Sfx 自动加载，避免解析期对自动加载标识符的依赖）
func _sfx(sfx_name: String) -> void:
	var s := get_node_or_null("/root/Sfx")
	if s != null:
		s.play(sfx_name)

# 按卡牌类型播放「放下」音效
func _play_drop_sound(c) -> void:
	if c == null or not is_instance_valid(c):
		return
	if c.is_cash:
		_sfx("cash_down")
	elif c.card_id == "founder":
		_sfx("founder")
	elif is_person(c) or c.ctype == "customer":   # 创始人/员工/客户
		_sfx("down")
	else:
		_sfx("resource_down")

func _end_drag(_wp: Vector2) -> void:
	if drag_cards.is_empty():
		return
	var sid := drag_sid
	# 供应链可能在拖拽期间完成生产，并把产出并入当前携带的下游栈。
	# 合并会生成新 stack_id；若仍拿着旧编号，则从携带卡实例恢复最新编号。
	if not stacks.has(sid) or not stack_base.has(sid):
		var carried = drag_cards[0] if not drag_cards.is_empty() else null
		if is_instance_valid(carried) and stacks.has(carried.stack_id) and stack_base.has(carried.stack_id):
			sid = carried.stack_id
			drag_sid = sid
		else:
			_clear_drag()
			return
	var bottom = stacks[sid][0]
	_play_drop_sound(bottom)         # 放下卡音效（按类型）
	var lead_person := is_person(bottom)
	var center: Vector2 = stack_base[sid] + Vector2(CW * 0.5, CH * 0.5)   # board space

	if battle_active and _stack_intersects_battle(stack_base[sid]):
		if _stack_is_battle_people(sid):
			_join_player_battle_stack(sid)
			_clear_drag()
			if is_instance_valid(battle_employee) and stacks.has(battle_employee.stack_id):
				relayout(battle_employee.stack_id)
			return
		stack_base[sid] = _push_stack_outside_battle(stack_base[sid])
		relayout(sid)
		_show_toast("只有人物牌可以进入战斗区域")
		_clear_drag()
		return

	if _bank_rect().has_point(_project(center)):
		var sale_display := _bank_rect().position + _bank_rect().size * 0.5
		if _sell_stack(sid, _unproject(sale_display), sale_display):
			_clear_drag()
			return

	# drop a pure-employee stack (>=3) into the org strip -> fold into a department
	if region_of(center) == "org" and _can_fold(sid):
		_fold_department(sid)
		_clear_drag()
		return

	var target_zone: String
	if lead_person:
		target_zone = _zone_for_center(center)
	elif is_fixed(bottom):
		target_zone = bottom.zone
	else:
		target_zone = bottom.zone if bottom.zone != "" else _zone_for_center(center)

	stack_base[sid] = clamp_to_zone(stack_base[sid], target_zone)
	relayout(sid)

	# 释放后：员工压在对手卡上 → 员工主动发起战斗（员工先手），需在躲闪发生前触发
	if not battle_active and stacks.has(sid):
		var mover = stacks[sid][0]
		if is_instance_valid(mover) and mover.ctype == "employee":
			var r = _overlapping_rival(sid)
			if r != null:
				_clear_drag()
				_start_battle(r, mover, false)
				return

	sid = _resolve_overlap(sid)   # 有互动→并入；无互动→对方平滑躲开

	if stacks.has(sid):
		for c in stacks[sid]:
			if not is_person(c) and not is_fixed(c):
				c.zone = target_zone
	_clear_drag()
	if stacks.has(sid):
		relayout(sid)

# 与指定员工栈重叠的独立对手卡（无则 null）
func _overlapping_rival(esid: int):
	var ec: Vector2 = stack_base[esid] + Vector2(CW, CH) * 0.5
	for c in all_cards:
		if not is_instance_valid(c) or c.ctype != "rival":
			continue
		var rsid: int = c.stack_id
		if not stacks.has(rsid) or stacks[rsid].size() != 1:
			continue
		var rc: Vector2 = stack_base[rsid] + Vector2(CW, CH) * 0.5
		if absf(rc.x - ec.x) < CW * 0.92 and absf(rc.y - ec.y) < CH * 0.92:
			return c
	return null

# 拖拽中：每张牌用减衰調和振動朝目标位置逼近。
# 顶牌频率高→几乎跟手（轻微滞后）；越往下频率越低→滞后更大、回摆更明显（甩动感）。
func _update_drag_spring(delta: float) -> void:
	if drag_sid == -1 or not stacks.has(drag_sid):
		return
	var dt := minf(delta, 1.0 / 50.0)        # 限幅，避免掉帧时弹簧发散
	var arr: Array = stacks[drag_sid]
	var base: Vector2 = stack_base[drag_sid]
	for i in arr.size():
		var c = arr[i]
		var bp := base + Vector2(0, i * CARD_OFFSET)
		var target := _project(bp) + Vector2(0, -_card_lift(c) * view_zoom)
		_apply_card_projection(c, bp, true)
		var omega: float = DRAG_OMEGA_TOP * pow(DRAG_OMEGA_FALLOFF, i)
		var accel: Vector2 = (target - c.position) * (omega * omega) - c.drag_vel * (2.0 * DRAG_ZETA * omega)
		c.drag_vel += accel * dt
		c.position += c.drag_vel * dt
		_place_face3d_from_display(c, c.position, bp, i, true)

# 拖拽提示：收集所有「能与被拖卡互动」的栈，各自在白板上平铺一个 3D 走马灯虚线框。
# 框平贴白板、位于卡牌厚度之下 → 被其它卡牌自然遮挡，不会压在别的牌上。
const HINT_BORDER := CW * 0.045              # 虚线框线宽（board 单位，细）
func _update_stack_hint(_delta: float) -> void:
	stack_hint_sids = []
	if supply_drag_source != null and is_instance_valid(supply_drag_source):
		var source_sid: int = supply_drag_source.stack_id
		for sid in stacks.keys():
			if int(sid) != source_sid and _stack_accepts_supply_outputs(source_sid, int(sid)):
				stack_hint_sids.append(sid)
	elif not drag_cards.is_empty() and stacks.has(drag_sid):
		for sid in stacks.keys():
			if sid == drag_sid:
				continue
			if _would_interact(drag_sid, sid):
				stack_hint_sids.append(sid)
	_ensure_stack_hint_quads(stack_hint_sids.size())
	for i in stack_hint_quads.size():
		var q: MeshInstance3D = stack_hint_quads[i]
		if i < stack_hint_sids.size() and stack_base.has(stack_hint_sids[i]):
			var center: Vector2 = stack_base[stack_hint_sids[i]] + Vector2(CW * 0.5, CH * 0.5)
			var w := board_to_world(center)
			w.y = 0.05 + 0.004               # 贴白板、略低于卡顶 → 被卡牌厚度遮挡
			q.transform = Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-90.0)), w)
			q.visible = true
		else:
			q.visible = false

func _stack_hint_border_shader() -> Shader:
	if stack_hint_border_shader != null:
		return stack_hint_border_shader
	stack_hint_border_shader = Shader.new()
	stack_hint_border_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform float thickness = 0.12;   // 外圈线宽（UV 占比）
uniform float dash = 0.12;
uniform float gap = 0.08;
uniform float speed = 0.10;       // 走马灯速度（慢）
uniform vec4 line_color : source_color = vec4(0.18, 0.17, 0.16, 0.95);
void fragment() {
	vec2 uv = UV;
	float dx = min(uv.x, 1.0 - uv.x);
	float dy = min(uv.y, 1.0 - uv.y);
	float edge = min(dx, dy);
	if (edge > thickness) discard;                 // 内部透明：不盖住卡
	float t;
	if (uv.y <= thickness && dx >= dy) t = uv.x;                       // 上边
	else if (uv.x >= 1.0 - thickness && dy >= dx) t = 1.0 + uv.y;      // 右边
	else if (uv.y >= 1.0 - thickness && dx >= dy) t = 2.0 + (1.0 - uv.x); // 下边
	else t = 3.0 + (1.0 - uv.y);                                       // 左边
	float period = dash + gap;
	float f = fract((t - TIME * speed) / period);
	if (f > dash / period) discard;                // gap 区透明 → 虚线
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a;
}
"""
	return stack_hint_border_shader

func _ensure_stack_hint_quads(n: int) -> void:
	if city_bg == null or city_bg.world_card_root() == null:
		return
	while stack_hint_quads.size() < n:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		# 方块卡 + 外圈线宽
		var sz := (CW + 2.0 * HINT_BORDER) / CITY_CELL
		qm.size = Vector2(sz, sz)
		q.mesh = qm
		var mat := ShaderMaterial.new()
		mat.shader = _stack_hint_border_shader()
		mat.set_shader_parameter("thickness", HINT_BORDER / (CW + 2.0 * HINT_BORDER))
		q.material_override = mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.visible = false
		city_bg.world_card_root().add_child(q)
		stack_hint_quads.append(q)

func _hide_stack_hint() -> void:
	stack_hint_sids = []
	for q in stack_hint_quads:
		if is_instance_valid(q):
			q.visible = false

# 右键取消：把拖拽中的栈放到它“当前显示位置”（夹回合法区），不触发出售/折叠。
func _cancel_drag() -> void:
	var sid := drag_sid
	if not stacks.has(sid):
		_clear_drag()
		return
	var bottom = stacks[sid][0]
	_play_drop_sound(bottom)         # 右键取消也是把卡放下
	# 顶牌当前显示位置反推 board 坐标 = 现卡牌所在地
	var board_pos := _unproject(bottom.position)
	var center := board_pos + Vector2(CW * 0.5, CH * 0.5)
	if battle_active and _stack_intersects_battle(board_pos) and not _stack_is_battle_people(sid):
		board_pos = _push_stack_outside_battle(board_pos)
		center = board_pos + Vector2(CW * 0.5, CH * 0.5)
	var target_zone: String
	if is_person(bottom):
		target_zone = _zone_for_center(center)
	elif is_fixed(bottom):
		target_zone = bottom.zone
	else:
		target_zone = bottom.zone if bottom.zone != "" else _zone_for_center(center)
	stack_base[sid] = clamp_to_zone(board_pos, target_zone)
	relayout(sid)
	sid = _resolve_overlap(sid)   # 有互动→并入；无互动→对方平滑躲开
	if stacks.has(sid):
		for c in stacks[sid]:
			if not is_person(c) and not is_fixed(c):
				c.zone = target_zone
	_clear_drag()
	if stacks.has(sid):
		relayout(sid)

# ---------------------------------------------------------------- selection
func _select_card(c) -> void:
	if not is_instance_valid(c):
		return
	if selected_card == c:
		hint_text = _card_hint(c)
		toast_t = 0.0
		return
	if is_instance_valid(selected_card):
		selected_card.set_selected(false)
	selected_card = c
	c.set_selected(true)
	hint_text = _card_hint(c)
	toast_t = 0.0

func _deselect() -> void:
	if is_instance_valid(selected_card):
		selected_card.set_selected(false)
	selected_card = null
	hint_text = DEFAULT_HINT
	toast_t = 0.0

func _card_hint(c) -> String:
	var d: Dictionary = c.cdef
	var nm := String(d.get("name", c.card_id))
	match c.ctype:
		"employee":
			return "「%s · 员工　月薪 $%d　产能 %d」" % [
				nm, int(d.get("salary", 0)), int(d.get("capacity", 0))]
		"resource_node":
			var us := ("剩余 %d 次" % c.uses_left) if c.uses_left >= 0 else "可无限使用"
			return "「%s · 资源节点　%s」" % [nm, us]
		"resource", "customer", "product":
			return "「%s · %s　价值 $%d」" % [
				nm, String(CODEX_TYPE.get(c.ctype, "资源")), int(d.get("value", 0))]
		"facility":
			return "「%s · 设施」" % nm
		"department":
			return "「%s · 部门　%d 人　月薪 $%d」" % [nm, int(d.get("capacity", 0)), int(d.get("salary", 0))]
		"risk":
			return "「%s · 风险」" % nm
		"idea":
			return "「%s · 想法 / 配方」" % nm
		"business_model":
			return "「%s · 商业模式　%s」" % [nm, DataLoader.recipe_formula_text(String(d.get("recipeId", "")))]
		_:
			return "「%s」" % nm

# ---------------------------------------------------------------- hover info
# 底部信息条的悬停内容（鼠标移到卡上即出，移开恢复选中/默认 hint）。
# 段落 = { t: 文本, b: 加粗, i: 斜体 }。返回空数组表示无悬停。
func _hover_info_parts() -> Array:
	if not is_instance_valid(hover_card):
		return []
	var sid: int = hover_card.stack_id
	if stacks.has(sid) and stacks[sid].size() > 1:
		return _stack_info_parts(sid)
	return _card_info_parts(hover_card)

# 单卡：名字加粗：功能加粗。「flavor」斜体不加粗
func _card_info_parts(c) -> Array:
	var d: Dictionary = c.cdef
	var nm := String(d.get("name", c.card_id))
	var func_txt := _card_func_text(c)
	var out: Array = []
	out.append({"t": (nm + "：" + func_txt) if func_txt != "" else nm, "b": true, "i": false})
	var flavor := String(d.get("flavor", "")).strip_edges()
	if flavor != "":
		out.append({"t": "　「" + flavor + "」", "b": false, "i": true})
	return out

# 卡牌功能段（加粗部分）：按类型给出关键数值，「、」分隔；产能为 当前/上限（类 HP）
func _card_func_text(c) -> String:
	var d: Dictionary = c.cdef
	var parts: Array = []
	match c.ctype:
		"employee", "department":
			parts.append("产能 %d/%d" % [c.cap_cur, int(d.get("capacity", 0))])
			parts.append("工资 $%d" % int(d.get("salary", 0)))
		"rival":
			parts.append("产能 %d" % int(d.get("capacity", 0)))
			parts.append("资金 %d/%d" % [c.funds_cur, c.funds_max])   # 资金 = 战斗 HP
		"resource", "customer", "product":
			parts.append("价值 $%d" % int(d.get("value", 0)))
			if int(d.get("cost", 0)) > 0:
				parts.append("成本 $%d" % int(d.get("cost", 0)))
		"resource_node":
			if c.uses_left >= 0:
				if d.has("maxUses"):
					parts.append("次数 %d/%d" % [c.uses_left, int(d["maxUses"])])
				else:
					parts.append("剩余 %d 次" % c.uses_left)
			else:
				parts.append("无限次")
		"business_model":
			return DataLoader.recipe_formula_text(String(d.get("recipeId", "")))
		_:
			pass
	return "、".join(parts)

# 堆叠（栈内不止一张）：堆叠卡牌：xxx*1、yyy*2
func _stack_info_parts(sid: int) -> Array:
	var counts: Array = []     # [[name, count], ...] 保持首次出现顺序
	var seen: Dictionary = {}
	for c in stacks[sid]:
		var nm := String(c.cdef.get("name", c.card_id))
		if seen.has(nm):
			counts[seen[nm]][1] += 1
		else:
			seen[nm] = counts.size()
			counts.append([nm, 1])
	var list: Array = []
	for pair in counts:
		list.append("%s*%d" % [pair[0], pair[1]])
	return [
		{"t": "堆叠卡牌：", "b": true, "i": false},
		{"t": "、".join(list), "b": false, "i": false},
	]

# 混排绘制一行信息（整体水平居中）：加粗=偏移重描，斜体=切变
func _draw_info_line(canvas: CanvasItem, f: Font, baseline_y: float, parts: Array, col: Color, size: int) -> void:
	var total := 0.0
	for p in parts:
		var w: float = f.get_string_size(p["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if p["b"]:
			w += 1.0
		p["_w"] = w
		total += w
	var x := maxf(24.0, (_screen_size().x - total) * 0.5)
	for p in parts:
		if p["i"]:
			var t := Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2(x, baseline_y))
			canvas.draw_set_transform_matrix(t)
			canvas.draw_string(f, Vector2.ZERO, p["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		else:
			canvas.draw_string(f, Vector2(x, baseline_y), p["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			if p["b"]:
				canvas.draw_string(f, Vector2(x + 1, baseline_y), p["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += p["_w"]

func _clear_drag() -> void:
	_set_drag_cards_carried(false)
	drag_cards = []
	drag_sid = -1
	_hide_stack_hint()                        # 立即收起叠放提示框
	if bank_button != null and is_instance_valid(bank_button):
		bank_button.queue_redraw()

func _set_drag_cards_carried(v: bool) -> void:
	for c in drag_cards:
		if is_instance_valid(c):
			c.set_carried(v)

func _set_stack_hovered(sid: int, v: bool) -> void:
	if not stacks.has(sid):
		return
	for c in stacks[sid]:
		if is_instance_valid(c):
			c.set_hovered(v)

func _merge(from_sid: int, to_sid: int) -> int:
	var moving: Array = stacks[from_sid]
	var dest: Array = stacks[to_sid]
	var merged_drag_stack := from_sid == drag_sid or to_sid == drag_sid
	for c in moving:
		dest.append(c)                      # 被拖入的牌追加到末尾 = 栈顶（最后放的在最上）
	# 整摞重新编号为最新栈号 → ORDER_DY 最高 → 渲染在所有重叠卡之上（最后操作的牌堆置顶）
	var new_sid := next_stack_id
	next_stack_id += 1
	stacks[new_sid] = dest
	stack_base[new_sid] = stack_base[to_sid]
	for c in dest:
		c.stack_id = new_sid
	stacks.erase(from_sid)
	stacks.erase(to_sid)
	stack_base.erase(from_sid)
	stack_base.erase(to_sid)
	productions.erase(from_sid)
	productions.erase(to_sid)
	if merged_drag_stack:
		drag_sid = new_sid
	relayout(new_sid)
	evaluate_stack(new_sid)
	return new_sid

# 落点处理：找压在下面的栈。有互动关系→并入；无互动→让对方随机平滑躲开。
func _resolve_overlap(sid: int) -> int:
	if not stacks.has(sid):
		return sid
	var nb: Vector2 = stack_base[sid] + Vector2(CW * 0.5, CH * 0.5)
	var target: Node2D = null
	var best_d := INF
	# 放宽判定：把目标卡命中框向四周外扩约半张卡，落点中心靠近就算叠上；多个命中取最近的
	var margin := Vector2(CW * 0.5, CH * 0.5)
	for c in all_cards:
		if c.stack_id == sid:
			continue
		var hit := Rect2(_board_topleft(c) - margin, Vector2(CW, CH) + margin * 2.0)
		if hit.has_point(nb):
			var d: float = (_board_center(c)).distance_to(nb)
			if d < best_d:
				best_d = d
				target = c
	if target != null and _would_interact(sid, target.stack_id):
		return _merge(sid, target.stack_id)
	if target != null:
		_dodge_overlaps(sid)   # 无互动：把压住的牌推开
	evaluate_stack(sid)
	return sid

# 两个栈合到一起是否会产生“互动”：能凑出配方，或纯员工组队（为折叠部门铺路）。
func _would_interact(a: int, b: int) -> bool:
	if not stacks.has(a) or not stacks.has(b):
		return false
	var counts: Dictionary = {}
	var has_worker := false
	var all_emp := true
	var arr: Array = []
	for src in [a, b]:
		for c in stacks[src]:
			arr.append(c)
			counts[c.card_id] = int(counts.get(c.card_id, 0)) + 1
			if c.ctype == "employee":
				has_worker = true
			else:
				all_emp = false
	if all_emp:
		return true                       # 员工叠员工 = 组队/组建部门
	if has_worker and counts.has("business_school"):
		return true                       # 员工叠商学院 = 累积洞察值
	if _can_stack_as_cards(arr, counts):
		return true
	if not _basic_resource_recipe(counts, arr).is_empty():
		return true
	for recipe in DataLoader.recipes:
		var gate := String(recipe.get("requiredIdeaId", ""))
		if gate != "" and not GameState.idea_done(gate):
			continue
		if _recipe_matches(recipe, counts, arr):
			return true
	return false

func _is_stackable_card(c) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	if c.ctype == "employee" or c.ctype == "department" or c.ctype == "risk" or c.ctype == "idea":
		return false
	return true

func _can_stack_as_cards(arr: Array, counts: Dictionary) -> bool:
	if arr.is_empty():
		return false
	var first_id := String(arr[0].card_id)
	var same_id := true
	var has_worker := false
	for c in arr:
		if c.ctype == "employee":
			has_worker = true
			continue
		if not _is_stackable_card(c):
			return false
		if c.card_id != first_id:
			same_id = false
	if not has_worker and same_id:
		return true
	if has_worker:
		return false
	return _is_partial_recipe_stack(counts)

func _is_partial_recipe_stack(counts: Dictionary) -> bool:
	for recipe in DataLoader.recipes:
		var matched_any := false
		var input_needs: Dictionary = {}
		for inp in recipe.get("inputs", []):
			input_needs[String(inp.get("id", ""))] = int(input_needs.get(String(inp.get("id", "")), 0)) + int(inp.get("count", 1))
		for id in counts.keys():
			if not input_needs.has(String(id)):
				matched_any = false
				break
			if int(counts[id]) > int(input_needs[String(id)]):
				matched_any = false
				break
			matched_any = true
		if matched_any:
			return true
	return false

# 把所有与落点栈重叠、且无互动的其他栈，随机向旁边平滑推开。
func _dodge_overlaps(dropped: int) -> void:
	if not stacks.has(dropped):
		return
	var drect := Rect2(stack_base[dropped], Vector2(CW, CH))
	var dc := drect.position + drect.size * 0.5
	var seen: Dictionary = {}
	for c in all_cards.duplicate():
		var osid: int = c.stack_id
		if osid == dropped or seen.has(osid) or not stacks.has(osid):
			continue
		if not drect.intersects(Rect2(_board_topleft(c), Vector2(CW, CH))):
			continue
		seen[osid] = true
		_dodge_stack(osid, dc)

func _dodge_stack(sid: int, from_center: Vector2) -> void:
	if not stacks.has(sid):
		return
	var bottom = stacks[sid][0]
	var sc: Vector2 = stack_base[sid] + Vector2(CW * 0.5, CH * 0.5)
	var dir := sc - from_center
	if dir.length() < 1.0:
		dir = Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	dir = dir.normalized().rotated(deg_to_rad(randf_range(-40.0, 40.0)))   # 随机偏向旁边
	var zone: String = bottom.zone if bottom.zone != "" else _zone_for_center(sc)
	var new_base := clamp_to_zone(stack_base[sid] + dir * (CW + GAP), zone)
	var tw := create_tween()
	tw.tween_method(_dodge_apply.bind(sid), stack_base[sid], new_base, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _dodge_apply(p: Vector2, sid: int) -> void:
	if stacks.has(sid) and sid != drag_sid:
		stack_base[sid] = p
		relayout(sid)

# 对手卡每秒朝创始人跳动半张卡，路线随机（非直线）。
func _rival_hop_tick() -> void:
	if game_over or battle_active:
		return
	var founder = _founder_on_board()
	if not is_instance_valid(founder):
		return
	var target_center: Vector2 = stack_base[founder.stack_id] + Vector2(CW, CH) * 0.5
	var hop := CW * 0.5     # 半张卡的距离
	for c in all_cards:
		if not is_instance_valid(c) or c.ctype != "rival":
			continue
		var sid: int = c.stack_id
		# 只让独立、未被拖动的对手卡跳动
		if sid == drag_sid or not stacks.has(sid) or stacks[sid].size() != 1:
			continue
		var base: Vector2 = stack_base[sid]
		var center := base + Vector2(CW, CH) * 0.5
		var to_founder := target_center - center
		if to_founder.length() < hop:
			continue   # 已贴近创始人
		# 朝创始人方向 ± 大幅随机偏角，折线更曲折（约 ±90°，偶尔几乎横向）
		var dir := to_founder.normalized().rotated(GameState.rng.randf_range(-1.6, 1.6))
		var zone: String = c.zone if c.zone != "" else _zone_for_center(center)
		var new_base := clamp_to_zone(base + dir * hop, zone)
		var tw := create_tween()
		tw.tween_method(_dodge_apply.bind(sid), base, new_base, 0.32) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------------------------------------------------------------- battle
# 每帧：战斗中刷新边框 / 检测结束；未战斗时检测对手卡是否触碰员工（含创始人）。
func _update_battle(delta: float) -> void:
	if battle_active:
		battle_dash_phase += delta * 90.0   # 虚线转圈速度（px/s）
		queue_redraw()                      # 刷新中心 VS 装饰
		if is_instance_valid(battle_border):
			battle_border.queue_redraw()   # 跟随缩放/平移刷新（中心固定在 employee 处）
		# HP 计数动画 + 顶角标签定位
		var k := clampf(delta * 10.0, 0.0, 1.0)
		battle_hp_shown_left = lerpf(battle_hp_shown_left, battle_hp_left, k)
		battle_hp_shown_right = lerpf(battle_hp_shown_right, battle_hp_right, k)
		_update_battle3d()
		var rect := _battle_screen_rect()
		var isz := 26.0   # 资金图标与战斗框同比例
		var mx := 20.0    # 左右边距（呼吸感）
		var my := 14.67   # 上边距（呼吸感）
		# 左上：图标 + 数字
		if battle_hp_label_left != null:
			battle_hp_label_left.text = "%.1f" % maxf(battle_hp_shown_left, 0.0)
			if battle_hp_icon_left != null:
				battle_hp_icon_left.size = Vector2(isz, isz)
				battle_hp_icon_left.position = rect.position + Vector2(mx, my + 1.33)
			battle_hp_label_left.position = rect.position + Vector2(mx + isz + 2.67, my)
		# 右上：图标 + 数字（整组右对齐到框右上角）
		if battle_hp_label_right != null:
			var txt := "%.1f" % maxf(battle_hp_shown_right, 0.0)
			battle_hp_label_right.text = txt
			var fnt := battle_hp_label_right.get_theme_font("font")
			var tw := 80.0
			if fnt != null:
				tw = fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
			var gx := rect.end.x - mx - (isz + 2.67 + tw)
			if battle_hp_icon_right != null:
				battle_hp_icon_right.size = Vector2(isz, isz)
				battle_hp_icon_right.position = Vector2(gx, rect.position.y + my + 1.33)
			battle_hp_label_right.position = Vector2(gx + isz + 2.67, rect.position.y + my)
		return
	# 拖动中不激活战斗（释放后才检测）；玩家拖员工撞对手的情形在 _end_drag 里触发
	if drag_sid != -1:
		return
	for c in all_cards:
		if not is_instance_valid(c) or c.ctype != "rival":
			continue
		var rsid: int = c.stack_id
		if not stacks.has(rsid) or stacks[rsid].size() != 1:
			continue
		var rc: Vector2 = stack_base[rsid] + Vector2(CW, CH) * 0.5
		for e in all_cards:
			if not is_instance_valid(e) or e.ctype != "employee" or not stacks.has(e.stack_id):
				continue
			var eb: Vector2 = stack_base[e.stack_id] + Vector2(0, e.stack_pos * CARD_OFFSET)
			var ec := eb + Vector2(CW, CH) * 0.5
			if absf(rc.x - ec.x) < CW * 0.92 and absf(rc.y - ec.y) < CH * 0.92:
				_start_battle(c, e, true)   # 对手跳过来撞上 → 对手先手
				return

func _stack_center(sid: int) -> Vector2:
	return stack_base[sid] + Vector2(CW, CH) * 0.5

func _battle_visual_center() -> Vector2:
	return battle_center + Vector2(0, -CH * 0.12 + (_battle_extra_height() - BATTLE_TOP_EXTRA) * 0.5)

func _battle_extra_height() -> float:
	if not battle_active or not is_instance_valid(battle_employee):
		return 0.0
	var sid: int = battle_employee.stack_id
	if not stacks.has(sid):
		return 0.0
	var people := 0
	for c in stacks[sid]:
		if _is_battle_person(c):
			people += 1
	return maxf(0.0, float(people - 1) * CARD_OFFSET)

func _battle_board_rect() -> Rect2:
	var height := 2.0 * CH + BATTLE_TOP_EXTRA + _battle_extra_height()
	return Rect2(_battle_visual_center() - Vector2(2.0 * CW, height * 0.5), Vector2(4.0 * CW, height))

func _battle_side_atk(rival_side: bool) -> int:
	if rival_side:
		return int(battle_rival.cdef.get("capacity", 0)) if is_instance_valid(battle_rival) else 0
	if not is_instance_valid(battle_employee) or not stacks.has(battle_employee.stack_id):
		return 0
	var total := 0
	for c in stacks[battle_employee.stack_id]:
		if _is_battle_person(c):
			total += int(c.cdef.get("capacity", 0))
	return total

func _stack_intersects_battle(base: Vector2) -> bool:
	return Rect2(base, Vector2(CW, CH)).intersects(_battle_board_rect())

func _is_battle_combatant_stack(sid: int) -> bool:
	if not battle_active:
		return false
	if is_instance_valid(battle_rival) and battle_rival.stack_id == sid:
		return true
	return is_instance_valid(battle_employee) and battle_employee.stack_id == sid

func _stack_is_battle_people(sid: int) -> bool:
	if not stacks.has(sid) or stacks[sid].is_empty():
		return false
	for c in stacks[sid]:
		if not _is_battle_person(c):
			return false
	return true

func _join_player_battle_stack(from_sid: int) -> void:
	if not stacks.has(from_sid) or not is_instance_valid(battle_employee):
		return
	var to_sid: int = battle_employee.stack_id
	if not stacks.has(to_sid) or from_sid == to_sid:
		return
	var moving: Array = stacks[from_sid]
	for c in moving:
		c.set_carried(false)
		c.stack_id = to_sid
		stacks[to_sid].append(c)
	stacks.erase(from_sid)
	stack_base.erase(from_sid)
	productions.erase(from_sid)
	productions.erase(to_sid)
	relayout(to_sid)
	_build_battle3d()

func _push_stack_outside_battle(base: Vector2) -> Vector2:
	var rect := _battle_board_rect()
	var candidates := [
		Vector2(rect.position.x - CW - GAP, base.y),
		Vector2(rect.end.x + GAP, base.y),
		Vector2(base.x, rect.position.y - CH - GAP),
		Vector2(base.x, rect.end.y + GAP),
	]
	var best := clamp_to_zone(candidates[0])
	var best_distance := INF
	for candidate in candidates:
		var clamped := clamp_to_zone(candidate)
		if _stack_intersects_battle(clamped):
			continue
		var distance := clamped.distance_squared_to(base)
		if distance < best_distance:
			best_distance = distance
			best = clamped
	return best

func _start_battle(rival, employee, rival_first: bool = true) -> void:
	battle_active = true
	_sfx("battle_start")
	battle_rival = rival
	battle_employee = employee
	battle_rival_first = rival_first
	# 若是玩家拖着卡触发的战斗，先松开拖拽，否则被拖的卡（drag_sid）无法被移到阵位
	if drag_sid != -1:
		_clear_drag()
	var rsid: int = rival.stack_id
	var esid: int = employee.stack_id
	# 战斗框中心选在 employee 牌的中心点
	var center := _stack_center(esid)
	# 夹住中心，使战斗框（宽 4CW、高 2CH）留在画布内
	center.x = clampf(center.x, CANVAS_X0 + GAP + 2.0 * CW, CANVAS_X1 - GAP - 2.0 * CW)
	center.y = clampf(center.y, MID_Y0 + CH, MID_Y1 - CH)
	battle_center = center
	# rival 往左、employee 往右，平行对齐，之间留一张牌的距离
	_battle_move_stack(rsid, Vector2(center.x - 1.5 * CW, center.y - 0.5 * CH))
	_battle_move_stack(esid, Vector2(center.x + 0.5 * CW, center.y - 0.5 * CH))
	# 战斗框节点
	if battle_border == null or not is_instance_valid(battle_border):
		battle_border = Node2D.new()
		battle_border.name = "BattleBorder"
		battle_border.z_index = 2700
		add_child(battle_border)
		battle_border.draw.connect(_draw_battle_border)
	battle_border.visible = true
	battle_border.queue_redraw()
	# 其它牌随机方向跳出战斗框
	_scatter_cards_out_of_battle(center, rsid, esid)
	# HP：对手=资金（产能×3），我方=现金储备
	_sync_cash_state()
	battle_hp_left = float(rival.funds_cur)
	battle_hp_right = float(GameState.cash)
	battle_hp_shown_left = battle_hp_left
	battle_hp_shown_right = battle_hp_right
	battle_dmg_to_player = 0.0
	_build_battle3d()
	# 开始回合循环
	_run_battle()

func _battle_move_stack(sid: int, target_base: Vector2) -> void:
	if not stacks.has(sid):
		return
	var tw := create_tween()
	tw.tween_method(_dodge_apply.bind(sid), stack_base[sid], target_base, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _scatter_cards_out_of_battle(center: Vector2, rsid: int, esid: int) -> void:
	var half := Vector2(2.0 * CW, CH)   # 战斗框 board 半尺寸
	for k in stacks.keys():
		var sid := int(k)
		if sid == rsid or sid == esid:
			continue
		var sc := _stack_center(sid)
		# 中心落在战斗框内（含一张牌容差）则踢出
		if absf(sc.x - center.x) < half.x + CW * 0.5 and absf(sc.y - center.y) < half.y + CH * 0.5:
			var ang := GameState.rng.randf_range(0.0, TAU)
			var dir := Vector2(cos(ang), sin(ang))
			var dist := half.length() + CW + GameState.rng.randf_range(0.0, CW)
			var new_base := clamp_to_zone(center + dir * dist - Vector2(CW, CH) * 0.5, "")
			_battle_move_stack(sid, new_base)

func _end_battle() -> void:
	if battle_active:
		_sfx("battle_end")
	battle_active = false
	battle_running = false
	battle_attacker_sid = -1
	battle_rival = null
	battle_employee = null
	if battle_view_changed:
		_battle_restore_view()
		battle_view_changed = false
	_clear_battle3d()
	if is_instance_valid(battle_border):
		battle_border.visible = false
		battle_border.queue_redraw()
	for n in [battle_hp_label_left, battle_hp_label_right, battle_hp_icon_left, battle_hp_icon_right]:
		if is_instance_valid(n):
			n.queue_free()
	battle_hp_label_left = null
	battle_hp_label_right = null
	battle_hp_icon_left = null
	battle_hp_icon_right = null

# 视角平滑移到战斗框中心并放大 1.5 倍（结束后可恢复）
func _battle_focus_view() -> void:
	battle_saved_zoom = view_zoom
	battle_saved_offset = view_offset
	battle_view_changed = true
	var focus := Vector2(BASE_W * 0.5, (HUD_H + INFO_Y) * 0.5)   # 屏幕上聚焦点（play 区中部）
	var target_zoom := clampf(view_zoom * 1.5, VIEW_ZOOM_MIN, VIEW_ZOOM_MAX)
	var s := _row_scale(battle_center.y)
	var flat := Vector2(BASE_W * 0.5 + (battle_center.x - BASE_W * 0.5) * s, battle_center.y)
	var from_zoom := view_zoom
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var z: float = lerpf(from_zoom, target_zoom, t)
		view_zoom = z
		view_offset = focus - flat * z   # 让战斗框中心始终落在 focus
		_clamp_view_offset()
		_relayout_all()
		_relayout_loose_packs()
		queue_redraw()
	, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _battle_restore_view() -> void:
	var from_zoom := view_zoom
	var from_off := view_offset
	var to_zoom := battle_saved_zoom
	var to_off := battle_saved_offset
	var tw := create_tween()
	tw.tween_method(func(t: float):
		view_zoom = lerpf(from_zoom, to_zoom, t)
		view_offset = from_off.lerp(to_off, t)
		_clamp_view_offset()
		_relayout_all()
		_relayout_loose_packs()
		queue_redraw()
	, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# 战斗框在屏幕空间的 AABB（board 矩形宽 4CW、高 2CH，四角投影后取包围盒）
func _battle_screen_rect() -> Rect2:
	var board_rect := _battle_board_rect()
	var bx0 := board_rect.position.x
	var bx1 := board_rect.end.x
	var by0 := board_rect.position.y
	var by1 := board_rect.end.y
	var corners := [
		_project(Vector2(bx0, by0)), _project(Vector2(bx1, by0)),
		_project(Vector2(bx1, by1)), _project(Vector2(bx0, by1))]
	var mn: Vector2 = corners[0]
	var mx: Vector2 = corners[0]
	for p in corners:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	return Rect2(mn, mx - mn)

func _ensure_battle_hp_labels() -> void:
	for side in ["L", "R"]:
		var lbl := Label.new()
		lbl.name = "BattleHP" + side
		lbl.z_index = 4095
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.size = Vector2(126.67, 30.67)
		_apply_battle_font(lbl, 23)
		lbl.add_theme_color_override("font_color", Color("2b2926"))
		hud.add_child(lbl)
		# HP 数字前的资金图标（与顶部 UI 栏一致）
		var icon := TextureRect.new()
		icon.name = "BattleHPIcon" + side
		icon.texture = _ui_icon("streamline/icon_cash")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.z_index = 4095
		hud.add_child(icon)
		if side == "L":
			battle_hp_label_left = lbl
			battle_hp_icon_left = icon
		else:
			battle_hp_label_right = lbl
			battle_hp_icon_right = icon

# 圆角矩形（屏幕空间）轮廓点，顺时针：TR→BR→BL→TL 角弧 + 直边
func _round_rect_points(rect: Rect2, r: float, steps: int) -> PackedVector2Array:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	r = minf(r, minf(w, h) * 0.5)
	var centers := [
		Vector2(x + w - r, y + r), Vector2(x + w - r, y + h - r),
		Vector2(x + r, y + h - r), Vector2(x + r, y + r)]
	var a0 := [-PI * 0.5, 0.0, PI * 0.5, PI]
	var pts := PackedVector2Array()
	for i in 4:
		for s in steps + 1:
			var a: float = a0[i] + (PI * 0.5) * float(s) / float(steps)
			pts.append((centers[i] as Vector2) + Vector2(cos(a), sin(a)) * r)
	pts.append(pts[0])
	return pts

# 沿折线连续画虚线（跨段相位连贯）
func _draw_dashed_polyline(canvas: CanvasItem, pts: PackedVector2Array, dash: float, gap: float, col: Color, width: float, phase0: float = 0.0) -> void:
	var period := dash + gap
	var phase := fposmod(phase0, period)
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := b - a
		var L := seg.length()
		if L < 0.001:
			continue
		var dir := seg / L
		var pos := -phase
		while pos < L:
			var f := maxf(pos, 0.0)
			var t := minf(pos + dash, L)
			if t > f:
				canvas.draw_line(a + dir * f, a + dir * t, col, width)
			pos += period
		phase = fposmod(phase + L, period)

func _draw_battle_border() -> void:
	return   # 战斗框已改 3D（_build_battle3d），不再 2D 绘制
	if not battle_active:
		return
	var rect := _battle_screen_rect()
	var pts := _round_rect_points(rect, 28.0 * view_zoom, 6)
	# 很粗的浅红色虚线，沿边框转圈行进
	_draw_dashed_polyline(battle_border, pts, 26.0 * view_zoom, 18.0 * view_zoom, Color("ef9a9a"), 9.0 * view_zoom, battle_dash_phase * view_zoom)

# ---------------------------------------------------------------- battle turns
func _run_battle() -> void:
	if battle_running:
		return
	battle_running = true
	_battle_focus_view()                          # 视角移到战斗框并放大
	await get_tree().create_timer(1.5).timeout    # 攻击前暂停 1.5 秒（等入场 + 视角到位）
	var rival_turn := battle_rival_first            # 谁先碰到谁先手
	while battle_active:
		if not (is_instance_valid(battle_rival) and is_instance_valid(battle_employee)):
			break
		await _battle_attack(rival_turn)
		if not battle_active:
			return
		if battle_hp_left <= 0.0 or battle_hp_right <= 0.0:
			break
		await get_tree().create_timer(1.0).timeout   # 间隔 1 秒
		rival_turn = not rival_turn
	_finish_battle()

# 攻击牌沿弧线跳到对方牌面，落点结算伤害，再沿弧线跳回。
func _battle_attack(rival_attacking: bool) -> void:
	var attacker = battle_rival if rival_attacking else battle_employee
	var defender = battle_employee if rival_attacking else battle_rival
	if not (is_instance_valid(attacker) and is_instance_valid(defender)):
		return
	var asid: int = attacker.stack_id
	var dsid: int = defender.stack_id
	if not (stacks.has(asid) and stacks.has(dsid)):
		return
	# 我方回合开始时快照当前人物牌。回合中途加入的新牌不在快照中，下回合才参战。
	var player_attackers: Array = []
	if not rival_attacking:
		for c in stacks[asid]:
			if _is_battle_person(c):
				player_attackers.append(c)
	# 攻击方置顶
	battle_attacker_sid = asid
	relayout(asid)
	if rival_attacking:
		var target = stacks[dsid].back()
		await _battle_arc_card(attacker, target, true)
		if not battle_active:
			return
		var cap := float(int(attacker.cdef.get("capacity", 0)))
		var power: float = maxf(0.1, cap * GameState.rng.randf_range(0.7, 1.3))
		_battle_apply_damage(true, power)
		if is_instance_valid(defender):
			_battle_damage_popup(target, power)
		await _battle_arc_card(attacker, target, false)
	else:
		# 每张快照人物牌各攻击一次、各自产生一个伤害数字；全部完成才结束我方回合。
		for member in player_attackers:
			if not battle_active or battle_hp_left <= 0.0:
				break
			if not is_instance_valid(member):
				continue
			var target = stacks[dsid].back()
			await _battle_arc_card(member, target, true)
			if not battle_active:
				return
			var cap := float(int(member.cdef.get("capacity", 0)))
			var power: float = maxf(0.1, cap * GameState.rng.randf_range(0.7, 1.3))
			_battle_apply_damage(false, power)
			if is_instance_valid(defender):
				_battle_damage_popup(target, power)
			await _battle_arc_card(member, target, false)
			await get_tree().create_timer(0.12).timeout
	if not battle_active:
		return
	# 取消置顶
	battle_attacker_sid = -1
	if stacks.has(asid):
		relayout(asid)

func _battle_arc_card(card, target, outward: bool) -> void:
	if not (is_instance_valid(card) and is_instance_valid(target)):
		return
	if not (is_instance_valid(card.face3d) and is_instance_valid(target.face3d)):
		return
	var home: Vector3 = board_to_world(_board_center(card))
	home.y = CARD_PLANE_Y + _face3d_lift(card, card.stack_pos, false)
	var landing: Vector3 = target.face3d.global_position
	landing.y += 0.09
	var from := home if outward else landing
	var to := landing if outward else home
	card.face3d.global_position = from
	var tween := create_tween()
	tween.tween_method(
		_battle_arc_apply.bind(card, from, to, 0.34),
		0.0, 1.0, 0.48
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

func _battle_arc_apply(progress: float, card, from: Vector3, to: Vector3, height: float) -> void:
	if not is_instance_valid(card) or not is_instance_valid(card.face3d):
		return
	var position := from.lerp(to, progress)
	position.y += sin(progress * PI) * height
	card.face3d.global_position = position

func _battle_apply_damage(rival_attacking: bool, power: float) -> void:
	if rival_attacking:
		battle_hp_right = maxf(0.0, battle_hp_right - power)   # 扣我方现金
		battle_dmg_to_player += power
	else:
		battle_hp_left = maxf(0.0, battle_hp_left - power)     # 扣对手资金
		if is_instance_valid(battle_rival):
			battle_rival.funds_cur = int(ceil(battle_hp_left))

# 伤害数字（保留一位小数）从被攻击卡上跳出，背景为 battle-bubble.svg
func _battle_damage_popup(defender, amount: float) -> void:
	_sfx("hit")
	var scr := _project(stack_base[defender.stack_id] + Vector2(CW * 0.5, CH * 0.3))
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 4096
	hud.add_child(holder)
	holder.position = scr
	var sz := 96.0
	var bg := TextureRect.new()
	bg.texture = _battle_bubble_texture()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.size = Vector2(sz, sz)
	bg.position = -Vector2(sz, sz) * 0.5
	holder.add_child(bg)
	var lbl := Label.new()
	lbl.text = "-%.1f" % amount
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.size = Vector2(sz, sz)
	lbl.position = -Vector2(sz, sz) * 0.5
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_battle_font(lbl, 26)
	lbl.add_theme_color_override("font_color", Color("8a1f1f"))
	holder.add_child(lbl)
	holder.scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(holder, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(holder, "position:y", scr.y - 70.0, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(holder, "modulate:a", 0.0, 0.4)
	tw.tween_callback(holder.queue_free)

# 战斗区域中心的 VS 背景装饰（画在画布层，位于双方卡牌之下）
func _draw_battle_decoration() -> void:
	return   # VS 装饰已改 3D（_build_battle3d），不再 2D 绘制

# ---- 战斗装饰 3D：微突出虚线边框 / 淡红底 / HP 数字都躺在白板上 ----
func _build_battle3d() -> void:
	_clear_battle3d()
	if city_bg == null or city_bg.world_card_root() == null:
		return
	battle3d = Node3D.new()
	city_bg.world_card_root().add_child(battle3d)
	var visual_center := _battle_visual_center()
	var center_world := board_to_world(visual_center)
	var m := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var rect_size := Vector2(
		4.0 * CW / CITY_CELL,
		(2.0 * CH + BATTLE_TOP_EXTRA + _battle_extra_height()) / CITY_CELL
	)
	# 深色错位底层作为虚线框的微厚度，亮色跑马灯浮在其上。
	var depth := MeshInstance3D.new()
	var depth_mesh := QuadMesh.new()
	depth_mesh.size = rect_size
	depth.mesh = depth_mesh
	depth.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	depth.position = Vector3(center_world.x + 0.022, 0.055, center_world.z + 0.028)
	depth.material_override = _battle_frame_material(
		rect_size, Color(0, 0, 0, 0), Color("8f2f35"), 0.32
	)
	depth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	battle3d.add_child(depth)
	qm.size = rect_size
	m.mesh = qm
	m.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	m.position = Vector3(center_world.x, 0.0565, center_world.z)
	m.material_override = _battle_frame_material(rect_size)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	battle3d.add_child(m)
	var label_y := _battle_board_rect().position.y + CH * 0.54
	battle_hp3d_left = _battle_label3d(
		board_to_world(Vector2(visual_center.x - 1.68 * CW, label_y)),
		HORIZONTAL_ALIGNMENT_LEFT
	)
	battle_hp3d_right = _battle_label3d(
		board_to_world(Vector2(visual_center.x + 1.04 * CW, label_y)),
		HORIZONTAL_ALIGNMENT_LEFT
	)

func _battle_frame_material(
	rect_size: Vector2,
	fill_color: Color = Color(0.94, 0.24, 0.24, 0.10),
	border_color: Color = Color("ef6a6a"),
	dash_speed: float = 0.32
) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec2 rect_size;
uniform float radius;
uniform float border_width;
uniform float dash_length;
uniform float gap_length;
uniform float dash_speed;
uniform vec4 fill_color : source_color;
uniform vec4 border_color : source_color;

void fragment() {
	vec2 p = abs((UV - vec2(0.5)) * rect_size) - (rect_size * 0.5 - vec2(radius));
	float edge = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - radius;
	if (edge > 0.0) {
		discard;
	}
	float border = step(-border_width, edge);
	vec2 half_size = rect_size * 0.5;
	vec2 local = (UV - vec2(0.5)) * rect_size;
	vec2 inset = half_size - abs(local);
	float along = inset.x < inset.y ? (local.y + half_size.y) : (local.x + half_size.x);
	float dash = step(gap_length, mod(along - TIME * dash_speed, dash_length + gap_length));
	vec4 color = mix(fill_color, border_color, border * dash);
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("rect_size", rect_size)
	mat.set_shader_parameter("radius", 0.055)
	mat.set_shader_parameter("border_width", 0.012)
	mat.set_shader_parameter("dash_length", 0.11)
	mat.set_shader_parameter("gap_length", 0.065)
	mat.set_shader_parameter("dash_speed", dash_speed)
	mat.set_shader_parameter("fill_color", fill_color)
	mat.set_shader_parameter("border_color", border_color)
	return mat

func _battle_label3d(pos: Vector3, alignment: HorizontalAlignment) -> Label3D:
	var l := Label3D.new()
	l.font = _battle_font()
	l.font_size = 18
	l.pixel_size = 0.004
	l.horizontal_alignment = alignment
	l.width = 150.0
	l.line_spacing = 5
	l.modulate = Color.BLACK
	l.outline_size = 0
	l.double_sided = true
	l.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	pos.y = CARD_PLANE_Y + 0.04
	l.position = pos
	battle3d.add_child(l)
	return l

func _update_battle3d() -> void:
	if battle3d == null or not is_instance_valid(battle3d):
		return
	if battle_hp3d_left != null:
		battle_hp3d_left.text = "HP：$%.0f\nATK：%d" % [
			maxf(battle_hp_shown_left, 0.0), _battle_side_atk(true)]
	if battle_hp3d_right != null:
		battle_hp3d_right.text = "HP：$%.0f\nATK：%d" % [
			maxf(battle_hp_shown_right, 0.0), _battle_side_atk(false)]

func _clear_battle3d() -> void:
	if battle3d != null and is_instance_valid(battle3d):
		battle3d.queue_free()
	battle3d = null
	battle_hp3d_left = null
	battle_hp3d_right = null

func _versus_texture() -> Texture2D:
	if battle_versus_tex != null:
		return battle_versus_tex
	var path := "res://assets/versus.svg"
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_svg_from_string(FileAccess.get_file_as_string(path), 4.0) == OK:
			battle_versus_tex = ImageTexture.create_from_image(img)
	elif ResourceLoader.exists(path):
		battle_versus_tex = load(path) as Texture2D
	return battle_versus_tex

func _battle_bubble_texture() -> Texture2D:
	if battle_bubble_tex != null:
		return battle_bubble_tex
	var path := "res://assets/battle-bubble.svg"
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_svg_from_string(FileAccess.get_file_as_string(path), 4.0) == OK:
			battle_bubble_tex = ImageTexture.create_from_image(img)
	elif ResourceLoader.exists(path):
		battle_bubble_tex = load(path) as Texture2D
	return battle_bubble_tex

func _finish_battle() -> void:
	# 我方累计受伤，按整数从现金卡扣除
	var lost := int(floor(battle_dmg_to_player))
	if lost > 0:
		_spend_cash_cards(mini(lost, _cash_card_count()))
		_sync_cash_state()
	var rival_dead := battle_hp_left <= 0.0
	var player_dead := battle_hp_right <= 0.0
	var rival_ref = battle_rival
	var emp_ref = battle_employee
	_end_battle()
	# 败者消失（对手优先）
	if rival_dead and is_instance_valid(rival_ref):
		_dissolve_node(rival_ref)
		_show_toast("击退了 %s！" % String(rival_ref.cdef.get("name", "对手")))
	elif player_dead and is_instance_valid(emp_ref):
		_dissolve_node(emp_ref)
		_show_toast("%s 被击败了…" % String(emp_ref.cdef.get("name", "员工")))

func _sell_stack(sid: int, sale_origin: Vector2, sale_display: Vector2) -> bool:
	var arr: Array = stacks[sid].duplicate()
	for c in arr:
		if c.ctype in ["facility", "employee", "resource_node"]:
			_show_toast("设施、员工、资源点不能出售")
			return false
	var total := 0
	for c in arr:
		total += int(c.cdef.get("value", 0))
	if total <= 0:
		_show_toast("这张卡卖不出钱")
		return false
	for c in arr:
		destroy_card(c)
	_spawn_cash_cards(total, sale_origin, "office", sale_display)
	_float_text_screen("+$" + str(total), _bank_rect().position + Vector2(60, 0), Color("ffe66d"))
	return true

func _can_sell_stack(sid: int) -> bool:
	if not stacks.has(sid):
		return false
	var arr: Array = stacks[sid]
	if arr.is_empty():
		return false
	var total := 0
	for c in arr:
		if not is_instance_valid(c):
			return false
		if c.ctype in ["facility", "employee", "resource_node"]:
			return false
		total += int(c.cdef.get("value", 0))
	return total > 0

func _is_dragging_sellable() -> bool:
	if drag_sid == -1:
		return false
	return _can_sell_stack(drag_sid)

func _draw_bank_button_hint() -> void:
	if bank_button == null or not is_instance_valid(bank_button):
		return
	if not _is_dragging_sellable():
		return
	var rect := Rect2(-3, -3, bank_button.size.x + 6, bank_button.size.y + 6)
	var col := Color(0.18, 0.17, 0.16, 0.92)
	var width := 5.0
	var dash := 20.0
	var gap := 10.0
	_draw_dashed_side_on(bank_button, rect.position, rect.position + Vector2(rect.size.x, 0), dash, gap, dash_phase, col, width)
	_draw_dashed_side_on(bank_button, rect.position + Vector2(rect.size.x, 0), rect.position + rect.size, dash, gap, dash_phase + 7.0, col, width)
	_draw_dashed_side_on(bank_button, rect.position + rect.size, rect.position + Vector2(0, rect.size.y), dash, gap, dash_phase + 14.0, col, width)
	_draw_dashed_side_on(bank_button, rect.position + Vector2(0, rect.size.y), rect.position, dash, gap, dash_phase + 21.0, col, width)

func _draw_dashed_side_on(canvas: CanvasItem, a: Vector2, b: Vector2, dash: float, gap: float, phase: float, col: Color, width: float) -> void:
	var v := b - a
	var length := v.length()
	if length <= 0.1:
		return
	var dir := v / length
	var period := dash + gap
	var pos := -fposmod(phase, period)
	while pos < length:
		var from := maxf(pos, 0.0)
		var to := minf(pos + dash, length)
		if to > 0.0:
			canvas.draw_line(a + dir * from, a + dir * to, col, width)
		pos += period

# ---------------------------------------------------------------- recipes
func evaluate_stack(sid: int) -> void:
	if not stacks.has(sid) or productions.has(sid):
		return
	var arr: Array = stacks[sid]
	var counts: Dictionary = {}
	for c in arr:
		counts[c.card_id] = int(counts.get(c.card_id, 0)) + 1
	var basic_recipe := _basic_resource_recipe(counts, arr)
	if not basic_recipe.is_empty():
		var target = _work_target(arr, basic_recipe)
		if not _can_afford_product_cost(sid, basic_recipe):
			return
		productions[sid] = { "recipe": basic_recipe, "target": target }
		if target != null:
			_set_stack_workbar(
				sid,
				clampf(target.work_elapsed / float(basic_recipe.get("duration", 3.0)), 0, 1),
				target
			)
		return
	for recipe in DataLoader.recipes:
		var gate := String(recipe.get("requiredIdeaId", ""))
		if gate != "" and not GameState.idea_done(gate):
			continue
		if _recipe_matches(recipe, counts, arr):
			var target = _work_target(arr, recipe)
			if not _can_afford_product_cost(sid, recipe):
				return
			productions[sid] = { "recipe": recipe, "target": target }
			if target != null:    # 接续被工作对象上已有的进度（员工换人也不丢）
				_set_stack_workbar(
					sid,
					clampf(target.work_elapsed / float(recipe.get("duration", 4.0)), 0, 1),
					target
				)
			return

func _basic_resource_recipe(counts: Dictionary, arr: Array) -> Dictionary:
	var has_worker := false
	var worker_tags: Dictionary = {}
	for c in arr:
		if c.ctype != "employee":
			continue
		has_worker = true
		for t in c.cdef.get("workTags", []):
			worker_tags[t] = true
	if not has_worker:
		return {}
	if int(counts.get("lead", 0)) >= 1 and (worker_tags.has("sales") or worker_tags.has("any")):
		return {
			"id": "follow_single_lead",
			"name": "跟进线索",
			"worker_tags": ["sales", "any"],
			"duration": 3.0,
			"inputs": [{"id": "lead", "count": 1, "consume": true}],
			"outputs": [{"id": "order", "count": 1}],
			"output_zone": "market",
		}
	if int(counts.get("code", 0)) >= 1 and (worker_tags.has("dev") or worker_tags.has("any")):
		return {
			"id": "shape_single_code",
			"name": "封装代码",
			"worker_tags": ["dev", "any"],
			"duration": 3.0,
			"inputs": [{"id": "code", "count": 1, "consume": true}],
			"outputs": [{"id": "module", "count": 1}],
			"output_zone": "office",
		}
	return {}

# 被工作对象 = 配方第一个 input 对应的卡（资源/节点）；退化取首个非员工卡
func _work_target(arr: Array, recipe: Dictionary):
	var inputs: Array = recipe.get("inputs", [])
	if inputs.size() > 0:
		var tid := String(inputs[0].get("id", ""))
		for c in arr:
			if c.card_id == tid:
				return c
	for c in arr:
		if not is_person(c):
			return c
	return arr[0] if arr.size() > 0 else null

# 进度条始终绑定被生产的非人物目标卡。人物离开导致生产中断时，不清除目标卡自身
# 的 work_ratio，因此未完成进度条会留在目标卡上，重新加入员工后继续生产。
func _set_stack_workbar(sid: int, ratio: float, target = null) -> void:
	if not stacks.has(sid):
		return
	var arr: Array = stacks[sid]
	var display_target = target
	if not is_instance_valid(display_target) or not arr.has(display_target) or is_person(display_target):
		display_target = null
		for c in arr:
			if not is_person(c) and c.work_elapsed > 0.0:
				display_target = c
				break
		if display_target == null:
			for c in arr:
				if not is_person(c):
					display_target = c
					break
	for c in arr:
		c.set_work(ratio if c == display_target else 0.0)

func _can_afford_product_cost(sid: int, recipe: Dictionary) -> bool:
	var cost := _product_output_cost(sid, recipe)
	_sync_cash_state()
	if cost > GameState.cash:
		_show_toast("资金不足，无法生产产品")
		return false
	return true

func _charge_product_cost_on_complete(sid: int, recipe: Dictionary) -> bool:
	var cost := _product_output_cost(sid, recipe)
	if cost <= 0:
		return true
	if not _spend_cash_cards(cost):
		_show_toast("资金不足，产品未完成")
		return false
	var base: Vector2 = stack_base.get(sid, Vector2(300, 360))
	_float_cost(cost, base + Vector2(CW * 0.5, -34.0))
	return true

func _product_output_cost(sid: int, recipe: Dictionary) -> int:
	var mult := _output_mult(_stack_capacity(sid))
	var total := 0
	for outp in recipe.get("outputs", []):
		if not outp.has("id"):
			continue
		var id := String(outp["id"])
		if DataLoader.card_type(id) != "product":
			continue
		var cdef := DataLoader.card_def(id)
		total += int(cdef.get("cost", 0)) * int(outp.get("count", 1)) * mult
	return total

func _recipe_matches(recipe: Dictionary, counts: Dictionary, arr: Array) -> bool:
	for inp in recipe.get("inputs", []):
		var need := int(inp.get("count", 1))
		if int(counts.get(inp.get("id", ""), 0)) < need:
			return false
	var reserved_workers: Dictionary = {}
	for inp in recipe.get("inputs", []):
		if not inp.get("consume", false):
			continue
		var id := String(inp.get("id", ""))
		if DataLoader.card_type(id) == "employee":
			reserved_workers[id] = int(reserved_workers.get(id, 0)) + int(inp.get("count", 1))
	var rtags: Array = recipe.get("worker_tags", [])
	var worker_tags: Dictionary = {}
	var has_worker := false
	for c in arr:
		if c.ctype != "employee":
			continue
		var reserved := int(reserved_workers.get(c.card_id, 0))
		if reserved > 0:
			reserved_workers[c.card_id] = reserved - 1
			continue
		has_worker = true
		for t in c.cdef.get("workTags", []):
			worker_tags[t] = true
	for t in rtags:
		if t == "any" and has_worker:
			return true
		if worker_tags.has(t):
			return true
	return rtags.is_empty()

func _stack_capacity(sid: int) -> int:
	var cap := 0
	if stacks.has(sid):
		for c in stacks[sid]:
			if is_person(c):
				cap += int(c.cdef.get("capacity", 0))
	return cap

func _complete_production(sid: int) -> void:
	var rec: Dictionary = productions[sid]["recipe"]
	var target = productions[sid].get("target")
	var supply_chain = _supply_chain_for_source_stack(sid)
	var supply_target = supply_chain.get("target") if supply_chain != null else null
	productions.erase(sid)
	if not stacks.has(sid):
		return
	var arr: Array = stacks[sid]
	var base: Vector2 = stack_base[sid]
	var mult := _output_mult(_stack_capacity(sid))   # 产能 -> 产出倍率
	if not _charge_product_cost_on_complete(sid, rec):
		if is_instance_valid(target):
			target.work_elapsed = 0.0
			target.set_work(0.0)
		_set_stack_workbar(sid, 0.0)
		return
	for inp in rec.get("inputs", []):
		if not inp.get("consume", false):
			continue
		var need := int(inp.get("count", 1))
		var rid := String(inp.get("id", ""))
		for c in arr.duplicate():
			if need <= 0:
				break
			if c.card_id == rid:
				_dissolve_node(c)
				need -= 1
	if supply_chain != null and _recipe_can_route_to_target(rec, supply_target):
		await _animate_supply_transfer(supply_chain)
	var made_card := false
	for outp in rec.get("outputs", []):
		if outp.has("cash"):
			var amt := _cash_output_amount(rec, int(outp["cash"]) * mult)
			_spawn_cash_output(amt, base, supply_target)
			GameState.add_revenue(amt)
			_ka_ching(base, amt)
		elif outp.has("id"):
			var n := int(outp.get("count", 1)) * mult
			var oid := String(outp["id"])
			if oid == "cash":
				# 产品 + 客户成交时，现金按 value 公式动态计算；其它现金产物按配方数量。
				# 依次快速跳出现金卡（_spawn_cash_cards 内已带 0.04s 逐张弹出 + 同步资金）
				var cash_n := _cash_output_amount(rec, int(outp.get("count", 1)))
				_spawn_cash_output(cash_n, base, supply_target)
				GameState.add_revenue(cash_n)
				_ka_ching(base, cash_n)
				made_card = true
			else:
				var forced := String(rec.get("output_zone", ""))
				var zone := forced if forced != "" else _zone_for_center(base + Vector2(CW * 0.5, CH * 0.5))
				for i in n:
					_drop_output(oid, base, zone, supply_target)
				made_card = true
	if made_card:
		_wiggle_top_card(sid)            # 产出时生产堆顶卡轻微扭动
	_consume_node_uses(sid, rec)
	GameState.discover(String(rec.get("id", "")))
	if is_instance_valid(target):       # 完成后重置被工作对象的进度（若未被消耗销毁）
		target.work_elapsed = 0.0
		target.set_work(0.0)
	_set_stack_workbar(sid, 0.0)        # 完成后清掉目标卡上的进度条
	if stacks.has(sid):
		relayout(sid)
		evaluate_stack(sid)

func _cash_output_amount(recipe: Dictionary, fallback: int) -> int:
	var product_value := 0
	var customer_value := 0
	for inp in recipe.get("inputs", []):
		var id := String(inp.get("id", ""))
		var count := int(inp.get("count", 1))
		var cdef := DataLoader.card_def(id)
		match DataLoader.card_type(id):
			"product":
				product_value += int(cdef.get("cost", cdef.get("value", 0))) * count
			"customer":
				customer_value += int(cdef.get("value", 0)) * count
	if product_value > 0 and customer_value > 0:
		return int(ceil(float(product_value + customer_value) * 1.5))
	return fallback

# Decrement remaining uses on non-consumed node inputs; destroy when depleted.
# Lab equipment / research bench have many or unlimited uses.
func _consume_node_uses(sid: int, rec: Dictionary) -> void:
	if not stacks.has(sid):
		return
	for inp in rec.get("inputs", []):
		if inp.get("consume", false):
			continue
		var rid := String(inp.get("id", ""))
		for c in stacks[sid].duplicate():
			if c.card_id == rid and c.uses_left >= 0:
				c.uses_left -= 1
				_refresh_card_face(c)
				if c.uses_left <= 0:
					_show_toast(String(c.cdef.get("name", rid)) + " 已耗尽")
					_dissolve_node(c)
				break

# 产能 -> 产出倍率：能力越强一次产出越多（边际递减）
func _output_mult(cap: int) -> int:
	return 1 + int(floor(maxf(0, cap - 3) / 4.0))

func _supply_chain_for_source_stack(source_sid: int):
	_cleanup_supply_chains()
	for chain in supply_chains:
		var source = chain.get("source")
		var target = chain.get("target")
		if is_instance_valid(source) and source.stack_id == source_sid \
				and is_instance_valid(target) and target.stack_id != source_sid:
			return chain
	return null

func _recipe_can_route_to_target(recipe: Dictionary, supplied_target) -> bool:
	if supplied_target == null or not is_instance_valid(supplied_target) \
			or not stacks.has(supplied_target.stack_id):
		return false
	for outp in recipe.get("outputs", []):
		var id := "cash" if outp.has("cash") else String(outp.get("id", ""))
		if _output_id_interacts_with_stack(id, supplied_target.stack_id):
			return true
	return false

func _animate_supply_transfer(chain) -> void:
	if chain == null:
		return
	var source = chain.get("source")
	var supplied_target = chain.get("target")
	if not is_instance_valid(source) or not is_instance_valid(supplied_target):
		return
	var transit := {
		"source": source,
		"target": supplied_target,
		"progress": 0.0,
	}
	supply_transits.append(transit)
	var tw := create_tween()
	tw.tween_method(func(value: float):
		transit["progress"] = value
		queue_redraw()
	, 0.0, 1.0, 0.8).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	await tw.finished
	supply_transits.erase(transit)
	queue_redraw()

func _spawn_cash_output(amount: int, from_pos: Vector2, supplied_target = null) -> void:
	if supplied_target != null and is_instance_valid(supplied_target) \
			and stacks.has(supplied_target.stack_id) \
			and _output_id_interacts_with_stack("cash", supplied_target.stack_id):
		for i in amount:
			_drop_output("cash", from_pos, "office", supplied_target)
		_sync_cash_state()
		return
	_spawn_cash_cards(amount, from_pos, "office")

func _drop_output(id: String, from_pos: Vector2, zone: String, supplied_target = null) -> void:
	if supplied_target != null and is_instance_valid(supplied_target) \
			and stacks.has(supplied_target.stack_id) \
			and _output_id_interacts_with_stack(id, supplied_target.stack_id):
		var target_sid: int = supplied_target.stack_id
		var landing: Vector2 = stack_base[target_sid]
		var nc := spawn_card(id, landing)
		nc.zone = zone
		var merged_sid := _merge(nc.stack_id, target_sid)
		_fly_out_card(nc, _project(from_pos + Vector2(CW, CH) * 0.5))
		if stacks.has(merged_sid):
			relayout(merged_sid)
		return
	const GROUP_RANGE := 2.0
	var origin_center := from_pos + Vector2(CW, CH) * 0.5
	var landing := _nearby_output_landing(origin_center, zone)
	var best = null
	var best_d := CW * GROUP_RANGE
	for c in all_cards:
		if c.card_id == id:
			var d: float = _board_center(c).distance_to(landing + Vector2(CW, CH) * 0.5)
			if d < best_d:
				best_d = d
				best = c
	var nc := spawn_card(id, landing)
	nc.zone = zone
	if best != null:
		_merge(nc.stack_id, best.stack_id)
	_fly_out_card(nc, _project(origin_center))

# 产出卡顺滑飞出：从生产堆中心放大着滑到落点（无回弹，cubic 缓出）
func _fly_out_card(c, from_display: Vector2) -> void:
	if not is_instance_valid(c):
		return
	var final_pos: Vector2 = c.position
	var final_scale: Vector2 = c.scale
	c.position = from_display - Vector2(CW, CH) * 0.5 * maxf(view_zoom, 0.1)
	c.scale = final_scale * 0.18
	c.rotation = GameState.rng.randf_range(-0.05, 0.05)
	var old_z: int = c.z_index
	c.z_index = max(old_z, 2300)
	var final_face_pos := Vector3.ZERO
	var has_face := c.face3d != null and is_instance_valid(c.face3d)
	if has_face:
		final_face_pos = c.face3d.position
		var start_face_pos := _unproject_world(from_display)
		start_face_pos.y = final_face_pos.y + 0.02
		c.face3d.position = start_face_pos
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "position", final_pos, FLY_OUT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", final_scale, FLY_OUT_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", 0.0, FLY_OUT_ROT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if has_face:
		tw.tween_property(c.face3d, "position", final_face_pos, FLY_OUT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func():
		if is_instance_valid(c):
			c.z_index = old_z
			relayout(c.stack_id)
	)

func _nearby_output_landing(origin_center: Vector2, zone: String) -> Vector2:
	const DROP_MIN := 1.0   # 至少 1 张卡距离 → 不与中心卡重合
	const DROP_MAX := 3.0   # 最多 3 张卡距离
	var half := Vector2(CW, CH) * 0.5
	var best_corner := clamp_to_zone(origin_center - half, zone)
	var best_clear := -INF
	# 多次尝试，挑一个与已有卡不重叠的落点；都不行就用「离最近卡最远」的那个
	for attempt in 30:
		var ang := GameState.rng.randf() * TAU
		var grow := 1.0 + attempt * 0.03   # 一直找不到就稍微放宽外圈
		var dist := GameState.rng.randf_range(CW * DROP_MIN, CW * DROP_MAX * grow)
		var corner := clamp_to_zone(origin_center + Vector2(cos(ang), sin(ang)) * dist - half, zone)
		var center := corner + half
		# 与现有所有卡牌堆做矩形不重叠判定
		var clear := INF
		for sid in stack_base.keys():
			var oc: Vector2 = stack_base[sid] + half
			var dx := absf(center.x - oc.x)
			var dy := absf(center.y - oc.y)
			# 归一化重叠间隙：>0 表示分离
			var gap := maxf(dx / (CW * 0.9) - 1.0, dy / (CH * 0.9) - 1.0)
			clear = minf(clear, gap)
		if clear > 0.0:
			return corner
		if clear > best_clear:
			best_clear = clear
			best_corner = corner
	return best_corner

# 生产堆顶卡轻微扭动一下（产出反馈）
func _wiggle_top_card(sid: int) -> void:
	if not stacks.has(sid) or stacks[sid].is_empty():
		return
	var top = stacks[sid].back()
	if not is_instance_valid(top):
		return
	var r0: float = top.rotation
	var tw := create_tween()
	tw.tween_property(top, "rotation", r0 + 0.06, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(top, "rotation", r0 - 0.045, 0.09).set_trans(Tween.TRANS_SINE)
	tw.tween_property(top, "rotation", r0, 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _attach_to_stack(c, sid: int) -> void:
	var own: int = c.stack_id
	if own != sid:
		stacks.erase(own)
		stack_base.erase(own)
		c.stack_id = sid
		stacks[sid].append(c)

# ---------------------------------------------------------------- research
func _update_research(delta: float) -> void:
	for sid in stacks.keys():
		var arr: Array = stacks[sid]
		var has_bench := false
		var cap := 0
		for c in arr:
			if c.card_id == "research_bench":
				has_bench = true
			elif is_person(c):
				cap += int(c.cdef.get("capacity", 0))
		if has_bench:
			var bench = null
			for c in arr:
				if c.card_id == "research_bench":
					bench = c
					break
			if cap > 0 and not productions.has(sid):
				GameState.add_rp(cap * 0.15 * delta)
				if bench:
					bench.set_work(fmod(Time.get_ticks_msec() / 600.0, 1.0))   # 研究中（即时，不持久）
			elif bench:
				bench.set_work(0.0)

func _update_business_school(delta: float) -> void:
	if school_empty_toast_t > 0.0:
		school_empty_toast_t -= delta
	for sid in stacks.keys():
		if not stacks.has(sid) or productions.has(sid):
			continue
		var arr: Array = stacks[sid]
		var school = null
		var cap := 0
		for c in arr:
			if c.card_id == "business_school":
				school = c
			elif is_person(c):
				cap += int(c.cdef.get("capacity", 0))
		if school == null:
			continue
		if cap <= 0:
			school.set_work(0.0)
			continue
		school.work_elapsed += delta * maxf(1.0, cap)
		school.set_work(clampf(school.work_elapsed / SCHOOL_INSIGHT_NEED, 0.0, 1.0))
		if school.work_elapsed >= SCHOOL_INSIGHT_NEED:
			school.work_elapsed = 0.0
			school.set_work(0.0)
			_unlock_random_stage_idea()

func _stage_idea_candidates() -> Array:
	var out: Array = []
	var pool: Array = DataLoader.idea_pools.get(str(GameState.stage), [])
	for raw_id in pool:
		var id := String(raw_id)
		var node: Dictionary = DataLoader.research.get(id, {})
		if node.is_empty() or GameState.idea_done(id):
			continue
		if int(node.get("stage", -1)) != GameState.stage:
			continue
		if not _prereq_ok(node):
			continue
		out.append(id)
	return out

func _unlock_random_stage_idea() -> void:
	var candidates := _stage_idea_candidates()
	if candidates.is_empty():
		if school_empty_toast_t <= 0.0:
			_show_toast("商学院暂无可跳出的「%s」阶段 idea：先补前置或推进阶段" % GameState.stage_name())
			school_empty_toast_t = 8.0
		return
	var recipe_candidates: Array = []
	for raw_id in candidates:
		var cid := String(raw_id)
		var cnode: Dictionary = DataLoader.research.get(cid, {})
		if String(cnode.get("kind", "")) == "recipe":
			recipe_candidates.append(cid)
	var pick_from := recipe_candidates if not recipe_candidates.is_empty() else candidates
	var id := String(pick_from[GameState.rng.randi_range(0, pick_from.size() - 1)])
	var node: Dictionary = DataLoader.research.get(id, {})
	if GameState.unlock_idea_free(id):
		_show_toast("商学院产出新 idea：%s" % String(node.get("name", id)))

# ---------------------------------------------------------------- departments
func _employees_in(sid: int) -> Array:
	var out: Array = []
	if stacks.has(sid):
		for c in stacks[sid]:
			if is_person(c):
				out.append(c)
	return out

func _can_fold(sid: int) -> bool:
	if not stacks.has(sid):
		return false
	var arr: Array = stacks[sid]
	if arr.size() < 3:
		return false
	for c in arr:
		if not is_person(c):
			return false        # only pure-employee stacks fold
	return true

func _fold_department(sid: int) -> void:
	var emps := _employees_in(sid)
	var tally: Dictionary = {}
	var headcount := 0
	var cap := 0
	var salary := 0
	for c in emps:
		headcount += 1
		cap += int(c.cdef.get("capacity", 0))
		salary += int(c.cdef.get("salary", 0))
		for t in c.cdef.get("workTags", []):
			if t != "any":
				tally[t] = int(tally.get(t, 0)) + 1
	var specialty := "sales"
	var best := -1
	for t in tally:
		if int(tally[t]) > best:
			best = int(tally[t])
			specialty = t
	var base: Vector2 = stack_base[sid]
	for c in emps.duplicate():
		destroy_card(c)
	_spawn_department(specialty, headcount, cap, salary, base)
	_show_toast("组建%s！%d人，自动产出" % [_dept_name(specialty), headcount])

func _dept_name(specialty: String) -> String:
	match specialty:
		"sales": return "销售部"
		"dev": return "研发部"
		"admin": return "行政部"
		_: return "综合部"

func _spawn_department(specialty: String, headcount: int, cap: int, salary: int, base: Vector2) -> void:
	var c = CardScript.new()
	add_child(c)
	c.card_id = "dept_" + specialty
	c.ctype = "department"
	c.cdef = { "name": _dept_name(specialty), "type": "department", "salary": salary, "capacity": headcount }
	var sid := next_stack_id
	next_stack_id += 1
	c.stack_id = sid
	c.stack_pos = 0
	var px: float = clampf(base.x, CANVAS_X0 + 40, CANVAS_X1 - 40 - CW)
	c.zone = "market" if px >= DIVIDER_X else "office"   # 部门落在所在分区
	stacks[sid] = [c] as Array
	stack_base[sid] = Vector2(px, MID_Y1 - CH - 16)      # 紧贴信息栏上方的 play area 内
	all_cards.append(c)
	relayout(sid)
	_play_card_pop(c)
	departments.append({
		"card": c, "specialty": specialty, "headcount": headcount,
		"capacity": cap, "timer": 0.0, "interval": maxf(2.5, 6.0 - 0.3 * cap) })

func _update_departments(delta: float) -> void:
	for d in departments:
		d["timer"] += delta
		if d["timer"] >= d["interval"]:
			d["timer"] = 0.0
			_department_output(d)

# Loose valuable resource cards in the MARKET (right) zone auto-convert after 1s idle:
# they fly to the bank slot and convert to cash.
const AUTOSELL_DELAY := 1.0
func _update_auto_sell(delta: float) -> void:
	for c in all_cards.duplicate():
		var sid: int = c.stack_id
		# only 回款(revenue) auto-sells; lead/contract stay until processed（单画布，不再限分区）
		if c.card_id != "revenue":
			continue
		if sid == drag_sid or not stacks.has(sid) or stacks[sid].size() != 1 or productions.has(sid):
			c.idle_t = 0.0
			continue
		c.idle_t += delta
		if c.idle_t >= AUTOSELL_DELAY:
			_fly_sell(c)

func _fly_sell(c) -> void:
	var value := int(c.cdef.get("value", 0))
	# detach from logic
	var sid: int = c.stack_id
	stacks.erase(sid)
	stack_base.erase(sid)
	productions.erase(sid)
	all_cards.erase(c)
	c.z_index = 2600
	var dest := _bank_rect().position + _bank_rect().size * 0.5 - Vector2(CW, CH) * 0.25
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "position", dest, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "scale", c.scale * 0.4, 0.45)
	# 3D 网格同步：飞向出售栏方向 + 缩小
	var mesh := _face3d_mesh(c)
	if mesh != null and is_instance_valid(c.face3d):
		var dest_world := _unproject_world(_bank_rect().position + _bank_rect().size * 0.5)
		dest_world.y += 0.4
		var tw3 := create_tween()
		tw3.set_parallel(true)
		tw3.tween_property(c.face3d, "global_position", dest_world, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw3.tween_property(mesh, "scale", Vector3.ONE * 0.3, 0.45)
	tw.chain().tween_callback(func():
		_spawn_cash_cards(value, _unproject(_bank_rect().position), "office")
		_float_text_screen("+$" + str(value), _bank_rect().position + Vector2(60, -10), Color("ffe66d"))
		c.queue_free())

func _department_output(d: Dictionary) -> void:
	var spec: String = d["specialty"]
	var out_id := "lead"
	var zone := "market"
	var origin := Vector2(1100, 360)
	if spec == "dev":
		out_id = "prd"; zone = "office"; origin = Vector2(260, 360)
	elif spec == "admin":
		out_id = "training"; zone = "office"; origin = Vector2(260, 360)   # 行政部=培训引擎
	elif spec == "sales":
		out_id = "revenue"; zone = "market"; origin = Vector2(1100, 360)   # 销售部=自动回款引擎
	var n := _output_mult(d["capacity"])
	for i in n:
		_drop_output(out_id, origin, zone)

# ---------------------------------------------------------------- process
func _process(delta: float) -> void:
	if is_instance_valid(bottom_info):
		bottom_info.queue_redraw()   # 底部信息栏随 hover/hint 实时刷新
	_update_workbars()
	_relayout_loose_packs()   # 确保卡包就绪后转 3D（含开局卡包）并跟随
	_update_battle(delta)
	if is_instance_valid(founder_bubble):
		var founder = _founder_on_board()
		if is_instance_valid(founder):
			# Pop the bubble the moment the founder card is moved.
			if _board_topleft(founder).distance_to(founder_bubble_anchor) > 2.0:
				founder_bubble.queue_free()
			else:
				_reposition_founder_bubble(founder_bubble, founder)
		else:
			founder_bubble.queue_free()
	if game_over:
		return
	if selected_card != null and not is_instance_valid(selected_card):
		selected_card = null
		hint_text = DEFAULT_HINT
	for sid in productions.keys():
		if not stacks.has(sid):
			productions.erase(sid)
			continue
		var p: Dictionary = productions[sid]
		var target = p.get("target")
		if not is_instance_valid(target):
			productions.erase(sid)
			continue
		var speed: float = maxf(0.4, _stack_capacity(sid) / 3.0)
		var dur := float(p["recipe"].get("duration", 4.0))
		target.work_elapsed += delta * speed                 # 进度累加在被工作对象卡上
		_set_stack_workbar(sid, clampf(target.work_elapsed / dur, 0, 1), target)
		if target.work_elapsed >= dur:
			_complete_production(sid)
	_update_research(delta)
	_update_business_school(delta)
	_update_departments(delta)
	_update_auto_sell(delta)
	_update_drag_spring(delta)
	_update_stack_hint(delta)
	val_timer -= delta
	if val_timer <= 0:
		val_timer = 0.5
		_recompute_valuation()
	if emergency:
		emergency_t -= delta
		_sync_cash_state()
		if GameState.cash > 0:
			emergency = false
			_show_toast("渡过危机！")
		elif emergency_t <= 0:
			_trigger_game_over()
	else:
		month_time -= delta
		if month_time <= 0:
			_settle_month()
	if toast_t > 0:
		toast_t -= delta
	_update_card_visual_states(delta)
	_update_cursor()
	_update_hud()
	queue_redraw()

# 生产进度条（3D）：在持有 work_ratio 的卡上方画一条 bg+fill 小条
func _update_workbars() -> void:
	for c in all_cards:
		if not is_instance_valid(c):
			continue
		var active: bool = c.work_ratio > 0.0 and is_instance_valid(c.face3d)
		if not active:
			if c.workbar3d != null and is_instance_valid(c.workbar3d):
				c.workbar3d.visible = false
			continue
		if c.workbar3d == null or not is_instance_valid(c.workbar3d):
			c.workbar3d = _make_workbar3d(c)
		if c.workbar3d == null:
			continue
		c.workbar3d.visible = true
		var fill = c.workbar3d.get_child(1)
		var r := clampf(c.work_ratio, 0.02, 1.0)
		fill.scale.x = r
		var fill_width := CARD3D_W - 0.028
		fill.position.x = -fill_width * 0.5 + fill_width * r * 0.5   # 左对齐生长

func _make_workbar3d(c) -> Node3D:
	if not is_instance_valid(c.face3d):
		return null
	var bar := Node3D.new()
	bar.position = Vector3(0, 0.014, -(CARD3D_H * 0.5 + 0.026))   # 卡顶（北）外侧
	var flat := Basis.from_euler(Vector3(deg_to_rad(-90.0), 0, 0))
	var bar_width := CARD3D_W - 0.012
	var bg := MeshInstance3D.new()
	var bgm := QuadMesh.new()
	bgm.size = Vector2(bar_width, 0.05)
	bg.mesh = bgm
	bg.transform = Transform3D(flat, Vector3.ZERO)
	bg.material_override = _rounded_unshaded_mat(Color("2a2824"), bgm.size, 0.008, 0.007)
	bar.add_child(bg)
	var fill := MeshInstance3D.new()
	var fm := QuadMesh.new()
	fm.size = Vector2(bar_width - 0.016, 0.036)
	fill.mesh = fm
	fill.transform = Transform3D(flat, Vector3(0, 0.001, 0))
	fill.material_override = _unshaded_mat(Color("bdbab1"))
	bar.add_child(fill)
	c.face3d.add_child(bar)
	return bar

func _rounded_unshaded_mat(col: Color, rect_size: Vector2, radius: float, border_width: float = 0.0) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 tint : source_color;
uniform vec2 rect_size;
uniform float radius;
uniform float border_width;

void fragment() {
	vec2 p = abs((UV - vec2(0.5)) * rect_size) - (rect_size * 0.5 - vec2(radius));
	float edge = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - radius;
	if (edge > 0.0) {
		discard;
	}
	vec2 inner_size = rect_size - vec2(border_width * 2.0);
	float inner_radius = max(radius - border_width, 0.0);
	vec2 inner_p = abs((UV - vec2(0.5)) * rect_size) - (inner_size * 0.5 - vec2(inner_radius));
	float inner_edge = length(max(inner_p, vec2(0.0))) + min(max(inner_p.x, inner_p.y), 0.0) - inner_radius;
	float border = step(0.0, inner_edge);
	ALBEDO = mix(tint.rgb, vec3(0.02), border);
	ALPHA = tint.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("rect_size", rect_size)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("border_width", border_width)
	return m

func _unshaded_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m

func _update_card_visual_states(delta: float) -> void:
	dash_phase += delta * 35.0
	supply_flow_phase += delta * 55.0
	_update_supply_arrow_mesh()
	if bank_button != null and is_instance_valid(bank_button) and _is_dragging_sellable():
		bank_button.queue_redraw()
	var mouse_pos := get_viewport().get_mouse_position()
	var hovered_chain = null
	if drag_cards.is_empty() and drag_pack == null and supply_drag_source == null and not panning_canvas:
		hovered_chain = _supply_chain_at(mouse_pos)
	if hovered_chain != supply_hover_chain:
		supply_hover_chain = hovered_chain
	supply_hover_scale = move_toward(
		supply_hover_scale,
		1.0 if supply_hover_chain != null else 0.0,
		delta * 7.5
	)
	var next_hover = null
	if drag_cards.is_empty() and not panning_canvas:
		next_hover = _topmost_at(mouse_pos, true)   # 对手卡虽不可拾取，悬停仍显示信息
	if next_hover != hover_card:
		var old_sid: int = hover_card.stack_id if is_instance_valid(hover_card) else -1
		var new_sid: int = next_hover.stack_id if is_instance_valid(next_hover) else -1
		
		# If the stack changed, unhover the old stack
		if old_sid != -1 and old_sid != new_sid:
			_set_stack_hovered(old_sid, false)
			relayout(old_sid)
			
		hover_card = next_hover
		
		# If the stack changed, hover the new stack (single card stacks included)
		if new_sid != -1 and old_sid != new_sid:
			if stacks.has(new_sid):
				_dismiss_new_card_badge(next_hover)
				_set_stack_hovered(new_sid, true)
				relayout(new_sid)

	var hint_sids: Dictionary = {}
	if supply_drag_source != null and is_instance_valid(supply_drag_source):
		var source_sid: int = supply_drag_source.stack_id
		for sid in stacks.keys():
			var osid := int(sid)
			if osid != source_sid and _stack_accepts_supply_outputs(source_sid, osid):
				hint_sids[osid] = true
	elif drag_sid != -1 and stacks.has(drag_sid):
		for sid in stacks.keys():
			var osid := int(sid)
			if osid == drag_sid:
				continue
			if _would_interact(drag_sid, osid):
				hint_sids[osid] = true

	for c in all_cards:
		if not is_instance_valid(c):
			continue
		var hint := hint_sids.has(c.stack_id)
		c.set_stack_hint(hint)
		if hint:
			c.set_dash_phase(dash_phase)

func _update_cursor() -> void:
	if supply_drag_source != null:
		_set_cursor_state("drag")
		return
	if not drag_cards.is_empty() or drag_pack != null:
		_set_cursor_state("drag")
		return
	if panning_canvas:
		_set_cursor_state("pan")
		return
	var hovered_control := get_viewport().gui_get_hovered_control()
	if hovered_control != null and CursorManager.is_interactive_control(hovered_control):
		_set_cursor_state("hover")
		return
	var p := get_viewport().get_mouse_position()
	if supply_hover_chain != null:
		_set_cursor_state("hover")
		return
	if _topmost_at(p) != null:
		_set_cursor_state("hover")
		return
	_set_cursor_state("default")

# ---------------------------------------------------------------- month
func _settle_month() -> void:
	var payroll := 0
	for c in all_cards:
		payroll += int(c.cdef.get("salary", 0))
	var payroll_short := payroll > GameState.cash
	if payroll > 0:
		_spend_cash_cards(mini(payroll, GameState.cash))
	_float_text("发薪 -$" + str(payroll), Vector2(880, 300), Color("ff8c8c"))
	GameState.advance_month()
	month_time = float(DataLoader.balance.get("month_seconds", 90.0))
	_sync_cash_state()
	if payroll_short:
		emergency = true
		emergency_t = float(DataLoader.balance.get("emergency_seconds", 30.0))
		_show_toast("现金不足以发薪！30秒内卖卡补足，否则破产")

func _trigger_game_over() -> void:
	game_over = true
	_show_toast("💀 资金链断裂，公司破产")

# ---------------------------------------------------------------- pack
func buy_pack(pack_id: String) -> void:
	var pack: Dictionary = DataLoader.packs.get(pack_id, {})
	if pack.is_empty():
		return
	if GameState.stage < int(pack.get("stage", 0)):
		_show_toast("该卡包需「%s」阶段解锁" % GameState.STAGE_NAMES[int(pack.get("stage", 0))])
		return
	if (pack.get("slots", []) as Array).is_empty():
		_show_toast("该卡包内容尚未开放")
		return
	var price := int(pack.get("price", 6))
	if not _spend_cash_cards(price):
		_show_toast("场上现金不足，买不起卡包")
		return
	var slots: Array = pack.get("slots", [])
	var n := GameState.rng.randi_range(int(pack.get("minCards", 3)), int(pack.get("maxCards", 5)))
	var got := mini(n, slots.size())
	var contents: Array = []
	for i in got:
		contents.append(_pick_pack_card(pack_id, slots[i], contents))
	var bm := _pick_business_model_card(int(pack.get("stage", 0)), contents)
	if bm != "":
		contents.append(bm)
	contents = _sanitize_pack_contents(pack_id, contents)
	_spawn_loose_pack(pack_id, pack, contents)
	_show_toast("%s 已弹出，点击画布上的卡包拆开" % String(pack.get("name", "卡包")))

func _sanitize_pack_contents(pack_id: String, contents: Array) -> Array:
	var out: Array = []
	var founder_reserved := _founder_on_board() != null
	for idv in contents:
		var id := String(idv)
		if id == "founder":
			if pack_id != "garage_pack" or founder_reserved:
				continue
			founder_reserved = true
		out.append(id)
	return out

func _spawn_loose_pack(pack_id: String, pack: Dictionary, contents: Array, landing_override = null, instant: bool = false) -> Node2D:
	var p = PackCardScript.new()
	add_child(p)
	p.setup(pack_id, String(pack.get("name", "卡包")), contents)
	p.z_index = 2100
	loose_packs.append(p)
	p.board_pos = (landing_override as Vector2) if landing_override != null else _pack_landing_below(pack_id)
	var landing := _project(p.board_pos)
	p.position = landing
	p.scale = Vector2.ONE * PACK_SCALE * view_zoom
	p.rotation = 0.0
	p.visible = false
	_place_pack3d(p)
	if instant or p.face3d == null or not is_instance_valid(p.face3d):
		p.ready_to_open = true
		return p

	# 全程保持平躺的 3D 形态：从顶部对应卡包按钮处缩小出现，落到画布时恢复正常大小。
	p.ready_to_open = false
	var start_board := _pack_button_board_start(pack_id)
	var start_world := board_to_world(start_board + Vector2(PACK_W, PACK_H) * 0.5)
	start_world.y = 0.05 + PACK3D_THICK
	var landing_world: Vector3 = p.face3d.position
	p.face3d.position = start_world
	var cardroot := p.face3d.get_child(0) as Node3D
	if cardroot != null:
		cardroot.scale = Vector3.ONE * 0.35
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p.face3d, "position", landing_world, 0.48) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if cardroot != null:
		tw.tween_property(cardroot, "scale", Vector3.ONE, 0.48) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func():
		if is_instance_valid(p):
			p.ready_to_open = true)
	return p

func _pack_button_board_start(pack_id: String) -> Vector2:
	for row in pack_buttons:
		if String(row["id"]) == pack_id:
			var btn: Button = row["btn"]
			var center_on_board := _unproject(btn.global_position + btn.size * 0.5)
			return center_on_board - Vector2(PACK_W, PACK_H) * 0.5
	return _random_pack_landing()

func _random_pack_landing() -> Vector2:
	return Vector2(
		GameState.rng.randf_range(190.0, 760.0),
		GameState.rng.randf_range(198.0, 350.0)
	)

# Landing point (board space) directly below the pack's UI button, so the
# thrown pack settles under the button it came from. Small jitter avoids
# perfect overlap when several packs are opened in a row.
func _pack_landing_below(pack_id: String) -> Vector2:
	for row in pack_buttons:
		if String(row["id"]) == pack_id:
			var btn: Button = row["btn"]
			var bcx: float = btn.global_position.x + btn.size.x * 0.5
			var drop: float = GameState.rng.randf_range(150.0, 240.0)
			var jitter: float = GameState.rng.randf_range(-36.0, 36.0)
			# Screen-space top-left target that centers the full-size card under the button.
			var target := Vector2(
				bcx + jitter - PACK_W * 0.5 * view_zoom,
				btn.global_position.y + btn.size.y + drop
			)
			var bp := _unproject(target)
			# 卡包只能落在白板内：横纵都夹到白板矩形
			bp.x = clampf(bp.x, CANVAS_X0 + 8.0, CANVAS_X1 - PACK_W - 8.0)
			bp.y = clampf(bp.y, MID_Y0 + 8.0, MID_Y1 - PACK_H)
			return bp
	return _random_pack_landing()

func _relayout_loose_packs() -> void:
	for p in loose_packs:
		if not is_instance_valid(p) or p.opened or not p.ready_to_open:
			continue
		p.position = _project(p.board_pos)        # 旧 2D 位置仍设（开包原点等读它）
		p.scale = Vector2.ONE * PACK_SCALE * view_zoom
		p.visible = false                          # 2D 隐藏，改用 3D 网格
		_place_pack3d(p)

# 把卡包封面的 2D 轮廓多边形（PackCard._body_poly，0..W / 0..H）挤出成有厚度的棱柱：
# 中央 80% 保持正常厚度，左右各 10% 以斜面逐渐收薄，最外缘为 50% 厚度。
func _pack_bottom_y(x: float, pw: float, thick: float) -> float:
	var edge_ratio := absf(x) / (pw * 0.5)
	if edge_ratio <= 0.8:
		return -thick
	var taper := clampf((edge_ratio - 0.8) / 0.2, 0.0, 1.0)
	return -lerpf(thick, thick * 0.5, taper)

func _pack_prism_mesh(poly2: PackedVector2Array, pw: float, ph: float, thick: float) -> ArrayMesh:
	var n := poly2.size()
	# 卡包本地坐标 (0..W, 0..H) → 居中世界 XZ
	var pts := PackedVector2Array()
	for q in poly2:
		pts.append(Vector2((q.x / PackCardScript.W - 0.5) * pw, (q.y / PackCardScript.H - 0.5) * ph))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y_top := 0.0
	# 侧壁底边随横向位置变化，左右形成斜向收薄的厚度轮廓。
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var ta := Vector3(a.x, y_top, a.y)
		var tb := Vector3(b.x, y_top, b.y)
		var ba := Vector3(a.x, _pack_bottom_y(a.x, pw, thick), a.y)
		var bb := Vector3(b.x, _pack_bottom_y(b.x, pw, thick), b.y)
		st.add_vertex(ta); st.add_vertex(tb); st.add_vertex(bb)
		st.add_vertex(ta); st.add_vertex(bb); st.add_vertex(ba)
	# 上盖保持平整，底盖使用相同厚度函数形成连续斜面。
	var idx := Geometry2D.triangulate_polygon(pts)
	for k in range(0, idx.size(), 3):
		var p0 := pts[idx[k]]
		var p1 := pts[idx[k + 1]]
		var p2 := pts[idx[k + 2]]
		st.add_vertex(Vector3(p0.x, y_top, p0.y))
		st.add_vertex(Vector3(p1.x, y_top, p1.y))
		st.add_vertex(Vector3(p2.x, y_top, p2.y))
		st.add_vertex(Vector3(p0.x, _pack_bottom_y(p0.x, pw, thick), p0.y))
		st.add_vertex(Vector3(p1.x, _pack_bottom_y(p1.x, pw, thick), p1.y))
		st.add_vertex(Vector3(p2.x, _pack_bottom_y(p2.x, pw, thick), p2.y))
	st.generate_normals()
	return st.commit()

# ---- 卡包 3D 网格（与卡牌同套：pivot + mesh，躺在白板上）----
func _ensure_pack3d(p) -> void:
	if p.face3d != null and is_instance_valid(p.face3d):
		return
	if city_bg == null or city_bg.world_card_root() == null:
		return
	var pw := PACK_W / CITY_CELL
	var ph := PACK_H / CITY_CELL
	var pivot := Node3D.new()
	var cardroot := Node3D.new()                            # 可缩放节点（pop 弹出），placement 不动它
	pivot.add_child(cardroot)
	# 卡包盒身（沿封面真实轮廓——桶形+上下锯齿——挤出的厚棱柱，投射真阴影）：
	# 顶面在 cardroot 原点、底面贴白板
	var frame := MeshInstance3D.new()
	frame.mesh = _pack_prism_mesh(p._body_poly(), pw, ph, PACK3D_THICK)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.1, 0.1, 0.1)
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	frame.material_override = fmat
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	cardroot.add_child(frame)
	# 卡包封面：烘焙图贴在盒子顶面
	var m := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(pw, ph)
	m.mesh = qm
	m.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	m.position = Vector3(0, 0.002, 0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR   # 不透明部分能投射阴影
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # 卡包保持原色
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cardroot.add_child(m)
	_add_glass_coat(cardroot, pw, ph, 0.006)   # 卡包：玻璃反光
	city_bg.world_card_root().add_child(pivot)
	p.face3d = pivot
	p.tree_exited.connect(func():
		if is_instance_valid(pivot):
			pivot.queue_free())
	_bake_pack_async(p, mat)
	cardroot.scale = Vector3.ONE

func _bake_pack_async(p, mat) -> void:
	if face_baker == null:
		return
	var tex = await face_baker.bake_pack(p.pack_id, p.pack_name, p.contents)
	if tex != null and is_instance_valid(mat):
		mat.albedo_texture = tex
		mat.albedo_color = Color(1, 1, 1)   # 贴图就位后取消占位深色，否则白图标/名字被乘暗
		if mat.emission_enabled:
			mat.emission_texture = tex

func _place_pack3d(p) -> void:
	_ensure_pack3d(p)
	var pivot = p.face3d
	if pivot == null or not is_instance_valid(pivot):
		return
	var w := board_to_world(p.board_pos + Vector2(PACK_W * 0.5, PACK_H * 0.5))
	w.y = 0.05 + PACK3D_THICK            # 盒底贴白板（盒顶在 pivot 原点）
	if p == drag_pack:
		w.y += 0.1333
	pivot.transform = Transform3D(Basis.IDENTITY, w)

func _topmost_pack_at(display_pt: Vector2):
	var bpt := _unproject(display_pt)
	var best = null
	var best_key := -INF
	for p in loose_packs:
		if not is_instance_valid(p) or p.opened or not p.ready_to_open:
			continue
		var bp: Vector2 = p.board_pos
		if bpt.x >= bp.x and bpt.x <= bp.x + PACK_W and bpt.y >= bp.y and bpt.y <= bp.y + PACK_H:
			if bp.y > best_key:
				best_key = bp.y
				best = p
	return best

func _open_loose_pack(p) -> void:
	# 点一下弹出一张；点完最后一张后卡包消失
	if not is_instance_valid(p) or p.opened or not p.ready_to_open:
		return
	if p.contents.is_empty():
		_dissolve_pack(p)
		return
	_sfx("unpack")                     # 拆包点击音效
	var id := String(p.contents.pop_front())
	while _skip_pack_card(id):
		if p.contents.is_empty():
			p.opened = true
			_dissolve_pack(p)
			return
		id = String(p.contents.pop_front())
	var origin: Vector2 = p.position + Vector2(PackCardScript.W, PackCardScript.H) * 0.5 * p.scale.x
	var zone := _zone_for_center(_unproject(origin))
	_burst_card_from_pack(id, origin, zone)
	p.queue_redraw()                       # 刷新剩余数量角标
	if p.contents.is_empty():
		p.opened = true                    # 锁住后续点击
		_dissolve_pack(p)
	else:
		var tw := create_tween()           # 弹一下反馈
		tw.tween_property(p, "scale", Vector2(1.14, 0.86) * PACK_SCALE * view_zoom, 0.08).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(p, "scale", Vector2.ONE * PACK_SCALE * view_zoom, 0.14).set_trans(Tween.TRANS_BACK)

func _dissolve_pack(p) -> void:
	if not is_instance_valid(p):
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "scale", Vector2(1.1, 0.55) * PACK_SCALE * view_zoom, 0.14).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(p, "modulate:a", 0.0, 0.30).set_delay(0.06)
	tw.chain().tween_callback(func():
		loose_packs.erase(p)
		if is_instance_valid(p):
			p.queue_free()
	)

func _skip_pack_card(id: String) -> bool:
	if id == "founder" and _founder_on_board() != null:
		return true
	if _is_business_model_card(id):
		var rid := DataLoader.business_model_recipe_id(id)
		return rid != "" and GameState.business_model_done(rid)
	return false

func _burst_card_from_pack(id: String, origin_display: Vector2, zone: String) -> void:
	if id == "founder" and _founder_on_board() != null:
		return
	if _is_business_model_card(id):
		GameState.unlock_business_model(DataLoader.business_model_recipe_id(id))
		_refresh_recipe_book()
	var origin_center := _unproject(origin_display)
	var landing := _nearby_output_landing(origin_center, zone)
	var c := spawn_card(id, landing)
	if c == null:
		return
	c.zone = zone
	_fly_out_card(c, origin_display)
	var sid: int = c.stack_id
	get_tree().create_timer(FLY_OUT_TIME).timeout.connect(func():
		# 创始人/员工/客户从卡包飞出落地时播放放下音效
		if is_instance_valid(c):
			if c.card_id == "founder":
				_sfx("founder")
			elif is_person(c) or c.ctype == "customer":
				_sfx("down")
		if stacks.has(sid):
			evaluate_stack(sid)
	)

func _weighted_pick(options: Array) -> String:
	var total := 0
	for o in options:
		total += int(o.get("w", 1))
	var r := GameState.rng.randi_range(1, max(1, total))
	for o in options:
		r -= int(o.get("w", 1))
		if r <= 0:
			return String(o.get("id", "lead"))
	return String(options[0].get("id", "lead"))

func _pick_pack_card(_pack_id: String, options: Array, picked: Array) -> String:
	var filtered := []
	for o in options:
		var id := String(o.get("id", ""))
		if _is_facility_card(id) and _facility_already_present(id, picked):
			continue
		if _is_business_model_card(id) and _business_model_already_present(id, picked):
			continue
		filtered.append(o)
	return _weighted_pick(filtered if not filtered.is_empty() else options)

func _pick_business_model_card(stage: int, picked: Array) -> String:
	var candidates := []
	for recipe in DataLoader.recipes:
		if _business_model_stage(recipe) != stage:
			continue
		var cid := DataLoader.business_model_card_id(String(recipe.get("id", "")))
		if not _business_model_already_present(cid, picked):
			candidates.append(cid)
	if candidates.is_empty():
		return ""
	return String(candidates[GameState.rng.randi_range(0, candidates.size() - 1)])

func _facility_already_present(id: String, picked: Array) -> bool:
	for c in all_cards:
		if is_instance_valid(c) and String(c.card_id) == id:
			return true
	for idv in picked:
		if String(idv) == id:
			return true
	for p in loose_packs:
		if is_instance_valid(p) and p.contents.has(id):
			return true
	return false

func _is_facility_card(id: String) -> bool:
	return String(DataLoader.cards.get(id, {}).get("type", "")) == "facility"

func _is_business_model_card(id: String) -> bool:
	return String(DataLoader.cards.get(id, {}).get("type", "")) == "business_model"

func _business_model_already_present(id: String, picked: Array) -> bool:
	var rid := DataLoader.business_model_recipe_id(id)
	if rid != "" and GameState.business_model_done(rid):
		return true
	for c in all_cards:
		if is_instance_valid(c) and String(c.card_id) == id:
			return true
	for idv in picked:
		if String(idv) == id:
			return true
	for p in loose_packs:
		if is_instance_valid(p) and p.contents.has(id):
			return true
	return false

# ---------------------------------------------------------------- valuation / stage
func _recompute_valuation() -> void:
	_sync_cash_state()
	var headcount := 0
	var expense := 0
	var patents := 0
	for c in all_cards:
		expense += int(c.cdef.get("salary", 0))
		if c.ctype == "employee":
			headcount += 1
		if c.card_id == "patent":
			patents += 1
	for d in departments:
		headcount += int(d["headcount"])
	GameState.monthly_expense = expense
	# 虚拟估值公式：现金 + 累计营收×3 + 人数×10 + 部门×25 + 专利×40（无形资产壁垒）
	var val := GameState.cash + GameState.total_revenue * 3 + headcount * 10 + departments.size() * 25 + patents * 40
	# 研发"估值"类节点每个 +10% 估值（解锁优化估值体系）
	var mult := 1.0
	for idea in GameState.unlocked_ideas.keys():
		var rd: Dictionary = DataLoader.research.get(idea, {})
		if String(rd.get("kind", "")) == "valuation":
			mult += 0.10
	GameState.set_valuation(int(val * mult))

func _refresh_packs() -> void:
	for row in pack_buttons:
		var pack: Dictionary = row["pack"]
		var stg := int(pack.get("stage", 0))
		var btn: Button = row["btn"]
		var locked := GameState.stage < stg
		var unavailable := (pack.get("slots", []) as Array).is_empty()
		btn.disabled = locked or unavailable
		var label := String(pack.get("name", ""))
		if unavailable:
			label += "（开发中）"
		_style_pack_button(btn, label, int(pack.get("price", 0)), locked or unavailable)

func _on_stage_changed(_stage: int) -> void:
	_refresh_packs()
	_refresh_research()

# ---------------------------------------------------------------- juice
func _ka_ching(board_pos: Vector2, amount: int) -> void:
	var dp := _project(board_pos + Vector2(CW * 0.5, 20))
	var p := CPUParticles2D.new()
	add_child(p)
	p.position = dp
	p.z_index = 2000
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 16
	p.lifetime = 0.8
	p.direction = Vector2(0, -1)
	p.spread = 60
	p.initial_velocity_min = 80
	p.initial_velocity_max = 160
	p.gravity = Vector2(0, 240)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = Color("ffe66d")
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
	_float_text("+$" + str(amount), board_pos + Vector2(13.33, -6.67), Color("ffe66d"))

func _float_text(txt: String, board_pos: Vector2, col: Color) -> void:
	var pos := _project(board_pos)
	_float_text_screen(txt, pos, col)

func _float_text_screen(txt: String, pos: Vector2, col: Color) -> void:
	var l := Label.new()
	l.text = txt
	l.position = pos
	l.z_index = 2001
	_apply_pixel_font(l, 6)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 2)
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position", pos + Vector2(0, -15.33), 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9)
	tw.chain().tween_callback(l.queue_free)

func _float_cost(amount: int, board_pos: Vector2) -> void:
	const CARD_BADGE_SIZE := 12.0
	const CARD_BADGE_FONT_SIZE := 6
	var tl := _project(board_pos)
	var tr := _project(board_pos + Vector2(CW, 0))
	var bl := _project(board_pos + Vector2(0, CH))
	var x_axis := (tr - tl) / CW
	var y_axis := (bl - tl) / CH
	var group = FloatingCostScript.new()
	group.setup(amount, _ui_icon("cost_float"), _ui_font(), CARD_BADGE_SIZE * 1.3, int(round(CARD_BADGE_FONT_SIZE * 1.3)))
	group.transform = Transform2D(x_axis * CARD_SCALE, y_axis * CARD_SCALE, tl)
	group.z_index = 2002
	add_child(group)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(group, "position", group.position + Vector2(0, -11.33 * view_zoom), 0.95)
	tw.tween_property(group, "modulate:a", 0.0, 0.95)
	tw.chain().tween_callback(group.queue_free)

func _on_discovery(recipe_id: String) -> void:
	# 首次发现配方不再奖励现金（现金只由「产品+客户」成交产生）
	_show_toast("🎉 新发现：" + _recipe_name(recipe_id))
	_refresh_recipe_book()

func _recipe_name(id: String) -> String:
	for r in DataLoader.recipes:
		if String(r.get("id", "")) == id:
			return String(r.get("name", id))
	return id

# ---------------------------------------------------------------- pixel UI font
func _ui_font() -> Font:
	if pixel_font != null:
		return pixel_font
	var candidates := [
		"res://fonts/SmileySans-Oblique.ttf",
		"res://fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/Users/frankfan/Library/Fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/System/Library/Fonts/STHeiti Medium.ttc",
		"/System/Library/Fonts/PingFang.ttc",
		"/System/Library/Fonts/SFNSMono.ttf",
		"/System/Library/Fonts/Supplemental/PTMono.ttc"
	]
	for path in candidates:
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

func _ui_regular_font() -> Font:
	if pixel_regular_font != null:
		return pixel_regular_font
	var candidates := [
		"res://fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/Users/frankfan/Library/Fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/System/Library/Fonts/STHeiti Medium.ttc",
		"/System/Library/Fonts/PingFang.ttc",
		"/System/Library/Fonts/SFNSMono.ttf",
		"/System/Library/Fonts/Supplemental/PTMono.ttc"
	]
	for path in candidates:
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
		pixel_regular_font = ff
		return pixel_regular_font
	pixel_regular_font = ThemeDB.fallback_font
	return pixel_regular_font

func _apply_pixel_font(c: Control, size: int) -> void:
	c.add_theme_font_override("font", _ui_font())
	c.add_theme_font_size_override("font_size", size)

func _apply_bold_pixel_font(c: Control, size: int) -> void:
	_apply_pixel_font(c, size)
	c.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.55))
	c.add_theme_constant_override("outline_size", 1)

func _battle_font() -> Font:
	if battle_bold_font != null:
		return battle_bold_font
	var variation := FontVariation.new()
	variation.base_font = _ui_font()
	variation.variation_embolden = 0.75
	battle_bold_font = variation
	return battle_bold_font

func _apply_battle_font(c: Control, size: int) -> void:
	c.add_theme_font_override("font", _battle_font())
	c.add_theme_font_size_override("font_size", size)
	c.add_theme_constant_override("outline_size", 0)

func _ui_icon(name: String) -> Texture2D:
	if ui_icon_cache.has(name):
		return ui_icon_cache[name]
	var path := "res://assets/ui/%s.svg" % name
	if name.begins_with("streamline/"):
		path = "res://assets/ui/%s.svg" % name
	var tex := ResourceLoader.load(path) as Texture2D
	ui_icon_cache[name] = tex
	return tex

func _set_button_icon(b: Button, icon_name: String) -> void:
	var tex := _ui_icon(icon_name)
	if tex == null:
		return
	b.icon = null
	var tr := b.get_node_or_null("ButtonIcon") as TextureRect
	if tr == null:
		tr = TextureRect.new()
		tr.name = "ButtonIcon"
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tr)
	tr.texture = tex
	var icon_size := TOP_ICON_SIZE
	tr.size = Vector2(icon_size, icon_size)
	tr.position = Vector2((b.size.x - icon_size) * 0.5, (b.size.y - icon_size) * 0.5) if b.text == "" else Vector2(14, (b.size.y - icon_size) * 0.5)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

# ---------------------------------------------------------------- HUD
func _style_button(b: Button, fill: Color) -> void:
	# 2.5D 像素风：粗墨线、硬边阴影；HUD 保持正交，不做透视/斜切
	b.add_theme_font_override("font", _ui_font())
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.7))
	b.add_theme_constant_override("outline_size", 1)
	b.add_theme_constant_override("h_separation", 8)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		var c := fill
		if state == "hover":
			c = fill.lightened(0.10)
		elif state == "pressed":
			c = fill.darkened(0.08)
		elif state == "disabled":
			c = fill.lerp(Color("d9d2c4"), 0.6)
		sb.bg_color = c
		sb.set_corner_radius_all(0)
		sb.skew = Vector2.ZERO
		sb.border_color = INK
		sb.set_border_width_all(4)
		sb.shadow_color = Color(0, 0, 0, 0.28)
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(4, 5)
		sb.content_margin_left = 11
		sb.content_margin_right = 11
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		sb.corner_detail = 1
		b.add_theme_stylebox_override(state, sb)

	var gloss := b.get_node_or_null("ButtonGloss") as ColorRect
	if gloss == null:
		gloss = ColorRect.new()
		gloss.name = "ButtonGloss"
		gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gloss.z_index = -1
		b.add_child(gloss)
	gloss.position = Vector2(8, 7)
	gloss.size = Vector2(maxf(0, b.size.x - 16), maxf(0, b.size.y * 0.28))
	gloss.color = Color(1, 1, 1, 0.16)

func _ensure_top_icon(name: String, icon_name: String, pos: Vector2, icon_size: float = 18.0) -> TextureRect:
	var tr := hud.get_node_or_null(name) as TextureRect
	if tr == null:
		tr = TextureRect.new()
		tr.name = name
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(tr)
	tr.texture = _ui_icon(icon_name)
	tr.position = pos
	tr.size = Vector2(icon_size, icon_size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr

func _clear_button_style(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(0)
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		b.add_theme_stylebox_override(state, sb)

func _style_menu_text_button(b: Button, font_size: int) -> void:
	_apply_pixel_font(b, font_size)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color("5b8295"))
	b.add_theme_color_override("font_focus_color", Color("5b8295"))
	b.add_theme_color_override("font_pressed_color", Color("3f6f85"))
	b.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0))
	b.add_theme_constant_override("outline_size", 0)

	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 8
	empty.content_margin_right = 8
	empty.content_margin_top = 4
	empty.content_margin_bottom = 4
	for state in ["normal", "hover", "focus", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, empty)

	b.resized.connect(_update_menu_text_button_pivot.bind(b))
	b.mouse_entered.connect(_set_menu_text_button_emphasis.bind(b, true))
	b.mouse_exited.connect(_set_menu_text_button_emphasis.bind(b, false))
	b.focus_entered.connect(_set_menu_text_button_emphasis.bind(b, true))
	b.focus_exited.connect(_set_menu_text_button_emphasis.bind(b, false))
	_update_menu_text_button_pivot(b)

func _update_menu_text_button_pivot(b: Button) -> void:
	b.pivot_offset = b.size * 0.5

func _set_menu_text_button_emphasis(b: Button, emphasized: bool) -> void:
	var target := Vector2.ONE * (1.025 if emphasized else 1.0)
	var old: Tween = b.get_meta("menu_scale_tween") as Tween if b.has_meta("menu_scale_tween") else null
	if old != null and old.is_valid():
		old.kill()
	if Settings.reduce_motion:
		b.scale = target
		return
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	b.set_meta("menu_scale_tween", tw)
	tw.tween_property(b, "scale", target, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _pack_button_poly(size: Vector2, cut: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cut, 0), Vector2(size.x - cut, 0), Vector2(size.x, cut),
		Vector2(size.x, size.y - cut), Vector2(size.x - cut, size.y),
		Vector2(cut, size.y), Vector2(0, size.y - cut), Vector2(0, cut)])

func _toolbar_y() -> float:
	return HUD_H + (DRAW_Y1 - HUD_H - TOOLBAR_BUTTON_H) * 0.5

func _top_icon_y() -> float:
	return (HUD_H - TOP_ICON_SIZE) * 0.5

func _top_label_y() -> float:
	return (HUD_H - 40.0) * 0.5

func _ensure_top_bar() -> Control:
	top_bar = hud.get_node_or_null("TopBar") as Control
	if top_bar == null:
		top_bar = Control.new()
		top_bar.name = "TopBar"
		top_bar.position = Vector2.ZERO
		hud.add_child(top_bar)
	top_bar.size = Vector2(_screen_size().x, HUD_H)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := top_bar.get_node_or_null("TopBarBg") as ColorRect
	if bg != null:
		bg.size = Vector2(_screen_size().x, HUD_H)
	var line := top_bar.get_node_or_null("TopBarLine") as ColorRect
	if line != null:
		line.position = Vector2(0, HUD_H - 2.0)
		line.size = Vector2(_screen_size().x, 2.0)

	return top_bar

func _clear_legacy_top_nodes() -> void:
	for n in [
		"StatusIcon", "RPIcon", "BusinessIcon", "FinanceIcon", "ExpenseIcon", "ValuationIcon",
		"StatusLabel", "RPLabel", "BusinessLabel", "FinanceLabel", "ExpenseLabel", "ValuationLabel",
		"MonthProgressFill"]:
		var node := hud.get_node_or_null(n)
		if node != null:
			node.queue_free()

func _top_stat_label(
	group_name: String,
	icon_name: String,
	x: float,
	w: float,
	icon_size: float = TOP_ICON_SIZE,
	right_align: bool = false
) -> Label:
	var group := top_bar.get_node_or_null(group_name) as Control
	if group == null:
		group = Control.new()
		group.name = group_name
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_bar.add_child(group)
	group.position = Vector2(x, 0)
	group.size = Vector2(w, HUD_H)

	var icon := group.get_node_or_null("Icon") as TextureRect
	if icon_name == "":
		if icon != null:
			icon.queue_free()
	else:
		if icon == null:
			icon = TextureRect.new()
			icon.name = "Icon"
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			group.add_child(icon)
		icon.size = Vector2(icon_size, icon_size)
		icon.position = Vector2(0, (HUD_H - icon_size) * 0.5)
		icon.texture = _ui_icon(icon_name)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var label := group.get_node_or_null("Label") as Label
	if label == null:
		label = Label.new()
		label.name = "Label"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(label)
	var text_left := 0.0 if icon_name == "" else icon_size + 12.0
	label.position = Vector2(text_left, _top_label_y())
	label.size = Vector2(w - text_left, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right_align else HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_bold_pixel_font(label, TOP_LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", INK)
	return label

func _style_pack_button(pb: Button, pack_name: String, price: int, locked: bool) -> void:
	pb.text = ""
	pb.icon = null
	pb.clip_text = true
	pb.mouse_filter = Control.MOUSE_FILTER_STOP
	_clear_button_style(pb)
	var size := pb.size
	var cut := 8.0
	var poly := _pack_button_poly(size, cut)

	var shadow := pb.get_node_or_null("GlassShadow") as Polygon2D
	if shadow == null:
		shadow = Polygon2D.new()
		shadow.name = "GlassShadow"
		shadow.z_index = -3
		pb.add_child(shadow)
	shadow.position = Vector2(5, 6)
	shadow.polygon = poly
	shadow.color = Color(0, 0, 0, 0.32)

	var fill := pb.get_node_or_null("GlassFill") as Polygon2D
	if fill == null:
		fill = Polygon2D.new()
		fill.name = "GlassFill"
		fill.z_index = -2
		pb.add_child(fill)
	fill.polygon = poly
	fill.color = Color("34383b") if not locked else Color("464849")

	var gloss := pb.get_node_or_null("GlassGloss") as Polygon2D
	if gloss == null:
		gloss = Polygon2D.new()
		gloss.name = "GlassGloss"
		gloss.z_index = -1
		pb.add_child(gloss)
	gloss.polygon = PackedVector2Array([
		Vector2(cut + 4, 5), Vector2(size.x - cut - 4, 5), Vector2(size.x - cut - 10, 20),
		Vector2(cut + 10, 20)])
	gloss.color = Color(1, 1, 1, 0.18 if not locked else 0.08)

	var border := pb.get_node_or_null("GlassBorder") as Line2D
	if border == null:
		border = Line2D.new()
		border.name = "GlassBorder"
		border.z_index = 0
		border.closed = true
		border.joint_mode = Line2D.LINE_JOINT_SHARP
		pb.add_child(border)
	border.points = poly
	border.default_color = INK
	border.width = 4.0

	var hi := pb.get_node_or_null("GlassTopEdge") as Line2D
	if hi == null:
		hi = Line2D.new()
		hi.name = "GlassTopEdge"
		hi.z_index = 1
		pb.add_child(hi)
	hi.points = PackedVector2Array([Vector2(cut + 4, 5), Vector2(size.x - cut - 4, 5)])
	hi.default_color = Color(1, 1, 1, 0.35 if not locked else 0.14)
	hi.width = 2.0

	var icon := pb.get_node_or_null("PackIcon") as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = "PackIcon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.add_child(icon)
	var content_h := 58.0
	var offset_y := (size.y - content_h) * 0.5
	var icon_w := 30.6
	icon.visible = not locked
	icon.texture = _ui_icon("cost")
	icon.position = Vector2((size.x - icon_w) * 0.5, offset_y)
	icon.size = Vector2(icon_w, icon_w)
	icon.modulate = Color(1, 1, 1, 0.55 if locked else 1.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment() { vec4 c = COLOR; COLOR = vec4(1.0 - c.rgb, c.a); }"
	mat.shader = shader
	icon.material = mat

	var cost := pb.get_node_or_null("PackCost") as Label
	if cost == null:
		cost = Label.new()
		cost.name = "PackCost"
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.add_child(cost)
	cost.visible = not locked
	cost.text = str(price)
	cost.position = Vector2((size.x - icon_w) * 0.5, offset_y + 6.3)
	cost.size = Vector2(icon_w, 18)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_bold_pixel_font(cost, 15)
	cost.add_theme_color_override("font_color", Color("141414") if not locked else Color("5f5c58"))

	var label := pb.get_node_or_null("PackLabel") as Label
	if label == null:
		label = Label.new()
		label.name = "PackLabel"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.add_child(label)
	label.visible = not locked
	label.text = pack_name
	label.position = Vector2(7, offset_y + 40.0)
	label.size = Vector2(size.x - 14, 18)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_bold_pixel_font(label, 13)
	label.add_theme_color_override("font_color", Color("f7f2e8") if not locked else Color("9b978f"))

	# Locked pack: hide icon/cost/name, show a centered "？？" instead.
	var qmark := pb.get_node_or_null("PackLocked") as Label
	if qmark == null:
		qmark = Label.new()
		qmark.name = "PackLocked"
		qmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.add_child(qmark)
	qmark.visible = locked
	qmark.text = "？？"
	qmark.position = Vector2(0, 0)
	qmark.size = size
	qmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qmark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_bold_pixel_font(qmark, 24)
	qmark.add_theme_color_override("font_color", Color("9b978f"))

func _build_hud() -> void:
	hud = get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		hud = CanvasLayer.new()
		hud.name = "HUD"
		add_child(hud)

	_ensure_top_bar()
	_clear_legacy_top_nodes()

	lbl_status = _top_stat_label("StageGroup", "streamline/icon_stage", 24, 320)
	lbl_top_rp = null

	var progress_group := top_bar.get_node_or_null("ProgressGroup") as Control
	if progress_group == null:
		progress_group = Control.new()
		progress_group.name = "ProgressGroup"
		progress_group.position = Vector2(356, 0)
		progress_group.size = Vector2(270, HUD_H)
		progress_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_bar.add_child(progress_group)
	else:
		progress_group.position = Vector2(356, 0)
		progress_group.size = Vector2(270, HUD_H)

	var month_progress_slot := progress_group.get_node_or_null("MonthProgressSlot") as Panel
	if month_progress_slot != null:
		month_progress_slot.position = Vector2(0, (HUD_H - TOP_LABEL_FONT_SIZE) * 0.5)
		month_progress_slot.size = Vector2(270, TOP_LABEL_FONT_SIZE)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("8d8d8d")
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		month_progress_slot.add_theme_stylebox_override("panel", sb)

	month_progress = progress_group.get_node_or_null("MonthProgressFill") as Panel
	if month_progress == null:
		month_progress = Panel.new()
		month_progress.name = "MonthProgressFill"
		month_progress.position = Vector2(0, (HUD_H - TOP_LABEL_FONT_SIZE) * 0.5)
		month_progress.size = Vector2(270, TOP_LABEL_FONT_SIZE)
		progress_group.add_child(month_progress)
	else:
		month_progress.position = Vector2(0, (HUD_H - TOP_LABEL_FONT_SIZE) * 0.5)
		month_progress.size = Vector2(270, TOP_LABEL_FONT_SIZE)

	var sb_fill := StyleBoxFlat.new()
	sb_fill.bg_color = Color("141414")
	sb_fill.corner_radius_top_left = 6
	sb_fill.corner_radius_top_right = 6
	sb_fill.corner_radius_bottom_left = 6
	sb_fill.corner_radius_bottom_right = 6
	month_progress.add_theme_stylebox_override("panel", sb_fill)

	month_progress_full_width = 270.0
	month_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE

	lbl_expense = _top_stat_label("ExpenseGroup", "", 1220, 220, TOP_ICON_SIZE, true)
	lbl_expense.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl_expense.mouse_entered.connect(_on_expense_hover)
	lbl_expense.mouse_exited.connect(_hide_hover)
	lbl_business = _top_stat_label("BusinessGroup", "", 1450, 180, TOP_ICON_SIZE, true)
	lbl_finance = _top_stat_label("FinanceGroup", "", 1640, 180, TOP_ICON_SIZE, true)
	lbl_val = null

	var gear_btn := top_bar.get_node_or_null("GearButton") as Button
	if gear_btn == null:
		gear_btn = Button.new()
		gear_btn.name = "GearButton"
		gear_btn.text = ""
		top_bar.add_child(gear_btn)
	gear_btn.position = Vector2(1844, (HUD_H - 44.0) * 0.5)
	gear_btn.size = Vector2(64, 44)
	_apply_pixel_font(gear_btn, 26)
	_style_button(gear_btn, Color("f3ead7"))
	_set_button_icon(gear_btn, "streamline/icon_settings")
	gear_btn.pressed.connect(_toggle_gear_menu)

	var rbtn := hud.get_node_or_null("Buttons/ResearchButton") as Button
	if rbtn == null:
		rbtn = Button.new()
		rbtn.name = "ResearchButton"
		hud.add_child(rbtn)
	rbtn.position = Vector2(28, _toolbar_y())
	rbtn.size = Vector2(154.0, TOOLBAR_BUTTON_H)
	rbtn.text = "研发"
	_apply_bold_pixel_font(rbtn, 22)
	_style_button(rbtn, Color("6f8793"))
	var rbtn_icon := rbtn.get_node_or_null("ButtonIcon")
	if rbtn_icon != null:
		rbtn_icon.queue_free()
	rbtn.pressed.connect(_toggle_research)

	book_btn = hud.get_node_or_null("Buttons/RecipeBookButton") as Button
	if book_btn == null:
		book_btn = Button.new()
		book_btn.name = "RecipeBookButton"
		book_btn.position = Vector2(30, INFO_Y - 88)
		book_btn.size = Vector2(130, 64)
		hud.add_child(book_btn)
	book_btn.text = "商业模式"
	_apply_pixel_font(book_btn, 26)
	# 按钮底色与弹窗一致，作为文件夹标签
	_style_button(book_btn, PANEL_CREAM)
	if not book_btn.pressed.is_connected(_toggle_recipe_book):
		book_btn.pressed.connect(_toggle_recipe_book)

	# 公司任务：同款样式，深蓝色；按钮大小不变，右边界对齐「商业模式」弹窗右边界
	var book_panel_right := 30.0 + 310.0   # recipe_panel: position.x 30 + size.x 310
	var task_w := 130.0
	var task_btn := hud.get_node_or_null("Buttons/CompanyTaskButton") as Button
	if task_btn == null:
		task_btn = Button.new()
		task_btn.name = "CompanyTaskButton"
		task_btn.size = Vector2(task_w, 64)
		hud.add_child(task_btn)
	task_btn.position = Vector2(book_panel_right - task_w, INFO_Y - 88)
	task_btn.text = "公司任务"
	_apply_pixel_font(task_btn, 26)
	_style_button(task_btn, Color("2c3e63"))
	# 深蓝底配浅色字，保证可读
	var task_fg := Color("f3ead7")
	task_btn.add_theme_color_override("font_color", task_fg)
	task_btn.add_theme_color_override("font_hover_color", task_fg)
	task_btn.add_theme_color_override("font_pressed_color", task_fg)
	task_btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	if not task_btn.pressed.is_connected(_toggle_company_tasks):
		task_btn.pressed.connect(_toggle_company_tasks)

	# 底部信息栏：放在 HUD 层（在所有卡牌之上），z 低于底部按钮但高于卡牌
	bottom_info = hud.get_node_or_null("BottomInfo") as Node2D
	if bottom_info == null:
		bottom_info = Node2D.new()
		bottom_info.name = "BottomInfo"
		hud.add_child(bottom_info)
	bottom_info.z_index = -1
	if not bottom_info.draw.is_connected(_draw_bottom_info):
		bottom_info.draw.connect(_draw_bottom_info)
	bottom_info.queue_redraw()

	bank_button = hud.get_node_or_null("BankButton") as Button
	if bank_button != null and bank_button.get_parent() == hud:
		hud.remove_child(bank_button)
		bank_button.z_index = 10
		bank_button.z_as_relative = false
		add_child(bank_button)
	elif bank_button == null:
		bank_button = get_node_or_null("BankButton") as Button
		if bank_button == null:
			bank_button = Button.new()
			bank_button.name = "BankButton"
			bank_button.z_index = 10
			bank_button.z_as_relative = false
			add_child(bank_button)
	bank_button.position = Vector2(1738, _toolbar_y())
	bank_button.size = Vector2(154, TOOLBAR_BUTTON_H)
	bank_button.text = "出售"
	_apply_bold_pixel_font(bank_button, 20)
	_style_button(bank_button, Color("c8a55a"))
	bank_button.icon = null
	bank_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not bank_button.draw.is_connected(_draw_bank_button_hint):
		bank_button.draw.connect(_draw_bank_button_hint)

	pack_buttons.clear()
	var pack_container := hud.get_node_or_null("PackButtons")
	var pack_count := DataLoader.packs.size()
	var pack_w := 120.0
	var pack_space_x0 := rbtn.position.x + rbtn.size.x + 26.0
	var pack_space_x1 := bank_button.position.x - 26.0
	var pack_gap := 126.0
	var px := pack_space_x0
	if pack_count > 1:
		var max_gap := (pack_space_x1 - pack_space_x0 - pack_w) / (pack_count - 1)
		var gap_between_borders := max_gap - pack_w
		var reduced_gap := gap_between_borders * 0.6
		pack_gap = pack_w + reduced_gap
		var pack_total_w := pack_w + (pack_count - 1) * pack_gap
		px = pack_space_x0 + (pack_space_x1 - pack_space_x0 - pack_total_w) * 0.5
	var pack_i := 0
	for pid in DataLoader.packs.keys():
		var pack: Dictionary = DataLoader.packs[pid]
		var pb: Button = null
		if pack_container != null and pack_i < pack_container.get_child_count():
			pb = pack_container.get_child(pack_i) as Button
		if pb == null:
			pb = Button.new()
			pb.name = "PackButton%d" % (pack_i + 1)
			if pack_container != null:
				pack_container.add_child(pb)
			else:
				hud.add_child(pb)
		pb.position = Vector2(px, _toolbar_y())
		pb.size = Vector2(pack_w, TOOLBAR_BUTTON_H)
		pb.autowrap_mode = TextServer.AUTOWRAP_OFF
		_style_pack_button(pb, String(pack.get("name", "")), int(pack.get("price", 0)), false)
		pb.pressed.connect(buy_pack.bind(String(pid)))
		pb.mouse_entered.connect(_on_pack_hover.bind(String(pid)))   # hover 显示可抽到的牌
		pb.mouse_exited.connect(_hide_hover)
		pack_buttons.append({ "btn": pb, "id": String(pid), "pack": pack })
		px += pack_gap
		pack_i += 1

	_refresh_packs()
	_build_research_panel()
	_build_recipe_book_panel()
	_build_codex_panel()
	_build_settings_panel()
	_build_gear_menu()
	_build_hover_panel()
	_build_zoom_buttons()

func _layout_responsive() -> void:
	var screen := _screen_size()
	var extra := screen - Vector2(BASE_W, BASE_H)
	if city_bg != null:
		city_bg.size = Vector2i(maxi(1, roundi(screen.x)), maxi(1, roundi(screen.y)))

	if top_bar != null:
		top_bar.size.x = screen.x
		var bg := top_bar.get_node_or_null("TopBarBg") as Control
		var line := top_bar.get_node_or_null("TopBarLine") as Control
		if bg != null:
			bg.size.x = screen.x
		if line != null:
			line.size.x = screen.x
		var gear_btn := top_bar.get_node_or_null("GearButton") as Control
		if gear_btn != null:
			gear_btn.position.x = screen.x - 76.0
	_layout_top_right_stats()

	var bottom := _bottom_y()
	if book_btn != null:
		book_btn.position.y = bottom - 88.0
	var task_btn := hud.find_child("CompanyTaskButton", true, false) as Control if hud != null else null
	if task_btn != null:
		task_btn.position.y = bottom - 88.0
	if recipe_panel != null:
		var panel_h := recipe_panel.size.y
		recipe_panel.position.y = (bottom - 88.0) - 22.0 - panel_h

	if bank_button != null:
		bank_button.position.x = screen.x - 182.0
	_layout_pack_buttons()

	var zoom_x := screen.x - 70.8
	var zoom_bottom := bottom - 68.8
	for data in [
		["ZoomOut", 0.0],
		["ZoomIn", -72.8],
		["ViewBack", -145.6],
		["ViewFront", -218.4],
	]:
		var button := hud.get_node_or_null(String(data[0])) as Control if hud != null else null
		if button != null:
			button.position = Vector2(zoom_x, zoom_bottom + float(data[1]))

	if gear_menu != null:
		gear_menu.size = screen
		var dim := gear_menu.get_child(0) as Control if gear_menu.get_child_count() > 0 else null
		var panel := gear_menu.get_child(1) as Control if gear_menu.get_child_count() > 1 else null
		if dim != null:
			dim.size = screen
		if panel != null:
			panel.position = Vector2((screen.x - panel.size.x) * 0.5, 300.0 + extra.y * 0.5)
	if codex_panel != null:
		codex_panel.position = Vector2((screen.x - 1320.0) * 0.5 - 110.0, 120.0 + extra.y * 0.5)
	if settings_panel != null:
		settings_panel.position = Vector2((screen.x - 460.0) * 0.5, 320.0 + extra.y * 0.5)
	if research_panel != null:
		research_panel.size = screen
	if bottom_info != null:
		bottom_info.queue_redraw()
	if book_tab_shadow != null:
		book_tab_shadow.queue_redraw()
	if book_tab_seam != null:
		book_tab_seam.queue_redraw()
	_recompute_view_zoom()
	_relayout_all()
	_relayout_loose_packs()

func _layout_pack_buttons() -> void:
	if pack_buttons.is_empty() or bank_button == null:
		return
	var count := pack_buttons.size()
	var pack_w := 120.0
	var old_first_x := 208.0
	var old_last_x := bank_button.position.x - 26.0 - pack_w
	var old_step := 0.0 if count <= 1 else (old_last_x - old_first_x) / float(count - 1)
	var old_border_gap := maxf(0.0, old_step - pack_w)
	var new_step := pack_w + old_border_gap * 0.9
	var group_width := pack_w + float(maxi(0, count - 1)) * new_step
	var first_x := (_screen_size().x - group_width) * 0.5
	for i in pack_buttons.size():
		var button := pack_buttons[i].get("btn") as Button
		if button != null:
			button.position = Vector2(
				first_x + new_step * i,
				_toolbar_y()
			)

# ---------------------------------------------------------------- zoom buttons
func _build_zoom_buttons() -> void:
	# 屏幕右下角：柔软白色立体 + / - 键（+ 在上放大、- 在下缩小）
	var bs := 52.8                          # 比原 66 缩小 20%
	var gap := 20.0                         # 间距拉大一倍（原 10）
	var right_x := BASE_W - 18.0 - bs
	var minus_y := INFO_Y - 16.0 - bs
	var plus_y := minus_y - gap - bs
	var plus_btn := hud.get_node_or_null("ZoomIn") as Button
	if plus_btn == null:
		plus_btn = Button.new()
		plus_btn.name = "ZoomIn"
		hud.add_child(plus_btn)
		plus_btn.pressed.connect(_zoom_view_center.bind(VIEW_ZOOM_STEP * VIEW_ZOOM_STEP))
	plus_btn.position = Vector2(right_x, plus_y)
	plus_btn.size = Vector2(bs, bs)
	_style_zoom_button(plus_btn, "res://assets/ui/zoom_in.svg")

	var minus_btn := hud.get_node_or_null("ZoomOut") as Button
	if minus_btn == null:
		minus_btn = Button.new()
		minus_btn.name = "ZoomOut"
		hud.add_child(minus_btn)
		minus_btn.pressed.connect(_zoom_view_center.bind(1.0 / (VIEW_ZOOM_STEP * VIEW_ZOOM_STEP)))
	minus_btn.position = Vector2(right_x, minus_y)
	minus_btn.size = Vector2(bs, bs)
	_style_zoom_button(minus_btn, "res://assets/ui/zoom_out.svg")

	# 两个视角键（在 + 之上，同样大小与间距）：向前下=更前倾、向后下=更俯视
	var back_y := plus_y - gap - bs              # 紧挨 + 之上
	var front_y := back_y - gap - bs             # 最上
	var front_btn := hud.get_node_or_null("ViewFront") as Button
	if front_btn == null:
		front_btn = Button.new()
		front_btn.name = "ViewFront"
		hud.add_child(front_btn)
		front_btn.pressed.connect(_tilt_view.bind(-CAM_PITCH_STEP))
	front_btn.position = Vector2(right_x, front_y)
	front_btn.size = Vector2(bs, bs)
	_style_zoom_button(front_btn, "res://assets/ui/view_front.svg")

	var back_btn := hud.get_node_or_null("ViewBack") as Button
	if back_btn == null:
		back_btn = Button.new()
		back_btn.name = "ViewBack"
		hud.add_child(back_btn)
		back_btn.pressed.connect(_tilt_view.bind(CAM_PITCH_STEP))
	back_btn.position = Vector2(right_x, back_y)
	back_btn.size = Vector2(bs, bs)
	_style_zoom_button(back_btn, "res://assets/ui/view_back.svg")

func _zoom_view_center(factor: float) -> void:
	# 以播放区中心为锚点缩放视角
	_zoom_view_at(Vector2(_screen_size().x * 0.5, (HUD_H + _bottom_y()) * 0.5), factor)

func _style_zoom_button(b: Button, icon_path: String = "") -> void:
	# 柔软白色立体：圆角、柔和投影、淡边；图标为灰黑色 svg
	b.text = ""
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		var c := Color("fbf9f4")
		if state == "hover":
			c = Color("ffffff")
		elif state == "pressed":
			c = Color("eee9e0")
		sb.bg_color = c
		sb.set_corner_radius_all(20)
		sb.corner_detail = 8
		sb.border_color = Color(1, 1, 1, 0.9)
		sb.set_border_width_all(2)
		sb.shadow_color = Color(0, 0, 0, 0.28)
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(4, 5)
		b.add_theme_stylebox_override(state, sb)

	# 顶部柔光高光，增强立体感
	var gloss := b.get_node_or_null("ZoomGloss") as ColorRect
	if gloss == null:
		gloss = ColorRect.new()
		gloss.name = "ZoomGloss"
		gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(gloss)
	gloss.position = Vector2(16, 6)
	gloss.size = Vector2(maxf(0, b.size.x - 32), maxf(0, b.size.y * 0.34))
	gloss.color = Color(1, 1, 1, 0.5)

	# 居中的灰黑 svg 图标
	if icon_path != "":
		var icon := b.get_node_or_null("ZoomIcon") as TextureRect
		if icon == null:
			icon = TextureRect.new()
			icon.name = "ZoomIcon"
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(icon)
		icon.texture = _zoom_icon_texture(icon_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var pad := b.size.x * 0.212   # 图标比原来放大 20%
		icon.position = Vector2(pad, pad)
		icon.size = Vector2(b.size.x - pad * 2.0, b.size.y - pad * 2.0)

func _zoom_icon_texture(path: String) -> Texture2D:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		# web 导出剥离了源文件 → 用导入的纹理
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
		return null
	var txt := f.get_as_text()
	var img := Image.new()
	if img.load_svg_from_string(txt, 8.0) != OK:
		return null
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- hover tooltip
func _build_hover_panel() -> void:
	hover_panel = hud.get_node_or_null("HoverPanel") as Panel
	if hover_panel == null:
		hover_panel = Panel.new()
		hover_panel.name = "HoverPanel"
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("fbf6ec")
		sb.border_color = INK
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(6)
		hover_panel.add_theme_stylebox_override("panel", sb)
		hud.add_child(hover_panel)
	hover_panel.z_index = 4096
	hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_panel.visible = false
	hover_label = hover_panel.get_node_or_null("HoverLabel") as Label
	if hover_label == null:
		hover_label = Label.new()
		hover_label.name = "HoverLabel"
		hover_label.position = Vector2(12, 8)
		hover_panel.add_child(hover_label)
	_apply_pixel_font(hover_label, 18)
	hover_label.add_theme_color_override("font_color", INK)
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _show_hover(text: String, anchor: Control, centered: bool = false) -> void:
	if hover_panel == null:
		return
	hover_label.text = text
	var rows := text.split("\n").size()
	var w := 230.0
	var h := rows * 26.0 + 16.0
	hover_panel.size = Vector2(w, h)
	if centered:
		hover_label.position = Vector2(12, 8)
		hover_label.size = Vector2(w - 24, h - 16)
		hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hover_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		hover_label.position = Vector2(12, 8)
		hover_label.size = Vector2(w - 24, h - 16)
		hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hover_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var x := clampf(anchor.position.x, 8.0, BASE_W - w - 8.0)
	var y := anchor.position.y + anchor.size.y + 6.0
	if y + h > BASE_H:
		y = anchor.position.y - h - 6.0
	hover_panel.position = Vector2(x, y)
	hover_panel.visible = true

func _hide_hover() -> void:
	if hover_panel:
		hover_panel.visible = false

func _on_pack_hover(pid: String) -> void:
	var btn: Control = null
	for e in pack_buttons:
		if String(e.get("id", "")) == pid:
			btn = e.get("btn")
			break
	if btn != null:
		var pack: Dictionary = DataLoader.packs.get(pid, {})
		var locked := GameState.stage < int(pack.get("stage", 0))
		if locked:
			# Locked pack: hide its real contents, just show a left-aligned "？？".
			_show_hover("？？", btn)
		else:
			_show_hover(_pack_hover_text(pid), btn)

func _pack_hover_text(pid: String) -> String:
	var pack: Dictionary = DataLoader.packs.get(pid, {})
	var pack_name := String(pack.get("name", pid))
	var price := int(pack.get("price", 0))
	
	# Find all unique card IDs in this pack's slots
	var pack_card_ids: Array = []
	for slot in pack.get("slots", []):
		for opt in slot:
			var cid = String(opt.get("id", ""))
			if cid != "" and not pack_card_ids.has(cid):
				pack_card_ids.append(cid)
				
	# Compute drawn vs undrawn cards
	var undrawn_count := 0
	var drawn_names := []
	for cid in pack_card_ids:
		if GameState.drawn_cards.has(cid):
			var nm := DataLoader.card_name(cid)
			if not drawn_names.has(nm):
				drawn_names.append(nm)
		else:
			undrawn_count += 1
			
	var lines: Array = []
	lines.append("%s（$%d）包含：" % [pack_name, price])
	if undrawn_count > 0:
		lines.append("剩余 %d 张卡片未抽到" % undrawn_count)
	for nm in drawn_names:
		lines.append("- %s" % nm)
		
	return _join_text(lines, "\n")

func _current_expense() -> int:
	var p := 0
	for c in all_cards:
		p += int(c.cdef.get("salary", 0))
	return p

func _business_card_count() -> int:
	var n := 0
	for c in all_cards:
		if c.card_id == "cash" or c.card_id == "revenue":
			continue
		n += 1
	return n

func _business_card_capacity() -> int:
	var offices := 0
	for c in all_cards:
		if c.card_id == "office":
			offices += 1
	var cap := maxi(1, offices) * BUSINESS_CAPACITY_PER_OFFICE
	return maxi(cap, _business_card_count())

func _on_expense_hover() -> void:
	_show_hover(_expense_hover_text(), lbl_expense)

func _expense_hover_text() -> String:
	var by_name: Dictionary = {}
	for c in all_cards:
		var s := int(c.cdef.get("salary", 0))
		if s <= 0:
			continue
		var nm := String(c.cdef.get("name", c.card_id))
		if by_name.has(nm):
			by_name[nm][0] += 1
		else:
			by_name[nm] = [1, s]
	var lines: Array = ["月运营支出构成（薪资）："]
	var total := 0
	for nm in by_name:
		var cnt: int = by_name[nm][0]
		var each: int = by_name[nm][1]
		total += cnt * each
		lines.append("· %s ×%d  $%d" % [nm, cnt, cnt * each])
	lines.append("合计  $%d / 月" % total)
	return _join_text(lines, "\n")

func _show_toast(txt: String) -> void:
	# 所有解说/提示进入底部信息栏，斜体「」呈现（见 _draw）
	var t := txt
	if not t.begins_with("「"):
		t = "「" + t + "」"
	hint_text = t
	toast_t = 6.0   # 高亮 6s 后回落为常态信息色

# ---------------------------------------------------------------- recipe book
func _build_recipe_book_panel() -> void:
	# 阴影层：添加在最底层以绘制整体阴影
	book_tab_shadow = Node2D.new()
	book_tab_shadow.name = "BookTabShadow"
	book_tab_shadow.visible = false
	hud.add_child(book_tab_shadow)
	book_tab_shadow.draw.connect(_draw_book_tab_shadow)

	recipe_panel = PanelContainer.new()
	# 弹窗坐落在「商业模式」按钮上方、左对齐；底边内缩（recessed）到按钮顶边之上，
	# 由 book_tab_seam 用圆弧把内缩的底边自然下接到按钮（文件夹标签效果）。
	var panel_h := 700.0
	var y_recess := (INFO_Y - 88.0) - 22.0   # 弹窗底边：按钮顶边再往上缩 22px
	recipe_panel.position = Vector2(30, y_recess - panel_h)
	recipe_panel.size = Vector2(310, panel_h)
	recipe_panel.visible = false
	var psb := StyleBoxFlat.new()
	psb.bg_color = PANEL_CREAM
	# 顶部圆角，底部直角；底边线交给 seam 画（这里关掉），与按钮无缝拼接
	psb.corner_radius_top_left = 8
	psb.corner_radius_top_right = 8
	psb.corner_radius_bottom_left = 0
	psb.corner_radius_bottom_right = 0
	psb.border_color = INK
	psb.set_border_width_all(4)        # 与按钮边框同粗
	psb.border_width_bottom = 0        # 底边交给 seam 画
	# 弹窗自身的默认 shadow size 设为 0，因为其阴影由底层的 book_tab_shadow 统一绘制
	psb.shadow_color = Color(0, 0, 0, 0.28)
	psb.shadow_size = 0
	psb.shadow_offset = Vector2(4, 5)
	psb.content_margin_left = 18
	psb.content_margin_right = 18
	psb.content_margin_top = 16
	psb.content_margin_bottom = 16
	recipe_panel.add_theme_stylebox_override("panel", psb)
	hud.add_child(recipe_panel)

	# 缝盖：用按钮色抹掉「面板底边 + 按钮顶边」之间的墨线，使两者融合成文件夹标签
	book_tab_seam = Node2D.new()
	book_tab_seam.name = "BookTabSeam"
	book_tab_seam.visible = false
	hud.add_child(book_tab_seam)
	book_tab_seam.draw.connect(_draw_book_tab_seam)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "商业模式"
	_apply_pixel_font(title, 30)
	title.add_theme_color_override("font_color", INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "关闭"
	close.size = Vector2(90, 42)
	_apply_pixel_font(close, 18)
	_style_button(close, Color("e0c39a"))
	close.pressed.connect(_toggle_recipe_book)
	head.add_child(close)

	recipe_list = RichTextLabel.new()
	recipe_list.bbcode_enabled = true
	recipe_list.fit_content = false
	recipe_list.scroll_active = true
	recipe_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_list.add_theme_font_override("normal_font", _ui_font())
	recipe_list.add_theme_font_override("bold_font", _ui_font())
	recipe_list.add_theme_font_override("italics_font", _ui_font())
	recipe_list.add_theme_font_size_override("normal_font_size", 20)
	recipe_list.add_theme_font_size_override("bold_font_size", 20)
	recipe_list.add_theme_font_size_override("italics_font_size", 20)
	recipe_list.add_theme_color_override("default_color", INK)
	box.add_child(recipe_list)
	_refresh_recipe_book()

# 弹窗（文件夹）+ 按钮（标签）整体只画一条连续墨线：
# 弹窗内缩底边 → 圆弧下接 → 标签右/底/左边 → 接回弹窗左边框。线段一体化，无接缝。
func _draw_book_tab_shadow() -> void:
	if book_tab_shadow == null or recipe_panel == null or not recipe_panel.visible:
		return
	
	var pl := 30.0                   # 弹窗/标签矩形左边
	var pr := 340.0                  # 弹窗矩形右边
	var tr := 160.0                  # 标签（按钮）矩形右边
	var tab_top := _bottom_y() - 88.0     # 按钮顶边
	var tab_bot := _bottom_y() - 24.0     # 按钮底边（position.y + 高 64）
	var y_recess := tab_top - 22.0   # 弹窗内缩后的底边
	var pt := y_recess - recipe_panel.size.y
	var r := 16.0                    # 连接圆弧半径
	
	var poly := PackedVector2Array()
	# Top-left rounded corner (radius 8)
	poly.append(Vector2(pl + 8.0, pt))
	poly.append(Vector2(pl + 2.3, pt + 2.3))
	poly.append(Vector2(pl, pt + 8.0))
	
	# Left edge down to bottom of button
	poly.append(Vector2(pl, tab_bot))
	
	# Bottom of button
	poly.append(Vector2(tr, tab_bot))
	
	# Right of button up to recess
	poly.append(Vector2(tr, y_recess + r))
	
	# Arc from (tr, y_recess + r) to (tr + r, y_recess)
	var cx := tr + r
	var cy := y_recess + r
	var steps := 12
	for i in steps + 1:
		var ang := deg_to_rad(180.0 + 90.0 * float(i) / float(steps)) # 180° -> 270°
		poly.append(Vector2(cx + r * cos(ang), cy + r * sin(ang)))
		
	# Bottom of panel (recessed part)
	poly.append(Vector2(pr, y_recess))
	
	# Right edge of panel up to top-right corner
	poly.append(Vector2(pr, pt + 8.0))
	
	# Top-right rounded corner (radius 8)
	poly.append(Vector2(pr - 2.3, pt + 2.3))
	poly.append(Vector2(pr - 8.0, pt))
	
	# Draw the unified shadow offset by (4, 5)
	var shadow_offset := Vector2(4, 5)
	var shadow_poly := PackedVector2Array()
	for p in poly:
		shadow_poly.append(p + shadow_offset)
	
	book_tab_shadow.draw_colored_polygon(shadow_poly, Color(0, 0, 0, 0.28))

# 弹窗（文件夹）+ 按钮（标签）整体只画一条连续墨线：
# 弹窗内缩底边 → 圆弧下接 → 标签右/底/左边 → 接回弹窗左边框。线段一体化，无接缝。
func _draw_book_tab_seam() -> void:
	if book_tab_seam == null or recipe_panel == null or not recipe_panel.visible:
		return
	var w := 4.0                     # 与按钮/弹窗边框同粗
	var ins := w * 0.5               # 边框画在矩形内侧，线中心内移半个线宽
	var pl := 30.0                   # 弹窗/标签矩形左边
	var pr := 340.0                  # 弹窗矩形右边
	var tr := 160.0                  # 标签（按钮）矩形右边
	var pl_line := pl + ins          # 左框线中心（= 按钮左框线，对齐）
	var pr_line := pr - ins          # 右框线中心
	var tr_line := tr - ins          # 标签右框线中心
	var tab_top := _bottom_y() - 88.0     # 按钮顶边
	var tab_bot := _bottom_y() - 24.0     # 按钮底边（position.y + 高 64）
	var y_recess := tab_top - 22.0   # 弹窗内缩后的底边（与 _build_recipe_book_panel 一致）
	var r := 16.0                    # 连接圆弧半径
	var up := 8.0                    # 向上叠进弹窗左右边框，消除接缝缺口

	# 凹角连接圆弧：内缩底边 (tr_line+r, y_recess) → 标签右框线 (tr_line, y_recess+r)，两端相切
	var arc := PackedVector2Array()
	var cx := tr_line + r
	var cy := y_recess + r
	var steps := 12
	for i in steps + 1:
		var ang := deg_to_rad(270.0 - 90.0 * float(i) / float(steps))   # 270° → 180°
		arc.append(Vector2(cx + r * cos(ang), cy + r * sin(ang)))

	# 奶白填充：桥接区（弹窗底 ↔ 按钮顶），随圆弧收口，不溢进缺口、不盖按钮文字
	var fill := PackedVector2Array()
	fill.append(Vector2(pl, y_recess - up))
	fill.append(Vector2(tr_line + r, y_recess - up))
	for p in arc:
		fill.append(p)
	fill.append(Vector2(tr, tab_top + 6.0))
	fill.append(Vector2(pl, tab_top + 6.0))
	book_tab_seam.draw_colored_polygon(fill, PANEL_CREAM)

	# 一条连续墨线，串起整个底部 + 标签轮廓；两端叠进弹窗左右边框，无缝衔接
	var path := PackedVector2Array()
	path.append(Vector2(pr_line, y_recess - up))   # 叠进弹窗右边框
	path.append(Vector2(pr_line, y_recess))        # 转角
	path.append(Vector2(tr_line + r, y_recess))    # 内缩底边
	for p in arc:                                  # 圆弧下接
		path.append(p)
	path.append(Vector2(tr_line, tab_bot))         # 标签右边
	path.append(Vector2(pl_line, tab_bot))         # 标签底边
	path.append(Vector2(pl_line, y_recess - up))   # 标签/弹窗左边，叠进弹窗左边框
	book_tab_seam.draw_polyline(path, INK, w, false)

# 打开/合上「商业模式」按钮自身边框：打开时整框关闭，轮廓交由 seam 一体绘制
func _set_book_tab_open(open: bool) -> void:
	if book_btn == null:
		return
	var bw := 0 if open else 4
	var ss := 0 if open else 4
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := book_btn.get_theme_stylebox(state) as StyleBoxFlat
		if sb != null:
			sb.border_width_left = bw
			sb.border_width_right = bw
			sb.border_width_top = bw
			sb.border_width_bottom = bw
			sb.shadow_size = ss

func _toggle_recipe_book() -> void:
	if recipe_panel == null:
		return
	recipe_panel.visible = not recipe_panel.visible
	_set_book_tab_open(recipe_panel.visible)
	if book_tab_shadow != null:
		book_tab_shadow.visible = recipe_panel.visible
		book_tab_shadow.queue_redraw()
	if book_tab_seam != null:
		book_tab_seam.visible = recipe_panel.visible
		book_tab_seam.queue_redraw()
	if recipe_panel.visible:
		_refresh_recipe_book()

func _toggle_company_tasks() -> void:
	# TODO: 公司任务面板待实现
	pass

# ---------------------------------------------------------------- gear menu
func _panel_stylebox() -> StyleBoxFlat:
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.98, 0.95, 0.89, 0.97)
	psb.set_corner_radius_all(8)
	psb.border_color = INK
	psb.set_border_width_all(3)
	psb.content_margin_left = 18
	psb.content_margin_right = 18
	psb.content_margin_top = 16
	psb.content_margin_bottom = 16
	return psb

func _build_gear_menu() -> void:
	gear_menu = Control.new()
	gear_menu.name = "GearMenu"
	gear_menu.position = Vector2.ZERO
	gear_menu.size = Vector2(BASE_W, BASE_H)
	gear_menu.visible = false
	gear_menu.process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停时仍可交互
	hud.add_child(gear_menu)

	# 半透明遮罩，拦截下层点击
	var dim := ColorRect.new()
	dim.color = Color(0.10, 0.09, 0.08, 0.55)
	dim.position = Vector2.ZERO
	dim.size = Vector2(BASE_W, BASE_H)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	gear_menu.add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	panel.position = Vector2(BASE_W * 0.5 - 210, 300)
	panel.size = Vector2(420, 0)
	gear_menu.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "菜单"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_pixel_font(title, 30)
	title.add_theme_color_override("font_color", INK)
	box.add_child(title)

	var items := [
		{"t": "继续", "f": Callable(self, "_gear_continue")},
		{"t": "重新开始", "f": Callable(self, "_gear_restart")},
		{"t": "图鉴", "f": Callable(self, "_gear_codex")},
		{"t": "商业模式", "f": Callable(self, "_gear_recipes")},
		{"t": "设置", "f": Callable(self, "_gear_settings")},
		{"t": "回到主菜单", "f": Callable(self, "_gear_main_menu")},
	]
	for it in items:
		var b := Button.new()
		b.text = String(it["t"])
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_menu_text_button(b, 34)
		b.pressed.connect(it["f"])
		box.add_child(b)

func _toggle_gear_menu() -> void:
	if gear_menu == null:
		return
	var open := not gear_menu.visible
	gear_menu.visible = open
	get_tree().paused = open

func _close_gear_menu() -> void:
	if gear_menu != null:
		gear_menu.visible = false
	get_tree().paused = false

func _gear_continue() -> void:
	_close_gear_menu()

func _gear_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _gear_codex() -> void:
	_close_gear_menu()
	_toggle_codex()

func _gear_recipes() -> void:
	_close_gear_menu()
	_toggle_recipe_book()

func _gear_settings() -> void:
	_close_gear_menu()
	_toggle_settings()

func _gear_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/StartMenu.tscn")

# ---------------------------------------------------------------- codex (全卡图鉴)
const CODEX_TYPE := {
	"employee": "员工", "resource_node": "资源点", "facility": "设施", "resource": "资源",
	"customer": "客户", "product": "产品", "business_model": "商业模式",
}
# 列：名称 / 类型 / 数值 / 卡包 / 解锁 / 配方
const CODEX_COLS := ["名称", "类型", "数值", "卡包", "解锁前置", "产出配方"]
const CODEX_W := [150.0, 80.0, 250.0, 230.0, 230.0, 250.0]

func _build_codex_panel() -> void:
	codex_panel = PanelContainer.new()
	codex_panel.size = Vector2(1320, 840)
	codex_panel.position = Vector2((BASE_W - 1320) * 0.5 - 110, 120)   # 偏左，右侧留出卡片预览位
	codex_panel.visible = false
	codex_panel.add_theme_stylebox_override("panel", _panel_stylebox())
	hud.add_child(codex_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	codex_panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "图鉴 · 全卡属性"
	_apply_pixel_font(title, 28)
	title.add_theme_color_override("font_color", INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var tip := Label.new()
	tip.text = "悬停卡名查看卡面"
	_apply_pixel_font(tip, 15)
	tip.add_theme_color_override("font_color", Color("8a8175"))
	head.add_child(tip)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(90, 42)
	_apply_pixel_font(close, 16)
	_style_button(close, Color("e0c39a"))
	close.pressed.connect(_toggle_codex)
	head.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	codex_grid = GridContainer.new()
	codex_grid.columns = CODEX_COLS.size()
	codex_grid.add_theme_constant_override("h_separation", 14)
	codex_grid.add_theme_constant_override("v_separation", 7)
	codex_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(codex_grid)

	# 右侧悬停卡面预览（背景 + Card 实例）
	codex_preview_bg = Panel.new()
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(0.10, 0.09, 0.08, 0.92)
	pbg.set_corner_radius_all(10)
	pbg.border_color = INK
	pbg.set_border_width_all(3)
	codex_preview_bg.add_theme_stylebox_override("panel", pbg)
	codex_preview_bg.size = Vector2(212, 232)
	codex_preview_bg.visible = false
	codex_preview_bg.z_index = 4000
	hud.add_child(codex_preview_bg)

	codex_preview = CardScript.new()
	codex_preview.visible = false
	codex_preview.z_index = 4001
	hud.add_child(codex_preview)

	_refresh_codex()

func _toggle_codex() -> void:
	if codex_panel == null:
		return
	codex_panel.visible = not codex_panel.visible
	if codex_panel.visible:
		_refresh_codex()
	else:
		_codex_unhover()

func _refresh_codex() -> void:
	if codex_grid == null:
		return
	for c in codex_grid.get_children():
		c.queue_free()
	# 表头
	for i in range(CODEX_COLS.size()):
		var h := _codex_cell(String(CODEX_COLS[i]), CODEX_W[i], true)
		h.add_theme_color_override("font_color", INK)
		codex_grid.add_child(h)
	# 行（按类型分组排序）
	var order := ["employee", "resource_node", "facility", "customer", "product", "resource", "business_model"]
	var ids := DataLoader.cards.keys()
	ids.sort_custom(func(a, b):
		var ta := order.find(String(DataLoader.cards[a].get("type", "")))
		var tb := order.find(String(DataLoader.cards[b].get("type", "")))
		if ta != tb:
			return ta < tb
		return a < b)
	for id in ids:
		var d: Dictionary = DataLoader.cards[id]
		# 名称（可悬停 → 卡面预览）
		var nm := _codex_cell(String(d.get("name", id)), CODEX_W[0], false)
		nm.add_theme_color_override("font_color", Color("2b6cb0"))
		nm.mouse_filter = Control.MOUSE_FILTER_STOP
		nm.mouse_entered.connect(_codex_hover.bind(String(id), nm))
		nm.mouse_exited.connect(_codex_unhover)
		codex_grid.add_child(nm)
		codex_grid.add_child(_codex_cell(String(CODEX_TYPE.get(String(d.get("type", "")), "—")), CODEX_W[1], false))
		codex_grid.add_child(_codex_cell(_codex_values(d), CODEX_W[2], false))
		codex_grid.add_child(_codex_cell(_codex_packs_label(String(id)), CODEX_W[3], false))
		codex_grid.add_child(_codex_cell(_codex_unlock_label(String(id)), CODEX_W[4], false))
		codex_grid.add_child(_codex_cell(_codex_recipes_label(String(id)), CODEX_W[5], false))

func _codex_cell(text: String, w: float, header: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(w, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_pixel_font(l, 17 if header else 16)
	l.add_theme_color_override("font_color", INK if header else Color("4a443c"))
	return l

func _codex_values(d: Dictionary) -> String:
	var parts: Array = []
	if int(d.get("salary", 0)) > 0:
		parts.append("薪$%d" % int(d["salary"]))
	if int(d.get("capacity", 0)) > 0:
		parts.append("产能%d" % int(d["capacity"]))
	if int(d.get("value", 0)) > 0:
		parts.append("值$%d" % int(d["value"]))
	if int(d.get("cost", 0)) > 0:
		parts.append("成本$%d" % int(d["cost"]))
	if int(d.get("maxUses", -1)) > 0:
		parts.append("可用%d次" % int(d["maxUses"]))
	var tags = d.get("workTags", [])
	if tags is Array and not tags.is_empty():
		parts.append("[%s]" % _join_text(tags, "/"))
	return _join_text(parts, " ") if not parts.is_empty() else "—"

func _codex_packs_of(id: String) -> Array:
	var out: Array = []
	for pid in DataLoader.packs.keys():
		var p: Dictionary = DataLoader.packs[pid]
		var found := false
		for slot in p.get("slots", []):
			for opt in slot:
				if String(opt.get("id", "")) == id:
					found = true
					break
			if found:
				break
		if found:
			out.append(p)
	return out

func _codex_packs_label(id: String) -> String:
	var names: Array = []
	for p in _codex_packs_of(id):
		names.append(String(p.get("name", "")))
	return _join_text(names, "、") if not names.is_empty() else "—"

func _codex_recipes_of(id: String) -> Array:
	var out: Array = []
	for r in DataLoader.recipes:
		for o in r.get("outputs", []):
			if String(o.get("id", "")) == id:
				out.append(r)
				break
	return out

func _codex_recipes_label(id: String) -> String:
	var out: Array = []
	for r in _codex_recipes_of(id):
		out.append("%s（%s）" % [String(r.get("name", "")), _recipe_formula(r)])
	return _join_text(out, "\n") if not out.is_empty() else "—"

func _codex_unlock_label(id: String) -> String:
	var parts: Array = []
	# 卡包阶段（取最低阶）
	var min_stage := 99
	for p in _codex_packs_of(id):
		min_stage = mini(min_stage, int(p.get("stage", 0)))
	if min_stage < 99:
		parts.append("阶段「%s」" % GameState.STAGE_NAMES[clampi(min_stage, 0, GameState.STAGE_NAMES.size() - 1)])
	# 产出配方所需研发
	var ideas: Array = []
	for r in _codex_recipes_of(id):
		var gate := String(r.get("requiredIdeaId", ""))
		if gate != "" and not ideas.has(gate):
			ideas.append(gate)
	for g in ideas:
		var rd: Dictionary = DataLoader.research.get(g, {})
		parts.append("研发「%s」" % String(rd.get("name", g)))
	return _join_text(parts, " / ") if not parts.is_empty() else "初始可得"

func _codex_hover(id: String, lbl: Label) -> void:
	if codex_preview == null or not is_instance_valid(codex_preview):
		return
	codex_preview.setup(id)
	codex_preview.queue_redraw()
	var screen := _screen_size()
	var px := minf(codex_panel.position.x + codex_panel.size.x + 26, screen.x - 220)
	var py := clampf(lbl.global_position.y - 60, 130, screen.y - 250)
	codex_preview.position = Vector2(px, py)
	codex_preview.visible = true
	codex_preview_bg.position = Vector2(px - 16, py - 16)
	codex_preview_bg.visible = true

func _codex_unhover() -> void:
	if codex_preview and is_instance_valid(codex_preview):
		codex_preview.visible = false
	if codex_preview_bg and is_instance_valid(codex_preview_bg):
		codex_preview_bg.visible = false

# ---------------------------------------------------------------- settings
func _build_settings_panel() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.position = Vector2(BASE_W * 0.5 - 230, 320)
	settings_panel.size = Vector2(460, 0)
	settings_panel.visible = false
	settings_panel.add_theme_stylebox_override("panel", _panel_stylebox())
	hud.add_child(settings_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "设置"
	_apply_pixel_font(title, 28)
	title.add_theme_color_override("font_color", INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "关闭"
	close.size = Vector2(90, 42)
	_apply_pixel_font(close, 16)
	_style_button(close, Color("e0c39a"))
	close.pressed.connect(_toggle_settings)
	head.add_child(close)

	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	box.add_child(volume_row)
	var volume_label := Label.new()
	volume_label.text = "音效音量"
	volume_label.custom_minimum_size = Vector2(120, 48)
	_apply_pixel_font(volume_label, 20)
	volume_label.add_theme_color_override("font_color", INK)
	volume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	volume_row.add_child(volume_label)
	var volume_slider := HSlider.new()
	volume_slider.custom_minimum_size = Vector2(220, 48)
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 1.0
	volume_slider.value = Settings.sfx_volume * 100.0
	volume_slider.value_changed.connect(_on_settings_volume_changed)
	volume_row.add_child(volume_slider)
	var volume_value := Label.new()
	volume_value.name = "VolumeValue"
	volume_value.custom_minimum_size = Vector2(64, 48)
	volume_value.text = "%d%%" % roundi(Settings.sfx_volume * 100.0)
	volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_pixel_font(volume_value, 18)
	volume_value.add_theme_color_override("font_color", INK)
	volume_row.add_child(volume_value)

	var fs := CheckButton.new()
	fs.text = "全屏"
	fs.button_pressed = Settings.fullscreen
	_apply_pixel_font(fs, 22)
	fs.add_theme_color_override("font_color", INK)
	fs.toggled.connect(_on_fullscreen_toggled)
	box.add_child(fs)

	var motion := CheckButton.new()
	motion.text = "减少动态"
	motion.button_pressed = Settings.reduce_motion
	_apply_pixel_font(motion, 22)
	motion.add_theme_color_override("font_color", INK)
	motion.toggled.connect(_on_reduce_motion_toggled)
	box.add_child(motion)

func _toggle_settings() -> void:
	if settings_panel != null:
		settings_panel.visible = not settings_panel.visible

func _on_settings_volume_changed(value: float) -> void:
	Settings.set_sfx_volume(value / 100.0)
	if settings_panel != null:
		var value_label := settings_panel.find_child("VolumeValue", true, false) as Label
		if value_label != null:
			value_label.text = "%d%%" % roundi(value)

func _on_fullscreen_toggled(on: bool) -> void:
	Settings.set_fullscreen(on)

func _on_reduce_motion_toggled(on: bool) -> void:
	Settings.set_reduce_motion(on)

func _refresh_recipe_book() -> void:
	if recipe_list == null:
		return
	var lines: Array = []
	var by_stage := _business_models_by_stage()
	var stages := by_stage.keys()
	stages.sort()
	for si in stages.size():
		var stage := int(stages[si])
		var recipes: Array = by_stage[stage]
		var known := _known_business_models(recipes)
		lines.append("[b]阶段「%s」[/b]" % GameState.STAGE_NAMES[clampi(stage, 0, GameState.STAGE_NAMES.size() - 1)])
		lines.append("[color=#5b5145]已解锁 商业模式：%d/%d[/color]" % [known.size(), recipes.size()])
		for recipe in known:
			lines.append("[color=#2f2a25]• %s：%s[/color]" % [
				String(recipe.get("name", "")), DataLoader.recipe_formula_text(String(recipe.get("id", "")))])
		for i in range(maxi(0, recipes.size() - known.size())):
			lines.append("[color=#777067]• ？？[/color]")
		if si < stages.size() - 1:
			lines.append("[color=#b9ad9c]────────────────────────[/color]")
	recipe_list.text = _join_text(lines, "\n")

func _business_models_by_stage() -> Dictionary:
	var out := {}
	for recipe in DataLoader.recipes:
		var stage := _business_model_stage(recipe)
		if not out.has(stage):
			out[stage] = []
		out[stage].append(recipe)
	return out

func _known_business_models(recipes: Array) -> Array:
	var known := []
	var remaining := recipes.duplicate()
	for rid in GameState.business_model_order:
		for recipe in remaining.duplicate():
			if String(recipe.get("id", "")) == String(rid):
				known.append(recipe)
				remaining.erase(recipe)
				break
	for recipe in remaining.duplicate():
		if _has_business_model_card(String(recipe.get("id", ""))):
			known.append(recipe)
			remaining.erase(recipe)
	return known

func _business_model_stage(recipe: Dictionary) -> int:
	var gate := String(recipe.get("requiredIdeaId", ""))
	if gate != "":
		var node: Dictionary = DataLoader.research.get(gate, {})
		if not node.is_empty():
			return int(node.get("stage", 0))
	var min_stage := 99
	for id in _recipe_card_ids(recipe):
		for pack in _codex_packs_of(id):
			min_stage = mini(min_stage, int(pack.get("stage", 0)))
	return min_stage if min_stage < 99 else 0

func _recipe_card_ids(recipe: Dictionary) -> Array:
	var ids := []
	for inp in recipe.get("inputs", []):
		var id := String(inp.get("id", ""))
		if id != "" and not ids.has(id):
			ids.append(id)
	for outp in recipe.get("outputs", []):
		var id := String(outp.get("id", ""))
		if id != "" and not ids.has(id):
			ids.append(id)
	return ids

func _has_business_model_card(recipe_id: String) -> bool:
	for c in all_cards:
		if is_instance_valid(c) and _card_unlocks_business_model(String(c.card_id), recipe_id):
			return true
	for p in loose_packs:
		if not is_instance_valid(p):
			continue
		for id in p.contents:
			if _card_unlocks_business_model(String(id), recipe_id):
				return true
	return false

func _card_unlocks_business_model(card_id: String, recipe_id: String) -> bool:
	if card_id == recipe_id:
		return true
	var d := DataLoader.card_def(card_id)
	return String(d.get("recipeId", "")) == recipe_id \
		or String(d.get("businessModelId", "")) == recipe_id \
		or String(d.get("unlocksRecipeId", "")) == recipe_id

func _recipe_unlocked(recipe: Dictionary) -> bool:
	var gate := String(recipe.get("requiredIdeaId", ""))
	return gate == "" or GameState.idea_done(gate)

func _recipe_formula(recipe: Dictionary) -> String:
	return "：" + DataLoader.recipe_formula_text(String(recipe.get("id", "")))

func _input_label(inp: Dictionary) -> String:
	var id := String(inp.get("id", ""))
	var count := int(inp.get("count", 1))
	var s := DataLoader.card_name(id)
	s += "*%d" % count
	if not inp.get("consume", false):
		s += "(工作站)"
	return s

func _outputs_label(outputs: Array) -> String:
	var parts: Array = []
	for outp in outputs:
		if outp.has("cash"):
			parts.append("现金*%d" % int(outp["cash"]))
		elif outp.has("id"):
			var s := DataLoader.card_name(String(outp["id"]))
			var count := int(outp.get("count", 1))
			s += "*%d" % count
			parts.append(s)
	return _join_text(parts, "+")

func _worker_label(tags: Array) -> String:
	if tags.is_empty():
		return ""
	var labels: Array = []
	for t in tags:
		match String(t):
			"sales": labels.append("销售")
			"admin": labels.append("行政")
			"dev": labels.append("研发")
			"build": labels.append("建设")
			"data": labels.append("数据")
			"founder": labels.append("创始人")
			"any": labels.append("任意员工")
			_: labels.append(String(t))
	return "员工[%s]" % _join_text(labels, "/")

func _join_text(parts: Array, sep: String) -> String:
	var out := ""
	for i in parts.size():
		if i > 0:
			out += sep
		out += String(parts[i])
	return out

# ---------------------------------------------------------------- research panel
func _build_research_panel() -> void:
	research_panel = hud.get_node_or_null("ResearchPanel") as Control
	if research_panel == null:
		research_panel = preload("res://scripts/ResearchGraph.gd").new()
		research_panel.name = "ResearchPanel"
		research_panel.position = Vector2.ZERO
		research_panel.size = Vector2(BASE_W, BASE_H)
		hud.add_child(research_panel)
	research_panel.visible = false

func _toggle_research() -> void:
	if research_panel:
		research_panel.visible = not research_panel.visible

func _refresh_research() -> void:
	pass

func _prereq_ok(node: Dictionary) -> bool:
	for pre in node.get("prereq", []):
		if not GameState.idea_done(pre):
			return false
	return true

func _on_idea_unlocked(idea_id: String) -> void:
	var node: Dictionary = DataLoader.research.get(idea_id, {})
	var kind := String(node.get("kind", ""))
	var tag: String = {"recipe": "新配方", "feature": "新功能", "event": "新事件", "valuation": "估值优化"}.get(kind, "")
	_show_toast("🔬 研发完成：%s（%s）" % [String(node.get("name", idea_id)), tag])
	# re-evaluate idle stacks so newly unlocked recipes can start
	for sid in stacks.keys():
		evaluate_stack(sid)
	_refresh_recipe_book()

func _stage_pack_name(stage: int) -> String:
	for pack_value in DataLoader.packs.values():
		var pack: Dictionary = pack_value
		if int(pack.get("stage", -1)) != stage:
			continue
		var pack_name := String(pack.get("name", GameState.stage_name()))
		return pack_name.trim_suffix("包")
	return GameState.stage_name()

func _layout_top_right_stats() -> void:
	var right_edge := _screen_size().x - 100.0
	var visible_gap := 10.0
	for label in [lbl_finance, lbl_business, lbl_expense]:
		if label == null or not is_instance_valid(label):
			continue
		var font: Font = label.get_theme_font("font")
		var text_width := 0.0
		if font != null:
			text_width = font.get_string_size(
				label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, TOP_LABEL_FONT_SIZE
			).x
		var width := ceilf(text_width) + 4.0
		var group := label.get_parent() as Control
		if group == null:
			continue
		group.position.x = right_edge - width
		group.size.x = width
		label.position.x = 0.0
		label.size.x = width
		right_edge = group.position.x - visible_gap

func _update_hud() -> void:
	if lbl_status == null:
		return
	_sync_cash_state()
	lbl_status.text = "阶段「%s」  第%d月%s" % [
		_stage_pack_name(GameState.stage), GameState.month,
		("   [紧急!]" if emergency else "")]
	if lbl_top_rp:
		lbl_top_rp.text = "RP %d" % int(GameState.rp)
	if month_progress:
		var total := float(DataLoader.balance.get("month_seconds", 90.0))
		var ratio := clampf(month_time / maxf(1.0, total), 0.0, 1.0)
		month_progress.size = Vector2(month_progress_full_width * ratio, month_progress.size.y)
	if lbl_business:
		lbl_business.text = "空间 %d/%d" % [_business_card_count(), _business_card_capacity()]
	if lbl_finance:
		lbl_finance.text = "资金 $%d" % GameState.cash
	if lbl_expense:
		lbl_expense.text = "月支出 $%d" % _current_expense()
	_layout_top_right_stats()
	if lbl_val:
		lbl_val.text = "估值 $%d" % GameState.valuation
	if research_panel and research_panel.visible:
		_refresh_research()

# ---------------------------------------------------------------- background
func _draw() -> void:
	# 地面 = 3D 城市里的白板（在 CityBackground 渲染）。
	_draw_battle_decoration()   # 战斗中：中心 VS 装饰（画在卡牌之下）
	_draw_supply_chains()

	var f := _ui_font()
	# fixed bank slot, outside the zoomable canvas
	if bank_button == null or not is_instance_valid(bank_button):
		draw_rect(BANK_RECT, Color("f3ead7"), true)
		draw_rect(BANK_RECT, Color("d9a552"), false, 3.0)
		draw_string(f, BANK_RECT.position + Vector2(86, 54), "在市场上出售", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("3a352f"))

	# 底部信息栏现绘制在 bottom_info（HUD 层）上，始终置顶，见 _draw_bottom_info()

func _cleanup_supply_chains() -> void:
	for chain in supply_chains.duplicate():
		var source = chain.get("source")
		var target = chain.get("target")
		if not is_instance_valid(source) or not is_instance_valid(target) \
				or not stacks.has(source.stack_id) or not stacks.has(target.stack_id):
			supply_chains.erase(chain)

func _draw_supply_chains() -> void:
	_cleanup_supply_chains()
	for chain in supply_chains:
		var source = chain.get("source")
		var target = chain.get("target")
		if source.stack_id == target.stack_id:
			continue
		_draw_supply_glow(source.stack_id, false)
		_draw_supply_glow(target.stack_id, false)
		var edge_pair := _supply_edge_pair(source.stack_id, target.stack_id)
		_draw_supply_arrow(
			edge_pair,
			true,
			chain == supply_hover_chain
		)
	if supply_drag_source != null and is_instance_valid(supply_drag_source):
		_draw_supply_glow(supply_drag_source.stack_id, true)
		var drag_pair := _supply_edge_pair_to_point(supply_drag_source.stack_id, supply_drag_mouse)
		if supply_drag_target != null and is_instance_valid(supply_drag_target):
			_draw_supply_glow(supply_drag_target.stack_id, true)
			drag_pair = _supply_edge_pair(supply_drag_source.stack_id, supply_drag_target.stack_id)
		_draw_supply_arrow(drag_pair, false, false)
	for transit in supply_transits:
		_draw_supply_transit(transit)

func _supply_edge_points(sid: int) -> Array:
	if not stack_base.has(sid):
		return []
	var stack_height := CH
	if stacks.has(sid):
		stack_height += maxf(0.0, float(stacks[sid].size() - 1) * CARD_OFFSET)
	var base: Vector2 = stack_base[sid]
	return [
		{"point": _project(base + Vector2(CW * 0.5, 0)), "normal": Vector2.UP},
		{"point": _project(base + Vector2(CW, stack_height * 0.5)), "normal": Vector2.RIGHT},
		{"point": _project(base + Vector2(CW * 0.5, stack_height)), "normal": Vector2.DOWN},
		{"point": _project(base + Vector2(0, stack_height * 0.5)), "normal": Vector2.LEFT},
	]

func _supply_edge_pair(source_sid: int, target_sid: int) -> Dictionary:
	var source_edges := _supply_edge_points(source_sid)
	var target_edges := _supply_edge_points(target_sid)
	if source_edges.is_empty() or target_edges.is_empty():
		return {}
	var best: Dictionary = {}
	var best_distance := INF
	for source_edge in source_edges:
		for target_edge in target_edges:
			var distance: float = source_edge["point"].distance_squared_to(target_edge["point"])
			if distance < best_distance:
				best_distance = distance
				best = {
					"start": source_edge["point"],
					"finish": target_edge["point"],
					"start_normal": source_edge["normal"],
					"finish_normal": target_edge["normal"],
				}
	return best

func _supply_edge_pair_to_point(source_sid: int, target_point: Vector2) -> Dictionary:
	var source_edges := _supply_edge_points(source_sid)
	if source_edges.is_empty():
		return {}
	var best: Dictionary = {}
	var best_distance := INF
	for source_edge in source_edges:
		var distance: float = source_edge["point"].distance_squared_to(target_point)
		if distance < best_distance:
			best_distance = distance
			best = {
				"start": source_edge["point"],
				"finish": target_point,
				"start_normal": source_edge["normal"],
				"finish_normal": -source_edge["normal"],
			}
	return best

func _draw_supply_glow(sid: int, active: bool) -> void:
	if not stack_base.has(sid):
		return
	var base: Vector2 = stack_base[sid]
	var stack_height := CH + maxf(0.0, float(stacks[sid].size() - 1) * CARD_OFFSET)
	var breath := (sin(supply_flow_phase * 0.035) + 1.0) * 0.5
	# 光罩紧贴牌堆实际轮廓，不再向外留出“框”的间距。
	var corners := PackedVector2Array([
		_project(base),
		_project(base + Vector2(CW, 0)),
		_project(base + Vector2(CW, stack_height)),
		_project(base + Vector2(0, stack_height)),
	])
	var loop := corners.duplicate()
	loop.append(corners[0])
	var strength := (0.72 if active else 0.48) + breath * (0.20 if active else 0.15)
	var flicker := 0.84 + sin(supply_flow_phase * 0.19) * 0.10 + sin(supply_flow_phase * 0.41) * 0.06
	var glow := Color(SUPPLY_BLUE_LIGHT, strength * flicker)
	draw_colored_polygon(corners, Color(SUPPLY_BLUE, 0.025 + breath * 0.035))
	draw_polyline(loop, Color(SUPPLY_BLUE, (0.08 + breath * 0.09) * flicker), 6.7 + breath * 1.7, true)
	draw_polyline(loop, Color(SUPPLY_BLUE_LIGHT, (0.18 + breath * 0.13) * flicker), 3.7 + breath, true)
	draw_polyline(loop, glow, 1.5 + breath * 0.5, true)

func _draw_supply_arrow(edge_pair: Dictionary, connected: bool, hovered: bool) -> void:
	if edge_pair.is_empty():
		return
	var points := _supply_path(edge_pair)
	if points.size() < 2:
		return
	if hovered and connected:
		_draw_supply_delete_x(_point_along_polyline(points, 0.5), supply_hover_scale)

func _update_supply_arrow_mesh() -> void:
	if supply_arrow_mesh == null or not is_instance_valid(supply_arrow_mesh):
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	_cleanup_supply_chains()
	for chain in supply_chains:
		var source = chain.get("source")
		var target = chain.get("target")
		if not is_instance_valid(source) or not is_instance_valid(target) \
				or source.stack_id == target.stack_id:
			continue
		_append_supply_arrow_geometry(
			_supply_path(_supply_edge_pair(source.stack_id, target.stack_id)),
			true, vertices, normals, colors, indices
		)
	if supply_drag_source != null and is_instance_valid(supply_drag_source):
		var pair := _supply_edge_pair_to_point(supply_drag_source.stack_id, supply_drag_mouse)
		if supply_drag_target != null and is_instance_valid(supply_drag_target):
			pair = _supply_edge_pair(supply_drag_source.stack_id, supply_drag_target.stack_id)
		_append_supply_arrow_geometry(
			_supply_path(pair), false, vertices, normals, colors, indices
		)
	if vertices.is_empty():
		supply_arrow_mesh.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	supply_arrow_mesh.mesh = mesh

func _append_supply_arrow_geometry(
		points: PackedVector2Array,
		connected: bool,
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		colors: PackedColorArray,
		indices: PackedInt32Array
	) -> void:
	if points.size() < 2:
		return
	var col := Color(SUPPLY_BLUE_LIGHT, 0.94 if connected else 0.76)
	_append_dashed_supply_ribbon(
		points, 22.0, 11.0, Color(col, col.a * 0.18), 16.0,
		-supply_flow_phase, vertices, normals, colors, indices
	)
	_append_dashed_supply_ribbon(
		points, 22.0, 11.0, col, 8.0,
		-supply_flow_phase, vertices, normals, colors, indices
	)
	var end_pt := points[points.size() - 1]
	var arrow_dir := (end_pt - points[points.size() - 2]).normalized()
	if arrow_dir.length() < 0.1:
		arrow_dir = Vector2.RIGHT
	var side := arrow_dir.orthogonal()
	var head := PackedVector2Array([
		end_pt + arrow_dir * 5.0,
		end_pt - arrow_dir * 13.0 + side * 9.0,
		end_pt - arrow_dir * 13.0 - side * 9.0,
	])
	_append_supply_triangle(head, col, vertices, normals, colors, indices)

func _append_dashed_supply_ribbon(
		points: PackedVector2Array,
		dash: float,
		gap: float,
		col: Color,
		width: float,
		phase0: float,
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		colors: PackedColorArray,
		indices: PackedInt32Array
	) -> void:
	var period := dash + gap
	var phase := fposmod(phase0, period)
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var segment := b - a
		var length := segment.length()
		if length < 0.001:
			continue
		var direction := segment / length
		var pos := -phase
		while pos < length:
			var from := maxf(pos, 0.0)
			var to := minf(pos + dash, length)
			if to > from:
				_append_supply_ribbon_segment(
					a + direction * from, a + direction * to, width, col,
					vertices, normals, colors, indices
				)
			pos += period
		phase = fposmod(phase + length, period)

func _append_supply_ribbon_segment(
		display_a: Vector2,
		display_b: Vector2,
		width: float,
		col: Color,
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		colors: PackedColorArray,
		indices: PackedInt32Array
	) -> void:
	var board_a := _unproject(display_a)
	var board_b := _unproject(display_b)
	var a := board_to_world(board_a)
	var b := board_to_world(board_b)
	a.y = SUPPLY_ARROW_Y
	b.y = SUPPLY_ARROW_Y
	var direction := b - a
	direction.y = 0.0
	if direction.length_squared() < 0.000001:
		return
	direction = direction.normalized()
	var half_width := width / maxf(view_zoom, 0.05) / CITY_CELL * 0.5
	var side := Vector3(-direction.z, 0.0, direction.x) * half_width
	var start := vertices.size()
	vertices.append_array(PackedVector3Array([a - side, a + side, b + side, b - side]))
	for i in 4:
		normals.append(Vector3.UP)
		colors.append(col)
	indices.append_array(PackedInt32Array([
		start, start + 1, start + 2,
		start, start + 2, start + 3,
	]))

func _append_supply_triangle(
		display_points: PackedVector2Array,
		col: Color,
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		colors: PackedColorArray,
		indices: PackedInt32Array
	) -> void:
	if display_points.size() != 3:
		return
	var start := vertices.size()
	for point in display_points:
		var world := board_to_world(_unproject(point))
		world.y = SUPPLY_ARROW_Y + 0.0002
		vertices.append(world)
		normals.append(Vector3.UP)
		colors.append(col)
	indices.append_array(PackedInt32Array([start, start + 1, start + 2]))

func _supply_path(edge_pair: Dictionary) -> PackedVector2Array:
	if edge_pair.is_empty():
		return PackedVector2Array()
	var start: Vector2 = edge_pair["start"]
	var finish: Vector2 = edge_pair["finish"]
	if start.distance_to(finish) < 8.0:
		return PackedVector2Array([start, finish])
	var start_normal: Vector2 = edge_pair.get("start_normal", Vector2.RIGHT)
	var finish_normal: Vector2 = edge_pair.get("finish_normal", Vector2.LEFT)
	var stub := minf(28.0, start.distance_to(finish) * 0.22)
	var start_out := start + start_normal * stub
	var finish_out := finish + finish_normal * stub
	var raw := PackedVector2Array([start, start_out])
	if absf(start_normal.x) > 0.5:
		var elbow_x := (start_out.x + finish_out.x) * 0.5
		raw.append(Vector2(elbow_x, start_out.y))
		raw.append(Vector2(elbow_x, finish_out.y))
	else:
		var elbow_y := (start_out.y + finish_out.y) * 0.5
		raw.append(Vector2(start_out.x, elbow_y))
		raw.append(Vector2(finish_out.x, elbow_y))
	raw.append(finish_out)
	raw.append(finish)
	return _rounded_supply_path(raw, 18.0)

func _supply_chain_at(display_pt: Vector2):
	_cleanup_supply_chains()
	var best = null
	var best_distance := 15.0
	for chain in supply_chains:
		var source = chain.get("source")
		var target = chain.get("target")
		if not is_instance_valid(source) or not is_instance_valid(target) \
				or source.stack_id == target.stack_id:
			continue
		var path := _supply_path(_supply_edge_pair(source.stack_id, target.stack_id))
		var distance := _distance_to_polyline(display_pt, path)
		if distance < best_distance:
			best_distance = distance
			best = chain
	return best

func _supply_chain_midpoint(chain) -> Vector2:
	if chain == null:
		return Vector2.ZERO
	var source = chain.get("source")
	var target = chain.get("target")
	if not is_instance_valid(source) or not is_instance_valid(target):
		return Vector2.ZERO
	return _point_along_polyline(
		_supply_path(_supply_edge_pair(source.stack_id, target.stack_id)),
		0.5
	)

func _draw_supply_delete_x(center: Vector2, amount: float) -> void:
	if amount <= 0.01:
		return
	var radius := 15.0 * amount
	draw_circle(center, radius + 5.0, Color(SUPPLY_BLUE_DARK, 0.22 * amount))
	draw_circle(center, radius, Color("f3eee4"))
	draw_arc(center, radius, 0.0, TAU, 32, Color(SUPPLY_BLUE_DARK, 0.95), 3.0, true)
	var arm := 6.5 * amount
	draw_line(center + Vector2(-arm, -arm), center + Vector2(arm, arm), SUPPLY_BLUE_DARK, 3.5, true)
	draw_line(center + Vector2(arm, -arm), center + Vector2(-arm, arm), SUPPLY_BLUE_DARK, 3.5, true)

func _draw_supply_transit(transit: Dictionary) -> void:
	var source = transit.get("source")
	var target = transit.get("target")
	if not is_instance_valid(source) or not is_instance_valid(target) \
			or not stacks.has(source.stack_id) or not stacks.has(target.stack_id):
		return
	var path := _supply_path(_supply_edge_pair(source.stack_id, target.stack_id))
	var point := _point_along_polyline(path, float(transit.get("progress", 0.0)))
	draw_circle(point, 13.0, Color(SUPPLY_BLUE, 0.16))
	draw_circle(point, 8.0, Color(SUPPLY_BLUE_LIGHT, 0.34))
	draw_circle(point, 4.5, SUPPLY_BLUE_DARK)

func _distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	var best := INF
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var segment := b - a
		var denom := segment.length_squared()
		var t := 0.0 if denom <= 0.001 else clampf((point - a).dot(segment) / denom, 0.0, 1.0)
		best = minf(best, point.distance_to(a + segment * t))
	return best

func _point_along_polyline(points: PackedVector2Array, ratio: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	if total <= 0.001:
		return points[0]
	var wanted := clampf(ratio, 0.0, 1.0) * total
	var walked := 0.0
	for i in range(points.size() - 1):
		var length := points[i].distance_to(points[i + 1])
		if walked + length >= wanted:
			return points[i].lerp(points[i + 1], (wanted - walked) / maxf(length, 0.001))
		walked += length
	return points[points.size() - 1]

func _rounded_supply_path(points: PackedVector2Array, radius: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := PackedVector2Array([points[0]])
	for i in range(1, points.size() - 1):
		var prev: Vector2 = points[i - 1]
		var corner: Vector2 = points[i]
		var next: Vector2 = points[i + 1]
		var in_len := corner.distance_to(prev)
		var out_len := corner.distance_to(next)
		if in_len < 0.01 or out_len < 0.01:
			out.append(corner)
			continue
		var r := minf(radius, minf(in_len, out_len) * 0.45)
		var before := corner + (prev - corner).normalized() * r
		var after := corner + (next - corner).normalized() * r
		out.append(before)
		for step in range(1, 6):
			var t := float(step) / 5.0
			var omt := 1.0 - t
			out.append(before * (omt * omt) + corner * (2.0 * omt * t) + after * (t * t))
	out.append(points[points.size() - 1])
	return out

# 伪斜体：对画布做切变后绘制（fallback 字体无真斜体）
func _round_corners(q: Array, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := q.size()
	for i in n:
		var p: Vector2 = q[i]
		var prev: Vector2 = q[(i - 1 + n) % n]
		var nxt: Vector2 = q[(i + 1) % n]
		var rr := minf(r, minf(p.distance_to(prev), p.distance_to(nxt)) * 0.5)
		var a := p + (prev - p).normalized() * rr
		var b := p + (nxt - p).normalized() * rr
		out.append(a)
		for s in range(1, 4):
			var t := float(s) / 4.0
			out.append(a.lerp(p, t).lerp(p.lerp(b, t), t))
		out.append(b)
	return out

func _round_corner_cutouts(q: Array, r: float) -> Array:
	var out := []
	var n := q.size()
	for i in n:
		var p: Vector2 = q[i]
		var prev: Vector2 = q[(i - 1 + n) % n]
		var nxt: Vector2 = q[(i + 1) % n]
		var rr := minf(r, minf(p.distance_to(prev), p.distance_to(nxt)) * 0.5)
		var a := p + (prev - p).normalized() * rr
		var b := p + (nxt - p).normalized() * rr
		var cut := PackedVector2Array([p, a])
		for s in range(1, 4):
			var t := float(s) / 4.0
			cut.append(a.lerp(p, t).lerp(p.lerp(b, t), t))
		cut.append(b)
		out.append(cut)
	return out

func _inset_quad(q: Array, d: float) -> Array:
	var c: Vector2 = (q[0] + q[1] + q[2] + q[3]) / 4.0
	var out := []
	for p in q:
		var dir: Vector2 = c - p
		if dir.length() > 0.01:
			dir = dir.normalized()
		out.append(p + dir * d)
	return out

func _draw_italic(canvas: CanvasItem, f: Font, pos: Vector2, text: String, size: int, col: Color) -> void:
	var t := Transform2D(Vector2(1, 0), Vector2(-0.22, 1), pos)
	canvas.draw_set_transform_matrix(t)
	canvas.draw_string(f, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_CENTER, _screen_size().x, size, col)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

# 底部信息栏：画在 HUD 层的 bottom_info 节点上，z 高于所有卡牌，始终置顶。
func _draw_bottom_info() -> void:
	if bottom_info == null:
		return
	var f := _ui_font()
	var screen := _screen_size()
	var info_y := _bottom_y()
	var info_h := screen.y - info_y
	var font_size := 29
	var baseline_y := info_y + (info_h - f.get_height(font_size)) * 0.5 + f.get_ascent(font_size)
	bottom_info.draw_rect(Rect2(0, info_y, screen.x, info_h), ORG_BG, true)
	bottom_info.draw_line(Vector2(0, info_y), Vector2(screen.x, info_y), Color(0.23, 0.21, 0.18, 0.5), 2.5)
	if battle_active and is_instance_valid(battle_rival) and is_instance_valid(battle_employee):
		var rival_name := String(battle_rival.cdef.get("name", battle_rival.card_id))
		var employee_name := String(battle_employee.cdef.get("name", battle_employee.card_id))
		_draw_info_line(bottom_info, f, baseline_y, [
			{"t": "商战开始！　", "b": true, "i": false},
			{"t": "%s vs %s" % [rival_name, employee_name], "b": false, "i": false},
		], Color(0.27, 0.25, 0.22, 0.98), font_size)
		return
	# 悬停优先：鼠标移到卡上即出该卡（或堆叠）信息；移开则恢复选中/默认 hint
	var info_parts := _hover_info_parts()
	if not info_parts.is_empty():
		_draw_info_line(bottom_info, f, baseline_y, info_parts, Color(0.30, 0.27, 0.23, 0.95), font_size)
	else:
		var fresh := toast_t > 0.0
		var hint_col := Color("8a5a26") if fresh else Color(0.36, 0.33, 0.29, 0.92)
		_draw_italic(bottom_info, f, Vector2(0, baseline_y), hint_text, font_size, hint_col)

func _on_business_model_unlocked(recipe_id: String) -> void:
	var bm_name := DataLoader.card_name(DataLoader.business_model_card_id(recipe_id))
	_show_founder_bubble("发现了 %s！" % bm_name)

# Anchor where the speech tail originates: the founder's "mouth",
# upper-right inside the card. Mapped through the card's own transform so it
# tracks the live, projected card position (NOT re-projected from screen space).
func _founder_mouth_screen(founder: Node2D) -> Vector2:
	return _project(_board_topleft(founder) + Vector2(CW * 0.70, CH * 0.34))

func _show_founder_bubble(text: String) -> void:
	var founder = _founder_on_board()
	if not is_instance_valid(founder):
		return
		
	if is_instance_valid(founder_bubble):
		founder_bubble.queue_free()

	_sfx("aha")
		
	var bubble := PanelContainer.new()
	bubble.name = "FounderSpeechBubble"
	hud.add_child(bubble)
	bubble.z_index = 4090
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(22)
	sb.border_width_left = 6
	sb.border_width_right = 6
	sb.border_width_top = 6
	sb.border_width_bottom = 6
	sb.border_color = Color.BLACK
	sb.content_margin_left = 25
	sb.content_margin_right = 25
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	
	bubble.add_theme_stylebox_override("panel", sb)

	# 主体与尾巴共用一个位于背后的阴影层，避免两块阴影各画各的产生割裂。
	var bubble_shadow := Control.new()
	bubble_shadow.name = "BubbleShadow"
	bubble_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble_shadow.show_behind_parent = true
	bubble.add_child(bubble_shadow)
	
	var label := Label.new()
	label.name = "BubbleLabel"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_font_override("font", _ui_font())
	label.add_theme_font_size_override("font_size", 28)
	bubble.add_child(label)

	bubble_shadow.draw.connect(func():
		var f = _founder_on_board()
		if not is_instance_valid(f):
			return
		var depth := Vector2(8.0 / 3.0, 8.0 / 3.0)
		var mouth := _founder_mouth_screen(f)
		var local_pivot := mouth - bubble.position
		var w := bubble.size.x
		var h := bubble.size.y
		var base_w := 36.0
		var lean := 28.0
		var on_bottom: bool = local_pivot.y > h * 0.5
		var edge_y: float = (h - 6.0) if on_bottom else 6.0
		var base_cx: float = clampf(local_pivot.x + lean, 25.0 + base_w * 0.5, w - 25.0 - base_w * 0.5)
		var pt_a := local_pivot
		var pt_b := Vector2(base_cx - base_w * 0.5, edge_y)
		var pt_c := Vector2(base_cx + base_w * 0.5, edge_y)
		var shadow_color := Color(0.04, 0.04, 0.04, 0.20)
		var shadow_box := StyleBoxFlat.new()
		shadow_box.bg_color = shadow_color
		shadow_box.set_corner_radius_all(22)
		shadow_box.corner_detail = 8
		bubble_shadow.draw_style_box(shadow_box, Rect2(depth, bubble.size))
		# 阴影尾巴只从主体外轮廓开始，避免半透明区域与主体阴影重复叠色。
		var shadow_edge_y := h if on_bottom else 0.0
		bubble_shadow.draw_colored_polygon(
			PackedVector2Array([
				Vector2(pt_b.x, shadow_edge_y) + depth,
				pt_a + depth,
				Vector2(pt_c.x, shadow_edge_y) + depth,
			]),
			shadow_color
		)
	)
	
	# Connect draw signal to draw the comic speech balloon pointing tail
	bubble.draw.connect(func():
		var f = _founder_on_board()
		if not is_instance_valid(f):
			return
		var mouth = _founder_mouth_screen(f)
		var local_pivot = mouth - bubble.position
		var w = bubble.size.x
		var h = bubble.size.y

		# Tail tip points at the mouth.
		var pt_a = local_pivot

		# Tail base sits on whichever edge faces the mouth. The base is offset
		# to the RIGHT of the tip so the tail leans left → classic speech-bubble look.
		var base_w := 36.0
		var lean := 28.0   # how far the base center is pushed right of the tip
		var on_bottom: bool = local_pivot.y > h * 0.5
		var edge_y: float = (h - 6.0) if on_bottom else 6.0
		var base_cx: float = clampf(local_pivot.x + lean, 25.0 + base_w * 0.5, w - 25.0 - base_w * 0.5)
		var pt_b := Vector2(base_cx - base_w * 0.5, edge_y)
		var pt_c := Vector2(base_cx + base_w * 0.5, edge_y)

		# Fill the tail (extend the base a few px into the body so it merges seamlessly).
		var inset: float = 8.0 if on_bottom else -8.0
		bubble.draw_colored_polygon(
			PackedVector2Array([
				Vector2(pt_b.x, pt_b.y - inset),
				pt_a,
				Vector2(pt_c.x, pt_c.y - inset),
			]),
			Color.WHITE
		)
		# Erase the bubble's border segment where the tail attaches (no seam line).
		bubble.draw_line(
			Vector2(pt_b.x + 2.0, edge_y),
			Vector2(pt_c.x - 2.0, edge_y),
			Color.WHITE, 10.0
		)
		# 斜边略微压进主体边框，线帽在底座两端与气泡轮廓无缝相接。
		var join_y := edge_y + (2.0 if on_bottom else -2.0)
		bubble.draw_line(Vector2(pt_b.x, join_y), pt_a, Color.BLACK, 6.0, true)
		bubble.draw_line(Vector2(pt_c.x, join_y), pt_a, Color.BLACK, 6.0, true)
	)
	
	founder_bubble = bubble
	founder_bubble_anchor = _board_topleft(founder)
	_reposition_founder_bubble(bubble, founder)

	bubble.scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(bubble, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.0)
	tw.tween_property(bubble, "scale", Vector2.ZERO, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(bubble.queue_free)

func _reposition_founder_bubble(bubble: Control, founder: Node2D) -> void:
	var mouth = _founder_mouth_screen(founder)

	if bubble.size == Vector2.ZERO:
		bubble.reset_size()

	var w = bubble.size.x
	var h = bubble.size.y
	var shadow := bubble.get_node_or_null("BubbleShadow") as Control
	if shadow != null:
		shadow.size = bubble.size

	# Sit the bubble up-and-to-one-side of the mouth so the tail angles back
	# toward the face. Bias toward the open space horizontally.
	var x = 0.0
	var screen := _screen_size()
	if mouth.x > screen.x * 0.5:
		x = mouth.x - w * 0.78
	else:
		x = mouth.x - w * 0.22

	x = clampf(x, 16.0, screen.x - w - 16.0)
	var y = mouth.y - h - 31.0
	y = clampf(y, HUD_H + 8.0, screen.y - h - 8.0)

	bubble.position = Vector2(x, y)

	# Pivot the pop-in animation from the mouth side for a "spoken" feel.
	var local_pivot = mouth - bubble.position
	bubble.pivot_offset = Vector2(clampf(local_pivot.x, 0.0, w), clampf(local_pivot.y, 0.0, h))
	if shadow != null:
		shadow.queue_redraw()
	bubble.queue_redraw()
