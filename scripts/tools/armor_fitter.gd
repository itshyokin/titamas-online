extends Node3D
## Armour-fitting editor (Godot toolbar → Fit Armor, or open scenes/tools/armor_fitter.tscn
## and press F6). Shows the masc and femme bodies side by side wearing the chosen item.
## For rigid parts (helmets, shoulder plates, shields, weapons) pick a body and a part,
## then move/turn/scale it until it fits; each body type keeps its own fit. Saves into
## data/items.json ("fit"), which the game and the Database editor read.
##
## Mouse: hold right button to turn the view, wheel to zoom. Keys: arrows move the part
## left/right and forward/back, Page Up/Down up and down (hold Shift for bigger steps).

const BODIES_SCENE := "res://assets/models/characters/base_bodies.glb"
const CHARACTER_SCRIPT := "res://scripts/player/character_model.gd"
const POSES := ["rest (T-pose)", "idle", "idle_armed", "walking", "running", "attack_light_1", "attack_heavy", "block", "bow_aim", "cast_channel"]

var data: Dictionary = {}  # items.json
var item_index := -1
var body := "masc"
var part := 0

var _models := {}  # "masc"/"femme" -> CharacterModel
var _camera: Camera3D
var _yaw := 0.0
var _pitch := -10.0
var _distance := 3.6
var _orbiting := false

var _items: ItemList
var _body_buttons := {}
var _part_select: OptionButton
var _model_edit: LineEdit
var _bone_select: OptionButton
var _grip: CheckBox
var _pos: Array[SpinBox] = []
var _rot: Array[SpinBox] = []
var _scale: SpinBox
var _pose: OptionButton
var _status: Label
var _info: Label
var _updating := false
var _dirty := false
var _marker: MeshInstance3D


func _ready() -> void:
	data = DataFiles.read(DataFiles.ITEMS)
	if not data is Dictionary:
		data = {"items": []}
	_build_world()
	_build_ui()
	_fill_items()
	if _items.item_count > 0:
		_items.select(0)
		_select_item(0)


# --- World ----------------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.22, 0.27)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.8)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.34, 0.38)
	plane.material = fm
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	for key in ["masc", "femme"]:
		var model := (load(BODIES_SCENE) as PackedScene).instantiate() as Node3D
		model.set_script(load(CHARACTER_SCRIPT))
		model.set("body_type", 1 if key == "femme" else 0)
		model.position = Vector3(-0.75 if key == "masc" else 0.75, 0, 0)
		model.rotation_degrees.y = 180.0  # face the camera
		add_child(model)
		_models[key] = model
	_camera = Camera3D.new()
	add_child(_camera)
	_marker = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.02
	m.height = 0.04
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1, 0.3, 0.9)
	mm.no_depth_test = true
	m.material = mm
	_marker.mesh = m
	add_child(_marker)
	_update_camera()


func _update_camera() -> void:
	var target := Vector3(0, 1.0, 0)
	var dir := Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0)) * Vector3(0, 0, 1)
	_camera.global_position = target + dir * _distance
	_camera.look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_distance = maxf(_distance - 0.25, 0.8)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_distance = minf(_distance + 0.25, 8.0)
			_update_camera()
	elif event is InputEventMouseMotion and _orbiting:
		_yaw -= event.relative.x * 0.3
		_pitch = clampf(_pitch - event.relative.y * 0.3, -80, 60)
		_update_camera()
	elif event is InputEventKey and event.pressed:
		var step := 0.025 if event.shift_pressed else 0.005
		var move := Vector3.ZERO
		match event.keycode:
			KEY_LEFT: move.x = -step
			KEY_RIGHT: move.x = step
			KEY_UP: move.z = -step
			KEY_DOWN: move.z = step
			KEY_PAGEUP: move.y = step
			KEY_PAGEDOWN: move.y = -step
		if move != Vector3.ZERO:
			for i in 3:
				_pos[i].value += move[i]
			get_viewport().set_input_as_handled()


