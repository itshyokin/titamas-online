extends SceneTree
## Builds assets/models/characters/base_bodies.scn from the two rigged Mixamo base models
## (assets/models/characters/new/masc_tpose.fbx and fem_tpose.fbx), in the layout the game
## expects (the same as the old base_bodies.glb):
##   base_bodies
##     Armature_masc / Skeleton3D / head, torso, left_arm, left_hand, left_leg, left_foot, right_...
##     Armature_femme / Skeleton3D / f_head, f_torso, ...
## Each body is turned to face -Z, scaled to its height in metres and baked into that space
## (skeleton rests, mesh vertices and bind poses), so the eyes, builds (weight), armour
## fitting and hair placement all work in metres with the feet at 0. The single body mesh
## is cut into parts by the bone each triangle mostly follows, so gear can hide parts.
##
##   godot --headless --path . --script res://tools/godot/build_bodies.gd
## Then rebuild the animations (tools/godot/retarget_mixamo.gd), the placeholder armour
## (tools/godot/make_placeholder_armor.gd) and hair (tools/godot/make_appearance.gd).

const OUT := "res://assets/models/characters/base_bodies.scn"
## Source FBX, armature name, part-name prefix and height (top of the head, m).
const BODIES := [
	["res://assets/models/characters/new/masc_tpose.fbx", "Armature_masc", "", 1.86],
	["res://assets/models/characters/new/fem_tpose.fbx", "Armature_femme", "f_", 1.80],
]
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


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "base_bodies"
	for entry in BODIES:
		var armature := _build(entry[0], entry[1], entry[2], entry[3])
		root.add_child(armature)
		_own(armature, root)
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT)
	print("saved %s err=%d" % [OUT, err])
	root.free()
	quit()


func _own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for c in node.get_children():
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


