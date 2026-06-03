extends Node2D
## Zoned board with a shared 1-point perspective projection applied to BOTH the
## background and the cards. All gameplay logic runs in flat "board space";
## rendering projects board space -> display space (top narrower than bottom).

const CardScript = preload("res://scripts/Card.gd")
const PackCardScript = preload("res://scripts/PackCard.gd")
const CARD_SCALE := 1.0               # 卡按 120×180 设计，节点不再额外缩放
const CW := 180.0                     # square card, keeping the old long side
const CH := 180.0
const CARD_OFFSET := 44.0             # 叠放露出标题栏
const DRAG_Z := 4000

# ---- Layout (board space 1920x1080) ----
const BASE_W := 1920.0
const BASE_H := 1080.0
const HUD_H := 52.0
const DRAW_Y0 := 52.0
const DRAW_Y1 := 160.0          # 抽卡区压扁成一条工具栏（研发|卡包|银行同排）
const MID_Y0 := 160.0           # 画布上边（锚定在 UI 区下方）
const MID_Y1 := 1356.0          # 画布下边（画布区扩大一倍）
const ORG_Y0 := 1356.0          # 组织/部门折叠区位于画布底部
const INFO_Y := 1016.0          # fixed bottom information strip
const DIVIDER_X := 960.0
const CANVAS_X0 := -300.0       # 画布左边（以中线 960 为中心对称扩大）
const CANVAS_X1 := 2220.0       # 画布右边
const GAP := 16.0
const BANK_RECT := Rect2(1590, 60, 300, 84)     # fixed HUD bank, outside canvas zoom
const VIEW_PAD := 420.0

# ---- Perspective ----  (1.0 = OFF/flat)；0.9 = 轻微一点透视（顶窄底宽）
const TOP_SCALE := 0.9         # horizontal width factor at the very top (y=0)

# ---- 拖拽弹簧（滞后 + 摆动）----  减衰調和振動：顶牌跟手、越往下越软越晃
const DRAG_OMEGA_TOP := 26.0       # 顶牌角频率（越大越跟手）
const DRAG_OMEGA_FALLOFF := 0.74   # 每往下一张，频率×此值 → 滞后/摆动递增
const DRAG_ZETA := 0.62            # 阻尼比 <1 → 欠阻尼，产生回摆/甩动感

# 莫兰迪淡色 + 奶白底
const BG := Color("efe7d8")          # 画布纸面（画布内底色）
const BG_OUT := Color("736b5e")      # 画布外·压暗，衬托白色外框
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

var month_time: float = 0.0

const DEFAULT_HINT := "「拖动『创始人』到资源节点上即可开始生产；员工可跨区搬运，资源不能跨区」"

var hud: CanvasLayer
var lbl_status: Label
var lbl_finance: Label
var lbl_expense: Label
var lbl_val: Label
var hover_panel: Panel
var hover_label: Label
var month_progress: ColorRect
var pixel_font: Font
var hint_text: String = DEFAULT_HINT
var selected_card = null
var toast_t: float = 0.0
var emergency: bool = false
var emergency_t: float = 0.0
var game_over: bool = false
var dbg_last := Vector2.ZERO
var view_zoom: float = 1.0
var view_offset: Vector2 = Vector2.ZERO
var panning_canvas: bool = false
var pan_last: Vector2 = Vector2.ZERO
const VIEW_ZOOM_MIN := 0.55
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
var school_empty_toast_t: float = 0.0
var val_timer: float = 0.0

const SCHOOL_INSIGHT_NEED := 25.0

func _ready() -> void:
	GameState.reset()
	month_time = float(DataLoader.balance.get("month_seconds", 90.0))
	_build_hud()
	_spawn_start_cards()
	GameState.recipe_discovered.connect(_on_discovery)
	GameState.idea_unlocked.connect(_on_idea_unlocked)
	GameState.stage_changed.connect(_on_stage_changed)

# ---------------------------------------------------------------- perspective
func _row_scale(y: float) -> float:
	return lerpf(TOP_SCALE, 1.0, clampf(y / BASE_H, 0.0, 1.0))

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

