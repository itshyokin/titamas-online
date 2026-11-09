@tool
extends EditorPlugin
## Prop Painter (dock on the right, "Props" tab): paint props from assets/props onto the
## terrain chunks shown by the level's ChunkStreamer (its Editor Preview must be on).
##   Turn on "Paint", pick one or more props (each dab picks one of them at random), then
##   click or drag in the 3D view. Shift + click/drag erases props under the brush.
##   Ctrl + mouse wheel changes the brush size. Ctrl+Z undoes a stroke.
## Placements go into chunk_I_J.props.json next to each chunk (the same file the Blender
## add-on writes), so the game places them like any other prop.

const Z_UP := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

var _dock: VBoxContainer
var _paint: CheckButton
var _list: ItemList
var _radius: SpinBox
var _count: SpinBox
var _spacing: SpinBox
var _scale_min: SpinBox
var _scale_max: SpinBox
var _tilt: SpinBox
var _sink: SpinBox
var _status: Label
var _brush: MeshInstance3D
var _b := preload("res://addons/prop_painter/prop_brush.gd").new()
var _last_dab := Vector3.INF
var _painting := false
var _erasing := false


func _enter_tree() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Props"
	_paint = CheckButton.new()
	_paint.text = "Paint props"
	_paint.toggled.connect(func(on: bool) -> void:
		if not on:
			_hide_brush()
		_status.text = "Select the level's ChunkStreamer, then click / drag in the 3D view." if on else "")
	_dock.add_child(_paint)
	var refresh := Button.new()
	refresh.text = "Reload prop list"
	refresh.pressed.connect(_fill_list)
	_dock.add_child(refresh)
	_list = ItemList.new()
	_list.select_mode = ItemList.SELECT_MULTI
	_list.custom_minimum_size = Vector2(0, 220)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock.add_child(_list)
	_radius = _spin("Brush radius (m)", 0.5, 40.0, 4.0, 0.5)
	_count = _spin("Props per dab", 1, 30, 3, 1)
	_spacing = _spin("Dab spacing when dragging (m)", 0.5, 20.0, 3.0, 0.5)
	_scale_min = _spin("Scale from", 0.2, 4.0, 0.85, 0.05)
	_scale_max = _spin("Scale to", 0.2, 4.0, 1.2, 0.05)
	_tilt = _spin("Lean with the slope (0–1)", 0.0, 1.0, 0.0, 0.05)
	_sink = _spin("Sink into the ground (m)", 0.0, 2.0, 0.08, 0.02)
	var help := Label.new()
	help.text = "Click / drag: paint · Shift: erase · Ctrl + wheel: brush size · Ctrl+Z: undo"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.7)
	_dock.add_child(help)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(_status)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_fill_list()


func _exit_tree() -> void:
	_hide_brush()
	remove_control_from_docks(_dock)
	_dock.queue_free()


