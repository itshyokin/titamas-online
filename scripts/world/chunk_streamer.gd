@tool
class_name ChunkStreamer
extends Node3D
## Loads terrain chunks around the player and unloads distant ones.
## Streaming is spread out so walking never stutters: chunk files and the prop models they
## need load on a background thread, one chunk is added per frame, and its props are put
## down a few per frame (world.json performance props_per_frame). Props fade out by size
## with distance and each chunk gets a ground occluder (see WorldPerf).
## Chunks are files named chunk_I_J.glb in chunk_dir; chunk_I_J is placed at
## (I * chunk_size, 0, J * chunk_size), matching the Blender terrain add-on.

@export_dir var chunk_dir := "res://assets/levels/overworld"
@export var chunk_size := 64.0
## Chunks within this many cells of the player's cell are loaded.
@export var load_radius := 2
## Extra cells kept loaded before unloading, so walking along a border doesn't thrash.
@export var unload_margin := 1
@export var target_path: NodePath
## Drop the target onto the ground once the first chunks are in.
@export var snap_target_to_ground := true
## Used for chunks exported without a material.
@export var default_material: Material
## Shared materials, matched by name: a Blender material called "grass" on a chunk is
## replaced by <material_dir>/grass.tres. Keeps one copy of each texture for the whole
## world, and lets materials be tuned in Godot.
@export_dir var material_dir := "res://assets/materials/terrain"
## Prop models (<name>.glb). Placements come from chunk_I_J.props.json next to each chunk.
@export_dir var prop_dir := "res://assets/props"
## Show every chunk (with props and water) in the editor, so the world can be seen while
## tuning lights, fog and sky. Nothing from the preview is saved into the scene.
## Toggle off and on to reload after copying in new exports.
@export var editor_preview := true:
	set(value):
		editor_preview = value
		if Engine.is_editor_hint() and is_inside_tree():
			_refresh_editor_preview()

var _shared_materials := {}  # name -> Material (or null if none)
var _props: PropLibrary
const WATER_MATERIAL := preload("res://assets/materials/water.tres")
## How deep the swimmable box under a Blender water plane reaches.
const WATER_PLANE_DEPTH := 30.0
## Terrain vertex spacing (m), matching the Blender add-on.
const PAINT_SPACING := 2.0

var _paint := {}  # Vector2i -> PackedVector2Array of (dirt, cliff) per terrain vertex
var _heights := {}  # Vector2i -> PackedFloat32Array of terrain heights (same grid)
var _water_rects := {}  # Vector2i -> Array of [Rect2 (world XZ), surface height]
var _grass := {}  # Vector2i -> GrassField
## Grass grows on chunks this many cells from the player's.
@export var grass_radius := 1
## Fallback grass density (clumps per m²) when no AtmosphereManager is found.
@export var grass_density := 1.0
## Grass tiles (16 m squares) grown per frame.
@export var grass_tiles_per_frame := 2
var _available := {}  # Vector2i -> path
var _loaded := {}  # Vector2i -> Node3D
var _pending := {}  # Vector2i -> path
var _prop_lists := {}  # Vector2i -> Array of prop entries (read when the chunk is requested)
var _prop_queue: Array = []  # [cell, entry] still to place
var _last_center := Vector2i(1 << 30, 1 << 30)
var _grass_settled := false
var _target: Node3D