func clamp_to_zone(pos: Vector2, zone: String) -> Vector2:
	var y := clampf(pos.y, MID_Y0 + 2, MID_Y1 - CH)
	var x: float
	if zone == "market":
		x = clampf(pos.x, DIVIDER_X + GAP, CANVAS_X1 - GAP - CW)
	else:
		x = clampf(pos.x, CANVAS_X0 + GAP, DIVIDER_X - GAP - CW)
	return Vector2(x, y)

func _zone_for_center(center: Vector2) -> String:
	return "office" if center.x < DIVIDER_X else "market"

# ---------------------------------------------------------------- spawning
func _spawn_start_cards() -> void:
	_spawn_card_pop("founder", Vector2(160, 420), 0.00)
	_spawn_card_pop("dev_rep", Vector2(340, 420), 0.05)
	_spawn_card_pop("admin_rep", Vector2(560, 420), 0.07)
	_spawn_card_pop("office", Vector2(160, 660), 0.10)
	_spawn_card_pop("research_bench", Vector2(360, 660), 0.15)
	_spawn_card_pop("market_research", Vector2(560, 660), 0.20)
	_spawn_card_pop("sales_rep", Vector2(1120, 420), 0.25)
	_spawn_card_pop("market_lead_pool", Vector2(1320, 420), 0.30)
	_spawn_card_pop("client_demand", Vector2(1520, 420), 0.35)

func _spawn_card_pop(id: String, pos: Vector2, delay: float = 0.0) -> Node2D:
	var c := spawn_card(id, pos)
	_play_card_pop(c, delay)
	return c

func spawn_card(id: String, pos: Vector2) -> Node2D:
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
	var ds_dy := (1.0 - TOP_SCALE) / BASE_H              # perspective convergence rate
	for i in arr.size():
		var c = arr[i]
		c.stack_pos = i
		var bp := base + Vector2(0, i * CARD_OFFSET)        # board space
		var s := _row_scale(bp.y + CH * 0.5)
		c.scale = Vector2(s, s) * CARD_SCALE * view_zoom
		# tilt the card's vertical edges toward the vanishing point (same angle as walls)
		var cx := bp.x + CW * 0.5
		c.skew = -atan((cx - BASE_W * 0.5) * ds_dy)   # 与画布透视同向（卡铺在画布上）
		if sid != drag_sid:
			c.position = _project(bp)                        # display space
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
			elif BANK_RECT.has_point(wp):
				_withdraw_cash_from_bank()
				return
			else:
				var pack: Node2D = _topmost_pack_at(wp)
				if pack != null:
					_open_loose_pack(pack)
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
	var src: int = picked.stack_id
	var arr: Array = stacks[src]
	var k: int = picked.stack_pos
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
	# 拿起：卡心对齐光标。目标设为“光标=被点卡中心”，卡仍留在原位，
	# 由弹簧迅速弹向光标——即点击后先自动动一下，再进入跟随拖拽。
	drag_offset = Vector2(CW * 0.5, CH * 0.5)
	stack_base[sid] = _unproject(wp) - drag_offset
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

	if BANK_RECT.has_point(_project(center)):
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
		var target := _project(bp)
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
			return "「%s · 员工　月薪 $%d　产能 %d — 可跨区搬运资源；叠到资源或节点上即可开始生产」" % [
				nm, int(d.get("salary", 0)), int(d.get("capacity", 0))]
		"resource_node":
			var us := ("剩余 %d 次" % c.uses_left) if c.uses_left >= 0 else "可无限使用"
			return "「%s · 资源节点　%s — 固定在本区，派员工叠上去产出」" % [nm, us]
		"resource":
			return "「%s · 资源　售价 $%d — 不能跨区，需员工搬运；拖到右上『银行』变现」" % [nm, int(d.get("sell", 0))]
		"facility":
			if c.card_id == "business_school":
				return "「%s · 设施　员工在其上工作会累积洞察值，满值随机解锁当前阶段 idea」" % nm
			return "「%s · 设施　固定在本区，提供加成」" % nm
		"department":
			return "「%s · 部门　%d 人　月薪 $%d — 自动持续产出」" % [nm, int(d.get("capacity", 0)), int(d.get("salary", 0))]
		"risk":
			return "「%s · 风险　拖员工上去处理，否则持续造成损失」" % nm
		"idea":
			return "「%s · 想法 / 配方」" % nm
		_:
			return "「%s」" % nm

