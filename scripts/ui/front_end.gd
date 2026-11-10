class_name FrontEnd
extends Node3D
## The title screen, character select (Load Game), character creator and class select.
## One scene with a small 3D stage (a stone dais in a glade at sunset): the character
## stands on it and the camera moves between pages. Main scene of the game.
##
## Creator choices come from data/appearance.json, classes from data/classes.json and
## the credits from data/credits.json. Saves are handled by the GameSession autoload.

const PANEL_COLOR := Color(0.08, 0.07, 0.11, 0.86)
const ACCENT := Color(1.0, 0.82, 0.42)
const DIM := Color(0.75, 0.72, 0.68)
const DAIS_TOP := 0.22
const NAME_MAX := 16

## Camera shots: [position, look-at point]. Heights get the character's height added.
## The camera looks along +Z at the character, so +X is the left of the screen.
const SHOTS := {
	"title": [Vector3(2.0, 1.5, -5.4), Vector3(1.25, 1.2, 0.0)],
	"full": [Vector3(0.0, 1.05, -3.6), Vector3(0.0, 0.98, 0.0)],
	"face": [Vector3(0.0, 1.66, -1.45), Vector3(0.0, 1.56, 0.0)],
	"left": [Vector3(-0.8, 1.05, -3.7), Vector3(-0.8, 0.98, 0.0)],
	"credits": [Vector3(0.0, 2.6, -7.5), Vector3(0.0, 2.2, 0.0)],
}

var _ui: Control
var _pages := {}
var _page := ""
var _camera: Camera3D
var _shot := "title"
var _turntable: Node3D
var _model: CharacterModel
var _settings: SettingsMenu
var _loading: Control

# Creator state.
var _look := {}
var _pronouns := "he"
var _pronouns_touched := false
var _class_id := "fighter"
var _name_edit: LineEdit
var _name_error: Label
var _swatches := {}  # look key -> [[colour string, Button]]
var _steppers := {}  # look key -> [list name, value Label]
var _choices := {}  # key -> [[id, Button]]
var _class_buttons := []  # [[id, Button]]
var _class_info: RichTextLabel
var _species_buttons := []  # [[id, Button]]
var _species_info: RichTextLabel
var _points := {}  # attribute id -> points spent at creation
var _attr_rows := {}  # attribute id -> [value Label, minus Button, plus Button]
var _points_label: Label
var _derived: Label

# Load page state.
var _saves: Array[Dictionary] = []
var _save_list: VBoxContainer
var _selected_save := -1
var _play_button: Button
var _delete_button: Button
var _confirm_delete: ConfirmationDialog
var _load_game_button: Button
var _host_button: Button
var _join_button: Button
var _join_box: HBoxContainer
var _join_address: LineEdit
var _net_status: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.menu_open = false
	_build_stage()
	_build_ui()
	_saves = GameSession.list_saves()
	if not _saves.is_empty():
		_show_character(_saves[0])  # the last character played stands on the dais
	else:
		_model.visible = false
	_show("title")
	_camera.global_transform = _shot_transform("title")
	Net.connected_to_host.connect(_on_net_connected)
	Net.connection_failed.connect(_on_net_failed)
	if GameSession.last_message != "":
		_show("load")
		_net_status.text = GameSession.last_message
		GameSession.last_message = ""


func _process(delta: float) -> void:
	# Ease the camera toward the page's shot.
	var want := _shot_transform(_shot)
	var t := 1.0 - exp(-4.0 * delta)
	_camera.global_transform = _camera.global_transform.interpolate_with(want, t)
	# Right stick turns the character.
	var stick := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	if absf(stick) > 0.2 and _page in ["creator", "class", "load"]:
		_turntable.rotation.y += stick * 2.5 * delta


func _unhandled_input(event: InputEvent) -> void:
	if _settings.is_open():
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) and _page in ["creator", "class", "load"]:
		_turntable.rotation.y += event.relative.x * 0.012
	elif event is InputEventMouseButton and event.pressed and _page == "creator":
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_shot = "face"
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_shot = "full"
	elif event.is_action_pressed("ui_cancel"):
		match _page:
			"load", "credits", "creator":
				_show("title")
			"class":
				_show("creator")
		get_viewport().set_input_as_handled()


func _shot_transform(shot: String) -> Transform3D:
	var s: Array = SHOTS[shot]
	var h := _model.scale.y if _model else 1.0
	var pos: Vector3 = s[0]
	var at: Vector3 = s[1]
	if shot in ["full", "face", "left"]:
		pos.y = pos.y * h + DAIS_TOP
		at.y = at.y * h + DAIS_TOP
	return Transform3D.IDENTITY.looking_at(at - pos, Vector3.UP).translated(pos)


# --- Stage -----------------------------------------------------------------------

