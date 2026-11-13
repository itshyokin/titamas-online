extends SceneTree
## Builds assets/models/characters/base_bodies.scn, the bodies every character uses:
##   base_bodies
##     Armature_masc / Skeleton3D / head, torso, left_arm, left_hand, left_leg, left_foot,
##                                  right_..., underwear
##     Armature_femme / Skeleton3D / f_head, f_torso, ...   (copied as it is from the old
##                                  base_bodies.glb until the femme version is made)
## The masc body comes from the low-poly Blender file exported as
## assets/models/characters/src/lowpoly_guy.glb (Mixamo rig). It is turned to face -Z,
## scaled so the top of the head is at HEIGHT metres and baked into that space (skeleton
## rests, vertices, bind poses), so eyes, builds (weight), armour fitting and hair work in
## metres with the feet at 0. The body mesh is cut into parts by the bone each triangle
## mostly follows, so gear can hide parts; its "leather" surface becomes `underwear`.
##
## The other meshes in the file (outfits, heads, hair, the face, hats) are saved with the
## same bake as fitted (skinned) scenes in assets/characters/lowpoly/, cut into pieces as
## listed in PIECES, for items and appearance options (data/items.json, appearance.json).
##
##   godot --headless --path . --script res://tools/godot/build_bodies.gd
## Then rebuild the animations (tools/godot/retarget_mixamo.gd) and the placeholder hair
## (tools/godot/make_appearance.gd). Database → Body Models → Rebuild runs this and
## make_appearance from the editor.

const OUT := "res://assets/models/characters/base_bodies.scn"
const OLD_BODIES := "res://assets/models/characters/base_bodies.glb"
const GEAR_DIR := "res://assets/characters/lowpoly"
## What to build: data/body_models.json (Database → Body Models): the source .glb, the
## height, which meshes make the body, which body materials become their own parts, and the
## pieces to save. A piece: {id, mesh, material ("" = all, or a comma list), min_y / max_y / max_side (m after the
## bake, -1 = none; to split one mesh by height), bone (rigid meshes follow it)}.
const SETTINGS := "res://data/body_models.json"

var SOURCE := "res://assets/models/characters/src/lowpoly_guy.glb"
var HEIGHT := 1.86
var BODY_MESHES: Array = []
var BODY_EXTRA := {}
var PIECES := {}
var BONE_OF := {}
## More bodies (body_models.json "extra_bodies", Database → Body Models → Body types 3 and 4):
## [{key, name, source (.fbx/.glb with a Mixamo rig), height, body_meshes ([] = every skinned
## mesh except teeth/tongue), pieces (same as above, saved as <id>_<key>.scn)}]. Each is
## built like the masc body into Armature_<key>, parts named the same (head comes from the
## bones, as these bodies are one mesh).
var EXTRA_BODIES: Array = []
var SUFFIX := "masc"  # file suffix of the pieces being saved
var HEAD_BY_BONES := false

## Which part a bone's skin belongs to.
const PART_OF := {
	"Neck": "head", "Head": "head", "HeadTop_End": "head",
	"Hips": "torso", "Spine": "torso", "Spine1": "torso", "Spine2": "torso",
	"LeftShoulder": "torso", "RightShoulder": "torso",
	"LeftArm": "left_arm", "LeftForeArm": "left_arm", "RightArm": "right_arm", "RightForeArm": "right_arm",
	"LeftUpLeg": "left_leg", "LeftLeg": "left_leg", "RightUpLeg": "right_leg", "RightLeg": "right_leg",
	"LeftFoot": "left_foot", "LeftToeBase": "left_foot", "LeftToe_End": "left_foot",
	"RightFoot": "right_foot", "RightToeBase": "right_foot", "RightToe_End": "right_foot",
}
## Hands and feet win a triangle only when they clearly own it.
const PART_BIAS := {"left_hand": 0.6, "right_hand": 0.6, "left_foot": 0.75, "right_foot": 0.75}

var _skel: Skeleton3D
var _src: Node
var _globals: Array[Transform3D] = []
var _scale := 1.0
var _turn := Basis(Vector3.UP, PI)
var _skin: Skin
var _out: Skeleton3D


func _load_settings() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	if not d is Dictionary:
		push_error("Can't read " + SETTINGS)
		return
	SOURCE = String(d.get("source", SOURCE))
	HEIGHT = float(d.get("height", HEIGHT))
	BODY_MESHES = d.get("body_meshes", [])
	for e: Dictionary in d.get("body_extra", []):
		# material -> [[part, min_y, max_y]...]: one material can make several parts by height
		# (the underwear's shorts and top, so trousers don't hide the top).
		var mat := String(e.material)
		if not BODY_EXTRA.has(mat):
			BODY_EXTRA[mat] = []
		BODY_EXTRA[mat].append([String(e.part), float(e.get("min_y", -1)), float(e.get("max_y", -1))])
	EXTRA_BODIES = d.get("extra_bodies", [])
	_read_pieces(d.get("pieces", []))


