extends Node
## Player settings (autoload "GameSettings"): volumes, graphics and control bindings.
## Saved to user://settings.cfg and applied at startup. The Settings menu edits them.

signal bindings_changed
## Grass or other graphics settings that need the world rebuilt changed.
signal graphics_changed
## HUD options (portraits) changed.
signal hud_changed
## The player switched between keyboard/mouse and controller (for button hints).
signal device_changed(gamepad: bool)

const PATH := "user://settings.cfg"

## Volume sliders: setting name -> audio bus.
const BUSES := {"master": &"Master", "music": &"Music", "effects": &"SFX", "footsteps": &"Footsteps", "ambience": &"Ambience"}
const DEFAULT_VOLUMES := {"master": 1.0, "music": 0.8, "effects": 1.0, "footsteps": 0.5, "ambience": 0.7}

## Pixel textures: label -> texels per 4 m tile (0 = smooth).
const PIXEL_OPTIONS := {"Off": 0.0, "Fine": 64.0, "Chunky": 32.0, "Retro": 16.0}
const DEFAULT_PIXEL := "Chunky"
## Grass: label -> share of each region's grass density.
const GRASS_OPTIONS := {"Off": 0.0, "Low": 0.4, "Medium": 0.7, "High": 1.0}
const DEFAULT_GRASS := "High"
## View distance: label -> share of how far props and grass are drawn (world.json performance).
const VIEW_OPTIONS := {"Near": 0.6, "Medium": 0.8, "Far": 1.0}
const DEFAULT_VIEW := "Far"
## Shadows: label -> [shadow map size (0 = no shadows), share of the level's shadow distance].
const SHADOW_OPTIONS := {"Off": [0, 0.0], "Low": [2048, 0.5], "Medium": [4096, 0.75], "High": [4096, 1.0]}
const DEFAULT_SHADOWS := "High"
## Frame limit: label -> frames per second (0 = no limit).
const FPS_OPTIONS := {"No limit": 0, "30": 30, "60": 60, "90": 90, "120": 120, "144": 144}
const DEFAULT_FPS := "No limit"

## Actions shown in the controls menu, in order: [action, label].
const REBINDABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"], ["move_right", "Move right"],
	["camera_left", "Camera left"], ["camera_right", "Camera right"], ["camera_up", "Camera up"], ["camera_down", "Camera down"],
	["jump", "Jump"], ["interact", "Interact (talk, loot, open)"], ["sprint", "Sprint"], ["walk", "Walk"], ["dodge", "Dodge"],
	["attack", "Attack (hold to charge)"], ["block", "Block"], ["cycle_mode", "Take all (loot)"],
	["hotbar_1", "Hotbar 1"], ["hotbar_2", "Hotbar 2"], ["hotbar_3", "Hotbar 3"], ["hotbar_4", "Hotbar 4"],
	["hotbar_5", "Hotbar 5"], ["hotbar_6", "Hotbar 6"], ["hotbar_7", "Hotbar 7"], ["hotbar_8", "Hotbar 8"],
	["hotbar_9", "Hotbar 9"], ["hotbar_10", "Hotbar 10"], ["ability_wheel", "Ability wheel (hold)"],
	["inventory", "Character / backpack"], ["spellbook", "Spellbook"], ["skills", "Skill trees"], ["quest_log", "Quest log"], ["map", "Region map"], ["danger_mode", "Danger mode (attack NPCs)"], ["toggle_weapon", "Draw / put away weapon"], ["chat", "Chat"],
	["target_next", "Target nearest / clear (Shift: next target)"], ["target_prev", "Next target (controller)"], ["lock_on", "Lock on (camera follows target)"], ["target_clear", "Clear target"],
	["camera_look", "Hold to look (mouse)"], ["zoom_in", "Zoom in"], ["zoom_out", "Zoom out"], ["menu", "Settings menu"],
]