func _build_stage() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.3, 0.62)
	sky_mat.sky_horizon_color = Color(0.95, 0.68, 0.5)
	sky_mat.ground_horizon_color = Color(0.55, 0.42, 0.35)
	sky_mat.ground_bottom_color = Color(0.16, 0.2, 0.12)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.6, 0.5)
	env.fog_density = 0.007
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.ssao_enabled = GameSettings.ssao
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-24.0, 205.0, 0.0)  # low, from behind the camera's left
	add_child(sun)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.55, 0.65, 1.0)
	rim.light_energy = 1.4
	rim.omni_range = 5.0
	rim.position = Vector3(1.4, 2.4, 1.6)
	add_child(rim)

	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 40.0
	disc.bottom_radius = 40.0
	disc.height = 0.2
	disc.radial_segments = 48
	ground.mesh = disc
	ground.position.y = -0.1
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.62, 0.8, 0.45)
	if ResourceLoader.exists("res://assets/materials/terrain/grass_color.jpg"):
		grass.albedo_texture = load("res://assets/materials/terrain/grass_color.jpg")
		grass.uv1_scale = Vector3(30, 30, 1)
		grass.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	grass.roughness = 1.0
	ground.material_override = grass
	add_child(ground)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.4, 0.38, 0.4)
	stone.roughness = 0.9
	for ring in [[1.05, 0.12, 0.06], [0.9, 0.12, DAIS_TOP - 0.06]]:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = ring[0]
		cyl.bottom_radius = ring[0] + 0.04
		cyl.height = ring[1]
		cyl.radial_segments = 10
		mi.mesh = cyl
		mi.position.y = ring[2]
		mi.material_override = stone
		add_child(mi)

	# A glade of pines and rocks around the dais (props from assets/props).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var props := [["pine_tree", 18, 7.0, 20.0, 0.2, 0.34], ["rock2", 5, 5.0, 12.0, 0.06, 0.12], ["rock4", 5, 5.0, 14.0, 0.08, 0.15], ["rock5", 4, 6.0, 14.0, 0.08, 0.14]]
	for p in props:
		var path := "res://assets/props/%s.glb" % p[0]
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		for i in int(p[1]):
			var node := scene.instantiate() as Node3D
			# Keep the view toward the camera open: mostly behind and to the sides.
			var a := rng.randf_range(-PI * 0.42, PI * 0.42)
			var r := rng.randf_range(p[2], p[3])
			# Props are modelled Z-up (as exported for the level chunks).
			var z_up := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
			node.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * z_up.scaled(Vector3.ONE * rng.randf_range(p[4], p[5])),
				Vector3(sin(a) * r, 0.0, cos(a) * r))
			add_child(node)

	_turntable = Node3D.new()
	_turntable.position.y = DAIS_TOP
	add_child(_turntable)
	var body := (load("res://assets/models/characters/base_bodies.scn") as PackedScene).instantiate()
	body.set_script(load("res://scripts/player/character_model.gd"))
	_turntable.add_child(body)
	_model = body as CharacterModel

	_camera = Camera3D.new()
	_camera.fov = 40.0
	add_child(_camera)
	_camera.current = true

	var ambience := AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/ambience/breeze_loop.ogg"):
		ambience.stream = load("res://assets/audio/ambience/breeze_loop.ogg")
		ambience.bus = "Ambience"
		ambience.volume_db = -8.0
		ambience.autoplay = true
		add_child(ambience)


## Shows a saved character (look and equipment) on the dais.
func _show_character(save: Dictionary) -> void:
	_model.visible = true
	_model.take_off_all()
	_model.apply_appearance(Database.resolve_appearance(save.get("look", {})))
	var inv: Dictionary = save.get("inventory", {})
	var eq: Dictionary = inv.get("equipped", {})
	if eq.is_empty():
		eq = _class_kit(String(save.get("class", ""))).get("equipment", {})
	_dress(eq)


func _dress(equipment: Dictionary) -> void:
	# Armour and shield; weapons stay off (they'd hang in the hand in the idle pose).
	for slot in ["head", "shoulders", "chest", "hands", "legs", "feet", "off_hand"]:
		_model.take_off(slot)
		var item := Database.item(String(equipment.get(slot, "")))
		if not item.is_empty():
			_model.wear(item, slot)


func _class_kit(class_id: String) -> Dictionary:
	var kit = Database.class_data(class_id).get("starting_kit", {})
	if kit is Dictionary and (not kit.get("equipment", {}).is_empty() or not kit.get("backpack", []).is_empty()):
		return kit
	return Database.player.get("starting_kit", {})


# --- UI building ---------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = _make_theme()
	layer.add_child(_ui)
	_pages["title"] = _title_page()
	_pages["load"] = _load_page()
	_pages["credits"] = _credits_page()
	_pages["achievements"] = _achievements_page()
	_pages["species"] = _species_page()
	_pages["creator"] = _creator_page()
	_pages["class"] = _class_page()
	for key: String in _pages:
		_ui.add_child(_pages[key])

	_settings = SettingsMenu.new()
	_settings.title_screen = true
	add_child(_settings)
	_settings.closed.connect(func() -> void: _show("title"))

	_loading = ColorRect.new()
	(_loading as ColorRect).color = Color(0.03, 0.03, 0.05, 0.92)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.visible = false
	var lab := Label.new()
	lab.text = "Loading…"
	lab.add_theme_font_size_override("font_size", 34)
	lab.add_theme_color_override("font_color", ACCENT)
	lab.set_anchors_preset(Control.PRESET_CENTER)
	lab.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lab.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading.add_child(lab)
	var top := CanvasLayer.new()
	top.layer = 30
	add_child(top)
	top.add_child(_loading)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var normal := _box(Color(0.16, 0.14, 0.2, 0.95), Color(0.4, 0.34, 0.24), 1)
	var hover := _box(Color(0.24, 0.2, 0.28, 0.98), ACCENT.darkened(0.2), 1)
	var pressed := _box(Color(0.32, 0.25, 0.16, 1.0), ACCENT, 2)
	var disabled := _box(Color(0.12, 0.11, 0.14, 0.8), Color(0.25, 0.23, 0.22), 1)
	var focus := _box(Color(0, 0, 0, 0), ACCENT, 2)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Color(0.95, 0.92, 0.86))
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_hover_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.48, 0.46))
	t.set_stylebox("panel", "PanelContainer", _box(PANEL_COLOR, ACCENT.darkened(0.45), 2, 14))
	t.set_stylebox("normal", "LineEdit", _box(Color(0.1, 0.09, 0.12, 1.0), Color(0.45, 0.38, 0.26), 1, 8))
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), ACCENT, 2))
	t.set_color("font_color", "Label", Color(0.93, 0.9, 0.85))
	return t


