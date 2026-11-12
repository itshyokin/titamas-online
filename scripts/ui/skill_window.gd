class_name SkillWindow
extends CanvasLayer
## Skill trees, Saturn-style: one tab per tree of the class (data/skill_trees.json, Database →
## Skill Trees), each drawn as a constellation (skills at their column / row, row 0 at the
## bottom, lines to the skills they need) with the chosen skill's details beside it.
## Click a skill to choose it, click it again (or Learn) to learn a rank, then once more to
## confirm. Keys: arrows choose, Enter learns, [ / ] switch trees. Shown in the Codex (N).

const PANEL := Color(0.055, 0.067, 0.11, 0.97)
const LINE := Color(1, 1, 1, 0.18)
const DOT := Color(0.11, 0.125, 0.19)
const TEXT := Color(0.95, 0.92, 0.85)
const SOFT := Color(0.62, 0.64, 0.71)
const WARN := Color(1.0, 0.6, 0.54)
const NEED := Color(0.79, 0.72, 0.54)
const STAT_NAMES := {"attack": "Attack", "spell_power": "Spell power", "armor": "Armour", "block": "Block",
	"bonus_health": "Max health", "bonus_mana": "Max mana", "crit_chance": "% critical chance",
	"move_speed": "% move speed", "stamina": "Max stamina"}

var progress: PlayerProgress
var _window: PanelContainer
var _points: Label
var _tabs: HBoxContainer
var _map: SkillMap
var _detail: VBoxContainer
var _tree_index := 0
var _sel := ""
var _confirming := false

## Shown inside the Codex right now (the Codex handles keys and closing).
var embedded := false


func _init(player_progress: PlayerProgress) -> void:
	progress = player_progress


func _ready() -> void:
	layer = 15
	_window = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = CharacterWindow.ACCENT.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	_window.add_theme_stylebox_override("panel", sb)
	_window.custom_minimum_size = Vector2(900, 540)
	_window.visible = false
	add_child(_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_window.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "Skill Tree"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", CharacterWindow.ACCENT)
	head.add_child(title)
	_points = Label.new()
	_points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_points.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_points)
	var reset := Button.new()
	reset.text = "Reset"
	reset.tooltip_text = "Give back every skill point."
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void: progress.respec())
	head.add_child(reset)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	head.add_child(close_button)
	v.add_child(head)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 2)
	v.add_child(_tabs)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	_map = SkillMap.new()
	_map.window = self
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_stretch_ratio = 1.7
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_map)
	var side := PanelContainer.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(1, 1, 1, 0.04)
	ssb.set_corner_radius_all(8)
	ssb.set_content_margin_all(12)
	side.add_theme_stylebox_override("panel", ssb)
	side.custom_minimum_size.x = 280
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(side)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	side.add_child(_detail)
	var note := Label.new()
	note.text = "Click a skill to choose it, again to learn  ·  Arrows choose  ·  Enter learns  ·  [ / ] trees"
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", SOFT)
	v.add_child(note)
	progress.skills_changed.connect(func() -> void:
		if is_open():
			_fill())
	Database.changed.connect(func(which: String) -> void:
		if which == "skill_trees" and is_open():
			_fill())


func is_open() -> bool:
	return _window.visible


func open() -> void:
	_fill()
	_window.visible = true
	GameSettings.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if embedded:
		get_tree().call_group("codex", "close")
		return
	_window.visible = false
	GameSettings.menu_open = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not _window.is_visible_in_tree():
		return
	if not embedded and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu")):
		if _confirming:
			_confirming = false
			_fill()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		match key.keycode:
			KEY_LEFT, KEY_A:
				_move(Vector2(-1, 0))
			KEY_RIGHT, KEY_D:
				_move(Vector2(1, 0))
			KEY_UP, KEY_W:
				_move(Vector2(0, 1))
			KEY_DOWN, KEY_S:
				_move(Vector2(0, -1))
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate()
			KEY_BRACKETLEFT:
				_switch_tree(-1)
			KEY_BRACKETRIGHT:
				_switch_tree(1)
			_:
				return
		get_viewport().set_input_as_handled()