# --- UI ----------------------------------------------------------------------------

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var left := _panel(Vector2(12, 12), Vector2(250, 0), ui)
	left.add_child(_heading("Items"))
	_items = ItemList.new()
	_items.custom_minimum_size = Vector2(230, 420)
	_items.item_selected.connect(_select_item)
	left.add_child(_items)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.custom_minimum_size = Vector2(230, 0)
	_info.add_theme_font_size_override("font_size", 12)
	left.add_child(_info)

	var right := _panel(Vector2(-372, 12), Vector2(360, 0), ui, true)
	right.add_child(_heading("Fit"))
	var bodies := HBoxContainer.new()
	var group := ButtonGroup.new()
	for key in ["masc", "femme"]:
		var b := Button.new()
		b.text = key.capitalize()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = key == body
		b.pressed.connect(func() -> void: body = key; part = 0; _load_part())
		bodies.add_child(b)
		_body_buttons[key] = b
	right.add_child(_row("Body", bodies))
	var parts := HBoxContainer.new()
	_part_select = OptionButton.new()
	_part_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_part_select.item_selected.connect(func(i: int) -> void: part = i; _load_part())
	parts.add_child(_part_select)
	var add := Button.new()
	add.text = "+"
	add.tooltip_text = "Add another part (e.g. the second shoulder plate)"
	add.pressed.connect(_add_part)
	parts.add_child(add)
	var remove := Button.new()
	remove.text = "–"
	remove.tooltip_text = "Remove this part"
	remove.pressed.connect(_remove_part)
	parts.add_child(remove)
	right.add_child(_row("Part", parts))
	_model_edit = LineEdit.new()
	_model_edit.placeholder_text = "builtin:helm or res://…glb (empty = item's model)"
	_model_edit.text_submitted.connect(func(_t: String) -> void: _store())
	_model_edit.focus_exited.connect(_store)
	right.add_child(_row("Model", _model_edit))
	_bone_select = OptionButton.new()
	_bone_select.item_selected.connect(func(_i: int) -> void: _store())
	var bone_row := HBoxContainer.new()
	_bone_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bone_row.add_child(_bone_select)
	var nearest := Button.new()
	nearest.text = "Nearest"
	nearest.tooltip_text = "Attach to the bone closest to where the part is now"
	nearest.pressed.connect(_snap_to_nearest_bone)
	bone_row.add_child(nearest)
	right.add_child(_row("Bone", bone_row))
	_grip = CheckBox.new()
	_grip.text = "Held in the hand's grip (weapons)"
	_grip.toggled.connect(func(_on: bool) -> void: _store())
	right.add_child(_grip)
	right.add_child(_row("Position", _vec_row(_pos, 0.001, -3.0, 3.0)))
	right.add_child(_row("Rotation", _vec_row(_rot, 1.0, -360.0, 360.0)))
	_scale = SpinBox.new()
	_scale.step = 0.01
	_scale.min_value = 0.05
	_scale.max_value = 10.0
	_scale.value_changed.connect(func(_v: float) -> void: _store())
	right.add_child(_row("Scale", _scale))
	var copy := Button.new()
	copy.text = "Copy this fit to the other body"
	copy.pressed.connect(_copy_to_other)
	right.add_child(copy)
	_pose = OptionButton.new()
	for p in POSES:
		_pose.add_item(p)
	_pose.item_selected.connect(_set_pose)
	right.add_child(_row("Pose", _pose))
	var save := Button.new()
	save.text = "Save fits"
	save.pressed.connect(_save)
	right.add_child(save)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	right.add_child(_status)
	var help := Label.new()
	help.text = "Right mouse: turn view · wheel: zoom\nArrows / Page Up / Page Down: move the part (Shift = bigger steps)\nPosition and rotation are on the body standing in its rest pose."
	help.add_theme_font_size_override("font_size", 11)
	help.modulate = Color(1, 1, 1, 0.65)
	right.add_child(help)
	_set_pose(0)


func _panel(pos: Vector2, min_size: Vector2, parent: Node, from_right := false) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.075, 0.1, 0.92)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	if from_right:
		p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.position = pos
	p.custom_minimum_size = min_size
	parent.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	return v


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	return l