static func _box(bg: Color, border: Color, width: int, margin := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(margin)
	return sb


func _panel(anchor: int, offset: Vector2, min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.set_anchors_preset(anchor)
	p.offset_left = offset.x
	p.offset_top = offset.y
	p.offset_right = offset.x + min_size.x
	p.offset_bottom = offset.y + min_size.y
	# Bottom panels grow upward, centred ones both ways, as their contents need.
	if anchor in [Control.PRESET_CENTER_BOTTOM, Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]:
		p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	elif anchor == Control.PRESET_CENTER:
		p.grow_vertical = Control.GROW_DIRECTION_BOTH
	if anchor in [Control.PRESET_CENTER, Control.PRESET_CENTER_BOTTOM]:
		p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	return p


## Fills a top panel down to just above the bottom bar and scrolls what doesn't fit
## (so tall panels never run under the buttons or off a small window).
func _scrolling(panel: PanelContainer, separation: int) -> VBoxContainer:
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -110.0
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	return v


func _heading(text: String, size := 22) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	return l


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_font_size_override("font_size", 15)
	return l


func _button(text: String, action: Callable, min_width := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 40)
	b.pressed.connect(action)
	return b


func _page_root() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _show(page: String) -> void:
	_page = page
	for key: String in _pages:
		(_pages[key] as Control).visible = key == page
	match page:
		"title":
			_shot = "title"
			_saves = GameSession.list_saves()
			_load_game_button.disabled = _saves.is_empty()
			_load_game_button.tooltip_text = "No saved characters yet." if _saves.is_empty() else ""
			if not _saves.is_empty():
				_show_character(_saves[0])
			else:
				_model.visible = false
		"load":
			_shot = "left"
			_refresh_saves()
		"credits", "achievements":
			_shot = "credits"
			_model.visible = not _saves.is_empty()
			if page == "achievements":
				_fill_achievements()
		"species":
			_shot = "full"
			_model.visible = true
			_model.take_off_all()
			_select_species(String(_look.get("species", "human")))
		"creator":
			_shot = "full"
			_model.visible = true
			_model.take_off_all()
			_apply_look()
		"class":
			_shot = "full"
			_select_class(_class_id)
			_refresh_attributes()
	if GameSettings.gamepad:
		_focus_first(_pages[page])


func _focus_first(node: Node) -> void:
	for c in node.find_children("*", "Button", true, false):
		if (c as Button).is_visible_in_tree() and not (c as Button).disabled:
			(c as Button).grab_focus()
			return


# --- Title -------------------------------------------------------------------------

func _title_page() -> Control:
	var page := _page_root()
	var box := VBoxContainer.new()
	box.position = Vector2(72, 70)
	box.add_theme_constant_override("separation", 10)
	page.add_child(box)
	var logo := Label.new()
	logo.text = "TITAMAS"
	logo.add_theme_font_size_override("font_size", 84)
	logo.add_theme_color_override("font_color", ACCENT)
	logo.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.05))
	logo.add_theme_constant_override("outline_size", 14)
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	logo.add_theme_constant_override("shadow_offset_y", 5)
	box.add_child(logo)
	var sub := Label.new()
	sub.text = "O  N  L  I  N  E"
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", Color(0.98, 0.94, 0.86))
	sub.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.05))
	sub.add_theme_constant_override("outline_size", 8)
	box.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	box.add_child(gap)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	buttons.add_child(_button("New Game", _new_game, 260))
	_load_game_button = _button("Load Game", func() -> void: _show("load"), 260)
	buttons.add_child(_load_game_button)
	buttons.add_child(_button("Achievements", func() -> void: _show("achievements"), 260))
	buttons.add_child(_button("Settings", func() -> void:
		(_pages["title"] as Control).visible = false
		_settings.open(), 260))
	buttons.add_child(_button("Credits", func() -> void: _show("credits"), 260))
	buttons.add_child(_button("Quit", func() -> void:
		get_tree().quit(), 260))
	var version := _note("Early test build · milestone 3")
	version.autowrap_mode = TextServer.AUTOWRAP_OFF
	version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 24
	version.offset_top = -40
	version.offset_bottom = -16
	page.add_child(version)
	return page


func _new_game() -> void:
	_look = (Database.appearance.get("default", {}) as Dictionary).duplicate()
	_pronouns = String(_look.get("pronouns", "he"))
	_look.erase("pronouns")
	_pronouns_touched = false
	_class_id = "fighter"
	_name_edit.text = ""
	_name_error.text = ""
	_turntable.rotation.y = 0.0
	_points = {}
	if not Database.species_list.is_empty() and not _look.has("species"):
		_look["species"] = String(Database.species_list[0].get("id", "human"))
	_show("species")


# --- Load game (character select) ----------------------------------------------------------

func _load_page() -> Control:
	var page := _page_root()
	var panel := _panel(Control.PRESET_RIGHT_WIDE, Vector2(-440, 0), Vector2(400, 0))
	panel.offset_left = -440
	panel.offset_right = -30
	panel.offset_top = 40
	panel.offset_bottom = -40
	page.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_heading("Characters", 26))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_save_list = VBoxContainer.new()
	_save_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_save_list)
	_play_button = _button("Play", _play_selected)
	_play_button.custom_minimum_size.y = 52
	_play_button.add_theme_font_size_override("font_size", 24)
	v.add_child(_play_button)
	# Co-op: host this character's world, or join a friend's.
	var coop := HBoxContainer.new()
	coop.add_theme_constant_override("separation", 10)
	_host_button = _button("Host co-op", _host_selected)
	_host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_button.tooltip_text = "Play this character and let friends join you."
	coop.add_child(_host_button)
	_join_button = _button("Join co-op…", func() -> void: _join_box.visible = not _join_box.visible)
	_join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_button.tooltip_text = "Bring this character into a friend's game."
	coop.add_child(_join_button)
	v.add_child(coop)
	_join_box = HBoxContainer.new()
	_join_box.add_theme_constant_override("separation", 8)
	_join_box.visible = false
	_join_address = LineEdit.new()
	_join_address.placeholder_text = "Host's address, e.g. 192.168.1.20"
	_join_address.text = "127.0.0.1"
	_join_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_box.add_child(_join_address)
	_join_box.add_child(_button("Connect", _join_selected))
	v.add_child(_join_box)
	_net_status = _note("")
	v.add_child(_net_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var back := _button("Back", func() -> void: _show("title"))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back)
	_delete_button = _button("Delete character", func() -> void:
		if _selected_save >= 0:
			_confirm_delete.dialog_text = "Delete %s for good? This can't be undone." % _saves[_selected_save].name
			_confirm_delete.popup_centered())
	_delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_delete_button)
	v.add_child(row)
	_confirm_delete = ConfirmationDialog.new()
	_confirm_delete.title = "Delete character"
	_confirm_delete.ok_button_text = "Delete"
	_confirm_delete.confirmed.connect(func() -> void:
		if _selected_save >= 0:
			GameSession.delete_save(String(_saves[_selected_save].path))
			_selected_save = -1
			_refresh_saves())
	page.add_child(_confirm_delete)
	return page