func _ready() -> void:
	add_to_group("chunk_streamer")
	_props = PropLibrary.new(prop_dir)
	if Engine.is_editor_hint():
		_refresh_editor_preview()
		return
	_target = get_node_or_null(target_path) as Node3D
	var settings := get_node_or_null("/root/GameSettings")
	if settings:
		settings.connect("graphics_changed", refresh_grass)
		settings.connect("graphics_changed", refresh_prop_ranges)
	_scan_chunks()
	if _target == null:
		push_warning("ChunkStreamer: no target; loading every chunk")
		for cell in _available:
			_add_chunk(cell, load(_available[cell]))
		return
	# Load the starting area immediately so the player has ground under them.
	for cell in _cells_around(_cell_of(_target.global_position), load_radius):
		if _available.has(cell):
			_add_chunk(cell, load(_available[cell]))
	if snap_target_to_ground:
		_snap_to_ground.call_deferred()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _target == null:
		return
	var center := _cell_of(_target.global_position)
	if center != _last_center:
		_last_center = center
		_grass_settled = false
		for cell in _cells_around(center, load_radius):
			if _available.has(cell) and not _loaded.has(cell) and not _pending.has(cell):
				_pending[cell] = _available[cell]
				ResourceLoader.load_threaded_request(_available[cell])
				# Its prop models load alongside, so placing them later costs nothing.
				_prop_lists[cell] = _read_prop_list(cell)
				for entry in _prop_lists[cell]:
					_props.request(String(entry.name))
		var keep := load_radius + unload_margin
		for cell in _loaded.keys():
			if absi(cell.x - center.x) > keep or absi(cell.y - center.y) > keep:
				_loaded[cell].queue_free()
				_loaded.erase(cell)
				_paint.erase(cell)
				_heights.erase(cell)
				_water_rects.erase(cell)
				_grass.erase(cell)

	# One finished chunk goes in per frame, nearest first.
	if not _pending.is_empty():
		var best := Vector2i.ZERO
		var best_d := INF
		for cell: Vector2i in _pending.keys():
			var status := ResourceLoader.load_threaded_get_status(_pending[cell])
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				var d := float((cell - center).length_squared())
				if d < best_d:
					best_d = d
					best = cell
			elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_error("ChunkStreamer: failed to load %s" % _pending[cell])
				_available.erase(cell)
				_pending.erase(cell)
				_prop_lists.erase(cell)
		if best_d < INF:
			_add_chunk(best, ResourceLoader.load_threaded_get(_pending[best]), false)
			_pending.erase(best)
			_grass_settled = false
	_place_queued_props()
	if not _grass_settled:
		_update_grass(center)


## Puts down a few of the props waiting for their chunk (and their model) each frame.
func _place_queued_props() -> void:
	if _prop_queue.is_empty():
		return
	var budget := maxi(int(WorldPerf.settings().props_per_frame), 1)
	var i := 0
	while i < _prop_queue.size() and budget > 0:
		var cell: Vector2i = _prop_queue[i][0]
		var entry = _prop_queue[i][1]
		if not _loaded.has(cell):
			_prop_queue.remove_at(i)  # the chunk went away again
			continue
		if not _props.is_ready(String(entry.name)):
			i += 1  # its model is still loading
			continue
		_place_prop(_loaded[cell].get_node("Props"), entry)
		_prop_queue.remove_at(i)
		budget -= 1


func _refresh_editor_preview() -> void:
	for cell in _loaded:
		if is_instance_valid(_loaded[cell]):
			_loaded[cell].queue_free()
	_loaded.clear()
	_paint.clear()
	_heights.clear()
	_water_rects.clear()
	_grass.clear()
	_available.clear()
	_shared_materials.clear()
	_props = PropLibrary.new(prop_dir)
	if not editor_preview:
		return
	_scan_chunks()
	for cell in _available:
		_add_chunk(cell, load(_available[cell]))


func get_loaded_cells() -> Array:
	return _loaded.keys()


## Horizontal distance (m) from a point to the nearest chunk that exists (land).
## 0 inside a chunk. Used for ocean fatigue.
func distance_to_land(point: Vector3) -> float:
	var best := INF
	var half := chunk_size * 0.5
	for cell: Vector2i in _available:
		var dx := maxf(absf(point.x - cell.x * chunk_size) - half, 0.0)
		var dz := maxf(absf(point.z - cell.y * chunk_size) - half, 0.0)
		best = minf(best, Vector2(dx, dz).length())
		if best == 0.0:
			break
	return best


## Ground paint under a point as (dirt, cliff), each 0..1; grass is what's left.
## Read from the terrain's paint layer (second UV map), nearest vertex. (0, 0) if unknown.
func paint_at(point: Vector3) -> Vector2:
	var cell := _cell_of(point)
	var grid: PackedVector2Array = _paint.get(cell, PackedVector2Array())
	if grid.is_empty():
		return Vector2.ZERO
	var n := _paint_grid_size()
	var half := chunk_size * 0.5
	var gx := clampi(roundi((point.x - cell.x * chunk_size + half) / PAINT_SPACING), 0, n - 1)
	var gz := clampi(roundi((point.z - cell.y * chunk_size + half) / PAINT_SPACING), 0, n - 1)
	return grid[gz * n + gx]


