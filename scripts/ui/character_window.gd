class_name CharacterWindow
extends CanvasLayer
## Character window (I, or Back on a controller), in the bottom-right corner so casting
## and the hotbar stay in view: equipment, stats, and the backpack in tabs
## (Weapons / Armour / Potions / Items / Keys: one 24-slot bag, filtered).
## Pointing at an item shows it, compared with what's equipped: weapon damage per second
## and stat changes in green (better) or red (worse).
## Mouse: drag items between slots (onto the hotbar too; drag out of the window to throw
## away), right-click or double-click to equip / use / take off.
## Controller: move with the D-pad or stick, A = equip / use / take off, Y = pick up and
## put down (move), X = add to the hotbar, LB/RB = tabs, B = close.

const SLOT_SIZE := 46.0
const PANEL := Color(0.08, 0.075, 0.1, 0.95)
const ACCENT := Color(1.0, 0.85, 0.45)
const GOOD := "7fe07f"
const BAD := "ff7a6a"
const TABS := [["weapons", "Weapons"], ["armor", "Armour"], ["potions", "Potions"], ["items", "Items"], ["keys", "Keys"]]

var inventory: Inventory
var stats: Stats
var combat: PlayerCombat

var _window: PanelContainer
var _title_label: Label
var _tab_buttons: Array[Button] = []
var _tab := 0
var _grid: GridContainer
var _bag_slots: Array[ItemSlot] = []  # the grid's slots (key = backpack index)
var _equip_slots := {}  # slot name -> ItemSlot
var _stats_label: RichTextLabel
var _details: RichTextLabel
var _use_button: Button
var _bar_button: Button
var _drop_button: Button
var _selected: ItemSlot = null
var _held: ItemSlot = null  # controller "pick up" source
var _confirm: ConfirmationDialog
var _pending_discard := -1
## The slot a mouse drag started from (set by ItemSlot).
var drag_source: ItemSlot = null


func _init(inv: Inventory, player_stats: Stats, player_combat: PlayerCombat = null) -> void:
	inventory = inv
	stats = player_stats
	combat = player_combat


func _ready() -> void:
	layer = 15
	_build()
	_window.visible = false
	inventory.changed.connect(refresh)
	inventory.equipment_changed.connect(refresh)
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
	elif not is_open():
		return
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("target_clear"):
		if _held:
			_held = null
			refresh()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("target_prev") and GameSettings.is_gamepad_event(event):
		set_tab(_tab - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("target_next") and GameSettings.is_gamepad_event(event):
		set_tab(_tab + 1)
		get_viewport().set_input_as_handled()


# --- Building --------------------------------------------------------------------

func _build() -> void:
	_window = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = ACCENT.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	_window.add_theme_stylebox_override("panel", sb)
	# Bottom right, clear of the hotbar.
	_window.anchor_left = 1.0
	_window.anchor_right = 1.0
	_window.anchor_top = 1.0
	_window.anchor_bottom = 1.0
	_window.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_window.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_window.offset_right = -18
	_window.offset_bottom = -18
	_window.custom_minimum_size = Vector2(318, 0)
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_window)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_window.add_child(outer)
	var head := HBoxContainer.new()
	_title_label = _title("Character", 18)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title_label)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.tooltip_text = "Close (%s)" % GameSettings.binding_label("inventory")
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	head.add_child(close_button)
	outer.add_child(head)

	# Equipment: armour row, then weapons + stats.
	var armour := HBoxContainer.new()
	armour.add_theme_constant_override("separation", 4)
	for slot: String in ["head", "shoulders", "chest", "hands", "legs", "feet"]:
		armour.add_child(_equip_box(slot))
	outer.add_child(armour)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for slot: String in ["primary", "secondary", "off_hand"]:
		row.add_child(_equip_box(slot))
	_stats_label = RichTextLabel.new()
	_stats_label.bbcode_enabled = true
	_stats_label.fit_content = true
	_stats_label.scroll_active = false
	_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_label.add_theme_font_size_override("normal_font_size", 12)
	_stats_label.add_theme_font_size_override("bold_font_size", 12)
	row.add_child(_stats_label)
	outer.add_child(row)

	# Tabs.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i][1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(set_tab.bind(i))
		_tab_buttons.append(b)
		tabs.add_child(b)
	outer.add_child(tabs)

	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	outer.add_child(_grid)

	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.custom_minimum_size = Vector2(0, 150)
	_details.add_theme_font_size_override("normal_font_size", 13)
	_details.add_theme_font_size_override("bold_font_size", 13)
	_details.add_theme_font_size_override("italics_font_size", 13)
	outer.add_child(_details)
	var buttons := HBoxContainer.new()
	_use_button = Button.new()
	_use_button.pressed.connect(func() -> void: if _selected: activate(_selected))
	_bar_button = Button.new()
	_bar_button.text = "To hotbar"
	_bar_button.pressed.connect(func() -> void: if _selected: add_to_hotbar(_selected))
	_drop_button = Button.new()
	_drop_button.text = "Throw away"
	_drop_button.pressed.connect(func() -> void: if _selected and _selected.where == "bag": _ask_discard(_selected.key))
	for b in [_use_button, _bar_button, _drop_button]:
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		buttons.add_child(b)
	outer.add_child(buttons)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Throw away"
	_confirm.confirmed.connect(func() -> void:
		if _pending_discard >= 0:
			inventory.discard(_pending_discard)
		_pending_discard = -1)
	add_child(_confirm)
	set_tab(0)


