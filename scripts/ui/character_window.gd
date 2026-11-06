class_name CharacterWindow
extends CanvasLayer
## Character window (I, or Back on a controller): equipment slots, stats, gold, the two
## quick-item slots and the 24-slot backpack.
## Mouse: drag items between slots (drag out of the window to throw away), right-click
## or double-click to equip / use / take off.
## Controller: move with the D-pad or stick, A = equip / use / take off, Y = pick up and
## put down (move), X = put a potion/bandage on the next quick slot, B = close.

const SLOT_SIZE := 54.0
const PANEL := Color(0.08, 0.075, 0.1, 0.95)
const ACCENT := Color(1.0, 0.85, 0.45)

var inventory: Inventory
var stats: Stats

var _window: PanelContainer
var _bag_slots: Array[ItemSlot] = []
var _equip_slots := {}  # slot name -> ItemSlot
var _quick_slots: Array[ItemSlot] = []
var _stats_label: RichTextLabel
var _details: RichTextLabel
var _use_button: Button
var _quick_button: Button
var _drop_button: Button
var _selected: ItemSlot = null
var _held: ItemSlot = null  # controller "pick up" source
var _confirm: ConfirmationDialog
var _pending_discard := -1
## The slot a mouse drag started from (set by ItemSlot).
var drag_source: ItemSlot = null


func _init(inv: Inventory, player_stats: Stats) -> void:
	inventory = inv
	stats = player_stats


func _ready() -> void:
	layer = 15
	_build()
	_window.visible = false
	inventory.changed.connect(refresh)
	inventory.gold_changed.connect(func(_g: int) -> void: refresh())
	stats.health_changed.connect(func(_a: float, _b: float) -> void: _refresh_stats())


func is_open() -> bool:
	return _window.visible


func open() -> void:
	_window.visible = true
	GameSettings.menu_open = true
	refresh()
	if GameSettings.gamepad and not _bag_slots.is_empty():
		_bag_slots[0].grab_focus()


func close() -> void:
	_window.visible = false
	_held = null
	GameSettings.menu_open = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		close() if is_open() else open()
		get_viewport().set_input_as_handled()
	elif is_open() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("target_clear")):
		if _held:
			_held = null
			refresh()
		else:
			close()
		get_viewport().set_input_as_handled()


# --- Building --------------------------------------------------------------------

func _build() -> void:
	_window = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = ACCENT.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	_window.add_theme_stylebox_override("panel", sb)
	_window.set_anchors_preset(Control.PRESET_CENTER)
	_window.custom_minimum_size = Vector2(900, 560)
	_window.position = Vector2(-450, -290)
	add_child(_window)
	_window.mouse_filter = Control.MOUSE_FILTER_STOP

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_window.add_child(outer)
	var head := HBoxContainer.new()
	head.add_child(_title("Character", 24))
	var hint := Label.new()
	hint.text = "Drag to move · right-click to equip/use · drag out to throw away"
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(hint)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	head.add_child(close_button)
	outer.add_child(head)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(columns)

	# Equipment.
	var eq := VBoxContainer.new()
	eq.add_child(_title("Equipment", 16))
	var eq_grid := GridContainer.new()
	eq_grid.columns = 3
	eq_grid.add_theme_constant_override("h_separation", 6)
	eq_grid.add_theme_constant_override("v_separation", 6)
	for slot: String in Inventory.SLOTS:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		var s := ItemSlot.new(self, "equip", slot)
		_equip_slots[slot] = s
		box.add_child(s)
		var l := Label.new()
		l.text = Inventory.SLOT_NAMES[slot]
		l.add_theme_font_size_override("font_size", 11)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.modulate = Color(1, 1, 1, 0.6)
		box.add_child(l)
		eq_grid.add_child(box)
	eq.add_child(eq_grid)
	columns.add_child(eq)

	# Stats, gold, quick slots.
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(190, 0)
	mid.add_child(_title("Stats", 16))
	_stats_label = RichTextLabel.new()
	_stats_label.bbcode_enabled = true
	_stats_label.fit_content = true
	_stats_label.scroll_active = false
	_stats_label.custom_minimum_size = Vector2(190, 0)
	mid.add_child(_stats_label)
	mid.add_child(_title("Quick items", 16))
	var quick_row := HBoxContainer.new()
	for i in Inventory.QUICK_SLOTS:
		var s := ItemSlot.new(self, "quick", i)
		_quick_slots.append(s)
		quick_row.add_child(s)
	mid.add_child(quick_row)
	var qhint := Label.new()
	qhint.text = "Used with %s / %s" % [GameSettings.binding_label("item_prev"), GameSettings.binding_label("item_next")]
	qhint.modulate = Color(1, 1, 1, 0.6)
	qhint.add_theme_font_size_override("font_size", 12)
	mid.add_child(qhint)
	columns.add_child(mid)

	# Backpack + details.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_title("Backpack", 16))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for i in Inventory.SIZE:
		var s := ItemSlot.new(self, "bag", i)
		_bag_slots.append(s)
		grid.add_child(s)
	right.add_child(grid)
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.custom_minimum_size = Vector2(0, 120)
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_details)
	var buttons := HBoxContainer.new()
	_use_button = Button.new()
	_use_button.pressed.connect(func() -> void: if _selected: activate(_selected))
	_quick_button = Button.new()
	_quick_button.text = "Set as quick item"
	_quick_button.pressed.connect(func() -> void: if _selected: assign_quick(_selected))
	_drop_button = Button.new()
	_drop_button.text = "Throw away"
	_drop_button.pressed.connect(func() -> void: if _selected and _selected.where == "bag": _ask_discard(_selected.key))
	for b in [_use_button, _quick_button, _drop_button]:
		b.focus_mode = Control.FOCUS_NONE
		buttons.add_child(b)
	right.add_child(buttons)
	columns.add_child(right)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Throw away"
	_confirm.confirmed.connect(func() -> void:
		if _pending_discard >= 0:
			inventory.discard(_pending_discard)
		_pending_discard = -1)
	add_child(_confirm)


