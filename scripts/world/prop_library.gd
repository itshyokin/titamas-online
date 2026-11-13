@tool
class_name PropLibrary
extends RefCounted
## Loads prop models (<prop_dir>/<name>.glb, exported by the Blender add-on's
## "Export Prop Library") and makes ready-to-place instances:
## - Foliage (name contains tree/bush/grass/...) gets the wind shader.
## - Trees get a trunk cylinder for collision (sized from the part whose material is
##   called trunk/bark/wood, or the bottom of the model), rocks and other solid props
##   their exact shape, small plants none.
## Everything is worked out once per prop and shared by every instance.

const FOLIAGE_WORDS := ["tree", "bush", "shrub", "grass", "fern", "flower", "plant", "leaf", "leaves", "reed", "vine", "herb"]
const NO_COLLISION_WORDS := ["grass", "fern", "flower", "reed", "vine", "small", "pebble"]
const TRUNK_WORDS := ["trunk", "bark", "wood", "stem", "log"]
## Props named with these become ladders (walk into them) or climbable walls (jump onto them).
const LADDER_WORDS := ["ladder"]
const CLIMBABLE_WORDS := ["climb", "ivy", "vine", "trellis"]
## Footstep sound for walking on a prop, by the first word found in its name.
const SURFACE_WORDS := {
	"wood": ["ladder", "tree", "log", "stump", "plank", "crate", "barrel", "bridge", "wood", "dock", "fence"],
	"metal": ["metal", "iron", "steel", "anvil", "grate"],
	"grass": ["bush", "shrub", "grass", "fern", "flower", "plant", "leaf", "leaves", "reed", "moss"],
}
const WIND_SHADER := preload("res://assets/materials/foliage_wind.gdshader")

var prop_dir := "res://assets/props"
var _cache := {}  # name -> {scene, materials: {Material: ShaderMaterial}, shape, shape_xform} or null
var _warned := {}
var _requested := {}  # name -> path being loaded on a thread


func _init(dir := "res://assets/props") -> void:
	prop_dir = dir


## A new instance of the prop, or null if there's no model for it yet.
func instantiate(prop_name: String) -> Node3D:
	var info = _info(prop_name)
	if info == null:
		return null
	var node := (info.scene as PackedScene).instantiate() as Node3D
	node.set_meta("prop_name", prop_name)
	if not info.materials.is_empty():
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mi as MeshInstance3D
			for s in mesh_instance.mesh.get_surface_count():
				var mat := mesh_instance.mesh.surface_get_material(s)
				if info.materials.has(mat):
					mesh_instance.set_surface_override_material(s, info.materials[mat])
	if info.shape:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		col.shape = info.shape
		col.transform = info.shape_xform
		body.add_child(col)
		body.set_meta("surface", surface_of(prop_name))
		body.set_meta("prop_name", prop_name)
		if not String(info.group).is_empty():
			body.add_to_group(info.group)
		node.add_child(body)
	return node


## Starts loading the prop's model on a background thread (streaming chunks ask ahead,
## so the first tree of a kind doesn't stall a frame).
func request(prop_name: String) -> void:
	if _cache.has(prop_name) or _requested.has(prop_name):
		return
	var path := prop_dir.path_join(prop_name + ".glb")
	if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path) == OK:
		_requested[prop_name] = path


## The model is in memory (or will never be): instantiate() won't wait for the disk.
func is_ready(prop_name: String) -> bool:
	if _cache.has(prop_name) or not _requested.has(prop_name):
		return true
	return ResourceLoader.load_threaded_get_status(_requested[prop_name]) != ResourceLoader.THREAD_LOAD_IN_PROGRESS


## The prop's longest side (m, unscaled); 1 if unknown.
func size_of(prop_name: String) -> float:
	var info = _info(prop_name)
	return float(info.size) if info != null else 1.0


## Footstep surface for a prop name: "wood", "metal", "grass" or (rocks and the rest) "stone".
static var _harvest := {}
static var _harvest_time := -1


## data/harvest.json (what can be chopped / smashed; see Harvest).
static func harvest_data() -> Dictionary:
	var t := DataFiles.modified_time("res://data/harvest.json")
	if t != _harvest_time:
		_harvest_time = t
		var d = DataFiles.read("res://data/harvest.json")
		_harvest = d if d is Dictionary else {}
	return _harvest


