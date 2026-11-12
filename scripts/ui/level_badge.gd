class_name LevelBadge
extends PanelContainer
## A character's level as a gold number on a small dark plate with a gold rim, shown at the
## right end of the name row over the health bars (player frame and party rows).

var _label: Label


func _init(font_size := 15) -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_END
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.12, 0.09, 0.05, 0.92)
	box.border_color = Color(0.85, 0.66, 0.26)
	box.set_border_width_all(2)
	box.set_corner_radius_all(5)
	box.content_margin_left = 7
	box.content_margin_right = 7
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	box.shadow_color = Color(0, 0, 0, 0.4)
	box.shadow_size = 2
	add_theme_stylebox_override("panel", box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.38))
	_label.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.0))
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	tooltip_text = "Level"


func set_level(level: int) -> void:
	_label.text = str(level)
	tooltip_text = "Level %d" % level


## A name row: the name on the left, the badge at the right end (fills its container's width).
static func name_row(name_label: Label, badge: LevelBadge) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)
	row.add_child(badge)
	return row
