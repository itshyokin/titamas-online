class_name StatusIcons
extends HBoxContainer
## Round icons under the player frame for statuses (poison, blind... and buffs from
## data/statuses.json), healing over time and Weakened. Each icon's lit part shrinks
## clockwise as it runs out; pointing at one shows its name, what it does and the time left.

const SIZE := 30.0

var stats: Stats
var progress: Node  # PlayerProgress (Weakened)
var _icons := {}  # key -> StatusIcon
var _check := 0.0


func _init(player_stats: Stats, player_progress: Node) -> void:
	stats = player_stats
	progress = player_progress
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.1
	var want := {}  # key -> [name, description, icon, color, left, duration, kind]
	for id: String in stats.statuses:
		var d := Stats.status_data(id)
		if bool(d.get("special", false)):
			continue
		var e: Dictionary = stats.statuses[id]
		want[id] = [String(d.get("name", id)), String(d.get("description", "")), String(d.get("icon", "")),
			Color.html(String(d.get("color", "#ffffff"))), float(e.left), float(e.duration), String(d.get("kind", "ailment"))]
	var hots: Array = stats.get("_hots")
	if not hots.is_empty():
		var left := 0.0
		var total := 0.0
		for h: Dictionary in hots:
			left = maxf(left, float(h.ticks_left) * float(h.interval) - float(h.get("timer", 0.0)))
			total = maxf(total, float(h.get("total", float(h.ticks_left) * float(h.interval))))
			if not h.has("total"):
				h["total"] = float(h.ticks_left) * float(h.interval)
		want["_hot"] = ["Healing", "Recovering health over time.", "heal", Color(1.0, 0.86, 0.32), left, maxf(total, left), "buff"]
	if progress and progress.has_method("weakened_left"):
		var w := float(progress.call("weakened_left"))
		if w > 0.0:
			var total := float(Database.player.get("death", {}).get("weakened_seconds", w))
			want["_weak"] = ["Weakened", "You deal less damage, have less health and move slower until it wears off.", "skull", Color(0.75, 0.7, 0.8), w, maxf(total, w), "debuff"]
	for key in _icons.keys():
		if not want.has(key):
			(_icons[key] as Control).queue_free()
			_icons.erase(key)
	for key: String in want:
		var w: Array = want[key]
		var icon: StatusIcon = _icons.get(key)
		if icon == null:
			icon = StatusIcon.new()
			icon.custom_minimum_size = Vector2(SIZE, SIZE)
			add_child(icon)
			_icons[key] = icon
		icon.set_status(w[0], w[1], w[2], w[3], w[4], w[5], w[6])


