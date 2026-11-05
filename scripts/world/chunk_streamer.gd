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

var _shared_materials := {}  # name -> Material (or null if none)

var _available := {}  # Vector2i -> path
var _loaded := {}  # Vector2i -> Node3D
var _pending := {}  # Vector2i -> path
var _target: Node3D


func _ready() -> void:
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
	if _target == null:
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


func get_loaded_cells() -> Array:
	return _loaded.keys()


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
	add_child(chunk)
	_loaded[cell] = chunk


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