func _refresh_saves() -> void:
	_saves = GameSession.list_saves()
	for c in _save_list.get_children():
		c.queue_free()
	var group := ButtonGroup.new()
	for i in _saves.size():
		var s := _saves[i]
		var cls := String(Database.class_data(String(s.get("class", ""))).get("name", "Adventurer"))
		var species := String(Database.species_of(s).get("name", "Human"))
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 84)
		b.text = "%s\nLevel %d %s %s\nPlayed %s · %s" % [s.name, int(s.get("level", 1)), species, cls,
			GameSession.format_time(float(s.get("play_time", 0.0))), _date(float(s.get("saved", 0)))]
		b.pressed.connect(func() -> void: _select_save(i))
		b.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.double_click:
				_select_save(i)
				_play_selected())
		_save_list.add_child(b)
	if _saves.is_empty():
		_save_list.add_child(_note("No saved characters yet. Choose New Game on the title screen."))
		_selected_save = -1
		_model.visible = false
	else:
		_select_save(clampi(_selected_save, 0, _saves.size() - 1))
	_play_button.disabled = _saves.is_empty()
	_delete_button.disabled = _saves.is_empty()
	_host_button.disabled = _saves.is_empty()
	_join_button.disabled = _saves.is_empty()


func _select_save(i: int) -> void:
	_selected_save = i
	var buttons := _save_list.get_children()
	if i < buttons.size() and buttons[i] is Button:
		(buttons[i] as Button).set_pressed_no_signal(true)
	_show_character(_saves[i])


func _play_selected() -> void:
	if _selected_save < 0 or _selected_save >= _saves.size():
		return
	if GameSession.load_save(String(_saves[_selected_save].path)):
		_start()


func _host_selected() -> void:
	if _selected_save < 0 or not GameSession.load_save(String(_saves[_selected_save].path)):
		return
	var err := Net.host_game()
	if err != OK:
		_net_status.text = "Couldn't host (port %d may be in use)." % Net.DEFAULT_PORT
		return
	_start()


func _join_selected() -> void:
	if _selected_save < 0 or not GameSession.load_save(String(_saves[_selected_save].path)):
		return
	var address := _join_address.text.strip_edges()
	if address.is_empty():
		_net_status.text = "Type the host's address first."
		return
	if Net.join_game(address) != OK:
		_net_status.text = "That address doesn't look right."
		return
	_net_status.text = "Connecting to %s…" % address
	_loading.visible = true


func _on_net_connected() -> void:
	_net_status.text = ""
	_start()


func _on_net_failed(reason: String) -> void:
	_loading.visible = false
	_net_status.text = reason


func _start() -> void:
	_loading.visible = true
	# Let "Loading…" draw before the level loads.
	await get_tree().process_frame
	await get_tree().process_frame
	GameSession.start_game()


static func _date(unix: float) -> String:
	if unix <= 0.0:
		return "never"
	var local: int = int(unix) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(local)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %d, %d:%02d" % [months[d.month - 1], d.day, d.hour, d.minute]


# --- Credits ---------------------------------------------------------------------------

func _credits_page() -> Control:
	var page := _page_root()
	var panel := _panel(Control.PRESET_CENTER, Vector2(-300, -280), Vector2(600, 560))
	page.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(_heading("Credits", 30))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var data = DataFiles.read("res://data/credits.json")
	for section: Dictionary in (data.get("sections", []) if data is Dictionary else []):
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 10)
		list.add_child(gap)
		var h := _heading(String(section.get("title", "")), 20)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(h)
		for line in section.get("lines", []):
			var l := Label.new()
			l.text = String(line)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(l)
	v.add_child(_button("Back", func() -> void: _show("title")))
	return page


# --- Achievements (account-wide; Database → Achievements) -----------------------------------

var _ach_list: VBoxContainer
var _ach_total: Label


func _achievements_page() -> Control:
	var page := _page_root()
	var panel := _panel(Control.PRESET_CENTER, Vector2(-330, -290), Vector2(660, 580))
	page.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(_heading("Achievements", 30))
	_ach_total = _note("")
	v.add_child(_ach_total)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_ach_list = VBoxContainer.new()
	_ach_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ach_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_ach_list)
	v.add_child(_button("Back", func() -> void: _show("title")))
	return page


func _fill_achievements() -> void:
	for c in _ach_list.get_children():
		c.queue_free()
	var ach := get_node_or_null("/root/Achievements")
	if ach == null:
		return
	var got_count := 0
	var defs: Array = ach.call("all")
	for d: Dictionary in defs:
		var id := String(d.get("id", ""))
		var got := bool(ach.call("is_unlocked", id))
		got_count += 1 if got else 0
		var secret := bool(d.get("hidden", false)) and not got
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.05 if got else 0.025)
		sb.border_color = Color(1, 1, 1, 0.1)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(8)
		row.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		var badge := AchievementPopup.Trophy.new()
		badge.custom_minimum_size = Vector2(52, 52)
		badge.locked = not got
		badge.icon = AchievementPopup.icon_of(d)
		h.add_child(badge)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		var name_l := Label.new()
		name_l.text = "???" if secret else String(d.get("name", id))
		name_l.add_theme_font_size_override("font_size", 18)
		name_l.add_theme_color_override("font_color", Color(0.96, 0.92, 0.85) if got else Color(0.72, 0.74, 0.8))
		text.add_child(name_l)
		var desc := _note("Hidden achievement." if secret else String(d.get("description", "")))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(desc)
		h.add_child(text)
		var right := VBoxContainer.new()
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		var pts := Label.new()
		pts.text = "%d pts" % int(d.get("points", 0))
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pts.add_theme_color_override("font_color", Color(1.0, 0.82, 0.48) if got else Color(0.42, 0.44, 0.53))
		right.add_child(pts)
		if got:
			var when := _note(Time.get_date_string_from_unix_time(int(ach.call("unlocked_at", id))))
			when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			when.add_theme_font_size_override("font_size", 12)
			right.add_child(when)
		h.add_child(right)
		_ach_list.add_child(row)
	var p: Vector2i = ach.call("points")
	_ach_total.text = "%d of %d earned  ·  %d / %d points" % [got_count, defs.size(), p.x, p.y]


