class_name ShopWindow
extends CanvasLayer
## A merchant's shop (event command "shop", data/shops.json, Database → Shops).
## Buy: the shop's stock at item value × buy_rate (or the entry's own price); limited stock
## (count > 0) is remembered per character and comes back after restock_hours of play.
## Sell: anything in the backpack with a value (not "keep" items like the hearthstone) for
## value × sell_rate, if the shop buys that kind (buys: "all" or a list of item kinds).
## Click a row to buy / sell one (Shift: five). Esc, the Close button or walking off closes.

signal closed

const SIZE := Vector2(620, 520)

var shop := {}
var player: Node3D
var inventory: Inventory

var _tab := 0
var _rows: VBoxContainer
var _gold: Label
var _note: Label
var _tabs: TabBar
var _started := 0
static var _loose := {}


## Opens shop `id` for `who` (the player). Returns the window ({} shop = null).
static func open(id: String, who: Node3D) -> ShopWindow:
	var data := ShopWindow.find_shop(id)
	if data.is_empty() or who == null:
		push_warning("Shop: no shop '%s' in data/shops.json" % id)
		return null
	var w := ShopWindow.new()
	w.shop = data
	w.player = who
	w.inventory = who.get_node_or_null("Inventory") as Inventory
	who.get_tree().root.add_child(w)
	return w


static func find_shop(id: String) -> Dictionary:
	var d = DataFiles.read("res://data/shops.json")
	for s in (d.get("shops", []) if d is Dictionary else []):
		if s is Dictionary and String(s.get("id", "")) == id:
			return s
	return {}


func _ready() -> void:
	layer = 15
	_started = Time.get_ticks_msec()
	GameSettings.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiSounds.play("open")
	_build()
	_fill()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		close()
	elif event is InputEventKey and event.pressed and Time.get_ticks_msec() - _started > 400 \
			and (event as InputEventKey).physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
		close()


func close() -> void:
	if not is_inside_tree():
		return
	UiSounds.play("close")
	GameSettings.menu_open = false
	closed.emit()
	queue_free()


# --- Prices and stock ---------------------------------------------------------------

func buy_price(entry: Dictionary) -> int:
	var d := Database.item(String(entry.get("item", "")))
	var own := float(entry.get("price", 0.0))
	if own > 0.0:
		return int(own)
	return maxi(int(round(float(d.get("value", 0.0)) * float(shop.get("buy_rate", 1.0)))), 1)


func sell_price(d: Dictionary) -> int:
	return int(floor(float(d.get("value", 0.0)) * float(shop.get("sell_rate", 0.4))))


func buys(d: Dictionary) -> bool:
	if bool(d.get("keep", false)) or float(d.get("value", 0.0)) <= 0.0:
		return false
	var kinds = shop.get("buys", "all")
	if kinds is Array:
		return String(d.get("kind", "")) in kinds
	return String(kinds) == "all"


## What's left of a limited entry (count > 0): saved per character in data "shops".
func stock_left(entry: Dictionary) -> int:
	var count := int(entry.get("count", -1))
	if count <= 0:
		return -1  # endless
	var mem := _memory()
	var sold: Dictionary = mem.get("sold", {})
	return maxi(count - int(sold.get(String(entry.item), 0)), 0)


func _memory() -> Dictionary:
	# Kept in the save; without a session (F6) only for this run.
	var all: Dictionary = GameSession.data.get("shops", {}) if GameSession.active() else ShopWindow._loose
	var mine: Dictionary = all.get(String(shop.id), {})
	# Restock after so many hours of play.
	var hours := float(shop.get("restock_hours", 2.0))
	var now := GameSession.play_seconds() if GameSession.has_method("play_seconds") else 0.0
	if hours > 0.0 and now - float(mine.get("since", 0.0)) > hours * 3600.0:
		mine = {"since": now, "sold": {}}
	all[String(shop.id)] = mine
	if GameSession.active():
		GameSession.data["shops"] = all
	return mine


func _note_sold(item_id: String, n: int) -> void:
	var mem := _memory()
	var sold: Dictionary = mem.get("sold", {})
	sold[item_id] = int(sold.get(item_id, 0)) + n
	mem["sold"] = sold


# --- Buying and selling ---------------------------------------------------------------

func _buy(entry: Dictionary, n: int) -> void:
	var id := String(entry.get("item", ""))
	var left := stock_left(entry)
	if left >= 0:
		n = mini(n, left)
	var price := buy_price(entry)
	n = mini(n, inventory.gold / maxi(price, 1))
	if n <= 0:
		_say("Not enough gold" if left != 0 else "Sold out", Color(1.0, 0.5, 0.4))
		UiSounds.play("error")
		return
	var didnt := inventory.add_item(id, n)
	var got := n - didnt
	if got <= 0:
		_say("Your backpack is full", Color(1.0, 0.5, 0.4))
		UiSounds.play("error")
		return
	inventory.add_gold(-price * got)
	if left >= 0:
		_note_sold(id, got)
	_say("Bought %s%s for %d gold" % [Database.item(id).get("name", id), " x%d" % got if got > 1 else "", price * got], Color(0.7, 1.0, 0.6))
	inventory.play_equip_sound(id, -6.0)
	_fill()


