extends Node2D
class_name Card
## A single draggable card, redesigned 100% in the Stacklands style.
## Drawn entirely via _draw (no image assets): 2:3 portrait, thick black
## outline, rounded corners, title bar + divider, centered black emblem on a
## light circular backing, black circular value badges with white numbers.

const W := 180.0          # square, keeping the previous long side
const H := 180.0
const HEADER := 30.0
const TITLE_FONT_SIZE := 21

var card_id: String = ""
var ctype: String = "resource"
var cdef: Dictionary = {}

var stack_id: int = -1
var stack_pos: int = 0
var zone: String = ""
var uses_left: int = -1       # -1 = unlimited; >=0 = remaining uses (nodes)
var cap_cur: int = 0          # 当前产能（类 HP；battle 拼产能会消耗后缓慢恢复，现在 == capacity）
var funds_max: int = 0        # 资金（战斗 HP）上限。对手卡自带，默认 = 产能 × 3
var funds_cur: int = 0        # 当前资金（战斗 HP）
var idle_t: float = 0.0       # idle time (for market auto-convert)

var work_ratio: float = 0.0       # 工作进度比例(0..1)，>0 即在本卡上方显示工作条
var work_elapsed: float = 0.0     # 已工作秒数，持久化在【被工作对象】卡上（员工离开也保留）

var drag_vel: Vector2 = Vector2.ZERO   # 拖拽弹簧的当前速度（用于滞后/摆动）
var selected: bool = false             # 单击选中
var hovered: bool = false
var carried: bool = false
var stack_hint: bool = false
var dash_phase: float = 0.0
var is_cash: bool = false            # 现金卡：金色玻璃质感 + hover 扫光
var shimmer_t: float = 0.0           # hover 扫光相位
var face3d: Node = null          # 3D 卡牌网格（Phase 2：本卡的真立体表现，挂在城市世界里）
var workbar3d: Node = null       # 生产进度条的 3D 表现（在 face3d 上方）
var shadow3d: Node = null        # 右下方柔和投影（hover 浅、拿起稍厚）
var ui_font: Font
var capacity_icon_tex: Texture2D
var cost_icon_tex: Texture2D
var star_icon_tex: Texture2D
var idea_icon_tex: Texture2D

# 每张卡的像素美术：优先 res://assets/cards/<卡牌名>.svg，其次兼容旧 <id>.svg / png。
static var _art_cache: Dictionary = {}

const INK := Color("141414")     # 黑描边 / 分割线 / 图标 / 数字圈
const BODY := Color("faf5ec")    # 奶白卡身

# 游戏分类 -> 莫兰迪淡彩标题栏色
func _header_color() -> Color:
	if card_id == "founder":
		return Color("e6b8c2")          # 创始人：换成办公室/设施红粉色
	if card_id == "cash":
		return Color("c8910f")          # 现金：饱满金（整体加深）
	if card_id == "revenue":
		return Color("ecd590")          # 金币 / 回款：黄
	if _is_black_series_card():
		return Color("2b2926")          # 第一包场景牌：创始人式黑灰系
	if _is_blue_series_card():
		return Color("8eb8d8")          # 产品牌：蓝色系
	if ctype == "business_model":
		return Color("4c3478")
	match ctype:
		"employee":      return Color("efe7d6")   # 人物：米白
		"resource_node": return Color("aebfcf")   # 资源（节点）：灰蓝
		"resource", "customer", "product":
			return Color("aeccb0")                 # 资源 / 客户 / 产品：绿色
		"facility":      return Color("e6b8c2")   # 建筑：粉红
		"risk":          return Color("d99a90")   # 怪物 / 风险：红
		"rival":         return Color("75383a")   # 对手：深红（略加饱和、整体加深）
		"idea":          return Color("2a2622")   # 想法 / 卡包：黑
		"department":    return Color("c2b6d6")   # 部门：雾紫
		_:               return Color("d8d2c4")

# 卡身颜色（与 _draw 里的 bg 一致）—— 供 3D 卡牌厚度涂成卡牌本身的颜色
func body_color() -> Color:
	var head := _header_color()
	var bg := head.lightened(0.28)
	if card_id == "founder":
		bg = Color("f4d7dd")
	if _is_black_series_card():
		bg = Color("d5d1c9")
	if _is_blue_series_card():
		bg = Color("d4e5f1")
	if ctype == "business_model":
		bg = Color("6b4ca0")
	return bg

