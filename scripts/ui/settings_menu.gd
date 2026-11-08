class_name SettingsMenu
extends CanvasLayer
## The gear button (top right) and the Settings window: sound volumes, graphics, and
## rebinding for keyboard/mouse and for controller. Also opens with the menu button
## (Start) or Esc when nothing is targeted. Everything is saved by GameSettings.

const PANEL_COLOR := Color(0.09, 0.08, 0.12, 0.94)
const ACCENT := Color(1.0, 0.85, 0.45)

signal closed

## Set by the HUD so Esc clears a target before it opens the menu.
var targeting: Node = null
## The title screen opens the window itself: no gear button, no Esc/Start shortcut.
var title_screen := false

var _window: PanelContainer
var _tabs: TabContainer
var _gear: Button
var _rows := {}  # "kbm"/"pad" -> Array of [action, Button]
var _waiting: Array = []  # [action, gamepad, Button] while waiting for a key/button


func _ready() -> void:
	layer = 20
	if not title_screen:
		_build_gear()
	_build_window()
	_window.visible = false
	GameSettings.bindings_changed.connect(_refresh_bindings)


func is_open() -> bool:
	return _window.visible


func open() -> void:
	_window.visible = true
	GameSettings.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_bindings()
	if GameSettings.gamepad:
		_tabs.get_tab_bar().grab_focus()


func close() -> void:
	_cancel_wait()
	_window.visible = false
	GameSettings.menu_open = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if title_screen and not _window.visible:
		return
	if _window.visible:
		if event.is_action_pressed("menu") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE):
			close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu"):
		open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("target_clear"):
		# Esc clears the target first (Targeting handles that); with nothing targeted it opens Settings.
		if targeting and (targeting.get("target") != null or targeting.get("locked")):
			return
		open()
		get_viewport().set_input_as_handled()


# --- Rebinding capture ---------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _waiting.is_empty():
		return
	var want_pad: bool = _waiting[1]
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_cancel_wait()
		get_viewport().set_input_as_handled()
		return
	var ok := false
	if want_pad:
		ok = (event is InputEventJoypadButton and event.pressed) \
			or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.6)
	else:
		ok = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed)
	if not ok:
		return
	get_viewport().set_input_as_handled()
	var action: String = _waiting[0]
	_waiting = []
	GameSettings.rebind(action, event)


func _start_wait(action: String, gamepad: bool, button: Button) -> void:
	_cancel_wait()
	_waiting = [action, gamepad, button]
	button.text = "Press a button…" if gamepad else "Press a key…"


func _cancel_wait() -> void:
	if _waiting.is_empty():
		return
	_waiting = []
	_refresh_bindings()


# --- Building ------------------------------------------------------------------

func _build_gear() -> void:
	_gear = Button.new()
	_gear.flat = true
	_gear.custom_minimum_size = Vector2(44, 44)
	_gear.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_gear.position = Vector2(-60, 16)
	_gear.tooltip_text = "Settings"
	_gear.focus_mode = Control.FOCUS_NONE
	var icon := GearIcon.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear.add_child(icon)
	_gear.pressed.connect(func() -> void: close() if is_open() else open())
	add_child(_gear)


func _build_window() -> void:
	_window = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.border_color = ACCENT.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	_window.add_theme_stylebox_override("panel", sb)
	_window.set_anchors_preset(Control.PRESET_CENTER)
	_window.custom_minimum_size = Vector2(640, 520)
	_window.position = Vector2(-320, -260)
	add_child(_window)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_window.add_child(v)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if not title_screen and GameSession.active():
		var save := Button.new()
		save.text = "Save game"
		save.pressed.connect(func() -> void:
			GameSession.save_game()
			save.text = "Saved ✓"
			get_tree().create_timer(1.5).timeout.connect(func() -> void: save.text = "Save game"))
		head.add_child(save)
		var leave := Button.new()
		leave.text = "Quit to title"
		leave.pressed.connect(func() -> void:
			close()
			GameSession.quit_to_title())
		head.add_child(leave)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	head.add_child(close_button)
	v.add_child(head)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	if not title_screen:
		_tabs.add_child(_help_tab())
	_tabs.add_child(_sound_tab())
	_tabs.add_child(_graphics_tab())
	_tabs.add_child(_controls_tab(false))
	_tabs.add_child(_controls_tab(true))


