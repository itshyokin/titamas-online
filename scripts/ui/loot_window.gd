class_name LootWindow
extends CanvasLayer
## Looking through a body's loot: the character kneels (animation role "loot"), holds
## still partway down (data/animations.json "loot.pause_at") while a small window shows
## over the body, and gets up again when it closes.
## Click (or A / Space on) an entry to take it; Take all (R / Y); close with Esc / B or by
## walking off. Closes by itself when everything's taken or you're hit.

const WIDTH := 250.0

var bag: LootBag
var player: PlayerController
var inventory: Inventory

var _panel: PanelContainer
var _rows: VBoxContainer
var _closing := false
var _paused := false
var _started := 0  # msec


static func open_for(loot: LootBag, who: Node3D) -> void:
	var pc := who as PlayerController
	if pc == null or loot.open or GameSettings.menu_open:
		return
	if not pc.start_action(0.0):
		return
	var w := LootWindow.new()
	w.bag = loot
	w.player = pc
	w.inventory = pc.get_node_or_null("Inventory") as Inventory
	pc.add_child(w)


func _ready() -> void:
	layer = 14
	bag.open = true
	_started = Time.get_ticks_msec()
	GameSettings.menu_open = true
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	player.face_toward(bag.global_position)
	player.action_animation.emit("loot", 0.0, 0.2, 1.0)
	player.action_interrupted.connect(_close)
	var stats := player.get_node_or_null("Stats") as Stats
	if stats:
		stats.damaged.connect(func(_a: float, _s: Node, _c: bool) -> void: _close())
	_build()
	_fill()


func _pause_at() -> float:
	return float(Database.animations.get("loot", {}).get("pause_at", 1.33))


func _process(_delta: float) -> void:
	if _closing:
		return
	if not is_instance_valid(bag):
		_close()
		return
	# Hold the kneel partway down while the window is open.
	var character := player.get_node("Model/Character") as CharacterModel
	if not _paused and character.current_animation() == "loot" and character.animation_position() >= _pause_at():
		character.set_speed(0.0)
		_paused = true
	# Sit over the body.
	var cam := player.get_viewport().get_camera_3d()
	if cam and not cam.is_position_behind(bag.global_position + Vector3.UP * 0.6):
		var at := cam.unproject_position(bag.global_position + Vector3.UP * 0.6)
		var size := player.get_viewport().get_visible_rect().size
		_panel.position = Vector2(clampf(at.x - _panel.size.x * 0.5, 8.0, size.x - _panel.size.x - 8.0),
			clampf(at.y - _panel.size.y, 8.0, size.y - _panel.size.y - 120.0))


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("target_clear") or event.is_action_pressed("inventory"):
		_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_mode"):
		_take_all()
		get_viewport().set_input_as_handled()
	elif Time.get_ticks_msec() - _started > 400 and _walks_off(event):
		_close()


## Walking off closes it: the movement stick or WASD (arrow keys move between entries).
func _walks_off(event: InputEvent) -> bool:
	if not (event.is_action_pressed("move_forward") or event.is_action_pressed("move_back") \
			or event.is_action_pressed("move_left") or event.is_action_pressed("move_right")):
		return false
	if event is InputEventKey:
		return (event as InputEventKey).physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D]
	return event is InputEventJoypadMotion


func _build() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.075, 0.1, 0.94)
	sb.border_color = CharacterWindow.ACCENT.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 6
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	var title := Label.new()
	title.text = bag.title
	title.add_theme_color_override("font_color", CharacterWindow.ACCENT)
	title.add_theme_font_size_override("font_size", 15)
	v.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	v.add_child(_rows)
	var buttons := HBoxContainer.new()
	var all := Button.new()
	all.text = "Take all (%s)" % GameSettings.binding_label("cycle_mode")
	all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all.pressed.connect(_take_all)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close)
	for b in [all, close]:
		b.add_theme_font_size_override("font_size", 13)
		buttons.add_child(b)
	v.add_child(buttons)


## One button per thing in the bag; the first gets focus (A / Space / Enter takes it).
func _fill() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var first: Button = null
	if bag.gold > 0:
		var b := _row({"icon": "coin", "icon_color": "#ffd76a", "name": "Gold"}, bag.gold, "%d gold" % bag.gold)
		b.pressed.connect(func() -> void:
			bag.take_gold(inventory)
			_refresh())
		first = b
	for i in bag.items.size():
		var entry: Array = bag.items[i]
		var d := Database.item(String(entry[0]))
		var label := String(d.get("name", entry[0])) + ((" x%d" % int(entry[1])) if int(entry[1]) > 1 else "")
		var b := _row(d, int(entry[1]), label)
		var index := i
		b.pressed.connect(func() -> void:
			bag.take_item(inventory, index)
			_refresh())
		if first == null:
			first = b
	if first:
		first.grab_focus.call_deferred()


func _row(item: Dictionary, count: int, text: String) -> Button:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 38)
	b.text = "        " + text
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", ItemIcon.rarity_color(item) if item.has("rarity") else Color(1, 0.9, 0.6))
	b.tooltip_text = String(item.get("description", ""))
	var icon := ItemIcon.new()
	icon.position = Vector2(4, 3)
	icon.size = Vector2(32, 32)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.show_item(item, count if count > 1 and not item.has("icon") else 0)
	b.add_child(icon)
	_rows.add_child(b)
	return b


func _refresh() -> void:
	if not is_instance_valid(bag) or bag.is_empty():
		_close()
	else:
		_fill()


func _take_all() -> void:
	if is_instance_valid(bag):
		bag.take_all(inventory)
	_refresh()


## Closes the window; the character finishes getting up.
func _close() -> void:
	if _closing:
		return
	_closing = true
	_panel.visible = false
	GameSettings.menu_open = false
	if is_instance_valid(bag):
		bag.open = false
		if bag.is_empty():
			bag.queue_free()
	var character := player.get_node("Model/Character") as CharacterModel
	if player.state == PlayerController.State.ACTION and character.current_animation() == "loot":
		# Get up (a little quicker than kneeling down).
		var speed := 1.4
		character.set_speed(speed)
		var left := maxf(character.get_animation_length("loot") - character.animation_position(), 0.0) / speed
		await get_tree().create_timer(minf(left, 1.6)).timeout
		# Done getting up (unless something else has started since, like an attack).
		if player.state == PlayerController.State.ACTION and character.current_animation() in ["loot", ""]:
			player.end_action()
	else:
		player.end_action() if player.state == PlayerController.State.ACTION else null
	queue_free()
