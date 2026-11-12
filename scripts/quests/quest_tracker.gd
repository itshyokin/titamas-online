class_name QuestTracker
extends VBoxContainer
## Top right, under the gold: the active quests and their objectives ("Bandit Insignias
## 2 / 3"), ticked off as they're met; a line flashes and pops up over the hotbar when it
## moves on. Built by the HUD; refreshes twice a second.

var _check := 0.0
var _last := ""
## Objective progress last seen ("quest/index" → have), to pop up "Insignias 3 / 10".
var _seen := {}
var _seeded := false


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
	var changed_rows := []
	var now := {}
	for q: Dictionary in Quests.active_quests():
		var id := String(q.get("id", ""))
		rows.append([String(q.get("name", id)), true, Quests.ready(id)])
		var i := 0
		for o: Dictionary in q.get("objectives", []):
			var p := Quests.progress(id, o)
			var line := String(o.get("text", ""))
			if p.y > 1:
				line += "  %d / %d" % [p.x, p.y]
			var k := "%s/%d" % [id, i]
			now[k] = p.x
			if _seeded and _seen.has(k) and p.x > int(_seen[k]):
				changed_rows.append(rows.size())
				_pop(line, p.x >= p.y)
			rows.append([line, false, p.x >= p.y])
			i += 1
	_seen = now
	_seeded = true
	key = str(rows)
	if key == _last:
		return
	_last = key
	for c in get_children():
		c.queue_free()
	var index := 0
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
		if index in changed_rows:
			# Just moved on: flash it.
			l.pivot_offset = Vector2(300, 10)
			l.modulate = Color(1.6, 1.5, 1.0)
			var t := l.create_tween()
			t.tween_property(l, "modulate", Color.WHITE, 1.2)
		index += 1


## "Bandit Insignias  3 / 10" over the hotbar when an objective moves on (ticked when done).
func _pop(line: String, done: bool) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.call("show_message", ("✓ " if done else "") + line, 2.5, Color(0.6, 1.0, 0.55) if done else Color(1.0, 0.95, 0.8))
	UiSounds.play("toggle")
