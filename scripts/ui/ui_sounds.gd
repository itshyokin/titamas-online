extends Node
## Menu sounds for every menu, without each one wiring them (autoload "UiSounds"):
## buttons click (toggles latch), sliders tick, tab bars turn a page, and pointing at a
## button gives a soft tick while a menu is open (not over the hotbar in play). Windows
## call `UiSounds.play("open" / "close" / "tab" / "back" / "error")` themselves.
## A control with meta "ui_sound" = a sound name plays that on press instead; "" = silent.
## Sounds and volume: player.json "ui_sounds" (Database → Player → Menu sounds);
## made by tools/audio/make_menu_sounds.py.

const DEFAULTS := {
	"hover": "res://assets/audio/ui/ui_hover.ogg",
	"click": "res://assets/audio/ui/ui_click.ogg",
	"toggle": "res://assets/audio/ui/ui_toggle.ogg",
	"slider": "res://assets/audio/ui/ui_slider.ogg",
	"tab": "res://assets/audio/ui/ui_tab.ogg",
	"open": "res://assets/audio/ui/ui_open.ogg",
	"close": "res://assets/audio/ui/ui_close.ogg",
	"back": "res://assets/audio/ui/ui_back.ogg",
	"error": "res://assets/audio/ui/ui_error.ogg",
}

var _players: Array[AudioStreamPlayer] = []
var _streams := {}
var _last := {}  # sound -> msec last played (no machine-gun hovers)
var _pointer := true  # last input came from the mouse (focus moves by keys/pad tick too)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)
	get_tree().node_added.connect(_on_node_added)


func _settings() -> Dictionary:
	var db := get_tree().root.get_node_or_null("Database")
	var p = db.get("player") if db else null
	var d = (p as Dictionary).get("ui_sounds", {}) if p is Dictionary else {}
	return d if d is Dictionary else {}


## Plays a menu sound by name (see DEFAULTS).
func play(sound: String) -> void:
	var cfg := _settings()
	if not bool(cfg.get("enabled", true)) or sound == "":
		return
	var now := Time.get_ticks_msec()
	var gap := 40 if sound in ["hover", "slider"] else 25
	if now - int(_last.get(sound, -1000)) < gap:
		return
	_last[sound] = now
	var path := String(cfg.get(sound, DEFAULTS.get(sound, "")))
	if path == "" or not ResourceLoader.exists(path):
		return
	if not _streams.has(path):
		_streams[path] = load(path)
	var player := _players[0]
	for p in _players:
		if not p.playing:
			player = p
			break
	player.stream = _streams[path]
	player.volume_db = float(cfg.get("volume_db", -4.0)) + float(cfg.get(sound + "_db", 0.0))
	player.pitch_scale = randf_range(0.97, 1.03)
	player.play()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_pointer = true
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_pointer = false


## Pointing at things only ticks in menus (the Codex, the title screen, windows), not over
## the hotbar while playing.
func _menu_up() -> bool:
	var gs := get_tree().root.get_node_or_null("GameSettings")
	if gs and bool(gs.get("menu_open")):
		return true
	return get_tree().get_first_node_in_group("player") == null


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var b := node as BaseButton
		b.mouse_entered.connect(func() -> void:
			if not b.disabled and _menu_up() and _sound_of(b, "hover") != "":
				play("hover"))
		b.focus_entered.connect(func() -> void:
			if not _pointer and _menu_up() and _sound_of(b, "hover") != "":
				play("hover"))
		b.pressed.connect(func() -> void:
			play(_sound_of(b, "toggle" if b.toggle_mode else "click")))
		if b is OptionButton:
			(b as OptionButton).item_selected.connect(func(_i: int) -> void: play("click"))
	elif node is Range and node is Slider:
		(node as Slider).value_changed.connect(func(_v: float) -> void:
			if (node as Slider).is_visible_in_tree():
				play("slider"))
	elif node is TabContainer:
		(node as TabContainer).tab_changed.connect(func(_t: int) -> void: play("tab"))
	elif node is TabBar and not (node.get_parent() is TabContainer):
		(node as TabBar).tab_changed.connect(func(_t: int) -> void: play("tab"))
	elif node is ItemList:
		(node as ItemList).item_selected.connect(func(_i: int) -> void: play("click"))


## The sound a control asked for (meta "ui_sound"), else the usual one.
func _sound_of(c: Control, usual: String) -> String:
	if c.has_meta("ui_sound"):
		var s := String(c.get_meta("ui_sound"))
		return "" if s == "" else (usual if usual == "hover" else s)
	return usual