func _equip_box(slot: String) -> Control:
	var s := ItemSlot.new(self, "equip", slot)
	s.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	s.tooltip_text = Inventory.SLOT_NAMES[slot]
	_equip_slots[slot] = s
	return s


func _title(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	return l


# --- Tabs --------------------------------------------------------------------------

## Which tab an item belongs in.
static func tab_of(d: Dictionary) -> String:
	if bool(d.get("keep", false)) or String(d.get("kind", "")) in ["quest", "key"]:
		return "keys"
	match String(d.get("kind", "")):
		"weapon":
			return "weapons"
		"armor":
			return "armor"
		"consumable":
			return "potions"
	return "items"


func set_tab(i: int) -> void:
	_tab = posmod(i, TABS.size())
	for j in _tab_buttons.size():
		_tab_buttons[j].button_pressed = j == _tab
	_fill_grid()


## The grid shows this tab's items, then the empty backpack slots (each keeps its real
## backpack index, so moving and dropping work as before).
func _fill_grid() -> void:
	var focus_index := -1
	if GameSettings.gamepad and _grid.get_viewport() and _grid.get_viewport().gui_get_focus_owner() is ItemSlot:
		focus_index = _bag_slots.find(_grid.get_viewport().gui_get_focus_owner())
	for s in _bag_slots:
		s.queue_free()
	_bag_slots.clear()
	var want: String = TABS[_tab][0]
	var shown: Array[int] = []
	for i in Inventory.SIZE:
		var s = inventory.bag[i]
		if s and tab_of(Database.item(s.id)) == want:
			shown.append(i)
	for i in Inventory.SIZE:
		if inventory.bag[i] == null:
			shown.append(i)
	for i in shown:
		var slot := ItemSlot.new(self, "bag", i)
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		_bag_slots.append(slot)
		_grid.add_child(slot)
		slot.refresh()
	if focus_index >= 0 and not _bag_slots.is_empty():
		_bag_slots[mini(focus_index, _bag_slots.size() - 1)].grab_focus.call_deferred()
	# Count per tab on the buttons.
	for j in TABS.size():
		var n := 0
		for s in inventory.bag:
			if s and tab_of(Database.item(s.id)) == TABS[j][0]:
				n += 1
		_tab_buttons[j].text = TABS[j][1] + ((" %d" % n) if n > 0 else "")


# --- Contents ----------------------------------------------------------------------

## The item id and count a slot shows.
func contents(slot: ItemSlot) -> Array:
	match slot.where:
		"bag":
			var s = inventory.bag[slot.key]
			return [s.id, s.count] if s else ["", 0]
		"equip":
			return [String(inventory.equipped.get(slot.key, "")), 1]
	return ["", 0]


func refresh() -> void:
	if not is_inside_tree() or not is_open():
		return
	var char_name := String(GameSession.data.get("name", "Character")) if GameSession.active() else "Character"
	_title_label.text = "%s  ·  Level %d" % [char_name, stats.level]
	_fill_grid()
	for s in _equip_slots.values():
		s.refresh()
	_refresh_stats()
	_show_details(_selected if is_instance_valid(_selected) else null)


func _refresh_stats() -> void:
	if _stats_label == null:
		return
	var lines := [
		"Armour [b]%d[/b]   Attack [b]+%d[/b]" % [stats.armor, stats.attack],
		"Spell power [b]+%d[/b]" % stats.spell_power,
	]
	if combat:
		var dps := combat.dps_of(combat.weapon) if not combat.weapon.is_empty() else 0.0
		lines.append("Weapon DPS [b]%.1f[/b]" % dps)
	lines.append("[color=#ffd76a]Gold [b]%d[/b][/color]" % inventory.gold)
	_stats_label.text = "\n".join(lines)


## Shows an item's details.
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
	_bar_button.visible = not d.is_empty() and inventory.is_usable(id) and slot.where == "bag"
	_drop_button.visible = not d.is_empty() and slot.where == "bag"
	if d.is_empty():
		_details.text = "[color=#999999]Point at an item to see what it is. Drag potions and other usable items onto the hotbar.[/color]"
		return
	_use_button.text = "Take off" if slot.where == "equip" else ("Equip" if not inventory.slot_of(id).is_empty() else "Use")
	_details.text = describe(d, _compare_text(d, slot))


## Green/red changes against what this item would replace.
func _compare_text(d: Dictionary, slot: ItemSlot) -> String:
	if slot == null or slot.where != "bag" or String(d.get("slot", "")).is_empty():
		return ""
	var id := String(d.get("id", ""))
	var target := inventory.target_slot(id)
	var current := inventory.equipped_item(target)
	var lines: Array[String] = []
	if inventory.is_weapon(id) and combat:
		var mine := combat.dps_of(d)
		var theirs := combat.dps_of(current) if not current.is_empty() else 0.0
		var delta := mine - theirs
		var col := GOOD if delta >= 0.0 else BAD
		lines.append("[b]%.1f DPS[/b]  [color=#%s](%s%.1f)[/color]" % [mine, col, "+" if delta >= 0.0 else "−", absf(delta)])
		var type_id := String(d.get("weapon_type", ""))
		if combat.is_proficient(type_id):
			lines.append("[color=#%s]Proficient: +%d%% damage, +%d%% speed[/color]" % [GOOD, int(combat.proficiency_damage * 100), int(combat.proficiency_speed * 100)])
		else:
			lines.append("[color=#aaaaaa]Not proficient with %ss[/color]" % Database.weapon_type(type_id).get("name", type_id).to_lower())
	var names := {"armor": "Armour", "attack": "Attack", "spell_power": "Spell power", "bonus_health": "Health", "bonus_mana": "Mana", "block": "Block"}
	for key: String in names:
		if inventory.is_weapon(id) and key == "attack":
			continue  # shown as DPS
		var delta := float(d.get(key, 0.0)) - float(current.get(key, 0.0))
		if absf(delta) < 0.001:
			continue
		var shown := ("%d%%" % int(absf(delta) * 100)) if key == "block" else ("%d" % absf(delta))
		lines.append("[color=#%s]%s%s %s[/color]" % [GOOD if delta > 0.0 else BAD, "+" if delta > 0.0 else "−", shown, names[key]])
	if lines.is_empty():
		return ""
	var header := "vs %s" % current.get("name", "nothing") if not current.is_empty() else "vs empty slot"
	return "[color=#aaaaaa]%s[/color]\n%s" % [header, "\n".join(lines)]


static func describe(d: Dictionary, compare := "") -> String:
	var rarity: Color = ItemIcon.rarity_color(d)
	var t := "[font_size=16][color=#%s]%s[/color][/font_size]\n" % [rarity.to_html(false), d.get("name", "?")]
	var slot := String(d.get("slot", ""))
	var kind := String(d.get("kind", "")).capitalize()
	if slot == "weapon":
		var wt := Database.weapon_type(String(d.get("weapon_type", "")))
		kind = String(wt.get("name", "Weapon"))
		if int(wt.get("hands", 1)) >= 2:
			kind += " · two-handed"
		if float(wt.get("reload", 0.0)) > 0.0:
			kind += " · %.1f s reload" % float(wt.reload)
		if String(wt.get("category", "")) == "ranged" and not bool(d.get("auto_aim", true)):
			kind += " · aimed by hand"
	elif not slot.is_empty():
		kind += " · " + String(Inventory.SLOT_NAMES.get(slot, slot))
	t += "[color=#aaaaaa]%s[/color]\n" % kind
	if not compare.is_empty():
		t += compare + "\n"
	else:
		var stat_names := {"armor": "Armour", "attack": "Attack", "spell_power": "Spell power", "bonus_health": "Health", "bonus_mana": "Mana"}
		for key: String in stat_names:
			var v := float(d.get(key, 0.0))
			if v != 0.0:
				t += "[color=#%s]+%d %s[/color]\n" % [GOOD, v, stat_names[key]]
		if float(d.get("block", 0.0)) > 0.0:
			t += "[color=#%s]+%d%% Block[/color]\n" % [GOOD, int(float(d.block) * 100)]
	if bool(d.get("use_hearth", false)):
		var home: Dictionary = GameSession.data.get("home", {})
		t += "Use: return to %s (%d s, then %d min to recharge).\n" % [home.get("name", "your home"), int(d.get("cast_time", 8)), int(float(d.get("cooldown", 600)) / 60.0)]
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
	refresh()


## Puts a usable item in the first free hotbar box.
func add_to_hotbar(slot: ItemSlot) -> void:
	var id: String = contents(slot)[0]
	if id.is_empty() or not inventory.is_usable(id):
		return
	if inventory.hotbar.has("item:" + id):
		FloatingText.spawn(inventory.get_parent(), "Already on the hotbar", Color(1, 0.9, 0.7), 0.7)
		return
	if not inventory.hotbar.has(""):
		FloatingText.spawn(inventory.get_parent(), "Hotbar full", Color(1, 0.7, 0.6), 0.7)
		return
	inventory.add_to_hotbar("item:" + id)


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


func _id_of(data: Dictionary) -> String:
	match String(data.get("where", "")):
		"bag":
			var s = inventory.bag[int(data.key)]
			return String(s.id) if s else ""
		"equip":
			return String(inventory.equipped.get(String(data.key), ""))
	return ""


func can_drop(data: Variant, target: ItemSlot) -> bool:
	if not data is Dictionary or not data.has("where"):
		return false
	var id := _id_of(data)
	if id.is_empty():
		return false
	match target.where:
		"equip":
			return inventory.fits(id, String(target.key))
		"bag":
			return true
	return false


func drop(data: Dictionary, target: ItemSlot) -> void:
	if not can_drop(data, target):
		return
	match [String(data.where), target.where]:
		["bag", "bag"]:
			inventory.move(int(data.key), target.key)
		["bag", "equip"]:
			inventory.equip_from(int(data.key), String(target.key))
		["equip", "bag"]:
			inventory.unequip(String(data.key), target.key)
		["equip", "equip"]:
			if String(data.key) in Inventory.WEAPON_SLOTS and String(target.key) in Inventory.WEAPON_SLOTS:
				inventory.swap_weapon_slots()
	refresh()


## Dragged out of the window: throw away (from the backpack), unless it went onto the hotbar.
func dropped_outside(data: Dictionary) -> void:
	if _window.get_global_rect().has_point(_window.get_viewport().get_mouse_position()):
		return  # let go somewhere in the window that isn't a slot: nothing happens
	if data.where == "bag":
		_ask_discard(data.key)


func _ask_discard(index: int) -> void:
	if not inventory.can_discard(index):
		if combat:
			combat.notice.emit("You can't throw that away.")
		return
	var s = inventory.bag[index]
	if s == null:
		return
	_pending_discard = index
	var d := Database.item(s.id)
	_confirm.dialog_text = "Throw away %s%s?" % [d.get("name", s.id), (" x%d" % s.count) if s.count > 1 else ""]
	_confirm.popup_centered()