func _read_pieces(list: Array) -> void:
	PIECES = {}
	BONE_OF = {}
	for p: Dictionary in list:
		var id := String(p.get("id", ""))
		if id == "" or String(p.get("mesh", "")) == "":
			continue
		if not PIECES.has(id):
			PIECES[id] = []
		PIECES[id].append([String(p.mesh), String(p.get("material", "")), float(p.get("min_y", -1)), float(p.get("max_y", -1)), float(p.get("max_side", -1))])
		if String(p.get("bone", "")) != "":
			BONE_OF[String(p.mesh)] = String(p.bone)


func _initialize() -> void:
	_load_settings()
	_src = (load(SOURCE) as PackedScene).instantiate()
	_skel = _src.find_children("*", "Skeleton3D", true, false)[0]
	var root := Node3D.new()
	root.name = "base_bodies"
	var masc := _build_skeleton("Armature_masc")
	root.add_child(masc)
	_build_body()
	var masc_head := head_box(_out)
	# The femme body, unchanged.
	var old := (load(OLD_BODIES) as PackedScene).instantiate()
	var femme := old.get_node("Armature_femme")
	old.remove_child(femme)
	femme.owner = null
	root.add_child(femme)
	old.free()
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	print("saved %s err=%d" % [OUT, ResourceSaver.save(packed, OUT)])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEAR_DIR))
	for file: String in PIECES:
		_save_piece(file, PIECES[file])
	_src.free()
	# Body types 3, 4...: their own armatures in the same scene, and their own pieces.
	for e: Dictionary in EXTRA_BODIES:
		var key := String(e.get("key", ""))
		var source := String(e.get("source", ""))
		if key == "" or not ResourceLoader.exists(source):
			push_warning("extra body '%s': no source %s" % [key, source])
			continue
		_src = (load(source) as PackedScene).instantiate()
		_skel = _src.find_children("*", "Skeleton3D", true, false)[0]
		_globals.clear()
		HEIGHT = float(e.get("height", 1.86))
		BODY_MESHES = e.get("body_meshes", [])
		if BODY_MESHES.is_empty():
			for mi in _src.find_children("*", "MeshInstance3D", true, false):
				var low := String(mi.name).to_lower()
				if mi.skin != null and not (low.contains("teeth") or low.contains("tongue")):
					BODY_MESHES.append(String(mi.name))
		BODY_EXTRA = {}
		HEAD_BY_BONES = true
		_read_pieces(e.get("pieces", []))
		SUFFIX = key
		var arm := _build_skeleton("Armature_" + key)
		root.add_child(arm)
		_build_body()
		# Hair, hats and beards made on the masc head land on this head: the masc head's box
		# (above the head bone, in its space) mapped onto this one's. CharacterModel puts it
		# into the head bind of masc pieces worn here until they're refitted.
		var mine := head_box(_out)
		if masc_head.size != Vector3.ZERO and mine.size != Vector3.ZERO:
			# One even scale, the largest of the three, so the masc hair always covers this
			# head (a smaller axis would let the scalp poke through).
			var ratio := mine.size / masc_head.size
			var sc := Vector3.ONE * maxf(ratio.x, maxf(ratio.y, ratio.z)) * float(e.get("head_fit_grow", 1.02))
			var b := Basis.from_scale(sc)
			# Centred side to side and front to back; tops of the heads level (hair sits on
			# the crown, not around the middle of the face).
			var from := Vector3(masc_head.get_center().x, masc_head.end.y, masc_head.get_center().z)
			var to := Vector3(mine.get_center().x, mine.end.y, mine.get_center().z) \
				+ Vector3(0, float(e.get("head_fit_raise", 0.0)), float(e.get("head_fit_back", 0.0)))
			var fit := Transform3D(b, to - b * from)
			arm.set_meta("head_fit", fit)
			print("  head fit %s: scale %s" % [key, sc])
		arm.owner = root
		_own(arm, root)
		for file: String in PIECES:
			_save_piece(file, PIECES[file])
		_src.free()
	var packed2 := PackedScene.new()
	packed2.pack(root)
	print("saved %s with %d extra bodies err=%d" % [OUT, EXTRA_BODIES.size(), ResourceSaver.save(packed2, OUT)])
	root.free()
	quit()


