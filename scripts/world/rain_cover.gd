class_name RainCover
extends Node
## The cover map (a child of Weather): for a square around the camera, how high the
## highest solid thing is at each spot. It is found with rays straight down against the
## world (ground, roofs, overhangs: physics layer 1) and water (layer 4), plus the tops of
## indoors SafeArea boxes and the sea. Shaders read it through
## assets/materials/rain_cover.gdshaderinc: rain streaks aren't drawn below it (so from
## indoors you still see rain outside the door), splashes sit on it, and the terrain only
## looks wet where nothing is over it.
##
## The map has a second layer for snow on the ground: the same heights, raised to the tops
## of trees within their canopies (props named *tree*, not *dead*; `canopy_cover`), so
## snow doesn't lie and grass doesn't frost under trees while rain still falls through.
##
## 64 x 64 cells of `cell` metres. The texture wraps: a world cell always lives in the
## same texel, so walking only costs rays for the row of cells that came into view.
## The rest is checked again a few cells per frame (doors, chunks streaming in).
## Settings: weather.json "indoors" cover_map / cover_cell / cover_refresh.

const CELLS := 64
const NONE := -100000.0
## Most new cells looked up in one frame (after a teleport the map fills over a few frames).
const BURST := 768

var cell := 0.75
var refresh_per_frame := 160
var active := false

var _heights := PackedFloat32Array()  # two per cell: solid cover, cover with tree canopies
var _canopies: Array = []  # [x, z, radius, top] of trees near the window
var _canopy_check := 0.0
var _use_canopies := true
var _image: Image
var _texture: ImageTexture
var _min := Vector2i(1 << 30, 1 << 30)  # lowest world cell in the window
var _pending: Array[Vector2i] = []
var _cursor := 0
var _query: PhysicsRayQueryParameters3D
var _dirty := false


func _ready() -> void:
	_heights.resize(CELLS * CELLS * 2)
	_heights.fill(NONE)
	_image = Image.create_from_data(CELLS, CELLS, false, Image.FORMAT_RGF, _heights.to_byte_array())
	_texture = ImageTexture.create_from_image(_image)
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = 1 | 8  # world, water
	_query.collide_with_areas = true  # water volumes
	RenderingServer.global_shader_parameter_set(&"rain_cover", _texture.get_rid())
	_set_window(Vector3.ZERO, false)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"rain_cover_window", Vector4(0, 0, 1, 0))


func texture() -> Texture2D:
	return _texture


## Keeps the map up to date around `centre` (the camera). `on`: something needs it now.
func update(centre: Vector3, world: World3D, on: bool, settings: Dictionary) -> void:
	on = on and bool(settings.get("cover_map", true))
	var new_cell := clampf(float(settings.get("cover_cell", 0.75)), 0.25, 4.0)
	refresh_per_frame = int(settings.get("cover_refresh", 160))
	if not on:
		if active:
			active = false
			_set_window(centre, false)
		return
	if not active or not is_equal_approx(new_cell, cell):
		active = true
		cell = new_cell
		_min = Vector2i(1 << 30, 1 << 30)  # start again
	_use_canopies = bool(settings.get("canopy_cover", true))
	_canopy_check -= get_process_delta_time()
	if _canopy_check <= 0.0:
		_canopy_check = 1.5
		_find_canopies(centre)
	var lowest := Vector2i(floori(centre.x / cell), floori(centre.z / cell)) - Vector2i(CELLS / 2, CELLS / 2)
	_scroll(lowest)
	var space := world.direct_space_state
	var top := centre.y + 120.0
	var bottom := centre.y - 80.0
	var sea := _sea_level()
	# New cells first, then a few old ones again.
	var n := mini(_pending.size(), BURST)
	for i in n:
		var c: Vector2i = _pending[_pending.size() - 1 - i]
		if _in_window(c):
			_look(c, space, top, bottom, sea)
	_pending.resize(_pending.size() - n)
	for i in refresh_per_frame:
		_cursor = (_cursor + 1) % (CELLS * CELLS)
		var sx := _cursor % CELLS
		var sz := _cursor / CELLS
		_look(Vector2i(_min.x + posmod(sx - _min.x, CELLS), _min.y + posmod(sz - _min.y, CELLS)), space, top, bottom, sea)
	if _dirty:
		_dirty = false
		_image.set_data(CELLS, CELLS, false, Image.FORMAT_RGF, _heights.to_byte_array())
		_texture.update(_image)
	_set_window(centre, true)


## The height stored for the cell over `point` (NONE if not looked up). For tests.
func height_at(point: Vector3) -> float:
	var c := Vector2i(floori(point.x / cell), floori(point.z / cell))
	return _heights[_slot(c) * 2] if active and _in_window(c) else NONE


