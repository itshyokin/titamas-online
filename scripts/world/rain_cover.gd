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

var _heights := PackedFloat32Array()
var _image: Image
var _texture: ImageTexture
var _min := Vector2i(1 << 30, 1 << 30)  # lowest world cell in the window
var _pending: Array[Vector2i] = []
var _cursor := 0
var _query: PhysicsRayQueryParameters3D
var _dirty := false


func _ready() -> void:
	_heights.resize(CELLS * CELLS)
	_heights.fill(NONE)
	_image = Image.create_from_data(CELLS, CELLS, false, Image.FORMAT_RF, _heights.to_byte_array())
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
		_image.set_data(CELLS, CELLS, false, Image.FORMAT_RF, _heights.to_byte_array())
		_texture.update(_image)
	_set_window(centre, true)


## The height stored for the cell over `point` (NONE if not looked up). For tests.
func height_at(point: Vector3) -> float:
	var c := Vector2i(floori(point.x / cell), floori(point.z / cell))
	return _heights[_slot(c)] if active and _in_window(c) else NONE


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
			_heights[_slot(c)] = NONE
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
	var slot := _slot(c)
	if not is_equal_approx(_heights[slot], h):
		_heights[slot] = h
		_dirty = true


func _sea_level() -> float:
	var ocean := get_tree().get_first_node_in_group("ocean")
	var level = ocean.get("sea_level") if ocean else null
	return float(level) if level != null else NONE


func _set_window(centre: Vector3, on: bool) -> void:
	RenderingServer.global_shader_parameter_set(&"rain_cover_window", Vector4(centre.x, centre.z, cell * CELLS, 1.0 if on else 0.0))