## Grows grass on the chunks near the player (one chunk per frame) and removes it further away.
func _update_grass(center: Vector2i) -> void:
	for cell: Vector2i in _grass.keys():
		if absi(cell.x - center.x) > grass_radius + 1 or absi(cell.y - center.y) > grass_radius + 1:
			if is_instance_valid(_grass[cell]):
				_grass[cell].queue_free()
			_grass.erase(cell)
	for cell in _cells_around(center, grass_radius):
		if _loaded.has(cell) and not _grass.has(cell) and _heights.has(cell):
			var field := GrassField.create(cell, chunk_size, PAINT_SPACING, _heights[cell], _paint.get(cell, PackedVector2Array()),
				_water_rects.get(cell, []), _sea_level(), _grass_density_at(cell))
			_loaded[cell].add_child(field)
			_grass[cell] = field
	# Grow a few tiles per frame, nearest chunk first, so streaming never stutters.
	var budget := grass_tiles_per_frame
	var order := _cells_around(center, grass_radius)
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - center).length_squared() < (b - center).length_squared())
	var waiting := false
	for cell in order:
		var field: GrassField = _grass.get(cell)
		if field == null and _available.has(cell):
			waiting = true  # its chunk isn't in yet
		while budget > 0 and field and is_instance_valid(field) and field.build_next():
			budget -= 1
		if budget <= 0:
			return
	# Everything near is grown: nothing more to do until the player changes cell.
	_grass_settled = not waiting


## Rebuilds all grass (after the grass setting changes).
func refresh_grass() -> void:
	for cell: Vector2i in _grass:
		if is_instance_valid(_grass[cell]):
			_grass[cell].queue_free()
	_grass.clear()
	_grass_settled = false


## Draw distances again for every placed prop (the View distance setting changed).
func refresh_prop_ranges() -> void:
	for cell: Vector2i in _loaded:
		var holder := (_loaded[cell] as Node).get_node_or_null("Props")
		if holder:
			for prop in holder.get_children():
				_apply_range(prop as Node3D)


func _sea_level() -> float:
	var ocean := get_tree().get_first_node_in_group("ocean")
	return ocean.surface_height() if ocean else -INF


func _grass_density_at(cell: Vector2i) -> float:
	var density := grass_density
	var atmosphere := get_tree().get_first_node_in_group("atmosphere")
	if atmosphere:
		var region: RegionAtmosphere = atmosphere.region_at(Vector3(cell.x * chunk_size, 0, cell.y * chunk_size))
		if region:
			density = region.grass_density
	var settings := get_node_or_null("/root/GameSettings")
	if settings:
		density *= float(settings.call("grass_multiplier"))
	return density


func _paint_grid_size() -> int:
	return int(round(chunk_size / PAINT_SPACING)) + 1


