extends Node
## Player settings (autoload "GameSettings"): volumes, graphics and control bindings.
## Saved to user://settings.cfg and applied at startup. The Settings menu edits them.

signal bindings_changed
## The player switched between keyboard/mouse and controller (for button hints).
signal device_changed(gamepad: bool)

const PATH := "user://settings.cfg"

## Volume sliders: setting name -> audio bus.
const BUSES := {"master": &"Master", "music": &"Music", "effects": &"SFX", "footsteps": &"Footsteps", "ambience": &"Ambience"}
const DEFAULT_VOLUMES := {"master": 1.0, "music": 0.8, "effects": 1.0, "footsteps": 0.5, "ambience": 0.7}

## Pixel textures: label -> texels per 4 m tile (0 = smooth).
const PIXEL_OPTIONS := {"Off": 0.0, "Fine": 64.0, "Chunky": 32.0, "Retro": 16.0}
const DEFAULT_PIXEL := "Chunky"

## Actions shown in the controls menu, in order: [action, label].
const REBINDABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"], ["move_right", "Move right"],
	["camera_left", "Camera left"], ["camera_right", "Camera right"], ["camera_up", "Camera up"], ["camera_down", "Camera down"],
	["jump", "Jump / talk"], ["sprint", "Sprint"], ["walk", "Walk"], ["dodge", "Dodge"],
	["attack", "Attack (hold to charge)"], ["block", "Block"], ["cycle_mode", "Melee / ranged / magic"],
	["spell_prev", "Previous spell"], ["spell_next", "Next spell"], ["item_prev", "Quick item up"], ["item_next", "Quick item down"],
	["target_prev", "Previous target"], ["target_next", "Next target"], ["lock_on", "Lock on"], ["target_clear", "Clear target"],
	["camera_look", "Hold to look (mouse)"], ["zoom_in", "Zoom in"], ["zoom_out", "Zoom out"], ["menu", "Settings menu"],
]

var volumes := DEFAULT_VOLUMES.duplicate()
var pixel := DEFAULT_PIXEL
var camera_sensitivity := 1.0
var invert_camera_y := false
## True while a menu is open: gameplay ignores input.
var menu_open := false
var gamepad := false

var _defaults := {}  # action -> Array[InputEvent] from project settings


func _ready() -> void:
	for entry in REBINDABLE:
		_defaults[entry[0]] = InputMap.action_get_events(entry[0]).duplicate()
	load_settings()
	apply_all()


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4)
	var kbm := event is InputEventKey or event is InputEventMouseButton
	if (pad and not gamepad) or (kbm and gamepad):
		gamepad = pad
		device_changed.emit(gamepad)


# --- Apply ---------------------------------------------------------------------

func apply_all() -> void:
	for key: String in BUSES:
		set_volume(key, volumes.get(key, 1.0), false)
	set_pixel(pixel, false)


func set_volume(key: String, value: float, save := true) -> void:
	volumes[key] = clampf(value, 0.0, 1.0)
	var bus := AudioServer.get_bus_index(BUSES[key])
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volumes[key], 0.0001)))
		AudioServer.set_bus_mute(bus, volumes[key] <= 0.001)
	if save:
		save_settings()


func set_pixel(option: String, save := true) -> void:
	if not PIXEL_OPTIONS.has(option):
		option = DEFAULT_PIXEL
	pixel = option
	RenderingServer.global_shader_parameter_set("pixel_texels", PIXEL_OPTIONS[option])
	if save:
		save_settings()


# --- Bindings -------------------------------------------------------------------

static func is_gamepad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


## The action's bindings for one kind of device.
func events_for(action: String, for_gamepad: bool) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for e in InputMap.action_get_events(action):
		if is_gamepad_event(e) == for_gamepad:
			out.append(e)
	return out


## Replaces the action's binding for that kind of device with `event`.
func rebind(action: String, event: InputEvent) -> void:
	var pad := is_gamepad_event(event)
	for e in events_for(action, pad):
		InputMap.action_erase_event(action, e)
	var clean := _clean(event)
	if clean:
		InputMap.action_add_event(action, clean)
	save_settings()
	bindings_changed.emit()


func reset_bindings(for_gamepad: bool) -> void:
	for action: String in _defaults:
		for e in events_for(action, for_gamepad):
			InputMap.action_erase_event(action, e)
		for e: InputEvent in _defaults[action]:
			if is_gamepad_event(e) == for_gamepad:
				InputMap.action_add_event(action, e)
	save_settings()
	bindings_changed.emit()