func _page(page_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = page_name
	page.add_theme_constant_override("separation", 8)
	return page


func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(220, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


## How to play: the controls in use right now (they follow rebinding and the device).
func _help_tab() -> Control:
	var page := _page("How to play")
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(text)
	var fill := func() -> void:
		var g := GameSettings
		var k := func(action: String) -> String: return "[color=#ffd76a]%s[/color]" % g.binding_label(action)
		text.text = "\n".join([
			"[b]Moving[/b]",
			"%s/%s/%s/%s move · %s walk · %s sprint · %s jump (and talk) · %s dodge" % [k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right"), k.call("walk"), k.call("sprint"), k.call("jump"), k.call("dodge")],
			"%s hold to look around · %s / %s zoom" % [k.call("camera_look"), k.call("zoom_in"), k.call("zoom_out")],
			"",
			"[b]Fighting[/b]",
			"%s attack: tap to swing (tap again to combo), hold for a heavy blow or to draw a bow" % k.call("attack"),
			"%s block with melee weapons (start just before a hit to parry) · aim with ranged weapons" % k.call("block"),
			"%s swap primary / secondary weapon · %s / %s pick one" % [k.call("cycle_mode"), k.call("hotbar_1"), k.call("hotbar_2")],
			"%s…%s use hotbar boxes 3–10 (spells, potions) · %s ability wheel (controller)" % [k.call("hotbar_3"), k.call("hotbar_10"), k.call("ability_wheel")],
			"%s target and lock on (again to clear) · %s cycle targets · %s lock on / off" % [k.call("target_next"), k.call("target_prev"), k.call("lock_on")],
			"",
			"[b]Windows[/b]",
			"%s character and backpack · %s spellbook · %s chat · %s / gear: this menu" % [k.call("inventory"), k.call("spellbook"), k.call("chat"), k.call("menu")],
		])
	fill.call()
	GameSettings.bindings_changed.connect(fill)
	GameSettings.device_changed.connect(func(_g: bool) -> void: fill.call())
	return page


func _sound_tab() -> Control:
	var page := _page("Sound")
	var names := {"master": "Master", "music": "Music", "effects": "Effects", "footsteps": "Footsteps", "ambience": "Ambience"}
	for key: String in names:
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = GameSettings.volumes.get(key, 1.0)
		var percent := Label.new()
		percent.custom_minimum_size = Vector2(48, 0)
		percent.text = "%d%%" % int(slider.value * 100)
		slider.value_changed.connect(func(value: float) -> void:
			GameSettings.set_volume(key, value)
			percent.text = "%d%%" % int(value * 100))
		var row := _row(names[key], slider)
		row.add_child(percent)
		page.add_child(row)
	return page


func _graphics_tab() -> Control:
	var page := _page("Graphics")
	var pixel := OptionButton.new()
	var options := GameSettings.PIXEL_OPTIONS.keys()
	for i in options.size():
		pixel.add_item(options[i])
		if options[i] == GameSettings.pixel:
			pixel.select(i)
	pixel.item_selected.connect(func(i: int) -> void: GameSettings.set_pixel(options[i]))
	page.add_child(_row("Pixel textures", pixel))
	var grass := OptionButton.new()
	var grass_options := GameSettings.GRASS_OPTIONS.keys()
	for i in grass_options.size():
		grass.add_item(grass_options[i])
		if grass_options[i] == GameSettings.grass:
			grass.select(i)
	grass.item_selected.connect(func(i: int) -> void: GameSettings.set_grass(grass_options[i]))
	page.add_child(_row("Grass", grass))
	var rays := CheckBox.new()
	rays.text = "God rays (light shafts through the air)"
	rays.button_pressed = GameSettings.god_rays
	rays.toggled.connect(func(on: bool) -> void: GameSettings.set_god_rays(on))
	page.add_child(rays)
	var ao := CheckBox.new()
	ao.text = "Ambient occlusion (soft shadows in corners and under things)"
	ao.button_pressed = GameSettings.ssao
	ao.toggled.connect(func(on: bool) -> void: GameSettings.set_ssao(on))
	page.add_child(ao)
	var reflect := CheckBox.new()
	reflect.text = "Water reflections (trees and cliffs mirrored in water)"
	reflect.button_pressed = GameSettings.water_reflections
	reflect.toggled.connect(func(on: bool) -> void: GameSettings.set_water_reflections(on))
	page.add_child(reflect)
	var shake := HSlider.new()
	shake.min_value = 0.0
	shake.max_value = 1.0
	shake.step = 0.05
	shake.value = GameSettings.screen_shake
	shake.value_changed.connect(func(v: float) -> void: GameSettings.set_screen_shake(v))
	page.add_child(_row("Screen shake", shake))
	var note := Label.new()
	note.text = "Off = smooth textures. Fine, Chunky and Retro show textures as bigger and bigger square pixels."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.modulate = Color(1, 1, 1, 0.7)
	page.add_child(note)
	return page


func _controls_tab(gamepad: bool) -> Control:
	var page := _page("Controller" if gamepad else "Keyboard & Mouse")
	var top := HBoxContainer.new()
	var hint := Label.new()
	hint.text = "Click an action, then press the new %s. Esc cancels." % ("button" if gamepad else "key or mouse button")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.modulate = Color(1, 1, 1, 0.7)
	top.add_child(hint)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(func() -> void: GameSettings.reset_bindings(gamepad))
	top.add_child(reset)
	page.add_child(top)

	var sens := HSlider.new()
	sens.min_value = 0.3
	sens.max_value = 2.5
	sens.step = 0.05
	sens.value = GameSettings.camera_sensitivity
	sens.value_changed.connect(func(value: float) -> void:
		GameSettings.camera_sensitivity = value
		GameSettings.save_settings())
	page.add_child(_row("Camera speed", sens))
	var invert := CheckBox.new()
	invert.text = "Invert camera up/down"
	invert.button_pressed = GameSettings.invert_camera_y
	invert.toggled.connect(func(on: bool) -> void:
		GameSettings.invert_camera_y = on
		GameSettings.save_settings())
	page.add_child(invert)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	page.add_child(scroll)
	var rows := []
	for entry in GameSettings.REBINDABLE:
		var action: String = entry[0]
		# Mouse-only actions have nothing to bind on a controller.
		if gamepad and action in ["camera_look", "zoom_in", "zoom_out", "walk"]:
			continue
		if not gamepad and action.begins_with("camera_") and action != "camera_look":
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(200, 0)
		button.pressed.connect(func() -> void: _start_wait(action, gamepad, button))
		list.add_child(_row(entry[1], button))
		rows.append([action, button])
	_rows["pad" if gamepad else "kbm"] = rows
	return page


func _refresh_bindings() -> void:
	for key: String in _rows:
		var pad := key == "pad"
		for row: Array in _rows[key]:
			var names := []
			for e in GameSettings.events_for(row[0], pad):
				names.append(GameSettings.event_name(e))
			(row[1] as Button).text = " / ".join(names) if not names.is_empty() else "(none)"


## A simple drawn gear for the settings button.
class GearIcon:
	extends Control

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.3
		var col := Color(0.95, 0.9, 0.8, 0.95)
		for i in 8:
			var a := TAU * i / 8.0
			var dir := Vector2(cos(a), sin(a))
			var side := Vector2(-dir.y, dir.x)
			var p := PackedVector2Array([
				c + dir * r * 0.9 + side * r * 0.28, c + dir * r * 1.4 + side * r * 0.2,
				c + dir * r * 1.4 - side * r * 0.2, c + dir * r * 0.9 - side * r * 0.28])
			draw_colored_polygon(p, col)
		draw_circle(c, r, col)
		draw_circle(c, r * 0.42, Color(0.1, 0.1, 0.12, 0.95))
