extends SceneTree
## Builds stand-in fitted (skinned) armour from the base bodies: copies of body parts,
## pushed out a little along their normals, recoloured, keeping the bones' weights so they
## bend with the body. One scene per piece per body in assets/items/skinned/.
##   godot --headless --path . --script res://tools/godot/make_placeholder_armor.gd
## Real armour made in Blender (weight-painted to the same rig) replaces these: point the
## item's "Fitted model (masc/femme)" at the new file in the Database.

const BODIES := "res://assets/models/characters/base_bodies.glb"
const OUT := "res://assets/items/skinned"

## piece id -> {parts, thickness (m), colour, below/above (optional height limits, m)}
const PIECES := {
	"leather_jerkin": {"parts": ["torso", "left_arm", "right_arm"], "thickness": 0.014, "color": Color(0.45, 0.27, 0.14)},
	"travelers_trousers": {"parts": ["left_leg", "right_leg", "torso"], "thickness": 0.008, "color": Color(0.25, 0.27, 0.38), "below": 1.02},
	"worn_boots": {"parts": ["left_foot", "right_foot", "left_leg", "right_leg"], "thickness": 0.012, "color": Color(0.28, 0.18, 0.1), "below": 0.47},
	"leather_gloves": {"parts": ["left_hand", "right_hand"], "thickness": 0.005, "color": Color(0.36, 0.22, 0.12)},
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var bodies := (load(BODIES) as PackedScene).instantiate() as Node3D
	for body in ["masc", "femme"]:
		var skel := bodies.get_node("Armature_%s/Skeleton3D" % body) as Skeleton3D
		var prefix := "f_" if body == "femme" else ""
		# Heights are measured in the model's real size (the import scales the skeleton).
		var to_world := Transform3D.IDENTITY
		var walk: Node = skel
		while walk is Node3D:
			to_world = (walk as Node3D).transform * to_world
			walk = walk.get_parent()
		for id: String in PIECES:
			var spec: Dictionary = PIECES[id]
			var piece := Node3D.new()
			piece.name = id
			var mat := StandardMaterial3D.new()
			mat.albedo_color = spec.color
			mat.roughness = 0.85
			for part: String in spec.parts:
				var src := skel.get_node_or_null(prefix + part) as MeshInstance3D
				if src == null:
					push_warning("no part %s%s" % [prefix, part])
					continue
				var mesh := _shell(src, spec, to_world)
				if mesh == null:
					continue
				var mi := MeshInstance3D.new()
				mi.name = part
				mi.mesh = mesh
				mi.skin = src.skin
				mi.material_override = mat
				piece.add_child(mi)
				mi.owner = piece
			var packed := PackedScene.new()
			packed.pack(piece)
			var path := "%s/%s_%s.scn" % [OUT, id, body]
			print(path, " ", ResourceSaver.save(packed, path), " parts=", piece.get_child_count())
			piece.free()
	bodies.free()
	quit()


## A copy of a body part pushed out along its normals, optionally cut to the triangles
## above/below a height (metres from the floor at rest).
func _shell(src: MeshInstance3D, spec: Dictionary, to_world: Transform3D) -> ArrayMesh:
	var arrays := src.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# The body meshes are stored in metres, Y up, feet at 0 (their skin maps them onto the
	# scaled skeleton), so heights and thickness can be used directly.
	var unit := 1.0
	var out_verts := PackedVector3Array()
	out_verts.resize(verts.size())
	for i in verts.size():
		out_verts[i] = verts[i] + normals[i] * float(spec.thickness) * unit
	if spec.has("above") or spec.has("below"):
		var keep := PackedInt32Array()
		for t in range(0, indices.size(), 3):
			var ok := true
			for k in 3:
				var y := verts[indices[t + k]].y
				if spec.has("above") and y < float(spec.above):
					ok = false
				if spec.has("below") and y > float(spec.below):
					ok = false
			if ok:
				keep.append_array([indices[t], indices[t + 1], indices[t + 2]])
		if keep.is_empty():
			return null
		indices = keep
	arrays[Mesh.ARRAY_VERTEX] = out_verts
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
