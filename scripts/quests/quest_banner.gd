class_name QuestBanner
extends Control
## Big centred banner for quest news (Quests → HUD.quest_banner): a small caption
## ("Quest accepted", "Quest complete", "Ready to hand in"…) over the quest's name between
## two thin rules, fading in and out. A second one waits for the first.
## Made by the HUD.

const SECONDS := 3.2

var _caption := Label.new()
var _title := Label.new()
var _rules: Array[ColorRect] = []
var _queue: Array = []
var _busy := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -360
	offset_right = 360
	offset_top = 150
	offset_bottom = 230
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	for l: Label in [_caption, _title]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_caption.add_theme_font_size_override("font_size", 16)
	_caption.add_theme_constant_override("outline_size", 6)
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_constant_override("outline_size", 9)
	for i in 2:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(0, 2)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rules.append(r)
	box.add_child(_rules[0])
	box.add_child(_caption)
	box.add_child(_title)
	box.add_child(_rules[1])


func show_banner(caption: String, title: String, color: Color) -> void:
	_queue.append([caption, title, color])
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var b: Array = _queue.pop_front()
	_caption.text = String(b[0]).to_upper()
	_title.text = String(b[1])
	var col: Color = b[2]
	_caption.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.35))
	_title.add_theme_color_override("font_color", col)
	for r in _rules:
		r.color = Color(col, 0.7)
	var t := create_tween()
	scale = Vector2(0.92, 0.92)
	pivot_offset = size * 0.5
	t.set_parallel()
	t.tween_property(self, "modulate:a", 1.0, 0.3)
	t.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_interval(SECONDS)
	t.chain().tween_property(self, "modulate:a", 0.0, 0.7)
	t.chain().tween_callback(_next)