func _clear_drag() -> void:
	drag_cards = []
	drag_sid = -1

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
	for c in all_cards:
		if c.stack_id == sid:
			continue
		if Rect2(_board_topleft(c), Vector2(CW, CH)).has_point(nb):
			if target == null or c.z_index > target.z_index:
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
	var worker_tags: Dictionary = {}
	var has_worker := false
	var all_emp := true
	for src in [a, b]:
		for c in stacks[src]:
			counts[c.card_id] = int(counts.get(c.card_id, 0)) + 1
			if c.ctype == "employee":
				has_worker = true
				for t in c.cdef.get("workTags", []):
					worker_tags[t] = true
			else:
				all_emp = false
	if all_emp:
		return true                       # 员工叠员工 = 组队/组建部门
	if has_worker and counts.has("business_school"):
		return true                       # 员工叠商学院 = 累积洞察值
	for recipe in DataLoader.recipes:
		var gate := String(recipe.get("requiredIdeaId", ""))
		if gate != "" and not GameState.idea_done(gate):
			continue
		if _recipe_matches(recipe, counts, worker_tags, has_worker):
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
	for c in arr:
		total += int(c.cdef.get("sell", 0))
		destroy_card(c)
	if total > 0:
		GameState.add_cash(total)
		_float_text_screen("+$" + str(total), BANK_RECT.position + Vector2(60, 0), Color("ffe66d"))
	else:
		_show_toast("这张卡卖不出钱")

func _withdraw_cash_from_bank() -> void:
	if not GameState.spend_cash(1):
		_show_toast("银行库存现金不足")
		return
	var origin := BANK_RECT.position + BANK_RECT.size * 0.5
	var landing := clamp_to_zone(Vector2(260, 310) + Vector2(GameState.rng.randf_range(-40.0, 90.0), GameState.rng.randf_range(-20.0, 90.0)), "office")
	var c := spawn_card("cash", landing)
	c.zone = "office"
	_play_card_pop(c, 0.0, origin)
	_float_text_screen("-$1", BANK_RECT.position + Vector2(60, 0), Color("bdbab1"))

# ---------------------------------------------------------------- recipes
func evaluate_stack(sid: int) -> void:
	if not stacks.has(sid) or productions.has(sid):
		return
	var arr: Array = stacks[sid]
	var counts: Dictionary = {}
	var worker_tags: Dictionary = {}
	var has_worker := false
	for c in arr:
		counts[c.card_id] = int(counts.get(c.card_id, 0)) + 1
		if c.ctype == "employee":
			has_worker = true
			for t in c.cdef.get("workTags", []):
				worker_tags[t] = true
	for recipe in DataLoader.recipes:
		var gate := String(recipe.get("requiredIdeaId", ""))
		if gate != "" and not GameState.idea_done(gate):
			continue
		if _recipe_matches(recipe, counts, worker_tags, has_worker):
			var target = _work_target(arr, recipe)
			productions[sid] = { "recipe": recipe, "target": target }
			if target != null:    # 接续被工作对象上已有的进度（员工换人也不丢）
				target.set_work(clampf(target.work_elapsed / float(recipe.get("duration", 4.0)), 0, 1))
			return

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

