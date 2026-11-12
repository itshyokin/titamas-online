class_name HotbarSlot
extends Panel
## One box on the hotbar (Inventory.hotbar[index]): a spell, an item or a weapon. Click
## (press and release on it, without dragging) to use (a weapon: take it in hand). Drag between boxes to rearrange, off the bar to
## clear; drop spells from the spellbook, items and weapons from the backpack or the
## weapon slot.

const SIZE := 54.0

var bar: Hotbar
var index := 0  # 0-9

var _style := StyleBoxFlat.new()
var _item_icon: ItemIcon
var _ability_icon: AbilityIcon
var _cover: ColorRect
var _timer: Label
var _key: Label


func _init(owner_bar: Hotbar, i: int) -> void:
	bar = owner_bar
	index = i
	custom_minimum_size = Vector2(SIZE, SIZE)
	_style.bg_color = Color(0.07, 0.065, 0.09, 0.82)
	_style.border_color = Color(0.32, 0.3, 0.36)
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(5)
	add_theme_stylebox_override("panel", _style)
	_ability_icon = AbilityIcon.new()
	_item_icon = ItemIcon.new()
	for icon: Control in [_ability_icon, _item_icon]:
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 5
		icon.offset_top = 5
		icon.offset_right = -5
		icon.offset_bottom = -5
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
	_cover = ColorRect.new()
	_cover.color = Color(0, 0, 0, 0.62)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.visible = false
	add_child(_cover)
	_timer = _make_label(17)
	_timer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_timer)
	_key = _make_label(11)
	_key.position = Vector2(4, 1)
	_key.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	add_child(_key)


func _make_label(fs: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## "ability:<id>", "item:<id>" or "".
func entry() -> String:
	return String(bar.inventory.hotbar[index])


## A weapon on this box that's in hand now.
func holds_weapon_in_hand() -> bool:
	var e := entry()
	return e.begins_with("item:") and String(bar.inventory.equipped.get("primary", "")) == e.substr(5)


func refresh() -> void:
	var e := entry()
	_ability_icon.show_ability(null)
	_item_icon.show_item({})
	_item_icon.modulate = Color.WHITE
	var tip := ""
	if e.begins_with("ability:"):
		var ab := Database.ability(e.substr(8))
		_ability_icon.show_ability(ab)
		modulate = Color.WHITE
		if ab:
			tip = "%s\n%s" % [ab.display_name, ab.description]
			if ab.mana_cost > 0.0:
				tip += "\nMana: %d" % ab.mana_cost
			if ab.cast_time > 0.0:
				tip += "   Cast: %.1f s" % ab.cast_time
	elif e.begins_with("item:"):
		var id := e.substr(5)
		var d := Database.item(id)
		var n := bar.inventory.count_of(id)
		if String(d.get("slot", "")) == "weapon":
			var in_hand := holds_weapon_in_hand()
			_item_icon.show_item(d)
			_item_icon.modulate = Color.WHITE if in_hand or n > 0 else Color(1, 1, 1, 0.35)
			tip = "%s\n%s" % [d.get("name", id), "In hand" if in_hand else ("Press to take it in hand" if n > 0 else "Not in your backpack")]
		else:
			_item_icon.show_item(d, n)
			_item_icon.modulate = Color(1, 1, 1, 0.35) if n == 0 else Color.WHITE
			tip = "%s (%d)\n%s" % [d.get("name", id), n, d.get("description", "")]
		modulate = Color.WHITE
	else:
		modulate = Color.WHITE
	_style.border_color = Color(0.32, 0.3, 0.36)
	tooltip_text = tip
	_key.text = GameSettings.binding_label("hotbar_%d" % (index + 1))


## Cooldowns (and "can't afford" tint), each frame.
func update_state(combat: PlayerCombat) -> void:
	var e := entry()
	var left := 0.0
	var total := 1.0
	var dim := false
	if e.begins_with("ability:"):
		var ab := Database.ability(e.substr(8))
		if ab:
			left = combat.cooldown_left(ab)
			total = maxf(ab.cooldown, 0.01)
			dim = not combat.can_afford(ab)
	elif e.begins_with("item:") and bool(Database.item(e.substr(5)).get("use_hearth", false)):
		left = GameSession.hearth_cooldown_left()
		total = maxf(float(Database.item(e.substr(5)).get("cooldown", 600.0)), 1.0)
	_cover.visible = left > 0.0
	if _cover.visible:
		var k := clampf(left / total, 0.0, 1.0)
		_cover.position = Vector2(0, size.y * (1.0 - k))
		_cover.size = Vector2(size.x, size.y * k)
	if left <= 0.0:
		_timer.text = ""
	elif left >= 60.0:
		_timer.text = "%dm" % ceili(left / 60.0)
	else:
		_timer.text = ("%.1f" % left) if left < 10.0 else str(ceili(left))
	_ability_icon.modulate = Color(0.55, 0.55, 0.95) if dim else Color.WHITE


var _pressed := false
var _dragged := false


## Used on release, and only when the press wasn't the start of a drag (rearranging a box
## shouldn't fire it).
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_pressed = not mb.double_click
		_dragged = false
		accept_event()
	elif _pressed:
		_pressed = false
		if not _dragged and not get_viewport().gui_is_dragging() and Rect2(Vector2.ZERO, size).has_point(mb.position):
			bar.use(index)
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	var e := entry()
	if e.is_empty():
		return null
	var holder := Control.new()
	var icon := AbilityIcon.new() if e.begins_with("ability:") else null
	if icon:
		icon.size = Vector2(44, 44)
		icon.show_ability(Database.ability(e.substr(8)))
		holder.add_child(icon)
		icon.position = -icon.size * 0.5
	else:
		var it := ItemIcon.new()
		it.size = Vector2(44, 44)
		it.show_item(Database.item(e.substr(5)))
		holder.add_child(it)
		it.position = -it.size * 0.5
	set_drag_preview(holder)
	_dragged = true
	_pressed = false
	bar.drag_from = index
	return {"where": "hotbar", "key": index}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return bar.can_drop(data, self)


func _drop_data(_at: Vector2, data: Variant) -> void:
	bar.drop(data, self)


func _notification(what: int) -> void:
	# Dragged off the bar (not onto another box): take it off the bar.
	if what == NOTIFICATION_DRAG_END and bar.drag_from == index:
		bar.drag_from = -1
		if not get_viewport().gui_is_drag_successful():
			bar.inventory.set_hotbar(index, "")