# --- Trees and the chosen skill ----------------------------------------------------------

func _trees() -> Array:
	return progress.trees()


func tree() -> Dictionary:
	var t := _trees()
	return t[_tree_index] if _tree_index < t.size() else {}


func tree_color() -> Color:
	var c := String(tree().get("color", ""))
	return Color.html(c) if Color.html_is_valid(c) else CharacterWindow.ACCENT


func nodes() -> Array:
	return tree().get("nodes", [])


func selected() -> String:
	return _sel


## locked / ready (needs met, can't afford or level) / open (can learn) / some / full.
func state_of(n: Dictionary) -> String:
	var id := String(n.get("id", ""))
	var r := progress.rank(id)
	var max_r := int(n.get("max_rank", 1))
	if r >= max_r:
		return "full"
	if r > 0:
		return "some"
	if progress.cant_rank(id) == "":
		return "open"
	for req in n.get("requires", []):
		if progress.rank(String(req)) < 1:
			return "locked"
	return "ready"


func select(id: String) -> void:
	if id == _sel:
		_activate()
		return
	_sel = id
	_confirming = false
	_fill()


func _pick_default() -> void:
	var list := nodes()
	for n: Dictionary in list:
		if String(n.get("id", "")) == _sel:
			return
	_sel = ""
	for n: Dictionary in list:
		if progress.cant_rank(String(n.get("id", ""))) == "":
			_sel = String(n.get("id", ""))
			return
	var best := {}
	for n: Dictionary in list:
		if best.is_empty() or float(n.get("row", 0)) < float(best.get("row", 0)) \
				or float(n.get("row", 0)) == float(best.get("row", 0)) and float(n.get("col", 0)) < float(best.get("col", 0)):
			best = n
	_sel = String(best.get("id", ""))


func _switch_tree(dir: int) -> void:
	var count := _trees().size()
	if count == 0:
		return
	_tree_index = posmod(_tree_index + dir, count)
	_sel = ""
	_confirming = false
	_fill()


## The nearest skill in a direction (x right, y up).
func _move(dir: Vector2) -> void:
	var list := nodes()
	var cur := {}
	for n: Dictionary in list:
		if String(n.get("id", "")) == _sel:
			cur = n
	if cur.is_empty():
		_pick_default()
		_fill()
		return
	var from := Vector2(float(cur.get("col", 0)), float(cur.get("row", 0)))
	var best := ""
	var best_score := INF
	for n: Dictionary in list:
		if n == cur:
			continue
		var d := Vector2(float(n.get("col", 0)), float(n.get("row", 0))) - from
		var along := d.normalized().dot(dir)
		if along < 0.35:
			continue
		var score := d.length() * (2.0 - along)
		if score < best_score:
			best_score = score
			best = String(n.get("id", ""))
	if best != "":
		_sel = best
		_confirming = false
		_fill()


## Learn (press twice: the first asks to confirm).
func _activate() -> void:
	if _sel == "":
		return
	var why := progress.cant_rank(_sel)
	if why != "":
		HUD.notify(self, why, WARN)
		return
	if not _confirming:
		_confirming = true
		_fill()
		return
	_confirming = false
	progress.rank_up(_sel)
	_fill()


# --- Drawing -------------------------------------------------------------------------------

