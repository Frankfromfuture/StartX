extends Node2D

var amount: int = 0
var icon: Texture2D
var font: Font
var icon_size: float = 46.8
var font_size: int = 22

func setup(value: int, icon_tex: Texture2D, ui_font: Font, badge_size: float, text_size: int) -> void:
	amount = value
	icon = icon_tex
	font = ui_font
	icon_size = badge_size
	font_size = text_size
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2(-icon_size * 0.5, -icon_size * 0.5), Vector2(icon_size, icon_size))
	if icon != null:
		draw_texture_rect(icon, rect, false)
	else:
		draw_circle(Vector2.ZERO, icon_size * 0.5, Color("e8b21f"))
		draw_circle(Vector2.ZERO, icon_size * 0.5, Color("141414"), false, 4.0)
	if font == null:
		return
	var text := "-%d" % amount
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline_y := (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var pos := Vector2(-w * 0.5, baseline_y)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("141414"))
	draw_string(font, pos + Vector2(1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("141414"))