func _recipe_matches(recipe: Dictionary, counts: Dictionary, worker_tags: Dictionary, has_worker: bool) -> bool:
	var rtags: Array = recipe.get("worker_tags", [])
	var worker_ok := false
	for t in rtags:
		if t == "any" and has_worker:
			worker_ok = true
		elif worker_tags.has(t):
			worker_ok = true
	if not worker_ok:
		return false
	for inp in recipe.get("inputs", []):
		var need := int(inp.get("count", 1))
		if int(counts.get(inp.get("id", ""), 0)) < need:
			return false
	return true

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
	for outp in rec.get("outputs", []):
		if outp.has("cash"):
			var amt := int(outp["cash"]) * mult
			GameState.add_cash(amt)
			GameState.add_revenue(amt)
			_ka_ching(base, amt)
		elif outp.has("id"):
			var n := int(outp.get("count", 1)) * mult
			var forced := String(rec.get("output_zone", ""))
			var zone := forced if forced != "" else _zone_for_center(base + Vector2(CW * 0.5, CH * 0.5))
			var origin := base
			if forced == "market":
				origin = Vector2(1080, 360)
			elif forced == "office":
				origin = Vector2(240, 360)
			for i in n:
				_drop_output(String(outp["id"]), origin, zone)
	_consume_node_uses(sid, rec)
	GameState.discover(String(rec.get("id", "")))
	if is_instance_valid(target):       # 完成后重置被工作对象的进度（若未被消耗销毁）
		target.work_elapsed = 0.0
		target.set_work(0.0)
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
	const DROP_MIN := 90.0
	const DROP_MAX := 180.0
	const GROUP_RANGE := 190.0
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
	_play_card_pop(nc)

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
		# only 回款(revenue) auto-sells; lead/contract stay until processed
		if c.card_id != "revenue" or c.zone != "market":
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
	var dest := BANK_RECT.position + BANK_RECT.size * 0.5 - Vector2(CW, CH) * 0.25
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "position", dest, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "scale", c.scale * 0.4, 0.45)
	tw.chain().tween_callback(func():
		GameState.add_cash(value)
		_float_text_screen("+$" + str(value), BANK_RECT.position + Vector2(60, -10), Color("ffe66d"))
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
		target.set_work(clampf(target.work_elapsed / dur, 0, 1))
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
		if GameState.cash >= 0:
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
	_update_cursor()
	_update_hud()
	queue_redraw()

func _update_cursor() -> void:
	if panning_canvas:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		return
	if not drag_cards.is_empty():
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	var p := get_viewport().get_mouse_position()
	if BANK_RECT.has_point(p):
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		return
	var board := _unproject(p)
	if region_of(board) in ["office", "market"] and _topmost_at(p) == null and _topmost_pack_at(p) == null:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

# ---------------------------------------------------------------- month
func _settle_month() -> void:
	var payroll := 0
	var office_n := 0
	for c in all_cards:
		payroll += int(c.cdef.get("salary", 0))
		if c.card_id == "office":
			office_n += 1
	payroll = maxi(0, payroll - office_n * 2)    # 办公室：行政效率，每间每月省 $2 发薪
	GameState.add_cash(-payroll)
	_float_text("发薪 -$" + str(payroll), Vector2(880, 300), Color("ff8c8c"))
	GameState.advance_month()
	month_time = float(DataLoader.balance.get("month_seconds", 90.0))
	if GameState.cash < 0:
		emergency = true
		emergency_t = float(DataLoader.balance.get("emergency_seconds", 30.0))
		_show_toast("现金为负！30秒内卖卡补足，否则破产")

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
	if not GameState.spend_cash(price):
		_show_toast("现金不足，买不起卡包")
		return
	var slots: Array = pack.get("slots", [])
	var n := GameState.rng.randi_range(int(pack.get("minCards", 3)), int(pack.get("maxCards", 5)))
	var got := mini(n, slots.size())
	var contents: Array = []
	for i in got:
		contents.append(_weighted_pick(slots[i]))
	_spawn_loose_pack(pack_id, pack, contents)
	_show_toast("%s 已弹出，点击画布上的卡包拆开" % String(pack.get("name", "卡包")))

func _spawn_loose_pack(pack_id: String, pack: Dictionary, contents: Array) -> void:
	var p = PackCardScript.new()
	add_child(p)
	p.setup(pack_id, String(pack.get("name", "卡包")), contents)
	p.z_index = 2100
	p.position = _pack_button_start(pack_id)
	p.scale = Vector2(0.35, 0.35) * view_zoom
	loose_packs.append(p)
	p.board_pos = _random_pack_landing()
	var landing := _project(p.board_pos)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "position", landing, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "scale", Vector2.ONE * view_zoom, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "rotation", GameState.rng.randf_range(-0.08, 0.08), 0.42)
	tw.chain().tween_callback(func(): p.ready_to_open = true)

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
	if p.opened or not p.ready_to_open:
		return
	p.opened = true
	_show_toast("拆开 %s！" % p.pack_name)
	var origin: Vector2 = p.position + Vector2(PackCardScript.W, PackCardScript.H) * 0.5 * p.scale.x
	var zone := _zone_for_center(_unproject(origin))
	for i in p.contents.size():
		var id := String(p.contents[i])
		var delay := float(i) * 0.085
		get_tree().create_timer(delay).timeout.connect(_burst_card_from_pack.bind(id, origin, zone))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "scale", Vector2(1.12, 0.82), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 0.0, 0.36).set_delay(0.20)
	tw.chain().tween_callback(func():
		loose_packs.erase(p)
		p.queue_free()
	)

