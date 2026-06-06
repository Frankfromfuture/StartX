extends Node2D
## Zoned board with a shared 1-point perspective projection applied to BOTH the
## background and the cards. All gameplay logic runs in flat "board space";
## rendering projects board space -> display space (top narrower than bottom).

const CardScript = preload("res://scripts/Card.gd")
const PackCardScript = preload("res://scripts/PackCard.gd")
const CARD_SCALE := 1.0               # 卡按 120×180 设计，节点不再额外缩放
const CW := 180.0                     # square card, keeping the old long side
const CH := 180.0
const CARD_OFFSET := 34.0             # 叠放时每张上面的牌再往下一点
const DRAG_Z := 4000

# ---- Layout (board space 1920x1080) ----
const BASE_W := 1920.0
const BASE_H := 1080.0
const HUD_H := 78.0
const DRAW_Y0 := 52.0
const DRAW_Y1 := 160.0          # 抽卡区压扁成一条工具栏（研发|卡包|银行同排）
const MID_Y0 := 160.0           # 画布上边（锚定在 UI 区下方）
const MID_Y1 := 2552.0          # 画布下边（画布区再翻倍：高 1196→2392）
const ORG_Y0 := 2552.0          # 组织/部门折叠区位于画布底部
const INFO_Y := 1016.0          # fixed bottom information strip
const DIVIDER_X := 960.0
const CANVAS_X0 := -1560.0      # 画布左边（以中线 960 为中心对称扩大：宽 2520→5040）
const CANVAS_X1 := 3480.0       # 画布右边
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
var pack_drag_offset: Vector2 = Vector2.ZERO  # board space
var hover_card = null
var cursor_default: Texture2D
var cursor_card_hover: Texture2D
var cursor_card_drag: Texture2D
var cursor_state: String = ""
var dash_phase: float = 0.0

var month_time: float = 0.0

const DEFAULT_HINT := "「拖动『创始人』到资源节点上即可开始生产」"

var hud: CanvasLayer
var top_bar: Control
var lbl_status: Label
var lbl_top_rp: Label
var lbl_finance: Label
var lbl_expense: Label
var lbl_val: Label
var lbl_business: Label
var hover_panel: Panel
var hover_label: Label
var month_progress: ColorRect
var month_progress_full_width: float = 320.0
var bank_button: Button
var pixel_font: Font
var hint_text: String = DEFAULT_HINT
var selected_card = null
var toast_t: float = 0.0
var emergency: bool = false
var emergency_t: float = 0.0
var game_over: bool = false
var dbg_last := Vector2.ZERO
var view_zoom: float = 0.6             # 初始拉远：视野更大、卡片更小
var view_offset: Vector2 = Vector2.ZERO
var panning_canvas: bool = false
var pan_last: Vector2 = Vector2.ZERO
const VIEW_ZOOM_MIN := 0.45
const VIEW_ZOOM_MAX := 1.9
const VIEW_ZOOM_STEP := 1.12

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
var ui_icon_cache: Dictionary = {}

func _ready() -> void:
	GameState.reset()
	canvas_bg_tex = _load_canvas_bg()
	_load_cursors()
	month_time = float(DataLoader.balance.get("month_seconds", 90.0))
	_reset_view_default()               # 初始视角：画布水平居中、顶边锚定
	_build_hud()
	_spawn_start_cards()
	GameState.recipe_discovered.connect(_on_discovery)
	GameState.idea_unlocked.connect(_on_idea_unlocked)
	GameState.stage_changed.connect(_on_stage_changed)

# ---------------------------------------------------------------- perspective
func _row_scale(y: float) -> float:
	var t := clampf((y - MID_Y0) / maxf(1.0, MID_Y1 - MID_Y0), 0.0, 1.0)
	return lerpf(TOP_SCALE, 1.0, t)

func _project(p: Vector2) -> Vector2:
	var s := _row_scale(p.y)
	var flat := Vector2(BASE_W * 0.5 + (p.x - BASE_W * 0.5) * s, p.y)
	return flat * view_zoom + view_offset

func _unproject(d: Vector2) -> Vector2:
	var flat := (d - view_offset) / view_zoom
	var s := _row_scale(flat.y)         # y is unchanged by the projection
	return Vector2(BASE_W * 0.5 + (flat.x - BASE_W * 0.5) / s, flat.y)

