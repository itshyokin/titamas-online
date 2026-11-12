class_name SpeechBubble
extends CanvasLayer
## A line spoken out loud while play goes on (the "Say" event command: a companion
## guiding you, a shout across a field): a white bubble over the speaker's head that types
## itself out, holds, then fades. Nothing waits for a key. Optional voice clip from the
## speaker, and the line also goes to the game log. Off-screen speakers still talk: the
## bubble sits at the screen edge nearest them.

const WIDTH := 340.0
const PER_LETTER := 0.055

var speaker: Node3D
var speaker_name := ""
var text := ""
var seconds := 0.0  # 0 = long enough to read

var _panel: PanelContainer
var _name: Label
var _text: RichTextLabel
var _tail: Polygon2D
var _tick: AudioStreamPlayer
var _age := 0.0
var _shown := 0.0
var _ticked := 0
var _cps := 45.0


## Says `line` over `who` (may be null: the bubble then sits low in the middle). Returns
## the bubble; it frees itself, emitting tree_exited, when done.
static func say(from: Node, who: Node3D, who_name: String, line: String, show_for := 0.0, voice: AudioStream = null) -> SpeechBubble:
	# One bubble per speaker: a new line replaces the old one.
	for b in from.get_tree().get_nodes_in_group("speech_bubbles"):
		if (b as SpeechBubble).speaker == who:
			b.queue_free()
	var b := SpeechBubble.new()
	b.speaker = who
	b.speaker_name = who_name
	b.text = line
	b.seconds = show_for if show_for > 0.0 else 1.6 + line.length() * PER_LETTER
	from.get_tree().root.add_child(b)
	if voice and who:
		var p := AudioStreamPlayer3D.new()
		p.stream = voice
		p.bus = &"SFX"
		p.max_distance = 60.0
		who.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	return b


func _ready() -> void:
	layer = 6
	add_to_group("speech_bubbles")
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.97, 0.95)
	style.border_color = Color(0.12, 0.11, 0.13)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(10)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_panel.add_child(box)
	_name = Label.new()
	_name.text = speaker_name
	_name.visible = not speaker_name.is_empty()
	_name.add_theme_color_override("font_color", Color(0.45, 0.3, 0.08))
	_name.add_theme_font_size_override("font_size", 14)
	box.add_child(_name)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.text = text
	_text.visible_characters = 0
	_text.add_theme_color_override("default_color", Color(0.05, 0.05, 0.06))
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text)
	_tail = Polygon2D.new()
	_tail.color = style.bg_color
	add_child(_tail)
	_tick = AudioStreamPlayer.new()
	_tick.bus = &"SFX"
	var d := _settings()
	_cps = float(d.get("chars_per_second", 45.0))
	var path := String(d.get("tick_sound", ""))
	if path != "" and ResourceLoader.exists(path):
		_tick.stream = load(path)
	_tick.volume_db = float(d.get("tick_db", -14.0)) - 4.0
	_tick.pitch_scale = 0.9 + float(hash(speaker_name) % 30) / 100.0
	add_child(_tick)
	_place()


func _settings() -> Dictionary:
	var db := get_tree().root.get_node_or_null("Database")
	var d = (db.get("player") as Dictionary).get("dialogue", {}) if db else {}
	return d if d is Dictionary else {}


func _process(delta: float) -> void:
	_age += delta
	# The speaker's mouth moves while the line types out.
	var model := DialogueBox.model_of(speaker) if is_instance_valid(speaker) else null
	if model:
		model.talking = _text.visible_characters >= 0
	if _text.visible_characters >= 0:
		_shown += delta * _cps
		_text.visible_characters = int(_shown)
		var n := int(_shown)
		if _tick.stream and n - _ticked >= 2:
			_ticked = n
			var plain := _text.get_parsed_text()
			if n > 0 and n <= plain.length() and plain[n - 1] != " ":
				_tick.play()
		if _shown >= _text.get_total_character_count():
			_text.visible_characters = -1
	var fade := clampf((seconds - _age) / 0.4, 0.0, 1.0) * clampf(_age / 0.12, 0.0, 1.0)
	_panel.modulate.a = fade
	_tail.modulate.a = fade
	if _age >= seconds:
		if model:
			model.talking = false
		queue_free()
		return
	_place()


## Over the speaker's head, kept on screen; the tail points at them.
func _place() -> void:
	var screen := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_3d()
	var size := _panel.get_combined_minimum_size()
	_panel.size = size
	var anchor := Vector2(screen.x * 0.5, screen.y * 0.62)
	var on_screen := false
	if is_instance_valid(speaker) and cam:
		var head := DialogueBox._head_top(speaker)
		if not cam.is_position_behind(head):
			anchor = cam.unproject_position(head)
			on_screen = Rect2(Vector2.ZERO, screen).has_point(anchor)
		else:
			# Behind the camera: along the bottom on their side.
			var side := cam.global_basis.x.dot(head - cam.global_position)
			anchor = Vector2(screen.x * (0.92 if side > 0.0 else 0.08), screen.y * 0.7)
	var pos := anchor - Vector2(size.x * 0.5, size.y + 18.0)
	pos.x = clampf(pos.x, 12.0, screen.x - size.x - 12.0)
	pos.y = clampf(pos.y, 70.0, screen.y - size.y - 150.0)
	_panel.position = pos
	_tail.visible = on_screen
	if on_screen:
		var bx := clampf(anchor.x, pos.x + 20.0, pos.x + size.x - 20.0)
		var by := pos.y + size.y - 2.0
		_tail.polygon = PackedVector2Array([Vector2(bx - 9, by), Vector2(bx + 9, by), Vector2(anchor.x, minf(anchor.y - 4.0, by + 16.0))])
