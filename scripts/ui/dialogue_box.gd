class_name DialogueBox
extends CanvasLayer
## The talk window: speaker's name and title, then their lines one at a time, typed out.
## Where it shows:
##   - someone (or something) speaking: a speech bubble over their head, following them;
##   - narration (no speaker): at the bottom, just above the hotbar;
##   - choices (accept / decline a quest...): the question and its buttons move to the
##     upper left of the screen.
## Interact, Jump, Attack, Enter or a click shows the whole line, then the next; Esc or
## B closes. Gameplay input is paused while it's open.
##
## After the last line it can offer choices (buttons; left/right or the mouse to pick,
## Interact to choose). A choice's callable may return a reply line to show before
## the window closes.
##
## Speech bubbles are white with black text (bbcode colours still work); narration and
## choices use the dark panel. Text types out with a soft tick (player.json "dialogue":
## chars_per_second, tick_sound, tick_every, tick_db; each speaker gets their own pitch).
##
## Lines can use {player} (the character's name) and the player's pronouns:
## {they} {them} {their} {theirs} {themself} (he/him/his..., she/her/hers..., they/them...).

const CHARS_PER_SECOND := 45.0
const BUBBLE_WIDTH := 460.0
## Narration sits this far above the bottom of the screen (clear of the hotbar).
const NARRATION_BOTTOM := 150.0
## Choices go to the upper left, below the player frame.
const CHOICES_AT := Vector2(18, 110)

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
var _panel: PanelContainer
var _tail: Polygon2D
var _anchor: Node3D  # the speaker the bubble floats over (null = narration)
var _bubble_style: StyleBoxFlat
var _dark_style: StyleBoxFlat
var _is_bubble := -1  # style in use (-1 = not set yet)
var _tick: AudioStreamPlayer
var _ticked := 0
var _cps := CHARS_PER_SECOND


static func open(from: Node, speaker: String, title: String, lines: Array, on_done: Callable, choices: Array = []) -> DialogueBox:
	var box := DialogueBox.new()
	box._lines = lines.map(func(l: Variant) -> String: return DialogueBox.fill(String(l), from))
	box._on_done = on_done
	box._choices = choices
	box._from = from
	from.get_tree().root.add_child(box)
	box._name.text = speaker + ("  —  " + title if title != "" else "")
	box._name.visible = speaker != ""
	box._anchor = DialogueBox._anchor_of(from) if speaker != "" else null
	box._tick.pitch_scale = 0.85 + float(absi(hash(speaker)) % 1000) / 1000.0 * 0.35 if speaker != "" else 1.0
	if box._lines.is_empty():
		# Just choices (an event's choice with no text before it).
		box._lines = [""]
		box._show_line()
		box._text.visible = false
		box._show_choices()
	else:
		box._show_line()
	return box


