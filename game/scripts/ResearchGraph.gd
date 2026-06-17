extends Control
## Kingdom Rush-style research room: five vertical upgrade branches, each rising
## through five tiers from bottom to top.

const CHAINS := ["basic", "org", "supply", "competition", "capital"]
const CHAIN_LABELS := {
	"basic": "基础规则",
	"org": "组织",
	"supply": "供应链",
	"competition": "竞争",
	"capital": "资本",
}
const CHAIN_SUBTITLES := {
	"basic": "操作 / 节奏",
	"org": "人才 / 部门",
	"supply": "资源 / 自动化",
	"competition": "商战 / 壁垒",
	"capital": "现金 / 估值",
}
const CHAIN_KINDS := {
	"basic": "feature",
	"org": "recipe",
	"supply": "feature",
	"competition": "event",
	"capital": "valuation",
}
const CHAIN_W := 286.0
const TIER_H := 118.0
const NODE_R := 34.0
const LANE_OFFSET := 48.0
const TOP_PAD := 132.0
const LEFT_PAD := 74.0
const ROOM_H := 680.0

var center_pos: Dictionary = {}
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
	_build_layout()

func _build_layout() -> void:
	center_pos.clear()
	children.clear()
	graph_w = LEFT_PAD * 2.0 + CHAIN_W * CHAINS.size()
	graph_h = TOP_PAD + ROOM_H + 90.0
	for id in DataLoader.research.keys():
		var d: Dictionary = DataLoader.research[id]
		var chain := String(d.get("chain", "basic"))
		var col := maxi(0, CHAINS.find(chain))
		var tier := clampi(int(d.get("tier", int(d.get("row", 0)) + 1)), 1, 5)
		var lane := float(d.get("lane", 0))
		var cx := LEFT_PAD + CHAIN_W * col + CHAIN_W * 0.5 + lane * LANE_OFFSET
		var cy := TOP_PAD + ROOM_H - 82.0 - float(tier - 1) * TIER_H
		center_pos[String(id)] = Vector2(cx, cy)
		children[String(id)] = []
	for id in DataLoader.research.keys():
		var d: Dictionary = DataLoader.research[id]
		for pre in _all_prereqs(d):
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
	pan.x = clampf(pan.x, minf(0.0, size.x - graph_w - 24.0), 0.0)
	pan.y = clampf(pan.y, minf(0.0, size.y - graph_h - 24.0), 0.0)

func _collect_anc(id: String, acc: Dictionary) -> void:
	for pre in _all_prereqs(DataLoader.research.get(id, {})):
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

func _chain_color(chain: String) -> Color:
	match chain:
		"basic": return Color("6f8fa8")
		"org": return Color("a56f75")
		"supply": return Color("6f956f")
		"competition": return Color("b77b52")
		"capital": return Color("9a82b8")
		_: return Color("8d8578")

func _kind_color(kind: String) -> Color:
	match kind:
		"recipe": return Color("aecbe0")
		"feature": return Color("c2b6d6")
		"event": return Color("e0c39a")
		"valuation": return Color("a9c9b4")
		_: return Color("d5c9b8")

func _kind_label(kind: String) -> String:
	match kind:
		"recipe": return "配方"
		"feature": return "功能"
		"event": return "事件"
		"valuation": return "估值"
		_: return "研发"

func _draw() -> void:
	_build_layout()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.075, 0.067, 0.058, 0.92), true)
	draw_rect(Rect2(Vector2(18, 18), size - Vector2(36, 36)), Color("efe5d2"), true)
	draw_rect(Rect2(Vector2(18, 18), size - Vector2(36, 36)), Color("332f2a"), false, 4.0)
	draw_string(font, Vector2(48, 62),
		"研发室    RP %d    阶段「%s」    左键研发 · 悬停查看链路 · 拖动/滚轮移动 · 右键关闭"
		% [int(GameState.rp), GameState.stage_name()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("332f2a"))

	_draw_rooms()
	var hl := _highlight_set()
	var has_hl := not hl.is_empty()
	_draw_connectors(hl, has_hl)
	for id in center_pos.keys():
		_draw_node(String(id), hl, has_hl)
	if hovered != "":
		_draw_tooltip(hovered)

func _draw_rooms() -> void:
	for i in CHAINS.size():
		var chain := String(CHAINS[i])
		var x := LEFT_PAD + CHAIN_W * i + pan.x
		var y := TOP_PAD + pan.y
		var rect := Rect2(Vector2(x + 10, y), Vector2(CHAIN_W - 20, ROOM_H))
		var col := _chain_color(chain)
		draw_rect(rect.grow(8), Color(0, 0, 0, 0.18), true)
		draw_rect(rect, Color("fbf4e7"), true)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 58)), col.darkened(0.12), true)
		draw_rect(rect, Color("332f2a"), false, 3.0)
		draw_string(font, rect.position + Vector2(0, 36), String(CHAIN_LABELS[chain]),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 25, Color("fbf4e7"))
		draw_string(font, rect.position + Vector2(0, 76), String(CHAIN_SUBTITLES[chain]),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 15, Color("7a7167"))
		for tier in range(1, 6):
			var cy := TOP_PAD + ROOM_H - 82.0 - float(tier - 1) * TIER_H + pan.y
			var line_col := Color("d9cbb7") if tier % 2 == 1 else Color("e8decd")
			draw_line(Vector2(rect.position.x + 18, cy), Vector2(rect.end.x - 18, cy), line_col, 2.0)
			draw_string(font, Vector2(rect.position.x + 12, cy - 8), str(tier),
				HORIZONTAL_ALIGNMENT_LEFT, 24, 13, Color("8a8175"))
		_draw_chain_icon(chain, rect.position + Vector2(rect.size.x * 0.5, rect.size.y - 26), col)

