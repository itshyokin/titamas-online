class_name AbilityIcon
extends Control
## A drawn icon for an ability (until there's icon art): a rounded tile in the ability's
## colour with a symbol from its "icon" field (slash, heavy, arrow, bullet, fire, heal,
## frost, shield, lightning), or its first letter.

var ability: Ability
## Draws the vector picture itself (the copy PixelIcons draws small); off = shows the
## pixel version.
var raw := false


func _ready() -> void:
	if not raw:
		add_to_group("pixel_icons")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # big crisp pixels when scaled up


func show_ability(ab: Ability) -> void:
	ability = ab
	queue_redraw()


func _draw() -> void:
	if ability == null:
		return
	var art := IconArt.ability(ability.id) if not raw else null
	if art:
		var side := minf(size.x, size.y)
		draw_texture_rect(art, Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)), false)
		return
	if not raw and PixelIcons.pixels() > 0:
		var ab := ability
		var tex := PixelIcons.get_texture("ability:%s:%s:%s" % [ab.id, ab.icon, ab.color.to_html()], func() -> Control:
			var c := AbilityIcon.new()
			c.raw = true
			c.ability = ab
			return c)
		if tex:
			var s := minf(size.x, size.y)
			draw_texture_rect(tex, Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s)), false)
		return
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var c := ability.color
	# Tile: darker rim, lighter centre.
	var tile := StyleBoxFlat.new()
	tile.bg_color = c.darkened(0.35)
	tile.set_corner_radius_all(int(s * 0.14))
	tile.border_color = c.darkened(0.6)
	tile.set_border_width_all(maxi(int(s * 0.04), 1))
	draw_style_box(tile, Rect2(o, Vector2(s, s)))
	draw_circle(p.call(0.5, 0.42), s * 0.36, Color(c.lightened(0.25), 0.25))
	var ink := c.lightened(0.75)
	var deep := c.darkened(0.55)
	match ability.icon:
		"slash":
			draw_arc(p.call(0.3, 0.75), s * 0.5, -1.45, -0.2, 18, ink, s * 0.08)
			draw_arc(p.call(0.34, 0.78), s * 0.38, -1.3, -0.3, 14, Color(ink, 0.5), s * 0.04)
		"heavy":
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.14), p.call(0.62, 0.52), p.call(0.5, 0.62), p.call(0.38, 0.52)]), ink)
			draw_line(p.call(0.2, 0.78), p.call(0.8, 0.78), ink, s * 0.06)
			for x in [0.28, 0.5, 0.72]:
				draw_line(p.call(x, 0.7), p.call(x + (x - 0.5) * 0.4, 0.62), Color(ink, 0.7), s * 0.035)
		"arrow":
			draw_line(p.call(0.2, 0.8), p.call(0.76, 0.24), ink, s * 0.05)
			draw_colored_polygon(PackedVector2Array([p.call(0.82, 0.18), p.call(0.62, 0.26), p.call(0.74, 0.38)]), ink)
			draw_line(p.call(0.2, 0.8), p.call(0.16, 0.68), ink, s * 0.04)
			draw_line(p.call(0.2, 0.8), p.call(0.32, 0.84), ink, s * 0.04)
		"bullet":
			draw_circle(p.call(0.66, 0.36), s * 0.12, ink)
			for i in 3:
				var y := 0.42 + i * 0.1
				draw_line(p.call(0.18 + i * 0.05, y + 0.02), p.call(0.5, y - 0.04), Color(ink, 0.7 - i * 0.18), s * 0.035)
		"fire":
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.12), p.call(0.66, 0.36), p.call(0.74, 0.6), p.call(0.64, 0.82),
				p.call(0.5, 0.88), p.call(0.34, 0.82), p.call(0.26, 0.6), p.call(0.36, 0.42), p.call(0.42, 0.5)]), ink)
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.46), p.call(0.6, 0.64), p.call(0.56, 0.8), p.call(0.44, 0.8), p.call(0.4, 0.64)]), deep)
		"heal":
			draw_rect(Rect2(p.call(0.4, 0.18), Vector2(s * 0.2, s * 0.64)), ink)
			draw_rect(Rect2(p.call(0.18, 0.4), Vector2(s * 0.64, s * 0.2)), ink)
		"frost":
			for i in 3:
				var a := i * PI / 3.0
				var d := Vector2(cos(a), sin(a)) * s * 0.34
				draw_line(p.call(0.5, 0.5) - d, p.call(0.5, 0.5) + d, ink, s * 0.05)
		"shield":
			draw_colored_polygon(PackedVector2Array([p.call(0.24, 0.2), p.call(0.76, 0.2), p.call(0.74, 0.55), p.call(0.5, 0.84), p.call(0.26, 0.55)]), ink)
			draw_colored_polygon(PackedVector2Array([p.call(0.36, 0.3), p.call(0.64, 0.3), p.call(0.62, 0.52), p.call(0.5, 0.68), p.call(0.38, 0.52)]), deep)
		"lightning":
			draw_colored_polygon(PackedVector2Array([p.call(0.58, 0.1), p.call(0.3, 0.54), p.call(0.48, 0.54), p.call(0.38, 0.9),
				p.call(0.72, 0.42), p.call(0.54, 0.42)]), ink)
		"stealth":
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.14), p.call(0.82, 0.82), p.call(0.18, 0.82)]), Color(ink, 0.85))
			draw_circle(p.call(0.5, 0.6), s * 0.12, deep)
		"quake":
			draw_colored_polygon(PackedVector2Array([p.call(0.42, 0.14), p.call(0.6, 0.14), p.call(0.62, 0.44), p.call(0.4, 0.44)]), ink)
			draw_line(p.call(0.14, 0.7), p.call(0.86, 0.7), ink, s * 0.05)
			draw_arc(p.call(0.5, 0.7), s * 0.22, PI, TAU, 12, Color(ink, 0.8), s * 0.04)
			draw_arc(p.call(0.5, 0.7), s * 0.36, PI, TAU, 14, Color(ink, 0.5), s * 0.035)
		"rage":
			var pts := PackedVector2Array()
			for i in 14:
				var a := -PI * 0.5 + TAU * i / 14.0
				pts.append(p.call(0.5, 0.52) + Vector2(cos(a), sin(a)) * s * (0.36 if i % 2 == 0 else 0.17))
			draw_colored_polygon(pts, ink)
			draw_circle(p.call(0.5, 0.52), s * 0.1, deep)
		"wave":
			for i in 3:
				var y := 0.38 + i * 0.16
				var pts := PackedVector2Array()
				for k in 9:
					var x := 0.14 + k * 0.09
					pts.append(p.call(x, y + sin(k * 1.4 + i) * 0.05))
				draw_polyline(pts, Color(ink, 1.0 - i * 0.25), s * 0.07)
			draw_arc(p.call(0.62, 0.34), s * 0.16, PI * 0.9, PI * 2.1, 10, ink, s * 0.07)
		"teleport":
			draw_arc(p.call(0.5, 0.78), s * 0.3, 0.0, TAU, 18, Color(ink, 0.7), s * 0.05)
			for i in 3:
				var x := 0.34 + i * 0.16
				draw_line(p.call(x, 0.72), p.call(x, 0.2 + (i % 2) * 0.12), Color(ink, 0.9 - i * 0.15), s * 0.06)
			draw_circle(p.call(0.5, 0.18), s * 0.08, ink)
		"cloud":
			for q in [[0.34, 0.5, 0.18], [0.54, 0.4, 0.22], [0.68, 0.54, 0.16], [0.48, 0.58, 0.18]]:
				draw_circle(p.call(q[0], q[1]), s * q[2], deep.darkened(0.3))
			for q in [[0.4, 0.5], [0.6, 0.5]]:
				draw_circle(p.call(q[0], q[1]), s * 0.05, Color(1.0, 0.3, 0.3))
		_:
			var font := get_theme_default_font()
			var letter := ability.display_name.left(1).to_upper()
			var fs := int(s * 0.55)
			var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, o + Vector2((s - w) * 0.5, s * 0.7), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, deep)
			draw_string(font, o + Vector2((s - w) * 0.5, s * 0.7), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