## Collects each terrain vertex's paint (for paint_at() and grass) and height (for grass)
## into grids. Painted surfaces (second UV map) are the terrain; without paint, every
## mesh in the chunk counts as ground. Returns [paint (empty if unpainted), heights].
func _read_terrain(chunk: Node3D) -> Array:
	var n := _paint_grid_size()
	var paint := PackedVector2Array()
	paint.resize(n * n)
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	heights.fill(-INF)
	var found := false
	var half := chunk_size * 0.5
	for pass_index in 2:
		for node in chunk.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if String(mi.name).ends_with("-water") or mi.mesh == null or mi.get_parent().name == "Props":
				continue
			if _is_prop(mi, chunk):
				continue
			# Transform relative to the chunk (it isn't in the tree yet).
			var xf := Transform3D.IDENTITY
			var walk: Node = mi
			while walk != chunk and walk is Node3D:
				xf = (walk as Node3D).transform * xf
				walk = walk.get_parent()
			for s in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(s)
				var uv2 = arrays[Mesh.ARRAY_TEX_UV2]
				var painted: bool = uv2 != null and not (uv2 as PackedVector2Array).is_empty()
				if pass_index == 0 and not painted:
					continue
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for i in verts.size():
					var p := xf * verts[i]
					var gx := roundi((p.x + half) / PAINT_SPACING)
					var gz := roundi((p.z + half) / PAINT_SPACING)
					if gx >= 0 and gx < n and gz >= 0 and gz < n:
						var k := gz * n + gx
						if painted:
							paint[k] = uv2[i]
						heights[k] = maxf(heights[k], p.y)
						found = true
		if found:
			break
	if not found:
		return [PackedVector2Array(), PackedFloat32Array()]
	# Holes (no vertex landed there): borrow a neighbour's height.
	for k in heights.size():
		if heights[k] == -INF:
			heights[k] = heights[k - 1] if k > 0 and heights[k - 1] != -INF else 0.0
	var any_paint := false
	for v in paint:
		if v != Vector2.ZERO:
			any_paint = true
			break
	return [paint if any_paint else PackedVector2Array(), heights]


func _is_prop(node: Node, chunk: Node) -> bool:
	var n := node.get_parent()
	while n and n != chunk:
		if n.name == "Props":
			return true
		n = n.get_parent()
	return false


## Horizontal distance (m) from a point to open sea (the nearest spot with no chunk).
## 0 when already over the sea. Looks a few chunks around; INF if the sea is further.
func distance_to_sea(point: Vector3) -> float:
	var center := _cell_of(point)
	var best := INF
	var half := chunk_size * 0.5
	for cell in _cells_around(center, 3):
		if _available.has(cell):
			continue
		var dx := maxf(absf(point.x - cell.x * chunk_size) - half, 0.0)
		var dz := maxf(absf(point.z - cell.y * chunk_size) - half, 0.0)
		best = minf(best, Vector2(dx, dz).length())
	return best


func _scan_chunks() -> void:
	var regex := RegEx.create_from_string("^chunk_(-?\\d+)_(-?\\d+)\\.glb$")
	for file in ResourceLoader.list_directory(chunk_dir):
		var m := regex.search(file)
		if m:
			var cell := Vector2i(m.get_string(1).to_int(), m.get_string(2).to_int())
			_available[cell] = chunk_dir.path_join(file)
	if _available.is_empty():
		push_warning("ChunkStreamer: no chunk_I_J.glb files in %s" % chunk_dir)


## `props_now`: put every prop down at once (start of the level, the editor preview);
## otherwise they are queued and placed a few per frame.
func _add_chunk(cell: Vector2i, scene: PackedScene, props_now := true) -> void:
	if scene == null or _loaded.has(cell):
		return
	var chunk := scene.instantiate() as Node3D
	chunk.name = "chunk_%d_%d" % [cell.x, cell.y]
	chunk.position = Vector3(cell.x * chunk_size, 0, cell.y * chunk_size)
	for mesh in chunk.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if String(mi.name).ends_with("-water"):
			_make_water(mi, cell, chunk)
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			# Material-less glTF meshes get an unnamed default material on import
			# (fully metallic, renders white), so treat that as "no material" too.
			if mat == null or mat.resource_name.is_empty():
				if default_material:
					mi.set_surface_override_material(s, default_material)
				continue
			var shared := _shared_material(mat.resource_name)
			if shared:
				mi.set_surface_override_material(s, shared)
	_place_props(cell, chunk, props_now)
	if not Engine.is_editor_hint():
		var terrain := _read_terrain(chunk)
		_paint[cell] = terrain[0]
		_heights[cell] = terrain[1]
		var occluder := WorldPerf.make_occluder(terrain[1], _paint_grid_size(), PAINT_SPACING, chunk_size)
		if occluder:
			chunk.add_child(occluder)
	add_child(chunk)
	_loaded[cell] = chunk


