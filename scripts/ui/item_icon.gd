class_name ItemIcon
extends Control
## A simple drawn icon for an item, by its "icon" type and colour (until there's icon art):
## sword, bow, shield, helm, shoulders, chest, legs, boots, gloves, potion, bandage, coin,
## cloth, bag. A stack count shows in the corner.

const RARITY_COLORS := {
	"common": Color(0.85, 0.85, 0.85),
	"uncommon": Color(0.35, 0.9, 0.35),
	"rare": Color(0.35, 0.6, 1.0),
	"epic": Color(0.75, 0.45, 1.0),
	"legendary": Color(1.0, 0.6, 0.15),
}

var icon := ""
var color := Color.WHITE
var count := 0


static func rarity_color(item: Dictionary) -> Color:
	return RARITY_COLORS.get(String(item.get("rarity", "common")), Color.WHITE)


func show_item(item: Dictionary, stack := 0) -> void:
	icon = String(item.get("icon", "")) if not item.is_empty() else ""
	color = DataFiles.color_from(item.get("icon_color", "#ffffff")) if not item.is_empty() else Color.WHITE
	count = stack
	queue_redraw()


func _draw() -> void:
	if icon.is_empty():
		return
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var dark := color.darkened(0.45)
	var light := color.lightened(0.3)
	match icon:
		"sword":
			draw_colored_polygon(PackedVector2Array([p.call(0.72, 0.12), p.call(0.82, 0.18), p.call(0.4, 0.62), p.call(0.34, 0.56)]), light)
			draw_line(p.call(0.27, 0.5), p.call(0.5, 0.73), Color(0.75, 0.6, 0.3), s * 0.06)
			draw_line(p.call(0.37, 0.63), p.call(0.2, 0.8), Color(0.35, 0.22, 0.12), s * 0.07)
		"bow":
			draw_arc(p.call(0.3, 0.5), s * 0.42, -1.1, 1.1, 16, color, s * 0.07)
			draw_line(p.call(0.49, 0.13), p.call(0.49, 0.87), Color(0.9, 0.9, 0.85), s * 0.02)
		"shield":
			draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.18), p.call(0.8, 0.18), p.call(0.78, 0.55), p.call(0.5, 0.86), p.call(0.22, 0.55)]), color)
			draw_colored_polygon(PackedVector2Array([p.call(0.33, 0.28), p.call(0.67, 0.28), p.call(0.66, 0.52), p.call(0.5, 0.72), p.call(0.34, 0.52)]), dark)
		"helm":
			draw_circle(p.call(0.5, 0.55), s * 0.3, color)
			draw_rect(Rect2(p.call(0.18, 0.55), Vector2(s * 0.64, s * 0.3)), Color(0, 0, 0, 0))
			draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.55), p.call(0.8, 0.55), p.call(0.8, 0.72), p.call(0.2, 0.72)]), dark)
			draw_rect(Rect2(p.call(0.46, 0.55), Vector2(s * 0.08, s * 0.25)), light)
		"shoulders":
			draw_circle(p.call(0.3, 0.5), s * 0.2, color)
			draw_circle(p.call(0.7, 0.5), s * 0.2, color)
			draw_rect(Rect2(p.call(0.1, 0.5), Vector2(s * 0.8, s * 0.22)), dark)
		"chest":
			draw_colored_polygon(PackedVector2Array([p.call(0.25, 0.15), p.call(0.4, 0.2), p.call(0.6, 0.2), p.call(0.75, 0.15), p.call(0.9, 0.35),
				p.call(0.75, 0.42), p.call(0.72, 0.85), p.call(0.28, 0.85), p.call(0.25, 0.42), p.call(0.1, 0.35)]), color)
			draw_line(p.call(0.5, 0.25), p.call(0.5, 0.82), dark, s * 0.03)
		"legs":
			draw_colored_polygon(PackedVector2Array([p.call(0.28, 0.12), p.call(0.72, 0.12), p.call(0.75, 0.88), p.call(0.56, 0.88), p.call(0.5, 0.35),
				p.call(0.44, 0.88), p.call(0.25, 0.88)]), color)
		"boots":
			draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.15), p.call(0.55, 0.15), p.call(0.55, 0.6), p.call(0.85, 0.7), p.call(0.85, 0.85),
				p.call(0.3, 0.85)]), color)
			draw_rect(Rect2(p.call(0.3, 0.78), Vector2(s * 0.55, s * 0.07)), dark)
		"gloves":
			draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.85), p.call(0.3, 0.35), p.call(0.38, 0.15), p.call(0.46, 0.35), p.call(0.5, 0.12),
				p.call(0.58, 0.35), p.call(0.64, 0.17), p.call(0.7, 0.4), p.call(0.82, 0.38), p.call(0.72, 0.6), p.call(0.7, 0.85)]), color)
		"potion":
			draw_rect(Rect2(p.call(0.43, 0.12), Vector2(s * 0.14, s * 0.18)), Color(0.75, 0.65, 0.5))
			draw_circle(p.call(0.5, 0.6), s * 0.27, color)
			draw_circle(p.call(0.42, 0.52), s * 0.07, light)
		"bandage":
			draw_circle(p.call(0.5, 0.5), s * 0.32, color)
			draw_circle(p.call(0.5, 0.5), s * 0.12, dark)
			draw_arc(p.call(0.5, 0.5), s * 0.22, 0.0, TAU, 20, dark, s * 0.02)
		"coin":
			draw_circle(p.call(0.5, 0.5), s * 0.3, color)
			draw_arc(p.call(0.5, 0.5), s * 0.22, 0.0, TAU, 20, dark, s * 0.04)
		"hearthstone":
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.15), p.call(0.8, 0.35), p.call(0.75, 0.75), p.call(0.45, 0.88), p.call(0.2, 0.65), p.call(0.25, 0.3)]), dark)
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.25), p.call(0.7, 0.4), p.call(0.66, 0.68), p.call(0.46, 0.78), p.call(0.3, 0.6), p.call(0.33, 0.36)]), color)
			draw_circle(p.call(0.5, 0.52), s * 0.09, light)
		"cloth":
			draw_colored_polygon(PackedVector2Array([p.call(0.15, 0.3), p.call(0.8, 0.2), p.call(0.85, 0.7), p.call(0.2, 0.8)]), color)
			draw_line(p.call(0.2, 0.45), p.call(0.82, 0.37), dark, s * 0.02)
			draw_line(p.call(0.2, 0.62), p.call(0.84, 0.55), dark, s * 0.02)
		_:
			draw_circle(p.call(0.5, 0.55), s * 0.3, color)
			draw_rect(Rect2(p.call(0.4, 0.15), Vector2(s * 0.2, s * 0.15)), dark)
	if count > 1:
		var font := get_theme_default_font()
		var text := str(count)
		var fs := int(s * 0.3)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := o + Vector2(s - w - 3, s - 4)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