func _burst_card_from_pack(id: String, origin_display: Vector2, zone: String) -> void:
	var origin_board := _unproject(origin_display) - Vector2(CW, CH) * 0.5
	var ang := GameState.rng.randf_range(-0.25 * PI, 1.15 * PI)
	var dist := GameState.rng.randf_range(96.0, 230.0)
	var landing := clamp_to_zone(origin_board + Vector2(cos(ang), sin(ang)) * dist, zone)
	var c := spawn_card(id, landing)
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
	var headcount := 0
	var expense := 0
	for c in all_cards:
		expense += int(c.cdef.get("salary", 0))
		if c.ctype == "employee":
			headcount += 1
	for d in departments:
		headcount += int(d["headcount"])
	GameState.monthly_expense = expense
	# 虚拟估值公式：现金 + 累计营收×3 + 人数×10 + 部门×25
	var val := GameState.cash + GameState.total_revenue * 3 + headcount * 10 + departments.size() * 25
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
		if GameState.stage < stg:
			btn.disabled = true
			btn.text = "🔒 %s\n需「%s」阶段" % [String(pack.get("name", "")), GameState.STAGE_NAMES[stg]]
		else:
			btn.disabled = false
			btn.text = "%s\n$%d" % [String(pack.get("name", "")), int(pack.get("price", 0))]

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
	var reward := int(DataLoader.balance.get("discovery_reward", 1))
	if reward > 0:
		GameState.add_cash(reward)
	_show_toast("🎉 新发现：" + _recipe_name(recipe_id) + "  (+$" + str(reward) + ")")
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