func _own(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		_own(c, owner_node)


func _part_of(bone_name: String) -> String:
	var short := bone_name.trim_prefix("mixamorig_").trim_prefix("mixamorig:")
	if PART_OF.has(short):
		return PART_OF[short]
	if short.begins_with("LeftHand"):
		return "left_hand"
	if short.begins_with("RightHand"):
		return "right_hand"
	return "torso"


## The skeleton, turned to face -Z and scaled to HEIGHT.
func _build_skeleton(armature_name: String) -> Node3D:
	var skel_xf := _scene_xform(_skel, _src)
	var n := _skel.get_bone_count()
	for b in n:
		_globals.append(skel_xf * _skel.get_bone_global_rest(b))
	var top := _skel.find_bone("mixamorig_HeadTop_End")
	_scale = HEIGHT / _globals[top].origin.y
	var armature := Node3D.new()
	armature.name = armature_name
	_out = Skeleton3D.new()
	_out.name = "Skeleton3D"
	armature.add_child(_out)
	var new_globals: Array[Transform3D] = []
	for b in n:
		_out.add_bone(_skel.get_bone_name(b))
	for b in n:
		_out.set_bone_parent(b, _skel.get_bone_parent(b))
		new_globals.append(Transform3D(_turn * _globals[b].basis.orthonormalized(), _to_new(_globals[b].origin)))
	for b in n:
		var p := _out.get_bone_parent(b)
		var rest := new_globals[b] if p < 0 else new_globals[p].affine_inverse() * new_globals[b]
		_out.set_bone_rest(b, rest)
		_out.set_bone_pose(b, rest)
	_skin = Skin.new()
	for b in n:
		_skin.add_named_bind(_out.get_bone_name(b), new_globals[b].affine_inverse())
	return armature


func _to_new(p: Vector3) -> Vector3:
	return _turn * p * _scale


## One surface of a source mesh at rest in the new space:
## {pos, nrm, uv, bones (4 per vertex), weights, index, parts (per-vertex part weights), material}
func _bake_surface(mi: MeshInstance3D, surf: int) -> Dictionary:
	var arrays := mi.mesh.surface_get_arrays(surf)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var index = arrays[Mesh.ARRAY_INDEX]
	if index == null:
		index = PackedInt32Array(range(verts.size()))
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var vb := PackedInt32Array()
	var vw := PackedFloat32Array()
	var part_weights: Array[Dictionary] = []
	pos.resize(verts.size())
	nrm.resize(verts.size())
	var src_skin := mi.skin
	if src_skin == null:
		# A rigid mesh: everything follows one bone.
		var bone_name := String(BONE_OF.get(String(mi.name), "mixamorig_Head"))
		var bone := _skel.find_bone(bone_name)
		if bone < 0:
			bone = _skel.find_bone(bone_name.replace(":", "_"))  # Blender's "mixamorig:Hand"
		if bone < 0:
			push_warning("%s: no bone '%s', using the head" % [mi.name, bone_name])
			bone = _skel.find_bone("mixamorig_Head")
		var xf := _scene_xform(mi, _src)
		for v in verts.size():
			pos[v] = _to_new(xf * verts[v])
			nrm[v] = (_turn * (xf.basis * normals[v])).normalized()
			vb.append_array([bone, 0, 0, 0])
			vw.append_array([1.0, 0.0, 0.0, 0.0])
			part_weights.append({_part_of(_skel.get_bone_name(bone)): 1.0})
	else:
		var bind_bone := PackedInt32Array()
		var bind_pose: Array[Transform3D] = []
		for i in src_skin.get_bind_count():
			var bname := String(src_skin.get_bind_name(i))
			bind_bone.append(_skel.find_bone(bname) if bname != "" else src_skin.get_bind_bone(i))
			bind_pose.append(src_skin.get_bind_pose(i))
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		for v in verts.size():
			var p := Vector3.ZERO
			var nn := Vector3.ZERO
			var total := 0.0
			var slots := []
			for k in per:
				var w := weights[v * per + k]
				if w <= 0.0:
					continue
				var bi := bones[v * per + k]
				var bone := bind_bone[bi]
				var m: Transform3D = _globals[bone] * bind_pose[bi]
				p += m * verts[v] * w
				nn += (m.basis * normals[v]) * w
				total += w
				slots.append([bone, w])
			if total > 0.0:
				p /= total
			pos[v] = _to_new(p)
			nrm[v] = (_turn * nn).normalized()
			slots.sort_custom(func(a: Array, c: Array) -> bool: return a[1] > c[1])
			for k in 4:
				vb.append(slots[k][0] if k < slots.size() else 0)
				vw.append(slots[k][1] / total if k < slots.size() else 0.0)
			var pw := {}
			for slot: Array in slots:
				var pn := _part_of(_skel.get_bone_name(slot[0]))
				pw[pn] = float(pw.get(pn, 0.0)) + float(slot[1]) / total * float(PART_BIAS.get(pn, 1.0))
			part_weights.append(pw)
	var mat := mi.get_active_material(surf)
	return {"pos": pos, "nrm": nrm, "uv": uvs, "bones": vb, "weights": vw, "index": index,
		"parts": part_weights, "material": mat, "material_name": mat.resource_name if mat else ""}


## Collects triangles into a new mesh (keyed groups of vertices).
class Builder:
	var map := {}
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var b := PackedInt32Array()
	var w := PackedFloat32Array()
	var i := PackedInt32Array()

	func add_tri(s: Dictionary, t: int, key: String) -> void:
		for c in 3:
			var vi: int = s.index[t + c]
			var k := "%s:%d" % [key, vi]
			if not map.has(k):
				map[k] = v.size()
				v.append(s.pos[vi])
				n.append(s.nrm[vi])
				uv.append(s.uv[vi] if s.uv != null else Vector2.ZERO)
				for q in 4:
					b.append(s.bones[vi * 4 + q])
					w.append(s.weights[vi * 4 + q])
			i.append(map[k])

	func surface() -> Array:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_BONES] = b
		arrays[Mesh.ARRAY_WEIGHTS] = w
		arrays[Mesh.ARRAY_INDEX] = i
		return arrays


