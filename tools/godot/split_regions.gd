extends SceneTree
## Moves what's placed in a level (enemies, NPCs, events, areas, campfires, chests, beds…)
## into one sub-scene per region (data/regions.json chunk rectangles), saved as
## scenes/levels/regions/<region id>.tscn and instanced under the level's "Regions" node.
## The level stays one seamless world for streaming; the editor tree just shows a node per
## region, and each region's scene can be opened on its own.
##
## Safe to run again: anything left (or newly placed) at the level's top level is sorted
## into its region's scene by position; what's already in a region scene stays put.
## Also tags each event in data/events.json with the region it's placed in (Database →
## Events groups the list by it), where the event has no region yet.
##
##   godot --headless --path . --script res://tools/godot/split_regions.gd
##   LEVEL=res://scenes/levels/other.tscn godot --headless --path . --script ...

const KEEP := ["WorldEnvironment", "Sun", "WorldCycle", "ChunkStreamer", "Player", "Ocean", "AtmosphereManager", "Regions", "RemotePlayers"]
const FOLDERS := ["Enemies", "NPCs", "Events", "Areas", "Campfires"]
const OUT_DIR := "res://scenes/levels/regions"

var level_path := "res://scenes/levels/overworld_test.tscn"
var chunk_size := 64.0
var regions: Array = []  # [{id, rect: Rect2 in metres}]