# ---------------------------------------------------------------- HUD
func _style_button(b: Button, fill: Color) -> void:
	# 漫画风：淡彩底 + 墨线边 + 圆角，hover/press 微调
	b.add_theme_font_override("font", _ui_font())
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
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
		sb.set_corner_radius_all(10)
		sb.border_color = INK
		sb.set_border_width_all(2)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		b.add_theme_stylebox_override(state, sb)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var bar := ColorRect.new()
	bar.color = Color("f3ecdd")          # 奶白顶栏
	bar.size = Vector2(BASE_W, HUD_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bar)
	var barline := ColorRect.new()       # 底部墨线
	barline.color = INK
	barline.position = Vector2(0, HUD_H - 2)
	barline.size = Vector2(BASE_W, 2)
	barline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(barline)
	lbl_status = Label.new()
	lbl_status.position = Vector2(16, 12)
	lbl_status.size = Vector2(620, 34)
	_apply_pixel_font(lbl_status, 22)
	lbl_status.add_theme_color_override("font_color", INK)
	lbl_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(lbl_status)
	var progress_frame := ColorRect.new()
	progress_frame.position = Vector2(646, 14)
	progress_frame.size = Vector2(328, 24)
	progress_frame.color = Color.WHITE
	progress_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(progress_frame)
	var progress_slot := ColorRect.new()
	progress_slot.position = Vector2(650, 18)
	progress_slot.size = Vector2(320, 16)
	progress_slot.color = Color("8d8d8d")
	progress_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(progress_slot)
	month_progress = ColorRect.new()
	month_progress.position = progress_slot.position
	month_progress.size = progress_slot.size
	month_progress.color = Color("141414")
	month_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(month_progress)
	lbl_finance = Label.new()
	lbl_finance.position = Vector2(1180, 12)
	lbl_finance.size = Vector2(190, 34)
	_apply_pixel_font(lbl_finance, 22)
	lbl_finance.add_theme_color_override("font_color", INK)
	lbl_finance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(lbl_finance)
	lbl_expense = Label.new()                       # 月支出单独成段，可 hover 看构成
	lbl_expense.position = Vector2(1380, 12)
	lbl_expense.size = Vector2(220, 34)
	_apply_pixel_font(lbl_expense, 22)
	lbl_expense.add_theme_color_override("font_color", INK)
	lbl_expense.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl_expense.mouse_entered.connect(_on_expense_hover)
	lbl_expense.mouse_exited.connect(_hide_hover)
	hud.add_child(lbl_expense)
	lbl_val = Label.new()
	lbl_val.position = Vector2(1620, 12)
	lbl_val.size = Vector2(280, 34)
	_apply_pixel_font(lbl_val, 22)
	lbl_val.add_theme_color_override("font_color", INK)
	lbl_val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(lbl_val)
	# 研发按钮：抽卡区最左
	var rbtn := Button.new()
	rbtn.text = "研发"
	rbtn.position = Vector2(30, HUD_H + 8)
	rbtn.size = Vector2(130, 84)
	_apply_pixel_font(rbtn, 22)
	_style_button(rbtn, Color("aecbe0"))
	rbtn.pressed.connect(_toggle_research)
	hud.add_child(rbtn)

	var book_btn := Button.new()
	book_btn.text = "配方书"
	book_btn.position = Vector2(30, INFO_Y - 88)
	book_btn.size = Vector2(130, 64)
	_apply_pixel_font(book_btn, 20)
	_style_button(book_btn, Color("c2b6d6"))
	book_btn.pressed.connect(_toggle_recipe_book)
	hud.add_child(book_btn)

	# stage packs row in the top (抽卡区) strip — 研发右侧、银行左侧之间
	var px := 185.0
	for pid in DataLoader.packs.keys():
		var pack: Dictionary = DataLoader.packs[pid]
		var pb := Button.new()
		pb.position = Vector2(px, HUD_H + 8)
		pb.size = Vector2(150, 84)
		_apply_pixel_font(pb, 16)
		pb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_style_button(pb, Color("dcc9a6"))
		pb.pressed.connect(buy_pack.bind(String(pid)))
		pb.mouse_entered.connect(_on_pack_hover.bind(String(pid)))   # hover 显示可抽到的牌
		pb.mouse_exited.connect(_hide_hover)
		hud.add_child(pb)
		pack_buttons.append({ "btn": pb, "id": String(pid), "pack": pack })
		px += 162.0

	_refresh_packs()
	_build_research_panel()
	_build_recipe_book_panel()
	_build_hover_panel()

# ---------------------------------------------------------------- hover tooltip
func _build_hover_panel() -> void:
	hover_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("fbf6ec")
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	hover_panel.add_theme_stylebox_override("panel", sb)
	hover_panel.z_index = 4096
	hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_panel.visible = false
	hud.add_child(hover_panel)
	hover_label = Label.new()
	hover_label.position = Vector2(12, 8)
	_apply_pixel_font(hover_label, 18)
	hover_label.add_theme_color_override("font_color", INK)
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_panel.add_child(hover_label)

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
	var o := 0
	for c in all_cards:
		p += int(c.cdef.get("salary", 0))
		if c.card_id == "office":
			o += 1
	return maxi(0, p - o * 2)

