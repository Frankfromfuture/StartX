extends Node2D
class_name Card
## A single draggable card, redesigned 100% in the Stacklands style.
## Drawn entirely via _draw (no image assets): 2:3 portrait, thick black
## outline, rounded corners, title bar + divider, centered black emblem on a
## light circular backing, black circular value badges with white numbers.

const W := 180.0          # square, keeping the previous long side
const H := 180.0
const HEADER := 30.0

var card_id: String = ""
var ctype: String = "resource"
var cdef: Dictionary = {}

var stack_id: int = -1
var stack_pos: int = 0
var zone: String = ""
var uses_left: int = -1       # -1 = unlimited; >=0 = remaining uses (nodes)
var idle_t: float = 0.0       # idle time (for market auto-sell)

var work_ratio: float = 0.0       # 工作进度比例(0..1)，>0 即在本卡上方显示工作条
var work_elapsed: float = 0.0     # 已工作秒数，持久化在【被工作对象】卡上（员工离开也保留）

var drag_vel: Vector2 = Vector2.ZERO   # 拖拽弹簧的当前速度（用于滞后/摆动）
var selected: bool = false             # 单击选中
var ui_font: Font

const INK := Color("141414")     # 黑描边 / 分割线 / 图标 / 数字圈
const BODY := Color("faf5ec")    # 奶白卡身
const SEL := Color("e0a23a")     # 选中高亮

# 游戏分类 -> 莫兰迪淡彩标题栏色
func _header_color() -> Color:
	if card_id == "revenue":
		return Color("ecd590")          # 金币 / 回款：黄
	match ctype:
		"employee":      return Color("efe7d6")   # 人物：米白
		"resource_node": return Color("aebfcf")   # 资源（节点）：灰蓝
		"resource":      return Color("aeccb0")   # 资源：绿色
		"facility":      return Color("e6b8c2")   # 建筑：粉红
		"risk":          return Color("d99a90")   # 怪物 / 风险：红
		"idea":          return Color("2a2622")   # 想法 / 卡包：黑
		"department":    return Color("c2b6d6")   # 部门：雾紫
		_:               return Color("d8d2c4")

func setup(id: String) -> void:
	card_id = id
	cdef = DataLoader.card_def(id)
	ctype = String(cdef.get("type", "resource"))
	uses_left = int(cdef.get("maxUses", -1))
	queue_redraw()

func _draw() -> void:
	var head := _header_color()
	var dark_head := (ctype == "idea")
	var title_fg := Color("f7f2e8") if dark_head else INK   # 深色标题栏用浅字
	var bg := head.lightened(0.45)                          # 卡身 = header 浅一号
	var ring := head.lightened(0.68)                        # 中间圆圈 = 更浅一号

	# 卡身：圆角 8、黑粗描边 5、轻微投影
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.border_color = INK
	sb.set_border_width_all(5)
	sb.shadow_color = Color(0, 0, 0, 0.22)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(3, 5)
	draw_style_box(sb, Rect2(0, 0, W, H))

	# 选中高亮：外圈琥珀
	if selected:
		var hl := StyleBoxFlat.new()
		hl.bg_color = Color(0, 0, 0, 0)
		hl.set_corner_radius_all(11)
		hl.border_color = SEL
		hl.set_border_width_all(4)
		draw_style_box(hl, Rect2(-5, -5, W + 10, H + 10))

	# 标题栏色块（顶部跟随圆角）+ 底部黑色分割线
	var hb := StyleBoxFlat.new()
	hb.bg_color = head
	hb.corner_radius_top_left = 4
	hb.corner_radius_top_right = 4
	hb.corner_radius_bottom_left = 0
	hb.corner_radius_bottom_right = 0
	draw_style_box(hb, Rect2(5, 5, W - 10, HEADER))
	draw_line(Vector2(5, 5 + HEADER), Vector2(W - 5, 5 + HEADER), INK, 3.0)

	# 主体图像：更浅圆底纹 + 居中黑色线稿剪影
	_draw_emblem(ring)

	# 标题：像素体，统一字号、左对齐、纵向居中于标题栏
	draw_string(_ui_font(), Vector2(12, 26), _card_name(), HORIZONTAL_ALIGNMENT_LEFT, W - 24, 18, title_fg)

	# 磨砂光照（拿起时增强 + 掠光）
	_draw_gloss(selected)

	# 底部角标：左下 = 月薪，右下 = 产能；名称区右上 = 剩余次数
	var salary := int(cdef.get("salary", 0))
	if salary > 0:
		_draw_badge(Vector2(24, H - 24), str(salary))
	var cap := int(cdef.get("capacity", 0))
	if cap > 0:
		_draw_badge(Vector2(W - 24, H - 24), str(cap))
	if uses_left >= 0:
		draw_string(_ui_font(), Vector2(W - 42, 26), str(uses_left), HORIZONTAL_ALIGNMENT_RIGHT, 30, 18, INK)

	# 工作条：显示在【被工作对象】卡的正上方（卡顶之上悬浮），灰白、加粗、全宽
	if work_ratio > 0.0:
		var bh := 18.0
		var by := -bh - 5.0
		draw_rect(Rect2(0, by, W, bh), Color("eceae4"), true)                              # 灰白底槽
		draw_rect(Rect2(0, by, W * clampf(work_ratio, 0, 1), bh), Color("bdbab1"), true)   # 灰进度
		draw_rect(Rect2(0, by, W, bh), INK, false, 2.0)                                    # 黑描边