## "chop", "smash" or "" for a prop / object name ("_chop" / "_smash" in it, or listed
## under harvest.json "props").
static func harvest_kind(n: String) -> String:
	var lower := n.to_lower()
	if lower.contains("_chop"):
		return "chop"
	if lower.contains("_smash"):
		return "smash"
	return String((harvest_data().get("props", {}) as Dictionary).get(n, ""))


static func surface_of(prop_name: String) -> String:
	var lower := prop_name.to_lower()
	for surface: String in SURFACE_WORDS:
		for w: String in SURFACE_WORDS[surface]:
			if lower.contains(w):
				return surface
	return "stone"


func _info(prop_name: String):
	if _cache.has(prop_name):
		return _cache[prop_name]
	var path := prop_dir.path_join(prop_name + ".glb")
	if not ResourceLoader.exists(path):
		if not _warned.has(prop_name):
			_warned[prop_name] = true
			push_warning("PropLibrary: no model for prop '%s' (expected %s)" % [prop_name, path])
		_cache[prop_name] = null
		return null
	var scene: PackedScene = null
	if _requested.has(prop_name):
		scene = ResourceLoader.load_threaded_get(path) as PackedScene  # waits if it isn't done yet
		_requested.erase(prop_name)
	if scene == null:
		scene = load(path) as PackedScene
	var probe := scene.instantiate() as Node3D
	var lower := prop_name.to_lower()
	var foliage := FOLIAGE_WORDS.any(func(w: String) -> bool: return lower.contains(w))
	var ladder := LADDER_WORDS.any(func(w: String) -> bool: return lower.contains(w))
	var climbable := CLIMBABLE_WORDS.any(func(w: String) -> bool: return lower.contains(w))
	# Things you can chop or smash (data/harvest.json, or _chop / _smash in the name) are
	# always solid, so a swing can reach them.
	var harvest := harvest_kind(prop_name)
	# Herbs to pick (harvest kinds with "pick") are walked through.
	var kinds: Dictionary = harvest_data().get("kinds", {})
	var pick := harvest != "" and bool((kinds.get(harvest, {}) as Dictionary).get("pick", false))
	var solid := not pick and (harvest != "" or ladder or climbable or not NO_COLLISION_WORDS.any(func(w: String) -> bool: return lower.contains(w)))

	# Bounds of the whole prop in its own space.
	var bounds := AABB()
	var first := true
	var meshes: Array[MeshInstance3D] = []
	for mi in probe.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		meshes.append(m)
		var box := _local_xform(m, probe) * m.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false

	# A prop named for something else (watchtower_climb) is still a ladder when its
	# material or texture says so (a "rope_ladder" picture).
	if not ladder:
		for m in meshes:
			for s in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(s)
				var words := (mat.resource_name if mat else "").to_lower()
				if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture:
					words += " " + (mat as BaseMaterial3D).albedo_texture.resource_path.get_file().to_lower()
				if LADDER_WORDS.any(func(w: String) -> bool: return words.contains(w)):
					ladder = true
	var info := {"scene": scene, "materials": {}, "shape": null, "shape_xform": Transform3D.IDENTITY,
		"group": "ladder" if ladder else ("climbable" if climbable else ""),
		"size": maxf(bounds.get_longest_axis_size(), 0.1)}

	# Every prop gets the shared prop shader (pixel textures setting); foliage also sways.
	for m in meshes:
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			if src and not info.materials.has(src):
				var mat := _wind_material(src, maxf(bounds.end.y, 0.5))
				# The texture usually spans the whole model: keep its texels terrain-sized.
				mat.set_shader_parameter("pixel_scale", maxf(bounds.get_longest_axis_size() / 4.0, 0.25))
				if not foliage:
					mat.set_shader_parameter("sway_strength", 0.0)
					mat.set_shader_parameter("flutter_strength", 0.0)
				info.materials[src] = mat

	if solid and not meshes.is_empty():
		if ladder:
			# A solid slab over the whole ladder: the climb probes would slip between the
			# rungs of the exact mesh (and walk straight through a rope ladder).
			var slab := BoxShape3D.new()
			slab.size = bounds.size.max(Vector3.ONE * 0.08)
			info.shape = slab
			info.shape_xform = Transform3D(Basis.IDENTITY, bounds.get_center())
		elif lower.contains("tree") and not climbable:
			# The trunk's longest side is its length. Usually that's up (Y), but props
			# exported lying down and stood up by their placement have it along another
			# axis, so the cylinder follows whichever is longest. Sizes stay in prop units:
			# the placement's scale applies to the shape too.
			var trunk_box := _trunk_bounds(meshes, probe, bounds)
			var size := trunk_box.size
			var axis := 1
			if size.x > size[axis]:
				axis = 0
			if size.z > size[axis]:
				axis = 2
			var across := (size.x + size.y + size.z - size[axis]) * 0.5
			var trunk := CylinderShape3D.new()
			trunk.radius = maxf(across * 0.5 * 0.8, 0.01)
			trunk.height = maxf(size[axis], 0.05)
			info.shape = trunk
			var up_basis := Basis.IDENTITY
			if axis == 0:
				up_basis = Basis(Vector3.BACK, -PI * 0.5)  # cylinder Y -> X
			elif axis == 2:
				up_basis = Basis(Vector3.RIGHT, PI * 0.5)  # cylinder Y -> Z
			info.shape_xform = Transform3D(up_basis, trunk_box.get_center())
		else:
			# Exact shape (static bodies can use concave meshes).
			info.shape = meshes[0].mesh.create_trimesh_shape()
			info.shape_xform = _local_xform(meshes[0], probe)
	probe.free()
	_cache[prop_name] = info
	return info