func _spin(label_text: String, lo: float, hi: float, value: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	row.add_child(s)
	_dock.add_child(row)
	return s


func _fill_list() -> void:
	var picked := _picked()
	_list.clear()
	var names: Array[String] = []
	for f in ResourceLoader.list_directory("res://assets/props"):
		if f.ends_with(".glb"):
			names.append(f.get_basename())
	names.sort()
	for n in names:
		_list.add_item(n)
		if n in picked:
			_list.select(_list.item_count - 1, false)


func _picked() -> Array[String]:
	var out: Array[String] = []
	for i in _list.get_selected_items():
		out.append(_list.get_item_text(i))
	return out


func _handles(object: Object) -> bool:
	return _paint != null and _paint.button_pressed and _streamer() != null


func _streamer() -> Node:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return null
	if root is ChunkStreamer:
		return root
	var found := root.find_children("*", "ChunkStreamer", true, false)
	return found[0] if not found.is_empty() else null


# --- Input -----------------------------------------------------------------------------

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _paint.button_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var streamer := _streamer()
	if streamer == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.ctrl_pressed and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_radius.value *= 1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouse:
		var hit := _b._ray(streamer, camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
		if hit.is_empty():
			_hide_brush()
		else:
			_show_brush(streamer, hit.position, event.shift_pressed)
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if hit.is_empty():
					return EditorPlugin.AFTER_GUI_INPUT_PASS
				_painting = true
				_erasing = event.shift_pressed
				_b.stroke_before.clear()
				_last_dab = Vector3.INF
				_dab(streamer, hit.position)
			else:
				if _painting:
					_end_stroke(streamer)
				_painting = false
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event is InputEventMouseMotion and _painting and not hit.is_empty():
			if hit.position.distance_to(_last_dab) >= (_spacing.value if not _erasing else _radius.value * 0.3):
				_dab(streamer, hit.position)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


# --- Painting ----------------------------------------------------------------------------

func _dab(streamer: Node, at: Vector3) -> void:
	_last_dab = at
	if _erasing:
		_erase(streamer, at)
		return
	var names := _picked()
	if names.is_empty():
		_status.text = "Pick a prop in the list first."
		return
	var placed := 0
	for i in int(_count.value):
		var a := randf() * TAU
		var r := sqrt(randf()) * _radius.value
		var p := at + Vector3(cos(a) * r, 0, sin(a) * r)
		var hit := _b._ray(streamer, p + Vector3.UP * 200.0, Vector3.DOWN)
		if hit.is_empty():
			continue
		var cell := _b._cell_of(streamer, hit.position)
		var chunk := _b._chunk(streamer, cell)
		if chunk == null:
			continue
		var prop_name: String = names[randi() % names.size()]
		var scale := randf_range(_scale_min.value, maxf(_scale_max.value, _scale_min.value))
		var up := Vector3.UP.lerp(hit.normal, _tilt.value).normalized()
		var yaw := Basis(Vector3.UP, randf() * TAU)
		var align := Basis(Quaternion(Vector3.UP, up)) if up.dot(Vector3.UP) < 0.9999 else Basis.IDENTITY
		var basis := (align * yaw * Z_UP).scaled(Vector3.ONE * scale)
		var local_pos: Vector3 = hit.position - chunk.position - up * _sink.value
		_b._add_entry(streamer, cell, chunk, prop_name, local_pos, basis)
		placed += 1
	_status.text = "Placed %d" % placed


func _erase(streamer: Node, at: Vector3) -> void:
	var removed := 0
	for cell: Vector2i in streamer.get("_loaded").keys():
		var chunk := _b._chunk(streamer, cell)
		var data := _b._read(streamer, cell)
		var props: Array = data.get("props", [])
		var keep: Array = []
		for e in props:
			var w := chunk.position + Vector3(e.pos[0], e.pos[1], e.pos[2])
			if Vector2(w.x - at.x, w.z - at.z).length() <= _radius.value:
				removed += 1
			else:
				keep.append(e)
		if keep.size() != props.size():
			data["props"] = keep
			_b._write(streamer, cell, data)
			_b._rebuild_props(streamer, cell, chunk)
	_status.text = "Removed %d" % removed if removed > 0 else _status.text


func _end_stroke(streamer: Node) -> void:
	if _b.stroke_before.is_empty():
		return
	var undo := get_undo_redo()
	undo.create_action("Paint props" if not _erasing else "Erase props")
	for path: String in _b.stroke_before:
		var after := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		undo.add_do_method(self, "_restore", path, after)
		undo.add_undo_method(self, "_restore", path, _b.stroke_before[path])
	undo.commit_action(false)
	_b.stroke_before.clear()


## Undo / redo: puts a props file back and reshows that chunk.
func _restore(path: String, text: String) -> void:
	if text == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	var streamer := _streamer()
	if streamer == null:
		return
	var m := RegEx.create_from_string("chunk_(-?\\d+)_(-?\\d+)\\.props\\.json$").search(path)
	if m:
		var cell := Vector2i(m.get_string(1).to_int(), m.get_string(2).to_int())
		var chunk := _b._chunk(streamer, cell)
		if chunk:
			_b._rebuild_props(streamer, cell, chunk)


# --- Files -------------------------------------------------------------------------------

# --- Terrain hits ------------------------------------------------------------------------

# --- Brush -------------------------------------------------------------------------------

func _show_brush(streamer: Node, at: Vector3, erasing: bool) -> void:
	if _brush == null or not is_instance_valid(_brush):
		_brush = MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.96
		ring.outer_radius = 1.0
		ring.rings = 48
		ring.ring_segments = 3
		_brush.mesh = ring
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_brush.material_override = mat
		streamer.add_child(_brush)  # no owner: never saved
	(_brush.material_override as StandardMaterial3D).albedo_color = Color(1, 0.35, 0.3, 0.9) if erasing else Color(0.4, 1, 0.5, 0.9)
	_brush.global_transform = Transform3D(Basis().scaled(Vector3(_radius.value, 0.3, _radius.value)), at + Vector3.UP * 0.1)
	_brush.visible = true


func _hide_brush() -> void:
	if _brush and is_instance_valid(_brush):
		_brush.queue_free()
	_brush = null