func _initialize() -> void:
	var env := OS.get_environment("LEVEL")
	if env != "":
		level_path = env
	var level: Node = (load(level_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var streamer := level.get_node_or_null("ChunkStreamer")
	if streamer and streamer.get("chunk_size") != null:
		chunk_size = float(streamer.get("chunk_size"))
	_read_regions()
	if regions.is_empty():
		push_error("split_regions: no regions in data/regions.json")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# Region scenes: the ones already instanced in the level are loaded to add to.
	var holder := level.get_node_or_null("Regions") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "Regions"
		level.add_child(holder)
		holder.owner = level
	var roots := {}  # region id -> root Node3D (a fresh, unowned copy we save)
	for inst in holder.get_children():
		var id := String(inst.get_meta("region", ""))
		if id != "" and inst.scene_file_path != "":
			roots[id] = (load(inst.scene_file_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)

	# Sort what's at the top level (and inside the old folders) by position.
	var moved := 0
	for child in level.get_children():
		if String(child.name) in KEEP:
			continue
		if String(child.name) in FOLDERS and child.get_class() == "Node3D" and child.scene_file_path == "":
			for item in child.get_children():
				_move(level, item, String(child.name), roots)
				moved += 1
			if child.get_child_count() == 0:
				level.remove_child(child)
				child.free()
		elif child is Node3D:
			_move(level, child, "Places", roots)
			moved += 1

	# Save each region scene, then instance it in the level.
	for id in roots:
		var root: Node3D = roots[id]
		if root.get_script() == null:
			root.set_script(load("res://scripts/world/region_content.gd"))
		root.set("region_id", id)
		var path := "%s/%s.tscn" % [OUT_DIR, id]
		var packed := PackedScene.new()
		var err := packed.pack(root)
		if err != OK:
			push_error("split_regions: couldn't pack %s (%d)" % [id, err])
			continue
		ResourceSaver.save(packed, path)
		root.free()
		var old := holder.get_node_or_null(_node_name(id))
		if old:
			holder.remove_child(old)
			old.free()
		var inst: Node3D = (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		holder.add_child(inst)
		inst.owner = level
		print("split_regions: %s → %s" % [id, path])
	var packed_level := PackedScene.new()
	packed_level.pack(level)
	ResourceSaver.save(packed_level, level_path)
	print("split_regions: moved %d node(s); saved %s" % [moved, level_path])
	_tag_events(level)
	level.free()
	quit()


func _read_regions() -> void:
	var d = DataFiles.read("res://data/regions.json")
	for r in (d.get("regions", []) if d is Dictionary else []):
		if not r is Dictionary or bool(r.get("default", false)):
			continue
		var c: Array = r.get("chunks", [0, 0, 1, 1])
		regions.append({"id": String(r.id), "rect": Rect2(float(c[0]) * chunk_size, float(c[1]) * chunk_size, float(c[2]) * chunk_size, float(c[3]) * chunk_size)})


## The region a point is in (or the nearest one).
func _region_at(p: Vector3) -> String:
	var xz := Vector2(p.x, p.z)
	var best := ""
	var best_d := INF
	for r in regions:
		var rect: Rect2 = r.rect
		if rect.has_point(xz):
			return String(r.id)
		var d := (rect.get_center() - xz).length()
		if d < best_d:
			best_d = d
			best = String(r.id)
	return best


static func _node_name(id: String) -> String:
	return id.to_pascal_case()


## Where a node stands (a plain folder: the middle of what's in it).
func _where(n: Node) -> Vector3:
	if n is Node3D and (n.get_child_count() == 0 or n.scene_file_path != "" or n.get_class() != "Node3D" or n.get_script() != null):
		return _global(n)
	var sum := Vector3.ZERO
	var count := 0
	for c in n.get_children():
		if c is Node3D:
			sum += _global(c)
			count += 1
	return sum / count if count > 0 else (_global(n) if n is Node3D else Vector3.ZERO)


## Position in level space without being in the tree.
func _global(n: Node3D) -> Vector3:
	var t := n.transform
	var p := n.get_parent()
	while p and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t.origin


func _move(level: Node, node: Node, folder: String, roots: Dictionary) -> void:
	var id := _region_at(_where(node))
	var root: Node3D = roots.get(id)
	if root == null:
		root = Node3D.new()
		root.name = _node_name(id)
		root.set_meta("region", id)
		roots[id] = root
	var into := root.get_node_or_null(folder)
	if into == null:
		into = Node3D.new()
		into.name = folder
		root.add_child(into)
		into.owner = root
	# Keep where it stands in the world (folders are at the origin, but just in case).
	var at: Transform3D = node.transform if node is Node3D else Transform3D.IDENTITY
	var p := node.get_parent()
	while p and p is Node3D and p != level:
		at = (p as Node3D).transform * at
		p = p.get_parent()
	node.owner = null  # set again by _reown, after the move
	node.get_parent().remove_child(node)
	var taken := String(node.name)
	if into.has_node(taken):
		node.name = taken + "_" + str(into.get_child_count())
	into.add_child(node)
	if node is Node3D:
		(node as Node3D).transform = at
	_reown(node, level, root)


## Everything the level owned now belongs to the region scene (nodes inside an instanced
## scene keep their own owner).
static func _reown(node: Node, level: Node, root: Node) -> void:
	if node.owner == level or node.owner == null:
		node.owner = root
	for c in node.get_children():
		if c.owner == level:
			_reown(c, level, root)


## Events placed in a region (or run by an NPC placed there) get that region in events.json.
func _tag_events(level: Node) -> void:
	var where := {}  # event id -> region
	var holder := level.get_node_or_null("Regions")
	if holder == null:
		return
	var npc_events := {}
	var npcs = DataFiles.read("res://data/npcs.json")
	for n in (npcs.get("npcs", []) if npcs is Dictionary else []):
		if n is Dictionary and String(n.get("event", "")) != "":
			npc_events[String(n.id)] = String(n.event)
	for inst in holder.get_children():
		var id := String(inst.get_meta("region", ""))
		for n in inst.find_children("*", "", true, false):
			var ev = n.get("event_id")
			if ev is String and ev != "" and not where.has(ev):
				where[ev] = id
			var npc_id = n.get("npc_id")
			if npc_id is String and npc_events.has(npc_id) and not where.has(npc_events[npc_id]):
				where[npc_events[npc_id]] = id
	var data = DataFiles.read("res://data/events.json")
	if not data is Dictionary:
		return
	var tagged := 0
	for e in data.get("events", []):
		if e is Dictionary and String(e.get("region", "")) == "" and where.has(String(e.get("id", ""))):
			e["region"] = where[String(e.id)]
			tagged += 1
	if tagged > 0:
		DataFiles.write("res://data/events.json", data)
	print("split_regions: tagged %d event(s) with their region" % tagged)
