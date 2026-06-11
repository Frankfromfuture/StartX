extends Control
## RimWorld-style research tree: solid CIRCLE nodes with pixel icons + a progress
## ring (RP toward cost), rounded-diagonal connectors, hover tooltip + chain
## highlight. Left-drag / wheel to pan, left-click to research, right-click close.

const COL_W := 330.0
const ROW_H := 168.0
const R := 40.0
const STUB := 26.0
const OX := 60.0
const OY := 110.0

var center_pos: Dictionary = {}     # id -> Vector2 (circle center, graph space)
var children: Dictionary = {}
var pan := Vector2.ZERO
var graph_w := 0.0
var graph_h := 0.0
var hovered := ""
var panning := false
var mouse_pos := Vector2.ZERO
var font: Font

func _ready() -> void:
	font = _ui_font()
	mouse_filter = Control.MOUSE_FILTER_STOP
	for id in DataLoader.research.keys():
		var d: Dictionary = DataLoader.research[id]
		var cx := OX + float(d.get("col", 0)) * COL_W + R
		var cy := OY + float(d.get("row", 0)) * ROW_H + R
		center_pos[String(id)] = Vector2(cx, cy)
		graph_w = maxf(graph_w, cx + R)
		graph_h = maxf(graph_h, cy + R + 40.0)
		children[String(id)] = []
	for id in DataLoader.research.keys():
		var d: Dictionary = DataLoader.research[id]
		for pre in d.get("prereq", []):
			if children.has(String(pre)):
				children[String(pre)].append(String(id))

func _ui_font() -> Font:
	var candidates := [
		"res://fonts/SmileySans-Oblique.ttf",
		"res://fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/Users/frankfan/Library/Fonts/HarmonyOS_Sans_SC_Regular.ttf",
		"/System/Library/Fonts/STHeiti Medium.ttc",
		"/System/Library/Fonts/PingFang.ttc",
		"/System/Library/Fonts/SFNSMono.ttf"
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
		return ff
	return ThemeDB.fallback_font

func _process(_dt: float) -> void:
	if visible:
		queue_redraw()

func _center(id: String) -> Vector2:
	return center_pos[id] + pan

func _clamp_pan() -> void:
	pan.x = clampf(pan.x, minf(0.0, size.x - graph_w - OX), 0.0)
	pan.y = clampf(pan.y, minf(0.0, size.y - graph_h - 40.0), 0.0)

# ---- chain ------------------------------------------------------------------
func _collect_anc(id: String, acc: Dictionary) -> void:
	for pre in DataLoader.research.get(id, {}).get("prereq", []):
		var p := String(pre)
		if not acc.has(p):
			acc[p] = true
			_collect_anc(p, acc)

func _collect_desc(id: String, acc: Dictionary) -> void:
	for ch in children.get(id, []):
		var c := String(ch)
		if not acc.has(c):
			acc[c] = true
			_collect_desc(c, acc)

func _highlight_set() -> Dictionary:
	if hovered == "":
		return {}
	var s := { hovered: true }
	_collect_anc(hovered, s)
	_collect_desc(hovered, s)
	return s

# ---- helpers ----------------------------------------------------------------
func _kind_color(kind: String) -> Color:
	match kind:
		"recipe":    return Color("aecbe0")   # 淡天蓝
		"feature":   return Color("c2b6d6")   # 雾紫
		"event":     return Color("e0c39a")   # 暖砂橙
		"valuation": return Color("a9c9b4")   # 雾绿
		_:           return Color("c4bcae")

func _kind_label(kind: String) -> String:
	match kind:
		"recipe":    return "配方"
		"feature":   return "功能"
		"event":     return "事件"
		"valuation": return "估值"
		_:           return "?"

func _smooth(pts: PackedVector2Array, iters: int) -> PackedVector2Array:
	var p := pts
	for _i in iters:
		var np := PackedVector2Array()
		np.append(p[0])
		for j in range(p.size() - 1):
			var a: Vector2 = p[j]
			var b: Vector2 = p[j + 1]
			np.append(a.lerp(b, 0.25))
			np.append(a.lerp(b, 0.75))
		np.append(p[p.size() - 1])
		p = np
	return p

func _connector(ca: Vector2, cb: Vector2, col: Color, w: float) -> void:
	var a := ca + Vector2(R, 0)
	var b := cb - Vector2(R, 0)
	var p1 := a + Vector2(STUB, 0)
	var p2 := b - Vector2(STUB, 0)
	var path := _smooth(PackedVector2Array([a, p1, p2, b]), 3)
	draw_polyline(path, col, w, true)

# pixel icon (blocky cells) centered at c
func _icon(kind: String, c: Vector2, col: Color) -> void:
	var bs := 5.0
	var cells: Array = []
	match kind:
		"recipe":     # gear-ish
			cells = [Vector2i(0,-2),Vector2i(0,2),Vector2i(-2,0),Vector2i(2,0),Vector2i(0,0),Vector2i(-1,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1)]
		"feature":    # spark / star
			cells = [Vector2i(0,-2),Vector2i(0,-1),Vector2i(0,0),Vector2i(0,1),Vector2i(0,2),Vector2i(-2,0),Vector2i(-1,0),Vector2i(1,0),Vector2i(2,0)]
		"event":      # lightning bolt
			cells = [Vector2i(1,-2),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),Vector2i(0,0),Vector2i(0,1),Vector2i(-1,1),Vector2i(0,2)]
		"valuation":  # rising bars
			cells = [Vector2i(-2,2),Vector2i(-1,1),Vector2i(-1,2),Vector2i(0,0),Vector2i(0,1),Vector2i(0,2),Vector2i(1,-1),Vector2i(1,0),Vector2i(1,1),Vector2i(1,2)]
		_:
			cells = [Vector2i(0,0)]
	for cell in cells:
		var cv: Vector2i = cell
		var p := c + Vector2(cv.x * bs - bs * 0.5, cv.y * bs - bs * 0.5)
		draw_rect(Rect2(p, Vector2(bs, bs)), col, true)

