class_name NavMarkers
extends Control
## Draws the nav points (NavPoints) over the game, Halo-style: a small pixel arrow over each
## target with the range in metres under it, slid along the screen edge (pointing the way)
## when the target is off-screen or behind you. The label shows when you look toward it.

var _points: Array = []
var _check := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.25
		_points = NavPoints.resolve(get_tree())
	queue_redraw()


func points() -> Array:
	return _points


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if cam == null or player == null or GameSettings.menu_open and DialogueBox.is_open:
		return
	var font := get_theme_default_font()
	# The viewport, not our own size: under the HUD's CanvasLayer the control's rect can
	# still be zero on the first frames (that pinned markers to the top-left corner).
	var screen := get_viewport_rect().size
	if screen.x < 10.0 or screen.y < 10.0:
		return
	var centre := screen * 0.5
	var margin := Vector2(40.0, 56.0)
	var area := Rect2(margin, screen - margin * 2.0)
	for p: Dictionary in _points:
		var at: Vector3 = p.position + Vector3.UP * 1.2  # over the target's head, not its feet
		var col: Color = p.color
		var metres := int(round(player.global_position.distance_to(p.position)))
		var behind := cam.is_position_behind(at)
		var spot := cam.unproject_position(at)
		var on_screen := not behind and area.has_point(spot)
		var point_dir := Vector2.DOWN  # on screen: the arrow points down at the target
		if not on_screen:
			# Halo-style: slide along the screen edge toward where the target is.
			var dir := spot - centre
			if behind:
				dir = -dir
				if dir.length() < 1.0:
					dir = Vector2(0, 1)
			var half := area.size * 0.5
			var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
			spot = centre + dir * k
			point_dir = dir.normalized()
		_arrow(spot, point_dir, col)
		# Range under the arrow; the label only when you look toward it (like Halo).
		var fs := 14
		var dist := "%d m" % metres
		var dw := font.get_string_size(dist, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var below := spot + Vector2(-dw * 0.5, 26.0)
		if point_dir.y > 0.7 and not on_screen:
			below.y = spot.y - 20.0  # bottom edge: put the text above the arrow
		_text(font, below, dist, fs, col)
		var label := String(p.label)
		if label != "" and on_screen and spot.distance_to(centre) < screen.y * 0.22:
			var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_text(font, spot + Vector2(-lw * 0.5, -16.0), label, fs, col)


func _text(font: Font, at: Vector2, line: String, fs: int, col: Color) -> void:
	draw_string_outline(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
	draw_string(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## A small chunky (pixel-stepped) arrow whose tip is at `c` + dir · 8, pointing along `dir`.
func _arrow(c: Vector2, dir: Vector2, col: Color) -> void:
	var px := 2.0
	var n := dir.normalized()
	var side := n.orthogonal()
	var tip := c + n * 8.0
	var tail := c - n * 6.0
	# Outline first, then the fill, both made of px-sized squares so it matches the icons.
	for pass_i in 2:
		var grow := 2.0 if pass_i == 0 else 0.0
		var fill := Color(0, 0, 0, 0.85) if pass_i == 0 else col
		var steps := 8
		for s in steps + 1:
			var t := float(s) / steps
			var mid := tail.lerp(tip, t)
			var w := (1.0 - t) * 7.0 + grow
			var a := mid - side * w
			var b := mid + side * w
			var cells := int(ceil(a.distance_to(b) / px))
			for q in cells + 1:
				var pt := a.lerp(b, float(q) / maxf(cells, 1))
				draw_rect(Rect2(Vector2(floor(pt.x / px) * px, floor(pt.y / px) * px) - Vector2(grow, grow) * 0.5, Vector2(px, px) + Vector2(grow, grow)), fill)