func _build(path: String, armature_name: String, prefix: String, height: float) -> Node3D:
	var src: Node = (load(path) as PackedScene).instantiate()
	var skel: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var skel_xf := _scene_xform(skel, src)
	var n := skel.get_bone_count()
	var globals: Array[Transform3D] = []
	for b in n:
		globals.append(skel_xf * skel.get_bone_global_rest(b))
	# Turn to face -Z and scale so the top of the head is at `height`.
	var top := skel.find_bone("mixamorig_HeadTop_End")
	var feet := INF
	for b in n:
		feet = minf(feet, globals[b].origin.y)
	var s := height / (globals[top].origin.y - 0.0)
	var turn := Basis(Vector3.UP, PI)
	var to_new := func(p: Vector3) -> Vector3: return turn * p * s

	var armature := Node3D.new()
	armature.name = armature_name
	var out := Skeleton3D.new()
	out.name = "Skeleton3D"
	armature.add_child(out)
	var new_globals: Array[Transform3D] = []
	for b in n:
		out.add_bone(skel.get_bone_name(b))
	for b in n:
		out.set_bone_parent(b, skel.get_bone_parent(b))
		new_globals.append(Transform3D(turn * globals[b].basis.orthonormalized(), to_new.call(globals[b].origin)))
	for b in n:
		var p := out.get_bone_parent(b)
		var rest := new_globals[b] if p < 0 else new_globals[p].affine_inverse() * new_globals[b]
		out.set_bone_rest(b, rest)
		out.set_bone_pose(b, rest)

	# One skin bind per bone, in the new space.
	var skin := Skin.new()
	for b in n:
		skin.add_named_bind(out.get_bone_name(b), new_globals[b].affine_inverse())

	var parts := {}  # part -> {verts, normals, uvs, bones, weights, index map}
	for mi_node in skel.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_node as MeshInstance3D
		var src_skin := mi.skin
		var bind_bone := PackedInt32Array()
		var bind_pose: Array[Transform3D] = []
		for i in src_skin.get_bind_count():
			var bname := String(src_skin.get_bind_name(i))
			var bone := skel.find_bone(bname) if bname != "" else src_skin.get_bind_bone(i)
			bind_bone.append(bone)
			bind_pose.append(src_skin.get_bind_pose(i))
		for surf in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surf)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs = arrays[Mesh.ARRAY_TEX_UV]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / verts.size()
			var index = arrays[Mesh.ARRAY_INDEX]
			if index == null:
				index = PackedInt32Array(range(verts.size()))
			# Rest-pose positions and normals in the new space, and the bones as bone indices.
			var pos := PackedVector3Array()
			var nrm := PackedVector3Array()
			var vb := PackedInt32Array()
			var vw := PackedFloat32Array()
			var part_weights: Array[Dictionary] = []
			pos.resize(verts.size())
			nrm.resize(verts.size())
			for v in verts.size():
				var p := Vector3.ZERO
				var nn := Vector3.ZERO
				var total := 0.0
				var slots := []
				for k in per:
					var w := weights[v * per + k]
					var bi := bones[v * per + k]
					if w <= 0.0:
						continue
					var bone := bind_bone[bi]
					var m: Transform3D = globals[bone] * bind_pose[bi]
					p += m * verts[v] * w
					nn += (m.basis * normals[v]) * w
					total += w
					slots.append([bone, w])
				if total > 0.0:
					p /= total
				pos[v] = to_new.call(p)
				nrm[v] = (turn * nn).normalized()
				slots.sort_custom(func(a: Array, c: Array) -> bool: return a[1] > c[1])
				for k in 4:
					if k < slots.size():
						vb.append(slots[k][0])
						vw.append(slots[k][1] / total)
					else:
						vb.append(0)
						vw.append(0.0)
				var pw := {}
				for slot: Array in slots:
					var pn := _part_of(skel.get_bone_name(slot[0]))
					pw[pn] = float(pw.get(pn, 0.0)) + float(slot[1]) / total * float(PART_BIAS.get(pn, 1.0))
				part_weights.append(pw)
			# Each triangle goes to the part its corners follow most (all their weights added;
			# hands and feet count a little less, so wrists and ankles stay with the limb).
			for t in range(0, index.size(), 3):
				var votes := {}
				for c in 3:
					var pw: Dictionary = part_weights[index[t + c]]
					for pn in pw:
						votes[pn] = float(votes.get(pn, 0.0)) + float(pw[pn])
				var part := ""
				for pn in votes:
					if part.is_empty() or votes[pn] > votes[part]:
						part = pn
				if not parts.has(part):
					parts[part] = {"map": {}, "v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "b": PackedInt32Array(), "w": PackedFloat32Array(), "i": PackedInt32Array()}
				var P: Dictionary = parts[part]
				for c in 3:
					var vi: int = index[t + c]
					var key := "%d:%d" % [surf, vi]
					if not P.map.has(key):
						P.map[key] = P.v.size()
						P.v.append(pos[vi])
						P.n.append(nrm[vi])
						P.uv.append(uvs[vi] if uvs != null else Vector2.ZERO)
						for k in 4:
							P.b.append(vb[vi * 4 + k])
							P.w.append(vw[vi * 4 + k])
					P.i.append(P.map[key])
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Body"
	mat.albedo_color = Color(1.0, 0.8, 0.72)
	mat.roughness = 0.85
	var names := parts.keys()
	names.sort()
	for part in names:
		var P: Dictionary = parts[part]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = P.v
		arrays[Mesh.ARRAY_NORMAL] = P.n
		arrays[Mesh.ARRAY_TEX_UV] = P.uv
		arrays[Mesh.ARRAY_BONES] = P.b
		arrays[Mesh.ARRAY_WEIGHTS] = P.w
		arrays[Mesh.ARRAY_INDEX] = P.i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, mat)
		var part_mi := MeshInstance3D.new()
		part_mi.name = prefix + part
		part_mi.mesh = mesh
		part_mi.skin = skin
		out.add_child(part_mi)
		part_mi.skeleton = NodePath("..")
		print("  %s%-10s %5d verts %5d tris" % [prefix, part, P.v.size(), P.i.size() / 3])
	print("%s: scale %.4f, %d bones, feet at %.3f" % [armature_name, s, n, feet * s])
	src.free()
	return armature


func _scene_xform(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p := node
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