func _fill() -> void:
	var trees := _trees()
	var free := progress.points_free()
	_points.text = "Level %d  ·  %d skill point%s" % [progress.level, free, "" if free == 1 else "s"]
	_points.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35) if free > 0 else SOFT)
	for c in _tabs.get_children():
		c.queue_free()
	for c in _detail.get_children():
		c.queue_free()
	if trees.is_empty():
		_map.queue_redraw()
		_detail.add_child(_label("This class has no skill trees yet (Database → Skill Trees).", 14, SOFT))
		return
	_tree_index = clampi(_tree_index, 0, trees.size() - 1)
	for i in trees.size():
		var t: Dictionary = trees[i]
		var c := String(t.get("color", ""))
		var col := Color.html(c) if Color.html_is_valid(c) else CharacterWindow.ACCENT
		var tab := Button.new()
		tab.text = String(t.get("name", ""))
		tab.flat = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 15)
		var on := i == _tree_index
		tab.add_theme_color_override("font_color", col if on else SOFT)
		tab.add_theme_color_override("font_hover_color", col.lightened(0.2))
		var line := StyleBoxFlat.new()
		line.bg_color = Color(0, 0, 0, 0)
		line.border_color = col if on else Color(0, 0, 0, 0)
		line.border_width_bottom = 2
		line.set_content_margin_all(6)
		line.content_margin_left = 14
		line.content_margin_right = 14
		for st in ["normal", "hover", "pressed", "focus"]:
			tab.add_theme_stylebox_override(st, line)
		tab.pressed.connect(func() -> void:
			_tree_index = i
			_sel = ""
			_confirming = false
			_fill())
		_tabs.add_child(tab)
	_pick_default()
	_map.queue_redraw()
	_fill_detail()
	if not embedded:
		_center.call_deferred()


func _fill_detail() -> void:
	var accent := tree_color()
	var desc := String(tree().get("description", ""))
	var n := {}
	for x: Dictionary in nodes():
		if String(x.get("id", "")) == _sel:
			n = x
	if n.is_empty():
		_detail.add_child(_label(desc if desc != "" else "No skills in this tree yet.", 14, SOFT))
		return
	var id := String(n.get("id", ""))
	var r := progress.rank(id)
	var max_r := int(n.get("max_rank", 1))
	var cost := int(n.get("cost", 1))
	_detail.add_child(_label(String(n.get("name", id)), 20, accent))
	_detail.add_child(_label("Rank %d / %d%s" % [r, max_r, "  ·  %d points per rank" % cost if cost > 1 else ""], 13, SOFT))
	if String(n.get("description", "")) != "":
		_detail.add_child(_label(String(n.description), 14, TEXT))
	var eff := _effect_text(n)
	if eff != "":
		_detail.add_child(_label("•  " + eff, 13, Color(0.81, 0.9, 0.75)))
	var needs: Array[String] = []
	for req in n.get("requires", []):
		needs.append(String(progress.skill(String(req)).get("name", req)))
	if not needs.is_empty():
		_detail.add_child(_label("Needs: " + ", ".join(needs), 12, NEED))
	if int(n.get("min_level", 1)) > 1:
		_detail.add_child(_label("Level %d+" % int(n.min_level), 12, NEED))
	if int(n.get("points_above", 0)) > 0:
		_detail.add_child(_label("%d points spent in %s first" % [int(n.points_above), tree().get("name", "this tree")], 12, NEED))
	var why := progress.cant_rank(id)
	if why != "" and why != "Fully learned":
		_detail.add_child(_label(why, 12, WARN))
	if why == "":
		var learn := Button.new()
		learn.text = ("Learn %s? Click again to confirm" % n.get("name", id)) if _confirming else ("Learn (%d point%s)" % [cost, "s" if cost > 1 else ""])
		learn.focus_mode = Control.FOCUS_NONE
		learn.custom_minimum_size.y = 34
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 0.69, 0.29, 0.25) if _confirming else Color(1, 1, 1, 0.07)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(6)
		learn.add_theme_stylebox_override("normal", sb)
		var hov := sb.duplicate() as StyleBoxFlat
		hov.bg_color = hov.bg_color.lightened(0.1)
		learn.add_theme_stylebox_override("hover", hov)
		learn.pressed.connect(_activate)
		_detail.add_child(learn)


func _effect_text(n: Dictionary) -> String:
	match String(n.get("effect", "stat")):
		"stat":
			var stat := String(n.get("stat", ""))
			var amount := float(n.get("per_rank", 0))
			var name: String = STAT_NAMES.get(stat, stat)
			var num := ("%d" % int(amount)) if is_equal_approx(amount, roundf(amount)) else ("%.1f" % amount)
			var each := " per rank" if int(n.get("max_rank", 1)) > 1 else ""
			return ("+%s%s%s" if name.begins_with("%") else "+%s %s%s") % [num, name, each]
		"ability":
			var ab = Database.ability(String(n.get("ability", "")))
			return "Teaches %s" % (ab.display_name if ab and "display_name" in ab else String(n.get("ability", "")))
	return ""


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _center() -> void:
	if embedded:
		return
	_window.reset_size()
	var view := _window.get_viewport_rect().size
	_window.position = ((view - _window.size) * 0.5).floor()


