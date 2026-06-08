extends Node2D
## Zoned board with a shared 1-point perspective projection applied to BOTH the
## background and the cards. All gameplay logic runs in flat "board space";
## rendering projects board space -> display space (top narrower than bottom).

const CardScript = preload("res://scripts/Card.gd")
const PackCardScript = preload("res://scripts/PackCard.gd")
const FloatingCostScript = preload("res://scripts/FloatingCost.gd")
const CARD_SCALE := 1.0               # 卡按 120×180 设计，节点不再额外缩放
const CW := 180.0                     # square card, keeping the old long side
const CH := 180.0
const CARD_OFFSET := 34.0             # 叠放时每张上面的牌再往下一点
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
const DRAG_OMEGA_FALLOFF := 0.74   # 每往下一张，频率×此值 → 滞后/摆动递增
const DRAG_ZETA := 0.62            # 阻尼比 <1 → 欠阻尼，产生回摆/甩动感

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
var cursor_default: Texture2D
var cursor_card_hover: Texture2D
var cursor_card_drag: Texture2D
var cursor_state: String = ""
var dash_phase: float = 0.0

var month_time: float = 0.0

const DEFAULT_HINT := "「公司的地板光亮如新，有可能是创始人晚上擦的」"

var hud: CanvasLayer
var top_bar: Control
var bottom_info: Node2D     # 底部信息栏（HUD 层绘制，始终盖在卡牌之上）
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
var battle_rival_first: bool = true         # 谁先碰到谁先攻击
var battle_attacker_sid: int = -1           # 当前攻击方栈：relayout 时置顶
var month_progress: Panel
var month_progress_full_width: float = 320.0
var bank_button: Button
var pixel_font: Font
var pixel_regular_font: Font
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
const VIEW_ZOOM_MAX := 1.9
const VIEW_ZOOM_STEP := 1.12

# ---- 3D 相机驱动（Phase 1）：缩放/平移动 City Builder 的 3D 相机 ----
# board 空间 [CANVAS_X0..X1]×[MID_Y0..MID_Y1] 线性映射到白板世界矩形（中心在世界原点）
const BOARD_CX := (CANVAS_X0 + CANVAS_X1) * 0.5   # 960
const BOARD_CY := (MID_Y0 + MID_Y1) * 0.5         # 580
const CARD_PLANE_Y := 0.07                         # 卡牌所在平面高度（白板面 0.05 之上）
var cam_dist: float = 13.0                         # 相机距离（缩放）：默认让白板占据较大画面
var cam_target: Vector3 = Vector3.ZERO             # 相机注视点（平移，沿白板/城市平面）
const CAM_DIST_MIN := 7.0
const CAM_DIST_MAX := 70.0
const CAM_DIST_STEP := 1.12

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

var canvas_bg_tex: Texture2D = null
var street_bg_tex: Texture2D = null
var ui_icon_cache: Dictionary = {}

func _ready() -> void:
	GameState.reset()
	canvas_bg_tex = _load_canvas_bg()
	street_bg_tex = _load_image_tex("res://assets/bg_street.png")
	_setup_city_background()
	face_baker = CardFaceBakerScript.new()
	add_child(face_baker)
	_load_cursors()
	month_time = float(DataLoader.balance.get("month_seconds", 90.0))
	_reset_view_default()               # 初始视角：画布水平居中、顶边锚定
	_build_hud()
	_spawn_start_cards()
	if GameState.dev_mode:
		# In DEV mode, the 100 cash is not displayed as cards on the board
		pass
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
	city_bg.aim(cam_target, cam_dist)
	_recompute_view_zoom()
	_relayout_all()
	_relayout_loose_packs()
	queue_redraw()

# 把 view_zoom 同步为「屏幕每 board 单位像素数」，让所有 *view_zoom 的特效继续合理缩放
func _recompute_view_zoom() -> void:
	var a := _project(Vector2(BOARD_CX, BOARD_CY))
	var b := _project(Vector2(BOARD_CX + 100.0, BOARD_CY))
	view_zoom = clampf(a.distance_to(b) / 100.0, 0.05, 8.0)

func _reset_view_default() -> void:
	cam_target = Vector3.ZERO
	_apply_camera()

func _clamp_view_offset() -> void:
	pass   # 平移夹取交给相机逻辑（Phase 1 暂不夹）

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

# 运行时加载画布背景图（res:// 无需导入也能读）
# 3D 城市背景：在独立 SubViewport 渲染 Kenney 低多边形城市，作为画布外的背景层
var city_bg: SubViewport = null
const CityBackgroundScript = preload("res://scripts/CityBackground.gd")
const CardFaceBakerScript = preload("res://scripts/CardFaceBaker.gd")
var face_baker = null
# 3D 卡牌网格尺寸（世界单位）：board 120×180 / CITY_CELL(168)
const CARD3D_W := 120.0 / CITY_CELL
const CARD3D_H := 180.0 / CITY_CELL
const CARD3D_STACK_DY := 0.012     # 同栈每张抬高，避免共面闪烁
func _setup_city_background() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CityBackground"
	layer.layer = -10                       # 在所有 2D 棋盘内容之后（最底）
	add_child(layer)
	city_bg = CityBackgroundScript.new()
	layer.add_child(city_bg)
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

func _load_canvas_bg() -> Texture2D:
	for path in ["res://assets/bg_office.png", "res://assets/bg_canvas.png"]:
		var t := _load_image_tex(path)
		if t != null:
			return t
	return null