func _is_black_series_card() -> bool:
	return card_id in ["office", "p1_office", "university", "p1_university", "p1_wholesale"]

func _is_blue_series_card() -> bool:
	return card_id in ["product", "p1_rawprod", "p1_package"]

func setup(id: String) -> void:
	card_id = id
	cdef = DataLoader.card_def(id)
	ctype = String(cdef.get("type", "resource"))
	# 试用次数：支持区间（maxUsesMin/Max）→ 每张实例随机取；否则用固定 maxUses
	if cdef.has("maxUsesMin"):
		uses_left = GameState.rng.randi_range(int(cdef["maxUsesMin"]), int(cdef["maxUsesMax"]))
	else:
		uses_left = int(cdef.get("maxUses", -1))
	cap_cur = int(cdef.get("capacity", 0))
	# 资金作为战斗 HP：对手卡自带资金，默认 = 产能 × 3（可由数据的 funds 字段覆盖）
	if ctype == "rival":
		funds_max = int(cdef.get("funds", cap_cur * 3))
		funds_cur = funds_max
	is_cash = (id == "cash")
	set_process(false)                  # 仅现金卡 hover 时才逐帧动
	queue_redraw()

func _draw() -> void:
	var head := _header_color()
	var dark_head := (ctype == "idea") or ctype == "business_model" or ctype == "rival" or _is_black_series_card()   # 深色底卡用反白文字
	var title_fg := Color("f7f2e8") if dark_head else INK   # 深色标题栏用浅字
	var bg := head.lightened(0.28)                          # 卡身 = header 浅一号，但整体更沉
	var ring := head.lightened(0.48)                        # 中间圆圈 = 更浅一号
	if card_id == "founder":
		bg = Color("f4d7dd")
		ring = Color("f8e6ea")
	if _is_black_series_card():
		bg = Color("d5d1c9")
		ring = Color("ece9e3")
	if _is_blue_series_card():
		bg = Color("d4e5f1")
		ring = Color("e8f2f8")
	if ctype == "business_model":
		bg = Color("6b4ca0")
		ring = Color("8f75bd")

	var lift_level := 0
	if hovered:
		lift_level = 1
	if carried:
		lift_level = 2

	# ---- 像素风卡身：硬投影 + 纯色身 + 复古斜面描边（无圆角无抗锯齿）----
	var off := 5.0 + 3.0 * lift_level
	draw_rect(Rect2(off, off, W, H), Color(0, 0, 0, 0.16 + 0.08 * lift_level), true)   # 硬投影块
	draw_rect(Rect2(0, 0, W, H), bg, true)                                            # 卡身平涂
	_pixel_frame(Rect2(0, 0, W, H), 8.0, INK, bg.lightened(0.30), bg.darkened(0.22))  # 斜面描边（加粗）

	# 选中不再画外圈黄框（仅保留信息栏提示与轻微光泽反馈）

	# 标题栏：缩进到粗框内（上/左/右与卡身同样的 8px 粗边）+ 加粗墨线分隔
	var bw := 8.0
	draw_rect(Rect2(bw, bw, W - bw * 2.0, HEADER), head, true)
	draw_rect(Rect2(bw, bw + HEADER, W - bw * 2.0, 5), INK, true)

	# 主体图像：浅圆底纹 + 居中黑色线稿剪影
	if ctype == "business_model":
		_draw_business_model_body()
	else:
		_draw_emblem(ring)

	# 标题：左对齐、纵向居中于标题栏
	var title_font := _ui_font()
	var title_y := bw + (HEADER - title_font.get_height(TITLE_FONT_SIZE)) * 0.5 + title_font.get_ascent(TITLE_FONT_SIZE)
	var title_text := "商业模式" if ctype == "business_model" else _card_name()
	_draw_bold_string(title_font, Vector2(12, title_y), title_text, HORIZONTAL_ALIGNMENT_LEFT, W - 24, TITLE_FONT_SIZE, title_fg)
	# 剩余试用次数：表头右上、与标题同字号加粗、右对齐、纵向居中
	if uses_left >= 0:
		_draw_bold_string(title_font, Vector2(bw, title_y), str(uses_left), HORIZONTAL_ALIGNMENT_RIGHT, W - bw * 2.0 - 6.0, TITLE_FONT_SIZE, title_fg)

	# 抖动高光（替代平滑渐变）
	_draw_dither_gloss(selected or hovered or carried)
	if is_cash:
		_draw_cash_glass(hovered or carried)

