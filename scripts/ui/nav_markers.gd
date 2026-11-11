class_name NavMarkers
extends Control
## Draws the nav points (NavPoints) over the game: a pixel diamond with the label and the
## distance in metres over each, and an arrow at the screen edge for ones off-screen.

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
	var screen := size
	var margin := 46.0
	for p: Dictionary in _points:
		var at: Vector3 = p.position
		var col: Color = p.color
		var metres := int(round(player.global_position.distance_to(at)))
		var behind := cam.is_position_behind(at)
		var spot := cam.unproject_position(at)
		var inside := not behind and Rect2(Vector2(margin, margin), screen - Vector2(margin, margin) * 2.0).has_point(spot)
		if not inside:
			# Pinned to the edge, pointing the way.
			var centre := screen * 0.5
			var dir := spot - centre
			if behind:
				dir = -dir
				if dir.length() < 1.0:
					dir = Vector2(0, 1)
			var half := screen * 0.5 - Vector2(margin, margin)
			var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
			spot = centre + dir * k
			var n := dir.normalized()
			var tip := spot + n * 14.0
			draw_colored_polygon(PackedVector2Array([tip, spot + n.orthogonal() * 8.0, spot - n.orthogonal() * 8.0]), col)
		_diamond(spot, 9.0, col)
		var line := ("%s  %d m" % [p.label, metres]) if String(p.label) != "" else "%d m" % metres
		var fs := 15
		var tw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := Vector2(clampf(spot.x - tw * 0.5, 6.0, screen.x - tw - 6.0), spot.y + (24.0 if spot.y < screen.y * 0.5 else -16.0))
		draw_string_outline(font, tp, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
		draw_string(font, tp, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## A chunky pixel diamond (stepped, like the icons).
func _diamond(c: Vector2, r: float, col: Color) -> void:
	var px := 3.0
	var steps := int(r / px)
	for i in range(-steps, steps + 1):
		var w := (steps - absi(i)) * px
		draw_rect(Rect2(Vector2(c.x - w - px * 1.5, c.y + i * px - px * 0.5), Vector2(w * 2.0 + px * 3.0, px)), Color(0, 0, 0, 0.85))
	for i in range(-steps + 1, steps):
		var w := (steps - 1 - absi(i)) * px
		draw_rect(Rect2(Vector2(c.x - w - px * 0.5, c.y + i * px - px * 0.5), Vector2(w * 2.0 + px, px)), col)