# --- Character creator ----------------------------------------------------------------------

func _creator_page() -> Control:
	var page := _page_root()
	var a: Dictionary = Database.appearance

	# Left: species, body type, pronouns.
	var left := _panel(Control.PRESET_TOP_LEFT, Vector2(30, 40), Vector2(300, 0))
	page.add_child(left)
	var lv := _scrolling(left, 10)
	lv.add_child(_heading("Create your character", 24))
	lv.add_child(_section("Pronouns"))
	lv.add_child(_choice_row("pronouns", _options(a.get("pronouns", []))))
	lv.add_child(_section("Skin colour"))
	lv.add_child(_swatch_grid("skin", a.get("skin_colors", []), 5))
	lv.add_child(_note("Drag to turn your character · mouse wheel to zoom"))

	# Right: hair, facial hair, eyes.
	var right := _panel(Control.PRESET_TOP_RIGHT, Vector2(-370, 40), Vector2(340, 0))
	page.add_child(right)
	var rv := _scrolling(right, 10)
	rv.add_child(_heading("Appearance", 24))
	rv.add_child(_stepper("Face", "face", "faces"))
	rv.add_child(_stepper("Hair style", "hair", "hair_styles"))
	rv.add_child(_swatch_grid("hair_color", a.get("hair_colors", []), 7))
	rv.add_child(_stepper("Facial hair", "facial_hair", "facial_hair"))
	rv.add_child(_swatch_grid("facial_color", a.get("hair_colors", []), 7))
	rv.add_child(_stepper("Eyes", "eyes", "eyes"))
	rv.add_child(_swatch_grid("eye_color", a.get("eye_colors", []), 5))
	rv.add_child(_button("Randomize", _randomize))

	# Bottom: name and navigation.
	var bottom := _panel(Control.PRESET_CENTER_BOTTOM, Vector2(-260, -24), Vector2(520, 0))
	page.add_child(bottom)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 8)
	bottom.add_child(bv)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	var nl := Label.new()
	nl.text = "Name"
	name_row.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your character's name"
	_name_edit.max_length = NAME_MAX
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(_t: String) -> void: _name_error.text = "")
	name_row.add_child(_name_edit)
	bv.add_child(name_row)
	_name_error = Label.new()
	_name_error.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	_name_error.add_theme_font_size_override("font_size", 15)
	bv.add_child(_name_error)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	var back := _button("‹  Species", func() -> void: _show("species"))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(back)
	var next := _button("Next: choose a class  ›", _to_class)
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(next)
	bv.add_child(nav)
	return page


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", DIM)
	return l


func _options(list: Array) -> Array:
	var out := []
	for o in list:
		if o is Dictionary:
			out.append([String(o.get("id", "")), String(o.get("name", o.get("id", "")))])
	return out


