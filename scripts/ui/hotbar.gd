class_name Hotbar
extends Control
## The bottom bar: experience bar on top, then ten boxes. Boxes 1-2 are the primary and
## secondary weapons (the one in use has a gold frame with a little arrow, which slides
## across on a swap; the other is dimmed). Boxes 3-10 hold spells and items.
## Built by the HUD.

const GOLD := Color(1.0, 0.82, 0.35)
const GAP := 4.0
const WEAPON_GAP := 14.0

var inventory: Inventory
var combat: PlayerCombat
var slots: Array[HotbarSlot] = []
## Box a mouse drag started from (-1 = none).
var drag_from := -1

var xp_bar: ProgressBar
var xp_label: Label
var _row: HBoxContainer
var _frame: Panel
var _arrow: Control
var _frame_tween: Tween
var _level_now: Label
var _level_next: Label
var stamina_box: StaminaSlot


func _init(inv: Inventory, player_combat: PlayerCombat) -> void:
	inventory = inv
	combat = player_combat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	# Room between the experience bar and the boxes for the weapon frame's arrow.
	box.add_theme_constant_override("separation", 20)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	# Experience.
	xp_bar = ProgressBar.new()
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(0, 9)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.07, 0.8)
	bg.border_color = Color(0.25, 0.22, 0.3)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.62, 0.38, 0.95)
	fill.set_corner_radius_all(4)
	fill.border_color = Color(0.85, 0.7, 1.0, 0.6)
	fill.border_width_top = 1
	xp_bar.add_theme_stylebox_override("background", bg)
	xp_bar.add_theme_stylebox_override("fill", fill)
	xp_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Current level on the left, the next one on the right.
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 6)
	xp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_now = _level_label()
	_level_next = _level_label()
	xp_row.add_child(_level_now)
	xp_row.add_child(xp_bar)
	xp_row.add_child(_level_next)
	box.add_child(xp_row)
	xp_label = Label.new()
	xp_label.add_theme_font_size_override("font_size", 11)
	xp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	xp_label.add_theme_constant_override("outline_size", 3)
	xp_label.set_anchors_preset(Control.PRESET_CENTER)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_label.visible = false
	xp_bar.add_child(xp_label)
	xp_bar.mouse_entered.connect(func() -> void: xp_label.visible = true)
	xp_bar.mouse_exited.connect(func() -> void: xp_label.visible = false)
	# The boxes.
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", int(GAP))
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_row)
	for i in 10:
		var s := HotbarSlot.new(self, i)
		slots.append(s)
		_row.add_child(s)
		if i == 1:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(WEAPON_GAP - GAP, 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_row.add_child(gap)
	# Box 11: stamina (the sprint key); drains while sprinting and fills back up.
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(WEAPON_GAP - GAP, 0)
	gap2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(gap2)
	stamina_box = StaminaSlot.new(combat.get_parent().get_node("Stats") as Stats)
	_row.add_child(stamina_box)
	# Gold frame + arrow over the weapon in use.
	_frame = Panel.new()
	var fs := StyleBoxFlat.new()
	fs.draw_center = false
	fs.border_color = GOLD
	fs.set_border_width_all(3)
	fs.set_corner_radius_all(6)
	fs.shadow_color = Color(1.0, 0.75, 0.2, 0.35)
	fs.shadow_size = 6
	_frame.add_theme_stylebox_override("panel", fs)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.size = Vector2(HotbarSlot.SIZE + 4, HotbarSlot.SIZE + 4)
	add_child(_frame)
	_arrow = Control.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.size = Vector2(16, 10)
	_arrow.position = Vector2((_frame.size.x - 16) * 0.5, -14)
	_arrow.draw.connect(func() -> void:
		_arrow.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(16, 0), Vector2(8, 10)]), GOLD)
		_arrow.draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(16, 0), Vector2(8, 10), Vector2(0, 0)]), Color(0.3, 0.2, 0.05), 1.0))
	_frame.add_child(_arrow)
	box.resized.connect(func() -> void:
		size = box.size
		custom_minimum_size = box.size
		_place_frame(false))

	inventory.hotbar_changed.connect(refresh)
	inventory.changed.connect(refresh)
	inventory.equipment_changed.connect(refresh)
	inventory.weapon_swapped.connect(func(_s: String) -> void:
		refresh()
		_place_frame(true))
	GameSettings.bindings_changed.connect(refresh)
	GameSettings.device_changed.connect(func(_g: bool) -> void: refresh())
	Database.changed.connect(func(_w: String) -> void: refresh())
	refresh()