## The node a speech bubble should float over: the speaking NPC / object, or for an
## event, its model (or the event itself).
static func _anchor_of(from: Node) -> Node3D:
	var node := from
	if not node is Node3D and "source" in node:
		node = node.get("source")
	if node != null and "_visual" in node and node.get("_visual") is Node3D:
		node = node.get("_visual")
	return node as Node3D


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
	sb.bg_color = Color(0.08, 0.07, 0.11, 0.92)
	sb.border_color = Color(1.0, 0.82, 0.42).darkened(0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	_dark_style = sb
	_bubble_style = StyleBoxFlat.new()
	_bubble_style.bg_color = Color(0.98, 0.97, 0.95)
	_bubble_style.border_color = Color(0.12, 0.11, 0.13)
	_bubble_style.set_border_width_all(2)
	_bubble_style.set_corner_radius_all(16)
	_bubble_style.set_content_margin_all(14)
	panel.custom_minimum_size = Vector2(BUBBLE_WIDTH, 0)
	panel.size = Vector2(BUBBLE_WIDTH, 0)
	add_child(panel)
	_panel = panel
	# The bubble's tail, pointing down at the speaker.
	_tail = Polygon2D.new()
	_tail.polygon = PackedVector2Array([Vector2(-12, 0), Vector2(12, 0), Vector2(0, 18)])
	_tail.color = sb.bg_color
	add_child(_tail)
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
	_tick = AudioStreamPlayer.new()
	_tick.bus = &"SFX"
	add_child(_tick)


## Settings from player.json "dialogue".
func _settings() -> Dictionary:
	var db := get_tree().root.get_node_or_null("Database") if is_inside_tree() else null
	var d = (db.get("player") as Dictionary).get("dialogue", {}) if db else {}
	return d if d is Dictionary else {}


## White bubble with black text over a speaker; the dark panel for narration / choices.
func _set_bubble(on: bool) -> void:
	if int(on) == _is_bubble:
		return
	_is_bubble = int(on)
	_panel.add_theme_stylebox_override("panel", _bubble_style if on else _dark_style)
	_tail.color = _bubble_style.bg_color if on else _dark_style.bg_color
	_text.add_theme_color_override("default_color", Color(0.05, 0.05, 0.06) if on else Color(0.95, 0.94, 0.92))
	_name.add_theme_color_override("font_color", Color(0.45, 0.3, 0.08) if on else Color(1.0, 0.82, 0.42))
	_hint.add_theme_color_override("font_color", Color(0.2, 0.2, 0.22) if on else Color(1, 1, 1))


func _ready() -> void:
	GameSettings.menu_open = true
	is_open = true
	var d := _settings()
	_cps = float(d.get("chars_per_second", CHARS_PER_SECOND))
	var path := String(d.get("tick_sound", ""))
	if path != "" and ResourceLoader.exists(path):
		_tick.stream = load(path)
	_tick.volume_db = float(d.get("tick_db", -14.0))


func _show_line() -> void:
	_text.text = _lines[_index]
	_shown = 0.0
	_ticked = 0
	_text.visible_characters = 0
	var key := GameSettings.interact_label()
	var last := _index >= _lines.size() - 1
	if last and _replying:
		_hint.text = "%s  Close" % key
	elif last and not _choices.is_empty():
		_hint.text = "%s  Choose" % key
	else:
		_hint.text = ("%s  Next" if not last else "%s  Goodbye") % key


func _process(delta: float) -> void:
	_place()
	if _text.visible_characters >= 0:
		_shown += delta * _cps
		_text.visible_characters = int(_shown)
		_tick_sound()
		if _shown >= _text.get_total_character_count():
			_text.visible_characters = -1


## A tick every few letters while the text types out (not on spaces).
func _tick_sound() -> void:
	if _tick.stream == null or not _text.visible:
		return
	var every := maxi(int(_settings().get("tick_every", 2)), 1)
	var n := int(_shown)
	if n - _ticked < every:
		return
	_ticked = n
	var plain := _text.get_parsed_text()
	if n > 0 and n <= plain.length() and plain[n - 1] != " ":
		_tick.play()


func _input(event: InputEvent) -> void:
	if _choosing:
		_choice_input(event)
		return
	var advance: bool = event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("attack") or event.is_action_pressed("ui_accept") \
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


## Bubble over the speaker, narration above the hotbar, choices in the upper left.
func _place() -> void:
	var view := get_viewport().get_visible_rect().size
	_panel.size = Vector2(BUBBLE_WIDTH, 0)  # shrink to fit the text
	var size := _panel.get_combined_minimum_size()
	size.x = BUBBLE_WIDTH
	_tail.visible = false
	if _choosing or _choice_row.visible:
		_set_bubble(false)
		_panel.position = CHOICES_AT
		return
	var cam := get_viewport().get_camera_3d()
	if _anchor and is_instance_valid(_anchor) and cam:
		var top := _head_top(_anchor)
		if not cam.is_position_behind(top):
			var at := cam.unproject_position(top)
			var pos := Vector2(at.x - size.x * 0.5, at.y - size.y - 22.0)
			pos.x = clampf(pos.x, 12.0, view.x - size.x - 12.0)
			pos.y = clampf(pos.y, 12.0, view.y - NARRATION_BOTTOM - size.y)
			_set_bubble(true)
			_panel.position = pos
			_tail.visible = true
			_tail.position = Vector2(clampf(at.x, pos.x + 24.0, pos.x + size.x - 24.0), pos.y + size.y - 2.0)
			return
	_set_bubble(false)
	_panel.position = Vector2((view.x - size.x) * 0.5, view.y - NARRATION_BOTTOM - size.y)


## Just above the speaker's head (its head bone if it has a character model).
static func _head_top(node: Node3D) -> Vector3:
	var model := node.find_child("Character", true, false) as CharacterModel if not node is CharacterModel else node as CharacterModel
	if model:
		var skel := model.get_skeleton()
		var bone := skel.find_bone("mixamorig_HeadTop_End") if skel else -1
		if bone >= 0:
			return (skel.global_transform * skel.get_bone_global_pose(bone)).origin + Vector3.UP * 0.25
	return node.global_position + Vector3.UP * 1.6


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
	elif event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("attack") and not event is InputEventMouseButton:
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