## The controller ability wheel is up (its right-stick choice mustn't turn the camera).
var wheel_open := false
var volumes := DEFAULT_VOLUMES.duplicate()
var pixel := DEFAULT_PIXEL
var grass := DEFAULT_GRASS
var god_rays := true
## Character portraits beside the health bars (player and party).
var portraits := true
## The HUD clock: 24-hour (14:05) or 12-hour (2:05 PM).
var clock_24h := true
## Screen-space ambient occlusion: soft contact shadows in corners and under things.
var ssao := true
## Trees, cliffs and characters reflected in water (costs a little on slower PCs).
var water_reflections := true
var view_distance := DEFAULT_VIEW
var shadows := DEFAULT_SHADOWS
## The 3D picture is drawn at this share of the window's size, then stretched (0.5–1).
var render_scale := 1.0
var fps_limit := DEFAULT_FPS
var vsync := true
## Retro look (Settings → Retro, RetroFilter): one intensity and which parts are on.
var retro_on := true
var retro_intensity := 0.5
var retro_pixelate := true
var retro_colors := true
var retro_dither := true
var retro_scanlines := false
var retro_wobble := false
var retro_fog := true
var retro_fov := true
var retro_font := true
const RETRO_KEYS := ["retro_on", "retro_intensity", "retro_pixelate", "retro_colors", "retro_dither", "retro_scanlines", "retro_wobble", "retro_fog", "retro_fov", "retro_font"]
const PIXEL_FONT := "res://assets/fonts/PixelifySans.ttf"
var _retro: RetroFilter
## Camera shake on hits: 0 = off, 1 = full.
var screen_shake := 1.0
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
	set_water_reflections(water_reflections, false)
	apply_display()
	_apply_retro()


## The pixel font for every menu and the HUD: swapped into Godot's default theme (a theme
## on the root window doesn't reach controls under CanvasLayers), then every control is
## told its theme changed.
var _plain_font: Font
var _pixel_font: Font


func _apply_font() -> void:
	var theme := ThemeDB.get_default_theme()
	if theme == null:
		return
	if _plain_font == null:
		_plain_font = theme.default_font if theme.default_font else ThemeDB.fallback_font
	var want: Font = _plain_font
	if retro_on and retro_font and ResourceLoader.exists(PIXEL_FONT):
		if _pixel_font == null:
			var f := (load(PIXEL_FONT) as FontFile).duplicate() as FontFile
			f.fallbacks = [_plain_font]  # symbols the pixel font lacks
			_pixel_font = f
		want = _pixel_font
	if theme.default_font == want:
		return
	theme.default_font = want
	get_tree().root.propagate_notification(Control.NOTIFICATION_THEME_CHANGED)


func set_retro(key: String, value: Variant) -> void:
	set(key, value)
	save_settings()
	_apply_retro()


## Retro fog on (the regions' retro_fog_start / end; AtmosphereManager reads this).
func retro_fog_on() -> bool:
	return retro_on and retro_fog and retro_intensity > 0.0


## The game camera's field of view × this (narrower, like old consoles).
func fov_scale() -> float:
	return lerpf(1.0, 0.78, retro_intensity) if retro_on and retro_fov else 1.0


func _apply_retro() -> void:
	if not is_inside_tree():
		return
	_apply_font()
	if _retro == null or not is_instance_valid(_retro):
		_retro = RetroFilter.new()
		_retro.name = "RetroFilter"
		get_tree().root.add_child.call_deferred(_retro)
		return  # applies itself when it enters the tree
	_retro.apply()


## Render scale, frame limit and vsync (the window's own settings).
func apply_display() -> void:
	var root := get_tree().root if is_inside_tree() else null
	if root:
		root.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)
	Engine.max_fps = int(FPS_OPTIONS.get(fps_limit, 0))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func set_render_scale(value: float) -> void:
	render_scale = clampf(value, 0.5, 1.0)
	apply_display()
	save_settings()


func set_fps_limit(option: String) -> void:
	fps_limit = option if FPS_OPTIONS.has(option) else DEFAULT_FPS
	apply_display()
	save_settings()


func set_vsync(on: bool) -> void:
	vsync = on
	apply_display()
	save_settings()


func set_view_distance(option: String) -> void:
	view_distance = option if VIEW_OPTIONS.has(option) else DEFAULT_VIEW
	save_settings()
	graphics_changed.emit()


func view_distance_scale() -> float:
	return float(VIEW_OPTIONS.get(view_distance, 1.0))


func set_shadows(option: String) -> void:
	shadows = option if SHADOW_OPTIONS.has(option) else DEFAULT_SHADOWS
	save_settings()
	graphics_changed.emit()


func set_volume(key: String, value: float, save := true) -> void:
	volumes[key] = clampf(value, 0.0, 1.0)
	var bus := AudioServer.get_bus_index(BUSES[key])
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volumes[key], 0.0001)))
		AudioServer.set_bus_mute(bus, volumes[key] <= 0.001)
	if save:
		save_settings()