func refresh() -> void:
	for s in slots:
		s.refresh()


func _process(_delta: float) -> void:
	for s in slots:
		s.update_state(combat)
	# Keep the frame on its box while nothing animates it (the row lays itself out a frame
	# or two after loading, and the active weapon can be restored after the HUD is built).
	if not (_frame_tween and _frame_tween.is_running()):
		_place_frame(false)


func _place_frame(animate: bool) -> void:
	if slots.is_empty():
		return
	var target := slots[0 if inventory.active_weapon == "primary" else 1]
	var to := target.position + _row.position - Vector2(2, 2)
	if _frame_tween:
		_frame_tween.kill()
	if animate and is_inside_tree():
		_frame_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_frame_tween.tween_property(_frame, "position", to, 0.22)
		# A little bounce of the arrow as it lands.
		_frame_tween.tween_property(_arrow, "position:y", -18.0, 0.08)
		_frame_tween.tween_property(_arrow, "position:y", -14.0, 0.12)
	else:
		_frame.position = to


## Click or key: use a box (weapons: switch to it).
func use(i: int) -> void:
	if i < 2:
		combat.select_weapon(Inventory.WEAPON_SLOTS[i])
	else:
		combat.use_hotbar(i - 2)


func _level_label() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.85, 0.72, 1.0))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.custom_minimum_size = Vector2(18, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func set_xp(current: int, needed: int, level: int, max_level: bool) -> void:
	_level_now.text = str(level)
	_level_next.text = "" if max_level else str(level + 1)
	xp_bar.max_value = maxf(needed, 1)
	xp_bar.value = xp_bar.max_value if max_level else current
	xp_label.text = "Level %d · max level" % level if max_level else "Level %d · %d / %d XP" % [level, current, needed]
	xp_bar.tooltip_text = xp_label.text


# --- Drag and drop --------------------------------------------------------------

func can_drop(data: Variant, target: HotbarSlot) -> bool:
	if not data is Dictionary or not data.has("where"):
		return false
	var id := _item_of(data)
	match String(data.where):
		"hotbar":
			return not target.is_weapon_box()
		"spellbook":
			return not target.is_weapon_box()
		"bag":
			if target.is_weapon_box():
				return inventory.is_weapon(id)
			return inventory.is_usable(id)
		"equip":
			return target.is_weapon_box() and inventory.is_weapon(id)
	return false


func drop(data: Dictionary, target: HotbarSlot) -> void:
	if not can_drop(data, target):
		return
	match String(data.where):
		"hotbar":
			inventory.move_hotbar(int(data.key), target.index - 2)
		"spellbook":
			inventory.set_hotbar(target.index - 2, "ability:" + String(data.key))
		"bag":
			if target.is_weapon_box():
				inventory.equip_from(int(data.key), target.weapon_slot())
			else:
				inventory.set_hotbar(target.index - 2, "item:" + _item_of(data))
		"equip":
			if String(data.key) != target.weapon_slot() and String(data.key) in Inventory.WEAPON_SLOTS:
				inventory.swap_weapon_slots()
	refresh()


func _item_of(data: Dictionary) -> String:
	match String(data.where):
		"bag":
			var s = inventory.bag[int(data.key)]
			return String(s.id) if s else ""
		"equip":
			return String(inventory.equipped.get(String(data.key), ""))
	return ""
