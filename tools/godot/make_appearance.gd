extends SceneTree
## Builds the placeholder hair and facial hair for the character creator from the base
## bodies' head meshes: the scalp (or jaw) is copied, pushed out along its normals by a
## thickness that fades at the hairline, keeping the bone weights so it moves with the
## head. One scene per style per body:
##   assets/characters/hair/<style>_<masc|femme>.scn
##   assets/characters/facial_hair/<style>_<masc|femme>.scn
##   godot --headless --path . --script res://tools/godot/make_appearance.gd
## Hair made in Blender (skinned to the same rig) replaces these: point the style's
## fitted_masc / fitted_femme in data/appearance.json at the new file. Long hair, ponytail
## and bun add a rigid piece on the head bone (WeaponModels "builtin:hair_*").

const BODIES := "res://assets/models/characters/base_bodies.scn"

## Head measurements at rest, metres: top of the head, chin, front of the face, back.
## Measured from each body's head mesh (chin = just under the head bone).
var HEAD := {}

## u = 0 at the chin, 1 at the top; d = 0 at the face, 1 at the back of the head.
## front/back: hairline height (u) at the forehead and at the nape.
const HAIR := {
	"buzz": {"front": 0.74, "back": 0.08, "base": 0.0035},
	"short": {"front": 0.72, "back": 0.1, "base": 0.009, "top": 0.012},
	"spiky": {"front": 0.73, "back": 0.12, "base": 0.01, "top": 0.008, "spike": 0.032},
	"swept": {"front": 0.77, "back": 0.0, "base": 0.014, "top": 0.022},
	"mohawk": {"front": 0.74, "back": 0.1, "base": 0.003, "mohawk": 0.05},
	"long": {"front": 0.7, "back": -0.05, "base": 0.014, "top": 0.01},
	"ponytail": {"front": 0.73, "back": 0.05, "base": 0.008, "top": 0.004},
	"bun": {"front": 0.73, "back": 0.05, "base": 0.008, "top": 0.004},
}

const FACIAL := ["stubble", "mustache", "goatee", "short_beard", "full_beard"]

## Plain underclothes worn under everything (shorts; a band top on the femme body):
## [lowest, highest] heights (m) per body part kind.
const UNDERWEAR := {
	"masc": {"torso": [[0.0, 1.05]], "leg": [[0.78, 2.0]]},
	"femme": {"torso": [[0.0, 1.03], [1.22, 1.4]], "leg": [[0.76, 2.0]]},
}


func _initialize() -> void:
	var bodies := (load(BODIES) as PackedScene).instantiate() as Node3D
	for body: String in ["masc", "femme"]:
		var skel := bodies.get_node("Armature_%s/Skeleton3D" % body) as Skeleton3D
		var head := skel.get_node(("f_" if body == "femme" else "") + "head") as MeshInstance3D
		var hv: PackedVector3Array = head.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for v in hv:
			lo = lo.min(v)
			hi = hi.max(v)
		var head_bone := skel.get_bone_global_rest(skel.find_bone("mixamorig_Head")).origin.y
		HEAD[body] = {"top": hi.y, "chin": head_bone - 0.012, "front": lo.z, "back": hi.z}
		print(body, " head ", HEAD[body])
		for style: String in HAIR:
			_save(head, func(p: Vector3) -> float: return _hair(p, HEAD[body], HAIR[style]),
				"res://assets/characters/hair/%s_%s.scn" % [style, body], Color(0.35, 0.22, 0.12))
		for style: String in FACIAL:
			_save(head, func(p: Vector3) -> float: return _facial(p, HEAD[body], style),
				"res://assets/characters/facial_hair/%s_%s.scn" % [style, body], Color(0.35, 0.22, 0.12))
		var parts: Array[MeshInstance3D] = []
		var prefix := "f_" if body == "femme" else ""
		for part in ["torso", "left_leg", "right_leg"]:
			parts.append(skel.get_node(prefix + part) as MeshInstance3D)
		_save_parts(parts, UNDERWEAR[body], "res://assets/characters/underwear_%s.scn" % body)
	bodies.free()
	quit()


func _save_parts(parts: Array[MeshInstance3D], bands: Dictionary, path: String) -> void:
	var root := Node3D.new()
	root.name = "underwear"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.74, 0.62)
	mat.roughness = 0.95
	for src in parts:
		var kind := "torso" if String(src.name).ends_with("torso") else "leg"
		var ranges: Array = bands[kind]
		var mesh := _band(src, ranges, 0.006)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = src.name
		mi.mesh = mesh
		mi.skin = src.skin
		mi.material_override = mat
		root.add_child(mi)
		mi.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	print(path, " ", ResourceSaver.save(packed, path))
	root.free()