## A row of toggle buttons; one is picked.
func _choice_row(key: String, options: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	var entries := []
	for o: Array in options:
		var b := Button.new()
		b.text = o[1]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 36
		var id: String = o[0]
		b.pressed.connect(func() -> void: _set_choice(key, id))
		row.add_child(b)
		entries.append([id, b])
	_choices[key] = entries
	return row


func _set_choice(key: String, id: String) -> void:
	if key == "pronouns":
		_pronouns = id
		_pronouns_touched = true
		return
	_look[key] = id
	if key == "body" and not _pronouns_touched:
		_pronouns = "she" if id == "femme" else "he"
	_shot = "full"
	_apply_look()


## Name, "<", the current choice, ">" — steps through an appearance list.
func _stepper(title: String, key: String, list: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_child(_section(title))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var prev := _button("‹", func() -> void: _step(key, list, -1))
	prev.custom_minimum_size = Vector2(44, 36)
	row.add_child(prev)
	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	var next := _button("›", func() -> void: _step(key, list, 1))
	next.custom_minimum_size = Vector2(44, 36)
	row.add_child(next)
	v.add_child(row)
	_steppers[key] = [list, value]
	return v


func _step(key: String, list: String, dir: int) -> void:
	var options: Array = Database.appearance.get(list, [])
	if options.is_empty():
		return
	var i := 0
	for k in options.size():
		if String(options[k].get("id", "")) == String(_look.get(key, "")):
			i = k
	_look[key] = String(options[posmod(i + dir, options.size())].id)
	_shot = "face"
	_apply_look()


## A row of preset colours plus "More colours…", which opens a full picker.
func _swatch_grid(key: String, colors: Array, columns: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.add_child(_swatch_row(key, colors, columns))
	var face := key in ["hair_color", "facial_color", "eye_color"]
	var more := Button.new()
	more.text = "More colours…"
	more.custom_minimum_size = Vector2(0, 26)
	more.pressed.connect(func() -> void: _pick_color(key, face, more))
	box.add_child(more)
	return box


## The picker window: changing the colour shows on the character as you drag.
func _pick_color(key: String, face: bool, from: Control) -> void:
	var popup := PopupPanel.new()
	var picker := ColorPicker.new()
	picker.edit_alpha = false
	picker.color = Color.html(String(_look.get(key, "#ffffff")))
	picker.custom_minimum_size = Vector2(300, 0)
	# Applying the look rebuilds the model, so wait for a pause in the dragging.
	var settle := Timer.new()
	settle.wait_time = 0.12
	settle.one_shot = true
	settle.timeout.connect(func() -> void:
		if face:
			_shot = "face"
		_apply_look())
	picker.add_child(settle)
	picker.color_changed.connect(func(c: Color) -> void:
		_look[key] = "#" + c.to_html(false)
		settle.start())
	popup.add_child(picker)
	add_child(popup)
	popup.popup_hide.connect(popup.queue_free)
	popup.popup_centered()
	if from and from.is_inside_tree():
		popup.position = Vector2i(from.get_screen_position()) + Vector2i(-320, -120)


func _swatch_row(key: String, colors: Array, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var entries := []
	for c in colors:
		var col := String(c)
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 30)
		b.tooltip_text = col
		var face := key in ["hair_color", "facial_color", "eye_color"]
		b.pressed.connect(func() -> void:
			_look[key] = col
			_shot = "face" if face else _shot
			_apply_look())
		grid.add_child(b)
		entries.append([col, b])
	_swatches[key] = entries
	return grid


func _randomize() -> void:
	var a := Database.appearance
	var pick := func(list: String) -> String:
		var o: Array = a.get(list, [])
		return String(o[randi() % o.size()].get("id", "")) if not o.is_empty() else ""
	var pick_color := func(list: String) -> String:
		var o: Array = a.get(list, [])
		return String(o[randi() % o.size()]) if not o.is_empty() else ""
	_look["skin"] = pick_color.call("skin_colors")
	_look["face"] = "painted"
	_look["hair"] = pick.call("hair_styles")
	# Natural hair colours most of the time.
	var hair_colors: Array = a.get("hair_colors", [])
	_look["hair_color"] = String(hair_colors[randi() % mini(10, hair_colors.size())]) if randf() < 0.85 and not hair_colors.is_empty() else pick_color.call("hair_colors")
	_look["facial_color"] = _look.hair_color
	_look["facial_hair"] = pick.call("facial_hair") if randf() < 0.5 else "none"
	_look["eyes"] = pick.call("eyes")
	_look["eye_color"] = pick_color.call("eye_colors")
	_shot = "full"
	_apply_look()


func _apply_look() -> void:
	_model.apply_appearance(Database.resolve_appearance(_look))
	_refresh_creator()


func _refresh_creator() -> void:
	for key: String in _choices:
		var current := _pronouns if key == "pronouns" else String(_look.get(key, ""))
		for e: Array in _choices[key]:
			(e[1] as Button).set_pressed_no_signal(e[0] == current)
	for key: String in _steppers:
		var list: String = _steppers[key][0]
		var options: Array = Database.appearance.get(list, [])
		var label := _steppers[key][1] as Label
		for k in options.size():
			if String(options[k].get("id", "")) == String(_look.get(key, "")):
				label.text = "%s   (%d / %d)" % [options[k].get("name", ""), k + 1, options.size()]
	for key: String in _swatches:
		for e: Array in _swatches[key]:
			var col := Color.html(e[0])
			var on: bool = String(e[0]).to_lower() == String(_look.get(key, "")).to_lower()
			var sb := _box(col, ACCENT if on else Color(0.1, 0.08, 0.08), 3 if on else 1, 0)
			for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
				var s: StyleBoxFlat = sb.duplicate()
				if state == "hover" and not on:
					s.border_color = Color(0.9, 0.9, 0.9)
				if state == "focus":
					s.bg_color = Color(0, 0, 0, 0)
					s.border_color = Color(1, 1, 1)
				(e[1] as Button).add_theme_stylebox_override(state, s)


func _to_class() -> void:
	var n := _name_edit.text.strip_edges()
	while n.contains("  "):
		n = n.replace("  ", " ")
	var regex := RegEx.create_from_string("^[\\p{L}][\\p{L} '\\-]*$")
	if n.length() < 2:
		_name_error.text = "Give your character a name (2 to %d letters)." % NAME_MAX
		_name_edit.grab_focus()
		return
	if regex.search(n) == null:
		_name_error.text = "Names can use letters, spaces, apostrophes and hyphens."
		_name_edit.grab_focus()
		return
	_name_edit.text = n
	_show("class")


# --- Species -------------------------------------------------------------------------------

func _species_page() -> Control:
	var page := _page_root()
	var left := _panel(Control.PRESET_TOP_LEFT, Vector2(30, 40), Vector2(280, 0))
	page.add_child(left)
	var lv := _scrolling(left, 10)
	lv.add_child(_heading("Choose a species", 24))
	var group := ButtonGroup.new()
	for sp: Dictionary in Database.species_list:
		var id := String(sp.get("id", ""))
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 48)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = String(sp.get("name", id))
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func() -> void: _select_species(id))
		lv.add_child(b)
		_species_buttons.append([id, b])
	lv.add_child(_note("Drag to turn your character"))

	var right := _panel(Control.PRESET_TOP_RIGHT, Vector2(-410, 30), Vector2(380, 0))
	page.add_child(right)
	var rv := _scrolling(right, 10)
	_species_info = RichTextLabel.new()
	_species_info.bbcode_enabled = true
	_species_info.fit_content = true
	_species_info.scroll_active = false
	_species_info.add_theme_font_size_override("normal_font_size", 17)
	_species_info.add_theme_font_size_override("bold_font_size", 17)
	rv.add_child(_species_info)

	var bottom := _panel(Control.PRESET_CENTER_BOTTOM, Vector2(-210, -24), Vector2(420, 0))
	page.add_child(bottom)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	bottom.add_child(nav)
	var back := _button("‹  Back", func() -> void: _show("title"))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(back)
	var go := _button("Next: appearance  ›", func() -> void: _show("creator"))
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(go)
	return page


func _select_species(id: String) -> void:
	var sp := Database.species_data(id)
	if sp.is_empty():
		return
	_look["species"] = String(sp.get("id", id))
	for e: Array in _species_buttons:
		(e[1] as Button).set_pressed_no_signal(e[0] == _look.species)
	var t := "[font_size=28][color=#%s]%s[/color][/font_size]\n%s\n" % [ACCENT.to_html(false), sp.get("name", id), sp.get("description", "")]
	if String(sp.get("traits", "")) != "":
		t += "\n[color=#bfb7aa]%s[/color]\n" % sp.traits
	var mods: Dictionary = sp.get("attributes", {})
	if not mods.is_empty():
		t += "\n[b]Attributes[/b]\n"
		for a: Array in Database.attribute_list():
			var n := int(mods.get(a[0], 0))
			if n != 0:
				t += "  %s  [color=#%s]%+d[/color]\n" % [a[1], "7fe07f" if n > 0 else "ff7a6a", n]
	var stats_mod: Dictionary = sp.get("stats", {})
	if not stats_mod.is_empty():
		t += "\n[b]Bonuses[/b]\n"
		for k: String in stats_mod:
			t += "  %s  [color=#7fe07f]%s%s[/color]\n" % [_stat_name(k), _signed(float(stats_mod[k])), "%" if k == "crit_chance" else ""]
	var mv: Dictionary = sp.get("movement", {})
	var moves: Array[String] = []
	for k: Array in [["run_speed", "Running"], ["sprint_speed", "Sprinting"], ["swim_speed", "Swimming"], ["jump", "Jumping"]]:
		var f := float(mv.get(k[0], 1.0))
		if absf(f - 1.0) > 0.001:
			moves.append("%s [color=#%s]%+d%%[/color]" % [k[1], "7fe07f" if f > 1.0 else "ff7a6a", roundi((f - 1.0) * 100.0)])
	if not moves.is_empty():
		t += "\n[b]Movement[/b]\n  %s\n" % "   ".join(moves)
	for r in sp.get("racial", []):
		var ab := Database.ability(String((r as Dictionary).get("ability", "")))
		if ab:
			t += "\n[b]Racial ability: %s[/b]\n[color=#bfb7aa]%s[/color]\n" % [ab.display_name, ab.description]
	_species_info.text = t
	_shot = "full"
	_apply_look()


## "+3", "-1", "+0.5".
static func _signed(v: float) -> String:
	var t := str(int(v)) if is_equal_approx(v, roundf(v)) else str(snappedf(v, 0.1))
	return ("+" if v >= 0.0 else "") + t


static func _stat_name(key: String) -> String:
	return {"attack": "Attack", "spell_power": "Spell power", "armor": "Armour", "block": "Block", "bonus_health": "Health",
		"bonus_mana": "Mana", "crit_chance": "Critical chance", "stamina": "Stamina", "mana_regen": "Mana per second",
		"move_speed": "Move speed"}.get(key, key.capitalize())


# --- Attributes (class page) -----------------------------------------------------------------

func _attributes_box() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(_section("Attributes"))
	_points_label = _note("")
	v.add_child(_points_label)
	for a: Array in Database.attribute_list():
		var id: String = a[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_l := Label.new()
		name_l.text = a[1]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.tooltip_text = "%s\n%s" % [a[2], _effects_text(a[3])]
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name_l)
		var minus := _button("−", func() -> void: _spend(id, -1))
		minus.custom_minimum_size = Vector2(34, 30)
		row.add_child(minus)
		var value := Label.new()
		value.custom_minimum_size = Vector2(34, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(value)
		var plus := _button("+", func() -> void: _spend(id, 1))
		plus.custom_minimum_size = Vector2(34, 30)
		row.add_child(plus)
		v.add_child(row)
		_attr_rows[id] = [value, minus, plus]
	_derived = _note("")
	_derived.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_derived)
	return v


func _effects_text(effects: Dictionary) -> String:
	var parts: Array[String] = []
	for k: String in effects:
		parts.append("%s %s" % [_signed(float(effects[k])), _stat_name(k)])
	return "Each point: " + ", ".join(parts)


func _spend(id: String, dir: int) -> void:
	var cfg: Dictionary = Database.player.get("attributes", {})
	var total := int(cfg.get("creation_points", 5))
	var cap := int(cfg.get("max_creation_per_attribute", 3))
	var used := 0
	for k in _points:
		used += int(_points[k])
	var have := int(_points.get(id, 0))
	if dir > 0 and (used >= total or have >= cap):
		return
	if dir < 0 and have <= 0:
		return
	_points[id] = have + dir
	_refresh_attributes()


func _refresh_attributes() -> void:
	if _points_label == null:
		return
	var cfg: Dictionary = Database.player.get("attributes", {})
	var total := int(cfg.get("creation_points", 5))
	var cap := int(cfg.get("max_creation_per_attribute", 3))
	var used := 0
	for k in _points:
		used += int(_points[k])
	_points_label.text = "%d of %d points left (up to %d in one)" % [total - used, total, cap]
	var vals := Database.attributes_for({"look": _look, "attribute_points": _points})
	var base := int(cfg.get("base", 10))
	for id: String in _attr_rows:
		var row: Array = _attr_rows[id]
		var n := int(vals.get(id, base))
		(row[0] as Label).text = str(n)
		(row[0] as Label).add_theme_color_override("font_color", Color(0.5, 0.88, 0.5) if n > base else (Color(1.0, 0.5, 0.45) if n < base else Color(0.95, 0.93, 0.9)))
		(row[1] as Button).disabled = int(_points.get(id, 0)) <= 0
		(row[2] as Button).disabled = used >= total or int(_points.get(id, 0)) >= cap
	var bonus := Database.attribute_bonus(vals)
	var sp_stats: Dictionary = Database.species_data(String(_look.get("species", ""))).get("stats", {})
	for k: String in sp_stats:
		bonus[k] = float(bonus.get(k, 0.0)) + float(sp_stats[k])
	var parts: Array[String] = []
	for k: String in ["bonus_health", "bonus_mana", "attack", "spell_power", "armor", "crit_chance", "stamina"]:
		if absf(float(bonus.get(k, 0.0))) >= 0.05:
			parts.append("%s %s%s" % [_stat_name(k), _signed(snappedf(float(bonus[k]), 0.1)), "%" if k == "crit_chance" else ""])
	_derived.text = "From species and attributes: " + (", ".join(parts) if not parts.is_empty() else "nothing yet")


# --- Class select ----------------------------------------------------------------------------

func _class_page() -> Control:
	var page := _page_root()
	var left := _panel(Control.PRESET_TOP_LEFT, Vector2(30, 40), Vector2(300, 0))
	page.add_child(left)
	var lv := _scrolling(left, 10)
	lv.add_child(_heading("Choose a class", 24))
	var group := ButtonGroup.new()
	for c: Dictionary in Database.classes:
		var id := String(c.get("id", ""))
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 56)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var available := bool(c.get("available", false))
		b.text = "%s\n%s" % [c.get("name", id), c.get("role", "") if available else "Coming soon"]
		b.add_theme_font_size_override("font_size", 17)
		var stripe := ColorRect.new()
		stripe.color = Color.html(String(c.get("color", "#888888")))
		stripe.custom_minimum_size = Vector2(6, 0)
		stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(stripe)
		b.disabled = not available
		b.tooltip_text = "" if available else "This class comes in a later update."
		b.pressed.connect(func() -> void: _select_class(id))
		lv.add_child(b)
		_class_buttons.append([id, b])
	lv.add_child(HSeparator.new())
	lv.add_child(_attributes_box())

	var right := _panel(Control.PRESET_TOP_RIGHT, Vector2(-410, 30), Vector2(380, 0))
	page.add_child(right)
	var rv := _scrolling(right, 10)
	_class_info = RichTextLabel.new()
	_class_info.bbcode_enabled = true
	_class_info.fit_content = true
	_class_info.scroll_active = false
	_class_info.add_theme_font_size_override("normal_font_size", 17)
	_class_info.add_theme_font_size_override("bold_font_size", 17)
	rv.add_child(_class_info)
	rv.add_child(_section("Skill trees"))
	_class_trees = VBoxContainer.new()
	_class_trees.add_theme_constant_override("separation", 8)
	rv.add_child(_class_trees)

	var bottom := _panel(Control.PRESET_CENTER_BOTTOM, Vector2(-210, -24), Vector2(420, 0))
	page.add_child(bottom)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	bottom.add_child(nav)
	var back := _button("‹  Back", func() -> void: _show("creator"))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(back)
	var go := _button("Begin your adventure", _begin)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.add_theme_font_size_override("font_size", 20)
	nav.add_child(go)
	return page


