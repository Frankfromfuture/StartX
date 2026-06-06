extends Node2D
class_name PackCard

# 卡包尺寸（180×1.15×1.15≈238）；黑底、上下薄锯齿边、两侧「直线-微斜-直线」折面纺锤、
# 玻璃高光、白色像素图标+文字。
const W := 238.0
const H := 238.0
const TOOTH := 7.0           # 锯齿高度（更薄）
const TEETH := 11            # 上/下各 11 个齿（更细密）
const INSET := 16.0          # 上/下窄边的内收量（更小 → 微斜更平缓）
const SIDE_WIDE := 8.0       # 中部最宽处的内收量（中间直线段）
# 两侧折面的纵向断点（0=顶 1=底）：窄直(5%) → 微斜(10%) → 宽直(70%) → 微斜(10%) → 窄直(5%)
const SIDE_TS := [0.05, 0.15, 0.85, 0.95, 1.0]
const WIDE_T0 := 0.15        # 宽直线段起点
const WIDE_T1 := 0.85        # 宽直线段终点
const BODY := Color("141414")
const EDGE := Color("f2f2f2")
const PAPER := Color("f2f2f2")

static var _tex_cache: Dictionary = {}

var pack_id: String = ""
var pack_name: String = ""
var contents: Array = []
var opened := false
var ready_to_open := false
var board_pos: Vector2 = Vector2.ZERO
var pixel_font: Font

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 像素图标硬边

func setup(id: String, pname: String, card_ids: Array) -> void:
	pack_id = id
	pack_name = pname
	contents = card_ids.duplicate()
	queue_redraw()

func contains_point(global_pt: Vector2) -> bool:
	var local := to_local(global_pt)
	return local.x >= 0 and local.x <= W and local.y >= 0 and local.y <= H

# 折面纺锤的单侧内收量：中部断点为宽直线段，其余为窄，断点间自动连成微斜线
func _side_inset(t: float) -> float:
	return SIDE_WIDE if (t >= WIDE_T0 and t <= WIDE_T1) else INSET

# 黑底折面纺锤包体的轮廓多边形：上下窄、中部直线最宽，腰部以微斜线相连
func _body_poly() -> PackedVector2Array:
	var poly := PackedVector2Array()
	var y0 := TOOTH
	var y1 := H - TOOTH
	# 顶边：左→右薄锯齿，横向收窄到 [INSET, W-INSET]
	for i in range(TEETH + 1):
		var x := lerpf(INSET, W - INSET, float(i) / float(TEETH))
		var y := 0.0 if i % 2 == 1 else TOOTH
		poly.append(Vector2(x, y))
	# 右侧：直-斜-直-斜-直（自上而下）
	for t in SIDE_TS:
		poly.append(Vector2(W - _side_inset(t), lerpf(y0, y1, t)))
	# 底边：右→左薄锯齿
	for i in range(TEETH + 1):
		var x := lerpf(W - INSET, INSET, float(i) / float(TEETH))
		var y := H if i % 2 == 1 else H - TOOTH
		poly.append(Vector2(x, y))
	# 左侧：自下而上（镜像）
	for j in range(SIDE_TS.size() - 1, -1, -1):
		var t: float = SIDE_TS[j]
		poly.append(Vector2(_side_inset(t), lerpf(y0, y1, t)))
	return poly

func _draw() -> void:
	var poly := _body_poly()
	draw_colored_polygon(poly, BODY)

	# 玻璃高光：左上→右下的两道半透明斜带
	var sheen := PackedVector2Array([
		Vector2(INSET, TOOTH + 8), Vector2(W * 0.44, TOOTH + 8),
		Vector2(W * 0.22, H - TOOTH - 8), Vector2(INSET * 0.4, H - TOOTH - 8)])
	draw_colored_polygon(sheen, Color(1, 1, 1, 0.07))
	var streak := PackedVector2Array([
		Vector2(W * 0.52, TOOTH + 6), Vector2(W * 0.64, TOOTH + 6),
		Vector2(W * 0.42, H - TOOTH - 6), Vector2(W * 0.30, H - TOOTH - 6)])
	draw_colored_polygon(streak, Color(1, 1, 1, 0.05))

	# 白色描边（闭合）
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, EDGE, 3.0, true)

	# 像素图标（白色），居中偏上
	var tex := _icon_tex()
	if tex != null:
		var isz := 138.0
		var ix := (W - isz) * 0.5
		var iy := 30.0
		draw_texture_rect(tex, Rect2(ix, iy, isz, isz), false)

	# 分隔细线 + 包名文字（白）
	draw_line(Vector2(34, 182), Vector2(W - 34, 182), Color(1, 1, 1, 0.35), 2.0)
	var f := _ui_font()
	draw_string(f, Vector2(16, 218), pack_name, HORIZONTAL_ALIGNMENT_CENTER, W - 32, 26, PAPER)

	# 剩余张数角标（右上）：点一张少一张
	var n := contents.size()
	if n > 0:
		draw_circle(Vector2(W - 30, 30), 19, BODY)
		draw_circle(Vector2(W - 30, 30), 19, EDGE, false, 2.0)
		draw_string(f, Vector2(W - 49, 39), "×%d" % n, HORIZONTAL_ALIGNMENT_CENTER, 38, 22, PAPER)

func _icon_tex() -> Texture2D:
	if pack_id == "":
		return null
	if _tex_cache.has(pack_id):
		return _tex_cache[pack_id]
	var path := "res://assets/packs/%s.svg" % pack_id
	if not FileAccess.file_exists(path):
		_tex_cache[pack_id] = null
		return null
	var txt := FileAccess.get_file_as_string(path)
	txt = _tint_svg(txt, "#f2f2f2")
	var img := Image.new()
	var err := img.load_svg_from_string(txt, 1.0)
	if err != OK:
		_tex_cache[pack_id] = null
		return null
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[pack_id] = tex
	return tex

func _tint_svg(txt: String, color_hex: String) -> String:
	var out := txt
	out = out.replace("#141414", color_hex)
	out = out.replace("#000000", color_hex)
	out = out.replace("#000", color_hex)
	out = out.replace("fill=\"black\"", "fill=\"%s\"" % color_hex)
	if out.find("<svg ") != -1 and out.find("<svg fill=") == -1:
		out = out.replace("<svg ", "<svg fill=\"%s\" " % color_hex)
	return out

func _ui_font() -> Font:
	if pixel_font != null:
		return pixel_font
	var candidates := [
		"res://fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/Users/frankfan/Library/Fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/System/Library/Fonts/STHeiti Medium.ttc",
		"/System/Library/Fonts/PingFang.ttc",
		"/System/Library/Fonts/SFNSMono.ttf"
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
