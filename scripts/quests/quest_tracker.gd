class_name QuestTracker
extends VBoxContainer
## Top right, under the gold: the active quests and their objectives ("Bandit Insignias
## 2 / 3"), ticked off as they're met. Built by the HUD; refreshes twice a second.

var _check := 0.0
var _last := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -320
	offset_right = -24
	offset_top = 96
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	# Rebuild only when something shown changed.
	var key := ""
	var rows := []
	for q: Dictionary in Quests.active_quests():
		var id := String(q.get("id", ""))
		rows.append([String(q.get("name", id)), true, Quests.ready(id)])
		for o: Dictionary in q.get("objectives", []):
			var p := Quests.progress(id, o)
			var line := String(o.get("text", ""))
			if p.y > 1:
				line += "  %d / %d" % [p.x, p.y]
			rows.append([line, false, p.x >= p.y])
	key = str(rows)
	if key == _last:
		return
	_last = key
	for c in get_children():
		c.queue_free()
	for r: Array in rows:
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		if r[1]:
			l.text = String(r[0]) + ("  (hand in)" if r[2] else "")
			l.add_theme_font_size_override("font_size", 16)
			l.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
		else:
			l.text = ("✓ " if r[2] else "• ") + String(r[0])
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", Color(0.6, 0.95, 0.55) if r[2] else Color(0.92, 0.9, 0.85))
		add_child(l)