# 现金卡：金色玻璃质感 —— 镜面渐变 + 静态高光斜带 + hover 动态扫光
func _draw_cash_glass(active: bool) -> void:
	var bw := 8.0
	var ix := bw
	var iy := bw + HEADER + 5.0
	var iw := W - bw * 2.0
	var ih := H - iy - bw
	# 金色玻璃竖向渐变：顶部亮金 -> 底部琥珀，营造玻璃体积
	draw_polygon(
		PackedVector2Array([Vector2(ix, iy), Vector2(ix + iw, iy),
			Vector2(ix + iw, iy + ih), Vector2(ix, iy + ih)]),
		PackedColorArray([Color("f2d878") * Color(1, 1, 1, 0.42), Color("e0bd52") * Color(1, 1, 1, 0.38),
			Color("805208") * Color(1, 1, 1, 0.44), Color("9c6e0f") * Color(1, 1, 1, 0.38)]))
	# 顶部镜面高光带（玻璃面反光）
	draw_polygon(
		PackedVector2Array([Vector2(ix, iy), Vector2(ix + iw, iy),
			Vector2(ix + iw, iy + ih * 0.22), Vector2(ix, iy + ih * 0.30)]),
		PackedColorArray([Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.32), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))
	# 静态斜向高光条
	_glass_streak(ix, iy, iw, ih, 0.32, 0.10)
	# hover 动态扫光：一条更亮的高光斜带循环划过
	if active:
		var p := fmod(shimmer_t * 0.85, 1.0)          # 0..1 循环
		var sweep := lerpf(-0.15, 1.15, p)
		var fade := sin(p * PI)                          # 进出端点淡入淡出
		_glass_streak(ix, iy, iw, ih, sweep, 0.55 * fade)

# 在内框内画一条从上到下的斜向亮带，pos∈[0,1] 控制水平位置
func _glass_streak(ix: float, iy: float, iw: float, ih: float, pos: float, alpha: float) -> void:
	if alpha <= 0.001:
		return
	var slant := iw * 0.22
	var cxp := ix + iw * pos
	var ww := iw * 0.14
	for k in range(3):
		var a := alpha * (1.0 - float(k) * 0.34)
		var o := float(k) * ww * 0.7
		var top := cxp + slant + o
		var bot := cxp - slant + o
		var pts := PackedVector2Array([
			Vector2(clampf(top, ix, ix + iw), iy),
			Vector2(clampf(top + ww, ix, ix + iw), iy),
			Vector2(clampf(bot + ww, ix, ix + iw), iy + ih),
			Vector2(clampf(bot, ix, ix + iw), iy + ih)])
		draw_colored_polygon(pts, Color(1, 1, 1, a))

# 复古斜面像素描边：外框纯色 + 内左上提亮 / 内右下压暗
func _pixel_frame(r: Rect2, thick: float, dark: Color, light: Color, shade: Color) -> void:
	const VPX := 4.0
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	draw_rect(Rect2(x, y, w, thick), dark, true)
	draw_rect(Rect2(x, y + h - thick, w, thick), dark, true)
	draw_rect(Rect2(x, y, thick, h), dark, true)
	draw_rect(Rect2(x + w - thick, y, thick, h), dark, true)
	var ix := x + thick
	var iy := y + thick
	var iw := w - thick * 2.0
	var ih := h - thick * 2.0
	draw_rect(Rect2(ix, iy, iw, VPX), light, true)                 # 内·上 提亮
	draw_rect(Rect2(ix, iy, VPX, ih), light, true)                 # 内·左 提亮
	draw_rect(Rect2(ix, iy + ih - VPX, iw, VPX), shade, true)      # 内·下 压暗
	draw_rect(Rect2(ix + iw - VPX, iy, VPX, ih), shade, true)      # 内·右 压暗

func _draw_bold_string(f: Font, pos: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, col: Color) -> void:
	draw_string(f, pos, text, align, width, size, col)
	draw_string(f, pos + Vector2(0.4, 0), text, align, width, size, col)