# ---- emblem (centered black line-art on a light circular backing) ----------
func _draw_emblem(ring: Color) -> void:
	var col := INK                    # 剪影统一黑色线稿
	var cx := W * 0.5
	var cy := HEADER + (H - HEADER) * 0.44
	var u := W / 12.0
	# 更浅圆形底纹
	draw_circle(Vector2(cx, cy), W * 0.28, ring)
	draw_arc(Vector2(cx, cy), W * 0.28, 0, TAU, 40, Color(0, 0, 0, 0.08), 2.0, true)

	if card_id == "revenue":          # 金币
		draw_circle(Vector2(cx, cy), 2.6 * u, col)
		draw_rect(Rect2(cx - 0.8 * u, cy - 0.8 * u, 1.6 * u, 1.6 * u), ring, true)
		return

	match ctype:
		"employee":
			draw_circle(Vector2(cx, cy - 1.8 * u), 1.5 * u, col)
			var body := PackedVector2Array([
				Vector2(cx - 2.4 * u, cy + 2.4 * u), Vector2(cx - 1.7 * u, cy - 0.1 * u),
				Vector2(cx + 1.7 * u, cy - 0.1 * u), Vector2(cx + 2.4 * u, cy + 2.4 * u)])
			draw_colored_polygon(body, col)
		"resource_node":
			draw_rect(Rect2(cx - 2.7 * u, cy + 0.9 * u, 5.4 * u, 1.4 * u), col)
			draw_rect(Rect2(cx - 1.9 * u, cy - 0.6 * u, 3.8 * u, 1.4 * u), col)
			draw_rect(Rect2(cx - 1.1 * u, cy - 2.1 * u, 2.2 * u, 1.4 * u), col)
		"resource":
			draw_rect(Rect2(cx - 2.4 * u, cy - 2.4 * u, 4.8 * u, 4.8 * u), col)
			draw_rect(Rect2(cx - 2.4 * u, cy - 0.35 * u, 4.8 * u, 0.7 * u), ring)
			draw_rect(Rect2(cx - 0.35 * u, cy - 2.4 * u, 0.7 * u, 4.8 * u), ring)
		"facility":
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx - 3.0 * u, cy - 0.4 * u), Vector2(cx, cy - 3.2 * u),
				Vector2(cx + 3.0 * u, cy - 0.4 * u)]), col)
			draw_rect(Rect2(cx - 2.3 * u, cy - 0.4 * u, 4.6 * u, 3.1 * u), col)
			draw_rect(Rect2(cx - 0.7 * u, cy + 0.8 * u, 1.4 * u, 1.9 * u), ring)
		"risk":
			draw_circle(Vector2(cx, cy - 0.2 * u), 2.5 * u, col)
			draw_circle(Vector2(cx - 0.95 * u, cy - 0.5 * u), 0.5 * u, ring)
			draw_circle(Vector2(cx + 0.95 * u, cy - 0.5 * u), 0.5 * u, ring)
			draw_rect(Rect2(cx - 1.3 * u, cy + 0.9 * u, 2.6 * u, 0.6 * u), ring)
		"idea":
			draw_circle(Vector2(cx, cy - 0.6 * u), 2.0 * u, col)
			draw_rect(Rect2(cx - 1.0 * u, cy + 1.2 * u, 2.0 * u, 1.3 * u), col)
			draw_rect(Rect2(cx - 0.7 * u, cy + 2.4 * u, 1.4 * u, 0.7 * u), col)
		"department":
			for dx in [-2.2 * u, 0.0, 2.2 * u]:
				draw_circle(Vector2(cx + dx, cy - 1.0 * u), 0.9 * u, col)
				draw_rect(Rect2(cx + dx - 1.0 * u, cy, 2.0 * u, 2.0 * u), col)
		_:
			draw_circle(Vector2(cx, cy), 2.0 * u, col)