func _draw_chain_icon(chain: String, c: Vector2, col: Color) -> void:
	draw_circle(c, 18, col.lightened(0.12))
	draw_arc(c, 18, 0, TAU, 32, Color("332f2a"), 2.0, true)
	_icon(String(CHAIN_KINDS[chain]), c, Color("332f2a"))

func _draw_connectors(hl: Dictionary, has_hl: bool) -> void:
	for id in center_pos.keys():
		var d: Dictionary = DataLoader.research[id]
		for pre in _all_prereqs(d):
			var p := String(pre)
			if not center_pos.has(p):
				continue
			var on_chain := has_hl and hl.has(p) and hl.has(id)
			var col := Color(0.34, 0.31, 0.27, 0.42)
			if GameState.idea_done(p):
				col = Color(0.38, 0.58, 0.42, 0.9)
			if has_hl and not on_chain:
				col.a *= 0.16
			elif on_chain:
				col = Color("d49a42")
			_connector(_center(p), _center(id), col, 5.0 if on_chain else 3.0)

func _connector(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var start := a + Vector2(0, -NODE_R)
	var finish := b + Vector2(0, NODE_R)
	var mid_y := (start.y + finish.y) * 0.5
	var pts := PackedVector2Array([start, Vector2(start.x, mid_y), Vector2(finish.x, mid_y), finish])
	draw_polyline(pts, Color(0, 0, 0, col.a * 0.28), w + 5.0, true)
	draw_polyline(pts, col, w, true)

func _draw_node(id: String, hl: Dictionary, has_hl: bool) -> void:
	var d: Dictionary = DataLoader.research[id]
	var c := _center(id)
	if c.x < -NODE_R * 2 or c.x > size.x + NODE_R * 2 or c.y < -NODE_R * 3 or c.y > size.y + NODE_R * 3:
		return
	var chain := String(d.get("chain", "basic"))
	var kind := String(d.get("kind", "feature"))
	var done := GameState.idea_done(id)
	var avail := GameState.can_unlock(id)
	var gate_ok := GameState.stage >= int(d.get("stage", 0)) and _prereq_ok(d)
	var dim := has_hl and not hl.has(id)
	var base := _kind_color(kind)
	if done:
		base = _chain_color(chain).lightened(0.18)
	elif not gate_ok:
		base = Color("8c8176")
	if dim:
		base.a = 0.24
	draw_circle(c + Vector2(4, 6), NODE_R + 6, Color(0, 0, 0, 0.18 if not dim else 0.05))
	draw_circle(c, NODE_R + 7, Color("332f2a"))
	draw_circle(c, NODE_R + 2, Color("fff7ea"))
	draw_circle(c, NODE_R - 4, base)
	var icon_col := Color("332f2a")
	icon_col.a = 0.9 if not dim else 0.25
	_icon(kind, c, icon_col)
	var cost := float(d.get("cost", 0))
	if done:
		var done_col := Color("5c9b67")
		done_col.a = 0.95 if not dim else 0.25
		draw_arc(c, NODE_R + 10, 0, TAU, 48, done_col, 4.0, true)
	elif gate_ok:
		var base_ring := Color("332f2a")
		base_ring.a = 0.26
		draw_arc(c, NODE_R + 10, 0, TAU, 48, base_ring, 4.0, true)
		var prog := clampf(GameState.rp / maxf(1.0, cost), 0.0, 1.0)
		draw_arc(c, NODE_R + 10, -PI / 2, -PI / 2 + TAU * prog, 48,
			Color("d49a42") if prog >= 1.0 else Color("5b8fb4"), 5.0, true)
	if avail:
		draw_arc(c, NODE_R + 14, 0, TAU, 48, Color("d49a42"), 3.0, true)
	elif id == hovered:
		draw_arc(c, NODE_R + 14, 0, TAU, 48, Color("332f2a"), 3.0, true)
	var ta := 1.0 if not dim else 0.3
	var title_col := Color("332f2a")
	title_col.a = ta
	draw_string(font, Vector2(c.x - 72, c.y + NODE_R + 22), String(d.get("name", id)),
		HORIZONTAL_ALIGNMENT_CENTER, 144, 16, title_col)
	var sl := ""
	if done:
		sl = "已研发"
	elif not (GameState.stage >= int(d.get("stage", 0))):
		sl = "需%s" % GameState.STAGE_NAMES[int(d.get("stage", 0))]
	elif not _prereq_ok(d):
		sl = "缺前置"
	else:
		sl = "%d/%d RP" % [int(GameState.rp), int(cost)]
	var status_col := Color("6f665c")
	status_col.a = ta
	draw_string(font, Vector2(c.x - 72, c.y + NODE_R + 39), sl,
		HORIZONTAL_ALIGNMENT_CENTER, 144, 13, status_col)

func _icon(kind: String, c: Vector2, col: Color) -> void:
	var bs := 4.8
	var cells: Array = []
	match kind:
		"recipe":
			cells = [Vector2i(0,-2),Vector2i(0,2),Vector2i(-2,0),Vector2i(2,0),Vector2i(0,0),Vector2i(-1,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1)]
		"feature":
			cells = [Vector2i(0,-2),Vector2i(0,-1),Vector2i(0,0),Vector2i(0,1),Vector2i(0,2),Vector2i(-2,0),Vector2i(-1,0),Vector2i(1,0),Vector2i(2,0)]
		"event":
			cells = [Vector2i(1,-2),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),Vector2i(0,0),Vector2i(0,1),Vector2i(-1,1),Vector2i(0,2)]
		"valuation":
			cells = [Vector2i(-2,2),Vector2i(-1,1),Vector2i(-1,2),Vector2i(0,0),Vector2i(0,1),Vector2i(0,2),Vector2i(1,-1),Vector2i(1,0),Vector2i(1,1),Vector2i(1,2)]
		_:
			cells = [Vector2i(0,0)]
	for cell in cells:
		var cv: Vector2i = cell
		var p := c + Vector2(cv.x * bs - bs * 0.5, cv.y * bs - bs * 0.5)
		draw_rect(Rect2(p, Vector2(bs, bs)), col, true)