## The same with tree canopies counted (the snow layer).
func canopy_height_at(point: Vector3) -> float:
	var c := Vector2i(floori(point.x / cell), floori(point.z / cell))
	return _heights[_slot(c) * 2 + 1] if active and _in_window(c) else NONE


## Trees whose canopy could reach into the map: [x, z, radius, top], from the placed
## props (worked out once per tree and kept on it).
func _find_canopies(centre: Vector3) -> void:
	_canopies.clear()
	if not _use_canopies:
		return
	var streamer := get_tree().get_first_node_in_group("chunk_streamer")
	if streamer == null:
		return
	var reach := cell * CELLS * 0.5
	for chunk in streamer.get_children():
		var holder := chunk.get_node_or_null("Props")
		if holder == null:
			continue
		for prop in holder.get_children():
			var prop_name := String(prop.get_meta("prop_name", "")).to_lower()
			if not prop_name.contains("tree") or prop_name.contains("dead"):
				continue
			if not prop.has_meta("canopy"):
				prop.set_meta("canopy", _canopy_of(prop as Node3D))
			var c: Array = prop.get_meta("canopy")
			if c.is_empty():
				continue
			if absf(float(c[0]) - centre.x) < reach + float(c[2]) and absf(float(c[1]) - centre.z) < reach + float(c[2]):
				_canopies.append(c)


## [x, z, radius, top] of a tree's leaves, from its meshes' bounds ([] if it has none).
func _canopy_of(prop: Node3D) -> Array:
	var box := AABB()
	var first := true
	for n in prop.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return []
	var centre := box.get_center()
	# Leaves fill most, not all, of the box around a tree.
	return [centre.x, centre.z, maxf(box.size.x, box.size.z) * 0.4, box.end.y]


func _slot(c: Vector2i) -> int:
	return posmod(c.y, CELLS) * CELLS + posmod(c.x, CELLS)


func _in_window(c: Vector2i) -> bool:
	return c.x >= _min.x and c.x < _min.x + CELLS and c.y >= _min.y and c.y < _min.y + CELLS


## The window moved to start at `lowest`: cells that came into it are cleared and queued.
func _scroll(lowest: Vector2i) -> void:
	if lowest == _min:
		return
	var old := _min
	_min = lowest
	if absi(lowest.x - old.x) >= CELLS or absi(lowest.y - old.y) >= CELLS:
		_heights.fill(NONE)
		_pending.clear()
		for z in CELLS:
			for x in CELLS:
				_pending.append(lowest + Vector2i(x, z))
		_dirty = true
		return
	for z in range(lowest.y, lowest.y + CELLS):
		for x in range(lowest.x, lowest.x + CELLS):
			if x >= old.x and x < old.x + CELLS and z >= old.y and z < old.y + CELLS:
				continue  # was already in view
			var c := Vector2i(x, z)
			_heights[_slot(c) * 2] = NONE
			_heights[_slot(c) * 2 + 1] = NONE
			_pending.append(c)
	_dirty = true


func _look(c: Vector2i, space: PhysicsDirectSpaceState3D, top: float, bottom: float, sea: float) -> void:
	var x := (c.x + 0.5) * cell
	var z := (c.y + 0.5) * cell
	_query.from = Vector3(x, top, z)
	_query.to = Vector3(x, bottom, z)
	var hit := space.intersect_ray(_query)
	var h: float = hit.position.y if not hit.is_empty() else NONE
	h = maxf(h, sea)
	if not SafeArea._areas.is_empty():
		h = maxf(h, SafeArea.cover_height(Vector3(x, 0.0, z)))
	var with_trees := h
	for t: Array in _canopies:
		var dx := x - float(t[0])
		var dz := z - float(t[1])
		if dx * dx + dz * dz <= float(t[2]) * float(t[2]):
			with_trees = maxf(with_trees, float(t[3]))
	var slot := _slot(c) * 2
	if not is_equal_approx(_heights[slot], h) or not is_equal_approx(_heights[slot + 1], with_trees):
		_heights[slot] = h
		_heights[slot + 1] = with_trees
		_dirty = true


func _sea_level() -> float:
	var ocean := get_tree().get_first_node_in_group("ocean")
	var level = ocean.get("sea_level") if ocean else null
	return float(level) if level != null else NONE


func _set_window(centre: Vector3, on: bool) -> void:
	RenderingServer.global_shader_parameter_set(&"rain_cover_window", Vector4(centre.x, centre.z, cell * CELLS, 1.0 if on else 0.0))