func _on_expense_hover() -> void:
	_show_hover(_expense_hover_text(), lbl_expense)

func _expense_hover_text() -> String:
	var by_name: Dictionary = {}
	var office_n := 0
	for c in all_cards:
		if c.card_id == "office":
			office_n += 1
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
	if office_n > 0:
		lines.append("· 办公室行政减免  -$%d" % (office_n * 2))
	lines.append("合计  $%d / 月" % maxi(0, total - office_n * 2))
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
	research_panel = preload("res://scripts/ResearchGraph.gd").new()
	research_panel.position = Vector2.ZERO
	research_panel.size = Vector2(BASE_W, BASE_H)
	research_panel.visible = false
	hud.add_child(research_panel)

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
	lbl_status.text = "阶段「%s」    第%d月    RP %d%s" % [
		GameState.stage_name(), GameState.month, int(GameState.rp),
		("   [紧急!]" if emergency else "")]
	if month_progress:
		var total := float(DataLoader.balance.get("month_seconds", 90.0))
		var ratio := clampf(month_time / maxf(1.0, total), 0.0, 1.0)
		month_progress.size = Vector2(320.0 * ratio, 16.0)
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
	var cf_r := 16.0 * view_zoom
	draw_colored_polygon(_round_corners(cf_quad, cf_r), BG)
	# all bands drawn as perspective trapezoids (top narrower than bottom)
	draw_colored_polygon(_band(CANVAS_X0, DIVIDER_X, MID_Y0, MID_Y1), OFFICE_BG)
	draw_colored_polygon(_band(DIVIDER_X, CANVAS_X1, MID_Y0, MID_Y1), MARKET_BG)
	# 轻微暖光渐变（顶亮→底稍沉），保持淡雅
	var col := _band(CANVAS_X0, CANVAS_X1, DRAW_Y0, MID_Y1)
	draw_polygon(col, PackedColorArray([
		Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.04), Color(0.23, 0.21, 0.18, 0.03), Color(0.23, 0.21, 0.18, 0.03)]))
	# 墨线分隔（漫画感）
	draw_line(_project(Vector2(DIVIDER_X, MID_Y0)), _project(Vector2(DIVIDER_X, MID_Y1)), Color(0.23, 0.21, 0.18, 0.55), 2.5)
	draw_line(_project(Vector2(CANVAS_X0, DRAW_Y1)), _project(Vector2(CANVAS_X1, DRAW_Y1)), Color(0.23, 0.21, 0.18, 0.5), 2.5)
	draw_line(_project(Vector2(CANVAS_X0, MID_Y1)), _project(Vector2(CANVAS_X1, MID_Y1)), Color(0.23, 0.21, 0.18, 0.5), 2.5)

	# 画布外框（跟随透视斜边的圆角梯形）：白色粗外框 + 黑色粗内框；上框线锚定 UI 下方
	var cf_outer := _round_corners(cf_quad, cf_r)
	cf_outer.append(cf_outer[0])
	draw_polyline(cf_outer, Color.WHITE, maxf(2.0, 12.0 * view_zoom), true)
	var cf_inner := _round_corners(_inset_quad(cf_quad, 9.0 * view_zoom), maxf(2.0, cf_r - 4.0))
	cf_inner.append(cf_inner[0])
	draw_polyline(cf_inner, Color("141414"), maxf(2.0, 7.0 * view_zoom), true)

	var f := _ui_font()
	var lbl := Color(0.36, 0.33, 0.29, 0.85)   # 深墨字标签
	draw_string(f, _project(Vector2(40, MID_Y0 + 36)), "办公室区（研发 / 行政 / 运营）", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, lbl)
	draw_string(f, _project(Vector2(DIVIDER_X + 30, MID_Y0 + 36)), "市场区（线索 / 推广 / 对外）", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, lbl)

	# fixed bank slot, outside the zoomable canvas
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