func _screen_to_view(p: Vector2) -> Vector2:
	return (p - view_offset) / view_zoom

func _zoom_view_at(screen_pos: Vector2, factor: float) -> void:
	var before := _screen_to_view(screen_pos)
	view_zoom = clampf(view_zoom * factor, VIEW_ZOOM_MIN, VIEW_ZOOM_MAX)
	view_offset = screen_pos - before * view_zoom
	_clamp_view_offset()
	_relayout_all()
	_relayout_loose_packs()
	queue_redraw()

func _reset_view_default() -> void:
	# 水平居中：让画布中线（=屏幕中线 BASE_W*0.5）投影后仍落在屏幕中线
	view_offset.x = BASE_W * 0.5 * (1.0 - view_zoom)
	# 顶边锚定：画布上边 MID_Y0 紧贴 UI 区下方（即 _clamp 的 max_y）
	view_offset.y = MID_Y0 * (1.0 - view_zoom)
	_clamp_view_offset()

func _clamp_view_offset() -> void:
	var min_x := BASE_W - (CANVAS_X1 + VIEW_PAD) * view_zoom
	var max_x := -(CANVAS_X0 - VIEW_PAD) * view_zoom
	var min_y := BASE_H - (MID_Y1 + VIEW_PAD) * view_zoom
	var max_y := MID_Y0 * (1.0 - view_zoom)   # 画布顶边锚定在框顶（UI 区下方），不再向下漂移
	view_offset.x = clampf(view_offset.x, min_x, max_x)
	view_offset.y = clampf(view_offset.y, min_y, max_y)

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
func _load_canvas_bg() -> Texture2D:
	for path in ["res://assets/bg_office.png", "res://assets/bg_canvas.png"]:
		if FileAccess.file_exists(path):
			var img := Image.new()
			if img.load(path) == OK:
				return ImageTexture.create_from_image(img)
	return null

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
	var p = _spawn_loose_pack("garage_pack", pack, contents)
	if is_instance_valid(p):
		p.board_pos = Vector2(BASE_W * 0.5, 560.0)   # 居中靠上

func _spawn_card_pop(id: String, pos: Vector2, delay: float = 0.0) -> Node2D:
	var c := spawn_card(id, pos)
	_play_card_pop(c, delay)
	return c

func spawn_card(id: String, pos: Vector2) -> Node2D:
	if id == "founder" and _founder_on_board() != null:
		return null
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
	var zbase := DRAG_Z if sid == drag_sid else 0
	for i in arr.size():
		var c = arr[i]
		c.stack_pos = i
		var bp := base + Vector2(0, i * CARD_OFFSET)        # board space
		_apply_card_projection(c, bp, sid == drag_sid)
		# 拖拽中：位置由 _update_drag_spring 弹簧驱动（滞后 + 摆动）
		c.z_index = zbase + i
		# 工作条现绑定在【被工作对象】卡上、按 work_ratio 自管，relayout 不再干预

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
	_sync_cash_state()
	return true

func _spawn_cash_cards(amount: int, around: Vector2, zone: String = "office") -> void:
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
	var origin_display := _project(around + Vector2(CW, CH) * 0.5)
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
			elif _bank_rect().has_point(wp):
				_withdraw_cash_from_bank()
				return
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
		view_offset += wp - pan_last
		_clamp_view_offset()
		pan_last = wp
		_relayout_all()
		_relayout_loose_packs()
		queue_redraw()
	elif event is InputEventMouseMotion and drag_pack != null:
		var wp := _to_world(event)
		if is_instance_valid(drag_pack):
			drag_pack.board_pos = _unproject(wp) - pack_drag_offset
			drag_pack.position = _project(drag_pack.board_pos)
			if wp.distance_to(press_pos) > DRAG_TAP_PX:
				press_moved = true
	elif event is InputEventMouseMotion and not drag_cards.is_empty():
		var wp := _to_world(event)
		stack_base[drag_sid] = _unproject(wp) - drag_offset
		relayout(drag_sid)
		if wp.distance_to(press_pos) > DRAG_TAP_PX:
			press_moved = true

func _topmost_at(display_pt: Vector2) -> Node2D:
	var best: Node2D = null
	for c in all_cards:
		if c.ctype == "department":
			continue        # departments are fixtures, not pickable (minimal)
		if c.contains_point(display_pt):
			if best == null or c.z_index > best.z_index:
				best = c
	return best

