class_name StaminaSlot
extends Panel
## Box 11 on the hotbar: stamina, labelled with the sprint key. It empties from the top
## while sprinting and fills back up as stamina recovers (like an ability cooling down),
## so there's no separate stamina bar. Flashes red when there's too little to sprint.

const SIZE := 54.0

var stats: Stats

var _style := StyleBoxFlat.new()
var _icon: AbilityIcon
var _cover: ColorRect
var _key: Label
var _flash := 0.0
var _last := -1.0


func _init(player_stats: Stats) -> void:
	stats = player_stats
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_style.bg_color = Color(0.07, 0.065, 0.09, 0.82)
	_style.border_color = Color(0.32, 0.3, 0.36)
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(5)
	add_theme_stylebox_override("panel", _style)
	var ab := Ability.new()
	ab.display_name = "Sprint"
	ab.icon = "lightning"
	ab.color = Color(0.92, 0.72, 0.18)
	_icon = AbilityIcon.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 5
	_icon.offset_top = 5
	_icon.offset_right = -5
	_icon.offset_bottom = -5
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_icon.show_ability(ab)
	_cover = ColorRect.new()
	_cover.color = Color(0, 0, 0, 0.62)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)
	_key = Label.new()
	_key.add_theme_font_size_override("font_size", 11)
	_key.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	_key.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_key.add_theme_constant_override("outline_size", 4)
	_key.position = Vector2(4, 1)
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_key)


func _ready() -> void:
	refresh()
	GameSettings.bindings_changed.connect(refresh)
	GameSettings.device_changed.connect(func(_g: bool) -> void: refresh())


func refresh() -> void:
	_key.text = GameSettings.binding_label("sprint")
	tooltip_text = "Stamina: hold %s to sprint" % _key.text


func _process(delta: float) -> void:
	if stats == null:
		return
	var k := clampf(stats.stamina / maxf(stats.max_stamina, 1.0), 0.0, 1.0)
	# Empty part from the top, like a cooldown.
	_cover.visible = k < 0.999
	_cover.position = Vector2(0, 0)
	_cover.size = Vector2(size.x, size.y * (1.0 - k))
	if _last >= 0.0 and k < _last - 0.0001:
		_flash = 0.0
	if k < 0.15 and Input.is_action_pressed("sprint"):
		_flash += delta
	_last = k
	var low := k < 0.15
	_style.border_color = Color(0.85, 0.3, 0.25) if low and fmod(_flash, 0.5) < 0.25 and _flash > 0.0 else (Color(0.92, 0.72, 0.18) if k < 0.999 else Color(0.32, 0.3, 0.36))
	tooltip_text = "Stamina %d / %d: hold %s to sprint" % [ceili(stats.stamina), roundi(stats.max_stamina), _key.text]