# 抖动高光：标题栏下方几排棋盘格亮点，硬边，复古磨砂感
func _draw_dither_gloss(_picked: bool) -> void:
	# 卡面烘焙高光已去除（保持纯平涂，不受光照影响）
	# 底部角标：左下 = 月薪，右下 = 产能；名称区右上 = 剩余次数
	var salary := int(cdef.get("salary", 0))
	if salary > 0:
		_draw_salary_badge(Vector2(28, H - 29), str(salary))
	elif ctype == "customer" or ctype == "product":
		var value := int(cdef.get("value", 0))
		if value > 0:
			_draw_value_badge(Vector2(28, H - 29), str(value))
	var cap := int(cdef.get("capacity", 0))
	if cap > 0:
		_draw_capacity_badge(Vector2(W - 30, H - 29), str(cap))

	# 工作条：画在被生产的非人物卡标题栏正上方。生产被人物离开中断时，
	# work_ratio 仍保留在该目标卡上，重新加入员工后可继续原有进度。
	if work_ratio > 0.0:
		var bh := 15.0
		var bx := 8.0
		var bw2 := W - 16.0
		var by := 8.0 - bh - 10.0 # header 顶边(y=8) 再往上 10px，整条落在基牌 header 上方
		draw_rect(Rect2(bx, by, bw2, bh), Color("eceae4"), true)                              # 灰白底槽
		draw_rect(Rect2(bx, by, bw2 * clampf(work_ratio, 0, 1), bh), Color("bdbab1"), true)   # 灰进度
		draw_rect(Rect2(bx, by, bw2, bh), INK, false, 2.0)                                    # 黑描边

	if stack_hint:
		_draw_stack_hint()

# ---- emblem (centered black line-art on a light circular backing) ----------
func _draw_emblem(ring: Color) -> void:
	var col := INK                    # 剪影统一黑色线稿
	var cx := W * 0.5
	var cy := HEADER + (H - HEADER) * 0.44
	var u := W / 12.0 * 0.9
	# 更浅圆形底纹
	draw_circle(Vector2(cx, cy), W * 0.252, ring)

	# 像素美术优先：有专属 SVG 就铺在圆底上（保留底纹衬托），其余走程序化剪影
	var art := _card_art()
	if art != null:
		var s := W * 0.46
		draw_texture_rect(art, Rect2(cx - s * 0.5, cy - s * 0.5, s, s), false)
		return

	if card_id == "revenue":          # 金币
		draw_circle(Vector2(cx, cy), 2.6 * u, col)
		draw_rect(Rect2(cx - 0.8 * u, cy - 0.8 * u, 1.6 * u, 1.6 * u), ring, true)
		return

	# ---- 商业成果产物：各画专属剪影 ----
	if card_id == "product":          # 产品：封箱胶带的包裹
		draw_rect(Rect2(cx - 2.3 * u, cy - 2.0 * u, 4.6 * u, 4.4 * u), col)
		draw_rect(Rect2(cx - 2.3 * u, cy - 0.3 * u, 4.6 * u, 0.6 * u), ring)   # 横向胶带
		draw_rect(Rect2(cx - 0.35 * u, cy - 2.0 * u, 0.7 * u, 0.8 * u), ring)  # 顶部封口缝
		return
	if card_id == "proposal":         # 方案：带夹子的文案纸
		draw_rect(Rect2(cx - 2.0 * u, cy - 2.2 * u, 4.0 * u, 4.8 * u), col)
		draw_rect(Rect2(cx - 0.8 * u, cy - 2.7 * u, 1.6 * u, 0.7 * u), col)
		for i in range(3):
			draw_rect(Rect2(cx - 1.3 * u, cy - 1.1 * u + i * 1.1 * u, 2.6 * u, 0.42 * u), ring)
		return
	if card_id == "patent":           # 专利：证书 + 印章
		draw_rect(Rect2(cx - 2.1 * u, cy - 2.4 * u, 4.2 * u, 3.9 * u), col)
		for i in range(2):
			draw_rect(Rect2(cx - 1.4 * u, cy - 1.5 * u + i * 0.95 * u, 2.8 * u, 0.36 * u), ring)
		draw_circle(Vector2(cx, cy + 2.2 * u), 0.95 * u, col)
		draw_circle(Vector2(cx, cy + 2.2 * u), 0.45 * u, ring)
		return
	if card_id == "report":           # 报告：带柱状图的文档
		draw_rect(Rect2(cx - 2.0 * u, cy - 2.4 * u, 4.0 * u, 4.8 * u), col)
		draw_rect(Rect2(cx - 1.3 * u, cy + 0.5 * u, 0.7 * u, 1.3 * u), ring)
		draw_rect(Rect2(cx - 0.3 * u, cy - 0.4 * u, 0.7 * u, 2.2 * u), ring)
		draw_rect(Rect2(cx + 0.7 * u, cy - 1.3 * u, 0.7 * u, 3.1 * u), ring)
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
		"resource", "customer", "product":
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

