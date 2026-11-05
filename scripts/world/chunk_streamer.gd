@tool
class_name ChunkStreamer
extends Node3D
## Loads terrain chunks around the player and unloads distant ones.
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
var _available := {}  # Vector2i -> path
var _loaded := {}  # Vector2i -> Node3D
var _pending := {}  # Vector2i -> path
var _target: Node3D


func _ready() -> void:
	add_to_group("chunk_streamer")
	_props = PropLibrary.new(prop_dir)
	if Engine.is_editor_hint():
		_refresh_editor_preview()
		return
	_target = get_node_or_null(target_path) as Node3D
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

	for cell in _cells_around(center, load_radius):
		if _available.has(cell) and not _loaded.has(cell) and not _pending.has(cell):
			_pending[cell] = _available[cell]
			ResourceLoader.load_threaded_request(_available[cell])

	for cell in _pending.keys():
		var status := ResourceLoader.load_threaded_get_status(_pending[cell])
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_add_chunk(cell, ResourceLoader.load_threaded_get(_pending[cell]))
			_pending.erase(cell)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("ChunkStreamer: failed to load %s" % _pending[cell])
			_available.erase(cell)
			_pending.erase(cell)

	var keep := load_radius + unload_margin
	for cell in _loaded.keys():
		if absi(cell.x - center.x) > keep or absi(cell.y - center.y) > keep:
			_loaded[cell].queue_free()
			_loaded.erase(cell)
			_paint.erase(cell)


func _refresh_editor_preview() -> void:
	for cell in _loaded:
		if is_instance_valid(_loaded[cell]):
			_loaded[cell].queue_free()
	_loaded.clear()
	_paint.clear()
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


func _paint_grid_size() -> int:
	return int(round(chunk_size / PAINT_SPACING)) + 1


## Collects each terrain vertex's paint into a grid for paint_at().
func _read_paint(chunk: Node3D) -> PackedVector2Array:
	var n := _paint_grid_size()
	var grid := PackedVector2Array()
	var found := false
	grid.resize(n * n)
	var half := chunk_size * 0.5
	for node in chunk.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if String(mi.name).ends_with("-water") or mi.mesh == null:
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
			if uv2 == null or (uv2 as PackedVector2Array).is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				var p := xf * verts[i]
				var gx := roundi((p.x + half) / PAINT_SPACING)
				var gz := roundi((p.z + half) / PAINT_SPACING)
				if gx >= 0 and gx < n and gz >= 0 and gz < n:
					grid[gz * n + gx] = uv2[i]
					found = true
	return grid if found else PackedVector2Array()


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


func _add_chunk(cell: Vector2i, scene: PackedScene) -> void:
	if scene == null or _loaded.has(cell):
		return
	var chunk := scene.instantiate() as Node3D
	chunk.name = "chunk_%d_%d" % [cell.x, cell.y]
	chunk.position = Vector3(cell.x * chunk_size, 0, cell.y * chunk_size)
	for mesh in chunk.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if String(mi.name).ends_with("-water"):
			_make_water(mi)
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
	_place_props(cell, chunk)
	if not Engine.is_editor_hint():
		_paint[cell] = _read_paint(chunk)
	add_child(chunk)
	_loaded[cell] = chunk


## Places the props listed in chunk_I_J.props.json (written by the Blender add-on).
func _place_props(cell: Vector2i, chunk: Node3D) -> void:
	var path := String(_available[cell]).get_basename() + ".props.json"
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.has("props"):
		push_warning("ChunkStreamer: couldn't read %s" % path)
		return
	var holder := Node3D.new()
	holder.name = "Props"
	chunk.add_child(holder)
	for entry in data.props:
		var prop := _props.instantiate(entry.name)
		if prop == null:
			continue
		var c: Array = entry.basis
		var basis := Basis(Vector3(c[0][0], c[0][1], c[0][2]), Vector3(c[1][0], c[1][1], c[1][2]), Vector3(c[2][0], c[2][1], c[2][2]))
		prop.transform = Transform3D(basis, Vector3(entry.pos[0], entry.pos[1], entry.pos[2]))
		holder.add_child(prop)


## A Blender water plane (object named "<name>-water"): give it the water look and a
## swimmable volume beneath its surface.
func _make_water(mi: MeshInstance3D) -> void:
	mi.material_override = WATER_MATERIAL
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
