class_name ItemSlot
extends Panel
## One slot in the character window (backpack or equipment). Shows the item's
## icon and stack size, and handles dragging, right/double-click and controller buttons
## (see CharacterWindow).

var window: CharacterWindow
var where := "bag"
var key: Variant

var _icon: ItemIcon
var _style := StyleBoxFlat.new()


func _init(owner_window: CharacterWindow, kind: String, slot_key: Variant) -> void:
	window = owner_window
	where = kind
	key = slot_key
	custom_minimum_size = Vector2(CharacterWindow.SLOT_SIZE, CharacterWindow.SLOT_SIZE)
	focus_mode = Control.FOCUS_ALL
	_style.bg_color = Color(0.16, 0.15, 0.2)
	_style.border_color = Color(0.35, 0.33, 0.4)
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", _style)
	_icon = ItemIcon.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 5
	_icon.offset_top = 5
	_icon.offset_right = -5
	_icon.offset_bottom = -5
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	mouse_entered.connect(func() -> void: window.inspect(self))
	focus_entered.connect(func() -> void:
		window.inspect(self)
		refresh())
	focus_exited.connect(refresh)


func refresh() -> void:
	var c := window.contents(self)
	var d := Database.item(String(c[0]))
	_icon.show_item(d, int(c[1]) if where != "equip" else 0)
	var border := Color(0.35, 0.33, 0.4)
	if not d.is_empty():
		border = ItemIcon.rarity_color(d).darkened(0.25)
	if window.is_held(self):
		border = Color(0.4, 0.8, 1.0)
	elif has_focus():
		border = CharacterWindow.ACCENT
	_style.border_color = border
	_style.bg_color = Color(0.16, 0.15, 0.2) if not d.is_empty() else Color(0.11, 0.1, 0.14)
	if where == "equip" and d.is_empty():
		# A faint outline of what goes here.
		var hint_icon := {"head": "helm", "shoulders": "shoulders", "chest": "chest", "hands": "gloves", "legs": "legs",
			"feet": "boots", "primary": "sword", "secondary": "bow", "off_hand": "shield"}
		_icon.show_item({"icon": hint_icon.get(key, ""), "icon_color": "#ffffff"})
		_icon.modulate = Color(1, 1, 1, 0.12)
	else:
		_icon.modulate = Color.WHITE
	if where == "equip":
		tooltip_text = Inventory.SLOT_NAMES.get(key, "") if d.is_empty() else ""
	else:
		tooltip_text = ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT or (event.button_index == MOUSE_BUTTON_LEFT and event.double_click):
			window.activate(self)
			accept_event()
	elif event.is_action_pressed("ui_accept"):
		window.activate(self)
		accept_event()
	elif event.is_action_pressed("cycle_mode") and GameSettings.is_gamepad_event(event):
		window.pick_or_place(self)
		accept_event()
	elif event.is_action_pressed("sprint") and GameSettings.is_gamepad_event(event):
		window.add_to_hotbar(self)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	var c := window.contents(self)
	if String(c[0]).is_empty():
		return null
	var preview := ItemIcon.new()
	preview.size = Vector2(44, 44)
	preview.show_item(Database.item(String(c[0])), int(c[1]) if where != "equip" else 0)
	var holder := Control.new()
	holder.add_child(preview)
	preview.position = -preview.size * 0.5
	set_drag_preview(holder)
	window.drag_source = self
	return {"where": where, "key": key}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return window.can_drop(data, self)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	window.drop(data, self)


func _notification(what: int) -> void:
	# A drag from here that wasn't dropped on a slot: thrown out of the window.
	if what == NOTIFICATION_DRAG_END and window.drag_source == self:
		window.drag_source = null
		if not get_viewport().gui_is_drag_successful():
			window.dropped_outside({"where": where, "key": key})
