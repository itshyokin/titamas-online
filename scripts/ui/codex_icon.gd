class_name CodexIcon
extends Control
## The little pictures on the Codex tabs, drawn in code once and saved as pictures
## (tools/godot/export_icons.gd → assets/icons/codex/<page>.png, art_sheets "icons"), which
## the Codex shows. Cream ink with a dark outline so they read on any button.

var page := ""

const INK := Color(1.0, 0.92, 0.72)
const LINE := Color(0.12, 0.08, 0.05)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var w := s * 0.09
	match page:
		"character":
			draw_circle(p.call(0.5, 0.32), s * 0.17, LINE)
			draw_circle(p.call(0.5, 0.32), s * 0.13, INK)
			_poly([p.call(0.18, 0.9), p.call(0.24, 0.62), p.call(0.5, 0.52), p.call(0.76, 0.62), p.call(0.82, 0.9)], s)
		"backpack":
			_poly([p.call(0.22, 0.38), p.call(0.78, 0.38), p.call(0.82, 0.9), p.call(0.18, 0.9)], s)
			draw_arc(p.call(0.5, 0.38), s * 0.17, PI, TAU, 10, LINE, w)
			draw_arc(p.call(0.5, 0.38), s * 0.17, PI, TAU, 10, INK, w * 0.5)
			draw_line(p.call(0.3, 0.6), p.call(0.7, 0.6), LINE, w * 0.6)
		"quests":
			_poly([p.call(0.24, 0.12), p.call(0.76, 0.12), p.call(0.76, 0.88), p.call(0.24, 0.88)], s)
			for y in [0.32, 0.48, 0.64]:
				draw_line(p.call(0.34, y), p.call(0.66, y), LINE, w * 0.55)
			draw_circle(p.call(0.76, 0.18), s * 0.12, LINE)
			draw_circle(p.call(0.76, 0.18), s * 0.08, Color(1.0, 0.75, 0.25))
		"spells":
			_poly([p.call(0.1, 0.3), p.call(0.5, 0.38), p.call(0.9, 0.3), p.call(0.9, 0.86), p.call(0.5, 0.92), p.call(0.1, 0.86)], s)
			draw_line(p.call(0.5, 0.38), p.call(0.5, 0.92), LINE, w * 0.6)
			_star(p.call(0.5, 0.16), s * 0.13, s)
		"skills":
			var pts := [p.call(0.5, 0.82), p.call(0.28, 0.5), p.call(0.72, 0.5), p.call(0.5, 0.18)]
			for pair in [[0, 1], [0, 2], [1, 3], [2, 3]]:
				draw_line(pts[pair[0]], pts[pair[1]], LINE, w)
				draw_line(pts[pair[0]], pts[pair[1]], INK, w * 0.45)
			for q in pts:
				draw_circle(q, s * 0.1, LINE)
				draw_circle(q, s * 0.065, INK)
		"achievements":
			_poly([p.call(0.26, 0.14), p.call(0.74, 0.14), p.call(0.68, 0.48), p.call(0.5, 0.58), p.call(0.32, 0.48)], s)
			draw_line(p.call(0.5, 0.58), p.call(0.5, 0.76), LINE, w * 1.4)
			draw_line(p.call(0.5, 0.58), p.call(0.5, 0.76), INK, w * 0.6)
			_poly([p.call(0.3, 0.76), p.call(0.7, 0.76), p.call(0.72, 0.88), p.call(0.28, 0.88)], s)
		"lore":
			_poly([p.call(0.2, 0.14), p.call(0.72, 0.14), p.call(0.8, 0.22), p.call(0.8, 0.88), p.call(0.2, 0.88)], s)
			draw_line(p.call(0.3, 0.14), p.call(0.3, 0.88), LINE, w * 0.7)
			draw_line(p.call(0.4, 0.34), p.call(0.7, 0.34), LINE, w * 0.5)
			draw_line(p.call(0.4, 0.48), p.call(0.66, 0.48), LINE, w * 0.5)
		"settings":
			var c: Vector2 = p.call(0.5, 0.5)
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * s * 0.2, c + d * s * 0.4, LINE, s * 0.2)
				draw_line(c + d * s * 0.2, c + d * s * 0.37, INK, s * 0.12)
			draw_circle(c, s * 0.28, LINE)
			draw_circle(c, s * 0.23, INK)
			draw_circle(c, s * 0.1, LINE)


func _poly(points: Array, s: float) -> void:
	var pts := PackedVector2Array(points)
	draw_colored_polygon(pts, INK)
	pts.append(pts[0])
	draw_polyline(pts, LINE, s * 0.07)


func _star(c: Vector2, r: float, s: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * i / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, Color(1.0, 0.8, 0.3))
	pts.append(pts[0])
	draw_polyline(pts, LINE, s * 0.05)