func _load_image_tex(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	return null

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

# 角点双线性插值：a=左上 b=右上 c=右下 d=左下
func _bilerp(a: Vector2, b: Vector2, c: Vector2, d: Vector2, u: float, v: float) -> Vector2:
	return a.lerp(b, u).lerp(d.lerp(c, u), v)

# 背景图：在画布 4 个投影角之间双线性铺满 → 直边梯形，和画布边框完全一致（无桶形）
func _draw_canvas_image() -> void:
	var p_tl := _project(Vector2(CANVAS_X0, MID_Y0))
	var p_tr := _project(Vector2(CANVAS_X1, MID_Y0))
	var p_br := _project(Vector2(CANVAS_X1, MID_Y1))
	var p_bl := _project(Vector2(CANVAS_X0, MID_Y1))
	var cols := 24
	var rows := 12
	for r in range(rows):
		var v0 := float(r) / rows
		var v1 := float(r + 1) / rows
		for c in range(cols):
			var u0 := float(c) / cols
			var u1 := float(c + 1) / cols
			var quad := PackedVector2Array([
				_bilerp(p_tl, p_tr, p_br, p_bl, u0, v0), _bilerp(p_tl, p_tr, p_br, p_bl, u1, v0),
				_bilerp(p_tl, p_tr, p_br, p_bl, u1, v1), _bilerp(p_tl, p_tr, p_br, p_bl, u0, v1)])
			var uvs := PackedVector2Array([
				Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
			draw_colored_polygon(quad, Color.WHITE, uvs, canvas_bg_tex)

func _load_cursors() -> void:
	cursor_default = _load_cursor_texture("res://assets/cursors/default.svg")
	cursor_card_hover = _load_cursor_texture("res://assets/cursors/card_hover.svg")
	cursor_card_drag = _load_cursor_texture("res://assets/cursors/card_drag.svg")
	_apply_cursor(cursor_default, Input.CURSOR_ARROW)

func _load_cursor_texture(path: String) -> Texture2D:
	var tex := ResourceLoader.load(path) as Texture2D
	if tex != null:
		return tex
	var img := Image.load_from_file(path)
	if img == null:
		return null
	if img.get_width() <= 0 or img.get_height() <= 0:
		return null
	return ImageTexture.create_from_image(img)

func _apply_cursor(tex: Texture2D, fallback_shape: Input.CursorShape) -> void:
	if tex != null:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2.ZERO)
	else:
		Input.set_default_cursor_shape(fallback_shape)

func _set_cursor_state(state: String) -> void:
	if cursor_state == state:
		return
	cursor_state = state
	match state:
		"drag":
			_apply_cursor(cursor_card_drag, Input.CURSOR_ARROW)
		"hover":
			_apply_cursor(cursor_card_hover, Input.CURSOR_ARROW)
		_:
			_apply_cursor(cursor_default, Input.CURSOR_ARROW)

# ---------------------------------------------------------------- spawning
const START_JITTER := 130.0     # 初始卡随机散布幅度（加大随机性）

func _jit(amount: float) -> Vector2:
	return Vector2(GameState.rng.randf_range(-amount, amount), GameState.rng.randf_range(-amount, amount))

func _spawn_start_cards() -> void:
	# 开局只有一个车库包（5 张牌，含创始人）；点一下跳一张，点完消失
	var pack: Dictionary = DataLoader.packs.get("garage_pack", {"name": "车库创业包"})
	var contents := ["founder", "p1_neighborhood", "p1_wholesale", "p1_office", "cash", "cash"]
	# 开局卡包直接弹到屏幕中央：以屏幕中心反投影到 board，再减去半张卡居中
	var center_tl := _unproject(Vector2(BASE_W, BASE_H) * 0.5 \
		- Vector2(PackCardScript.W, PackCardScript.H) * 0.5 * view_zoom)
	_spawn_loose_pack("garage_pack", pack, contents, center_tl)

func _spawn_card_pop(id: String, pos: Vector2, delay: float = 0.0) -> Node2D:
	var c := spawn_card(id, pos)
	_play_card_pop(c, delay)
	return c

func spawn_card(id: String, pos: Vector2) -> Node2D:
	if id == "founder" and _founder_on_board() != null:
		return null
	if not GameState.drawn_cards.has(id):
		GameState.drawn_cards[id] = true
	var c = CardScript.new()
	add_child(c)
	c.setup(id)
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
		_place_face3d(c, bp, i, sid == drag_sid)            # 真 3D 卡牌网格

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
	var m := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(CARD3D_W, CARD3D_H)
	m.mesh = qm
	m.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)       # 完全平躺在白板上（面朝上、顶边朝北）
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR   # 不透明部分能投射阴影
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.86, 0.84, 0.78)              # 烘焙完成前的占位底色
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pivot.add_child(m)
	city_bg.world_card_root().add_child(pivot)
	c.face3d = pivot
	c.tree_exited.connect(func():
		if is_instance_valid(pivot):
			pivot.queue_free())
	_bake_face_async(c, mat)
	# 出现时弹一下（scale 0→1，BACK 缓动）
	m.scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(m, "scale", Vector3.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _face3d_mesh(c) -> MeshInstance3D:
	if c.face3d != null and is_instance_valid(c.face3d) and c.face3d.get_child_count() > 0:
		return c.face3d.get_child(0) as MeshInstance3D
	return null

func _bake_face_async(c, mat) -> void:
	if face_baker == null:
		return
	var tex = await face_baker.bake(c)
	if tex != null and is_instance_valid(mat):
		mat.albedo_texture = tex
		mat.albedo_color = Color(1, 1, 1)   # 贴图就位后取消占位底色，否则会乘暗

func _place_face3d(c, bp: Vector2, idx: int, dragging: bool) -> void:
	_ensure_face3d(c)
	var pivot = c.face3d
	if pivot == null or not is_instance_valid(pivot):
		return
	var w := board_to_world(bp + Vector2(CW * 0.5, CH * 0.5))
	var lift := float(idx) * CARD3D_STACK_DY
	if c.carried or dragging:
		lift += 0.32          # 拿起：抬得更高（阴影随之拉开）
	elif c.hovered:
		lift += 0.06          # hover：轻轻上抬（不变色，仅靠抬升+阴影反馈）
	w.y = CARD_PLANE_Y + lift
	pivot.transform = Transform3D(Basis.IDENTITY, w)

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
		return 22.0
	if c.hovered:
		# 叠放中（栈里不止一张）不再有 hover 抬升
		if stacks.has(c.stack_id) and stacks[c.stack_id].size() > 1:
			return 0.0
		return 10.0
	return 0.0

func _cash_card_count() -> int:
	var n := 0
	for c in all_cards:
		if c.card_id == "cash":
			n += 1
	return n

func _sync_cash_state() -> void:
	if GameState.dev_mode:
		GameState.cash = GameState.dev_base_cash + _cash_card_count()
	else:
		GameState.cash = _cash_card_count()

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
	if need > 0 and GameState.dev_mode:
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
		_merge(c.stack_id, sid)   # 并入同一摞
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

# remove from game logic, then play a "disintegrate into ash" animation
func _dissolve_node(c) -> void:
	var sid: int = c.stack_id
	if stacks.has(sid):
		stacks[sid].erase(c)
		if stacks[sid].is_empty():
			stacks.erase(sid)
			stack_base.erase(sid)
			productions.erase(sid)
	all_cards.erase(c)
	_ash_burst(c.global_position + Vector2(CW * 0.5, CH * 0.5))
	c.z_index = 2500
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "scale", c.scale * 0.05, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "modulate", Color(0.5, 0.5, 0.5, 0.0), 0.45)
	tw.tween_property(c, "rotation", 0.5, 0.45)
	tw.tween_property(c, "position:y", c.position.y - 30, 0.45)
	tw.chain().tween_callback(c.queue_free)
	# 3D 网格同步：缩没 + 上飘
	var mesh := _face3d_mesh(c)
	if mesh != null and is_instance_valid(c.face3d):
		var tw3 := create_tween()
		tw3.set_parallel(true)
		tw3.tween_property(mesh, "scale", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw3.tween_property(c.face3d, "position:y", c.face3d.position.y + 0.3, 0.4)

func _ash_burst(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	add_child(p)
	p.position = pos
	p.z_index = 2400
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 26
	p.lifetime = 0.9
	p.direction = Vector2(0, -1)
	p.spread = 180
	p.initial_velocity_min = 40
	p.initial_velocity_max = 130
	p.gravity = Vector2(0, -30)
	p.damping_min = 20
	p.damping_max = 40
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = Color(0.62, 0.62, 0.6, 0.9)
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)

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
				var picked := _topmost_at(wp)
				if battle_active:
					picked = null            # 战斗中卡牌不可拖动
				if picked != null:
					_begin_drag(wp, picked)          # 点击即拿起并跟随光标（sticky）
					press_pos = wp
					press_moved = false
				else:
					_deselect()
					panning_canvas = true
					pan_last = wp
					Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
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
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# 右键：在卡牌当前所在地放下，并取消选取与拖拽
		if not drag_cards.is_empty():
			_cancel_drag()
		_deselect()
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
	if battle_active:
		return                       # 战斗中卡牌不可拖动
	if picked == null:
		picked = _topmost_at(wp)
		if picked == null:
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

func _end_drag(_wp: Vector2) -> void:
	if drag_cards.is_empty():
		return
	var sid := drag_sid
	var bottom = stacks[sid][0]
	var lead_person := is_person(bottom)
	var center: Vector2 = stack_base[sid] + Vector2(CW * 0.5, CH * 0.5)   # board space

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
		var dropped := region_of(center)
		if bottom.zone != "" and dropped != bottom.zone:
			_show_toast("资源不能跨区，只有人能搬运")
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

# 右键取消：把拖拽中的栈放到它“当前显示位置”（夹回合法区），不触发出售/折叠。
func _cancel_drag() -> void:
	var sid := drag_sid
	if not stacks.has(sid):
		_clear_drag()
		return
	var bottom = stacks[sid][0]
	# 顶牌当前显示位置反推 board 坐标 = 现卡牌所在地
	var board_pos := _unproject(bottom.position)
	var center := board_pos + Vector2(CW * 0.5, CH * 0.5)
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
			return "「%s · 员工　月薪 $%d　产能 %d — 叠到资源或节点上即可开始生产」" % [
				nm, int(d.get("salary", 0)), int(d.get("capacity", 0))]
		"resource_node":
			var us := ("剩余 %d 次" % c.uses_left) if c.uses_left >= 0 else "可无限使用"
			return "「%s · 资源节点　%s — 派员工叠上去产出」" % [nm, us]
		"resource", "customer", "product":
			return "「%s · %s　价值 $%d — 拖到右上『在市场上出售』变现」" % [
				nm, String(CODEX_TYPE.get(c.ctype, "资源")), int(d.get("value", 0))]
		"facility":
			if c.card_id == "business_school":
				return "「%s · 设施　员工在其上工作会累积洞察值，满值随机解锁当前阶段 idea」" % nm
			return "「%s · 设施　提供加成」" % nm
		"department":
			return "「%s · 部门　%d 人　月薪 $%d — 自动持续产出」" % [nm, int(d.get("capacity", 0)), int(d.get("salary", 0))]
		"risk":
			return "「%s · 风险　拖员工上去处理，否则持续造成损失」" % nm
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
	var x := maxf(24.0, (BASE_W - total) * 0.5)
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
	if bank_button != null and is_instance_valid(bank_button):
		bank_button.queue_redraw()

func _set_drag_cards_carried(v: bool) -> void:
	for c in drag_cards:
		if is_instance_valid(c):
			c.set_carried(v)

func _merge(from_sid: int, to_sid: int) -> void:
	var moving: Array = stacks[from_sid]
	var dest: Array = stacks[to_sid]
	for c in moving:
		c.stack_id = to_sid
		dest.append(c)
	stacks.erase(from_sid)
	stack_base.erase(from_sid)
	productions.erase(from_sid)
	productions.erase(to_sid)
	relayout(to_sid)
	evaluate_stack(to_sid)

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
		_merge(sid, target.stack_id)
		return target.stack_id
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
		var isz := 39.0   # 资金图标放大 30%
		var mx := 30.0    # 左右边距（呼吸感）
		var my := 22.0    # 上边距（呼吸感）
		# 左上：图标 + 数字
		if battle_hp_label_left != null:
			battle_hp_label_left.text = "%.1f" % maxf(battle_hp_shown_left, 0.0)
			if battle_hp_icon_left != null:
				battle_hp_icon_left.size = Vector2(isz, isz)
				battle_hp_icon_left.position = rect.position + Vector2(mx, my + 2)
			battle_hp_label_left.position = rect.position + Vector2(mx + isz + 4, my)
		# 右上：图标 + 数字（整组右对齐到框右上角）
		if battle_hp_label_right != null:
			var txt := "%.1f" % maxf(battle_hp_shown_right, 0.0)
			battle_hp_label_right.text = txt
			var fnt := battle_hp_label_right.get_theme_font("font")
			var tw := 80.0
			if fnt != null:
				tw = fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
			var gx := rect.end.x - mx - (isz + 4.0 + tw)
			if battle_hp_icon_right != null:
				battle_hp_icon_right.size = Vector2(isz, isz)
				battle_hp_icon_right.position = Vector2(gx, rect.position.y + my + 2)
			battle_hp_label_right.position = Vector2(gx + isz + 4.0, rect.position.y + my)
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

func _start_battle(rival, employee, rival_first: bool = true) -> void:
	battle_active = true
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
	var bx0 := battle_center.x - 2.0 * CW
	var bx1 := battle_center.x + 2.0 * CW
	var by0 := battle_center.y - CH
	var by1 := battle_center.y + CH
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
		lbl.size = Vector2(190, 46)
		_apply_bold_pixel_font(lbl, 34)   # 放大 30% + 加粗
		lbl.add_theme_color_override("font_color", Color("2b2926"))
		lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
		lbl.add_theme_constant_override("outline_size", 7)
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

# 一次攻击全过程约 3 秒：移上去(1s) → 扣血+跳数字(1s) → 移回(1s)
func _battle_attack(rival_attacking: bool) -> void:
	var attacker = battle_rival if rival_attacking else battle_employee
	var defender = battle_employee if rival_attacking else battle_rival
	if not (is_instance_valid(attacker) and is_instance_valid(defender)):
		return
	var asid: int = attacker.stack_id
	var dsid: int = defender.stack_id
	if not (stacks.has(asid) and stacks.has(dsid)):
		return
	var orig: Vector2 = stack_base[asid]
	var dest: Vector2 = stack_base[dsid]
	# 不完全重叠：随机重叠 30%~50%（两卡相隔一张卡，故 lerp 系数 = 0.5 + 0.5×重叠比）
	var overlap := GameState.rng.randf_range(0.3, 0.5)
	var hit_pos := orig.lerp(dest, 0.5 + 0.5 * overlap)
	# 攻击力 = 攻击方产能 ±30%
	var cap := float(int(attacker.cdef.get("capacity", 0)))
	var power: float = maxf(0.1, cap * GameState.rng.randf_range(0.7, 1.3))
	# 攻击方置顶
	battle_attacker_sid = asid
	relayout(asid)
	# 移到被攻击卡上（0.7s）
	var t1 := create_tween()
	t1.tween_method(_dodge_apply.bind(asid), orig, hit_pos, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t1.finished
	if not battle_active:
		return
	# 扣血 + 伤害数字跳出（1.2s）
	_battle_apply_damage(rival_attacking, power)
	if is_instance_valid(defender):
		_battle_damage_popup(defender, power)
	await get_tree().create_timer(1.2).timeout
	if not battle_active:
		return
	# 移回原位（0.7s）
	if stacks.has(asid):
		var t2 := create_tween()
		t2.tween_method(_dodge_apply.bind(asid), stack_base[asid], orig, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await t2.finished
	# 取消置顶
	battle_attacker_sid = -1
	if stacks.has(asid):
		relayout(asid)

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
	_apply_bold_pixel_font(lbl, 26)
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

# ---- 战斗装饰 3D：边框 / VS / HP 数字都躺在白板上 ----
func _build_battle3d() -> void:
	_clear_battle3d()
	if city_bg == null or city_bg.world_card_root() == null:
		return
	battle3d = Node3D.new()
	city_bg.world_card_root().add_child(battle3d)
	var cw := board_to_world(battle_center)
	var y := CARD_PLANE_Y + 0.03
	var hw := 2.0 * CW / CITY_CELL
	var hd := CH / CITY_CELL
	var t := 0.06
	var red := Color("ef6a6a")
	_battle_box(Vector3(cw.x, y, cw.z - hd), Vector3(2.0 * hw + t, 0.05, t), red)
	_battle_box(Vector3(cw.x, y, cw.z + hd), Vector3(2.0 * hw + t, 0.05, t), red)
	_battle_box(Vector3(cw.x - hw, y, cw.z), Vector3(t, 0.05, 2.0 * hd), red)
	_battle_box(Vector3(cw.x + hw, y, cw.z), Vector3(t, 0.05, 2.0 * hd), red)
	var tex := _versus_texture()
	if tex != null:
		var m := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.5, 1.5)
		m.mesh = qm
		m.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
		m.position = Vector3(cw.x, y + 0.02, cw.z)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_texture = tex
		mat.albedo_color = Color(1, 1, 1, 0.7)
		m.material_override = mat
		battle3d.add_child(m)
	battle_hp3d_left = _battle_label3d(board_to_world(Vector2(battle_center.x - 1.6 * CW, battle_center.y - CH * 0.7)))
	battle_hp3d_right = _battle_label3d(board_to_world(Vector2(battle_center.x + 0.6 * CW, battle_center.y - CH * 0.7)))

func _battle_box(pos: Vector3, size: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	m.material_override = _unshaded_mat(col)
	battle3d.add_child(m)

func _battle_label3d(pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font = _ui_font()
	l.font_size = 64
	l.pixel_size = 0.006
	l.modulate = Color("2b2926")
	l.outline_modulate = Color(1, 1, 1, 0.9)
	l.outline_size = 12
	l.double_sided = true
	l.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	pos.y = CARD_PLANE_Y + 0.06
	l.position = pos
	battle3d.add_child(l)
	return l

func _update_battle3d() -> void:
	if battle3d == null or not is_instance_valid(battle3d):
		return
	if battle_hp3d_left != null:
		battle_hp3d_left.text = "$%.0f" % maxf(battle_hp_shown_left, 0.0)
	if battle_hp3d_right != null:
		battle_hp3d_right.text = "$%.0f" % maxf(battle_hp_shown_right, 0.0)

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
	return battle_versus_tex

func _battle_bubble_texture() -> Texture2D:
	if battle_bubble_tex != null:
		return battle_bubble_tex
	var path := "res://assets/battle-bubble.svg"
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_svg_from_string(FileAccess.get_file_as_string(path), 4.0) == OK:
			battle_bubble_tex = ImageTexture.create_from_image(img)
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
			_set_stack_workbar(sid, clampf(target.work_elapsed / float(basic_recipe.get("duration", 3.0)), 0, 1))
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
				_set_stack_workbar(sid, clampf(target.work_elapsed / float(recipe.get("duration", 4.0)), 0, 1))
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

# 进度条显示在牌堆【最底下那张】（=arr[0]，叠放时被上面的牌覆盖、只露 header、位于画面最上方）
# 的 header 上方；进度仍累加在被工作对象(target.work_elapsed)上
func _set_stack_workbar(sid: int, ratio: float) -> void:
	if not stacks.has(sid):
		return
	var arr: Array = stacks[sid]
	for i in arr.size():
		arr[i].set_work(ratio if i == 0 else 0.0)

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
				destroy_card(c)
				need -= 1
	var made_card := false
	for outp in rec.get("outputs", []):
		if outp.has("cash"):
			var amt := _cash_output_amount(rec, int(outp["cash"]) * mult)
			_spawn_cash_cards(amt, base, "office")
			GameState.add_revenue(amt)
			_ka_ching(base, amt)
		elif outp.has("id"):
			var n := int(outp.get("count", 1)) * mult
			var oid := String(outp["id"])
			if oid == "cash":
				# 产品 + 客户成交时，现金按 value 公式动态计算；其它现金产物按配方数量。
				# 依次快速跳出现金卡（_spawn_cash_cards 内已带 0.04s 逐张弹出 + 同步资金）
				var cash_n := _cash_output_amount(rec, int(outp.get("count", 1)))
				_spawn_cash_cards(cash_n, base, "office")
				GameState.add_revenue(cash_n)
				_ka_ching(base, cash_n)
				made_card = true
			else:
				var forced := String(rec.get("output_zone", ""))
				var zone := forced if forced != "" else _zone_for_center(base + Vector2(CW * 0.5, CH * 0.5))
				var origin := base
				if forced == "market":
					origin = Vector2(1080, 360)
				elif forced == "office":
					origin = Vector2(240, 360)
				for i in n:
					_drop_output(oid, origin, zone)
				made_card = true
	if made_card:
		_wiggle_top_card(sid)            # 产出时生产堆顶卡轻微扭动
	_consume_node_uses(sid, rec)
	GameState.discover(String(rec.get("id", "")))
	if is_instance_valid(target):       # 完成后重置被工作对象的进度（若未被消耗销毁）
		target.work_elapsed = 0.0
		target.set_work(0.0)
	_set_stack_workbar(sid, 0.0)        # 清掉最下一张上的进度条
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
				c.queue_redraw()
				if c.uses_left <= 0:
					_show_toast(String(c.cdef.get("name", rid)) + " 已耗尽")
					_dissolve_node(c)
				break

# 产能 -> 产出倍率：能力越强一次产出越多（边际递减）
func _output_mult(cap: int) -> int:
	return 1 + int(floor(maxf(0, cap - 3) / 4.0))

func _drop_output(id: String, from_pos: Vector2, zone: String) -> void:
	const DROP_MIN := 160.0
	const DROP_MAX := 340.0
	const GROUP_RANGE := 200.0
	var ang := GameState.rng.randf() * TAU
	var dist := GameState.rng.randf_range(DROP_MIN, DROP_MAX)
	var landing := clamp_to_zone(from_pos + Vector2(cos(ang), sin(ang)) * dist, zone)
	var best = null
	var best_d := GROUP_RANGE
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
	_fly_out_card(nc, _project(from_pos + Vector2(CW * 0.5, CH * 0.5)))

# 产出卡顺滑飞出：从生产堆中心放大着滑到落点（无回弹，cubic 缓出）
func _fly_out_card(c, from_display: Vector2) -> void:
	if not is_instance_valid(c):
		return
	var final_pos: Vector2 = c.position
	var final_scale: Vector2 = c.scale
	c.position = from_display - Vector2(CW, CH) * 0.32 * maxf(view_zoom, 0.1)
	c.scale = final_scale * 0.32
	c.rotation = GameState.rng.randf_range(-0.05, 0.05)
	var old_z: int = c.z_index
	c.z_index = max(old_z, 2300)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "position", final_pos, 0.46).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", final_scale, 0.46).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", 0.0, 0.40).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func():
		if is_instance_valid(c):
			c.z_index = old_z
			relayout(c.stack_id)
	)

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
		_set_stack_workbar(sid, clampf(target.work_elapsed / dur, 0, 1))   # 进度条显示在最下一张
		if target.work_elapsed >= dur:
			_complete_production(sid)
	_update_research(delta)
	_update_business_school(delta)
	_update_departments(delta)
	_update_auto_sell(delta)
	_update_drag_spring(delta)
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
		fill.position.x = -CARD3D_W * 0.5 + CARD3D_W * r * 0.5   # 左对齐生长

func _make_workbar3d(c) -> Node3D:
	if not is_instance_valid(c.face3d):
		return null
	var bar := Node3D.new()
	bar.position = Vector3(0, 0.03, -(CARD3D_H * 0.5 + 0.06))   # 卡顶（北）外侧
	var flat := Basis.from_euler(Vector3(deg_to_rad(-90.0), 0, 0))
	var bg := MeshInstance3D.new()
	var bgm := QuadMesh.new()
	bgm.size = Vector2(CARD3D_W, 0.085)
	bg.mesh = bgm
	bg.transform = Transform3D(flat, Vector3.ZERO)
	bg.material_override = _unshaded_mat(Color("2a2824"))
	bar.add_child(bg)
	var fill := MeshInstance3D.new()
	var fm := QuadMesh.new()
	fm.size = Vector2(CARD3D_W, 0.06)
	fill.mesh = fm
	fill.transform = Transform3D(flat, Vector3(0, 0.001, 0))
	fill.material_override = _unshaded_mat(Color("8fcf6e"))
	bar.add_child(fill)
	c.face3d.add_child(bar)
	return bar

func _unshaded_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m

func _update_card_visual_states(delta: float) -> void:
	dash_phase += delta * 35.0
	if bank_button != null and is_instance_valid(bank_button) and _is_dragging_sellable():
		bank_button.queue_redraw()
	var mouse_pos := get_viewport().get_mouse_position()
	var next_hover = null
	if drag_cards.is_empty() and not panning_canvas:
		next_hover = _topmost_at(mouse_pos, true)   # 对手卡虽不可拾取，悬停仍显示信息
	if next_hover != hover_card:
		if is_instance_valid(hover_card):
			hover_card.set_hovered(false)
			relayout(hover_card.stack_id)
		hover_card = next_hover
		if is_instance_valid(hover_card):
			hover_card.set_hovered(true)
			relayout(hover_card.stack_id)

	var hint_sids: Dictionary = {}
	if drag_sid != -1 and stacks.has(drag_sid):
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
	if not drag_cards.is_empty():
		_set_cursor_state("drag")
		return
	var p := get_viewport().get_mouse_position()
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

func _spawn_loose_pack(pack_id: String, pack: Dictionary, contents: Array, landing_override = null) -> Node2D:
	var p = PackCardScript.new()
	add_child(p)
	p.setup(pack_id, String(pack.get("name", "卡包")), contents)
	p.z_index = 2100
	var start := _pack_button_start(pack_id)
	p.position = start
	p.scale = Vector2(0.35, 0.35) * view_zoom
	loose_packs.append(p)
	p.board_pos = (landing_override as Vector2) if landing_override != null else _pack_landing_below(pack_id)
	var landing := _project(p.board_pos)

	# 甩出方向：朝落点行进方向旋转
	var dir := signf(landing.x - start.x)
	if dir == 0.0:
		dir = 1.0 if GameState.rng.randf() < 0.5 else -1.0
	p.rotation = -dir * 0.28        # 反向蓄势微仰

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "position", landing, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "scale", Vector2.ONE * view_zoom, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func(): p.ready_to_open = true)

	# 旋转独立并行：先向行进方向甩转过冲，再弹性回摆稳定（纺锤造型甩动感）
	var settle := GameState.rng.randf_range(-0.07, 0.07)
	var rt := create_tween()
	rt.tween_property(p, "rotation", dir * GameState.rng.randf_range(0.45, 0.62), 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_property(p, "rotation", settle, 0.42) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return p

func _pack_button_start(pack_id: String) -> Vector2:
	# Spawn the loose pack centered on its UI button. The card is created at
	# 0.35 * view_zoom scale and draws from its top-left origin, so offset by
	# the *scaled* half-size (not the full size) to keep it on the button.
	var spawn_scale := 0.35 * view_zoom
	for row in pack_buttons:
		if String(row["id"]) == pack_id:
			var btn: Button = row["btn"]
			return btn.global_position + btn.size * 0.5 \
				- Vector2(PackCardScript.W, PackCardScript.H) * 0.5 * spawn_scale
	return Vector2(520, 80)

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
				bcx + jitter - PackCardScript.W * 0.5 * view_zoom,
				btn.global_position.y + btn.size.y + drop
			)
			var bp := _unproject(target)
			bp.y = clampf(bp.y, MID_Y0 + 8.0, MID_Y1 - PackCardScript.H)
			return bp
	return _random_pack_landing()