func _mesh_named(mesh_name: String) -> MeshInstance3D:
	for mi in _src.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name) == mesh_name:
			return mi
	push_error("no mesh " + mesh_name)
	return null


func _build_body() -> void:
	var parts := {}  # part -> Builder
	var extra_mats := {}
	var baked := []  # [mesh name, surface index, baked surface]
	for mesh_name: String in BODY_MESHES:
		var mi := _mesh_named(mesh_name)
		for surf in mi.mesh.get_surface_count():
			baked.append([mesh_name, surf, _bake_surface(mi, surf)])
	if HEAD_BY_BONES:
		_smooth_normals(baked)
	for entry: Array in baked:
		var mesh_name: String = entry[0]
		var surf: int = entry[1]
		var s: Dictionary = entry[2]
		if true:
			var extras: Array = BODY_EXTRA.get(s.material_name, [])
			for e: Array in extras:
				extra_mats[e[0]] = _material(s.material)
			for t in range(0, s.index.size(), 3):
				var part := ""
				if not extras.is_empty():
					var cy: float = (s.pos[s.index[t]].y + s.pos[s.index[t + 1]].y + s.pos[s.index[t + 2]].y) / 3.0
					part = String(extras[0][0])
					for e: Array in extras:
						if (float(e[1]) < 0.0 or cy >= float(e[1])) and (float(e[2]) < 0.0 or cy < float(e[2])):
							part = String(e[0])
							break
				if part == "":
					# The part its corners follow most (hands and feet count a little less,
					# so wrists and ankles stay with the limb). The head mesh is all head.
					var votes := {}
					for c in 3:
						var pw: Dictionary = s.parts[s.index[t + c]]
						for pn in pw:
							votes[pn] = float(votes.get(pn, 0.0)) + float(pw[pn])
					for pn in votes:
						if part.is_empty() or votes[pn] > votes[part]:
							part = pn
					if mesh_name.begins_with("head"):
						part = "head"
					elif part == "head" and not HEAD_BY_BONES:
						part = "torso"  # the body's own neck stump stays with the torso
				if not parts.has(part):
					parts[part] = Builder.new()
				(parts[part] as Builder).add_tri(s, t, "%s:%d" % [mesh_name, surf])
	var skin_mat := StandardMaterial3D.new()
	skin_mat.resource_name = "Body"
	skin_mat.albedo_color = Color(1.0, 0.8, 0.72)
	skin_mat.roughness = 0.85
	var names := parts.keys()
	names.sort()
	for part: String in names:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (parts[part] as Builder).surface())
		mesh.surface_set_material(0, extra_mats.get(part, skin_mat))
		var mi := MeshInstance3D.new()
		mi.name = part
		mi.mesh = mesh
		mi.skin = _skin
		_out.add_child(mi)
		mi.skeleton = NodePath("..")
		print("  %-10s %5d verts %5d tris" % [part, (parts[part] as Builder).v.size(), (parts[part] as Builder).i.size() / 3])
	print("%s: scale %.4f, %d bones" % [SUFFIX, _scale, _out.get_bone_count()])


