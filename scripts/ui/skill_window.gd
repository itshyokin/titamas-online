class_name SkillWindow
extends CanvasLayer
## Skill trees (N): the class's trees (data/skill_trees.json, Database → Skill Trees),
## one at a time (tabs along the top), each a grid of tiers. Click a skill to spend a point on it; hover for what
## it does and what it still needs. "Reset" gives every point back. Built by the HUD.

const PANEL := Color(0.08, 0.075, 0.1, 0.96)
const CELL := Vector2(118, 58)

var progress: PlayerProgress
var _window: PanelContainer
var _trees: HBoxContainer
var _points: Label
var _tabs: HBoxContainer
var _tree_index := 0


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
	_window.visible = false
	add_child(_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_window.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "Skills"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", CharacterWindow.ACCENT)
	head.add_child(title)
	_points = Label.new()
	_points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_tabs.add_theme_constant_override("separation", 6)
	v.add_child(_tabs)
	_trees = HBoxContainer.new()
	_trees.add_theme_constant_override("separation", 18)
	v.add_child(_trees)
	progress.skills_changed.connect(func() -> void:
		if is_open():
			_fill())
	Database.changed.connect(func(which: String) -> void:
		if which == "skill_trees" and is_open():
			_fill())


## Shown inside the Codex right now (the Codex handles keys and closing).
var embedded := false


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
	if embedded:
		return
	# N opens the Codex at Skills (Codex handles it); this only closes a standalone window.
	if is_open() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu")):
		close()
		get_viewport().set_input_as_handled()


func _fill() -> void:
	for c in _trees.get_children():
		c.queue_free()
	var free := progress.points_free()
	_points.text = "%d skill point%s to spend" % [free, "" if free == 1 else "s"]
	_points.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35) if free > 0 else Color(0.7, 0.68, 0.64))
	var trees := progress.trees()
	if trees.is_empty():
		var none := Label.new()
		none.text = "This class has no skill trees yet (Database → Skill Trees)."
		_trees.add_child(none)
		return
	for c in _tabs.get_children():
		c.queue_free()
	_tree_index = clampi(_tree_index, 0, trees.size() - 1)
	for i in trees.size():
		var t: Dictionary = trees[i]
		var tab := Button.new()
		tab.text = "%s (%d)" % [t.get("name", ""), progress.points_spent(String(t.get("id", "")))]
		tab.toggle_mode = true
		tab.button_pressed = i == _tree_index
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(func() -> void:
			_tree_index = i
			_fill())
		_tabs.add_child(tab)
	_trees.add_child(_tree_column(trees[_tree_index]))
	_center.call_deferred()


func _center() -> void:
	if embedded:
		return
	_window.reset_size()
	var view := _window.get_viewport_rect().size
	_window.position = ((view - _window.size) * 0.5).floor()


func _tree_column(tree: Dictionary) -> Control:
	var accent := Color.html(String(tree.get("color", "#c9a25a"))) if Color.html_is_valid(String(tree.get("color", ""))) else CharacterWindow.ACCENT
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var name_l := Label.new()
	name_l.text = String(tree.get("description", ""))
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", accent.lightened(0.3))
	col.add_child(name_l)
	var grid := GridContainer.new()
	grid.columns = maxi(int(tree.get("cols", 4)), 1)
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var rows := maxi(int(tree.get("rows", 6)), 1)
	var by_cell := {}
	for n: Dictionary in tree.get("nodes", []):
		by_cell[Vector2i(int(n.get("row", 0)), int(n.get("col", 0)))] = n
	# Only up to the last tier that has a skill.
	var last := 0
	for cell: Vector2i in by_cell:
		last = maxi(last, cell.x)
	for r in mini(rows, last + 1):
		for c in grid.columns:
			var n: Dictionary = by_cell.get(Vector2i(r, c), {})
			grid.add_child(_cell(n, accent) if not n.is_empty() else _blank())
	col.add_child(grid)
	return col


func _blank() -> Control:
	var c := Control.new()
	c.custom_minimum_size = CELL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _cell(n: Dictionary, accent: Color) -> Control:
	var id := String(n.get("id", ""))
	var r := progress.rank(id)
	var max_r := int(n.get("max_rank", 1))
	var why := progress.cant_rank(id)
	var b := Button.new()
	b.custom_minimum_size = CELL
	b.focus_mode = Control.FOCUS_ALL
	b.text = "%s\n%d / %d" % [n.get("name", id), r, max_r]
	b.add_theme_font_size_override("font_size", 13)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	if r >= max_r:
		sb.bg_color = accent.darkened(0.45)
		sb.border_color = accent.lightened(0.2)
	elif why == "":
		sb.bg_color = Color(0.16, 0.14, 0.1)
		sb.border_color = Color(1.0, 0.85, 0.35)
	elif r > 0:
		sb.bg_color = accent.darkened(0.6)
		sb.border_color = accent
	else:
		sb.bg_color = Color(0.1, 0.1, 0.12)
		sb.border_color = Color(0.3, 0.3, 0.34)
		b.modulate = Color(1, 1, 1, 0.6)
	for state in ["normal", "hover", "pressed", "focus"]:
		var st := sb.duplicate() as StyleBoxFlat
		if state == "hover" and why == "":
			st.bg_color = st.bg_color.lightened(0.12)
		b.add_theme_stylebox_override(state, st)
	var tip := "%s\n%s" % [n.get("name", id), n.get("description", "")]
	if int(n.get("cost", 1)) > 1:
		tip += "\nCost: %d points per rank" % int(n.get("cost", 1))
	tip += "\n" + (why if why != "" else "Click to learn rank %d" % (r + 1))
	b.tooltip_text = tip
	b.pressed.connect(func() -> void:
		if not progress.rank_up(id):
			HUD.notify(self, progress.cant_rank(id), Color(1, 0.75, 0.6)))
	return b