func set_grass(option: String) -> void:
	grass = option if GRASS_OPTIONS.has(option) else DEFAULT_GRASS
	save_settings()
	graphics_changed.emit()


func grass_multiplier() -> float:
	return GRASS_OPTIONS.get(grass, 1.0)


func set_screen_shake(value: float) -> void:
	screen_shake = clampf(value, 0.0, 1.0)
	save_settings()


func set_ssao(on: bool) -> void:
	ssao = on
	save_settings()
	graphics_changed.emit()


func set_water_reflections(on: bool, save := true) -> void:
	water_reflections = on
	RenderingServer.global_shader_parameter_set("water_reflections", 1.0 if on else 0.0)
	if save:
		save_settings()


func set_portraits(on: bool) -> void:
	portraits = on
	hud_changed.emit()
	save_settings()


func set_clock_24h(on: bool) -> void:
	clock_24h = on
	save_settings()


func set_god_rays(on: bool) -> void:
	god_rays = on
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


## The key/button shown in "E  Talk" prompts.
func interact_label() -> String:
	var keys := events_for("interact", gamepad)
	return event_name(keys[0]) if not keys.is_empty() else "E"


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
	cfg.set_value("graphics", "grass", grass)
	cfg.set_value("graphics", "god_rays", god_rays)
	cfg.set_value("interface", "portraits", portraits)
	cfg.set_value("interface", "clock_24h", clock_24h)
	cfg.set_value("graphics", "screen_shake", screen_shake)
	cfg.set_value("graphics", "water_reflections", water_reflections)
	cfg.set_value("graphics", "ssao", ssao)
	cfg.set_value("graphics", "view_distance", view_distance)
	cfg.set_value("graphics", "shadows", shadows)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "fps_limit", fps_limit)
	cfg.set_value("graphics", "vsync", vsync)
	for key in RETRO_KEYS:
		cfg.set_value("retro", key, get(key))
	cfg.set_value("controls", "camera_sensitivity", camera_sensitivity)
	cfg.set_value("controls", "invert_camera_y", invert_camera_y)
	for entry in REBINDABLE:
		var list := []
		for e in InputMap.action_get_events(entry[0]):
			var d := _to_dict(e)
			if not d.is_empty():
				list.append(d)
		cfg.set_value("bindings", entry[0], list)
	cfg.set_value("controls", "bindings_version", 4)
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key: String in DEFAULT_VOLUMES:
		volumes[key] = float(cfg.get_value("audio", key, DEFAULT_VOLUMES[key]))
	pixel = String(cfg.get_value("graphics", "pixel", DEFAULT_PIXEL))
	grass = String(cfg.get_value("graphics", "grass", DEFAULT_GRASS))
	god_rays = bool(cfg.get_value("graphics", "god_rays", true))
	portraits = bool(cfg.get_value("interface", "portraits", true))
	clock_24h = bool(cfg.get_value("interface", "clock_24h", true))
	screen_shake = float(cfg.get_value("graphics", "screen_shake", 1.0))
	water_reflections = bool(cfg.get_value("graphics", "water_reflections", true))
	ssao = bool(cfg.get_value("graphics", "ssao", true))
	view_distance = String(cfg.get_value("graphics", "view_distance", DEFAULT_VIEW))
	shadows = String(cfg.get_value("graphics", "shadows", DEFAULT_SHADOWS))
	render_scale = clampf(float(cfg.get_value("graphics", "render_scale", 1.0)), 0.5, 1.0)
	fps_limit = String(cfg.get_value("graphics", "fps_limit", DEFAULT_FPS))
	vsync = bool(cfg.get_value("graphics", "vsync", true))
	for key in RETRO_KEYS:
		set(key, cfg.get_value("retro", key, get(key)))
	camera_sensitivity = float(cfg.get_value("controls", "camera_sensitivity", 1.0))
	invert_camera_y = bool(cfg.get_value("controls", "invert_camera_y", false))
	# Bindings saved before a default changed keep the new default for those actions.
	var version := int(cfg.get_value("controls", "bindings_version", 1))
	if cfg.has_section("bindings"):
		for action in cfg.get_section_keys("bindings"):
			if not InputMap.has_action(action):
				continue
			if version < 3 and action in ["block", "camera_look", "lock_on", "interact"]:
				continue  # defaults changed: block Q, look right mouse, lock-on middle mouse, interact E
			if version < 4 and action in ["target_next", "target_prev", "target_clear", "lock_on"]:
				continue  # targeting defaults restored: Tab, Shift+Tab, Esc, middle mouse
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