func _relayout_loose_packs() -> void:
	for p in loose_packs:
		if not is_instance_valid(p) or p.opened or not p.ready_to_open:
			continue
		p.position = _project(p.board_pos)        # 旧 2D 位置仍设（开包原点等读它）
		p.scale = Vector2.ONE * view_zoom
		p.visible = false                          # 2D 隐藏，改用 3D 网格
		_place_pack3d(p)

# ---- 卡包 3D 网格（与卡牌同套：pivot + mesh，躺在白板上）----
func _ensure_pack3d(p) -> void:
	if p.face3d != null and is_instance_valid(p.face3d):
		return
	if city_bg == null or city_bg.world_card_root() == null:
		return
	var pivot := Node3D.new()
	var m := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(PackCardScript.W / CITY_CELL, PackCardScript.H / CITY_CELL)
	m.mesh = qm
	m.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR   # 不透明部分能投射阴影
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pivot.add_child(m)
	city_bg.world_card_root().add_child(pivot)
	p.face3d = pivot
	p.tree_exited.connect(func():
		if is_instance_valid(pivot):
			pivot.queue_free())
	_bake_pack_async(p, mat)
	m.scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(m, "scale", Vector3.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _bake_pack_async(p, mat) -> void:
	if face_baker == null:
		return
	var tex = await face_baker.bake_pack(p.pack_id, p.pack_name, p.contents)
	if tex != null and is_instance_valid(mat):
		mat.albedo_texture = tex
		mat.albedo_color = Color(1, 1, 1)   # 贴图就位后取消占位深色，否则白图标/名字被乘暗

func _place_pack3d(p) -> void:
	_ensure_pack3d(p)
	var pivot = p.face3d
	if pivot == null or not is_instance_valid(pivot):
		return
	var w := board_to_world(p.board_pos + Vector2(PackCardScript.W * 0.5, PackCardScript.H * 0.5))
	w.y = CARD_PLANE_Y + 0.02
	if p == drag_pack:
		w.y += 0.2
	pivot.transform = Transform3D(Basis.IDENTITY, w)

func _topmost_pack_at(display_pt: Vector2):
	var bpt := _unproject(display_pt)
	var best = null
	var best_key := -INF
	for p in loose_packs:
		if not is_instance_valid(p) or p.opened or not p.ready_to_open:
			continue
		var bp: Vector2 = p.board_pos
		if bpt.x >= bp.x and bpt.x <= bp.x + PackCardScript.W and bpt.y >= bp.y and bpt.y <= bp.y + PackCardScript.H:
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
		tw.tween_property(p, "scale", Vector2(1.14, 0.86) * view_zoom, 0.08).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(p, "scale", Vector2.ONE * view_zoom, 0.14).set_trans(Tween.TRANS_BACK)

func _dissolve_pack(p) -> void:
	if not is_instance_valid(p):
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "scale", Vector2(1.1, 0.55) * view_zoom, 0.14).set_trans(Tween.TRANS_QUAD)
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