## Bodies imported with hard (per-face) normals shade faceted and split anything pushed out
## along them (underwear): average the face normals of every corner at the same spot,
## across all the body's surfaces, so parts meet smoothly too.
func _smooth_normals(baked: Array) -> void:
	var sums := {}
	for entry: Array in baked:
		var s: Dictionary = entry[2]
		for t in range(0, s.index.size(), 3):
			var a: Vector3 = s.pos[s.index[t]]
			var b: Vector3 = s.pos[s.index[t + 1]]
			var c: Vector3 = s.pos[s.index[t + 2]]
			var n := (b - a).cross(c - a)  # area-weighted
			if n.dot(s.nrm[s.index[t]] + s.nrm[s.index[t + 1]] + s.nrm[s.index[t + 2]]) < 0.0:
				n = -n
			for k in 3:
				var key := (s.pos[s.index[t + k]] as Vector3).snappedf(0.0001)
				sums[key] = (sums.get(key, Vector3.ZERO) as Vector3) + n
	for entry: Array in baked:
		var s: Dictionary = entry[2]
		var nrm: PackedVector3Array = s.nrm
		for v in nrm.size():
			var sum: Vector3 = sums.get((s.pos[v] as Vector3).snappedf(0.0001), Vector3.ZERO)
			if sum.length() > 0.0:
				nrm[v] = sum.normalized()
		s.nrm = nrm


## The head above the head bone (cranium and face), in the head bone's own space at rest.
static func head_box(skel: Skeleton3D) -> AABB:
	var head := skel.get_node_or_null("head") as MeshInstance3D
	var bone := skel.find_bone("mixamorig_Head")
	if head == null or bone < 0:
		return AABB()
	var xf := skel.get_bone_global_rest(bone)
	var inv := xf.affine_inverse()
	var box := AABB()
	var first := true
	for surf in head.mesh.get_surface_count():
		for v: Vector3 in head.mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]:
			if v.y < xf.origin.y:
				continue
			var local := inv * v
			if first:
				box = AABB(local, Vector3.ZERO)
				first = false
			else:
				box = box.expand(local)
	return box


## A copy of a source material for the game (textures kept, pixel look, no specular glare).
func _material(src: Material) -> Material:
	if src is BaseMaterial3D:
		var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.metallic_specular = 0.3
		return m
	return src


func _save_piece(file: String, specs: Array) -> void:
	var root := Node3D.new()
	root.name = file
	var count := 0
	for spec: Array in specs:
		var mi := _mesh_named(spec[0])
		if mi == null:
			continue
		for surf in mi.mesh.get_surface_count():
			var s := _bake_surface(mi, surf)
			# material: "" = all, else one name or a comma list ("chainmail,chainmail_sway,leather").
			if String(spec[1]) != "" and not s.material_name in String(spec[1]).replace(" ", "").split(",", false):
				continue
			var builder := Builder.new()
			for t in range(0, s.index.size(), 3):
				var y: float = (s.pos[s.index[t]].y + s.pos[s.index[t + 1]].y + s.pos[s.index[t + 2]].y) / 3.0
				if (float(spec[2]) >= 0.0 and y < float(spec[2])) or (float(spec[3]) >= 0.0 and y > float(spec[3])):
					continue
				# max_side: only faces within this far of the middle (leave out cuffs on the arms).
				var side: float = absf(s.pos[s.index[t]].x + s.pos[s.index[t + 1]].x + s.pos[s.index[t + 2]].x) / 3.0
				if spec.size() > 4 and float(spec[4]) >= 0.0 and side > float(spec[4]):
					continue
				builder.add_tri(s, t, str(surf))
			if builder.i.is_empty():
				continue
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, builder.surface())
			mesh.surface_set_material(0, _material(s.material))
			var part := MeshInstance3D.new()
			# Faces given a "hat_clip" material in Blender (hair under a hat): their own
			# mesh, hidden by hats with Head clipping = Hat clip.
			part.name = "%s_%d%s" % [file, count, "_hat_clip" if s.material_name.contains("hat_clip") else ""]
			part.mesh = mesh
			part.skin = _skin
			root.add_child(part)
			part.owner = root
			count += 1
	var packed := PackedScene.new()
	packed.pack(root)
	var path := "%s/%s_%s.scn" % [GEAR_DIR, file, SUFFIX]
	var box := AABB()
	for c in root.get_children():
		box = (c as MeshInstance3D).get_aabb() if box.size == Vector3.ZERO else box.merge((c as MeshInstance3D).get_aabb())
	print("  %s err=%d meshes=%d %s" % [path, ResourceSaver.save(packed, path), count, box])
	root.free()


func _scene_xform(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p := node
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
