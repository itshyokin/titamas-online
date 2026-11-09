class_name QuestOffer
extends CanvasLayer
## The quest offer (event command "quest" op "offer"), in the upper left where choices go:
## name, giver, story, objectives and rewards (XP, gold, items with comparison tooltips),
## then Accept / Decline. `on_done(accepted: bool)` is called once; Esc / B declines.

const WIDTH := 420.0

var quest_id := ""
var _on_done: Callable
var _accept: Button
var _decline: Button
var _done := false


static func open(from: Node, id: String, on_done: Callable) -> QuestOffer:
	var o := QuestOffer.new()
	o.quest_id = id
	o._on_done = on_done
	from.get_tree().root.add_child(o)
	return o


func _ready() -> void:
	layer = 14
	var q := Quests.get_quest(quest_id)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.11, 0.94)
	sb.border_color = CharacterWindow.ACCENT.darkened(0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = DialogueBox.CHOICES_AT
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := Label.new()
	title.text = String(q.get("name", quest_id))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", CharacterWindow.ACCENT)
	v.add_child(title)
	if String(q.get("giver", "")) != "":
		var giver := Label.new()
		giver.text = "From %s" % q.giver
		giver.add_theme_color_override("font_color", Color(0.75, 0.72, 0.67))
		v.add_child(giver)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(WIDTH, 0)
	var t := "%s\n\n[b]Objectives[/b]\n" % DialogueBox.fill(String(q.get("description", "")), self)
	for o: Dictionary in q.get("objectives", []):
		var p := Quests.progress(quest_id, o)
		t += "  • %s%s\n" % [o.get("text", ""), ("  (%d)" % p.y) if p.y > 1 else ""]
	body.text = t
	v.add_child(body)
	var line := Quests.rewards_line(q)
	var items := Quests.reward_items(q)
	if line != "" or not items.is_empty():
		var head := Label.new()
		head.text = "Rewards"
		head.add_theme_color_override("font_color", CharacterWindow.ACCENT)
		v.add_child(head)
		if line != "":
			var l := Label.new()
			l.text = line
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(WIDTH, 0)
			v.add_child(l)
		if not items.is_empty():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			for r: Dictionary in items:
				row.add_child(RewardItem.new(String(r.item), int(r.count)))
			v.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_accept = Button.new()
	_accept.text = "Accept"
	_accept.custom_minimum_size = Vector2(150, 38)
	_accept.pressed.connect(_finish.bind(true))
	_decline = Button.new()
	_decline.text = "Decline"
	_decline.custom_minimum_size = Vector2(150, 38)
	_decline.pressed.connect(_finish.bind(false))
	buttons.add_child(_accept)
	buttons.add_child(_decline)
	v.add_child(buttons)
	_accept.grab_focus.call_deferred()
	GameSettings.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("dodge") or event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		_finish(false)
	elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left") or event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		(_decline if _accept.has_focus() else _accept).grab_focus()
	elif event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		get_viewport().set_input_as_handled()
		_finish(not _decline.has_focus())


func _finish(accepted: bool) -> void:
	if _done:
		return
	_done = true
	DialogueBox.closed_at = Time.get_ticks_msec()
	GameSettings.menu_open = false
	if accepted:
		Quests.start(quest_id)
	if _on_done.is_valid():
		_on_done.call(accepted)
	queue_free()
