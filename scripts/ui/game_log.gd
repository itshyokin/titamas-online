class_name GameLog
extends Control
## Bottom-left game log and chat. Anything can post a line with GameLog.post(text, colour)
## (experience, levels, loot, deaths, who joined). Lines fade after a while unless the
## chat is open. Chat (Enter): type and press Enter to send to everyone in co-op (Esc
## cancels). Built by the HUD.

const MAX_LINES := 60
const SHOWN_SECONDS := 12.0
const WIDTH := 420.0
const HEIGHT := 170.0

static var _instance: GameLog
## Lines posted before the log existed (or between levels), shown once it does.
static var _pending: Array = []

var _scroll: ScrollContainer
var _lines: VBoxContainer
var _input: LineEdit
var _back: Panel
var _typing := false


## Adds a line to the log.
static func post(text: String, color := Color(0.9, 0.9, 0.88)) -> void:
	if _instance and is_instance_valid(_instance) and _instance.is_inside_tree():
		_instance._add(text, color)
	else:
		_pending.append([text, color])
		if _pending.size() > 20:
			_pending.pop_front()


func _ready() -> void:
	_instance = self
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 18
	offset_right = 18 + WIDTH
	offset_top = -HEIGHT - 52
	offset_bottom = -52
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.55)
	sb.set_corner_radius_all(6)
	_back.add_theme_stylebox_override("panel", sb)
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.visible = false
	add_child(_back)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 6
	_scroll.offset_right = -6
	_scroll.offset_top = 4
	_scroll.offset_bottom = -4
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroll)
	_lines = VBoxContainer.new()
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.size_flags_vertical = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	_lines.add_theme_constant_override("separation", 1)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_lines)
	_input = LineEdit.new()
	_input.placeholder_text = "Say something (Enter to send, Esc to cancel)"
	_input.anchor_top = 1.0
	_input.anchor_bottom = 1.0
	_input.anchor_right = 1.0
	_input.offset_top = 6
	_input.offset_bottom = 38
	_input.max_length = 200
	_input.visible = false
	_input.text_submitted.connect(_send)
	add_child(_input)
	var net := get_tree().root.get_node_or_null("Net")
	if net:
		net.connect("chat_received", func(who: String, text: String) -> void: _add("[%s] %s" % [who, text], Color(1, 1, 1)))
	for p in _pending:
		_add(p[0], p[1])
	_pending.clear()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func is_typing() -> bool:
	return _typing


func _add(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 16, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("born", Time.get_ticks_msec())
	_lines.add_child(l)
	while _lines.get_child_count() > MAX_LINES:
		_lines.get_child(0).free()
	_scroll_down.call_deferred()


func _scroll_down() -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var shown := 0.0
	for l: Label in _lines.get_children():
		if _typing:
			l.modulate.a = 1.0
			continue
		var age := (now - int(l.get_meta("born", now))) / 1000.0
		l.modulate.a = clampf((SHOWN_SECONDS - age) / 2.0, 0.0, 1.0)
		shown = maxf(shown, l.modulate.a)
	# A faint backing while there's something to read; darker while typing.
	_back.visible = _typing or shown > 0.0
	_back.modulate.a = 1.0 if _typing else shown * 0.6


func _unhandled_input(event: InputEvent) -> void:
	if _typing:
		if event.is_action_pressed("ui_cancel"):
			_close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("chat") and not GameSettings.menu_open and not event.is_echo():
		_open()
		get_viewport().set_input_as_handled()


func _open() -> void:
	_typing = true
	GameSettings.menu_open = true
	_back.visible = true
	_input.visible = true
	_input.text = ""
	_input.grab_focus()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS


func _close() -> void:
	_typing = false
	GameSettings.menu_open = false
	_input.release_focus()
	_input.visible = false
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_down()


func _send(text: String) -> void:
	text = text.strip_edges()
	_close()
	if text.is_empty():
		return
	var who := String(GameSession.data.get("name", "You")) if GameSession.active() else "You"
	_add("[%s] %s" % [who, text], Color(1, 1, 1))
	var net := get_tree().root.get_node_or_null("Net")
	if net and net.get("active"):
		net.call("send_chat", who, text)