func _row(label: String, control: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(70, 0)
	r.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(control)
	return r


func _vec_row(store: Array[SpinBox], step: float, lo: float, hi: float) -> HBoxContainer:
	var r := HBoxContainer.new()
	for i in 3:
		var sb := SpinBox.new()
		sb.step = step
		sb.min_value = lo
		sb.max_value = hi
		sb.custom_minimum_size = Vector2(88, 0)
		sb.prefix = ["x", "y", "z"][i]
		sb.value_changed.connect(func(_v: float) -> void: _store())
		r.add_child(sb)
		store.append(sb)
	return r


# --- Items and parts ---------------------------------------------------------------

func _fill_items() -> void:
	_items.clear()
	for d: Dictionary in data.items:
		if String(d.get("slot", "")).is_empty():
			continue
		_items.add_item("%s  (%s)" % [d.get("name", d.id), d.get("slot", "")])
		_items.set_item_metadata(_items.item_count - 1, data.items.find(d))


func _select_item(list_index: int) -> void:
	item_index = int(_items.get_item_metadata(list_index))
	part = 0
	var d := _item()
	var notes := "Slot: %s" % d.get("slot", "")
	if not String(d.get("fitted_masc", "")).is_empty():
		notes += "\nFitted (skinned) model: shaped in Blender, nothing to fit here. Rigid extras can be added with +."
	_info.text = notes
	_load_part()


func _item() -> Dictionary:
	return data.items[item_index] if item_index >= 0 and item_index < data.items.size() else {}


func _parts() -> Array:
	var d := _item()
	if not d.has("fit") or not d.fit is Dictionary:
		d.fit = {"masc": [], "femme": []}
	if not d.fit.has(body):
		d.fit[body] = []
	return d.fit[body]


func _add_part() -> void:
	var parts := _parts()
	parts.append({"bone": "mixamorig_Hips", "position": [0, 1.0, 0], "rotation": [0, 0, 0], "scale": 1.0})
	part = parts.size() - 1
	_dirty = true
	_load_part()


func _remove_part() -> void:
	var parts := _parts()
	if part < parts.size():
		parts.remove_at(part)
		part = maxi(part - 1, 0)
		_dirty = true
	_load_part()


## Shows the current part's values in the controls and refreshes the preview.
func _load_part() -> void:
	_updating = true
	for key in _body_buttons:
		_body_buttons[key].button_pressed = key == body
	var parts := _parts()
	_part_select.clear()
	for i in parts.size():
		_part_select.add_item("%d: %s" % [i + 1, String(parts[i].get("bone", "")).trim_prefix("mixamorig_")])
	var has := part < parts.size()
	for c in [_model_edit, _bone_select, _grip, _scale] + _pos + _rot:
		if c is SpinBox or c is LineEdit:
			c.set("editable", has)
		else:
			c.set("disabled", not has)
	_fill_bones()
	if has:
		_part_select.select(part)
		var att: Dictionary = parts[part]
		_model_edit.text = String(att.get("model", ""))
		_select_bone(String(att.get("bone", "")))
		_grip.button_pressed = bool(att.get("grip", false))
		var p: Array = att.get("position", [0, 0, 0])
		var r: Array = att.get("rotation", [0, 0, 0])
		for i in 3:
			_pos[i].value = float(p[i])
			_rot[i].value = float(r[i])
		_scale.value = float(att.get("scale", 1.0))
	_updating = false
	_preview()


func _fill_bones() -> void:
	if _bone_select.item_count > 0:
		return
	var skel: Skeleton3D = _models.masc.get_skeleton()
	for i in skel.get_bone_count():
		_bone_select.add_item(skel.get_bone_name(i).trim_prefix("mixamorig_"))
		_bone_select.set_item_metadata(i, skel.get_bone_name(i))


func _select_bone(bone: String) -> void:
	for i in _bone_select.item_count:
		if _bone_select.get_item_metadata(i) == bone:
			_bone_select.select(i)
			return


## Copies the controls into the current part and refreshes the preview.
func _store() -> void:
	if _updating:
		return
	var parts := _parts()
	if part >= parts.size():
		return
	var att: Dictionary = parts[part]
	if _model_edit.text.strip_edges().is_empty():
		att.erase("model")
	else:
		att["model"] = _model_edit.text.strip_edges()
	att["bone"] = String(_bone_select.get_item_metadata(_bone_select.selected)) if _bone_select.selected >= 0 else "mixamorig_Hips"
	if _grip.button_pressed:
		att["grip"] = true
	else:
		att.erase("grip")
	att["position"] = [snappedf(_pos[0].value, 0.001), snappedf(_pos[1].value, 0.001), snappedf(_pos[2].value, 0.001)]
	att["rotation"] = [snappedf(_rot[0].value, 0.1), snappedf(_rot[1].value, 0.1), snappedf(_rot[2].value, 0.1)]
	att["scale"] = snappedf(_scale.value, 0.001)
	_dirty = true
	_status.text = "Unsaved changes"
	_part_select.set_item_text(part, "%d: %s" % [part + 1, String(att.bone).trim_prefix("mixamorig_")])
	_preview()


func _preview() -> void:
	var d := _item()
	for key in _models:
		var model: CharacterModel = _models[key]
		model.take_off_all()
		if not d.is_empty():
			model.wear(d, "preview")
	_update_marker.call_deferred()


func _update_marker() -> void:
	var parts := _parts()
	_marker.visible = part < parts.size()
	if not _marker.visible:
		return
	var att: Dictionary = parts[part]
	var model: CharacterModel = _models[body]
	var skel := model.get_skeleton()
	var bone := skel.find_bone(String(att.get("bone", "")))
	if bone >= 0:
		_marker.global_position = skel.global_transform * skel.get_bone_global_pose(bone).origin


func _snap_to_nearest_bone() -> void:
	var parts := _parts()
	if part >= parts.size():
		return
	var model: CharacterModel = _models[body]
	var p: Array = parts[part].get("position", [0, 0, 0])
	var at := Vector3(p[0], p[1], p[2])
	var skel := model.get_skeleton()
	var best := -1
	var best_d := INF
	for i in skel.get_bone_count():
		var d := model.bone_rest_position(skel.get_bone_name(i)).distance_to(at)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		_select_bone(skel.get_bone_name(best))
		_store()
		_status.text = "Attached to %s" % skel.get_bone_name(best).trim_prefix("mixamorig_")


func _copy_to_other() -> void:
	var d := _item()
	var other := "femme" if body == "masc" else "masc"
	d.fit[other] = _parts().duplicate(true)
	_dirty = true
	_status.text = "Copied to %s (unsaved)" % other
	_preview()


func _set_pose(i: int) -> void:
	for key in _models:
		var model: CharacterModel = _models[key]
		if i == 0:
			model.show_rest_pose()
		else:
			model.set_speed(1.0)
			model.play(POSES[i], 0.2)
	_update_marker.call_deferred()


func _save() -> void:
	DataFiles.write(DataFiles.ITEMS, data)
	_dirty = false
	_status.text = "Saved to data/items.json. A running game picks it up within a second."


func _process(_delta: float) -> void:
	if _pose and _pose.selected != 0:
		_update_marker()
