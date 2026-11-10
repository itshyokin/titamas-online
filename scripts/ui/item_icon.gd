class_name ItemIcon
extends Control
## A simple drawn icon for an item, by its "icon" type and colour (until there's icon art):
## sword, dagger, axe, hammer, bow, crossbow, gun, shield, helm, shoulders, chest, legs, boots, gloves, potion, bandage, coin,
## cloth, bag. A stack count shows in the corner.

const RARITY_COLORS := {
	"common": Color(0.66, 0.66, 0.66),
	"uncommon": Color(0.35, 0.9, 0.35),
	"rare": Color(0.35, 0.6, 1.0),
	"epic": Color(0.75, 0.45, 1.0),
	"legendary": Color(1.0, 0.6, 0.15),
}

var icon := ""
var color := Color.WHITE
var count := 0
## Draws the vector picture itself (the copy PixelIcons draws small); off = shows the
## pixel version (the stack count stays sharp on top).
var raw := false


func _ready() -> void:
	if not raw:
		add_to_group("pixel_icons")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # big crisp pixels when scaled up


## Grey, green, blue, purple, orange (player.json "rarity_colors" overrides; Database →
## Player → Item rarity).
static func rarity_color(item: Dictionary) -> Color:
	var r := String(item.get("rarity", "common"))
	var loop := Engine.get_main_loop() as SceneTree
	var db := loop.root.get_node_or_null("Database") if loop else null
	var custom = (db.get("player") as Dictionary).get("rarity_colors", {}) if db else {}
	if custom is Dictionary and Color.html_is_valid(String(custom.get(r, ""))):
		return Color.html(String(custom[r]))
	return RARITY_COLORS.get(r, Color.WHITE)


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
	if not raw and PixelIcons.pixels() > 0:
		var kind := icon
		var col := color
		var tex := PixelIcons.get_texture("item:%s:%s" % [kind, col.to_html()], func() -> Control:
			var c := ItemIcon.new()
			c.raw = true
			c.icon = kind
			c.color = col
			return c)
		if tex:
			draw_texture_rect(tex, Rect2(o, Vector2(s, s)), false)
		_draw_count(s, o)
		return
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var dark := color.darkened(0.45)
	var light := color.lightened(0.3)
	match icon:
		"sword":
			draw_colored_polygon(PackedVector2Array([p.call(0.72, 0.12), p.call(0.82, 0.18), p.call(0.4, 0.62), p.call(0.34, 0.56)]), light)
			draw_line(p.call(0.27, 0.5), p.call(0.5, 0.73), Color(0.75, 0.6, 0.3), s * 0.06)
			draw_line(p.call(0.37, 0.63), p.call(0.2, 0.8), Color(0.35, 0.22, 0.12), s * 0.07)
		"dagger":
			draw_colored_polygon(PackedVector2Array([p.call(0.62, 0.22), p.call(0.7, 0.27), p.call(0.44, 0.58), p.call(0.38, 0.52)]), light)
			draw_line(p.call(0.33, 0.48), p.call(0.5, 0.65), Color(0.75, 0.6, 0.3), s * 0.05)
			draw_line(p.call(0.41, 0.57), p.call(0.28, 0.72), Color(0.35, 0.22, 0.12), s * 0.07)
		"axe":
			draw_line(p.call(0.3, 0.85), p.call(0.62, 0.2), Color(0.5, 0.33, 0.18), s * 0.07)
			draw_colored_polygon(PackedVector2Array([p.call(0.55, 0.2), p.call(0.82, 0.12), p.call(0.88, 0.42), p.call(0.66, 0.38)]), light)
		"hammer":
			draw_line(p.call(0.3, 0.85), p.call(0.58, 0.3), Color(0.5, 0.33, 0.18), s * 0.07)
			draw_colored_polygon(PackedVector2Array([p.call(0.4, 0.2), p.call(0.66, 0.08), p.call(0.82, 0.38), p.call(0.56, 0.5)]), color)
			draw_line(p.call(0.53, 0.14), p.call(0.69, 0.44), dark, s * 0.03)
		"crossbow":
			draw_line(p.call(0.5, 0.2), p.call(0.5, 0.88), Color(0.5, 0.33, 0.18), s * 0.09)
			draw_arc(p.call(0.5, 0.62), s * 0.36, -2.6, -0.54, 16, color, s * 0.07)
			draw_line(p.call(0.2, 0.42), p.call(0.8, 0.42), Color(0.9, 0.9, 0.85), s * 0.02)
		"gun":
			draw_colored_polygon(PackedVector2Array([p.call(0.12, 0.36), p.call(0.82, 0.36), p.call(0.82, 0.46), p.call(0.12, 0.46)]), color.darkened(0.2))
			draw_colored_polygon(PackedVector2Array([p.call(0.6, 0.42), p.call(0.86, 0.42), p.call(0.9, 0.78), p.call(0.72, 0.8)]), Color(0.5, 0.33, 0.18))
			draw_line(p.call(0.66, 0.3), p.call(0.72, 0.38), dark, s * 0.04)
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
		"log":
			draw_colored_polygon(PackedVector2Array([p.call(0.12, 0.62), p.call(0.7, 0.28), p.call(0.82, 0.48), p.call(0.24, 0.82)]), color)
			draw_circle(p.call(0.76, 0.38), s * 0.12, light)
			draw_arc(p.call(0.76, 0.38), s * 0.06, 0.0, TAU, 12, dark, s * 0.02)
			draw_line(p.call(0.25, 0.66), p.call(0.6, 0.46), dark, s * 0.02)
		"ore":
			draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.62), p.call(0.35, 0.3), p.call(0.62, 0.22), p.call(0.82, 0.45), p.call(0.72, 0.78), p.call(0.38, 0.84)]), color)
			draw_colored_polygon(PackedVector2Array([p.call(0.35, 0.3), p.call(0.62, 0.22), p.call(0.55, 0.45)]), light)
			draw_line(p.call(0.55, 0.45), p.call(0.72, 0.78), dark, s * 0.02)
		_:
			draw_circle(p.call(0.5, 0.55), s * 0.3, color)
			draw_rect(Rect2(p.call(0.4, 0.15), Vector2(s * 0.2, s * 0.15)), dark)
	_draw_count(s, o)


func _draw_count(s: float, o: Vector2) -> void:
	if count > 1 and not raw:
		var font := get_theme_default_font()
		var text := str(count)
		var fs := int(s * 0.3)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := o + Vector2(s - w - 3, s - 4)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
