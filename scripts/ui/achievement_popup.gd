class_name AchievementPopup
extends CanvasLayer
## "Achievement unlocked" (as in Saturn): a round badge pops in above the
## hotbar, opens out into a bar with "Achievement unlocked" and the points and name; the
## name gives way to how it was earned for a moment, then it closes and fades.
## Achievements (autoload) queues them.

var def: Dictionary = {}
var sound: AudioStream

var _pill: Panel
var _badge: Control
var _small: Label
var _line: Label
var _clip: Control
const HEIGHT := 62.0
const OPEN_WIDTH := 440.0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_pill = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.15, 0.18, 0.96)
	sb.border_color = Color(0.81, 0.83, 0.86)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(HEIGHT / 2))
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 10
	_pill.add_theme_stylebox_override("panel", sb)
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.size = Vector2(HEIGHT, HEIGHT)
	root.add_child(_pill)
	_badge = Trophy.new()
	(_badge as Trophy).icon = AchievementPopup.icon_of(def)
	_badge.size = Vector2(HEIGHT - 4, HEIGHT - 4)
	_badge.position = Vector2(2, 2)
	_pill.add_child(_badge)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.position = Vector2(HEIGHT + 6, 0)
	_clip.size = Vector2(OPEN_WIDTH - HEIGHT - 26, HEIGHT)
	_clip.modulate.a = 0.0
	_pill.add_child(_clip)
	_small = Label.new()
	_small.text = "Achievement unlocked"
	_small.add_theme_font_size_override("font_size", 12)
	_small.add_theme_color_override("font_color", Color(0.81, 0.83, 0.86))
	_small.position = Vector2(0, 9)
	_clip.add_child(_small)
	_line = Label.new()
	_line.add_theme_font_size_override("font_size", 16)
	_line.add_theme_color_override("font_color", Color(1, 1, 1))
	_line.position = Vector2(0, 27)
	_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_line.size = Vector2(_clip.size.x, 24)
	_clip.add_child(_line)
	var pts := int(def.get("points", 0))
	_line.text = ("%d pts – " % pts if pts > 0 else "") + String(def.get("name", ""))
	_place()
	get_viewport().size_changed.connect(_place)
	_run()


func _place() -> void:
	var view := get_viewport().get_visible_rect().size
	_pill.position = Vector2((view.x - _pill.size.x) * 0.5, view.y - 190.0)


func _run() -> void:
	if sound:
		var p := AudioStreamPlayer.new()
		p.stream = sound
		p.bus = &"SFX"
		add_child(p)
		p.play()
	# Badge pops in.
	_pill.pivot_offset = _pill.size * 0.5
	_pill.scale = Vector2(0.2, 0.2)
	var t := create_tween()
	t.tween_property(_pill, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished
	# Opens into a bar with the name.
	t = create_tween().set_parallel(true)
	t.tween_method(_set_width, HEIGHT, OPEN_WIDTH, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_clip, "modulate:a", 1.0, 0.25).set_delay(0.2)
	await get_tree().create_timer(2.8).timeout
	# How it was earned.
	var how := String(def.get("description", ""))
	if how != "":
		t = create_tween()
		t.tween_property(_line, "modulate:a", 0.0, 0.2)
		t.tween_callback(func() -> void: _line.text = how)
		t.tween_property(_line, "modulate:a", 1.0, 0.25)
		await get_tree().create_timer(3.0).timeout
	# Closes and fades.
	t = create_tween().set_parallel(true)
	t.tween_property(_clip, "modulate:a", 0.0, 0.2)
	t.tween_method(_set_width, OPEN_WIDTH, HEIGHT, 0.35).set_delay(0.1)
	await t.finished
	t = create_tween()
	t.tween_property(_pill, "modulate:a", 0.0, 0.45)
	await t.finished
	queue_free()


func _set_width(w: float) -> void:
	_pill.size.x = w
	_place()


## The achievement's icon image (its "icon" res:// path), or null for the trophy.
static func icon_of(d: Dictionary) -> Texture2D:
	var path := String(d.get("icon", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## The round green badge with a cup (or the achievement's icon) on it. `locked` greys it.
class Trophy:
	extends Control

	var icon: Texture2D
	var locked := false

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var dark := Color(0.23, 0.54, 0.16) if not locked else Color(0.22, 0.23, 0.26)
		var light := Color(0.4, 0.7, 0.28) if not locked else Color(0.32, 0.33, 0.37)
		var mid := Color(0.33, 0.66, 0.22) if not locked else Color(0.27, 0.28, 0.31)
		draw_circle(c, r, dark)
		draw_circle(c + Vector2(-r * 0.15, -r * 0.18), r * 0.8, light)
		draw_circle(c, r * 0.78, mid)
		if icon:
			var s := r * 1.2
			draw_texture_rect(icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1) if not locked else Color(0.5, 0.5, 0.5))
			return
		var gold := Color(1.0, 0.85, 0.42) if not locked else Color(0.55, 0.56, 0.6)
		var cup := PackedVector2Array([c + Vector2(-r * 0.4, -r * 0.45), c + Vector2(r * 0.4, -r * 0.45),
			c + Vector2(r * 0.28, r * 0.05), c + Vector2(-r * 0.28, r * 0.05)])
		draw_colored_polygon(cup, gold)
		draw_arc(c + Vector2(-r * 0.4, -r * 0.25), r * 0.17, PI * 0.5, PI * 1.5, 10, gold, 3.0)
		draw_arc(c + Vector2(r * 0.4, -r * 0.25), r * 0.17, -PI * 0.5, PI * 0.5, 10, gold, 3.0)
		draw_rect(Rect2(c + Vector2(-r * 0.07, r * 0.05), Vector2(r * 0.14, r * 0.22)), gold)
		draw_rect(Rect2(c + Vector2(-r * 0.26, r * 0.27), Vector2(r * 0.52, r * 0.12)), gold)