## A copy of an input event with only what matters for a binding.
func _clean(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var k := InputEventKey.new()
		k.physical_keycode = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return k
	if event is InputEventMouseButton:
		var m := InputEventMouseButton.new()
		m.button_index = event.button_index
		return m
	if event is InputEventJoypadButton:
		var b := InputEventJoypadButton.new()
		b.device = -1
		b.button_index = event.button_index
		return b
	if event is InputEventJoypadMotion:
		var a := InputEventJoypadMotion.new()
		a.device = -1
		a.axis = event.axis
		a.axis_value = 1.0 if event.axis_value > 0.0 else -1.0
		return a
	return null


## Short name of the current binding for an action on the device in use, e.g. "RT" or "LMB".
func binding_label(action: String, for_gamepad := gamepad) -> String:
	var list := events_for(action, for_gamepad)
	return event_name(list[0]) if not list.is_empty() else "—"


const PAD_BUTTONS := {
	0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 5: "Guide", 6: "Start", 7: "L3", 8: "R3",
	9: "LB", 10: "RB", 11: "D-pad Up", 12: "D-pad Down", 13: "D-pad Left", 14: "D-pad Right",
}
const MOUSE_BUTTONS := {1: "LMB", 2: "RMB", 3: "Middle mouse", 4: "Wheel up", 5: "Wheel down", 8: "Mouse 4", 9: "Mouse 5"}


static func event_name(e: InputEvent) -> String:
	if e is InputEventKey:
		var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		return OS.get_keycode_string(code)
	if e is InputEventMouseButton:
		return MOUSE_BUTTONS.get(e.button_index, "Mouse %d" % e.button_index)
	if e is InputEventJoypadButton:
		return PAD_BUTTONS.get(e.button_index, "Button %d" % e.button_index)
	if e is InputEventJoypadMotion:
		var plus: bool = e.axis_value > 0.0
		match e.axis:
			0: return "Left stick " + ("right" if plus else "left")
			1: return "Left stick " + ("down" if plus else "up")
			2: return "Right stick " + ("right" if plus else "left")
			3: return "Right stick " + ("down" if plus else "up")
			4: return "LT"
			5: return "RT"
		return "Axis %d" % e.axis
	return "?"


# --- Save / load ----------------------------------------------------------------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key: String in volumes:
		cfg.set_value("audio", key, volumes[key])
	cfg.set_value("graphics", "pixel", pixel)
	cfg.set_value("controls", "camera_sensitivity", camera_sensitivity)
	cfg.set_value("controls", "invert_camera_y", invert_camera_y)
	for entry in REBINDABLE:
		var list := []
		for e in InputMap.action_get_events(entry[0]):
			var d := _to_dict(e)
			if not d.is_empty():
				list.append(d)
		cfg.set_value("bindings", entry[0], list)
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key: String in DEFAULT_VOLUMES:
		volumes[key] = float(cfg.get_value("audio", key, DEFAULT_VOLUMES[key]))
	pixel = String(cfg.get_value("graphics", "pixel", DEFAULT_PIXEL))
	camera_sensitivity = float(cfg.get_value("controls", "camera_sensitivity", 1.0))
	invert_camera_y = bool(cfg.get_value("controls", "invert_camera_y", false))
	if cfg.has_section("bindings"):
		for action in cfg.get_section_keys("bindings"):
			if not InputMap.has_action(action):
				continue
			InputMap.action_erase_events(action)
			for d in cfg.get_value("bindings", action, []):
				var e := _from_dict(d)
				if e:
					InputMap.action_add_event(action, e)


func _to_dict(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		return {"type": "key", "code": e.physical_keycode if e.physical_keycode != 0 else e.keycode}
	if e is InputEventMouseButton:
		return {"type": "mouse", "button": e.button_index}
	if e is InputEventJoypadButton:
		return {"type": "pad_button", "button": e.button_index}
	if e is InputEventJoypadMotion:
		return {"type": "pad_axis", "axis": e.axis, "value": signf(e.axis_value)}
	return {}


func _from_dict(d: Dictionary) -> InputEvent:
	match d.get("type", ""):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.code)
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(d.button)
			return m
		"pad_button":
			var b := InputEventJoypadButton.new()
			b.device = -1
			b.button_index = int(d.button)
			return b
		"pad_axis":
			var a := InputEventJoypadMotion.new()
			a.device = -1
			a.axis = int(d.axis)
			a.axis_value = float(d.value)
			return a
	return null