func _begin_drag(wp: Vector2, picked: Node2D = null) -> void:
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
		_sell_stack(sid)
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

	sid = _resolve_overlap(sid)   # 有互动→并入；无互动→对方平滑躲开

	if stacks.has(sid):
		for c in stacks[sid]:
			if not is_person(c) and not is_fixed(c):
				c.zone = target_zone
	_clear_drag()
	if stacks.has(sid):
		relayout(sid)

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
		"resource":
			return "「%s · 资源　售价 $%d — 拖到右上『银行』变现」" % [nm, int(d.get("sell", 0))]
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
		_:
			return "「%s」" % nm

func _clear_drag() -> void:
	_set_drag_cards_carried(false)
	drag_cards = []
	drag_sid = -1

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

func _sell_stack(sid: int) -> void:
	var arr: Array = stacks[sid].duplicate()
	var total := 0
	var origin: Vector2 = stack_base.get(sid, Vector2(300, 360))
	for c in arr:
		total += int(c.cdef.get("sell", 0))
		destroy_card(c)
	if total > 0:
		_spawn_cash_cards(total, origin, "office")
		_float_text_screen("+$" + str(total), _bank_rect().position + Vector2(60, 0), Color("ffe66d"))
	else:
		_show_toast("这张卡卖不出钱")

func _withdraw_cash_from_bank() -> void:
	_show_toast("资金现在只计算场上的现金卡；银行不再存放隐藏现金")

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
			var amt := int(outp["cash"]) * mult
			_spawn_cash_cards(amt, base, "office")
			GameState.add_revenue(amt)
			_ka_ching(base, amt)
		elif outp.has("id"):
			var n := int(outp.get("count", 1)) * mult
			var oid := String(outp["id"])
			if oid == "cash":
				# 现金作为产物：数量严格 = 配方设定（二者价值相加），不受产能倍率影响
				# 依次快速跳出现金卡（_spawn_cash_cards 内已带 0.04s 逐张弹出 + 同步资金）
				var cash_n := int(outp.get("count", 1))
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

# Loose sellable resource cards in the MARKET (right) zone auto-sell after 1s idle:
# they fly to the sell slot and convert to cash.
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
	var value := int(c.cdef.get("sell", 0))
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

func _update_card_visual_states(delta: float) -> void:
	dash_phase += delta * 35.0
	var mouse_pos := get_viewport().get_mouse_position()
	var next_hover = null
	if drag_cards.is_empty() and not panning_canvas:
		next_hover = _topmost_at(mouse_pos)
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
	var payroll_short := payroll > _cash_card_count()
	if payroll > 0:
		_spend_cash_cards(mini(payroll, _cash_card_count()))
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
		contents.append(_weighted_pick(slots[i]))
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

func _spawn_loose_pack(pack_id: String, pack: Dictionary, contents: Array) -> Node2D:
	var p = PackCardScript.new()
	add_child(p)
	p.setup(pack_id, String(pack.get("name", "卡包")), contents)
	p.z_index = 2100
	var start := _pack_button_start(pack_id)
	p.position = start
	p.scale = Vector2(0.35, 0.35) * view_zoom
	loose_packs.append(p)
	p.board_pos = _random_pack_landing()
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
	for row in pack_buttons:
		if String(row["id"]) == pack_id:
			var btn: Button = row["btn"]
			return btn.position + btn.size * 0.5 - Vector2(PackCardScript.W, PackCardScript.H) * 0.5
	return Vector2(520, 80)

func _random_pack_landing() -> Vector2:
	return Vector2(
		GameState.rng.randf_range(190.0, 760.0),
		GameState.rng.randf_range(198.0, 350.0)
	)

func _relayout_loose_packs() -> void:
	for p in loose_packs:
		if not is_instance_valid(p) or p.opened or not p.ready_to_open:
			continue
		p.position = _project(p.board_pos)
		p.scale = Vector2.ONE * view_zoom

func _topmost_pack_at(display_pt: Vector2):
	var best = null
	for p in loose_packs:
		if not is_instance_valid(p) or p.opened:
			continue
		if p.contains_point(display_pt):
			if best == null or p.z_index > best.z_index:
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
	while id == "founder" and _founder_on_board() != null:
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