func _draw_tooltip(id: String) -> void:
	var d: Dictionary = DataLoader.research[id]
	var lines: Array = []
	lines.append("%s  [%s · %s层]" % [
		String(d.get("name", id)),
		String(CHAIN_LABELS.get(String(d.get("chain", "basic")), "研发")),
		str(int(d.get("tier", 1)))
	])
	lines.append("阶段「%s」 · %d RP · %s" % [
		GameState.STAGE_NAMES[int(d.get("stage", 0))],
		int(d.get("cost", 0)),
		_kind_label(String(d.get("kind", "")))
	])
	var pretext := "无"
	var prl: Array = _all_prereqs(d)
	for i in prl.size():
		var prd: Dictionary = DataLoader.research.get(String(prl[i]), {})
		if i == 0:
			pretext = ""
		pretext += String(prd.get("name", prl[i]))
		if i < prl.size() - 1:
			pretext += ", "
	lines.append(("任选前置：" if not d.get("anyPrereq", []).is_empty() else "前置：") + pretext)
	lines.append(String(d.get("desc", "")))
	var w := 500.0
	var h := 30.0 + lines.size() * 25.0
	var pos := mouse_pos + Vector2(18, 18)
	pos.x = minf(pos.x, size.x - w - 10)
	pos.y = minf(pos.y, size.y - h - 10)
	draw_rect(Rect2(pos + Vector2(5, 6), Vector2(w, h)), Color(0, 0, 0, 0.22), true)
	draw_rect(Rect2(pos, Vector2(w, h)), Color("fbf4e7"), true)
	draw_rect(Rect2(pos, Vector2(w, h)), Color("332f2a"), false, 2.0)
	var y := pos.y + 25.0
	for i in lines.size():
		var col := Color("9b6a2f") if i == 0 else Color("332f2a")
		draw_string(font, Vector2(pos.x + 12, y), String(lines[i]),
			HORIZONTAL_ALIGNMENT_LEFT, w - 24, 18 if i == 0 else 15, col)
		y += 25.0

func _prereq_ok(d: Dictionary) -> bool:
	for pre in d.get("prereq", []):
		if not GameState.idea_done(String(pre)):
			return false
	var any_prereq: Array = d.get("anyPrereq", [])
	if not any_prereq.is_empty():
		for pre in any_prereq:
			if GameState.idea_done(String(pre)):
				return true
		return false
	return true

func _all_prereqs(d: Dictionary) -> Array:
	var out: Array = []
	for pre in d.get("prereq", []):
		out.append(pre)
	for pre in d.get("anyPrereq", []):
		out.append(pre)
	return out

func _node_at(pos: Vector2) -> String:
	for id in center_pos.keys():
		if _center(String(id)).distance_to(pos) <= NODE_R + 12.0:
			return String(id)
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			visible = false
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			pan.y += 80.0
			_clamp_pan()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			pan.y -= 80.0
			_clamp_pan()
			return
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