## Bounds of the trunk in prop space: vertices of surfaces whose material name says
## trunk/bark/wood. Without one, the lower half of the model's middle tenth.
func _trunk_bounds(meshes: Array[MeshInstance3D], root: Node3D, whole: AABB) -> AABB:
	var box := AABB()
	var found := false
	var points: Array[Vector3] = []
	for m in meshes:
		var xf := _local_xform(m, root)
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			var mat_name := (mat.resource_name if mat else "").to_lower()
			if not TRUNK_WORDS.any(func(w: String) -> bool: return mat_name.contains(w)):
				continue
			var verts: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := xf * v
				points.append(p)
				if not found:
					box = AABB(p, Vector3.ZERO)
					found = true
				else:
					box = box.expand(p)
	if found and box.size.y >= maxf(box.size.x, box.size.z):
		# Branches share the bark material and spread out up top: the trunk's width is
		# taken from the bark low down (the bottom quarter), around its middle.
		var low := box.position.y + box.size.y * 0.25
		var centre := Vector2.ZERO
		var n := 0
		for p in points:
			if p.y <= low:
				centre += Vector2(p.x, p.z)
				n += 1
		if n > 3:
			centre /= n
			var dists: Array[float] = []
			for p in points:
				if p.y <= low:
					dists.append(Vector2(p.x, p.z).distance_to(centre))
			dists.sort()
			var r := maxf(dists[int(dists.size() * 0.8)], 0.05)
			return AABB(Vector3(centre.x - r, box.position.y, centre.y - r), Vector3(r * 2.0, box.size.y, r * 2.0))
	if found:
		return box
	var c := whole.get_center()
	var w := maxf(minf(whole.size.x, whole.size.z) * 0.1, 0.3)
	return AABB(Vector3(c.x - w * 0.5, whole.position.y, c.z - w * 0.5), Vector3(w, whole.size.y * 0.5, w))


func _local_xform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Wind material carrying over the original's colour, texture and transparency.
func _wind_material(src: Material, height: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WIND_SHADER
	mat.resource_name = src.resource_name + "_wind"
	mat.set_shader_parameter("sway_height", height)
	if src is BaseMaterial3D:
		var base := src as BaseMaterial3D
		mat.set_shader_parameter("albedo_color", base.albedo_color)
		if base.albedo_texture:
			mat.set_shader_parameter("albedo_texture", base.albedo_texture)
		var cutout := base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.set_shader_parameter("use_alpha_cutout", cutout)
		if base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			mat.set_shader_parameter("alpha_cutout", base.alpha_scissor_threshold)
	return mat