# 从 origin_board 朝四周随机撒一张牌的落点，尽量不与已有牌堆重叠（多次试探取最空的）
func _scatter_landing(origin_board: Vector2, zone: String) -> Vector2:
	var clear := Vector2(CW * 0.92, CH * 0.7)   # 认为"不重叠"所需的最小间距
	var best := Vector2.ZERO
	var best_gap := -INF
	for attempt in range(14):
		var ang := GameState.rng.randf_range(-0.25 * PI, 1.15 * PI)
		var dist := GameState.rng.randf_range(170.0, 430.0)
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
	var origin_board := _unproject(origin_display) - Vector2(CW, CH) * 0.5
	var landing := _scatter_landing(origin_board, zone)
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
	_show_toast("📈 公司进入「%s」阶段！解锁新卡包/研发" % GameState.stage_name())
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
		top_bar.size = Vector2(BASE_W, HUD_H)
		hud.add_child(top_bar)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return top_bar

func _clear_legacy_top_nodes() -> void:
	for n in [
		"StatusIcon", "RPIcon", "BusinessIcon", "FinanceIcon", "ExpenseIcon", "ValuationIcon",
		"StatusLabel", "RPLabel", "BusinessLabel", "FinanceLabel", "ExpenseLabel", "ValuationLabel",
		"MonthProgressFill"]:
		var node := hud.get_node_or_null(n)
		if node != null:
			node.queue_free()

func _top_stat_label(group_name: String, icon_name: String, x: float, w: float) -> Label:
	var group := top_bar.get_node_or_null(group_name) as Control
	if group == null:
		group = Control.new()
		group.name = group_name
		group.position = Vector2(x, 0)
		group.size = Vector2(w, HUD_H)
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_bar.add_child(group)

	var icon := group.get_node_or_null("Icon") as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = "Icon"
		icon.position = Vector2(0, _top_icon_y())
		icon.size = Vector2(TOP_ICON_SIZE, TOP_ICON_SIZE)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(icon)
	icon.texture = _ui_icon(icon_name)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var label := group.get_node_or_null("Label") as Label
	if label == null:
		label = Label.new()
		label.name = "Label"
		label.position = Vector2(TOP_ICON_SIZE + 12, _top_label_y())
		label.size = Vector2(w - TOP_ICON_SIZE - 12, 40)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(label)
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
	icon.texture = _ui_icon("cost")
	icon.position = Vector2((size.x - 34.0) * 0.5, 8)
	icon.size = Vector2(34, 34)
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
	cost.text = str(price)
	cost.position = Vector2((size.x - 34.0) * 0.5, 16)
	cost.size = Vector2(34, 18)
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
	label.text = pack_name
	label.position = Vector2(7, 48)
	label.size = Vector2(size.x - 14, 18)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_bold_pixel_font(label, 13)
	label.add_theme_color_override("font_color", Color("f7f2e8") if not locked else Color("9b978f"))