## The constellation: skills as dots at their column / row (row 0 at the bottom), lines to the
## skills they need (lit once both are learned), rank pips under each.
class SkillMap:
	extends Control

	var window: SkillWindow
	var _spots := {}  # id -> Vector2 (this frame's layout)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _layout() -> float:
		_spots.clear()
		var list: Array = window.nodes()
		if list.is_empty():
			return 0.0
		var max_x := 4.0
		var max_y := 2.0
		for n: Dictionary in list:
			max_x = maxf(max_x, float(n.get("col", 0)))
			max_y = maxf(max_y, float(n.get("row", 0)))
		var cell := minf(minf(size.x / (max_x + 1.0), size.y / (max_y + 1.0)), 120.0)
		var used := Vector2((max_x + 1.0) * cell, (max_y + 1.0) * cell)
		var off := ((size - used) * 0.5).floor()
		for n: Dictionary in list:
			_spots[String(n.get("id", ""))] = off + Vector2(float(n.get("col", 0)) * cell + cell * 0.5, (max_y - float(n.get("row", 0))) * cell + cell * 0.5)
		return cell

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.025))
		var cell := _layout()
		if cell <= 0.0:
			return
		var accent := window.tree_color()
		var font := get_theme_default_font()
		var progress := window.progress
		var list: Array = window.nodes()
		var dot_r := clampf(cell * 0.18, 10.0, 17.0)
		for n: Dictionary in list:
			var id := String(n.get("id", ""))
			for req in n.get("requires", []):
				if not _spots.has(String(req)):
					continue
				var lit: bool = progress.rank(String(req)) > 0 and progress.rank(id) > 0
				draw_line(_spots[String(req)], _spots[id], Color(accent, 0.8) if lit else LINE, 3.0, true)
		for n: Dictionary in list:
			var id := String(n.get("id", ""))
			var at: Vector2 = _spots[id]
			var state := window.state_of(n)
			var fade := 0.55 if state == "locked" else 1.0
			if state == "full":
				draw_circle(at, dot_r * 1.55, Color(accent, 0.15))
			if state == "open":
				draw_arc(at, dot_r * 1.55, 0, TAU, 40, Color(accent, 0.35), 2.0, true)
			var fill := accent if state in ["some", "full"] else DOT
			var ring := Color(1, 0.97, 0.88) if state in ["some", "full"] else (accent if state == "open" else Color(1, 1, 1, 0.5 if state == "ready" else 0.25))
			draw_circle(at, dot_r, Color(fill, fade))
			draw_arc(at, dot_r, 0, TAU, 40, Color(ring, fade), 3.0 if state == "open" else 2.0, true)
			if id == window.selected():
				# Dashed white ring round the chosen skill.
				for k in 12:
					var a := TAU * k / 12.0
					draw_arc(at, dot_r * 1.55, a, a + TAU / 24.0, 4, Color(1, 1, 1, 0.9), 2.0, true)
			var name := String(n.get("name", id))
			var fs := 13
			var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var name_col := TEXT if state in ["some", "full", "open"] else SOFT
			draw_string(font, at + Vector2(-w * 0.5, -dot_r - 10.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(name_col, fade))
			var max_r := int(n.get("max_rank", 1))
			if max_r > 1:
				var r := progress.rank(id)
				for k in max_r:
					draw_circle(at + Vector2(-(max_r - 1) * 5.0 + k * 10.0, dot_r + 10.0), 3.0, accent if k < r else Color(1, 1, 1, 0.2))

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var best := ""
			var best_d := 34.0
			for id: String in _spots:
				var d := (_spots[id] as Vector2).distance_to(mb.position)
				if d < best_d:
					best_d = d
					best = id
			if best != "":
				window.select(best)
				accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
