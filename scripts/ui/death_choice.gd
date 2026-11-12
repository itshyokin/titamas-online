class_name DeathChoice
extends CanvasLayer
## "You have fallen": shown when the player dies (player.json "camp" death_choice).
##   Wait for help   the screen stays, greyed; a follower (or another player) can come and
##                   revive you (PlayerController.revive). Only offered when someone could.
##   Return to camp  the usual fade and wake at the last campfire (or home).
## Names no autoloads (built by PlayerController).

signal chose(wait: bool)

static var _open: DeathChoice

var _wait_button: Button
var _camp_button: Button
var _status: Label
var _dim: ColorRect
var _waiting := false
var can_wait := Callable()


static func open(parent: Node, camp_label: String, wait_check: Callable) -> DeathChoice:
	close()
	var d := DeathChoice.new()
	d.can_wait = wait_check
	d.layer = 30
	parent.add_child(d)
	d._build(camp_label)
	_open = d
	return d


static func close() -> void:
	if is_instance_valid(_open):
		_open.queue_free()
	_open = null


static func is_waiting() -> bool:
	return is_instance_valid(_open) and _open._waiting


func _build(camp_label: String) -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.05, 0.02, 0.03, 0.35)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(360, 0)
	box.position = Vector2(-180, -60)
	add_child(box)
	var title := Label.new()
	title.text = "You have fallen"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.95, 0.4, 0.35))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_status.add_theme_constant_override("outline_size", 6)
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_wait_button = _button("Wait for help")
	_wait_button.pressed.connect(func() -> void:
		_waiting = true
		_wait_button.disabled = true
		chose.emit(true))
	row.add_child(_wait_button)
	_camp_button = _button(camp_label)
	_camp_button.pressed.connect(func() -> void:
		chose.emit(false))
	row.add_child(_camp_button)
	_refresh()
	_camp_button.grab_focus.call_deferred()


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 40)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.1, 0.92)
	sb.border_color = Color(0.85, 0.66, 0.26)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.17, 0.1, 0.95)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	var off := sb.duplicate() as StyleBoxFlat
	off.border_color = Color(0.4, 0.38, 0.36)
	b.add_theme_stylebox_override("disabled", off)
	return b


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var someone := bool(can_wait.call()) if can_wait.is_valid() else false
	if _waiting:
		_status.text = "Waiting for help…" if someone else "No one is coming. Return to camp."
		_status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	else:
		_wait_button.disabled = not someone
		_status.text = "A companion can come and revive you." if someone else "No one is near to help."
		_status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