func _build_hud() -> void:
	hud = get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		hud = CanvasLayer.new()
		hud.name = "HUD"
		add_child(hud)

	_ensure_top_bar()
	_clear_legacy_top_nodes()

	lbl_status = _top_stat_label("StageGroup", "streamline/icon_stage", 24, 320)
	lbl_top_rp = _top_stat_label("RPGroup", "streamline/icon_rp", 372, 120)

	var progress_group := top_bar.get_node_or_null("ProgressGroup") as Control
	if progress_group == null:
		progress_group = Control.new()
		progress_group.name = "ProgressGroup"
		progress_group.position = Vector2(520, 0)
		progress_group.size = Vector2(180, HUD_H)
		progress_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_bar.add_child(progress_group)
	month_progress = progress_group.get_node_or_null("MonthProgressFill") as ColorRect
	if month_progress == null:
		month_progress = ColorRect.new()
		month_progress.name = "MonthProgressFill"
		month_progress.color = Color("141414")
		month_progress.position = Vector2(0, (HUD_H - 16.0) * 0.5)
		month_progress.size = Vector2(180, 16)
		progress_group.add_child(month_progress)
	month_progress_full_width = month_progress.size.x
	month_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE

	lbl_business = _top_stat_label("BusinessGroup", "streamline/icon_business", 735, 190)
	lbl_finance = _top_stat_label("FinanceGroup", "streamline/icon_cash", 965, 170)
	lbl_expense = _top_stat_label("ExpenseGroup", "streamline/icon_expense", 1170, 235)
	lbl_expense.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl_expense.mouse_entered.connect(_on_expense_hover)
	lbl_expense.mouse_exited.connect(_hide_hover)
	lbl_val = _top_stat_label("ValuationGroup", "streamline/icon_valuation", 1450, 260)

	var gear_btn := top_bar.get_node_or_null("GearButton") as Button
	if gear_btn == null:
		gear_btn = Button.new()
		gear_btn.name = "GearButton"
		gear_btn.text = ""
		gear_btn.position = Vector2(1844, (HUD_H - 44.0) * 0.5)
		gear_btn.size = Vector2(64, 44)
		top_bar.add_child(gear_btn)
	_apply_pixel_font(gear_btn, 26)
	_style_button(gear_btn, Color("f3ead7"))
	_set_button_icon(gear_btn, "streamline/icon_settings")
	gear_btn.pressed.connect(_toggle_gear_menu)

	var rbtn := hud.get_node_or_null("Buttons/ResearchButton") as Button
	if rbtn == null:
		rbtn = Button.new()
		rbtn.name = "ResearchButton"
		rbtn.position = Vector2(28, _toolbar_y())
		rbtn.size = Vector2(128, TOOLBAR_BUTTON_H)
		hud.add_child(rbtn)
	rbtn.text = "研发"
	_apply_bold_pixel_font(rbtn, 22)
	_style_button(rbtn, Color("6f8793"))
	_set_button_icon(rbtn, "icon_research")
	rbtn.pressed.connect(_toggle_research)

	var book_btn := hud.get_node_or_null("Buttons/RecipeBookButton") as Button
	if book_btn == null:
		book_btn = Button.new()
		book_btn.name = "RecipeBookButton"
		book_btn.text = "配方书"
		book_btn.position = Vector2(30, INFO_Y - 88)
		book_btn.size = Vector2(130, 64)
		hud.add_child(book_btn)
	_apply_pixel_font(book_btn, 20)
	_style_button(book_btn, Color("c2b6d6"))
	book_btn.pressed.connect(_toggle_recipe_book)

	bank_button = hud.get_node_or_null("BankButton") as Button
	if bank_button == null:
		bank_button = Button.new()
		bank_button.name = "BankButton"
		bank_button.position = Vector2(1610, _toolbar_y())
		bank_button.size = Vector2(260, TOOLBAR_BUTTON_H)
		hud.add_child(bank_button)
	bank_button.text = "银行"
	_apply_bold_pixel_font(bank_button, 24)
	_style_button(bank_button, Color("c8a55a"))
	_set_button_icon(bank_button, "icon_bank")
	bank_button.pressed.connect(_withdraw_cash_from_bank)

	var pack_container := hud.get_node_or_null("PackButtons")
	var pack_count := DataLoader.packs.size()
	var pack_w := 120.0
	var pack_gap := 126.0
	var pack_total_w := pack_w + maxf(0.0, pack_count - 1.0) * pack_gap
	var pack_space_x0 := rbtn.position.x + rbtn.size.x + 26.0
	var pack_space_x1 := bank_button.position.x - 26.0
	var px := pack_space_x0 + maxf(0.0, (pack_space_x1 - pack_space_x0 - pack_total_w) * 0.5)
	var pack_i := 0
	for pid in DataLoader.packs.keys():
		var pack: Dictionary = DataLoader.packs[pid]
		var pb: Button = null
		if pack_container != null and pack_i < pack_container.get_child_count():
			pb = pack_container.get_child(pack_i) as Button
		if pb == null:
			pb = Button.new()
			pb.name = "PackButton%d" % (pack_i + 1)
			pb.position = Vector2(px, _toolbar_y())
			pb.size = Vector2(pack_w, TOOLBAR_BUTTON_H)
			if pack_container != null:
				pack_container.add_child(pb)
			else:
				hud.add_child(pb)
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

func _show_hover(text: String, anchor: Control) -> void:
	if hover_panel == null:
		return
	hover_label.text = text
	var rows := text.split("\n").size()
	var w := 460.0
	var h := rows * 26.0 + 16.0
	hover_panel.size = Vector2(w, h)
	hover_label.size = Vector2(w - 24, h - 16)
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
		_show_hover(_pack_hover_text(pid), btn)