## Places the props listed in chunk_I_J.props.json (written by the Blender add-on) and
## chunk_I_J.painted.json (the Prop Painter in the editor; kept separate so a new Blender
## export never wipes what was painted).
func _place_props(cell: Vector2i, chunk: Node3D, now := true) -> void:
	var holder := Node3D.new()
	holder.name = "Props"
	chunk.add_child(holder)
	var list: Array = _prop_lists[cell] if _prop_lists.has(cell) else _read_prop_list(cell)
	_prop_lists.erase(cell)
	for entry in list:
		if now:
			_place_prop(holder, entry)
		else:
			_prop_queue.append([cell, entry])


## The entries of chunk_I_J.props.json and chunk_I_J.painted.json ({name, pos, basis}).
func _read_prop_list(cell: Vector2i) -> Array:
	var out := []
	for suffix in [".props.json", ".painted.json"]:
		var path: String = String(_available[cell]).get_basename() + suffix
		if not FileAccess.file_exists(path):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary or not data.has("props"):
			push_warning("ChunkStreamer: couldn't read %s" % path)
			continue
		out.append_array(data.props)
	return out


func _place_prop(holder: Node3D, entry) -> void:
	var prop := _props.instantiate(entry.name)
	if prop == null:
		return
	var c: Array = entry.basis
	var basis := Basis(Vector3(c[0][0], c[0][1], c[0][2]), Vector3(c[1][0], c[1][1], c[1][2]), Vector3(c[2][0], c[2][1], c[2][2]))
	prop.transform = Transform3D(basis, Vector3(entry.pos[0], entry.pos[1], entry.pos[2]))
	if not Engine.is_editor_hint():
		_apply_range(prop)
		# Blender custom properties show_switch / hide_switch: there only while a switch says so.
		var show_on := String(entry.get("show_switch", "")) if entry is Dictionary else ""
		var hide_on := String(entry.get("hide_switch", "")) if entry is Dictionary else ""
		if show_on != "" or hide_on != "":
			prop.add_child(SwitchGate.new(show_on, hide_on))
	holder.add_child(prop)


## Small props stop being drawn sooner than big ones (WorldPerf.prop_range).
func _apply_range(prop: Node3D) -> void:
	if prop == null or not prop.has_meta("prop_name"):
		return
	var scale_now := prop.transform.basis.get_scale()
	var size := _props.size_of(String(prop.get_meta("prop_name"))) * maxf(scale_now.x, maxf(scale_now.y, scale_now.z))
	WorldPerf.apply_prop_range(prop, size)


## A Blender water plane (object named "<name>-water"): give it the water look and a
## swimmable volume beneath its surface.
func _make_water(mi: MeshInstance3D, cell: Vector2i, chunk: Node3D) -> void:
	mi.material_override = WATER_MATERIAL
	# Remember where it is (world XZ rectangle and surface height) so grass stays out.
	var xf := Transform3D.IDENTITY
	var walk: Node = mi
	while walk != chunk and walk is Node3D:
		xf = (walk as Node3D).transform * xf
		walk = walk.get_parent()
	var world_box := (chunk.transform * xf) * mi.get_aabb()
	if not _water_rects.has(cell):
		_water_rects[cell] = []
	_water_rects[cell].append([Rect2(world_box.position.x, world_box.position.z, world_box.size.x, world_box.size.z), world_box.end.y])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := mi.get_aabb()
	var volume := WaterVolume.new()
	volume.show_surface = false
	volume.size = Vector3(box.size.x, WATER_PLANE_DEPTH, box.size.z)
	var top := box.position.y + box.size.y
	volume.position = Vector3(box.get_center().x, top - WATER_PLANE_DEPTH * 0.5, box.get_center().z)
	mi.add_child(volume)


func _shared_material(mat_name: String) -> Material:
	if not _shared_materials.has(mat_name):
		var path := material_dir.path_join(mat_name + ".tres")
		_shared_materials[mat_name] = load(path) if ResourceLoader.exists(path) else null
	return _shared_materials[mat_name]


func _cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / chunk_size), roundi(pos.z / chunk_size))


func _cells_around(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			cells.append(Vector2i(x, y))
	return cells


func _snap_to_ground() -> void:
	await get_tree().physics_frame
	var from := _target.global_position + Vector3.UP * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 400.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		_target.global_position = hit.position + Vector3.UP * 0.05
