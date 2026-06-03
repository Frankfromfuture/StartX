extends Node2D
class_name PackCard

const W := 148.0
const H := 108.0
const INK := Color("3a352f")

var pack_id: String = ""
var pack_name: String = ""
var contents: Array = []
var opened := false
var ready_to_open := false
var board_pos: Vector2 = Vector2.ZERO
var pixel_font: Font

func setup(id: String, name: String, card_ids: Array) -> void:
	pack_id = id
	pack_name = name
	contents = card_ids.duplicate()
	queue_redraw()

func contains_point(global_pt: Vector2) -> bool:
	var local := to_local(global_pt)
	return local.x >= 0 and local.x <= W and local.y >= 0 and local.y <= H

func _draw() -> void:
	var body := Color("d8bd80")
	var shade := Color("bd9550")
	var paper := Color("f4dfab")
	var poly := PackedVector2Array()
	var steps := 8
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := lerpf(18.0, W - 18.0, t)
		var y := 8.0 if i % 2 == 0 else 18.0
		poly.append(Vector2(x, y))
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var y := lerpf(20.0, H - 20.0, t)
		var wave := sin(t * TAU * 1.5) * 4.0
		poly.append(Vector2(W - 8.0 + wave, y))
	for i in range(steps, -1, -1):
		var t := float(i) / float(steps)
		var x := lerpf(18.0, W - 18.0, t)
		var y := H - (8.0 if i % 2 == 0 else 18.0)
		poly.append(Vector2(x, y))
	for i in range(steps, 0, -1):
		var t := float(i) / float(steps)
		var y := lerpf(20.0, H - 20.0, t)
		var wave := sin(t * TAU * 1.4 + 0.8) * 4.0
		poly.append(Vector2(8.0 + wave, y))

	draw_colored_polygon(poly, body)
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, INK, 4.0, true)
	draw_line(Vector2(18, 30), Vector2(W - 18, 30), shade, 3.0)
	draw_line(Vector2(18, H - 30), Vector2(W - 18, H - 30), shade, 3.0)
	draw_rect(Rect2(30, 38, W - 60, 32), paper, true)
	draw_rect(Rect2(30, 38, W - 60, 32), INK, false, 2.0)
	draw_circle(Vector2(W - 28, 24), 12, Color("b5803a"))
	draw_circle(Vector2(W - 28, 24), 6, paper)
	var f := _ui_font()
	var title := "CARD PACK"
	draw_string(f, Vector2(21, 60), title, HORIZONTAL_ALIGNMENT_CENTER, W - 42, 14, INK)
	draw_string(f, Vector2(14, H - 14), pack_name, HORIZONTAL_ALIGNMENT_CENTER, W - 28, 15, INK)

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
