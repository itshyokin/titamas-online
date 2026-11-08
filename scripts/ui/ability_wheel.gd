class_name AbilityWheel
extends Control
## Controller hotbar: hold the wheel button (D-pad up) and the eight hotbar boxes (3-10)
## fan out in a ring; point the right stick at one and let go to use it. You can keep walking
## with the left stick; the camera holds still while the wheel is up. Built by the HUD.

const RADIUS := 130.0
const BOX := 58.0

var hotbar: Hotbar
var _open := false
var _choice := -1
var _icons: Array[Control] = []  # per entry: a holder with an icon


func _init(bar: Hotbar) -> void:
	hotbar = bar


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	for i in 8:
		var holder := Panel.new()
		holder.size = Vector2(BOX, BOX)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ab := AbilityIcon.new()
		var it := ItemIcon.new()
		for icon: Control in [ab, it]:
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = 5
			icon.offset_top = 5
			icon.offset_right = -5
			icon.offset_bottom = -5
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(icon)
		add_child(holder)
		_icons.append(holder)


func is_open() -> bool:
	return _open


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ability_wheel") and not _open and not GameSettings.menu_open:
		_show()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("ability_wheel") and _open:
		_close(true)
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		_close(false)
		get_viewport().set_input_as_handled()


func _show() -> void:
	_open = true
	_choice = -1
	visible = true
	# The right stick picks, so it stops turning the camera meanwhile.
	GameSettings.wheel_open = true
	var inv := hotbar.inventory
	for i in 8:
		var holder := _icons[i]
		var e := String(inv.hotbar[i])
		var ab_icon := holder.get_child(0) as AbilityIcon
		var item_icon := holder.get_child(1) as ItemIcon
		ab_icon.show_ability(Database.ability(e.substr(8)) if e.begins_with("ability:") else null)
		item_icon.show_item(Database.item(e.substr(5)) if e.begins_with("item:") else {},
			inv.count_of(e.substr(5)) if e.begins_with("item:") else 0)
	queue_redraw()


func _close(use: bool) -> void:
	_open = false
	visible = false
	GameSettings.wheel_open = false
	if use and _choice >= 0:
		hotbar.combat.use_hotbar(_choice)


func _process(_delta: float) -> void:
	if not _open:
		return
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	var before := _choice
	if stick.length() > 0.5:
		# 0 = top, going clockwise.
		var angle := fposmod(atan2(stick.x, -stick.y), TAU)
		_choice = int(round(angle / (TAU / 8.0))) % 8
	if before != _choice:
		queue_redraw()
	var centre := get_viewport_rect().size * 0.5
	for i in 8:
		var a := i * TAU / 8.0
		var at := centre + Vector2(sin(a), -cos(a)) * RADIUS
		var holder := _icons[i]
		var big := 1.18 if i == _choice else 1.0
		holder.size = Vector2(BOX, BOX)
		holder.pivot_offset = holder.size * 0.5
		holder.scale = Vector2(big, big)
		holder.position = at - holder.size * 0.5
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.065, 0.09, 0.9)
		sb.border_color = Hotbar.GOLD if i == _choice else Color(0.35, 0.33, 0.4)
		sb.set_border_width_all(3 if i == _choice else 2)
		sb.set_corner_radius_all(8)
		holder.add_theme_stylebox_override("panel", sb)


func _draw() -> void:
	if not _open:
		return
	var centre := get_viewport_rect().size * 0.5
	draw_circle(centre, RADIUS + BOX * 0.8, Color(0, 0, 0, 0.35))
	draw_arc(centre, RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.12), 2.0)
	var font := get_theme_default_font()
	var text := "Let go to use"
	if _choice >= 0:
		var e := String(hotbar.inventory.hotbar[_choice])
		if e.begins_with("ability:"):
			var ab := Database.ability(e.substr(8))
			text = ab.display_name if ab else ""
		elif e.begins_with("item:"):
			text = String(Database.item(e.substr(5)).get("name", ""))
		else:
			text = "(empty)"
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string_outline(font, centre + Vector2(-w * 0.5, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color.BLACK)
	draw_string(font, centre + Vector2(-w * 0.5, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Hotbar.GOLD)
