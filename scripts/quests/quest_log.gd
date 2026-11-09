class_name QuestLog
extends CanvasLayer
## Quest log (L): active quests on the left, then finished ones; the picked quest's
## giver, story, objectives with progress, and rewards on the right. Built by the HUD.

const PANEL := Color(0.08, 0.075, 0.1, 0.96)

var _window: PanelContainer
var _list: VBoxContainer
var _detail: RichTextLabel
var _picked := ""
var _rewards: HBoxContainer


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
	_window.custom_minimum_size = Vector2(640, 380)
	_window.visible = false
	add_child(_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_window.add_child(v)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Quests"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", CharacterWindow.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	head.add_child(close_button)
	v.add_child(head)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(220, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 15)
	_detail.add_theme_font_size_override("bold_font_size", 15)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	right.add_child(_detail)
	_rewards = HBoxContainer.new()
	_rewards.add_theme_constant_override("separation", 6)
	right.add_child(_rewards)
	cols.add_child(right)


## Shown inside the Codex right now (the Codex handles keys and closing).
var embedded := false


func is_open() -> bool:
	return _window.visible


func open() -> void:
	_fill()
	_window.visible = true
	_window.reset_size()
	_window.position = ((_window.get_viewport_rect().size - _window.size) * 0.5).floor()
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
	if event.is_action_pressed("quest_log"):
		if is_open():
			close()
		elif not GameSettings.menu_open:
			open()
		get_viewport().set_input_as_handled()
	elif is_open() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu")):
		close()
		get_viewport().set_input_as_handled()


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var groups := [["Active", ["active"]], ["Finished", ["done", "failed"]]]
	var first := ""
	for g: Array in groups:
		var qs := Quests.all().filter(func(q: Dictionary) -> bool: return Quests.state(String(q.get("id", ""))) in g[1])
		if qs.is_empty():
			continue
		var h := Label.new()
		h.text = g[0]
		h.add_theme_color_override("font_color", Color(0.7, 0.68, 0.64))
		_list.add_child(h)
		for q: Dictionary in qs:
			var id := String(q.get("id", ""))
			if first.is_empty():
				first = id
			var b := Button.new()
			b.text = String(q.get("name", id)) + ("  ✓" if Quests.ready(id) else "")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.button_pressed = id == _picked
			b.pressed.connect(func() -> void:
				_picked = id
				_fill())
			_list.add_child(b)
	if first.is_empty():
		var none := Label.new()
		none.text = "No quests yet. Look for a ! over someone's head."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(none)
		_detail.text = ""
		return
	if Quests.state(_picked) == "not_started":
		_picked = first
	_show(_picked)


func _show(id: String) -> void:
	var q := Quests.get_quest(id)
	var gold := CharacterWindow.ACCENT.to_html(false)
	var t := "[font_size=20][color=#%s]%s[/color][/font_size]\n" % [gold, q.get("name", id)]
	if String(q.get("giver", "")) != "":
		t += "[color=#bfb7aa]From %s[/color]\n" % q.giver
	var st := Quests.state(id)
	if st == "done":
		t += "[color=#9be08a]Complete[/color]\n"
	elif st == "failed":
		t += "[color=#e07a6a]Failed[/color]\n"
	elif Quests.ready(id):
		t += "[color=#9be08a]Ready to hand in[/color]\n"
	t += "\n%s\n\n[b]Objectives[/b]\n" % q.get("description", "")
	for o: Dictionary in q.get("objectives", []):
		var p := Quests.progress(id, o)
		var done := p.x >= p.y
		t += "  %s %s%s\n" % ["✓" if done else "•", o.get("text", ""), ("  %d / %d" % [p.x, p.y]) if p.y > 1 else ""]
	for c in _rewards.get_children():
		c.queue_free()
	var line := Quests.rewards_line(q)
	var items := Quests.reward_items(q)
	if line != "" or not items.is_empty():
		t += "\n[b]Rewards[/b]\n  %s\n" % line
	for r: Dictionary in items:
		_rewards.add_child(RewardItem.new(String(r.item), int(r.count)))
	_detail.text = t