func _save(head: MeshInstance3D, thickness: Callable, path: String, color: Color) -> void:
	var mesh := _shell(head, thickness)
	if mesh == null:
		# Nothing of this style fits this head (too few vertices there): drop any old file
		# so the option simply shows nothing on this body.
		push_warning("empty: " + path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var root := Node3D.new()
	root.name = path.get_file().get_basename()
	var mi := MeshInstance3D.new()
	mi.name = "hair"
	mi.mesh = mesh
	mi.skin = head.skin
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	root.add_child(mi)
	mi.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	print(path, " ", ResourceSaver.save(packed, path), " tris=", mesh.surface_get_array_index_len(0) / 3)
	root.free()


## Copy of the head pushed out by thickness(p) along the normals, keeping only triangles
## where every corner has some thickness.
func _shell(src: MeshInstance3D, thickness: Callable) -> ArrayMesh:
	var arrays := src.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var t := PackedFloat32Array()
	t.resize(verts.size())
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		t[i] = thickness.call(verts[i])
		out[i] = verts[i] + normals[i] * maxf(t[i], 0.0)
	var keep := PackedInt32Array()
	for k in range(0, indices.size(), 3):
		if t[indices[k]] > 0.0005 and t[indices[k + 1]] > 0.0005 and t[indices[k + 2]] > 0.0005:
			keep.append_array([indices[k], indices[k + 1], indices[k + 2]])
	if keep.is_empty():
		return null
	arrays[Mesh.ARRAY_VERTEX] = out
	arrays[Mesh.ARRAY_INDEX] = keep
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Copy of a body part pushed out by `thickness`, keeping the triangles whose middle
## lies within one of the height ranges.
func _band(src: MeshInstance3D, ranges: Array, thickness: float) -> ArrayMesh:
	var arrays := src.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		out[i] = verts[i] + normals[i] * thickness
	var keep := PackedInt32Array()
	for k in range(0, indices.size(), 3):
		var y := (verts[indices[k]].y + verts[indices[k + 1]].y + verts[indices[k + 2]].y) / 3.0
		for r: Array in ranges:
			if y >= r[0] and y <= r[1]:
				keep.append_array([indices[k], indices[k + 1], indices[k + 2]])
				break
	if keep.is_empty():
		return null
	arrays[Mesh.ARRAY_VERTEX] = out
	arrays[Mesh.ARRAY_INDEX] = keep
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _ud(p: Vector3, h: Dictionary) -> Vector2:
	return Vector2((p.y - h.chin) / (h.top - h.chin), (p.z - h.front) / (h.back - h.front))


## Repeatable 0..1 noise per small cell, so neighbouring corners at the same spot match.
static func _noise(p: Vector3, cell := 0.022) -> float:
	var q := (p / cell).round()
	return fposmod(sin(q.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453, 1.0)


static func _hair(p: Vector3, h: Dictionary, s: Dictionary) -> float:
	var ud := _ud(p, h)
	var u := ud.x
	var cut := lerpf(float(s.front), float(s.back), smoothstep(0.15, 0.85, ud.y))
	var m := smoothstep(cut, cut + 0.07, u)
	if m <= 0.0:
		return 0.0
	var t := float(s.base) + float(s.get("top", 0.0)) * clampf(u, 0.0, 1.0)
	if s.has("spike"):
		t += float(s.spike) * _noise(p) * smoothstep(0.55, 0.9, u)
	if s.has("mohawk"):
		t += float(s.mohawk) * smoothstep(0.045, 0.018, absf(p.x)) * smoothstep(0.35, 0.65, u)
	return t * m


static func _bump(x: float, lo: float, hi: float, soft: float) -> float:
	return smoothstep(lo - soft, lo, x) * smoothstep(hi + soft, hi, x)


static func _facial(p: Vector3, h: Dictionary, style: String) -> float:
	var ud := _ud(p, h)
	var u := ud.x
	var d := ud.y
	var ax := absf(p.x)
	# Lips are around u 0.15-0.26, the nostrils at 0.31; sideburns reach up by the ears.
	var mouth := _bump(u, 0.15, 0.26, 0.02) * smoothstep(0.04, 0.028, ax) * smoothstep(0.28, 0.15, d)
	var mustache := _bump(u, 0.245, 0.3, 0.02) * smoothstep(0.048, 0.03, ax) * smoothstep(0.3, 0.18, d)
	var chin := smoothstep(0.15, 0.1, u) * smoothstep(-0.1, -0.03, u) * smoothstep(0.042, 0.026, ax) * smoothstep(0.35, 0.2, d)
	var cut := lerpf(0.27, 0.47, smoothstep(0.25, 0.6, d))
	var jaw := smoothstep(cut + 0.03, cut - 0.03, u) * smoothstep(-0.16, -0.06, u) * smoothstep(0.68, 0.58, d) * (1.0 - mouth)
	match style:
		"stubble":
			return 0.0016 * jaw
		"mustache":
			return 0.008 * mustache
		"goatee":
			return maxf(0.007 * mustache, 0.012 * chin)
		"short_beard":
			return 0.006 * jaw
		"full_beard":
			return (0.009 + 0.018 * smoothstep(0.3, 0.0, u) * smoothstep(0.5, 0.1, d)) * jaw
	return 0.0