func _title(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	return l


# --- Contents ----------------------------------------------------------------------

## The item id and count a slot shows.
func contents(slot: ItemSlot) -> Array:
	match slot.where:
		"bag":
			var s = inventory.bag[slot.key]
			return [s.id, s.count] if s else ["", 0]
		"equip":
			return [String(inventory.equipped.get(slot.key, "")), 1]
		"quick":
			var id: String = inventory.quick[slot.key]
			return [id, inventory.count_of(id)] if not id.is_empty() else ["", 0]
	return ["", 0]


func refresh() -> void:
	if not is_inside_tree():
		return
	for s in _bag_slots + _quick_slots + _equip_slots.values():
		s.refresh()
	_refresh_stats()
	_show_details(_selected)


func _refresh_stats() -> void:
	if _stats_label == null:
		return
	var lines := [
		"Health  [b]%d[/b] / %d" % [stats.health, stats.max_health],
		"Mana  [b]%d[/b] / %d" % [stats.mana, stats.max_mana],
		"Armour  [b]%d[/b]" % stats.armor,
		"Attack  [b]+%d[/b]" % stats.attack,
		"Spell power  [b]+%d[/b]" % stats.spell_power,
	]
	if stats.block > 0.0:
		lines.append("Block  [b]+%d%%[/b]" % int(stats.block * 100))
	lines.append("")
	lines.append("[color=#ffd76a]Gold  [b]%d[/b][/color]" % inventory.gold)
	_stats_label.text = "\n".join(lines)


## Shows an item's details below the backpack.
func inspect(slot: ItemSlot) -> void:
	_selected = slot
	_show_details(slot)


func _show_details(slot: ItemSlot) -> void:
	if _details == null:
		return
	var c := contents(slot) if slot else ["", 0]
	var id: String = c[0]
	var d := Database.item(id)
	_use_button.visible = not d.is_empty()
	_quick_button.visible = not d.is_empty() and inventory.is_usable(id)
	_drop_button.visible = not d.is_empty() and slot.where == "bag"
	if d.is_empty():
		_details.text = "[color=#999999]Point at an item to see what it is.[/color]"
		return
	_use_button.text = "Take off" if slot.where == "equip" else ("Equip" if not inventory.slot_of(id).is_empty() else "Use")
	_details.text = describe(d)


static func describe(d: Dictionary) -> String:
	var rarity: Color = ItemIcon.rarity_color(d)
	var t := "[font_size=18][color=#%s]%s[/color][/font_size]\n" % [rarity.to_html(false), d.get("name", "?")]
	var slot := String(d.get("slot", ""))
	var kind := String(d.get("kind", "")).capitalize()
	t += "[color=#aaaaaa]%s%s[/color]\n" % [kind, (" · " + Inventory.SLOT_NAMES.get(slot, slot)) if not slot.is_empty() else ""]
	var stat_names := {"armor": "Armour", "attack": "Attack", "spell_power": "Spell power", "bonus_health": "Health", "bonus_mana": "Mana"}
	for key: String in stat_names:
		var v := float(d.get(key, 0.0))
		if v != 0.0:
			t += "[color=#7fe07f]+%d %s[/color]\n" % [v, stat_names[key]]
	if float(d.get("block", 0.0)) > 0.0:
		t += "[color=#7fe07f]+%d%% Block[/color]\n" % int(float(d.block) * 100)
	if float(d.get("use_heal", 0.0)) > 0.0:
		t += "Use: restores %d health.\n" % float(d.use_heal)
	if float(d.get("use_hot_per_tick", 0.0)) > 0.0:
		t += "Use: heals %d over %d seconds.\n" % [float(d.use_hot_per_tick) * int(d.get("use_hot_ticks", 1)), int(d.get("use_hot_ticks", 1)) * 2]
	if float(d.get("use_mana", 0.0)) > 0.0:
		t += "Use: restores %d mana.\n" % float(d.use_mana)
	if not String(d.get("description", "")).is_empty():
		t += "[i]%s[/i]\n" % d.description
	t += "[color=#ffd76a]Worth %d gold[/color]" % int(d.get("value", 0))
	return t


# --- Actions -----------------------------------------------------------------------

## Equip / use / take off.
func activate(slot: ItemSlot) -> void:
	match slot.where:
		"bag":
			if inventory.bag[slot.key]:
				inventory.use_at(slot.key)
		"equip":
			if not inventory.unequip(slot.key):
				FloatingText.spawn(inventory.get_parent(), "Backpack full", Color(1, 0.7, 0.6), 0.8)
		"quick":
			inventory.set_quick(slot.key, "")
	refresh()


## Puts a usable item on the next quick slot (cycling 1 -> 2).
func assign_quick(slot: ItemSlot) -> void:
	var id: String = contents(slot)[0]
	if id.is_empty() or not inventory.is_usable(id):
		return
	var i := inventory.quick.find(id)
	inventory.set_quick((i + 1) % Inventory.QUICK_SLOTS if i >= 0 else 0, id)
	if i >= 0:
		inventory.set_quick(i, "")
	refresh()


## Controller move: first press picks up, second press puts down.
func pick_or_place(slot: ItemSlot) -> void:
	if _held == null:
		if not String(contents(slot)[0]).is_empty():
			_held = slot
	else:
		var from := _held
		_held = null
		drop({"where": from.where, "key": from.key}, slot)
	refresh()


func is_held(slot: ItemSlot) -> bool:
	return _held == slot


func can_drop(data: Variant, target: ItemSlot) -> bool:
	if not data is Dictionary or not data.has("where"):
		return false
	var id: String = contents(_slot_for(data))[0]
	if id.is_empty():
		return false
	match target.where:
		"equip":
			return inventory.slot_of(id) == target.key
		"quick":
			return inventory.is_usable(id)
		"bag":
			return data.where != "quick"
	return false


func drop(data: Dictionary, target: ItemSlot) -> void:
	if not can_drop(data, target):
		return
	var from := _slot_for(data)
	match [from.where, target.where]:
		["bag", "bag"]:
			inventory.move(from.key, target.key)
		["bag", "equip"]:
			inventory.equip_from(from.key)
		["equip", "bag"]:
			inventory.unequip(from.key, target.key)
		["bag", "quick"], ["quick", "quick"]:
			var id: String = contents(from)[0]
			if from.where == "quick":
				inventory.set_quick(from.key, inventory.quick[target.key])
			inventory.set_quick(target.key, id)
	refresh()


## Dragged out of the window: throw away (backpack) or clear (quick slot).
func dropped_outside(data: Dictionary) -> void:
	if _window.get_global_rect().has_point(_window.get_viewport().get_mouse_position()):
		return  # let go somewhere in the window that isn't a slot: nothing happens
	if data.where == "bag":
		_ask_discard(data.key)
	elif data.where == "quick":
		inventory.set_quick(data.key, "")
		refresh()


func _ask_discard(index: int) -> void:
	var s = inventory.bag[index]
	if s == null:
		return
	_pending_discard = index
	var d := Database.item(s.id)
	_confirm.dialog_text = "Throw away %s%s?" % [d.get("name", s.id), (" x%d" % s.count) if s.count > 1 else ""]
	_confirm.popup_centered()


func _slot_for(data: Dictionary) -> ItemSlot:
	match data.where:
		"bag":
			return _bag_slots[data.key]
		"equip":
			return _equip_slots[data.key]
		_:
			return _quick_slots[data.key]