func _draw_business_model_body() -> void:
	var icon := _idea_icon()
	var cx := W * 0.5
	var cy := HEADER + (H - HEADER) * 0.44
	draw_circle(Vector2(cx, cy), W * 0.252, Color("8f75bd"))
	if icon != null:
		var s := W * 0.46
		draw_texture_rect(icon, Rect2(cx - s * 0.5, cy - s * 0.5, s, s), false, Color.WHITE)
	else:
		draw_circle(Vector2(cx, cy), 2.0 * W / 12.0 * 0.9, Color.WHITE)

# ---- value badges: black icon silhouettes, white pixel number --------------
func _draw_salary_badge(center: Vector2, txt: String) -> void:
	const BADGE_RADIUS := 16.0
	var tex := _cost_icon()
	if tex != null:
		var size := Vector2(BADGE_RADIUS * 2.25, BADGE_RADIUS * 2.25)
		draw_texture_rect(tex, Rect2(center - size * 0.5, size), false, INK)
	else:
		draw_circle(center, BADGE_RADIUS, INK)
	_draw_badge_number(center, txt, BADGE_RADIUS)

func _draw_value_badge(center: Vector2, txt: String) -> void:
	const BADGE_RADIUS := 16.0
	var tex := _star_icon()
	if tex != null:
		var size := Vector2(BADGE_RADIUS * 2.25, BADGE_RADIUS * 2.25)
		draw_texture_rect(tex, Rect2(center - size * 0.5, size), false)
	else:
		draw_circle(center, BADGE_RADIUS, INK)
	_draw_badge_number(center, txt, BADGE_RADIUS)

func _draw_capacity_badge(center: Vector2, txt: String) -> void:
	const BADGE_RADIUS := 16.0
	var tex := _capacity_icon()
	if tex != null:
		var size := Vector2(BADGE_RADIUS * 2.25, BADGE_RADIUS * 2.25)
		draw_texture_rect(tex, Rect2(center - size * 0.5, size), false, INK)
	else:
		var pts := PackedVector2Array()
		for i in range(24):
			var a := -PI * 0.5 + float(i) / 24.0 * TAU
			var tooth := i % 2 == 0
			var r := BADGE_RADIUS if tooth else BADGE_RADIUS * 0.78
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, INK)
	draw_circle(center, BADGE_RADIUS * 0.48, INK)
	_draw_badge_number(center, txt, BADGE_RADIUS)

func _card_art() -> Texture2D:
	if card_id == "":
		return null
	var art_key := "%s|%s" % [card_id, _card_name()]
	if _art_cache.has(art_key):
		return _art_cache[art_key]
	var paths := _card_art_paths()
	for path in paths:
		var tex: Texture2D = null
		if FileAccess.file_exists(path):
			var img := Image.new()
			if path.ends_with(".png"):
				if img.load(path) == OK:
					tex = ImageTexture.create_from_image(img)
			else:
				# 16×8 = 128px 光栅，足够清晰且像素边缘锐利
				if img.load_svg_from_string(FileAccess.get_file_as_string(path), 8.0) == OK:
					tex = ImageTexture.create_from_image(img)
		elif ResourceLoader.exists(path):
			# web 导出剥离了源文件 → 用导入的纹理（svg 导入缩放已设为 8）
			tex = load(path) as Texture2D
		if tex != null:
			_art_cache[art_key] = tex
			return tex
	_art_cache[art_key] = null
	return null

func _card_art_paths() -> Array:
	var names: Array = []
	var display_name := _card_name().strip_edges()
	if display_name != "":
		names.append(display_name)
	if card_id != "" and not names.has(card_id):
		names.append(card_id)
	var paths: Array = []
	for n in names:
		paths.append("res://assets/cards/%s.svg" % n)
		paths.append("res://assets/cards/%s.png" % n)
	return paths

func _capacity_icon() -> Texture2D:
	if capacity_icon_tex != null:
		return capacity_icon_tex
	capacity_icon_tex = ResourceLoader.load("res://assets/gear.svg") as Texture2D
	return capacity_icon_tex

