class_name PropLibrary
extends RefCounted
## Loads prop models (<prop_dir>/<name>.glb, exported by the Blender add-on's
## "Export Prop Library") and makes ready-to-place instances:
## - Foliage (name contains tree/bush/grass/...) gets the wind shader.
## - Trees get a trunk cylinder for collision, rocks and other solid props a convex hull,
##   small plants none.
## Everything is worked out once per prop and shared by every instance.

const FOLIAGE_WORDS := ["tree", "bush", "shrub", "grass", "fern", "flower", "plant", "leaf", "leaves", "reed", "vine"]
const NO_COLLISION_WORDS := ["grass", "fern", "flower", "reed", "vine", "small", "pebble"]
const WIND_SHADER := preload("res://assets/materials/foliage_wind.gdshader")

var prop_dir := "res://assets/props"
var _cache := {}  # name -> {scene, materials: {Material: ShaderMaterial}, shape, shape_xform} or null
var _warned := {}


func _init(dir := "res://assets/props") -> void:
	prop_dir = dir


## A new instance of the prop, or null if there's no model for it yet.
func instantiate(prop_name: String) -> Node3D:
	var info = _info(prop_name)
	if info == null:
		return null
	var node := (info.scene as PackedScene).instantiate() as Node3D
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
		node.add_child(body)
	return node


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
	var scene := load(path) as PackedScene
	var probe := scene.instantiate() as Node3D
	var lower := prop_name.to_lower()
	var foliage := FOLIAGE_WORDS.any(func(w: String) -> bool: return lower.contains(w))
	var solid := not NO_COLLISION_WORDS.any(func(w: String) -> bool: return lower.contains(w))

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

	var info := {"scene": scene, "materials": {}, "shape": null, "shape_xform": Transform3D.IDENTITY}

	if foliage:
		for m in meshes:
			for s in m.mesh.get_surface_count():
				var src := m.mesh.surface_get_material(s)
				if src and not info.materials.has(src):
					info.materials[src] = _wind_material(src, maxf(bounds.end.y, 0.5))

	if solid and not meshes.is_empty():
		if lower.contains("tree"):
			var trunk := CylinderShape3D.new()
			trunk.radius = clampf(minf(bounds.size.x, bounds.size.z) * 0.08, 0.2, 0.8)
			trunk.height = maxf(bounds.size.y * 0.6, 1.0)
			info.shape = trunk
			var c := bounds.get_center()
			info.shape_xform = Transform3D(Basis.IDENTITY, Vector3(c.x, bounds.position.y + trunk.height * 0.5, c.z))
		else:
			info.shape = meshes[0].mesh.create_convex_shape(true, true)
			info.shape_xform = _local_xform(meshes[0], probe)
	probe.free()
	_cache[prop_name] = info
	return info


func _local_xform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Wind material carrying over the original's colour, texture and transparency.
func _wind_material(src: Material, height: float) -> Material:
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
