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
const TOP_PAD := 40.0 # Adjusted padding inside GraphArea to center contents
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

# Node components built programmatically
var backdrop: ColorRect
var window_frame: Control
var graph_area: Control
var close_btn: Button

func _ready() -> void:
	font = _ui_font()
	mouse_filter = Control.MOUSE_FILTER_STOP # Capture clicks outside window to close
	
	# 1. Frosted Glass Backdrop
	var shader := Shader.new()
	shader.code = """
	shader_type canvas_item;
	uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
	uniform float lod : hint_range(0.0, 5.0) = 3.0;
	void fragment() {
		COLOR = textureLod(screen_texture, SCREEN_UV, lod);
		COLOR.rgb *= 0.7; // Darken for focus
	}
	"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	
	backdrop = ColorRect.new()
	backdrop.name = "BlurBackdrop"
	backdrop.size = Vector2(1920, 1080)
	backdrop.material = mat
	add_child(backdrop)
	
	# 2. Window Frame
	window_frame = Control.new()
	window_frame.name = "WindowFrame"
	window_frame.size = Vector2(1600, 850)
	window_frame.position = Vector2((1920 - 1600) * 0.5, (1080 - 850) * 0.5)
	window_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(window_frame)
	window_frame.draw.connect(_on_window_frame_draw)
	
	# 3. Graph Area (under title bar)
	graph_area = Control.new()
	graph_area.name = "GraphArea"
	graph_area.size = Vector2(1600, 850 - 60)
	graph_area.position = Vector2(0, 60)
	graph_area.clip_contents = true
	graph_area.mouse_filter = Control.MOUSE_FILTER_STOP
	window_frame.add_child(graph_area)
	graph_area.draw.connect(_on_graph_area_draw)
	graph_area.gui_input.connect(_on_graph_area_input)
	
	# 4. Interactive Close Button ("X")
	close_btn = Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.size = Vector2(40, 40)
	close_btn.position = Vector2(1600 - 48, 10)
	close_btn.add_theme_font_override("font", font)
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.add_theme_color_override("font_color", Color("332f2a"))
	close_btn.add_theme_color_override("font_hover_color", Color("a56f75"))
	close_btn.add_theme_color_override("font_pressed_color", Color("a56f75"))
	close_btn.flat = true
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.pressed.connect(func(): visible = false)
	window_frame.add_child(close_btn)
	
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
		if window_frame:
			window_frame.queue_redraw()
		if graph_area:
			graph_area.queue_redraw()

func _center(id: String) -> Vector2:
	return center_pos[id] + pan

func _clamp_pan() -> void:
	if graph_area == null:
		return
	pan.x = clampf(pan.x, minf(0.0, graph_area.size.x - graph_w - 24.0), 0.0)
	pan.y = clampf(pan.y, minf(0.0, graph_area.size.y - graph_h - 24.0), 0.0)

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

# Main control draw (empty because we draw in WindowFrame and GraphArea)
func _draw() -> void:
	pass

# 5. Draw the premium floating Window Frame
func _on_window_frame_draw() -> void:
	var w_size := window_frame.size
	
	# Window Drop Shadow (soft dark border expansion)
	var shadow_sb := StyleBoxFlat.new()
	shadow_sb.bg_color = Color(0, 0, 0, 0.35)
	shadow_sb.corner_radius_top_left = 16
	shadow_sb.corner_radius_top_right = 16
	shadow_sb.corner_radius_bottom_left = 16
	shadow_sb.corner_radius_bottom_right = 16
	shadow_sb.shadow_color = Color(0, 0, 0, 0.4)
	shadow_sb.shadow_size = 24
	shadow_sb.shadow_offset = Vector2(8, 8)
	window_frame.draw_style_box(shadow_sb, Rect2(Vector2.ZERO, w_size))
	
	# Premium warm frosted-glass background
	var win_sb := StyleBoxFlat.new()
	win_sb.bg_color = Color("efe5d2e8") # Semi-transparent warm cream
	win_sb.border_width_left = 4
	win_sb.border_width_right = 4
	win_sb.border_width_top = 4
	win_sb.border_width_bottom = 4
	win_sb.border_color = Color("332f2a")
	win_sb.corner_radius_top_left = 16
	win_sb.corner_radius_top_right = 16
	win_sb.corner_radius_bottom_left = 16
	win_sb.corner_radius_bottom_right = 16
	window_frame.draw_style_box(win_sb, Rect2(Vector2.ZERO, w_size))
	
	# Header separator line
	window_frame.draw_line(Vector2(0, 60), Vector2(w_size.x, 60), Color("332f2a"), 3.0)
	
	# Header Title Text (Removed instructions/helper text)
	var title_str := "研发中心  |  RESEARCH CENTER  (RP %d)" % int(GameState.rp)
	window_frame.draw_string(font, Vector2(24, 40), title_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("332f2a"))

# 6. Draw graph area contents (rooms, nodes, connections, tooltips)
func _on_graph_area_draw() -> void:
	_build_layout()
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
		
		# Draw column room box with StyleBoxFlat
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("fbf4e7")
		sb.border_width_left = 3
		sb.border_width_right = 3
		sb.border_width_top = 3
		sb.border_width_bottom = 3
		sb.border_color = Color("332f2a")
		sb.corner_radius_top_left = 16
		sb.corner_radius_top_right = 16
		sb.corner_radius_bottom_left = 16
		sb.corner_radius_bottom_right = 16
		sb.shadow_color = Color(0, 0, 0, 0.12)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(3, 3)
		sb.draw(graph_area.get_canvas_item(), rect)
		
		# Draw header bar in column room
		var header_sb := StyleBoxFlat.new()
		header_sb.bg_color = col.darkened(0.12)
		header_sb.border_width_left = 3
		header_sb.border_width_right = 3
		header_sb.border_width_top = 3
		header_sb.border_color = Color("332f2a")
		header_sb.corner_radius_top_left = 16
		header_sb.corner_radius_top_right = 16
		var header_rect := Rect2(rect.position, Vector2(rect.size.x, 50))
		header_sb.draw(graph_area.get_canvas_item(), header_rect)
		
		# Draw column label
		graph_area.draw_string(font, rect.position + Vector2(0, 33), String(CHAIN_LABELS[chain]),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Color("fbf4e7"))
		
		# Chain icon at the bottom
		_draw_chain_icon(chain, rect.position + Vector2(rect.size.x * 0.5, rect.size.y - 30), col)

func _draw_chain_icon(chain: String, c: Vector2, col: Color) -> void:
	graph_area.draw_circle(c, 18, col.lightened(0.12))
	graph_area.draw_arc(c, 18, 0, TAU, 32, Color("332f2a"), 2.0, true)
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

# 7. Draw smooth cubic Bezier S-curve connectors
func _connector(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var r_parent := NODE_R
	var r_child := NODE_R
	
	# Offset node radius to draw lines from edge to edge
	var start := a + Vector2(0, -r_parent)
	var finish := b + Vector2(0, r_child)
	
	# Cubic Bezier control points for S-curve
	var cp1 := Vector2(start.x, (start.y + finish.y) * 0.5)
	var cp2 := Vector2(finish.x, (start.y + finish.y) * 0.5)
	
	var points := PackedVector2Array()
	var steps := 24
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var mt := 1.0 - t
		var pt := mt*mt*mt*start + 3.0*mt*mt*t*cp1 + 3.0*mt*t*t*cp2 + t*t*t*finish
		points.append(pt)
		
	# Draw soft shadow line first
	var shadow_col := Color(0, 0, 0, col.a * 0.3)
	var shadow_offset := Vector2(2, 3)
	var shadow_points := PackedVector2Array()
	for pt in points:
		shadow_points.append(pt + shadow_offset)
	graph_area.draw_polyline(shadow_points, shadow_col, w + 2.0, true)
	
	# Draw main curve
	graph_area.draw_polyline(points, col, w, true)

func _draw_node(id: String, hl: Dictionary, has_hl: bool) -> void:
	var d: Dictionary = DataLoader.research[id]
	var c := _center(id)
	if c.x < -NODE_R * 2 or c.x > graph_area.size.x + NODE_R * 2 or c.y < -NODE_R * 3 or c.y > graph_area.size.y + NODE_R * 3:
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
		
	# 8. Dynamic Hover Scale on nodes
	var r := NODE_R
	if id == hovered:
		r = NODE_R * 1.15
		
	# Draw node shadow, rings, and base
	graph_area.draw_circle(c + Vector2(4, 6), r + 6, Color(0, 0, 0, 0.18 if not dim else 0.05))
	graph_area.draw_circle(c, r + 7, Color("332f2a"))
	graph_area.draw_circle(c, r + 2, Color("fff7ea"))
	graph_area.draw_circle(c, r - 4, base)
	
	var icon_col := Color("332f2a")
	icon_col.a = 0.9 if not dim else 0.25
	_icon(kind, c, icon_col)
	
	var cost := float(d.get("cost", 0))
	if done:
		var done_col := Color("5c9b67")
		done_col.a = 0.95 if not dim else 0.25
		graph_area.draw_arc(c, r + 10, 0, TAU, 48, done_col, 4.0, true)
	elif gate_ok:
		var base_ring := Color("332f2a")
		base_ring.a = 0.26
		graph_area.draw_arc(c, r + 10, 0, TAU, 48, base_ring, 4.0, true)
		var prog := clampf(GameState.rp / maxf(1.0, cost), 0.0, 1.0)
		graph_area.draw_arc(c, r + 10, -PI / 2, -PI / 2 + TAU * prog, 48,
			Color("d49a42") if prog >= 1.0 else Color("5b8fb4"), 5.0, true)
	if avail:
		graph_area.draw_arc(c, r + 14, 0, TAU, 48, Color("d49a42"), 3.0, true)
	elif id == hovered:
		graph_area.draw_arc(c, r + 14, 0, TAU, 48, Color("332f2a"), 3.0, true)
		
	if id == hovered:
		var ta := 1.0 if not dim else 0.3
		var title_col := Color("332f2a")
		title_col.a = ta
		graph_area.draw_string(font, Vector2(c.x - 72, c.y + r + 22), String(d.get("name", id)),
			HORIZONTAL_ALIGNMENT_CENTER, 144, 16, title_col)
			
		# 9. Cleaned up sub-labels: remove "需产品", "需规模", "缺前置"
		var sl := ""
		if done:
			sl = "已研发"
		elif not (GameState.stage >= int(d.get("stage", 0))):
			sl = "" # Blank
		elif not _prereq_ok(d):
			sl = "" # Blank
		else:
			sl = "%d/%d RP" % [int(GameState.rp), int(cost)]
		var status_col := Color("6f665c")
		status_col.a = ta
		graph_area.draw_string(font, Vector2(c.x - 72, c.y + r + 39), sl,
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
		graph_area.draw_rect(Rect2(p, Vector2(bs, bs)), col, true)

func _draw_tooltip(id: String) -> void:
	var d: Dictionary = DataLoader.research[id]
	var lines: Array = []
	lines.append("%s  [%s]" % [
		String(d.get("name", id)),
		String(CHAIN_LABELS.get(String(d.get("chain", "basic")), "研发"))
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
	pos.x = minf(pos.x, graph_area.size.x - w - 10)
	pos.y = minf(pos.y, graph_area.size.y - h - 10)
	
	# Draw styled tooltip card
	var tooltip_sb := StyleBoxFlat.new()
	tooltip_sb.bg_color = Color("fbf4e7")
	tooltip_sb.border_width_left = 3
	tooltip_sb.border_width_right = 3
	tooltip_sb.border_width_top = 3
	tooltip_sb.border_width_bottom = 3
	tooltip_sb.border_color = Color("332f2a")
	tooltip_sb.corner_radius_top_left = 12
	tooltip_sb.corner_radius_top_right = 12
	tooltip_sb.corner_radius_bottom_left = 12
	tooltip_sb.corner_radius_bottom_right = 12
	tooltip_sb.shadow_color = Color(0, 0, 0, 0.22)
	tooltip_sb.shadow_size = 12
	tooltip_sb.shadow_offset = Vector2(4, 4)
	tooltip_sb.draw(graph_area.get_canvas_item(), Rect2(pos, Vector2(w, h)))
	
	var y := pos.y + 25.0
	for i in lines.size():
		var col := Color("9b6a2f") if i == 0 else Color("332f2a")
		graph_area.draw_string(font, Vector2(pos.x + 12, y), String(lines[i]),
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

# Input handler for clicking outside the window (backdrop click to close)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			visible = false

# GUI input handler inside GraphArea (panning, scrolling, node clicks)
func _on_graph_area_input(event: InputEvent) -> void:
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