func _cost_icon() -> Texture2D:
	if cost_icon_tex != null:
		return cost_icon_tex
	cost_icon_tex = ResourceLoader.load("res://assets/cost.svg") as Texture2D
	return cost_icon_tex

func _star_icon() -> Texture2D:
	if star_icon_tex != null:
		return star_icon_tex
	star_icon_tex = ResourceLoader.load("res://assets/star.svg") as Texture2D
	return star_icon_tex

func _idea_icon() -> Texture2D:
	if idea_icon_tex != null:
		return idea_icon_tex
	var path := "res://assets/idea.svg"
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_svg_from_string(FileAccess.get_file_as_string(path), 1.0) == OK:
			idea_icon_tex = ImageTexture.create_from_image(img)
	elif ResourceLoader.exists(path):
		idea_icon_tex = load(path) as Texture2D
	return idea_icon_tex

func _draw_badge_number(center: Vector2, txt: String, radius: float) -> void:
	const BADGE_FONT_SIZE := 17
	var f := _ui_font()
	var w := radius * 2.0
	var y := center.y - f.get_height(BADGE_FONT_SIZE) * 0.5 + f.get_ascent(BADGE_FONT_SIZE)
	_draw_bold_string(f, Vector2(center.x - w * 0.5, y), txt, HORIZONTAL_ALIGNMENT_CENTER, w, BADGE_FONT_SIZE, Color.WHITE)

func _wrap_text(text: String, f: Font, size: int, width: float) -> Array:
	var out := []
	var line := ""
	for token in text.split(" ", false):
		var candidate := token if line == "" else line + " " + token
		if f.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			line = candidate
		else:
			if line != "":
				out.append(line)
			line = token
	if line != "":
		out.append(line)
	return out

func _card_name() -> String:
	return String(cdef.get("name", card_id))

func _ui_font() -> Font:
	if ui_font != null:
		return ui_font
	var candidates := [
		"res://fonts/SmileySans-Oblique.ttf",
		"res://fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/Users/frankfan/Library/Fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/System/Library/Fonts/PingFang.ttc"
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
		# MSDF：字形以有向距离场存储，烘焙时从 180→1024 放大仍保持锐利（不再发糊）
		ff.multichannel_signed_distance_field = true
		ff.msdf_pixel_range = 8
		ff.msdf_size = 64
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
	"proposal": "PROPOSAL", "patent": "PATENT", "report": "REPORT",
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

func _process(delta: float) -> void:
	# 仅现金卡在 hover/携带时启用：推进扫光相位并重绘
	shimmer_t += delta
	queue_redraw()

func set_hovered(v: bool) -> void:
	if hovered == v:
		return
	hovered = v
	if is_cash:
		if v:
			shimmer_t = 0.0
		set_process(v or carried)
	queue_redraw()

func set_carried(v: bool) -> void:
	if carried == v:
		return
	carried = v
	if is_cash:
		set_process(v or hovered)
	queue_redraw()

func set_stack_hint(v: bool) -> void:
	if stack_hint == v:
		return
	stack_hint = v
	queue_redraw()

func set_dash_phase(v: float) -> void:
	dash_phase = v
	if stack_hint:
		queue_redraw()

func set_work(ratio: float) -> void:
	if is_equal_approx(work_ratio, ratio):
		return
	work_ratio = ratio
	queue_redraw()

func _draw_stack_hint() -> void:
	var rect := Rect2(-4, -4, W + 8, H + 8)
	var col := Color(0.18, 0.17, 0.16, 0.92)
	var width := 8.0
	var dash := 20.0
	var gap := 10.0
	_draw_dashed_side(rect.position, rect.position + Vector2(rect.size.x, 0), dash, gap, dash_phase, col, width)
	_draw_dashed_side(rect.position + Vector2(rect.size.x, 0), rect.position + rect.size, dash, gap, dash_phase + 7.0, col, width)
	_draw_dashed_side(rect.position + rect.size, rect.position + Vector2(0, rect.size.y), dash, gap, dash_phase + 14.0, col, width)
	_draw_dashed_side(rect.position + Vector2(0, rect.size.y), rect.position, dash, gap, dash_phase + 21.0, col, width)

func _draw_dashed_side(a: Vector2, b: Vector2, dash: float, gap: float, phase: float, col: Color, width: float) -> void:
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
			draw_line(a + dir * from, a + dir * to, col, width)
		pos += period