class StatusIcon:
	extends Control
	var title := ""
	var text := ""
	var glyph := ""
	var color := Color.WHITE
	var left := 0.0
	var duration := 1.0
	var kind := "ailment"

	## Draws only the glyph (the copy PixelIcons draws small).
	var raw := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = " "

	func _ready() -> void:
		if not raw:
			add_to_group("pixel_icons")
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # big crisp pixels when scaled up

	func set_status(t: String, d: String, g: String, c: Color, l: float, dur: float, k: String) -> void:
		title = t
		text = d
		glyph = g
		color = c
		left = l
		duration = maxf(dur, 0.01)
		kind = k
		queue_redraw()

	# Built when shown, so the text stays the same and the hover timer isn't restarted
	# every time the countdown changes.
	func _get_tooltip(_at: Vector2) -> String:
		return "%s\n%s\n%s" % [title, text, _time_text()]

	func _time_text() -> String:
		if left >= 60.0:
			return "%d:%02d left" % [int(left) / 60, int(left) % 60]
		return "%d s left" % ceili(left)

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		if raw:
			# The glyph reaches ±0.4 of the picture, so it fills it with a little room.
			_draw_glyph(c, minf(size.x, size.y) * 0.4)
			return
		var ring := Color(0.9, 0.3, 0.25) if kind == "ailment" else (Color(0.85, 0.55, 0.3) if kind == "debuff" else Color(0.95, 0.85, 0.4))
		draw_circle(c, r, Color(0, 0, 0, 0.75))
		draw_circle(c, r - 2.0, color.darkened(0.55))
		# Lit part: what's left, shrinking clockwise from the top.
		var frac := clampf(left / duration, 0.0, 1.0)
		var pts := PackedVector2Array([c])
		var steps := 32
		var start := -PI * 0.5 + (1.0 - frac) * TAU
		for i in steps + 1:
			var a := start + frac * TAU * i / steps
			pts.append(c + Vector2(cos(a), sin(a)) * (r - 2.0))
		if frac > 0.01 and pts.size() >= 3:
			draw_colored_polygon(pts, color.darkened(0.1))
		var art := IconArt.status(glyph)
		if art:
			# Exported at the pixel size: the glyph reaches ±0.4 of the picture.
			var art_side := r * 0.55 / 0.4
			draw_texture_rect(art, Rect2(c - Vector2(art_side, art_side) * 0.5, Vector2(art_side, art_side)), false)
		elif PixelIcons.pixels() > 0:
			var g := glyph
			var tex := PixelIcons.get_texture("status:" + g, func() -> Control:
				var icon := StatusIcon.new()
				icon.raw = true
				icon.glyph = g
				return icon)
			if tex:
				# Same size as the smooth glyph (it reaches ±0.55 of the radius).
				var side := r * 0.55 / 0.4
				draw_texture_rect(tex, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
		else:
			_draw_glyph(c, r * 0.55)
		draw_arc(c, r - 1.0, 0.0, TAU, 32, ring, 2.0)

	func _draw_glyph(c: Vector2, s: float) -> void:
		var ink := Color(1, 1, 1, 0.95)
		match glyph:
			"poison":
				draw_circle(c + Vector2(0, s * 0.25), s * 0.55, ink)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.48, s * 0.05), c + Vector2(0, -s * 0.85), c + Vector2(s * 0.48, s * 0.05)]), ink)
			"blind":
				draw_arc(c, s * 0.75, PI * 0.15, PI * 0.85, 12, ink, 2.0)
				draw_arc(c, s * 0.75, PI * 1.15, PI * 1.85, 12, ink, 2.0)
				draw_line(c + Vector2(-s, -s), c + Vector2(s, s), ink, 2.0)
			"silence":
				draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.2), Vector2(s * 1.4, s * 0.4)), ink)
				draw_line(c + Vector2(-s * 0.8, -s * 0.8), c + Vector2(s * 0.8, s * 0.8), ink, 2.0)
			"confuse":
				draw_arc(c, s * 0.7, 0.0, PI * 1.6, 14, ink, 2.0)
				draw_arc(c, s * 0.35, PI, PI * 2.6, 10, ink, 2.0)
			"heal":
				draw_rect(Rect2(c + Vector2(-s * 0.22, -s * 0.75), Vector2(s * 0.44, s * 1.5)), ink)
				draw_rect(Rect2(c + Vector2(-s * 0.75, -s * 0.22), Vector2(s * 1.5, s * 0.44)), ink)
			"frost":
				for i in 3:
					var a := PI * i / 3.0
					draw_line(c - Vector2(cos(a), sin(a)) * s * 0.85, c + Vector2(cos(a), sin(a)) * s * 0.85, ink, 2.0)
			"fire":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.6, s * 0.3), c + Vector2(0, s * 0.8), c + Vector2(-s * 0.6, s * 0.3)]), ink)
			"skull":
				draw_circle(c + Vector2(0, -s * 0.15), s * 0.6, ink)
				draw_rect(Rect2(c + Vector2(-s * 0.35, s * 0.25), Vector2(s * 0.7, s * 0.4)), ink)
				draw_circle(c + Vector2(-s * 0.25, -s * 0.15), s * 0.16, Color(0, 0, 0, 0.8))
				draw_circle(c + Vector2(s * 0.25, -s * 0.15), s * 0.16, Color(0, 0, 0, 0.8))
			"stealth":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.8, s * 0.7), c + Vector2(-s * 0.8, s * 0.7)]), ink)
				draw_circle(c + Vector2(0, s * 0.15), s * 0.3, Color(0, 0, 0, 0.8))
			"shield":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.7, -s * 0.7), c + Vector2(s * 0.7, -s * 0.7), c + Vector2(s * 0.6, s * 0.2), c + Vector2(0, s * 0.85), c + Vector2(-s * 0.6, s * 0.2)]), ink)
			"sun":
				draw_circle(c, s * 0.42, ink)
				for i in 8:
					var a := TAU * i / 8.0
					draw_line(c + Vector2(cos(a), sin(a)) * s * 0.6, c + Vector2(cos(a), sin(a)) * s * 0.92, ink, 2.0)
			"moon":
				draw_circle(c, s * 0.75, ink)
				draw_circle(c + Vector2(s * 0.35, -s * 0.25), s * 0.6, Color(0.1, 0.12, 0.2, 1.0))
			_:
				draw_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.7, -s * 0.7), ink, 3.0)
