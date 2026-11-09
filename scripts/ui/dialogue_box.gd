class_name DialogueBox
extends CanvasLayer
## The talk window: speaker's name and title, then their lines one at a time, typed out.
## Jump / talk, Attack, Enter or a click shows the whole line, then the next; Esc or
## B closes. Gameplay input is paused while it's open.
##
## After the last line it can offer choices (buttons; left/right or the mouse to pick,
## Jump / talk to choose). A choice's callable may return a reply line to show before
## the window closes.
##
## Lines can use {player} (the character's name) and the player's pronouns:
## {they} {them} {their} {theirs} {themself} (he/him/his..., she/her/hers..., they/them...).

const CHARS_PER_SECOND := 45.0

## When the last conversation closed (msec), so the button press that closed it doesn't
## start a new one or make the player jump.
static var closed_at := 0
static var is_open := false

var _lines: Array = []
var _index := 0
var _shown := 0.0
var _text: RichTextLabel
var _name: Label
var _hint: Label
var _on_done: Callable
var _choices: Array = []  # [label, Callable]
var _choice_row: HBoxContainer
var _choosing := false
var _replying := false
var _from: Node


static func open(from: Node, speaker: String, title: String, lines: Array, on_done: Callable, choices: Array = []) -> DialogueBox:
	var box := DialogueBox.new()
	box._lines = lines.map(func(l: Variant) -> String: return DialogueBox.fill(String(l), from))
	box._on_done = on_done
	box._choices = choices
	box._from = from
	from.get_tree().root.add_child(box)
	box._name.text = speaker + ("  —  " + title if title != "" else "")
	box._name.visible = speaker != ""
	if box._lines.is_empty():
		# Just choices (an event's choice with no text before it).
		box._lines = [""]
		box._show_line()
		box._text.visible = false
		box._show_choices()
	else:
		box._show_line()
	return box


## Swaps in the player's name and pronouns.
static func fill(line: String, from: Node) -> String:
	var session := from.get_tree().root.get_node_or_null("GameSession")
	var data: Dictionary = session.get("data") if session else {}
	var player_name := String(data.get("name", "traveller"))
	var forms := {
		"he": ["he", "him", "his", "his", "himself"],
		"she": ["she", "her", "her", "hers", "herself"],
		"they": ["they", "them", "their", "theirs", "themself"],
	}
	var p: Array = forms.get(String(data.get("pronouns", "they")), forms.they)
	return line.replace("{player}", player_name).replace("{they}", p[0]).replace("{them}", p[1]) \
		.replace("{their}", p[2]).replace("{theirs}", p[3]).replace("{themself}", p[4])


func _init() -> void:
	layer = 18
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.11, 0.9)
	sb.border_color = Color(1.0, 0.82, 0.42).darkened(0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -360
	panel.offset_right = 360
	panel.offset_top = -210
	panel.offset_bottom = -60
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 20)
	_name.add_theme_color_override("font_color", Color(1.0, 0.82, 0.42))
	v.add_child(_name)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 19)
	v.add_child(_text)
	_choice_row = HBoxContainer.new()
	_choice_row.add_theme_constant_override("separation", 10)
	_choice_row.visible = false
	v.add_child(_choice_row)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.modulate = Color(1, 1, 1, 0.6)
	v.add_child(_hint)


func _ready() -> void:
	GameSettings.menu_open = true
	is_open = true


func _show_line() -> void:
	_text.text = _lines[_index]
	_shown = 0.0
	_text.visible_characters = 0
	var keys := GameSettings.events_for("jump", GameSettings.gamepad)
	var key := GameSettings.event_name(keys[0]) if not keys.is_empty() else "Jump"
	var last := _index >= _lines.size() - 1
	if last and _replying:
		_hint.text = "%s  Close" % key
	elif last and not _choices.is_empty():
		_hint.text = "%s  Choose" % key
	else:
		_hint.text = ("%s  Next" if not last else "%s  Goodbye") % key


func _process(delta: float) -> void:
	if _text.visible_characters >= 0:
		_shown += delta * CHARS_PER_SECOND
		_text.visible_characters = int(_shown)
		if _shown >= _text.get_total_character_count():
			_text.visible_characters = -1


func _input(event: InputEvent) -> void:
	if _choosing:
		_choice_input(event)
		return
	var advance: bool = event.is_action_pressed("jump") or event.is_action_pressed("attack") or event.is_action_pressed("ui_accept") \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	var close: bool = event.is_action_pressed("ui_cancel") or event.is_action_pressed("dodge") or event.is_action_pressed("menu")
	if not advance and not close:
		return
	get_viewport().set_input_as_handled()
	if close:
		_finish()
	elif _text.visible_characters >= 0:
		_text.visible_characters = -1  # show the whole line first
	elif _index < _lines.size() - 1:
		_index += 1
		_show_line()
	elif not _choices.is_empty() and not _replying:
		_show_choices()
	else:
		_finish()


func _show_choices() -> void:
	_choosing = true
	_choice_row.visible = true
	for c in _choice_row.get_children():
		c.queue_free()
	for i in _choices.size():
		var b := Button.new()
		b.text = String(_choices[i][0])
		b.custom_minimum_size = Vector2(150, 38)
		b.pressed.connect(_choose.bind(i))
		_choice_row.add_child(b)
	(_choice_row.get_child(0) as Button).grab_focus.call_deferred()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _choice_input(event: InputEvent) -> void:
	var buttons := _choice_row.get_children()
	if buttons.is_empty():
		return
	var focused := buttons.find(get_viewport().gui_get_focus_owner())
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("dodge") or event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		_finish()
	elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		(buttons[posmod(focused - 1, buttons.size())] as Button).grab_focus()
	elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		(buttons[posmod(focused + 1, buttons.size())] as Button).grab_focus()
	elif event.is_action_pressed("jump") or event.is_action_pressed("attack") and not event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
		_choose(maxi(focused, 0))


## Runs choice i; shows its reply line if it gave one, otherwise closes.
func _choose(i: int) -> void:
	if not _choosing:
		return
	_choosing = false
	_choice_row.visible = false
	var action: Callable = _choices[i][1]
	var reply = action.call() if action.is_valid() else null
	if reply is String and reply != "":
		_replying = true
		_lines.append(DialogueBox.fill(reply, _from))
		_index = _lines.size() - 1
		_show_line()
	else:
		_finish()


func _finish() -> void:
	closed_at = Time.get_ticks_msec()
	is_open = false
	GameSettings.menu_open = false
	if _on_done.is_valid():
		_on_done.call()
	queue_free()