# ---- circular value badge: black disc, white pixel number ------------------
func _draw_badge(center: Vector2, txt: String) -> void:
	draw_circle(center, 13, INK)
	draw_string(_ui_font(), center + Vector2(-8, 6), txt, HORIZONTAL_ALIGNMENT_CENTER, 16, 15, Color.WHITE)

func _card_name() -> String:
	return String(cdef.get("name", card_id))

func _ui_font() -> Font:
	if ui_font != null:
		return ui_font
	var candidates := [
		"res://fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/Users/frankfan/Library/Fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/System/Library/Fonts/PingFang.ttc"
	]
	for path in candidates:
		if not FileAccess.file_exists(path):
			continue
		var ff := FontFile.new()
		ff.load_dynamic_font(path)
		ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		ff.generate_mipmaps = true
		ui_font = ff
		return ui_font
	ui_font = ThemeDB.fallback_font
	return ui_font

# ---- pixel font (5x7) ------------------------------------------------------
const EN_NAMES := {
	"founder": "FOUNDER", "sales_rep": "SALES REP", "product_manager": "PROD MGR",
	"market_lead_pool": "LEAD POOL", "client_demand": "DEMAND", "talent_market": "TALENT",
	"market_research": "SURVEY", "lab_equipment": "LAB GEAR", "research_bench": "DEV BENCH",
	"engineer": "ENGINEER", "analyst": "ANALYST", "data_source": "DATA SRC",
	"dev_studio": "DEV ROOM", "business_school": "B-SCHOOL",
	"lead": "LEAD", "opportunity": "DEAL", "requirement": "REQ", "prd": "PRD",
	"prototype": "PROTO", "product": "PRODUCT", "data": "DATA", "insight": "INSIGHT",
	"user": "USER", "contract": "CONTRACT", "revenue": "REVENUE", "office": "OFFICE", "crm": "CRM",
	"customer_complaint": "COMPLAINT", "bug": "INCIDENT",
}

func _en_name() -> String:
	if EN_NAMES.has(card_id):
		return EN_NAMES[card_id]
	if card_id.begins_with("dept_"):
		return card_id.substr(5).to_upper() + " DEPT"
	return card_id.to_upper().replace("_", " ")