# 从 origin_board 朝四周随机撒一张牌的落点，尽量不与已有牌堆重叠（多次试探取最空的）
func _scatter_landing(origin_board: Vector2, zone: String, dist_mult: float = 1.0) -> Vector2:
	var clear := Vector2(CW * 0.92, CH * 0.7)   # 认为"不重叠"所需的最小间距
	var best := Vector2.ZERO
	var best_gap := -INF
	for attempt in range(14):
		var ang := GameState.rng.randf_range(-0.25 * PI, 1.15 * PI)
		var dist := GameState.rng.randf_range(170.0, 430.0) * dist_mult
		var cand := clamp_to_zone(origin_board + Vector2(cos(ang), sin(ang)) * dist, zone)
		var nearest := INF
		for sb in stack_base.values():
			var dx: float = absf(sb.x - cand.x) / clear.x
			var dy: float = absf(sb.y - cand.y) / clear.y
			nearest = minf(nearest, maxf(dx, dy))   # <1 表示重叠
		if nearest >= 1.0:
			return cand                              # 找到不重叠的点，直接用
		if nearest > best_gap:
			best_gap = nearest
			best = cand
	return best                                       # 都挤，退而求其次取最空的

func _burst_card_from_pack(id: String, origin_display: Vector2, zone: String) -> void:
	if id == "founder" and _founder_on_board() != null:
		return
	if _is_business_model_card(id):
		GameState.unlock_business_model(DataLoader.business_model_recipe_id(id))
		_refresh_recipe_book()
	var origin_board := _unproject(origin_display) - Vector2(CW, CH) * 0.5
	# 对手卡跳出距离翻倍
	var is_rival := String(DataLoader.cards.get(id, {}).get("type", "")) == "rival"
	var landing := _scatter_landing(origin_board, zone, 2.0 if is_rival else 1.0)
	var c := spawn_card(id, landing)
	if c == null:
		return
	c.zone = zone
	_play_card_pop(c, 0.0, origin_display)
	var sid: int = c.stack_id
	get_tree().create_timer(0.38).timeout.connect(func():
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
		btn.disabled = locked
		_style_pack_button(btn, String(pack.get("name", "")), int(pack.get("price", 0)), locked)

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
	_float_text("+$" + str(amount), board_pos + Vector2(20, -10), Color("ffe66d"))

func _float_text(txt: String, board_pos: Vector2, col: Color) -> void:
	var pos := _project(board_pos)
	_float_text_screen(txt, pos, col)

func _float_text_screen(txt: String, pos: Vector2, col: Color) -> void:
	var l := Label.new()
	l.text = txt
	l.position = pos
	l.z_index = 2001
	_apply_pixel_font(l, 18)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position", pos + Vector2(0, -46), 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9)
	tw.chain().tween_callback(l.queue_free)

func _float_cost(amount: int, board_pos: Vector2) -> void:
	const CARD_BADGE_SIZE := 36.0
	const CARD_BADGE_FONT_SIZE := 17
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
	tw.tween_property(group, "position", group.position + Vector2(0, -34.0 * view_zoom), 0.95)
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
		if not FileAccess.file_exists(path):
			continue
		var ff := FontFile.new()
		ff.load_dynamic_font(path)
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
	top_bar.size = Vector2(BASE_W, HUD_H)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := top_bar.get_node_or_null("TopBarBg") as ColorRect
	if bg != null:
		bg.size = Vector2(BASE_W, HUD_H)
	var line := top_bar.get_node_or_null("TopBarLine") as ColorRect
	if line != null:
		line.position = Vector2(0, HUD_H - 2.0)
		line.size = Vector2(BASE_W, 2.0)

	return top_bar

func _clear_legacy_top_nodes() -> void:
	for n in [
		"StatusIcon", "RPIcon", "BusinessIcon", "FinanceIcon", "ExpenseIcon", "ValuationIcon",
		"StatusLabel", "RPLabel", "BusinessLabel", "FinanceLabel", "ExpenseLabel", "ValuationLabel",
		"MonthProgressFill"]:
		var node := hud.get_node_or_null(n)
		if node != null:
			node.queue_free()

func _top_stat_label(group_name: String, icon_name: String, x: float, w: float, icon_size: float = TOP_ICON_SIZE) -> Label:
	var group := top_bar.get_node_or_null(group_name) as Control
	if group == null:
		group = Control.new()
		group.name = group_name
		group.position = Vector2(x, 0)
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_bar.add_child(group)
	group.size = Vector2(w, HUD_H)

	var icon := group.get_node_or_null("Icon") as TextureRect
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
		label.size = Vector2(w - icon_size - 12, 40)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(label)
	label.position = Vector2(icon_size + 12, _top_label_y())
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
	lbl_top_rp = _top_stat_label("RPGroup", "streamline/icon_rp", 1150, 130)

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
		month_progress_slot.position = Vector2(0, (HUD_H - 24.0) * 0.5)
		month_progress_slot.size = Vector2(270, 24)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("8d8d8d")
		sb.corner_radius_top_left = 5
		sb.corner_radius_top_right = 5
		sb.corner_radius_bottom_left = 5
		sb.corner_radius_bottom_right = 5
		month_progress_slot.add_theme_stylebox_override("panel", sb)

	month_progress = progress_group.get_node_or_null("MonthProgressFill") as Panel
	if month_progress == null:
		month_progress = Panel.new()
		month_progress.name = "MonthProgressFill"
		month_progress.position = Vector2(0, (HUD_H - 24.0) * 0.5)
		month_progress.size = Vector2(270, 24)
		progress_group.add_child(month_progress)
	else:
		month_progress.position = Vector2(0, (HUD_H - 24.0) * 0.5)
		month_progress.size = Vector2(270, 24)

	var sb_fill := StyleBoxFlat.new()
	sb_fill.bg_color = Color("141414")
	sb_fill.corner_radius_top_left = 5
	sb_fill.corner_radius_top_right = 5
	sb_fill.corner_radius_bottom_left = 5
	sb_fill.corner_radius_bottom_right = 5
	month_progress.add_theme_stylebox_override("panel", sb_fill)

	month_progress_full_width = 270.0
	month_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE

	lbl_business = _top_stat_label("BusinessGroup", "streamline/icon_business", 1280, 170)
	lbl_finance = _top_stat_label("FinanceGroup", "streamline/icon_cash", 1450, 170, TOP_ICON_SIZE * 1.4)
	lbl_expense = _top_stat_label("ExpenseGroup", "streamline/icon_expense", 960, 190, TOP_ICON_SIZE * 1.4)
	lbl_expense.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl_expense.mouse_entered.connect(_on_expense_hover)
	lbl_expense.mouse_exited.connect(_hide_hover)
	lbl_val = _top_stat_label("ValuationGroup", "streamline/icon_valuation", 1620, 200)

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
	rbtn.size = Vector2(154, TOOLBAR_BUTTON_H)
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
	_apply_pixel_font(book_btn, 20)
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
	_apply_pixel_font(task_btn, 20)
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

func _zoom_view_center(factor: float) -> void:
	# 以播放区中心为锚点缩放视角
	_zoom_view_at(Vector2(BASE_W * 0.5, (HUD_H + INFO_Y) * 0.5), factor)

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
	# 与按钮一致的投影
	psb.shadow_color = Color(0, 0, 0, 0.28)
	psb.shadow_size = 4
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
	var tab_top := INFO_Y - 88.0     # 按钮顶边
	var tab_bot := INFO_Y - 24.0     # 按钮底边（position.y 928 + 高 64）
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
	book_tab_seam.draw_polyline(path, INK, w, true)

# 打开/合上「商业模式」按钮自身边框：打开时整框关闭，轮廓交由 seam 一体绘制
func _set_book_tab_open(open: bool) -> void:
	if book_btn == null:
		return
	var bw := 0 if open else 4
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := book_btn.get_theme_stylebox(state) as StyleBoxFlat
		if sb != null:
			sb.border_width_left = bw
			sb.border_width_right = bw
			sb.border_width_top = bw
			sb.border_width_bottom = bw

func _toggle_recipe_book() -> void:
	if recipe_panel == null:
		return
	recipe_panel.visible = not recipe_panel.visible
	_set_book_tab_open(recipe_panel.visible)
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
	panel.position = Vector2(BASE_W * 0.5 - 180, 300)
	panel.size = Vector2(360, 0)
	gear_menu.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "菜单"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_pixel_font(title, 30)
	title.add_theme_color_override("font_color", INK)
	box.add_child(title)

	var items := [
		{"t": "继续", "c": Color("aecbe0"), "f": Callable(self, "_gear_continue")},
		{"t": "重新开始", "c": Color("dcc9a6"), "f": Callable(self, "_gear_restart")},
		{"t": "图鉴", "c": Color("b9d6c2"), "f": Callable(self, "_gear_codex")},
		{"t": "商业模式", "c": Color("c2b6d6"), "f": Callable(self, "_gear_recipes")},
		{"t": "设置", "c": Color("e0c39a"), "f": Callable(self, "_gear_settings")},
		{"t": "回到主菜单", "c": Color("d8b3b0"), "f": Callable(self, "_gear_main_menu")},
	]
	for it in items:
		var b := Button.new()
		b.text = String(it["t"])
		b.custom_minimum_size = Vector2(0, 56)
		_apply_pixel_font(b, 24)
		_style_button(b, it["c"])
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
	var px := minf(codex_panel.position.x + codex_panel.size.x + 26, BASE_W - 220)
	var py := clampf(lbl.global_position.y - 60, 130, BASE_H - 250)
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

	var fs := CheckButton.new()
	fs.text = "全屏"
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_apply_pixel_font(fs, 22)
	fs.add_theme_color_override("font_color", INK)
	fs.toggled.connect(_on_fullscreen_toggled)
	box.add_child(fs)

	var dev := CheckButton.new()
	dev.text = "开发模式"
	dev.button_pressed = GameState.dev_mode
	_apply_pixel_font(dev, 22)
	dev.add_theme_color_override("font_color", INK)
	dev.toggled.connect(_on_dev_mode_toggled)
	box.add_child(dev)

	var todo := Label.new()
	todo.text = "更多选项（音量等）开发中…"
	_apply_pixel_font(todo, 16)
	todo.add_theme_color_override("font_color", Color("777067"))
	box.add_child(todo)

func _toggle_settings() -> void:
	if settings_panel != null:
		settings_panel.visible = not settings_panel.visible

func _on_fullscreen_toggled(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)

func _on_dev_mode_toggled(on: bool) -> void:
	GameState.dev_mode = on
	get_tree().paused = false
	get_tree().reload_current_scene()

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

func _update_hud() -> void:
	if lbl_status == null:
		return
	_sync_cash_state()
	lbl_status.text = "阶段「%s」  第%d月%s" % [
		GameState.stage_name(), GameState.month,
		("   [紧急!]" if emergency else "")]
	if lbl_top_rp:
		lbl_top_rp.text = "RP %d" % int(GameState.rp)
	if month_progress:
		var total := float(DataLoader.balance.get("month_seconds", 90.0))
		var ratio := clampf(month_time / maxf(1.0, total), 0.0, 1.0)
		month_progress.size = Vector2(month_progress_full_width * ratio, month_progress.size.y)
	if lbl_business:
		lbl_business.text = "业务 %d/%d" % [_business_card_count(), _business_card_capacity()]
	if lbl_finance:
		lbl_finance.text = "资金 $%d" % GameState.cash
	if lbl_expense:
		lbl_expense.text = "月运营支出 $%d" % _current_expense()
	if lbl_val:
		lbl_val.text = "估值 $%d" % GameState.valuation
	if research_panel and research_panel.visible:
		_refresh_research()

# ---------------------------------------------------------------- background
func _draw() -> void:
	# 地面 = 3D 城市里的白板（在 CityBackground 渲染），这里不再画 2D 办公室地板/边框/街道。
	_draw_battle_decoration()   # 战斗中：中心 VS 装饰（画在卡牌之下）

	var f := _ui_font()
	# fixed bank slot, outside the zoomable canvas
	if bank_button == null or not is_instance_valid(bank_button):
		draw_rect(BANK_RECT, Color("f3ead7"), true)
		draw_rect(BANK_RECT, Color("d9a552"), false, 3.0)
		draw_string(f, BANK_RECT.position + Vector2(86, 54), "在市场上出售", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("3a352f"))

	# 底部信息栏现绘制在 bottom_info（HUD 层）上，始终置顶，见 _draw_bottom_info()

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
	canvas.draw_string(f, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_CENTER, BASE_W, size, col)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

# 底部信息栏：画在 HUD 层的 bottom_info 节点上，z 高于所有卡牌，始终置顶。
func _draw_bottom_info() -> void:
	if bottom_info == null:
		return
	var f := _ui_font()
	bottom_info.draw_rect(Rect2(0, INFO_Y, BASE_W, BASE_H - INFO_Y), ORG_BG, true)
	bottom_info.draw_line(Vector2(0, INFO_Y), Vector2(BASE_W, INFO_Y), Color(0.23, 0.21, 0.18, 0.5), 2.5)
	var info_y := INFO_Y
	# 悬停优先：鼠标移到卡上即出该卡（或堆叠）信息；移开则恢复选中/默认 hint
	var info_parts := _hover_info_parts()
	if not info_parts.is_empty():
		_draw_info_line(bottom_info, f, info_y + 30, info_parts, Color(0.30, 0.27, 0.23, 0.95), 22)
	else:
		var fresh := toast_t > 0.0
		var hint_col := Color("8a5a26") if fresh else Color(0.36, 0.33, 0.29, 0.92)
		_draw_italic(bottom_info, f, Vector2(0, info_y + 30), hint_text, 22, hint_col)

func _on_business_model_unlocked(recipe_id: String) -> void:
	var bm_name := DataLoader.card_name(DataLoader.business_model_card_id(recipe_id))
	_show_founder_bubble("发现了 %s！" % bm_name)

# Anchor where the speech tail originates: the founder's "mouth",
# upper-right inside the card. Mapped through the card's own transform so it
# tracks the live, projected card position (NOT re-projected from screen space).
func _founder_mouth_screen(founder: Node2D) -> Vector2:
	return founder.to_global(Vector2(CW * 0.70, CH * 0.34))

func _show_founder_bubble(text: String) -> void:
	var founder = _founder_on_board()
	if not is_instance_valid(founder):
		return
		
	if is_instance_valid(founder_bubble):
		founder_bubble.queue_free()
		
	var bubble := PanelContainer.new()
	bubble.name = "FounderSpeechBubble"
	hud.add_child(bubble)
	bubble.z_index = 4090
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(16)
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = Color.BLACK
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	
	# Premium drop shadow for comic effect
	sb.shadow_color = Color(0, 0, 0, 0.15)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(4, 4)
	bubble.add_theme_stylebox_override("panel", sb)
	
	var label := Label.new()
	label.name = "BubbleLabel"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_font_override("font", _ui_font())
	label.add_theme_font_size_override("font_size", 20)
	bubble.add_child(label)
	
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
		var base_w := 26.0
		var lean := 20.0   # how far the base center is pushed right of the tip
		var on_bottom: bool = local_pivot.y > h * 0.5
		var edge_y: float = (h - 2.0) if on_bottom else 2.0
		var base_cx: float = clampf(local_pivot.x + lean, 18.0 + base_w * 0.5, w - 18.0 - base_w * 0.5)
		var pt_b := Vector2(base_cx - base_w * 0.5, edge_y)
		var pt_c := Vector2(base_cx + base_w * 0.5, edge_y)

		# Fill the tail (extend the base a few px into the body so it merges seamlessly).
		var inset: float = 6.0 if on_bottom else -6.0
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
			Vector2(pt_b.x - 1.0, edge_y),
			Vector2(pt_c.x + 1.0, edge_y),
			Color.WHITE, 5.0
		)
		# Comic black outline on the two free edges of the tail only.
		bubble.draw_line(pt_b, pt_a, Color.BLACK, 3.0)
		bubble.draw_line(pt_c, pt_a, Color.BLACK, 3.0)
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

	# Sit the bubble up-and-to-one-side of the mouth so the tail angles back
	# toward the face. Bias toward the open space horizontally.
	var x = 0.0
	if mouth.x > BASE_W * 0.5:
		x = mouth.x - w * 0.78
	else:
		x = mouth.x - w * 0.22

	x = clampf(x, 16.0, BASE_W - w - 16.0)
	var y = mouth.y - h - 22.0
	y = clampf(y, HUD_H + 8.0, BASE_H - h - 8.0)

	bubble.position = Vector2(x, y)

	# Pivot the pop-in animation from the mouth side for a "spoken" feel.
	var local_pivot = mouth - bubble.position
	bubble.pivot_offset = Vector2(clampf(local_pivot.x, 0.0, w), clampf(local_pivot.y, 0.0, h))
	bubble.queue_redraw()