func _pack_hover_text(pid: String) -> String:
	var pack: Dictionary = DataLoader.packs.get(pid, {})
	var lines: Array = ["%s（$%d，%d-%d 张）可抽到：" % [
		String(pack.get("name", pid)), int(pack.get("price", 0)),
		int(pack.get("minCards", 3)), int(pack.get("maxCards", 5))]]
	for slot in pack.get("slots", []):
		var total := 0
		for o in slot:
			total += int(o.get("w", 1))
		var parts: Array = []
		for o in slot:
			var nm := DataLoader.card_name(String(o.get("id", "")))
			var pct := int(round(100.0 * float(o.get("w", 1)) / maxf(1.0, total)))
			parts.append("%s %d%%" % [nm, pct])
		lines.append("· " + _join_text(parts, " / "))
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
	var lines: Array = ["月支出构成（薪资）："]
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
	recipe_panel.position = Vector2(180, 238)
	recipe_panel.size = Vector2(620, 720)
	recipe_panel.visible = false
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.98, 0.95, 0.89, 0.97)
	psb.set_corner_radius_all(8)
	psb.border_color = INK
	psb.set_border_width_all(3)
	psb.content_margin_left = 18
	psb.content_margin_right = 18
	psb.content_margin_top = 16
	psb.content_margin_bottom = 16
	recipe_panel.add_theme_stylebox_override("panel", psb)
	hud.add_child(recipe_panel)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "配方书"
	_apply_pixel_font(title, 28)
	title.add_theme_color_override("font_color", INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "关闭"
	close.size = Vector2(90, 42)
	_apply_pixel_font(close, 16)
	_style_button(close, Color("e0c39a"))
	close.pressed.connect(_toggle_recipe_book)
	head.add_child(close)

	recipe_list = RichTextLabel.new()
	recipe_list.bbcode_enabled = true
	recipe_list.fit_content = false
	recipe_list.scroll_active = true
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_list.add_theme_font_override("normal_font", _ui_font())
	recipe_list.add_theme_font_override("bold_font", _ui_font())
	recipe_list.add_theme_font_override("italics_font", _ui_font())
	recipe_list.add_theme_font_size_override("normal_font_size", 18)
	recipe_list.add_theme_color_override("default_color", INK)
	box.add_child(recipe_list)
	_refresh_recipe_book()

func _toggle_recipe_book() -> void:
	if recipe_panel == null:
		return
	recipe_panel.visible = not recipe_panel.visible
	if recipe_panel.visible:
		_refresh_recipe_book()

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
		{"t": "组合", "c": Color("c2b6d6"), "f": Callable(self, "_gear_recipes")},
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
	var order := ["employee", "resource_node", "facility", "resource"]
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
	if int(d.get("sell", 0)) > 0:
		parts.append("售$%d" % int(d["sell"]))
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

func _refresh_recipe_book() -> void:
	if recipe_list == null:
		return
	var lines: Array = []
	lines.append("[color=#5b5145]只显示已解锁配方；已完成的配方会划掉。[/color]\n")
	for recipe in DataLoader.recipes:
		if not _recipe_unlocked(recipe):
			continue
		var done := GameState.discovered.has(String(recipe.get("id", "")))
		var txt := "%s  %s" % [String(recipe.get("name", "")), _recipe_formula(recipe)]
		if done:
			txt = "[s][color=#777067]✓ " + txt + "[/color][/s]"
		else:
			txt = "[color=#2f2a25]• " + txt + "[/color]"
		lines.append(txt)
	if lines.size() == 1:
		lines.append("[color=#777067]暂无已解锁配方。[/color]")
	recipe_list.text = _join_text(lines, "\n")

func _recipe_unlocked(recipe: Dictionary) -> bool:
	var gate := String(recipe.get("requiredIdeaId", ""))
	return gate == "" or GameState.idea_done(gate)

func _recipe_formula(recipe: Dictionary) -> String:
	var parts: Array = []
	var workers := _worker_label(recipe.get("worker_tags", []))
	if workers != "":
		parts.append(workers)
	for inp in recipe.get("inputs", []):
		parts.append(_input_label(inp))
	return "：%s → %s" % [_join_text(parts, " + "), _outputs_label(recipe.get("outputs", []))]

func _input_label(inp: Dictionary) -> String:
	var id := String(inp.get("id", ""))
	var count := int(inp.get("count", 1))
	var s := DataLoader.card_name(id)
	if count > 1:
		s += " x%d" % count
	if not inp.get("consume", false):
		s += "(工作站)"
	return s

func _outputs_label(outputs: Array) -> String:
	var parts: Array = []
	for outp in outputs:
		if outp.has("cash"):
			parts.append("现金 $%d" % int(outp["cash"]))
		elif outp.has("id"):
			var s := DataLoader.card_name(String(outp["id"]))
			var count := int(outp.get("count", 1))
			if count > 1:
				s += " x%d" % count
			parts.append(s)
	return _join_text(parts, " + ")

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
		lbl_expense.text = "月支出 $%d" % _current_expense()
	if lbl_val:
		lbl_val.text = "估值 $%d" % GameState.valuation
	if research_panel and research_panel.visible:
		_refresh_research()

# ---------------------------------------------------------------- background
func _draw() -> void:
	draw_rect(Rect2(0, 0, BASE_W, BASE_H), BG_OUT, true)   # 画布外·压暗，衬托白框
	# 画布纸面（跟随透视斜边的圆角梯形奶白底）
	var cf_quad := [
		_project(Vector2(CANVAS_X0, MID_Y0)), _project(Vector2(CANVAS_X1, MID_Y0)),
		_project(Vector2(CANVAS_X1, MID_Y1)), _project(Vector2(CANVAS_X0, MID_Y1))]
	var cf_r := 28.0 * view_zoom
	var cf_poly := _round_corners(cf_quad, cf_r)
	if canvas_bg_tex != null:
		_draw_canvas_image()                                  # 背景图：铺满画布矩形 + 随透视投影
		for cutout in _round_corner_cutouts(cf_quad, cf_r):
			draw_colored_polygon(cutout, BG_OUT)
		draw_colored_polygon(cf_poly, Color(1, 1, 1, 0.62))   # 半透明白覆盖，压淡背景衬托卡片
	else:
		draw_colored_polygon(cf_poly, BG)
	# 顶/底硬墨线（无抗锯齿）
	draw_line(_project(Vector2(CANVAS_X0, DRAW_Y1)), _project(Vector2(CANVAS_X1, DRAW_Y1)), Color("3a352f"), maxf(2.0, 3.0 * view_zoom))
	draw_line(_project(Vector2(CANVAS_X0, MID_Y1)), _project(Vector2(CANVAS_X1, MID_Y1)), Color("3a352f"), maxf(2.0, 3.0 * view_zoom))

	# 画布外框（厚像素框，跟随透视斜边）：白色外框 + 黑色内框
	var cf_outer := cf_poly.duplicate()
	cf_outer.append(cf_outer[0])
	draw_polyline(cf_outer, Color.WHITE, maxf(3.0, 16.0 * view_zoom), true)
	var cf_inner := _round_corners(_inset_quad(cf_quad, 12.0 * view_zoom), maxf(2.0, cf_r - 6.0 * view_zoom))
	cf_inner.append(cf_inner[0])
	draw_polyline(cf_inner, Color("141414"), maxf(3.0, 12.0 * view_zoom), true)

	var f := _ui_font()
	# fixed bank slot, outside the zoomable canvas
	if bank_button == null or not is_instance_valid(bank_button):
		draw_rect(BANK_RECT, Color("f3ead7"), true)
		draw_rect(BANK_RECT, Color("d9a552"), false, 3.0)
		draw_string(f, BANK_RECT.position + Vector2(116, 54), "银行", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("3a352f"))

	# 底部信息栏：所有解说/hint，斜体「」呈现
	draw_rect(Rect2(0, INFO_Y, BASE_W, BASE_H - INFO_Y), ORG_BG, true)
	draw_line(Vector2(0, INFO_Y), Vector2(BASE_W, INFO_Y), Color(0.23, 0.21, 0.18, 0.5), 2.5)
	var info_y := INFO_Y
	draw_string(f, Vector2(40, info_y + 26), "信息", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.5, 0.44, 0.7))
	var fresh := toast_t > 0.0
	var hint_col := Color("8a5a26") if fresh else Color(0.36, 0.33, 0.29, 0.92)
	_draw_italic(f, Vector2(120, info_y + 30), hint_text, 22, hint_col)

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

func _draw_italic(f: Font, pos: Vector2, text: String, size: int, col: Color) -> void:
	var t := Transform2D(Vector2(1, 0), Vector2(-0.22, 1), pos)
	draw_set_transform_matrix(t)
	draw_string(f, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, BASE_W - 160, size, col)
	draw_set_transform_matrix(Transform2D.IDENTITY)