const GLYPHS := {
	" ": [0,0,0,0,0,0,0],
	"-": [0,0,0,0x1F,0,0,0],
	".": [0,0,0,0,0,0,0x04],
	"A": [0x0E,0x11,0x11,0x1F,0x11,0x11,0x11],
	"B": [0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E],
	"C": [0x0E,0x11,0x10,0x10,0x10,0x11,0x0E],
	"D": [0x1E,0x11,0x11,0x11,0x11,0x11,0x1E],
	"E": [0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F],
	"F": [0x1F,0x10,0x10,0x1E,0x10,0x10,0x10],
	"G": [0x0E,0x11,0x10,0x17,0x11,0x11,0x0F],
	"H": [0x11,0x11,0x11,0x1F,0x11,0x11,0x11],
	"I": [0x0E,0x04,0x04,0x04,0x04,0x04,0x0E],
	"J": [0x07,0x02,0x02,0x02,0x02,0x12,0x0C],
	"K": [0x11,0x12,0x14,0x18,0x14,0x12,0x11],
	"L": [0x10,0x10,0x10,0x10,0x10,0x10,0x1F],
	"M": [0x11,0x1B,0x15,0x15,0x11,0x11,0x11],
	"N": [0x11,0x19,0x19,0x15,0x13,0x13,0x11],
	"O": [0x0E,0x11,0x11,0x11,0x11,0x11,0x0E],
	"P": [0x1E,0x11,0x11,0x1E,0x10,0x10,0x10],
	"Q": [0x0E,0x11,0x11,0x11,0x15,0x12,0x0D],
	"R": [0x1E,0x11,0x11,0x1E,0x14,0x12,0x11],
	"S": [0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E],
	"T": [0x1F,0x04,0x04,0x04,0x04,0x04,0x04],
	"U": [0x11,0x11,0x11,0x11,0x11,0x11,0x0E],
	"V": [0x11,0x11,0x11,0x11,0x11,0x0A,0x04],
	"W": [0x11,0x11,0x11,0x15,0x15,0x1B,0x11],
	"X": [0x11,0x11,0x0A,0x04,0x0A,0x11,0x11],
	"Y": [0x11,0x11,0x0A,0x04,0x04,0x04,0x04],
	"Z": [0x1F,0x01,0x02,0x04,0x08,0x10,0x1F],
	"0": [0x0E,0x11,0x13,0x15,0x19,0x11,0x0E],
	"1": [0x04,0x0C,0x04,0x04,0x04,0x04,0x0E],
	"2": [0x0E,0x11,0x01,0x06,0x08,0x10,0x1F],
	"3": [0x1F,0x02,0x04,0x02,0x01,0x11,0x0E],
	"4": [0x02,0x06,0x0A,0x12,0x1F,0x02,0x02],
	"5": [0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E],
	"6": [0x06,0x08,0x10,0x1E,0x11,0x11,0x0E],
	"7": [0x1F,0x01,0x02,0x04,0x08,0x08,0x08],
	"8": [0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E],
	"9": [0x0E,0x11,0x11,0x0F,0x01,0x02,0x0C],
}

func _text_w(text: String, ps: float) -> float:
	return maxf(0.0, text.length() * 6.0 * ps - ps)

# 从左上角 (x,y) 绘制点阵文本
func _blit_pixels(text: String, x: float, y: float, ps: float, col: Color) -> void:
	var px := x
	for ch in text:
		var g: Array = GLYPHS.get(ch, GLYPHS[" "])
		for row in 7:
			var bits: int = g[row]
			for cb in 5:
				if bits & (1 << (4 - cb)):
					draw_rect(Rect2(px + cb * ps, y + row * ps, ps, ps), col, true)
		px += 6.0 * ps

# 区域内左对齐 + 纵向居中（统一字号 ps）
func _draw_pixel_text(text: String, ox: float, area_y: float, area_h: float, ps: float, col: Color) -> void:
	_blit_pixels(text, ox, area_y + (area_h - 7.0 * ps) * 0.5, ps, col)

# ---------------------------------------------------------------------------
func contains_point(global_pt: Vector2) -> bool:
	var local := to_local(global_pt)
	return local.x >= 0 and local.x <= W and local.y >= 0 and local.y <= H

# 磨砂光照：大面积低对比柔光（环境光感）。picked=拿起时整体提亮 + 一道斜向掠光。
func _draw_gloss(picked: bool) -> void:
	var a_top := 0.20 if picked else 0.10      # 上半柔光
	var a_diag := 0.12 if picked else 0.06     # 对角环境光（左上亮→右下暗）
	var a_edge := 0.50 if picked else 0.22     # 顶边高光线
	draw_polygon(
		PackedVector2Array([Vector2(6, 6), Vector2(W - 6, 6), Vector2(W - 6, H * 0.5), Vector2(6, H * 0.5)]),
		PackedColorArray([Color(1, 1, 1, a_top), Color(1, 1, 1, a_top), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))
	draw_polygon(
		PackedVector2Array([Vector2(6, 6), Vector2(W - 6, 6), Vector2(W - 6, H - 6), Vector2(6, H - 6)]),
		PackedColorArray([Color(1, 1, 1, a_diag), Color(1, 1, 1, a_diag * 0.35),
			Color(1, 1, 1, 0), Color(1, 1, 1, a_diag * 0.35)]))
	draw_line(Vector2(9, 8.5), Vector2(W - 9, 8.5), Color(1, 1, 1, a_edge), 2.0)
	if picked:
		draw_line(Vector2(W * 0.18, 6), Vector2(W * 0.46, H - 6), Color(1, 1, 1, 0.12), 7.0)

func set_selected(v: bool) -> void:
	if selected == v:
		return
	selected = v
	queue_redraw()

func set_work(ratio: float) -> void:
	if is_equal_approx(work_ratio, ratio):
		return
	work_ratio = ratio
	queue_redraw()