var _class_trees: VBoxContainer


## The class's skill trees (data/skill_trees.json, Database → Skill Trees): each tree's
## name, description and its skills by tier.
func _fill_trees(id: String) -> void:
	if _class_trees == null:
		return
	for c in _class_trees.get_children():
		c.queue_free()
	var trees: Array = Database.trees_for(id)
	if trees.is_empty():
		_class_trees.add_child(_note("No skill trees yet (Database → Skill Trees)."))
		return
	for tree: Dictionary in trees:
		var col := PanelContainer.new()
		var accent := Color.html(String(tree.get("color", "#c9a25a"))) if Color.html_is_valid(String(tree.get("color", ""))) else Color(0.79, 0.64, 0.35)
		col.add_theme_stylebox_override("panel", _box(Color(0.12, 0.11, 0.15, 0.9), accent.darkened(0.3), 1, 6))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		col.add_child(cv)
		var title := Label.new()
		title.text = String(tree.get("name", tree.get("id", "")))
		title.add_theme_color_override("font_color", accent.lightened(0.2))
		title.add_theme_font_size_override("font_size", 16)
		cv.add_child(title)
		if String(tree.get("description", "")) != "":
			var d := _note(String(tree.description))
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cv.add_child(d)
		var nodes: Array = (tree.get("nodes", []) as Array).duplicate()
		nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("row", 0)) * 100 + int(a.get("col", 0)) < int(b.get("row", 0)) * 100 + int(b.get("col", 0)))
		var names := nodes.map(func(n: Dictionary) -> String: return "◇ %s" % String(n.get("name", n.get("id", ""))))
		if not names.is_empty():
			var l := _note("   ".join(names))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.tooltip_text = "\n".join(nodes.map(func(n: Dictionary) -> String: return "%s: %s" % [n.get("name", ""), n.get("description", "")]))
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			cv.add_child(l)
		_class_trees.add_child(col)


