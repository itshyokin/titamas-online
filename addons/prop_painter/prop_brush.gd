@tool
extends RefCounted
## The Prop Painter's file and terrain work (the plugin handles the dock, input and undo).

const Z_UP := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

var tri_cache := {}  # Mesh -> TriangleMesh
## path -> text before the current stroke (for undo)
var stroke_before := {}

func _add_entry(streamer: Node, cell: Vector2i, chunk: Node3D, prop_name: String, pos: Vector3, basis: Basis) -> void:
	var data := _read(streamer, cell)
	if not data.has("props"):
		data["props"] = []
	var r := func(v: float) -> float: return snappedf(v, 0.0001)
	data.props.append({"name": prop_name, "pos": [r.call(pos.x), r.call(pos.y), r.call(pos.z)],
		"basis": [[r.call(basis.x.x), r.call(basis.x.y), r.call(basis.x.z)], [r.call(basis.y.x), r.call(basis.y.y), r.call(basis.y.z)], [r.call(basis.z.x), r.call(basis.z.y), r.call(basis.z.z)]]})
	_write(streamer, cell, data)
	# Show it right away.
	var lib = streamer.get("_props")
	var holder := chunk.get_node_or_null("Props") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "Props"
		chunk.add_child(holder)
	var node: Node3D = lib.call("instantiate", prop_name) if lib else null
	if node:
		node.transform = Transform3D(basis, pos)
		holder.add_child(node)



func _rebuild_props(streamer: Node, cell: Vector2i, chunk: Node3D) -> void:
	var holder := chunk.get_node_or_null("Props")
	if holder:
		holder.free()
	streamer.call("_place_props", cell, chunk)



func _props_path(streamer: Node, cell: Vector2i) -> String:
	return String(streamer.get("chunk_dir")).path_join("chunk_%d_%d.painted.json" % [cell.x, cell.y])



func _read(streamer: Node, cell: Vector2i) -> Dictionary:
	var path := _props_path(streamer, cell)
	if not FileAccess.file_exists(path):
		return {"props": []}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {"props": []}



func _write(streamer: Node, cell: Vector2i, data: Dictionary) -> void:
	var path := _props_path(streamer, cell)
	if not stroke_before.has(path):
		stroke_before[path] = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()



func _cell_of(streamer: Node, p: Vector3) -> Vector2i:
	var size := float(streamer.get("chunk_size"))
	return Vector2i(floori(p.x / size), floori(p.z / size))



func _chunk(streamer: Node, cell: Vector2i) -> Node3D:
	var loaded: Dictionary = streamer.get("_loaded")
	return loaded.get(cell) as Node3D if loaded.has(cell) and is_instance_valid(loaded[cell]) else null



## The nearest terrain hit along a ray ({position, normal} or {}), against the chunks'
## meshes (not their props or water).
func _ray(streamer: Node, from: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for cell: Vector2i in streamer.get("_loaded").keys():
		var chunk := _chunk(streamer, cell)
		if chunk == null:
			continue
		for n in chunk.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or String(mi.name).ends_with("-water") or _under_props(mi, chunk):
				continue
			if not tri_cache.has(mi.mesh):
				tri_cache[mi.mesh] = mi.mesh.generate_triangle_mesh()
			var tm: TriangleMesh = tri_cache[mi.mesh]
			var inv := mi.global_transform.affine_inverse()
			var hit := tm.intersect_ray(inv * from, (inv.basis * dir).normalized())
			if hit.is_empty():
				continue
			var p: Vector3 = mi.global_transform * (hit.position as Vector3)
			var d := from.distance_to(p)
			if d < best_d:
				best_d = d
				best = {"position": p, "normal": (mi.global_transform.basis * (hit.normal as Vector3)).normalized()}
	return best



func _under_props(node: Node, chunk: Node) -> bool:
	var n := node.get_parent()
	while n and n != chunk:
		if n.name == "Props":
			return true
		n = n.get_parent()
	return false