func _sell(id: String, n: int) -> void:
	var d := Database.item(id)
	n = mini(n, inventory.count_of(id))
	if n <= 0:
		return
	# Equipped items aren't in the backpack, so they can't be sold by accident.
	var gone := inventory.remove_item(id, n)
	var price := sell_price(d) * gone
	inventory.add_gold(price)
	_say("Sold %s%s for %d gold" % [d.get("name", id), " x%d" % gone if gone > 1 else "", price], Color(1.0, 0.85, 0.4))
	UiSounds.play("click")
	_fill()


func _say(text: String, color: Color) -> void:
	_note.text = text
	_note.add_theme_color_override("font_color", color)


# --- Window -------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.075, 0.1, 0.96)
	sb.border_color = CharacterWindow.ACCENT.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = SIZE
	panel.position = -SIZE * 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = String(shop.get("name", "Shop"))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", CharacterWindow.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_gold = Label.new()
	_gold.add_theme_font_size_override("font_size", 18)
	_gold.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	head.add_child(_gold)
	v.add_child(head)
	if String(shop.get("greeting", "")) != "":
		var greet := Label.new()
		greet.text = String(shop.greeting)
		greet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		greet.add_theme_color_override("font_color", Color(0.8, 0.78, 0.86))
		v.add_child(greet)
	_tabs = TabBar.new()
	_tabs.add_tab("Buy")
	_tabs.add_tab("Sell")
	_tabs.tab_changed.connect(func(t: int) -> void:
		_tab = t
		_fill())
	v.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 3)
	scroll.add_child(_rows)
	var foot := HBoxContainer.new()
	_note = Label.new()
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.text = "Click to buy or sell one · Shift-click for five"
	_note.add_theme_color_override("font_color", Color(0.6, 0.58, 0.66))
	foot.add_child(_note)
	var close_b := Button.new()
	close_b.text = "Close"
	close_b.pressed.connect(close)
	foot.add_child(close_b)
	v.add_child(foot)


func _fill() -> void:
	for c in _rows.get_children():
		c.queue_free()
	_gold.text = "%d gold" % inventory.gold
	if _tab == 0:
		for entry in shop.get("stock", []):
			if not entry is Dictionary:
				continue
			var d := Database.item(String(entry.get("item", "")))
			if d.is_empty():
				continue
			var left := stock_left(entry)
			var price := buy_price(entry)
			var extra := "" if left < 0 else ("  ·  sold out" if left == 0 else "  ·  %d left" % left)
			var b := _row(d, String(d.get("name", entry.item)) + extra, "%d g" % price, price <= inventory.gold and left != 0)
			var e: Dictionary = entry
			b.pressed.connect(func() -> void: _buy(e, 5 if Input.is_key_pressed(KEY_SHIFT) else 1))
	else:
		var seen := {}
		for s in inventory.bag:
			if s == null or seen.has(s.id):
				continue
			seen[s.id] = true
			var d := Database.item(String(s.id))
			if not buys(d):
				continue
			var count := inventory.count_of(String(s.id))
			var b := _row(d, String(d.get("name", s.id)) + (" x%d" % count if count > 1 else ""), "%d g" % sell_price(d), true)
			var id := String(s.id)
			b.pressed.connect(func() -> void: _sell(id, 5 if Input.is_key_pressed(KEY_SHIFT) else 1))
		if seen.is_empty() or _rows.get_child_count() == 0:
			var none := Label.new()
			none.text = "Nothing in your backpack they'd buy."
			none.add_theme_color_override("font_color", Color(0.6, 0.58, 0.66))
			_rows.add_child(none)


func _row(d: Dictionary, text: String, price: String, can: bool) -> Button:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 40)
	b.text = "         " + text
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", ItemIcon.rarity_color(d) if d.has("rarity") else Color(1, 0.92, 0.75))
	b.modulate = Color.WHITE if can else Color(1, 1, 1, 0.5)
	b.tooltip_text = String(d.get("description", ""))
	var icon := ItemIcon.new()
	icon.position = Vector2(5, 4)
	icon.size = Vector2(32, 32)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.show_item(d)
	b.add_child(icon)
	var p := Label.new()
	p.text = price
	p.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	p.add_theme_font_size_override("font_size", 15)
	p.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	p.offset_left = -90
	p.offset_right = -14
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(p)
	_rows.add_child(b)
	return b