func _select_class(id: String) -> void:
	var c := Database.class_data(id)
	if c.is_empty() or not bool(c.get("available", false)):
		return
	_class_id = id
	_fill_trees(id)
	for e: Array in _class_buttons:
		(e[1] as Button).set_pressed_no_signal(e[0] == id)
	var text := "[font_size=28][color=#%s]%s[/color][/font_size]\n[color=#bfb7aa]%s[/color]\n\n%s\n" % [
		ACCENT.to_html(false), c.get("name", id), c.get("role", ""), c.get("description", "")]
	var strengths: Array = c.get("strengths", [])
	if not strengths.is_empty():
		text += "\n[b]Strengths[/b]\n"
		for s in strengths:
			text += "  •  %s\n" % s
	var names := []
	for ab_id in Database.player.get("loadout", {}).get("spells", []):
		var ab := Database.ability(String(ab_id))
		if ab and not ab.display_name in names:
			names.append(ab.display_name)
	if not names.is_empty():
		text += "\n[b]Starting spells[/b]\n  %s\n" % ", ".join(names)
	var proficient: Array = c.get("proficient", [])
	if not proficient.is_empty():
		var types := proficient.map(func(t: Variant) -> String: return String(Database.weapon_type(String(t)).get("name", t)))
		text += "\n[b]Weapon proficiency[/b]\n  %s\n" % ", ".join(types)
	_class_info.text = text
	# Show the class's starting gear on the character.
	_model.take_off_all()
	_apply_look()
	_dress(_class_kit(id).get("equipment", {}))


func _begin() -> void:
	var look := _look.duplicate()
	GameSession.new_character(_name_edit.text.strip_edges(), _pronouns, look, _class_id)
	GameSession.data["attribute_points"] = _points.duplicate()
	GameSession.save_game()
	_start()