# ---- draw -------------------------------------------------------------------
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.937, 0.906, 0.847, 0.97), true)
	draw_string(font, Vector2(OX, 46),
		"研发树    RP %d    阶段「%s」    悬停看详情/前置链 · 拖动/滚轮平移 · 右键关闭"
		% [int(GameState.rp), GameState.stage_name()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("3a352f"))

	var hl := _highlight_set()
	var has_hl := not hl.is_empty()

	for id in center_pos.keys():
		var d: Dictionary = DataLoader.research[id]
		for pre in d.get("prereq", []):
			var p := String(pre)
			if not center_pos.has(p):
				continue
			var on_chain := has_hl and hl.has(p) and hl.has(id)
			var col: Color
			if GameState.idea_done(p):
				col = Color(0.42, 0.62, 0.48, 0.9)
			else:
				col = Color(0.36, 0.33, 0.29, 0.4)
			if has_hl and not on_chain:
				col.a *= 0.16
			elif on_chain:
				col = Color(0.83, 0.62, 0.32, 0.95)
			_connector(_center(p), _center(id), col, 4.0 if on_chain else 3.0)

	for id in center_pos.keys():
		_draw_node(String(id), hl, has_hl)

	if hovered != "":
		_draw_tooltip(hovered)

func _draw_node(id: String, hl: Dictionary, has_hl: bool) -> void:
	var d: Dictionary = DataLoader.research[id]
	var c := _center(id)
	if c.x < -R * 2 or c.x > size.x + R * 2 or c.y < -R * 2 or c.y > size.y + R * 2:
		return
	var kind := String(d.get("kind", ""))
	var base := _kind_color(kind)
	var done := GameState.idea_done(id)
	var avail := GameState.can_unlock(id)
	var gate_ok := GameState.stage >= int(d.get("stage", 0)) and _prereq_ok(d)
	var dim := has_hl and not hl.has(id)

	var fill := base
	if done:
		fill = base.lightened(0.08)
	elif not gate_ok:
		fill = base.darkened(0.5)
	if dim:
		fill.a = 0.22
	# solid circle
	draw_circle(c, R, fill)
	# pixel icon — 深墨图标，淡彩底上更清晰
	var icon_col := Color(0.227, 0.208, 0.184, 0.92 if not dim else 0.3)
	_icon(kind, c, icon_col)

	# progress / state ring
	var cost := float(d.get("cost", 0))
	if done:
		draw_arc(c, R + 3, 0, TAU, 48, Color(0.42, 0.66, 0.5, 0.9 if not dim else 0.3), 4.0, true)
	elif gate_ok:
		draw_arc(c, R + 3, 0, TAU, 48, Color(0.36, 0.33, 0.29, 0.3), 4.0, true)
		var prog := clampf(GameState.rp / max(1.0, cost), 0.0, 1.0)
		var ring := Color("d9a552") if prog >= 1.0 else Color("6f9bbf")
		if dim:
			ring.a = 0.3
		draw_arc(c, R + 3, -PI / 2, -PI / 2 + TAU * prog, 48, ring, 5.0, true)
	# border ring
	var border := Color("d9a552") if avail else (Color(0.42, 0.66, 0.5) if done else Color(0.36, 0.33, 0.29, 0.55))
	if id == hovered:
		border = Color("3a352f")
	if dim:
		border.a = 0.3
	draw_arc(c, R, 0, TAU, 48, border, 3.0 if (avail or done or id == hovered) else 2.0, true)

	# label below
	var ta := 1.0 if not dim else 0.3
	draw_string(font, Vector2(c.x - COL_W * 0.5, c.y + R + 22),
		String(d.get("name", id)), HORIZONTAL_ALIGNMENT_CENTER, COL_W, 18, Color(0.227, 0.208, 0.184, ta))
	var sl := ""
	if done:
		sl = "✓已研发"
	elif not (GameState.stage >= int(d.get("stage", 0))):
		sl = "需「%s」" % GameState.STAGE_NAMES[int(d.get("stage", 0))]
	elif not _prereq_ok(d):
		sl = "缺前置"
	else:
		sl = "%d/%d RP" % [int(GameState.rp), int(cost)]
	draw_string(font, Vector2(c.x - COL_W * 0.5, c.y + R + 42),
		sl, HORIZONTAL_ALIGNMENT_CENTER, COL_W, 14, Color(0.45, 0.42, 0.37, ta))

func _draw_tooltip(id: String) -> void:
	var d: Dictionary = DataLoader.research[id]
	var lines: Array = []
	lines.append("%s  [%s]" % [String(d.get("name", id)), _kind_label(String(d.get("kind", "")))])
	lines.append("阶段「%s」 · %d RP" % [GameState.STAGE_NAMES[int(d.get("stage", 0))], int(d.get("cost", 0))])
	var pretext := "无"
	var prl: Array = d.get("prereq", [])
	for i in prl.size():
		var prd: Dictionary = DataLoader.research.get(String(prl[i]), {})
		if i == 0:
			pretext = ""
		pretext += String(prd.get("name", prl[i]))
		if i < prl.size() - 1:
			pretext += ", "
	lines.append("前置：" + pretext)
	lines.append(String(d.get("desc", "")))
	var w := 460.0
	var h := 28.0 + lines.size() * 26.0
	var pos := mouse_pos + Vector2(18, 18)
	pos.x = minf(pos.x, size.x - w - 10)
	pos.y = minf(pos.y, size.y - h - 10)
	draw_rect(Rect2(pos, Vector2(w, h)), Color("fbf6ec"), true)
	draw_rect(Rect2(pos, Vector2(w, h)), Color("3a352f"), false, 2.0)
	var y := pos.y + 26.0
	for i in lines.size():
		var col := Color("b5803a") if i == 0 else Color(0.36, 0.33, 0.29)
		draw_string(font, Vector2(pos.x + 12, y), String(lines[i]),
			HORIZONTAL_ALIGNMENT_LEFT, w - 24, 18 if i == 0 else 15, col)
		y += 26.0

func _prereq_ok(d: Dictionary) -> bool:
	for pre in d.get("prereq", []):
		if not GameState.idea_done(String(pre)):
			return false
	return true

func _node_at(pos: Vector2) -> String:
	for id in center_pos.keys():
		if _center(String(id)).distance_to(pos) <= R:
			return String(id)
	return ""

# ---- input ------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			visible = false
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			pan.x += 80.0; _clamp_pan(); return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			pan.x -= 80.0; _clamp_pan(); return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hit := _node_at(event.position)
				if hit != "":
					GameState.unlock_idea(hit)
				else:
					panning = true
			else:
				panning = false
	elif event is InputEventMouseMotion:
		mouse_pos = event.position
		if panning:
			pan += event.relative
			_clamp_pan()
		else:
			hovered = _node_at(event.position)
